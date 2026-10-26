## What a program exports to C, as `exports.collect_exports` finds it
## (`PassState.exports`), apart from the pass so that the passes' state
## need not import it.

import [Loc] from "loc";
import [TypeName] from "model";

## The C function that frees a `String` an export returned, exported when
## one does.
export const STRING_FREE = "pepper_string_free";

## Returns whether `ty` is `String`, which crosses as UTF-8 bytes.
##
## @param ty the type
## @returns true for `String`
export is_export_string(ty: TypeName): bool {
    return ty.name == "String" and ty.sub_types.count == 0;
}

## A free function C code can call.
export struct Export {
    ## The C symbol.
    var symbol: String;
    ## The function it calls, by its model name.
    var function: String;
    ## Each parameter's name and type.
    var parameters: Array<(String, TypeName)>;
    ## Where each parameter's type is written, in the order of `parameters`.
    var parameter_locs: Loc[] = Array<Loc>();
    ## The result type (`void` for none).
    var result: TypeName;
    ## Where the function is declared.
    var loc: Loc;

    ## Creates an export.
    ##
    ## @param symbol the C symbol
    ## @param function the function's model name
    ## @param parameters each parameter's name and type
    ## @param result the result type
    ## @param loc where the function is declared
    construct(symbol: String, function: String, parameters: Array<(String, TypeName)>, result: TypeName, loc: Loc) {
        this.symbol = symbol;
        this.function = function;
        this.parameters = parameters;
        this.result = result;
        this.loc = loc;
    }
}

## The struct handle functions C uses to keep a reference: `retain` adds
## one, `release` drops one.
export struct Handle {
    ## The struct, by its model name.
    var structure: String;
    ## Its C type name (the struct's declared name).
    var c_type: String;
    ## The C symbol of its retain function.
    var retain: String;
    ## The C symbol of its release function.
    var release: String;

    ## Creates a handle.
    ##
    ## @param structure the struct's model name
    ## @param c_type its C type name
    ## @param retain the retain function's symbol
    ## @param release the release function's symbol
    construct(structure: String, c_type: String, retain: String, release: String) {
        this.structure = structure;
        this.c_type = c_type;
        this.retain = retain;
        this.release = release;
    }
}

## What a program exports to C: its exported functions and the handle
## functions of every struct they pass, both in C symbol order.
export struct Exports {
    ## The exported functions.
    var functions: Export[] = Array<Export>();
    ## The handles.
    var handles: Handle[] = Array<Handle>();
    ## Some export returns a `String`, so `STRING_FREE` is exported too.
    var frees_strings: bool = false;

    ## Creates no exports.
    construct() {}

    ## Returns whether nothing is exported.
    ##
    ## @returns true when no function is
    is_empty(): bool {
        return functions.count == 0;
    }
}
