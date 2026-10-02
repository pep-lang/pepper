//! Interpolated strings, `$"n = {n}"`: each snippet is compiled with the
//! runtime and JIT-executed through `test`. Their errors are in
//! `diagnostic_tests`.

use crate::support::compile_jit_with_runtime;

#[test]
fn integers_bool_and_strings() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var name = "Pepper";
    var count = 3;
    ulong big = 0xFFFFFFFFFFFFFFFF;
    short negative = -5;
    var ready = true;
    var s = $"{name}: {count} of {big}, {negative}, {ready}";
    if (!(s == "Pepper: 3 of 18446744073709551615, -5, true")) { return -1; }
    if (!($"" == "")) { return -2; }
    if (!($"plain" == "plain")) { return -3; }
    if (!($"{name}" == "Pepper")) { return -4; }
    if (!($"{count}{count}" == "33")) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn braces_and_escapes() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var x = 1;
    if (!($"{{x}} = {x}" == "{x} = 1")) { return -1; }
    if (!($"}}{{" == "}{")) { return -2; }
    if (!($"a\t{x}\n\"q\"" == "a\t1\n\"q\"")) { return -3; }
    if (!($"é{x}é" == "é1é")) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn to_string_trait_and_overrides() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    var x: int = 0;
    var y: int = 0;
    construct(this.x = 0, this.y = 0) {}
}

# Inside its own to_string(), a bare `{x}` still converts the field.
extend Point with ToString {
    to_string(): String {
        return $"({x}, {y})";
    }
}

struct Celsius {
    var degrees: int = 0;
    construct(this.degrees = 0) {}
}

to_string<Celsius>(value: Celsius): String {
    var degrees = value.degrees;
    return $"{degrees}C";
}

label<T>(value: T): String {
    return $"<{value}>";
}

test(): int {
    var p = Point(1, 2);
    if (!($"p = {p}" == "p = (1, 2)")) { return -1; }
    var shape: ToString = p;
    if (!($"{shape}" == "(1, 2)")) { return -2; }
    var t = Celsius(21);
    if (!($"{t}" == "21C")) { return -3; }
    if (!(label(p) == "<(1, 2)>")) { return -4; }
    if (!(label(7) == "<7>")) { return -5; }
    if (!(label(t) == "<21C>")) { return -6; }
    var b = StringBuilder();
    b.append("built");
    if (!($"{b}!" == "built!")) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn leaks_nothing() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    var x: int = 0;
    construct(this.x = 0) {}
}

extend Point with ToString {
    to_string(): String {
        return $"P{x}";
    }
}

test(): int {
    var before = _pep_live_allocs();
    {
        var p = Point(4);
        var name = "n";
        var i = 0;
        while (i < 10) {
            var s = $"{name} {i} {p} {{}}";
            i = i + 1;
        }
    }
    if (_pep_live_allocs() != before) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn expressions() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    var x: int = 0;
    var y: int = 0;
    construct(this.x = 0, this.y = 0) {}
}

twice(n: int): int {
    return n * 2;
}

greet(name: String): String {
    return "hi " + name;
}

test(): int {
    var a = 2;
    var b = 3;
    var p = Point(4, 5);
    var items = Array<int>();
    items.append(7);
    if (!($"sum {a + b}, {p.x}, {twice(a)}, {items[0]}" == "sum 5, 4, 4, 7")) { return -1; }
    if (!($"{a > b ? "big" : "small"}" == "small")) { return -2; }
    if (!($"{greet("you")}!" == "hi you!")) { return -3; }
    if (!($"{ a * (b + 1) }" == "8")) { return -4; }
    if (!($"[{$"<{a}>"}]" == "[<2>]")) { return -5; }
    if (!($"{"}"}{'{' == '{'}" == "}true")) { return -6; }
    if (!($"{items.count} item" == "1 item")) { return -7; }
    if (!($"{-a}" == "-2")) { return -8; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn expressions_leak_nothing() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    var x: int = 0;
    construct(this.x = 0) {}
}

extend Point with ToString {
    to_string(): String {
        return $"P{x}";
    }
}

make(x: int): Point {
    return Point(x);
}

test(): int {
    var before = _pep_live_allocs();
    {
        var points = Array<Point>();
        points.append(Point(1));
        var i = 0;
        while (i < 10) {
            var s = $"{make(i)} {points[0]} {"a" + "b"} {i % 2 == 0 ? make(1) : points[0]}";
            i = i + 1;
        }
    }
    if (_pep_live_allocs() != before) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn format_specifications() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    var x: int = 0;
    construct(this.x = 0) {}
}

extend Point with ToString {
    to_string(): String {
        return $"P{x}";
    }
}

test(): int {
    var n = 255;
    var negative = -42;
    var name = "ab";
    ulong big = 0xFFFFFFFFFFFFFFFF;
    byte small = 10;
    if (!($"[{n:>6}][{n:<6}][{n:^7}][{n:6}]" == "[   255][255   ][  255  ][   255]")) { return -1; }
    if (!($"[{name:6}][{name:>6}][{name:*^6}][{name:1}]" == "[ab    ][    ab][**ab**][ab]")) { return -2; }
    if (!($"{n:x} {n:X} {n:b} {n:o} {n:d}" == "ff FF 11111111 377 255")) { return -3; }
    if (!($"{n:08x} {negative:08} {negative:x} {n:+} {negative:+} {0:+}" == "000000ff -0000042 -2a +255 -42 +0")) { return -4; }
    if (!($"{big:x} {small:b} {-9223372036854775807 - 1:x}" == "ffffffffffffffff 1010 -8000000000000000")) { return -5; }
    if (!($"[{Point(3):>5}][{true:>6}][{n > 3 ? "yes" : "no":>5}]" == "[   P3][  true][  yes]")) { return -6; }
    if (!($"[{"é":-^5}][{n:é>5}]" == "[--é--][éé255]")) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn string_format() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import async;

struct Point {
    var x: int = 0;
    construct(this.x = 0) {}
}

extend Point with ToString {
    to_string(): String {
        return $"P{x}";
    }
}

const order = async.Atomic<int>(0);

# Records the order of the calls in its result's digits.
next(value: int): int {
    order.store(order.load() * 10 + value);
    return value;
}

test(): int {
    var n = 255;
    var name = "ab";
    if (!(String.format("{0} + {1} = {2:>4}", 2, 3, 2 + 3) == "2 + 3 =    5")) { return -1; }
    if (!(String.format("{1} {0} {0:x}", n, name) == "ab 255 ff")) { return -2; }
    if (!(String.format("{0}", Point(1)) == "P1")) { return -3; }
    if (!(String.format("{0} {0:x}", n) == "255 ff")) { return -4; }
    if (!(String.format("none {{}}") == "none {}")) { return -5; }
    if (!(String.format("") == "")) { return -6; }
    # Each argument is evaluated once, left to right, whatever the order
    # of the braces.
    if (!(String.format("{2}{1}{0}{2}", next(1), next(2), next(3)) == "3213")) { return -7; }
    if (order.load() != 123) { return -8; }
    if (!($"<{String.format("{0:>3}", n + 1)}>" == "<256>")) { return -9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn formats_leak_nothing() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    var x: int = 0;
    construct(this.x = 0) {}
}

extend Point with ToString {
    to_string(): String {
        return $"P{x}";
    }
}

make(x: int): Point {
    return Point(x);
}

test(): int {
    var before = _pep_live_allocs();
    {
        var points = Array<Point>();
        points.append(Point(1));
        var i = 0;
        while (i < 10) {
            var s = $"{make(i):>4} {points[0]:<3} {i:04x} {"a" + "b":^5}";
            var t = String.format("{1} {0} {1:>5} {0:x}", i, make(i));
            var u = String.format("{0} {1}", points[0], "x" + "y");
            i = i + 1;
        }
    }
    if (_pep_live_allocs() != before) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn closure_bodies_may_change_their_own_locals() {
    // A closure's body does not run in place, so it is not checked for
    // assignments.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
call(f: () => int): int {
    return f();
}

test(): int {
    var s = $"{call(() => { var c = 1; c += 2; c++; return c; })}";
    if (!(s == "4")) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn floats_print_their_shortest_text() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    if (!(to_string(0.1) == "0.1")) { return -1; }
    if (!(to_string(3.0) == "3.0")) { return -2; }
    if (!(to_string(-2.5) == "-2.5")) { return -3; }
    if (!(to_string(1.0e20) == "1e+20")) { return -4; }
    if (!(to_string(1.0e15) == "1000000000000000.0")) { return -5; }
    if (!(to_string(1.0e16) == "1e+16")) { return -6; }
    if (!(to_string(0.0001) == "0.0001")) { return -7; }
    if (!(to_string(0.00001) == "1e-05")) { return -8; }
    if (!(to_string(1.0 / 3.0) == "0.3333333333333333")) { return -9; }
    float third = 1.0 / 3.0;
    if (!(to_string(third) == "0.33333334")) { return -10; }
    if (!(to_string(0.0) == "0.0")) { return -11; }
    if (!(to_string(-0.0) == "-0.0")) { return -12; }
    var zero = 0.0;
    if (!(to_string(1.0 / zero) == "inf")) { return -13; }
    if (!(to_string(-1.0 / zero) == "-inf")) { return -14; }
    if (!(to_string(zero / zero) == "nan")) { return -15; }
    if (!(to_string(1.7976931348623157e308) == "1.7976931348623157e+308")) { return -16; }
    if (!(to_string(5.0e-324) == "5e-324")) { return -17; }
    var price = 4.5;
    if (!($"{price} and {price * 2.0}" == "4.5 and 9.0")) { return -18; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn floats_read_back_exactly() {
    // Random bit patterns and the edge cases of the shortest-digits search
    // (#411): every text parses back to the same bits, and at a power of 2,
    // where the interval below the value is half as wide, the digits are
    // still the shortest (the old search printed 17 digits there).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
double_reads_back(bits: ulong): bool {
    var value = unsafe_cast<double>(bits);
    if (value != value || value - value != 0) {
        return true;
    }
    var text = to_string(value);
    var back = double.parse(text);
    if (back.is_value() && unsafe_cast<ulong>(back.value()) == bits) {
        return true;
    }
    print($"double {bits:x} printed as {text} did not read back");
    return false;
}

float_reads_back(bits: uint): bool {
    float value = unsafe_cast<float>(bits);
    if (value != value || value - value != 0) {
        return true;
    }
    var text = to_string(value);
    var back = float.parse(text);
    if (back.is_value() && unsafe_cast<uint>(back.value()) == bits) {
        return true;
    }
    print($"float {bits:x} printed as {text} did not read back");
    return false;
}

test(): int {
    ulong state = 88172645463325252;
    var failures = 0;
    var i = 0;
    while (i < 100000) {
        state = state ^ (state << 13);
        state = state ^ (state >> 7);
        state = state ^ (state << 17);
        # Count the failures, so the printed ones show a pattern.
        if (!double_reads_back(state)) { failures = failures | 1; }
        if (!double_reads_back(state & 0xfff0000000000000)) { failures = failures | 2; }
        if (!float_reads_back((state >> 32) as uint)) { failures = failures | 4; }
        i = i + 1;
    }
    if (failures != 0) { return 0 - failures; }
    # Every power of 2 and its neighbors, subnormals included.
    ulong exponent = 0;
    while (exponent < 2047) {
        var base = exponent << 52;
        if (!double_reads_back(base) || !double_reads_back(base + 1)) { return -4; }
        if (!double_reads_back(base | 0xfffffffffffff)) { return -5; }
        exponent = exponent + 1;
    }
    uint narrow_exponent = 0;
    while (narrow_exponent < 255) {
        var base = narrow_exponent << 23;
        if (!float_reads_back(base) || !float_reads_back(base + 1)) { return -6; }
        if (!float_reads_back(base | 0x7fffff)) { return -7; }
        narrow_exponent = narrow_exponent + 1;
    }
    # Powers of 10 print as themselves.
    var power = 1.0;
    var digits = 0;
    while (digits < 16) {
        if (!(to_string(power) == "1" + "0".repeat(digits as ulong) + ".0")) { return -8; }
        power = power * 10.0;
        digits = digits + 1;
    }
    if (!(to_string(1.0e-4) == "0.0001")) { return -9; }
    if (!(to_string(1.0e22) == "1e+22")) { return -10; }
    if (!(to_string(1.0e23) == "1e+23")) { return -11; }
    if (!(to_string(1.0e-300) == "1e-300")) { return -12; }
    # The shortest digits at a power of 2.
    if (!(to_string(unsafe_cast<double>(0x4ab0000000000000)) == "5.986310706507379e+51")) { return -13; }
    if (!(to_string(unsafe_cast<double>(0x61f0000000000000)) == "5.758609657015292e+163")) { return -14; }
    if (!(to_string(unsafe_cast<float>(0x6b000000 as uint)) == "1.5474251e+26")) { return -15; }
    # The extremes: the largest double and float, the smallest normal and
    # subnormal values, and the largest subnormal.
    if (!(to_string(1.7976931348623157e308) == "1.7976931348623157e+308")) { return -16; }
    if (!(to_string(-1.7976931348623157e308) == "-1.7976931348623157e+308")) { return -17; }
    if (!(to_string(2.2250738585072014e-308) == "2.2250738585072014e-308")) { return -18; }
    if (!(to_string(unsafe_cast<double>(0x000fffffffffffff)) == "2.225073858507201e-308")) { return -19; }
    if (!(to_string(unsafe_cast<double>(1 as ulong)) == "5e-324")) { return -20; }
    float largest = 3.4028235e38;
    if (!(to_string(largest) == "3.4028235e+38")) { return -21; }
    if (!(to_string(unsafe_cast<float>(1 as uint)) == "1e-45")) { return -22; }
    if (!(to_string(unsafe_cast<double>(0x8000000000000000)) == "-0.0")) { return -23; }
    float negative_zero = unsafe_cast<float>(0x80000000 as uint);
    if (!(to_string(negative_zero) == "-0.0")) { return -24; }
    var zero = 0.0;
    if (!(to_string(0.0 - zero / zero) == "nan")) { return -25; }
    float narrow_infinity = (1.0 / zero) as float;
    if (!(to_string(narrow_infinity) == "inf")) { return -26; }
    if (!(to_string(-narrow_infinity) == "-inf")) { return -27; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn a_precision_rounds_a_float() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var pi = 3.14159265;
    if (!($"{pi:.2}" == "3.14")) { return -1; }
    if (!($"[{pi:8.3}]" == "[   3.142]")) { return -2; }
    if (!($"[{pi:<8.1}]" == "[3.1     ]")) { return -3; }
    if (!($"{pi:+.0}" == "+3")) { return -4; }
    if (!($"{pi:08.2}" == "00003.14")) { return -5; }
    if (!($"{-pi:08.2}" == "-0003.14")) { return -6; }
    if (!($"{2.7:.0}" == "3")) { return -7; }
    float f = 0.125;
    if (!($"{f:.2}" == "0.12")) { return -8; }
    if (!($"[{pi:>6}]" == "[3.14159265]")) { return -9; }
    if (!($"[{1.5:>6}]" == "[   1.5]")) { return -10; }
    if (!(String.format("{0:.1}|{0}", 0.25) == "0.2|0.25")) { return -11; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn tuples_convert_element_by_element() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    var x: int = 0;
    construct(this.x = 0) {}
    to_string(): String { return $"P{x}"; }
}

test(): int {
    var before = _pep_live_allocs();
    {
        var t = (1, "two");
        if (!($"{t}" == "(1, two)")) { return -1; }
        var nested = (1, (2.5, true));
        if (!($"{nested}" == "(1, (2.5, true))")) { return -2; }
        if (!(to_string((1, 2, 3, 4, 5, 6, 7, 8)) == "(1, 2, 3, 4, 5, 6, 7, 8)")) { return -3; }
        var p = (Point(3), "a");
        if (!($"{p:>10}" == "   (P3, a)")) { return -4; }
        var labeled = (line: 3, column: 7);
        if (!($"{labeled}" == "(3, 7)")) { return -5; }
    }
    if (_pep_live_allocs() != before) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn sizeof_interpolates_as_a_ulong() {
    // #338: `sizeof<T>()` had no type for inference, so the generic
    // `_pep_interpolate<T>` (and any generic call) could not infer `T`.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Span {
    var a: int = 0;
    var b: int = 0;
}

pick<T>(value: T): T {
    return value;
}

test(): int {
    ulong s = sizeof<Span>();
    if (!($"{sizeof<Span>()}" == $"{s}")) { return -1; }
    if (!($"{sizeof<int>()}" == "4")) { return -2; }
    if (!($"{sizeof<ulong>():>3}" == "  8")) { return -3; }
    ulong picked = pick(sizeof<short>());
    if (picked != 2) { return -4; }
    return 0;
}"#
        ),
        0
    );
}
