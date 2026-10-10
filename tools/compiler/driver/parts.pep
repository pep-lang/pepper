## Optimizing and compiling a program's module as parts in parallel: the
## module is split as `codegen/partition.pep` describes (one part per
## compilation unit, and one for the program's entry points), written once
## as bitcode, and a few `pepc --compile-part` children, one per logical
## CPU, each keep their share of the parts, optimize them and write their
## objects: with link-time optimization, their bitcode after LLVM's
## pre-link pipeline instead (`lto.pep`).

import async;
import compiler.codegen;
import [Directory, File, Path] from io;
import llvm;
import os;
import process;
import "build";

## The plan file beside the bitcode: the machine, the level, whether to
## print how long each part took, whether the parts are kept as bitcode
## for link-time optimization, then one `<part> <symbol>` line per symbol
## defined in exactly one part.
const _PLAN_FILE = "plan";
const _BITCODE_FILE = "program.bc";

## A part to compile, and where its object goes.
export struct PartJob {
    var part: uint;
    var object: Path;

    construct(part: uint, object: Path) {
        this.part = part;
        this.object = object;
    }
}

## Compiles `jobs`, parts of `ir` as `partition` splits it: in this process
## when there is one or `in_process` says so, else in child processes of
## this compiler, one per logical CPU at most, each given parts of about
## the same size.
##
## @param ir the whole program's module, prepared (`codegen.prepare`) and
##   unoptimized
## @param partition how it is split
## @param jobs the parts to compile
## @param machine the target: triple, CPU and features
## @param cpu the CPU code is generated for
## @param opt_level the `-O` level
## @param dir the folder for the bitcode and the plan
## @param trace_time whether to print how long each part took
## @param in_process whether to compile every part in this process, one
##   after another (for a program that is not this compiler, such as a
##   test, which cannot run `--compile-part`)
## @param partial whether other units' objects come from the build cache
## @param lto whether each part is written as bitcode after the pre-link
##   pipeline, for link-time optimization, rather than as an object
## @returns nothing, or why a part failed
export compile_parts(
    ir: llvm.Module,
    partition: codegen.Partition,
    jobs: PartJob[],
    machine: llvm.TargetMachine,
    cpu: codegen.Cpu,
    opt_level: uint,
    dir: Path,
    trace_time: bool = false,
    in_process: bool = false,
    partial: bool = false,
    lto: bool = false
): Result<void, String> {
    if (jobs.count == 1 or in_process) {
        for (var i in 0..jobs.count) {
            var module = i + 1 < jobs.count ? ir.clone() : ir;
            var compiled = _compile(module, partition, jobs[i], machine, opt_level, trace_time, lto);
            if (compiled.is_err()) {
                return compiled;
            }
        }
        return Result<void, String>.ok();
    }
    var created = Directory.create_all(dir);
    if (created.is_err()) {
        return Result<void, String>.err($"cannot create {dir}: {created.error().message}");
    }
    var kept = _keep_jobs(ir, partition, jobs, partial);
    if (kept.is_err()) {
        return Result<void, String>.err($"cannot split the parts: {kept.error().message}");
    }
    var written = ir.write_bitcode(dir.join(Path(_BITCODE_FILE)).to_string());
    if (written.is_err()) {
        return Result<void, String>.err(written.error().message);
    }
    var plan = StringBuilder();
    plan.append($"{machine.triple()}\n{cpu.name}\n{cpu.features}\n{opt_level}\n{trace_time}\n{lto}\n");
    for (var (symbol, part) in partition.part_of) {
        plan.append($"{part} {symbol}\n");
    }
    var saved = File.write_text(dir.join(Path(_PLAN_FILE)), plan.to_string());
    if (saved.is_err()) {
        return Result<void, String>.err($"cannot write the plan in {dir}: {saved.error().message}");
    }

    var executable = process.executable_path();
    if (executable.is_err()) {
        return Result<void, String>.err($"cannot find this compiler: {executable.error().message}");
    }
    var children = Array<process.Child>();
    # Each child's command line, to name a failed one and how to rerun it.
    var lines = Array<String>();
    String failure = "";
    for (var share in _shares(jobs, partition.sizes)) {
        var command = process.Command(executable.value().to_string());
        command.argument("--compile-part").argument(dir.to_string());
        var line = $"{executable.value()} --compile-part {dir}";
        for (var job in share) {
            command.argument($"{job.part}").argument(job.object.to_string());
            line = $"{line} {job.part} {job.object}";
        }
        var spawned = command.spawn();
        if (spawned.is_err()) {
            failure = $"cannot run {executable.value()}: {spawned.error().message}";
            break;
        }
        children.append(spawned.value());
        lines.append(line);
    }
    # Every child started is waited for, even after a failure.
    for (var i in 0..children.count) {
        var status = children[i].wait();
        if (!failure.is_empty) {
            continue;
        }
        if (status.is_err()) {
            failure = $"a part failed: {status.error().message}\n  rerun: {lines[i]}";
        } else if (!status.value().success()) {
            failure = $"a part failed ({status.value()})\n  rerun: {lines[i]}";
        }
    }
    if (!failure.is_empty) {
        return Result<void, String>.err(failure);
    }
    return Result<void, String>.ok();
}

## Splits `jobs` into one share per logical CPU (no more than the jobs),
## largest part first, each to the share with the least code so far.
_shares(jobs: PartJob[], sizes: ulong[]): Array<PartJob[]> {
    var cpus = async.logical_cpus();
    var count = cpus < (jobs.count as ulong) ? cpus : jobs.count as ulong;
    if (count < 1) {
        count = 1;
    }
    var ordered = jobs.copy();
    ordered.sort((a, b) => {
        var x = _size_of(sizes, a.part);
        var y = _size_of(sizes, b.part);
        return x != y ? (x > y ? -1 : 1) : (a.part < b.part ? -1 : (a.part > b.part ? 1 : 0));
    });
    var shares = Array<PartJob[]>();
    var loads = Array<ulong>();
    for (var _ in 0..count) {
        shares.append(Array<PartJob>());
        loads.append(0);
    }
    for (var job in ordered) {
        ulong least = 0;
        for (var share in 1..loads.count) {
            if (loads[share] < loads[least]) {
                least = share;
            }
        }
        shares[least].append(job);
        loads[least] += _size_of(sizes, job.part);
    }
    return shares;
}

## The size of part `part`, or 0 when `sizes` does not have it.
_size_of(sizes: ulong[], part: uint): ulong {
    return (part as ulong) < sizes.count ? sizes[part as ulong] : 0;
}

## Keeps `job`'s part of `ir`, optimizes it and writes its object, or with
## `lto` its bitcode after the pre-link pipeline: the static constructors
## then stay in `llvm.global_ctors` until the whole program is optimized.
_compile(
    ir: llvm.Module,
    partition: codegen.Partition,
    job: PartJob,
    machine: llvm.TargetMachine,
    opt_level: uint,
    trace_time: bool,
    lto: bool
): Result<void, String> {
    var start = os.Instant.now();
    # `PEPC_TRACE_PARTS` names each stage before it runs and verifies the
    # module between them, to find where a part fails.
    bool tracing = os.environment("PEPC_TRACE_PARTS").is_value();
    _stage(tracing, ir, job, "keep");
    var kept = codegen.keep_part(ir, partition, job.part, tracing);
    if (kept.is_err()) {
        return Result<void, String>.err($"cannot split part {job.part}: {kept.error().message}");
    }
    if (opt_level > 0) {
        _stage(tracing, ir, job, "optimize");
        var pipeline = lto ? "lto-pre-link" : "default";
        var optimized = ir.run_passes($"{pipeline}<O{opt_level}>", machine);
        if (optimized.is_err()) {
            return Result<void, String>.err($"cannot optimize: {optimized.error().message}");
        }
    }
    if (lto) {
        _stage(tracing, ir, job, "bitcode");
        var written = ir.write_bitcode(job.object.to_string());
        if (written.is_err()) {
            return Result<void, String>.err($"cannot write {job.object}: {written.error().message}");
        }
        if (trace_time) {
            File.stderr().write_all($"time: part {job.part} {start.elapsed().milliseconds()} ms\n");
        }
        return Result<void, String>.ok();
    }
    _stage(tracing, ir, job, "constructors");
    place_constructors(ir, machine.triple());
    _stage(tracing, ir, job, "emit");
    var emitted = machine.emit_to_file(ir, job.object.to_string());
    if (emitted.is_err()) {
        return Result<void, String>.err($"cannot write {job.object}: {emitted.error().message}");
    }
    if (trace_time) {
        File.stderr().write_all($"time: part {job.part} {start.elapsed().milliseconds()} ms\n");
    }
    return Result<void, String>.ok();
}

## When `tracing`, says which stage of `job` comes next, after checking
## the module the stages before it left.
_stage(tracing: bool, ir: llvm.Module, job: PartJob, stage: String) {
    if (!tracing) {
        return;
    }
    var verified = ir.verify();
    var state = verified.is_ok() ? "valid" : $"INVALID: {verified.error().message}";
    File.stderr().write_all($"part {job.part}: {stage} ({state})\n");
}

## Keeps only the parts of `jobs` in `ir` when other units' objects come
## from the build cache or the jobs hold less than half of its code, as
## after an edit: the bitcode written, and each child's read of it, then
## cover what the edit compiles rather than the whole program.
_keep_jobs(ir: llvm.Module, partition: codegen.Partition, jobs: PartJob[], partial: bool): Result<void> {
    ulong total = 0;
    for (var size in partition.sizes) {
        total += size;
    }
    var parts = HashSet<uint>();
    ulong compiled = 0;
    for (var job in jobs) {
        if (parts.insert(job.part)) {
            compiled += _size_of(partition.sizes, job.part);
        }
    }
    if (!partial and compiled * 2 >= total) {
        return Result<void>.ok();
    }
    return codegen.keep_parts(ir, partition, parts);
}

## Compiles `jobs`, parts of the program `compile_parts` split into `dir`:
## reads the bitcode once, and for each part keeps it (in a copy, but for
## the last), optimizes it at the plan's level and writes its object (or
## its bitcode, for link-time optimization).
## `pepc --compile-part` runs it.
##
## @param dir the folder holding the bitcode and the plan
## @param jobs the parts to compile
## @returns nothing, or why one failed
export compile_part(dir: Path, jobs: PartJob[]): Result<void, String> {
    var read = File.read_to_string(dir.join(Path(_PLAN_FILE)));
    if (read.is_err()) {
        return Result<void, String>.err($"cannot read the plan in {dir}: {read.error().message}");
    }
    var lines = read.value().split("\n");
    if (lines.count < 6) {
        return Result<void, String>.err($"the plan in {dir} is incomplete");
    }
    var level = uint.parse(lines[3]);
    if (!level.is_value() or level.value() > 3) {
        return Result<void, String>.err($"the plan in {dir} has no -O level");
    }
    var part_of = HashMap<String, uint>();
    var trace_time = lines[4] == "true";
    var lto = lines[5] == "true";
    for (var index in 6..lines.count) {
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
    codegen.initialize_backends();
    var machine = llvm.TargetMachine.create(lines[0], lines[1], lines[2], levels[level.value()]);
    if (machine.is_err()) {
        return Result<void, String>.err(machine.error().message);
    }
    var start = os.Instant.now();
    var context = llvm.Context();
    var ir = llvm.Module.read_bitcode(context, dir.join(Path(_BITCODE_FILE)).to_string());
    if (ir.is_err()) {
        return Result<void, String>.err(ir.error().message);
    }
    var partition = codegen.Partition(part_of);
    # Keeping all the parts first makes each copy below smaller.
    if (jobs.count > 1) {
        var parts = HashSet<uint>();
        for (var job in jobs) {
            parts.insert(job.part);
        }
        var kept = codegen.keep_parts(ir.value(), partition, parts);
        if (kept.is_err()) {
            return Result<void, String>.err($"cannot split the parts: {kept.error().message}");
        }
    }
    if (trace_time) {
        File.stderr().write_all($"time: read {jobs.count} parts {start.elapsed().milliseconds()} ms\n");
    }
    for (var i in 0..jobs.count) {
        var module = i + 1 < jobs.count ? ir.value().clone() : ir.value();
        var compiled = _compile(module, partition, jobs[i], machine.value(), level.value(), trace_time, lto);
        if (compiled.is_err()) {
            return compiled;
        }
    }
    return Result<void, String>.ok();
}
