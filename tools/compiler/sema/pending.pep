## What the model holds in memory only (fields `model.pep` declares with a
## default): never fingerprinted, written as JSON or recorded.

import [LocAnchors, LocShift] from "loc";
import [FunctionDef, StructDef, TypeName] from "model";

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
    ## Where the record's locations are now (`RecordIn.shift`).
    var shift: LocShift? = Optional<LocShift>.Empty;
    ## The declarations its locations are put back from (`RecordIn.anchors`).
    var anchors: LocAnchors? = Optional<LocAnchors>.Empty;

    construct(data: u8[], strings: String[], files: uint[], start: ulong, end: ulong) {
        this.data = data;
        this.strings = strings;
        this.files = files;
        this.start = start;
        this.end = end;
    }
}

## A compilation unit's checked declarations by name (`checked.checked_decls`),
## for the tables the passes build again each round: they look up the few the
## compilation unit's code names here rather than take in every checked one each
## time. Built once per compilation unit; a struct the compilation unit extends
## since is the compilation unit's own (`UnitDecls`), which a table finds first.
export struct CheckedDecls {
    ## The checked free functions that are not generic, and the generic
    ## ones, by name: the last of a name, as the tables kept them.
    var functions: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    var generic_functions: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    ## The constructors of the checked structs that are not generic, by the
    ## name a call gives them.
    var constructors: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    ## The checked structs, by type (`Box<int>`; a generic base as `Box<T>`).
    var structs: HashMap<String, StructDef> = HashMap<String, StructDef>();
    ## The checked globals' types, by name.
    var globals: HashMap<String, TypeName> = HashMap<String, TypeName>();

    construct() {}
}

## The declarations a compilation unit adds: its structs and functions, the
## checked ones left out but for the structs an extension of the compilation
## unit changed. A pass that only checks or rewrites declarations walks these;
## one that looks a name up still searches the whole module.
export struct UnitDecls {
    var structs: Array<StructDef> = Array<StructDef>();
    var functions: Array<FunctionDef> = Array<FunctionDef>();
    # What they were found from: the module's lists, their sizes, and how
    # many checked structs the compilation unit had extended.
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
