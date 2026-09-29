//! Atomic<T> semantics: every operation is exercised against a POD type and
//! (where meaningful) a struct type. Each test returns 0 on success or a
//! distinct negative code per check, so a failure pinpoints the exact broken
//! invariant without hand-tracing IR.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

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
    transform_pass(&mut module).expect("sema");
    module
}

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = build_module(source);
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

const POINT: &str = r#"
struct Point {
    int x;
    new(this.x = 0) {}
}
"#;

// ── load / store ─────────────────────────────────────────────────────────────

#[test]
fn load_store_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Atomic<int>(41);
    if (a.load() != 41) { return -1; }
    a.store(99);
    if (a.load() != 99) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn load_store_long() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Atomic<long>(1234567890123);
    if (a.load() != 1234567890123) { return -1; }
    a.store(42);
    if (a.load() != 42) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn load_store_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Atomic<Point>();
    var p = Point();
    p.x = 7;
    a.store(p);
    var q = a.load();
    if (q.x != 7) {{ return -1; }}
    # Slot holds the ref, and load() returned an owned copy: p + slot + q.
    if (__refcount<Point>(p) != 3) {{ return -2; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

#[test]
fn load_store_double() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Atomic<double>(1.5);
    if (a.load() != 1.5) { return -1; }
    a.store(2.25);
    if (a.load() != 2.25) { return -2; }
    var b = Atomic<double>(3.0);
    if (!b.compare_exchange(3.0, 4.0)) { return -3; }
    if (b.load() != 4.0) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn store_replaces_struct_ref() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Atomic<Point>();
    var p1 = Point();
    p1.x = 1;
    a.store(p1);
    if (__refcount<Point>(p1) != 2) {{ return -1; }}
    var p2 = Point();
    p2.x = 2;
    a.store(p2);
    # Slot dropped p1's ref and took p2's.
    if (__refcount<Point>(p1) != 1) {{ return -2; }}
    if (__refcount<Point>(p2) != 2) {{ return -3; }}
    if (a.load().x != 2) {{ return -4; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── compare_exchange ─────────────────────────────────────────────────────────

#[test]
fn cmpxchg_success_and_failure_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Atomic<int>(10);
    if (!a.compare_exchange(10, 20)) { return -1; }
    if (a.load() != 20) { return -2; }
    # Failure: expected does not match the slot.
    if (a.compare_exchange(10, 30)) { return -3; }
    if (a.load() != 20) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn cmpxchg_struct_refcount() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Atomic<Point>();
    var p1 = Point();
    p1.x = 1;
    a.store(p1);
    if (__refcount<Point>(p1) != 2) {{ return -1; }}
    var p2 = Point();
    p2.x = 2;
    # Success: slot takes p2, drops p1.
    if (!a.compare_exchange(p1, p2)) {{ return -2; }}
    if (__refcount<Point>(p1) != 1) {{ return -3; }}
    if (__refcount<Point>(p2) != 2) {{ return -4; }}
    # Failure: expected no longer matches (slot holds p2).
    var p3 = Point();
    p3.x = 3;
    if (a.compare_exchange(p1, p3)) {{ return -5; }}
    if (__refcount<Point>(p3) != 1) {{ return -6; }}
    if (a.load().x != 2) {{ return -7; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── exchange ─────────────────────────────────────────────────────────────────

#[test]
fn exchange_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Atomic<int>(5);
    var old = a.exchange(8);
    if (old != 5) { return -1; }
    if (a.load() != 8) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn exchange_struct_refcount() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Atomic<Point>();
    var p1 = Point();
    p1.x = 1;
    a.store(p1);
    var p2 = Point();
    p2.x = 2;
    var old = a.exchange(p2);
    if (old.x != 1) {{ return -1; }}
    # The returned old ref is owned by the caller: it must not be released.
    if (__refcount<Point>(p1) != 2) {{ return -2; }}
    if (__refcount<Point>(p2) != 2) {{ return -3; }}
    if (a.load().x != 2) {{ return -4; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── fetch_* ──────────────────────────────────────────────────────────────────

#[test]
fn fetch_ops_int() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Atomic<int>(10);
    if (a.fetch_add(5) != 10 || a.load() != 15) { return -1; }
    if (a.fetch_sub(3) != 15 || a.load() != 12) { return -2; }
    if (a.fetch_and(12) != 12 || a.load() != 12) { return -3; }
    if (a.fetch_or(5) != 12 || a.load() != 13) { return -4; }
    if (a.fetch_xor(13) != 13 || a.load() != 0) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn fetch_ops_long() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Atomic<long>(100);
    if (a.fetch_add(50) != 100 || a.load() != 150) { return -1; }
    if (a.fetch_sub(30) != 150 || a.load() != 120) { return -2; }
    if (a.fetch_and(128) != 120 || a.load() != 0) { return -3; }
    if (a.fetch_or(7) != 0 || a.load() != 7) { return -4; }
    if (a.fetch_xor(127) != 7 || a.load() != 120) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

// ── is_lock_free ─────────────────────────────────────────────────────────────

#[test]
fn is_lock_free() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    if (!Atomic<int>(0).is_lock_free()) {{ return -1; }}
    if (!Atomic<long>(0).is_lock_free()) {{ return -2; }}
    if (!Atomic<Point>().is_lock_free()) {{ return -3; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── multi-threaded contention ────────────────────────────────────────────────

#[test]
fn fetch_add_contention() {
    const THREADS: i32 = 4;
    const STEPS: i64 = 50_000;
    let mut module = build_module(
        r#"
var counter = Atomic<long>(0);
test(): int { return 0; }

add_one(): long {
    return counter.fetch_add(1) + 1;
}

read_counter(): long {
    return counter.load();
}"#
    );
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    // The engine borrows the generator's context: keep both alive until every
    // thread has joined, then they drop in order at scope exit.
    let ee = generator.jit_engine(&mut module).expect("jit");
    let add_one = unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>("add_one").expect("add_one").as_raw() };
    let mut handles = Vec::new();
    for _ in 0..THREADS {
        handles.push(std::thread::spawn(move || {
            let mut sum: i64 = 0;
            for _ in 0..STEPS {
                sum += unsafe { add_one() };
            }
            sum
        }));
    }
    let total: i64 = handles.into_iter().map(|h| h.join().unwrap()).sum();
    let read_counter = unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>("read_counter").expect("read_counter").as_raw() };
    let n = THREADS as i64 * STEPS;
    let final_count = unsafe { read_counter() };
    // fetch_add returns the previous value: across all threads the returned
    // old values are exactly 0..n-1 (each once) iff no update was lost, so
    // the total is exact.
    assert_eq!(final_count, n);
    assert_eq!(total, n * (n - 1) / 2 + n);
}

#[test]
fn cas_contention() {
    const THREADS: i32 = 4;
    const STEPS: i64 = 25_000;
    let mut module = build_module(
        r#"
var counter = Atomic<long>(0);

# CAS-retry increment: each call wins exactly one step of the counter.
try_inc(): int {
    var cur = counter.load();
    while (true) {
        if (counter.compare_exchange(cur, cur + 1)) { return 1; }
        cur = counter.load();
    }
}

read_counter(): long {
    return counter.load();
}"#
    );
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let try_inc = unsafe { ee.get_function::<unsafe extern "C" fn() -> i32>("try_inc").expect("try_inc").as_raw() };
    let mut handles = Vec::new();
    for _ in 0..THREADS {
        handles.push(std::thread::spawn(move || {
            let mut wins: i64 = 0;
            for _ in 0..STEPS {
                wins += unsafe { try_inc() } as i64;
            }
            wins
        }));
    }
    let total_wins: i64 = handles.into_iter().map(|h| h.join().unwrap()).sum();
    let read_counter = unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>("read_counter").expect("read_counter").as_raw() };
    let final_count = unsafe { read_counter() };
    // Every call wins exactly one step, and the counter advances by exactly
    // one per win: any lost or duplicated update breaks final == wins.
    assert_eq!(total_wins, THREADS as i64 * STEPS);
    assert_eq!(final_count, THREADS as i64 * STEPS);
}
