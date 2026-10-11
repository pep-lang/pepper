## Checking a program one compilation unit at a time (`compilation_units.pep`),
## loading each compilation unit's record from the build cache when its key is
## there: what `pepc` builds with (`driver.build`), and what the language server
## checks a document's program with, so an edit checks only the compilation
## units it reaches. Nothing here generates code, so a program that only checks
## does not link LLVM.

import [Diagnostic, SourceText, render_all] from compiler.diagnostic;
import [File, Path] from io;
import compiler.link;
import os;
import compiler.sema;
import "cache";
import "compilation_units";

## Orders diagnostics by file, then by where in it they start; those
## without a location first.
##
## @param a one diagnostic
## @param b the other
## @returns -1, 0 or 1, as `a` comes before, with or after `b`
export compare_locations(a: Diagnostic, b: Diagnostic): int {
    if (!a.location.is_value() or !b.location.is_value()) {
        return (a.location.is_value() ? 1 : 0) - (b.location.is_value() ? 1 : 0);
    }
    var x = a.location.value();
    var y = b.location.value();
    if (x.file != y.file) {
        return x.file < y.file ? -1 : 1;
    }
    if (x.span.start != y.span.start) {
        return x.span.start < y.span.start ? -1 : 1;
    }
    return 0;
}

## Whether `PEPC_VERIFY_CUTOFF` checks every compilation unit loaded by early
## cutoff again and compares: its record, written on an earlier check of the
## compilation units below, must be what checking it on them now gives.
_verify_cutoff(): bool {
    var named = os.environment("PEPC_VERIFY_CUTOFF");
    return named.is_value() and !named.value().is_empty;
}

## Whether `PEPC_TRACE_COMPILATION_UNITS` prints, for each compilation unit, the
## compilation units it reads and the hash of what it changed in the interface
## (`sema.DeltaBase.own_hash`).
_trace_compilation_units(): bool {
    var named = os.environment("PEPC_TRACE_COMPILATION_UNITS");
    return named.is_value() and !named.value().is_empty;
}

## Whether `PEPC_RECORD_STATS` prints the bytes each field of the module
## took in each delta record stored.
_record_stats(): bool {
    var named = os.environment("PEPC_RECORD_STATS");
    return named.is_value() and !named.value().is_empty;
}

## Returns every file of `program`, for `Program.link_bodies`.
##
## @param program the program
## @returns `true` for each of its files
export every_file(program: link.Program): bool[] {
    var out = Array<bool>();
    for (var _ in program.files) {
        out.append(true);
    }
    return out;
}

## Returns the ones of `warnings` in a file of `unit`.
##
## @param warnings the warnings
## @param unit the compilation unit
## @returns those in its files
export warnings_in(warnings: Diagnostic[], unit: CompilationUnit): Diagnostic[] {
    var files = HashSet<ulong>();
    for (var file in unit.files) {
        files.insert(file);
    }
    var out = Array<Diagnostic>();
    for (var w in warnings) {
        if (w.location.is_value() and files.contains(w.location.value().file)) {
            out.append(w);
        }
    }
    return out;
}

## Renders `warnings` in order of their places, as the build prints them:
## what a compilation unit's record keeps to print again when it is loaded.
##
## @param warnings the warnings
## @param sources the program's sources
## @returns the text, or empty when there are none
export render_warnings(warnings: Diagnostic[], sources: SourceText[]): String {
    if (warnings.is_empty) {
        return "";
    }
    var ordered = Array<Diagnostic>();
    ordered.append_all(warnings);
    ordered.sort((a, b) => compare_locations(a, b));
    return render_all(ordered, sources) + "\n";
}

## Why `check_compilation_units` stopped.
export enum CheckError {
    ## A file's bodies did not read: `Program.link_bodies`' error.
    Unread(message: String),
    ## The program's linking or visibility errors (`Program.check_diagnostics`).
    Linking(diagnostics: Diagnostic[]),
    ## The error checking a compilation unit found.
    Checking(diagnostic: Diagnostic),
    ## The cache's records did not merge, or one loaded by early cutoff
    ## differs from the compilation unit checked again (`PEPC_VERIFY_CUTOFF`).
    Failed(message: String),
}

## What `check_compilation_units` gives: the module checked and the state of the
## last compilation unit's passes; or, when the cache has the last compilation
## unit's objects (`driver`'s `_store_last`), only their folder.
export struct Checked {
    ## The module: the last compilation unit checked on the records of the
    ## compilation units it reads.
    var module: sema.Module;
    ## The state of the last compilation unit's passes.
    var state: sema.PassState;
    ## The cache's folder of the last compilation unit's objects, when it has
    ## them.
    var last: Path? = Optional<Path>.Empty;

    ## @param module the module checked
    ## @param state the state of its passes
    construct(module: sema.Module, state: sema.PassState) {
        this.module = module;
        this.state = state;
    }
}

## Checks `program` one compilation unit at a time (`compilation_units.pep`).
## Each compilation unit is keyed on its files and the own interfaces of the
## compilation units it reads; the cache's record under that key is loaded, else
## the compilation unit is checked on the module of the compilation units it
## reads, their records merged, and its record stored. The last compilation
## unit, the program's own, has no record: it is checked unless, with
## `last_extension`, the cache has its objects under its key. With `stop`, that
## compilation unit is checked as the last one is, and the compilation units
## after it are not looked at: the language server checks the compilation unit
## of the document it shows. A compilation unit loaded gives back the warnings
## its check gave, which its record keeps.
##
## @param program the program, loaded with `Setup.defer_bodies`: the bodies
##   of the files of the compilation units checked are linked here
## @param units its compilation units (`compilation_units`)
## @param cache the build cache
## @param reused the translation units whose objects the cache has, when the
##   build generates code
## @param sources the program's sources
## @param warnings where the warnings of the compilation units checked go
## @param replayed where the warnings of the compilation units loaded go,
##   rendered
## @param clock times the stages
## @param trace whether to say on standard error where each compilation unit
##   came from
## @param verify whether to check every compilation unit loaded by early cutoff
##   again
## @param prechecked the records compilation unit workers made, by compilation
##   unit
## @param last_extension the objects' extension when the cache may hold the
##   last compilation unit's objects (`driver`'s `_store_last`), else empty
## @param stop the compilation unit to check last, whose record is neither
##   loaded nor stored; none for the last compilation unit
## @param times where the time each pass took goes (`-T passes`), if anywhere
## @returns what was checked (`Checked`), or why it stopped
export check_compilation_units(
    program: link.Program,
    units: CompilationUnit[],
    cache: Cache,
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[],
    replayed: String[],
    clock: Clock,
    trace: bool,
    verify: bool,
    prechecked: HashMap<ulong, (u8[], String, String)> = HashMap<ulong, (u8[], String, String)>(),
    last_extension: String = "",
    stop: ulong? = Optional<ulong>.Empty,
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): Result<Checked, CheckError> {
    var last = stop.is_value() ? stop.value() : units.count - 1;
    var module = sema.Module();
    var state = sema.PassState(program.target);
    # Each compilation unit's own interface and record, as loaded or checked.
    var owns = Array<String>();
    for (var _ in 0..units.count) {
        owns.append("");
    }
    var records = HashMap<ulong, u8[]>();
    # The compilation units loaded, whose files' bodies are not linked.
    var loaded = HashSet<ulong>();
    bool checked_any = false;
    bool verify_cutoff = verify or _verify_cutoff();
    bool trace_compilation_units = _trace_compilation_units();
    for (var k in 0..last + 1) {
        units[k].key = compilation_unit_key(units[k], owns);
        var unit = units[k];
        # The last compilation unit is the program's own, checked on every build
        # that gets this far.
        if (k < last) {
            # What this build's workers found or made, else the cache's: the
            # cache may have changed since, as builds share it.
            var found = prechecked.contains(k) ?
                Optional<(u8[], String, String)>.Value(prechecked[k]) :
                find_checked(cache, program, unit);
            if (found.is_value()) {
                var (bytes, own, warned) = found.value();
                # Its warnings, as checking it gave them.
                if (!warned.is_empty) {
                    replayed.append(warned);
                }
                if (verify_cutoff and checked_any) {
                    var wrong = _verify_reuse_merged(program, units, records, k, bytes, reused, sources, warnings);
                    if (wrong.is_value()) {
                        return Result<Checked, CheckError>.err(
                            CheckError.Failed($"PEPC_VERIFY_CUTOFF: {wrong.value()}")
                        );
                    }
                }
                owns[k] = own;
                records[k] = bytes;
                loaded.insert(k);
                clock.lap($"find {unit.name}");
                if (trace_compilation_units) {
                    File.stderr().write_all($"compilation unit {unit.name} own {own.substr(0, 16)} loaded\n");
                }
                if (trace) {
                    var how = checked_any ? "unchanged interface below" : "checked already";
                    File.stderr().write_all($"cache: compilation unit {unit.name} {how}\n");
                }
                continue;
            }
        }
        # The last compilation unit's objects, when a build compiled them under
        # its key (`_store_last`): nothing is checked or generated, as Go links
        # a `main` package whose inputs did not change from its cache.
        if (k == last and !last_extension.is_empty) {
            var folder = cache.objects($"compilation unit {unit.name}", unit.key);
            if (folder.join(Path($"entry.{last_extension}")).is_file()) {
                var out = Checked(module, state);
                out.last = Optional<Path>.Value(folder);
                return Result<Checked, CheckError>.ok(out);
            }
        }
        # The first compilation unit to check: the files of the compilation
        # units not loaded are linked and checked before it. Those of the
        # compilation units loaded are as they were when checked, without an
        # error or a warning (see `store`).
        if (!checked_any) {
            var bodies = every_file(program);
            for (var j in loaded) {
                for (var file in units[j].files) {
                    bodies[file] = false;
                }
            }
            var unread = program.link_bodies(bodies);
            if (unread.is_value()) {
                return Result<Checked, CheckError>.err(CheckError.Unread(unread.value()));
            }
            var errors = program.check_diagnostics();
            if (errors.count > 0) {
                return Result<Checked, CheckError>.err(CheckError.Linking(errors));
            }
            warnings.append_all(program.warnings());
            clock.lap("link bodies");
        }
        # The compilation units it reads, their records merged.
        var merged = merged_module(program, records, unit.reads);
        if (merged.is_err()) {
            return Result<Checked, CheckError>.err(
                CheckError.Failed(
                    $"the compilation units that compilation unit {unit.name} reads do not merge: {merged.error()}"
                )
            );
        }
        module = merged.value();
        clock.lap($"merge {unit.name}");
        # What its record is a delta on, indexed before the compilation unit
        # changes it.
        var base = sema.DeltaBase();
        if (k < last) {
            sema.index_module(module, base);
            clock.lap("index");
        }
        var checked = check_compilation_unit(program, module, unit, reused, sources, warnings, times);
        if (checked.is_err()) {
            return Result<Checked, CheckError>.err(CheckError.Checking(checked.error()));
        }
        var (after, ran_state, aliases) = checked.value();
        module = after;
        state = ran_state;
        checked_any = true;
        clock.lap($"compilation unit {unit.name}");
        if (k == last) {
            break;
        }
        var checked_unit = sema.finish_checked(module, state, aliases);
        # A compilation unit with a warning is checked again on each build,
        # which reports it again; so a compilation unit loaded had none.
        var (
            bytes,
            own
        ) = store_checked(
            cache, program, unit, checked_unit, base, render_warnings(warnings_in(warnings, unit), sources)
        );
        owns[k] = own;
        records[k] = bytes;
        clock.lap("store");
        if (_record_stats()) {
            _print_record_stats(unit.name, base);
        }
        if (trace_compilation_units) {
            File.stderr().write_all($"compilation unit {unit.name} own {own.substr(0, 16)} checked\n");
        }
    }
    if (trace) {
        File.stderr().write_all($"cache: {loaded.count} of {units.count} compilation units checked already\n");
    }
    var out = Checked(module, state);
    return Result<Checked, CheckError>.ok(out);
}

## Checks compilation unit `unit`'s files on top of `module`, the compilation
## units it reads.
##
## @param program the program
## @param module the records of the compilation units `unit` reads, merged
##   (`merged_module`)
## @param unit the compilation unit
## @param reused the translation units whose objects the cache has, when the
##   build generates code
## @param sources the program's sources
## @param warnings where its warnings go
## @param times where the time each pass took goes (`-T passes`), if anywhere
## @returns the module after, the passes' state and the type aliases as
##   built; or the error
export check_compilation_unit(
    program: link.Program,
    module: sema.Module,
    unit: CompilationUnit,
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[],
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), Diagnostic> {
    # The specializations the checked compilation units asked for met their
    # constraints when they were checked.
    var checked_specs = (module.struct_specs.count, module.func_specs.count);
    var built = sema.build_on(program, module, unit.files);
    if (built.is_err()) {
        return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), Diagnostic>.err(built.error());
    }
    var after = built.value();
    var aliases = Array<sema.TypeAliasDef>();
    for (var alias in after.type_aliases) {
        aliases.append(alias.copy());
    }
    # Summaries for the build cache's skipped bodies; a compilation unit records
    # the ones it makes either way (`settled_summaries`).
    after.record_summaries = reused.is_value();
    if (reused.is_value()) {
        after.cached_files = reused.value().files;
        for (var (loc, text) in reused.value().summaries) {
            after.recorded_summaries[loc] = text;
        }
    }
    var state = sema.PassState(program.target);
    state.sources = sources;
    state.checked_specs = checked_specs;
    state.pass_times = times;
    # No lazy methods: a later compilation unit may use a method this one would
    # drop from a specialization it made.
    var ran = sema.run_steps_with(after, state, 0xffffffffffffffff);
    for (var note in state.notes) {
        warnings.append(note);
    }
    if (ran.is_err()) {
        return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), Diagnostic>.err(ran.error());
    }
    return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[]), Diagnostic>.ok((after, state, aliases));
}

# For `PEPC_VERIFY_CUTOFF`: checks compilation unit `k`, loaded by early cutoff,
# again on the compilation units it reads, merged, and compares the result with
# its record.
_verify_reuse_merged(
    program: link.Program,
    units: CompilationUnit[],
    records: HashMap<ulong, u8[]>,
    k: ulong,
    bytes: u8[],
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[]
): String? {
    var merged = merged_module(program, records, units[k].reads);
    if (merged.is_err()) {
        return Optional<String>.Value(
            $"the compilation units that compilation unit {units[k].name} reads do not merge: {merged.error()}"
        );
    }
    var reads = Array<ulong>();
    reads.append_all(units[k].reads);
    reads.append(k);
    var all = HashMap<ulong, u8[]>();
    for (var (d, b) in records) {
        all[d] = b;
    }
    all[k] = bytes;
    var loaded = merged_module(program, all, reads);
    if (loaded.is_err()) {
        return Optional<String>.Value(
            $"the record of compilation unit {units[k].name} does not merge: {loaded.error()}"
        );
    }
    # Checked again, then resumed and settled as merging leaves a module.
    var checked = check_compilation_unit(program, merged.value(), units[k], reused, sources, warnings);
    if (checked.is_err()) {
        return Optional<String>.Value(
            $"compilation unit {units[k].name} does not check again: {render_all([checked.error()], sources)}"
        );
    }
    var (after, state, aliases) = checked.value();
    var again = sema.resume_checked(sema.finish_checked(after, state, aliases));
    sema.settle_merged(again);
    sema.sort_globals(program, again);
    # Which files' objects the cache holds is this build's, not the compilation
    # unit's.
    again.cached_files = loaded.value().cached_files;
    return _differ(units[k], sema.CheckedUnit(loaded.value()), sema.CheckedUnit(again));
}

# What differs between `checked_unit`, compilation unit `unit`'s record as
# loaded, and `again`, the compilation unit checked again; none when nothing
# does.
_differ(unit: CompilationUnit, checked_unit: sema.CheckedUnit, again: sema.CheckedUnit): String? {
    var expected = sema.RecordOut();
    again.write(expected);
    var actual = sema.RecordOut();
    checked_unit.write(actual);
    if (!(expected.finish() == actual.finish())) {
        # Name what differs: the fields, structs and functions.
        var was = HashMap<String, String>();
        for (var (what, hash) in sema.interface_fields(again.module, false)) {
            was[what] = hash;
        }
        var differ = Array<String>();
        for (var (what, hash) in sema.interface_fields(checked_unit.module, false)) {
            var had = was.try_get(what);
            if (!had.is_value() or had.value() != hash) {
                differ.append(what);
            }
            was.remove(what);
        }
        for (var (what, _) in was) {
            differ.append(what + " (only checked again)");
        }
        # The checked summaries that differ, by key: as loaded, then as
        # checked again.
        var fresh = again.module.checked.summaries;
        var kept = checked_unit.module.checked.summaries;
        ulong told = 0;
        for (var (key, (loc, text)) in kept) {
            var other = fresh.try_get(key);
            var same = false;
            if (other.is_value()) {
                var (other_loc, other_text) = other.value();
                same = other_loc == loc and other_text == text;
            }
            if (!same and told < 8) {
                var shown_other = "none";
                if (other.is_value()) {
                    var (other_loc, other_text) = other.value();
                    shown_other = $"{other_loc.file}:{other_loc.span.start} {other_text}";
                }
                differ.append($"summary {key}: {loc.file}:{loc.span.start} {text} / {shown_other}");
                told += 1;
            }
        }
        for (var (key, _) in fresh) {
            if (!kept.contains(key) and told < 8) {
                differ.append($"summary {key} only checked again");
                told += 1;
            }
        }
        for (var name in again.module.checked.functions) {
            if (!checked_unit.module.checked.functions.contains(name) and told < 12) {
                differ.append($"checked function {name} only checked again");
                told += 1;
            }
        }
        for (var name in checked_unit.module.checked.functions) {
            if (!again.module.checked.functions.contains(name) and told < 16) {
                differ.append($"checked function {name} only loaded");
                told += 1;
            }
        }
        if (checked_unit.module.checked.extensions != again.module.checked.extensions) {
            differ.append(
                $"checked extensions {checked_unit.module.checked.extensions} / {again.module.checked.extensions}"
            );
        }
        var shown = Array<String>();
        for (var i in 0..(differ.count < 40 ? differ.count : 40)) {
            shown.append(differ[i]);
        }
        return Optional<String>.Value(
            $"the record of compilation unit {unit.name} loaded by early cutoff differs from the compilation unit checked again in {differ.count} parts: {", ".join(shown)}"
        );
    }
    return Optional<String>.Empty;
}

# Prints the bytes and counts `PEPC_RECORD_STATS` gathered for one record.
_print_record_stats(name: String, base: sema.DeltaBase) {
    var sizes = Array<(String, ulong)>();
    for (var (field, bytes) in base.stats) {
        sizes.append((field, bytes));
    }
    sizes.sort((a, b) => {
        var (_, x) = a;
        var (_, y) = b;
        return x > y ? -1 : (x < y ? 1 : 0);
    });
    for (var (field, bytes) in sizes) {
        if (field.ends_with(" count")) {
            File.stderr().write_all($"record: {name} {field} {bytes}\n");
        } else if (bytes >= 1024) {
            File.stderr().write_all($"record: {name} {field} {bytes / 1024} KB\n");
        }
    }
}

## Prints how long each stage of a build took (`-T time`).
export struct Clock {
    ## Whether it prints.
    var on: bool;
    ## When the current stage began.
    var start: os.Instant;

    ## @param on whether it prints
    construct(on: bool) {
        this.on = on;
        start = os.Instant.now();
    }

    ## Prints how long `stage` took, since the last stage ended.
    lap(stage: String) {
        if (!on) {
            return;
        }
        var now = os.Instant.now();
        File.stderr().write_all($"time: {stage} {(now - start).milliseconds()} ms\n");
        start = now;
    }
}
