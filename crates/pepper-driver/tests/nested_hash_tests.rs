//! Nested hash-container destruction coverage: `HashMap`/`HashSet` whose
//! keys or values are themselves heap containers must release every contained
//! object exactly once when the owning structure dies. Each snippet is compiled
//! with the runtime prelude and JIT-executed through `test`; the leak check
//! compares `_pep_live_allocs()` before construction and after the allocation
//! scope exits (RAII: locals are released automatically at scope exit).

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
fn hash_map_values_release_frees_all() {
    // Values are `Array<String>`: each value's String slots and the map's own
    // value slots must all release on destruction.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var m = HashMap<int, Array<String>>();
    var a1 = Array<String>(1);
    var s1 = "one";
    a1.append(s1);
    var a2 = Array<String>(1);
    var s2 = "two";
    a2.append(s2);
    if (!m.insert(1, a1)) { return -1; }
    if (!m.insert(2, a2)) { return -2; }
    if (m.count() != 2) { return -3; }
    # Compare through the creator variables: a literal in the expression
    # would allocate a temporary String that nothing releases.
    if (m[1][0] != s1) { return -4; }
    if (m[2][0] != s2) { return -5; }
    # The map's slots hold one ref each (acquired on insert); build's scope
    # exit drops the creators' refs and releases everything.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Each value's String slots and the map's own value slots must all
    # release on destruction.
    if (_pep_live_allocs() != before) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn hash_map_growth_release_frees_all() {
    // Five inserts into a default-capacity (8) map grow it once at the fifth
    // insert (size*2+1 >= capacity). grow() reinserts every existing value
    // into fresh arrays and releases the old keys/values/state arrays, so any
    // refcount slip shows up as a leak or double free.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var m = HashMap<int, Array<String>>();
    var i = 0;
    while (i < 5) {
        var a = Array<String>(1);
        var s = "v";
        a.append(s);
        # The slot holds the creator-independent ref; `s` and `a`'s own
        # refs are dropped when the loop body's scope exits.
        m.insert(i, a);
        i = i + 1;
    }
    if (m.count() != 5) { return -1; }
    if (m[4][0].size() != 1) { return -2; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # grow() reinserted every value into fresh arrays and released the old
    # keys/values/state arrays: any refcount slip shows up as a leak or
    # double free here.
    if (_pep_live_allocs() != before) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_hash_map_release_frees_all() {
    // `HashMap<String, HashMap<int,int>>`: the outer map's value slots hold
    // refs to inner maps whose own keys/values arrays must all release.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var m = HashMap<String, HashMap<int, int>>();
    var k1 = "a";
    var inner1 = HashMap<int, int>();
    inner1.insert(1, 10);
    inner1.insert(2, 20);
    var k2 = "b";
    var inner2 = HashMap<int, int>();
    inner2.insert(3, 30);
    if (!m.insert(k1, inner1)) { return -1; }
    if (!m.insert(k2, inner2)) { return -2; }
    if (m.count() != 2) { return -3; }
    if (m[k1][1] != 10) { return -4; }
    if (m[k2][3] != 30) { return -5; }
    # build's scope exit drops the creators' refs: String keys and inner maps.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # The outer map's value slots hold refs to inner maps whose own
    # keys/values arrays must all release.
    if (_pep_live_allocs() != before) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn hash_set_array_release_frees_all() {
    // `HashSet<Array<int>>`: arrays hash by identity, so distinct objects are
    // distinct members; the set's key slots must release each Array on death.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
build(): int {
    var s = HashSet<Array<int>>();
    var a1 = Array<int>(2);
    a1.append(1);
    a1.append(2);
    var a2 = Array<int>(2);
    a2.append(3);
    a2.append(4);
    if (!s.insert(a1)) { return -1; }
    if (!s.insert(a2)) { return -2; }
    if (s.count() != 2) { return -3; }
    # The set's slots hold one ref each; build's scope exit drops the
    # creators' refs.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # The set's key slots must release each Array on death.
    if (_pep_live_allocs() != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}
