# The regex parser: pattern text to a syntax tree of `_RegexNode`s, which
# `compile.pep` turns into a program for the matcher.
#
# The syntax is RE2's (see the Regular expressions chapter). The parser is
# recursive descent; groups nest at most `_REGEX_MAX_DEPTH` deep, so a
# pattern taken from user input cannot exhaust the stack.

export const _REGEX_NODE_EMPTY = 0;
export const _REGEX_NODE_CHAR = 1;
export const _REGEX_NODE_ANY = 2;
export const _REGEX_NODE_CLASS = 3;
export const _REGEX_NODE_ASSERT = 4;
export const _REGEX_NODE_GROUP = 5;
export const _REGEX_NODE_REPEAT = 6;
export const _REGEX_NODE_CONCAT = 7;
export const _REGEX_NODE_ALTERNATE = 8;

export const _REGEX_AT_TEXT_START = 0;
export const _REGEX_AT_TEXT_END = 1;
export const _REGEX_AT_LINE_START = 2;
export const _REGEX_AT_LINE_END = 3;
export const _REGEX_AT_WORD = 4;
export const _REGEX_AT_NOT_WORD = 5;

export const _REGEX_MAX_DEPTH: ulong = 250;
export const _REGEX_MAX_REPEAT: ulong = 1000;
export const _REGEX_MAX_CODE_POINT: uint = 1114111;

# One node of a parsed pattern.
export struct _RegexNode {
    # One of the `_REGEX_NODE_` kinds.
    var kind: int;
    # A CHAR's code point, an ASSERT's `_REGEX_AT_` kind, or for ANY 1 when
    # it also matches a newline.
    var value: uint;
    # A GROUP's capture index, or -1 for a non-capturing group.
    var group: long;
    # A REPEAT's bounds; `max` is -1 when unbounded.
    var min: ulong;
    var max: long;
    var greedy: bool;
    # A CLASS's code point ranges, each packed as `lo << 32 | hi`, sorted and
    # merged.
    var ranges: ulong[];
    # A GROUP's or REPEAT's child, or the items of a CONCAT or ALTERNATE.
    var children: _RegexNode[];

    construct(kind: int) {
        this.kind = kind;
        value = 0;
        group = -1;
        min = 0;
        max = 0;
        greedy = true;
        ranges = Array<ulong>();
        children = Array<_RegexNode>();
    }
}

# Parses one pattern. After `parse()`, `failed` says whether the pattern
# was invalid and `error` says why.
export struct _RegexParser {
    var _data: u8[];
    var _size: ulong;
    var _position: ulong;
    var _case_insensitive: bool;
    var _multi_line: bool;
    var _dot_all: bool;
    var _lazy: bool;
    var _depth: ulong;
    # The number of capture groups so far.
    var group_count: ulong;
    # The name of each group by index; "" for group 0 and unnamed groups.
    var names: String[];
    var failed: bool;
    var error: String;

    construct(pattern: String) {
        _data = pattern.bytes();
        _size = _data.count();
        _position = 0;
        _case_insensitive = false;
        _multi_line = false;
        _dot_all = false;
        _lazy = false;
        _depth = 0;
        group_count = 0;
        names = Array<String>();
        names.append("");
        failed = false;
        error = "";
    }

    # Parses the whole pattern.
    parse(): _RegexNode {
        var node = _parse_alternation();
        if (!failed && _position < _size) {
            # `_parse_alternation` stops only at the end or at a ')'.
            return _fail("unmatched ')'", _position);
        }
        return node;
    }

    _fail(why: String, at: ulong): _RegexNode {
        if (!failed) {
            failed = true;
            error = $"{why} at offset {at}";
        }
        return _RegexNode(_REGEX_NODE_EMPTY);
    }

    # The byte at the current position, or -1 at the end.
    _peek(): int {
        if (_position >= _size) {
            return -1;
        }
        return _data[_position] as int;
    }

    # The byte `ahead` bytes past the current position, or -1 past the end.
    _peek_at(ahead: ulong): int {
        if (_position + ahead >= _size) {
            return -1;
        }
        return _data[_position + ahead] as int;
    }

    _parse_alternation(): _RegexNode {
        var branches = Array<_RegexNode>();
        branches.append(_parse_concat());
        while (!failed && _peek() == '|') {
            _position += 1;
            branches.append(_parse_concat());
        }
        if (branches.count() == 1) {
            return branches[0];
        }
        var node = _RegexNode(_REGEX_NODE_ALTERNATE);
        node.children = branches;
        return node;
    }

    _parse_concat(): _RegexNode {
        var items = Array<_RegexNode>();
        while (!failed && _position < _size) {
            var c = _peek();
            if (c == '|' || c == ')') {
                break;
            }
            var atom = _parse_atom();
            if (failed) {
                break;
            }
            items.append(_parse_repeat(atom));
        }
        if (items.count() == 1) {
            return items[0];
        }
        var node = _RegexNode(_REGEX_NODE_CONCAT);
        node.children = items;
        return node;
    }

    # Reads a counted repetition `{n}`, `{n,}` or `{n,m}` at the current
    # position, leaving the position after it. Returns false, with the
    # position unchanged, when the text there is not one (a '{' that is
    # then a literal).
    _parse_count(): (bool, ulong, long) {
        var start = _position;
        _position += 1;
        var low = _parse_number();
        if (low < 0) {
            _position = start;
            return (false, 0, 0);
        }
        long high = low;
        if (_peek() == ',') {
            _position += 1;
            if (_peek() == '}') {
                high = -1;
            } else {
                high = _parse_number();
                if (high < 0) {
                    _position = start;
                    return (false, 0, 0);
                }
            }
        }
        if (_peek() != '}') {
            _position = start;
            return (false, 0, 0);
        }
        _position += 1;
        return (true, low as ulong, high);
    }

    # Reads decimal digits, or gives -1 when there are none. Values past
    # `_REGEX_MAX_REPEAT` stop growing, so they are still reported as too
    # large rather than overflowing.
    _parse_number(): long {
        long value = -1;
        while (true) {
            var c = _peek();
            if (c < '0' || c > '9') {
                break;
            }
            if (value < 0) {
                value = 0;
            }
            if (value <= (_REGEX_MAX_REPEAT as long)) {
                value = value * 10 + ((c - '0') as long);
            }
            _position += 1;
        }
        return value;
    }

    # Whether a repetition operator starts at the current position.
    _at_repeat(): bool {
        var c = _peek();
        if (c == '*' || c == '+' || c == '?') {
            return true;
        }
        if (c == '{') {
            var start = _position;
            var (counted, low, high) = _parse_count();
            _position = start;
            return counted;
        }
        return false;
    }

    _parse_repeat(atom: _RegexNode): _RegexNode {
        var start = _position;
        var c = _peek();
        ulong min = 0;
        long max = -1;
        if (c == '*') {
            _position += 1;
        } else if (c == '+') {
            min = 1;
            _position += 1;
        } else if (c == '?') {
            max = 1;
            _position += 1;
        } else if (c == '{') {
            var (counted, low, high) = _parse_count();
            if (!counted) {
                return atom;
            }
            if (low > _REGEX_MAX_REPEAT || high > (_REGEX_MAX_REPEAT as long)) {
                return _fail($"repeat count exceeds {_REGEX_MAX_REPEAT}", start);
            }
            if (high >= 0 && (low as long) > high) {
                return _fail("invalid repeat count: minimum is larger than maximum", start);
            }
            min = low;
            max = high;
        } else {
            return atom;
        }
        var greedy = !_lazy;
        if (_peek() == '?') {
            greedy = _lazy;
            _position += 1;
        }
        if (_at_repeat()) {
            return _fail("invalid nested repetition operator", _position);
        }
        var node = _RegexNode(_REGEX_NODE_REPEAT);
        node.min = min;
        node.max = max;
        node.greedy = greedy;
        node.children.append(atom);
        return node;
    }

    _parse_atom(): _RegexNode {
        var c = _peek();
        if (c == '(') {
            return _parse_group();
        }
        if (c == '[') {
            return _parse_class();
        }
        if (c == '\\') {
            return _parse_escape();
        }
        if (c == '*' || c == '+' || c == '?') {
            return _fail($"missing argument to repetition operator '{_text(_position, _position + 1)}'", _position);
        }
        _position += 1;
        if (c == '.') {
            var any = _RegexNode(_REGEX_NODE_ANY);
            if (_dot_all) {
                any.value = 1;
            }
            return any;
        }
        if (c == '^') {
            return _assertion(_multi_line ? _REGEX_AT_LINE_START : _REGEX_AT_TEXT_START);
        }
        if (c == '$') {
            return _assertion(_multi_line ? _REGEX_AT_LINE_END : _REGEX_AT_TEXT_END);
        }
        _position -= 1;
        return _literal(_read_code_point());
    }

    _assertion(kind: int): _RegexNode {
        var node = _RegexNode(_REGEX_NODE_ASSERT);
        node.value = kind as uint;
        return node;
    }

    # A node matching the code point `value`, in either case when the
    # pattern is case-insensitive.
    _literal(value: uint): _RegexNode {
        if (_case_insensitive && _regex_other_case(value) != value) {
            var ranges = Array<ulong>();
            _regex_add_range(ranges, value, value);
            return _class_node(ranges, false);
        }
        var node = _RegexNode(_REGEX_NODE_CHAR);
        node.value = value;
        return node;
    }

    # Decodes the UTF-8 code point at the current position and moves past it.
    _read_code_point(): uint {
        var (value, width) = _regex_decode(_data._data, _position, _size);
        _position += width;
        return value;
    }

    _parse_group(): _RegexNode {
        var start = _position;
        _position += 1;
        _depth += 1;
        if (_depth > _REGEX_MAX_DEPTH) {
            return _fail($"groups nest more than {_REGEX_MAX_DEPTH} deep", start);
        }
        long index = -1;
        if (_peek() == '?') {
            _position += 1;
            var c = _peek();
            var next = _peek_at(1);
            if (c == '=' || c == '!' || (c == '<' && (next == '=' || next == '!'))) {
                return _fail("lookaround is not supported", start);
            }
            if (c == '<' || (c == 'P' && next == '<')) {
                if (c == 'P') {
                    _position += 1;
                }
                _position += 1;
                var name = _parse_group_name(start);
                if (failed) {
                    return _RegexNode(_REGEX_NODE_EMPTY);
                }
                group_count += 1;
                index = group_count as long;
                names.append(name);
            } else {
                var scoped = _parse_flags(start);
                if (failed) {
                    return _RegexNode(_REGEX_NODE_EMPTY);
                }
                if (!scoped) {
                    # `(?flags)`: the flags hold to the end of the enclosing group.
                    _depth -= 1;
                    return _RegexNode(_REGEX_NODE_EMPTY);
                }
            }
        } else {
            group_count += 1;
            index = group_count as long;
            names.append("");
        }
        # A group's flag changes end with it.
        var case_insensitive = _case_insensitive;
        var multi_line = _multi_line;
        var dot_all = _dot_all;
        var lazy = _lazy;
        var child = _parse_alternation();
        if (failed) {
            return child;
        }
        if (_peek() != ')') {
            return _fail("missing ')'", start);
        }
        _position += 1;
        _case_insensitive = case_insensitive;
        _multi_line = multi_line;
        _dot_all = dot_all;
        _lazy = lazy;
        _depth -= 1;
        var node = _RegexNode(_REGEX_NODE_GROUP);
        node.group = index;
        node.children.append(child);
        return node;
    }

    # Reads a group name and its closing '>'.
    _parse_group_name(start: ulong): String {
        var begin = _position;
        while (true) {
            var c = _peek();
            if (c == '>') {
                break;
            }
            var word = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
            if (!word) {
                _fail("invalid group name: use letters, digits and '_', ended by '>'", start);
                return "";
            }
            _position += 1;
        }
        if (_position == begin) {
            _fail("empty group name", start);
            return "";
        }
        var name = _text(begin, _position);
        _position += 1;
        for (var existing in names) {
            if (existing == name) {
                _fail($"duplicate group name '{name}'", start);
                return "";
            }
        }
        return name;
    }

    # The pattern text from byte `begin` to byte `end`.
    _text(begin: ulong, end: ulong): String {
        var bytes = Array<u8>(end - begin);
        var index = begin;
        while (index < end) {
            bytes.append(_data[index]);
            index += 1;
        }
        return String._from_bytes(bytes);
    }

    # Reads the flags of `(?flags)` or `(?flags:`, after the '?', and sets
    # them. Returns true for the scoped form, `(?flags:...)`, with the
    # position at its body.
    _parse_flags(start: ulong): bool {
        var on = true;
        var any = false;
        while (true) {
            var c = _peek();
            if (c == ')' || c == ':') {
                if (!any && c == ')') {
                    _fail("missing flags", start);
                    return false;
                }
                _position += 1;
                return c == ':';
            }
            if (c == '-' && on) {
                on = false;
            } else if (c == 'i') {
                _case_insensitive = on;
            } else if (c == 'm') {
                _multi_line = on;
            } else if (c == 's') {
                _dot_all = on;
            } else if (c == 'U') {
                _lazy = on;
            } else if (c < 0) {
                _fail("missing ')'", start);
                return false;
            } else {
                _fail($"unknown flag '{_text(_position, _position + 1)}'", _position);
                return false;
            }
            any = true;
            _position += 1;
        }
        return false;
    }

    _parse_escape(): _RegexNode {
        var start = _position;
        _position += 1;
        var c = _peek();
        if (c < 0) {
            return _fail("trailing backslash", start);
        }
        _position += 1;
        if (c == 'b') {
            return _assertion(_REGEX_AT_WORD);
        }
        if (c == 'B') {
            return _assertion(_REGEX_AT_NOT_WORD);
        }
        if (c == 'A') {
            return _assertion(_REGEX_AT_TEXT_START);
        }
        if (c == 'z') {
            return _assertion(_REGEX_AT_TEXT_END);
        }
        var ranges = Array<ulong>();
        if (_regex_perl_class(ranges, c)) {
            return _class_node(ranges, false);
        }
        _position = start;
        var value = _parse_escaped_code_point();
        if (failed) {
            return _RegexNode(_REGEX_NODE_EMPTY);
        }
        return _literal(value);
    }

    # Reads an escape that stands for one code point (`\n`, `\x41`, `\.`),
    # from its backslash.
    _parse_escaped_code_point(): uint {
        var start = _position;
        _position += 1;
        var c = _peek();
        if (c < 0) {
            _fail("trailing backslash", start);
            return 0;
        }
        _position += 1;
        if (c == 'n') {
            return 10;
        }
        if (c == 't') {
            return 9;
        }
        if (c == 'r') {
            return 13;
        }
        if (c == 'f') {
            return 12;
        }
        if (c == 'v') {
            return 11;
        }
        if (c == 'a') {
            return 7;
        }
        if (c == 'x') {
            return _parse_hex(start);
        }
        if (c >= '1' && c <= '9') {
            _fail("backreferences are not supported", start);
            return 0;
        }
        var letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
        if (c < 128 && !letter) {
            return c as uint;
        }
        _position -= 1;
        _read_code_point();
        _fail($"unknown escape '{_text(start, _position)}'", start);
        return 0;
    }

    # Reads the digits of `\xHH` or `\x{H...}`, after the 'x'.
    _parse_hex(start: ulong): uint {
        var braced = _peek() == '{';
        if (braced) {
            _position += 1;
        }
        uint value = 0;
        ulong digits = 0;
        while (true) {
            if (!braced && digits == 2) {
                break;
            }
            var c = _peek();
            if (braced && c == '}' && digits > 0) {
                _position += 1;
                break;
            }
            uint digit = 0;
            if (c >= '0' && c <= '9') {
                digit = (c - '0') as uint;
            } else if (c >= 'a' && c <= 'f') {
                digit = (c - 'a' + 10) as uint;
            } else if (c >= 'A' && c <= 'F') {
                digit = (c - 'A' + 10) as uint;
            } else {
                _fail("invalid hexadecimal escape", start);
                return 0;
            }
            value = value * 16 + digit;
            digits += 1;
            if (value > _REGEX_MAX_CODE_POINT) {
                _fail("hexadecimal escape is past U+10FFFF", start);
                return 0;
            }
            _position += 1;
        }
        if (value >= 55296 && value <= 57343) {
            _fail("hexadecimal escape is a surrogate, not a code point", start);
            return 0;
        }
        return value;
    }

    _class_node(ranges: ulong[], negated: bool): _RegexNode {
        if (_case_insensitive) {
            _regex_add_other_cases(ranges);
        }
        var node = _RegexNode(_REGEX_NODE_CLASS);
        node.ranges = _regex_canonical(ranges, negated);
        return node;
    }

    _parse_class(): _RegexNode {
        var start = _position;
        _position += 1;
        var negated = false;
        if (_peek() == '^') {
            negated = true;
            _position += 1;
        }
        var ranges = Array<ulong>();
        var first = true;
        while (true) {
            var c = _peek();
            if (c < 0) {
                return _fail("missing ']'", start);
            }
            if (c == ']' && !first) {
                _position += 1;
                break;
            }
            first = false;
            if (c == '[' && _peek_at(1) == ':') {
                if (_parse_posix_class(ranges)) {
                    continue;
                }
                if (failed) {
                    return _RegexNode(_REGEX_NODE_EMPTY);
                }
            }
            if (c == '\\') {
                var letter = _peek_at(1);
                if (letter >= 0 && _regex_perl_class(ranges, letter)) {
                    _position += 2;
                    continue;
                }
            }
            var low = _parse_class_code_point();
            if (failed) {
                return _RegexNode(_REGEX_NODE_EMPTY);
            }
            var high = low;
            var next = _peek_at(1);
            if (_peek() == '-' && next >= 0 && next != ']') {
                var dash = _position;
                _position += 1;
                high = _parse_class_code_point();
                if (failed) {
                    return _RegexNode(_REGEX_NODE_EMPTY);
                }
                if (high < low) {
                    return _fail("invalid character class range", dash);
                }
            }
            _regex_add_range(ranges, low, high);
        }
        return _class_node(ranges, negated);
    }

    # Reads one code point of a class: a literal or a single-character escape.
    _parse_class_code_point(): uint {
        if (_peek() == '\\') {
            var letter = _peek_at(1);
            var ranges = Array<ulong>();
            if (letter >= 0 && _regex_perl_class(ranges, letter)) {
                _fail("a class such as '\\d' cannot bound a range", _position);
                return 0;
            }
            return _parse_escaped_code_point();
        }
        return _read_code_point();
    }

    # Reads `[:name:]` or `[:^name:]` into `ranges`. Returns false, with the
    # position unchanged, when the text is not one.
    _parse_posix_class(ranges: ulong[]): bool {
        var start = _position;
        _position += 2;
        var negated = false;
        if (_peek() == '^') {
            negated = true;
            _position += 1;
        }
        var begin = _position;
        while (_peek() >= 'a' && _peek() <= 'z') {
            _position += 1;
        }
        if (_peek() != ':' || _peek_at(1) != ']') {
            _position = start;
            return false;
        }
        var name = _text(begin, _position);
        _position += 2;
        var named = Array<ulong>();
        if (!_regex_posix_class(named, name)) {
            _fail($"unknown character class '[:{name}:]'", start);
            return false;
        }
        if (negated) {
            named = _regex_canonical(named, true);
        }
        for (var range in named) {
            ranges.append(range);
        }
        return true;
    }
}

# Decodes the UTF-8 code point at `index` of the `size` bytes at `data`:
# its value and byte width. A byte that does not start a valid sequence is
# U+FFFD, one byte wide.
export _regex_decode(data: __ptr<u8>, index: ulong, size: ulong): (uint, ulong) {
    var first = data[index] as uint;
    if (first < 128) {
        return (first, 1);
    }
    var run = String._utf8_sequence(data, index, size);
    if (run == 0) {
        return (65533, 1);
    }
    uint value = 0;
    if (run == 2) {
        value = first & 31;
    } else if (run == 3) {
        value = first & 15;
    } else {
        value = first & 7;
    }
    ulong k = 1;
    while (k < run) {
        value = (value << 6) | ((data[index + k] as uint) & 63);
        k += 1;
    }
    return (value, run);
}

# The other ASCII case of a letter, or `value` itself.
export _regex_other_case(value: uint): uint {
    if (value >= 'a' && value <= 'z') {
        return value - 32;
    }
    if (value >= 'A' && value <= 'Z') {
        return value + 32;
    }
    return value;
}

export _regex_add_range(ranges: ulong[], low: uint, high: uint) {
    ranges.append(((low as ulong) << 32) | (high as ulong));
}

export _regex_range_low(range: ulong): uint {
    return (range >> 32) as uint;
}

export _regex_range_high(range: ulong): uint {
    return (range & 4294967295) as uint;
}

# Adds the other ASCII case of every letter in `ranges`.
export _regex_add_other_cases(ranges: ulong[]) {
    var count = ranges.count();
    ulong index = 0;
    while (index < count) {
        var low = _regex_range_low(ranges[index]);
        var high = _regex_range_high(ranges[index]);
        _regex_add_shifted(ranges, low, high, 'a', 'z', false);
        _regex_add_shifted(ranges, low, high, 'A', 'Z', true);
        index += 1;
    }
}

# Adds the part of `low..high` inside `first..last`, moved 32 up or down.
export _regex_add_shifted(ranges: ulong[], low: uint, high: uint, first: uint, last: uint, up: bool) {
    var from = low > first ? low : first;
    var to = high < last ? high : last;
    if (from > to) {
        return;
    }
    if (up) {
        _regex_add_range(ranges, from + 32, to + 32);
    } else {
        _regex_add_range(ranges, from - 32, to - 32);
    }
}

_regex_compare_ranges(a: ulong, b: ulong): int {
    if (a < b) {
        return -1;
    }
    if (a > b) {
        return 1;
    }
    return 0;
}

# Returns `ranges` sorted with overlapping and touching ranges merged,
# complemented over all code points when `negated`.
export _regex_canonical(ranges: ulong[], negated: bool): ulong[] {
    var sorted = ranges.clone();
    sorted.sort(_regex_compare_ranges);
    var merged = Array<ulong>();
    for (var range in sorted) {
        var low = _regex_range_low(range);
        var high = _regex_range_high(range);
        var count = merged.count();
        if (count > 0) {
            var last_high = _regex_range_high(merged[count - 1]);
            if (low <= last_high + 1) {
                if (high > last_high) {
                    merged[count - 1] = ((_regex_range_low(merged[count - 1]) as ulong) << 32) | (high as ulong);
                }
                continue;
            }
        }
        _regex_add_range(merged, low, high);
    }
    if (!negated) {
        return merged;
    }
    var complement = Array<ulong>();
    uint next = 0;
    var open = true;
    for (var range in merged) {
        var low = _regex_range_low(range);
        var high = _regex_range_high(range);
        if (low > next) {
            _regex_add_range(complement, next, low - 1);
        }
        if (high >= _REGEX_MAX_CODE_POINT) {
            open = false;
            break;
        }
        next = high + 1;
    }
    if (open) {
        _regex_add_range(complement, next, _REGEX_MAX_CODE_POINT);
    }
    return complement;
}

# Adds the ranges of `\d`, `\w`, `\s` or (negated) `\D`, `\W`, `\S` for the
# escape letter `letter`. Returns false for any other letter.
export _regex_perl_class(ranges: ulong[], letter: int): bool {
    var named = Array<ulong>();
    if (letter == 'd' || letter == 'D') {
        _regex_posix_class(named, "digit");
    } else if (letter == 'w' || letter == 'W') {
        _regex_posix_class(named, "word");
    } else if (letter == 's' || letter == 'S') {
        _regex_add_range(named, 9, 10);
        _regex_add_range(named, 12, 13);
        _regex_add_range(named, ' ', ' ');
    } else {
        return false;
    }
    if (letter == 'D' || letter == 'W' || letter == 'S') {
        named = _regex_canonical(named, true);
    }
    for (var range in named) {
        ranges.append(range);
    }
    return true;
}

# Adds the ranges of the POSIX class `[:name:]`. Returns false for an
# unknown name.
export _regex_posix_class(ranges: ulong[], name: String): bool {
    if (name == "alnum") {
        _regex_add_range(ranges, '0', '9');
        _regex_add_range(ranges, 'A', 'Z');
        _regex_add_range(ranges, 'a', 'z');
    } else if (name == "alpha") {
        _regex_add_range(ranges, 'A', 'Z');
        _regex_add_range(ranges, 'a', 'z');
    } else if (name == "ascii") {
        _regex_add_range(ranges, 0, 127);
    } else if (name == "blank") {
        _regex_add_range(ranges, 9, 9);
        _regex_add_range(ranges, ' ', ' ');
    } else if (name == "cntrl") {
        _regex_add_range(ranges, 0, 31);
        _regex_add_range(ranges, 127, 127);
    } else if (name == "digit") {
        _regex_add_range(ranges, '0', '9');
    } else if (name == "graph") {
        _regex_add_range(ranges, 33, 126);
    } else if (name == "lower") {
        _regex_add_range(ranges, 'a', 'z');
    } else if (name == "print") {
        _regex_add_range(ranges, 32, 126);
    } else if (name == "punct") {
        _regex_add_range(ranges, 33, 47);
        _regex_add_range(ranges, 58, 64);
        _regex_add_range(ranges, 91, 96);
        _regex_add_range(ranges, 123, 126);
    } else if (name == "space") {
        _regex_add_range(ranges, 9, 13);
        _regex_add_range(ranges, ' ', ' ');
    } else if (name == "upper") {
        _regex_add_range(ranges, 'A', 'Z');
    } else if (name == "word") {
        _regex_add_range(ranges, '0', '9');
        _regex_add_range(ranges, 'A', 'Z');
        _regex_add_range(ranges, '_', '_');
        _regex_add_range(ranges, 'a', 'z');
    } else if (name == "xdigit") {
        _regex_add_range(ranges, '0', '9');
        _regex_add_range(ranges, 'A', 'F');
        _regex_add_range(ranges, 'a', 'f');
    } else {
        return false;
    }
    return true;
}
