## Regex, Match and the iterator over every match.

import "compile";
import "syntax";
import "vm";

## A compiled regular expression: compile a pattern once, then test, find,
## replace or split text with it.
##
## The syntax is RE2's, the one Go and Rust's `regex` use. Matching runs in
## time linear in the text whatever the pattern, because the engine never
## backtracks; in return there are no backreferences (`\1`) and no
## lookaround (`(?=...)`), and a pattern using them fails to compile.
##
## - **Positions** (`Match.start()`, `Match.end()`, `find_at`) are byte
##   offsets, like `String.find`, so they work with `substr_bytes`.
## - **`.`** and a negated class (`[^a]`) match one code point, never part
##   of one.
## - **`\d`, `\w`, `\s`, `\b`** and case-insensitive matching are ASCII-only.
##
## A Regex never changes once compiled and is `[Shared]`, so one compiled at
## module scope (`const word = regex.Regex("\\w+");`) serves every thread.
##
## @example
##     import regex;
##
##     main(): int {
##         var date = regex.Regex("(\\d{4})-(\\d{2})-(\\d{2})");
##         var found = date.find("due 2026-10-01").value();
##         assert(found.group(1).value() == "2026", "the year");
##         assert(found.start() == 4, "a byte offset");
##         return 0;
##     }
[Shared]
export struct Regex {
    const _program: _RegexProgram;

    ## Compiles `pattern`.
    ##
    ## @param pattern the regular expression
    ## @panics if `pattern` is not a valid regular expression; use `parse`
    ##   for a pattern that may be invalid, such as one from user input
    construct(pattern: String) {
        var compiled = _regex_compile(pattern);
        if (compiled.is_err()) {
            panic(compiled.error().message);
        }
        _program = compiled.value();
    }

    ## Wraps a compiled program. Use `Regex(pattern)` or `Regex.parse`; this
    ## constructor is for the runtime.
    ##
    ## @param program the compiled pattern
    construct(program: _RegexProgram) {
        _program = program;
    }

    ## Compiles `pattern`, or reports why it is invalid.
    ##
    ## @param pattern the regular expression
    ## @returns the compiled expression, or an error naming the problem and
    ##   its byte offset in `pattern`, such as `invalid regex '(a': missing ')' at offset 0`
    ## @example
    ##     import regex;
    ##
    ##     assert(regex.Regex.parse("[a-z]+").is_ok(), "valid");
    ##     assert(regex.Regex.parse("(a").is_err(), "unclosed group");
    static parse(pattern: String): Result<Regex> {
        var compiled = _regex_compile(pattern);
        if (compiled.is_err()) {
            return Result<Regex>.err(compiled.error());
        }
        return Result<Regex>.ok(Regex(compiled.value()));
    }

    ## Returns `text` with every character that has a meaning in a pattern
    ## escaped, so the result matches `text` literally.
    ##
    ## @param text the text to match
    ## @returns a pattern that matches exactly `text`
    ## @example
    ##     import regex;
    ##
    ##     assert(regex.Regex.escape("1+1=2?") == "1\\+1=2\\?", "escaped");
    static escape(text: String): String {
        var out = StringBuilder();
        var start: ulong = 0;
        var size = text.size();
        ulong index = 0;
        while (index < size) {
            var c = text.byte_at(index);
            var special = c == '\\'
                || c == '.'
                || c == '+'
                || c == '*'
                || c == '?'
                || c == '('
                || c == ')'
                || c == '|'
                || c == '['
                || c == ']'
                || c == '{'
                || c == '}'
                || c == '^'
                || c == '$';
            if (special) {
                out.append(text.substr_bytes(start, index - start));
                out.append("\\");
                start = index;
            }
            index += 1;
        }
        out.append(text.substr_bytes(start, size - start));
        return out.to_string();
    }

    ## Returns the pattern this expression was compiled from.
    ##
    ## @returns the pattern text
    pattern(): String {
        return _program.pattern();
    }

    ## Returns the number of capture groups in the pattern, not counting the
    ## whole match.
    ##
    ## @returns the number of `(...)` groups, named ones included
    group_count(): ulong {
        return _program.group_count;
    }

    ## Returns whether the expression matches anywhere in `text`. Faster
    ## than `find`, since it stops at the first match it sees.
    ##
    ## @param text the text to search
    ## @returns true when there is a match
    ## @example
    ##     import regex;
    ##
    ##     assert(regex.Regex("^\\d+$").is_match("2026"), "all digits");
    is_match(text: String): bool {
        return _RegexMatcher(_program).search(text, 0, true).is_some();
    }

    ## Returns the leftmost match in `text`, or none. Among matches that
    ## start at the same place, a greedy repetition prefers the longer one
    ## and alternation the earlier branch, as in Perl.
    ##
    ## @param text the text to search
    ## @returns the first match, or none
    find(text: String): Match? {
        return find_at(text, 0);
    }

    ## Returns the leftmost match in `text` that starts at or after byte
    ## offset `start`, or none. Assertions still see the text before `start`:
    ## `^` does not match at `start` unless it begins a line, and `\b` looks
    ## at the character before it.
    ##
    ## @param text the text to search
    ## @param start the byte offset to search from, at most `text.size()`
    ## @returns the first match from `start`, or none
    ## @panics if `start` is greater than `text.size()`
    find_at(text: String, start: ulong): Match? {
        assert(start <= text.size(), "Regex.find_at: start is past the end of the text");
        var slots = _RegexMatcher(_program).search(text, start, false);
        if (slots.is_none()) {
            return Optional<Match>.none();
        }
        return Optional<Match>.some(Match(text, slots.value(), _program));
    }

    ## Returns an iterator over the matches in `text`, left to right and
    ## without overlaps. An empty match right after the previous match is
    ## skipped, so `a*` finds `a` twice in `"aba"`, not also between them.
    ##
    ## @param text the text to search
    ## @returns an iterator over the matches
    ## @example
    ##     import regex;
    ##
    ##     var total = 0;
    ##     for (var number in regex.Regex("\\d+").find_all("1 22 333")) {
    ##         total += number.text().size();   # 1, then 2, then 3
    ##     }
    find_all(text: String): Matches {
        return Matches(_program, text);
    }

    ## Returns `text` with the first match replaced by `replacement`, or a
    ## copy of `text` when nothing matches.
    ##
    ## In `replacement`, `$1` or `${1}` stands for group 1's text (empty when
    ## the group did not take part), `${name}` for a named group's, `$0` for
    ## the whole match, and `$$` for a `$`. A `$` followed by anything else
    ## is kept as it is.
    ##
    ## @param text the text to search
    ## @param replacement the text to put in place of the match
    ## @returns a new String
    ## @panics if `replacement` names a group the pattern does not have
    ## @example
    ##     import regex;
    ##
    ##     var swapped = regex.Regex("(\\w+) (\\w+)").replace("hello world", "$2 $1");
    ##     assert(swapped == "world hello", "groups swapped");
    replace(text: String, replacement: String): String {
        return _replace(text, replacement, false);
    }

    ## Returns `text` with every match, as `find_all` finds them, replaced by
    ## `replacement`, which may name groups as in `replace`.
    ##
    ## @param text the text to search
    ## @param replacement the text to put in place of each match
    ## @returns a new String
    ## @panics if `replacement` names a group the pattern does not have
    ## @example
    ##     import regex;
    ##
    ##     var squeezed = regex.Regex("\\s+").replace_all("a  b\t\nc", " ");
    ##     assert(squeezed == "a b c", "runs of space replaced");
    replace_all(text: String, replacement: String): String {
        return _replace(text, replacement, true);
    }

    _replace(text: String, replacement: String, all: bool): String {
        var out = StringBuilder();
        ulong last = 0;
        for (var found in find_all(text)) {
            out.append(text.substr_bytes(last, found.start() - last));
            found._expand(replacement, out);
            last = found.end();
            if (!all) {
                break;
            }
        }
        out.append(text.substr_bytes(last, text.size() - last));
        return out.to_string();
    }

    ## Splits `text` at each match, as `find_all` finds them, and returns the
    ## pieces between them. A match at the start or end gives an empty first
    ## or last piece, and text with no match gives one piece, the whole text.
    ##
    ## @param text the text to split
    ## @returns the pieces, at least one
    ## @example
    ##     import regex;
    ##
    ##     var parts = regex.Regex(",\\s*").split("a, b,c");
    ##     assert(parts.count() == 3 && parts[1] == "b", "three pieces");
    split(text: String): String[] {
        var pieces = Array<String>();
        ulong last = 0;
        for (var found in find_all(text)) {
            pieces.append(text.substr_bytes(last, found.start() - last));
            last = found.end();
        }
        pieces.append(text.substr_bytes(last, text.size() - last));
        return pieces;
    }

    ## Returns the pattern, so `print` and interpolation show it.
    ##
    ## @returns the pattern text
    to_string(): String {
        return _program.pattern();
    }
}

extend Regex with ToString;

## One match of a `Regex`: where it is in the text, and what each capture
## group matched.
##
## Positions are byte offsets into the searched text. Group 0 is the whole
## match; groups are numbered from 1 by their opening `(`, named ones
## included.
export struct Match {
    var _text: String;
    var _slots: long[];
    var _program: _RegexProgram;

    ## Creates a match over `text` from its capture slots. Matches come from
    ## `Regex`; this constructor is for the runtime.
    ##
    ## @param text the searched text
    ## @param slots a start and end byte offset for the match and each group,
    ##   -1 for a group that did not take part
    ## @param program the compiled pattern, for its group names
    construct(text: String, slots: long[], program: _RegexProgram) {
        _text = text;
        _slots = slots;
        _program = program;
    }

    ## Returns the matched text.
    ##
    ## @returns the text of the whole match
    text(): String {
        return _text.substr_bytes(start(), end() - start());
    }

    ## Returns the byte offset where the match starts.
    ##
    ## @returns the offset of the match's first byte
    start(): ulong {
        return _slots[0] as ulong;
    }

    ## Returns the byte offset just past the end of the match.
    ##
    ## @returns the offset after the match's last byte; equal to `start()`
    ##   for an empty match
    end(): ulong {
        return _slots[1] as ulong;
    }

    ## Returns the number of capture groups, not counting the whole match.
    ##
    ## @returns the number of groups in the pattern
    group_count(): ulong {
        return _slots.count() / 2 - 1;
    }

    ## Returns the text that group `index` matched, or none when the group
    ## did not take part in the match (as in `(a)|b` matching `b`).
    ##
    ## @param index the group number; 0 is the whole match
    ## @returns the group's text, or none
    ## @panics if `index` is greater than `group_count()`
    group(index: ulong): String? {
        assert(index <= group_count(), "Match.group: no such group");
        var begin = _slots[index * 2];
        if (begin < 0) {
            return Optional<String>.none();
        }
        var finish = _slots[index * 2 + 1] as ulong;
        return Optional<String>.some(_text.substr_bytes(begin as ulong, finish - (begin as ulong)));
    }

    ## Returns the text that the group named `name` (`(?<name>...)` or
    ## `(?P<name>...)`) matched, or none when it did not take part.
    ##
    ## @param name the group's name
    ## @returns the group's text, or none
    ## @panics if the pattern has no group named `name`
    group(name: String): String? {
        return group(_group_index(name));
    }

    ## Returns the byte offsets where group `index` starts and ends, or none
    ## when it did not take part.
    ##
    ## @param index the group number; 0 is the whole match
    ## @returns the start and end offsets, or none
    ## @panics if `index` is greater than `group_count()`
    group_range(index: ulong): (ulong, ulong)? {
        assert(index <= group_count(), "Match.group_range: no such group");
        var begin = _slots[index * 2];
        if (begin < 0) {
            return Optional<(ulong, ulong)>.none();
        }
        return Optional<(ulong, ulong)>.some((begin as ulong, _slots[index * 2 + 1] as ulong));
    }

    _group_index(name: String): ulong {
        var index = _program.group_named(name);
        if (index == 0) {
            panic($"Match.group: no group named '{name}'");
        }
        return index;
    }

    # Appends `replacement` to `out` with its `$` references filled in.
    _expand(replacement: String, out: StringBuilder) {
        var size = replacement.size();
        ulong last = 0;
        ulong index = 0;
        while (index < size) {
            if (replacement.byte_at(index) != '$' || index + 1 >= size) {
                index += 1;
                continue;
            }
            var next = replacement.byte_at(index + 1);
            ulong end = index + 1;
            var name = "";
            if (next == '$') {
                out.append(replacement.substr_bytes(last, index + 1 - last));
                index += 2;
                last = index;
                continue;
            }
            if (next >= '0' && next <= '9') {
                while (end < size && replacement.byte_at(end) >= '0' && replacement.byte_at(end) <= '9') {
                    end += 1;
                }
                name = replacement.substr_bytes(index + 1, end - index - 1);
            } else if (next == '{') {
                var close = replacement.find("}", index + 2);
                if (close < 0) {
                    index += 1;
                    continue;
                }
                name = replacement.substr_bytes(index + 2, (close as ulong) - index - 2);
                end = (close as ulong) + 1;
            } else {
                index += 1;
                continue;
            }
            out.append(replacement.substr_bytes(last, index - last));
            var number = ulong.parse(name);
            if (number.is_some()) {
                out.append(group(number.value()).value_or(""));
            } else {
                out.append(group(name).value_or(""));
            }
            index = end;
            last = end;
        }
        out.append(replacement.substr_bytes(last, size - last));
    }

    ## Returns the matched text.
    ##
    ## @returns the text of the whole match
    to_string(): String {
        return text();
    }
}

extend Match with ToString;

## An iterator over the matches of a `Regex` in a text, from
## `Regex.find_all`: left to right, without overlaps.
export struct Matches {
    var _matcher: _RegexMatcher;
    var _text: String;
    # The byte offset to search from next.
    var _position: ulong;
    # The end of the previous match, or -1 before the first.
    var _last_end: long;
    var _current: Match?;
    var _done: bool;

    ## Creates an iterator over the matches of `program` in `text`. Use
    ## `Regex.find_all`; this constructor is for the runtime.
    ##
    ## @param program the compiled pattern
    ## @param text the text to search
    construct(program: _RegexProgram, text: String) {
        _matcher = _RegexMatcher(program);
        _text = text;
        _position = 0;
        _last_end = -1;
        _current = Optional<Match>.none();
        _done = false;
    }

    ## Advances to the next match.
    ##
    ## @returns true when there is another match, false once they are exhausted
    next(): bool {
        var size = _text.size();
        while (!_done && _position <= size) {
            var slots = _matcher.search(_text, _position, false);
            if (slots.is_none()) {
                break;
            }
            var found = slots.value();
            var start = found[0];
            var end = found[1];
            if (start == end && start == _last_end) {
                # An empty match right after the previous one: try one code
                # point further on.
                if ((start as ulong) >= size) {
                    break;
                }
                var (value, width) = _regex_decode(_text._data as __ptr<u8>, start as ulong, size);
                _position = (start as ulong) + width;
                continue;
            }
            _current = Optional<Match>.some(Match(_text, found, _matcher.program));
            _last_end = end;
            _position = end as ulong;
            return true;
        }
        _done = true;
        _current = Optional<Match>.none();
        return false;
    }

    ## Returns the match the last successful `next()` moved to.
    ##
    ## @returns the current match
    ## @panics if `next()` has not returned true
    current(): Match {
        assert(_current.is_some(), "Matches.current() without a current match");
        return _current.value();
    }
}

extend Matches with Iterator<Match>;
