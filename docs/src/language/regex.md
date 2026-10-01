# Regular expressions

The `regex` module finds patterns in text: test whether text matches,
find each match and its capture groups, and replace or split by a pattern.

```pepper
{{#include ../../examples/regex-basics.pep}}
```

## Compiling a pattern

- `regex.Regex(pattern)` compiles a pattern and panics when it is invalid.
  Use it for patterns written in the program.
- `regex.Regex.parse(pattern)` returns a `Result<Regex>` instead, whose
  error names the problem and its byte offset:
  `invalid regex '(a': missing ')' at offset 0`. Use it for patterns that
  come from input.
- Compile once and reuse the `Regex`; compiling costs more than a search.
- `Regex.escape(text)` escapes every character with a meaning in a
  pattern, so the result matches `text` literally.

A pattern is a `String`, so each backslash is doubled in a string literal:
`"\\d+"` is the pattern `\d+`.

## Searching

| Method | Result |
|--------|--------|
| `is_match(text)` | whether there is a match anywhere; the fastest test |
| `find(text)` | the leftmost `Match`, or none |
| `find_at(text, start)` | the leftmost match starting at or after byte `start` |
| `find_all(text)` | an iterator over every match, left to right, without overlaps |
| `replace(text, replacement)` | `text` with the first match replaced |
| `replace_all(text, replacement)` | `text` with every match replaced |
| `split(text)` | the pieces of `text` between matches |

A `Match` has `text()`, `start()` and `end()` (byte offsets, as `String.find`
returns, for use with `substr_bytes`), and `group(index)` or `group(name)`,
which give the group's text or none when the group did not take part (as
`(a)` in `(a)|b` matching `b`). Group 0 is the whole match; groups are
numbered by their opening `(`. `group_range(index)` gives a group's offsets.

Matching is leftmost-first, as in Perl: the match that starts earliest wins,
and among those, a greedy repetition prefers more and alternation prefers
its earlier branch (`a|ab` finds `a` in `ab`).

`find_all` skips an empty match that comes right after the previous match,
so `a*` finds `a` twice in `aba`, not also an empty match between them.

In a replacement, `$1` or `${1}` stands for group 1, `${name}` for a named
group, `$0` for the whole match and `$$` for a `$`. A group that did not take
part gives empty text. Use braces when a digit or letter follows:
`${1}0`, not `$10`.

## Syntax

The syntax is RE2's, the one Go's `regexp` and Rust's `regex` crate use.

| Syntax | Matches |
|--------|---------|
| `.` | any code point except a newline (any at all with `(?s)`) |
| `[abc]`, `[a-z]`, `[^a-z]` | a code point in, or not in, the set |
| `[[:alpha:]]`, `[[:^digit:]]` | a POSIX class: `alnum`, `alpha`, `ascii`, `blank`, `cntrl`, `digit`, `graph`, `lower`, `print`, `punct`, `space`, `upper`, `word`, `xdigit` |
| `\d`, `\w`, `\s` | an ASCII digit, word character (`[0-9A-Za-z_]`), or space (`[\t\n\f\r ]`) |
| `\D`, `\W`, `\S` | anything else |
| `\n`, `\t`, `\r`, `\f`, `\v`, `\a` | a control character |
| `\x41`, `\x{1F642}` | the code point with that hexadecimal value |
| `\.`, `\*`, `\\`, ... | the punctuation character itself |
| `x*`, `x+`, `x?` | zero or more, one or more, zero or one |
| `x{n}`, `x{n,}`, `x{n,m}` | exactly `n`, at least `n`, from `n` to `m` (at most 1000) |
| `x*?`, `x+?`, `x??`, `x{n,m}?` | the same, preferring fewer (lazy) |
| `xy`, `x\|y` | `x` then `y`; `x` or `y` |
| `(x)` | a capture group |
| `(?<name>x)`, `(?P<name>x)` | a named capture group |
| `(?:x)` | a group that does not capture |
| `^`, `$` | the start and end of the text (of a line with `(?m)`) |
| `\A`, `\z` | the start and end of the text, always |
| `\b`, `\B` | an ASCII word boundary, and anything else |

Flags go in the pattern: `(?i)` makes the rest of the enclosing group
case-insensitive, `(?i:x)` only `x`, and `(?-i)` turns a flag off.

| Flag | Meaning |
|------|---------|
| `i` | case-insensitive (ASCII letters) |
| `m` | multi-line: `^` and `$` also match at line breaks |
| `s` | `.` also matches a newline |
| `U` | swap greedy and lazy: `x*` is lazy and `x*?` greedy |

## Text

- A pattern works on code points: `.` and `[^a]` match one whole code
  point, such as `é` or `🙂`, never part of one.
- `\d`, `\w`, `\s`, `\b`, the POSIX classes and case-insensitive matching
  are ASCII-only: `\w` does not match `é`.
- Positions are byte offsets, like `String.find` and `substr_bytes`, not the
  code point positions of `substr`.

## Linear time

Matching never backtracks. The engine (a Pike VM, as in RE2) steps every
possible match through the text together, so a search takes time
proportional to the size of the text times the size of the pattern,
whatever both are. A pattern such as `(a*)*b`, which takes exponential
time in a backtracking engine, is safe on untrusted input.

The price is two features that need backtracking. A pattern that uses one
fails to compile:

- **Backreferences** (`\1`): `backreferences are not supported`
- **Lookaround** (`(?=x)`, `(?!x)`, `(?<=x)`, `(?<!x)`):
  `lookaround is not supported`

Groups nest at most 250 deep, and a pattern whose compiled program would
exceed 100,000 instructions (from large counted repetitions such as
`(a{1000}){1000}`) is rejected.

## Threads

A `Regex` does not change after it is compiled, but it is not `[Shared]`
yet, so it stays on the thread that made it. Compile one on each thread
that needs it.

The [reference](../reference/regex-module.md) lists every method.
