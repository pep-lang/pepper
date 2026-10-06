## Where a sema node came from: a byte span in one of the program's files,
## as `pepper_parser::diagnostic::Loc` is.

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

    ## Creates a location in file 0 at offset 0, as Rust's default.
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

    ## Returns the location as serde writes it: `[file, start, end]`.
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
