//! Properties (`docs/src/language/properties.md`): `var name: T { get; set; }`
//! members read and written like fields, through accessors that may run code.

use crate::support::{compile_error, compile_jit_with_runtime, jit_census};

#[test]
fn auto_property_reads_and_writes_its_storage() {
    let source = r#"
struct Point {
    var x: int { get; set; }
    var y: int { get; set; } = 5;
}
test(): int {
    var p = Point();
    p.x = 3;
    p.y += 1;
    p.x++;
    return p.x * 10 + p.y;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 46);
}

#[test]
fn custom_accessors_run_and_use_field() {
    let source = r#"
struct Temperature {
    var sets: int;
    var celsius: int {
        get;
        set {
            sets += 1;
            field = value;
        }
    }
    var fahrenheit: int {
        get {
            return celsius * 9 / 5 + 32;
        }
        set {
            celsius = (value - 32) * 5 / 9;
        }
    }
    var doubled: int {
        get {
            return field * 2;
        }
        set {
            field = value / 2;
        }
    }
}
test(): int {
    var t = Temperature();
    t.fahrenheit = 212;
    if (t.celsius != 100 || t.sets != 1) {
        return 1;
    }
    t.celsius = 0;
    if (t.fahrenheit != 32 || t.sets != 2) {
        return 2;
    }
    t.doubled = 10;
    t.doubled += 4;
    return t.doubled;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 14);
}

#[test]
fn get_only_property_is_set_by_its_own_code() {
    let source = r#"
struct Account {
    var balance: long { get; }
    var deposits: int { get; } = 0;
    construct(opening: long) {
        balance = opening;
    }
    deposit(amount: long) {
        balance += amount;
        deposits++;
    }
}
test(): int {
    var a = Account(10);
    a.deposit(5);
    a.deposit(7);
    return (a.balance as int) * 10 + a.deposits;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 222);
}

#[test]
fn bare_property_in_methods_is_a_member() {
    let source = r#"
struct Counter {
    var _n: int;
    var count: int {
        get {
            return _n;
        }
        set {
            _n = value;
        }
    }
    bump(): int {
        count = count + 1;
        count += 2;
        return count;
    }
}
test(): int {
    return Counter().bump();
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 3);
}

#[test]
fn constructor_parameter_assigns_through_set() {
    let source = r#"
struct Named {
    var calls: int;
    var name: String {
        get;
        set {
            calls += 1;
            field = value;
        }
    }
    construct(this.name = "x") {}
}
test(): int {
    var n = Named("abc");
    return n.calls * 10 + (n.name.size as int);
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 13);
}

#[test]
fn compound_assignment_evaluates_the_receiver_once() {
    let source = r#"
struct Box {
    var calls: int;
    var amount: int {
        get {
            return field;
        }
        set {
            calls += 1;
            field = value;
        }
    }
}
struct Tally {
    var made: int;
}
make(b: Box, t: Tally): Box {
    t.made += 1;
    return b;
}
test(): int {
    var b = Box();
    var t = Tally();
    make(b, t).amount += 5;
    make(b, t).amount++;
    return t.made * 100 + b.calls * 10 + b.amount;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 226);
}

#[test]
fn generic_struct_property() {
    let source = r#"
struct Holder<T> {
    var item: T { get; set; }
    var _reads: int;
    var reads: int {
        get {
            return _reads;
        }
    }
    take(): T {
        _reads += 1;
        return item;
    }
}
size_of<T>(h: Holder<T>): int {
    return h.reads;
}
test(): int {
    var h = Holder<String>();
    h.item = "abcd";
    var s = h.take();
    var n = Holder<int>();
    n.item = 7;
    return (s.size as int) * 100 + size_of(h) * 10 + n.item;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 417);
}

#[test]
fn trait_property_through_a_trait_value() {
    let source = r#"
trait Shape {
    var area: int { get; }
    var label: String { get; set; }
}
struct Square {
    var side: int { get; set; } = 1;
    var area: int {
        get {
            return side * side;
        }
    }
    var label: String { get; set; } = "square";
}
struct Dot {
    var area: int = 0;
    var label: String = "dot";
}
extend Square with Shape;
extend Dot with Shape;
total(shapes: Shape[]): int {
    var sum = 0;
    for (var s in shapes) {
        s.label = "seen";
        sum += s.area;
    }
    return sum;
}
test(): int {
    var sq = Square();
    sq.side = 3;
    var d = Dot();
    var shapes = Array<Shape>();
    shapes.append(sq);
    shapes.append(d);
    var sum = total(shapes);
    if (sq.label != "seen" || d.label != "seen") {
        return -1;
    }
    return sum;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 9);
}

#[test]
fn extension_adds_a_computed_property() {
    let source = r#"
struct Rect {
    var w: int = 2;
    var h: int = 3;
}
extend Rect {
    var area: int {
        get {
            return w * h;
        }
    }
}
test(): int {
    return Rect().area;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 6);
}

#[test]
fn shared_struct_property_is_set_in_its_constructor() {
    let source = r#"
[Shared]
struct Config {
    const port: int;
    var id: int { get; }
    var key: int {
        get {
            return id * 10000 + port;
        }
    }
    construct(this.port = 80) {
        id = 3;
    }
}
test(): int {
    var c = Config(8080);
    return c.key == 38080 ? 1 : 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 1);
}

#[test]
fn property_accessors_follow_the_reference_counting_model() {
    // `get` returns an owned temporary and `set` takes `value` by value: no
    // object leaks or is freed early, through default and custom accessors.
    let source = r#"
struct Node {
    var label: String { get; set; }
    var _next: Node;
    var next: Node {
        get {
            return _next;
        }
        set {
            _next = value;
        }
    }
    var tail: Node {
        get {
            return field;
        }
        set {
            field = value;
        }
    }
}
test(): int {
    var a = Node();
    a.label = "a";
    var b = Node();
    b.label = "b";
    a.next = b;
    a.tail = Node();
    a.tail.label = "t";
    var n = a.next;
    a.next = Node();
    a.next = a.next;
    var keep = a.tail;
    a.tail = b;
    return n.label.size as int + keep.label.size as int;
}
"#;
    assert_eq!(jit_census(source), (2, 0));
}

#[test]
fn an_extension_method_cannot_assign_a_get_only_property() {
    let error = compile_error(
        "struct A {\n    var x: long { get; }\n}\nextend A {\n    poke() {\n        x = 4;\n    }\n}\ntest(): int {\n    return 0;\n}\n",
    );
    assert!(error.contains("test.pep:6:9: error: cannot assign to 'x': it has no 'set' accessor"), "{}", error);
}

