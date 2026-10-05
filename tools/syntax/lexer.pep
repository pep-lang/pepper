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
# the longest. `>` never starts a longer token (see TokenKind.Punctuation).
punctuation_table(): String[] {
    return [
        "===",
        "!==",
        "<<=",
        "...",
        "..>",
        "..",
        "==",
        "!=",
        "<=",
        "+=",
        "-=",
        "*=",
        "/=",
        "%=",
        "++",
        "--",
        "<<",
        "**",
        "&&",
        "||",
        "&=",
        "|=",
        "^=",
        "=>",
        "+",
        "-",
        "*",
        "/",
        "%",
        "<",
        ">",
        "&",
        "|",
        "^",
        "!",
        "~",
        "=",
        "(",
        ")",
        "[",
        "]",
        "{",
        "}",
        ",",
        ";",
        ":",
        ".",
        "?",
        "@"
    ];
}

# Whether the bytes of `text` occur in `data` at `offset`.
matches_at(data: __ptr<char>, size: ulong, offset: ulong, text: String): bool {
    ulong length = text.size;
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

# The offset of the `quote` that closes the string or character literal whose
# text starts at `start`, or of the line break or end of source that stops
# the scan first.
quoted_end(data: __ptr<char>, size: ulong, start: ulong, quote: int): ulong {
    ulong i = start;
    while (i < size and data[i] != quote and data[i] != '\n') {
        if (data[i] == '\\') {
            i += 1;
        }
        i += 1;
    }
    if (i > size) {
        return size;
    }
    return i;
}

# The offset of the `"` that closes the interpolated string whose text starts
# at `start`, inside another one's braces, or of the line break, `#` or end
# of source that stops the scan first.
interpolated_end(data: __ptr<char>, size: ulong, start: ulong): ulong {
    ulong i = start;
    while (i < size and data[i] != '"' and data[i] != '\n') {
        int c = data[i];
        if (c == '\\' or (c == '{' and i + 1 < size and data[i + 1] == '{')) {
            i += 2;
            continue;
        }
        if (c == '{') {
            i = interpolation_end(data, size, i + 1);
            if (i >= size or data[i] != '}') {
                return i;
            }
        }
        i += 1;
    }
    if (i > size) {
        return size;
    }
    return i;
}

# Where the expression in an interpolated string's braces ends, scanning from
# `start`, just after the `{`: the offset of the `}` that closes it, or of the
# line break, `#` or end of source that stops the scan first. Brackets nest,
# and literals are skipped whole, so `{f("}")}` ends at its last `}`.
# Mirrors `interpolation_end` in crates/pepper-parser/src/parser/parsers.rs.
interpolation_end(data: __ptr<char>, size: ulong, start: ulong): ulong {
    ulong i = start;
    ulong depth = 0;
    while (i < size) {
        int c = data[i];
        if (c == '\n' or c == '#') {
            return i;
        }
        if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            if (depth == 0) {
                return i;
            }
            depth -= 1;
        } else if (c == '"' or c == '\'') {
            i = quoted_end(data, size, i + 1, c);
            if (i >= size or data[i] != c) {
                return i;
            }
        } else if (c == '$' and i + 1 < size and data[i + 1] == '"') {
            i = interpolated_end(data, size, i + 2);
            if (i >= size or data[i] != '"') {
                return i;
            }
        }
        i += 1;
    }
    return size;
}

## Splits `source` into tokens. The last token is always a `TokenKind.End`
## that holds the comments after the last real token.
##
## @param source the text of a Pepper source file
## @returns the tokens, or the first lexical error: an unterminated string,
##   an unclosed `{` in an interpolated string, or a character that cannot
##   start a token
export lex(source: String): Result<Token[], SyntaxError> {
    var tokens = Array<Token>();
    # The punctuation by first byte, longest first, so each token tries
    # only the entries that can match.
    var by_first = Array<String[]>();
    while (by_first.count < 128) {
        by_first.append(Array<String>());
    }
    for (var p in punctuation_table()) {
        by_first[p.byte_at(0) as ulong].append(p);
    }
    var data = source.c_str();
    ulong size = source.size;
    ulong i = 0;
    # The comments waiting for the next token; null while there are none.
    Comment[] pending = __null;
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
            if (tokens.count > 0 and newlines == 0 and tokens.last()._trailing_comment === __null) {
                # A token is a value: change the stored one in place.
                var last = tokens.last();
                last.trailing_comment = text;
                tokens[tokens.count - 1] = last;
            } else {
                if (pending === __null) {
                    pending = Array<Comment>();
                }
                pending.append(Comment(text, newlines_since_comment, start));
                newlines_since_comment = 0;
            }
            space = true;
            continue;
        }

        ulong start = i;
        var kind = TokenKind.Punctuation;
        if (is_identifier_start(c)) {
            kind = TokenKind.Identifier;
            while (i < size and is_identifier_part(data[i])) {
                i += 1;
            }
        } else if (is_digit(c)) {
            kind = TokenKind.Number;
            if (c == '0' and i + 1 < size and data[i + 1] == 'x') {
                i += 2;
                while (i < size and is_hex_digit(data[i])) {
                    i += 1;
                }
            } else if (start > 0 and data[start - 1] == '.' and !(start > 1 and data[start - 2] == '.')) {
                # A tuple element after `.` is digits only: `t.0.1` is two
                # accesses, as the compiler reads it. After a range's `..`
                # (`1.5..3.0`) the number is a whole one.
                while (i < size and is_digit(data[i])) {
                    i += 1;
                }
            } else {
                while (i < size and is_digit(data[i])) {
                    i += 1;
                }
                # `1..5` and `1..>5` are ranges, not `1.` and a `.`.
                if (i < size and data[i] == '.' and !(i + 1 < size and data[i + 1] == '.')) {
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
        } else if (c == '"' or c == '\'' or (c == '$' and i + 1 < size and data[i + 1] == '"')) {
            kind = TokenKind.String;
            if (c == '\'') {
                kind = TokenKind.Character;
            }
            # An interpolated string, `$"sum = {a + b}"`, is one token; the
            # expressions in its braces are skipped whole, strings and all.
            bool interpolated = c == '$';
            if (interpolated) {
                c = '"';
                i += 1;
            }
            i += 1;
            bool closed = false;
            bool line_break = false;
            while (i < size and (c == '"' or data[i] != '\n')) {
                int b = data[i];
                if (b == '\\' or (interpolated and b == '{' and i + 1 < size and data[i + 1] == '{')) {
                    i += 2;
                    continue;
                }
                if (interpolated and b == '{') {
                    ulong end = interpolation_end(data, size, i + 1);
                    if (end >= size or data[end] != '}') {
                        # After a line break, the literal was likely never
                        # closed, as the compiler reports it.
                        if (line_break) {
                            break;
                        }
                        if (end < size and data[end] == '#') {
                            return Result<Token[], SyntaxError>.err(
                                SyntaxError("a comment cannot appear inside '{}' in an interpolated string", end)
                            );
                        }
                        return Result<Token[], SyntaxError>.err(SyntaxError("expected '}'", end));
                    }
                    i = end + 1;
                    continue;
                }
                if (b == '\n') {
                    line_break = true;
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
            if (c >= 0 and c < 128) {
                for (var p in by_first[c as ulong]) {
                    if (matches_at(data, size, i, p)) {
                        i += p.size;
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                return Result<Token[], SyntaxError>.err(SyntaxError("unexpected character", start));
            }
        }

        if (i > size) {
            i = size;
        }
        var token = Token(kind, start, i - start);
        token.newlines_before = newlines;
        token.newlines_after_comments = newlines_since_comment;
        token.space_before = space;
        token._leading_comments = pending;
        tokens.append(token);
        pending = __null;
        newlines = 0;
        newlines_since_comment = 0;
        space = false;
    }
    var end = Token(TokenKind.End, size, 0);
    end.newlines_before = newlines;
    end.newlines_after_comments = newlines_since_comment;
    end.space_before = space;
    end._leading_comments = pending;
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
    while (i < offset and i < source.size) {
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
    if (i > source.size) {
        i = source.size;
    }
    ulong column = 1;
    while (i > 0 and data[i - 1] != '\n') {
        column += 1;
        i -= 1;
    }
    return column;
}
