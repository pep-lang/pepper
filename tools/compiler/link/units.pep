## A program's compilation units, as `Program::units` and
## `Program::unit_inputs` in `crates/pepper-sema/src/program.rs` make them:
## the files compiled into one object, which the build cache keeps.

import [Declaration, Module] from compiler.ast;
import [Program] from "program";

## The name of the unit of the runtime's top-level files.
export const PRELUDE_UNIT = "prelude";

## A compilation unit: files compiled into one object.
export struct Unit {
    ## Its name, also its place in the build cache (`io/file`, `prelude`).
    var name: String;
    ## Its files, as indices into `Program.files`.
    var files: ulong[];

    construct(name: String, files: ulong[]) {
        this.name = name;
        this.files = files;
    }
}

## Returns the program's units, sorted by name: the runtime's top-level
## files (prelude files outside any module) form the unit `prelude`; every
## other file is in the unit of its import cycle (a strongly connected
## component of the import graph, where the files of one module, which see
## each other's declarations without an import, all reach each other),
## named after its first file's namespace. A unit's name depends only on
## its files' paths, so it is the same in every program.
##
## @param program the linked program
## @returns the units
export units(program: Program): Unit[] {
    var count = program.files.count;
    var prelude = Array<ulong>();
    for (var i in 0..count) {
        if (_in_prelude(program, i)) {
            prelude.append(i);
        }
    }
    var units = Array<Unit>();
    if (!prelude.is_empty) {
        units.append(Unit(PRELUDE_UNIT, prelude));
    }
    for (var files in _components(program)) {
        files.sort((a, b) => _compare(program.files[a].namespace, program.files[b].namespace));
        units.append(Unit(program.files[files[0]].namespace, files));
    }
    units.sort((a, b) => _compare(a.name, b.name));
    # A user file named like the prelude keeps its own unit.
    var taken = HashSet<String>();
    for (var unit in units) {
        var base = unit.name;
        uint k = 1;
        while (taken.contains(unit.name)) {
            k += 1;
            unit.name = $"{base}#{k}";
        }
        taken.insert(unit.name);
    }
    return units;
}

## Returns the files whose text a unit's code can depend on, in namespace
## order: its own files and every prelude file (visible everywhere), the
## files they import or take extensions from and the other files of their
## modules, transitively; and every file that declares a concrete override
## (`hash<int>`), since sema honours an override wherever its generic is
## instantiated. An override file counts by its own text: what it imports
## matters only to code that names its types, which imports them itself.
##
## @param program the linked program
## @param unit one of its units
## @returns the files, as indices into `Program.files`
export unit_inputs(program: Program, unit: Unit): ulong[] {
    var modules = _modules(program);
    var seen = Array<bool>();
    var stack = Array<ulong>();
    for (var i in 0..program.files.count) {
        seen.append(false);
        var file = program.files[i];
        if (file.prelude or file.prelude_part) {
            stack.append(i);
        }
    }
    stack.append_all(unit.files);
    while (!stack.is_empty) {
        var file = stack.pop();
        if (seen[file]) {
            continue;
        }
        seen[file] = true;
        for (var target in program.files[file].imports) {
            if (target.is_value()) {
                stack.append(target.value());
            }
        }
        var root = program.files[file].module_root;
        if (root.is_value()) {
            stack.append_all(modules[root.value().to_string()]);
        }
        if (file < program.scopes.count) {
            for (var extension in program.scopes[file].extensions) {
                stack.append(extension);
            }
        }
    }
    # By namespace, not index: the index follows the order this program
    # loaded the files in, which a key must not depend on.
    var inputs = Array<ulong>();
    for (var i in 0..seen.count) {
        if (seen[i] or declares_override(program.files[i].module)) {
            inputs.append(i);
        }
    }
    inputs.sort((a, b) => _compare(program.files[a].namespace, program.files[b].namespace));
    return inputs;
}

## Returns whether `module` declares a concrete override (`hash<Point>`): a
## function with a generic argument.
##
## @param module a file's syntax tree
## @returns true when it declares one
export declares_override(module: Module): bool {
    for (var declaration in module.declarations) {
        if (declaration is Function(function)) {
            for (var param in function.generic_params) {
                if (param.is_argument) {
                    return true;
                }
            }
        }
    }
    return false;
}

## Whether file `i` is in the prelude unit: a runtime file outside any
## module.
_in_prelude(program: Program, i: ulong): bool {
    var file = program.files[i];
    return file.prelude and !file.module_root.is_value();
}

## The files of each module, by the module's folder.
_modules(program: Program): HashMap<String, ulong[]> {
    var modules = HashMap<String, ulong[]>();
    for (var i in 0..program.files.count) {
        var root = program.files[i].module_root;
        if (!root.is_value()) {
            continue;
        }
        var key = root.value().to_string();
        if (!modules.contains(key)) {
            modules[key] = Array<ulong>();
        }
        modules[key].append(i);
    }
    return modules;
}

## Compares two strings by their bytes.
_compare(a: String, b: String): int {
    return a < b ? -1 : (a > b ? 1 : 0);
}

## The strongly connected components of the import graph over the files
## outside the prelude unit, by Tarjan's algorithm with an explicit stack
## (an import chain can be deep).
_components(program: Program): Array<ulong[]> {
    var count = program.files.count;
    var edges = Array<ulong[]>();
    for (var i in 0..count) {
        var targets = Array<ulong>();
        if (!_in_prelude(program, i)) {
            for (var target in program.files[i].imports) {
                if (target.is_value() and !_in_prelude(program, target.value())) {
                    targets.append(target.value());
                }
            }
        }
        edges.append(targets);
    }
    # A module's files in a ring, so each reaches every other.
    for (var (_, files) in _modules(program)) {
        for (var k in 0..files.count) {
            var file = files[k];
            if (!_in_prelude(program, file)) {
                edges[file].append(files[(k + 1) % files.count]);
            }
        }
    }
    var index = Array<long>();
    var low = Array<ulong>();
    var on_stack = Array<bool>();
    for (var _ in 0..count) {
        index.append(-1);
        low.append(0);
        on_stack.append(false);
    }
    var stack = Array<ulong>();
    var components = Array<ulong[]>();
    ulong next = 0;
    for (var start in 0..count) {
        if (_in_prelude(program, start) or index[start] >= 0) {
            continue;
        }
        # Each frame is (file, the next of its edges to follow).
        var frames = Array<(ulong, ulong)>();
        index[start] = next as long;
        low[start] = next;
        next += 1;
        stack.append(start);
        on_stack[start] = true;
        frames.append((start, 0));
        while (!frames.is_empty) {
            var (v, edge) = frames[frames.count - 1];
            if (edge < edges[v].count) {
                frames[frames.count - 1] = (v, edge + 1);
                var w = edges[v][edge];
                if (index[w] < 0) {
                    index[w] = next as long;
                    low[w] = next;
                    next += 1;
                    stack.append(w);
                    on_stack[w] = true;
                    frames.append((w, 0));
                } else if (on_stack[w] and (index[w] as ulong) < low[v]) {
                    low[v] = index[w] as ulong;
                }
                continue;
            }
            frames.pop();
            if (!frames.is_empty) {
                var (parent, _) = frames[frames.count - 1];
                if (low[v] < low[parent]) {
                    low[parent] = low[v];
                }
            }
            if (low[v] != index[v] as ulong) {
                continue;
            }
            var component = Array<ulong>();
            while (true) {
                var w = stack.pop();
                on_stack[w] = false;
                component.append(w);
                if (w == v) {
                    break;
                }
            }
            components.append(component);
        }
    }
    return components;
}
