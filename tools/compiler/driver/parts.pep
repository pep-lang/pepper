## Optimizing and compiling a program's module as parts in parallel: the
## module is split as `codegen/partition.pep` describes, written once as
## bitcode, and one `pepc --compile-part` child per part keeps its part,
## optimizes it and writes its object.

import async;
import compiler.codegen;
import [Directory, File, Path] from io;
import llvm;
import process;
import "build";

## The plan file beside the bitcode: the machine, the level, then one
## `<part> <symbol>` line per symbol defined in exactly one part.
const _PLAN_FILE = "plan";
const _BITCODE_FILE = "program.bc";

## How many parts to compile a program of `files` files in: one per
## logical CPU, no more than the files.
##
## @param files how many files the program has
## @returns the number of parts, at least 1
export part_count(files: uint): uint {
    var cpus = async.logical_cpus();
    var parts = cpus < (files as ulong) ? cpus : files as ulong;
    return parts < 1 ? 1 : parts as uint;
}

## Splits `ir` into `parts` parts in `dir`, and compiles them in parallel
## child processes of this compiler, one object per part.
##
## @param ir the whole program's module, unoptimized
## @param owners each owned symbol's file, by name
## @param files how many files the program has
## @param parts how many parts to make, more than 1
## @param machine the target: triple, CPU and features
## @param cpu the CPU code is generated for
## @param opt_level the `-O` level
## @param dir the folder for the bitcode, the plan and the objects
## @param extension the object files' extension
## @returns the objects, or why a part failed
export compile_parts(
    ir: llvm.Module,
    owners: HashMap<String, uint>,
    files: uint,
    parts: uint,
    machine: llvm.TargetMachine,
    cpu: codegen.Cpu,
    opt_level: uint,
    dir: Path,
    extension: String
): Result<Path[], String> {
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Result<Path[], String>.err($"cannot create {dir}: {created.error().message}");
    }
    var partition = codegen.prepare(ir, owners, files, parts);
    var bitcode = dir.join(Path(_BITCODE_FILE));
    var written = ir.write_bitcode(bitcode.to_string());
    if (written.is_err()) {
        return Result<Path[], String>.err(written.error().message);
    }
    var plan = StringBuilder();
    plan.append($"{machine.triple()}\n{cpu.name}\n{cpu.features}\n{opt_level}\n");
    for (var (symbol, part) in partition.part_of) {
        plan.append($"{part} {symbol}\n");
    }
    var saved = File.write_text(dir.join(Path(_PLAN_FILE)), plan.to_string());
    if (saved.is_err()) {
        return Result<Path[], String>.err($"cannot write the plan in {dir}: {saved.error().message}");
    }

    var executable = process.executable_path();
    if (executable.is_err()) {
        return Result<Path[], String>.err($"cannot find this compiler: {executable.error().message}");
    }
    var children = Array<process.Child>();
    var objects = Array<Path>();
    String failure = "";
    for (var part in 0..parts) {
        var object = dir.join(Path($"{part}.{extension}"));
        objects.append(object);
        var command = process.Command(executable.value().to_string());
        command.argument("--compile-part").argument(dir.to_string()).argument($"{part}").argument(object.to_string());
        var spawned = command.spawn();
        if (spawned.is_err()) {
            failure = $"cannot run {executable.value()}: {spawned.error().message}";
            break;
        }
        children.append(spawned.value());
    }
    # Every child started is waited for, even after a failure.
    for (var part in 0..children.count) {
        var status = children[part].wait();
        if (failure.is_empty) {
            if (status.is_err()) {
                failure = $"part {part}: {status.error().message}";
            } else if (!status.value().success()) {
                failure = $"part {part} failed ({status.value()})";
            }
        }
    }
    if (!failure.is_empty) {
        return Result<Path[], String>.err(failure);
    }
    return Result<Path[], String>.ok(objects);
}

## Compiles part `part` of the program `compile_parts` split into `dir`:
## keeps the part, optimizes it at the plan's level and writes `object`.
## `pepc --compile-part` runs it.
##
## @param dir the folder holding the bitcode and the plan
## @param part the part to compile
## @param object the object file to write
## @returns nothing, or why it failed
export compile_part(dir: Path, part: uint, object: Path): Result<void, String> {
    var read = File.read_to_string(dir.join(Path(_PLAN_FILE)));
    if (read.is_err()) {
        return Result<void, String>.err($"cannot read the plan in {dir}: {read.error().message}");
    }
    var lines = read.value().split("\n");
    if (lines.count < 4) {
        return Result<void, String>.err($"the plan in {dir} is incomplete");
    }
    var level = uint.parse(lines[3]);
    if (!level.is_value() or level.value() > 3) {
        return Result<void, String>.err($"the plan in {dir} has no -O level");
    }
    var part_of = HashMap<String, uint>();
    for (var index in 4..lines.count) {
        var line = lines[index];
        var space = line.find(" ");
        if (space < 0) {
            continue;
        }
        var owner = uint.parse(line.substr_bytes(0, space as ulong));
        if (owner.is_value()) {
            part_of[line.substr_bytes(space as ulong + 1, line.size - space as ulong - 1)] = owner.value();
        }
    }
    var levels = [llvm.OptLevel.O0, llvm.OptLevel.O1, llvm.OptLevel.O2, llvm.OptLevel.O3];
    var machine = llvm.TargetMachine.create(lines[0], lines[1], lines[2], levels[level.value()]);
    if (machine.is_err()) {
        return Result<void, String>.err(machine.error().message);
    }
    var context = llvm.Context();
    var ir = llvm.Module.read_bitcode(context, dir.join(Path(_BITCODE_FILE)).to_string());
    if (ir.is_err()) {
        return Result<void, String>.err(ir.error().message);
    }
    var kept = codegen.keep_part(ir.value(), codegen.Partition(part_of), part);
    if (kept.is_err()) {
        return Result<void, String>.err($"cannot split part {part}: {kept.error().message}");
    }
    if (level.value() > 0) {
        var optimized = ir.value().run_passes($"default<O{level.value()}>", machine.value());
        if (optimized.is_err()) {
            return Result<void, String>.err($"cannot optimize: {optimized.error().message}");
        }
    }
    if (part == 0) {
        place_constructors(ir.value(), lines[0]);
    }
    var emitted = machine.value().emit_to_file(ir.value(), object.to_string());
    if (emitted.is_err()) {
        return Result<void, String>.err($"cannot write {object}: {emitted.error().message}");
    }
    return Result<void, String>.ok();
}
