## What the model holds in memory only (fields `model.pep` declares with a
## default): never fingerprinted, written as JSON or recorded.

import [FunctionDef, StructDef] from "model";

## A function body a checked unit's record holds that reading it skipped:
## where in the record it is, decoded only when a pass, codegen or a write
## needs it (`record.decode_body`). Most of a checked unit's bodies are
## needed by neither: their units' objects come from the build cache.

## Where a skipped body is in its record.
export struct PendingBody {
    ## The record's values.
    var data: u8[];
    ## The record's strings, in their order.
    var strings: String[];
    ## For each slot in the record, the program file it is now.
    var files: uint[];
    ## Where the body's values start, and end.
    var start: ulong;
    var end: ulong;

    construct(data: u8[], strings: String[], files: uint[], start: ulong, end: ulong) {
        this.data = data;
        this.strings = strings;
        this.files = files;
        this.start = start;
        this.end = end;
    }
}

## The declarations a layer adds: its structs and functions, the checked
## ones left out but for the structs an extension of the layer changed.
## A pass that only checks or rewrites declarations walks these; one that
## looks a name up still searches the whole module.
export struct LayerDecls {
    var structs: Array<StructDef> = Array<StructDef>();
    var functions: Array<FunctionDef> = Array<FunctionDef>();
    # What they were found from: the module's lists, their sizes, and how
    # many checked structs the layer had extended.
    var _structs_of: Array<StructDef>;
    var _functions_of: Array<FunctionDef>;
    var _counts: (ulong, ulong, ulong);

    construct(structs_of: Array<StructDef>, functions_of: Array<FunctionDef>, counts: (ulong, ulong, ulong)) {
        _structs_of = structs_of;
        _functions_of = functions_of;
        _counts = counts;
    }

    ## Whether these were found from `structs` and `functions` as they are.
    fits(structs: Array<StructDef>, functions: Array<FunctionDef>, extended: ulong): bool {
        return _structs_of === structs
            and _functions_of === functions
            and _counts == (structs.count, functions.count, extended);
    }
}
