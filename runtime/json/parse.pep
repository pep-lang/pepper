## `parse`: reading JSON text into a `JsonValue`, and `JsonError`, what it
## reports when the text is not JSON.

import text;
import "value";

## What `parse` reports when the text is not JSON: what is wrong, and the
## line and column where it is.
##
## `to_string()` renders it like a compiler error:
## `config.json:3:17: error: expected ',' or '}'`.
export struct JsonError {
    ## What is wrong, worded like a compiler error (`expected ':'`).
    var message: String;
    ## The path given to `parse`, which names the text in `to_string()`;
    ## empty when none was given.
    var path: String;
    ## The line of the error, from 1; 0 for an error from `from_json`, which
    ## has no text to point into.
    var line: ulong;
    ## The column of the error, from 1, counting bytes as clang does; 0
    ## when `line` is.
    var column: ulong;
    ## The byte offset of the error in the text, from 0.
    var offset: ulong;
    ## Where in the document the value an error is about is, as a path from
    ## the root `$` (`$.server.port`); empty for an error in the text's
    ## syntax. `decode` and `from_json` set it, and start `message` with it.
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

## Parses JSON text into a `JsonValue`.
##
## Parsing is strict RFC 8259: one value, surrounded only by spaces, tabs
## and line breaks. A byte-order mark at the start is skipped. The text
## must be valid UTF-8, and a string cannot hold a raw control character
## or a `\u` escape of an unpaired surrogate (`"\uD800"`). When an object
## repeats a key, the last value wins, in the place of the first.
##
## With `comments = true` the text may be JSONC, as VS Code's settings
## files are: `//` line comments, `/* */` block comments, and a trailing
## comma after the last element or member. The comments are skipped.
##
## Nesting comes from the text, so the parser keeps its own stack rather
## than recursing, and `max_depth` bounds it.
##
## @param text the JSON text
## @param comments whether to accept comments and trailing commas
## @param path the name of the text (a file name, say), which the error's
##   `to_string()` puts first
## @param max_depth how deeply arrays and objects may nest
## @returns the value, or an error naming the first problem and its line
##   and column
## @example
##     import json;
##
##     var parsed = json.parse("{\"server\": {\"port\": 8080}}");
##     assert(parsed.value()["server"]["port"].as_int().value() == 8080, "a lookup");
##     var bad = json.parse("[1 2]", path = "list.json");
##     assert(bad.error().to_string() == "list.json:1:4: error: expected ',' or ']'", "where");
export parse(
    text: String, comments: bool = false, path: String = "", max_depth: ulong = 1000
): Result<JsonValue, JsonError> {
    var parser = _JsonParser(text, comments, path, max_depth);
    return parser.run();
}

# Parses JSONC `text` like `parse` with `comments = true`, filing its
# comments in `notes`.
export _json_parse_commented(
    text: String, notes: _JsonComments, path: String, max_depth: ulong
): Result<JsonValue, JsonError> {
    var parser = _JsonParser(text, true, path, max_depth);
    parser._notes = Optional<_JsonComments>.Value(notes);
    return parser.run();
}

# The byte offset in `text`, which must parse, of the value at `value_path`
# (`$.server.port`, as `_json_path_key` writes it), or none when it is not
# there. Parses the text again, so it is only for errors.
export _json_locate(text: String, comments: bool, value_path: String): ulong? {
    var parser = _JsonParser(text, comments, "", 1000000);
    parser._find = value_path;
    parser.run();
    if (parser._found >= 0) {
        return Optional<ulong>.Value(parser._found as ulong);
    }
    return Optional<ulong>.Empty;
}

# Reads one value from `_text`. Each method that can fail returns false
# after recording the first error in `_error`.
struct _JsonParser {
    String _text;
    ulong _size;
    ulong _position;
    bool _comments;
    String _path;
    ulong _max_depth;
    JsonError _error;
    # The value the last `_scalar` or `_string` read.
    JsonValue _scalar_value;
    String _string_value;
    # A string literal makes a new String each time it runs, so the words
    # live in fields, made once.
    String _true;
    String _false;
    String _null;
    String _no_key;
    # With `_json_locate`: the path of the value to find, and its offset
    # once found (-1 until then).
    String _find;
    long _found;
    # With `_json_parse_commented`: where the comments go, the comments
    # read since the last value was filed, whether each began on the line
    # the last value ended on, and whether a line break came since then.
    _JsonComments? _notes;
    Array<String> _pending;
    Array<bool> _inline;
    bool _newline;

    construct(text: String, comments: bool, path: String, max_depth: ulong) {
        _text = text;
        _size = text.size;
        _comments = comments;
        _path = path;
        _max_depth = max_depth;
        _true = "true";
        _false = "false";
        _null = "null";
        _no_key = "";
        _find = "";
        _found = -1;
        _notes = Optional<_JsonComments>.Empty;
        _pending = Array<String>();
        _inline = Array<bool>();
        _newline = false;
    }

    # Files the comments read since the last value under `path` in `kind`,
    # only those on the last value's line when `inline_only`.
    _file(kind: HashMap<String, Array<String>>, path: String, inline_only: bool) {
        if (_pending.is_empty) {
            return;
        }
        var filed = Array<String>();
        var rest = Array<String>();
        var rest_inline = Array<bool>();
        for (var index in 0.._pending.count) {
            if (!inline_only || _inline[index]) {
                filed.append(_pending[index]);
            } else {
                rest.append(_pending[index]);
                rest_inline.append(false);
            }
        }
        _notes.value().add(kind, path, filed);
        _pending = rest;
        _inline = rest_inline;
    }

    run(): Result<JsonValue, JsonError> {
        if (_size >= 3 and _text.byte_at(0) == 239 and _text.byte_at(1) == 187 and _text.byte_at(2) == 191) {
            _position = 3;
        }
        var invalid = text.Utf8.find_invalid(_text);
        if (invalid.is_value()) {
            _fail_at("invalid UTF-8", invalid.value());
            return Result<JsonValue, JsonError>.err(_error);
        }
        var value = _parse();
        if (value.is_empty()) {
            return Result<JsonValue, JsonError>.err(_error);
        }
        return Result<JsonValue, JsonError>.ok(value.value());
    }

    # The parse loop. Each container still open is on `containers`, with
    # the key of the member being read on `keys` ("" for an array).
    _parse(): JsonValue? {
        var none = Optional<JsonValue>.Empty;
        var containers = Array<JsonValue>();
        var keys = Array<String>();
        # With `_find` or `_notes`: each open container's path, and each
        # array's index.
        var keeping = _notes.is_value();
        var tracking = keeping || !_find.is_empty;
        var paths = Array<String>();
        var indexes = Array<ulong>();
        var here = "$";
        while (true) {
            # Read a value, or open a container.
            if (!_skip_space()) {
                return none;
            }
            if (tracking) {
                if (containers.is_empty) {
                    here = "$";
                } else if (containers.last() is Array) {
                    here = $"{paths.last()}[{indexes.last()}]";
                } else {
                    here = _json_path_key(paths.last(), keys.last());
                }
                if (here == _find) {
                    _found = _position as long;
                    return none;
                }
                if (keeping) {
                    _file(_notes.value().before, here, false);
                }
            }
            var value = JsonValue.Null;
            var b = _peek();
            if (b == '[' or b == '{') {
                if (containers.count >= _max_depth) {
                    _fail($"arrays and objects nest more than {_max_depth} deep");
                    return none;
                }
                _position = _position + 1;
                var opened = b == '[' ? JsonValue.array() : JsonValue.object();
                if (!_skip_space()) {
                    return none;
                }
                if (_peek() == (b == '[' ? ']' : '}')) {
                    if (keeping) {
                        _file(_notes.value().end, here, false);
                    }
                    _position = _position + 1;
                    value = opened;
                } else {
                    containers.append(opened);
                    if (tracking) {
                        paths.append(here);
                        indexes.append(0);
                    }
                    if (b == '{') {
                        if (!_key()) {
                            return none;
                        }
                        keys.append(_string_value);
                    } else {
                        keys.append(_no_key);
                    }
                    continue;
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
                _newline = false;
                if (containers.is_empty) {
                    if (!_skip_space()) {
                        return none;
                    }
                    if (_position < _size) {
                        _fail("expected the end of the text after the value");
                        return none;
                    }
                    if (keeping) {
                        _file(_notes.value().after, "$", true);
                        _file(_notes.value().end, "", false);
                    }
                    return Optional<JsonValue>.Value(value);
                }
                var top = containers.last();
                var is_array = top is Array;
                # The path of the value just read, for its comments.
                var stored = _no_key;
                if (top is Array(items)) {
                    items.append(value);
                    if (tracking) {
                        if (keeping) {
                            stored = $"{paths.last()}[{indexes.last()}]";
                        }
                        indexes[indexes.count - 1] = indexes.last() + 1;
                    }
                } else if (top is Object(members)) {
                    members[keys.last()] = value;
                    if (keeping) {
                        stored = _json_path_key(paths.last(), keys.last());
                    }
                }
                if (!_skip_space()) {
                    return none;
                }
                byte closing = is_array ? ']' : '}';
                var next = _peek();
                if (next == ',') {
                    var comma = _position;
                    _position = _position + 1;
                    if (!_skip_space()) {
                        return none;
                    }
                    if (keeping) {
                        _file(_notes.value().after, stored, true);
                    }
                    if (_peek() == closing) {
                        if (!_comments) {
                            _fail_at(
                                "trailing comma is not allowed; parse with 'comments = true' to accept JSONC", comma
                            );
                            return none;
                        }
                    } else {
                        if (!is_array) {
                            if (!_key()) {
                                return none;
                            }
                            keys[keys.count - 1] = _string_value;
                        }
                        break;
                    }
                } else if (next != closing) {
                    _fail(is_array ? "expected ',' or ']'" : "expected ',' or '}'");
                    return none;
                }
                if (keeping) {
                    _file(_notes.value().after, stored, true);
                    _file(_notes.value().end, paths.last(), false);
                }
                _position = _position + 1;
                value = containers.pop();
                keys.pop();
                if (tracking) {
                    paths.pop();
                    indexes.pop();
                }
            }
        }
        return none;
    }

    # The byte at the position, or 0 at the end of the text.
    _peek(): byte {
        if (_position < _size) {
            return _text.byte_at(_position);
        }
        return 0;
    }

    # Skips spaces, tabs and line breaks, and with `_comments` the comments
    # among them. Fails only on a comment that is not allowed or not closed.
    _skip_space(): bool {
        while (_position < _size) {
            var b = _text.byte_at(_position);
            if (b == ' ' or b == '\t' or b == '\n' or b == '\r') {
                if (b == '\n') {
                    _newline = true;
                }
                _position = _position + 1;
            } else if (b == '/'
                and _position + 1 < _size
                and (_text.byte_at(_position + 1) == '/' or _text.byte_at(_position + 1) == '*')) {
                if (!_comments) {
                    _fail("comments are not allowed; parse with 'comments = true' to accept JSONC");
                    return false;
                }
                var start = _position;
                if (_text.byte_at(_position + 1) == '/') {
                    while (_position < _size and _text.byte_at(_position) != '\n') {
                        _position = _position + 1;
                    }
                } else {
                    var end = _text.find("*/", _position + 2);
                    if (end < 0) {
                        _fail_at("unterminated '/*' comment", start);
                        return false;
                    }
                    _position = (end as ulong) + 2;
                }
                if (_notes.is_value()) {
                    var size = _position - start;
                    if (_text.byte_at(_position - 1) == '\r') {
                        size = size - 1;
                    }
                    _pending.append(_text.substr_bytes(start, size));
                    _inline.append(!_newline);
                }
            } else {
                return true;
            }
        }
        return true;
    }

    # Reads an object member's key and the ':' after it into `_string_value`.
    _key(): bool {
        if (_peek() != '"') {
            _fail("expected a member name in double quotes");
            return false;
        }
        if (!_string()) {
            return false;
        }
        if (!_skip_space()) {
            return false;
        }
        if (_peek() != ':') {
            _fail("expected ':'");
            return false;
        }
        _position = _position + 1;
        return true;
    }

    # Reads a value that is not an array or object into `_scalar_value`.
    _scalar(): bool {
        var b = _peek();
        if (b == '"') {
            if (!_string()) {
                return false;
            }
            _scalar_value = JsonValue.String(_string_value);
            return true;
        }
        if (b == '-' or (b >= '0' and b <= '9')) {
            return _number();
        }
        if (_word(_true)) {
            _scalar_value = JsonValue.Bool(true);
            return true;
        }
        if (_word(_false)) {
            _scalar_value = JsonValue.Bool(false);
            return true;
        }
        if (_word(_null)) {
            _scalar_value = JsonValue.Null;
            return true;
        }
        if (_position >= _size) {
            _fail("expected a value");
        } else if (b == ']' or b == '}') {
            _fail($"expected a value before '{_text.substr_bytes(_position, 1)}'");
        } else {
            _fail("expected a value");
        }
        return false;
    }

    # Consumes `word` when the text continues with it and no letter or
    # digit follows.
    _word(word: String): bool {
        var size = word.size;
        if (_position + size > _size) {
            return false;
        }
        ulong index = 0;
        while (index < size) {
            if (_text.byte_at(_position + index) != word.byte_at(index)) {
                return false;
            }
            index = index + 1;
        }
        if (_position + size < _size) {
            var after = _text.byte_at(_position + size);
            if ((after >= 'a' and after <= 'z') or (after >= 'A' and after <= 'Z') or (after >= '0' and after <= '9')) {
                return false;
            }
        }
        _position = _position + size;
        return true;
    }

    # Reads a number: `-`, then `0` or digits not starting with `0`, then an
    # optional fraction and exponent, each with at least one digit.
    _number(): bool {
        var start = _position;
        var whole = true;
        if (_peek() == '-') {
            _position = _position + 1;
        }
        if (_peek() == '0') {
            _position = _position + 1;
            if (_peek().is_digit()) {
                _fail("a number cannot start with '0'");
                return false;
            }
        } else if (!_digits()) {
            return false;
        }
        if (_peek() == '.') {
            whole = false;
            _position = _position + 1;
            if (!_digits()) {
                return false;
            }
        }
        if (_peek() == 'e' or _peek() == 'E') {
            whole = false;
            _position = _position + 1;
            if (_peek() == '+' or _peek() == '-') {
                _position = _position + 1;
            }
            if (!_digits()) {
                return false;
            }
        }
        var spelled = _text.substr_bytes(start, _position - start);
        if (whole) {
            # 2^53 - 1, the largest integer every JSON reader agrees on.
            var parsed = long.parse(spelled);
            if (parsed.is_value() and parsed.value() <= 9007199254740991 and parsed.value() >= -9007199254740991) {
                _scalar_value = JsonValue.Integer(parsed.value());
                return true;
            }
        }
        var number = double.parse(spelled);
        if (number.is_empty()) {
            _fail_at("number is too large for a double", start);
            return false;
        }
        _scalar_value = JsonValue.Number(number.value());
        return true;
    }

    # Consumes one or more digits.
    _digits(): bool {
        if (!_peek().is_digit()) {
            _fail("expected a digit");
            return false;
        }
        while (_peek().is_digit()) {
            _position = _position + 1;
        }
        return true;
    }

    # Reads a string, starting at its opening '"', into `_string_value`.
    # Text without escapes is copied whole; escapes decode into bytes.
    _string(): bool {
        var open = _position;
        _position = _position + 1;
        var start = _position;
        Array<u8> decoded = __null;
        while (true) {
            if (_position >= _size) {
                _fail_at("unterminated string", open);
                return false;
            }
            var b = _text.byte_at(_position);
            if (b == '"') {
                break;
            }
            if (b < 32) {
                _fail("control character in a string; write it as an escape such as '\\n'");
                return false;
            }
            if (b != '\\') {
                _position = _position + 1;
                continue;
            }
            if (decoded === __null) {
                decoded = Array<u8>();
            }
            _append_bytes(decoded, start, _position);
            if (!_escape(decoded)) {
                return false;
            }
            start = _position;
        }
        if (decoded === __null) {
            _string_value = _text.substr_bytes(start, _position - start);
        } else {
            _append_bytes(decoded, start, _position);
            _string_value = text.Utf8.decode_lossy(decoded);
        }
        _position = _position + 1;
        return true;
    }

    # Appends the bytes of `_text` from `start` up to `end` to `out`.
    _append_bytes(out: u8[], start: ulong, end: ulong) {
        var index = start;
        while (index < end) {
            out.append(_text.byte_at(index) as u8);
            index = index + 1;
        }
    }

    # Decodes the escape at the position, a '\', onto `out`.
    _escape(out: u8[]): bool {
        var start = _position;
        _position = _position + 1;
        var b = _peek();
        _position = _position + 1;
        if (b == '"' or b == '\\' or b == '/') {
            out.append(b as u8);
        } else if (b == 'n') {
            out.append(10);
        } else if (b == 't') {
            out.append(9);
        } else if (b == 'r') {
            out.append(13);
        } else if (b == 'b') {
            out.append(8);
        } else if (b == 'f') {
            out.append(12);
        } else if (b == 'u') {
            var unit = _hex4(start);
            if (unit < 0) {
                return false;
            }
            var point = unit as uint;
            if (unit >= 56320 and unit <= 57343) {
                _fail_at($"unpaired surrogate '{_text.substr_bytes(start, 6)}'", start);
                return false;
            }
            if (unit >= 55296 and unit <= 56319) {
                var low = -1;
                if (_position + 1 < _size
                    and _text.byte_at(_position) == '\\'
                    and _text.byte_at(_position + 1) == 'u') {
                    var second = _position;
                    _position = _position + 2;
                    low = _hex4(second);
                    if (low < 0) {
                        return false;
                    }
                }
                if (low < 56320 or low > 57343) {
                    _fail_at($"unpaired surrogate '{_text.substr_bytes(start, 6)}'", start);
                    return false;
                }
                point = 65536 + (((unit - 55296) as uint) << 10) + ((low - 56320) as uint);
            }
            text.Utf8.append_code_point(out, point);
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

    # Reads the four hexadecimal digits after a `\u` that starts at
    # `start`, giving -1 after recording an error when they are not there.
    _hex4(start: ulong): int {
        var value = 0;
        var count = 0;
        while (count < 4) {
            var b = _peek();
            var digit = -1;
            if (b >= '0' and b <= '9') {
                digit = (b - '0') as int;
            } else if (b >= 'a' and b <= 'f') {
                digit = (b - 'a') as int + 10;
            } else if (b >= 'A' and b <= 'F') {
                digit = (b - 'A') as int + 10;
            }
            if (digit < 0) {
                _fail_at("'\\u' needs four hexadecimal digits", start);
                return -1;
            }
            value = value * 16 + digit;
            _position = _position + 1;
            count = count + 1;
        }
        return value;
    }

    _fail(message: String) {
        _fail_at(message, _position);
    }

    # Records the error `message` at byte `offset`, working out its line and
    # column.
    _fail_at(message: String, offset: ulong) {
        _error = JsonError(message, _path);
        _json_place(_error, _text, offset);
    }
}

# Sets `error`'s offset, and the line and column of that offset in `text`.
export _json_place(error: JsonError, text: String, offset: ulong) {
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
