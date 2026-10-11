## Checking layers in parallel, in worker children: the scheduler that
## hands each layer to an idle worker once the layers it reads are checked
## (`check_in_workers`), and the worker's side, which checks each layer it
## is given and leaves its record (`serve_layers`, `check_for_worker`).
## `pepc --layer-worker` workers also compile each layer into its object
## (`driver`); `pep-lsp --layer-worker` workers only check. INTERNALS.md
## §8.1 describes the protocol.

import async;
import [Diagnostic, SourceText, render_all] from compiler.diagnostic;
import [File, Path] from io;
import compiler.link;
import os;
import process;
import compiler.sema;
import "cache";
import "check";
import "layers";

## Returns the file a layer worker and the build pass layer `k`'s `what`
## through, in `dir`: `<k>.<what>`.
##
## @param dir the folder the build and its workers share
## @param k the layer's number
## @param what what the file holds: `rec`, `own`, `warn`, `err`, `checked`,
##   `done`, ...
## @returns the path
export layer_file(dir: Path, k: ulong, what: String): Path {
    return dir.join(Path($"{k}.{what}"));
}

## Leaves the empty file `<k>.<what>` in `dir`, whole, by a rename.
##
## @param dir the folder the build and its workers share
## @param k the layer's number
## @param what the mark: `checked`, `compiling`, `done`
export mark(dir: Path, k: ulong, what: String) {
    var partial = layer_file(dir, k, $"{what}.{process.id()}");
    File.write_text(partial, "");
    File.rename(partial, layer_file(dir, k, what));
}

# The record, own interface and warnings a worker left for layer `k` in
# `dir`.
_read_worker_record(dir: Path, k: ulong, layer: Layer): Result<(u8[], String, String), String> {
    var bytes = File.read_bytes(layer_file(dir, k, "rec"));
    var own = File.read_to_string(layer_file(dir, k, "own"));
    if (bytes.is_err() or own.is_err()) {
        return Result<(u8[], String, String), String>.err($"the worker checking layer {layer.name} left no record");
    }
    # Its warnings `check_layers` gives back, with the record.
    var warned = File.read_to_string(layer_file(dir, k, "warn"));
    return Result<(u8[], String, String), String>.ok(
        (bytes.value(), own.value(), warned.is_ok() ? warned.value() : "")
    );
}

# A layer worker child: its process, and the layer it checks, if any.
struct _Worker {
    var child: process.Child;
    var layer: long = -1;
    ## Whether it was told which layers were done (its first line).
    var told: bool = false;

    construct(child: process.Child) {
        this.child = child;
    }
}

## Checks layers `0..count` in up to `jobs` worker children of this
## executable (`<worker_args> --layer-worker <dir>`), each layer once the
## layers it reads are done, and puts in `prechecked` the record, own
## interface and warnings of every one, found in the cache or checked:
## `check_layers` takes them from there, not from the cache again, which
## builds running at once may have changed since. A worker leaves a layer's
## record (`<k>.checked`) before it is done with it (`<k>.done`), so the
## layers reading it start while it compiles.
##
## @param program the program
## @param layered its layers
## @param count how many layers, from the first, to check
## @param cache the build cache
## @param jobs how many workers may check or compile at once
## @param prechecked where each layer's record, own interface and warnings go
## @param dir the folder the workers pass layers through, which exists
## @param worker_args the arguments a worker is started with, before
##   `--layer-worker <dir>`
## @param early_worker a worker started already, to use first
## @param trace_time whether to leave `schedule` in `dir`: each layer a worker
##   checked, when it began and ended, and the layers it reads
## @param usable whether layer `k`, found in the cache, can be used as it
##   is: a build also needs its object (and gives the workers what it
##   defines); one that is not is checked again
## @returns nothing, or why a layer could not be checked
export check_in_workers(
    program: link.Program,
    layered: Layer[],
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
    # A layer's record is ready (`checked`), then its object (`done`).
    var checked = Array<bool>();
    var done = Array<bool>();
    var started = Array<bool>();
    # With `-T time`, when each layer a worker checked began and ended, in
    # milliseconds from the start, with the layers it reads (`schedule`, as
    # Ninja's `.ninja_log`): the chain of layers that bounds the build.
    var clock_start = os.Instant.now();
    var schedule = StringBuilder();
    var began = HashMap<ulong, ulong>();
    for (var _ in 0..layered.count) {
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
            # A layer is checked on the records of the layers it reads.
            bool reads_done = true;
            for (var d in layered[k].reads) {
                reads_done = reads_done and checked[d];
            }
            if (!reads_done) {
                continue;
            }
            started[k] = true;
            progressed = true;
            layered[k].key = layer_key(layered[k], owns);
            var found = find_checked(cache, program, layered[k]);
            if (found.is_value() and usable(k)) {
                var (bytes, own, warned) = found.value();
                File.write_bytes(layer_file(dir, k, "rec"), bytes);
                owns[k] = own;
                prechecked[k] = (bytes, own, warned);
                checked[k] = true;
                done[k] = true;
                left -= 1;
            } else {
                ready.append(k);
            }
        }
        # Each ready layer to an idle worker, starting one while fewer than
        # `jobs` are checking or compiling: one waiting for the objects of
        # the layers it reads uses no processor, but holds the program in
        # memory (at most half again as many workers, and two more).
        while (!ready.is_empty) {
            var idle = Optional<ulong>.Empty;
            ulong active = 0;
            for (var w in 0..workers.count) {
                var at = workers[w].layer;
                if (at < 0) {
                    if (!idle.is_value()) {
                        idle = Optional<ulong>.Value(w);
                    }
                } else if (!checked[at as ulong] or layer_file(dir, at as ulong, "compiling").is_file()) {
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
                command.argument("--layer-worker").argument(dir.to_string());
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
            var line = StringBuilder();
            if (!worker.told) {
                # The layers done already, whose files' bodies the worker
                # need not read, as the build's own process does not.
                line.append("done");
                for (var d in 0..layered.count) {
                    if (checked[d]) {
                        line.append($" {d}");
                    }
                }
                line.append("\n");
                worker.told = true;
            }
            line.append($"{k} {layered[k].key}\n");
            var sent = worker.child.stdin().write_all(line.to_string());
            if (sent.is_err()) {
                failure = Optional<String>.Value($"a layer worker stopped: {sent.error().message}");
                break;
            }
            worker.layer = k as long;
            began[k] = (os.Instant.now() - clock_start).milliseconds() as ulong;
            progressed = true;
        }
        for (var worker in workers) {
            if (worker.layer < 0) {
                continue;
            }
            var k = worker.layer as ulong;
            if (!checked[k] and layer_file(dir, k, "checked").is_file()) {
                var record = _read_worker_record(dir, k, layered[k]);
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
            if (!layer_file(dir, k, "done").is_file()) {
                var ended = worker.child.try_wait();
                if (ended.is_err() or ended.value().is_value()) {
                    failure = Optional<String>.Value($"the worker checking layer {layered[k].name} ended");
                }
                continue;
            }
            worker.layer = -1;
            progressed = true;
            if (trace_time) {
                var reads = StringBuilder();
                for (var d in layered[k].reads) {
                    reads.append($" {d}");
                }
                var ended = (os.Instant.now() - clock_start).milliseconds();
                schedule.append($"{k} {layered[k].name} {began[k]} {ended}{reads.to_string()}\n");
            }
            var error = File.read_to_string(layer_file(dir, k, "err"));
            if (error.is_ok()) {
                failure = Optional<String>.Value(error.value());
                continue;
            }
            if (!checked[k]) {
                failure = Optional<String>.Value($"the worker checking layer {layered[k].name} left no record");
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

## A worker's side of `check_in_workers`: reads lines from standard input
## until it ends, and for each `<k> <key>` hands layer `k`, with that key
## and the records of the layers it reads (`<d>.rec` in `dir`), to `work`,
## leaves its error in `<k>.err` if it gives one, then `<k>.done`. The first
## line, `done k...`, names the layers done when the worker started, whose
## files' bodies it does not read; the others' are linked before the first
## layer it is given.
##
## @param program the program, loaded as the build loads it, its bodies
##   deferred
## @param layered its layers, as the build made them
## @param dir the folder the build and its workers share
## @param clock times the stages
## @param work checks layer `k` on the records given: its error, if any
## @returns the exit code: 0 once standard input ends
export serve_layers(
    program: link.Program, layered: Layer[], dir: Path, clock: Clock, work: (ulong, HashMap<ulong, u8[]>) => String?
): int {
    # The files whose bodies are read: all but those of the layers done
    # when the worker started (its first line, `done k...`), which it is
    # never given; linked at the first layer it is.
    var bodies = every_file(program);
    bool linked = false;
    for (var read in File.stdin().lines()) {
        if (read.is_err()) {
            break;
        }
        var parts = read.value().trim().split(" ");
        if (parts.count > 0 and parts[0] == "done") {
            for (var i in 1..parts.count) {
                var d = ulong.parse(parts[i]);
                if (d.is_value() and d.value() < layered.count) {
                    for (var file in layered[d.value()].files) {
                        bodies[file] = false;
                    }
                }
            }
            continue;
        }
        if (parts.count != 2) {
            continue;
        }
        if (!linked) {
            var unread = program.link_bodies(bodies);
            if (unread.is_value()) {
                File.stderr().write_all($"pepc: {unread.value()}\n");
                return 1;
            }
            linked = true;
            clock.lap("worker link bodies");
        }
        var number = ulong.parse(parts[0]);
        if (!number.is_value() or number.value() >= layered.count) {
            continue;
        }
        var k = number.value();
        var layer = layered[k];
        layer.key = parts[1];
        var records = HashMap<ulong, u8[]>();
        String? error;
        for (var d in layer.reads) {
            var bytes = File.read_bytes(layer_file(dir, d, "rec"));
            if (bytes.is_err()) {
                error = Optional<String>.Value($"no record of layer {layered[d].name} for layer {layer.name}");
                break;
            }
            records[d] = bytes.value();
        }
        if (!error.is_value()) {
            error = work(k, records);
        }
        if (error.is_value()) {
            File.write_text(layer_file(dir, k, "err"), error.value());
        }
        mark(dir, k, "done");
    }
    return 0;
}

## Checks `layer` (number `k`) for a worker on the merged `records` of the
## layers it reads, stores its record in the cache, and leaves it in `dir`
## (`<k>.rec`, `<k>.own`, `<k>.warn`), then `<k>.checked`: the layers that
## read it are checked on it while it compiles (pipelining, as a build
## system starts a library's dependents on its interface while its code
## generates).
##
## @param program the program
## @param layer the layer
## @param records the records of the layers it reads, by number
## @param cache the build cache
## @param reused the units whose objects the cache has, when the build
##   generates code
## @param sources the program's sources
## @param dir the folder the build and its workers share
## @param k the layer's number
## @param stages where the time each stage took goes, a line each
## @param times where the time each pass took goes, left in `<k>.passes`
##   too (`-T passes`), if anywhere
## @returns the module checked and its passes' state, or the error, rendered
export check_for_worker(
    program: link.Program,
    layer: Layer,
    records: HashMap<ulong, u8[]>,
    cache: Cache,
    reused: Reused?,
    sources: SourceText[],
    dir: Path,
    k: ulong,
    stages: StringBuilder,
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): Result<(sema.Module, sema.PassState), String> {
    var t0 = os.Instant.now();
    var merged = merged_module(program, records, layer.reads);
    if (merged.is_err()) {
        return Result<(sema.Module, sema.PassState), String>.err(
            $"the layers layer {layer.name} reads do not merge: {merged.error()}"
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
    var checked = check_layer(program, module, layer, reused, sources, warnings, times);
    if (checked.is_err()) {
        return Result<(sema.Module, sema.PassState), String>.err(render_all([checked.error()], sources));
    }
    if (times.is_value()) {
        File.write_text(layer_file(dir, k, "passes"), times.value().to_text());
    }
    var t3 = os.Instant.now();
    stages.append($"check {(t3 - t2).milliseconds()}\n");
    var (after, state, aliases) = checked.value();
    var unit = sema.finish_checked(after, state, aliases);
    var t4 = os.Instant.now();
    stages.append($"finish {(t4 - t3).milliseconds()}\n");
    var warned = render_warnings(warnings, sources);
    var (bytes, own) = store_checked(cache, program, layer, unit, base, warned);
    var t5 = os.Instant.now();
    stages.append($"store {(t5 - t4).milliseconds()}\n");
    File.write_bytes(layer_file(dir, k, "rec"), bytes);
    File.write_text(layer_file(dir, k, "own"), own);
    if (!warned.is_empty) {
        File.write_text(layer_file(dir, k, "warn"), warned);
    }
    mark(dir, k, "checked");
    return Result<(sema.Module, sema.PassState), String>.ok((after, state));
}
