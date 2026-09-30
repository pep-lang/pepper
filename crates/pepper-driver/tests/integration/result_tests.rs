//! Result<TValue, TError> semantics: every method is exercised against a POD
//! `TValue` and a struct `TValue`, with the default `TError=Error` and a
//! custom error type. Each test returns 0 on success or a distinct negative
//! code per check, so a failure pinpoints the exact broken invariant without
//! hand-tracing IR.

use pepper_codegen::CodeGenerator;
use pepper_sema::model::Module as SemaModule;

/// Build the full module (runtime prelude + test source) and run sema.
fn build_module(source: &str) -> SemaModule {
    pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile")
}

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = build_module(source);
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

// ── ok / err construction ────────────────────────────────────────────────────

#[test]
fn ok_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var r = Result<int>.ok(42);
    if (!r.is_ok()) { return -1; }
    if (r.value() != 42) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn err_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var r = Result<int>.err(Error("boom"));
    if (r.is_ok()) { return -1; }
    if (!r.is_err()) { return -2; }
    if (r.error().message.length() != 4) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn ok_struct_value() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    construct(int v) { this.x = v; }
}
test(): int {
    var r = Result<Point>.ok(Point(7));
    if (!r.is_ok()) { return -1; }
    if (r.value().x != 7) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

// ── default TError ───────────────────────────────────────────────────────────

#[test]
fn default_terror() {
    // `Result<int>` must fill `TError` from the parameter default.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Result<int>.ok(1);
    var b = Result<int>.err(Error("e"));
    if (!a.is_ok() || b.is_ok()) { return -1; }
    if (b.error().message.length() != 1) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn explicit_terror_matches_default() {
    // `Result<int, Error>` is the same specialization shape as `Result<int>`.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Result<int>.ok(1);
    var b = Result<int, Error>.err(Error("x"));
    if (!a.is_ok() || !b.is_err()) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

// ── custom TError ────────────────────────────────────────────────────────────

#[test]
fn custom_terror() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Code {
    int value;
    construct(int v) { this.value = v; }
}
test(): int {
    var r = Result<int, Code>.err(Code(500));
    if (r.is_ok()) { return -1; }
    if (r.error().value != 500) { return -2; }
    var ok = Result<int, Code>.ok(3);
    if (!ok.is_ok() || ok.value() != 3) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

// ── ok_or / default ctor ─────────────────────────────────────────────────────

#[test]
fn ok_or_fallback() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var ok = Result<int>.ok(5);
    var err = Result<int>.err(Error("e"));
    if (ok.ok_or(-1) != 5) { return -1; }
    if (err.ok_or(-1) != -1) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn match_on_result() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
parse(text: String): Result<int> {
    if (text == "42") { return Result<int>.Ok(42); }
    return Result<int>.Err(Error("not a number"));
}

test(): int {
    var n = match (parse("42")) { Ok(v) => v, Err(e) => -1 };
    if (n != 42) { return -1; }
    match (parse("x")) {
        Ok(v) => { return -2; }
        Err(e) => { if (e.message != "not a number") { return -3; } }
    }
    if (!(parse("42") is Ok)) { return -4; }
    if (parse("x") is Err(e)) {
        if (e.message.length() != 12) { return -5; }
    } else {
        return -6;
    }
    var text = match (Result<String>.ok("s")) { Ok(s) => s, Err(e) => e.message };
    if (text != "s") { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn void_result_ok_carries_nothing() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
check(n: int): Result<void> {
    if (n < 0) { return Result<void>.Err(Error("negative")); }
    return Result<void>.Ok;
}

test(): int {
    match (check(1)) {
        Ok => {}
        Err(e) => { return -1; }
    }
    check(1).value();
    if (check(-1) is Ok) { return -2; }
    if (check(-1).error().message != "negative") { return -3; }
    return 0;
}"#
        ),
        0
    );
}

// ── refcount: struct TValue must not leak or double-free ─────────────────────

#[test]
fn struct_value_refcount_balanced() {
    // A struct `TValue` flows through ok/unwrap into a second reference; when
    // both references leave scope the live-alloc counter must be back to
    // baseline (no leak, no double free).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    construct(int v) { this.x = v; }
}
test(): int {
    var before = _pep_live_allocs();
    {
        var r = Result<Point>.ok(Point(7));
        var p = r.value();
        if (p.x != 7) { return -1; }
    }
    var after = _pep_live_allocs();
    if (after != before) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

// ── Result<void>: a result with nothing to return ───────────────────────────

#[test]
fn void_value() {
    // Ok and Err of Result<void>, and a function returning one; `ok()`
    // takes no argument, `value()` only checks, and every result is released
    // (live-alloc counter back to baseline).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
check(bool good): Result<void> {
    if (good) {
        return Result<void>.ok();
    }
    return Result<void>.err(Error("bad"));
}
test(): int {
    var before = _pep_live_allocs();
    {
        var ok = check(true);
        if (!ok.is_ok()) { return -1; }
        ok.value();
        var err = check(false);
        if (!err.is_err()) { return -2; }
        if (err.error().message.length() != 3) { return -3; }
    }
    var after = _pep_live_allocs();
    if (after != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}
