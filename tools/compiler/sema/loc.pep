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

## The declarations of the files a record's compilation unit reads, by
## name and where each starts (`anchors_of`): a record writes a location in
## one of those files from the declaration at or before it, and reading it
## puts it where that declaration is now. So a reader's record keeps its
## copies of their code (a specialization, a member synthesized at a
## struct) right when an edit moves them but leaves the reader's key.
export struct LocAnchors {
    # By file: the declarations' starts, ascending, and their names.
    var _starts: HashMap<uint, ulong[]> = HashMap<uint, ulong[]>();
    var _names: HashMap<uint, String[]> = HashMap<uint, String[]>();
    # Each name's file and start; a name declared twice is in neither.
    var _at: HashMap<String, (uint, ulong)> = HashMap<String, (uint, ulong)>();
    var _twice: HashSet<String> = HashSet<String>();
    var _sorted: bool = false;

    construct() {}

    ## Adds the declaration `name`, at `loc`.
    ##
    ## @param name the declaration's name
    ## @param loc where it is
    add(name: String, loc: Loc) {
        if (loc.is_none() or _twice.contains(name)) {
            return;
        }
        if (_at.contains(name)) {
            _at.remove(name);
            _twice.insert(name);
            return;
        }
        _at[name] = (loc.file, loc.span.start);
        _sorted = false;
    }

    ## Returns the declaration at or before `offset` in file `file`: its name
    ## and start.
    ##
    ## @param file the file
    ## @param offset the offset
    ## @returns the name and start, or none before the first declaration
    find(file: uint, offset: ulong): (String, ulong)? {
        _sort();
        var starts = _starts.try_get(file);
        if (!starts.is_value() or starts.value().is_empty or offset < starts.value()[0]) {
            return Optional<(String, ulong)>.Empty;
        }
        var all = starts.value();
        ulong low = 0;
        ulong high = all.count;
        while (high - low > 1) {
            var middle = (low + high) / 2;
            if (all[middle] <= offset) {
                low = middle;
            } else {
                high = middle;
            }
        }
        return Optional<(String, ulong)>.Value((_names[file][low], all[low]));
    }

    ## Sets where each declaration of `name` starts: it is found when it is
    ## declared once, as `add` leaves it.
    ##
    ## @param name the declaration's name
    ## @param places each declaration's file and start
    set_places(name: String, places: Array<(uint, ulong)>) {
        _at.remove(name);
        _twice.remove(name);
        if (places.count == 1) {
            _at[name] = places[0];
        } else if (places.count > 1) {
            _twice.insert(name);
        }
        _sorted = false;
    }

    ## Returns where declaration `name` starts in file `file`.
    ##
    ## @param name the declaration's name
    ## @param file the file
    ## @returns its start, or none when no one declaration of it is there
    start(name: String, file: uint): ulong? {
        var at = _at.try_get(name);
        if (!at.is_value()) {
            return Optional<ulong>.Empty;
        }
        var (in_file, start) = at.value();
        return in_file == file ? Optional<ulong>.Value(start) : Optional<ulong>.Empty;
    }

    # Sorts each file's declarations by start, once all are added.
    _sort() {
        if (_sorted) {
            return;
        }
        _sorted = true;
        var by_file = HashMap<uint, Array<(ulong, String)>>();
        for (var (name, (file, start)) in _at) {
            if (!by_file.contains(file)) {
                by_file[file] = Array<(ulong, String)>();
            }
            by_file[file].append((start, name));
        }
        _starts = HashMap<uint, ulong[]>();
        _names = HashMap<uint, String[]>();
        for (var (file, entries) in by_file) {
            entries.sort((a, b) => {
                var (x, m) = a;
                var (y, n) = b;
                return x < y ? -1 : (x > y ? 1 : m.compare(n));
            });
            var starts = Array<ulong>();
            var names = Array<String>();
            for (var (start, name) in entries) {
                starts.append(start);
                names.append(name);
            }
            _starts[file] = starts;
            _names[file] = names;
        }
    }
}
