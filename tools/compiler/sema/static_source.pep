## What a `static` block expands to, written back out as source, for
## `--emit-static` (Pepper's `cc -E`): `pepper_sema::passes::static_source`
## in Pepper.
##
## While a `PassState` records (`StaticRecording`), `static_blocks.expand`
## renders each block it expands as text beside the statements it builds:
## every emitted statement is its source as written, with each placeholder
## (`Expression.StaticValue`, `Expression.StaticMember`) replaced by the
## source of what it became (`SourceEdit`), and each `x.Type` and type
## parameter by the type it names. The driver splices the result into a
## copy of the file.

import compiler.ast;
import [Loc] from "loc";

## One expansion of one `static` block: a block in concrete code expands
## once, a block in generic code once per specialization.
export struct StaticExpansion {
    ## The block's `static` keyword.
    var loc: Loc;
    ## The whole block, from `static` to its `}`.
    var span: ast.Span;
    ## The specialization's type arguments, by parameter (`T` to `Point`);
    ## empty in concrete code.
    var type_arguments: Array<(String, String)>;
    ## What it emits: a `{ ... }` block, indented four spaces a level from
    ## column 0.
    var lines: String[];
    ## Where each emitted statement and pass header is in `lines`, for
    ## `--debug-static=expanded`: its id (`StaticPass`), line and byte
    ## column.
    var positions: Array<(uint, ulong, ulong)>;

    construct(
        loc: Loc,
        span: ast.Span,
        type_arguments: Array<(String, String)>,
        lines: String[],
        positions: Array<(uint, ulong, ulong)>
    ) {
        this.loc = loc;
        this.span = span;
        this.type_arguments = type_arguments;
        this.lines = lines;
        this.positions = positions;
    }

    ## Whether the type arguments are `other`'s.
    same_arguments(other: Array<(String, String)>): bool {
        if (type_arguments.count != other.count) {
            return false;
        }
        for (var i in 0..other.count) {
            var (a, b) = type_arguments[i];
            var (c, d) = other[i];
            if (a != c or b != d) {
                return false;
            }
        }
        return true;
    }
}

## The expansions a run of the sema passes records, when it records them
## (`PassState.static_recording`).
export struct StaticRecording {
    ## The expansions recorded so far.
    var expansions: StaticExpansion[] = Array<StaticExpansion>();
    ## The last id `next_id` gave.
    var last_id: uint = 0;

    construct() {}

    ## A new id for an emitted statement or pass header.
    next_id(): uint {
        last_id += 1;
        return last_id;
    }
}

## Emitted code, as it will be written. Each part carries the id that
## places it for the debugger, when it has one.
export enum Rendered {
    ## A statement: its first line, and the others indented relative to it.
    Code(lines: String[], id: uint?),
    ## `{ ... }`: a pass of a loop, the branch a compile-time `if` kept, or a
    ## nested block.
    Braced(items: Rendered[], id: uint?),
    ## A runtime `if`.
    Conditional(branch: RenderedBranch),
}

## A runtime `if` of emitted code: `Rendered.Conditional`.
export struct RenderedBranch {
    var condition: String;
    var then_items: Rendered[];
    var else_items: Rendered[]?;
    var id: uint?;

    construct(condition: String, then_items: Rendered[], else_items: Rendered[]?, id: uint?) {
        this.condition = condition;
        this.then_items = then_items;
        this.else_items = else_items;
        this.id = id;
    }
}

## Writes `items` as lines into `out`, at `depth` levels of indentation,
## adding to `positions` the line and column of each part with an id.
##
## @param items the parts
## @param depth the indentation, in levels of four spaces
## @param out the lines
## @param positions each id's line and byte column
export write_lines(items: Rendered[], depth: ulong, out: String[], positions: Array<(uint, ulong, ulong)>) {
    var indent = "    ".repeat(depth);
    for (var item in items) {
        match (item) {
            Code(lines, id) => {
                if (id.is_value()) {
                    positions.append((id.value(), out.count, indent.size));
                }
                for (var line in lines) {
                    out.append(line.is_empty ? "" : indent + line);
                }
            }
            Braced(inner, id) => {
                # A block holding only a block is that block, and an empty
                # one changes nothing.
                var ids = Array<uint>();
                if (id.is_value()) {
                    ids.append(id.value());
                }
                var body = inner;
                while (body.count == 1) {
                    if (body[0] is Braced(only, only_id)) {
                        if (only_id.is_value()) {
                            ids.append(only_id.value());
                        }
                        body = only;
                    } else {
                        break;
                    }
                }
                if (body.count > 0) {
                    for (var each in ids) {
                        positions.append((each, out.count, indent.size));
                    }
                    out.append(indent + "{");
                    write_lines(body, depth + 1, out, positions);
                    out.append(indent + "}");
                }
            }
            Conditional(branch) => {
                if (branch.id.is_value()) {
                    # At the condition, after `if (`.
                    positions.append((branch.id.value(), out.count, indent.size + 4));
                }
                out.append(indent + "if (" + _without_parentheses(branch.condition) + ") {");
                write_lines(branch.then_items, depth + 1, out, positions);
                if (branch.else_items.is_value()) {
                    out.append(indent + "} else {");
                    write_lines(branch.else_items.value(), depth + 1, out, positions);
                }
                out.append(indent + "}");
            }
        }
    }
}

## `text` without the parentheses around all of it, if it has them.
_without_parentheses(text: String): String {
    if (!text.starts_with("(") or !text.ends_with(")")) {
        return text;
    }
    var inner = text.substr_bytes(1, text.size - 2);
    long depth = 0;
    for (var i in 0..inner.size) {
        var c = inner.byte_at(i);
        if (c == '(') {
            depth += 1;
        } else if (c == ')') {
            if (depth == 0) {
                return text;
            }
            depth -= 1;
        }
    }
    return inner;
}

## A placeholder's replacement: its span, and the source that replaces it.
export struct SourceEdit {
    var span: ast.Span;
    var pieces: SourcePiece[];
    ## The text to write in place of the whole `{...}` when the placeholder
    ## fills a hole of an interpolated string (`$"{field.name} = "` writes
    ## `$"x = "`); none to keep the hole.
    var inline: String?;

    construct(span: ast.Span, pieces: SourcePiece[], inline: String? = Optional<String>.Empty) {
        this.span = span;
        this.pieces = pieces;
        this.inline = inline;
    }
}

## A part of a `SourceEdit`'s replacement.
export enum SourcePiece {
    Text(text: String),
    ## An argument as written, with its own placeholders replaced.
    Argument(span: ast.Span),
}

## What part of the source a byte is in.
enum _SourceRegion {
    Code,
    ## A string or character literal, or a comment: never substituted.
    Text,
    ## An interpolated string, holes included.
    Interpolated,
}

## The region of each byte of `source[span]`.
_regions(source: String, span: ast.Span): _SourceRegion[] {
    var out = Array<_SourceRegion>();
    for (var _ in span.start..span.end) {
        out.append(_SourceRegion.Code);
    }
    var i = span.start;
    while (i < span.end) {
        var start = i;
        var c = source.byte_at(i);
        _SourceRegion kind = _SourceRegion.Code;
        if (c == '#') {
            while (i < span.end and source.byte_at(i) != '\n') {
                i += 1;
            }
            kind = _SourceRegion.Text;
        } else if (c == '$' and i + 1 < source.size and source.byte_at(i + 1) == '"') {
            i = _string_end(source, i + 1, true);
            kind = _SourceRegion.Interpolated;
        } else if (c == '"') {
            i = _string_end(source, i, false);
            kind = _SourceRegion.Text;
        } else if (c == '\'') {
            i = _quoted_end(source, i, '\'');
            kind = _SourceRegion.Text;
        } else {
            i += 1;
            continue;
        }
        var end = i < span.end ? i : span.end;
        for (var at in start..end) {
            out[at - span.start] = kind;
        }
    }
    return out;
}

## The end of the string literal whose `"` is at `at`.
_string_end(source: String, at: ulong, interpolated: bool): ulong {
    var i = at + 1;
    while (i < source.size) {
        var c = source.byte_at(i);
        if (c == '\\') {
            i += 2;
        } else if (c == '"') {
            return i + 1;
        } else if (interpolated and c == '{' and i + 1 < source.size and source.byte_at(i + 1) == '{') {
            i += 2;
        } else if (interpolated and c == '{') {
            i = _hole_end(source, i + 1);
        } else {
            i += 1;
        }
    }
    return source.size;
}

## The end of the interpolation hole whose code starts at `at`: past its
## `}`, stepping over the strings and braces inside it.
_hole_end(source: String, at: ulong): ulong {
    long depth = 0;
    var i = at;
    while (i < source.size) {
        var c = source.byte_at(i);
        if (c == '"') {
            i = _string_end(source, i, false);
        } else if (c == '$' and i + 1 < source.size and source.byte_at(i + 1) == '"') {
            i = _string_end(source, i + 1, true);
        } else if (c == '\'') {
            i = _quoted_end(source, i, '\'');
        } else if (c == '{') {
            depth += 1;
            i += 1;
        } else if (c == '}' and depth == 0) {
            return i + 1;
        } else if (c == '}') {
            depth -= 1;
            i += 1;
        } else {
            i += 1;
        }
    }
    return source.size;
}

_quoted_end(source: String, at: ulong, quote: byte): ulong {
    var i = at + 1;
    while (i < source.size and source.byte_at(i) != '\n') {
        var c = source.byte_at(i);
        if (c == '\\') {
            i += 2;
        } else if (c == quote) {
            return i + 1;
        } else {
            i += 1;
        }
    }
    return i;
}

_is_word(c: byte): bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

_is_alpha(c: byte): bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

## `source[span]` with each name in `names` replaced where it is code: a
## type parameter (`T` to `Point`, not after a `.`), or a member's type
## (`field.Type` to `int`). Strings and comments are left alone.
##
## @param source the file's text
## @param span the part to copy
## @param names each name and the type that replaces it
## @returns the text
export substitute_names(source: String, span: ast.Span, names: Array<(String, String)>): String {
    var regions = _regions(source, span);
    return _substitute_in(source, span, regions, span.start, names);
}

## `substitute_names` over `source[span]`, with `regions` computed from
## `origin`.
_substitute_in(
    source: String, span: ast.Span, regions: _SourceRegion[], origin: ulong, names: Array<(String, String)>
): String {
    if (names.count == 0 or span.end <= span.start) {
        return span.end <= span.start ? "" : source.substr_bytes(span.start, span.end - span.start);
    }
    var out = StringBuilder();
    var i = span.start;
    var copied = span.start;
    while (i < span.end) {
        var c = source.byte_at(i);
        if (!(regions[i - origin] is Code) or !_is_alpha(c) or (i > 0 and _is_word(source.byte_at(i - 1)))) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < span.end and _is_word(source.byte_at(end))) {
            end += 1;
        }
        var after_dot = source.substr_bytes(0, i).trim_end().ends_with(".");
        var word = source.substr_bytes(i, end - i);
        var type_end = end + 5;
        String? replacement;
        ulong replaced_end = end;
        if (!after_dot
            and type_end <= span.end
            and source.substr_bytes(end, 5) == ".Type"
            and !(type_end < source.size and _is_word(source.byte_at(type_end)))) {
            var with_type = $"{word}.Type";
            for (var (name, ty) in names) {
                if (name == with_type) {
                    replacement = Optional<String>.Value(ty);
                    replaced_end = type_end;
                    break;
                }
            }
        }
        if (!replacement.is_value() and !after_dot) {
            for (var (name, ty) in names) {
                if (name == word) {
                    replacement = Optional<String>.Value(ty);
                    replaced_end = end;
                    break;
                }
            }
        }
        if (replacement.is_value()) {
            out.append(source.substr_bytes(copied, i - copied));
            out.append(replacement.value());
            copied = replaced_end;
            i = replaced_end;
        } else {
            i = end;
        }
    }
    out.append(source.substr_bytes(copied, span.end - copied));
    return out.to_string();
}

## `span` widened over the parentheses around its start or end that it
## closes or opens without the other: an operand's extent leaves out the
## parentheses around a part of it (`a + b) * c`).
_balanced(source: String, span: ast.Span): ast.Span {
    var start = span.start;
    var end = span.end;
    long depth = 0;
    long lowest = 0;
    var i = start;
    while (i < end) {
        var c = source.byte_at(i);
        if (c == '"') {
            var past = _string_end(source, i, false);
            i = (past < end ? past : end) - 1;
        } else if (c == '(' or c == '[') {
            depth += 1;
        } else if (c == ')' or c == ']') {
            depth -= 1;
            if (depth < lowest) {
                lowest = depth;
            }
        }
        i += 1;
    }
    # Each closer with no opener inside: take in the opener before.
    var missing = -lowest;
    while (missing > 0 and start > 0) {
        start -= 1;
        var c = source.byte_at(start);
        if (c == '(' or c == '[') {
            missing -= 1;
        } else if (c == ')' or c == ']') {
            missing += 1;
        }
    }
    # Each opener with no closer inside: take in the closer after.
    var open = depth - lowest;
    while (open > 0 and end < source.size) {
        var c = source.byte_at(end);
        if (c == '(' or c == '[') {
            open += 1;
        } else if (c == ')' or c == ']') {
            open -= 1;
        }
        end += 1;
    }
    return ast.Span(start, end);
}

## `edits` with their spans, and their arguments', `_balanced`.
_balance(source: String, edits: SourceEdit[]): SourceEdit[] {
    var out = Array<SourceEdit>();
    for (var edit in edits) {
        var pieces = Array<SourcePiece>();
        for (var piece in edit.pieces) {
            match (piece) {
                Argument(span) => {
                    pieces.append(SourcePiece.Argument(_balanced(source, span)));
                }
                Text(text) => {
                    pieces.append(SourcePiece.Text(text));
                }
            }
        }
        out.append(SourceEdit(_balanced(source, edit.span), pieces, edit.inline));
    }
    return out;
}

## An emitted statement as written at `span`, with `edits` applied and
## `names` substituted, as lines indented relative to its first.
##
## @param source the file's text
## @param span the statement, without its `;`
## @param edits the placeholders' replacements
## @param names the names to substitute (see `substitute_names`)
## @returns the lines
export statement_source(source: String, span: ast.Span, edits: SourceEdit[], names: Array<(String, String)>): String[] {
    var whole = _balanced(source, span);
    # A statement's span ends before its `;`.
    var after = whole.end;
    while (after < source.size and (source.byte_at(after) == ' ' or source.byte_at(after) == '\t')) {
        after += 1;
    }
    if (after < source.size and source.byte_at(after) == ';') {
        whole = ast.Span(whole.start, after + 1);
    }
    var text = expression_source(source, whole, edits, names);
    var line_start = source.substr_bytes(0, whole.start).rfind("\n") + 1;
    var before = source.substr_bytes(line_start as ulong, whole.start - line_start as ulong);
    var indent = before.size - before.trim_start().size;
    var out = Array<String>();
    var lines = text.split("\n");
    for (var i in 0..lines.count) {
        var line = lines[i];
        if (i == 0) {
            out.append(line.trim_end());
            continue;
        }
        var leading = line.size - line.trim_start().size;
        var cut = leading < indent ? leading : indent;
        out.append(line.substr_bytes(cut, line.size - cut).trim_end());
    }
    return out;
}

## `source[span]` with `edits` applied and `names` substituted.
##
## @param source the file's text
## @param span the expression
## @param edits the placeholders' replacements
## @param names the names to substitute (see `substitute_names`)
## @returns the text
export expression_source(source: String, span: ast.Span, edits: SourceEdit[], names: Array<(String, String)>): String {
    var whole = _balanced(source, span);
    var regions = _regions(source, whole);
    return _apply(source, whole, _balance(source, edits), names, regions, whole.start);
}

_apply(
    source: String,
    span: ast.Span,
    edits: SourceEdit[],
    names: Array<(String, String)>,
    regions: _SourceRegion[],
    origin: ulong
): String {
    var inside = Array<SourceEdit>();
    for (var edit in edits) {
        if (edit.span.start >= span.start and edit.span.end <= span.end) {
            inside.append(edit);
        }
    }
    # By start, the widest first.
    inside.sort((a, b) => {
        if (a.span.start != b.span.start) {
            return a.span.start < b.span.start ? -1 : 1;
        }
        return a.span.end > b.span.end ? -1 : (a.span.end < b.span.end ? 1 : 0);
    });
    var out = StringBuilder();
    var at = span.start;
    for (var edit in inside) {
        if (edit.span.start < at) {
            # Inside an edit already applied.
            continue;
        }
        var start = edit.span.start;
        var end = edit.span.end;
        String text;
        var hole = _hole(source, edit.span, regions, origin, span);
        if (edit.inline.is_value() and hole.is_value()) {
            var (open, close) = hole.value();
            start = open;
            end = close;
            text = edit.inline.value();
        } else {
            var built = StringBuilder();
            for (var piece in edit.pieces) {
                match (piece) {
                    Text(written) => {
                        built.append(written);
                    }
                    Argument(argument) => {
                        built.append(_apply(source, argument, edits, names, regions, origin));
                    }
                }
            }
            text = built.to_string();
        }
        out.append(_substitute_in(source, ast.Span(at, start), regions, origin, names));
        out.append(text);
        at = end;
    }
    out.append(_substitute_in(source, ast.Span(at, span.end), regions, origin, names));
    return out.to_string();
}

## When `span` is part of an interpolated string, what to replace with its
## text: the hole with its braces when `span` is a hole's expression, else
## `span` itself, a run of the string's text and holes (`{field.name} = `).
_hole(source: String, span: ast.Span, regions: _SourceRegion[], origin: ulong, within: ast.Span): (ulong, ulong)? {
    if (span.start < origin
        or span.start - origin >= regions.count
        or !(regions[span.start - origin] is Interpolated)
        or source.substr_bytes(span.start, source.size - span.start).starts_with("$\"")) {
        return Optional<(ulong, ulong)>.Empty;
    }
    var before = source.substr_bytes(0, span.start).trim_end();
    if (before.size == 0) {
        return Optional<(ulong, ulong)>.Empty;
    }
    var open = before.size - 1;
    var close = span.end;
    while (close < source.size
        and (source.byte_at(close) == ' ' or source.byte_at(close) == '\t' or source.byte_at(close) == '\n')) {
        close += 1;
    }
    # `{{` is a literal brace, not a hole.
    var is_hole = before.ends_with("{")
        and !before.ends_with("{{")
        and close < source.size
        and source.byte_at(close) == '}';
    if (!is_hole) {
        return Optional<(ulong, ulong)>.Value((span.start, span.end));
    }
    if (open >= within.start and close < within.end) {
        return Optional<(ulong, ulong)>.Value((open, close + 1));
    }
    return Optional<(ulong, ulong)>.Empty;
}

## `text` as a Pepper string literal.
##
## @param text the text
## @returns the literal
export string_literal(text: String): String {
    return $"\"{escape_text(text, false)}\"";
}

## `text` escaped for a string literal, or for the text of an interpolated
## string, where braces are doubled.
##
## @param text the text
## @param interpolated whether it goes in an interpolated string
## @returns the escaped text
export escape_text(text: String, interpolated: bool): String {
    var out = StringBuilder();
    for (var c in text) {
        if (c == "\\") {
            out.append("\\\\");
        } else if (c == "\"") {
            out.append("\\\"");
        } else if (c == "\n") {
            out.append("\\n");
        } else if (c == "\t") {
            out.append("\\t");
        } else if (c == "\r") {
            out.append("\\r");
        } else if (c == "\0") {
            out.append("\\0");
        } else if (interpolated and c == "{") {
            out.append("{{");
        } else if (interpolated and c == "}") {
            out.append("}}");
        } else if (c.size == 1 and (c.byte_at(0) < 32 or c.byte_at(0) == 127)) {
            out.append("\\u{" + _hex_digits(c.byte_at(0) as ulong) + "}");
        } else {
            out.append(c);
        }
    }
    return out.to_string();
}

_hex_digits(value: ulong): String {
    var digits = "0123456789abcdef";
    if (value < 16) {
        return digits.substr_bytes(value, 1);
    }
    return _hex_digits(value / 16) + digits.substr_bytes(value % 16, 1);
}
