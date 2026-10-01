//! Static method calls on a bare struct name (`File.open(p)`), from a free
//! function and from another struct's method. Generic receivers
//! (`Result<int>.ok(1)`) and aliases already went through a ctor-style
//! receiver; a plain name reached codegen as an unknown symbol, and inside a
//! method it panicked in convert_member_refs as an unresolved field.

use crate::support::compile_jit_with_runtime;

const MAKER: &str = r#"
struct Maker {
    int x;
    static Maker make(int x) {
        var m = Maker();
        m.x = x;
        return m;
    }
    static int twice(int v) { return v * 2; }
}
"#;

#[test]
fn static_call_on_struct_name_from_free_function() {
    let source = format!(
        "{MAKER}
test(): int {{
    var m = Maker.make(20);
    return m.x + Maker.twice(1) - 22;
}}"
    );
    assert_eq!(compile_jit_with_runtime(&source), 0);
}

#[test]
fn static_call_on_struct_name_from_another_structs_method() {
    let source = format!(
        "{MAKER}
struct User {{
    int y;
    int run() {{
        var m = Maker.make(y);
        return m.x + Maker.twice(3);
    }}
}}
test(): int {{
    var u = User();
    u.y = 4;
    return u.run() - 10;
}}"
    );
    assert_eq!(compile_jit_with_runtime(&source), 0);
}

#[test]
fn local_shadows_struct_name() {
    // A local named like a struct is the local, not the type.
    let source = format!(
        "{MAKER}
test(): int {{
    var Maker = 5;
    return Maker - 5;
}}"
    );
    assert_eq!(compile_jit_with_runtime(&source), 0);
}

#[test]
fn static_methods_call_statics_by_bare_name() {
    // A bare call to a static method goes to the struct, from a static
    // method (which has no `this`) as from an instance method, and in a
    // generic struct.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct S {
    var n: int = 1;
    construct(this.n = 1) {}
    static a(x: int): int { return b(x) + 1; }
    static b(x: int): int { return x * 2; }
    c(): int { return b(n) + a(n); }
}

struct Box<T> {
    var v: T;
    construct(value: T) { v = value; }
    static twice(x: T): Box<T> { return make(x); }
    static make(x: T): Box<T> { return Box<T>(x); }
}

struct C {
    static a(x: int): int {
        var f = (y: int): int => b(y);
        return f(x);
    }
    static b(x: int): int { return x * 3; }
}

test(): int {
    if (S.a(3) != 7) { return -1; }
    if (S(3).c() != 13) { return -2; }
    if (Box<int>.twice(4).v != 4) { return -3; }
    if (C.a(2) != 6) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn closures_in_static_methods_call_statics_by_bare_name() {
    // In a generic struct, through an extension's static, and in a generic
    // static method.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct C<T> {
    var v: T;
    construct(value: T) { v = value; }
    static a(x: T): T {
        var f = (y: T): T => b(y);
        return f(x);
    }
    static b(x: T): T { return x; }
}

struct E {
    static a(x: int): int {
        var f = (y: int): int => e(y);
        return f(x);
    }
}

extend E {
    static e(x: int): int { return x + 100; }
}

struct G {
    static a<T>(x: T): T {
        var f = (y: T): T => b(y);
        return f(x);
    }
    static b<T>(x: T): T { return x; }
}

helper(): int { return 7; }

# A field default has no struct to call on: a closure there calls the free
# function, not the static of the same name.
struct D {
    var f: () => int = () => helper();
    construct() {}
    static helper(): int { return 1; }
}

test(): int {
    if (D().f() != 7) { return -4; }
    if (C<int>.a(5) != 5) { return -1; }
    if (E.a(1) != 101) { return -2; }
    if (G.a<int>(9) != 9) { return -3; }
    return 0;
}"#
        ),
        0
    );
}
