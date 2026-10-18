<!-- Generated from runtime/io/glob.pep by `pep-doc reference`. Do not edit. -->

# Glob

Source: `runtime/io/glob.pep`

## glob_matches

```pepper
glob_matches(pattern: String, path: String): bool
```

Returns whether `path` matches the glob `pattern` as a whole.

The pattern language:

- `*` matches any run of characters within one path component (never a
  `/`), the empty run included.
- `?` matches one character (a code point) other than `/`.
- `**` as a whole component matches zero or more components, so
  `src/**/*.pep` matches `src/a.pep` and `src/x/y/a.pep`. Elsewhere it is
  the same as `*`.
- `[abc]` matches one of the characters listed, `[a-z]` one in the range,
  and `[!abc]` or `[^abc]` one not listed. A `]` right after the `[` (or
  the `!`) is listed rather than closing it.
- `{a,b}` matches either alternative; alternatives may hold any pattern,
  braces included.

`/` separates components in the pattern; on Windows `\` in `path` counts
as `/` too. There is no escape character, since it would clash with
Windows separators: `[*]` matches a literal `*`. An unclosed `[` or `{`
matches itself, so every pattern is valid. Matching is case-sensitive,
and `*` and `?` match a leading `.` like any other character.

**Parameters**
- `pattern` — the glob to match against
- `path` — the path to test, as text

**Returns**
- true when the whole of `path` matches

**Example**
```pepper
import io;

var yes = io.glob_matches("src/**/*.{pep,md}", "src/io/glob.pep");   # true
var no = io.glob_matches("*.pep", "src/main.pep");                  # false: `*` stops at `/`
```

## glob

```pepper
glob(pattern: String): Path[]
```

Returns the existing paths that match the glob `pattern`, sorted and
without duplicates. The pattern language is `glob_matches`'s.

The walk starts at the longest leading run of components without `*`,
`?`, `[` or `{`: `src/**/*.pep` lists only under `src`, and `*.pep` the
current directory. A relative pattern gives relative paths. `**` does not
descend into symlinked directories, so a link cycle cannot loop; other
components follow symlinks. Directories that cannot be read are skipped,
and a pattern whose start does not exist matches nothing.

**Parameters**
- `pattern` — the glob to expand

**Returns**
- the matching paths, joined with the platform separator, sorted by their text; empty when nothing matches

**Example**
```pepper
import io;

for (var source in io.glob("runtime/**/*.pep")) {
    print(source.to_string());
}
```
