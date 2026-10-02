//! Operators on numbers that the C-semantics matrix does not cover: `**`
//! with a floating-point operand (#384).

use crate::support::{compile_jit_with_runtime, run_linked};

#[test]
fn float_power_uses_pow_and_powi() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"test(): int {
    if (2.0 ** 3.0 != 8.0) { return 1; }
    if (2.0 ** 10 != 1024.0) { return 2; }            # int exponent: powi
    if (4 ** 0.5 != 2.0) { return 3; }                # int base converts
    var f: float = 1.5;
    var g = f ** 2;                                   # float stays float
    if (g != 2.25) { return 4; }
    var big: long = 40;
    if (2.0 ** big != 1099511627776.0) { return 5; }  # long exponent: pow
    if (2.0 ** -2 != 0.25) { return 6; }
    var u: uint = 3000000000;
    if (1.0 ** u != 1.0) { return 7; }                # uint above i32: pow
    if (2.0 ** 3 ** 2 != 512.0) { return 8; }         # right-associative
    var b: byte = 3;
    if (2.0 ** b != 8.0) { return 9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn float_power_links_without_naming_libm() {
    // `pow` lives in libm on Linux, which every program links.
    let out = run_linked(
        "float_power",
        "main(): int {\n    var e = 0.5;\n    print($\"{2.0 ** e}\");\n    return 0;\n}\n",
        |_| {},
    );
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "1.4142135623730951");
}

#[test]
fn number_on_the_left_calls_the_extension_operator() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"struct V {
    var x: double;
    construct(double x) { this.x = x; }
    ==(o: V): bool { return x == o.x; }
    *(s: double): V { return V(x * s); }
}
struct M {
    var k: int;
    construct(int k) { this.k = k; }
}
extend double {
    *(v: V): V { return V(v.x * this); }
    *(m: M): M { return M(m.k * 2); }
    ==(v: V): bool { return v.x == this; }
    <(v: V): bool { return this < v.x; }
}
extend int {
    *(v: V): V { return V(v.x * this); }
}
test(): int {
    var v = V(3.0);
    if ((2.0 * v).x != 6.0) { return 1; }
    if ((2.0 * M(4)).k != 8) { return 2; }      # overloaded by the right operand
    if ((2 * v).x != 6.0) { return 3; }         # int has its own
    if (!(3.0 == v)) { return 4; }
    if (!(2.0 != v)) { return 5; }              # != through ==
    if (!(2.0 < v)) { return 6; }
    if (2.0 * 3.0 != 6.0) { return 7; }         # built-in for two numbers
    var w = 2.0 * v * 2.0;                      # then V's own *
    if (w.x != 12.0) { return 8; }
    var scale: double = 0.5;
    var h = scale * v;                          # a variable, not a literal
    if (h.x != 1.5) { return 9; }
    return 0;
}"#
        ),
        0
    );
}
