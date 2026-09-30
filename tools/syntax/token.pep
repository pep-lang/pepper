## Tokens: the words of a Pepper source file, with the comments and line
## breaks around them kept, so a tool that prints tokens back loses nothing.

## The end of the file. Its leading comments are the file's last comments.
export const TOKEN_END = 0;
## A name or a keyword (`struct`, `if`, `x`, `String`).
export const TOKEN_IDENTIFIER = 1;
## An integer or floating-point literal (`42`, `0xFF`, `1.5e3`).
export const TOKEN_NUMBER = 2;
## A string literal, quotes and escapes included (`"a\n"`).
export const TOKEN_STRING = 3;
## An operator or punctuation mark (`+`, `==`, `{`, `=>`). `>` is always
## its own token, so `Array<Array<int>>` closes two generic lists; the
## parser joins adjacent `>` tokens into `>>`, `>=` and `>>=`.
export const TOKEN_PUNCTUATION = 4;
## A character literal, quotes and escapes included (`'a'`, `'\n'`).
export const TOKEN_CHARACTER = 5;

## A `#` comment, from the `#` to the end of its line.
export struct Comment {
    ## The comment's text, from `#` up to but not including the line break,
    ## with trailing whitespace removed.
    String text;
    ## The number of line breaks between the previous token or comment and
    ## this comment. Two or more means a blank line precedes it.
    int newlines_before;

    ## Creates a comment.
    ##
    ## @param this.text the comment's text, starting with `#`
    ## @param this.newlines_before the line breaks before it
    construct(this.text = "", this.newlines_before = 0) {}
}

## One token, with the trivia (whitespace and comments) around it.
##
## Comments belong to the token they sit next to: a comment on the same line
## after a token is that token's `trailing_comment`, and every other comment
## is a `LeadingComment` of the token after it.
export struct Token {
    ## What kind of token this is: one of the `TOKEN_` constants.
    int kind;
    ## The token's text exactly as written.
    String text;
    ## The byte offset of the token's first character in the source.
    ulong offset;
    ## The number of line breaks between the previous token (or its trailing
    ## comment) and this token, counting those around leading comments.
    int newlines_before;
    ## The number of line breaks between the last leading comment (or the
    ## previous token, when there are none) and this token.
    int newlines_after_comments;
    ## Whether any whitespace or comment separates this token from the one
    ## before it.
    bool space_before;
    ## The comments on their own lines before this token.
    Comment[] leading_comments = Array<Comment>();
    ## A comment after this token on the same line, or an empty String.
    String trailing_comment = "";

    ## Creates a token.
    ##
    ## @param this.kind one of the `TOKEN_` constants
    ## @param this.text the token's text
    ## @param this.offset the byte offset of its first character
    construct(this.kind = 0, this.text = "", this.offset = 0) {}

    ## Returns whether this token is the punctuation `text`.
    ##
    ## @param text the punctuation to compare with, such as `"{"`
    ## @returns true when the token is punctuation spelled `text`
    is(text: String): bool {
        return kind == TOKEN_PUNCTUATION and this.text == text;
    }

    ## Returns whether this token is the identifier or keyword `word`.
    ##
    ## @param word the word to compare with, such as `"struct"`
    ## @returns true when the token is an identifier spelled `word`
    is_word(word: String): bool {
        return kind == TOKEN_IDENTIFIER and text == word;
    }

    ## Returns whether any comment is attached to this token.
    ##
    ## @returns true when the token has leading or trailing comments
    has_comments(): bool {
        return leading_comments.count() > 0 or !trailing_comment.empty();
    }
}
