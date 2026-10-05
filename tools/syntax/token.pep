## Tokens: the words of a Pepper source file, with the comments and line
## breaks around them kept, so a tool that prints tokens back loses nothing.

## Which kind of word a `Token` is.
export enum TokenKind {
    ## The end of the file. Its leading comments are the file's last comments.
    End,
    ## A name or a keyword (`struct`, `if`, `x`, `String`).
    Identifier,
    ## An integer or floating-point literal (`42`, `0xFF`, `1.5e3`).
    Number,
    ## A string literal, quotes and escapes included (`"a\n"`), or an
    ## interpolated one, `$` included (`$"n = {n}"`).
    String,
    ## An operator or punctuation mark (`+`, `==`, `{`, `=>`). `>` is always
    ## its own token, so `Array<Array<int>>` closes two generic lists; the
    ## parser joins adjacent `>` tokens into `>>`, `>=` and `>>=`.
    Punctuation,
    ## A character literal, quotes and escapes included (`'a'`, `'\n'`).
    Character,
}

## A `#` comment, from the `#` to the end of its line.
export struct Comment {
    ## The comment's text, from `#` up to but not including the line break,
    ## with trailing whitespace removed.
    String text;
    ## The number of line breaks between the previous token or comment and
    ## this comment. Two or more means a blank line precedes it.
    int newlines_before;
    ## The byte offset of the `#` in the source.
    ulong offset;

    ## Creates a comment.
    ##
    ## @param this.text the comment's text, starting with `#`
    ## @param this.newlines_before the line breaks before it
    ## @param this.offset the byte offset of the `#` in the source
    construct(this.text = "", this.newlines_before = 0, this.offset = 0) {}
}

## One token, with the trivia (whitespace and comments) around it.
##
## A token is a value that points into the source it was read from: its
## text is the `size` bytes at `offset`, which `text(source)` copies out and
## `is` and `is_word` compare in place, so reading a token allocates
## nothing.
##
## Comments belong to the token they sit next to: a comment on the same line
## after a token is that token's `trailing_comment`, and every other comment
## is a `LeadingComment` of the token after it.
[Value]
export struct Token {
    ## What kind of token this is.
    TokenKind kind;
    ## The byte offset of the token's first character in the source.
    ulong offset;
    ## The token's length in bytes.
    ulong size;
    ## The number of line breaks between the previous token (or its trailing
    ## comment) and this token, counting those around leading comments.
    int newlines_before;
    ## The number of line breaks between the last leading comment (or the
    ## previous token, when there are none) and this token.
    int newlines_after_comments;
    ## Whether any whitespace or comment separates this token from the one
    ## before it.
    bool space_before;
    # The comments on their own lines before this token; null when there
    # are none, as for most tokens.
    Comment[] _leading_comments;
    # The comment after this token on its line; null when there is none.
    String _trailing_comment;

    ## Creates a token.
    ##
    ## @param this.kind what kind of token it is
    ## @param this.offset the byte offset of its first character
    ## @param this.size its length in bytes
    construct(this.kind = TokenKind.End, this.offset = 0, this.size = 0) {}

    ## The comments on their own lines before this token. Reads as a new
    ## empty array when there are none; assign the array to change them.
    var leading_comments: Comment[] {
        get {
            if (_leading_comments === __null) {
                return Array<Comment>();
            }
            return _leading_comments;
        }
        set {
            if (value.count == 0) {
                _leading_comments = __null;
            } else {
                _leading_comments = value;
            }
        }
    }

    ## A comment after this token on the same line, or an empty String.
    var trailing_comment: String {
        get {
            if (_trailing_comment === __null) {
                return "";
            }
            return _trailing_comment;
        }
        set {
            if (value.is_empty) {
                _trailing_comment = __null;
            } else {
                _trailing_comment = value;
            }
        }
    }

    ## Returns the token's text exactly as written: a copy of its bytes in
    ## `source`.
    ##
    ## @param source the text the token was read from
    ## @returns the token's text
    text(source: String): String {
        return source.substr_bytes(offset, size);
    }

    ## Returns whether this token is the punctuation `text`.
    ##
    ## @param source the text the token was read from
    ## @param text the punctuation to compare with, such as `"{"`
    ## @returns true when the token is punctuation spelled `text`
    is(source: String, text: String): bool {
        return kind == TokenKind.Punctuation and spells(source, text);
    }

    ## Returns whether this token is the identifier or keyword `word`.
    ##
    ## @param source the text the token was read from
    ## @param word the word to compare with, such as `"struct"`
    ## @returns true when the token is an identifier spelled `word`
    is_word(source: String, word: String): bool {
        return kind == TokenKind.Identifier and spells(source, word);
    }

    ## Returns whether the token's text is `text`, comparing in place.
    ##
    ## @param source the text the token was read from
    ## @param text the text to compare with
    ## @returns true when the token's bytes are those of `text`
    spells(source: String, text: String): bool {
        return text.size == size and spells_at(source, offset, size, text);
    }

    ## Returns whether comments on their own lines precede this token.
    ##
    ## @returns true when `leading_comments` is not empty
    has_leading_comments(): bool {
        return !_leading_comments.is_empty;
    }

    ## Returns whether a comment follows this token on its line.
    ##
    ## @returns true when `trailing_comment` is not empty
    has_trailing_comment(): bool {
        return _trailing_comment !== __null;
    }

    ## Returns whether any comment is attached to this token.
    ##
    ## @returns true when the token has leading or trailing comments
    has_comments(): bool {
        return !_leading_comments.is_empty or _trailing_comment !== __null;
    }
}

# Whether the `size` bytes of `source` at `offset` are those of `text`, which
# is `size` bytes long.
spells_at(source: String, offset: ulong, size: ulong, text: String): bool {
    var data = source.c_str() + offset;
    var bytes = text.c_str();
    ulong i = 0;
    while (i < size) {
        if (data[i] != bytes[i]) {
            return false;
        }
        i += 1;
    }
    return true;
}
