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
## (`sema.DeltaBase.own_text`), so an edit outside its closure, or one that
## keeps every own interface in it, loads its record rather than checking it
## again (early cutoff). INTERNALS.md §8.1 describes the whole design.

import [Diagnostic] from compiler.diagnostic;
import digest;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import compiler.sema;
import "cache";
import [file_names] from "interface";

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
    ## What every key of the build starts from (`Keys`' base): the compiler,
    ## the target and the build options.
    var base: String = "";
    ## The compilation units it reads, directly or through others, as
    ## indices into the compilation units, in order: the runtime, its files'
    ## imports and the extensions they see.
    var reads: ulong[] = Array<ulong>();
    ## Its record's key: its files' hash and the own interfaces of the
    ## compilation units it reads (`compilation_unit_key`), set as the build
    ## reaches it.
    var key: String = "";
    ## Every name in its files' code, the names its files show every
    ## compilation unit that reads it, and those each of their declarations
    ## shows code that names it (`file_names`).
    var mentions: HashSet<String> = HashSet<String>();
    var shown: HashSet<String> = HashSet<String>();
    var shown_by: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>();
    ## The compilation units whose `shown_by` has each name, by index: one
    ## map every compilation unit of the program shares.
    var shown_in: HashMap<String, ulong[]> = HashMap<String, ulong[]>();
    ## The names its code can name (`_names_reached`), once a key needed
    ## them: a build computes each key twice, scheduling the workers and
    ## checking. Empty again after `mentions`, `shown` or `shown_by`
    ## change.
    var reach: HashSet<String>? = Optional<HashSet<String>>.Empty;
    # Its own interface as `compilation_unit_key` reads it, once a key read
    # it, and the text it was read from.
    var _own_lines: _OwnLines? = Optional<_OwnLines>.Empty;

    construct(name: String) {
        this.name = name;
    }
}

## Returns `program`'s compilation units, in the order they are checked; none
## when the runtime cannot be checked alone (a runtime file imports one outside
## it), or, with `root_last`, when a compilation unit reads the root's.
##
## @param program the linked program
## @param base what every key starts from (`Keys`' base)
## @param root_last whether the root's compilation unit must come last, as a
##   build's, which defines the entry points; the language server checks the
##   document's and none after it
## @returns the compilation units, each with its key
export compilation_units(program: link.Program, base: String, root_last: bool = true): CompilationUnit[] {
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
    # The last compilation unit is the program's own, which defines the entry
    # points: the root file's. Files of the root's module it never reads can
    # come after it in that order; move it last when nothing reads it,
    # else check the program whole.
    if (root_last and !_move_root_last(order, cycle_of[0], reads, skip)) {
        return Array<CompilationUnit>();
    }
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
        unit.base = base;
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
        for (var file in unit.files) {
            var (all, shown, shown_by) = file_names(program.files[file]);
            for (var name in all) {
                unit.mentions.insert(name);
            }
            for (var name in shown) {
                unit.shown.insert(name);
            }
            for (var (name, names) in shown_by) {
                if (!unit.shown_by.contains(name)) {
                    unit.shown_by[name] = HashSet<String>();
                }
                for (var shown_name in names) {
                    unit.shown_by[name].insert(shown_name);
                }
            }
        }
    }
    var shown_in = HashMap<String, ulong[]>();
    for (var u in 0..out.count) {
        out[u].shown_in = shown_in;
        for (var (name, _) in out[u].shown_by) {
            if (!shown_in.contains(name)) {
                shown_in[name] = Array<ulong>();
            }
            shown_in[name].append(u);
        }
    }
    return out;
}

## Returns the key of compilation unit `k`'s record: its files and what it is
## checked on, the own interface (`sema.DeltaBase.own_text`) of each compilation
## unit it reads. Of the entries of functions, structs and enums that are not
## generic, it takes those its code can name (`_names_reached`), and of a
## struct's methods those it names or may call without naming
## (`_OwnLines.taken_by`); all of the runtime's, which the compiler's own
## code calls. A change to a compilation unit it does not read, or one
## that keeps what it takes of every own interface in it, keeps the key: the
## record is still good (early cutoff).
##
## @param units the compilation units
## @param k the compilation unit's index
## @param owns each compilation unit's own interface, by index: those unit `k`
##   reads set
## @returns the key, as hex
export compilation_unit_key(units: CompilationUnit[], k: ulong, owns: String[]): String {
    var unit = units[k];
    var hasher = digest.Blake3();
    hasher.update("pepper checked compilation unit 9\n");
    hasher.update(unit.files_key);
    hasher.update("\n");
    if (!unit.reach.is_value()) {
        unit.reach = Optional<HashSet<String>>.Value(_names_reached(units, unit));
    }
    var reach = unit.reach.value();
    for (var d in unit.reads) {
        var own = _own_lines_of(units[d], owns[d]);
        hasher.update(own.first);
        hasher.update("\n");
        # The compiler's own code calls the runtime's functions by name
        # (`_pep_panic`): a reader can reach any of them, so it takes them
        # all, as their hash.
        if (units[d].name == "runtime") {
            hasher.update(own.all);
            hasher.update("\n");
            continue;
        }
        for (var i in 0..own.lines.count) {
            if (own.taken_by(reach, i)) {
                hasher.update(own.lines[i]);
                hasher.update("\n");
            }
        }
    }
    return hasher.finish_hex();
}

# An own interface's lines after its first, each with the name it is under:
# a declaration's, or a method's struct and its own (`DeltaBase.own_text`).
struct _OwnLines {
    var text: String;
    var first: String = "";
    # The hash of every line after the first.
    var all: String = "";
    var lines: String[] = Array<String>();
    var names: String[] = Array<String>();
    var members: String[] = Array<String>();
    # Whether code may call each method without naming it.
    var unnamed: bool[] = Array<bool>();

    construct(text: String) {
        this.text = text;
        var split = text.split("\n");
        first = split[0];
        var hasher = digest.Blake3();
        for (var i in 1..split.count) {
            var line = split[i];
            hasher.update(line);
            hasher.update("\n");
            var name = line.substr(0, line.find(" ") as ulong);
            var method = name.split_once("\t");
            lines.append(line);
            if (!method.is_value()) {
                names.append(name);
                members.append("");
                unnamed.append(false);
                continue;
            }
            var (owner, member) = method.value();
            names.append(owner);
            # A field's line (`.{field}`) goes by the field's name.
            bool field = member.starts_with(".");
            members.append(field ? member.substr_bytes(1, member.size - 1) : member);
            unnamed.append(!field and sema.called_without_naming(member));
        }
        all = hasher.finish_hex();
    }

    # Whether a unit whose code can name `reach` takes line `i`: a
    # declaration it can name, or a method of a struct it can name that it
    # names too or that code may call without naming it.
    taken_by(reach: HashSet<String>, i: ulong): bool {
        if (!reach.contains(names[i])) {
            return false;
        }
        return members[i].is_empty or unnamed[i] or reach.contains(members[i]);
    }
}

# `unit`'s own interface `own` as `compilation_unit_key` reads it, read once.
_own_lines_of(unit: CompilationUnit, own: String): _OwnLines {
    if (unit._own_lines.is_value() and unit._own_lines.value().text == own) {
        return unit._own_lines.value();
    }
    var lines = _OwnLines(own);
    unit._own_lines = Optional<_OwnLines>.Value(lines);
    return lines;
}

# The names `unit`'s code can name: those in its files, those the files it
# reads show every reader, and, closing over them, those each declaration
# so named shows.
_names_reached(units: CompilationUnit[], unit: CompilationUnit): HashSet<String> {
    var reach = HashSet<String>();
    var pending = Array<String>();
    var add = (name: String) => {
        if (!reach.contains(name)) {
            reach.insert(name);
            pending.append(name);
        }
    };
    for (var name in unit.mentions) {
        add(name);
    }
    for (var d in unit.reads) {
        for (var name in units[d].shown) {
            add(name);
        }
    }
    var reads = Array<bool>();
    for (var _ in 0..units.count) {
        reads.append(false);
    }
    for (var d in unit.reads) {
        reads[d] = true;
    }
    while (pending.count > 0) {
        var name = pending.pop();
        var holders = unit.shown_in.try_get(name);
        if (!holders.is_value()) {
            continue;
        }
        for (var d in holders.value()) {
            if (!reads[d]) {
                continue;
            }
            for (var shown_name in units[d].shown_by[name]) {
                add(shown_name);
            }
        }
    }
    return reach;
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

## Returns `module` with record `bytes` merged on, as `merged_module` merges
## each, its locations moved by `shift`; or why it does not merge.
##
## @param program the program
## @param module the module the record's compilation unit reads, merged
## @param bytes the record
## @param shift where its locations are now
## @returns the module
export merged_onto(
    program: link.Program, module: sema.Module, bytes: u8[], shift: sema.LocShift
): Result<sema.Module, String> {
    var read = _read_record(
        _record_slots(program), bytes, Optional<sema.Module>.Value(module), true, Optional<sema.LocShift>.Value(shift)
    );
    if (read.is_err()) {
        return Result<sema.Module, String>.err(read.error());
    }
    var out = sema.resume_checked(read.value());
    sema.settle_merged(out);
    sema.sort_globals(program, out);
    return Result<sema.Module, String>.ok(out);
}

# Moves the group of `order` holding cycle `root` last. Whether it could: no
# other cycle, but those `skip` names, reads that group.
_move_root_last(order: Array<ulong[]>, root: ulong, reads: Array<HashSet<ulong>>, skip: bool[]): bool {
    for (var g in 0..order.count) {
        if (!order[g].contains(root)) {
            continue;
        }
        var group = order.remove_at(g);
        for (var u in 0..reads.count) {
            if (group.contains(u) or skip[u]) {
                continue;
            }
            for (var read in group) {
                if (reads[u].contains(read)) {
                    return false;
                }
            }
        }
        order.append(group);
        return true;
    }
    return true;
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
## the interface (`sema.DeltaBase.own_text`). The build cache keeps both under
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
## @param source what a later re-check of it reads (`recheck_source`)
## @param read_owns the own interfaces of the compilation units it reads
##   (`owns_read`), which the structs whose whole member lists it used are
##   kept beside it from (`member_lines`)
## @returns the record and the own interface
export store_checked(
    cache: Cache,
    program: link.Program,
    unit: CompilationUnit,
    checked_unit: sema.CheckedUnit,
    base: sema.DeltaBase,
    warned: String,
    source: String,
    read_owns: String[]
): (u8[], String) {
    var bytes = _record_bytes(program, checked_unit, base);
    var own = base.own_text();
    var path = record_path(cache, unit);
    var source_path = Path($"{path}.src");
    var source_partial = Path($"{source_path}.{process.id()}");
    var fields_path = _fields_path(path);
    var fields_partial = Path($"{fields_path}.{process.id()}");
    var fields = member_lines(read_owns, _whole_member_lists(checked_unit.module));
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
        or File.write_text(source_partial, source).is_err()
        or File.write_text(fields_partial, fields).is_err()
        or File.rename(fields_partial, fields_path).is_err()
        or File.rename(source_partial, source_path).is_err()
        or File.rename(warn_partial, warn_path).is_err()
        or File.rename(own_partial, own_path).is_err()
        or File.rename(partial, path).is_err()) {
        File.remove(partial);
        File.remove(own_partial);
        File.remove(warn_partial);
        File.remove(source_partial);
        File.remove(fields_partial);
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

# Where the structs whose whole member lists the record at `path` used are
# kept, with what they were (`member_lines`).
_fields_path(path: Path): Path {
    return Path($"{path}.fields");
}

## Whether the structs whose whole member lists `unit`'s record under its key
## used (`store_checked`) have the member lines they had when it was checked:
## a record that copied, extended or reflected on a struct of a compilation
## unit it reads depends on fields its key does not take (the recorded
## dependencies of Salsa's and Bazel's early cutoff). A build that finds
## the record treats a difference as a miss.
##
## @param cache the build cache
## @param unit the compilation unit, its key set
## @param read_owns the own interfaces of the compilation units it reads
##   (`owns_read`)
## @returns whether they match
export fields_still_match(cache: Cache, unit: CompilationUnit, read_owns: String[]): bool {
    var kept = File.read_to_string(_fields_path(record_path(cache, unit)));
    if (kept.is_err()) {
        return false;
    }
    if (kept.value().is_empty) {
        return true;
    }
    var names = Array<String>();
    for (var line in kept.value().trim().split("\n")) {
        names.append(line.substr(0, line.find(" ") as ulong));
    }
    return member_lines(read_owns, names) == kept.value();
}

## The own interfaces of the compilation units `unit` reads, in order.
##
## @param unit the compilation unit
## @param owns each compilation unit's own interface, by number
## @returns those it reads
export owns_read(unit: CompilationUnit, owns: String[]): String[] {
    var out = Array<String>();
    for (var d in unit.reads) {
        out.append(owns[d]);
    }
    return out;
}

## The own-interface lines of each of structs `names` in `owns`, the own
## interfaces of the compilation units a compilation unit reads, hashed:
## a line each, `<struct> <hash>`, sorted. A struct with none (one the
## compilation unit declares) is left out.
##
## @param owns the own interfaces
## @param names the structs' full names
## @returns the lines
export member_lines(owns: String[], names: String[]): String {
    var found = HashMap<String, Array<String>>();
    for (var name in names) {
        found[sema.function_name(name)] = Array<String>();
    }
    if (found.count == 0) {
        return "";
    }
    for (var own in owns) {
        for (var line in own.split("\n")) {
            var name = line.substr(0, line.find(" ") as ulong);
            var tab = name.find("\t");
            var owner = tab < 0 ? name : name.substr(0, tab as ulong);
            if (found.contains(owner)) {
                found[owner].append(line);
            }
        }
    }
    var plains = Array<String>();
    for (var (plain, _) in found) {
        plains.append(plain);
    }
    plains.sort((a, b) => a.compare(b));
    var out = StringBuilder();
    for (var plain in plains) {
        var lines = found[plain];
        if (lines.is_empty) {
            continue;
        }
        var hasher = digest.Blake3();
        for (var line in lines) {
            hasher.update(line);
            hasher.update("\n");
        }
        out.append($"{plain} {hasher.finish_hex()}\n");
    }
    return out.to_string();
}

# The structs of compilation units it read whose whole member lists checking
# `module` used: those it extended, copied or reflected on.
_whole_member_lists(module: sema.Module): String[] {
    var out = Array<String>();
    for (var name in module.extended_checked) {
        out.append(name);
    }
    for (var name in module.field_lists_read) {
        out.append(name);
    }
    return out;
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
        File.remove(Path($"{path}.src"));
        File.remove(_fields_path(path));
    }
}

# The record of `checked_unit`: the program's files' namespaces, then the unit, as
# a delta on `base`.
_record_bytes(program: link.Program, checked_unit: sema.CheckedUnit, base: sema.DeltaBase): u8[] {
    var out = sema.RecordOut();
    out.anchors = Optional<sema.LocAnchors>.Value(base.anchors);
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
# before, which the read may change (`sema.RecordIn.consumes_base`): the
# caller drops it.
_read_record(
    slots: HashMap<String, uint>,
    bytes: u8[],
    base: sema.Module?,
    merging: bool,
    shift: sema.LocShift? = Optional<sema.LocShift>.Empty
): Result<sema.CheckedUnit, String> {
    var input = sema.RecordIn(bytes);
    input.shift = shift;
    # Before the read changes the base.
    if (base.is_value()) {
        input.anchors = Optional<sema.LocAnchors>.Value(sema.anchors_of(base.value()));
    }
    # Most checked bodies are needed by neither the passes nor codegen:
    # each is decoded when one needs it (`sema.PendingBody`).
    input.lazy_bodies = true;
    input.merging = merging;
    input.consumes_base = true;
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
