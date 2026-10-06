## Pepper's lexer as a library: `lex(source)` returns the tokens of a source
## file, each with the comments and line breaks around it, for the compiler's
## parser (`compiler.parse`) and the tools that read its token table, such as
## pep-fmt.
export * from "lexer";
export * from "token";
