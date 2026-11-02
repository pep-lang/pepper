# Markdown that a package wrote (its doc comments, its `pep.toml`), made
# safe to serve beside every other package's docs on one site (#301).
# mdBook passes raw HTML through, so outside code a `<` becomes `&lt;` (a
# tag, a comment or an autolink shows as text); and a link whose target
# names a scheme other than `http`, `https` or `mailto` (`javascript:`)
# points nowhere instead. Code is left as written: mdBook escapes it.

# `markdown` with its raw HTML shown as text and its links' unsafe targets
# replaced by `#`.
export inert_markdown(markdown: String): String {
    var out = StringBuilder();
    var fence = "";
    bool previous_blank = true;
    bool previous_code = false;
    var lines = markdown.split("\n");
    for (var index in 0..lines.count) {
        var line = lines[index];
        if (index > 0) {
            out.append("\n");
        }
        var trimmed = line.trim_start();
        if (!fence.is_empty) {
            out.append(line);
            if (trimmed.starts_with(fence)) {
                fence = "";
            }
            continue;
        }
        if (trimmed.starts_with("```") or trimmed.starts_with("~~~")) {
            fence = trimmed.substr_bytes(0, 3);
            out.append(line);
            continue;
        }
        bool blank = trimmed.is_empty;
        bool code = !blank and _indented(line) and (previous_blank or previous_code);
        previous_blank = blank;
        previous_code = code;
        out.append(code ? line : _inert_line(line));
    }
    return out.to_string();
}

# Whether `line` starts with four spaces or a tab: an indented code block's
# line, after a blank one.
_indented(line: String): bool {
    return line.starts_with("    ") or line.starts_with("\t");
}

# One line outside code blocks: its code spans as written, a `<` elsewhere
# as `&lt;`, and each link's target made safe.
_inert_line(line: String): String {
    var definition = _link_definition(line);
    if (definition.is_value()) {
        return definition.value();
    }
    var out = StringBuilder();
    ulong at = 0;
    while (at < line.size) {
        var b = line.byte_at(at);
        if (b == '`') {
            # A code span: the same number of backticks closes it.
            var ticks = at;
            while (ticks < line.size and line.byte_at(ticks) == '`') {
                ticks += 1;
            }
            var marker = line.substr_bytes(at, ticks - at);
            var close = line.find(marker, ticks);
            if (close < 0) {
                out.append(marker);
                at = ticks;
                continue;
            }
            var end = close as ulong + marker.size;
            out.append(line.substr_bytes(at, end - at));
            at = end;
            continue;
        }
        if (b == '<') {
            out.append("&lt;");
            at += 1;
            continue;
        }
        if (b == ']' and at + 1 < line.size and line.byte_at(at + 1) == '(') {
            # An inline link's target runs to its `)`.
            var close = line.find(")", at + 2);
            var end = close < 0 ? line.size : close as ulong;
            out.append("](");
            out.append(_safe_target(line.substr_bytes(at + 2, end - at - 2)));
            at = end;
            continue;
        }
        # Plain text, up to the next byte that may start one of the above
        # (all ASCII, so a code point is never split).
        var next = at + 1;
        while (next < line.size) {
            var c = line.byte_at(next);
            if (c == '`' or c == '<' or c == ']') {
                break;
            }
            next += 1;
        }
        out.append(line.substr_bytes(at, next - at));
        at = next;
    }
    return out.to_string();
}

# A link reference definition (`[name]: target "title"`) with its target
# made safe, or nothing for any other line.
_link_definition(line: String): String? {
    var trimmed = line.trim_start();
    if (!trimmed.starts_with("[")) {
        return Optional<String>.Empty;
    }
    var close = trimmed.find("]:");
    if (close < 0) {
        return Optional<String>.Empty;
    }
    var after = close as ulong + 2;
    var rest = trimmed.substr_bytes(after, trimmed.size - after);
    var indent = line.substr_bytes(0, line.size - trimmed.size);
    return Optional<String>.Value(
        indent + trimmed.substr_bytes(0, after).replace("<", "&lt;") + " " + _safe_target(rest.trim())
    );
}

# `target` (a link's, with any title after it) when it is relative or
# names `http`, `https` or `mailto`; else `#`.
_safe_target(target: String): String {
    var url = target.trim();
    var space = url.find(" ");
    var address = (space < 0 ? url : url.substr_bytes(0, space as ulong)).lower();
    if (address.starts_with("<")) {
        address = address.substr_bytes(1, address.size - 1);
    }
    # What comes before the path: a scheme, if anything. Markdown decodes
    # entities in a target (`javascript&#58;`), so one there is unsafe too.
    var path_at = address.size;
    for (var stop in ["/", "?", "#"]) {
        var at = address.find(stop);
        if (at >= 0 and (at as ulong) < path_at) {
            path_at = at as ulong;
        }
    }
    var head = address.substr_bytes(0, path_at);
    if (head.contains("&")) {
        return "#";
    }
    var colon = head.find(":");
    if (colon < 0) {
        return target.replace("<", "&lt;");
    }
    var scheme = address.substr_bytes(0, colon as ulong);
    if (scheme == "http" or scheme == "https" or scheme == "mailto") {
        return target.replace("<", "&lt;");
    }
    return "#";
}
