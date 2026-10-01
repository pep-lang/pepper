//! Character literals: `'a'` is a `byte` holding the character's ASCII code.
//! Covers escapes, inference, widening against the other integer types,
//! comparisons with raw bytes, module-scope constants, and the parse errors.

use crate::support::compile_jit_with_runtime;

/// Run a `test(): int` program whose checks `return <case index>` on failure.
fn assert_cases(source: &str) {
    assert_eq!(compile_jit_with_runtime(source), 0, "first failing case index");
}

fn parse_error(source: &str) -> String {
    pepper_parser::parser::parse_source("main.pep", source).map(|_| ()).unwrap_err().to_string()
}

#[test]
fn values_and_escapes() {
    assert_cases(
        r#"test(): int {
    if ('a' != 97) { return 1; }
    if ('"' != 34) { return 2; }
    if ('#' != 35) { return 3; }
    if ('\n' != 10 or '\t' != 9 or '\r' != 13 or '\0' != 0) { return 4; }
    if ('\\' != 92 or '\'' != 39) { return 5; }
    if ('\x41' != 'A') { return 6; }
    if ('\xFF' != 255) { return 7; }
    if ('\u{7A}' != 'z') { return 8; }
    if (' ' != 32) { return 9; }
    return 0;
}"#,
    );
}

#[test]
fn is_a_byte_that_widens() {
    assert_cases(
        r#"takes_int(x: int): int { return x; }
test(): int {
    var c = 'a';
    if (sizeof<byte>() != 1) { return 1; }
    byte b = c;
    int i = 'b';
    short s = 'c';
    ulong u = 'd';
    char ch = 'e';
    if (b != 97 or i != 98 or s != 99 or u != 100 or ch != 101) { return 2; }
    if (takes_int('f') != 102) { return 3; }
    if ('z' - 'a' != 25) { return 4; }
    int digit = '7' - '0';
    if (digit != 7) { return 5; }
    return 0;
}"#,
    );
}

#[test]
fn compares_with_raw_bytes() {
    assert_cases(
        r#"const QUOTE = '"';
is_lower(c: int): bool { return c >= 'a' and c <= 'z'; }
test(): int {
    var s = "a\"Z";
    var p = s.c_str();
    if (p[0] != 'a') { return 1; }
    if (p[1] != QUOTE) { return 2; }
    if (!is_lower(p[0]) or is_lower(p[2])) { return 3; }
    var bytes = Array<byte>();
    bytes.append('x');
    if (bytes[0] != 'x') { return 4; }
    return 0;
}"#,
    );
}

#[test]
fn parse_errors() {
    assert_eq!(
        parse_error("main(): int {\n    var x = '';\n    return 0;\n}\n"),
        "main.pep:2:13: error: empty character literal\n\
         \x20   2 |     var x = '';\n\
         \x20     |             ^~"
    );
    assert_eq!(
        parse_error("main(): int {\n    var x = 'ab';\n    return 0;\n}\n"),
        "main.pep:2:13: error: character literal may only contain one character; use a string for more\n\
         \x20   2 |     var x = 'ab';\n\
         \x20     |             ^~~~"
    );
    assert_eq!(
        parse_error("main(): int {\n    var x = 'a;\n    return 0;\n}\n"),
        "main.pep:2:13: error: missing terminating ' character\n\
         \x20   2 |     var x = 'a;\n\
         \x20     |             ^"
    );
    assert_eq!(
        parse_error("main(): int {\n    var x = '\u{e9}';\n    return 0;\n}\n"),
        "main.pep:2:14: error: character literal must be a single ASCII character; use a string for other characters\n\
         \x20   2 |     var x = '\u{e9}';\n\
         \x20     |              ^"
    );
    assert_eq!(
        parse_error("main(): int {\n    var x = '\\x4';\n    return 0;\n}\n"),
        "main.pep:2:14: error: '\\x' escape needs two hexadecimal digits\n\
         \x20   2 |     var x = '\\x4';\n\
         \x20     |              ^~~"
    );
}
