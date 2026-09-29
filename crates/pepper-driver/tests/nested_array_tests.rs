//! Nested-Array destruction coverage: `Array<Array<T>>` and other nested
//! containers must release every contained object exactly once when the
//! owning structure dies. Each snippet is compiled with the runtime prelude
//! and JIT-executed through `test`; the leak check compares
//! `_pep_live_allocs()` before construction and after the allocation scope
//! exits (RAII: locals are released automatically at scope exit).

use pepper_codegen::CodeGenerator;

/// `_pep_live_allocs()` is a process-wide counter, so leak-census tests must
/// not run concurrently with each other; serialize on this lock.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn compile_jit_with_runtime(source: &str) -> i32 {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn nested_array_release_frees_inner_arrays() {
    // The outer Array holds one ref per inner Array (acquired on store).
    // Dropping the creators' refs and releasing the outer must free every
    // inner Array object, its buffer, and the outer's own buffer.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var outer = Array<Array<int>>(4);
    var a = Array<int>(2);
    a.append(1);
    a.append(2);
    var b = Array<int>(2);
    b.append(3);
    b.append(4);
    var c = Array<int>(2);
    c.append(5);
    c.append(6);
    outer.append(a);
    outer.append(b);
    outer.append(c);
    if (outer.count() != 3) { return -1; }
    if (outer[0][1] != 2) { return -2; }
    if (outer[2][0] != 5) { return -3; }
    # The slots hold one ref each; build's scope exit drops the creators'
    # refs and releases everything.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every inner Array object, its buffer, and the outer's own buffer must
    # be freed.
    if (_pep_live_allocs() != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array_insert_remove_swap_release_frees_all() {
    // Shift-based insert/remove and the raw-pointer swap must keep every
    // inner Array's refcount at exactly one per slot: after all operations,
    // releasing the outer frees everything.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var outer = Array<Array<int>>(2);
    var a = Array<int>(1);
    a.append(1);
    var b = Array<int>(1);
    b.append(2);
    var c = Array<int>(1);
    c.append(3);
    var d = Array<int>(1);
    d.append(4);
    outer.append(a);
    outer.append(b);
    outer.insert(0, c);
    # order: c, a, b
    if (outer[0][0] != 3) { return -1; }
    if (outer[1][0] != 1) { return -2; }
    var removed = outer.remove_at(1);
    if (removed[0] != 1) { return -3; }
    # order: c, b
    if (outer.count() != 2) { return -4; }
    if (outer[1][0] != 2) { return -5; }
    outer.append(d);
    outer.swap(0, 2);
    # order: d, b, c
    if (outer[0][0] != 4) { return -6; }
    if (outer[1][0] != 2) { return -7; }
    if (outer[2][0] != 3) { return -8; }
    # `removed` is a local holding one ref to `a`; build's scope exit
    # drops it along with the creators' refs.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Releasing the outer frees everything.
    if (_pep_live_allocs() != before) { return -9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array_growth_release_frees_all() {
    // Appending past capacity reallocates the outer buffer; the old buffer
    // must be freed and every inner Array released exactly once.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var outer = Array<Array<int>>(1);
    var i = 0;
    while (i < 10) {
        var inner = Array<int>(1);
        inner.append(i * 10);
        outer.append(inner);
        # The slot holds the creator-independent ref; `inner`'s own ref
        # is dropped when the loop body's scope exits.
        i = i + 1;
    }
    if (outer.count() != 10) { return -1; }
    if (outer[9][0] != 90) { return -2; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # The old buffer must be freed and every inner Array released.
    if (_pep_live_allocs() != before) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array_of_strings_release_frees_all() {
    // Strings are struct elements too: each inner Array's String slots and
    // the outer's inner-Array slots must all release on destruction.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var outer = Array<Array<String>>(2);
    var a = Array<String>(1);
    var s1 = "one";
    a.append(s1);
    if (a.count() != 1) { return -1; }
    if (s1.size() != 3) { return -2; }
    var b = Array<String>(1);
    var s2 = "two";
    b.append(s2);
    outer.append(a);
    outer.append(b);
    if (outer.count() != 2) { return -3; }
    # Compare through the creator variables: a literal in the expression
    # would allocate a temporary String that nothing releases.
    if (outer[0][0] != s1) { return -4; }
    if (outer[1][0] != s2) { return -5; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Each inner Array's String slots and the outer's inner-Array slots
    # must all release when build's scope exits.
    if (_pep_live_allocs() != before) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array_clear_release_frees_all() {
    // clear() nulls every slot (releasing the inner arrays); the later
    // destruct must then find nothing to release - no double free, no leak.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var outer = Array<Array<int>>(2);
    var a = Array<int>(1);
    a.append(1);
    var b = Array<int>(1);
    b.append(2);
    outer.append(a);
    outer.append(b);
    if (outer.count() != 2) { return -1; }
    outer.clear();
    if (!outer.empty()) { return -2; }
    # clear released the slots' refs; build's scope exit drops the
    # creators' too. The later destruct must then find nothing to release -
    # no double free, no leak.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    if (_pep_live_allocs() != before) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array_clone_release_frees_all() {
    // clone() copies the reference slots (each copy acquires), so original
    // and clone share the inner arrays; both owners must be released for
    // every inner Array to free.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var outer = Array<Array<int>>(2);
    var a = Array<int>(1);
    a.append(7);
    outer.append(a);
    var copy = outer.clone();
    if (copy.count() != 1) { return -1; }
    if (copy[0][0] != 7) { return -2; }
    # The clone shares the inner Array: a mutation through the clone is
    # visible in the original.
    copy[0].append(8);
    if (outer[0].count() != 2) { return -3; }
    if (outer[0][1] != 8) { return -4; }
    # The clone shares the inner Array: build's scope exit releases both
    # owners, freeing every inner Array.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    if (_pep_live_allocs() != before) { return -5; }
    return 0;
}"#
        ),
        0
    );
}
