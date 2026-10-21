## Checking compilation units in parallel, in worker children: the scheduler
## that hands each compilation unit to an idle worker once the compilation units
## it reads are checked (`check_in_workers`), and the worker's side, which
## checks each compilation unit it is given and leaves its record
## (`serve_compilation_units`, `check_for_worker`). `pepc
## --compilation-unit-worker` workers also compile each compilation unit into
## its object (`driver`); `pep-lsp --compilation-unit-worker` workers only
## check. INTERNALS.md §8.1 describes the protocol.

import async;
import [Diagnostic, SourceText, render_all] from compiler.diagnostic;
import [File, Path] from io;
import compiler.link;
import os;
import process;
import compiler.sema;
import "cache";
import "check";
import "compilation_units";

## Returns the file a compilation unit worker and the build pass compilation
## unit `k`'s `what` through, in `dir`: `<k>.<what>`.
##
## @param dir the folder the build and its workers share
## @param k the compilation unit's number
## @param what what the file holds: `rec`, `own`, `warn`, `err`, `checked`,
##   `done`, ...
## @returns the path
export worker_file(dir: Path, k: ulong, what: String): Path {
    return dir.join(Path($"{k}.{what}"));
}

## Leaves the empty file `<k>.<what>` in `dir`, whole, by a rename.
##
## @param dir the folder the build and its workers share
## @param k the compilation unit's number
## @param what the mark: `checked`, `compiling`, `done`
export mark(dir: Path, k: ulong, what: String) {
    var partial = worker_file(dir, k, $"{what}.{process.id()}");
    File.write_text(partial, "");
    File.rename(partial, worker_file(dir, k, what));
}

# The record, own interface and warnings a worker left for compilation unit `k`
# in `dir`.
_read_worker_record(dir: Path, k: ulong, unit: CompilationUnit): Result<(u8[], String, String), String> {
    var bytes = File.read_bytes(worker_file(dir, k, "rec"));
    var own = File.read_to_string(worker_file(dir, k, "own"));
    if (bytes.is_err() or own.is_err()) {
        return Result<(u8[], String, String), String>.err(
            $"the worker checking compilation unit {unit.name} left no record"
        );
    }
    # Its warnings `check_compilation_units` gives back, with the record.
    var warned = File.read_to_string(worker_file(dir, k, "warn"));
    return Result<(u8[], String, String), String>.ok(
        (bytes.value(), own.value(), warned.is_ok() ? warned.value() : "")
    );
}

# A compilation unit worker child: its process, and the compilation unit it
# checks, if any.
struct _Worker {
    var child: process.Child;
    var unit: long = -1;

    construct(child: process.Child) {
        this.child = child;
    }
}

## Checks compilation units `0..count` in up to `jobs` worker children of this
## executable (`<worker_args> --compilation-unit-worker <dir>`), each
## compilation unit once the compilation units it reads are done, and puts in
## `prechecked` the record, own interface and warnings of every one, found in
## the cache or checked: `check_compilation_units` takes them from there, not
## from the cache again, which builds running at once may have changed since. A
## worker leaves a compilation unit's record (`<k>.checked`) before it is done
## with it (`<k>.done`), so the compilation units reading it start while it
## compiles.
##
## @param program the program
## @param units its compilation units
## @param count how many compilation units, from the first, to check
## @param cache the build cache
## @param jobs how many workers may check or compile at once
## @param prechecked where each compilation unit's record, own interface and
##   warnings go
## @param dir the folder the workers pass compilation units through, which
##   exists
## @param worker_args the arguments a worker is started with, before
##   `--compilation-unit-worker <dir>`
## @param early_worker a worker started already, to use first
## @param trace_time whether to leave `schedule` in `dir`: each compilation unit
##   a worker checked, when it began and ended, and the compilation units it
##   reads
## @param usable whether compilation unit `k`, found in the cache, can be used
##   as it is, asked once the compilation units it reads are done (those
##   reading it start on its record before): a build also needs its object,
##   one that links with theirs (and gives the workers what it defines); one
##   that is not is checked again, which compiles it
## @returns nothing, or why a compilation unit could not be checked
export check_in_workers(
    program: link.Program,
    units: CompilationUnit[],
    count: ulong,
    cache: Cache,
    jobs: ulong,
    prechecked: HashMap<ulong, (u8[], String, String)>,
    dir: Path,
    worker_args: String[],
    early_worker: process.Child?,
    trace_time: bool,
    usable: (ulong) => bool
): Result<void, String> {
    var executable = process.executable_path();
    if (executable.is_err()) {
        return Result<void, String>.err($"cannot find this compiler: {executable.error().message}");
    }
    var owns = Array<String>();
    # A compilation unit's record is ready (`checked`), then its object
    # (`done`).
    var checked = Array<bool>();
    var done = Array<bool>();
    var started = Array<bool>();
    # The hits whose objects are not yet known to link (`usable`).
    var linking = Array<ulong>();
    # With `-T time`, when each compilation unit a worker checked began and
    # ended, in milliseconds from the start, with the compilation units it reads
    # (`schedule`, as Ninja's `.ninja_log`): the chain of compilation units that
    # bounds the build.
    var clock_start = os.Instant.now();
    var schedule = StringBuilder();
    var began = HashMap<ulong, ulong>();
    for (var _ in 0..units.count) {
        owns.append("");
        checked.append(false);
        done.append(false);
        started.append(false);
    }
    var ready = Array<ulong>();
    var workers = Array<_Worker>();
    if (early_worker.is_value()) {
        workers.append(_Worker(early_worker.value()));
    }
    ulong left = count;
    var failure = Optional<String>.Empty;
    while (left > 0 and !failure.is_value()) {
        bool progressed = false;
        for (var k in 0..count) {
            if (started[k]) {
                continue;
            }
            # A compilation unit is checked on the records of the compilation
            # units it reads.
            bool reads_done = true;
            for (var d in units[k].reads) {
                reads_done = reads_done and checked[d];
            }
            if (!reads_done) {
                continue;
            }
            started[k] = true;
            progressed = true;
            units[k].key = compilation_unit_key(units, k, owns);
            var found = find_checked(cache, program, units[k]);
            if (found.is_value() and fields_still_match(cache, units[k], owns_read(units[k], owns))) {
                var (bytes, own, warned) = found.value();
                File.write_bytes(worker_file(dir, k, "rec"), bytes);
                File.write_text(worker_file(dir, k, "own"), own);
                owns[k] = own;
                prechecked[k] = (bytes, own, warned);
                checked[k] = true;
                linking.append(k);
            } else {
                ready.append(k);
            }
        }
        # A hit's object declares what the objects of the compilation units
        # it reads define, so whether it links with theirs (`usable`) waits
        # for those objects, while the compilation units reading its record
        # start. One that does not is checked again, which compiles it.
        var waiting = Array<ulong>();
        for (var k in linking) {
            bool objects_done = true;
            for (var d in units[k].reads) {
                objects_done = objects_done and done[d];
            }
            if (!objects_done) {
                waiting.append(k);
                continue;
            }
            progressed = true;
            if (usable(k)) {
                done[k] = true;
                left -= 1;
            } else {
                ready.append(k);
            }
        }
        linking = waiting;
        # Each ready compilation unit to an idle worker, starting one while
        # fewer than `jobs` are checking or compiling: one waiting for the
        # objects of the compilation units it reads uses no processor, but holds
        # the program in memory (at most half again as many workers, and two
        # more).
        while (!ready.is_empty) {
            var idle = Optional<ulong>.Empty;
            ulong active = 0;
            for (var w in 0..workers.count) {
                var at = workers[w].unit;
                if (at < 0) {
                    if (!idle.is_value()) {
                        idle = Optional<ulong>.Value(w);
                    }
                } else if (!checked[at as ulong] or worker_file(dir, at as ulong, "compiling").is_file()) {
                    active += 1;
                }
            }
            if (active >= jobs) {
                break;
            }
            if (!idle.is_value()) {
                if (workers.count as ulong >= jobs + jobs / 2 + 2) {
                    break;
                }
                var command = process.Command(executable.value().to_string());
                for (var arg in worker_args) {
                    command.argument(arg);
                }
                command.argument("--compilation-unit-worker").argument(dir.to_string());
                command.stdin(process.Stream.Pipe);
                var spawned = command.spawn();
                if (spawned.is_err()) {
                    failure = Optional<String>.Value($"cannot run {executable.value()}: {spawned.error().message}");
                    break;
                }
                workers.append(_Worker(spawned.value()));
                idle = Optional<ulong>.Value(workers.count - 1);
            }
            var k = ready.remove_at(0);
            var worker = workers[idle.value()];
            var sent = worker.child.stdin().write_all($"{k} {units[k].key}\n");
            if (sent.is_err()) {
                failure = Optional<String>.Value($"a compilation unit worker stopped: {sent.error().message}");
                break;
            }
            worker.unit = k as long;
            began[k] = (os.Instant.now() - clock_start).milliseconds() as ulong;
            progressed = true;
        }
        for (var worker in workers) {
            if (worker.unit < 0) {
                continue;
            }
            var k = worker.unit as ulong;
            if (!checked[k] and worker_file(dir, k, "checked").is_file()) {
                var record = _read_worker_record(dir, k, units[k]);
                if (record.is_err()) {
                    failure = Optional<String>.Value(record.error());
                    continue;
                }
                var (bytes, own, warned) = record.value();
                owns[k] = own;
                prechecked[k] = (bytes, own, warned);
                checked[k] = true;
                progressed = true;
            }
            if (!worker_file(dir, k, "done").is_file()) {
                var ended = worker.child.try_wait();
                if (ended.is_err() or ended.value().is_value()) {
                    failure = Optional<String>.Value($"the worker checking compilation unit {units[k].name} ended");
                }
                continue;
            }
            worker.unit = -1;
            progressed = true;
            if (trace_time) {
                var reads = StringBuilder();
                for (var d in units[k].reads) {
                    reads.append($" {d}");
                }
                var ended = (os.Instant.now() - clock_start).milliseconds();
                schedule.append($"{k} {units[k].name} {began[k]} {ended}{reads.to_string()}\n");
            }
            var error = File.read_to_string(worker_file(dir, k, "err"));
            if (error.is_ok()) {
                failure = Optional<String>.Value(error.value());
                continue;
            }
            if (!checked[k]) {
                failure = Optional<String>.Value(
                    $"the worker checking compilation unit {units[k].name} left no record"
                );
                continue;
            }
            done[k] = true;
            left -= 1;
        }
        if (!progressed and !failure.is_value()) {
            async.Thread.sleep(2);
        }
    }
    if (trace_time) {
        File.write_text(dir.join(Path("schedule")), schedule.to_string());
    }
    for (var worker in workers) {
        worker.child.stdin().close();
    }
    for (var worker in workers) {
        if (failure.is_value()) {
            worker.child.kill();
        }
        worker.child.wait();
    }
    if (failure.is_value()) {
        return Result<void, String>.err(failure.value());
    }
    return Result<void, String>.ok();
}

## A worker's side of `check_in_workers`: reads lines from standard input until
## it ends, and for each `<k> <key>` hands compilation unit `k`, with that key
## and the records of the compilation units it reads (`<d>.rec` in `dir`), to
## `work`, leaves its error in `<k>.err` if it gives one, then `<k>.done`. It
## links the bodies of each compilation unit's own files before checking it
## (`Program.link_bodies`); what it reads comes as records.
##
## @param program the program, loaded as the build loads it, its bodies
##   deferred
## @param units its compilation units, as the build made them
## @param dir the folder the build and its workers share
## @param clock times the stages
## @param work checks compilation unit `k` on the records given: its error, if
##   any
## @returns the exit code: 0 once standard input ends
export serve_compilation_units(
    program: link.Program,
    units: CompilationUnit[],
    dir: Path,
    clock: Clock,
    work: (ulong, HashMap<ulong, u8[]>) => String?
): int {
    for (var read in File.stdin().lines()) {
        if (read.is_err()) {
            break;
        }
        var parts = read.value().trim().split(" ");
        if (parts.count != 2) {
            continue;
        }
        var number = ulong.parse(parts[0]);
        if (!number.is_value() or number.value() >= units.count) {
            continue;
        }
        var k = number.value();
        var unit = units[k];
        unit.key = parts[1];
        # Only its own files' bodies are read: what it reads comes as records.
        var unread = program.link_bodies(_own_files(program, unit));
        if (unread.is_value()) {
            File.stderr().write_all($"pepc: {unread.value()}\n");
            return 1;
        }
        clock.lap("worker link bodies");
        var records = HashMap<ulong, u8[]>();
        String? error;
        for (var d in unit.reads) {
            var bytes = File.read_bytes(worker_file(dir, d, "rec"));
            if (bytes.is_err()) {
                error = Optional<String>.Value(
                    $"no record of compilation unit {units[d].name} for compilation unit {unit.name}"
                );
                break;
            }
            records[d] = bytes.value();
        }
        if (!error.is_value()) {
            error = work(k, records);
        }
        if (error.is_value()) {
            File.write_text(worker_file(dir, k, "err"), error.value());
        }
        mark(dir, k, "done");
    }
    return 0;
}

# Per file of `program`, whether it is one of `unit`'s.
_own_files(program: link.Program, unit: CompilationUnit): bool[] {
    var own = Array<bool>();
    for (var _ in 0..program.files.count) {
        own.append(false);
    }
    for (var file in unit.files) {
        own[file] = true;
    }
    return own;
}

## Checks `unit` (number `k`) for a worker on the merged `records` of the
## compilation units it reads, after the linking and visibility errors in
## its files (`Program.check_diagnostics`), stores its record in the cache, and
## leaves it in `dir` (`<k>.rec`, `<k>.own`, `<k>.warn`), then `<k>.checked`: the compilation
## units that read it are checked on it while it compiles (pipelining, as a
## build system starts a library's dependents on its interface while its code
## generates).
##
## @param program the program
## @param unit the compilation unit
## @param records the records of the compilation units it reads, by number
## @param cache the build cache
## @param reused the translation units whose objects the cache has, when the
##   build generates code
## @param sources the program's sources
## @param dir the folder the build and its workers share
## @param k the compilation unit's number
## @param stages where the time each stage took goes, a line each
## @param times where the time each pass took goes, left in `<k>.passes`
##   too (`-T passes`), if anywhere
## @returns the module checked and its passes' state, or the error, rendered
export check_for_worker(
    program: link.Program,
    unit: CompilationUnit,
    records: HashMap<ulong, u8[]>,
    cache: Cache,
    reused: Reused?,
    sources: SourceText[],
    dir: Path,
    k: ulong,
    stages: StringBuilder,
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): Result<(sema.Module, sema.PassState), String> {
    var start = os.Instant.now();
    # What the build checks before sema, as `check_compilation_units` does:
    # with the bodies of this compilation unit's files linked now, its
    # linking and visibility errors come before what sema would make of them.
    # Only its own files are walked: those of the compilation units this
    # worker checked before are linked too, and checked already.
    var errors = program.check_diagnostics(_own_files(program, unit));
    if (errors.count > 0) {
        return Result<(sema.Module, sema.PassState), String>.err(render_all(errors, sources));
    }
    var t0 = os.Instant.now();
    stages.append($"diagnostics {(t0 - start).milliseconds()}\n");
    var merged = merged_module(program, records, unit.reads);
    if (merged.is_err()) {
        return Result<(sema.Module, sema.PassState), String>.err(
            $"the compilation units that compilation unit {unit.name} reads do not merge: {merged.error()}"
        );
    }
    var module = merged.value();
    var t1 = os.Instant.now();
    stages.append($"merge {(t1 - t0).milliseconds()}\n");
    var base = sema.DeltaBase();
    sema.index_module(module, base);
    var t2 = os.Instant.now();
    stages.append($"index {(t2 - t1).milliseconds()}\n");
    var warnings = Array<Diagnostic>();
    var checked = check_unit(
        program, module, records, unit, Optional<Cache>.Value(cache), reused, sources, warnings, Array<String>(), times
    );
    if (checked.is_err()) {
        return Result<(sema.Module, sema.PassState), String>.err(render_all([checked.error()], sources));
    }
    if (times.is_value()) {
        File.write_text(worker_file(dir, k, "passes"), times.value().to_text());
    }
    var t3 = os.Instant.now();
    stages.append($"check {(t3 - t2).milliseconds()}\n");
    var (after, state, aliases, kept) = checked.value();
    var checked_unit = sema.finish_checked(after, state, aliases);
    var t4 = os.Instant.now();
    stages.append($"finish {(t4 - t3).milliseconds()}\n");
    var warned = render_warnings(warnings, sources);
    # The own interfaces of what it reads, which its workers or the build
    # left beside their records.
    var read_owns = Array<String>();
    for (var d in unit.reads) {
        var read = File.read_to_string(worker_file(dir, d, "own"));
        read_owns.append(read.is_ok() ? read.value() : "");
    }
    var (bytes, own) = store_checked(cache, program, unit, checked_unit, base, warned, kept, read_owns);
    var t5 = os.Instant.now();
    stages.append($"store {(t5 - t4).milliseconds()}\n");
    # A hit checked again for its object (`check_in_workers`) keeps the record
    # the build left, which the compilation units reading it may be reading.
    if (!worker_file(dir, k, "rec").is_file()) {
        File.write_bytes(worker_file(dir, k, "rec"), bytes);
        File.write_text(worker_file(dir, k, "own"), own);
        if (!warned.is_empty) {
            File.write_text(worker_file(dir, k, "warn"), warned);
        }
    }
    mark(dir, k, "checked");
    return Result<(sema.Module, sema.PassState), String>.ok((after, state));
}
