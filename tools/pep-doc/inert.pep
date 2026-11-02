# Markdown that a package wrote (its doc comments, its `pep.toml`, its file
# names), made safe to serve beside every other package's docs on one site
# (#301). mdBook passes raw HTML through and expands its own `{{#include}}`
# directives, so:
#
# - `{{#` is written `\{{#` everywhere, which mdBook shows as it is;
# - outside code, `<` becomes `&lt;` (no tag, comment or autolink is HTML)
#   and `&` becomes `&amp;` (no entity spells a character a link needs);
# - outside code, `javascript:`, `vbscript:` and `data:` get a zero-width
#   space before their `:`, so wherever Markdown finds a link target (a
#   reference definition's next line included), none of them is a scheme.
#
# What counts as code here is never more than CommonMark counts: a fence
# indented less than four spaces, and a code span that a backtick run of
# its own length closes. An indented code block is treated as text, since
# in a list it may be a paragraph; its `<` then shows as `&lt;`.

# `markdown` with its raw HTML shown as text, its unsafe link schemes broken
# and mdBook's directives escaped.
export inert_markdown(markdown: String): String {
    var out = StringBuilder();
    var fence = "";
    var lines = markdown.replace("{{#", "\\{{#").split("\n");
    for (var index in 0..lines.count) {
        var line = lines[index];
        if (index > 0) {
            out.append("\n");
        }
        if (!fence.is_empty) {
            out.append(line);
            if (_closes(line, fence)) {
                fence = "";
            }
            continue;
        }
        var opened = _opening_fence(line);
        if (opened.is_value()) {
            fence = opened.value();
            out.append(line);
            continue;
        }
        out.append(_inert_line(line));
    }
    return out.to_string();
}

# The run of backticks or tildes that opens a fenced code block on `line`,
# as CommonMark has it: indented less than four spaces, at least three,
# and for backticks, none in the rest of the line.
_opening_fence(line: String): String? {
    var none = Optional<String>.Empty;
    ulong indent = 0;
    while (indent < line.size and line.byte_at(indent) == ' ') {
        indent += 1;
    }
    if (indent >= 4 or indent >= line.size) {
        return none;
    }
    var mark = line.byte_at(indent);
    if (mark != '`' and mark != '~') {
        return none;
    }
    var end = indent;
    while (end < line.size and line.byte_at(end) == mark) {
        end += 1;
    }
    if (end - indent < 3) {
        return none;
    }
    if (mark == '`' and line.find("`", end) >= 0) {
        return none;
    }
    return Optional<String>.Value(line.substr_bytes(indent, end - indent));
}

# Whether `line` closes the fence `fence` opened: a run of its character at
# least as long, indented less than four spaces, with nothing after it.
_closes(line: String, fence: String): bool {
    var trimmed = line.trim();
    ulong indent = line.size - line.trim_start().size;
    if (indent >= 4 or trimmed.size < fence.size) {
        return false;
    }
    for (var at in 0..trimmed.size) {
        if (trimmed.byte_at(at) != fence.byte_at(0)) {
            return false;
        }
    }
    return true;
}

# One line outside fenced code: its code spans as written; elsewhere `<`
# and `&` escaped, a backslash escape kept whole, and unsafe schemes broken.
_inert_line(line: String): String {
    var out = StringBuilder();
    ulong at = 0;
    while (at < line.size) {
        var b = line.byte_at(at);
        if (b == '\\' and at + 1 < line.size and line.byte_at(at + 1) < 128) {
            # An escaped character is text, and a `\`` opens no code span;
            # an escaped `<` or `&` is safe as it is.
            out.append(line.substr_bytes(at, 2));
            at += 2;
            continue;
        }
        if (b == '`') {
            var end = _code_span_end(line, at);
            if (end.is_value()) {
                out.append(line.substr_bytes(at, end.value() - at));
                at = end.value();
                continue;
            }
            # No run of its length closes it: the backticks are text.
            var run = _run_end(line, at);
            out.append(line.substr_bytes(at, run - at));
            at = run;
            continue;
        }
        if (b == '<') {
            out.append("&lt;");
            at += 1;
            continue;
        }
        if (b == '&') {
            out.append("&amp;");
            at += 1;
            continue;
        }
        if (b == ':' and _ends_unsafe_scheme(line, at)) {
            out.append("&#8203;:");
            at += 1;
            continue;
        }
        # Plain text, up to the next byte that may start one of the above
        # (all ASCII, so a code point is never split).
        var next = at + 1;
        while (next < line.size) {
            var c = line.byte_at(next);
            if (c == '`' or c == '<' or c == '&' or c == ':' or c == '\\') {
                break;
            }
            next += 1;
        }
        out.append(line.substr_bytes(at, next - at));
        at = next;
    }
    return out.to_string();
}

# Where the run of backticks starting at `start` ends.
_run_end(line: String, start: ulong): ulong {
    var end = start;
    while (end < line.size and line.byte_at(end) == '`') {
        end += 1;
    }
    return end;
}

# Where the code span opening at `start` ends: after the next run of
# exactly as many backticks; nothing when no such run closes it.
_code_span_end(line: String, start: ulong): ulong? {
    var open = _run_end(line, start);
    var length = open - start;
    var at = open;
    while (at < line.size) {
        if (line.byte_at(at) != '`') {
            at += 1;
            continue;
        }
        var end = _run_end(line, at);
        if (end - at == length) {
            return Optional<ulong>.Value(end);
        }
        at = end;
    }
    return Optional<ulong>.Empty;
}

# Whether the `:` at `colon` ends `javascript`, `vbscript` or `data`, in
# any case, starting a word.
_ends_unsafe_scheme(line: String, colon: ulong): bool {
    # The schemes a link must not have.
    for (var scheme in ["javascript", "vbscript", "data"]) {
        if (colon < scheme.size) {
            continue;
        }
        var start = colon - scheme.size;
        bool same = true;
        for (var i in 0..scheme.size) {
            var c = line.byte_at(start + i);
            # ASCII letters only: a byte of a longer code point never matches.
            var lower = c >= 'A' and c <= 'Z' ? (c + 32) as byte : c;
            same = same and lower == scheme.byte_at(i);
        }
        if (!same) {
            continue;
        }
        if (start == 0) {
            return true;
        }
        var before = line.byte_at(start - 1);
        bool letter = (before >= 'a' and before <= 'z')
            or (before >= 'A' and before <= 'Z')
            or (before >= '0' and before <= '9');
        if (!letter) {
            return true;
        }
    }
    return false;
}
