//! Collection literals: `[a, b]` arrays, `[k: v]` maps and `[:]`, and
//! arrays converting to sets. Each snippet is compiled with the runtime
//! prelude and JIT-executed through the entry function `test`; each checks
//! that every reference it made was released.

use crate::support::{compile_jit_with_runtime, jit_census};

#[test]
fn array_literals() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    construct(x: int) { this.x = x; }
}
check(): int {
    var a = [1, 2, 3];
    if (!(a.count == 3 && a[2] == 3)) { return -1; }
    var words = ["===", "!==", "=>",];
    if (!(words.count == 3 && words[1] == "!==")) { return -2; }
    var nested = [[1, 2], [3]];
    if (!(nested[1][0] == 3)) { return -3; }
    var points = [Point(1), Point(2)];
    if (!(points[1].x == 2)) { return -4; }
    long total = 0;
    for (var n in [10, 20]) { total = total + n; }
    if (!(total == 30)) { return -5; }
    if (!([5].count == 1)) { return -6; }
    var longs = [1 as long, 2];
    if (!(longs[1] == 2)) { return -7; }
    return 0;
}

test(): int {
    var before = _pep_live_allocs();
    var result = check();
    if (result != 0) {
        return result;
    }
    if (_pep_live_allocs() != before) {
        return -100;
    }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn literals_take_the_slot_type() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
trait Shape {
    area(): int;
}
struct Square {
    int side;
    construct(side: int) { this.side = side; }
}
extend Square with Shape {
    area(): int { return side * side; }
}
struct Circle {
    construct() {}
}
extend Circle with Shape {
    area(): int { return 3; }
}
total(values: long[]): long {
    long sum = 0;
    for (var v in values) { sum = sum + v; }
    return sum;
}
make(): long[] {
    return [4, 5];
}
check(): int {
    if (!(total([1, 2, 3]) == 6)) { return -1; }
    if (!(make()[1] == 5)) { return -2; }
    long[] a = [1, 2];
    a = [7];
    if (!(a[0] == 7)) { return -3; }
    Shape[] shapes = [Square(2), Circle()];
    if (!(shapes[0].area() + shapes[1].area() == 7)) { return -4; }
    HashSet<String> keywords = ["if", "else", "if"];
    if (!(keywords.count == 2 && keywords.contains("else"))) { return -5; }
    return 0;
}

test(): int {
    var before = _pep_live_allocs();
    var result = check();
    if (result != 0) {
        return result;
    }
    if (_pep_live_allocs() != before) {
        return -100;
    }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn map_and_set_literals() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
count_of(m: HashMap<String, long>): long {
    return m.count as long;
}
check(): int {
    var ages = ["Ada": 36, "Alan": 41];
    if (!(ages.count == 2 && ages["Alan"] == 41)) { return -1; }
    HashMap<String, long> big = ["x": 1];
    if (!(big["x"] == 1)) { return -2; }
    HashMap<String, int> none = [:];
    if (!(none.count == 0)) { return -3; }
    if (!(count_of(["a": 1, "b": 2, "a": 3]) == 2)) { return -4; }
    var dup = ["k": 1, "k": 2];
    if (!(dup["k"] == 2)) { return -5; }
    HashSet<String> empty_set = [];
    if (!(empty_set.count == 0)) { return -6; }
    long[] empty = [];
    if (!(empty.count == 0)) { return -7; }
    var table = ["ops": ["+", "-"], "cmp": ["<"]];
    if (!(table["ops"][1] == "-")) { return -8; }
    var pick = true ? 1 : 2;
    var t = [pick > 0 ? "a" : "b": 1];
    if (!(t["a"] == 1)) { return -9; }
    return 0;
}

test(): int {
    var before = _pep_live_allocs();
    var result = check();
    if (result != 0) {
        return result;
    }
    if (_pep_live_allocs() != before) {
        return -100;
    }
    return 0;
}"#
        ),
        0
    );
}

/// A field default calling an overloaded constructor picks its member
/// (`HashSet` has two constructors).
#[test]
fn overloaded_constructor_in_field_default() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Keywords {
    HashSet<String> words = HashSet<String>();
    construct() {}
}
test(): int {
    var k = Keywords();
    k.words.insert("if");
    return k.words.count as int - 1;
}"#
        ),
        0
    );
}

/// Literals long enough that one call chain per element would overflow the
/// stack: built as a tree of short chains (`pepper_sema::literals`), they
/// compile on a test thread's default 2 MB stack, keep their order, convert
/// to the slot's type, and release everything.
#[test]
fn long_literals_compile_on_a_small_stack() {
    let numbers = |n: usize| (0..n).map(|i| i.to_string()).collect::<Vec<_>>().join(", ");
    let entries = |n: usize| (0..n).map(|i| format!("{}: {}", i, i * 2)).collect::<Vec<_>>().join(", ");
    let words = (0..300).map(|i| format!("\"w{}\"", i)).collect::<Vec<_>>().join(", ");
    let squares = (0..300).map(|i| format!("Square({})", i)).collect::<Vec<_>>().join(", ");
    let source = format!(
        r#"
trait Shape {{
    area(): int;
}}
struct Square {{
    int side;
    construct(side: int) {{ this.side = side; }}
    area(): int {{ return side * side; }}
}}
extend Square with Shape;
check(): int {{
    var big = [{big}];
    if (big.count != 30000) {{ return -1; }}
    for (var i in 0..big.count) {{
        if (big[i] != i as int) {{ return -2; }}
    }}
    long[] longs = [{numbers}];
    if (!(longs.count == 300 && longs[299] == 299)) {{ return -3; }}
    var words = [{words}];
    if (!(words.count == 300 && words[0] == "w0" && words[299] == "w299")) {{ return -4; }}
    Shape[] shapes = [{squares}];
    if (!(shapes.count == 300 && shapes[17].area() == 289)) {{ return -5; }}
    var map = [{entries}];
    if (!(map.count == 300 && map[299] == 598)) {{ return -6; }}
    HashMap<long, long> longs_map = [{entries}];
    if (!(longs_map.count == 300 && longs_map[5] == 10)) {{ return -7; }}
    var nested = [[{numbers}], [{numbers}]];
    if (!(nested[1][299] == 299)) {{ return -8; }}
    return 0;
}}

test(): int {{
    return check();
}}"#,
        big = numbers(30000),
        numbers = numbers(300),
        entries = entries(300),
    );
    // The test thread's default size, set explicitly so RUST_MIN_STACK
    // cannot hide a regression.
    let (result, leaked) = std::thread::Builder::new()
        .stack_size(2 << 20)
        .spawn(move || jit_census(&source))
        .expect("spawn a test thread")
        .join()
        .unwrap_or_else(|panic| std::panic::resume_unwind(panic));
    assert_eq!((result, leaked), (0, 0));
}
