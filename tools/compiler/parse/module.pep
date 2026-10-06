## The compiler's parser: `parse(source)` builds the `compiler.ast` tree of
## one source file, exactly as the Rust parser does, straight from the
## tokens that the `syntax` library's lexer reads.
export * from "parser";
