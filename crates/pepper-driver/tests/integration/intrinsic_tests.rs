//! LLVM intrinsics (#344): externs bound to `llvm.*` symbols, the integer
//! types' bit methods, the float functions and the `hint` module written
//! with them.

use crate::support::{compile_jit_with_runtime, jit_cases, run_linked_with};

#[test]
fn integer_bit_methods_work_at_each_width() {
    jit_cases(
        r#"
counts(): int {
    if ((0 as char).leading_zeros() != 8 || (0 as byte).trailing_zeros() != 8) { return 1; }
    if ((0 as short).leading_zeros() != 16 || (0 as ushort).trailing_zeros() != 16) { return 2; }
    if ((0 as int).leading_zeros() != 32 || (0 as uint).trailing_zeros() != 32) { return 3; }
    if ((0 as long).leading_zeros() != 64 || (0 as ulong).trailing_zeros() != 64) { return 4; }
    if ((-1 as char).count_ones() != 8 || (-1 as short).count_ones() != 16) { return 5; }
    if ((-1 as int).count_ones() != 32 || (-1 as long).count_zeros() != 0) { return 6; }
    if ((1 as byte).leading_zeros() != 7 || (1 as ulong).leading_zeros() != 63) { return 7; }
    if ((0x8000 as ushort).trailing_zeros() != 15 || (-128 as char).trailing_zeros() != 7) { return 8; }
    if ((0x00FF00FF00FF00FF as ulong).count_ones() != 32) { return 9; }
    return 0;
}

order(): int {
    if ((0x1234 as short).swap_bytes() != 0x3412) { return 1; }
    # A swap that sets the sign bit of a signed type.
    if ((0x80 as int).swap_bytes() != -2147483648) { return 2; }
    if ((0x0102030405060708 as ulong).swap_bytes() != 0x0807060504030201) { return 3; }
    if ((7 as byte).swap_bytes() != 7) { return 4; }
    if ((1 as byte).reverse_bits() != 0x80 || (1 as char).reverse_bits() != -128) { return 5; }
    if ((1 as uint).reverse_bits() != 0x80000000 || (-2 as long).reverse_bits() != 0x7FFFFFFFFFFFFFFF) { return 6; }
    return 0;
}

rotates(): int {
    if ((0x81 as byte).rotate_left(1) != 0x03 || (0x81 as byte).rotate_right(1) != 0xC0) { return 1; }
    if ((-128 as char).rotate_left(1) != 1) { return 2; }
    if ((-2 as int).rotate_right(1) != 2147483647) { return 3; }
    # The count is taken modulo the width; a negative one rotates the other way.
    if ((1 as uint).rotate_left(33) != 2 || (1 as uint).rotate_left(-1) != 0x80000000) { return 4; }
    if ((1 as ulong).rotate_right(64) != 1 || (0x8000 as ushort).rotate_left(1) != 1) { return 5; }
    var n = 3;
    if ((1 as long).rotate_left(n) != 8) { return 6; }
    return 0;
}

min_max_abs(): int {
    if ((-3 as char).min(2) != -3 || (200 as byte).max(100) != 200) { return 1; }
    if ((-3).max(-7) != -3 || (5 as ulong).min(9) != 5) { return 2; }
    if ((-127 as char).abs() != 127 || (-32767 as short).abs() != 32767) { return 3; }
    if ((-5).abs() != 5 || (6 as long).abs() != 6 || (-9223372036854775807 as long).abs() != 9223372036854775807) { return 4; }
    return 0;
}
"#,
        &["counts", "order", "rotates", "min_max_abs"],
    );
}

#[test]
fn float_functions() {
    jit_cases(
        r#"
doubles(): int {
    if ((2.25).square_root() != 1.5 || (-1.5).floor() != -2.0 || (-1.5).ceiling() != -1.0) { return 1; }
    if ((-1.5).truncate() != -1.0 || (2.5).round() != 3.0 || (-2.5).round() != -3.0) { return 2; }
    if ((-4.0).abs() != 4.0 || (4.0).copy_sign(-0.0) != -4.0 || (-4.0).copy_sign(1.0) != 4.0) { return 3; }
    if ((2.0).multiply_add(3.0, 1.0) != 7.0) { return 4; }
    var nan = (-1.0).square_root();
    if (nan == nan) { return 5; }
    if ((1.5).min(nan) != 1.5 || nan.max(1.5) != 1.5 || (1.5).min(-2.0) != -2.0) { return 6; }
    return 0;
}

floats(): int {
    float x = 6.25;
    if (x.square_root() != 2.5 || x.floor() != 6.0 || x.ceiling() != 7.0 || x.round() != 6.0) { return 1; }
    if ((-x).abs() != x || x.copy_sign(-1.0) != -x || x.min(1.0) != 1.0 || x.max(1.0) != x) { return 2; }
    if (x.multiply_add(2.0, 0.5) != 13.0 || x.truncate() != 6.0) { return 3; }
    return 0;
}
"#,
        &["doubles", "floats"],
    );
}

#[test]
fn abs_of_the_lowest_value_panics_at_the_caller() {
    let source = "main(): int {\n    var m = -2147483647 - 1;\n    return m.abs();\n}\n";
    let output = run_linked_with("intrinsic_abs_panics", source, &[], |_| {});
    let stderr = String::from_utf8_lossy(&output.stderr).replace('\r', "");
    assert!(!output.status.success(), "{}", stderr);
    assert!(stderr.contains("intrinsic_abs_panics.pep:3:14: panic: integer overflow in 'int' absolute value"), "{}", stderr);
}

#[test]
fn an_extern_binds_an_intrinsic_by_its_base_or_mangled_name() {
    let source = r#"
[Link(name = "llvm.ctpop")]
extern uint population(uint value);

[Link(name = "llvm.ctpop.i64")]
extern long population64(long value);

[Link(name = "llvm.fshl")]
extern ulong funnel_left(ulong high, ulong low, ulong count);

[Link(name = "llvm.umax")]
extern byte larger(byte a, byte b);

[Link(name = "llvm.sqrt")]
extern float root(float value);

[Link(name = "llvm.expect")]
extern bool expect(bool value, bool expected);

[Link(name = "llvm.prefetch")]
extern void prefetch(void* address, int write, int locality, int cache);

test(): int {
    if (population(0xF0F0) != 8 || population64(-1) != 64) { return 1; }
    if (funnel_left(1, 0x8000000000000000, 1) != 3) { return 2; }
    if (larger(200, 100) != 200) { return 3; }
    if (root(16.0) != 4.0) { return 4; }
    var text = "x";
    prefetch(text.c_str(), 0, 3, 1);
    if (!expect(text.length == 1, true)) { return 5; }
    return 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

#[test]
fn hint_functions_return_their_condition() {
    jit_cases(
        r#"
import hint;

hints(): int {
    var values = [3, -1, 2];
    var negatives = 0;
    for (var value in values) {
        if (hint.unlikely(value < 0)) {
            negatives += 1;
        }
        if (!hint.likely(value != 0)) {
            return 1;
        }
    }
    var text = "hello";
    hint.prefetch_read(text.c_str());
    hint.prefetch_write(text.c_str());
    return negatives == 1 ? 0 : 2;
}
"#,
        &["hints"],
    );
}

#[test]
fn trailing_zeros_compiles_to_the_intrinsic() {
    // The point of the methods: no loop, a call of the intrinsic that LLVM
    // turns into one instruction.
    let source = "main(): int {\n    var x = 40 as ulong;\n    return x.trailing_zeros();\n}\n";
    let module = crate::support::sema(source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = pepper_codegen::CodeGenerator::new(&ctx, "main");
    let mut module = module;
    generator.generate(&mut module).expect("generate");
    let ir = generator.module.print_to_string().to_string();
    assert!(ir.contains("@llvm.cttz.i64("), "{}", ir);
}
