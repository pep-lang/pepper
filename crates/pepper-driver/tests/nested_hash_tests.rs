//! Nested hash-container destruction coverage: `hash_map`/`hash_set` whose
//! keys or values are themselves heap containers must release every contained
//! object exactly once when the owning structure dies. Each snippet is compiled
//! with the runtime prelude and JIT-executed through `test`; the leak check
//! compares `_pep_live_allocs()` before construction and after the owner's
//! `__release` (Pepper has no scope-exit destruction, so explicit release stands
//! in for going out of scope).

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

/// `_pep_live_allocs()` is a process-wide counter, so leak-census tests must
/// not run concurrently with each other; serialize on this lock.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

fn compile_jit_with_runtime(source: &str) -> i32 {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
    module.merge(build(&ast).expect("build"));
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module);
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn hash_map_values_release_frees_all() {
    // Values are `array<string>`: each value's string slots and the map's own
    // value slots must all release on destruction.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var m = hash_map<int, array<string>>();
    var a1 = array<string>(1);
    var s1 = "one";
    a1.append(s1);
    var a2 = array<string>(1);
    var s2 = "two";
    a2.append(s2);
    if (!m.insert(1, a1)) { return -1; }
    if (!m.insert(2, a2)) { return -2; }
    if (m.count() != 2) { return -3; }
    # Compare through the creator variables: a literal in the expression
    # would allocate a temporary string that nothing releases.
    if (m[1][0] != s1) { return -4; }
    if (m[2][0] != s2) { return -5; }
    # The map's slots hold one ref each (acquired on insert); drop the
    # creators' refs so releasing the map frees everything.
    s1.__release();
    s2.__release();
    a1.__release();
    a2.__release();
    m.__release();
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
test(): int {
    long before = _pep_live_allocs();
    var m = hash_map<int, array<string>>();
    var i = 0;
    while (i < 5) {
        var a = array<string>(1);
        var s = "v";
        a.append(s);
        # The slot now holds the only creator-independent ref.
        s.__release();
        m.insert(i, a);
        a.__release();
        i = i + 1;
    }
    if (m.count() != 5) { return -1; }
    if (m[4][0].size() != 1) { return -2; }
    m.__release();
    if (_pep_live_allocs() != before) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_hash_map_release_frees_all() {
    // `hash_map<string, hash_map<int,int>>`: the outer map's value slots hold
    // refs to inner maps whose own keys/values arrays must all release.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var m = hash_map<string, hash_map<int, int>>();
    var k1 = "a";
    var inner1 = hash_map<int, int>();
    inner1.insert(1, 10);
    inner1.insert(2, 20);
    var k2 = "b";
    var inner2 = hash_map<int, int>();
    inner2.insert(3, 30);
    if (!m.insert(k1, inner1)) { return -1; }
    if (!m.insert(k2, inner2)) { return -2; }
    if (m.count() != 2) { return -3; }
    if (m[k1][1] != 10) { return -4; }
    if (m[k2][3] != 30) { return -5; }
    # Drop the creators' refs: string keys and inner maps.
    k1.__release();
    k2.__release();
    inner1.__release();
    inner2.__release();
    m.__release();
    if (_pep_live_allocs() != before) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn hash_set_array_release_frees_all() {
    // `hash_set<array<int>>`: arrays hash by identity, so distinct objects are
    // distinct members; the set's key slots must release each array on death.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var s = hash_set<array<int>>();
    var a1 = array<int>(2);
    a1.append(1);
    a1.append(2);
    var a2 = array<int>(2);
    a2.append(3);
    a2.append(4);
    if (!s.insert(a1)) { return -1; }
    if (!s.insert(a2)) { return -2; }
    if (s.count() != 2) { return -3; }
    # The set's slots hold one ref each; drop the creators' refs.
    a1.__release();
    a2.__release();
    s.__release();
    if (_pep_live_allocs() != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}
