## Compilation units: sema checks a program one compilation unit at a
## time, and the build cache keeps each one's result (its checked unit's
## record, `sema.CheckedUnit`), so an edit costs the compilation units it
## reaches.
##
## A compilation unit is a group of files checked together: one file, or
## the files that import each other in a cycle (and cycles that read each
## other through extensions). The runtime is the first one. A compilation
## unit comes after every compilation unit it reads, so they are the nodes
## of a DAG, in a topological order. Each is checked on its closure only
## (`CompilationUnit.reads`): the records of the compilation units it reads,
## merged (`merged_module`). Its key (`compilation_unit_key`) hashes its
## files and the own interface of each compilation unit it reads
## (`sema.DeltaBase.own_hash`), so an edit outside its closure, or one that
## keeps every own interface in it, loads its record rather than checking it
## again (early cutoff). INTERNALS.md §8.1 describes the whole design.

import [Diagnostic] from compiler.diagnostic;
import digest;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import compiler.sema;
import "cache";

## The record format's version: a new format gets a new folder.
const _RECORDS_FOLDER = "checked16";
## How many keys' records each compilation unit keeps.
const _KEEP_RECORDS = 4;

## One compilation unit: files checked together, on top of the
## compilation units they read.
export struct CompilationUnit {
    ## Its name: `runtime`, or its first file's namespace.
    var name: String;
    ## Its files, as indices into `Program.files`.
    var files: ulong[] = Array<ulong>();
    ## Its files' hash: their names, namespaces and texts.
    var files_key: String = "";
    ## The compilation units it reads, directly or through others, as
    ## indices into the compilation units, in order: the runtime, its files'
    ## imports and the extensions they see.
    var reads: ulong[] = Array<ulong>();
    ## Its record's key: its files' hash and the own interfaces of the
    ## compilation units it reads (`compilation_unit_key`), set as the build
    ## reaches it.
    var key: String = "";

    construct(name: String) {
        this.name = name;
    }
}

## Returns `program`'s compilation units, in the order they are checked; none
## when the runtime cannot be checked alone (a runtime file imports one outside
## it).
##
## @param program the linked program
## @param base what every key starts from (`Keys`' base)
## @returns the compilation units, each with its key
export compilation_units(program: link.Program, base: String): CompilationUnit[] {
    var in_runtime = program.in_runtime();
    var count = program.files.count;
    for (var i in 0..count) {
        if (!in_runtime[i]) {
            continue;
        }
        for (var target in program.files[i].imports) {
            if (target.is_value() and !in_runtime[target.value()]) {
                return Array<CompilationUnit>();
            }
        }
    }
    var cycles = _import_cycles(program);
    var cycle_of = Array<ulong>();
    for (var _ in 0..count) {
        cycle_of.append(0);
    }
    for (var u in 0..cycles.count) {
        for (var file in cycles[u]) {
            cycle_of[file] = u;
        }
    }
    # A cycle is in the runtime when all its files are.
    var runtime_cycle = Array<bool>();
    for (var cycle in cycles) {
        bool all = true;
        for (var file in cycle) {
            all = all and in_runtime[file];
        }
        runtime_cycle.append(all);
    }
    # What each cycle reads: the cycles of the files its files import, and
    # of the extensions they see.
    var reads = Array<HashSet<ulong>>();
    for (var cycle in cycles) {
        var read = HashSet<ulong>();
        for (var file in cycle) {
            for (var target in program.files[file].imports) {
                if (target.is_value()) {
                    read.insert(cycle_of[target.value()]);
                }
            }
            if (file < program.scopes.count) {
                for (var extension in program.scopes[file].extensions) {
                    read.insert(cycle_of[extension]);
                }
                # A type's extensions go with it: a compilation unit that
                # reads the type's file reads them too, so a specialization
                # means the same in every one (`Array<T>.find` uses the `==` an
                # extension gives `T`). The runtime's types are checked on
                # their own, before any file outside it.
                if (!in_runtime[file]) {
                    for (var extender in program.scopes[file].extended_by) {
                        read.insert(cycle_of[extender]);
                    }
                }
            }
        }
        reads.append(read);
    }
    # A cycle whose files only import and re-export declares nothing to
    # check: the linker resolved its names to the files they come from. It
    # is no compilation unit; a cycle reading it reads what it reads
    # instead. One that no cycle reads stays, as the program's own
    # (`pep-build sema/module.pep`).
    var read_by = Array<bool>();
    for (var _ in 0..cycles.count) {
        read_by.append(false);
    }
    for (var u in 0..cycles.count) {
        for (var read in reads[u]) {
            if (read != u) {
                read_by[read] = true;
            }
        }
    }
    var through = Array<bool>();
    for (var u in 0..cycles.count) {
        bool empty = !runtime_cycle[u] and read_by[u];
        for (var file in cycles[u]) {
            empty = empty and program.files[file].module.declarations.is_empty;
        }
        through.append(empty);
    }
    for (var u in 0..cycles.count) {
        if (through[u]) {
            continue;
        }
        var resolved = HashSet<ulong>();
        var pending = Array<ulong>();
        var seen = HashSet<ulong>();
        for (var read in reads[u]) {
            pending.append(read);
        }
        while (!pending.is_empty) {
            var next = pending.remove_at(pending.count - 1);
            if (!through[next]) {
                resolved.insert(next);
            } else if (seen.insert(next)) {
                for (var further in reads[next]) {
                    pending.append(further);
                }
            }
        }
        reads[u] = resolved;
    }
    var skip = Array<bool>();
    for (var u in 0..cycles.count) {
        skip.append(runtime_cycle[u] or through[u]);
    }
    var order = _components(reads, skip);
    var out = Array<CompilationUnit>();
    var unit_of = Array<ulong>();
    for (var _ in 0..cycles.count) {
        unit_of.append(0);
    }
    var runtime = CompilationUnit("runtime");
    for (var u in 0..cycles.count) {
        if (runtime_cycle[u]) {
            runtime.files.append_all(cycles[u]);
        }
    }
    if (!runtime.files.is_empty) {
        out.append(runtime);
    }
    for (var group in order) {
        var unit = CompilationUnit(program.files[cycles[group[0]][0]].namespace);
        for (var u in group) {
            unit.files.append_all(cycles[u]);
            unit_of[u] = out.count;
        }
        out.append(unit);
    }
    # A compilation unit comes after every one it reads, so each one's
    # closure is complete when a later one takes it in.
    var closures = Array<HashSet<ulong>>();
    for (var _ in 0..out.count) {
        closures.append(HashSet<ulong>());
    }
    for (var u in 0..cycles.count) {
        if (runtime_cycle[u] or through[u]) {
            continue;
        }
        var k = unit_of[u];
        if (!runtime.files.is_empty) {
            closures[k].insert(0);
        }
        for (var read in reads[u]) {
            var d = runtime_cycle[read] ? 0 : unit_of[read];
            if (d != k) {
                closures[k].insert(d);
            }
        }
    }
    for (var k in 0..out.count) {
        var direct = Array<ulong>();
        for (var d in closures[k]) {
            direct.append(d);
        }
        for (var d in direct) {
            for (var further in closures[d]) {
                closures[k].insert(further);
            }
        }
        for (var d in closures[k]) {
            out[k].reads.append(d);
        }
        out[k].reads.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
    }
    for (var unit in out) {
        unit.files.sort((a, b) => _compare(program.files[a].namespace, program.files[b].namespace));
        var hasher = digest.Blake3();
        hasher.update(base);
        hasher.update($"\ncompilation unit {unit.name}\n");
        for (var file in unit.files) {
            var f = program.files[file];
            hasher.update($"{f.name}\n{f.namespace}\n{f.prelude} {f.prelude_part}\n{f.source.size}\n");
            hasher.update(f.source);
        }
        unit.files_key = hasher.finish_hex();
    }
    return out;
}

## Returns the key of `unit`'s record: its files and what it is checked on, the
## own interface (`sema.DeltaBase.own_hash`) of each compilation unit it reads.
## A change to a compilation unit it does not read, or one that keeps the own
## interface of every compilation unit it reads, keeps the key: the record is
## still good (early cutoff).
##
## @param unit the compilation unit
## @param owns each compilation unit's own interface, by index: those `unit`
##   reads set
## @returns the key, as hex
export compilation_unit_key(unit: CompilationUnit, owns: String[]): String {
    var hasher = digest.Blake3();
    hasher.update("pepper checked compilation unit 4\n");
    hasher.update(unit.files_key);
    hasher.update("\n");
    for (var d in unit.reads) {
        hasher.update(owns[d]);
        hasher.update("\n");
    }
    return hasher.finish_hex();
}

## Returns the module the compilation units `reads` leave, their records merged
## in order (`sema.RecordIn.merging`), each compilation unit's new declarations
## after those of the compilation units before; or why a record does not merge.
##
## @param program the program
## @param records each compilation unit's record, by index: those of `reads` set
## @param reads the compilation units, in order
## @returns the module
export merged_module(
    program: link.Program, records: HashMap<ulong, u8[]>, reads: ulong[]
): Result<sema.Module, String> {
    var slots = _record_slots(program);
    var module = sema.Module();
    for (var d in reads) {
        var bytes = records.try_get(d);
        if (!bytes.is_value()) {
            return Result<sema.Module, String>.err($"no record of compilation unit {d}");
        }
        var read = _read_record(slots, bytes.value(), Optional<sema.Module>.Value(module), true);
        if (read.is_err()) {
            return Result<sema.Module, String>.err(read.error());
        }
        module = sema.resume_checked(read.value());
    }
    sema.settle_merged(module);
    sema.sort_globals(program, module);
    return Result<sema.Module, String>.ok(module);
}

## The nodes of `reads` but those `skip` names, in groups: the strongly
## connected components of the graph, each group after every group it
## reads (Tarjan's order, the reverse topological order of the
## condensation).
_components(reads: Array<HashSet<ulong>>, skip: bool[]): Array<ulong[]> {
    var count = reads.count;
    var index = Array<long>();
    var low = Array<ulong>();
    var on_stack = Array<bool>();
    for (var _ in 0..count) {
        index.append(-1);
        low.append(0);
        on_stack.append(false);
    }
    var edges = Array<ulong[]>();
    for (var u in 0..count) {
        var targets = Array<ulong>();
        for (var v in reads[u]) {
            if (!skip[v] and v != u) {
                targets.append(v);
            }
        }
        targets.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
        edges.append(targets);
    }
    var stack = Array<ulong>();
    var out = Array<ulong[]>();
    ulong next = 0;
    for (var start in 0..count) {
        if (skip[start] or index[start] >= 0) {
            continue;
        }
        var frames = Array<(ulong, ulong)>();
        index[start] = next as long;
        low[start] = next;
        next += 1;
        stack.append(start);
        on_stack[start] = true;
        frames.append((start, 0));
        while (!frames.is_empty) {
            var (node, edge) = frames[frames.count - 1];
            if (edge < edges[node].count) {
                frames[frames.count - 1] = (node, edge + 1);
                var target = edges[node][edge];
                if (index[target] < 0) {
                    index[target] = next as long;
                    low[target] = next;
                    next += 1;
                    stack.append(target);
                    on_stack[target] = true;
                    frames.append((target, 0));
                } else if (on_stack[target] and (index[target] as ulong) < low[node]) {
                    low[node] = index[target] as ulong;
                }
                continue;
            }
            frames.pop();
            if (!frames.is_empty) {
                var (parent, _) = frames[frames.count - 1];
                if (low[node] < low[parent]) {
                    low[parent] = low[node];
                }
            }
            if (low[node] != index[node] as ulong) {
                continue;
            }
            var group = Array<ulong>();
            while (true) {
                var member = stack.pop();
                on_stack[member] = false;
                group.append(member);
                if (member == node) {
                    break;
                }
            }
            group.sort((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            out.append(group);
        }
    }
    return out;
}

# The files' import cycles, the strongly connected components of the
# import graph, each in namespace order and in the order of its first
# file: what compilation units are made of, one or more each.
_import_cycles(program: link.Program): Array<ulong[]> {
    var imports = Array<HashSet<ulong>>();
    var skip = Array<bool>();
    for (var file in program.files) {
        var targets = HashSet<ulong>();
        for (var target in file.imports) {
            if (target.is_value()) {
                targets.insert(target.value());
            }
        }
        imports.append(targets);
        skip.append(false);
    }
    var cycles = _components(imports, skip);
    for (var cycle in cycles) {
        cycle.sort((a, b) => _compare(program.files[a].namespace, program.files[b].namespace));
    }
    cycles.sort((a, b) => _compare(program.files[a[0]].namespace, program.files[b[0]].namespace));
    return cycles;
}

_compare(a: String, b: String): int {
    return a < b ? -1 : (a > b ? 1 : 0);
}

## Where compilation unit `unit`'s record under its key is.
##
## @param cache the build cache
## @param unit the compilation unit
## @returns the record's path, which need not exist
export record_path(cache: Cache, unit: CompilationUnit): Path {
    return cache.dir.join(Path(_RECORDS_FOLDER)).join(Path(_record_folder(unit.name))).join(Path($"{unit.key}.rec"));
}

# A compilation unit's name as a folder name: its namespace's separators kept as
# folders, anything else plain.
_record_folder(name: String): String {
    return name.replace(":", "_").replace("#", "_");
}

## Writes `checked_unit`'s record, the record of `unit`: a delta on the module
## of the compilation units it reads, merged, which `base` indexes. Returns the
## record and the compilation unit's own interface, what the delta changed in
## the interface (`sema.DeltaBase.own_hash`). The build cache keeps both under
## the compilation unit's key: the record, and beside it its own interface,
## which the keys of the compilation units that read it need without reading the
## record, and the warnings checking it gave, rendered, which a build that loads
## the record prints again (as incremental compilers and ccache replay a unit's
## diagnostics).
##
## @param cache the build cache
## @param program the program
## @param unit the compilation unit
## @param checked_unit the checked unit
## @param base the index of the module the compilation unit was checked on
## @param warned the compilation unit's warnings, rendered, or empty
## @returns the record and the own interface
export store_checked(
    cache: Cache,
    program: link.Program,
    unit: CompilationUnit,
    checked_unit: sema.CheckedUnit,
    base: sema.DeltaBase,
    warned: String
): (u8[], String) {
    var bytes = _record_bytes(program, checked_unit, base);
    var own = base.own_hash();
    var path = record_path(cache, unit);
    var folder = path.parent().value();
    if (Directory.create_all(folder).is_err()) {
        return (bytes, own);
    }
    var partial = Path($"{path}.{process.id()}");
    var own_path = _own_path(path);
    var own_partial = Path($"{own_path}.{process.id()}");
    var warn_path = _warn_path(path);
    var warn_partial = Path($"{warn_path}.{process.id()}");
    if (File.write_bytes(partial, bytes).is_err()
        or File.write_text(own_partial, own).is_err()
        or File.write_text(warn_partial, warned).is_err()
        or File.rename(warn_partial, warn_path).is_err()
        or File.rename(own_partial, own_path).is_err()
        or File.rename(partial, path).is_err()) {
        File.remove(partial);
        File.remove(own_partial);
        File.remove(warn_partial);
        return (bytes, own);
    }
    _prune_records(folder);
    return (bytes, own);
}

## Returns the record of `unit` under its key, its own interface and its
## warnings, rendered, when the cache has them.
##
## @param cache the build cache
## @param program the program
## @param unit the compilation unit, its key set
## @returns the record's bytes, its own interface and its warnings
export find_checked(cache: Cache, program: link.Program, unit: CompilationUnit): (u8[], String, String)? {
    var path = record_path(cache, unit);
    var own = File.read_to_string(_own_path(path));
    if (own.is_err() or own.value().is_empty) {
        return Optional<(u8[], String, String)>.Empty;
    }
    var warned = File.read_to_string(_warn_path(path));
    if (warned.is_err()) {
        return Optional<(u8[], String, String)>.Empty;
    }
    var bytes = File.read_bytes(path);
    if (bytes.is_err()) {
        return Optional<(u8[], String, String)>.Empty;
    }
    var found = (bytes.value(), own.value(), warned.value());
    return Optional<(u8[], String, String)>.Value(found);
}

# Where the warnings of the record at `path` are kept.
_warn_path(path: Path): Path {
    return Path($"{path}.warn");
}

# Where the own interface of the record at `path` is kept.
_own_path(path: Path): Path {
    return Path($"{path}.own");
}

# The program's files by namespace, which a record names its slots by.
_record_slots(program: link.Program): HashMap<String, uint> {
    var out = HashMap<String, uint>();
    for (var i in 0..program.files.count) {
        out[program.files[i].namespace] = i as uint;
    }
    return out;
}

# Keeps the newest `_KEEP_RECORDS` records in `folder`.
_prune_records(folder: Path) {
    var listing = Directory.open(folder);
    if (listing.is_err()) {
        return;
    }
    var entries = listing.value().entries();
    if (entries.is_err()) {
        return;
    }
    var found = Array<(String, long)>();
    for (var entry in entries.value()) {
        if (!entry.name.ends_with(".rec")) {
            continue;
        }
        var metadata = folder.join(Path(entry.name)).metadata();
        if (metadata.is_ok()) {
            found.append((entry.name, metadata.value().modified));
        }
    }
    if (found.count <= _KEEP_RECORDS) {
        return;
    }
    found.sort((a, b) => {
        var (_, x) = a;
        var (_, y) = b;
        return x > y ? -1 : (x < y ? 1 : 0);
    });
    for (var i in (_KEEP_RECORDS as ulong)..found.count) {
        var (name, _) = found[i];
        var path = folder.join(Path(name));
        File.remove(path);
        File.remove(_own_path(path));
        File.remove(_warn_path(path));
    }
}

# The record of `checked_unit`: the program's files' namespaces, then the unit, as
# a delta on `base`.
_record_bytes(program: link.Program, checked_unit: sema.CheckedUnit, base: sema.DeltaBase): u8[] {
    var out = sema.RecordOut();
    # Slot i is program file i; the record keeps their names, so it loads
    # into a program whose files sit elsewhere.
    for (var i in 0..program.files.count) {
        out.files[i as uint] = i as uint;
    }
    out.unsigned(program.files.count);
    for (var file in program.files) {
        out.text(file.namespace);
    }
    checked_unit.write(out, Optional<sema.DeltaBase>.Value(base));
    return out.finish();
}

# Reads the unit in record `bytes`, its slots mapped to the program's files by
# `slots`: a delta merged onto `base`, the module of the compilation units
# before.
_read_record(
    slots: HashMap<String, uint>, bytes: u8[], base: sema.Module?, merging: bool
): Result<sema.CheckedUnit, String> {
    var input = sema.RecordIn(bytes);
    # Most checked bodies are needed by neither the passes nor codegen:
    # each is decoded when one needs it (`sema.PendingBody`).
    input.lazy_bodies = true;
    input.merging = merging;
    var count = input.count();
    for (var _ in 0..count) {
        var file = slots.try_get(input.text());
        input.files.append(file.is_value() ? file.value() : sema.NO_FILE);
    }
    var checked_unit = sema.CheckedUnit.read(input, base);
    if (!input.error.is_empty) {
        return Result<sema.CheckedUnit, String>.err(input.error);
    }
    if (!input.done()) {
        return Result<sema.CheckedUnit, String>.err("the record does not read whole");
    }
    return Result<sema.CheckedUnit, String>.ok(checked_unit);
}
