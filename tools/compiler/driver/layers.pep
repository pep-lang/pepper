## Checked layers: sema checks a program one layer at a time, each on top of
## the layers before it, and the build cache keeps each layer's result (a
## checked unit's record, `sema.CheckedUnit`). A build loads the record of
## the longest run of unchanged layers and checks only the layers after it,
## so an edit costs the layers from the edited one on, not the program.
##
## The runtime is the first layer: its files depend on nothing else. Each
## other unit (`link.units`) is a layer of its own, in an order where a unit
## comes after every unit it reads; units that read each other (through
## extensions) share one.

import [Diagnostic] from compiler.diagnostic;
import digest;
import [Directory, File, Path] from io;
import compiler.link;
import process;
import compiler.sema;
import "cache";

## The record format's version: a new format gets a new folder.
const _RECORDS_FOLDER = "checked1";
## How many keys' records each layer keeps.
const _KEEP_RECORDS = 4;

## One layer: files checked together, on top of the layers before.
export struct Layer {
    ## Its name: `runtime`, or its first unit's.
    var name: String;
    ## Its files, as indices into `Program.files`.
    var files: ulong[] = Array<ulong>();
    ## Its key: the layers before it and its files' names and texts.
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
    # What each unit reads: the units of the files its files import, of
    # their modules' other files, and of the extensions they see.
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
            }
        }
        reads.append(read);
    }
    var order = _layer_order(reads, runtime_unit);
    var out = Array<Layer>();
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
        }
        out.append(layer);
    }
    String previous = base;
    for (var layer in out) {
        layer.files.sort((a, b) => _layer_compare(program.files[a].namespace, program.files[b].namespace));
        var hasher = digest.Blake3();
        hasher.update("pepper checked layer 1\n");
        hasher.update(previous);
        hasher.update($"\nlayer {layer.name}\n");
        for (var file in layer.files) {
            var f = program.files[file];
            hasher.update($"{f.name}\n{f.namespace}\n{f.prelude} {f.prelude_part}\n{f.source.size}\n");
            hasher.update(f.source);
        }
        layer.key = hasher.finish_hex();
        previous = layer.key;
    }
    return out;
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

## Loads the record of the last layer of `layers` whose record the cache
## has, and the program's files mapped to its slots.
##
## @param cache the build cache
## @param program the program
## @param layers the layers
## @returns how many layers it covers, and the checked unit; none when the
##   cache has none
export load_checked(cache: Cache, program: link.Program, layers: Layer[]): (ulong, sema.CheckedUnit)? {
    var slots = _record_slots(program);
    ulong n = layers.count;
    # The last layer is the program's own, checked on every build that
    # gets this far; a record covering it would mean nothing changed.
    while (n > 1) {
        n -= 1;
        var path = record_path(cache, layers[n - 1]);
        var bytes = File.read_bytes(path);
        if (bytes.is_err()) {
            continue;
        }
        var input = sema.RecordIn(bytes.value());
        var count = input.count();
        for (var _ in 0..count) {
            var file = slots.try_get(input.text());
            input.files.append(file.is_value() ? file.value() : sema.NO_FILE);
        }
        var unit = sema.CheckedUnit.read(input);
        if (!input.done()) {
            continue;
        }
        return Optional<(ulong, sema.CheckedUnit)>.Value((n, unit));
    }
    return Optional<(ulong, sema.CheckedUnit)>.Empty;
}

## Stores `unit`, the record of the layers up to `layer`.
##
## @param cache the build cache
## @param program the program
## @param layer the last layer it covers
## @param unit the checked unit
export store_checked(cache: Cache, program: link.Program, layer: Layer, unit: sema.CheckedUnit) {
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
    unit.write(out);
    var path = record_path(cache, layer);
    var folder = path.parent().value();
    if (Directory.create_all(folder).is_err()) {
        return;
    }
    var partial = Path($"{path}.{process.id()}");
    if (File.write_bytes(partial, out.finish()).is_err() or File.rename(partial, path).is_err()) {
        File.remove(partial);
        return;
    }
    _prune_records(folder);
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
        File.remove(folder.join(Path(name)));
    }
}
