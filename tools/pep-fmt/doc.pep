## Documents: a layout description in the style of Wadler's "prettier
## printer". The formatter describes the code as a `Doc` tree (text, places
## where a line may break, groups that break together) and `render` chooses
## the line breaks that keep lines within a width.

## Which layout node a `Doc` is.
export enum DocKind {
    ## Text printed as is. It must not contain a line break.
    Text,
    ## Its parts, one after another.
    Concat,
    ## A space, or a line break when its group breaks.
    Line,
    ## Nothing, or a line break when its group breaks.
    Softline,
    ## Always a line break; every group around it breaks.
    Hardline,
    ## Its parts, with lines that break inside them indented one level more.
    Indent,
    ## Its parts, laid out on one line when they fit, else with every line of the
    ## group broken.
    Group,
    ## Text deferred to the end of the current line: a trailing comment.
    LineSuffix,
    ## Nothing, but it breaks every group around it, like a line break would.
    BreakParent,
    ## Alternative layouts of the same content: the first whose every line fits
    ## is printed flat; if none fits, the last is printed with its groups broken.
    Choice,
}

## The number of spaces in one indentation level.
export const INDENT_WIDTH = 4;

## Returns the byte that marks where a trailing comment starts in `render`'s
## output, so that `align_trailing_comments` can line them up. It never
## reaches the file. (A function, because a module-scope `String` constant is
## not allowed: `String` is not thread-safe.)
##
## @returns a String holding the byte 0x01
export comment_mark(): String {
    return "\x01";
}

# How a group's lines print: as spaces (flat) or as line breaks.
enum Mode {
    Flat,
    Break,
}

## A node of a layout description.
export struct Doc {
    ## What the node is.
    DocKind kind;
    ## The text of a `DocKind.Text` or `DocKind.LineSuffix`.
    String text = "";
    ## The children of a `DocKind.Concat`, `DocKind.Indent`, `DocKind.Group` or the
    ## options of a `DocKind.Choice`.
    Doc[] parts = Array<Doc>();
    # Whether a hard line break is inside, once `is_hard` has worked it out.
    bool? _hard;

    ## Creates a document node.
    ##
    ## @param this.kind what the node is
    ## @param this.text the text of a `DocKind.Text` or `DocKind.LineSuffix`
    construct(this.kind = DocKind.Concat, this.text = "") {}

    ## Appends `part` to this node's parts. A `DocKind.Text` becomes a
    ## `DocKind.Concat` of its text and then `part`, so a text can stand in
    ## for a sequence that may grow.
    ##
    ## @param part the document to append
    ## @returns this node, so calls can be chained
    add(part: Doc): Doc {
        if (kind == DocKind.Text) {
            parts.append(Doc(DocKind.Text, text));
            kind = DocKind.Concat;
            text = "";
        }
        parts.append(part);
        return this;
    }

    ## Returns whether a hard line break (or a trailing comment) is inside,
    ## which forces every group around it to break.
    ##
    ## @returns true when the document cannot be printed on one line
    is_hard(): bool {
        if (!_hard) {
            _hard = Optional<bool>.Value(_find_hard());
        }
        return _hard.value();
    }

    # Whether a hard line break is inside, worked out from the parts.
    _find_hard(): bool {
        match (kind) {
            Hardline, BreakParent => {
                return true;
            }
            Choice => {
                return parts.count > 0 and parts[0].is_hard();
            }
            else => {
                for (var part in parts) {
                    if (part.is_hard()) {
                        return true;
                    }
                }
                return false;
            }
        }
        return false;
    }
}

## Returns a text document.
##
## @param value the text, with no line break in it
## @returns a `DocKind.Text`
export text(value: String): Doc {
    return Doc(DocKind.Text, value);
}

## Returns an empty sequence to `add` parts to.
##
## @returns a `DocKind.Concat` with no parts
export concat(): Doc {
    return Doc(DocKind.Concat);
}

## Returns a space that becomes a line break when its group breaks.
##
## @returns a `DocKind.Line`
export line(): Doc {
    return Doc(DocKind.Line);
}

## Returns nothing that becomes a line break when its group breaks.
##
## @returns a `DocKind.Softline`
export softline(): Doc {
    return Doc(DocKind.Softline);
}

## Returns a line break that always breaks.
##
## @returns a `DocKind.Hardline`
export hardline(): Doc {
    return Doc(DocKind.Hardline);
}

## Returns `content` indented one level where its lines break.
##
## @param content the document to indent
## @returns a `DocKind.Indent` holding `content`
export indent(content: Doc): Doc {
    return Doc(DocKind.Indent).add(content);
}

## Returns `content` as a group that breaks as a whole.
##
## @param content the document to group
## @returns a `DocKind.Group` holding `content`
export group(content: Doc): Doc {
    return Doc(DocKind.Group).add(content);
}

## Returns an empty choice to `add` layouts to, best first.
##
## @returns a `DocKind.Choice` with no options
export choice(): Doc {
    return Doc(DocKind.Choice);
}

## Returns a trailing comment, printed at the end of the current line.
##
## @param comment the comment text, starting with `#`
## @returns the comment as a line suffix that also breaks its groups
export trailing_comment(comment: String): Doc {
    return concat().add(Doc(DocKind.LineSuffix, comment_mark() + comment)).add(Doc(DocKind.BreakParent));
}

# A document to print, with the indentation and mode it is printed in.
struct Frame {
    int indent;
    Mode mode;
    Doc item;
    # Whether this frame is on the rest of the line after the item `fits`
    # measures, which only matters up to its first line break.
    bool in_rest;

    construct(this.indent = 0, this.mode = Mode.Flat, this.item = __null, this.in_rest = false) {}
}

# Whether `item`, printed flat from `column` at `indent`, keeps every line
# within `width`, including the rest of the line after it (from `rest`, whose
# frames are printed last to first) up to the next line break.
fits(item: Doc, indent: int, column: int, width: int, rest: Frame[]): bool {
    var stack = Array<Frame>();
    stack.append(Frame(indent, Mode.Flat, item));
    ulong rest_index = rest.count;
    int current = column;
    while (true) {
        if (current > width) {
            return false;
        }
        if (stack.is_empty) {
            if (rest_index == 0) {
                return true;
            }
            rest_index -= 1;
            var next = rest[rest_index];
            stack.append(Frame(next.indent, next.mode, next.item, true));
        }
        var frame = stack.pop();
        var doc = frame.item;
        match (doc.kind) {
            Text => {
                current += doc.text.length as int;
            }
            Concat, Indent, Group => {
                int nested = frame.indent;
                if (doc.kind == DocKind.Indent) {
                    nested += INDENT_WIDTH;
                }
                var nested_mode = frame.mode;
                if (doc.kind == DocKind.Group and doc.is_hard()) {
                    nested_mode = Mode.Break;
                }
                ulong i = doc.parts.count;
                while (i > 0) {
                    i -= 1;
                    stack.append(Frame(nested, nested_mode, doc.parts[i], frame.in_rest));
                }
            }
            Choice => {
                if (doc.parts.count > 0) {
                    stack.append(Frame(frame.indent, frame.mode, doc.parts[0], frame.in_rest));
                }
            }
            Line, Softline => {
                if (frame.mode == Mode.Break) {
                    if (frame.in_rest) {
                        return true;
                    }
                    current = frame.indent;
                } else if (doc.kind == DocKind.Line) {
                    current += 1;
                }
            }
            Hardline => {
                if (frame.in_rest) {
                    return true;
                }
                current = frame.indent;
            }
            LineSuffix, BreakParent => {}
        }
    }
    return true;
}

## Lays out `document` within `width` columns and returns the text. Lines
## end in `newline`, and have no trailing whitespace. Trailing comments start
## with `comment_mark()`; see `align_trailing_comments`.
##
## @param document the layout to print
## @param width the maximum line width to aim for
## @returns the printed text
export render(document: Doc, width: int): String {
    var lines = Array<String>();
    var current = StringBuilder();
    var suffix = StringBuilder();
    int column = 0;
    var stack = Array<Frame>();
    stack.append(Frame(0, Mode.Break, document));
    while (!stack.is_empty) {
        var frame = stack.pop();
        var doc = frame.item;
        var breaks = false;
        match (doc.kind) {
            Text => {
                current.append(doc.text);
                column += doc.text.length as int;
            }
            Concat, Indent => {
                int nested = frame.indent;
                if (doc.kind == DocKind.Indent) {
                    nested += INDENT_WIDTH;
                }
                ulong i = doc.parts.count;
                while (i > 0) {
                    i -= 1;
                    stack.append(Frame(nested, frame.mode, doc.parts[i]));
                }
            }
            Group => {
                var mode = Mode.Flat;
                if (doc.is_hard()) {
                    mode = Mode.Break;
                } else if (frame.mode == Mode.Break and !fits(doc, frame.indent, column, width, stack)) {
                    mode = Mode.Break;
                }
                ulong i = doc.parts.count;
                while (i > 0) {
                    i -= 1;
                    stack.append(Frame(frame.indent, mode, doc.parts[i]));
                }
            }
            Choice => {
                ulong count = doc.parts.count;
                ulong chosen = count - 1;
                var mode = Mode.Break;
                ulong i = 0;
                while (i + 1 < count) {
                    if (fits(doc.parts[i], frame.indent, column, width, stack)) {
                        chosen = i;
                        mode = Mode.Flat;
                        break;
                    }
                    i += 1;
                }
                stack.append(Frame(frame.indent, mode, doc.parts[chosen]));
            }
            Line => {
                if (frame.mode == Mode.Flat) {
                    current.append(" ");
                    column += 1;
                } else {
                    breaks = true;
                }
            }
            Softline => {
                breaks = frame.mode == Mode.Break;
            }
            Hardline => {
                breaks = true;
            }
            LineSuffix => {
                suffix.append(doc.text);
            }
            BreakParent => {}
        }
        if (breaks) {
            current.append(suffix.to_string());
            suffix.clear();
            lines.append(current.to_string());
            current.clear();
            current.append(" ".repeat(frame.indent as ulong));
            column = frame.indent;
        }
    }
    current.append(suffix.to_string());
    lines.append(current.to_string());
    var result = StringBuilder();
    for (var printed in lines) {
        result.append(printed.trim_end()).append("\n");
    }
    return result.to_string();
}
