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

import [Path] from io;
import llvm;
import "build";

# `LLVMLinkModules2` links `source` into `destination` and disposes of
# `source`; nonzero when the two do not link.
extern int LLVMLinkModules2(void* destination, void* source);
extern void* LLVMCloneModule(void* module);
extern int LLVMGetVisibility(void* global);
extern void LLVMSetComdat(void* global, void* comdat);

## Links the parts' bitcode files `bitcode` into one module, optimizes it
## as a whole at `opt_level`, and writes it to `object`. Each part's
## functions already carry the build's CPU (`codegen.generate`).
##
## @param bitcode the parts' bitcode files, the entry part's among them
## @param object the object file to write
## @param machine the target machine: triple, CPU and features
## @param opt_level the `-O` level, 1 to 3
## @returns nothing, or why a step failed
export optimize_whole(
    bitcode: Path[], object: Path, machine: llvm.TargetMachine, opt_level: uint
): Result<void, String> {
    if (bitcode.is_empty) {
        return Result<void, String>.err("nothing to link");
    }
    var context = llvm.Context();
    var program = llvm.Module.read_bitcode(context, bitcode[0].to_string());
    if (program.is_err()) {
        return Result<void, String>.err(program.error().message);
    }
    var ir = program.value();
    for (var i in 1..bitcode.count) {
        var part = llvm.Module.read_bitcode(context, bitcode[i].to_string());
        if (part.is_err()) {
            return Result<void, String>.err(part.error().message);
        }
        # The link disposes of the module it links in, which `part` still
        # owns: it gets a copy.
        if (LLVMLinkModules2(ir.ref, LLVMCloneModule(part.value().ref)) != 0) {
            return Result<void, String>.err($"cannot link {bitcode[i]} into the program");
        }
    }
    internalize(ir);
    var optimized = ir.run_passes($"lto<O{opt_level}>", machine);
    if (optimized.is_err()) {
        return Result<void, String>.err($"cannot optimize the linked program: {optimized.error().message}");
    }
    var verified = ir.verify();
    if (verified.is_err()) {
        return Result<void, String>.err($"the linked program does not verify: {verified.error().message}");
    }
    place_constructors(ir, machine.triple());
    var emitted = machine.emit_to_file(ir, object.to_string());
    if (emitted.is_err()) {
        return Result<void, String>.err($"cannot write {object}: {emitted.error().message}");
    }
    return Result<void, String>.ok();
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
