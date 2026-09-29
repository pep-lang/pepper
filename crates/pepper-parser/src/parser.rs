pub mod parsers;

use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::ast::{Module, Span};
use crate::diagnostic::{Diagnostic, FileId, Loc};

/// Parse a single `.pep` file from disk.
pub fn parse_file(path: &Path) -> Result<Module, String> {
    let name = path
        .to_str()
        .ok_or_else(|| format!("invalid path: {:?}", path))?;
    let mut file = File::open(path).map_err(|e| format!("cannot open {}: {}", name, e))?;
    let mut content = String::new();
    file.read_to_string(&mut content)
        .map_err(|e| format!("cannot read {}: {}", name, e))?;
    parse_source(name, &content)
}

/// Parse source text into a `Module`. Errors are rendered clang-style (see
/// [`crate::diagnostic`]).
pub fn parse_source(name: &str, source: &str) -> Result<Module, String> {
    parse_source_diag(source).map_err(|d| d.render_in(name, source))
}

/// Parse source text into a `Module`, returning a failure as a structured
/// diagnostic whose locations carry the default [`FileId`](crate::diagnostic::FileId).
pub fn parse_source_diag(source: &str) -> Result<Module, Diagnostic> {
    let _guard = parsers::track_source(source.len());
    let mut input: &str = source;
    let module = parsers::parse_module(&mut input).map_err(|_| parse_error(source))?;
    // `T*` is only legal in extern declarations; see `check_pointer_syntax`.
    // Imports come first; see `check_import_order`.
    parsers::check_pointer_syntax(&module).and_then(|_| parsers::check_import_order(&module)).map_err(|e| {
        Diagnostic::error(e.message).at(at(token_at(source, e.offset)))
    })?;
    Ok(module)
}

fn at(span: Span) -> Loc {
    Loc::new(FileId::default(), span)
}

/// The diagnostic for a failed parse: what the grammar expected at the
/// furthest point it reached, or the token it could not use there. PEG
/// backtracking rewinds the input, so the remaining slice alone would
/// underreport the failure position.
fn parse_error(source: &str) -> Diagnostic {
    let furthest = parsers::skip_trivia(source, parsers::max_pos());
    match parsers::expectation() {
        Some(e) if e.offset >= furthest => {
            let mut d = Diagnostic::error(format!("expected {}", one_of(&e.expected))).at(at(token_at(source, e.offset)));
            if let Some((offset, note)) = e.note {
                d = d.with_note(note, Some(at(Span { start: offset, end: offset + 1 })));
            }
            d
        }
        _ => {
            let span = token_at(source, furthest);
            let message = if span.is_empty() {
                "unexpected end of file".to_string()
            } else {
                format!("unexpected '{}'", &source[span.start..span.end])
            };
            Diagnostic::error(message).at(at(span))
        }
    }
}

/// `a`, `a or b`, `a, b, or c`.
fn one_of(items: &[&str]) -> String {
    match items {
        [] => "a token".to_string(),
        [one] => one.to_string(),
        [a, b] => format!("{} or {}", a, b),
        [rest @ .., last] => format!("{}, or {}", rest.join(", "), last),
    }
}

/// The span of the token starting at `offset`: an identifier or number, a
/// string literal's opening quote, or one punctuation character; empty at the
/// end of the input.
fn token_at(source: &str, offset: usize) -> Span {
    let offset = offset.min(source.len());
    let rest = &source[offset..];
    let word = rest.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).unwrap_or(rest.len());
    let len = if word > 0 { word } else { rest.chars().next().map_or(0, char::len_utf8) };
    Span { start: offset, end: offset + len }
}

#[cfg(test)]
mod tests {
    fn pointer_error(src: &str) -> String {
        match super::parse_source("t.pep", src) {
            Ok(_) => panic!("expected `T*` to be rejected in: {}", src),
            Err(e) => e,
        }
    }

    #[test]
    fn c_pointer_syntax_allowed_in_extern() {
        let src = "extern void* memcpy(void* dst, char* src, ulong n);\n\
                   extern int** table(int*** p);\n\
                   struct S {\n    extern char* getenv(char* name);\n}\n";
        super::parse_source("t.pep", src).expect("extern `T*` must parse");
    }

    #[test]
    fn c_pointer_syntax_rejected_outside_extern() {
        let cases = [
            ("f(p: void*) {}", "void*", "__ptr<void>"),
            ("f(char* p) {}", "char*", "__ptr<char>"),
            ("f(): char* { return __null; }", "char*", "__ptr<char>"),
            ("struct S {\n    char* data;\n}", "char*", "__ptr<char>"),
            ("struct S {\n    var data: int** = __null;\n}", "int**", "__ptr<__ptr<int>>"),
            ("f() {\n    var a: void* = __null;\n}", "void*", "__ptr<void>"),
            ("f() {\n    char* x = __null;\n}", "char*", "__ptr<char>"),
            ("var g: void* = __null;", "void*", "__ptr<void>"),
            ("type P = char*;", "char*", "__ptr<char>"),
            ("f() {\n    var a = Array<char*>();\n}", "char*", "__ptr<char>"),
            ("f(x: ulong) {\n    var p = x as void*;\n}", "void*", "__ptr<void>"),
            ("f(p: __ptr<char>*) {}", "__ptr<char>*", "__ptr<__ptr<char>>"),
        ];
        for (src, written, suggested) in cases {
            let e = pointer_error(src);
            let expected = format!(
                "C pointer syntax `{}` is only allowed in extern declarations; use `{}`",
                written, suggested
            );
            assert!(e.contains(&expected), "source {:?}: got {:?}", src, e);
        }
    }

    #[test]
    fn c_pointer_syntax_error_position() {
        let e = pointer_error("f() {\n    var a: void* = __null;\n}\n");
        assert!(e.starts_with("t.pep:2:12: "), "reported position: {}", e);
    }

    #[test]
    fn ptr_intrinsic_accepted_everywhere() {
        let src = "type P = __ptr<char>;\n\
                   var g: __ptr<void> = __null;\n\
                   struct S {\n    __ptr<char> data;\n    var more: __ptr<__ptr<int>> = __null;\n}\n\
                   f(p: __ptr<void>, __ptr<char> q): __ptr<char> {\n\
                       var a: __ptr<void> = p + 1;\n\
                       __ptr<char> b = q;\n\
                       var c = Array<__ptr<char>>();\n\
                       var d = (a as ulong) as __ptr<char>;\n\
                       return b;\n\
                   }\n";
        super::parse_source("t.pep", src).expect("`__ptr<T>` must parse everywhere");
    }

    #[test]
    fn multiplication_is_not_pointer_syntax() {
        // `*` in expressions is multiplication, never a pointer type.
        let src = "f(a: int, b: int): int {\n    var c = a * b;\n    c = a*b;\n    return a < b * c ? 1 : 0;\n}\n";
        super::parse_source("t.pep", src).expect("multiplication must parse");
    }

    #[test]
    fn imports_come_before_declarations() {
        let e = match super::parse_source("t.pep", "import a;\nf() {}\nimport b;\n") {
            Ok(_) => panic!("expected a late import to be rejected"),
            Err(e) => e,
        };
        assert_eq!(
            e,
            "t.pep:3:1: error: imports must come before all declarations\n\
             \x20   3 | import b;\n\
             \x20     | ^~~~~~"
        );
        super::parse_source("t.pep", "import a;\nimport \"b\";\nexport x as y;\nf() {}\n").expect("imports first");
    }

    #[test]
    fn parse_error_reports_furthest_position() {
        // The failure is mid-file; PEG backtracking must not drag the reported
        // position back to line 1.
        let src = "main(): int {\n    var x = ;\n}\n";
        match super::parse_source("t.pep", src) {
            Ok(_) => panic!("expected a parse error"),
            Err(e) => assert!(e.starts_with("t.pep:2:"), "reported position: {}", e),
        }
    }

    /// The header line of the error `src` fails to parse with.
    fn parse_error_header(src: &str) -> String {
        match super::parse_source("t.pep", src) {
            Ok(_) => panic!("expected a parse error in: {:?}", src),
            Err(e) => e.lines().next().unwrap().to_string(),
        }
    }

    #[test]
    fn parse_errors_say_what_was_expected() {
        let cases = [
            ("main(): int {\n    var x = ;\n}\n", "t.pep:2:13: error: expected expression"),
            ("main(): int {\n    var x = 1 2;\n}\n", "t.pep:2:15: error: expected ';'"),
            ("main(): int {\n    return f(1, 2;\n}\n", "t.pep:2:18: error: expected ')'"),
            ("main(): int {\n    return (1 + 2;\n}\n", "t.pep:2:18: error: expected ')'"),
            ("main(): int {\n    var a = b[1;\n}\n", "t.pep:2:16: error: expected ']'"),
            ("main(): int {\n    var p = q.;\n}\n", "t.pep:2:15: error: expected member name"),
            ("main(): int {\n    var x: = 3;\n}\n", "t.pep:2:12: error: expected type"),
            ("main(): int {\n    x = 1 +;\n}\n", "t.pep:2:12: error: expected expression"),
            ("123\n", "t.pep:1:1: error: expected declaration"),
            ("main(: int {\n}\n", "t.pep:1:6: error: unexpected ':'"),
        ];
        for (src, header) in cases {
            assert_eq!(parse_error_header(src), header, "source {:?}", src);
        }
    }

    #[test]
    fn unclosed_brace_points_at_its_opening() {
        let e = super::parse_source("t.pep", "main(): int {\n    if x {\n        return 1;\n    }\n").unwrap_err();
        assert_eq!(
            e,
            "t.pep:5:1: error: expected '}'\n\
             \x20   5 | \n\
             \x20     | ^\n\
             t.pep:1:13: note: to match this '{'\n\
             \x20   1 | main(): int {\n\
             \x20     |             ^"
        );
        let e = super::parse_source("t.pep", "struct P {\n    int x;\n").unwrap_err();
        assert!(e.starts_with("t.pep:3:1: error: expected '}'\n") && e.contains("t.pep:1:10: note: to match this '{'"), "{}", e);
    }

    #[test]
    fn unterminated_string_points_at_its_opening_quote() {
        let e = super::parse_source("t.pep", "main(): int {\n    var s = \"abc;\n}\n").unwrap_err();
        assert!(e.contains("t.pep:2:13: note: to match this '\"'"), "{}", e);
    }

    #[test]
    fn parse_error_renders_the_source_line() {
        let e = super::parse_source("t.pep", "main(): int {\n    var x = ;\n}\n").unwrap_err();
        assert_eq!(e, "t.pep:2:13: error: expected expression\n    2 |     var x = ;\n      |             ^");
    }
}
