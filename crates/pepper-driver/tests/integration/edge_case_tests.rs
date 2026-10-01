//! Edge-case language constructs exercised end-to-end through the JIT:
//! literals, casts, operator semantics, control flow, structs, globals.

use pepper_codegen::CodeGenerator;

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn shadowing() {
    // Variable shadowing in a nested block.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var x = 1;
    {
        var x = 2;
        return x + 10;
    }
}
"#
        ),
        12
    );
}

#[test]
fn recursion() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
fact(n: int): int {
    if (n <= 1) { return 1; }
    return n * fact(n - 1);
}
test(): int {
    return fact(6) / 720;
}
"#
        ),
        1
    );
}

#[test]
fn else_if_chain() {
    // `else if` is an extension over the reference grammar, which requires a
    // block after `else` (LexyParser.h Branch rule).
    let src = r#"
test(): int {
    var x = 5;
    if (x < 3) {
        return 1;
    } else if (x < 5) {
        return 2;
    } else {
        return 4;
    }
}
"#;
    assert_eq!(compile_jit_with_runtime(src), 4);
}

#[test]
fn nested_ternary() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var x = 2;
    return (x == 1 ? 10 : x == 2 ? 20 : 30);
}
"#
        ),
        20
    );
}

#[test]
fn hex_and_exponent_literals() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var h = 0xFF;
    var e = 1.5e2;
    return (h - 255) + ((e as int) - 150);
}
"#
        ),
        0
    );
}

#[test]
fn hex_only() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var h = 0xFF;
    return h - 255;
}
"#
        ),
        0
    );
}

#[test]
fn exponent_only() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var e = 1.5e2;
    return (e as int) - 150;
}
"#
        ),
        0
    );
}

#[test]
fn negative_division() {
    // C semantics: truncation toward zero, remainder sign follows dividend.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var q = -7 / 2;
    var r = -7 % 2;
    return (q + 3) * 10 + (r + 1);
}
"#
        ),
        0
    );
}

#[test]
fn i8_u8() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    i8 a = 100;
    u8 b = 200;
    return (a + b) - 300;
}
"#
        ),
        0
    );
}

#[test]
fn default_params() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
add(a: int, b: int = 10): int {
    return a + b;
}
test(): int {
    return add(5) - 15;
}
"#
        ),
        0
    );
}

#[test]
fn operator_overload_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x = 0;
    int y = 0;
    construct(this.x = 0, this.y = 0) {}
    Point +(other: Point) {
        return Point(x + other.x, y + other.y);
    }
}
test(): int {
    var p = Point(1, 2);
    var q = Point(3, 4);
    var r = p + q;
    return (r.x - 4) * 10 + (r.y - 6);
}
"#
        ),
        0
    );
}

#[test]
fn method_chaining() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = "a";
    s.append("b");
    s.append("c");
    return s.length() - 3;
}
"#
        ),
        0
    );
}

#[test]
fn compound_assign_indexed() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a[0] += 10;
    a[1] *= 3;
    return (a[0] - 11) * 10 + (a[1] - 6);
}
"#
        ),
        0
    );
}

#[test]
fn compound_assign_indexed_nested() {
    // `a[i] += x` inside if/while bodies must expand to the tmp/get/set pair
    // too — a bare __index_set rewrite would drop the read-modify-write.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    var i = 0;
    while (i < 2) {
        a[0] += 10;
        i += 1;
    }
    if (a[0] == 21) {
        a[0] += 1;
    }
    return a[0] - 22;
}
"#
        ),
        0
    );
}

#[test]
fn nested_member_access() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Inner { int v = 7; }
struct Outer { Inner i; }
test(): int {
    var o = Outer();
    o.i = Inner();
    return o.i.v - 7;
}
"#
        ),
        0
    );
}

#[test]
fn void_function() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import async;
const g = async.Atomic<int>(0);
bump(): void {
    g.store(g.load() + 5);
}
test(): int {
    bump();
    bump();
    return g.load() - 10;
}
"#
        ),
        0
    );
}

#[test]
fn global_variable() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import async;
const counter = async.Atomic<int>(1);
test(): int {
    counter.fetch_add(41);
    return counter.load() - 42;
}
"#
        ),
        0
    );
}

#[test]
fn int_overflow_wrap() {
    // LLVM add wraps: INT_MAX + 1 == INT_MIN.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = 2147483647;
    return (m + 1) - (-2147483648);
}
"#
        ),
        0
    );
}

#[test]
fn crlf_source() {
    // CRLF line endings must parse and run identically.
    assert_eq!(
        compile_jit_with_runtime("test(): int {\r\n    return 40 + 2;\r\n}\r\n"),
        42
    );
}

#[test]
fn struct_return_from_function() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Box { int v = 0; construct(this.v = 0) {} }
make(v: int): Box {
    return Box(v);
}
test(): int {
    var b = make(9);
    return b.v - 9;
}
"#
        ),
        0
    );
}

#[test]
fn array_pass_by_ref() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
sum(a: Array<int>): int {
    var s = 0;
    var i = 0;
    while (i < a.count()) {
        s += a[i];
        i += 1;
    }
    return s;
}
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    sum(a);
    a.append(4);
    return sum(a) - 10;
}
"#
        ),
        0
    );
}

#[test]
fn unary_ops() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = -(3 + 4);
    var b = !false;
    var c = ~0;
    return (a + 7) * 100 + (b - 1) * 10 + (c + 1);
}
"#
        ),
        0
    );
}

#[test]
fn bitwise_combo() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = (6 & 3) + (5 | 2) + (9 ^ 1) + (~4 & 7);
    return a - (2 + 7 + 8 + 3);
}
"#
        ),
        0
    );
}

#[test]
fn shift_assign() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = 1;
    a <<= 3;
    a >>= 1;
    return a - 4;
}
"#
        ),
        0
    );
}

#[test]
fn logical_short_circuit() {
    // `&&`/`||` short-circuit: neither line runs boom(), so side stays 0.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import async;
const side = async.Atomic<int>(0);
boom(): bool {
    side.store(1);
    return true;
}
test(): int {
    var r = false && boom();
    var s = true || boom();
    return (r as int) + (s as int) * 10 + side.load();
}
"#
        ),
        10
    );
}

#[test]
fn logical_short_circuit2() {
    // Short-circuit: `false && boom()` and `true || boom()` skip boom().
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import async;
const side = async.Atomic<int>(0);
boom(): bool {
    side.store(1);
    return true;
}
test(): int {
    var r = false && boom();
    if (r) { return -1; }
    var s = true || boom();
    if (!s) { return -2; }
    return side.load();
}
"#
        ),
        0
    );
}

#[test]
fn double_type() {
    // C-style `(int)e` is NOT a cast (only `as` is spec'd). `(int)` parses as
    // a TypeLiteral expression, so `return (int)` is a statement missing its
    // `;` before `e`: an error rather than a cast. The working form is
    // `e as int`.
    let src = r#"
test(): int {
    double d = 1.5;
    var e = d * 4.0;
    return (int)e - 6;
}
"#;
    let error = pepper_parser::parser::parse_source_diag(src).unwrap_err();
    assert_eq!(error.message, "expected ';'");

    // Double arithmetic must stay in the float domain: `1.5 + 2.5` is f64 math
    // (4.0), not integer truncation (3) — guards result_type's float detection.
    // Declared `double` on purpose: implicit `var` inference types binary ops
    // as auto/i32, a separate gap this test must not depend on.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    double d = 1.5 + 2.5;
    return (d as int) - 4;
}
"#
        ),
        0
    );
}

#[test]
fn as_cast() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var e = 1.5e2 as int;
    return e - 150;
}
"#
        ),
        0
    );
}

#[test]
fn paren_cast() {
    // C-style `(int)x` is NOT a cast (only `as` is spec'd); it must not parse.
    let src = r#"
test(): int {
    var e = (int)1.5e2;
    return e - 150;
}
"#;
    assert!(pepper_parser::parser::parse_source("test.pep", src).is_err());
}

#[test]
fn empty_blocks() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var x = 1;
    if (x == 2) {}
    while (false) {}
    return x;
}
"#
        ),
        1
    );
}

#[test]
fn struct_method_call_from_function() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Counter {
    int n = 0;
    construct(this.n = 0) {}
    inc(by: int): int {
        n += by;
        return n;
    }
}
test(): int {
    var c = Counter();
    c.inc(3);
    c.inc(4);
    return c.n - 7;
}
"#
        ),
        0
    );
}

#[test]
fn destructor_runs() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import async;
const destroyed = async.Atomic<int>(0);
struct T {
    int v = 0;
    construct(this.v = 0) {}
    destruct {
        destroyed.fetch_add(1);
    }
}
test(): int {
    {
        var t = T();
    }
    return destroyed.load() - 1;
}
"#
        ),
        0
    );
}

#[test]
fn field_shadows_global() {
    // A bare symbol in a struct method that names both a field and a
    // file-scope global must resolve to the field (member-lookup order);
    // routing it to the global is a silent miscompile.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
const v = 100;
struct Box {
    int v = 7;
    peek(): int { return v; }
}
test(): int {
    var b = Box();
    return b.peek() - 7;
}
"#
        ),
        0
    );
}

#[test]
fn cast_to_bool() {
    // A bool cast target compares != 0: truncation keeps only the low bit
    // (`2 as bool` would be false), and fptosi to i1 is poison for > 0.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var x = 2;
    if (x as bool) { return 1; }
    return 0;
}
"#
        ),
        1
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var f = 2.5;
    if (f as bool) { return 1; }
    return 0;
}
"#
        ),
        1
    );
}

#[test]
fn unsigned_cast_to_float() {
    // Unsigned and bool sources convert to float via uitofp: `u8 200 as
    // float` is 200.0, not the signed reinterpretation -56.0.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 b = 200;
    var f = b as float;
    return (f as int) - 200;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var t = true;
    var f = t as float;
    return (f as int) - 1;
}
"#
        ),
        0
    );
}

#[test]
fn binary_result_casts_as_signed() {
    // Binary ops promote to canonical i32/i64, so a cast of a negative
    // binary result with an unsigned lhs must sign-convert: `(u8 200 - 300)
    // as float` is -100.0, not the unsigned reinterpretation 4294967196.0.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 a = 200;
    var f = (a - 300) as float;
    return (f as int) + 100;
}
"#
        ),
        0
    );
    // Both operands typed: exercises the `ops::result_type` branch, which
    // promotes `u8 - u8` to signed i32.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 a = 200;
    u8 b = 44;
    var f = (b - a) as float;
    return (f as int) + 156;
}
"#
        ),
        0
    );
}

#[test]
fn chained_pointer_arithmetic() {
    // `p + 1 + 1` must stride by the pointee (1 byte per step): the inner
    // binary's element type comes from its lhs, not a fallback i32.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    String s = "abcdef";
    __ptr<char> p = s.c_str();
    __ptr<char> r = p + 1 + 1;
    return r[0] as int - 99;
}
"#
        ),
        0
    );
}

#[test]
fn float_cast_to_unsigned() {
    // Unsigned cast targets use fptoui: `4e9 as u32` is representable in u32
    // (not in i32), so fptosi would poison/saturate to -2147483648. The
    // round-tripped value is 4000000000, whose i32 bit pattern is
    // -294967296.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var f = 4000000000.0;
    u32 b = f as u32;
    return (b as long) as int;
}
"#
        ),
        -294967296
    );
}

#[test]
fn unsigned_binary_result_keeps_unsignedness() {
    // u32 operands keep their unsignedness through promotion (C-style: only
    // narrower-than-int operands promote to signed), so a cast of the result
    // zero-extends: `(u32 3e9 + 1) as long` is ~3.0e9, not -1294e6.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u32 a = 3000000000;
    long c = (a + 1) as long;
    return (c / 1000000) as int - 3000;
}
"#
        ),
        0
    );
}

#[test]
fn float_literal_binary_produces_float() {
    // A float literal rhs makes the binary produce f32/f64; value_sema_type
    // must not report the promoted *int* type for it, or coerce hits a
    // FloatValue named "i32" and panics.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int i = 4;
    double d = 0.0;
    d = i * 1.5;
    return (d as int) - 6;
}
"#
        ),
        0
    );
}

#[test]
fn shift_result_type_follows_lhs() {
    // Shifts are excluded from the usual arithmetic conversions: the result
    // takes the promoted *left* operand's type, so an unsigned shift amount
    // must not turn a signed `>>` into a logical shift.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int x = -8;
    u32 s = 2;
    return (x >> s) + 2;
}
"#
        ),
        0
    );
    // Compound form takes the same path.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int x = -8;
    u32 s = 2;
    x >>= s;
    return x + 2;
}
"#
        ),
        0
    );
    // An unsigned lhs still shifts logically.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u32 a = 8;
    return (a >> 1) - 4;
}
"#
        ),
        0
    );
}

#[test]
fn shift_result_nested_ops_stay_signed() {
    // value_sema_type must report the same type codegen_binary produces for
    // a shift (promoted lhs), or nested ops on the shift pick unsigned
    // variants: division becomes udiv, comparison ULT, cast uitofp.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int x = -8;
    u32 s = 2;
    return ((x >> s) / 2) + 1;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int x = -8;
    u32 s = 2;
    if ((x >> s) < 0) { return 0; }
    return 1;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int x = -8;
    u32 s = 2;
    double d = (x >> s) as double;
    return (d as int) + 2;
}
"#
        ),
        0
    );
}

#[test]
fn float_valued_unresolved_rhs_produces_float() {
    // A rhs that value_sema_type cannot resolve but that codegens to a float
    // (a binary of float literals) must not take the int-promotion arm, or
    // coerce hits into_int_value() on a FloatValue and panics.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int i = 4;
    double d = 0.0;
    d = i * (1.5 + 1.0);
    return (d as int) - 10;
}
"#
        ),
        0
    );
}

#[test]
fn comparison_as_arithmetic_operand_is_bool() {
    // A comparison produces an i1; value_sema_type must name it `bool`, or
    // the outer binary's coerce is a no-op and apply_op sign-extends
    // `true` into -1.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int a = 1;
    int b = 2;
    return (a < b) + 1 - 2;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int a = 1;
    int b = 2;
    return 1 + (a < b) - 2;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int a = 1;
    return (a == 1) * 5 - 5;
}
"#
        ),
        0
    );
}

#[test]
fn ternary_float_branch_produces_float() {
    // A ternary with a float-literal branch produces a float even when the
    // other branch is only resolvable as a variable; value_sema_type cannot
    // resolve the ternary, so is_float_valued must catch it.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int i = 4;
    double d = 2.5;
    double r = 0.0;
    r = i * (true ? 1.5 : d);
    return (r as int) - 6;
}
"#
        ),
        0
    );
}

#[test]
fn unary_float_operand_resolves() {
    // `-d` / `++d` on a double resolve to the operand's type, so an outer
    // binary sees a float rhs and does not take the int-promotion arm.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int i = 4;
    double d = 2.0;
    double r = 0.0;
    r = i * (-d);
    return (r as int) + 8;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int i = 4;
    double d = 2.0;
    double r = 0.0;
    r = i * (++d);
    return (r as int) - 12;
}
"#
        ),
        0
    );
}

#[test]
fn neg_and_bitnot_on_unsigned_promote_to_signed() {
    // `-x` / `~x` are emitted at the operand's width as signed two's
    // complement; value_sema_type must name the promoted type (narrower-than-
    // int unsigned promotes to signed int), or consumers zero-extend:
    // `-(u8 1)` becomes 255 instead of -1.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 b = 1;
    return (-b) + 1;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 b = 1;
    return (~b) + 2;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 b = 1;
    double f = (-b) as double;
    return (f as int) + 1;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    byte b = 1;
    return (-b) + 1;
}
"#
        ),
        0
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 b = 1;
    int r = 0;
    if ((-b) < 0) { r = 1; }
    return r;
}
"#
        ),
        1
    );
    // A u32 operand keeps its unsignedness (C-style: as wide as the
    // promoted result), so `-(u32)` stays an unsigned value.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u32 b = 1;
    u32 n = -b;
    return (n == 4294967295) ? 0 : 1;
}
"#
        ),
        0
    );
}


#[test]
fn nested_call_args() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
f(a: int, b: int): int {
    return a * 10 + b;
}
test(): int {
    return f(f(1, 2), f(3, 4)) - 154;
}
"#
        ),
        0
    );
}

#[test]
fn while_with_complex_condition() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var i = 0;
    var sum = 0;
    while (i < 10) {
        if (i % 2 == 0 and i > 0) {
            sum += i;
        }
        i += 1;
    }
    return sum - 20;
}
"#
        ),
        0
    );
}

#[test]
fn ternary_with_calls() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
pick(x: int): int {
    return x * 2;
}
test(): int {
    var r = pick(3) > 5 ? pick(4) : pick(1);
    return r - 8;
}
"#
        ),
        0
    );
}

#[test]
fn string_in_array() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<String>();
    a.append("ab");
    a.append("cd");
    a[0].append("ef");
    return (a[0] == "abef" ? 1 : -1) + (a[1] == "cd" ? 1 : -1);
}
"#
        ),
        2
    );
}

#[test]
fn struct_field_of_array() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Holder {
    Array<int> items;
    construct() {}
}
test(): int {
    var h = Holder();
    h.items = Array<int>();
    h.items.append(5);
    h.items.append(6);
    return h.items[0] + h.items[1] - 11;
}
"#
        ),
        0
    );
}

#[test]
fn reserved_like_identifiers() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var interface = 3;
    var return_value = 4;
    var const_pool = 5;
    return interface + return_value + const_pool - 12;
}
"#
        ),
        0
    );
}

#[test]
fn unicode_comment_and_string() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
# café — üñíçødé comment
test(): int {
    var s = "héllo";
    return s.length() - 5;
}
"#
        ),
        0
    );
}

#[test]
fn nonconst_global_init() {
    // Non-constant global initializers are stored by __pep_global_init, which
    // only runs if the JIT calls run_static_constructors — without it every
    // such global (including every String global) stays at its null/zero base.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
mk(): int { return 5; }
const g = mk();
test(): int { return g - 5; }
"#
        ),
        0
    );
}

#[test]
fn string_global_init() {
    // Struct globals are constructor calls (non-constant), built by the same
    // __pep_global_init path; a null global faults on first use. The
    // constructor copies a String, so its init runs String code too.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
[Shared]
struct Name {
    const length: ulong;
    construct(String text) { length = text.length(); }
}
const s = Name("pepper");
test(): int { return (s.length as int) - 6; }
"#
        ),
        0
    );
}

#[test]
fn generic_cast_target() {
    // A cast target naming a type parameter must be substituted by the
    // specialization passes (`v as T` → `v as int`).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
conv<T>(T v): int { return v as T; }
test(): int { return conv<int>(42) - 42; }
"#
        ),
        0
    );
}

#[test]
fn bool_from_nonzero() {
    // A bool initialized from a wider int must compare != 0, not truncate to
    // the low bit (`2` truncated is false; `2 != 0` is true).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    bool b = 2;
    if (b) { return 1; }
    return 0;
}
"#
        ),
        1
    );
}

#[test]
fn compound_assign_float_literal_stays_at_lhs_width() {
    // `x += 2.5` runs the add at the lhs's width (the rhs is converted to
    // the lhs type first): feeding the unconverted float into the op would
    // promote to f64 and store an f64 into the i32/i8 slot — opaque pointers
    // hide that from module verify, so it surfaces as garbage (int) or an
    // access violation (u8) at runtime.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    int x = 5;
    x += 2.5;
    return x + 1;
}
"#
        ),
        8
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 x = 5;
    x += 2.0;
    return x + 1;
}
"#
        ),
        8
    );
}

#[test]
fn compound_assign_bool_is_nonzero_test() {
    // C 6.3.1.4: conversion to _Bool is a nonzero test, not a low-bit
    // truncation — `b += 2` from true must stay true (a trunc would give 0).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    bool b = true;
    b += 2;
    return b as int;
}
"#
        ),
        1
    );
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    bool b = false;
    b += 2;
    return b as int;
}
"#
        ),
        1
    );
}

#[test]
fn compound_assign_u8_wraps_at_int_width() {
    // C usual conversions: `u8 += u8` promotes both to int, adds there, then
    // converts back — 200 + 100 = 300 wraps to 44 at the store.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    u8 x = 200;
    x += 100;
    return x as int + 1;
}
"#
        ),
        45
    );
}

// ── assert with a null message ──────────────────────────────────────────────

#[test]
fn assert_with_null_message() {
    // A null `String` message is only read when the assertion fails.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    assert(true, __null);
    var message: String = __null;
    assert(1 < 2, message);
    return 7;
}
"#
        ),
        7
    );
}

// ── Identity comparison: `===` and `!==` ────────────────────────────────────

#[test]
fn identity_comparison() {
    // References compare addresses, even when the type defines `==`
    // (`String` compares content); POD values compare like `==`/`!=`.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct S { int x = 0; }
test(): int {
    var a = 3;
    var b = 3.5;
    var s = S();
    var t = s;
    var u = S();
    var r = 0;
    if (a === 3) { r = r + 1; }
    if (b === 3.5 && !(b !== 3.5)) { r = r + 2; }
    if (s === t && !(s !== t)) { r = r + 4; }
    if (s !== u) { r = r + 8; }
    if (a !== 4) { r = r + 16; }
    var x = "hi";
    var y = "hi";
    if (x == y && x !== y && x === x) { r = r + 32; }
    if (s !== __null) { r = r + 64; }
    return r;
}
"#
        ),
        127
    );
}

// ── panic and assert take a String ──────────────────────────────────────────

#[test]
fn assert_takes_a_string_message() {
    // A computed message is an ordinary `String` argument.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var name = "count";
    assert(1 + 1 == 2, name + " must add up");
    assert(true, "literal");
    return 5;
}
"#
        ),
        5
    );
}

#[test]
fn trait_argument_naming_the_implementing_generic() {
    // `Twin<T>` with its `T` bound to `Box<T>`: substituting the trait's `T`
    // must not recurse into the `T` of the argument.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
trait Twin<T> {
    T twin();
}
struct Box<T> {
    T value;
    Box<T> twin() { return this; }
}
extend Box<T> with Twin<Box<T>> {}
test(): int {
    var b = Box<int>();
    b.value = 4;
    return b.twin().value - 4;
}
"#
        ),
        0
    );
}

#[test]
fn generic_method_call_with_type_arguments_in_generic_code() {
    // `holder.same<T>(v)` inside a generic function is specialized with the
    // function's type argument.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Holder {
    int unused;
    same<T>(value: T): T {
        return value;
    }
}
pass<T>(value: T): T {
    var holder = Holder();
    return holder.same<T>(value);
}
test(): int {
    return pass<int>(5) - 5;
}
"#
        ),
        0
    );
}

#[test]
fn constructor_parameter_named_size() {
    // The constructor's allocation size is a hidden local; a parameter the
    // user names `size` must not be shadowed by it.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Buffer {
    var _size: ulong = 0;
    construct(ulong size = 0) {
        _size = size;
    }
    size(): ulong { return _size; }
}
test(): int {
    return Buffer(7).size() as int;
}
"#
        ),
        7
    );
}

#[test]
fn struct_field_of_its_own_type() {
    // A struct-typed field is a reference slot, so a struct may name itself.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Node {
    var value: int;
    var parent: Node;
    construct(this.value = 0) {}
}
test(): int {
    var root = Node(4);
    var child = Node(5);
    child.parent = root;
    return child.parent.value * 10 + child.value;
}
"#
        ),
        45
    );
}

#[test]
fn structs_that_refer_to_each_other() {
    // A cycle through two struct types, the second declared after the first.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct A {
    var b: B;
}
struct B {
    var a: A;
    var x: int;
}
test(): int {
    var a = A();
    a.b = B();
    a.b.x = 7;
    a.b.a = a;
    var x = a.b.a.b.x;
    a.b.a = __null;
    return x;
}
"#
        ),
        7
    );
}

#[test]
fn generic_struct_field_of_its_own_type() {
    // Releasing the head of a self-referential chain destroys every link.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import async;
const destroyed = async.Atomic<int>(0);
struct Link<T> {
    var value: T;
    var next: Link<T>;
    construct(T v) { value = v; }
    destruct { destroyed.fetch_add(1); }
}
test(): int {
    {
        var head = Link<int>(1);
        head.next = Link<int>(2);
        head.next.next = Link<int>(3);
    }
    return destroyed.load();
}
"#
        ),
        3
    );
}

#[test]
fn index_through_a_with_binding_from_a_generic_method() {
    // The binding's type is the scope's generic parameter until the scope's
    // struct is specialized; `list[0]` must still reach the Array indexer.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Box<T> {
    T items;
    construct(this.items = __default<T>()) {}
    T enter() { return items; }
    exit() {}
}
struct Holder<T> {
    T items;
    construct(this.items = __default<T>()) {}
    Box<T> open() { return Box<T>(items); }
}
test(): int {
    var a = Array<String>();
    a.append("line");
    var h = Holder<Array<String>>(a);
    with (var list = h.open()) {
        var x = list[0];
        if (x != "line") { return 1; }
    }
    return 0;
}
"#
        ),
        0
    );
}

#[test]
fn float_comparisons_with_nan_follow_ieee_754() {
    // `!=` is the negation of `==` (unordered: true when either side is
    // NaN), while `==`, `<`, `<=`, `>`, `>=` are false against NaN. A NaN
    // is true as a condition, as in C.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    double zero = 0.0;
    var n = zero / zero;
    float f = n;
    if (!(n != n)) { return 1; }
    if (!(n != 1.0)) { return 2; }
    if (n == n) { return 3; }
    if (n < 1.0 || n <= 1.0 || n > 1.0 || n >= 1.0) { return 4; }
    if (!(f != f)) { return 5; }
    if (f == f) { return 6; }
    if (!n) { return 7; }
    if (!(1.0 != 2.0) || 1.0 != 1.0) { return 8; }
    return 0;
}
"#
        ),
        0
    );
}
