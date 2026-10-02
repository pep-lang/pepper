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

// ── default TError ───────────────────────────────────────────────────────────

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
        if (e.message.length != 12) { return -5; }
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
        if (err.error().message.length != 3) { return -3; }
    }
    var after = _pep_live_allocs();
    if (after != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

/// A `void` type argument keeps a call stored into the field it removes
/// (`this.value = body()` runs `body()`), and drops the removed field where
/// it is passed on (`Result<T>.ok(this.value)` becomes `ok()`).
#[test]
fn a_void_instance_keeps_the_call_it_stores_and_passes_nothing_on() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Cell<T> {
    var value: T;
    var runs: int;
    construct() {}
    run(body: () => T) {
        this.value = body();
    }
    result(): Result<T> {
        return Result<T>.ok(this.value);
    }
}

test(): int {
    var counter = Cell<int>();
    var c = Cell<void>();
    c.run(() => { counter.runs = counter.runs + 1; });
    if (!c.result().is_ok()) { return 1; }
    var d = Cell<int>();
    d.run(() => { return 41; });
    return d.result().value() + counter.runs;
}
"#
        ),
        42
    );
}
