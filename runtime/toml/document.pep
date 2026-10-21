## `TomlDocument`: a TOML document changed in place, keeping its comments,
## blank lines and layout, as `pepper package add` changes `pep.toml`.

import "parse";
import "value";
import "write";

## A TOML document that keeps the text it was read from, so a file people
## edit can be changed and written back without reformatting it.
##
## `set` and `remove` change only the text they must: a changed value is
## rewritten where it stands, a new key goes after the last key of its
## table, a new table goes at the end, and a removed key or table takes
## its lines with it, along with the comment lines right above them. Every
## other byte, comments included, stays as it was. Each edit parses the
## result again, so `root()` and `get` always see the current text.
##
## Keys are given as arrays, outermost first (`["dependencies", "json5"]`),
## so a key holding a dot needs no quoting. An edit cannot reach inside an
## array of tables (`[[bin]]`); set or remove the whole array instead.
##
## @example
##     import toml;
##
##     var text = "[package]\nname = \"demo\"  # the name\n\n[dependencies]\njson5 = \"1.0\"\n";
##     var document = toml.parse_document(text).value();
##     document.set(["package", "version"], toml.TomlValue.String("0.2.0")).value();
##     document.set(["dependencies", "yaml"], toml.TomlValue.String("0.3")).value();
##     document.remove(["dependencies", "json5"]).value();
##     assert(
##         document.to_string()
##             == "[package]\nname = \"demo\"  # the name\nversion = \"0.2.0\"\n\n[dependencies]\nyaml = \"0.3\"\n",
##         "only the edits change"
##     );
export struct TomlDocument {
    String _text;
    String _path;
    _TomlLayout _layout;
    TomlValue _root;

    ## Creates an empty document.
    construct() {
        _text = "";
        _path = "";
        _layout = _TomlLayout();
        _layout.sections.append(_toml_root_section());
        _root = TomlValue.table();
    }

    ## Returns the document's table, as `parse` reads the current text.
    ## Changing it does not change the document; use `set` and `remove`.
    ##
    ## @returns the root table
    root(): TomlValue {
        return _root;
    }

    ## Returns the value at `keys`.
    ##
    ## @param keys the keys, outermost first
    ## @returns the value, or none when a part is missing or is not a table
    get(keys: Array<String>): TomlValue? {
        return _root.get_path(keys);
    }

    ## Returns the value at a dotted key, read as TOML reads a key:
    ## `package.name`, `dependencies."my.package"`.
    ##
    ## @param key the dotted key
    ## @returns the value, or none when it is missing or `key` is not a
    ##   valid TOML key
    lookup(key: String): TomlValue? {
        return _root.lookup(key);
    }

    ## Sets the value at `keys`, adding the key, and any tables above it,
    ## when it is missing.
    ##
    ## A key that is there has its value rewritten in place, on one line;
    ## a key inside an inline table rewrites that inline table. A new key
    ## goes after the last key of the table it belongs to, indented like
    ## it, or under a new `[header]` at the end when that table has no
    ## section to put it in. A new table value (or array of tables) is
    ## written as its own `[header]` section at the end, unless `inline` is
    ## true, which writes it `{ ... }` on the key's line instead, as
    ## `cargo add` writes a dependency.
    ##
    ## @param keys the keys, outermost first
    ## @param value the value to store
    ## @param inline whether a new table value is written as an inline table
    ##   rather than a section
    ## @returns nothing, or an error when a part of `keys` holds a value
    ##   that is not a table, or lies inside an array of tables
    ## @panics if `keys` is empty ("TomlDocument.set needs a key")
    set(keys: Array<String>, value: TomlValue, inline: bool = false): Result<void, TomlError> {
        assert(!keys.is_empty, "TomlDocument.set needs a key");
        var checked = _check_path(keys);
        if (checked.is_value()) {
            return Result<void, TomlError>.err(checked.value());
        }
        var entry = _entry(keys);
        if (entry.is_value()) {
            var found = entry.value();
            return _splice(found.value_start, found.value_end, value.to_string());
        }
        var holder = _holder(keys);
        if (holder.is_value()) {
            var found = holder.value();
            var held = _root.get_path(found.keys).value();
            var table = held;
            for (var index in found.keys.count..keys.count - 1) {
                var next = table.try_get(keys[index]);
                if (next.is_empty()) {
                    var made = TomlValue.table();
                    table[keys[index]] = made;
                    table = made;
                } else {
                    table = next.value();
                }
            }
            table[keys.last()] = value;
            return _splice(found.value_start, found.value_end, held.to_string());
        }
        if (_root.get_path(keys).is_value()) {
            # A table with a header, or one made of dotted keys: replace it
            # whole.
            var removed = remove(keys);
            if (removed.is_err()) {
                return Result<void, TomlError>.err(removed.error());
            }
            return set(keys, value, inline);
        }
        var section_index = _section_for(keys);
        var section = _layout.sections[section_index];
        var rest = keys.count - section.keys.count;
        var sectioned = !inline && (value is Table || _toml_is_table_array(value));
        if (!sectioned && (rest == 1 || _has_dotted(section_index, keys[section.keys.count]))) {
            var line = StringBuilder();
            line.append(section.indent);
            var relative = Array<String>();
            for (var index in section.keys.count..keys.count) {
                relative.append(keys[index]);
            }
            _toml_append_keys(line, relative);
            line.append(" = ");
            line.append(value.to_string());
            line.append("\n");
            var at = section.last_end;
            if (at == 0 && !_text.is_empty) {
                # The first key of a root that has only sections: keep a
                # blank line before the first header.
                line.append("\n");
            }
            if (at > 0 && _text.byte_at(at - 1) != '\n') {
                return _splice(at, at, "\n" + line.to_string());
            }
            return _splice(at, at, line.to_string());
        }
        # A new section at the end: the value in tables named by `keys`,
        # written as a document, which leaves out headers holding only
        # tables.
        var wrapper = value;
        if (!sectioned) {
            wrapper = TomlValue.table();
            wrapper[keys.last()] = value;
        }
        var count = sectioned ? keys.count : keys.count - 1;
        var index = count;
        while (index > 0) {
            index = index - 1;
            var outer = TomlValue.table();
            outer[keys[index]] = wrapper;
            wrapper = outer;
        }
        var out = StringBuilder();
        if (!_text.is_empty) {
            if (!_text.ends_with("\n")) {
                out.append("\n");
            }
            out.append("\n");
        }
        if (inline && value is Table) {
            # `to_document` would write the table as a section of its own.
            var header = keys.copy();
            header.pop();
            out.append("[");
            out.append(_name(header));
            out.append("]\n");
            out.append(_name([keys.last()]));
            out.append(" = ");
            out.append(value.to_string());
            out.append("\n");
            return _splice(_text.size, _text.size, out.to_string());
        }
        out.append(wrapper.to_document());
        return _splice(_text.size, _text.size, out.to_string());
    }

    ## Removes the key or table at `keys`, with its lines and the comment
    ## lines right above them. Removing a table removes its sections, the
    ## tables below it, and any dotted keys that define it.
    ##
    ## @param keys the keys, outermost first
    ## @returns whether something was removed, or an error when a part of
    ##   `keys` lies inside an array of tables
    ## @panics if `keys` is empty ("TomlDocument.remove needs a key")
    remove(keys: Array<String>): Result<bool, TomlError> {
        assert(!keys.is_empty, "TomlDocument.remove needs a key");
        var checked = _check_path(keys);
        if (checked.is_value()) {
            return Result<bool, TomlError>.err(checked.value());
        }
        if (_root.get_path(keys).is_empty()) {
            return Result<bool, TomlError>.ok(false);
        }
        var entry = _entry(keys);
        if (entry.is_value()) {
            var found = entry.value();
            var spliced = _splice(found.decor_start, found.line_end, "");
            if (spliced.is_err()) {
                return Result<bool, TomlError>.err(spliced.error());
            }
            return Result<bool, TomlError>.ok(true);
        }
        var holder = _holder(keys);
        if (holder.is_value()) {
            var found = holder.value();
            var held = _root.get_path(found.keys).value();
            var parent = Array<String>();
            for (var index in found.keys.count..keys.count - 1) {
                parent.append(keys[index]);
            }
            held.get_path(parent).value().remove(keys.last());
            var spliced = _splice(found.value_start, found.value_end, held.to_string());
            if (spliced.is_err()) {
                return Result<bool, TomlError>.err(spliced.error());
            }
            return Result<bool, TomlError>.ok(true);
        }
        # A table: every section and key-value at or below it.
        var starts = Array<ulong>();
        var ends = Array<ulong>();
        for (var section in _layout.sections) {
            if (!section.keys.is_empty && _toml_starts_with(section.keys, keys)) {
                starts.append(section.decor_start);
                ends.append(section.end);
            }
        }
        for (var item in _layout.entries) {
            var section = _layout.sections[item.section];
            var inside = !section.keys.is_empty && _toml_starts_with(section.keys, keys);
            if (!inside && _toml_starts_with(item.keys, keys)) {
                starts.append(item.decor_start);
                ends.append(item.line_end);
            }
        }
        # Cut from the end, so earlier offsets stay right.
        var text = _text;
        while (!starts.is_empty) {
            ulong latest = 0;
            for (var index in 0..starts.count) {
                if (starts[index] > starts[latest]) {
                    latest = index;
                }
            }
            text = text.substr_bytes(0, starts[latest]) + text.substr_bytes(ends[latest], text.size - ends[latest]);
            starts.remove_at(latest);
            ends.remove_at(latest);
        }
        var replaced = _replace(text);
        if (replaced.is_err()) {
            return Result<bool, TomlError>.err(replaced.error());
        }
        return Result<bool, TomlError>.ok(true);
    }

    ## Returns the document's text, with every edit made.
    ##
    ## @returns the TOML text
    to_string(): String {
        return _text;
    }

    # An error when `keys` goes through a value that is not a table, or
    # through an array of tables.
    _check_path(keys: Array<String>): TomlError? {
        var here = _root;
        var path = Array<String>();
        for (var index in 0..keys.count) {
            if (index > 0 && !(here is Table)) {
                var message = $"cannot edit '{_name(keys)}': '{_name(path)}' is {_toml_kind(here)}, not a table";
                if (_toml_is_table_array(here)) {
                    message = $"cannot edit '{_name(keys)}' inside the array of tables '{_name(path)}'; set or remove it whole";
                }
                return Optional<TomlError>.Value(TomlError(message, _path, 0, 0));
            }
            var next = here.try_get(keys[index]);
            if (next.is_empty()) {
                return Optional<TomlError>.Empty;
            }
            here = next.value();
            path.append(keys[index]);
        }
        return Optional<TomlError>.Empty;
    }

    # The key-value line whose keys are `keys`, outside arrays of tables.
    _entry(keys: Array<String>): _TomlEntry? {
        for (var entry in _layout.entries) {
            if (!_layout.sections[entry.section].in_array
                && entry.keys.count == keys.count
                && _toml_starts_with(keys, entry.keys)) {
                return Optional<_TomlEntry>.Value(entry);
            }
        }
        return Optional<_TomlEntry>.Empty;
    }

    # The key-value line whose value (an inline table) holds `keys`.
    _holder(keys: Array<String>): _TomlEntry? {
        for (var entry in _layout.entries) {
            if (!_layout.sections[entry.section].in_array
                && entry.keys.count < keys.count
                && _toml_starts_with(keys, entry.keys)) {
                return Optional<_TomlEntry>.Value(entry);
            }
        }
        return Optional<_TomlEntry>.Empty;
    }

    # The section a new key at `keys` belongs in: the one whose header is
    # the longest start of `keys`, outside arrays of tables; the root at
    # least.
    _section_for(keys: Array<String>): ulong {
        ulong best = 0;
        for (var index in 0.._layout.sections.count) {
            var section = _layout.sections[index];
            if (!section.in_array
                && section.keys.count < keys.count
                && section.keys.count > _layout.sections[best].keys.count
                && _toml_starts_with(keys, section.keys)) {
                best = index;
            }
        }
        return best;
    }

    # Whether section `section` has dotted keys starting with `key`, so a
    # new dotted key under `key` belongs there.
    _has_dotted(section: ulong, key: String): bool {
        var depth = _layout.sections[section].keys.count;
        for (var entry in _layout.entries) {
            if (entry.section == section && entry.keys.count > depth + 1 && entry.keys[depth] == key) {
                return true;
            }
        }
        return false;
    }

    # Replaces the bytes from `start` up to `end` with `replacement`.
    _splice(start: ulong, end: ulong, replacement: String): Result<void, TomlError> {
        return _replace(_text.substr_bytes(0, start) + replacement + _text.substr_bytes(end, _text.size - end));
    }

    # Makes `text` the document's text, parsing it again; on an error, the
    # document stays as it was.
    _replace(text: String): Result<void, TomlError> {
        var layout = _TomlLayout();
        var parsed = _toml_parse_layout(text, _path, layout);
        if (parsed.is_err()) {
            return Result<void, TomlError>.err(parsed.error());
        }
        _text = text;
        _layout = layout;
        _root = parsed.value();
        return Result<void, TomlError>.ok();
    }

    _name(keys: Array<String>): String {
        var out = StringBuilder();
        _toml_append_keys(out, keys);
        return out.to_string();
    }
}

## Parses a TOML document into a `TomlDocument`, to change it in place.
##
## The text is read as `parse` reads it. Use it to change a file people
## edit, such as `pep.toml`, and write it back with its comments and
## layout; use `parse` when only the values matter.
##
## @param text the TOML text
## @param path the name of the text (a file name, say), which an error's
##   `to_string()` puts first
## @returns the document, or an error naming the first problem and its
##   line and column
export parse_document(text: String, path: String = ""): Result<TomlDocument, TomlError> {
    var document = TomlDocument();
    document._path = path;
    var replaced = document._replace(text);
    if (replaced.is_err()) {
        return Result<TomlDocument, TomlError>.err(replaced.error());
    }
    return Result<TomlDocument, TomlError>.ok(document);
}

# Whether `keys` starts with every key of `prefix`.
export _toml_starts_with(keys: Array<String>, prefix: Array<String>): bool {
    if (prefix.count > keys.count) {
        return false;
    }
    for (var index in 0..prefix.count) {
        if (keys[index] != prefix[index]) {
            return false;
        }
    }
    return true;
}
