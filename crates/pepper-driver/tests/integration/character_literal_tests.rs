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

/// The classification methods (`is_digit`, `is_punctuation`, ...) on all 256
/// `byte` and `char` values, checked against Rust's ASCII methods, which
/// match C's ctype.h in the "C" locale (plus `\v` for `isspace`).
#[test]
fn classification_matches_c_ctype() {
    let mut masks = Vec::new();
    let mut uppers = Vec::new();
    let mut lowers = Vec::new();
    let mut digits = Vec::new();
    for b in 0..=255u8 {
        let flags = [
            b.is_ascii_digit(),
            b.is_ascii_hexdigit(),
            b.is_ascii_alphabetic(),
            b.is_ascii_alphanumeric(),
            b.is_ascii_uppercase(),
            b.is_ascii_lowercase(),
            b.is_ascii_whitespace() || b == 0x0B,
            b == b' ' || b == b'\t',
            b.is_ascii_punctuation(),
            b.is_ascii_graphic(),
            b.is_ascii_graphic() || b == b' ',
            b.is_ascii_control(),
            b.is_ascii(),
        ];
        masks.push(flags.iter().enumerate().map(|(i, &f)| (f as u32) << i).sum::<u32>().to_string());
        uppers.push(b.to_ascii_uppercase().to_string());
        lowers.push(b.to_ascii_lowercase().to_string());
        digits.push((b as char).to_digit(36).map_or(-1, |d| d as i32).to_string());
    }
    let source = format!(
        r#"mask(b: byte): int {{
    var flags = [b.is_digit(), b.is_hex_digit(), b.is_alphabetic(), b.is_alphanumeric(),
        b.is_upper(), b.is_lower(), b.is_whitespace(), b.is_blank(), b.is_punctuation(),
        b.is_graphic(), b.is_printable(), b.is_control(), b.is_ascii()];
    var result = 0;
    for (var i in 0..flags.count) {{
        if (flags[i]) {{ result = result | (1 << i); }}
    }}
    return result;
}}
char_mask(c: char): int {{
    var flags = [c.is_digit(), c.is_hex_digit(), c.is_alphabetic(), c.is_alphanumeric(),
        c.is_upper(), c.is_lower(), c.is_whitespace(), c.is_blank(), c.is_punctuation(),
        c.is_graphic(), c.is_printable(), c.is_control(), c.is_ascii()];
    var result = 0;
    for (var i in 0..flags.count) {{
        if (flags[i]) {{ result = result | (1 << i); }}
    }}
    return result;
}}
test(): int {{
    var masks = [{masks}];
    var uppers = [{uppers}];
    var lowers = [{lowers}];
    var digits = [{digits}];
    for (var i in 0..256) {{
        var b = i as byte;
        var c = b as char;
        if (mask(b) != masks[i] or char_mask(c) != masks[i]) {{ return 1000 + i; }}
        if (b.to_upper() != uppers[i] or (c.to_upper() as byte) != uppers[i]) {{ return 2000 + i; }}
        if (b.to_lower() != lowers[i] or (c.to_lower() as byte) != lowers[i]) {{ return 3000 + i; }}
        for (var base in 2..>36) {{
            var expected = digits[i] >= 0 and digits[i] < base ? digits[i] : -1;
            var value = b.digit_value(base);
            var actual = value.is_value() ? value.value() : -1;
            var char_value = c.digit_value(base);
            var char_actual = char_value.is_value() ? char_value.value() : -1;
            if (actual != expected or char_actual != expected) {{ return 4000 + i; }}
        }}
    }}
    if ('7'.digit_value().value() != 7 or 'a'.digit_value().is_value()) {{ return 1; }}
    return 0;
}}"#,
        masks = masks.join(", "),
        uppers = uppers.join(", "),
        lowers = lowers.join(", "),
        digits = digits.join(", "),
    );
    assert_cases(&source);
}
