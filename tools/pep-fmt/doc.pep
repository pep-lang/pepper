## Documents: a layout description in the style of Wadler's "prettier
## printer". The formatter describes the code as a `Doc` tree (text, places
## where a line may break, groups that break together) and `render` chooses
## the line breaks that keep lines within a width.

## Text printed as is. It must not contain a line break.
export const doc_text = 0;
## Its parts, one after another.
export const doc_concat = 1;
## A space, or a line break when its group breaks.
export const doc_line = 2;
## Nothing, or a line break when its group breaks.
export const doc_softline = 3;
## Always a line break; every group around it breaks.
export const doc_hardline = 4;
## Its parts, with lines that break inside them indented one level more.
export const doc_indent = 5;
## Its parts, laid out on one line when they fit, else with every line of the
## group broken.
export const doc_group = 6;
## Text deferred to the end of the current line: a trailing comment.
export const doc_line_suffix = 7;
## Nothing, but it breaks every group around it, like a line break would.
export const doc_break_parent = 8;
## Alternative layouts of the same content: the first whose every line fits
## is printed flat; if none fits, the last is printed with its groups broken.
export const doc_choice = 9;

## The number of spaces in one indentation level.
export const indent_width = 4;

## Returns the byte that marks where a trailing comment starts in `render`'s
## output, so that `align_trailing_comments` can line them up. It never
## reaches the file. (A function, because a module-scope `String` constant is
## not allowed: `String` is not thread-safe.)
##
## @returns a String holding the byte 0x01
export comment_mark(): String {
    return "\x01";
}

const mode_flat = 0;
const mode_break = 1;

## A node of a layout description.
export struct Doc {
    ## What the node is: one of the `DOC_` constants.
    int kind;
    ## The text of a `doc_text` or `doc_line_suffix`.
    String text = "";
    ## The children of a `doc_concat`, `doc_indent`, `doc_group` or the
    ## options of a `doc_choice`.
    Doc[] parts = Array<Doc>();
    # Whether a hard line break is inside: 0 not computed yet, 1 yes, 2 no.
    int hard_state;

    ## Creates a document node.
    ##
    ## @param this.kind one of the `DOC_` constants
    ## @param this.text the text of a `doc_text` or `doc_line_suffix`
    construct(this.kind = 1, this.text = "") {}

    ## Appends `part` to this node's parts.
    ##
    ## @param part the document to append
    ## @returns this node, so calls can be chained
    add(part: Doc): Doc {
        parts.append(part);
        return this;
    }

    ## Returns whether a hard line break (or a trailing comment) is inside,
    ## which forces every group around it to break.
    ##
    ## @returns true when the document cannot be printed on one line
    is_hard(): bool {
        if (hard_state == 0) {
            hard_state = 2;
            if (kind == doc_hardline or kind == doc_break_parent) {
                hard_state = 1;
            } else if (kind == doc_choice) {
                if (parts.count() > 0 and parts[0].is_hard()) {
                    hard_state = 1;
                }
            } else {
                for (var part in parts) {
                    if (part.is_hard()) {
                        hard_state = 1;
                        break;
                    }
                }
            }
        }
        return hard_state == 1;
    }
}

## Returns a text document.
##
## @param value the text, with no line break in it
## @returns a `doc_text`
export text(value: String): Doc {
    return Doc(doc_text, value);
}

## Returns an empty sequence to `add` parts to.
##
## @returns a `doc_concat` with no parts
export concat(): Doc {
    return Doc(doc_concat);
}

## Returns a space that becomes a line break when its group breaks.
##
## @returns a `doc_line`
export line(): Doc {
    return Doc(doc_line);
}

## Returns nothing that becomes a line break when its group breaks.
##
## @returns a `doc_softline`
export softline(): Doc {
    return Doc(doc_softline);
}

## Returns a line break that always breaks.
##
## @returns a `doc_hardline`
export hardline(): Doc {
    return Doc(doc_hardline);
}

## Returns `content` indented one level where its lines break.
##
## @param content the document to indent
## @returns a `doc_indent` holding `content`
export indent(content: Doc): Doc {
    return Doc(doc_indent).add(content);
}

## Returns `content` as a group that breaks as a whole.
##
## @param content the document to group
## @returns a `doc_group` holding `content`
export group(content: Doc): Doc {
    return Doc(doc_group).add(content);
}

## Returns an empty choice to `add` layouts to, best first.
##
## @returns a `doc_choice` with no options
export choice(): Doc {
    return Doc(doc_choice);
}

## Returns a trailing comment, printed at the end of the current line.
##
## @param comment the comment text, starting with `#`
## @returns the comment as a line suffix that also breaks its groups
export trailing_comment(comment: String): Doc {
    return concat().add(Doc(doc_line_suffix, comment_mark() + comment)).add(Doc(doc_break_parent));
}

# A document to print, with the indentation and mode it is printed in.
struct Frame {
    int indent;
    int mode;
    Doc item;

    construct(this.indent = 0, this.mode = 0, this.item = __null) {}
}

spaces(count: int): String {
    var result = "";
    int i = 0;
    while (i < count) {
        result += " ";
        i += 1;
    }
    return result;
}

# Whether `item`, printed flat from `column` at `indent`, keeps every line
# within `width`, including the rest of the line after it (from `rest`, whose
# frames are printed last to first) up to the next line break.
fits(item: Doc, indent: int, column: int, width: int, rest: Frame[]): bool {
    var stack = Array<Frame>();
    stack.append(Frame(indent, mode_flat, item));
    ulong rest_index = rest.count();
    int current = column;
    while (true) {
        if (current > width) {
            return false;
        }
        if (stack.empty()) {
            if (rest_index == 0) {
                return true;
            }
            rest_index -= 1;
            var next = rest[rest_index];
            stack.append(Frame(next.indent, next.mode, next.item));
            # Everything after `item` only matters up to its first line break.
            stack.last().mode = next.mode + 10;
        }
        var frame = stack.pop();
        var doc = frame.item;
        bool in_rest = frame.mode >= 10;
        int mode = frame.mode % 10;
        int kind = doc.kind;
        if (kind == doc_text) {
            current += doc.text.length() as int;
        } else if (kind == doc_concat or kind == doc_indent or kind == doc_group) {
            int nested = frame.indent;
            if (kind == doc_indent) {
                nested += indent_width;
            }
            int nested_mode = frame.mode;
            if (kind == doc_group and doc.is_hard()) {
                nested_mode = mode_break;
                if (in_rest) {
                    nested_mode += 10;
                }
            }
            ulong i = doc.parts.count();
            while (i > 0) {
                i -= 1;
                stack.append(Frame(nested, nested_mode, doc.parts[i]));
            }
        } else if (kind == doc_choice) {
            if (doc.parts.count() > 0) {
                stack.append(Frame(frame.indent, frame.mode, doc.parts[0]));
            }
        } else if (kind == doc_line or kind == doc_softline) {
            if (mode == mode_break) {
                if (in_rest) {
                    return true;
                }
                current = frame.indent;
            } else if (kind == doc_line) {
                current += 1;
            }
        } else if (kind == doc_hardline) {
            if (in_rest) {
                return true;
            }
            current = frame.indent;
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
    var current = "";
    var suffix = "";
    int column = 0;
    var stack = Array<Frame>();
    stack.append(Frame(0, mode_break, document));
    while (!stack.empty()) {
        var frame = stack.pop();
        var doc = frame.item;
        int kind = doc.kind;
        if (kind == doc_text) {
            current += doc.text;
            column += doc.text.length() as int;
        } else if (kind == doc_concat or kind == doc_indent) {
            int nested = frame.indent;
            if (kind == doc_indent) {
                nested += indent_width;
            }
            ulong i = doc.parts.count();
            while (i > 0) {
                i -= 1;
                stack.append(Frame(nested, frame.mode, doc.parts[i]));
            }
        } else if (kind == doc_group) {
            int mode = mode_flat;
            if (doc.is_hard()) {
                mode = mode_break;
            } else if (frame.mode == mode_break and !fits(doc, frame.indent, column, width, stack)) {
                mode = mode_break;
            }
            ulong i = doc.parts.count();
            while (i > 0) {
                i -= 1;
                stack.append(Frame(frame.indent, mode, doc.parts[i]));
            }
        } else if (kind == doc_choice) {
            ulong count = doc.parts.count();
            ulong chosen = count - 1;
            int mode = mode_break;
            ulong i = 0;
            while (i + 1 < count) {
                if (fits(doc.parts[i], frame.indent, column, width, stack)) {
                    chosen = i;
                    mode = mode_flat;
                    break;
                }
                i += 1;
            }
            stack.append(Frame(frame.indent, mode, doc.parts[chosen]));
        } else if (kind == doc_line and frame.mode == mode_flat) {
            current += " ";
            column += 1;
        } else if (kind == doc_softline and frame.mode == mode_flat) {
            # Nothing.
        } else if (kind == doc_line or kind == doc_softline or kind == doc_hardline) {
            if (!suffix.empty()) {
                current += suffix;
                suffix = "";
            }
            lines.append(current);
            current = spaces(frame.indent);
            column = frame.indent;
        } else if (kind == doc_line_suffix) {
            suffix += doc.text;
        }
    }
    current += suffix;
    lines.append(current);
    var result = "";
    for (var printed in lines) {
        result += trim_end(printed);
        result += "\n";
    }
    return result;
}

## Returns `value` without trailing spaces.
##
## @param value the text to trim
## @returns the text up to its last non-space byte
export trim_end(value: String): String {
    var data = value.c_str();
    ulong end = value.size();
    while (end > 0 and data[end - 1] == ' ') {
        end -= 1;
    }
    if (end == value.size()) {
        return value;
    }
    if (end == 0) {
        return "";
    }
    return String(data, end);
}
