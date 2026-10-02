//! Atomic<T> semantics: every operation is exercised against a POD type and
//! (where meaningful) a struct type. Each check function returns 0 on
//! success or a distinct negative code per check, so a failure pinpoints the
//! exact broken invariant without hand-tracing IR. The checks share one
//! program, since each compile pays for `import async`.

use pepper_codegen::CodeGenerator;

use crate::support;

const PROGRAM: &str = r#"
import async;

# Atomic<T> needs a thread-safe struct T: `[Shared]`, with const fields.
[Shared]
struct Point {
    const x: int;
    construct(this.x = 0) {}
}

# ── load / store ────────────────────────────────────────────────────────────

load_store_pod(): int {
    var a = async.Atomic<int>(41);
    if (a.load() != 41) { return -1; }
    a.store(99);
    if (a.load() != 99) { return -2; }
    return 0;
}

load_store_long(): int {
    var a = async.Atomic<long>(1234567890123);
    if (a.load() != 1234567890123) { return -1; }
    a.store(42);
    if (a.load() != 42) { return -2; }
    return 0;
}

load_store_struct(): int {
    var a = async.Atomic<Point>();
    var p = Point(7);
    a.store(p);
    var q = a.load();
    if (q.x != 7) { return -1; }
    # Slot holds the ref, and load() returned an owned copy: p + slot + q.
    if (__refcount<Point>(p) != 3) { return -2; }
    return 0;
}

load_store_double(): int {
    var a = async.Atomic<double>(1.5);
    if (a.load() != 1.5) { return -1; }
    a.store(2.25);
    if (a.load() != 2.25) { return -2; }
    var b = async.Atomic<double>(3.0);
    if (!b.compare_exchange(3.0, 4.0)) { return -3; }
    if (b.load() != 4.0) { return -4; }
    return 0;
}

store_replaces_struct_ref(): int {
    var a = async.Atomic<Point>();
    var p1 = Point(1);
    a.store(p1);
    if (__refcount<Point>(p1) != 2) { return -1; }
    var p2 = Point(2);
    a.store(p2);
    # Slot dropped p1's ref and took p2's.
    if (__refcount<Point>(p1) != 1) { return -2; }
    if (__refcount<Point>(p2) != 2) { return -3; }
    if (a.load().x != 2) { return -4; }
    return 0;
}

# ── compare_exchange ────────────────────────────────────────────────────────

cmpxchg_success_and_failure_pod(): int {
    var a = async.Atomic<int>(10);
    if (!a.compare_exchange(10, 20)) { return -1; }
    if (a.load() != 20) { return -2; }
    # Failure: expected does not match the slot.
    if (a.compare_exchange(10, 30)) { return -3; }
    if (a.load() != 20) { return -4; }
    return 0;
}

cmpxchg_struct_refcount(): int {
    var a = async.Atomic<Point>();
    var p1 = Point(1);
    a.store(p1);
    if (__refcount<Point>(p1) != 2) { return -1; }
    var p2 = Point(2);
    # Success: slot takes p2, drops p1.
    if (!a.compare_exchange(p1, p2)) { return -2; }
    if (__refcount<Point>(p1) != 1) { return -3; }
    if (__refcount<Point>(p2) != 2) { return -4; }
    # Failure: expected no longer matches (slot holds p2).
    var p3 = Point(3);
    if (a.compare_exchange(p1, p3)) { return -5; }
    if (__refcount<Point>(p3) != 1) { return -6; }
    if (a.load().x != 2) { return -7; }
    return 0;
}

# ── exchange ────────────────────────────────────────────────────────────────

exchange_pod(): int {
    var a = async.Atomic<int>(5);
    var old = a.exchange(8);
    if (old != 5) { return -1; }
    if (a.load() != 8) { return -2; }
    return 0;
}

exchange_struct_refcount(): int {
    var a = async.Atomic<Point>();
    var p1 = Point(1);
    a.store(p1);
    var p2 = Point(2);
    var old = a.exchange(p2);
    if (old.x != 1) { return -1; }
    # The returned old ref is owned by the caller: it must not be released.
    if (__refcount<Point>(p1) != 2) { return -2; }
    if (__refcount<Point>(p2) != 2) { return -3; }
    if (a.load().x != 2) { return -4; }
    return 0;
}

# ── fetch_* ─────────────────────────────────────────────────────────────────

fetch_ops_int(): int {
    var a = async.Atomic<int>(10);
    if (a.fetch_add(5) != 10 || a.load() != 15) { return -1; }
    if (a.fetch_sub(3) != 15 || a.load() != 12) { return -2; }
    if (a.fetch_and(12) != 12 || a.load() != 12) { return -3; }
    if (a.fetch_or(5) != 12 || a.load() != 13) { return -4; }
    if (a.fetch_xor(13) != 13 || a.load() != 0) { return -5; }
    return 0;
}

fetch_ops_long(): int {
    var a = async.Atomic<long>(100);
    if (a.fetch_add(50) != 100 || a.load() != 150) { return -1; }
    if (a.fetch_sub(30) != 150 || a.load() != 120) { return -2; }
    if (a.fetch_and(128) != 120 || a.load() != 0) { return -3; }
    if (a.fetch_or(7) != 0 || a.load() != 7) { return -4; }
    if (a.fetch_xor(127) != 7 || a.load() != 120) { return -5; }
    return 0;
}

# ── is_lock_free ────────────────────────────────────────────────────────────

is_lock_free(): int {
    if (!async.Atomic<int>(0).is_lock_free()) { return -1; }
    if (!async.Atomic<long>(0).is_lock_free()) { return -2; }
    if (!async.Atomic<Point>().is_lock_free()) { return -3; }
    return 0;
}
"#;

#[test]
fn atomic_operations() {
    support::jit_cases(
        PROGRAM,
        &[
            "load_store_pod",
            "load_store_long",
            "load_store_struct",
            "load_store_double",
            "store_replaces_struct_ref",
            "cmpxchg_success_and_failure_pod",
            "cmpxchg_struct_refcount",
            "exchange_pod",
            "exchange_struct_refcount",
            "fetch_ops_int",
            "fetch_ops_long",
            "is_lock_free",
        ],
    );
}

// ── multi-threaded contention ────────────────────────────────────────────────

/// Host threads hammer two counters through JIT-compiled functions, one
/// counter after the other: `fetch_add`, then a compare-exchange retry loop.
#[test]
fn contention() {
    const THREADS: i32 = 4;
    let mut module = support::sema(
        r#"
import async;
const added = async.Atomic<long>(0);
const swapped = async.Atomic<long>(0);

add_one(): long {
    return added.fetch_add(1) + 1;
}

read_added(): long {
    return added.load();
}

# CAS-retry increment: each call wins exactly one step of the counter.
try_inc(): int {
    var cur = swapped.load();
    while (true) {
        if (swapped.compare_exchange(cur, cur + 1)) { return 1; }
        cur = swapped.load();
    }
}

read_swapped(): long {
    return swapped.load();
}"#,
    )
    .expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    // The engine borrows the generator's context: keep both alive until every
    // thread has joined, then they drop in order at scope exit.
    let ee = generator.jit_engine(&mut module).expect("jit");
    let function = |name: &str| unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>(name).expect(name).as_raw() };

    const ADD_STEPS: i64 = 50_000;
    let add_one = function("add_one");
    let handles: Vec<_> = (0..THREADS)
        .map(|_| std::thread::spawn(move || (0..ADD_STEPS).map(|_| unsafe { add_one() }).sum::<i64>()))
        .collect();
    let total: i64 = handles.into_iter().map(|h| h.join().unwrap()).sum();
    let n = THREADS as i64 * ADD_STEPS;
    // fetch_add returns the previous value: across all threads the returned
    // old values are exactly 0..n-1 (each once) iff no update was lost, so
    // the total is exact.
    assert_eq!(unsafe { function("read_added")() }, n);
    assert_eq!(total, n * (n - 1) / 2 + n);

    const CAS_STEPS: i64 = 25_000;
    let try_inc = unsafe { ee.get_function::<unsafe extern "C" fn() -> i32>("try_inc").expect("try_inc").as_raw() };
    let handles: Vec<_> = (0..THREADS)
        .map(|_| std::thread::spawn(move || (0..CAS_STEPS).map(|_| unsafe { try_inc() } as i64).sum::<i64>()))
        .collect();
    let wins: i64 = handles.into_iter().map(|h| h.join().unwrap()).sum();
    // Every call wins exactly one step, and the counter advances by exactly
    // one per win: any lost or duplicated update breaks final == wins.
    assert_eq!(wins, THREADS as i64 * CAS_STEPS);
    assert_eq!(unsafe { function("read_swapped")() }, THREADS as i64 * CAS_STEPS);
}
