//! Methods, constructors and generic functions used as values: `p.norm`,
//! `Point.norm`, `Point`, `identity<int>`. Each becomes a closure, so these
//! also check the leak census for the receiver a bound method captures.

use crate::support::jit_census as run;
use crate::support::compile_error;

const POINT: &str = r#"
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
    norm(): int { return x + y; }
    shifted(dx: int): int { return x + dx; }
    static origin(): Point { return Point(0, 0); }
}
"#;

fn with_point(body: &str) -> String {
    format!("{}\n{}", POINT, body)
}

#[test]
fn bound_method() {
    let src = with_point(
        r#"
test(): int {
    var p = Point(1, 2);
    var norm = p.norm;
    var shift: (int) => int = p.shifted;
    return norm() * 10 + shift(4);
}
"#,
    );
    assert_eq!(run(&src), (35, 0));
}

#[test]
fn bound_method_keeps_its_receiver_alive() {
    let src = with_point(
        r#"
reader(): () => int {
    var p = Point(3, 4);
    return p.norm;
}

test(): int {
    var read = reader();
    var copy = read;
    return read() + copy();
}
"#,
    );
    assert_eq!(run(&src), (14, 0));
}

#[test]
fn bound_method_of_a_temporary_and_of_this() {
    let src = with_point(
        r#"
struct Counter {
    int count;
    construct(this.count = 0) {}
    bump(): int { count = count + 1; return count; }
    bumper(): () => int { return this.bump; }
}

apply(f: (int) => int, x: int): int { return f(x); }

test(): int {
    var c = Counter();
    var bump = c.bumper();
    bump();
    bump();
    return apply(Point(5, 0).shifted, 1) * 10 + c.count;
}
"#,
    );
    assert_eq!(run(&src), (62, 0));
}

#[test]
fn unbound_and_static_methods() {
    let src = with_point(
        r#"
struct Box<T> {
    T value;
    construct(T v) { value = v; }
    get(): T { return value; }
}

test(): int {
    var norm: (Point) => int = Point.norm;
    var shifted = Point.shifted;
    var origin = Point.origin;
    var get = Box<int>.get;
    return norm(Point(1, 2)) + shifted(Point(10, 0), 5) + origin().x + get(Box<int>(100));
}
"#,
    );
    assert_eq!(run(&src), (118, 0));
}

#[test]
fn constructors_as_values() {
    let src = with_point(
        r#"
struct Box<T> {
    T value;
    construct(T v) { value = v; }
}

build(make: (int, int) => Point): Point { return make(3, 4); }

test(): int {
    var p = build(Point);
    var make_box = Box<int>;
    var local_type_name = Point;
    return p.x * 100 + make_box(7).value * 10 + local_type_name(1, 1).y;
}
"#,
    );
    assert_eq!(run(&src), (371, 0));
}

#[test]
fn generic_function_specialization() {
    let src = r#"
identity<T>(x: T): T { return x; }
larger<T>(a: T, b: T): T { return a > b ? a : b; }

apply(f: (int, int) => int, a: int, b: int): int { return f(a, b); }

test(): int {
    var id = identity<int>;
    return id(2) + apply(larger<int>, 3, 40);
}
"#;
    assert_eq!(run(src), (42, 0));
}

#[test]
fn methods_in_arrays_and_through_traits() {
    let src = r#"
trait Shape {
    area(): int;
}

struct Square {
    int side;
    construct(this.side = 0) {}
    area(): int { return side * side; }
}

extend Square with Shape {}

extend Square {
    perimeter(): int { return 4 * side; }
}

test(): int {
    var s = Square(3);
    var shape: Shape = s;
    var measures = Array<() => int>();
    measures.append(s.area);
    measures.append(s.perimeter);
    measures.append(shape.area);
    return measures[0]() + measures[1]() + measures[2]();
}
"#;
    assert_eq!(run(src), (30, 0));
}

#[test]
fn void_method_reference() {
    let src = r#"
struct Counter {
    int count;
    construct(this.count = 0) {}
    bump() { count = count + 1; }
}

test(): int {
    var c = Counter();
    var bump = c.bump;
    bump();
    bump();
    return c.count;
}
"#;
    assert_eq!(run(src), (2, 0));
}

#[test]
fn storing_a_method_of_this_in_a_field_is_an_error() {
    let err = compile_error(
        r#"
struct Widget {
    int size;
    () => int measure;
    area(): int { return size * size; }
    setup() {
        this.measure = this.area;
    }
}

test(): int { return 0; }
"#,
    );
    assert!(err.contains("storing a method of 'this' in field 'measure' of 'this' creates a reference cycle"), "{}", err);
}
