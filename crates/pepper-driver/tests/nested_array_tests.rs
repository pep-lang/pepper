//! Nested-array destruction coverage: `array<array<T>>` and other nested
//! containers must release every contained object exactly once when the
//! owning structure dies. Each snippet is compiled with the runtime prelude
//! and JIT-executed through `test`; the leak check compares
//! `_pep_live_allocs()` before construction and after the owner's
//! `__release` (Pepper has no scope-exit destruction, so explicit release
//! stands in for going out of scope).

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
fn nested_array_release_frees_inner_arrays() {
    // The outer array holds one ref per inner array (acquired on store).
    // Dropping the creators' refs and releasing the outer must free every
    // inner array object, its buffer, and the outer's own buffer.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var outer = array<array<int>>(4);
    var a = array<int>(2);
    a.append(1);
    a.append(2);
    var b = array<int>(2);
    b.append(3);
    b.append(4);
    var c = array<int>(2);
    c.append(5);
    c.append(6);
    outer.append(a);
    outer.append(b);
    outer.append(c);
    if (outer.count() != 3) { return -1; }
    if (outer[0][1] != 2) { return -2; }
    if (outer[2][0] != 5) { return -3; }
    # The slots hold one ref each; drop the creators' refs so releasing
    # the outer frees everything.
    a.__release();
    b.__release();
    c.__release();
    outer.__release();
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
    // inner array's refcount at exactly one per slot: after all operations,
    // releasing the outer frees everything.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var outer = array<array<int>>(2);
    var a = array<int>(1);
    a.append(1);
    var b = array<int>(1);
    b.append(2);
    var c = array<int>(1);
    c.append(3);
    var d = array<int>(1);
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
    # `removed` is a local holding one ref to `a`; drop it too.
    removed.__release();
    a.__release();
    b.__release();
    c.__release();
    d.__release();
    outer.__release();
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
    // must be freed and every inner array released exactly once.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var outer = array<array<int>>(1);
    var i = 0;
    while (i < 10) {
        var inner = array<int>(1);
        inner.append(i * 10);
        outer.append(inner);
        # The slot now holds the only creator-independent ref.
        inner.__release();
        i = i + 1;
    }
    if (outer.count() != 10) { return -1; }
    if (outer[9][0] != 90) { return -2; }
    outer.__release();
    if (_pep_live_allocs() != before) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array_of_strings_release_frees_all() {
    // Strings are struct elements too: each inner array's string slots and
    // the outer's inner-array slots must all release on destruction.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var outer = array<array<string>>(2);
    var a = array<string>(1);
    var s1 = "one";
    a.append(s1);
    if (a.count() != 1) { return -1; }
    if (s1.size() != 3) { return -2; }
    var b = array<string>(1);
    var s2 = "two";
    b.append(s2);
    outer.append(a);
    outer.append(b);
    if (outer.count() != 2) { return -3; }
    # Compare through the creator variables: a literal in the expression
    # would allocate a temporary string that nothing releases.
    if (outer[0][0] != s1) { return -4; }
    if (outer[1][0] != s2) { return -5; }
    s1.__release();
    s2.__release();
    a.__release();
    b.__release();
    outer.__release();
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
test(): int {
    long before = _pep_live_allocs();
    var outer = array<array<int>>(2);
    var a = array<int>(1);
    a.append(1);
    var b = array<int>(1);
    b.append(2);
    outer.append(a);
    outer.append(b);
    if (outer.count() != 2) { return -1; }
    outer.clear();
    if (!outer.empty()) { return -2; }
    # clear released the slots' refs; drop the creators' too.
    a.__release();
    b.__release();
    outer.__release();
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
    // every inner array to free.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    long before = _pep_live_allocs();
    var outer = array<array<int>>(2);
    var a = array<int>(1);
    a.append(7);
    outer.append(a);
    var copy = outer.clone();
    if (copy.count() != 1) { return -1; }
    if (copy[0][0] != 7) { return -2; }
    # The clone shares the inner array: a mutation through the clone is
    # visible in the original.
    copy[0].append(8);
    if (outer[0].count() != 2) { return -3; }
    if (outer[0][1] != 8) { return -4; }
    a.__release();
    outer.__release();
    copy.__release();
    if (_pep_live_allocs() != before) { return -5; }
    return 0;
}"#
        ),
        0
    );
}
