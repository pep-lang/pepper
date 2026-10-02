//! Overloaded free functions: several functions of one file sharing a name,
//! each call resolved to the member whose parameters fit its arguments best
//! (see `pepper_sema::passes::overloads`). Covers the ranking (exact,
//! promotion, conversion, `[Implicit]` constructor), generic members and the
//! non-generic tie-breaker, calls in generic code, function values, closure
//! arguments, and the shared_ptr lifetime of arguments to a resolved call;
//! then methods, operators, extension methods and traits.

use crate::support::jit_census as run;
use crate::support::compile_error;
use crate::support::sema;

fn value(source: &str) -> i32 {
    let (result, leaked) = run(source);
    assert_eq!(leaked, 0, "leaked allocations");
    result
}

#[test]
fn calls_pick_the_member_their_argument_types_match() {
    let source = r#"
kind(x: int): int { return 1; }
kind(x: double): int { return 2; }
kind(x: String): int { return 3; }
kind(x: bool, y: int): int { return 4; }
test(): int {
    var s = String();
    return kind(7) * 1000 + kind(2.5) * 100 + kind(s) * 10 + kind(true, 1);
}
"#;
    assert_eq!(value(source), 1234);
}

#[test]
fn a_member_s_return_type_types_the_call() {
    let source = r#"
half(x: int): int { return x / 2; }
half(x: double): double { return x / 2.0; }
test(): int {
    var a = half(9);
    var b = half(9.0);
    if (b != 4.5) { return -1; }
    return a;
}
"#;
    assert_eq!(value(source), 4);
}

#[test]
fn exact_beats_promotion_beats_conversion() {
    let source = r#"
f(x: long): int { return 1; }
f(x: double): int { return 2; }
g(x: int): int { return 1; }
g(x: bool): int { return 2; }
test(): int {
    var small: short = 3;
    var ratio: float = 0.5;
    var wide: long = 3;
    # short -> long widens (promotion); short -> double converts.
    # float -> double is a promotion; float -> long converts.
    var n: int = 2;
    return f(small) * 1000 + f(ratio) * 100 + g(n) * 10 + f(wide);
}
"#;
    assert_eq!(value(source), 1211);
}

#[test]
fn the_narrowest_widening_wins() {
    // `short` widens to both `int` and `long`; `int` is closer.
    let source = r#"
g(x: int): int { return 1; }
g(x: long): int { return 2; }
h(x: long): int { return 3; }
h(x: double): int { return 4; }
test(): int {
    var small: short = 3;
    var tiny: u8 = 1;
    var wide: int = 2;
    return g(small) * 1000 + g(tiny) * 100 + g(wide) * 10 + h(small);
}
"#;
    assert_eq!(value(source), 1113);
}

#[test]
fn widenings_to_one_width_are_ambiguous() {
    let source = r#"
g(x: long): int { return 1; }
g(x: ulong): int { return 2; }
test(): int { var small: ushort = 3; return g(small); }
"#;
    assert!(compile_error(source).contains("error: call to 'g' is ambiguous"));
}

#[test]
fn an_integer_literal_promotes_to_any_integer_type_it_fits() {
    let source = r#"
f(x: u8): int { return 1; }
f(x: String): int { return 2; }
test(): int { return f(200) * 10 + f("x"); }
"#;
    assert_eq!(value(source), 12);
}

#[test]
fn an_integer_literal_that_fits_two_members_is_ambiguous() {
    let source = r#"
f(x: long): int { return 1; }
f(x: short): int { return 2; }
test(): int { return f(1); }
"#;
    let error = compile_error(source);
    assert!(error.contains("error: call to 'f' is ambiguous"), "{}", error);
    assert_eq!(error.matches("note: candidate function").count(), 2, "{}", error);
}

#[test]
fn a_string_literal_passes_its_characters_to_a_pointer_member() {
    let source = r#"
extern ulong strlen(char* s);
size(p: __ptr<char>): ulong { return strlen(p) * 10; }
size(s: String): ulong { return s.size; }
test(): int {
    var text = "hello";
    return (size("abc") + size(text)) as int;
}
"#;
    assert_eq!(value(source), 35);
}

#[test]
fn an_implicit_constructor_ranks_below_an_exact_member() {
    let source = r#"
import io;
open(p: io.Path): int { return 1; }
open(s: String): int { return 2; }
show(p: io.Path): int { return 3; }
show(n: long): int { return 4; }
test(): int { return open("a") * 100 + show("docs") * 10 + show(5); }
"#;
    assert_eq!(value(source), 234);
}

#[test]
fn a_non_generic_member_beats_a_generic_one_it_ties() {
    let source = r#"
describe<T>(v: T): int { return 1; }
describe(v: int): int { return 2; }
test(): int { return describe(7) * 100 + describe(1.5) * 10 + describe<int>(7); }
"#;
    assert_eq!(value(source), 211);
}

#[test]
fn generic_members_differ_by_arity() {
    let source = r#"
pick<T>(a: T): T { return a; }
pick<T>(a: T, b: T): T { return b; }
test(): int { return pick(1) * 10 + pick(3, 4); }
"#;
    assert_eq!(value(source), 14);
}

#[test]
fn calls_in_generic_code_resolve_per_specialization() {
    let source = r#"
classify(i: int): int { return 1; }
classify(s: String): int { return 2; }
wrap<T>(v: T): int { return classify(v); }
struct Box<T> {
    T value;
    construct(T v) { value = v; }
    kind(): int { return classify(value); }
}
test(): int {
    var a = Box<int>(3);
    var b = Box<String>("x");
    return wrap(3) * 1000 + wrap("s") * 100 + a.kind() * 10 + b.kind();
}
"#;
    assert_eq!(value(source), 1212);
}

#[test]
fn nested_and_recursive_calls_resolve() {
    let source = r#"
inc(x: int) { return x + 1; }
inc(x: double) { return x + 0.5; }
count(n: int): int { if (n == 0) { return 0; } return count(n - 1) + 1; }
count(s: String): int { return count(s.length as int); }
test(): int {
    var d = inc(inc(1.0));
    if (d != 2.0) { return -1; }
    return inc(inc(1)) * 10 + count("hey");
}
"#;
    assert_eq!(value(source), 33);
}

#[test]
fn a_function_value_takes_the_member_its_slot_s_type_names() {
    let source = r#"
twice(x: int): int { return x * 2; }
twice(s: String): int { return s.size as int; }
apply(f: (int) => int, x: int): int { return f(x); }
chooser(): (String) => int { return twice; }
test(): int {
    var f: (int) => int = twice;
    var g = chooser();
    return f(1) * 100 + apply(twice, 3) * 10 + g("abcd");
}
"#;
    assert_eq!(value(source), 264);
}

#[test]
fn an_overloaded_argument_picks_the_parameter_that_fits_it() {
    let source = r#"
twice(x: int): int { return x * 2; }
twice(s: String): int { return 0; }
run(f: (int) => int, x: int): int { return f(x); }
run(f: (String) => int, s: String): int { return f(s) + 100; }
test(): int { return run(twice, 21); }
"#;
    assert_eq!(value(source), 42);
}

#[test]
fn an_untyped_closure_picks_the_member_of_its_arity() {
    let source = r#"
run(f: (int) => int): int { return f(1); }
run(f: (int, int) => int): int { return f(1, 2); }
test(): int { return run((a) => a + 10) * 10 + run((a, b) => a + b); }
"#;
    assert_eq!(value(source), 113);
}

#[test]
fn arguments_to_a_resolved_call_follow_the_shared_ptr_rules() {
    let source = r#"
struct Item { int n; construct(int v) { n = v; } }
weigh(i: Item): int { return i.n; }
weigh(i: Item, extra: int): int { return i.n + extra; }
test(): int {
    var kept = Item(4);
    return weigh(kept) + weigh(Item(5), 1) + weigh(Item(6));
}
"#;
    assert_eq!(value(source), 16);
}

#[test]
fn an_override_attaches_to_the_member_it_matches() {
    let source = r#"
struct Point { int x; construct(int v) { x = v; } }
tag<T>(v: T): int { return 1; }
tag<T>(v: T, w: T): int { return 2; }
tag<Point>(v: Point): int { return 30; }
test(): int { var p = Point(1); return tag(p) + tag(p, p) + tag(5); }
"#;
    assert_eq!(value(source), 33);
}

#[test]
fn a_file_s_private_set_is_its_own() {
    let source = r#"
helper(x: int): int { return 1; }
helper(x: String): int { return 2; }
test(): int { return helper(1) * 10 + helper("x"); }
"#;
    assert_eq!(value(source), 12);
}

#[test]
fn method_calls_pick_the_member_their_arguments_match() {
    let source = r#"
struct Meter {
    int n;
    construct(int v) { n = v; }
    add(x: int): int { return n + x; }
    add(x: int, y: int): int { return n + x + y; }
    add(s: String): int { return 100; }
    # A bare call and a call on `this` resolve too.
    total(): int { return add(1) + this.add(1, 2); }
}
test(): int {
    var m = Meter(5);
    return m.add(2) * 1000 + m.add("x") + m.total();
}
"#;
    // 7 * 1000 + 100 + (6 + 8)
    assert_eq!(value(source), 7114);
}

#[test]
fn static_methods_overload_apart_from_instance_methods() {
    let source = r#"
struct Meter {
    int n;
    construct(int v) { n = v; }
    static of(x: int): Meter { return Meter(x); }
    static of(s: String): Meter { return Meter(s.size as int); }
}
test(): int { return Meter.of(3).n * 10 + Meter.of("abcd").n; }
"#;
    assert_eq!(value(source), 34);
}

#[test]
fn operators_overload_by_operand_type() {
    let source = r#"
struct Money {
    int cents;
    construct(int c) { cents = c; }
    Money +(Money other) { return Money(cents + other.cents); }
    Money +(int more) { return Money(cents + more); }
    bool ==(Money other) { return cents == other.cents; }
    bool ==(int c) { return cents == c; }
}
test(): int {
    var a = Money(5);
    var b = (a + a) + 1;
    if (!(b == 11) || b != Money(11) || !(a == a)) { return -1; }
    return b.cents;
}
"#;
    assert_eq!(value(source), 11);
}

#[test]
fn an_overloaded_operator_types_a_variable_by_the_member_it_picks() {
    // `var` takes the chosen member's return type, not the left operand's,
    // as for `os.Instant`: `Instant - Instant` is a Duration.
    let source = r#"
struct Span {
    var length: int;
    construct(length: int) { this.length = length; }
}
struct Moment {
    var at: int;
    construct(at: int) { this.at = at; }
    -(earlier: Moment): Span { return Span(at - earlier.at); }
    -(span: Span): Moment { return Moment(at - span.length); }
}
test(): int {
    var start = Moment(3);
    var span = Moment(10) - start;
    var before = start - span;
    Span check = span;
    Moment check_moment = before;
    return span.length * 10 + before.at + 4;
}
"#;
    assert_eq!(value(source), 70);
}

#[test]
fn generic_struct_methods_overload_per_specialization() {
    let source = r#"
struct Holder<T> {
    T v;
    construct(T value) { v = value; }
    has(x: T): int { return 1; }
    has(x: String): int { return 2; }
    both(): int { return has(v) * 10 + has("s"); }
}
test(): int { var h = Holder<int>(3); return h.both() * 10 + h.has(4); }
"#;
    assert_eq!(value(source), 121);
}

#[test]
fn an_overloaded_method_value_takes_the_member_its_slot_names() {
    let source = r#"
struct Meter {
    int n;
    construct(int v) { n = v; }
    get(x: int): int { return n + x; }
    get(s: String): int { return 100; }
    static make(x: int): Meter { return Meter(x); }
    static make(s: String): Meter { return Meter(7); }
}
apply(f: (int) => int, x: int): int { return f(x); }
test(): int {
    var m = Meter(1);
    var f: (int) => int = m.get;
    var make: (String) => Meter = Meter.make;
    return f(2) * 100 + apply(m.get, 5) * 10 + make("x").n;
}
"#;
    assert_eq!(value(source), 367);
}

#[test]
fn an_extension_method_calls_an_overloaded_method() {
    let source = r#"
struct Meter {
    int n;
    construct(int v) { n = v; }
    add(x: int): int { return n + x; }
    add(s: String): int { return 100; }
}
extend Meter {
    total(): int { return add(1) + this.add("s"); }
}
test(): int { var m = Meter(5); return m.total(); }
"#;
    assert_eq!(value(source), 106);
}

#[test]
fn extension_methods_join_the_struct_s_set() {
    let source = r#"
struct Meter {
    int n;
    construct(int v) { n = v; }
    add(x: int): int { return n + x; }
}
extend Meter {
    add(s: String): int { return 100; }
    add(x: int, y: int): int { return n + x + y; }
    total(): int { return add(1) + add("s") + this.add(1, 2); }
}
test(): int {
    var m = Meter(5);
    var f: (String) => int = m.add;
    # 6 + 100 + 7 + (6 + 100 + 8) + 100
    return m.add(1) + m.add("x") + m.add(1, 1) + m.total() + f("q");
}
"#;
    assert_eq!(value(source), 327);
}

#[test]
fn a_trait_member_is_implemented_by_the_overload_with_its_parameters() {
    let source = r#"
trait Scaled {
    scale(by: int): int;
    label(): int { return 40; }
}
struct Box {
    int n;
    construct(int v) { n = v; }
    scale(by: String): int { return 7; }
    scale(by: int): int { return n * by; }
    label(x: int): int { return x; }
}
extend Box with Scaled {}
show(s: Scaled): int { return s.scale(3) + s.label(); }
test(): int {
    var b = Box(2);
    # (6 + 40) * 100 + 7 * 10 + 1, and the default joined `label`'s set
    return show(b) * 100 + b.scale("x") * 10 + b.label(1) + b.label() * 0;
}
"#;
    assert_eq!(value(source), 4671);
}

#[test]
fn a_trait_s_overloads_are_separate_slots() {
    let source = r#"
trait Shape {
    area(): int;
    area(scale: int): int;
    describe(): int { return area() * 1000 + area(2); }
}
struct Square {
    int side;
    construct(int v) { side = v; }
    area(): int { return side * side; }
    area(scale: int): int { return side * side * scale; }
}
extend Square with Shape {}
total(s: Shape): int { return s.area() * 100 + s.area(3); }
test(): int {
    var q = Square(2);
    var s: Shape = q;
    # 412, then 4008 through the trait value
    return total(q) * 10000 + s.describe();
}
"#;
    assert_eq!(value(source), 4124008);
}

// ── Constructors ───────────────────────────────────────────────────────────

#[test]
fn constructors_overload_by_parameters() {
    let source = r#"
struct Point {
    int x;
    int y;
    construct() { x = 1; y = 2; }
    construct(v: int) { x = v; y = v; }
    construct(a: int, b: int) { x = a; y = b; }
    construct(s: String) { x = s.length as int; y = 0; }
}
test(): int {
    var a = Point();
    var b = Point(3);
    var c = Point(4, 5);
    var d = Point("hello");
    return a.x * 1000000 + a.y * 100000 + b.x * 10000 + c.x * 1000 + c.y * 100 + d.x * 10 + d.y;
}
"#;
    assert_eq!(value(source), 1234550);
}

#[test]
fn generic_constructors_overload_in_each_specialization() {
    let source = r#"
struct Pair<T> {
    T first;
    T second;
    construct(v: T) { first = v; second = v; }
    construct(a: T, b: T) { first = a; second = b; }
}
test(): int {
    var a = Pair<int>(7);
    var b = Pair<int>(1, 2);
    var c = Pair<String>("x");
    return a.first * 1000 + a.second * 100 + b.first * 10 + b.second + (c.first.length as int) * 0;
}
"#;
    assert_eq!(value(source), 7712);
}

/// A call on an overloaded constructor's temporary has the method's type:
/// `==` compares Strings by value and `print` prints the text (both went
/// by the type of `Name$1(...)`, which was unknown).
#[test]
fn a_method_on_an_overloaded_constructor_temporary_is_typed() {
    let source = r#"
struct Label {
    int n;
    construct() { n = 1; }
    construct(v: int) { n = v; }
    text(): String { return "label"; }
}
struct Holder<T> {
    T value;
    construct(v: T) { value = v; }
    construct(a: T, b: T) { value = b; }
    text(): String { return "holder"; }
}
test(): int {
    var r = 0;
    if (Label().text() == "label") { r = r + 1; }
    if (Label(5).text() == "label") { r = r + 10; }
    if (Holder<int>(1, 2).text() == "holder") { r = r + 100; }
    return r;
}
"#;
    assert_eq!(value(source), 111);
}

#[test]
fn an_overloaded_constructor_is_a_function_value_by_type() {
    let source = r#"
struct Point {
    int x;
    construct(v: int) { x = v; }
    construct(a: int, b: int) { x = a + b; }
}
test(): int {
    var one: (int) => Point = Point;
    var two: (int, int) => Point = Point;
    return one(4).x * 10 + two(2, 3).x;
}
"#;
    assert_eq!(value(source), 45);
}

#[test]
fn no_matching_constructor_is_an_error() {
    let err = compile_error(
        r#"
struct Point {
    int x;
    construct(v: int) { x = v; }
    construct(a: int, b: int) { x = a + b; }
}
test(): int { return Point(1, 2, 3).x; }
"#,
    );
    assert!(err.contains("error: no matching constructor for initialization of 'Point'"), "{}", err);
    assert!(err.contains("note: candidate constructor not viable: requires 1 argument, but 3 were provided"), "{}", err);
}

#[test]
fn an_ambiguous_constructor_call_is_an_error() {
    let err = compile_error(
        r#"
struct Point {
    int x;
    construct(v: long) { x = v as int; }
    construct(v: double) { x = 0; }
}
test(): int { var i: ulong = 3; return Point(i).x; }
"#,
    );
    assert!(err.contains("error: call to constructor of 'Point' is ambiguous"), "{}", err);
}

#[test]
fn a_redeclared_constructor_is_an_error() {
    let err = compile_error(
        r#"
struct Point {
    int x;
    construct(v: int) { x = v; }
    construct(w: int) { x = w; }
}
test(): int { return Point(1).x; }
"#,
    );
    assert!(err.contains("error: constructor of 'Point' cannot be redeclared"), "{}", err);
    assert!(err.contains("note: previous declaration is here"), "{}", err);
}

#[test]
fn an_implicit_constructor_converts_beside_its_overloads() {
    let source = r#"
struct Meters {
    int value;
    [Implicit]
    construct(v: int) { value = v; }
    construct(a: int, b: int) { value = a * b; }
}
twice(m: Meters): int { return m.value * 2; }
test(): int { return twice(21) * 100 + Meters(3, 4).value; }
"#;
    assert_eq!(value(source), 4212);
}

#[test]
fn only_one_constructor_may_be_implicit() {
    let err = compile_error(
        r#"
struct Meters {
    int value;
    [Implicit]
    construct(v: int) { value = v; }
    [Implicit]
    construct(v: double) { value = 0; }
}
test(): int { return 0; }
"#,
    );
    assert!(err.contains("error: only one constructor of 'Meters' may be 'Implicit'"), "{}", err);
}

#[test]
fn a_deprecated_constructor_overload_warns_only_where_called() {
    let module = sema(
        r#"
struct Point {
    int x;
    construct(v: int) { x = v; }
    [Deprecated("use 'Point(int)' instead")]
    construct(v: double) { x = 0; }
}
test(): int { return Point(1).x + Point(2.5).x; }
"#,
    )
    .expect("compile");
    let warnings = module.render_warnings();
    assert_eq!(warnings.matches("warning:").count(), 1, "{}", warnings);
    assert!(warnings.contains("'Point' is deprecated: use 'Point(int)' instead"), "{}", warnings);
    assert!(warnings.contains("Point(2.5)"), "{}", warnings);
}

#[test]
fn the_more_specialized_generic_member_wins() {
    // `(A, B)` deduces into `T` but not the reverse, so a tuple argument
    // picks the pair member; anything else can only take `T`. A
    // non-generic member still beats both.
    assert_eq!(
        value(
            r#"
describe<T>(value: T): int { return 1; }
describe<A, B>(pair: (A, B)): int { return 2; }
describe<A>(items: A[]): int { return 3; }
describe(value: int): int { return 4; }

forward<T>(value: T): int { return describe(value); }

test(): int {
    if (describe((1, "x")) != 2) { return -1; }
    if (describe("s") != 1) { return -2; }
    if (describe(Array<int>()) != 3) { return -3; }
    if (describe(7) != 4) { return -4; }
    if (forward((1, 2)) != 2) { return -5; }
    if (forward(true) != 1) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn equally_specialized_generic_members_are_ambiguous() {
    let error = compile_error(
        r#"
pick<A, B>(pair: (A, B)): int { return 1; }
pick<A, B>(pair: (A, B), extra: int = 0): int { return 2; }

test(): int { return pick((1, 2)); }"#,
    );
    assert!(error.contains("call to 'pick' is ambiguous"), "{}", error);
}
