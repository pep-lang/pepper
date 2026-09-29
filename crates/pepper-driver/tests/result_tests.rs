//! Result<TValue, TError> semantics: every method is exercised against a POD
//! `TValue` and a struct `TValue`, with the default `TError=Error` and a
//! custom error type. Each test returns 0 on success or a distinct negative
//! code per check, so a failure pinpoints the exact broken invariant without
//! hand-tracing IR.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

/// `_pep_live_allocs()` is a process-wide counter, so leak-census tests must
/// not run concurrently with each other; serialize on this lock.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Build the full module (runtime prelude + test source) and run sema.
fn build_module(source: &str) -> SemaModule {
    let mut module = SemaModule::default();
    let (runtime_sources, _libs, _dirs) = pepper_driver::runtime::discover();
    assert!(!runtime_sources.is_empty(), "runtime prelude not discovered");
    for path in runtime_sources {
        let content = std::fs::read_to_string(&path).expect("read runtime source");
        let ast = pepper_parser::parser::parse_source(&path.to_string_lossy(), &content)
            .expect("parse runtime source");
        module.merge(build(&ast).expect("build"));
    }
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    pepper_driver::compiler::check_with_runtime("test.pep", source).expect("visibility");
    module.merge(build(&ast).expect("build"));
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module);
    module
}

fn compile_jit_with_runtime(source: &str) -> i32 {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
    if (r.unwrap() != 42) { return -2; }
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
    if (r.Error.Message.length() != 4) { return -3; }
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
    new(int v) { this.x = v; }
}
test(): int {
    var r = Result<Point>.ok(Point(7));
    if (!r.is_ok()) { return -1; }
    if (r.unwrap().x != 7) { return -2; }
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
    if (b.Error.Message.length() != 1) { return -2; }
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
    int Value;
    new(int v) { this.Value = v; }
}
test(): int {
    var r = Result<int, Code>.err(Code(500));
    if (r.is_ok()) { return -1; }
    if (r.Error.Value != 500) { return -2; }
    var ok = Result<int, Code>.ok(3);
    if (!ok.is_ok() || ok.unwrap() != 3) { return -3; }
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
fn default_ctor_is_err() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var r = Result<int>();
    if (r.is_ok()) { return -1; }
    if (!r.is_err()) { return -2; }
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
    new(int v) { this.x = v; }
}
test(): int {
    var before = _pep_live_allocs();
    {
        var r = Result<Point>.ok(Point(7));
        var p = r.unwrap();
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

// ── None: the value type of a result with nothing to return ─────────────────

#[test]
fn none_value() {
    // Ok and Err of Result<None>, and a function returning one; the None
    // instances must be released (live-alloc counter back to baseline).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
check(bool good): Result<None> {
    if (good) {
        return Result<None>.ok(None());
    }
    return Result<None>.err(Error("bad"));
}
test(): int {
    var before = _pep_live_allocs();
    {
        var ok = check(true);
        if (!ok.is_ok()) { return -1; }
        var n = ok.unwrap();
        var err = check(false);
        if (!err.is_err()) { return -2; }
        if (err.Error.Message.length() != 3) { return -3; }
    }
    var after = _pep_live_allocs();
    if (after != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}
