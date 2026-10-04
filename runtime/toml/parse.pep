## `parse`: reading a TOML document into a `TomlValue`, and `TomlError`,
## what it reports when the text is not TOML.

import text;
import "value";
import "write";

## What `parse` reports when the text is not TOML, and what `decode`
## reports when a value does not fit its property: what is wrong, and the
## line and column where it is.
##
## `to_string()` renders it like a compiler error:
## `pep.toml:4:12: error: expected '='`.
export struct TomlError {
    ## What is wrong, worded like a compiler error (`expected '='`).
    var message: String;
    ## The path given to `parse`, which names the text in `to_string()`;
    ## empty when none was given.
    var path: String;
    ## The line of the error, from 1; 0 for an error with no text to point
    ## into, such as one from `from_toml`.
    var line: ulong;
    ## The column of the error, from 1, counting bytes as clang does; 0
    ## when `line` is.
    var column: ulong;
    ## The byte offset of the error in the text, from 0.
    var offset: ulong;
    ## Where in the document the value an error is about is, as a path from
    ## the root `$` (`$.package.version`, `$.bin[0].name`); empty for an
    ## error in the text's syntax. `decode` and `from_toml` set it, and
    ## start `message` with it.
    var value_path: String;

    ## Creates an error.
    ##
    ## @param message what is wrong
    ## @param path the name of the text, or empty
    ## @param line the line of the error, from 1
    ## @param column the column of the error, from 1
    ## @param offset the byte offset of the error, from 0
    construct(message: String = "", path: String = "", line: ulong = 1, column: ulong = 1, offset: ulong = 0) {
        this.message = message;
        this.path = path;
        this.line = line;
        this.column = column;
        this.offset = offset;
        value_path = "";
    }

    ## Returns the error as a compiler prints one:
    ## `path:line:column: error: message`, without the `path:` when there
    ## is no path and without `line:column:` when `line` is 0.
    ##
    ## @returns the rendered error
    to_string(): String {
        if (line == 0) {
            if (path.is_empty) {
                return $"error: {message}";
            }
            return $"{path}: error: {message}";
        }
        if (path.is_empty) {
            return $"{line}:{column}: error: {message}";
        }
        return $"{path}:{line}:{column}: error: {message}";
    }
}

## Parses a TOML 1.0 document into a `TomlValue`, a `Table`.
##
## Every rule of TOML 1.0 is checked: a key or table defined twice, a table
## extended after it was closed (an inline table, or one written with
## dotted keys in another section), strings, numbers and dates as the
## specification spells them. The text must be valid UTF-8; a byte-order
## mark at the start is skipped. Tables keep their keys in the order they
## were written. A line break in a multi-line string reads as `\n`, also
## when the text has `\r\n`.
##
## Arrays and inline tables nest as deeply as the text says, so the parser
## keeps its own stack rather than recursing, and `max_depth` bounds it.
##
## @param text the TOML text
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @param max_depth how deeply arrays and inline tables may nest
## @returns the document's table, or an error naming the first problem and
##   its line and column
## @example
##     import toml;
##
##     var parsed = toml.parse("[server]\nport = 8080\n");
##     assert(parsed.value()["server"]["port"].as_int().value() == 8080, "a lookup");
##     var bad = toml.parse("name \"demo\"", path = "pep.toml");
##     assert(bad.error().to_string() == "pep.toml:1:6: error: expected '=' after the key", "where");
export parse(text: String, path: String = "", max_depth: ulong = 1000): Result<TomlValue, TomlError> {
    var parser = _TomlParser(text, path, max_depth);
    return parser.run();
}

# Parses `text` like `parse`, recording where each key-value and section is
# in `layout`.
export _toml_parse_layout(text: String, path: String, layout: _TomlLayout): Result<TomlValue, TomlError> {
    var parser = _TomlParser(text, path, 1000);
    parser._layout = Optional<_TomlLayout>.Value(layout);
    return parser.run();
}

# The byte offset in `text`, which must parse, of the value at `value_path`
# (`$.package.version`, as `_toml_path_key` writes it), or none when it is
# not there (an implicit table has no place of its own).
export _toml_locate(text: String, value_path: String): ulong? {
    var parser = _TomlParser(text, "", 1000000);
    parser._locating = true;
    parser.run();
    return parser._offsets.try_get(value_path);
}

# The keys of the dotted key `key` (`a."b.c".d`), or none when it is not a
# valid TOML key.
export _toml_split_key(key: String): Array<String>? {
    var parser = _TomlParser(key, "", 1);
    parser._skip_space();
    if (!parser._key()) {
        return Optional<Array<String>>.Empty;
    }
    parser._skip_space();
    if (parser._position < parser._size) {
        return Optional<Array<String>>.Empty;
    }
    return Optional<Array<String>>.Value(parser._keys);
}

# `path.key`, or `path["key"]` when the key is not bare: how a value's path
# in a document is written.
export _toml_path_key(path: String, key: String): String {
    var plain = !key.is_empty;
    for (var b in key.bytes()) {
        var letter = (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || b == '_';
        if (!letter && !(b >= '0' && b <= '9')) {
            plain = false;
        }
    }
    if (plain) {
        return $"{path}.{key}";
    }
    var out = StringBuilder();
    out.append(path);
    out.append("[");
    _toml_append_string(out, key);
    out.append("]");
    return out.to_string();
}

# Sets `error`'s offset, and the line and column of that offset in `text`.
export _toml_place(error: TomlError, text: String, offset: ulong) {
    ulong line = 1;
    ulong line_start = 0;
    ulong index = 0;
    while (index < offset and index < text.size) {
        if (text.byte_at(index) == '\n') {
            line = line + 1;
            line_start = index + 1;
        }
        index = index + 1;
    }
    error.line = line;
    error.column = offset - line_start + 1;
    error.offset = offset;
}

# Where a document's key-values and sections are, for `TomlDocument`'s
# edits. Section 0 is the root, before the first header.
export struct _TomlLayout {
    Array<_TomlEntry> entries;
    Array<_TomlSection> sections;

    construct() {
        entries = Array<_TomlEntry>();
        sections = Array<_TomlSection>();
    }
}

# The layout's section for the root table, before the first header.
export _toml_root_section(): _TomlSection {
    var root = _TomlSection();
    root.keys = Array<String>();
    root.indent = "";
    return root;
}

# A `key = value` line: its absolute keys; the offsets of the comment lines
# right above it (`decor_start`), its line, its value, and the end of its
# line after any comment and line break; the spaces it is indented by; and
# its section.
export struct _TomlEntry {
    Array<String> keys;
    ulong section;
    ulong decor_start;
    ulong line_start;
    ulong value_start;
    ulong value_end;
    ulong line_end;
    String indent;
}

# A section: the keys of its header (none for the root), whether it is
# `[[keys]]` or lies in one; the offsets of the comment lines right above
# its header, of its header line and its end, of the end of its last
# key-value's line (`last_end`, the header's end when it has none), and of
# where the next section's comment lines start (`end`); and the indent of
# its last key-value.
export struct _TomlSection {
    Array<String> keys;
    bool is_array;
    bool in_array;
    ulong decor_start;
    ulong header_start;
    ulong header_end;
    ulong last_end;
    ulong end;
    String indent;
}

# A table is defined by a `[header]` (or holds the dotted keys of a section
# that has ended), or can no longer change (an inline table or an array
# written as a value).
const EXPLICIT = 1;
const FROZEN = 2;

# The flags of the tables at one path of keys, as Python's `tomllib` keeps
# them: those of the table itself, those that hold for everything below it
# (`recursive`), and the tables below it.
struct _TomlFlagNode {
    int flags;
    int recursive;
    HashMap<String, _TomlFlagNode> nested;

    construct() {
        nested = HashMap<String, _TomlFlagNode>();
    }
}

# A container still open while reading a value: an array, or an inline
# table with the key of the member being read, where that key starts, and
# the tables its dotted keys made (by `_toml_joined` keys), which later
# dotted keys may add to.
struct _TomlFrame {
    TomlValue value;
    bool is_array;
    Array<TomlValue> items;
    OrderedMap<String, TomlValue> members;
    Array<String> keys;
    ulong key_start;
    HashMap<String, bool> dotted;
    String path;

    construct(is_array: bool, path: String) {
        this.is_array = is_array;
        this.path = path;
        items = Array<TomlValue>();
        members = OrderedMap<String, TomlValue>();
        value = is_array ? TomlValue.Array(items) : TomlValue.Table(members);
        keys = Array<String>();
        dotted = HashMap<String, bool>();
    }
}

# `keys` as one string that no other keys give: each key after its size.
_toml_joined(keys: Array<String>, count: ulong): String {
    var out = StringBuilder();
    for (var index in 0..count) {
        out.append($"{keys[index].size}:");
        out.append(keys[index]);
    }
    return out.to_string();
}

# The first `count` keys of `keys` after `header`.
_toml_concat(header: Array<String>, keys: Array<String>, count: ulong): Array<String> {
    var out = header.clone();
    for (var index in 0..count) {
        out.append(keys[index]);
    }
    return out;
}

# Reads a document from `_text`. Each method that can fail returns false
# (or none) after recording the first error in `_error`.
struct _TomlParser {
    String _text;
    ulong _size;
    ulong _position;
    String _path;
    ulong _max_depth;
    TomlError _error;
    OrderedMap<String, TomlValue> _root;
    _TomlFlagNode _flags;
    # The containers of the dotted keys of the current section, flagged
    # `EXPLICIT` once the section ends.
    Array<Array<String>> _pending;
    # The current section's keys and table, and with `_locating` its path.
    Array<String> _header;
    String _header_path;
    # What the last `_key`, string or `_scalar` read.
    Array<String> _keys;
    String _string_value;
    TomlValue _scalar_value;
    # Set by `_nest` when its path went through an array of tables.
    bool _through_array;
    # With `_toml_parse_layout`: where things are, and the comment lines
    # right above the current line.
    _TomlLayout? _layout;
    ulong _decor_start;
    bool _decor_open;
    # With `_toml_locate`: the offset of each value, by path.
    bool _locating;
    HashMap<String, ulong> _offsets;

    construct(text: String, path: String, max_depth: ulong) {
        _text = text;
        _size = text.size;
        _path = path;
        _max_depth = max_depth;
        _error = TomlError();
        _root = OrderedMap<String, TomlValue>();
        _flags = _TomlFlagNode();
        _pending = Array<Array<String>>();
        _header = Array<String>();
        _header_path = "$";
        _keys = Array<String>();
        _string_value = "";
        _scalar_value = TomlValue.Boolean(false);
        _layout = Optional<_TomlLayout>.Empty;
        _offsets = HashMap<String, ulong>();
    }

    run(): Result<TomlValue, TomlError> {
        if (_size >= 3 and _text.byte_at(0) == 239 and _text.byte_at(1) == 187 and _text.byte_at(2) == 191) {
            _position = 3;
        }
        var invalid = text.Utf8.find_invalid(_text);
        if (invalid.is_value()) {
            _fail_at("invalid UTF-8", invalid.value());
            return Result<TomlValue, TomlError>.err(_error);
        }
        if (_layout.is_value()) {
            _layout.value().sections.append(_toml_root_section());
        }
        if (!_document()) {
            return Result<TomlValue, TomlError>.err(_error);
        }
        if (_layout.is_value()) {
            _layout.value().sections.last().end = _size;
        }
        return Result<TomlValue, TomlError>.ok(TomlValue.Table(_root));
    }

    # Reads the document a line at a time: blank lines, comments, headers
    # and key-values.
    _document(): bool {
        while (true) {
            var line_start = _position;
            _skip_space();
            if (_position >= _size) {
                return true;
            }
            var b = _peek();
            if (b == '\n' or (b == '\r' and _at(_position + 1) == '\n')) {
                _position = _position + (b == '\r' ? 2 : 1);
                _decor_open = false;
                continue;
            }
            if (b == '#') {
                if (!_decor_open) {
                    _decor_start = line_start;
                    _decor_open = true;
                }
                if (!_comment() or !_line_break("expected a line break after the comment")) {
                    return false;
                }
                continue;
            }
            var decor = _decor_open ? _decor_start : line_start;
            _decor_open = false;
            if (b == '[') {
                if (!_table_header(line_start, decor)) {
                    return false;
                }
            } else if (!_key_value(line_start, decor)) {
                return false;
            }
        }
        return true;
    }

    # Reads a `[table]` or `[[array of tables]]` header line.
    _table_header(line_start: ulong, decor: ulong): bool {
        var start = _position;
        _position = _position + 1;
        var is_array = _peek() == '[';
        if (is_array) {
            _position = _position + 1;
        }
        _skip_space();
        var key_start = _position;
        if (!_key()) {
            return false;
        }
        var keys = _keys;
        _skip_space();
        if (_peek() != ']' or (is_array and _at(_position + 1) != ']')) {
            _fail(is_array ? "expected ']]' after the table name" : "expected ']' after the table name");
            return false;
        }
        _position = _position + (is_array ? 2 : 1);
        if (!_end_of_line("expected a line break after the table header")) {
            return false;
        }
        # A section's dotted keys can no longer be added to by a later one.
        for (var pending in _pending) {
            _set_flag(pending, EXPLICIT, false);
        }
        _pending.clear();
        var name = _keys_name(keys);
        if (is_array) {
            if (_has_flag(keys, FROZEN)) {
                _fail_at($"cannot add to '{name}': it was written as a value", key_start);
                return false;
            }
            _unset_flags(keys);
            _set_flag(keys, EXPLICIT, false);
            var parent = _nest(keys, keys.count - 1, key_start);
            if (parent.is_empty()) {
                return false;
            }
            var element = OrderedMap<String, TomlValue>();
            var stem = keys.last();
            var existing = parent.value().try_get(stem);
            if (existing.is_value()) {
                if (existing.value() is Array(items)) {
                    items.append(TomlValue.Table(element));
                } else {
                    _fail_at($"'{name}' is already defined as {_toml_kind(existing.value())}", key_start);
                    return false;
                }
            } else {
                parent.value()[stem] = TomlValue.array([TomlValue.Table(element)]);
            }
            _header = keys;
            _start_section(keys, true, true, line_start, decor, start);
        } else {
            if (_has_flag(keys, EXPLICIT) or _has_flag(keys, FROZEN)) {
                _fail_at($"table '{name}' is already defined", key_start);
                return false;
            }
            _set_flag(keys, EXPLICIT, false);
            var table = _nest(keys, keys.count, key_start);
            if (table.is_empty()) {
                return false;
            }
            _header = keys;
            _start_section(keys, false, _through_array, line_start, decor, start);
        }
        if (_locating) {
            _header_path = _value_path(keys);
            _offsets[_header_path] = start;
        }
        return true;
    }

    # Records a new section in the layout, ending the one before it.
    _start_section(keys: Array<String>, is_array: bool, in_array: bool, line_start: ulong, decor: ulong, start: ulong) {
        if (_layout.is_empty()) {
            return;
        }
        var sections = _layout.value().sections;
        sections.last().end = decor;
        var section = _TomlSection();
        section.keys = keys;
        section.is_array = is_array;
        section.in_array = in_array;
        section.decor_start = decor;
        section.header_start = line_start;
        section.header_end = _position;
        section.last_end = _position;
        section.end = _size;
        section.indent = "";
        sections.append(section);
    }

    # Reads a `key = value` line of the current section.
    _key_value(line_start: ulong, decor: ulong): bool {
        var key_start = _position;
        if (!_key()) {
            return false;
        }
        var keys = _keys;
        _skip_space();
        if (_peek() != '=') {
            _fail("expected '=' after the key");
            return false;
        }
        _position = _position + 1;
        _skip_space();
        var value_start = _position;
        var value_path = _header_path;
        if (_locating) {
            for (var key in keys) {
                value_path = _toml_path_key(value_path, key);
            }
        }
        var value = _value(value_path);
        if (value.is_empty()) {
            return false;
        }
        var value_end = _position;
        if (!_end_of_line("expected a line break after the value")) {
            return false;
        }
        # The containers of a dotted key: none may be a table with a header,
        # and later sections may not add to them.
        for (var count in 1..keys.count) {
            var container = _toml_concat(_header, keys, count);
            if (_has_flag(container, EXPLICIT)) {
                _fail_at(
                    $"cannot add to table '{_keys_name(container)}' with a dotted key: it has a header", key_start
                );
                return false;
            }
            _pending.append(container);
        }
        var parent_keys = _toml_concat(_header, keys, keys.count - 1);
        if (_has_flag(parent_keys, FROZEN)) {
            _fail_at($"cannot add to '{_keys_name(parent_keys)}': it was written as a value", key_start);
            return false;
        }
        var parent = _nest(parent_keys, parent_keys.count, key_start);
        if (parent.is_empty()) {
            return false;
        }
        var stem = keys.last();
        if (parent.value().contains(stem)) {
            _fail_at($"duplicate key '{_keys_name(_toml_concat(_header, keys, keys.count))}'", key_start);
            return false;
        }
        var stored = value.value();
        if (stored is Array || stored is Table) {
            _set_flag(_toml_concat(_header, keys, keys.count), FROZEN, true);
        }
        parent.value()[stem] = stored;
        if (_layout.is_value()) {
            var sections = _layout.value().sections;
            var entry = _TomlEntry();
            entry.keys = _toml_concat(_header, keys, keys.count);
            entry.section = sections.count - 1;
            entry.decor_start = decor;
            entry.line_start = line_start;
            entry.value_start = value_start;
            entry.value_end = value_end;
            entry.line_end = _position;
            entry.indent = _text.substr_bytes(line_start, key_start - line_start);
            _layout.value().entries.append(entry);
            sections.last().last_end = _position;
            sections.last().indent = entry.indent;
        }
        return true;
    }

    # The table at the first `count` keys of `keys`, made where missing; in
    # an array of tables, its last element. Sets `_through_array` when it
    # went through one.
    _nest(keys: Array<String>, count: ulong, at: ulong): OrderedMap<String, TomlValue>? {
        var none = Optional<OrderedMap<String, TomlValue>>.Empty;
        _through_array = false;
        var table = _root;
        for (var index in 0..count) {
            var key = keys[index];
            var found = table.try_get(key);
            if (found.is_empty()) {
                var made = OrderedMap<String, TomlValue>();
                table[key] = TomlValue.Table(made);
                table = made;
                continue;
            }
            var value = found.value();
            if (value is Array(items)) {
                if (!items.is_empty and items.last() is Table) {
                    _through_array = true;
                    value = items.last();
                }
            }
            if (value is Table(members)) {
                table = members;
            } else {
                var name = _keys_name(_toml_concat(Array<String>(), keys, index + 1));
                _fail_at($"'{name}' is already defined as {_toml_kind(value)}, not a table", at);
                return none;
            }
        }
        return Optional<OrderedMap<String, TomlValue>>.Value(table);
    }

    # The path of the table at `keys`, through the last element of each
    # array of tables on the way.
    _value_path(keys: Array<String>): String {
        var path = "$";
        var table = _root;
        for (var key in keys) {
            path = _toml_path_key(path, key);
            var value = table.try_get(key).value();
            if (value is Array(items)) {
                path = $"{path}[{items.count - 1}]";
                value = items.last();
            }
            table = value.as_table().value();
        }
        return path;
    }

    # The flag node at `keys`, or none.
    _flag_node(keys: Array<String>): _TomlFlagNode? {
        var node = _flags;
        for (var key in keys) {
            var next = node.nested.try_get(key);
            if (next.is_empty()) {
                return next;
            }
            node = next.value();
        }
        return Optional<_TomlFlagNode>.Value(node);
    }

    # Whether the table at `keys` has `flag`, or a table above it has it
    # recursively.
    _has_flag(keys: Array<String>, flag: int): bool {
        if (keys.is_empty) {
            return false;
        }
        var node = _flags;
        for (var index in 0..keys.count) {
            var next = node.nested.try_get(keys[index]);
            if (next.is_empty()) {
                return false;
            }
            node = next.value();
            if (index + 1 < keys.count and (node.recursive & flag) != 0) {
                return true;
            }
        }
        return (node.flags & flag) != 0 or (node.recursive & flag) != 0;
    }

    _set_flag(keys: Array<String>, flag: int, recursive: bool) {
        var node = _flags;
        for (var key in keys) {
            var next = node.nested.try_get(key);
            if (next.is_empty()) {
                var made = _TomlFlagNode();
                node.nested[key] = made;
                node = made;
            } else {
                node = next.value();
            }
        }
        if (recursive) {
            node.recursive = node.recursive | flag;
        } else {
            node.flags = node.flags | flag;
        }
    }

    # Forgets the flags at and below `keys`, for a new element of an array
    # of tables.
    _unset_flags(keys: Array<String>) {
        var parent = _flag_node(_toml_concat(Array<String>(), keys, keys.count - 1));
        if (parent.is_value()) {
            parent.value().nested.remove(keys.last());
        }
    }

    # A dotted key as errors show it.
    _keys_name(keys: Array<String>): String {
        var out = StringBuilder();
        _toml_append_keys(out, keys);
        return out.to_string();
    }

    # ── Values ────────────────────────────────────────────────────────────

    # Reads a value. Arrays and inline tables still open are on `frames`,
    # with the member being read last.
    _value(path: String): TomlValue? {
        var none = Optional<TomlValue>.Empty;
        var frames = Array<_TomlFrame>();
        var here = path;
        while (true) {
            if (_locating) {
                _offsets[here] = _position;
            }
            var b = _peek();
            var value = TomlValue.Boolean(false);
            if (b == '[' or b == '{') {
                if (frames.count >= _max_depth) {
                    _fail($"arrays and inline tables nest more than {_max_depth} deep");
                    return none;
                }
                _position = _position + 1;
                var frame = _TomlFrame(b == '[', here);
                if (b == '[') {
                    if (!_skip_array_space()) {
                        return none;
                    }
                    if (_peek() == ']') {
                        _position = _position + 1;
                        value = frame.value;
                    } else {
                        frames.append(frame);
                        here = $"{frame.path}[0]";
                        continue;
                    }
                } else {
                    _skip_space();
                    if (_peek() == '}') {
                        _position = _position + 1;
                        value = frame.value;
                    } else {
                        if (!_inline_key(frame)) {
                            return none;
                        }
                        frames.append(frame);
                        here = _frame_path(frame);
                        continue;
                    }
                }
            } else {
                if (!_scalar()) {
                    return none;
                }
                value = _scalar_value;
            }
            # Store the value in its container, then close every container
            # that ends after it.
            while (true) {
                if (frames.is_empty) {
                    return Optional<TomlValue>.Value(value);
                }
                var top = frames.last();
                if (top.is_array) {
                    top.items.append(value);
                    if (!_skip_array_space()) {
                        return none;
                    }
                    if (_peek() == ',') {
                        _position = _position + 1;
                        if (!_skip_array_space()) {
                            return none;
                        }
                        if (_peek() != ']') {
                            here = $"{top.path}[{top.items.count}]";
                            break;
                        }
                    } else if (_peek() != ']') {
                        _fail("expected ',' or ']'");
                        return none;
                    }
                } else {
                    if (!_inline_put(top, value)) {
                        return none;
                    }
                    _skip_space();
                    if (_peek() == ',') {
                        _position = _position + 1;
                        _skip_space();
                        if (_peek() == '}') {
                            _fail("a trailing comma is not allowed in an inline table");
                            return none;
                        }
                        if (!_inline_key(top)) {
                            return none;
                        }
                        here = _frame_path(top);
                        break;
                    } else if (_peek() != '}') {
                        if (_peek() == '\n' or _peek() == '\r') {
                            _fail("expected ',' or '}': an inline table stays on one line");
                        } else {
                            _fail("expected ',' or '}'");
                        }
                        return none;
                    }
                }
                _position = _position + 1;
                value = top.value;
                frames.pop();
            }
        }
        return none;
    }

    # The path of the member an inline table frame is reading.
    _frame_path(frame: _TomlFrame): String {
        if (!_locating) {
            return frame.path;
        }
        var path = frame.path;
        for (var key in frame.keys) {
            path = _toml_path_key(path, key);
        }
        return path;
    }

    # Reads an inline table member's key and the `=` after it into `frame`.
    _inline_key(frame: _TomlFrame): bool {
        frame.key_start = _position;
        if (!_key()) {
            return false;
        }
        frame.keys = _keys;
        _skip_space();
        if (_peek() != '=') {
            _fail("expected '=' after the key");
            return false;
        }
        _position = _position + 1;
        _skip_space();
        return true;
    }

    # Stores `value` under the inline table frame's key. A dotted key may
    # only add to tables earlier dotted keys of the same inline table made.
    _inline_put(frame: _TomlFrame, value: TomlValue): bool {
        var keys = frame.keys;
        var table = frame.members;
        for (var index in 0..keys.count - 1) {
            var key = keys[index];
            var joined = _toml_joined(keys, index + 1);
            var found = table.try_get(key);
            if (found.is_empty()) {
                var made = OrderedMap<String, TomlValue>();
                table[key] = TomlValue.Table(made);
                frame.dotted[joined] = true;
                table = made;
            } else if (frame.dotted.contains(joined)) {
                table = found.value().as_table().value();
            } else {
                var name = _keys_name(_toml_concat(Array<String>(), keys, index + 1));
                _fail_at($"cannot add to '{name}': it is already defined", frame.key_start);
                return false;
            }
        }
        if (table.contains(keys.last())) {
            _fail_at($"duplicate key '{_keys_name(keys)}'", frame.key_start);
            return false;
        }
        table[keys.last()] = value;
        return true;
    }

    # Reads a value that is not an array or inline table into
    # `_scalar_value`.
    _scalar(): bool {
        var b = _peek();
        if (b == '"' or b == '\'') {
            if (!_string()) {
                return false;
            }
            _scalar_value = TomlValue.String(_string_value);
            return true;
        }
        if (_word("true")) {
            _scalar_value = TomlValue.Boolean(true);
            return true;
        }
        if (_word("false")) {
            _scalar_value = TomlValue.Boolean(false);
            return true;
        }
        if (_is_digit(b)) {
            if (_is_digit(_at(_position + 1))
                and _is_digit(_at(_position + 2))
                and _is_digit(_at(_position + 3))
                and _at(_position + 4) == '-') {
                return _date_time();
            }
            if (_is_digit(_at(_position + 1)) and _at(_position + 2) == ':') {
                return _date_time();
            }
        }
        if (b == '+' or b == '-' or b == 'i' or b == 'n' or _is_digit(b)) {
            return _number();
        }
        if (_position >= _size or b == '\n' or b == '\r' or b == '#') {
            _fail("expected a value");
        } else if (b == ']' or b == '}' or b == ',') {
            _fail($"expected a value before '{_text.substr_bytes(_position, 1)}'");
        } else {
            _fail("expected a value: a string, number, boolean, date, array or inline table");
        }
        return false;
    }

    # Consumes `word` when the text continues with it.
    _word(word: String): bool {
        var size = word.size;
        if (_position + size > _size) {
            return false;
        }
        for (var index in 0..size) {
            if (_text.byte_at(_position + index) != word.byte_at(index)) {
                return false;
            }
        }
        _position = _position + size;
        return true;
    }

    # ── Numbers ───────────────────────────────────────────────────────────

    # Reads an integer or float: decimal with optional fraction and
    # exponent, `0x`, `0o` or `0b` integers, or `inf` and `nan` with an
    # optional sign. `_` may sit between two digits.
    _number(): bool {
        var start = _position;
        var signed = false;
        if (_peek() == '+' or _peek() == '-') {
            signed = true;
            _position = _position + 1;
        }
        if (_word("inf")) {
            _scalar_value = TomlValue.Float(_text.byte_at(start) == '-' ? -1.0 / 0.0 : 1.0 / 0.0);
            return true;
        }
        if (_word("nan")) {
            _scalar_value = TomlValue.Float(0.0 / 0.0);
            return true;
        }
        if (_peek() == '0' and (_at(_position + 1) == 'x' or _at(_position + 1) == 'o' or _at(_position + 1) == 'b')) {
            if (signed) {
                _fail_at("a hexadecimal, octal or binary integer cannot have a sign", start);
                return false;
            }
            return _radix_integer();
        }
        var whole = true;
        var digits = StringBuilder();
        if (signed) {
            digits.append(_text.substr_bytes(start, 1));
        }
        if (_peek() == '0') {
            _position = _position + 1;
            digits.append("0");
            if (_is_digit(_peek()) or _peek() == '_') {
                _fail_at("an integer cannot start with '0'", start);
                return false;
            }
        } else if (!_digits(digits, 10)) {
            return false;
        }
        if (_peek() == '.') {
            whole = false;
            _position = _position + 1;
            digits.append(".");
            if (!_digits(digits, 10)) {
                return false;
            }
        }
        if (_peek() == 'e' or _peek() == 'E') {
            whole = false;
            _position = _position + 1;
            digits.append("e");
            if (_peek() == '+' or _peek() == '-') {
                digits.append(_text.substr_bytes(_position, 1));
                _position = _position + 1;
            }
            if (!_digits(digits, 10)) {
                return false;
            }
        }
        var spelled = digits.to_string();
        if (whole) {
            var parsed = long.parse(spelled);
            if (parsed.is_empty()) {
                _fail_at("integer does not fit in 64 bits", start);
                return false;
            }
            _scalar_value = TomlValue.Integer(parsed.value());
            return true;
        }
        var number = double.parse(spelled);
        if (number.is_empty()) {
            _fail_at("float is out of range", start);
            return false;
        }
        _scalar_value = TomlValue.Float(number.value());
        return true;
    }

    # Reads a `0x`, `0o` or `0b` integer.
    _radix_integer(): bool {
        var start = _position;
        var letter = _at(_position + 1);
        ulong radix = letter == 'x' ? 16 : (letter == 'o' ? 8 : 2);
        _position = _position + 2;
        var digits = StringBuilder();
        if (!_digits(digits, radix)) {
            return false;
        }
        ulong value = 0;
        for (var b in digits.to_string().bytes()) {
            var digit = _digit_value(b) as ulong;
            if (value > (9223372036854775807 - digit) / radix) {
                _fail_at("integer does not fit in 64 bits", start);
                return false;
            }
            value = value * radix + digit;
        }
        _scalar_value = TomlValue.Integer(value as long);
        return true;
    }

    # Appends one or more digits of base `radix` to `out`, skipping a `_`
    # between two of them.
    _digits(out: StringBuilder, radix: ulong): bool {
        if (!_is_radix_digit(_peek(), radix)) {
            if (_peek() == '_') {
                _fail("an underscore must sit between two digits");
            } else {
                _fail("expected a digit");
            }
            return false;
        }
        var start = _position;
        while (true) {
            var b = _peek();
            if (_is_radix_digit(b, radix)) {
                _position = _position + 1;
            } else if (b == '_') {
                if (!_is_radix_digit(_at(_position + 1), radix)) {
                    _fail("an underscore must sit between two digits");
                    return false;
                }
                out.append(_text.substr_bytes(start, _position - start));
                _position = _position + 1;
                start = _position;
            } else {
                break;
            }
        }
        out.append(_text.substr_bytes(start, _position - start));
        return true;
    }

    _is_radix_digit(b: byte, radix: ulong): bool {
        var value = _digit_value(b);
        return value >= 0 and (value as ulong) < radix;
    }

    # The value of a hexadecimal digit, or -1.
    _digit_value(b: byte): int {
        if (b >= '0' and b <= '9') {
            return (b - '0') as int;
        }
        if (b >= 'a' and b <= 'f') {
            return (b - 'a') as int + 10;
        }
        if (b >= 'A' and b <= 'F') {
            return (b - 'A') as int + 10;
        }
        return -1;
    }

    _is_digit(b: byte): bool {
        return b >= '0' and b <= '9';
    }

    # ── Dates and times ───────────────────────────────────────────────────

    # Reads an offset or local date-time, a local date or a local time.
    _date_time(): bool {
        var start = _position;
        var value = TomlDateTime();
        if (_at(_position + 2) == ':') {
            value.has_date = false;
            if (!_time(value)) {
                return false;
            }
            _scalar_value = TomlValue.DateTime(value);
            return true;
        }
        value.year = _two_digits(4);
        if (value.year < 0) {
            return false;
        }
        if (!_expect_byte('-')) {
            return false;
        }
        value.month = _two_digits(2);
        if (value.month < 0 or !_expect_byte('-')) {
            return false;
        }
        value.day = _two_digits(2);
        if (value.day < 0) {
            return false;
        }
        if (value.month < 1 or value.month > 12) {
            _fail_at($"month {value.month} is not between 1 and 12", start);
            return false;
        }
        if (value.day < 1 or value.day > _days_in_month(value.year, value.month)) {
            _fail_at($"{_text.substr_bytes(start, 10)} is not a day of the calendar", start);
            return false;
        }
        var b = _peek();
        var time_follows = b == 'T' or b == 't';
        if (b == ' '
            and _is_digit(_at(_position + 1))
            and _is_digit(_at(_position + 2))
            and _at(_position + 3) == ':') {
            time_follows = true;
        }
        if (!time_follows) {
            value.has_time = false;
            _scalar_value = TomlValue.DateTime(value);
            return true;
        }
        _position = _position + 1;
        if (!_time(value)) {
            return false;
        }
        b = _peek();
        if (b == 'Z' or b == 'z') {
            _position = _position + 1;
            value.has_offset = true;
        } else if (b == '+' or b == '-') {
            var offset_start = _position;
            _position = _position + 1;
            var hours = _two_digits(2);
            if (hours < 0 or !_expect_byte(':')) {
                return false;
            }
            var minutes = _two_digits(2);
            if (minutes < 0) {
                return false;
            }
            if (hours > 23 or minutes > 59) {
                _fail_at("invalid offset from UTC", offset_start);
                return false;
            }
            value.has_offset = true;
            value.offset_minutes = (hours * 60 + minutes) * (b == '-' ? -1 : 1);
        }
        _scalar_value = TomlValue.DateTime(value);
        return true;
    }

    # Reads `HH:MM:SS` and an optional fraction into `value`.
    _time(value: TomlDateTime): bool {
        var start = _position;
        value.hour = _two_digits(2);
        if (value.hour < 0 or !_expect_byte(':')) {
            return false;
        }
        value.minute = _two_digits(2);
        if (value.minute < 0 or !_expect_byte(':')) {
            return false;
        }
        value.second = _two_digits(2);
        if (value.second < 0) {
            return false;
        }
        if (value.hour > 23 or value.minute > 59 or value.second > 59) {
            _fail_at($"{_text.substr_bytes(start, 8)} is not a time of day", start);
            return false;
        }
        if (_peek() == '.') {
            _position = _position + 1;
            if (!_is_digit(_peek())) {
                _fail("expected a digit after '.'");
                return false;
            }
            var digits = 0;
            var nanosecond = 0;
            while (_is_digit(_peek())) {
                if (digits < 9) {
                    nanosecond = nanosecond * 10 + (_peek() - '0') as int;
                    digits = digits + 1;
                }
                _position = _position + 1;
            }
            value.fraction_digits = digits;
            while (digits < 9) {
                nanosecond = nanosecond * 10;
                digits = digits + 1;
            }
            value.nanosecond = nanosecond;
        }
        return true;
    }

    # Reads exactly `count` digits as a number, or gives -1 after recording
    # an error.
    _two_digits(count: int): int {
        var value = 0;
        for (var index in 0..count) {
            if (!_is_digit(_peek())) {
                _fail("expected a digit");
                return -1;
            }
            value = value * 10 + (_peek() - '0') as int;
            _position = _position + 1;
        }
        return value;
    }

    _expect_byte(b: byte): bool {
        if (_peek() != b) {
            _fail($"expected '{_byte_text(b)}'");
            return false;
        }
        _position = _position + 1;
        return true;
    }

    _byte_text(b: byte): String {
        var bytes = Array<u8>();
        bytes.append(b as u8);
        return text.Utf8.decode_lossy(bytes);
    }

    _days_in_month(year: int, month: int): int {
        if (month == 2) {
            var leap = (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
            return leap ? 29 : 28;
        }
        if (month == 4 or month == 6 or month == 9 or month == 11) {
            return 30;
        }
        return 31;
    }

    # ── Keys and strings ──────────────────────────────────────────────────

    # Reads a key, dotted or not, into `_keys`.
    _key(): bool {
        _keys = Array<String>();
        while (true) {
            var b = _peek();
            if (b == '"' or b == '\'') {
                if (_at(_position + 1) == b and _at(_position + 2) == b) {
                    _fail("a key cannot be a multi-line string");
                    return false;
                }
                if (!_string()) {
                    return false;
                }
                _keys.append(_string_value);
            } else {
                var start = _position;
                while (_is_bare_key_byte(_peek())) {
                    _position = _position + 1;
                }
                if (_position == start) {
                    _fail("expected a key");
                    return false;
                }
                _keys.append(_text.substr_bytes(start, _position - start));
            }
            _skip_space();
            if (_peek() != '.') {
                return true;
            }
            _position = _position + 1;
            _skip_space();
        }
        return true;
    }

    _is_bare_key_byte(b: byte): bool {
        return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_' or b == '-';
    }

    # Reads a basic, literal, or multi-line string into `_string_value`.
    _string(): bool {
        var quote = _peek();
        var multi_line = _at(_position + 1) == quote and _at(_position + 2) == quote;
        var open = _position;
        _position = _position + (multi_line ? 3 : 1);
        if (multi_line) {
            # A line break right after the opening quotes is not part of the
            # string.
            if (_peek() == '\n') {
                _position = _position + 1;
            } else if (_peek() == '\r' and _at(_position + 1) == '\n') {
                _position = _position + 2;
            }
        }
        var out = StringBuilder();
        var start = _position;
        while (true) {
            if (_position >= _size) {
                _fail_at("unterminated string", open);
                return false;
            }
            var b = _text.byte_at(_position);
            if (b == quote) {
                if (!multi_line) {
                    break;
                }
                # Up to two quotes may come right before the closing three.
                ulong run = 0;
                while (_at(_position + run) == quote) {
                    run = run + 1;
                }
                if (run >= 3) {
                    if (run > 5) {
                        _fail_at("too many quotes at the end of a multi-line string", _position + 5);
                        return false;
                    }
                    _position = _position + run - 3;
                    break;
                }
                _position = _position + run;
                continue;
            }
            if (b == '\\' and quote == '"') {
                out.append(_text.substr_bytes(start, _position - start));
                if (multi_line and _line_ending_backslash()) {
                    start = _position;
                    continue;
                }
                if (!_escape(out)) {
                    return false;
                }
                start = _position;
                continue;
            }
            if (b == '\n' and multi_line) {
                _position = _position + 1;
                continue;
            }
            if (b == '\r' and multi_line and _at(_position + 1) == '\n') {
                out.append(_text.substr_bytes(start, _position - start));
                out.append("\n");
                _position = _position + 2;
                start = _position;
                continue;
            }
            if (b == '\n' or b == '\r') {
                _fail("line break in a string; use '\"\"\"' or ''''' for a multi-line string");
                return false;
            }
            if ((b < 32 and b != '\t') or b == 127) {
                _fail("control character in a string; write it as an escape such as '\\u0001'");
                return false;
            }
            _position = _position + 1;
        }
        out.append(_text.substr_bytes(start, _position - start));
        _position = _position + (multi_line ? 3 : 1);
        _string_value = out.to_string();
        return true;
    }

    # At a `\` in a multi-line basic string: when only spaces follow it on
    # its line, skips it and all the spaces and line breaks after it.
    _line_ending_backslash(): bool {
        var index = _position + 1;
        while (_at(index) == ' ' or _at(index) == '\t') {
            index = index + 1;
        }
        if (_at(index) != '\n' and !(_at(index) == '\r' and _at(index + 1) == '\n')) {
            return false;
        }
        while (true) {
            var b = _at(index);
            if (b == ' ' or b == '\t' or b == '\n') {
                index = index + 1;
            } else if (b == '\r' and _at(index + 1) == '\n') {
                index = index + 2;
            } else {
                break;
            }
        }
        _position = index;
        return true;
    }

    # Decodes the escape at the position, a `\`, onto `out`.
    _escape(out: StringBuilder): bool {
        var start = _position;
        _position = _position + 1;
        var b = _peek();
        _position = _position + 1;
        if (b == '"') {
            out.append("\"");
        } else if (b == '\\') {
            out.append("\\");
        } else if (b == 'n') {
            out.append("\n");
        } else if (b == 't') {
            out.append("\t");
        } else if (b == 'r') {
            out.append("\r");
        } else if (b == 'b') {
            out.append(_byte_text(8));
        } else if (b == 'f') {
            out.append(_byte_text(12));
        } else if (b == 'u' or b == 'U') {
            var count = b == 'u' ? 4 : 8;
            long point = 0;
            for (var index in 0..count) {
                var digit = _digit_value(_peek());
                if (digit < 0) {
                    _fail_at($"'\\{_byte_text(b)}' needs {count} hexadecimal digits", start);
                    return false;
                }
                point = point * 16 + (digit as long);
                _position = _position + 1;
            }
            if (point > 1114111 or (point >= 55296 and point <= 57343)) {
                _fail_at($"'{_text.substr_bytes(start, _position - start)}' is not a Unicode scalar value", start);
                return false;
            }
            var bytes = Array<u8>();
            text.Utf8.append_code_point(bytes, point as uint);
            out.append(text.Utf8.decode_lossy(bytes));
        } else {
            if (_position > _size) {
                _fail_at("unterminated string", start);
            } else {
                _fail_at($"invalid escape '{_text.substr_bytes(start, _position - start)}'", start);
            }
            return false;
        }
        return true;
    }

    # ── Space, comments and line ends ─────────────────────────────────────

    # The byte at `index`, or 0 past the end of the text.
    _at(index: ulong): byte {
        if (index < _size) {
            return _text.byte_at(index);
        }
        return 0;
    }

    # The byte at the position, or 0 at the end of the text.
    _peek(): byte {
        return _at(_position);
    }

    # Skips spaces and tabs.
    _skip_space() {
        while (_position < _size) {
            var b = _text.byte_at(_position);
            if (b != ' ' and b != '\t') {
                return;
            }
            _position = _position + 1;
        }
    }

    # Skips spaces, tabs, line breaks and comments, as an array allows
    # between its elements.
    _skip_array_space(): bool {
        while (true) {
            _skip_space();
            var b = _peek();
            if (b == '\n') {
                _position = _position + 1;
            } else if (b == '\r' and _at(_position + 1) == '\n') {
                _position = _position + 2;
            } else if (b == '#') {
                if (!_comment()) {
                    return false;
                }
            } else {
                return true;
            }
        }
        return true;
    }

    # Skips a comment, from its `#` up to the line break.
    _comment(): bool {
        while (_position < _size) {
            var b = _text.byte_at(_position);
            if (b == '\n' or (b == '\r' and _at(_position + 1) == '\n')) {
                return true;
            }
            if ((b < 32 and b != '\t') or b == 127) {
                _fail("control character in a comment");
                return false;
            }
            _position = _position + 1;
        }
        return true;
    }

    # Skips spaces and a comment, then the line break or the end of the
    # text, failing with `message` when something else comes.
    _end_of_line(message: String): bool {
        _skip_space();
        if (_peek() == '#' and !_comment()) {
            return false;
        }
        return _line_break(message);
    }

    _line_break(message: String): bool {
        var b = _peek();
        if (_position >= _size) {
            return true;
        }
        if (b == '\n') {
            _position = _position + 1;
            return true;
        }
        if (b == '\r' and _at(_position + 1) == '\n') {
            _position = _position + 2;
            return true;
        }
        _fail(message);
        return false;
    }

    _fail(message: String) {
        _fail_at(message, _position);
    }

    # Records the error `message` at byte `offset`, working out its line and
    # column.
    _fail_at(message: String, offset: ulong) {
        _error = TomlError(message, _path);
        _toml_place(_error, _text, offset);
    }
}
