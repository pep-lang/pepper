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
