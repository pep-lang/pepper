<!-- Generated from runtime/regex/regex.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# regex/regex.pep

Regex, Match and the iterator over every match.

Source: `runtime/regex/regex.pep`

## Regex

```pepper
[Shared] struct Regex
```

A compiled regular expression: compile a pattern once, then test, find,
replace or split text with it.

The syntax is RE2's, the one Go and Rust's `regex` use. Matching runs in
time linear in the text whatever the pattern, because the engine never
backtracks; in return there are no backreferences (`\1`) and no
lookaround (`(?=...)`), and a pattern using them fails to compile.

- **Positions** (`Match.start()`, `Match.end()`, `find_at`) are byte
  offsets, like `String.find`, so they work with `substr_bytes`.
- **`.`** and a negated class (`[^a]`) match one code point, never part
  of one.
- **`\d`, `\w`, `\s`, `\b`** and case-insensitive matching are ASCII-only.

A Regex never changes once compiled and is `[Shared]`, so one compiled at
module scope (`const word = regex.Regex("\\w+");`) serves every thread.

**Example**
```pepper
    import regex;

    main(): int {
        var date = regex.Regex("(\\d{4})-(\\d{2})-(\\d{2})");
        var found = date.find("due 2026-10-01").value();
        assert(found.group(1).value() == "2026", "the year");
        assert(found.start() == 4, "a byte offset");
        return 0;
    }
```

### Constructors

#### Regex()

```pepper
construct(pattern: String)
```

Compiles `pattern`.

**Parameters**
- `pattern` — the regular expression

**Panics**
- if `pattern` is not a valid regular expression; use `parse` for a pattern that may be invalid, such as one from user input

#### Regex()

```pepper
construct(program: _RegexProgram)
```

Wraps a compiled program. Use `Regex(pattern)` or `Regex.parse`; this
constructor is for the runtime.

**Parameters**
- `program` — the compiled pattern

### Static methods

#### parse

```pepper
static parse(pattern: String): Result<Regex>
```

Compiles `pattern`, or reports why it is invalid.

**Parameters**
- `pattern` — the regular expression

**Returns**
- the compiled expression, or an error naming the problem and its byte offset in `pattern`, such as `invalid regex '(a': missing ')' at offset 0`

**Example**
```pepper
    import regex;

    assert(regex.Regex.parse("[a-z]+").is_ok(), "valid");
    assert(regex.Regex.parse("(a").is_err(), "unclosed group");
```

#### escape

```pepper
static escape(text: String): String
```

Returns `text` with every character that has a meaning in a pattern
escaped, so the result matches `text` literally.

**Parameters**
- `text` — the text to match

**Returns**
- a pattern that matches exactly `text`

**Example**
```pepper
    import regex;

    assert(regex.Regex.escape("1+1=2?") == "1\\+1=2\\?", "escaped");
```

### Methods

#### pattern

```pepper
pattern(): String
```

Returns the pattern this expression was compiled from.

**Returns**
- the pattern text

#### group_count

```pepper
group_count(): ulong
```

Returns the number of capture groups in the pattern, not counting the
whole match.

**Returns**
- the number of `(...)` groups, named ones included

#### is_match

```pepper
is_match(text: String): bool
```

Returns whether the expression matches anywhere in `text`. Faster
than `find`, since it stops at the first match it sees.

**Parameters**
- `text` — the text to search

**Returns**
- true when there is a match

**Example**
```pepper
    import regex;

    assert(regex.Regex("^\\d+$").is_match("2026"), "all digits");
```

#### find

```pepper
find(text: String): Match?
```

Returns the leftmost match in `text`, or none. Among matches that
start at the same place, a greedy repetition prefers the longer one
and alternation the earlier branch, as in Perl.

**Parameters**
- `text` — the text to search

**Returns**
- the first match, or none

#### find_at

```pepper
find_at(text: String, start: ulong): Match?
```

Returns the leftmost match in `text` that starts at or after byte
offset `start`, or none. Assertions still see the text before `start`:
`^` does not match at `start` unless it begins a line, and `\b` looks
at the character before it.

**Parameters**
- `text` — the text to search
- `start` — the byte offset to search from, at most `text.size`

**Returns**
- the first match from `start`, or none

**Panics**
- if `start` is greater than `text.size`

#### find_all

```pepper
find_all(text: String): Matches
```

Returns an iterator over the matches in `text`, left to right and
without overlaps. An empty match right after the previous match is
skipped, so `a*` finds `a` twice in `"aba"`, not also between them.

**Parameters**
- `text` — the text to search

**Returns**
- an iterator over the matches

**Example**
```pepper
    import regex;

    var total = 0;
    for (var number in regex.Regex("\\d+").find_all("1 22 333")) {
        total += number.text().size;   # 1, then 2, then 3
    }
```

#### replace

```pepper
replace(text: String, replacement: String): String
```

Returns `text` with the first match replaced by `replacement`, or a
copy of `text` when nothing matches.

In `replacement`, `$1` or `${1}` stands for group 1's text (empty when
the group did not take part), `${name}` for a named group's, `$0` for
the whole match, and `$$` for a `$`. A `$` followed by anything else
is kept as it is.

**Parameters**
- `text` — the text to search
- `replacement` — the text to put in place of the match

**Returns**
- a new String

**Panics**
- if `replacement` names a group the pattern does not have

**Example**
```pepper
    import regex;

    var swapped = regex.Regex("(\\w+) (\\w+)").replace("hello world", "$2 $1");
    assert(swapped == "world hello", "groups swapped");
```

#### replace_all

```pepper
replace_all(text: String, replacement: String): String
```

Returns `text` with every match, as `find_all` finds them, replaced by
`replacement`, which may name groups as in `replace`.

**Parameters**
- `text` — the text to search
- `replacement` — the text to put in place of each match

**Returns**
- a new String

**Panics**
- if `replacement` names a group the pattern does not have

**Example**
```pepper
    import regex;

    var squeezed = regex.Regex("\\s+").replace_all("a  b\t\nc", " ");
    assert(squeezed == "a b c", "runs of space replaced");
```

#### split

```pepper
split(text: String): String[]
```

Splits `text` at each match, as `find_all` finds them, and returns the
pieces between them. A match at the start or end gives an empty first
or last piece, and text with no match gives one piece, the whole text.

**Parameters**
- `text` — the text to split

**Returns**
- the pieces, at least one

**Example**
```pepper
    import regex;

    var parts = regex.Regex(",\\s*").split("a, b,c");
    assert(parts.count == 3 && parts[1] == "b", "three pieces");
```

#### to_string

```pepper
to_string(): String
```

Returns the pattern, so `print` and interpolation show it.

**Returns**
- the pattern text

## Match

```pepper
struct Match
```

One match of a `Regex`: where it is in the text, and what each capture
group matched.

Positions are byte offsets into the searched text. Group 0 is the whole
match; groups are numbered from 1 by their opening `(`, named ones
included.

### Constructor

#### Match()

```pepper
construct(text: String, slots: long[], program: _RegexProgram)
```

Creates a match over `text` from its capture slots. Matches come from
`Regex`; this constructor is for the runtime.

**Parameters**
- `text` — the searched text
- `slots` — a start and end byte offset for the match and each group, -1 for a group that did not take part
- `program` — the compiled pattern, for its group names

### Methods

#### text

```pepper
text(): String
```

Returns the matched text.

**Returns**
- the text of the whole match

#### start

```pepper
start(): ulong
```

Returns the byte offset where the match starts.

**Returns**
- the offset of the match's first byte

#### end

```pepper
end(): ulong
```

Returns the byte offset just past the end of the match.

**Returns**
- the offset after the match's last byte; equal to `start()` for an empty match

#### group_count

```pepper
group_count(): ulong
```

Returns the number of capture groups, not counting the whole match.

**Returns**
- the number of groups in the pattern

#### group

```pepper
group(index: ulong): String?
```

Returns the text that group `index` matched, or none when the group
did not take part in the match (as in `(a)|b` matching `b`).

**Parameters**
- `index` — the group number; 0 is the whole match

**Returns**
- the group's text, or none

**Panics**
- if `index` is greater than `group_count()`

#### group

```pepper
group(name: String): String?
```

Returns the text that the group named `name` (`(?<name>...)` or
`(?P<name>...)`) matched, or none when it did not take part.

**Parameters**
- `name` — the group's name

**Returns**
- the group's text, or none

**Panics**
- if the pattern has no group named `name`

#### group_range

```pepper
group_range(index: ulong): (ulong, ulong)?
```

Returns the byte offsets where group `index` starts and ends, or none
when it did not take part.

**Parameters**
- `index` — the group number; 0 is the whole match

**Returns**
- the start and end offsets, or none

**Panics**
- if `index` is greater than `group_count()`

#### to_string

```pepper
to_string(): String
```

Returns the matched text.

**Returns**
- the text of the whole match

## Matches

```pepper
struct Matches
```

An iterator over the matches of a `Regex` in a text, from
`Regex.find_all`: left to right, without overlaps.

### Constructor

#### Matches()

```pepper
construct(program: _RegexProgram, text: String)
```

Creates an iterator over the matches of `program` in `text`. Use
`Regex.find_all`; this constructor is for the runtime.

**Parameters**
- `program` — the compiled pattern
- `text` — the text to search

### Methods

#### next

```pepper
next(): bool
```

Advances to the next match.

**Returns**
- true when there is another match, false once they are exhausted

#### current

```pepper
current(): Match
```

Returns the match the last successful `next()` moved to.

**Returns**
- the current match

**Panics**
- if `next()` has not returned true
