//! The parser reports an error, never panics, on a file cut off mid-way:
//! the language server parses every half-typed state of a document.

use pepper_parser::parser::parse_source_diag;

/// A closure cut off after its `=>`: the `(` is parsed again as a
/// parenthesized expression, from where it started.
#[test]
fn closure_cut_off_after_its_arrow() {
    for source in ["main(): int {\n    var f = (x) =>", "main(): int {\n    var f = (x: int) => ", "main(): int {\n    g((x) =>"] {
        assert!(parse_source_diag(source).is_err(), "{source:?}");
    }
}
