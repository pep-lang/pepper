//! String API edge cases: each snippet is compiled together with the runtime
//! prelude and JIT-executed through the entry function `test`.

use pepper_codegen::CodeGenerator;

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn empty_string() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var e = "";
    if (!e.empty()) { return -1; }
    if (e.length() != 0) { return -2; }
    if (e.size() != 0) { return -3; }
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
    if (u.length() != 3) { return -1; }
    if (u.size() != 6) { return -2; }
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
fn compound_append_from_empty() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var x = "";
    x += "ab";
    x += "cd";
    if (!(x == "abcd")) { return -1; }
    if (x.length() != 4) { return -2; }
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
    if (s.size() != 2) { return -1; }
    var i = 0;
    while (i < 64) {
        s += "x";
        i = i + 1;
    }
    if (s.length() != 66) { return -2; }
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
