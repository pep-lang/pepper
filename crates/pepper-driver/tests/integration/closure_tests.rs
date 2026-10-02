//! Closure literals: `(x: int) => x * 2`. Type inference from the slot a
//! closure flows into, by-value captures (locals, parameters, `this`),
//! nested closures, the "captured locals are never assigned" rule, and the
//! leak census for every way a closure is created, copied and dropped.

use crate::support::jit_census as run;
use crate::support::compile_error;

#[test]
fn annotated_literal_in_a_local() {
    let src = r#"
test(): int {
    var double = (x: int) => x * 2;
    return double(21);
}
"#;
    assert_eq!(run(src), (42, 0));
}

#[test]
fn parameter_types_come_from_the_variable_type() {
    let src = r#"
test(): int {
    var add: (int, int) => int = (a, b) => a + b;
    return add(40, 2);
}
"#;
    assert_eq!(run(src), (42, 0));
}

#[test]
fn block_body_with_return_type() {
    let src = r#"
test(): int {
    var clamp = (x: int, low: int, high: int): int => {
        if x < low { return low; }
        if x > high { return high; }
        return x;
    };
    return clamp(5, 0, 3) * 10 + clamp(-4, 0, 3);
}
"#;
    assert_eq!(run(src), (30, 0));
}

#[test]
fn capture_a_local_and_a_parameter() {
    let src = r#"
make_adder(n: int): (int) => int {
    return (x) => x + n;
}

test(): int {
    var base = 10;
    var add_base = (x: int) => x + base;
    var add_five = make_adder(5);
    return add_base(1) + add_five(20);
}
"#;
    assert_eq!(run(src), (36, 0));
}

#[test]
fn closure_as_an_argument() {
    let src = r#"
apply(f: (int) => int, x: int): int { return f(x); }

test(): int {
    var offset = 3;
    return apply((x) => x * x + offset, 4);
}
"#;
    assert_eq!(run(src), (19, 0));
}

#[test]
fn captured_struct_is_shared_and_released() {
    let src = r#"
struct Counter {
    int count;
    construct(this.count = 0) {}
    bump() { count = count + 1; }
}

test(): int {
    var counter = Counter();
    var bump = () => counter.bump();
    bump();
    bump();
    bump();
    return counter.count;
}
"#;
    assert_eq!(run(src), (3, 0));
}

#[test]
fn closure_outlives_the_captured_local() {
    let src = r#"
struct Box {
    int value;
    construct(this.value = 0) {}
}

make_reader(v: int): () => int {
    var box = Box(v);
    return () => box.value;
}

test(): int {
    var read = make_reader(7);
    var again = read;
    return read() + again();
}
"#;
    assert_eq!(run(src), (14, 0));
}

#[test]
fn discarded_and_temporary_closures_are_released() {
    let src = r#"
struct Box {
    int value;
    construct(this.value = 0) {}
}

apply(f: (int) => int, x: int): int { return f(x); }

test(): int {
    var box = Box(2);
    (x: int) => x + box.value;
    var total = apply((x) => x * box.value, 5);
    total = total + ((y: int) => y + box.value)(1);
    return total;
}
"#;
    assert_eq!(run(src), (13, 0));
}

#[test]
fn closures_in_fields_and_arrays() {
    let src = r#"
struct Button {
    () => int on_click;
    click(): int { return on_click(); }
}

test(): int {
    var clicks = 5;
    var b = Button();
    b.on_click = () => clicks * 2;
    var ops = Array<(int) => int>();
    ops.append((x) => x + 1);
    ops.append((x) => x * clicks);
    return b.click() + ops[0](1) + ops[1](2);
}
"#;
    assert_eq!(run(src), (22, 0));
}

#[test]
fn capture_this_in_a_method() {
    let src = r#"
struct Scaler {
    int factor;
    construct(this.factor = 1) {}
    scale(x: int): int { return x * factor; }
    scaler(): (int) => int { return (x) => scale(x) + this.factor - factor; }
    multiplier(): (int) => int { return (x) => x * factor; }
}

test(): int {
    var s = Scaler(3);
    var f = s.scaler();
    var g = s.multiplier();
    return f(2) * 10 + g(4);
}
"#;
    assert_eq!(run(src), (72, 0));
}

#[test]
fn nested_closures_capture_through() {
    let src = r#"
test(): int {
    var a = 1;
    var outer = (b: int) => {
        var inner = (c: int) => a + b + c;
        return inner(100);
    };
    return outer(10);
}
"#;
    assert_eq!(run(src), (111, 0));
}

#[test]
fn curried_closure() {
    let src = r#"
test(): int {
    var add: (int) => (int) => int = (a) => (b) => a + b;
    var add2 = add(2);
    return add2(40);
}
"#;
    assert_eq!(run(src), (42, 0));
}

#[test]
fn void_closure_with_an_expression_body() {
    let src = r#"
struct Counter {
    int count;
    construct(this.count = 0) {}
}

test(): int {
    var c = Counter();
    var bump: () => void = () => c.count++;
    bump();
    bump();
    return c.count;
}
"#;
    assert_eq!(run(src), (2, 0));
}

#[test]
fn closure_inside_a_generic_function() {
    let src = r#"
apply<T>(f: (T) => T, x: T): T { return f(x); }

twice<T>(f: (T) => T): (T) => T {
    return (x) => f(f(x));
}

test(): int {
    var inc = (x: int) => x + 1;
    var add_two = twice<int>(inc);
    return apply<int>(add_two, 40);
}
"#;
    assert_eq!(run(src), (42, 0));
}

#[test]
fn closure_capturing_a_function_value() {
    let src = r#"
square(x: int): int { return x * x; }

test(): int {
    var f = square;
    var g = (x: int) => f(x) + 1;
    return g(4);
}
"#;
    assert_eq!(run(src), (17, 0));
}

#[test]
fn closure_capturing_a_string() {
    let src = r#"
test(): int {
    var greeting = "hello";
    var length = () => greeting.size;
    return length();
}
"#;
    assert_eq!(run(src), (5, 0));
}

// ── Errors ────────────────────────────────────────────────────────────────────

#[test]
fn assigning_a_captured_local_after_is_an_error() {
    let err = compile_error(
        r#"
test(): int {
    var count = 0;
    var f = () => count;
    count = 5;
    return f();
}
"#,
    );
    assert!(err.contains("cannot assign to 'count' because a closure captures it"), "{}", err);
    assert!(err.contains("test.pep:5:5"), "{}", err);
    assert!(err.contains("note: captured here"), "{}", err);
}

#[test]
fn assigning_a_captured_local_inside_is_an_error() {
    let err = compile_error(
        r#"
test(): int {
    var count = 0;
    var f = () => { count = count + 1; return count; };
    return f();
}
"#,
    );
    assert!(err.contains("cannot assign to 'count' because a closure captures it"), "{}", err);
}

#[test]
fn incrementing_a_captured_local_is_an_error() {
    let err = compile_error(
        r#"
test(): int {
    var i = 0;
    var f = () => i;
    i++;
    return f();
}
"#,
    );
    assert!(err.contains("cannot assign to 'i' because a closure captures it"), "{}", err);
}

#[test]
fn uninferable_parameter_is_an_error() {
    let err = compile_error(
        r#"
test(): int {
    var f = (x) => x;
    return 0;
}
"#,
    );
    assert!(err.contains("cannot infer the type of parameter 'x'"), "{}", err);
    assert!(err.contains("test.pep:3:14"), "{}", err);
}

#[test]
fn mismatched_closure_is_an_error() {
    let err = compile_error(
        r#"
test(): int {
    var f: (int) => int = (x: String) => 1;
    return 0;
}
"#,
    );
    assert!(err.contains("cannot initialize variable 'f' of type '(int) => int' with a value of type '(String) => int'"), "{}", err);
}

#[test]
fn storing_a_this_capturing_closure_in_a_field_is_an_error() {
    let err = compile_error(
        r#"
struct Widget {
    int size;
    () => int measure;
    setup() {
        measure = () => size * 2;
    }
}

test(): int { return 0; }
"#,
    );
    assert!(err.contains("storing a closure that captures 'this' in field 'measure' of 'this' creates a reference cycle"), "{}", err);
    assert!(err.contains("test.pep:6:9"), "{}", err);
}

#[test]
fn closure_in_an_extension_method() {
    let src = r#"
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
}

extend Point {
    adder(): (int) => int { return (d) => x + y + d; }
}

test(): int {
    var p = Point(1, 2);
    var add = p.adder();
    return add(10);
}
"#;
    assert_eq!(run(src), (13, 0));
}

#[test]
fn closure_in_a_generic_struct_method() {
    let src = r#"
struct Holder<T> {
    T value;
    construct(T initial) { value = initial; }
    getter(): () => T { return () => value; }
}

test(): int {
    var h = Holder<int>(9);
    var get = h.getter();
    var s = Holder<String>("abc");
    var get_s = s.getter();
    return get() + get_s().size;
}
"#;
    assert_eq!(run(src), (12, 0));
}

#[test]
fn module_scope_closure() {
    let src = r#"
const triple: shared (int) => int = (x: int) => x * 3;

test(): int { return triple(14); }
"#;
    assert_eq!(run(src), (42, 0));
}

#[test]
fn method_argument_takes_its_type_from_the_parameter() {
    let src = r#"
struct Numbers {
    int a;
    int b;
    construct(this.a = 0, this.b = 0) {}
    combine(f: (int, int) => int): int { return f(a, b); }
}

test(): int {
    var n = Numbers(6, 7);
    return n.combine((x, y) => x * y);
}
"#;
    assert_eq!(run(src), (42, 0));
}

#[test]
fn closures_parse_next_to_parenthesized_expressions() {
    let src = r#"
test(): int {
    var a = 2;
    var b = (a + 1) * 2;
    var c = a > 1 ? (b) : (a);
    var f = (x: int) => (x + a) * 2;
    return b * 100 + c * 10 + f(0) - 4;
}
"#;
    assert_eq!(run(src), (660, 0));
}

#[test]
fn explicit_generic_call_types_the_closure() {
    let src = r#"
apply<T>(f: (T) => T, x: T): T { return f(x); }

test(): int {
    var widened = (x: int): long => x;
    return apply<int>((x) => x + 1, 2) + (widened(3) as int);
}
"#;
    assert_eq!(run(src), (6, 0));
}
