//! String API edge cases: each snippet is compiled together with the runtime
//! prelude and JIT-executed through the entry function `test`.

use crate::support::compile_jit_with_runtime;

#[test]
fn empty_string() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var e = "";
    if (!e.is_empty) { return -1; }
    if (e.length != 0) { return -2; }
    if (e.size != 0) { return -3; }
    if (!(e == "")) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn negative_indexing_from_end() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "TEST";
    if (!(s[-1] == "T")) { return -1; }
    if (!(s[-4] == "T")) { return -2; }
    if (!(s[-3] == "E")) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn utf8_length_counts_chars_not_bytes() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var u = "aé中";
    if (u.length != 3) { return -1; }
    if (u.size != 6) { return -2; }
    if (!(u[0] == "a")) { return -3; }
    if (!(u[1] == "é")) { return -4; }
    if (!(u[2] == "中")) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn substr_boundaries() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "TEST";
    if (!(s.substr(4, 5) == "")) { return -1; }
    if (!(s.substr(0, 99) == "TEST")) { return -2; }
    if (!(s.substr(1, 2) == "ES")) { return -3; }
    if (!(s.substr(3, 1) == "T")) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn find_and_contains_boundaries() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "TEST";
    if (s.find("TEST") != 0) { return -1; }
    if (s.find("ZZ") != -1) { return -2; }
    if (s.contains("ZZ")) { return -3; }
    if (!s.contains("T")) { return -4; }
    if (s.find("ST") != 2) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn prefix_suffix_boundaries() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "TEST";
    if (!s.starts_with("")) { return -1; }
    if (!s.ends_with("")) { return -2; }
    if (s.starts_with("TESTING")) { return -3; }
    if (s.ends_with("ESTING")) { return -4; }
    if (!s.starts_with("TE")) { return -5; }
    if (!s.ends_with("ST")) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn clone_is_independent() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "TEST";
    var c = s.clone();
    c.append("!");
    if (!(c == "TEST!")) { return -1; }
    if (!(s == "TEST")) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn plus_operator_concatenates() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = "ab";
    var b = "cd";
    var y = a + b;
    if (!(y == "abcd")) { return -1; }
    if (!(a == "ab") || !(b == "cd")) { return -2; }
    var z = "" + "solo";
    if (!(z == "solo")) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn inequality_operator() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "TEST";
    if (!(s != "TESTS")) { return -1; }
    if (!(s != "TETS")) { return -2; }
    if (s != "TEST") { return -3; }
    if (!("a" != "")) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn append_grows_capacity() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "ab";
    if (s.size != 2) { return -1; }
    var i = 0;
    while (i < 64) {
        s += "x";
        i = i + 1;
    }
    if (s.length != 66) { return -2; }
    if (!(s[0] == "a") || !(s[65] == "x")) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn equality_ignores_capacity() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = "hello";
    var b = "";
    b += "he";
    b += "llo";
    if (!(a == b)) { return -1; }
    if (a != b) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn utf8_find_and_substr() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var u = "aé中";
    if (u.find("中") != 3) { return -1; }
    if (!u.contains("é")) { return -2; }
    if (!(u.substr(1, 2) == "é中")) { return -3; }
    if (!(u.substr(0, 1) == "a")) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn byte_access_substr_bytes_and_compare() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "a=b";
    if (!(s.byte_at(1) == '=')) { return -1; }
    var kv = "key=value";
    var eq = kv.find("=") as ulong;
    if (!(kv.substr_bytes(0, eq) == "key")) { return -2; }
    if (!(kv.substr_bytes(eq + 1, kv.size - eq - 1) == "value")) { return -3; }
    if (!(kv.substr_bytes(3, 0) == "")) { return -4; }
    if (!("aé".substr_bytes(1, 2).length == 1)) { return -5; }
    if (!("apple".compare("banana") < 0)) { return -6; }
    if (!("banana".compare("apple") > 0)) { return -7; }
    if (!("ab".compare("abc") < 0)) { return -8; }
    if (!("x".compare("x") == 0)) { return -9; }
    if (!("".compare("") == 0)) { return -10; }
    if (!("a" < "b" && "b" > "a" && "a" <= "a" && "a" >= "a")) { return -11; }
    if (!(!("b" < "a") && !("a" > "b"))) { return -12; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn trim_case_lines_and_repeat() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    if (!("code;  \r\n".trim_end() == "code;")) { return -1; }
    if (!("   ".trim_end() == "")) { return -2; }
    if (!("  x".trim_end() == "  x")) { return -3; }
    var lines = "first\r\nsecond\n\nfourth".lines();
    if (!(lines.count == 4)) { return -4; }
    if (!(lines[0] == "first" && lines[1] == "second" && lines[2] == "" && lines[3] == "fourth")) { return -5; }
    if (!("a\nb\n".lines().count == 2)) { return -6; }
    if (!("".lines().count == 0)) { return -7; }
    if (!("\n".lines().count == 1)) { return -8; }
    if (!("ab".repeat(3) == "ababab")) { return -9; }
    if (!("é".repeat(2).length == 2)) { return -10; }
    if (!("x".repeat(0) == "")) { return -11; }
    if (!("".repeat(5) == "")) { return -12; }
    if (!("  \tcode".trim_start() == "code")) { return -13; }
    if (!(" \t value \r\n".trim() == "value")) { return -14; }
    if (!("   ".trim() == "")) { return -15; }
    if (!("Content-Type 1".lower() == "content-type 1")) { return -16; }
    if (!("get ÄÖ".upper() == "GET ÄÖ")) { return -17; }
    if (!("Ärger".lower() == "Ärger" && "Ärger".lower().length == 5)) { return -18; }
    if (!("".upper() == "")) { return -19; }
    var data = "hé".bytes();
    if (!(data.count == 3 && data[0] == 104 && data[1] == 195 && data[2] == 169)) { return -20; }
    if (!(String._from_bytes(data) == "hé" && String._from_bytes(data).length == 2)) { return -21; }
    data.append(255);
    data.append(105);
    if (!(String._from_bytes(data) == "hé\u{FFFD}i" && String._from_bytes(data).length == 4)) { return -22; }
    var cut = Array<u8>();
    cut.append(226);
    cut.append(130);
    if (!(String._from_bytes(cut) == "\u{FFFD}\u{FFFD}")) { return -23; }
    var surrogate = Array<u8>();
    surrogate.append(237);
    surrogate.append(160);
    surrogate.append(128);
    if (!(String._from_bytes(surrogate).length == 3)) { return -24; }
    if (!(String._from_bytes(Array<u8>()) == "")) { return -25; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn integer_to_string() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    if (!(to_string(-42) == "-42")) { return -1; }
    if (!(to_string(0) == "0")) { return -2; }
    int line = 3;
    if (!(to_string(line) == "3")) { return -3; }
    ulong big = 0xFFFFFFFFFFFFFFFF;
    if (!(to_string(big) == "18446744073709551615")) { return -4; }
    long small = -9223372036854775807 - 1;
    if (!(to_string(small) == "-9223372036854775808")) { return -5; }
    byte b = 200;
    if (!(to_string(b) == "200")) { return -6; }
    uint u = 7;
    if (!(to_string(u) == "7")) { return -7; }
    short s = -5;
    if (!(to_string(s) == "-5")) { return -8; }
    ushort us = 5;
    if (!(to_string(us) == "5")) { return -9; }
    char c = -1;
    if (!(to_string(c) == "-1")) { return -10; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn string_builder() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var out = StringBuilder();
    if (!(out.is_empty && out.to_string() == "")) { return -1; }
    out.append("line ").append(to_string(3)).append("\n");
    if (!(out.to_string() == "line 3\n")) { return -2; }
    if (!(out.length == 7 && out.size == 7)) { return -3; }
    var many = StringBuilder(4);
    var i = 0;
    while (i < 1000) {
        many.append("é");
        i = i + 1;
    }
    var t = many.to_string();
    if (!(t.length == 1000 && t.size == 2000)) { return -4; }
    many.clear();
    if (!(many.is_empty && many.to_string() == "")) { return -5; }
    many.append("again");
    if (!(many.to_string() == "again")) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn text_utf8_reads_and_appends_code_points() {
    assert_eq!(compile_jit_with_runtime(r#"
import text;

test(): int {
    var s = "aé€𝄞";
    if (!text.Utf8.find_invalid(s).is_empty()) { return -1; }
    var bytes = Array<u8>();
    bytes.append(104);
    bytes.append(105);
    bytes.append(192);
    var raw = String(unsafe_cast<__ptr<char>>(bytes._data), 3);
    if (text.Utf8.find_invalid(raw).value() != 2) { return -2; }
    var (a, a_run) = text.Utf8.code_point_at(s, 0);
    if (a != 97 or a_run != 1) { return -3; }
    var (e, e_run) = text.Utf8.code_point_at(s, 1);
    if (e != 233 or e_run != 2) { return -4; }
    var (euro, euro_run) = text.Utf8.code_point_at(s, 3);
    if (euro != 8364 or euro_run != 3) { return -5; }
    var (clef, clef_run) = text.Utf8.code_point_at(s, 6);
    if (clef != 119070 or clef_run != 4) { return -6; }
    var out = Array<u8>();
    text.Utf8.append_code_point(out, 97);
    text.Utf8.append_code_point(out, 233);
    text.Utf8.append_code_point(out, 8364);
    text.Utf8.append_code_point(out, 119070);
    if (text.Utf8.decode(out).value() != s) { return -7; }
    return 0;
}
"#), 0);
}

#[test]
fn text_module_encodes_and_decodes() {
    assert_eq!(compile_jit_with_runtime(r#"
import text;

test(): int {
    var s = "héllo €𝄞";
    var b = text.Utf8.encode(s);
    if (!(text.Utf8.decode(b).value() == s)) { return -1; }
    var bad = Array<u8>();
    bad.append(104);
    bad.append(255);
    if (!(text.Utf8.decode(bad).is_empty())) { return -2; }
    if (!(text.Utf8.decode_lossy(bad) == "h\u{FFFD}")) { return -3; }
    var le = text.Utf16.encode(s);
    if (!(le.count == 18)) { return -4; }
    if (!(text.Utf16.decode(le).value() == s)) { return -5; }
    var be = text.Utf16.encode(s, true);
    if (!(be[0] == 0 && be[1] == 104)) { return -6; }
    if (!(text.Utf16.decode(be, true).value() == s)) { return -7; }
    var lone = Array<u8>();
    lone.append(0);
    lone.append(216);
    if (!(text.Utf16.decode(lone).is_empty())) { return -8; }
    if (!(text.Utf16.decode_lossy(lone) == "\u{FFFD}")) { return -9; }
    if (!(text.Ascii.encode("ok").value().count == 2)) { return -10; }
    if (!(text.Ascii.encode(s).is_empty())) { return -11; }
    var q = text.Ascii.encode_lossy("aé€");
    if (!(q.count == 3 && q[1] == 63)) { return -12; }
    if (!(text.Ascii.decode(bad).is_empty())) { return -13; }
    if (!(text.Ascii.decode_lossy(bad) == "h\u{FFFD}")) { return -14; }
    var before = _pep_live_allocs();
    {
        var x = text.Utf16.decode_lossy(text.Utf16.encode(s));
        var y = text.Ascii.encode_lossy(x);
    }
    if (!(_pep_live_allocs() == before)) { return -15; }
    return 0;
}
"#), 0);
}

#[test]
fn find_from_rfind_split_join_replace() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var before = _pep_live_allocs();
    {
        if ("a,b,c".find(",", 2) != 3) { return -1; }
        if ("a,b,c".find(",", 4) != -1) { return -2; }
        if ("a,b,c".find(",", 99) != -1) { return -3; }
        if ("héllo".find("l", 1) != 3) { return -4; }
        if ("a/b/c".rfind("/") != 3) { return -5; }
        if ("abc".rfind("x") != -1) { return -6; }
        if ("abc".rfind("") != 3) { return -7; }
        if ("abcabc".rfind("abc") != 3) { return -8; }
        var parts = "a,b,,c".split(",");
        if (parts.count != 4 || !(parts[2] == "") || !(parts[3] == "c")) { return -9; }
        if ("".split(",").count != 1) { return -10; }
        if (",a,".split(",").count != 3) { return -11; }
        if ("a--b".split("--").count != 2) { return -12; }
        var once = "Host: x: y".split_once(": ");
        if (!once.is_value()) { return -13; }
        var (name, value) = once.value();
        if (!(name == "Host") || !(value == "x: y")) { return -14; }
        if ("abc".split_once(":").is_value()) { return -15; }
        if (!(", ".join(parts) == "a, b, , c")) { return -16; }
        if (!(", ".join(Array<String>()) == "")) { return -17; }
        if (!("aaa".replace("aa", "b") == "ba")) { return -18; }
        if (!("a\r\nb\r\n".replace("\r\n", "\n") == "a\nb\n")) { return -19; }
        if (!("héllo wörld".replace("ö", "o") == "héllo world")) { return -20; }
        if (!("abc".replace("x", "y") == "abc")) { return -21; }
    }
    if (_pep_live_allocs() != before) { return -22; }
    return 0;
}"#
        ),
        0
    );
}

// #511: `find` re-checked that the whole rest of the String was valid UTF-8
// on every call, so `split`, `replace` and a `find(_, from)` loop were
// quadratic (20 s for these three over 100 KB). Linear, they take
// milliseconds; quadratic, this 240 KB text takes about two minutes.
#[test]
fn find_split_replace_are_linear() {
    let started = std::time::Instant::now();
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var text = "wörd,".repeat(40000);
    if (text.split(",").count != 40001) { return -1; }
    if (text.replace(",", ";").size != text.size) { return -2; }
    ulong found = 0;
    var at = text.find(",");
    while (at >= 0) {
        found = found + 1;
        at = text.find(",", (at as ulong) + 1);
    }
    if (found != 40000) { return -3; }
    return 0;
}"#
        ),
        0
    );
    let elapsed = started.elapsed();
    assert!(
        elapsed < std::time::Duration::from_secs(20),
        "split, replace and find over 240 KB took {elapsed:?}: quadratic again?"
    );
}

#[test]
fn long_parse() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    if (long.parse("-42").value() != -42) { return -1; }
    if (long.parse("+7").value() != 7) { return -2; }
    if (long.parse("ff", 16).value() != 255) { return -3; }
    if (long.parse("FF", 16).value() != 255) { return -4; }
    if (long.parse("101", 2).value() != 5) { return -5; }
    if (long.parse("z", 36).value() != 35) { return -6; }
    if (long.parse("12x").is_value()) { return -7; }
    if (long.parse("").is_value()) { return -8; }
    if (long.parse("-").is_value()) { return -9; }
    if (long.parse(" 1").is_value()) { return -10; }
    if (long.parse("2", 2).is_value()) { return -11; }
    if (long.parse("9223372036854775807").value() != 9223372036854775807) { return -12; }
    if (long.parse("9223372036854775808").is_value()) { return -13; }
    if (long.parse("-9223372036854775808").value() != -9223372036854775807 - 1) { return -14; }
    if (long.parse("-9223372036854775809").is_value()) { return -15; }
    if (long.parse("99999999999999999999999").is_value()) { return -16; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn math_parse_int_is_deprecated_but_still_parses() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import math;

test(): int {
    if (math.parse_int("ff", 16).value() != 255) { return -1; }
    if (math.parse_int("12x").is_value()) { return -2; }
    return 0;
}"#
        ),
        0
    );
}
