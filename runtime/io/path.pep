# Path: an owned file-system path (Rust's `Path` + `PathBuf` in one type).
#
# Everything except exists/is_file/is_dir/metadata/symlink_metadata/
# canonicalize is pure string manipulation. Paths are scanned byte by byte:
# separators and dots are ASCII, so splitting at them never cuts a UTF-8
# sequence. "No value" is an Optional (`Path?`, `String?`, `ulong?`) that is
# none, as in Rust; the empty Path is an ordinary (relative) path.
#
# Bytes are read through `_io_byte`, which is bounds-checked (an empty String
# has no buffer at all).

import "file";
import "sys_posix";
import "sys_windows";
import "types";

# ── Path syntax per platform (pure; no C calls) ─────────────────────────────

[Target(!OS(Windows))]
export _io_path_is_sep(b: int): bool {
    return b == '/';
}

[Target(OS(Windows))]
export _io_path_is_sep(b: int): bool {
    return b == '/' || b == '\\';
}

[Target(!OS(Windows))]
export _io_path_separator(): String {
    return "/";
}

[Target(OS(Windows))]
export _io_path_separator(): String {
    return "\\";
}

# Length of the prefix before any root separator: always 0 on POSIX; on
# Windows a drive (`C:`) or a UNC `\\server\share`.
[Target(!OS(Windows))]
export _io_path_prefix_len(p: __ptr<u8>, n: ulong): ulong {
    return 0;
}

[Target(OS(Windows))]
export _io_path_prefix_len(p: __ptr<u8>, n: ulong): ulong {
    if (_io_byte(p, n, 1) == ':') {
        var c = _io_byte(p, n, 0) | 32;  # ASCII lower case
        if (c >= 'a' && c <= 'z') {
            return 2;
        }
    }
    if (_io_path_is_sep(_io_byte(p, n, 0)) && _io_path_is_sep(_io_byte(p, n, 1))) {
        # \\server\share: the prefix runs through the share name.
        ulong i = 2;
        while (i < n && !_io_path_is_sep(_io_byte(p, n, i))) {
            i = i + 1;
        }
        if (i < n) {
            i = i + 1;
        }
        while (i < n && !_io_path_is_sep(_io_byte(p, n, i))) {
            i = i + 1;
        }
        return i;
    }
    return 0;
}

# True when a path with this prefix and root is absolute. POSIX: it has a
# root. Windows: a drive with a root (`C:\x`) or any UNC path.
[Target(!OS(Windows))]
export _io_path_absolute(p: __ptr<u8>, prefix: ulong, has_root: bool): bool {
    return has_root;
}

[Target(OS(Windows))]
export _io_path_absolute(p: __ptr<u8>, prefix: ulong, has_root: bool): bool {
    if (prefix > 2) {
        return true;  # UNC
    }
    return prefix == 2 && has_root;
}

# ── Byte-level helpers ───────────────────────────────────────────────────────

export _io_slice(s: String, begin: ulong, end: ulong): String {
    if (end <= begin) {
        return String();
    }
    return _io_string_from(s.c_str() + begin, end - begin);
}

# End of the prefix plus any root separators: the part no operation strips.
export _io_path_root_end(s: String): ulong {
    var p = unsafe_cast<__ptr<u8>>(s.c_str());
    var n = s.size;
    var i = _io_path_prefix_len(p, n);
    while (i < n && _io_path_is_sep(_io_byte(p, n, i))) {
        i = i + 1;
    }
    return i;
}

# End of the path with trailing separators removed (never inside the root).
export _io_path_trimmed_end(s: String): ulong {
    var p = unsafe_cast<__ptr<u8>>(s.c_str());
    var root = _io_path_root_end(s);
    var e = s.size;
    while (e > root && _io_path_is_sep(_io_byte(p, s.size, e - 1))) {
        e = e - 1;
    }
    return e;
}

# Start of the last component (== root end when there is no separator).
export _io_path_name_start(s: String, e: ulong): ulong {
    var p = unsafe_cast<__ptr<u8>>(s.c_str());
    var root = _io_path_root_end(s);
    var i = e;
    while (i > root && !_io_path_is_sep(_io_byte(p, s.size, i - 1))) {
        i = i - 1;
    }
    return i;
}

# The components after the prefix and root, split at separators, with empty
# parts dropped. `.` parts are dropped too unless `keep_leading_dot` and the
# path starts with one.
export _io_path_parts(s: String, keep_leading_dot: bool): String[] {
    var parts = Array<String>();
    var p = unsafe_cast<__ptr<u8>>(s.c_str());
    var n = s.size;
    var i = _io_path_root_end(s);
    var first = true;
    while (i < n) {
        var j = i;
        while (j < n && !_io_path_is_sep(_io_byte(p, n, j))) {
            j = j + 1;
        }
        if (j > i) {
            var part = _io_slice(s, i, j);
            if (part != "." || (first && keep_leading_dot)) {
                parts.append(part);
            }
            first = false;
        }
        i = j + 1;
    }
    return parts;
}

## An owned file-system path: the text of the path plus operations on it
## (Rust's `Path` and `PathBuf` in one type).
##
## Every method except `exists`, `is_file`, `is_dir`, `metadata`,
## `symlink_metadata` and `canonicalize` is pure text manipulation: it never
## touches the file system, so `..` is not resolved against symlinks and
## nothing needs to exist. A part that may be missing comes back as an
## optional, as in Rust: `parent()` of a root is none.
##
## Breaking change: `parent()`, `file_name()`, `file_stem()`, `extension()`
## and `dot_index()` used to return an empty Path or String (or
## `name.size`) for "none"; they now return `Path?`, `String?` and
## `ulong?`.
##
## Separators: on POSIX only `/` separates components (`\` is an ordinary
## byte of a name). On Windows both `/` and `\` separate, and a path may
## start with a prefix: a drive (`C:`) or a UNC share (`\\server\share`).
## Methods that build a path (`join`, `normalize`, `with_extension`) insert
## the platform separator (`separator()`), but the rest of the text is kept
## as written. Paths are UTF-8 Strings, scanned byte by byte; separators and
## dots are ASCII, so splitting at them never cuts a character in two.
##
## @example
##     import io;
##
##     var p = io.Path("docs").join("guide.md");   # "docs/guide.md"
##     var name = p.file_name().value();               # "guide.md"
##     var ext = p.extension().value_or("");           # "md"
##     var dir = p.parent();                           # some io.Path("docs")
##     if (p.is_file()) {
##         print(p.to_string());
##     }
export struct Path {
    ## The path's text, exactly as given or built: UTF-8, not normalized,
    ## possibly empty.
    String _value;

    ## Creates a path holding `value` as is: no validation, normalization or
    ## separator conversion.
    ##
    ## The constructor is `[Implicit]`: a `String` (or a string literal)
    ## converts to a `Path` wherever a `Path` is expected, so every API that
    ## takes a `Path` also accepts text.
    ##
    ## @param value the path's text; the default, `""`, is the empty path
    ## @example
    ##     import io;
    ##
    ##     var p = io.Path("/usr/lib");
    ##     var empty = io.Path();   # is_empty is true
    ##     var q: io.Path = "docs";   # converted implicitly
    [Implicit]
    construct(value: String = "") {
        this._value = value;
    }

    ## Returns the separator this platform inserts when it builds a path.
    ##
    ## @returns `"/"` on POSIX, `"\"` on Windows (where `/` is also accepted
    ## as a separator on input)
    static separator(): String {
        return _io_path_separator();
    }

    ## Returns the path's text, the same String the Path holds, not a copy.
    ##
    ## @returns the path as a String
    to_string(): String {
        return _value;
    }

    ## Whether the path has no text at all. File-system operations
    ## on the empty path fail.
    var is_empty: bool {
        get {
            return _value.size == 0;
        }
    }

    ## Returns whether the path is absolute, meaning it does not depend on
    ## the current directory. Pure text: the path need not exist.
    ##
    ## On POSIX a path is absolute when it starts with `/`. On Windows it is
    ## absolute when it has a drive followed by a root separator (`C:\x`,
    ## `C:/x`) or is a UNC path (`\\server\share\x`); a root without a drive
    ## (`\x`) and a drive without a root (`C:x`) are both relative. The empty
    ## path is relative.
    ##
    ## @returns true when the path is absolute
    is_absolute(): bool {
        var p = unsafe_cast<__ptr<u8>>(_value.c_str());
        var n = _value.size;
        var prefix = _io_path_prefix_len(p, n);
        var has_root = _io_path_is_sep(_io_byte(p, n, prefix));
        return _io_path_absolute(p, prefix, has_root);
    }

    ## Returns whether the path is relative: the opposite of
    ## `is_absolute()`. The empty path is relative.
    ##
    ## @returns true when the path is not absolute
    is_relative(): bool {
        return !is_absolute();
    }

    ## Returns this path with `other` appended as further components.
    ##
    ## A platform separator is inserted between the two unless this path
    ## already ends in one. If `other` is absolute, or (on Windows) starts
    ## with a root separator or a drive or UNC prefix, it replaces this path
    ## instead, as in Rust. Joining an empty `other` returns a copy of this
    ## path; joining onto the empty path returns `other`. Nothing is
    ## normalized: `a` joined with `../b` is `a/../b`.
    ##
    ## @param other the path to append
    ## @returns a new Path; this path is not changed
    ## @example
    ##     import io;
    ##
    ##     var p = io.Path("usr").join(io.Path("lib"));   # "usr/lib" ("usr\lib" on Windows)
    ##     var q = io.Path("a/").join(io.Path("b"));      # "a/b"
    ##     var r = io.Path("a").join(io.Path("/abs"));    # "/abs"
    ##     var so = io.Path("usr").join("lib").join("x.so");   # a String converts to a Path
    join(other: Path): Path {
        if (other._value.size == 0) {
            return Path(_value.copy());
        }
        if (_value.size == 0 || other.is_absolute() || other.has_root_or_prefix()) {
            return Path(other._value.copy());
        }
        var p = unsafe_cast<__ptr<u8>>(_value.c_str());
        var s = _value.copy();
        if (!_io_path_is_sep(_io_byte(p, _value.size, _value.size - 1))) {
            s.append(_io_path_separator());
        }
        s.append(other._value);
        return Path(s);
    }

    ## Returns this path with the String `other` appended, exactly like
    ## `join(Path(other))`. Deprecated: `join` accepts a `String` directly,
    ## since a `String` converts to a `Path` implicitly.
    ##
    ## @param other the path text to append
    ## @returns a new Path; this path is not changed
    ## @example
    ##     import io;
    ##
    ##     var so = io.Path("usr").join("lib").join("x.so");   # "usr/lib/x.so"
    ## @see join
    [Deprecated("use 'join', which accepts a String", "join")]
    join_str(other: String): Path {
        return join(Path(other));
    }

    ## Returns whether the path starts with a root separator or, on Windows,
    ## a drive or UNC prefix. This is what makes `join` replace instead of
    ## append; unlike `is_absolute()` it is also true for Windows paths such
    ## as `\x` and `C:x`. On POSIX it equals `is_absolute()`.
    ##
    ## @returns true when the path has a root separator or a prefix
    has_root_or_prefix(): bool {
        var p = unsafe_cast<__ptr<u8>>(_value.c_str());
        var n = _value.size;
        if (_io_path_prefix_len(p, n) > 0) {
            return true;
        }
        return _io_path_is_sep(_io_byte(p, n, 0));
    }

    ## Returns the path without its last component. Pure text: `..` is not
    ## resolved, so the parent of `a/..` is `a`.
    ##
    ## Trailing and repeated separators before the last component are
    ## dropped (`a/b/` and `a//b` both give `a`). The parent of a top-level
    ## name keeps the root and prefix (`/a` gives `/`, `C:\x` gives `C:\`,
    ## `C:x` gives `C:`).
    ##
    ## Breaking change: this used to return the empty path for "no parent";
    ## it now returns none.
    ##
    ## @returns the parent path, or none for a root (`/`, `C:\`, a bare
    ## prefix such as `C:`), a bare name with no root (`a`, `.`, `..`), or
    ## the empty path
    ## @example
    ##     import io;
    ##
    ##     var p = io.Path("/a/b/c.txt").parent().value();   # "/a/b"
    ##     var root = io.Path("/a").parent().value();        # "/"
    ##     var none = io.Path("/").parent();                 # none
    parent(): Path? {
        var root = _io_path_root_end(_value);
        var e = _io_path_trimmed_end(_value);
        if (e <= root) {
            return Optional<Path>.Empty;
        }
        var start = _io_path_name_start(_value, e);
        if (start <= root) {
            if (root == 0) {
                return Optional<Path>.Empty;
            }
            return Optional<Path>.Value(Path(_io_slice(_value, 0, root)));
        }
        var p = unsafe_cast<__ptr<u8>>(_value.c_str());
        var j = start;
        while (j > root && _io_path_is_sep(_io_byte(p, _value.size, j - 1))) {
            j = j - 1;
        }
        return Optional<Path>.Value(Path(_io_slice(_value, 0, j)));
    }

    ## Returns the last component of the path, ignoring trailing separators
    ## (`a/b/` gives `b`).
    ##
    ## Breaking change: this used to return `""` for "no file name"; it now
    ## returns none.
    ##
    ## @returns the last component, or none for a root (`/`, `C:\`), the
    ## empty path, or a path whose last component is `.` or `..`
    ## @example
    ##     import io;
    ##
    ##     var name = io.Path("/a/b/c.txt").file_name().value();   # "c.txt"
    ##     var none = io.Path("a/..").file_name();                 # none
    file_name(): String? {
        var root = _io_path_root_end(_value);
        var e = _io_path_trimmed_end(_value);
        if (e <= root) {
            return Optional<String>.Empty;
        }
        var name = _io_slice(_value, _io_path_name_start(_value, e), e);
        if (name == "." || name == "..") {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(name);
    }

    ## Returns the byte offset of the dot that starts the extension in the
    ## file name `name`: the last `.` that is not the first byte. A leading
    ## dot (`.bashrc`) starts the name, not an extension.
    ##
    ## Breaking change: this used to return `name.size` for "no
    ## extension"; it now returns none.
    ##
    ## @param name a file name (one component, as `file_name()` returns)
    ## @returns the index of the extension's dot, or none when the name has
    ## no such dot (`noext`, `.bashrc`, the empty name)
    static dot_index(name: String): ulong? {
        # A dot at 0 starts a hidden file's name, not an extension.
        var dot = name.rfind(".");
        if (dot > 0) {
            return Optional<ulong>.Value(dot as ulong);
        }
        return Optional<ulong>.Empty;
    }

    ## Returns the file name without its extension: everything before the
    ## last dot, unless that dot is the first character.
    ##
    ## Breaking change: this used to return `""` for "no file name"; it now
    ## returns none.
    ##
    ## @returns the stem (`c.tar` for `c.tar.gz`, `.bashrc` for `.bashrc`,
    ## `foo` for `foo.`, `noext` for `noext`), or none when there is no file
    ## name (see `file_name()`)
    file_stem(): String? {
        var name = file_name();
        if (!name) {
            return Optional<String>.Empty;
        }
        var text = name.value();
        var dot = Path.dot_index(text).value_or(text.size);
        return Optional<String>.Value(_io_slice(text, 0, dot));
    }

    ## Returns the file name's extension, without its dot: the text after
    ## the last dot, unless that dot is the first character. Only the file
    ## name counts; a dot in a directory name (`a.b/c`) is not an extension.
    ##
    ## Breaking change: this used to return `""` for "no extension"; it now
    ## returns none. As in Rust, a name ending in a dot (`foo.`) has the
    ## empty extension, which is not none.
    ##
    ## @returns the extension (`gz` for `c.tar.gz`, `""` for `foo.`), or none
    ## when the file name has no dot after its first character (`noext`,
    ## `.bashrc`) or there is no file name
    extension(): String? {
        var name = file_name();
        if (!name) {
            return Optional<String>.Empty;
        }
        var text = name.value();
        var dot = Path.dot_index(text);
        if (!dot) {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(_io_slice(text, dot.value() + 1, text.size));
    }

    ## Returns this path with its file name's extension replaced by `ext`,
    ## added when it has none, or removed when `ext` is empty. Trailing
    ## separators after the file name are dropped.
    ##
    ## @param ext the new extension without a leading dot (a dot is inserted;
    ## `".md"` would give `b..md`), or `""` to remove the extension
    ## @returns the new path, or a copy of this path unchanged when it has no
    ## file name (a root, `.`, `..`, or the empty path)
    ## @example
    ##     import io;
    ##
    ##     var md = io.Path("a/b.txt").with_extension("md");   # "a/b.md"
    ##     var rs = io.Path("a/b").with_extension("rs");       # "a/b.rs"
    ##     var bare = io.Path("a/b.txt").with_extension("");   # "a/b"
    with_extension(ext: String): Path {
        var stem = file_stem();
        if (!stem) {
            return Path(_value.copy());
        }
        var e = _io_path_trimmed_end(_value);
        var start = _io_path_name_start(_value, e);
        var s = _io_slice(_value, 0, start);
        s.append(stem.value());
        if (ext.size > 0) {
            s.append(".");
            s.append(ext);
        }
        return Path(s);
    }

    ## Returns the path split into its components: the prefix (Windows drive
    ## or UNC share, such as `C:`), then the root separator (one character,
    ## as written), then each non-empty part between separators.
    ##
    ## Repeated and trailing separators produce no empty parts. `.` parts
    ## are dropped, except a leading one in a path with no prefix or root
    ## (`./a` gives `.` and `a`). `..` parts are kept as they are.
    ##
    ## @returns the components in order; empty for the empty path
    ## @example
    ##     import io;
    ##
    ##     var c = io.Path("/usr//lib/./x/").components();   # ["/", "usr", "lib", "x"]
    ##     var d = io.Path("./a/b").components();            # [".", "a", "b"]
    components(): Array<String> {
        var out = Array<String>();
        var p = unsafe_cast<__ptr<u8>>(_value.c_str());
        var n = _value.size;
        var prefix = _io_path_prefix_len(p, n);
        if (prefix > 0) {
            out.append(_io_slice(_value, 0, prefix));
        }
        var has_root = _io_path_is_sep(_io_byte(p, n, prefix));
        if (has_root) {
            out.append(_io_slice(_value, prefix, prefix + 1));
        }
        var parts = _io_path_parts(_value, prefix == 0 && !has_root);
        out.append_all(parts);
        return out;
    }

    ## Returns the path cleaned up lexically, without touching the file
    ## system: `.` parts and repeated or trailing separators are dropped, and
    ## each `..` removes the part before it.
    ##
    ## A `..` cannot climb above a root (`/../x` gives `/x`) and is kept at
    ## the start of a relative path (`../a/..` gives `..`). The prefix is
    ## kept, and every separator becomes the platform separator. Because
    ## symlinks are not consulted, `link/..` becomes `.` even when `link`
    ## points elsewhere; use `canonicalize()` for the path the file system
    ## resolves.
    ##
    ## @returns the normalized path; `.` when the path cleans to nothing
    ## (`a/..`, `./`), and the empty path for the empty path
    ## @example
    ##     import io;
    ##
    ##     var p = io.Path("a/./b/../c").normalize();   # "a/c" ("a\c" on Windows)
    ##     var q = io.Path("a/..").normalize();         # "."
    ## @see canonicalize
    normalize(): Path {
        if (_value.size == 0) {
            return Path();
        }
        var p = unsafe_cast<__ptr<u8>>(_value.c_str());
        var n = _value.size;
        var prefix = _io_path_prefix_len(p, n);
        var has_root = _io_path_is_sep(_io_byte(p, n, prefix));
        var parts = _io_path_parts(_value, false);
        var kept = Array<String>();
        ulong k = 0;
        while (k < parts.count) {
            var part = parts[k];
            k = k + 1;
            if (part == "..") {
                var climb = false;
                if (kept.count > 0) {
                    climb = kept.last() != "..";
                }
                if (climb) {
                    kept.pop();
                } else {
                    if (!has_root) {
                        kept.append(part);
                    }
                }
            } else {
                kept.append(part);
            }
        }
        var sep = _io_path_separator();
        var s = _io_slice(_value, 0, prefix);
        if (has_root) {
            s.append(sep);
        }
        ulong i = 0;
        while (i < kept.count) {
            if (i > 0) {
                s.append(sep);
            }
            s.append(kept[i]);
            i = i + 1;
        }
        if (s.size == 0) {
            s = ".";
        }
        return Path(s);
    }

    ## Returns whether something exists at this path, following symlinks. A
    ## relative path is resolved against the current directory.
    ##
    ## Any error counts as not existing: a dangling symlink, a path under a
    ## directory that cannot be read, and the empty path all give false. Use
    ## `metadata()` to tell those apart.
    ##
    ## @returns true when the path (or a symlink's target) can be stat'ed
    exists(): bool {
        return _io_sys_stat(this, true).is_ok();
    }

    ## Returns whether the path names a regular file, following symlinks.
    ##
    ## @returns true for a regular file or a symlink to one; false for
    ## anything else, and on any error (including a missing path)
    is_file(): bool {
        var r = _io_sys_stat(this, true);
        if (r.is_err()) {
            return false;
        }
        return r.value().is_file;
    }

    ## Returns whether the path names a directory, following symlinks.
    ##
    ## @returns true for a directory or a symlink to one; false for anything
    ## else, and on any error (including a missing path)
    is_directory(): bool {
        var r = _io_sys_stat(this, true);
        if (r.is_err()) {
            return false;
        }
        return r.value().is_directory;
    }

    ## Deprecated: use `is_directory` instead. Returns whether the path
    ## names a directory, following symlinks.
    ##
    ## @returns the same as `is_directory()`
    [Deprecated("use 'is_directory' instead", "is_directory")]
    is_dir(): bool {
        return is_directory();
    }

    ## Returns the metadata of the file or directory at this path, following
    ## symlinks: the result describes the target (so on POSIX `is_symlink` is
    ## always false). `stat` / `statx` on POSIX; on Windows the path is
    ## opened for attributes only.
    ##
    ## @returns the `Metadata` of the path (or of a symlink's target); an
    ## error when the path cannot be stat'ed: `is_not_found()` when it (or a
    ## symlink's target) is missing or the path is empty,
    ## `is_permission_denied()` when a directory on the way cannot be
    ## searched, and on POSIX `is_not_a_directory()` when a file is used as
    ## a directory in the middle of the path
    ## @example
    ##     import io;
    ##
    ##     var m = io.Path("data.bin").metadata();
    ##     if (m.is_ok()) {
    ##         var size = m.value().size;
    ##     }
    ## @see symlink_metadata
    metadata(): IoResult<Metadata> {
        return _io_sys_stat(this, true);
    }

    ## Returns the metadata of the path itself without following a symlink
    ## at the end of it, so for a symlink `is_symlink` is true and the rest
    ## describes the link rather than its target. `lstat` / `statx` with
    ## `AT_SYMLINK_NOFOLLOW` on POSIX; on Windows the path is opened with
    ## `FILE_FLAG_OPEN_REPARSE_POINT`, and any reparse point (junctions
    ## included) reports `is_symlink`, together with `is_directory` for a directory
    ## link. For anything that is not a symlink it equals `metadata()`.
    ##
    ## @returns the `Metadata` of the path itself; an error as for
    ## `metadata()`, except that a dangling symlink succeeds
    ## @see metadata
    symlink_metadata(): IoResult<Metadata> {
        return _io_sys_stat(this, false);
    }

    ## Returns the absolute path the file system resolves this path to:
    ## relative to the current directory, with every symlink, `.` and `..`
    ## resolved. Unlike `normalize()`, the path must exist.
    ##
    ## POSIX uses `realpath`. Windows opens the path and asks for its final
    ## name; the result uses `\`, and the `\\?\` prefix Windows reports is
    ## removed (`\\?\UNC\server\share` becomes `\\server\share`).
    ##
    ## @returns the canonical absolute path; an error when the path cannot
    ## be resolved: `is_not_found()` when it (or a symlink's target) is
    ## missing or the path is empty, `is_permission_denied()` when a
    ## directory on the way cannot be searched
    ## @example
    ##     import io;
    ##
    ##     var real = io.Path("a/../b.txt").canonicalize();
    ##     if (real.is_ok()) {
    ##         print(real.value().to_string());
    ##     }
    ## @see normalize
    canonicalize(): IoResult<Path> {
        return _io_sys_realpath(this);
    }

    ## Returns whether two paths have exactly the same text. The comparison
    ## is byte by byte, with no normalization and case-sensitive on every
    ## platform: `a/b` differs from `a//b`, from `a/b/`, and (on Windows)
    ## from `a\b` and `A/b`. Compare `normalize()` or `canonicalize()`
    ## results to ignore spelling differences.
    ##
    ## @param rhs the path to compare with
    ## @returns true when both paths' texts are equal
    ==(rhs: Path): bool {
        return _value == rhs._value;
    }

    ## Returns whether two paths differ in their text: the opposite of `==`,
    ## with the same byte-by-byte comparison.
    ##
    ## @param rhs the path to compare with
    ## @returns true when the paths' texts differ
    !=(rhs: Path): bool {
        return !(_value == rhs._value);
    }
}

extend Path with ToString;
