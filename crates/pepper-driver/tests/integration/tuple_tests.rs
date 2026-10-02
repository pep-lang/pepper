//! Tuples: `(A, B)` types, `(a, b)` literals, `t.0` element reads and
//! destructuring (`var (a, b) = f();`, `(a, b) = (b, a);`). A tuple is a
//! value that holds one reference to each element, like a `std::tuple` of
//! `shared_ptr`s (passes/tuples.rs, codegen's `register_tuple`).

use clap::Parser;
use std::process::Command;
use crate::support::compile_jit_with_runtime as run;
use crate::support::repo_root;

const NODE: &str = r#"
import async;
const destroyed = async.Atomic<int>(0);

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

/// Builds `source` into an executable and runs it; returns whether it
/// exited cleanly and its stdout.
fn run_exe(name: &str, source: &str) -> (bool, String) {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_tuple_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("main.pep");
    std::fs::write(&src, source).unwrap();
    let exe = dir.join(if cfg!(windows) { "main.exe" } else { "main" });
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src.to_string_lossy().into_owned(),
        "-o".to_string(),
        exe.to_string_lossy().into_owned(),
        "--build".to_string(),
        dir.join("build").to_string_lossy().into_owned(),
    ]);
    pepper_driver::run(options).expect("compile + link");
    let output = Command::new(&exe).output().expect("spawn");
    let _ = std::fs::remove_dir_all(dir);
    (output.status.success(), String::from_utf8_lossy(&output.stdout).replace("\r\n", "\n"))
}

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
fn default_element() {
    // `__default<T>()` as an element: the literal's type needs the
    // intrinsic's, in a generic body and a concrete one.
    let src = r#"
missing<T>(): (bool, T) {
    return (false, __default<T>());
}

test(): int {
    var (found, n) = missing<int>();
    if (found || n != 0) { return 1; }
    var (_, d) = missing<f64>();
    if (d != 0.0) { return 2; }
    var t = (true, __default<long>());
    if (!t.0 || t.1 != 0) { return 3; }
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

#[test]
fn generic_arguments_equality_and_hashing() {
    let src = with_node(
        r#"
test(): int {
    var before = _pep_live_allocs();
    {
        var a = Array<(int, String)>();
        a.append((1, "one"));
        a.append((2, "two"));
        if (a[1].1 != "two") { return 1; }
        if (!a.contains((2, "t" + "wo"))) { return 2; }
        if (!((1, "x") == (1, "x")) || !((1, "x") != (1, "y"))) { return 3; }
        if ((1, (2.5, true)) != (1, (2.5, true))) { return 4; }
        var n = Node(1);
        if ((n, 1) != (n, 1)) { return 5; }
        if ((Node(1), 1) == (Node(1), 1)) { return 6; }
        var m = HashMap<(int, String), int>();
        m[(1, "a")] = 10;
        m[(2, "b")] = 20;
        if (m[(1, "a")] != 10 || !m.contains((2, "b"))) { return 7; }
        var by_name = HashMap<String, (int, Node)>();
        by_name["p"] = (3, Node(4));
        if (by_name["p"].1.value != 4) { return 8; }
        var spelled = HashMap<Tuple<int, int>, String>();
        spelled[(1, 2)] = "x";
        var u: Tuple<int, String> = (1, "a");
        var v: (int, String) = u;
        if (spelled[(1, 2)] != "x" || v != (1, "a")) { return 9; }
        a.remove_at(0);
    }
    if (_pep_live_allocs() != before) { return 10; }
    return 0;
}
"#,
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn nested_and_for_loop_destructuring() {
    let src = with_node(
        r#"
nested(): (int, (String, Node)) {
    return (1, ("x", Node(9)));
}

test(): int {
    var before = _pep_live_allocs();
    {
        var (a, (s, n)) = nested();
        if (a != 1 || s != "x" || n.value != 9) { return 1; }
        if (__refcount<Node>(n) != 1) { return 2; }
        var (_, (_, m: Node)) = nested();
        if (m.value != 9) { return 3; }
        var b = 0;
        var t = "";
        (b, (t, _)) = nested();
        if (b != 1 || t != "x") { return 4; }
        var pairs = Array<(String, int)>();
        pairs.append(("a", 1));
        pairs.append(("b", 2));
        var total = 0;
        var names = "";
        for (var (name, count) in pairs) {
            total += count;
            names = names + name;
        }
        if (total != 3 || names != "ab") { return 5; }
        var trios = Array<(int, (int, Node))>();
        trios.append((1, (2, Node(3))));
        for (var (x, (y, z)) in trios) {
            if (x + y + z.value != 6) { return 6; }
        }
    }
    if (_pep_live_allocs() != before) { return 7; }
    return 0;
}
"#,
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn labeled_elements() {
    let src = r#"
struct Token {
    var at: (line: int, column: int);
}

position(): (line: int, column: int) {
    return (3, 7);
}

span(): (start: (line: int, column: int), length: int) {
    return (position(), 4);
}

column_of(p: (line: int, column: int)): int {
    return p.column;
}

test(): int {
    var p = position();
    if (p.line != 3 || p.column != 7 || p.0 != 3) { return 1; }
    if (position().column != 7) { return 2; }
    var plain: (int, int) = p;
    var back: (line: int, column: int) = plain;
    if (back.line != 3) { return 3; }
    if (column_of((1, 2)) != 2) { return 4; }
    var t = Token();
    t.at = (5, 6);
    if (t.at.column != 6) { return 5; }
    if (span().start.column != 7 || span().length != 4) { return 6; }
    var (line, column) = p;
    if (line != 3 || column != 7) { return 7; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn map_and_set_iteration() {
    let src = r#"
test(): int {
    var before = _pep_live_allocs();
    {
        var ages = HashMap<String, int>();
        ages["ada"] = 36;
        ages["alan"] = 41;
        ages["grace"] = 85;
        ages.remove("alan");
        var total = 0;
        var names = 0;
        for (var (name, age) in ages) {
            total += age;
            names += name.size as int;
        }
        if (total != 121 || names != 8) { return 1; }
        var seen = HashSet<String>();
        seen.insert("x");
        seen.insert("yy");
        var size = 0;
        for (var s in seen) {
            size += s.size as int;
        }
        if (size != 3) { return 2; }
        for (var entry in ages) {
            ages[entry.0] = entry.1 + 1;
        }
        if (ages["ada"] != 37) { return 3; }
    }
    if (_pep_live_allocs() != before) { return 4; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn inserting_while_iterating_a_map_panics() {
    let (ok, stdout) = run_exe(
        "iterate_insert",
        r#"
main(): int {
    var m = HashMap<int, int>();
    m[1] = 1;
    for (var (k, v) in m) {
        m[k + 100] = v;
    }
    return 0;
}
"#,
    );
    assert!(!ok, "expected a panic; stdout: {stdout:?}");
    assert!(stdout.contains("HashMap modified during iteration"), "stdout: {stdout:?}");
}

#[test]
fn print_writes_tuples() {
    let (ok, stdout) = run_exe(
        "print",
        r#"
main(): int {
    var s = "two";
    var t = (1, s, (2.5, true));
    print("{0} {1}", t, 7);
    print($"{(-3, "x" + "y")}");
    return 0;
}
"#,
    );
    assert!(ok, "stdout: {stdout:?}");
    assert_eq!(stdout, "(1, two, (2.5, true)) 7\n(-3, xy)\n");
}

#[test]
fn deep_copies_copy_each_element() {
    let src = r#"
struct Leaf {
    var value: int = 0;
    construct(this.value = 0) {}
}

test(): int {
    var before = _pep_live_allocs();
    {
        var n = Leaf(1);
        var a = Array<(String, (Leaf, int))>();
        a.append(("x", (n, 2)));
        a.append(("y", (n, 3)));
        var b = copy(a);
        if (b.count != 2 || b[1].0 != "y" || b[1].1.1 != 3) { return 1; }
        if (b[0].1.0 === n) { return 2; }
        if (b[0].1.0 !== b[1].1.0) { return 3; }
        b[0].1.0.value = 9;
        if (n.value != 1) { return 4; }
        var t = copy((n, 5));
        if (t.0 === n || t.0.value != 1 || t.1 != 5) { return 5; }
        var plain = copy((1, 2.5));
        if (plain.1 != 2.5) { return 6; }
    }
    if (_pep_live_allocs() != before) { return 7; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn copying_a_tuple_names_the_element_that_blocks_it() {
    let src = with_node("test(): int {\n    var p: (int, Node) = (1, Node(2));\n    var t = copy(p);\n    return 0;\n}\n");
    let Err(error) = pepper_driver::compiler::compile_with_runtime("test.pep", &src) else { panic!("copy must fail") };
    assert!(error.contains("error: cannot copy '(int, Node)' because it contains 'Node'"), "{error}");
    assert!(error.contains("note: '(int, Node)' reaches it through element 1"), "{error}");
}

#[test]
fn optional_tuples() {
    let src = r#"
find(ok: bool): (int, String)? {
    if (ok) {
        return Optional<(int, String)>.some((1, "a"));
    }
    return Optional<(int, String)>.none();
}

test(): int {
    var r = find(true);
    var labeled: (line: int, name: String)? = r;
    if (!r.is_some() || r.value().1 != "a" || labeled.value().0 != 1) { return 1; }
    if (find(false).is_some()) { return 2; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn labeled_tuple_literals() {
    let src = r#"
bounds(): (low: int, high: int) {
    return (low: 1, high: 9);
}

test(): int {
    var p = (line: 3, column: 7);
    if (p.line != 3 || p.column != 7 || p.0 != 3) { return 1; }
    var plain: (int, int) = p;
    if (plain.1 != 7) { return 2; }
    var nested = (name: "a", at: (line: 1, column: 2));
    if (nested.at.column != 2 || nested.name != "a") { return 3; }
    var (low, high) = bounds();
    if (high - low != 8 || bounds().high != 9) { return 4; }
    var sum = (x: int, y: int) => x + y;
    if (sum(p.line, p.column) != 10) { return 5; }
    var chosen = (first: p.line > 1 ? 1 : 2, second: 0);
    if (chosen.first != 1) { return 6; }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn tuple_patterns_in_match() {
    let src = r#"
enum Shape {
    Circle,
    Square,
    Line,
}

enum Doc {
    Text(text: String),
    Pair(left: int, right: int),
    Empty,
}

describe(a: Shape, b: Shape): int {
    match ((a, b)) {
        (Circle, Circle) => {
            return 1;
        }
        (Circle, other) => {
            return 10 + other.name().length;
        }
        (_, Line) => {
            return 3;
        }
        (x, _) => {
            return 20 + x.name().length;
        }
    }
}

classify(n: int, flag: bool): String {
    return match ((n, flag)) {
        (0, true) => "zero on",
        (0, false) => "zero off",
        (k, true) => "on",
        else => "other",
    };
}

docs(a: Doc, n: int): int {
    match ((a, n)) {
        (Text(t), 0) => {
            return t.length;
        }
        (Pair(l, r), k) => {
            return l + r + k;
        }
        (Text(t), k) => {
            return k;
        }
        (Empty, _) => {
            return -1;
        }
    }
}

nested(p: (int, (bool, String))): int {
    match (p) {
        (1, (true, s)) => {
            return s.length;
        }
        (_, (flag, "x")) => {
            return 7;
        }
        else => {
            return 0;
        }
    }
}

test(): int {
    if (describe(Shape.Circle, Shape.Circle) != 1) { return 1; }
    if (describe(Shape.Circle, Shape.Line) != 14) { return 2; }
    if (describe(Shape.Square, Shape.Line) != 3) { return 3; }
    if (describe(Shape.Square, Shape.Circle) != 26) { return 4; }
    if (classify(0, false) != "zero off" || classify(5, true) != "on" || classify(5, false) != "other") { return 5; }
    if (docs(Doc.Text("abc"), 0) != 3 || docs(Doc.Pair(1, 2), 3) != 6 || docs(Doc.Text("a"), 9) != 9 || docs(Doc.Empty(), 1) != -1) { return 6; }
    if (nested((1, (true, "ab"))) != 2 || nested((2, (false, "x"))) != 7 || nested((2, (false, "y"))) != 0) { return 7; }
    var pair = (3, Shape.Line);
    if (pair is (3, Line)) {
    } else {
        return 8;
    }
    if (pair is (n, Square)) { return 9; }
    if (pair is (k, Line)) {
        if (k != 3) { return 10; }
    } else {
        return 11;
    }
    return 0;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn tuple_holding_a_value_enum() {
    // A tuple element that is a value struct (here `Optional` and `Result`,
    // value enums) is copied and released through the value's own thunks.
    let src = r#"
struct Box {
    int v;
    construct(this.v = 0) {}
}

pair(): (int, Optional<Box>) {
    return (1, Optional<Box>.some(Box(4)));
}

test(): int {
    var t = pair();
    var u = t;
    var r = (2, Result<int, String>.ok(5));
    var nested = Result<Box?, String>.ok(Optional<Box>.some(Box(6)));
    return t.0 + u.1.value().v + r.1.value() + nested.value().value().v;
}
"#;
    assert_eq!(crate::support::jit_census(src), (16, 0));
}
