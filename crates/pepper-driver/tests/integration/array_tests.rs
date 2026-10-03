//! Array tests that check compiler behaviour: `int[]` signature syntax, the
//! `__refcount` intrinsic and the shared_ptr copy semantics of returned
//! references, construct-at stores, and codegen regressions. Each snippet is
//! compiled with the runtime prelude and JIT-executed through `test`. The
//! Array library behaviour is tested in `runtime/test/array_test.pep`.

use crate::support::{compile_jit_with_runtime, jit_census};

#[test]
fn bracket_syntax_in_signature() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
int[] echo(int[] in): int[] {
    return in;
}
test(): int {
    var a = Array<int>();
    a.append(4);
    a.append(5);
    int[] r = echo(a);
    if (r.count != 2) { return -1; }
    var sum = r[0] + r[1];
    return 9 - sum;
}"#
        ),
        0
    );
}

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
    construct(this.x = 0) {}
}
test(): int {
    var p = Point();
    if (__refcount<Point>(p) != 1) { return -1; }
    var a = Array<Point>();
    a.append(p);
    if (__refcount<Point>(p) != 2) { return -2; }
    # pop returns a copy of the reference (shared_ptr semantics): the slot
    # release and the return acquire cancel, so p's count is unchanged.
    var q = a.pop();
    if (__refcount<Point>(p) != 2) { return -3; }
    if (__refcount<Point>(q) != 2) { return -5; }
    if (q.x != 0) { return -4; }
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
    construct(this.x = 0) {}
}
test(): int {
    var a = Array<Point>();
    var p = Point();
    p.x = 7;
    a.append(p);
    if (__refcount<Point>(p) != 2) { return -1; }
    # clone copies every element reference: +1.
    var b = a.clone();
    if (__refcount<Point>(p) != 3) { return -2; }
    # remove_at returns a copy of the reference: slot release and return
    # acquire cancel, so p's count is unchanged; r holds its own ref.
    var r = b.remove_at(0);
    if (__refcount<Point>(p) != 3) { return -3; }
    if (__refcount<Point>(r) != 3) { return -8; }
    if (r.x != 7) { return -4; }
    # clear releases every slot: b's copy of p drops.
    b.clear();
    if (__refcount<Point>(p) != 3) { return -5; }
    a.clear();
    if (__refcount<Point>(p) != 2) { return -6; }
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
    var inner = Array<int>();
    inner.append(1);
    if (__refcount<Array<int>>(inner) != 1) { return -1; }
    var outer = Array<Array<int>>();
    outer.append(inner);
    if (__refcount<Array<int>>(inner) != 2) { return -2; }
    # pop returns a copy of the reference: slot release and return acquire
    # cancel, so inner's count is unchanged.
    var out = outer.pop();
    if (__refcount<Array<int>>(inner) != 2) { return -3; }
    if (out[0] != 1) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn bracket_signature_auto_typed_return() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
roundtrip(int[] xs): int[] {
    xs.append(9);
    return xs;
}
test(): int {
    var out = roundtrip(Array<int>());
    if (out.count != 1) { return -1; }
    if (out[0] != 9) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn nested_array_raw_buffer_write() {
    // Regression: a raw-buffer field write (`Data[i] = v`) inside an
    // `Array<Array<int>>` body must stay a buffer store, not be rewritten to
    // the element type's `__index_set` with the raw pointer as receiver.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var outer = Array<Array<int>>(4);
    outer._size = 4;
    var inner = Array<int>(3);
    inner.append(10);
    inner.append(20);
    outer._data[0] = inner;
    if (outer._data[0].count != 2) { return -1; }
    if (outer._data[0][1] != 20) { return -2; }
    var empty = Array<int>();
    outer._data[1] = empty;
    if (!outer._data[1].is_empty) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn float_compound_assign() {
    // Regression: compound assigns must coerce the ALREADY-COERCED rhs value,
    // not the raw rhs with the post-coercion name — `x += 1` on a float lhs
    // used to reach codegen as int + float and fail.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    double x = 1.5;
    x += 1;
    if (x != 2.5) { return -1; }
    x -= 0.5;
    if (x != 2.0) { return -2; }
    double y = 3.0;
    y *= 2;
    if (y != 6.0) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn construct_at_stores_count_and_free() {
    // `append`, `insert` and HashMap's insert and rehash construct into
    // empty slots: each element holds exactly one reference, and nothing
    // leaks once the containers go.
    let (result, leaked) = jit_census(
        r#"
struct Point {
    int x;
    construct(this.x = 0) {}
}
trait Shape {
    area(): int;
}
extend Point with Shape {
    area(): int { return x; }
}
make(x: int): Point {
    return Point(x);
}
test(): int {
    var p = Point(1);
    {
        var a = Array<Point>();
        a.append(p);
        a.append(make(2));
        a.insert(0, p);
        a.insert(1, make(3));
        if (__refcount<Point>(p) != 3) { return -1; }
        # `a[i]` is a copy of the element, so it holds a second reference.
        if (__refcount<Point>(a[1]) != 2 || __refcount<Point>(a[3]) != 2) { return -2; }
        if (a[0].x + a[1].x + a[2].x + a[3].x != 7) { return -3; }

        var tuples = Array<(int, Point)>();
        tuples.append((1, p));
        tuples.insert(0, (2, make(4)));
        if (__refcount<Point>(p) != 4) { return -4; }
        if (__refcount<Point>(tuples[0].1) != 2) { return -5; }

        var shapes = Array<Shape>();
        shapes.append(p);
        shapes.insert(0, make(5));
        if (__refcount<Point>(p) != 5) { return -6; }
        if (shapes[0].area() + shapes[1].area() != 6) { return -7; }

        var m = HashMap<int, Point>();
        var i = 0;
        while (i < 40) {
            m.insert(i, p);
            i = i + 1;
        }
        if (__refcount<Point>(p) != 45) { return -8; }
        m.remove(3);
        m.insert(3, make(6));
        if (__refcount<Point>(p) != 44) { return -9; }
    }
    if (__refcount<Point>(p) != 1) { return -10; }
    return 0;
}"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}
