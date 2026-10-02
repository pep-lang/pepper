## `JsonValue`: a JSON value of any kind, and how it is written as text.

import text;

## A JSON value: `null`, a boolean, a number, a string, an array or an
## object. `json.parse` makes one from text and `to_string` writes it back.
##
## Look values up with `value["key"]` and `value[index]`. A lookup that
## finds nothing (a missing key, an index past the end, or a lookup on a
## value of another kind) gives `Null` rather than panicking, so lookups
## chain: `root["server"]["port"]`. Then read the value with an `as_` method,
## which gives none when the value is of another kind, or `match` on its
## case.
##
## Numbers keep the form they were written in: an integer within
## ±(2^53 − 1), the range every JSON implementation agrees on (RFC 7493), is
## an `Integer`; any other number is a `Number`, a `double`.
##
## An `Array` or `Object` case holds its array or map by reference, so
## changing them through `value[key] = ...`, `append` or the map from
## `as_object()` changes every holder of the value.
##
## @example
##     import json;
##
##     var reply = json.JsonValue.object();
##     reply["id"] = json.JsonValue.Integer(42);
##     reply["tags"] = json.JsonValue.array([json.JsonValue.String("a")]);
##     assert(reply.to_string() == "{\"id\":42,\"tags\":[\"a\"]}", "compact");
##     assert(reply["id"].as_int().value() == 42, "a lookup");
##     assert(reply["missing"]["deeper"].is_null(), "lookups chain");
export enum JsonValue {
    ## JSON's `null`, and what a lookup gives when it finds nothing.
    Null,
    ## `true` or `false`.
    ##
    ## @param value the boolean
    Bool(value: bool),
    ## A number written without a fraction or an exponent, within
    ## ±(2^53 − 1).
    ##
    ## @param value the integer
    Integer(value: long),
    ## Any other number: one with a fraction or an exponent, or an integer
    ## outside ±(2^53 − 1).
    ##
    ## @param value the number
    Number(value: double),
    ## A string.
    ##
    ## @param value the text
    String(value: String),
    ## An array, holding its elements in order.
    ##
    ## @param items the elements
    Array(items: Array<JsonValue>),
    ## An object, holding its members in insertion order: the order the
    ## text or the code wrote them, so a document round-trips unchanged.
    ##
    ## @param members the members, by key
    Object(members: OrderedMap<String, JsonValue>),

    ## Returns a new, empty object.
    ##
    ## @returns an `Object` with no members
    ## @example
    ##     import json;
    ##
    ##     var config = json.JsonValue.object();
    ##     config["name"] = json.JsonValue.String("pepper");
    static object(): JsonValue {
        return JsonValue.Object(OrderedMap<String, JsonValue>());
    }

    ## Returns an array holding `items`, which it keeps by reference rather
    ## than copying.
    ##
    ## @param items the elements; an empty array when not given
    ## @returns an `Array` of `items`
    ## @example
    ##     import json;
    ##
    ##     var list = json.JsonValue.array([json.JsonValue.Integer(1)]);
    ##     list.append(json.JsonValue.Integer(2));
    ##     assert(list.to_string() == "[1,2]", "two elements");
    static array(items: Array<JsonValue> = Array<JsonValue>()): JsonValue {
        return JsonValue.Array(items);
    }

    ## Reads `value[key]`: the member named `key` of an object.
    ##
    ## @param key the member's key
    ## @returns the member, or `Null` when this is not an object or has no
    ##   member named `key`
    [](key: String): JsonValue {
        if (this is Object(members)) {
            var found = members.try_get(key);
            if (found.is_value()) {
                return found.value();
            }
        }
        return JsonValue.Null;
    }

    ## Writes `value[key] = member`: sets the member named `key` of an
    ## object. A new key goes at the end; an existing key keeps its place.
    ##
    ## @param key the member's key
    ## @param member the value to store
    ## @returns `member`, the value of the assignment expression
    ## @panics if this is not an object ("JsonValue[key] = value needs an
    ##   object")
    [](key: String, member: JsonValue): JsonValue {
        if (this is Object(members)) {
            members[key] = member;
            return member;
        }
        panic($"JsonValue[key] = value needs an object, not '{name()}'");
        return member;
    }

    ## Reads `value[index]`: an element of an array.
    ##
    ## @param index the element's position, from 0
    ## @returns the element, or `Null` when this is not an array or `index`
    ##   is not less than its count
    [](index: ulong): JsonValue {
        if (this is Array(items)) {
            if (index < items.count) {
                return items[index];
            }
        }
        return JsonValue.Null;
    }

    ## Writes `value[index] = element`: replaces an element of an array.
    ##
    ## @param index the element's position, from 0
    ## @param element the value to store
    ## @returns `element`, the value of the assignment expression
    ## @panics if this is not an array ("JsonValue[index] = value needs an
    ##   array")
    ## @panics if `index` is not less than the array's count (as
    ##   `Array`'s indexer does)
    [](index: ulong, element: JsonValue): JsonValue {
        if (this is Array(items)) {
            items[index] = element;
            return element;
        }
        panic($"JsonValue[index] = value needs an array, not '{name()}'");
        return element;
    }

    ## Appends `element` to the end of an array.
    ##
    ## @param element the value to append
    ## @panics if this is not an array ("JsonValue.append needs an array")
    append(element: JsonValue) {
        if (this is Array(items)) {
            items.append(element);
            return;
        }
        panic($"JsonValue.append needs an array, not '{name()}'");
    }

    ## Returns whether this is an object with a member named `key`.
    ##
    ## @param key the key to look for
    ## @returns true when the member exists, even if its value is `Null`
    contains(key: String): bool {
        if (this is Object(members)) {
            return members.contains(key);
        }
        return false;
    }

    ## Removes the member named `key` from an object.
    ##
    ## @param key the key to remove
    ## @returns true when this is an object and the member was there
    remove(key: String): bool {
        if (this is Object(members)) {
            return members.remove(key);
        }
        return false;
    }

    ## Returns whether this is `Null`, which is also what a lookup that finds
    ## nothing gives.
    ##
    ## @returns true for `Null`
    is_null(): bool {
        return this is Null;
    }

    ## Returns the boolean, when this is one.
    ##
    ## @returns the value of a `Bool`, or none
    as_bool(): bool? {
        if (this is Bool(value)) {
            return Optional<bool>.Value(value);
        }
        return Optional<bool>.Empty;
    }

    ## Returns the number as an integer, when it is one: an `Integer`, or a
    ## `Number` with no fraction that fits in a `long` (`2.0`, `1e3`).
    ##
    ## @returns the integer, or none
    ## @example
    ##     import json;
    ##
    ##     assert(json.parse("1e3").value().as_int().value() == 1000, "no fraction");
    ##     assert(json.parse("1.5").value().as_int().is_empty(), "a fraction");
    as_int(): long? {
        match (this) {
            Integer(value) => { return Optional<long>.Value(value); }
            Number(value) => {
                # 2^63 is the first double past the end of a long.
                if (value >= -9223372036854775808.0 and value < 9223372036854775808.0) {
                    var whole = value as long;
                    if ((whole as double) == value) {
                        return Optional<long>.Value(whole);
                    }
                }
            }
            else => {}
        }
        return Optional<long>.Empty;
    }

    ## Returns the number as a `double`, when this is an `Integer` or a
    ## `Number`.
    ##
    ## @returns the number, or none
    as_double(): double? {
        match (this) {
            Integer(value) => { return Optional<double>.Value(value as double); }
            Number(value) => { return Optional<double>.Value(value); }
            else => {}
        }
        return Optional<double>.Empty;
    }

    ## Returns the string, when this is one.
    ##
    ## @returns the text of a `String`, or none
    as_string(): String? {
        if (this is String(value)) {
            return Optional<String>.Value(value);
        }
        return Optional<String>.Empty;
    }

    ## Returns the elements, when this is an array. The array is the one
    ## this value holds, not a copy.
    ##
    ## @returns the elements of an `Array`, or none
    as_array(): Array<JsonValue>? {
        if (this is Array(items)) {
            return Optional<Array<JsonValue>>.Value(items);
        }
        return Optional<Array<JsonValue>>.Empty;
    }

    ## Returns the members, when this is an object. The map is the one this
    ## value holds, not a copy.
    ##
    ## @returns the members of an `Object`, or none
    as_object(): OrderedMap<String, JsonValue>? {
        if (this is Object(members)) {
            return Optional<OrderedMap<String, JsonValue>>.Value(members);
        }
        return Optional<OrderedMap<String, JsonValue>>.Empty;
    }

    ## Returns the value as compact JSON text, with no spaces or line
    ## breaks: `{"id":42,"tags":["a","b"]}`.
    ##
    ## Strings are written as UTF-8, escaping `"`, `\` and the control
    ## characters. A `Number` that is not finite (NaN or an infinity, which
    ## JSON cannot spell) is written as `null`.
    ##
    ## @returns the JSON text
    to_string(): String {
        return _json_write(this, 0, false);
    }

    ## Returns the value as compact JSON text, like `to_string()`, choosing
    ## whether to escape every character outside ASCII as `\u` (a pair of
    ## them past U+FFFF), so the text is plain ASCII.
    ##
    ## @param ascii_only whether to escape every non-ASCII character
    ## @returns the JSON text
    ## @example
    ##     import json;
    ##
    ##     var word = json.JsonValue.String("é");
    ##     assert(word.to_string(ascii_only = true) == "\"\\u00e9\"", "escaped");
    to_string(ascii_only: bool): String {
        return _json_write(this, 0, ascii_only);
    }

    ## Returns the value as indented JSON text: each element and member on
    ## its own line, indented `indent` spaces per level, with a space after
    ## each `:`. An empty array or object stays `[]` or `{}`.
    ##
    ## @param indent the number of spaces per level of nesting
    ## @param ascii_only whether to escape every non-ASCII character as `\u`
    ## @returns the JSON text, without a final line break
    ## @panics if `indent` is negative ("JsonValue.to_pretty_string needs a
    ##   non-negative indent")
    ## @example
    ##     import json;
    ##
    ##     var list = json.JsonValue.array([json.JsonValue.Integer(1)]);
    ##     assert(list.to_pretty_string() == "[\n  1\n]", "two spaces");
    to_pretty_string(indent: int = 2, ascii_only: bool = false): String {
        assert(indent >= 0, "JsonValue.to_pretty_string needs a non-negative indent");
        return _json_write(this, indent + 1, ascii_only);
    }
}

# A step of `_json_write`: a value still to write at a nesting depth, an
# object member's key to write before its value (after a comma unless it is
# the first), the comma before an array's element, or the closing bracket
# of a container. With comments to keep, each step also carries the paths
# their comments are filed under (empty otherwise): the value's (`lead` when
# its comments go before it, false for a member's value, whose key has
# them), the member or element before a comma, and a container and its
# last element.
[Value]
enum _JsonStep {
    Write(value: JsonValue, depth: ulong, path: String, lead: bool),
    Key(key: String, depth: ulong, first: bool, path: String, previous: String),
    Comma(depth: ulong, previous: String),
    Close(bracket: String, depth: ulong, container: String, last: String),
}

# Writes `root` as JSON text. `layout` is 0 for compact text, or one more
# than the number of spaces per level for indented text.
_json_write(root: JsonValue, layout: int, ascii_only: bool): String {
    var writer = _JsonWriter(layout, ascii_only);
    writer.write(root);
    return writer.out.to_string();
}

# Writes `root` as indented JSON text with the comments in `notes`, each
# where its path says. `layout` is as for `_json_write`, and not 0.
export _json_write_commented(root: JsonValue, notes: _JsonComments, layout: int, ascii_only: bool): String {
    var writer = _JsonWriter(layout, ascii_only);
    writer._notes = Optional<_JsonComments>.Value(notes);
    writer.write(root);
    return writer.out.to_string();
}

# The comments of a JSONC document, filed by the path of the value they
# belong to (`$.server.port`, as `_json_path_key` writes it): those on the
# lines before it (`before`), those after it on its own line (`after`), and
# those before a container's closing bracket (`end`, by the container's
# path, with "" for those after the whole document). Each comment is its
# text, `//` or `/* */` included.
export struct _JsonComments {
    HashMap<String, Array<String>> before;
    HashMap<String, Array<String>> after;
    HashMap<String, Array<String>> end;

    construct() {
        before = HashMap<String, Array<String>>();
        after = HashMap<String, Array<String>>();
        end = HashMap<String, Array<String>>();
    }

    # Files `comments` under `path` in `kind`, after those already there.
    add(kind: HashMap<String, Array<String>>, path: String, comments: Array<String>) {
        if (comments.is_empty) {
            return;
        }
        var filed = kind.try_get(path);
        if (filed.is_value()) {
            for (var comment in comments) {
                filed.value().append(comment);
            }
        } else {
            var copy = Array<String>();
            for (var comment in comments) {
                copy.append(comment);
            }
            kind.insert(path, copy);
        }
    }
}

# `path.key`, or `path["key"]` when the key is not an identifier: how a
# value's path in a document is written.
export _json_path_key(path: String, key: String): String {
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
    return $"{path}[{JsonValue.String(key).to_string()}]";
}

# Writes JSON text into `out`. A string literal makes a new String each time
# it runs, so the punctuation lives in fields, made once.
struct _JsonWriter {
    StringBuilder out;
    bool _pretty;
    ulong _spaces;
    bool _ascii_only;
    # The line break and indentation before an element at each depth, and
    # the same after a comma.
    Array<String> _indents;
    Array<String> _commas;
    String _quote;
    String _null;
    String _true;
    String _false;
    String _colon;
    String _open_array;
    String _close_array;
    String _empty_array;
    String _open_object;
    String _close_object;
    String _empty_object;
    # The comments to write, for `_json_write_commented`.
    _JsonComments? _notes;
    String _space;
    String _comma;
    String _no_path;

    construct(layout: int, ascii_only: bool) {
        out = StringBuilder();
        _pretty = layout > 0;
        _spaces = _pretty ? (layout - 1) as ulong : 0;
        _ascii_only = ascii_only;
        _indents = Array<String>();
        _commas = Array<String>();
        _quote = "\"";
        _null = "null";
        _true = "true";
        _false = "false";
        _colon = _pretty ? ": " : ":";
        _open_array = "[";
        _close_array = "]";
        _empty_array = "[]";
        _open_object = "{";
        _close_object = "}";
        _empty_object = "{}";
        _notes = Optional<_JsonComments>.Empty;
        _space = " ";
        _comma = ",";
        _no_path = "";
    }

    # Writes the comments filed under `path` in `kind`: each followed by
    # the indentation at `depth` (`before`), or each after a space.
    _comments(kind: HashMap<String, Array<String>>, path: String, depth: ulong, leading: bool) {
        var filed = kind.try_get(path);
        if (filed.is_empty()) {
            return;
        }
        for (var comment in filed.value()) {
            if (leading) {
                out.append(comment);
                out.append(_indents[depth]);
            } else {
                out.append(_space);
                out.append(comment);
            }
        }
    }

    # Whether a container at `path` has comments before its closing
    # bracket, so it is not written as `[]` or `{}`.
    _has_end(path: String): bool {
        return _notes.is_value() && _notes.value().end.contains(path);
    }

    # Writes the comments before the closing bracket of the container at
    # `path`, each on its own line at `depth`.
    _end_comments(path: String, depth: ulong) {
        var filed = _notes.value().end.try_get(path);
        if (filed.is_empty()) {
            return;
        }
        _reach(depth);
        for (var comment in filed.value()) {
            out.append(_indents[depth]);
            out.append(comment);
        }
    }

    # Makes sure `_indents` and `_commas` reach `depth`.
    _reach(depth: ulong) {
        while (_indents.count <= depth) {
            var indent = _pretty ? "\n" + " ".repeat(_indents.count * _spaces) : "";
            _indents.append(indent);
            _commas.append("," + indent);
        }
    }

    # Nesting comes from the data, so the steps still to take live on an
    # explicit stack rather than the call stack: each container pushes its
    # closing bracket, then its elements in reverse.
    write(root: JsonValue) {
        var keeping = _notes.is_value();
        var root_path = keeping ? "$" : _no_path;
        var steps = Array<_JsonStep>();
        steps.append(_JsonStep.Write(root, 0, root_path, true));
        while (!steps.is_empty) {
            var step = steps.pop();
            match (step) {
                Close(bracket, at, container, last) => {
                    _reach(at + 1);
                    if (keeping) {
                        _comments(_notes.value().after, last, at, false);
                        _end_comments(container, at + 1);
                    }
                    out.append(_indents[at]);
                    out.append(bracket);
                }
                Comma(at, previous) => {
                    _reach(at);
                    if (keeping) {
                        out.append(_comma);
                        _comments(_notes.value().after, previous, at, false);
                        out.append(_indents[at]);
                    } else {
                        out.append(_commas[at]);
                    }
                }
                Key(key, at, first, path, previous) => {
                    _reach(at);
                    if (keeping) {
                        if (!first) {
                            out.append(_comma);
                            _comments(_notes.value().after, previous, at, false);
                        }
                        out.append(_indents[at]);
                        _comments(_notes.value().before, path, at, true);
                    } else {
                        out.append(first ? _indents[at] : _commas[at]);
                    }
                    quote(key);
                    out.append(_colon);
                }
                Write(value, at, path, lead) => {
                    if (keeping && lead) {
                        _reach(at);
                        _comments(_notes.value().before, path, at, true);
                    }
                    match (value) {
                        Null => {
                            out.append(_null);
                        }
                        Bool(flag) => {
                            out.append(flag ? _true : _false);
                        }
                        Integer(number) => {
                            out.append($"{number}");
                        }
                        Number(number) => {
                            # NaN and the infinities are not JSON; NaN
                            # differs from itself and an infinity minus
                            # itself is NaN.
                            if (number - number != 0.0) {
                                out.append(_null);
                            } else {
                                out.append($"{number}");
                            }
                        }
                        String(text) => {
                            quote(text);
                        }
                        Array(items) => {
                            if (items.is_empty && !_has_end(path)) {
                                out.append(_empty_array);
                            } else if (items.is_empty) {
                                out.append(_open_array);
                                steps.append(_JsonStep.Close(_close_array, at, path, _no_path));
                            } else {
                                # The first element follows at once; each
                                # other one follows its comma.
                                _reach(at + 1);
                                out.append(_open_array);
                                out.append(_indents[at + 1]);
                                var index = items.count;
                                var last = keeping ? $"{path}[{index - 1}]" : _no_path;
                                steps.append(_JsonStep.Close(_close_array, at, path, last));
                                while (index > 1) {
                                    index = index - 1;
                                    var element = keeping ? $"{path}[{index}]" : _no_path;
                                    var before = keeping ? $"{path}[{index - 1}]" : _no_path;
                                    steps.append(_JsonStep.Write(items[index], at + 1, element, true));
                                    steps.append(_JsonStep.Comma(at + 1, before));
                                }
                                var first = keeping ? $"{path}[0]" : _no_path;
                                steps.append(_JsonStep.Write(items[0], at + 1, first, true));
                            }
                        }
                        Object(members) => {
                            if (members.is_empty && !_has_end(path)) {
                                out.append(_empty_object);
                            } else {
                                out.append(_open_object);
                                # The closing bracket's last member is known
                                # once the members are pushed.
                                var close = steps.count;
                                steps.append(_JsonStep.Close(_close_object, at, path, _no_path));
                                # Push the members, then reverse them, so
                                # the first is written first.
                                var low = steps.count;
                                var first = true;
                                var last = _no_path;
                                for (var (key, member) in members) {
                                    var at_key = keeping ? _json_path_key(path, key) : _no_path;
                                    steps.append(_JsonStep.Key(key, at + 1, first, at_key, last));
                                    steps.append(_JsonStep.Write(member, at + 1, at_key, false));
                                    first = false;
                                    last = at_key;
                                }
                                var high = steps.count - 1;
                                while (low < high) {
                                    steps.swap(low, high);
                                    low = low + 1;
                                    high = high - 1;
                                }
                                if (keeping) {
                                    steps[close] = _JsonStep.Close(_close_object, at, path, last);
                                }
                            }
                        }
                    }
                }
            }
        }
        if (keeping) {
            _comments(_notes.value().after, root_path, 0, false);
            _end_comments("", 0);
        }
    }

    # Appends `value` as a JSON string in double quotes, escaping `"`, `\`
    # and the control characters, and with `_ascii_only` everything past
    # ASCII. Runs of bytes that need no escape are copied whole.
    quote(value: String) {
        out.append(_quote);
        var size = value.size;
        ulong start = 0;
        ulong index = 0;
        while (index < size) {
            var b = value.byte_at(index);
            if (b >= 32 and b != '"' and b != '\\' and (b < 128 or !_ascii_only)) {
                index = index + 1;
                continue;
            }
            if (index > start) {
                out.append(value.substr_bytes(start, index - start));
            }
            var run: ulong = 1;
            if (b >= 128) {
                var (point, length) = text.Utf8.code_point_at(value, index);
                run = length;
                if (point >= 65536) {
                    var rest = point - 65536;
                    out.append(_json_unit(55296 + (rest >> 10)));
                    out.append(_json_unit(56320 + (rest & 1023)));
                } else {
                    out.append(_json_unit(point));
                }
            } else {
                out.append(_json_escape(b));
            }
            index = index + run;
            start = index;
        }
        if (start == 0) {
            out.append(value);
        } else if (size > start) {
            out.append(value.substr_bytes(start, size - start));
        }
        out.append(_quote);
    }
}

# The escape for the ASCII byte `b`: `"`, `\` or a control character.
_json_escape(b: byte): String {
    if (b == '"') {
        return "\\\"";
    } else if (b == '\\') {
        return "\\\\";
    } else if (b == '\n') {
        return "\\n";
    } else if (b == '\r') {
        return "\\r";
    } else if (b == '\t') {
        return "\\t";
    } else if (b == 8) {
        return "\\b";
    } else if (b == 12) {
        return "\\f";
    }
    return _json_unit(b as uint);
}

# The escape `\uXXXX` for the UTF-16 code unit `unit`.
_json_unit(unit: uint): String {
    return $"\\u{unit:04x}";
}
