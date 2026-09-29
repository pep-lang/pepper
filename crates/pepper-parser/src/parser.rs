pub mod parsers;

use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::ast::{Module, Span};

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

/// Parse source text into a `Module`.
pub fn parse_source(name: &str, source: &str) -> Result<Module, String> {
    let _guard = parsers::track_source(source.len());
    let mut input: &str = source;
    let module = parsers::parse_module(&mut input).map_err(|_| {
        // Report the parse error at the furthest point parsing reached. PEG
        // backtracking rewinds `input`, so the remaining-slice offset alone
        // underreports the true failure position.
        let offset = parsers::max_pos().min(source.len());
        let p = Span::offset_to_position(source, offset);
        format!("{}:{}:{}: parse error", name, p.line + 1, p.col + 1)
    })?;
    // `T*` is only legal in extern declarations; see `check_pointer_syntax`.
    parsers::check_pointer_syntax(&module).map_err(|e| {
        let p = Span::offset_to_position(source, e.offset.min(source.len()));
        format!("{}:{}:{}: {}", name, p.line + 1, p.col + 1, e.message)
    })?;
    Ok(module)
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
    fn parse_error_reports_furthest_position() {
        // The failure is mid-file; PEG backtracking must not drag the reported
        // position back to line 1.
        let src = "main(): int {\n    var x = ;\n}\n";
        match super::parse_source("t.pep", src) {
            Ok(_) => panic!("expected a parse error"),
            Err(e) => assert!(e.starts_with("t.pep:2:"), "reported position: {}", e),
        }
    }
}
