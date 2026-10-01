//! `[Implicit]` constructors: a value flowing into a typed slot of a struct
//! whose constructor is `[Implicit]` becomes a call to that constructor.
//! Covers every flow site, the shared_ptr lifetime of the converted
//! temporary, the conversions that must not happen (narrowing, chains,
//! receivers, untyped locals, `__null`), and the runtime's `Path` and `Error`.

use crate::support::jit_census as run;
use crate::support::compile_error;
use crate::support::sema;

/// `Name` converts from a `String`, `Meters` from a `long`; `made` counts
/// `Name`s constructed and `destroyed` counts `Name`s destroyed.
const TYPES: &str = r#"
import async;
const made = async.Atomic<int>(0);
const destroyed = async.Atomic<int>(0);

struct Name {
    String text;

    [Implicit]
    construct(String text = "") {
        this.text = text;
        made.fetch_add(1);
    }

    destruct { destroyed.fetch_add(1); }

    bool ==(Name rhs) { return text == rhs.text; }
}

struct Meters {
    long value;

    [Implicit]
    construct(long value) { this.value = value; }
}

struct Holder {
    Name name;
    construct(Name name) { this.name = name; }
}

greet(n: Name): String {
    return "hi " + n.text;
}

make(): Name {
    return "returned";
}

total(m: Meters): long { return m.value; }
"#;

fn with_types(test: &str) -> String {
    format!("{}\n{}", TYPES, test)
}

#[test]
fn converts_at_every_flow_site() {
    let (result, leaked) = run(&with_types(
        r#"
test(): int {
    if (greet("bob") != "hi bob") { return 1; }
    var s = "alice";
    if (greet(s) != "hi alice") { return 2; }
    var n: Name = "typed";
    if (n.text != "typed") { return 3; }
    n = "assigned";
    if (n.text != "assigned") { return 4; }
    if (make().text != "returned") { return 5; }
    if (!(n == "assigned")) { return 6; }
    var names = Array<Name>();
    names.append("element");
    names[0] = "replaced";
    if (names[0].text != "replaced") { return 7; }
    var h = Holder("field");
    if (h.name.text != "field") { return 8; }
    var f: (Name) => String = greet;
    if (f("called") != "hi called") { return 9; }
    return 0;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn numbers_convert_by_promotion() {
    let (result, _) = run(&with_types(
        r#"
test(): int {
    if (total(5) != 5) { return 1; }
    var i: int = 7;
    if (total(i) != 7) { return 2; }
    var m: Meters = 9;
    return (m.value == 9) ? 0 : 3;
}
"#,
    ));
    assert_eq!(result, 0);
}

#[test]
fn the_converted_temporary_is_released_after_the_call() {
    let (result, leaked) = run(&with_types(
        r#"
test(): int {
    var s = "kept";
    greet(s);
    if (made.load() != 1 || destroyed.load() != 1) { return 1; }
    # The String is shared with the temporary, not consumed by it.
    if (__refcount<String>(s) != 1) { return 2; }
    var n: Name = s;
    if (__refcount<String>(s) != 2) { return 3; }
    return (destroyed.load() == 1) ? 0 : 4;
}
"#,
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn a_struct_converts_through_a_trait_parameter() {
    let (result, leaked) = run(
        r#"
trait Shape { int area(); }

struct Square {
    int side;
    construct(int side) { this.side = side; }
}

extend Square with Shape {
    int area() { return side * side; }
}

struct Framed {
    Shape inner;
    [Implicit]
    construct(Shape inner) { this.inner = inner; }
}

measure(f: Framed): int { return f.inner.area(); }

test(): int {
    return measure(Square(3)) - 9;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn null_untyped_locals_and_receivers_do_not_convert() {
    let (result, _) = run(&with_types(
        r#"
maybe(m: Meters): int { return (m == __null) ? 1 : 0; }

test(): int {
    if (maybe(__null) != 1) { return 1; }
    var plain = "text";
    if (plain.length() != 4) { return 2; }
    return (made.load() == 0) ? 0 : 3;
}
"#,
    ));
    assert_eq!(result, 0);
}

#[test]
fn narrowing_does_not_convert() {
    let error = compile_error(
        "struct Small {\n    int v;\n    [Implicit] construct(int v) { this.v = v; }\n}\n\
         f(s: Small): int { return s.v; }\n\
         test(): int { var big: long = 5; return f(big); }\n",
    );
    assert!(error.contains("cannot pass a value of type 'long' as argument 1 of 'f', which has type 'Small'"), "{}", error);
}

#[test]
fn conversions_do_not_chain() {
    let error = compile_error(&with_types(
        "struct Tag {\n    Name name;\n    [Implicit] construct(Name name) { this.name = name; }\n}\n\
         tagged(t: Tag): int { return 0; }\n\
         test(): int { return tagged(\"x\"); }\n",
    ));
    assert!(error.contains("cannot pass a value of type 'String' as argument 1 of 'tagged', which has type 'Tag'"), "{}", error);
}

#[test]
fn a_plain_constructor_does_not_convert_but_is_suggested() {
    let error = compile_error(
        "struct Label {\n    String text;\n    construct(String text) { this.text = text; }\n}\n\
         show(l: Label): int { return 0; }\n\
         test(): int { return show(\"x\"); }\n",
    );
    assert!(error.contains("which has type 'Label'"), "{}", error);
    assert!(error.contains("'Label' has a constructor from 'String': call 'Label(...)', or mark the constructor [Implicit]"), "{}", error);
}

#[test]
fn the_attribute_is_checked() {
    for (source, message) in [
        ("struct A {\n    [Implicit] construct() {}\n}\n", "'Implicit' constructor of 'A' must be callable with one argument"),
        ("struct A {\n    [Implicit] construct(int a, int b) {}\n}\n", "'Implicit' constructor of 'A' must be callable with one argument"),
        ("struct A {\n    [Implicit] construct(A other) {}\n}\n", "'Implicit' constructor of 'A' cannot convert from 'A'"),
        ("struct Box<T> {\n    [Implicit] construct(T value) {}\n}\n", "'Implicit' constructor of 'Box' cannot convert from its type parameter 'T'"),
        ("[Implicit]\nf(): int { return 1; }\n", "'Implicit' applies only to constructors"),
        ("struct A {\n    [Implicit] int m() { return 1; }\n}\n", "'Implicit' applies only to constructors"),
        ("struct A {\n    [Implicit] int x;\n}\n", "'Implicit' applies only to constructors"),
        ("[Implicit]\nstruct A {}\n", "'Implicit' applies only to constructors"),
    ] {
        let error = compile_error(&format!("{}test(): int {{ return 0; }}\n", source));
        assert!(error.contains(message), "expected '{}' in:\n{}", message, error);
    }
    // Trailing parameters with defaults are fine.
    sema("struct A {\n    int x;\n    [Implicit] construct(int x, int y = 0) { this.x = x; }\n}\ntest(): int { return 0; }\n")
        .expect("one required parameter");
}

#[test]
fn the_runtime_converts_strings_to_paths_and_errors() {
    let (result, leaked) = run(
        r#"
import io;

fails(): Result<int> {
    return Result<int>.err("bad input");
}

test(): int {
    var p = io.Path("usr").join("lib");
    if (p != io.Path("usr").join(io.Path("lib"))) { return 1; }
    var q: io.Path = "docs";
    if (q.to_string() != "docs") { return 2; }
    var r = fails();
    if (r.error().message != "bad input") { return 4; }
    return 0;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}
