<!-- Generated from runtime/io/path.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Path

Source: `runtime/io/path.pep`

## Path

```pepper
struct Path
```

An owned file-system path: the text of the path plus operations on it
(Rust's `Path` and `PathBuf` in one type).

Every method except `exists`, `is_file`, `is_dir`, `metadata`,
`symlink_metadata` and `canonicalize` is pure text manipulation: it never
touches the file system, so `..` is not resolved against symlinks and
nothing needs to exist. A part that may be missing comes back as an
optional, as in Rust: `parent()` of a root is none.

Breaking change: `parent()`, `file_name()`, `file_stem()`, `extension()`
and `dot_index()` used to return an empty Path or String (or
`name.size`) for "none"; they now return `Path?`, `String?` and
`ulong?`.

Separators: on POSIX only `/` separates components (`\` is an ordinary
byte of a name). On Windows both `/` and `\` separate, and a path may
start with a prefix: a drive (`C:`) or a UNC share (`\\server\share`).
Methods that build a path (`join`, `normalize`, `with_extension`) insert
the platform separator (`separator()`), but the rest of the text is kept
as written. Paths are UTF-8 Strings, scanned byte by byte; separators and
dots are ASCII, so splitting at them never cuts a character in two.

**Example**
```pepper
    import io;

    var p = io.Path("docs").join("guide.md");   # "docs/guide.md"
    var name = p.file_name().value();               # "guide.md"
    var ext = p.extension().value_or("");           # "md"
    var dir = p.parent();                           # some io.Path("docs")
    if (p.is_file()) {
        print(p.to_string());
    }
```

### Properties

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the path has no text at all. File-system operations
on the empty path fail.

### Constructor

#### Path()

```pepper
[Implicit] construct(value: String = "")
```

Creates a path holding `value` as is: no validation, normalization or
separator conversion.

The constructor is `[Implicit]`: a `String` (or a string literal)
converts to a `Path` wherever a `Path` is expected, so every API that
takes a `Path` also accepts text.

**Parameters**
- `value` — the path's text; the default, `""`, is the empty path

**Example**
```pepper
    import io;

    var p = io.Path("/usr/lib");
    var empty = io.Path();   # is_empty is true
    var q: io.Path = "docs";   # converted implicitly
```

### Static methods

#### separator

```pepper
static separator(): String
```

Returns the separator this platform inserts when it builds a path.

**Returns**
- `"/"` on POSIX, `"\"` on Windows (where `/` is also accepted as a separator on input)

#### dot_index

```pepper
static dot_index(name: String): ulong?
```

Returns the byte offset of the dot that starts the extension in the
file name `name`: the last `.` that is not the first byte. A leading
dot (`.bashrc`) starts the name, not an extension.

Breaking change: this used to return `name.size` for "no
extension"; it now returns none.

**Parameters**
- `name` — a file name (one component, as `file_name()` returns)

**Returns**
- the index of the extension's dot, or none when the name has no such dot (`noext`, `.bashrc`, the empty name)

### Methods

#### to_string

```pepper
to_string(): String
```

Returns the path's text, the same String the Path holds, not a copy.

**Returns**
- the path as a String

#### is_absolute

```pepper
is_absolute(): bool
```

Returns whether the path is absolute, meaning it does not depend on
the current directory. Pure text: the path need not exist.

On POSIX a path is absolute when it starts with `/`. On Windows it is
absolute when it has a drive followed by a root separator (`C:\x`,
`C:/x`) or is a UNC path (`\\server\share\x`); a root without a drive
(`\x`) and a drive without a root (`C:x`) are both relative. The empty
path is relative.

**Returns**
- true when the path is absolute

#### is_relative

```pepper
is_relative(): bool
```

Returns whether the path is relative: the opposite of
`is_absolute()`. The empty path is relative.

**Returns**
- true when the path is not absolute

#### join

```pepper
join(other: Path): Path
```

Returns this path with `other` appended as further components.

A platform separator is inserted between the two unless this path
already ends in one. If `other` is absolute, or (on Windows) starts
with a root separator or a drive or UNC prefix, it replaces this path
instead, as in Rust. Joining an empty `other` returns a copy of this
path; joining onto the empty path returns `other`. Nothing is
normalized: `a` joined with `../b` is `a/../b`.

**Parameters**
- `other` — the path to append

**Returns**
- a new Path; this path is not changed

**Example**
```pepper
    import io;

    var p = io.Path("usr").join(io.Path("lib"));   # "usr/lib" ("usr\lib" on Windows)
    var q = io.Path("a/").join(io.Path("b"));      # "a/b"
    var r = io.Path("a").join(io.Path("/abs"));    # "/abs"
    var so = io.Path("usr").join("lib").join("x.so");   # a String converts to a Path
```

#### join_str

```pepper
[Deprecated("use 'join', which accepts a String", "join")] join_str(other: String): Path
```

Returns this path with the String `other` appended, exactly like
`join(Path(other))`. Deprecated: `join` accepts a `String` directly,
since a `String` converts to a `Path` implicitly.

**Parameters**
- `other` — the path text to append

**Returns**
- a new Path; this path is not changed

**See also**
- `join`

**Example**
```pepper
    import io;

    var so = io.Path("usr").join("lib").join("x.so");   # "usr/lib/x.so"
```

#### has_root_or_prefix

```pepper
has_root_or_prefix(): bool
```

Returns whether the path starts with a root separator or, on Windows,
a drive or UNC prefix. This is what makes `join` replace instead of
append; unlike `is_absolute()` it is also true for Windows paths such
as `\x` and `C:x`. On POSIX it equals `is_absolute()`.

**Returns**
- true when the path has a root separator or a prefix

#### parent

```pepper
parent(): Path?
```

Returns the path without its last component. Pure text: `..` is not
resolved, so the parent of `a/..` is `a`.

Trailing and repeated separators before the last component are
dropped (`a/b/` and `a//b` both give `a`). The parent of a top-level
name keeps the root and prefix (`/a` gives `/`, `C:\x` gives `C:\`,
`C:x` gives `C:`).

Breaking change: this used to return the empty path for "no parent";
it now returns none.

**Returns**
- the parent path, or none for a root (`/`, `C:\`, a bare prefix such as `C:`), a bare name with no root (`a`, `.`, `..`), or the empty path

**Example**
```pepper
    import io;

    var p = io.Path("/a/b/c.txt").parent().value();   # "/a/b"
    var root = io.Path("/a").parent().value();        # "/"
    var none = io.Path("/").parent();                 # none
```

#### file_name

```pepper
file_name(): String?
```

Returns the last component of the path, ignoring trailing separators
(`a/b/` gives `b`).

Breaking change: this used to return `""` for "no file name"; it now
returns none.

**Returns**
- the last component, or none for a root (`/`, `C:\`), the empty path, or a path whose last component is `.` or `..`

**Example**
```pepper
    import io;

    var name = io.Path("/a/b/c.txt").file_name().value();   # "c.txt"
    var none = io.Path("a/..").file_name();                 # none
```

#### file_stem

```pepper
file_stem(): String?
```

Returns the file name without its extension: everything before the
last dot, unless that dot is the first character.

Breaking change: this used to return `""` for "no file name"; it now
returns none.

**Returns**
- the stem (`c.tar` for `c.tar.gz`, `.bashrc` for `.bashrc`, `foo` for `foo.`, `noext` for `noext`), or none when there is no file name (see `file_name()`)

#### extension

```pepper
extension(): String?
```

Returns the file name's extension, without its dot: the text after
the last dot, unless that dot is the first character. Only the file
name counts; a dot in a directory name (`a.b/c`) is not an extension.

Breaking change: this used to return `""` for "no extension"; it now
returns none. As in Rust, a name ending in a dot (`foo.`) has the
empty extension, which is not none.

**Returns**
- the extension (`gz` for `c.tar.gz`, `""` for `foo.`), or none when the file name has no dot after its first character (`noext`, `.bashrc`) or there is no file name

#### with_extension

```pepper
with_extension(ext: String): Path
```

Returns this path with its file name's extension replaced by `ext`,
added when it has none, or removed when `ext` is empty. Trailing
separators after the file name are dropped.

**Parameters**
- `ext` — the new extension without a leading dot (a dot is inserted; `".md"` would give `b..md`), or `""` to remove the extension

**Returns**
- the new path, or a copy of this path unchanged when it has no file name (a root, `.`, `..`, or the empty path)

**Example**
```pepper
    import io;

    var md = io.Path("a/b.txt").with_extension("md");   # "a/b.md"
    var rs = io.Path("a/b").with_extension("rs");       # "a/b.rs"
    var bare = io.Path("a/b.txt").with_extension("");   # "a/b"
```

#### components

```pepper
components(): Array<String>
```

Returns the path split into its components: the prefix (Windows drive
or UNC share, such as `C:`), then the root separator (one character,
as written), then each non-empty part between separators.

Repeated and trailing separators produce no empty parts. `.` parts
are dropped, except a leading one in a path with no prefix or root
(`./a` gives `.` and `a`). `..` parts are kept as they are.

**Returns**
- the components in order; empty for the empty path

**Example**
```pepper
    import io;

    var c = io.Path("/usr//lib/./x/").components();   # ["/", "usr", "lib", "x"]
    var d = io.Path("./a/b").components();            # [".", "a", "b"]
```

#### normalize

```pepper
normalize(): Path
```

Returns the path cleaned up lexically, without touching the file
system: `.` parts and repeated or trailing separators are dropped, and
each `..` removes the part before it.

A `..` cannot climb above a root (`/../x` gives `/x`) and is kept at
the start of a relative path (`../a/..` gives `..`). The prefix is
kept, and every separator becomes the platform separator. Because
symlinks are not consulted, `link/..` becomes `.` even when `link`
points elsewhere; use `canonicalize()` for the path the file system
resolves.

**Returns**
- the normalized path; `.` when the path cleans to nothing (`a/..`, `./`), and the empty path for the empty path

**See also**
- `canonicalize`

**Example**
```pepper
    import io;

    var p = io.Path("a/./b/../c").normalize();   # "a/c" ("a\c" on Windows)
    var q = io.Path("a/..").normalize();         # "."
```

#### exists

```pepper
exists(): bool
```

Returns whether something exists at this path, following symlinks. A
relative path is resolved against the current directory.

Any error counts as not existing: a dangling symlink, a path under a
directory that cannot be read, and the empty path all give false. Use
`metadata()` to tell those apart.

**Returns**
- true when the path (or a symlink's target) can be stat'ed

#### is_file

```pepper
is_file(): bool
```

Returns whether the path names a regular file, following symlinks.

**Returns**
- true for a regular file or a symlink to one; false for anything else, and on any error (including a missing path)

#### is_directory

```pepper
is_directory(): bool
```

Returns whether the path names a directory, following symlinks.

**Returns**
- true for a directory or a symlink to one; false for anything else, and on any error (including a missing path)

#### is_dir

```pepper
[Deprecated("use 'is_directory' instead", "is_directory")] is_dir(): bool
```

Deprecated: use `is_directory` instead. Returns whether the path
names a directory, following symlinks.

**Returns**
- the same as `is_directory()`

#### metadata

```pepper
metadata(): IoResult<Metadata>
```

Returns the metadata of the file or directory at this path, following
symlinks: the result describes the target (so on POSIX `is_symlink` is
always false). `stat` / `statx` on POSIX; on Windows the path is
opened for attributes only.

**Returns**
- the `Metadata` of the path (or of a symlink's target); an error when the path cannot be stat'ed: `is_not_found()` when it (or a symlink's target) is missing or the path is empty, `is_permission_denied()` when a directory on the way cannot be searched, and on POSIX `is_not_a_directory()` when a file is used as a directory in the middle of the path

**See also**
- `symlink_metadata`

**Example**
```pepper
    import io;

    var m = io.Path("data.bin").metadata();
    if (m.is_ok()) {
        var size = m.value().size;
    }
```

#### symlink_metadata

```pepper
symlink_metadata(): IoResult<Metadata>
```

Returns the metadata of the path itself without following a symlink
at the end of it, so for a symlink `is_symlink` is true and the rest
describes the link rather than its target. `lstat` / `statx` with
`AT_SYMLINK_NOFOLLOW` on POSIX; on Windows the path is opened with
`FILE_FLAG_OPEN_REPARSE_POINT`, and any reparse point (junctions
included) reports `is_symlink`, together with `is_directory` for a directory
link. For anything that is not a symlink it equals `metadata()`.

**Returns**
- the `Metadata` of the path itself; an error as for `metadata()`, except that a dangling symlink succeeds

**See also**
- `metadata`

#### canonicalize

```pepper
canonicalize(): IoResult<Path>
```

Returns the absolute path the file system resolves this path to:
relative to the current directory, with every symlink, `.` and `..`
resolved. Unlike `normalize()`, the path must exist.

POSIX uses `realpath`. Windows opens the path and asks for its final
name; the result uses `\`, and the `\\?\` prefix Windows reports is
removed (`\\?\UNC\server\share` becomes `\\server\share`).

**Returns**
- the canonical absolute path; an error when the path cannot be resolved: `is_not_found()` when it (or a symlink's target) is missing or the path is empty, `is_permission_denied()` when a directory on the way cannot be searched

**See also**
- `normalize`

**Example**
```pepper
    import io;

    var real = io.Path("a/../b.txt").canonicalize();
    if (real.is_ok()) {
        print(real.value().to_string());
    }
```

#### operator ==

```pepper
==(rhs: Path): bool
```

Returns whether two paths have exactly the same text. The comparison
is byte by byte, with no normalization and case-sensitive on every
platform: `a/b` differs from `a//b`, from `a/b/`, and (on Windows)
from `a\b` and `A/b`. Compare `normalize()` or `canonicalize()`
results to ignore spelling differences.

**Parameters**
- `rhs` — the path to compare with

**Returns**
- true when both paths' texts are equal

#### operator !=

```pepper
!=(rhs: Path): bool
```

Returns whether two paths differ in their text: the opposite of `==`,
with the same byte-by-byte comparison.

**Parameters**
- `rhs` — the path to compare with

**Returns**
- true when the paths' texts differ
