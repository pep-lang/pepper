//! Optional<T> semantics: every method against a POD `T` and a struct `T`,
//! the None panic, and reference counts of a struct value held by an
//! optional. Each test returns 0 on success or a distinct negative code per
//! check.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::process::Command;

/// Compile and JIT `test()`; assert it left no allocation behind and return
/// its result.
fn run(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs =
        unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs") };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    assert_eq!(after - before, 0, "allocations leaked or double-released");
    result
}

#[test]
fn some_and_none_pod() {
    assert_eq!(
        run(r#"
test(): int {
    var a = Optional<int>.some(42);
    if (!a.is_some() || a.is_none()) { return -1; }
    if (a.value() != 42) { return -2; }
    if (a.value_or(7) != 42) { return -3; }
    var b = Optional<int>.none();
    if (b.is_some() || !b.is_none()) { return -4; }
    if (b.value_or(7) != 7) { return -5; }
    var c = Optional<int>.None;
    if (!c.is_none()) { return -6; }
    return 0;
}"#),
        0
    );
}

#[test]
fn some_of_a_zero_value_is_still_some() {
    assert_eq!(
        run(r#"
test(): int {
    var a = Optional<int>.some(0);
    if (!a.is_some()) { return -1; }
    var b = Optional<bool>.some(false);
    if (!b.is_some() || b.value()) { return -2; }
    return 0;
}"#),
        0
    );
}

#[test]
fn struct_value_and_fallback() {
    assert_eq!(
        run(r#"
struct Point {
    int x;
    construct(int v) { this.x = v; }
}
test(): int {
    var a = Optional<Point>.some(Point(7));
    if (a.value().x != 7) { return -1; }
    var b = Optional<Point>.none();
    if (b.value_or(Point(3)).x != 3) { return -2; }
    if (a.value_or(Point(3)).x != 7) { return -3; }
    return 0;
}"#),
        0
    );
}

#[test]
fn returned_from_a_function() {
    assert_eq!(
        run(r#"
first_negative(values: Array<int>): Optional<int> {
    for (var v in values) {
        if (v < 0) { return Optional<int>.some(v); }
    }
    return Optional<int>.none();
}
test(): int {
    var values = Array<int>();
    values.append(1);
    if (first_negative(values).is_some()) { return -1; }
    values.append(-5);
    if (first_negative(values).value() != -5) { return -2; }
    return 0;
}"#),
        0
    );
}

#[test]
fn held_struct_is_released_with_the_optional() {
    assert_eq!(
        run(r#"
struct Tracker {
    construct() {}
}
test(): int {
    var t = Tracker();
    {
        var a = Optional<Tracker>.some(t);
        if (__refcount<Tracker>(t) != 2) { return -1; }
        var copy = a.value();
        if (__refcount<Tracker>(t) != 3) { return -2; }
    }
    if (__refcount<Tracker>(t) != 1) { return -3; }
    return 0;
}"#),
        0
    );
}

#[test]
fn value_of_none_panics() {
    let dir = std::env::temp_dir().join(format!("pepper_optional_none_panics_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("main.pep");
    std::fs::write(&src, "main(): int {\n    var a = Optional<int>.none();\n    return a.value();\n}\n").unwrap();
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src.to_string_lossy().into_owned(),
        "-o".to_string(),
        exe.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    pepper_driver::run(options).expect("compile + link");
    let output = Command::new(&exe).output().expect("spawn");
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    assert!(!output.status.success(), "expected a panic; stdout: {stdout:?}");
    assert!(stdout.contains("Optional.value on a None value"), "stdout: {stdout:?}");
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn question_mark_shorthand() {
    assert_eq!(
        run(r#"
struct Token {
    String text;
    construct(String text) { this.text = text; }
}
first_even(values: Array<int>): int? {
    for (var v in values) {
        if (v % 2 == 0) { return Optional<int>.some(v); }
    }
    return Optional<int>.none();
}
text_of(t: Token?): String {
    return t.value_or(Token("none")).text;
}
test(): int {
    var values = Array<int>();
    values.append(3);
    if (first_even(values).is_some()) { return -1; }
    values.append(8);
    if (first_even(values).value() != 8) { return -2; }
    if (text_of(Optional<Token>.none()) != "none") { return -3; }
    Token? t = Optional<Token>.some(Token("x"));
    if (text_of(t) != "x") { return -4; }
    var all = Array<int?>();
    all.append(Optional<int>.none());
    if (!all[0].is_none()) { return -5; }
    var x = 3;
    var y = x > 2 ? 10 : 20;
    if (y != 10) { return -6; }
    return 0;
}"#),
        0
    );
}

#[test]
fn optional_slots_start_as_none() {
    assert_eq!(
        run(r#"
struct Token {
    construct() {}
}
struct Node {
    Token? leaf;
    Optional<int> count;
    construct() {}
}
test(): int {
    var n = Node();
    if (!n.leaf.is_none()) { return -1; }
    if (!n.count.is_none()) { return -2; }
    var local: int?;
    if (!local.is_none()) { return -3; }
    Token? c_style;
    if (!c_style.is_none()) { return -4; }
    n.leaf = Optional<Token>.some(Token());
    if (!n.leaf.is_some()) { return -5; }
    return 0;
}"#),
        0
    );
}

#[test]
fn optional_is_an_enum_with_none_and_some_cases() {
    assert_eq!(
        run(r#"
describe(o: String?): int {
    return match (o) {
        None => 0,
        Some(text) => text.length as int,
    };
}

test(): int {
    var some = Optional<String>.Some("four");
    if (describe(some) != 4) { return -1; }
    if (describe(Optional<String>.None) != 0) { return -2; }
    if (some is Some(text)) {
        if (text != "four") { return -3; }
    } else {
        return -3;
    }
    if (some != Optional<String>.some("four")) { return -4; }
    if (some == Optional<String>.none()) { return -5; }
    String? unset;
    if (unset != Optional<String>.None) { return -6; }
    return 0;
}"#),
        0
    );
}
