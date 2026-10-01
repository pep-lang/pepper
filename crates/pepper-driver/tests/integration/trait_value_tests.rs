//! Traits used as types: struct values converted to trait values, calls
//! through the vtable, destruction of the concrete type through a trait
//! value, shared_ptr refcount order and leak balance, generic traits, `for`
//! over trait-typed iterators, and the errors that keep a value out of a
//! trait-typed slot or a member out of reach.

use crate::support::jit_census as run;
use crate::support::compile_error;
use crate::support::sema;

/// Two shapes whose destructors count into `destroyed` (1 per Square, 10 per
/// Rect), so a test can tell which concrete destructor ran.
const SHAPES: &str = r#"
import async;
import [ThreadLocal] from async;

const destroyed = async.Atomic<int>(0);

trait Shape {
    int area();

    int scaled(int k) {
        return area() * k;
    }
}

struct Square {
    int side;
    construct(int side) { this.side = side; }
    destruct { destroyed.fetch_add(1); }
}

extend Square with Shape {
    int area() { return side * side; }
}

struct Rect {
    int w;
    int h;
    construct(int w, int h) { this.w = w; this.h = h; }
    destruct { destroyed.fetch_add(10); }
}

extend Rect with Shape {
    int area() { return w * h; }
}

struct Holder {
    Shape shape;
    construct(Shape s) { this.shape = s; }
}

make(n: int): Shape {
    if (n > 2) {
        return Rect(n, 2);
    }
    return Square(n);
}

int measure(Shape s) {
    return s.area();
}
"#;

fn shapes(test: &str) -> String {
    format!("{}{}", SHAPES, test)
}

#[test]
fn calls_through_locals_parameters_results_and_fields() {
    let (result, leaked) = run(&shapes(
        r#"
test(): int {
    Shape a = Square(2);
    if (a.area() != 4) { return 1; }
    if (measure(Rect(2, 3)) != 6) { return 2; }
    if (make(5).area() != 10) { return 3; }
    var h = Holder(Square(3));
    if (h.shape.area() != 9) { return 4; }
    if (measure(h.shape) != 9) { return 5; }
    return 0;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn default_trait_methods_dispatch_too() {
    let (result, leaked) = run(&shapes(
        r#"
test(): int {
    Shape s = Rect(2, 3);
    return s.scaled(2);
}
"#,
    ));
    assert_eq!(result, 12);
    assert_eq!(leaked, 0);
}

#[test]
fn the_last_release_runs_the_concrete_destructor() {
    let (result, leaked) = run(&shapes(
        r#"
test(): int {
    {
        Shape s = Rect(1, 1);
    }
    if (destroyed.load() != 10) { return 1; }
    Shape b = make(1);
    b = make(4);
    if (destroyed.load() != 11) { return 2; }
    var h = Holder(Square(1));
    h.shape = b;
    if (destroyed.load() != 12) { return 3; }
    h = Holder(Square(2));
    if (destroyed.load() != 12) { return 4; }
    b = __null;
    if (destroyed.load() != 22) { return 5; }
    return 0;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn refcounts_follow_shared_ptr_copies() {
    let (result, leaked) = run(&shapes(
        r#"
int count_inside(Shape s, Square sq) {
    return __refcount<Square>(sq);
}

test(): int {
    var sq = Square(2);
    if (__refcount<Square>(sq) != 1) { return 1; }
    Shape a = sq;
    if (__refcount<Square>(sq) != 2) { return 2; }
    if (__refcount<Shape>(a) != 2) { return 3; }
    # Both by-value parameters hold a reference during the call.
    if (count_inside(a, sq) != 4) { return 4; }
    if (__refcount<Square>(sq) != 2) { return 5; }
    {
        Shape b = a;
        if (__refcount<Square>(sq) != 3) { return 6; }
    }
    a = a;
    if (__refcount<Square>(sq) != 2) { return 7; }
    a = __null;
    if (__refcount<Square>(sq) != 1) { return 8; }
    return 0;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn discarded_and_receiver_temporaries_are_released() {
    let (result, leaked) = run(&shapes(
        r#"
test(): int {
    make(1);
    make(3);
    var total = make(2).area() + measure(make(4));
    if (destroyed.load() != 22) { return 1; }
    return total;
}
"#,
    ));
    assert_eq!(result, 12);
    assert_eq!(leaked, 0);
}

#[test]
fn trait_values_compare_by_object() {
    let (result, leaked) = run(&shapes(
        r#"
test(): int {
    var sq = Square(2);
    Shape a = sq;
    Shape b = sq;
    Shape c = Square(2);
    Shape n = __null;
    if (a != b) { return 1; }
    if (a == c) { return 2; }
    if (a != sq) { return 3; }
    if (n != __null) { return 4; }
    if (a == __null) { return 5; }
    return 0;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn arrays_of_trait_values() {
    let (result, leaked) = run(&shapes(
        r#"
test(): int {
    var shapes = Array<Shape>();
    shapes.append(Square(3));
    shapes.append(Rect(2, 5));
    shapes.insert(0, Square(1));
    var total = 0;
    for (var s in shapes) {
        total = total + s.area();
    }
    if (total != 20) { return 1; }
    shapes.swap(0, 2);
    if (shapes[0].area() != 10) { return 2; }
    shapes.reverse();
    if (shapes[2].area() != 10) { return 3; }
    Shape removed = shapes.remove_at(0);
    if (removed.area() != 1) { return 4; }
    if (destroyed.load() != 0) { return 5; }
    shapes[0] = Square(4);
    if (destroyed.load() != 1) { return 6; }
    if (shapes.find(removed) != -1) { return 7; }
    shapes.clear();
    if (destroyed.load() != 12) { return 8; }
    return 0;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn ternaries_globals_maps_and_function_types() {
    let (result, leaked) = run(&shapes(
        r#"
# A trait value is not thread-safe, so a module-scope one lives in a
# ThreadLocal (set on this thread, cleared before the leak check).
const global_shape = ThreadLocal<Shape>();

int apply(f: (Shape) => int, s: Shape) {
    return f(s);
}

struct Labeled {
    int id;
    construct(int id) { this.id = id; }

    Shape as_shape() {
        Shape s = Square(id);
        return s;
    }
}

test(): int {
    var flag = true;
    # Each arm converts with its own vtable.
    Shape t = flag ? Square(2) : Rect(3, 3);
    Shape u = !flag ? Square(2) : Rect(3, 3);
    if (t.area() + u.area() != 13) { return 1; }
    global_shape.set(Square(5));
    with (var shape = global_shape.enter()) {
        if (shape.area() != 25) { return 2; }
    }
    global_shape.clear();
    var m = HashMap<String, Shape>();
    m["a"] = Square(3);
    m["b"] = Rect(1, 2);
    if (m["a"].area() + m["b"].area() != 11) { return 3; }
    if (apply(measure, Rect(2, 2)) != 4) { return 4; }
    if (Labeled(6).as_shape().area() != 36) { return 5; }
    return 0;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn generic_traits_specialize_like_structs() {
    let (result, leaked) = run(r#"
trait Getter<T> {
    T get();
}

struct Box<T> {
    T value;
    construct(T v) { this.value = v; }
}

extend Box<T> with Getter<T> {
    T get() { return value; }
}

int read(Getter<int> g) {
    return g.get();
}

test(): int {
    var b = Box<int>(5);
    Getter<String> s = Box<String>("hi");
    return read(b) + s.get().length();
}
"#);
    assert_eq!(result, 7);
    assert_eq!(leaked, 0);
}

#[test]
fn for_loops_drive_trait_typed_iterators_and_iterables() {
    let (result, leaked) = run(r#"
struct Countdown {
    int n;
    construct(int n) { this.n = n; }

    bool next() {
        if (n == 0) { return false; }
        n = n - 1;
        return true;
    }

    int current() { return n; }
}

extend Countdown with Iterator<int> {}

struct Below {
    int n;
    construct(int n) { this.n = n; }
}

extend Below with Iterable<int> {
    iterate(): Iterator<int> {
        return Countdown(n);
    }
}

numbers(): Iterator<int> {
    return Countdown(4);
}

test(): int {
    var sum = 0;
    for (var x in numbers()) {
        sum = sum + x;
    }
    Iterable<int> source = Below(3);
    for (var x in source) {
        sum = sum + x * 10;
    }
    return sum;
}
"#);
    assert_eq!(result, 36);
    assert_eq!(leaked, 0);
}

/// An iterable whose `iterate()` returns its concrete iterator type, which
/// `Iterable<int>` declares as `Iterator<int>`.
const EVENS: &str = r#"
struct Evens {
    int limit;
    construct(this.limit = 0) {}

    EvensIterator iterate() {
        var it = EvensIterator();
        it.limit = limit;
        it.now = -2;
        return it;
    }
}

struct EvensIterator {
    int limit;
    int now;

    bool next() {
        now = now + 2;
        return now < limit;
    }

    int current() { return now; }
}

extend EvensIterator with Iterator<int> {}
extend Evens with Iterable<int> {}
"#;

#[test]
fn a_struct_result_converts_where_the_trait_returns_a_trait() {
    let (result, leaked) = run(&format!(
        "{}{}",
        EVENS,
        r#"
test(): int {
    var total = 0;
    # Static: the loop drives EvensIterator directly.
    for (var n in Evens(6)) {
        total = total + n;
    }
    # Dynamic: iterate() through the vtable yields an Iterator<int>.
    Iterable<int> evens = Evens(10);
    for (var n in evens) {
        total = total + n * 10;
    }
    Iterator<int> it = evens.iterate();
    it.next();
    it.next();
    return total + it.current() * 1000;
}
"#
    ));
    assert_eq!(result, 6 + 200 + 2000);
    assert_eq!(leaked, 0);
}

#[test]
fn a_covariant_result_must_conform() {
    let error = compile_error(
        "struct Plain {\n    construct() {}\n}\nstruct Source {\n    construct() {}\n    Plain iterate() { return Plain(); }\n}\nextend Source with Iterable<int> {}\ntest(): int { return 0; }\n",
    );
    assert!(
        error.contains("error: 'iterate' in 'Source' returns 'Plain', which does not conform to 'Iterator<int>' as trait 'Iterable<int>' requires"),
        "{}",
        error
    );
}

const ERRORS: &str = r#"
trait Shape {
    int area();
    static this unit();
}

trait Named {
    int id();
}

struct Square {
    int side;
    construct(int side) { this.side = side; }
}

extend Square with Shape {
    int area() { return side * side; }
    static Square unit() { return Square(1); }
}

struct Circle {
    int r;
    construct(int r) { this.r = r; }

    int area() { return 3 * r * r; }
}
"#;

#[test]
fn a_struct_must_declare_the_trait() {
    let error = compile_error(&format!(
        "{}{}",
        ERRORS, "test(): int { Shape s = Circle(1); return 0; }\n"
    ));
    assert!(
        error.contains("error: 'Circle' does not conform to trait 'Shape'"),
        "{}",
        error
    );
    assert!(
        error.contains("note: declare it with 'extend Circle with Shape'"),
        "{}",
        error
    );
    let error = compile_error(&format!(
        "{}{}",
        ERRORS, "int f(Shape s) { return 0; }\ntest(): int { return f(Circle(1)); }\n"
    ));
    assert!(
        error.contains("error: 'Circle' does not conform to trait 'Shape'"),
        "{}",
        error
    );
}

#[test]
fn only_dispatchable_members_are_called_through_a_value() {
    let error = compile_error(&format!(
        "{}{}",
        ERRORS, "test(): int { Shape s = Square(1); var t = s.unit(); return 0; }\n"
    ));
    assert!(
        error.contains(
            "error: 'unit' is static and cannot be called on a value of trait type 'Shape'"
        ),
        "{}",
        error
    );
    let error = compile_error(&format!(
        "{}{}",
        ERRORS, "test(): int { Shape s = Square(1); return s.perimeter(); }\n"
    ));
    assert!(
        error.contains("error: no member named 'perimeter' in 'Shape'"),
        "{}",
        error
    );
}

#[test]
fn one_trait_does_not_convert_to_another() {
    let error = compile_error(&format!(
        "{}{}",
        ERRORS, "test(): int { Shape s = Square(1); Named n = s; return 0; }\n"
    ));
    assert!(
        error.contains("error: cannot convert a value of trait type 'Shape' to trait type 'Named'"),
        "{}",
        error
    );
}

#[test]
fn atomics_reject_trait_values() {
    // Atomic<T: Shared>, and a trait value is not thread-safe: the
    // constraint rejects it before codegen's own guard is reached.
    let error = sema(&shapes(
        "test(): int {\n    var a = async.Atomic<Shape>();\n    a.store(Square(1));\n    return 0;\n}\n",
    ))
    .expect_err("expected a thread-safety error");
    assert!(
        error.contains("error: 'Shape' does not conform to 'Shared', required by 'T' in 'Atomic'"),
        "{}",
        error
    );
}

#[test]
fn an_implementation_must_match_the_declared_signature() {
    let error = compile_error(
        "trait Shape {\n    int area();\n}\nstruct Square {\n    int side;\n}\nextend Square with Shape {\n    long area() { return 1; }\n}\ntest(): int { return 0; }\n",
    );
    assert!(error.contains("error: 'area' in 'Square' has type '() => long', but trait 'Shape' declares '() => int'"), "{}", error);
}

#[test]
fn a_default_method_calls_the_function_its_trait_author_meant() {
    // S happens to have its own `helper` and field `count`, which T's author
    // could not know about: `helper()` and `count` in the default are the
    // top-level function and variable.
    let (result, leaked) = run(r#"
const count = 10;
helper(): int { return 1; }
trait T {
    area(): int;
    total(): int { return helper() + count + area(); }
}
struct S {
    var count: int;
    construct() { count = 500; }
    helper(): int { return 100; }
}
extend S with T { area(): int { return 1000; } }
test(): int {
    var s = S();
    T t = S();
    return s.total() + t.total();
}
"#);
    // 1 + 10 + 1000, twice: directly and through the trait value.
    assert_eq!(result, 2022);
    assert_eq!(leaked, 0);
}

#[test]
fn a_generic_extension_names_another_generic_type_over_its_parameter() {
    // `Maybe<E>` in a generic trait's signature and in the generic
    // extension's body is unbound until `Constant<int>` specializes it.
    let (result, leaked) = run(r#"
enum Maybe<T> {
    Some(value: T),
    Nothing,
}
trait Source<E> {
    take(): Maybe<E>;
}
struct Constant<E> {
    const _value: E;
    construct(value: E) { _value = value; }
}
extend Constant<E> with Source<E> {
    take(): Maybe<E> { return Maybe<E>.Some(_value); }
}
unwrap(m: Maybe<int>): int {
    match (m) {
        Some(v) => { return v; }
        Nothing => { return -1; }
    }
}
test(): int {
    Source<int> s = Constant<int>(4);
    var m = s.take();
    return unwrap(m) + unwrap(Constant<int>(30).take());
}
"#);
    assert_eq!(result, 34);
    assert_eq!(leaked, 0);
}

#[test]
fn a_trait_value_call_infers_a_struct_result() {
    // `var b = s.take()` takes the trait instance's return type, with the
    // trait's type arguments substituted.
    let (result, leaked) = run(r#"
struct Box<T> {
    var value: T;
    construct(value: T) { this.value = value; }
}
trait Source<E> {
    take(): Box<E>;
}
struct Counter {
    var n: int;
    construct() { n = 7; }
}
extend Counter with Source<int> {
    take(): Box<int> { return Box<int>(n); }
}
test(): int {
    Source<int> s = Counter();
    var b = s.take();
    return b.value;
}
"#);
    assert_eq!(result, 7);
    assert_eq!(leaked, 0);
}

/// A default body's string literals are Strings, as in any other method:
/// they were left raw (`apply_extensions` copies the body after literals are
/// converted), so a default returning one crashed at run time and one
/// concatenating one failed with "no member named '+' in ''" (#242).
const NAMED: &str = r#"
trait Named {
    String name();

    String label() {
        return "pet";
    }

    String greet() {
        return "hi " + name();
    }
}

struct Dog {
    construct() {}
}

extend Dog with Named {
    String name() { return "dog"; }
}
"#;

#[test]
fn a_default_method_returns_a_string_literal() {
    let source = format!(
        "{NAMED}\nint test() {{\n    var d = Dog();\n    return d.label() == \"pet\" ? 0 : 1;\n}}\n"
    );
    assert_eq!(run(&source), (0, 0));
}

#[test]
fn a_default_method_concatenates_a_string_literal() {
    let source = format!(
        "{NAMED}\nint test() {{\n    var d = Dog();\n    return d.greet() == \"hi dog\" ? 0 : 1;\n}}\n"
    );
    assert_eq!(run(&source), (0, 0));
}

#[test]
fn a_default_method_with_a_string_literal_runs_through_a_trait_value() {
    let source = format!(
        "{NAMED}\nint test() {{\n    Named n = Dog();\n    return n.label() + n.greet() == \"pethi dog\" ? 0 : 1;\n}}\n"
    );
    assert_eq!(run(&source), (0, 0));
}
