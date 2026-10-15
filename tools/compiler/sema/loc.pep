## Where a sema node came from: a byte span in one of the program's files.

import compiler.ast;
import json;
import [JsonValue] from json;
import [Fingerprint] from "fingerprint";

## The file index of `Loc.none()`.
export const NO_FILE: uint = 4294967295;

## A byte span in one of the program's files.
export struct Loc {
    ## The file, as an index into the program's files.
    var file: uint;
    ## The bytes.
    var span: ast.Span = ast.Span();

    ## Creates a location in file 0 at offset 0.
    construct() {}

    ## Creates a location.
    ##
    ## @param file the file
    ## @param span the bytes
    static at(file: uint, span: ast.Span): Loc {
        var out = Loc();
        out.file = file;
        out.span = span;
        return out;
    }

    ## Returns no location: what the compiler synthesizes rather than parses.
    ##
    ## @returns the location
    static none(): Loc {
        var out = Loc();
        out.file = NO_FILE;
        return out;
    }

    ## Adds this to `into`: equal locations add the same.
    ##
    ## @param into the fingerprint
    fingerprint(into: Fingerprint) {
        into.add(file);
        into.add(span.start);
        into.add(span.end);
    }

    ## Returns whether this is `none()`.
    ##
    ## @returns true for no location
    is_none(): bool {
        return file == NO_FILE;
    }

    ## Returns whether `other` is the same place.
    ##
    ## @param other the other location
    ## @returns true when equal
    same(other: Loc): bool {
        return file == other.file and span.start == other.span.start and span.end == other.span.end;
    }

    ## Returns whether `other` is the same place.
    ##
    ## @param other the other location
    ## @returns true when equal
    ==(other: Loc): bool {
        return same(other);
    }

    ## Returns the location as JSON: `[file, start, end]`.
    ##
    ## @returns the JSON value
    to_json(): JsonValue {
        var out = JsonValue.array();
        out.append(JsonValue.Integer(file as long));
        out.append(JsonValue.Integer(span.start as long));
        out.append(JsonValue.Integer(span.end as long));
        return out;
    }
}

## Returns the hash of `value`, for sets and maps of locations.
##
## @param value the location
## @returns the hash
export hash<Loc>(value: Loc): u64 {
    return hash<ulong>(((value.file as ulong) << 40) ^ (value.span.start << 20) ^ value.span.end);
}

## Where the locations of a record written before an edit are in the files
## as edited (`RecordIn.shift`): an edit that changed only some bodies
## (and comments or spacing) keeps every other token, so each old offset
## moves with the token at or before it. An offset inside a changed body
## goes to that body's new start: what it located went with the old body.
export struct LocShift {
    # By file: its kept tokens' old offsets, ascending, and their new ones.
    var _old: HashMap<uint, ulong[]> = HashMap<uint, ulong[]>();
    var _new: HashMap<uint, ulong[]> = HashMap<uint, ulong[]>();
    # By file: the changed bodies' old spans, and each one's new start.
    var _changed: HashMap<uint, Array<(ast.Span, ulong)>> = HashMap<uint, Array<(ast.Span, ulong)>>();

    construct() {}

    ## Maps file `file`'s kept tokens: `before[i]` is now `after[i]`.
    ##
    ## @param file the file
    ## @param before the old offsets, ascending
    ## @param after the new offsets
    ## @param changed the changed bodies' old spans and new starts
    add_file(file: uint, before: ulong[], after: ulong[], changed: Array<(ast.Span, ulong)>) {
        _old[file] = before;
        _new[file] = after;
        _changed[file] = changed;
    }

    ## Returns where `loc` is now.
    ##
    ## @param loc a location in the old files
    ## @returns the location in the edited ones
    map(loc: Loc): Loc {
        if (loc.is_none() or !_old.contains(loc.file)) {
            return loc;
        }
        return Loc.at(loc.file, ast.Span(_offset(loc.file, loc.span.start), _offset(loc.file, loc.span.end)));
    }

    _offset(file: uint, offset: ulong): ulong {
        for (var (span, start) in _changed[file]) {
            if (offset >= span.start and offset < span.end) {
                return start;
            }
        }
        var old = _old[file];
        if (old.is_empty or offset < old[0]) {
            return offset;
        }
        # The last kept token at or before `offset`.
        ulong low = 0;
        ulong high = old.count;
        while (high - low > 1) {
            var middle = (low + high) / 2;
            if (old[middle] <= offset) {
                low = middle;
            } else {
                high = middle;
            }
        }
        return _new[file][low] + (offset - old[low]);
    }
}
