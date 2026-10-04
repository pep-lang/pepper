## What the passes keep between steps besides the model: the first error
## a pass reported, the closure numbering, and the facts some passes
## install for the later ones, as the Rust passes keep them in
## thread-locals.

import [Diagnostic] from compiler.diagnostic;
import [Target] from compiler.link;
import [EnumDef] from "model";
import [is_integral_name] from "type_name";

## The passes' state for one program.
export struct PassState {
    ## The compile target.
    var target: Target;
    ## The first error reported since the last `take_error`.
    var error: Diagnostic? = Optional<Diagnostic>.Empty;
    ## The program's file namespaces, by file, for naming closures.
    var namespaces: String[] = Array<String>();
    ## How many closures each file has (by file index; `-1` for code in no
    ## file).
    var closure_counts: HashMap<long, ulong> = HashMap<long, ulong>();
    ## Each enum's representation and default value, by name.
    var enum_representations: HashMap<String, (String, long)> = HashMap<String, (String, long)>();
    ## The value structs' names (`[Value]`), as `value_structs::install`
    ## records them.
    var value_structs: HashSet<String> = HashSet<String>();

    ## Creates the state for compiling for `target`.
    ##
    ## @param target the compile target
    construct(target: Target) {
        this.target = target;
    }

    ## Records an error. Only the first is kept: later ones are usually
    ## fallout from it.
    ##
    ## @param diagnostic the error
    report(diagnostic: Diagnostic) {
        if (!error.is_value()) {
            error = Optional<Diagnostic>.Value(diagnostic);
        }
    }

    ## Returns the error reported since the last call, clearing it.
    ##
    ## @returns the error, if any
    take_error(): Diagnostic? {
        var out = error;
        error = Optional<Diagnostic>.Empty;
        return out;
    }

    ## Records each enum's representation and default value, as
    ## `enums::install` does: enum names are integer types from here on.
    ##
    ## @param enums the program's enums
    install_enums(enums: EnumDef[]) {
        enum_representations.clear();
        for (var e in enums) {
            enum_representations[e.name] = (e.representation.name, _default_value(e));
        }
    }

    ## Returns the default value of the enum named `name`, or none when it
    ## names no enum.
    ##
    ## @param name the type's name
    ## @returns the value
    enum_default(name: String): long? {
        var found = enum_representations.try_get(name);
        if (!found.is_value()) {
            return Optional<long>.Empty;
        }
        var (_, value) = found.value();
        return Optional<long>.Value(value);
    }

    ## Returns whether the type spelled `name` is a value struct.
    ##
    ## @param name the type's spelling
    ## @returns true for a `[Value]` struct
    is_value_struct(name: String): bool {
        if (name.ends_with("*")) {
            return false;
        }
        var open = name.find("<");
        var base = open < 0 ? name : name.substr_bytes(0, open as ulong);
        return value_structs.contains(base);
    }

    ## Returns whether `name` is a primitive type or an enum.
    ##
    ## @param name the type's name
    ## @returns true for an integral type
    is_integral(name: String): bool {
        return is_integral_name(name) or enum_representations.contains(name);
    }
}

## The value of a slot nothing was stored in yet: the case whose value is
## 0, else the first case (0 for an enum with no cases).
_default_value(e: EnumDef): long {
    for (var c in e.cases) {
        if (c.value == 0) {
            return 0;
        }
    }
    return e.cases.count > 0 ? e.cases[0].value : 0;
}
