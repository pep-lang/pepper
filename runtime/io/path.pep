# Path: an owned file-system path (Rust's `Path` + `PathBuf` in one type).
#
# Everything except exists/is_file/is_dir/metadata/symlink_metadata/
# canonicalize is pure string manipulation. Paths are scanned byte by byte:
# separators and dots are ASCII, so splitting at them never cuts a UTF-8
# sequence. "No value" is the empty Path / String (there is no Option).
#
# `&&` and `||` evaluate both operands, so bytes are read through `_io_byte`,
# which is bounds-checked (an empty String has no buffer at all).

import "types";
import "file";
import "sys_posix";
import "sys_windows";

# ── Path syntax per platform (pure; no C calls) ─────────────────────────────

[Target(!OS(Windows))] export _io_path_is_sep(b: int): bool {
    return b == 47;   # '/'
}
[Target(OS(Windows))] export _io_path_is_sep(b: int): bool {
    return b == 47 || b == 92;   # '/' or '\'
}

[Target(!OS(Windows))] export _io_path_separator(): String {
    return "/";
}
[Target(OS(Windows))] export _io_path_separator(): String {
    # String literals have no escape sequences: build "\" from its byte.
    return _io_string_from_byte(92);
}

# Length of the prefix before any root separator: always 0 on POSIX; on
# Windows a drive (`C:`) or a UNC `\\server\share`.
[Target(!OS(Windows))] export _io_path_prefix_len(p: __ptr<u8>, n: ulong): ulong {
    return 0;
}
[Target(OS(Windows))] export _io_path_prefix_len(p: __ptr<u8>, n: ulong): ulong {
    if (_io_byte(p, n, 1) == 58) {   # ':'
        var c = _io_byte(p, n, 0) | 32;   # ASCII lower case
        if (c >= 97 && c <= 122) {
            return 2;
        }
    }
    if (_io_path_is_sep(_io_byte(p, n, 0)) && _io_path_is_sep(_io_byte(p, n, 1))) {
        # \\server\share: the prefix runs through the share name.
        ulong i = 2;
        while (i < n && !_io_path_is_sep(_io_byte(p, n, i))) { i = i + 1; }
        if (i < n) { i = i + 1; }
        while (i < n && !_io_path_is_sep(_io_byte(p, n, i))) { i = i + 1; }
        return i;
    }
    return 0;
}

# True when a path with this prefix and root is absolute. POSIX: it has a
# root. Windows: a drive with a root (`C:\x`) or any UNC path.
[Target(!OS(Windows))] export _io_path_absolute(p: __ptr<u8>, prefix: ulong, has_root: bool): bool {
    return has_root;
}
[Target(OS(Windows))] export _io_path_absolute(p: __ptr<u8>, prefix: ulong, has_root: bool): bool {
    if (prefix > 2) {
        return true;   # UNC
    }
    return prefix == 2 && has_root;
}

# ── Byte-level helpers ───────────────────────────────────────────────────────

export _io_slice(s: String, begin: ulong, end: ulong): String {
    if (end <= begin) {
        return String();
    }
    return _io_string_from(s.Data + begin, end - begin);
}

# End of the prefix plus any root separators: the part no operation strips.
export _io_path_root_end(s: String): ulong {
    var p = s.Data as __ptr<u8>;
    var n = s.Size;
    var i = _io_path_prefix_len(p, n);
    while (i < n && _io_path_is_sep(_io_byte(p, n, i))) { i = i + 1; }
    return i;
}

# End of the path with trailing separators removed (never inside the root).
export _io_path_trimmed_end(s: String): ulong {
    var p = s.Data as __ptr<u8>;
    var root = _io_path_root_end(s);
    var e = s.Size;
    while (e > root && _io_path_is_sep(_io_byte(p, s.Size, e - 1))) { e = e - 1; }
    return e;
}

# Start of the last component (== root end when there is no separator).
export _io_path_name_start(s: String, e: ulong): ulong {
    var p = s.Data as __ptr<u8>;
    var root = _io_path_root_end(s);
    var i = e;
    while (i > root && !_io_path_is_sep(_io_byte(p, s.Size, i - 1))) { i = i - 1; }
    return i;
}

export _io_is_dot(s: String): bool {
    var p = s.Data as __ptr<u8>;
    return s.Size == 1 && _io_byte(p, s.Size, 0) == 46;
}

export _io_is_dotdot(s: String): bool {
    var p = s.Data as __ptr<u8>;
    return s.Size == 2 && _io_byte(p, s.Size, 0) == 46 && _io_byte(p, s.Size, 1) == 46;
}

# The components after the prefix and root, split at separators, with empty
# parts dropped. `.` parts are dropped too unless `keep_leading_dot` and the
# path starts with one.
export _io_path_parts(s: String, keep_leading_dot: bool): String[] {
    var parts = Array<String>();
    var p = s.Data as __ptr<u8>;
    var n = s.Size;
    var i = _io_path_root_end(s);
    var first = true;
    while (i < n) {
        var j = i;
        while (j < n && !_io_path_is_sep(_io_byte(p, n, j))) { j = j + 1; }
        if (j > i) {
            var part = _io_slice(s, i, j);
            if (!_io_is_dot(part) || (first && keep_leading_dot)) {
                parts.append(part);
            }
            first = false;
        }
        i = j + 1;
    }
    return parts;
}

export struct Path {
    String Value;

    new(String value = "") {
        this.Value = value;
    }

    static String separator() {
        return _io_path_separator();
    }

    String to_string() {
        return Value;
    }

    bool is_empty() {
        return Value.Size == 0;
    }

    bool is_absolute() {
        var p = Value.Data as __ptr<u8>;
        var n = Value.Size;
        var prefix = _io_path_prefix_len(p, n);
        var has_root = _io_path_is_sep(_io_byte(p, n, prefix));
        return _io_path_absolute(p, prefix, has_root);
    }

    bool is_relative() {
        return !is_absolute();
    }

    # Append `other`; an absolute `other` (or, on Windows, one with a root or
    # a drive) replaces this path instead.
    Path join(Path other) {
        if (other.Value.Size == 0) {
            return Path(Value.clone());
        }
        if (Value.Size == 0 || other.is_absolute() || other.has_root_or_prefix()) {
            return Path(other.Value.clone());
        }
        var p = Value.Data as __ptr<u8>;
        var s = Value.clone();
        if (!_io_path_is_sep(_io_byte(p, Value.Size, Value.Size - 1))) {
            s.append(_io_path_separator());
        }
        s.append(other.Value);
        return Path(s);
    }

    # `join` with a String; a separate name because methods do not overload.
    Path join_str(String other) {
        return join(Path(other));
    }

    bool has_root_or_prefix() {
        var p = Value.Data as __ptr<u8>;
        var n = Value.Size;
        if (_io_path_prefix_len(p, n) > 0) {
            return true;
        }
        return _io_path_is_sep(_io_byte(p, n, 0));
    }

    # The path without its last component: "" for a root or a bare name.
    Path parent() {
        var root = _io_path_root_end(Value);
        var e = _io_path_trimmed_end(Value);
        if (e <= root) {
            return Path();
        }
        var start = _io_path_name_start(Value, e);
        if (start <= root) {
            return Path(_io_slice(Value, 0, root));
        }
        var p = Value.Data as __ptr<u8>;
        var j = start;
        while (j > root && _io_path_is_sep(_io_byte(p, Value.Size, j - 1))) { j = j - 1; }
        return Path(_io_slice(Value, 0, j));
    }

    # The last component; "" for a root, an empty path, "." or "..".
    String file_name() {
        var root = _io_path_root_end(Value);
        var e = _io_path_trimmed_end(Value);
        if (e <= root) {
            return String();
        }
        var name = _io_slice(Value, _io_path_name_start(Value, e), e);
        if (_io_is_dot(name) || _io_is_dotdot(name)) {
            return String();
        }
        return name;
    }

    # Byte offset of the extension's dot in `name`, or name.Size when it has
    # none. A leading dot (".bashrc") starts the name, not an extension.
    static ulong dot_index(String name) {
        var p = name.Data as __ptr<u8>;
        var i = name.Size;
        while (i > 1) {
            i = i - 1;
            if (p[i] == 46) {
                return i;
            }
        }
        return name.Size;
    }

    String file_stem() {
        var name = file_name();
        return _io_slice(name, 0, Path.dot_index(name));
    }

    # The extension without its dot; "" when there is none.
    String extension() {
        var name = file_name();
        var dot = Path.dot_index(name);
        if (dot >= name.Size) {
            return String();
        }
        return _io_slice(name, dot + 1, name.Size);
    }

    # This path with its extension replaced by `ext` (removed when `ext` is
    # empty). A path without a file name is returned unchanged.
    Path with_extension(String ext) {
        var name = file_name();
        if (name.Size == 0) {
            return Path(Value.clone());
        }
        var e = _io_path_trimmed_end(Value);
        var start = _io_path_name_start(Value, e);
        var s = _io_slice(Value, 0, start);
        s.append(_io_slice(name, 0, Path.dot_index(name)));
        if (ext.Size > 0) {
            s.append(".");
            s.append(ext);
        }
        return Path(s);
    }

    # The prefix (Windows), the root separator, then each non-empty part. `.`
    # parts are dropped except a leading one ("./a" -> [".", "a"]).
    Array<String> components() {
        var out = Array<String>();
        var p = Value.Data as __ptr<u8>;
        var n = Value.Size;
        var prefix = _io_path_prefix_len(p, n);
        if (prefix > 0) {
            out.append(_io_slice(Value, 0, prefix));
        }
        var has_root = _io_path_is_sep(_io_byte(p, n, prefix));
        if (has_root) {
            out.append(_io_slice(Value, prefix, prefix + 1));
        }
        var parts = _io_path_parts(Value, prefix == 0 && !has_root);
        out.append_all(parts);
        return out;
    }

    # Lexical clean-up: drop "." parts and repeated separators, resolve ".."
    # against the preceding part. ".." cannot climb above a root and is kept
    # at the start of a relative path. A path that cleans to nothing is ".";
    # the empty path stays empty.
    Path normalize() {
        if (Value.Size == 0) {
            return Path();
        }
        var p = Value.Data as __ptr<u8>;
        var n = Value.Size;
        var prefix = _io_path_prefix_len(p, n);
        var has_root = _io_path_is_sep(_io_byte(p, n, prefix));
        var parts = _io_path_parts(Value, false);
        var kept = Array<String>();
        ulong k = 0;
        while (k < parts.count()) {
            var part = parts[k];
            k = k + 1;
            if (_io_is_dotdot(part)) {
                var climb = false;
                if (kept.count() > 0) {
                    climb = !_io_is_dotdot(kept.last());
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
        var s = _io_slice(Value, 0, prefix);
        if (has_root) {
            s.append(sep);
        }
        ulong i = 0;
        while (i < kept.count()) {
            if (i > 0) {
                s.append(sep);
            }
            s.append(kept[i]);
            i = i + 1;
        }
        if (s.Size == 0) {
            s = ".";
        }
        return Path(s);
    }

    bool exists() {
        return _io_sys_stat(this, true).is_ok();
    }

    bool is_file() {
        var r = _io_sys_stat(this, true);
        if (r.is_err()) {
            return false;
        }
        return r.Value.IsFile;
    }

    bool is_dir() {
        var r = _io_sys_stat(this, true);
        if (r.is_err()) {
            return false;
        }
        return r.Value.IsDir;
    }

    # Follows symlinks.
    IoResult<Metadata> metadata() {
        return _io_sys_stat(this, true);
    }

    # Describes a symlink itself rather than its target.
    IoResult<Metadata> symlink_metadata() {
        return _io_sys_stat(this, false);
    }

    # The absolute path with symlinks, "." and ".." resolved; fails if it
    # does not exist.
    IoResult<Path> canonicalize() {
        return _io_sys_realpath(this);
    }

    bool ==(Path rhs) {
        return Value == rhs.Value;
    }

    bool !=(Path rhs) {
        return !(Value == rhs.Value);
    }
}
