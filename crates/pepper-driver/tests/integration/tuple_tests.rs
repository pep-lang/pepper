//! Tuples: `(A, B)` types, `(a, b)` literals, `t.0` element reads and
//! destructuring (`var (a, b) = f();`, `(a, b) = (b, a);`). A tuple is a
//! value that holds one reference to each element, like a `std::tuple` of
//! `shared_ptr`s (passes/tuples.rs, codegen's `register_tuple`).

use pepper_codegen::CodeGenerator;

fn run(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

const NODE: &str = r#"
const destroyed = Atomic<int>(0);

trait Shape {
    area(): int;
}

struct Node {
    var value: int = 0;
    construct(this.value = 0) {}
    destruct { destroyed.fetch_add(1); }
}

extend Node with Shape {
    area(): int { return this.value; }
}

pair(a: int, b: int): (Node, Node) {
    return (Node(a), Node(b));
}
"#;

fn with_node(body: &str) -> String {
    format!("{}{}", NODE, body)
}

#[test]
fn multiple_returns_destructure() {
    let src = r#"
divide(a: int, b: int): (int, int) {
    return (a / b, a % b);
}

test(): int {
    var (q, r) = divide(17, 5);
    if (q != 3 || r != 2) { return 1; }
    var (_, only) = divide(7, 2);
    if (only != 1) { return 2; }
    const (x, y: long) = divide(9, 2);
    if (x != 4 || y != 1) { return 3; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn element_access() {
    let src = r#"
nested(): (int, (String, long)) {
    return (1, ("x", 9));
}

test(): int {
    var t = nested();
    if (t.0 != 1) { return 1; }
    if (t.1.0 != "x" || t.1.1 != 9) { return 2; }
    if (nested().1.1 != 9) { return 3; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn destructuring_assignment_swaps() {
    let src = r#"
struct Point {
    var x: int = 0;
    var y: int = 0;
}

test(): int {
    var a = 1;
    var b = 2;
    (a, b) = (b, a);
    if (a != 2 || b != 1) { return 1; }
    var p = Point();
    (p.x, _, p.y) = (5, "skipped", 6);
    if (p.x != 5 || p.y != 6) { return 2; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn literal_converts_to_declared_type() {
    let src = r#"
widen(): (long, String) {
    return (5, "five");
}

test(): int {
    var t: (long, double) = (1, 2);
    if (t.0 != 1 || t.1 != 2.0) { return 1; }
    var (n, s) = widen();
    if (n != 5 || s != "five") { return 2; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn bindings_own_their_elements() {
    let src = with_node(
        r#"
test(): int {
    var before = _pep_live_allocs();
    {
        var (a, b) = pair(1, 2);
        # A binding names the element: it holds the only reference.
        if (__refcount<Node>(a) != 1 || __refcount<Node>(b) != 1) { return 1; }
        (a, b) = (b, a);
        if (a.value != 2 || b.value != 1) { return 2; }
        if (__refcount<Node>(a) != 1 || __refcount<Node>(b) != 1) { return 3; }
        var t = (a, b);
        if (__refcount<Node>(a) != 2) { return 4; }
        t = t;
        if (__refcount<Node>(a) != 2) { return 5; }
        t = pair(3, 4);
        if (__refcount<Node>(a) != 1) { return 6; }
        var copy = t;
        if (__refcount<Node>(copy.0) != 2) { return 7; }
    }
    if (_pep_live_allocs() != before) { return 8; }
    if (destroyed.load() != 4) { return 9; }
    return 0;
}
"#,
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn temporaries_and_parameters_release() {
    let src = with_node(
        r#"
first(t: (Node, Node)): Node {
    return t.0;
}

pick(flag: bool): (int, Node) {
    return flag ? (1, Node(1)) : (2, Node(2));
}

test(): int {
    var before = _pep_live_allocs();
    {
        if (first(pair(1, 2)).value != 1) { return 1; }
        if (pair(5, 6).1.value != 6) { return 2; }
        var (n, node) = pick(false);
        if (n != 2 || node.value != 2) { return 3; }
        var (s: Shape, _) = pair(3, 4);
        if (s.area() != 3) { return 4; }
        var i = 0;
        while (i < 10) {
            var (a, b) = pair(i, i);
            (a, b) = pair(1, 2);
            i = i + 1;
        }
    }
    if (_pep_live_allocs() != before) { return 5; }
    if (destroyed.load() != 47) { return 6; }
    return 0;
}
"#,
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn fields_and_globals() {
    let src = with_node(
        r#"
const origin: (int, long) = (1, 2);

struct Holder {
    var pair: (int, Node);
    construct() { this.pair = (0, Node(0)); }
}

test(): int {
    var before = _pep_live_allocs();
    {
        var h = Holder();
        h.pair = (5, Node(5));
        if (h.pair.1.value != 5) { return 1; }
    }
    if (_pep_live_allocs() != before) { return 2; }
    if (origin.0 != 1 || origin.1 != 2) { return 3; }
    return 0;
}
"#,
    );
    assert_eq!(run(&src), 0);
}
