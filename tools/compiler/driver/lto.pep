## Link-time optimization (`--lto=full`, the default at `-O2` and `-O3`).
##
## Each part is optimized alone, so a call into another unit (user code
## calling the runtime's `_pep_malloc`, or `String.__acquire`) stays a
## call. With LTO, each part is kept as bitcode that LLVM's pre-link
## pipeline (`lto-pre-link<On>`) has run over (`parts.pep`, cached like an
## object), and `optimize_whole` links every part into one module, makes
## every symbol but `main` and the C exports internal to it, runs the
## link-time pipeline (`lto<On>`) over the whole program, and emits one
## object. The program then links with the system linker as usual: no
## linker plugin is involved, so it works on every platform the compiler
## does.

import async;
import compiler.codegen;
import [Clock] from compiler.incremental;
import [Path] from io;
import llvm;
import "build";
import "parts";

extern int LLVMGetVisibility(void* global);
extern void LLVMSetComdat(void* global, void* comdat);
extern int LLVMIsGlobalConstant(void* global);

## Links the parts' bitcode files `bitcode` into one module, optimizes it
## as a whole at `opt_level`, and writes its objects into `dir`. Each
## part's functions already carry the build's CPU (`codegen.generate`).
## Optimizing is one module's work, but writing the objects is not: the
## optimized program is split into one part per logical CPU (`split`),
## and `compile_parts` writes each part's object in a child, in parallel.
##
## @param bitcode the parts' bitcode files, the entry part's among them
## @param dir the folder for the objects (and the children's bitcode)
## @param extension the objects' file extension, `o` or `obj`
## @param machine the target machine: triple, CPU and features
## @param cpu the CPU code is generated for
## @param opt_level the `-O` level, 1 to 3
## @param in_process whether to write one object in this process (for a
##   program that is not this compiler, which cannot run `--compile-part`)
## @param clock times each step (`-T time`)
## @returns the objects, or why a step failed
export optimize_whole(
    bitcode: Path[],
    dir: Path,
    extension: String,
    machine: llvm.TargetMachine,
    cpu: codegen.Cpu,
    opt_level: uint,
    in_process: bool,
    clock: Clock
): Result<Path[], String> {
    if (bitcode.is_empty) {
        return Result<Path[], String>.err("nothing to link");
    }
    var context = llvm.Context();
    var program = llvm.Module.read_bitcode(context, bitcode[0].to_string());
    if (program.is_err()) {
        return Result<Path[], String>.err(program.error().message);
    }
    var ir = program.value();
    for (var i in 1..bitcode.count) {
        var part = llvm.Module.read_bitcode(context, bitcode[i].to_string());
        if (part.is_err()) {
            return Result<Path[], String>.err(part.error().message);
        }
        if (ir.link(part.value()).is_err()) {
            return Result<Path[], String>.err($"cannot link {bitcode[i]} into the program");
        }
    }
    clock.lap("link-time optimization: link");
    internalize(ir);
    var optimized = ir.run_passes($"lto<O{opt_level}>", machine);
    if (optimized.is_err()) {
        return Result<Path[], String>.err($"cannot optimize the linked program: {optimized.error().message}");
    }
    clock.lap("link-time optimization: optimize");
    var verified = ir.verify();
    if (verified.is_err()) {
        return Result<Path[], String>.err($"the linked program does not verify: {verified.error().message}");
    }
    clock.lap("link-time optimization: verify");
    var count = in_process ? 1 : async.logical_cpus() as uint;
    var objects = Array<Path>();
    if (count < 2) {
        var object = dir.join(Path($"lto.{extension}"));
        place_constructors(ir, machine.triple());
        var emitted = machine.emit_to_file(ir, object.to_string());
        if (emitted.is_err()) {
            return Result<Path[], String>.err($"cannot write {object}: {emitted.error().message}");
        }
        clock.lap("link-time optimization: emit");
        objects.append(object);
        return Result<Path[], String>.ok(objects);
    }
    var partition = split(ir, count);
    var jobs = Array<PartJob>();
    for (var part in 0..count) {
        if (partition.sizes[part as ulong] == 0) {
            continue;
        }
        var object = dir.join(Path($"lto.{part}.{extension}"));
        jobs.append(PartJob(part, object));
        objects.append(object);
    }
    var compiled = compile_parts(
        ir, partition, jobs, machine, cpu, opt_level, dir.join(Path("lto")), clock.on, false, false, false, true
    );
    if (compiled.is_err()) {
        return Result<Path[], String>.err(compiled.error());
    }
    clock.lap($"link-time optimization: emit {jobs.count} objects");
    return Result<Path[], String>.ok(objects);
}

## Splits `ir`, the optimized whole program, into `count` parts of about
## the same size, each a run of its definitions in order, for their
## objects to be written in parallel. Every definition is in one part; a
## local one (`internalize` made nearly all of them local) becomes
## external with hidden visibility, since another part may call it, and
## gets a name if it has none. A local constant whose address means
## nothing (a string's bytes) stays local, copied into each part that
## uses it; `llvm.*` globals such as `llvm.global_ctors` are in part 0.
##
## @param ir the optimized program
## @param count how many parts, at least 1
## @returns the partition
export split(ir: llvm.Module, count: uint): codegen.Partition {
    var values = ir.functions();
    values.append_all(ir.globals());
    var definitions = Array<llvm.Value>();
    ulong total = 0;
    for (var value in values) {
        if (value.is_declaration()) {
            continue;
        }
        var linkage = value.linkage();
        bool local = linkage == llvm.Linkage.Private or linkage == llvm.Linkage.Internal;
        # Only a constant: the optimizer marks local variables
        # `local_unnamed_addr` too, and a copy of one per part would split
        # its state.
        if (local and !value.is_function() and LLVMIsGlobalConstant(value.ref) != 0 and value.unnamed_address() != 0) {
            continue;
        }
        definitions.append(value);
        total += _size(value);
    }
    var part_of = HashMap<String, uint>();
    var sizes = Array<ulong>();
    for (var _ in 0..count) {
        sizes.append(0);
    }
    ulong done = 0;
    ulong unnamed = 0;
    for (var value in definitions) {
        var name = value.name();
        if (name.starts_with("llvm.")) {
            part_of[name] = 0;
            sizes[0] += 1;
            continue;
        }
        if (name.is_empty) {
            value.set_name($"__pep_lto.{unnamed}");
            unnamed += 1;
            name = value.name();
        }
        var linkage = value.linkage();
        if (linkage == llvm.Linkage.Private or linkage == llvm.Linkage.Internal) {
            value.set_linkage(llvm.Linkage.External);
            value.set_visibility(llvm.Visibility.Hidden);
        }
        var part = total == 0 ? 0 : (done * count as ulong / total) as uint;
        part_of[name] = part;
        sizes[part as ulong] += _size(value);
        done += _size(value);
    }
    return codegen.Partition(part_of, sizes);
}

# How much code `value` is: its blocks, plus one for the definition.
_size(value: llvm.Value): ulong {
    return value.is_function() ? value.block_count() as ulong + 1 : 1;
}

## Makes every definition in `ir` but `main` and the C entry points of
## `[Export]`ed functions (the only definitions with default visibility)
## internal: nothing else outside the program calls Pepper code by name,
## so the optimizer may inline, specialize or drop any of it. A definition
## leaves its comdat, which only told the linker to keep one copy of it.
##
## @param ir the linked program
export internalize(ir: llvm.Module) {
    var values = ir.functions();
    values.append_all(ir.globals());
    for (var value in values) {
        var name = value.name();
        var linkage = value.linkage();
        bool visible = LLVMGetVisibility(value.ref) == llvm.Visibility.Default as int
            and linkage == llvm.Linkage.External;
        if (value.is_declaration() or name == "main" or name.starts_with("llvm.") or visible) {
            continue;
        }
        if (linkage == llvm.Linkage.Appending) {
            continue;
        }
        LLVMSetComdat(value.ref, __null);
        value.set_linkage(llvm.Linkage.Internal);
    }
}
