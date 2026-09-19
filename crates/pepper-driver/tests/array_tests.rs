//! Array API coverage: each snippet is compiled together with the runtime
//! prelude and JIT-executed through the entry function `test`.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

fn compile_jit_with_runtime(source: &str) -> i32 {
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
fn append_and_count() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    if (a.count() != 3) { return -1; }
    var sum = a[0] + a[1] + a[2];
    return 6 - sum;
}"#
        ),
        0
    );
}

#[test]
fn growth_reallocates() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    var i = 0;
    while (i < 10) {
        a.append(i);
        i = i + 1;
    }
    if (a.count() != 10) { return -1; }
    var j = 0;
    var bad = 0;
    while (j < 10) {
        if (a[j] != j) { bad = bad + 1; }
        j = j + 1;
    }
    return bad;
}"#
        ),
        0
    );
}

#[test]
fn ctor_capacity() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>(8);
    if (a.capacity() < 8) { return -1; }
    if (a.count() != 0) { return -2; }
    if (!a.empty()) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn reserve_never_shrinks() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.reserve(8);
    a.reserve(2);
    if (a.capacity() < 8) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn index_get_and_set() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>(4);
    a.append(1);
    a.append(2);
    a.append(3);
    a[1] = 7;
    if (a[1] != 7) { return -1; }
    if (a[0] != 1 || a[2] != 3) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn insert_front_middle_end() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(5);
    a.insert(0, 1);
    a.insert(1, 3);
    a.insert(a.count(), 9);
    if (a.count() != 4) { return -1; }
    if (a[0] != 1 || a[1] != 3 || a[2] != 5 || a[3] != 9) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn remove_at_shifts() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    var r = a.remove_at(1);
    if (r != 2) { return -1; }
    if (a.count() != 2 || a[0] != 1 || a[1] != 3) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn pop_returns_last() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    var r = a.pop();
    if (r != 2) { return -1; }
    if (a.count() != 1 || a[0] != 1) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn first_and_last() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    if (a.first() != 1) { return -1; }
    if (a.last() != 3) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn clear_then_reuse() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.clear();
    if (!a.empty()) { return -1; }
    a.append(9);
    if (a.count() != 1 || a[0] != 9) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn truncate_drops_tail() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    a.truncate(1);
    if (a.count() != 1 || a[0] != 1) { return -1; }
    a.truncate(5);
    if (a.count() != 1) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn swap_and_reverse() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    a.swap(0, 2);
    if (a[0] != 3 || a[2] != 1) { return -1; }
    a.reverse();
    if (a[0] != 1 || a[1] != 2 || a[2] != 3) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn find_and_contains() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    if (a.find(2) != 1) { return -1; }
    if (a.find(99) != -1) { return -2; }
    if (!a.contains(3)) { return -3; }
    if (a.contains(99)) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn clone_is_independent() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    var b = a.clone();
    b.append(2);
    if (a.count() != 1) { return -1; }
    if (b.count() != 2 || b[1] != 2) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn append_all_and_plus_assign() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    var b = array<int>();
    b.append(2);
    b.append(3);
    a += b;
    if (a.count() != 3) { return -1; }
    if (a[0] != 1 || a[1] != 2 || a[2] != 3) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn plus_operator_concatenates() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    var b = array<int>();
    b.append(2);
    var c = a + b;
    if (c.count() != 2) { return -1; }
    if (a.count() != 1 || b.count() != 1) { return -2; }
    if (c[0] != 1 || c[1] != 2) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn equality_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    a.append(2);
    var b = array<int>();
    b.append(1);
    b.append(2);
    if (!(a == b)) { return -1; }
    b.append(3);
    if (a == b) { return -2; }
    b[0] = 9;
    var c = array<int>();
    c.append(1);
    c.append(2);
    if (b == c) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn inequality_operator() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = array<int>();
    a.append(1);
    var b = array<int>();
    b.append(1);
    if (a != b) { return -1; }
    b.append(2);
    if (!(a != b)) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn array_of_structs() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    new(this.x = 0, this.y = 0) {}
}
test(): int {
    var pts = array<Point>();
    var p = Point();
    p.x = 3;
    p.y = 4;
    pts.append(p);
    var q = pts[0];
    return 7 - (q.x + q.y);
}"#
        ),
        0
    );
}

#[test]
fn array_of_strings() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = array<string>();
    s.append("hello");
    s.append("world");
    if (s.find("world") != 1) { return -1; }
    if (!s.contains("hello")) { return -2; }
    var t = array<string>();
    t.append("hello");
    t.append("world");
    if (!(s == t)) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var outer = array<array<int>>();
    var inner = array<int>();
    inner.append(1);
    inner.append(2);
    outer.append(inner);
    if (outer.count() != 1) { return -1; }
    if (outer[0][1] != 2) { return -2; }
    var sum = outer[0][0] + outer[0][1];
    return 3 - sum;
}"#
        ),
        0
    );
}

#[test]
fn bracket_syntax_is_array() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int[] xs = array<int>();
    xs.append(1);
    xs.append(2);
    if (xs.count() != 2) { return -1; }
    var sum = xs[0] + xs[1];
    return 3 - sum;
}"#
        ),
        0
    );
}

#[test]
fn bracket_syntax_in_signature() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
int[] echo(int[] in): int[] {
    return in;
}
test(): int {
    var a = array<int>();
    a.append(4);
    a.append(5);
    int[] r = echo(a);
    if (r.count() != 2) { return -1; }
    var sum = r[0] + r[1];
    return 9 - sum;
}"#
        ),
        0
    );
}

// ── __refcount<T>(t) intrinsic: array element reference semantics ───────────

#[test]
fn refcount_pod_is_zero() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var x = 42;
    if (__refcount<int>(x) != 0) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn refcount_append_pop() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    new(this.x = 0) {}
}
test(): int {
    var p = Point();
    if (__refcount<Point>(p) != 1) { return -1; }
    var a = array<Point>();
    a.append(p);
    if (__refcount<Point>(p) != 2) { return -2; }
    var q = a.pop();
    if (__refcount<Point>(p) != 1) { return -3; }
    if (q.x != 0) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn refcount_clear_destroys_elements() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Tally {
    int alive;
    new(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}
test(): int {
    var t = Tally();
    var a = array<Tally>();
    a.append(t);
    a.append(Tally());
    if (__refcount<Tally>(t) != 2) { return -1; }
    a.clear();
    if (t.alive != 1) { return -2; }
    if (__refcount<Tally>(t) != 1) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn refcount_truncate_releases_tail_only() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Tally {
    int alive;
    new(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}
test(): int {
    var a = array<Tally>();
    var t = Tally();
    a.append(t);
    a.append(Tally());
    a.append(Tally());
    a.truncate(2);
    if (__refcount<Tally>(t) != 2) { return -1; }
    if (a.count() != 2) { return -2; }
    if (t.alive != 1) { return -3; }
    a.truncate(0);
    if (__refcount<Tally>(t) != 1) { return -4; }
    if (t.alive != 1) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn refcount_clone_and_remove_at() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    new(this.x = 0) {}
}
test(): int {
    var a = array<Point>();
    var p = Point();
    p.x = 7;
    a.append(p);
    if (__refcount<Point>(p) != 2) { return -1; }
    var b = a.clone();
    if (__refcount<Point>(p) != 3) { return -2; }
    var r = b.remove_at(0);
    if (__refcount<Point>(p) != 2) { return -3; }
    if (r.x != 7) { return -4; }
    b.clear();
    if (__refcount<Point>(p) != 2) { return -5; }
    a.clear();
    if (__refcount<Point>(p) != 1) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn refcount_insert_shifts_without_churn() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    new(this.x = 0) {}
}
test(): int {
    var a = array<Point>();
    var p1 = Point();
    p1.x = 1;
    var p2 = Point();
    p2.x = 2;
    a.append(p1);
    a.append(p2);
    if (__refcount<Point>(p1) != 2) { return -1; }
    if (__refcount<Point>(p2) != 2) { return -2; }
    var p3 = Point();
    p3.x = 3;
    a.insert(0, p3);
    if (__refcount<Point>(p1) != 2) { return -3; }
    if (__refcount<Point>(p2) != 2) { return -4; }
    if (__refcount<Point>(p3) != 2) { return -5; }
    if (a[0].x != 3 || a[1].x != 1 || a[2].x != 2) { return -6; }
    a.clear();
    if (__refcount<Point>(p1) != 1 || __refcount<Point>(p2) != 1 || __refcount<Point>(p3) != 1) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn refcount_nested_array() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var inner = array<int>();
    inner.append(1);
    if (__refcount<array<int>>(inner) != 1) { return -1; }
    var outer = array<array<int>>();
    outer.append(inner);
    if (__refcount<array<int>>(inner) != 2) { return -2; }
    var out = outer.pop();
    if (__refcount<array<int>>(inner) != 1) { return -3; }
    if (out[0] != 1) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn refcount_shift_of_unreferenced_element() {
    // The array is the sole owner of these elements. A shift implemented as
    // per-slot release/acquire stores would destroy them mid-move (their only
    // reference), so shifts must move raw pointer slots instead.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Tally {
    int alive;
    new(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}
test(): int {
    var a = array<Tally>();
    a.append(Tally());
    a.append(Tally());
    a.insert(0, Tally());
    if (a.count() != 3) { return -1; }
    if (a[0].alive != 1 || a[1].alive != 1 || a[2].alive != 1) { return -2; }
    var r = a.remove_at(0);
    if (r.alive != 1) { return -3; }
    if (a.count() != 2) { return -4; }
    if (a[0].alive != 1 || a[1].alive != 1) { return -5; }
    a.clear();
    if (r.alive != 1) { return -6; }
    return 0;
}"#
        ),
        0
    );
}
