## The lexer: splits Pepper source text into tokens, attaching every comment
## and line break to a token so nothing is lost.

import "token";

## A syntax error: what went wrong and where.
export struct SyntaxError {
    ## What went wrong, worded like a clang diagnostic (`expected ';'`).
    String message;
    ## The byte offset in the source where the error was found.
    ulong offset;

    ## Creates a syntax error.
    ##
    ## @param this.message what went wrong
    ## @param this.offset the byte offset of the problem
    construct(this.message = "", this.offset = 0) {}
}

## Returns whether `c` is an ASCII digit.
##
## @param c the byte to test
## @returns true for `0` to `9`
export is_digit(c: int): bool {
    return c >= '0' and c <= '9';
}

## Returns whether `c` can start an identifier: an ASCII letter or `_`.
##
## @param c the byte to test
## @returns true for a letter or underscore
export is_identifier_start(c: int): bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

## Returns whether `c` can continue an identifier: a letter, digit or `_`.
##
## @param c the byte to test
## @returns true for a letter, digit or underscore
export is_identifier_part(c: int): bool {
    return is_identifier_start(c) or is_digit(c);
}

is_hex_digit(c: int): bool {
    return is_digit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

# The punctuation the lexer recognizes, longest first so the first match is
# the longest. `>` never starts a longer token (see token_punctuation).
punctuation_table(): String[] {
    var table = Array<String>();
    table.append("===");
    table.append("!==");
    table.append("<<=");
    table.append("...");
    table.append("==");
    table.append("!=");
    table.append("<=");
    table.append("+=");
    table.append("-=");
    table.append("*=");
    table.append("/=");
    table.append("%=");
    table.append("++");
    table.append("--");
    table.append("<<");
    table.append("**");
    table.append("&&");
    table.append("||");
    table.append("&=");
    table.append("|=");
    table.append("^=");
    table.append("=>");
    table.append("+");
    table.append("-");
    table.append("*");
    table.append("/");
    table.append("%");
    table.append("<");
    table.append(">");
    table.append("&");
    table.append("|");
    table.append("^");
    table.append("!");
    table.append("~");
    table.append("=");
    table.append("(");
    table.append(")");
    table.append("[");
    table.append("]");
    table.append("{");
    table.append("}");
    table.append(",");
    table.append(";");
    table.append(":");
    table.append(".");
    table.append("?");
    table.append("@");
    return table;
}

# Whether the bytes of `text` occur in `data` at `offset`.
matches_at(data: __ptr<char>, size: ulong, offset: ulong, text: String): bool {
    ulong length = text.size();
    if (offset + length > size) {
        return false;
    }
    var bytes = text.c_str();
    ulong i = 0;
    while (i < length) {
        if (data[offset + i] != bytes[i]) {
            return false;
        }
        i += 1;
    }
    return true;
}

# The bytes from `start` up to `end` as a String.
slice(data: __ptr<char>, start: ulong, end: ulong): String {
    if (end <= start) {
        return "";
    }
    return String(data + start, end - start);
}

## Splits `source` into tokens. The last token is always a `token_end`
## that holds the comments after the last real token.
##
## @param source the text of a Pepper source file
## @returns the tokens, or the first lexical error: an unterminated string or
##   a character that cannot start a token
export lex(source: String): Result<Token[], SyntaxError> {
    var tokens = Array<Token>();
    var table = punctuation_table();
    var data = source.c_str();
    ulong size = source.size();
    ulong i = 0;
    var pending = Array<Comment>();
    int newlines = 0;
    int newlines_since_comment = 0;
    bool space = false;
    while (i < size) {
        int c = data[i];
        if (c == '\n') {
            newlines += 1;
            newlines_since_comment += 1;
            space = true;
            i += 1;
            continue;
        }
        if (c == ' ' or c == '\t' or c == '\r') {
            space = true;
            i += 1;
            continue;
        }
        if (c == '#') {
            ulong start = i;
            while (i < size and data[i] != '\n') {
                i += 1;
            }
            ulong end = i;
            while (end > start and (data[end - 1] == ' ' or data[end - 1] == '\t' or data[end - 1] == '\r')) {
                end -= 1;
            }
            var text = slice(data, start, end);
            if (tokens.count() > 0 and newlines == 0 and tokens.last().trailing_comment.empty()) {
                tokens.last().trailing_comment = text;
            } else {
                pending.append(Comment(text, newlines_since_comment));
                newlines_since_comment = 0;
            }
            space = true;
            continue;
        }

        ulong start = i;
        int kind = token_punctuation;
        if (is_identifier_start(c)) {
            kind = token_identifier;
            while (i < size and is_identifier_part(data[i])) {
                i += 1;
            }
        } else if (is_digit(c)) {
            kind = token_number;
            if (c == '0' and i + 1 < size and data[i + 1] == 'x') {
                i += 2;
                while (i < size and is_hex_digit(data[i])) {
                    i += 1;
                }
            } else if (start > 0 and data[start - 1] == '.') {
                # A tuple element after `.` is digits only: `t.0.1` is two
                # accesses, as the compiler reads it.
                while (i < size and is_digit(data[i])) {
                    i += 1;
                }
            } else {
                while (i < size and is_digit(data[i])) {
                    i += 1;
                }
                if (i < size and data[i] == '.') {
                    i += 1;
                    while (i < size and is_digit(data[i])) {
                        i += 1;
                    }
                }
                if (i < size and (data[i] == 'e' or data[i] == 'E')) {
                    i += 1;
                    if (i < size and (data[i] == '+' or data[i] == '-')) {
                        i += 1;
                    }
                    while (i < size and is_digit(data[i])) {
                        i += 1;
                    }
                }
            }
        } else if (c == '"' or c == '\'') {
            kind = token_string;
            if (c == '\'') {
                kind = token_character;
            }
            i += 1;
            bool closed = false;
            while (i < size and (c == '"' or data[i] != '\n')) {
                int b = data[i];
                if (b == '\\') {
                    i += 2;
                    continue;
                }
                i += 1;
                if (b == c) {
                    closed = true;
                    break;
                }
            }
            if (!closed) {
                if (c == '\'') {
                    return Result<Token[], SyntaxError>.err(SyntaxError("missing terminating ' character", start));
                }
                return Result<Token[], SyntaxError>.err(SyntaxError("missing terminating '\"' character", start));
            }
        } else {
            bool found = false;
            for (var p in table) {
                if (matches_at(data, size, i, p)) {
                    i += p.size();
                    found = true;
                    break;
                }
            }
            if (!found) {
                return Result<Token[], SyntaxError>.err(SyntaxError("unexpected character", start));
            }
        }

        if (i > size) {
            i = size;
        }
        var token = Token(kind, slice(data, start, i), start);
        token.newlines_before = newlines;
        token.newlines_after_comments = newlines_since_comment;
        token.space_before = space;
        token.leading_comments = pending;
        tokens.append(token);
        pending = Array<Comment>();
        newlines = 0;
        newlines_since_comment = 0;
        space = false;
    }
    var end = Token(token_end, "", size);
    end.newlines_before = newlines;
    end.newlines_after_comments = newlines_since_comment;
    end.space_before = space;
    end.leading_comments = pending;
    tokens.append(end);
    return Result<Token[], SyntaxError>.ok(tokens);
}

## Converts a byte offset in `source` to a 1-based line number.
##
## @param source the text the offset points into
## @param offset a byte offset in `source`
## @returns the line that holds the offset, counting from 1
export line_of(source: String, offset: ulong): ulong {
    var data = source.c_str();
    ulong line = 1;
    ulong i = 0;
    while (i < offset and i < source.size()) {
        if (data[i] == '\n') {
            line += 1;
        }
        i += 1;
    }
    return line;
}

## Converts a byte offset in `source` to a 1-based column, counted in bytes.
##
## @param source the text the offset points into
## @param offset a byte offset in `source`
## @returns the column of the offset within its line, counting from 1
export column_of(source: String, offset: ulong): ulong {
    var data = source.c_str();
    ulong i = offset;
    if (i > source.size()) {
        i = source.size();
    }
    ulong column = 1;
    while (i > 0 and data[i - 1] != '\n') {
        column += 1;
        i -= 1;
    }
    return column;
}
