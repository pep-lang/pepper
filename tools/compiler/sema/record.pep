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
import io;
import os;
import [Utf8] from text;
import [Loc, LocAnchors, LocShift, NO_FILE] from "loc";
import [Checked, FunctionDef, Module, StructDef] from "model";
import [set_name] from "names";
import [PendingBody] from "pending";

## What every record starts with: the format's name and version.
export const MAGIC = "pepper record 3\n";

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
    ## For a hash compared within one build (a delta's index, an own
    ## interface): a body still undecoded (`PendingBody`) is written as the
    ## hash of its bytes in its record, not decoded and written again.
    var pending_as_bytes: bool = false;
    ## For a delta: the declarations of the module it is written on, which
    ## its locations in their files are written from (`LocAnchors`).
    var anchors: LocAnchors? = Optional<LocAnchors>.Empty;
    # Each string's place in the list, by its text.
    var _places: HashMap<String, ulong> = HashMap<String, ulong>();
    # The strings' sizes, in their order.
    var _sizes: ulong[] = Array<ulong>();
    # The strings' text, in their order.
    var _text: StringBuilder = StringBuilder();

    construct() {}

    ## Writes `pending`, a body still undecoded, as the hash of its bytes
    ## in its record and how many strings that record has.
    ##
    ## @param pending the body
    pending(pending: PendingBody) {
        var hasher = digest.Blake3();
        hasher.update_range(pending.data, pending.start, pending.end - pending.start);
        text(hasher.finish_hex());
        unsigned(pending.strings.count);
    }

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
            unsigned(value.span.start);
            unsigned(value.span.end);
            return;
        }
        var slot = (files.is_empty ? value.file : files[value.file]) as ulong + 1;
        var anchor = anchors.is_value() ?
            anchors.value().find(value.file, value.span.start) :
            Optional<(String, ulong)>.Empty;
        if (!anchor.is_value()) {
            unsigned(slot << 1);
            unsigned(value.span.start);
            unsigned(value.span.end);
            return;
        }
        # From the declaration at or before it: its name and start then.
        var (name, start) = anchor.value();
        unsigned((slot << 1) | 1);
        text(name);
        unsigned(start);
        unsigned(value.span.start - start);
        unsigned(value.span.end - start);
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
        out.pending_as_bytes = pending_as_bytes;
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

## Whether struct `st`'s own interface keeps each field under a line of
## its own (`S\t.{field}`), taken only by a reader that names the field:
## a struct that is not generic, with no attributes (a value struct lays
## its fields out in its readers, an attribute struct takes positional
## arguments in their order), and no enum's.
##
## @param st the struct
## @returns whether it does
export splits_fields(st: StructDef): bool {
    return st.generic_params.count == 0 and st.attributes.count == 0 and !st.enum_cases.is_value();
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

## Returns the place of the first struct named `name` in `structs`, or
## their count when none is.
##
## @param structs the structs
## @param name the name
## @returns the place, or `structs.count`
export struct_named(structs: StructDef[], name: String): ulong {
    for (var i in 0..structs.count) {
        if (structs[i].name == name) {
            return i;
        }
    }
    return structs.count;
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
    # What the delta written on this base changed in the interface: an
    # entry for each element, entry or name it added, changed or dropped.
    var _own: Array<String> = Array<String>();
    # The entries of `_own` about functions, structs and enums that are
    # not generic, by name: a unit that reads this one depends on them
    # only when it can name one (`own_text`).
    var _named: Array<(String, String)> = Array<(String, String)>();
    # The delta's module's functions, structs and enums that are not
    # generic, by full name, and its functions and methods by location, as
    # their names (a method's is its struct's).
    var _function_names: HashMap<String, String> = HashMap<String, String>();
    var _function_locs: HashMap<Loc, String> = HashMap<Loc, String>();
    # Each list's elements' hashes, and its structs' names, in order.
    var _sequences: HashMap<String, Array<String>> = HashMap<String, Array<String>>();
    # The base's checked names: structs, functions and globals, as indexed.
    var _checked: Array<HashSet<String>> = Array<HashSet<String>>();
    ## The base's declarations, which a delta's locations in their files are
    ## written from (`RecordOut.anchors`).
    var anchors: LocAnchors = LocAnchors();
    # The base's checked summaries, as indexed.
    var _summaries: HashMap<String, (Loc, String)> = HashMap<String, (Loc, String)>();
    ## The base's structs, functions and templates as indexed: the elements
    ## themselves, which a delta finds by identity. The passes change a
    ## checked declaration only by extending a struct (`extended_checked`),
    ## so one still there is the same as the base's; with
    ## `PEPC_VERIFY_IDENTITY` set, the delta checks that against the hashes.
    var ref_structs: Array<StructDef> = Array<StructDef>();
    var ref_templates: Array<StructDef> = Array<StructDef>();
    var ref_functions: Array<FunctionDef> = Array<FunctionDef>();
    var ref_template_functions: Array<FunctionDef> = Array<FunctionDef>();
    ## Each of `ref_structs` and `ref_templates` with its member lists as
    ## indexed, which an extension may grow since.
    var ref_struct_parts: Array<StructDef> = Array<StructDef>();
    var ref_template_parts: Array<StructDef> = Array<StructDef>();
    ## Whether the lists found by identity are also indexed by hash, and
    ## each element found checked against its hash (`PEPC_VERIFY_IDENTITY`).
    var verifying: bool = os.environment("PEPC_VERIFY_IDENTITY").is_value();

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
            for (var name in lost) {
                own_named($"checked {i} lost", name, name);
            }
            for (var name in gained) {
                own_named($"checked {i}", name, name);
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
            own_named("checked summary lost", key, key);
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
            own_named("checked summary", key, $"{key} {summary_without_place(text)}");
        }
    }

    ## Reads what `write_checked` wrote on `base`, the base's checked
    ## declarations, which it leaves as they are unless `input.consumes_base`
    ## says the base is dropped after the read: then they are changed in
    ## place.
    ##
    ## @param input the record
    ## @param base the base's checked declarations
    ## @returns the checked declarations
    static read_checked(input: RecordIn, base: Checked): Checked {
        # Copying the base for each of a closure's records made merging the
        # closure quadratic in its size.
        var out = input.consumes_base ? base : base.copy();
        for (var names in [out.structs, out.functions, out.globals]) {
            var lost = input.count();
            for (var _ in 0..lost) {
                names.remove(input.text());
            }
            var gained = input.count();
            for (var _ in 0..gained) {
                names.insert(input.text());
            }
        }
        out.extensions = input.unsigned();
        var lost = input.count();
        for (var _ in 0..lost) {
            out.summaries.remove(input.text());
        }
        var count = input.count();
        for (var _ in 0..count) {
            var key = input.text();
            var loc = input.loc();
            out.summaries[key] = (loc, input.text());
        }
        return out;
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
        # Compared within this build only: undecoded bodies stay so.
        out.pending_as_bytes = true;
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

    ## With `verifying`, reports on standard error the element of the
    ## base's list `list` at `at` found by identity whose record is not the
    ## one written to `scratch`: an element changed in place.
    ##
    ## @param list the list
    ## @param at the element's place in the base's list
    ## @param scratch the element as it is, written alone
    ## @param name the element's name, if it has one
    verify_same(list: String, at: ulong, scratch: RecordOut, name: String = "") {
        var sequence = sequence(list);
        if (at >= sequence.count or sequence[at] != _hash(scratch)) {
            io.File.stderr().write_all($"identity: {list} {at} {name} changed in place\n");
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

    ## Adds to the own interface of the delta being written on this base:
    ## `hash`, the interface of something it added, changed or dropped,
    ## under `what`.
    ##
    ## @param what the field
    ## @param hash its interface hash, or text
    own(what: String, hash: String) {
        _own.append($"{what} {hash}");
    }

    ## Notes which functions, structs and enums of `module`, the module a
    ## delta is written for, are not generic: their entries in the own
    ## interface go under their names (`own_text`), and a struct's methods'
    ## under its name. Code that does not name such a declaration reaches
    ## it only through what other entries hold (a signature, a field's
    ## type, a generic body), which name it.
    ##
    ## @param module the module
    name_declarations(module: Module) {
        for (var f in module.functions) {
            if (f.is_generic_func or f.generic_params.count > 0) {
                continue;
            }
            var name = function_name(f.name);
            _function_names[f.name] = name;
            _function_locs[f.loc] = name;
        }
        for (var s in module.structs) {
            if (s.generic_params.count > 0) {
                continue;
            }
            var name = function_name(s.name);
            _function_names[s.name] = name;
            for (var m in s.method_members) {
                _function_locs[m.loc] = _method_line(name, m.name);
            }
            for (var c in s.constructors) {
                _function_locs[c.loc] = name;
            }
        }
        for (var e in module.enums) {
            _function_names[e.name] = function_name(e.name);
        }
    }

    ## `own`, for an entry about function `f`.
    ##
    ## @param what the field
    ## @param f the function
    ## @param hash its interface hash
    own_function(what: String, f: FunctionDef, hash: String) {
        own_named(what, f.name, hash);
    }

    ## `own`, for an entry about the function at `loc`.
    ##
    ## @param what the field
    ## @param loc the function's location
    ## @param hash its interface hash, or text
    own_at(what: String, loc: Loc, hash: String) {
        var name = _function_locs.try_get(loc);
        if (name.is_value()) {
            _named.append((name.value(), $"{what} {hash}"));
            return;
        }
        own(what, hash);
    }

    ## `own`, for an entry about the function, struct or global named `name`.
    ##
    ## @param what the field
    ## @param name the full name
    ## @param hash its interface hash, or text
    own_named(what: String, name: String, hash: String) {
        var named = _function_names.try_get(name);
        var method = name.split_once("\n");
        if (!named.is_value() and method.is_value()) {
            var (owner, member) = method.value();
            own_method(what, owner, member, hash);
            return;
        }
        if (named.is_value()) {
            _named.append((named.value(), $"{what} {hash}"));
            return;
        }
        own(what, hash);
    }

    ## `own`, for an entry about method `method` of struct `owner`: a struct
    ## that is not generic keeps it under its name and the method's
    ## (`own_text`), a constructor's under its name alone.
    ##
    ## @param what the field
    ## @param owner the struct's full name
    ## @param method the method's name
    ## @param hash its interface hash, or text
    own_method(what: String, owner: String, method: String, hash: String) {
        var named = _function_names.try_get(owner);
        if (!named.is_value()) {
            own(what, hash);
            return;
        }
        var line = method == "__ctor" ? named.value() : _method_line(named.value(), method);
        _named.append((line, $"{what} {hash}"));
    }

    ## Returns what the delta written on this base changed in the interface
    ## (`own`): unlike an interface hash of the whole module, it does not
    ## depend on the compilation units before. Its first line is the hash
    ## of every entry but those of functions that are not generic; each
    ## line after is one of those names and the hash of its entries,
    ## sorted, which `compilation_unit_key` takes only when the reader can
    ## name it; a method's name is its struct's and its own, apart by a tab.
    ##
    ## @returns the text
    own_text(): String {
        var lines = Array<String>();
        lines.append_all(_own);
        lines.sort((a, b) => a.compare(b));
        var hasher = digest.Blake3();
        hasher.update("pepper own interface 6\n");
        for (var line in lines) {
            hasher.update(line);
            hasher.update("\n");
        }
        var out = StringBuilder();
        out.append(hasher.finish_hex());
        var by_name = HashMap<String, Array<String>>();
        for (var (name, line) in _named) {
            if (!by_name.contains(name)) {
                by_name[name] = Array<String>();
            }
            by_name[name].append(line);
        }
        var names = Array<String>();
        for (var (name, _) in by_name) {
            names.append(name);
        }
        names.sort((a, b) => a.compare(b));
        for (var name in names) {
            var entries = by_name[name];
            entries.sort((a, b) => a.compare(b));
            var named = digest.Blake3();
            for (var line in entries) {
                named.update(line);
                named.update("\n");
            }
            out.append($"\n{name} {named.finish_hex()}");
        }
        return out.to_string();
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
    ## Whether a delta is read onto a base other than the one it was written on:
    ## the module of the compilation units its compilation unit reads, merged.
    ## New elements go after the base's, a patched struct is found by name, and
    ## a list written by place cannot be read so (`error`).
    var merging: bool = false;
    ## Whether the base a delta is read on is dropped after the read, as
    ## merging a closure's records does: what the read changes of the base's
    ## checked declarations is then changed in place rather than in a copy.
    var consumes_base: bool = false;
    ## Where the record's locations are now, when it was written before an
    ## edit that kept them all but those in the bodies it changed.
    var shift: LocShift? = Optional<LocShift>.Empty;
    ## The declarations of the module a delta is read on, as they are now,
    ## which its locations written from one are put back from
    ## (`RecordOut.anchors`).
    var anchors: LocAnchors? = Optional<LocAnchors>.Empty;

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
        out.shift = shift;
        out.anchors = anchors;
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
        out.shift = pending.shift;
        out.anchors = pending.anchors;
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
        var tag = unsigned();
        if (tag == 0) {
            var none = Loc.none();
            var start = unsigned();
            none.span = ast.Span(start, unsigned());
            return none;
        }
        var file = ((tag >> 1) - 1) as uint;
        if (!files.is_empty) {
            if (file >= files.count) {
                _fail("a location in a file the record does not list");
                return Loc.none();
            }
            file = files[file];
        }
        ulong start = 0;
        if (tag & 1 == 1) {
            # From a declaration: where it is now, else where it was.
            var name = text();
            start = unsigned();
            var now = anchors.is_value() ? anchors.value().start(name, file) : Optional<ulong>.Empty;
            if (now.is_value()) {
                start = now.value();
            }
        }
        var from = unsigned();
        var out = Loc.at(file, ast.Span(start + from, start + unsigned()));
        return shift.is_value() ? shift.value().map(out) : out;
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

## The name code uses for function `name`: its name before any `$` (an
## overload's), `@` (a file's) or `<` (a specialization's).
##
## @param name the function's full name
## @returns the name
export function_name(name: String): String {
    var bytes = name.bytes();
    ulong end = 0;
    while (end < bytes.count and bytes[end] != '$' as u8 and bytes[end] != '@' as u8 and bytes[end] != '<' as u8) {
        end += 1;
    }
    return name.substr_bytes(0, end);
}

# The own-interface line name of method `method` of the struct named `owner`
# (`DeltaBase.own_text`): the two names apart by a tab, the method's without
# its overload's number or a specialization's type arguments (not an
# operator's `<`).
_method_line(owner: String, method: String): String {
    var name = set_name(method);
    var angle = name.find("<");
    if (angle > 0) {
        name = name.substr(0, angle as ulong);
    }
    return $"{owner}\t{name}";
}

## The declarations of `module` a record's locations are written from
## (`LocAnchors`): its structs, templates, traits and enums, their methods
## and constructors, and its functions. Members the passes synthesize
## (`__copy`) are left out: a record may lose them.
##
## @param module the module
## @returns the declarations
export anchors_of(module: Module): LocAnchors {
    var out = LocAnchors();
    for (var structs in [module.structs, module.templates.structs]) {
        for (var s in structs) {
            if (s.name.contains("<")) {
                continue;
            }
            out.add($"s {s.name}", s.loc);
            for (var methods in [s.method_members, s.constructors, s.generic_methods]) {
                for (var m in methods) {
                    if (!m.name.starts_with("__")) {
                        out.add($"m {s.name}\n{m.name}", m.loc);
                    }
                }
            }
        }
    }
    for (var functions in [module.functions, module.templates.functions]) {
        for (var f in functions) {
            if (!f.name.contains("<")) {
                out.add($"f {f.name}", f.loc);
            }
        }
    }
    for (var t in module.traits) {
        out.add($"t {t.name}", t.loc);
        for (var m in t.methods) {
            out.add($"m {t.name}\n{m.name}", m.loc);
        }
    }
    for (var e in module.enums) {
        out.add($"e {e.name}", e.loc);
    }
    return out;
}
