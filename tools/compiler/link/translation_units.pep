## A program's translation units: each source file compiled into an object
## of its own, which the build cache keeps.

import [Declaration, Module] from compiler.ast;
import [Program] from "program";

## A translation unit: a source file compiled into an object of its own.
export struct TranslationUnit {
    ## Its name, also its place in the build cache (`io/file`, `prelude`).
    var name: String;
    ## Its files, as indices into `Program.files`: the one file.
    var files: ulong[];

    construct(name: String, files: ulong[]) {
        this.name = name;
        this.files = files;
    }
}

## Returns the program's translation units, sorted by name: each file is a
## unit of its own, named after its namespace, compiled into an object of
## its own as a C compiler compiles a translation unit (the instantiations
## it uses go in it too, as `linkonce_odr`: `codegen.prepare`). A unit's
## name depends only on its file's path, so it is the same in every
## program.
##
## @param program the linked program
## @returns the translation units
export translation_units(program: Program): TranslationUnit[] {
    var units = Array<TranslationUnit>();
    for (var i in 0..program.files.count) {
        units.append(TranslationUnit(program.files[i].namespace, [i]));
    }
    return _named(units);
}

# `units` sorted by name, each name made unique.
_named(units: TranslationUnit[]): TranslationUnit[] {
    units.sort((a, b) => _compare(a.name, b.name));
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

## Returns the files whose text a translation unit's code can depend on, in
## namespace order: its own files and every prelude file (visible everywhere),
## the files they import or take extensions from, transitively (a file sees
## another file of its module only through an import); and every file that
## declares a concrete override (`hash<int>`), since sema honours an override
## wherever its generic is instantiated. An override file counts by its own
## text: what it imports matters only to code that names its types, which
## imports them itself.
##
## @param program the linked program
## @param unit one of its translation units
## @returns the files, as indices into `Program.files`
export unit_inputs(program: Program, unit: TranslationUnit): ulong[] {
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

## Compares two strings by their bytes.
_compare(a: String, b: String): int {
    return a < b ? -1 : (a > b ? 1 : 0);
}
