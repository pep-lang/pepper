# glob, glob_matches: shell-style patterns over paths.
#
# A pattern is matched one path component at a time: braces expand first
# into plain patterns, each pattern splits at `/`, and a `**` component
# stands for any number of whole components. Within a component, `*`, `?`
# and `[...]` work on code points, not bytes.

import "directory";
import "path";
import "types";

## Returns whether `path` matches the glob `pattern` as a whole.
##
## The pattern language:
##
## - `*` matches any run of characters within one path component (never a
##   `/`), the empty run included.
## - `?` matches one character (a code point) other than `/`.
## - `**` as a whole component matches zero or more components, so
##   `src/**/*.pep` matches `src/a.pep` and `src/x/y/a.pep`. Elsewhere it is
##   the same as `*`.
## - `[abc]` matches one of the characters listed, `[a-z]` one in the range,
##   and `[!abc]` or `[^abc]` one not listed. A `]` right after the `[` (or
##   the `!`) is listed rather than closing it.
## - `{a,b}` matches either alternative; alternatives may hold any pattern,
##   braces included.
##
## `/` separates components in the pattern; on Windows `\` in `path` counts
## as `/` too. There is no escape character, since it would clash with
## Windows separators: `[*]` matches a literal `*`. An unclosed `[` or `{`
## matches itself, so every pattern is valid. Matching is case-sensitive,
## and `*` and `?` match a leading `.` like any other character.
##
## @param pattern the glob to match against
## @param path the path to test, as text
## @returns true when the whole of `path` matches
## @example
##     import io;
##
##     var yes = io.glob_matches("src/**/*.{pep,md}", "src/io/glob.pep");   # true
##     var no = io.glob_matches("*.pep", "src/main.pep");                  # false: `*` stops at `/`
export glob_matches(pattern: String, path: String): bool {
    var names = _io_glob_components(_io_glob_slashes(path));
    for (var alternative in _io_glob_expand_braces(pattern)) {
        var parts = _io_glob_components(alternative);
        if (_io_glob_match_components(parts, 0, names, 0)) {
            return true;
        }
    }
    return false;
}

## Returns the existing paths that match the glob `pattern`, sorted and
## without duplicates. The pattern language is `glob_matches`'s.
##
## The walk starts at the longest leading run of components without `*`,
## `?`, `[` or `{`: `src/**/*.pep` lists only under `src`, and `*.pep` the
## current directory. A relative pattern gives relative paths. `**` does not
## descend into symlinked directories, so a link cycle cannot loop; other
## components follow symlinks. Directories that cannot be read are skipped,
## and a pattern whose start does not exist matches nothing.
##
## @param pattern the glob to expand
## @returns the matching paths, joined with the platform separator, sorted
## by their text; empty when nothing matches
## @example
##     import io;
##
##     for (var source in io.glob("runtime/**/*.pep")) {
##         print(source.to_string());
##     }
export glob(pattern: String): Path[] {
    var found = HashSet<String>();
    for (var alternative in _io_glob_expand_braces(pattern)) {
        var parts = _io_glob_components(alternative);
        var start = 0 as ulong;
        var base = "";
        if (alternative.starts_with("/")) {
            base = "/";
        }
        while (start + 1 < parts.count && !_io_glob_has_wildcard(parts[start])) {
            base = _io_glob_join(base, parts[start]);
            start = start + 1;
        }
        _io_glob_walk(base, parts, start, found);
    }
    var texts = Array<String>();
    for (var text in found) {
        texts.append(text);
    }
    texts.sort((a, b) => a.compare(b));
    var paths = Array<Path>();
    for (var text in texts) {
        paths.append(Path(text));
    }
    return paths;
}

# Adds to `found` every path under `directory` (a joined path, "" for the
# current directory) that matches `parts` from `index` on.
_io_glob_walk(directory: String, parts: String[], index: ulong, found: HashSet<String>) {
    if (index == parts.count) {
        return;
    }
    var part = parts[index];
    var last = index + 1 == parts.count;
    if (part == "**") {
        # Zero components here, then one more for each real directory below.
        if (last) {
            _io_glob_add_tree(directory, found);
            return;
        }
        _io_glob_walk(directory, parts, index + 1, found);
        for (var entry in _io_glob_entries(directory)) {
            if (entry.is_directory && !entry.is_symlink) {
                _io_glob_walk(_io_glob_join(directory, entry.name), parts, index, found);
            }
        }
        return;
    }
    if (!_io_glob_has_wildcard(part)) {
        var child = _io_glob_join(directory, part);
        if (last) {
            if (Path(child).exists()) {
                found.insert(Path(child).to_string());
            }
            return;
        }
        if (Path(child).is_directory()) {
            _io_glob_walk(child, parts, index + 1, found);
        }
        return;
    }
    var pattern = _io_glob_code_points(part);
    for (var entry in _io_glob_entries(directory)) {
        if (!_io_glob_match_name(pattern, 0, _io_glob_code_points(entry.name), 0)) {
            continue;
        }
        var child = _io_glob_join(directory, entry.name);
        if (last) {
            found.insert(Path(child).to_string());
            continue;
        }
        if (Path(child).is_directory()) {
            _io_glob_walk(child, parts, index + 1, found);
        }
    }
}

# Adds `directory` (unless it is the current directory) and everything
# below it, not descending into symlinked directories: what a final `**`
# matches.
_io_glob_add_tree(directory: String, found: HashSet<String>) {
    if (directory != "") {
        found.insert(Path(directory).to_string());
    }
    for (var entry in _io_glob_entries(directory)) {
        var child = _io_glob_join(directory, entry.name);
        if (entry.is_directory && !entry.is_symlink) {
            _io_glob_add_tree(child, found);
            continue;
        }
        found.insert(Path(child).to_string());
    }
}

# The entries of `directory` ("" for the current one), none when it cannot
# be read.
_io_glob_entries(directory: String): DirEntry[] {
    var listing = _io_list(Path(directory == "" ? "." : directory));
    if (listing.is_err()) {
        return Array<DirEntry>();
    }
    return listing.value();
}

# `name` inside `directory`, which is "" for the current directory.
_io_glob_join(directory: String, name: String): String {
    if (directory == "") {
        return name;
    }
    return Path(directory).join(Path(name)).to_string();
}

# Whether `part` holds a character that makes it a pattern.
_io_glob_has_wildcard(part: String): bool {
    return part.contains("*") || part.contains("?") || part.contains("[");
}

# `path` with `\` turned into `/` on Windows, where both separate.
_io_glob_slashes(path: String): String {
    var out = path;
    [Target(OS(Windows))]
    {
        out = path.replace("\\", "/");
    }
    return out;
}

# The components of `text` split at `/`, without empty ones (a leading,
# doubled or trailing `/`).
_io_glob_components(text: String): String[] {
    var parts = Array<String>();
    for (var part in text.split("/")) {
        if (part != "") {
            parts.append(part);
        }
    }
    return parts;
}

# Each code point of `text` as its own String.
_io_glob_code_points(text: String): String[] {
    var points = Array<String>();
    for (var point in text) {
        points.append(point);
    }
    return points;
}

# Whether `names` from `name` on match `parts` from `part` on.
_io_glob_match_components(parts: String[], part: ulong, names: String[], name: ulong): bool {
    if (part == parts.count) {
        return name == names.count;
    }
    if (parts[part] == "**") {
        var skip = name;
        while (skip <= names.count) {
            if (_io_glob_match_components(parts, part + 1, names, skip)) {
                return true;
            }
            skip = skip + 1;
        }
        return false;
    }
    if (name == names.count) {
        return false;
    }
    var pattern = _io_glob_code_points(parts[part]);
    if (!_io_glob_match_name(pattern, 0, _io_glob_code_points(names[name]), 0)) {
        return false;
    }
    return _io_glob_match_components(parts, part + 1, names, name + 1);
}

# Whether the component `name` from `n` on matches `pattern` from `p` on.
_io_glob_match_name(pattern: String[], p: ulong, name: String[], n: ulong): bool {
    var pi = p;
    var ni = n;
    while (pi < pattern.count) {
        var token = pattern[pi];
        if (token == "*") {
            # Collapse a run of stars, then try every split of the rest.
            while (pi < pattern.count && pattern[pi] == "*") {
                pi = pi + 1;
            }
            if (pi == pattern.count) {
                return true;
            }
            while (ni <= name.count) {
                if (_io_glob_match_name(pattern, pi, name, ni)) {
                    return true;
                }
                ni = ni + 1;
            }
            return false;
        }
        if (ni == name.count) {
            return false;
        }
        if (token == "[") {
            var close = _io_glob_class_end(pattern, pi);
            if (close != 0) {
                if (!_io_glob_class_matches(pattern, pi, close, name[ni])) {
                    return false;
                }
                pi = close + 1;
                ni = ni + 1;
                continue;
            }
        }
        if (token != "?" && token != name[ni]) {
            return false;
        }
        pi = pi + 1;
        ni = ni + 1;
    }
    return ni == name.count;
}

# The index of the `]` closing the class that opens at `open`, or 0 when it
# is unclosed (and the `[` is literal).
_io_glob_class_end(pattern: String[], open: ulong): ulong {
    var i = open + 1;
    if (i < pattern.count && (pattern[i] == "!" || pattern[i] == "^")) {
        i = i + 1;
    }
    # A `]` first in the class is a member.
    if (i < pattern.count && pattern[i] == "]") {
        i = i + 1;
    }
    while (i < pattern.count) {
        if (pattern[i] == "]") {
            return i;
        }
        i = i + 1;
    }
    return 0;
}

# Whether `point` is in the class between `open` (its `[`) and `close` (its
# `]`).
_io_glob_class_matches(pattern: String[], open: ulong, close: ulong, point: String): bool {
    var i = open + 1;
    var negated = pattern[i] == "!" || pattern[i] == "^";
    if (negated) {
        i = i + 1;
    }
    var member = false;
    while (i < close) {
        var low = pattern[i];
        if (i + 2 < close && pattern[i + 1] == "-") {
            # UTF-8 byte order is code point order.
            var high = pattern[i + 2];
            if (point.compare(low) >= 0 && point.compare(high) <= 0) {
                member = true;
            }
            i = i + 3;
        } else {
            if (point == low) {
                member = true;
            }
            i = i + 1;
        }
    }
    return member != negated;
}

# The plain patterns `pattern` stands for once each `{a,b}` is replaced by
# its alternatives, in order. An unclosed `{` stays as it is.
_io_glob_expand_braces(pattern: String): String[] {
    var open = 0 as ulong;
    while (open < pattern.size) {
        if (pattern.byte_at(open) != '{') {
            open = open + 1;
            continue;
        }
        var close = _io_glob_brace_end(pattern, open);
        if (close == 0) {
            open = open + 1;
            continue;
        }
        var prefix = pattern.substr_bytes(0, open);
        var suffix = pattern.substr_bytes(close + 1, pattern.size - close - 1);
        var expanded = Array<String>();
        for (var alternative in _io_glob_brace_alternatives(pattern, open, close)) {
            for (var result in _io_glob_expand_braces(prefix + alternative + suffix)) {
                expanded.append(result);
            }
        }
        return expanded;
    }
    var single = Array<String>();
    single.append(pattern);
    return single;
}

# The index of the `}` matching the `{` at `open`, or 0 when it has none.
_io_glob_brace_end(pattern: String, open: ulong): ulong {
    var depth = 0;
    var i = open;
    while (i < pattern.size) {
        var b = pattern.byte_at(i);
        if (b == '{') {
            depth = depth + 1;
        } else if (b == '}') {
            depth = depth - 1;
            if (depth == 0) {
                return i;
            }
        }
        i = i + 1;
    }
    return 0;
}

# The alternatives between the `{` at `open` and the `}` at `close`: the
# text split at the commas not inside a nested pair.
_io_glob_brace_alternatives(pattern: String, open: ulong, close: ulong): String[] {
    var alternatives = Array<String>();
    var depth = 0;
    var start = open + 1;
    var i = start;
    while (i < close) {
        var b = pattern.byte_at(i);
        if (b == '{') {
            depth = depth + 1;
        } else if (b == '}') {
            depth = depth - 1;
        } else if (b == ',' && depth == 0) {
            alternatives.append(pattern.substr_bytes(start, i - start));
            start = i + 1;
        }
        i = i + 1;
    }
    alternatives.append(pattern.substr_bytes(start, close - start));
    return alternatives;
}
