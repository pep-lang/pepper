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
