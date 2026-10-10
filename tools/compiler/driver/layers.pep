## Checked layers: sema checks a program one layer at a time, and the build
## cache keeps each layer's result (a checked unit's record,
## `sema.CheckedUnit`), so an edit costs the layers it reaches.
##
## The runtime is the first layer. Each other unit (`link.layer_units`) is a
## layer of its own; units that read each other (through extensions) share
## one. A layer comes after every layer it reads, so the layers are the
## nodes of a DAG, in a topological order. Each layer is checked on its
## closure only (`Layer.reads`): the records of the layers it reads, merged
## (`merged_module`). Its key (`layer_key`) hashes its files and the own
## interface of each layer it reads (`sema.DeltaBase.own_hash`), so an edit
## outside its closure, or one that keeps every own interface in it, loads
## its record rather than checking it again (early cutoff). INTERNALS.md
## §8.1 describes the whole design.

import [Diagnostic] from compiler.diagnostic;
import digest;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import compiler.sema;
import "cache";

## The record format's version: a new format gets a new folder.
const _RECORDS_FOLDER = "checked15";
## How many keys' records each layer keeps.
const _KEEP_RECORDS = 4;

## One layer: files checked together, on top of the layers they read.
export struct Layer {
    ## Its name: `runtime`, or its first unit's.
    var name: String;
    ## Its files, as indices into `Program.files`.
    var files: ulong[] = Array<ulong>();
    ## Its files' hash: their names, namespaces and texts.
    var files_key: String = "";
    ## The layers it reads, directly or through others, as indices into
    ## the layers, in order: the runtime, its units' imports, their modules'
    ## other files and the extensions they see.
    var reads: ulong[] = Array<ulong>();
    ## Its record's key: its files' hash and the own interfaces of the
    ## layers it reads (`layer_key`), set as the build reaches it.
    var key: String = "";

    construct(name: String) {
        this.name = name;
    }
}

## Returns `program`'s layers, in the order they are checked; none when the
## runtime cannot be checked alone (a runtime file imports one outside it).
##
## @param program the linked program
## @param units its units
## @param base what every key starts from (`Keys`' base)
## @returns the layers, each with its key
export layers(program: link.Program, units: link.Unit[], base: String): Layer[] {
    var in_runtime = _runtime_files(program);
    var count = program.files.count;
    for (var i in 0..count) {
        if (!in_runtime[i]) {
            continue;
        }
        for (var target in program.files[i].imports) {
            if (target.is_value() and !in_runtime[target.value()]) {
                return Array<Layer>();
            }
        }
    }
    var unit_of = Array<ulong>();
    for (var _ in 0..count) {
        unit_of.append(0);
    }
    for (var u in 0..units.count) {
        for (var file in units[u].files) {
            unit_of[file] = u;
        }
    }
    # A unit is in the runtime when all its files are.
    var runtime_unit = Array<bool>();
    for (var unit in units) {
        bool all = true;
        for (var file in unit.files) {
            all = all and in_runtime[file];
        }
        runtime_unit.append(all);
    }
    # What each unit reads: the units of the files its files import, and of
    # the extensions they see.
    var reads = Array<HashSet<ulong>>();
    for (var unit in units) {
        var read = HashSet<ulong>();
        for (var file in unit.files) {
            for (var target in program.files[file].imports) {
                if (target.is_value()) {
                    read.insert(unit_of[target.value()]);
                }
            }
            if (file < program.scopes.count) {
                for (var extension in program.scopes[file].extensions) {
                    read.insert(unit_of[extension]);
                }
                # A type's extensions go with it: a layer that reads the
                # type's file reads them too, so a specialization means the
                # same in every layer (`Array<T>.find` uses the `==` an
                # extension gives `T`). The runtime's types are checked on
                # their own, before any file outside it.
                if (!in_runtime[file]) {
                    for (var extender in program.scopes[file].extended_by) {
                        read.insert(unit_of[extender]);
                    }
                }
            }
        }
        reads.append(read);
    }
    # A unit whose files only import and re-export declares nothing to
    # check: the linker resolved its names to the files they come from. It
    # is no layer; a unit reading it reads what it reads instead. One that
    # no unit reads stays, as the program's own (`pep-build sema/module.pep`).
    var read_by = Array<bool>();
    for (var _ in 0..units.count) {
        read_by.append(false);
    }
    for (var u in 0..units.count) {
        for (var read in reads[u]) {
            if (read != u) {
                read_by[read] = true;
            }
        }
    }
    var through = Array<bool>();
    for (var u in 0..units.count) {
        bool empty = !runtime_unit[u] and read_by[u];
        for (var file in units[u].files) {
            empty = empty and program.files[file].module.declarations.is_empty;
        }
        through.append(empty);
    }
    for (var u in 0..units.count) {
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
    for (var u in 0..units.count) {
        skip.append(runtime_unit[u] or through[u]);
    }
    var order = _layer_order(reads, skip);
    var out = Array<Layer>();
    var layer_of = Array<ulong>();
    for (var _ in 0..units.count) {
        layer_of.append(0);
    }
    var runtime = Layer("runtime");
    for (var u in 0..units.count) {
        if (runtime_unit[u]) {
            runtime.files.append_all(units[u].files);
        }
    }
    if (!runtime.files.is_empty) {
        out.append(runtime);
    }
    for (var group in order) {
        var layer = Layer(units[group[0]].name);
        for (var u in group) {
            layer.files.append_all(units[u].files);
            layer_of[u] = out.count;
        }
        out.append(layer);
    }
    # A layer comes after every layer it reads, so each one's closure is
    # complete when a later one takes it in.
    var closures = Array<HashSet<ulong>>();
    for (var _ in 0..out.count) {
        closures.append(HashSet<ulong>());
    }
    for (var u in 0..units.count) {
        if (runtime_unit[u] or through[u]) {
            continue;
        }
        var k = layer_of[u];
        if (!runtime.files.is_empty) {
            closures[k].insert(0);
        }
        for (var read in reads[u]) {
            var d = runtime_unit[read] ? 0 : layer_of[read];
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
    for (var layer in out) {
        layer.files.sort((a, b) => _layer_compare(program.files[a].namespace, program.files[b].namespace));
        var hasher = digest.Blake3();
        hasher.update(base);
        hasher.update($"\nlayer {layer.name}\n");
        for (var file in layer.files) {
            var f = program.files[file];
            hasher.update($"{f.name}\n{f.namespace}\n{f.prelude} {f.prelude_part}\n{f.source.size}\n");
            hasher.update(f.source);
        }
        layer.files_key = hasher.finish_hex();
    }
    return out;
}

## Returns the key of `layer`'s record: its files and what it is checked
## on, the own interface (`sema.DeltaBase.own_hash`) of each layer it reads. A
## change to a layer it does not read, or one that keeps the own interface
## of every layer it reads, keeps the key: the record is still good (early
## cutoff).
##
## @param layer the layer
## @param owns each layer's own interface, by index: those `layer` reads set
## @returns the key, as hex
export layer_key(layer: Layer, owns: String[]): String {
    var hasher = digest.Blake3();
    hasher.update("pepper checked layer 3\n");
    hasher.update(layer.files_key);
    hasher.update("\n");
    for (var d in layer.reads) {
        hasher.update(owns[d]);
        hasher.update("\n");
    }
    return hasher.finish_hex();
}

## Returns the module the layers `reads` leave, their records merged in
## order (`sema.RecordIn.merging`), each layer's new declarations after
## those of the layers before; or why a record does not merge.
##
## @param program the program
## @param records each layer's record, by index: those of `reads` set
## @param reads the layers, in order
## @returns the module
export merged_module(
    program: link.Program, records: HashMap<ulong, u8[]>, reads: ulong[]
): Result<sema.Module, String> {
    var slots = _record_slots(program);
    var module = sema.Module();
    for (var d in reads) {
        var bytes = records.try_get(d);
        if (!bytes.is_value()) {
            return Result<sema.Module, String>.err($"no record of layer {d}");
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

## The units outside the runtime in groups, each group after every group it
## reads: the strongly connected components of `reads`, in reverse
## topological order of the condensation (Tarjan's order), which is the
## order dependencies come first in.
_layer_order(reads: Array<HashSet<ulong>>, skip: bool[]): Array<ulong[]> {
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

## For each file of `program`, whether it is the runtime's: the prelude, a
## forced import, or a file under a runtime folder.
_runtime_files(program: link.Program): bool[] {
    var dirs = Array<String>();
    for (var dir in link.Runtime.discover().dirs) {
        dirs.append(link.path_key(dir));
    }
    var out = Array<bool>();
    for (var file in program.files) {
        bool runtime = file.prelude or file.prelude_part;
        if (!runtime) {
            var key = link.path_key(Path(file.name));
            for (var dir in dirs) {
                if (key.starts_with(dir)) {
                    runtime = true;
                    break;
                }
            }
        }
        out.append(runtime);
    }
    return out;
}

_layer_compare(a: String, b: String): int {
    return a < b ? -1 : (a > b ? 1 : 0);
}

## Where layer `layer`'s record under its key is.
##
## @param cache the build cache
## @param layer the layer
## @returns the record's path, which need not exist
export record_path(cache: Cache, layer: Layer): Path {
    return cache.dir.join(Path(_RECORDS_FOLDER)).join(Path(_record_folder(layer.name))).join(Path($"{layer.key}.rec"));
}

# A layer's name as a folder name: its namespace's separators kept as
# folders, anything else plain.
_record_folder(name: String): String {
    return name.replace(":", "_").replace("#", "_");
}

## Writes `unit`'s record, the record of `layer`: a delta on the module of
## the layers it reads, merged, which `base` indexes. Returns the record and
## the layer's own interface, what the delta changed in the interface
## (`sema.DeltaBase.own_hash`). The build cache keeps both under the layer's
## key: the record, and beside it its own interface, which the keys of the
## layers that read it need without reading the record, and the warnings
## checking it gave, rendered, which a build that loads the record prints
## again (as rustc's incremental cache and ccache replay a unit's
## diagnostics).
##
## @param cache the build cache
## @param program the program
## @param layer the layer
## @param unit the checked unit
## @param base the index of the module the layer was checked on
## @param warned the layer's warnings, rendered, or empty
## @returns the record and the own interface
export store_checked(
    cache: Cache, program: link.Program, layer: Layer, unit: sema.CheckedUnit, base: sema.DeltaBase, warned: String
): (u8[], String) {
    var bytes = _record_bytes(program, unit, base);
    var own = base.own_hash();
    var path = record_path(cache, layer);
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

## Returns the record of `layer` under its key, its own interface and its
## warnings, rendered, when the cache has them.
##
## @param cache the build cache
## @param program the program
## @param layer the layer, its key set
## @returns the record's bytes, its own interface and its warnings
export find_checked(cache: Cache, program: link.Program, layer: Layer): (u8[], String, String)? {
    var path = record_path(cache, layer);
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

# The record of `unit`: the program's files' namespaces, then the unit, as
# a delta on `base`.
_record_bytes(program: link.Program, unit: sema.CheckedUnit, base: sema.DeltaBase): u8[] {
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
    unit.write(out, Optional<sema.DeltaBase>.Value(base));
    return out.finish();
}

# Reads the unit in record `bytes`, its slots mapped to the program's files
# by `slots`: a delta merged onto `base`, the module of the layers before.
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
    var unit = sema.CheckedUnit.read(input, base);
    if (!input.error.is_empty) {
        return Result<sema.CheckedUnit, String>.err(input.error);
    }
    if (!input.done()) {
        return Result<sema.CheckedUnit, String>.err("the record does not read whole");
    }
    return Result<sema.CheckedUnit, String>.ok(unit);
}
