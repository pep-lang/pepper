## The bytes of a checked unit's record, as `record_codec.pep` writes and
## reads them: numbers as LEB128 varints, each distinct string once.
##
## A record is a header (`MAGIC`), the number of strings and each one's size
## in bytes, the size of the values, the values, then the strings' UTF-8
## text one after another. A value refers to a string by its place in that
## list. A location's file is written as its slot in `RecordOut.files`, so a
## record loads into a program whose files sit in other places.

import compiler.ast;
import digest;
import [Utf8] from text;
import [Loc, NO_FILE] from "loc";
import [Checked] from "model";
import [PendingBody] from "pending";

## What every record starts with: the format's name and version.
export const MAGIC = "pepper record 2\n";

## A record being written.
export struct RecordOut {
    ## The values written so far.
    var values: u8[] = Array<u8>();
    ## For each program file a location may name, its slot in the record,
    ## from 0. Empty: every file is its own slot.
    var files: HashMap<uint, uint> = HashMap<uint, uint>();
    ## For an interface: write no body of a function that is not generic
    ## (as none) outside the templates.
    var blank_bodies: bool = false;
    ## For an interface: write every location as the same, so moving code
    ## around in a file does not change it.
    var blank_locs: bool = false;
    # Each string's place in the list, by its text.
    var _places: HashMap<String, ulong> = HashMap<String, ulong>();
    # The strings' sizes, in their order.
    var _sizes: ulong[] = Array<ulong>();
    # The strings' text, in their order.
    var _text: StringBuilder = StringBuilder();

    construct() {}

    ## Leaves room for a size, filled in by `size_fill` with how many bytes
    ## were written after it.
    ##
    ## @returns where the size goes
    size_mark(): ulong {
        var at = values.count;
        for (var _ in 0..4) {
            values.append(0);
        }
        return at;
    }

    ## Fills in the size `size_mark` left room for at `at`.
    ##
    ## @param at what `size_mark` returned
    size_fill(at: ulong) {
        var size = values.count - at - 4;
        for (var i in 0..4) {
            values[at + i] = ((size >> (8 * i as ulong)) & 0xFF) as u8;
        }
    }

    ## Writes an unsigned number.
    ##
    ## @param value the number
    unsigned(value: ulong) {
        var rest = value;
        while (rest >= 0x80) {
            values.append((rest & 0x7F | 0x80) as u8);
            rest = rest >> 7;
        }
        values.append(rest as u8);
    }

    ## Writes a signed number.
    ##
    ## @param value the number
    signed(value: long) {
        unsigned(((value << 1) ^ (value >> 63)) as ulong);
    }

    ## Writes a boolean.
    ##
    ## @param value the boolean
    flag(value: bool) {
        values.append(value ? 1 : 0);
    }

    ## Writes a floating-point number, by its bits.
    ##
    ## @param value the number
    number(value: double) {
        unsigned(unsafe_cast<ulong>(value));
    }

    ## Writes a string: its place in the list, which it joins when new.
    ##
    ## @param value the string
    text(value: String) {
        var place = _places.try_get(value);
        if (place.is_value()) {
            unsigned(place.value());
            return;
        }
        var next = _sizes.count;
        _places[value] = next;
        _sizes.append(value.size);
        _text.append(value);
        unsigned(next);
    }

    ## Writes a location: its file's slot (0 for none, else the slot plus
    ## one) and its bytes.
    ##
    ## @param value the location
    loc(value: Loc) {
        if (blank_locs) {
            unsigned(0);
            return;
        }
        if (value.file == NO_FILE) {
            unsigned(0);
        } else if (files.is_empty) {
            unsigned(value.file as ulong + 1);
        } else {
            unsigned(files[value.file] as ulong + 1);
        }
        unsigned(value.span.start);
        unsigned(value.span.end);
    }

    ## Returns an empty record whose locations name the same file slots, to
    ## write one value into alone.
    ##
    ## @returns the record
    scratch(): RecordOut {
        var out = RecordOut();
        out.files = files;
        out.blank_bodies = blank_bodies;
        out.blank_locs = blank_locs;
        return out;
    }

    ## Returns the whole record.
    ##
    ## @returns the bytes
    finish(): u8[] {
        var head = RecordOut();
        for (var byte in MAGIC.bytes()) {
            head.values.append(byte);
        }
        head.unsigned(_sizes.count);
        for (var size in _sizes) {
            head.unsigned(size);
        }
        head.unsigned(values.count);
        var out = head.values;
        out.append_all(values);
        out.append_all(_text.to_string().bytes());
        return out;
    }
}

## A record being read.
## Returns the hash of what was written to `out`, as hex.
##
## @param out the record
## @returns the hash
export interface_text(out: RecordOut): String {
    var hasher = digest.Blake3();
    hasher.update(out.finish());
    return hasher.finish_hex();
}

## Returns a link summary's text without the place its error would point
## at (`classes;taint;start-end`, the first line's third part), for an
## interface.
##
## @param text the summary
## @returns the summary, its place left out
export summary_without_place(text: String): String {
    var line_end = text.find("\n");
    var first = line_end >= 0 ? text.substr(0, line_end as ulong) : text;
    var rest = line_end >= 0 ? text.substr(line_end as ulong, text.size) : "";
    var parts = first.split(";");
    if (parts.count < 3) {
        return text;
    }
    parts[2] = "-";
    return ";".join(parts) + rest;
}

## Writes link summaries by location to an interface: their texts without
## places, sorted, the locations left out.
##
## @param out the record, writing an interface
## @param summaries the summaries
export write_interface_summaries(out: RecordOut, summaries: HashMap<Loc, String>) {
    var texts = Array<String>();
    for (var (_, text) in summaries) {
        texts.append(summary_without_place(text));
    }
    texts.sort((a, b) => a.compare(b));
    out.unsigned(texts.count);
    for (var text in texts) {
        out.text(text);
    }
}

## Writes link summaries by key to an interface: by key, their texts
## without places, the locations left out.
##
## @param out the record, writing an interface
## @param summaries the summaries
export write_interface_checked_summaries(out: RecordOut, summaries: HashMap<String, (Loc, String)>) {
    var keys = Array<String>();
    for (var (key, _) in summaries) {
        keys.append(key);
    }
    keys.sort((a, b) => a.compare(b));
    out.unsigned(keys.count);
    for (var key in keys) {
        var (_, text) = summaries[key];
        out.text(key);
        out.text(summary_without_place(text));
    }
}

## Compares two byte strings, byte by byte, the shorter first on a tie.
##
## @param a the first
## @param b the second
## @returns a negative number, zero or a positive number as `a` sorts before, with or after `b`
export compare_bytes(a: u8[], b: u8[]): int {
    var n = a.count < b.count ? a.count : b.count;
    for (var i in 0..n) {
        if (a[i] != b[i]) {
            return a[i] < b[i] ? -1 : 1;
        }
    }
    if (a.count == b.count) {
        return 0;
    }
    return a.count < b.count ? -1 : 1;
}

## Returns `base` and `added` in one list, sorted by place (file, then
## start) without repeats, as `argument_names` keeps it.
##
## @param base a sorted list
## @param added the elements to merge in
## @returns the merged list
export merge_by_place(base: Array<(Loc, String)>, added: Array<(Loc, String)>): Array<(Loc, String)> {
    var all = Array<(Loc, String)>();
    all.append_all(base);
    all.append_all(added);
    all.sort((a: (Loc, String), b: (Loc, String)) => {
        var (x, _) = a;
        var (y, _) = b;
        if (x.file != y.file) {
            return x.file < y.file ? -1 : 1;
        }
        return x.span.start < y.span.start ? -1 : (x.span.start > y.span.start ? 1 : 0);
    });
    var kept = Array<(Loc, String)>();
    for (var (at, name) in all) {
        if (kept.count > 0) {
            var (last_at, last_name) = kept[kept.count - 1];
            if (last_at == at and last_name == name) {
                continue;
            }
        }
        kept.append((at, name));
    }
    return kept;
}

## The index a delta record is written on (`write_module_delta`): each list
## element of the base module, by its field and the hash of its own record,
## at its place in that field.
export struct DeltaBase {
    ## The file slots of the record the delta goes into, which each element
    ## is written with.
    var files: HashMap<uint, uint> = HashMap<uint, uint>();
    ## With `PEPC_RECORD_STATS` set, the bytes each field of the module took
    ## in the last delta written on this base, by field.
    var stats: HashMap<String, ulong> = HashMap<String, ulong>();
    # The hashes of the base's lists kept whole and of its map entries.
    var _hashes: HashMap<String, String> = HashMap<String, String>();
    # How many different elements each of the base's lists holds.
    var _distinct: HashMap<String, ulong> = HashMap<String, ulong>();
    # How many elements each of the base's lists holds.
    var _sizes: HashMap<String, ulong> = HashMap<String, ulong>();
    # Each element's place, by "field:hash" of its record.
    var _places: HashMap<String, ulong> = HashMap<String, ulong>();
    # Each list's elements' hashes, and its structs' names, in order.
    var _sequences: HashMap<String, Array<String>> = HashMap<String, Array<String>>();
    # The base's checked names: structs, functions and globals, as indexed.
    var _checked: Array<HashSet<String>> = Array<HashSet<String>>();
    # The base's checked summaries, as indexed.
    var _summaries: HashMap<String, (Loc, String)> = HashMap<String, (Loc, String)>();

    construct() {}

    ## Keeps copies of the names `checked`, the base's, marks checked, for
    ## `write_checked`.
    ##
    ## @param checked the base's checked declarations
    keep_checked(checked: Checked) {
        _checked = Array<HashSet<String>>();
        for (var names in [checked.structs, checked.functions, checked.globals]) {
            var kept = HashSet<String>();
            for (var name in names) {
                kept.insert(name);
            }
            _checked.append(kept);
        }
        _summaries = HashMap<String, (Loc, String)>();
        for (var (key, value) in checked.summaries) {
            _summaries[key] = value;
        }
    }

    ## Writes `checked` as a delta on the base's: each name set as the names
    ## it lost and gained, sorted; the rest in full.
    ##
    ## @param out the record
    ## @param checked the checked declarations
    write_checked(out: RecordOut, checked: Checked) {
        var sets = [checked.structs, checked.functions, checked.globals];
        for (var i in 0..3) {
            var had = i < _checked.count ? _checked[i] : HashSet<String>();
            var lost = Array<String>();
            for (var name in had) {
                if (!sets[i].contains(name)) {
                    lost.append(name);
                }
            }
            var gained = Array<String>();
            for (var name in sets[i]) {
                if (!had.contains(name)) {
                    gained.append(name);
                }
            }
            for (var names in [lost, gained]) {
                names.sort((a, b) => a.compare(b));
                out.unsigned(names.count);
                for (var name in names) {
                    out.text(name);
                }
            }
        }
        out.unsigned(checked.extensions);
        # The summaries: the keys the base's lost, then the entries new or
        # changed since, by key.
        var lost = Array<String>();
        for (var (key, _) in _summaries) {
            if (!checked.summaries.contains(key)) {
                lost.append(key);
            }
        }
        lost.sort((a, b) => a.compare(b));
        out.unsigned(lost.count);
        for (var key in lost) {
            out.text(key);
        }
        var changed = Array<String>();
        for (var (key, (loc, text)) in checked.summaries) {
            var had = _summaries.try_get(key);
            if (had.is_value()) {
                var (had_loc, had_text) = had.value();
                if (had_loc == loc and had_text == text) {
                    continue;
                }
            }
            changed.append(key);
        }
        changed.sort((a, b) => a.compare(b));
        out.unsigned(changed.count);
        for (var key in changed) {
            var (loc, text) = checked.summaries[key];
            out.text(key);
            out.loc(loc);
            out.text(text);
        }
    }

    ## Reads what `write_checked` wrote on `base`, the base's checked
    ## declarations, which it leaves as they are.
    ##
    ## @param input the record
    ## @param base the base's checked declarations
    ## @returns the checked declarations
    static read_checked(input: RecordIn, base: Checked): Checked {
        var sets = Array<HashSet<String>>();
        for (var had in [base.structs, base.functions, base.globals]) {
            var names = HashSet<String>();
            for (var name in had) {
                names.insert(name);
            }
            var lost = input.count();
            for (var _ in 0..lost) {
                names.remove(input.text());
            }
            var gained = input.count();
            for (var _ in 0..gained) {
                names.insert(input.text());
            }
            sets.append(names);
        }
        var extensions = input.unsigned();
        var summaries = HashMap<String, (Loc, String)>();
        for (var (key, value) in base.summaries) {
            summaries[key] = value;
        }
        var lost = input.count();
        for (var _ in 0..lost) {
            summaries.remove(input.text());
        }
        var count = input.count();
        for (var _ in 0..count) {
            var key = input.text();
            var loc = input.loc();
            summaries[key] = (loc, input.text());
        }
        return Checked(sets[0], sets[1], sets[2], extensions, summaries);
    }

    ## Adds `bytes` to the bytes counted under `what`, and one to its count
    ## (`PEPC_RECORD_STATS`).
    ##
    ## @param what what was written
    ## @param bytes its size in the record
    count(what: String, bytes: ulong) {
        var had = stats.try_get(what + " bytes");
        stats[what + " bytes"] = (had.is_value() ? had.value() : 0) + bytes;
        var many = stats.try_get(what + " count");
        stats[what + " count"] = (many.is_value() ? many.value() : 0) + 1;
    }

    ## Notes how many different elements of the base's list `list` a delta
    ## did not refer to, of the `hit` it did: elements it rewrote or dropped,
    ## under `category` (`PEPC_RECORD_STATS`).
    ##
    ## @param category what the count is added to
    ## @param list the base's list
    ## @param hit how many of its elements the delta referred to
    missed(category: String, list: String, hit: ulong) {
        var size = _distinct.try_get(list);
        if (!size.is_value() or size.value() <= hit) {
            return;
        }
        var had = stats.try_get(category + " missed count");
        stats[category + " missed count"] = (had.is_value() ? had.value() : 0) + size.value() - hit;
    }

    ## Notes that field `field` took `bytes` bytes of the delta.
    ##
    ## @param field the field's name
    ## @param bytes its size in the record
    stat(field: String, bytes: ulong) {
        stats[field] = bytes;
    }

    ## Returns an empty record to write one element into.
    ##
    ## @returns the record
    scratch(): RecordOut {
        var out = RecordOut();
        out.files = files;
        return out;
    }

    ## Indexes the element written to `scratch` as the `index`th of the
    ## base's list `list`; an element already indexed keeps its first
    ## place.
    ##
    ## @param list the list: a field of `Module`, or a member list of a struct
    ## @param scratch the element, written alone
    ## @param index its place in the list
    add(list: String, scratch: RecordOut, index: ulong) {
        add_hashed(list, _hash(scratch), index);
    }

    ## Returns the place of the element of the base's list `list` whose
    ## record is the one written to `scratch`, or -1 when it has none.
    ##
    ## @param list the list
    ## @param scratch the element, written alone
    ## @returns its place in the base's list, or -1
    find(list: String, scratch: RecordOut): long {
        var at = _places.try_get(_key(list, scratch));
        return at.is_value() ? at.value() as long : -1;
    }

    ## Returns how many elements, or entries, the base's list or map `list`
    ## holds.
    ##
    ## @param list the list or map
    ## @returns its size; 0 when the base has none
    size(list: String): ulong {
        var had = _sizes.try_get(list);
        return had.is_value() ? had.value() : 0;
    }

    ## Keeps the size of the base's list `list` and the hash of its
    ## elements, written one after another to `scratch`.
    ##
    ## @param list the list
    ## @param count how many elements it holds
    ## @param scratch its elements, written
    keep_list(list: String, count: ulong, scratch: RecordOut) {
        _sizes[list] = count;
        _hashes[list] = _hash(scratch);
    }

    ## Returns whether the elements written to `scratch` are the base's
    ## list `list`, as `keep_list` kept it.
    ##
    ## @param list the list
    ## @param scratch elements, written one after another
    ## @returns true when they are the same
    same_list(list: String, scratch: RecordOut): bool {
        var had = _hashes.try_get(list);
        return had.is_value() and had.value() == _hash(scratch);
    }

    ## Indexes an entry of the base's set or map `map`: its key written to
    ## `key`, its value to `value` (empty for a set).
    ##
    ## @param map the set or map
    ## @param key the key, written alone
    ## @param value the value, written alone
    keep_entry(map: String, key: RecordOut, value: RecordOut) {
        var had = _sizes.try_get(map);
        _sizes[map] = (had.is_value() ? had.value() : 0) + 1;
        _hashes[$"{map}:{_hash(key)}"] = _hash(value);
    }

    ## Returns whether the base's set or map `map` has the entry: -1 when
    ## it has no such key, 0 when the key has another value, 1 when it has
    ## the same entry.
    ##
    ## @param map the set or map
    ## @param key the key, written alone
    ## @param value the value, written alone
    ## @returns -1, 0 or 1
    entry(map: String, key: RecordOut, value: RecordOut): int {
        var had = _hashes.try_get($"{map}:{_hash(key)}");
        if (!had.is_value()) {
            return -1;
        }
        return had.value() == _hash(value) ? 1 : 0;
    }

    ## Returns the hash of the element written to `scratch`, for
    ## `find_hashed` and `add_hashed`.
    ##
    ## @param scratch the element, written alone
    ## @returns its hash
    hash_of(scratch: RecordOut): String {
        return _hash(scratch);
    }

    ## `find`, with the element's `hash_of`.
    ##
    ## @param list the list
    ## @param hash the element's hash
    ## @returns its place in the base's list, or -1
    find_hashed(list: String, hash: String): long {
        var at = _places.try_get($"{list}:{hash}");
        return at.is_value() ? at.value() as long : -1;
    }

    ## `add`, with the element's `hash_of`.
    ##
    ## @param list the list
    ## @param hash the element's hash
    ## @param index its place in the list
    add_hashed(list: String, hash: String, index: ulong) {
        var had = _sizes.try_get(list);
        if (!had.is_value() or had.value() < index + 1) {
            _sizes[list] = index + 1;
        }
        _in_order(list, hash, index);
        var key = $"{list}:{hash}";
        if (!_places.contains(key)) {
            _places[key] = index;
            var distinct = _distinct.try_get(list);
            _distinct[list] = (distinct.is_value() ? distinct.value() : 0) + 1;
        }
    }

    # The hash of what was written to `scratch`.
    _hash(scratch: RecordOut): String {
        var hasher = digest.Blake3();
        hasher.update(scratch.finish());
        return hasher.finish_hex();
    }

    ## Indexes the struct named `name` as the `index`th of the base's list
    ## `list`; a name already indexed keeps its first place.
    ##
    ## @param list the list of structs
    ## @param name the struct's name
    ## @param index its place in the list
    name(list: String, name: String, index: ulong) {
        _in_order($"{list}#", name, index);
        var key = $"{list}#{name}";
        if (!_places.contains(key)) {
            _places[key] = index;
        }
    }

    ## Returns the place of the struct named `name` in the base's list
    ## `list`, or -1 when it has none.
    ##
    ## @param list the list of structs
    ## @param name the struct's name
    ## @returns its place, or -1
    named(list: String, name: String): long {
        var at = _places.try_get($"{list}#{name}");
        return at.is_value() ? at.value() as long : -1;
    }

    ## Returns the hashes of the elements of the base's list `list`, in
    ## order; with `list` followed by `#`, its structs' names.
    ##
    ## @param list the list
    ## @returns the hashes, or names; empty when the base has no such list
    sequence(list: String): Array<String> {
        var had = _sequences.try_get(list);
        return had.is_value() ? had.value() : Array<String>();
    }

    # Keeps `value` as the `index`th of `list`'s sequence: elements are
    # indexed in order, once each.
    _in_order(list: String, value: String, index: ulong) {
        if (!_sequences.contains(list)) {
            _sequences[list] = Array<String>();
        }
        var sequence = _sequences[list];
        if (sequence.count == index) {
            sequence.append(value);
        }
    }

    # The key of the element written to `scratch`, in list `list`.
    _key(list: String, scratch: RecordOut): String {
        return $"{list}:{_hash(scratch)}";
    }
}

export struct RecordIn {
    ## For each slot in the record, the program file it is now. Empty:
    ## every slot is the file of its number.
    var files: uint[] = Array<uint>();
    ## Why reading failed; empty while it has not.
    var error: String = "";
    # The record.
    var _data: u8[];
    # The next byte of `_data` to read.
    var _next: ulong;
    # Where the values end.
    var _end: ulong;
    # The strings, in their order.
    var _strings: String[] = Array<String>();
    ## Whether the bodies of functions that are not generic are skipped
    ## (`skip`), decoded when needed.
    var lazy_bodies: bool = false;

    ## Starts reading `data`, a whole record. A record that is not one
    ## leaves `error` set and reads as zeros.
    ##
    ## @param data the record
    construct(data: u8[]) {
        _data = data;
        _end = data.count;
        _open();
    }

    # Reads the header and the strings.
    _open() {
        var magic = MAGIC.bytes();
        if (_data.count < magic.count) {
            error = "not a record";
            return;
        }
        for (var i in 0..magic.count) {
            if (_data[i] != magic[i]) {
                error = "not a record of this version";
                return;
            }
        }
        _next = magic.count;
        var count = this.count();
        var sizes = Array<ulong>();
        for (var _ in 0..count) {
            sizes.append(unsigned());
        }
        var size = unsigned();
        if (error != "" or _next + size > _data.count) {
            error = "a truncated record";
            return;
        }
        var text_start = _next + size;
        var bytes = Array<u8>();
        for (var i in text_start.._data.count) {
            bytes.append(_data[i]);
        }
        var decoded = Utf8.decode(bytes);
        if (!decoded.is_value()) {
            error = "a record whose strings are not UTF-8";
            return;
        }
        var all = decoded.value();
        ulong offset = 0;
        for (var s in sizes) {
            if (offset + s > all.size) {
                error = "a truncated record";
                return;
            }
            _strings.append(all.substr_bytes(offset, s));
            offset += s;
        }
        _end = text_start;
    }

    ## Reads the size `RecordOut.size_mark` and `size_fill` wrote: four
    ## bytes, low first.
    ##
    ## @returns the size, 0 past the end
    size(): ulong {
        if (_next + 4 > _end) {
            _fail("a truncated record");
            return 0;
        }
        ulong value = 0;
        for (var i in 0..4) {
            value = value | ((_data[_next + i] as ulong) << (8 * i as ulong));
        }
        _next += 4;
        return value;
    }

    ## Skips the next `size` bytes, which hold a function body, and returns
    ## where they are, to decode later (`decode_body`).
    ##
    ## @param size how many bytes
    ## @returns where the body is
    skip(size: ulong): PendingBody {
        if (_next + size > _end) {
            _fail("a truncated record");
            return PendingBody(_data, _strings, files, _end, _end);
        }
        var out = PendingBody(_data, _strings, files, _next, _next + size);
        _next += size;
        return out;
    }

    ## A reader of the values `pending` spans, in its record.
    ##
    ## @param pending where a skipped body is
    ## @returns the reader
    static at(pending: PendingBody): RecordIn {
        var out = RecordIn(Array<u8>());
        out.error = "";
        out._data = pending.data;
        out._strings = pending.strings;
        out.files = pending.files;
        out._next = pending.start;
        out._end = pending.end;
        out.lazy_bodies = false;
        return out;
    }

    ## Reads an unsigned number.
    ##
    ## @returns the number, 0 past the end
    unsigned(): ulong {
        ulong value = 0;
        ulong shift = 0;
        while (_next < _end) {
            var byte = _data[_next];
            _next += 1;
            if (shift < 64) {
                value = value | (((byte & 0x7F) as ulong) << shift);
            }
            if (byte < 0x80) {
                return value;
            }
            shift += 7;
        }
        _fail("a truncated record");
        return 0;
    }

    ## Reads how many items follow: no more than bytes are left, since each
    ## takes at least one.
    ##
    ## @returns the count, 0 when the record is broken
    count(): ulong {
        var value = unsigned();
        if (value > _end - _next) {
            _fail("a count past the record's end");
            return 0;
        }
        return value;
    }

    ## Reads a signed number.
    ##
    ## @returns the number
    signed(): long {
        var raw = unsigned();
        return (raw >> 1) as long ^ -((raw & 1) as long);
    }

    ## Reads a boolean.
    ##
    ## @returns the boolean
    flag(): bool {
        if (_next >= _end) {
            _fail("a truncated record");
            return false;
        }
        var byte = _data[_next];
        _next += 1;
        return byte != 0;
    }

    ## Reads a floating-point number.
    ##
    ## @returns the number
    number(): double {
        return unsafe_cast<double>(unsigned());
    }

    ## Reads a string.
    ##
    ## @returns the string, empty when the record is broken
    text(): String {
        var place = unsigned();
        if (place >= _strings.count) {
            _fail("a string past the record's list");
            return "";
        }
        return _strings[place];
    }

    ## Reads a location.
    ##
    ## @returns the location
    loc(): Loc {
        var slot = unsigned();
        var start = unsigned();
        var end = unsigned();
        if (slot == 0) {
            var none = Loc.none();
            none.span = ast.Span(start, end);
            return none;
        }
        var file = (slot - 1) as uint;
        if (!files.is_empty) {
            if (file >= files.count) {
                _fail("a location in a file the record does not list");
                return Loc.none();
            }
            file = files[file];
        }
        return Loc.at(file, ast.Span(start, end));
    }

    ## Notes a value whose tag names no case of its type.
    ##
    ## @param type_name the type
    ## @param tag the tag read
    fail(type_name: String, tag: ulong) {
        _fail($"tag {tag} is no case of {type_name}");
    }

    ## Whether every value was read and nothing failed.
    ##
    ## @returns true for a whole, good record
    done(): bool {
        return error == "" and _next == _end;
    }

    _fail(why: String) {
        if (error == "") {
            error = why;
        }
        _next = _end;
    }
}
