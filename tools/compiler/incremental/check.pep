## Checking a program one compilation unit at a time (`compilation_units.pep`),
## loading each compilation unit's record from the build cache when its key is
## there: what `pepc` builds with (`driver.build`), and what the language server
## checks a document's program with, so an edit checks only the compilation
## units it reaches. Nothing here generates code, so a program that only checks
## does not link LLVM.

import compiler.ast;
import [Diagnostic, SourceText, render_all] from compiler.diagnostic;
import [File, Path] from io;
import compiler.link;
import os;
import compiler.sema;
import "cache";
import "compilation_units";
import "recheck";

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
## (`sema.DeltaBase.own_text`).
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
    ## The compilation units checked again from an earlier record of them
    ## (`recheck_compilation_unit`), by name.
    var rechecked: String[] = Array<String>();

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
    var rechecked = Array<String>();
    bool verify_cutoff = verify or _verify_cutoff();
    bool trace_compilation_units = _trace_compilation_units();
    for (var k in 0..last + 1) {
        units[k].key = compilation_unit_key(units, k, owns);
        var unit = units[k];
        # The last compilation unit is the program's own, checked on every build
        # that gets this far.
        if (k < last) {
            # What this build's workers found or made, else the cache's: the
            # cache may have changed since, as builds share it.
            var found = prechecked.contains(k) ?
                Optional<(u8[], String, String)>.Value(prechecked[k]) :
                find_checked(cache, program, unit);
            if (found.is_value()
                and !prechecked.contains(k)
                and !fields_still_match(cache, unit, owns_read(unit, owns))) {
                found = Optional<(u8[], String, String)>.Empty;
            }
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
            var folder = cache.objects($"+{unit.name}", unit.key);
            if (cache.used(folder) and folder.join(Path($"entry.{last_extension}")).is_file()) {
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
        # The last compilation unit keeps no record to re-check from.
        var checked = check_unit(
            program,
            module,
            records,
            unit,
            k < last ? Optional<Cache>.Value(cache) : Optional<Cache>.Empty,
            reused,
            sources,
            warnings,
            rechecked,
            times
        );
        if (checked.is_err()) {
            return Result<Checked, CheckError>.err(CheckError.Checking(checked.error()));
        }
        var (after, ran_state, aliases, kept) = checked.value();
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
            cache,
            program,
            unit,
            checked_unit,
            base,
            render_warnings(warnings_in(warnings, unit), sources),
            kept,
            owns_read(unit, owns)
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
    out.rechecked = rechecked;
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

## Checks compilation unit `unit` on `module`, the records of the compilation
## units it reads merged: again from an earlier record of it when the cache
## has one an edit of only bodies left (`recheck_compilation_unit`), else from
## its files (`check_compilation_unit`). Also returns what its record keeps
## for a later re-check (`recheck_source`).
##
## @param program the program
## @param module the records of the compilation units `unit` reads, merged
## @param records each compilation unit's record, by index: those `unit` reads set
## @param unit the compilation unit
## @param cache the build cache, if any
## @param reused the translation units whose objects the cache has, when the
##   build generates code
## @param sources the program's sources
## @param warnings where its warnings go
## @param rechecked where its name goes when it is checked again from a record
## @param times where the time each pass took goes (`-T passes`), if anywhere
## @returns as `check_compilation_unit`, and the text to keep
export check_unit(
    program: link.Program,
    module: sema.Module,
    records: HashMap<ulong, u8[]>,
    unit: CompilationUnit,
    cache: Cache?,
    reused: Reused?,
    sources: SourceText[],
    warnings: Diagnostic[],
    rechecked: String[],
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): Result<(sema.Module, sema.PassState, sema.TypeAliasDef[], String), Diagnostic> {
    var inputs = inputs_digest(records, unit);
    var source = recheck_source(program, unit, inputs);
    var found = cache.is_value() ?
        find_recheck_base(cache.value(), program, unit, inputs) :
        Optional<RecheckBase>.Empty;
    var on = module;
    if (found.is_value()) {
        var again = recheck_compilation_unit(program, on, unit, found.value(), reused, sources, times);
        if (_trace_compilation_units()) {
            var how = again.is_value() ? "rechecked" : "not rechecked";
            File.stderr().write_all(
                $"compilation unit {unit.name} {how}: {found.value().changed.count} bodies changed\n"
            );
        }
        if (again.is_value()) {
            rechecked.append(unit.name);
            var (after, state, aliases) = again.value();
            return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[], String), Diagnostic>.ok(
                (after, state, aliases, source)
            );
        }
        # The re-check changed the merged records: merge them again.
        var merged = merged_module(program, records, unit.reads);
        if (merged.is_err()) {
            return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[], String), Diagnostic>.err(
                Diagnostic.error(
                    $"the compilation units that compilation unit {unit.name} reads do not merge: {merged.error()}"
                )
            );
        }
        on = merged.value();
    }
    var checked = check_compilation_unit(program, on, unit, reused, sources, warnings, times);
    if (checked.is_err()) {
        return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[], String), Diagnostic>.err(checked.error());
    }
    var (after, state, aliases) = checked.value();
    return Result<(sema.Module, sema.PassState, sema.TypeAliasDef[], String), Diagnostic>.ok(
        (after, state, aliases, source)
    );
}

## Checks compilation unit `unit` again from an earlier record of it
## (`find_recheck_base`): the record, read onto `module` with its locations
## moved, keeps everything but the changed bodies, which are checked on top
## as the compilation unit's own code. Gives nothing back, to check the
## compilation unit from its files instead, when a changed function's facts
## (its return type, its link summary) came out other than the record's,
## since code the record keeps was checked against them, or when anything
## else does not fit.
##
## @param program the program
## @param module the records of the compilation units `unit` reads, merged
## @param unit the compilation unit
## @param base the record to start from
## @param reused the translation units whose objects the cache has, when the
##   build generates code
## @param sources the program's sources
## @param times where the time each pass took goes (`-T passes`), if anywhere
## @returns as `check_compilation_unit`, or nothing
export recheck_compilation_unit(
    program: link.Program,
    module: sema.Module,
    unit: CompilationUnit,
    base: RecheckBase,
    reused: Reused?,
    sources: SourceText[],
    times: sema.PassTimes? = Optional<sema.PassTimes>.Empty
): (sema.Module, sema.PassState, sema.TypeAliasDef[])? {
    var merged = merged_onto(program, module, base.bytes, base.shift);
    if (merged.is_err()) {
        return _not_rechecked("merge");
    }
    var after = merged.value();
    # The record's specializations met their constraints when it was checked.
    var checked_specs = (after.struct_specs.count, after.func_specs.count);
    var aliases = Array<sema.TypeAliasDef>();
    for (var alias in after.type_aliases) {
        aliases.append(alias.copy());
    }
    # Each changed function or method, as checked, and its body as built now.
    var (by_loc, repeated) = _by_loc(after);
    var built = HashMap<uint, sema.Module>();
    var rechecked = Array<(sema.FunctionDef, String, String)>();
    var methods = HashSet<String>();
    for (var (file, name, body) in base.changed) {
        if (!built.contains(file)) {
            var made = sema.build_file(program.files[file as ulong].module, file);
            if (made.is_err()) {
                return _not_rechecked("build");
            }
            built[file] = made.value();
        }
        var loc = sema.Loc.at(file, name);
        var old = by_loc.try_get(loc);
        var (fresh_by_loc, _) = _by_loc(built[file]);
        var fresh = fresh_by_loc.try_get(loc);
        if (!old.is_value() or repeated.contains(loc) or !fresh.is_value() or !fresh.value().0.body.is_value()) {
            return _not_rechecked("match");
        }
        var (function, owner, kind) = old.value();
        var checked = kind.is_empty ?
            after.checked.functions.contains(function.name) :
            after.checked.structs.contains(owner);
        if (!checked or fresh.value().2 != kind) {
            return _not_rechecked("match");
        }
        var key = _summary_key(function, owner, kind);
        rechecked.append((function, key, _facts(after, function, key)));
        sema.drop_body(function);
        function.body = fresh.value().0.body;
        if (fresh.value().0.ty.is_auto()) {
            function.ty = sema.TypeName.auto();
        }
        if (kind.is_empty) {
            after.checked.functions.remove(function.name);
        } else {
            # Its struct stays checked; the passes walk this body as one an
            # extension added.
            methods.insert($"m {owner} {kind} {function.name}");
        }
        after.checked.summaries.remove(key);
        after.recorded_summaries.remove(function.loc);
    }
    # The structs an added field replaced, as the record had them.
    var replaced = Array<sema.StructDef>();
    for (var (file, name) in base.added) {
        if (!built.contains(file)) {
            var made = sema.build_file(program.files[file as ulong].module, file);
            if (made.is_err()) {
                return _not_rechecked("build");
            }
            built[file] = made.value();
        }
        if (!_add(after, built[file], sema.Loc.at(file, name), methods, replaced)) {
            return _not_rechecked("an added function");
        }
    }
    # A replaced struct's members, checked again whole: what other code was
    # checked against of each, and where its closures were.
    var members = Array<(String, String, String, String)>();
    var dropped = Array<sema.Loc>();
    var copies = HashSet<String>();
    for (var old in replaced) {
        for (var (function, kind) in _members(old)) {
            # Made because code the record keeps copies the struct.
            if (function.name == "__copy") {
                copies.insert(old.name);
            }
            var key = _summary_key(function, old.name, kind);
            members.append((old.name, kind, function.name, _facts(after, function, key)));
            after.checked.summaries.remove(key);
            after.recorded_summaries.remove(function.loc);
        }
        var span = _struct_span(program, old.loc);
        if (!span.is_value()) {
            return _not_rechecked($"the span of {old.name}");
        }
        dropped.append(span.value());
    }
    # The closures the old bodies made went with them; the new ones are
    # numbered after every closure of their files.
    var counts = HashMap<long, ulong>();
    var kept = Array<sema.StructDef>();
    for (var st in after.structs) {
        if (!sema.is_closure_struct(st.name) or st.loc.is_none()) {
            kept.append(st);
            continue;
        }
        if (_in_changed(base, st.loc) or _in_any(dropped, st.loc)) {
            after.checked.structs.remove(st.name);
            continue;
        }
        kept.append(st);
        var digits = st.name.substr(sema.CLOSURE_PREFIX.size, st.name.size).split("@")[0];
        ulong n = 0;
        bool numbered = !digits.is_empty and digits.size < 10;
        for (var b in digits.bytes()) {
            numbered = numbered and b >= '0' as u8 and b <= '9' as u8;
            if (numbered) {
                n = n * 10 + (b - '0' as u8) as ulong;
            }
        }
        if (!numbered) {
            continue;
        }
        var key = st.loc.file as long;
        if (!counts.contains(key) or counts[key] <= n) {
            counts[key] = n + 1;
        }
    }
    after.structs = kept;
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
    state.closure_counts = counts;
    state.rechecked_methods = methods;
    state.copies_again = copies;
    var ran = sema.run_steps_with(after, state, 0xffffffffffffffff);
    if (ran.is_err()) {
        return _not_rechecked($"an error: {ran.error().message}");
    }
    if (!state.notes.is_empty) {
        return _not_rechecked($"a warning: {state.notes[0].message}");
    }
    for (var (function, key, facts) in rechecked) {
        var now = _facts(after, function, key, Optional<sema.PassState>.Value(state));
        if (now != facts) {
            return _not_rechecked($"the facts of {function.name}: {facts} became {now}");
        }
    }
    for (var (owner, kind, name, facts) in members) {
        var found = _member(after, owner, kind, name);
        if (!found.is_value()) {
            return _not_rechecked($"{owner}.{name}, which checking {owner} again dropped");
        }
        var key = _summary_key(found.value(), owner, kind);
        var now = _facts(after, found.value(), key, Optional<sema.PassState>.Value(state));
        if (now != facts) {
            return _not_rechecked($"the facts of {owner}.{name}: {facts} became {now}");
        }
    }
    return Optional<(sema.Module, sema.PassState, sema.TypeAliasDef[])>.Value((after, state, aliases));
}

# Adds the function, method, struct or field at `loc` in `fresh`, its file
# as built now, to `after`, the record it is checked on top of, after the
# one before it in its file, as checking the file would; a method's struct
# is walked again (`methods`), and a field's is replaced whole (`replaced`
# gets the record's). Whether it could: no code the record keeps can call
# it, or anything it declares already.
_add(
    after: sema.Module, fresh: sema.Module, loc: sema.Loc, methods: HashSet<String>, replaced: sema.StructDef[]
): bool {
    # A struct's implicit constructor is where its name is, too.
    for (var st in fresh.structs) {
        if (st.loc == loc) {
            return _add_struct(after, fresh, loc);
        }
        for (var field in st.field_members) {
            if (field.loc == loc) {
                return _add_field(after, st, replaced);
            }
        }
    }
    var (by_loc, _) = _by_loc(fresh);
    var found = by_loc.try_get(loc);
    if (!found.is_value()) {
        return false;
    }
    var (function, owner, kind) = found.value();
    var name = sema.set_name(function.name);
    if (kind == "constructor" or sema.called_without_naming(name) or !function.body.is_value()) {
        return false;
    }
    # A trait's method of that name may dispatch to it.
    for (var t in after.traits) {
        for (var m in t.methods) {
            if (sema.set_name(m.name) == name) {
                return false;
            }
        }
    }
    if (kind.is_empty) {
        for (var f in after.functions) {
            if (sema.set_name(f.name) == name) {
                return false;
            }
        }
        # A file's first function has none before it to follow.
        var at = _after_previous(fresh.functions, after.functions, loc);
        if (!at.is_value() or at.value() == 0) {
            return false;
        }
        after.functions.insert(at.value(), function);
        if (fresh.private_functions.contains(loc)) {
            after.private_functions.insert(loc);
        }
        if (fresh.file_private_functions.contains(loc)) {
            after.file_private_functions.insert(loc);
        }
        return true;
    }
    if (!after.checked.structs.contains(owner)) {
        return false;
    }
    for (var st in after.structs) {
        if (st.name != owner) {
            continue;
        }
        for (var m in st.method_members) {
            if (sema.set_name(m.name) == name) {
                return false;
            }
        }
        for (var m in st.generic_methods) {
            if (sema.set_name(m.name) == name) {
                return false;
            }
        }
        for (var field in st.field_members) {
            if (field.name == name) {
                return false;
            }
        }
        for (var mine in fresh.structs) {
            if (mine.name != owner) {
                continue;
            }
            var at = _after_previous(mine.method_members, st.method_members, loc);
            if (!at.is_value()) {
                return false;
            }
            st.method_members.insert(at.value(), function);
            methods.insert($"m {owner} method {function.name}");
            return true;
        }
    }
    return false;
}

# Adds the struct at `loc` in `fresh` to `after`, after the struct before
# it in its file, unchecked, so the passes check it whole. Whether it could:
# not the first struct of its file, and no struct of its name already.
_add_struct(after: sema.Module, fresh: sema.Module, loc: sema.Loc): bool {
    for (var i in 1..fresh.structs.count) {
        if (fresh.structs[i].loc != loc) {
            continue;
        }
        var added = fresh.structs[i];
        for (var st in after.structs) {
            if (st.name == added.name) {
                return false;
            }
        }
        for (var j in 0..after.structs.count) {
            if (after.structs[j].loc == fresh.structs[i - 1].loc) {
                after.structs.insert(j + 1, added);
                return true;
            }
        }
        return false;
    }
    return false;
}

# Replaces the record's struct of the name of `fresh`, a struct as built now
# with a field the record's lacks, with `fresh`, unchecked, so the passes
# check it whole: its members' bodies, the members they synthesize from its
# fields (`__dtor`, copies) and its layout. Code outside it reads its fields
# by name and its layout from code generation, which the passes leave alone.
# Adds the record's struct to `replaced`. Whether it could: the record has
# the struct, checked, and is not generic.
_add_field(after: sema.Module, fresh: sema.StructDef, replaced: sema.StructDef[]): bool {
    for (var old in replaced) {
        if (old.name == fresh.name) {
            # Another field of it, which `fresh` has too.
            return true;
        }
    }
    if (fresh.generic_params.count > 0 or !after.checked.structs.contains(fresh.name)) {
        return false;
    }
    for (var j in 0..after.structs.count) {
        if (after.structs[j].name != fresh.name) {
            continue;
        }
        replaced.append(after.structs[j]);
        after.structs[j] = fresh;
        after.checked.structs.remove(fresh.name);
        after.extended_checked.remove(fresh.name);
        return true;
    }
    return false;
}

# The methods and constructors of `st`, each with its kind.
_members(st: sema.StructDef): Array<(sema.FunctionDef, String)> {
    var out = Array<(sema.FunctionDef, String)>();
    for (var m in st.method_members) {
        out.append((m, "method"));
    }
    for (var c in st.constructors) {
        out.append((c, "constructor"));
    }
    return out;
}

# The method or constructor (`kind`) `name` of struct `owner` in `module`.
_member(module: sema.Module, owner: String, kind: String, name: String): sema.FunctionDef? {
    for (var st in module.structs) {
        if (st.name != owner) {
            continue;
        }
        for (var (function, k) in _members(st)) {
            if (k == kind and function.name == name) {
                return Optional<sema.FunctionDef>.Value(function);
            }
        }
    }
    return Optional<sema.FunctionDef>.Empty;
}

# Where the whole struct whose name is at `loc` is in its file now.
_struct_span(program: link.Program, loc: sema.Loc): sema.Loc? {
    for (var declaration in program.files[loc.file as ulong].module.declarations) {
        if (declaration is Struct(decl)) {
            if (decl.name_span.start == loc.span.start and decl.name_span.end == loc.span.end) {
                return Optional<sema.Loc>.Value(sema.Loc.at(loc.file, decl.span));
            }
        }
    }
    return Optional<sema.Loc>.Empty;
}

# Whether `loc` is inside one of `spans`, in the same file.
_in_any(spans: sema.Loc[], loc: sema.Loc): bool {
    for (var span in spans) {
        if (loc.file == span.file and loc.span.start >= span.span.start and loc.span.end <= span.span.end) {
            return true;
        }
    }
    return false;
}

# Where in `into` the function at `loc` in `fresh` goes: after the one
# before it in `fresh`, by location, or first when none is before it.
_after_previous(fresh: sema.FunctionDef[], into: sema.FunctionDef[], loc: sema.Loc): ulong? {
    for (var i in 0..fresh.count) {
        if (fresh[i].loc != loc) {
            continue;
        }
        if (i == 0) {
            return Optional<ulong>.Value(0);
        }
        for (var j in 0..into.count) {
            if (into[j].loc == fresh[i - 1].loc) {
                return Optional<ulong>.Value(j + 1);
            }
        }
        return Optional<ulong>.Empty;
    }
    return Optional<ulong>.Empty;
}

# Nothing, after saying why with `PEPC_TRACE_COMPILATION_UNITS`.
_not_rechecked(why: String): (sema.Module, sema.PassState, sema.TypeAliasDef[])? {
    if (_trace_compilation_units()) {
        File.stderr().write_all($"recheck: no, at {why}\n");
    }
    return Optional<(sema.Module, sema.PassState, sema.TypeAliasDef[])>.Empty;
}

# Whether `loc` is in a body `base` changed: where `LocShift` puts what was
# in the old one.
_in_changed(base: RecheckBase, loc: sema.Loc): bool {
    for (var (file, _, body) in base.changed) {
        if (loc.file == file and loc.span.start >= body.start and loc.span.end <= body.end) {
            return true;
        }
    }
    return false;
}

# What other code was checked against of function or method `function`,
# whose summary key is `key`: its return type and settled link summary,
# without the blame's place.
_facts(
    module: sema.Module,
    function: sema.FunctionDef,
    key: String,
    state: sema.PassState? = Optional<sema.PassState>.Empty
): String {
    var summary = module.checked.summaries.try_get(key);
    var text = summary.is_value() ? summary.value().1 : "";
    if (state.is_value()) {
        var settled = state.value().settled_summaries.try_get(key);
        text = settled.is_value() ? settled.value().1 : "";
    }
    return $"{function.ty}\n{sema.summary_without_place(text)}";
}

# The link summary key of `function`: a free function's name, or its
# struct's and its own (a constructor's as `__ctor`).
_summary_key(function: sema.FunctionDef, owner: String, kind: String): String {
    if (kind.is_empty) {
        return function.name;
    }
    return kind == "constructor" ? sema.method_key(function.name, "__ctor") : sema.method_key(owner, function.name);
}

# The free functions of `module`, and the methods and constructors of its
# structs that are not generic, by location, with their struct's name and
# kind (`method`, `constructor`, empty for a free function); and the
# locations more than one has.
_by_loc(module: sema.Module): (HashMap<sema.Loc, (sema.FunctionDef, String, String)>, HashSet<sema.Loc>) {
    var out = HashMap<sema.Loc, (sema.FunctionDef, String, String)>();
    var repeated = HashSet<sema.Loc>();
    var add = (function: sema.FunctionDef, owner: String, kind: String) => {
        if (out.contains(function.loc)) {
            repeated.insert(function.loc);
        }
        out[function.loc] = (function, owner, kind);
    };
    for (var f in module.functions) {
        add(f, "", "");
    }
    for (var st in module.structs) {
        if (st.generic_params.count > 0 or sema.is_closure_struct(st.name)) {
            continue;
        }
        for (var m in st.method_members) {
            add(m, st.name, "method");
        }
        for (var c in st.constructors) {
            add(c, st.name, "constructor");
        }
    }
    return (out, repeated);
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
            if (same or told >= 8) {
                continue;
            }
            var shown_other = "none";
            if (other.is_value()) {
                var (other_loc, other_text) = other.value();
                shown_other = $"{other_loc.file}:{other_loc.span.start} {other_text}";
            }
            differ.append($"summary {key}: {loc.file}:{loc.span.start} {text} / {shown_other}");
            told += 1;
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
