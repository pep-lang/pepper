//! Runtime checks (#265): integer overflow, division by zero and oversized
//! shifts panic with a located message; the integer types' `wrapping_`,
//! `checked_`, `saturating_` and `overflowing_` methods; and
//! `--no-runtime-checks`, which removes kinds of check from `-O1` up.

use crate::support::{compile_jit_with_runtime, parallel_map, run_linked_with};

/// Runs `body` (statements of `main`, which read the `int` `n`, 1 unless
/// the program is given an argument) compiled with `args`, and returns its
/// exit success and its output (standard output, then standard error).
fn run(name: &str, body: &str, args: &[&str]) -> (bool, String) {
    let source = format!(
        "import process;\nmain(): int {{\n    var n = 1;\n    if (process.arguments().count > 1) {{ n = 2; }}\n{}\n    return 0;\n}}\n",
        body
    );
    let output = run_linked_with(name, &source, args, |_| {});
    // A panic's message and the warnings go to standard error, what the
    // program prints to standard output: read both.
    let text = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
    (output.status.success(), text.replace('\r', ""))
}

/// Each case's body and the message it must panic with.
const PANICS: &[(&str, &str, &str)] = &[
    ("add", "    int x = 2147483647;\n    x = x + n;", "integer overflow in 'int' addition"),
    ("sub_unsigned", "    uint x = 0;\n    x = x - n;", "integer overflow in 'uint' subtraction"),
    ("mul_long", "    long x = 9223372036854775807;\n    x *= n + 1;", "integer overflow in 'long' multiplication"),
    ("negate", "    int x = -2147483647 - n;\n    x = -x;", "integer overflow in 'int' negation"),
    ("increment", "    ulong x = 0xFFFFFFFFFFFFFFFF;\n    x += n - 1;\n    x++;", "integer overflow in 'ulong' increment"),
    ("decrement", "    int x = -2147483647 - n;\n    x--;", "integer overflow in 'int' decrement"),
    ("power", "    int x = 10;\n    x = x ** (n * 10);", "integer overflow in 'int' exponentiation"),
    ("divide_zero", "    int x = 10 / (n - 1);", "division by zero"),
    ("remainder_zero", "    ulong x = 10;\n    x = x % ((n - 1) as ulong);", "division by zero"),
    ("divide_min", "    int x = -2147483647 - n;\n    x = x / -n;", "integer overflow in 'int' division"),
    ("shift", "    int x = 1 << (n * 32);", "shift count out of range for 'int': must be from 0 to 31"),
    ("shift_negative", "    long x = 1;\n    x = x >> (n - 2);", "shift count out of range for 'long': must be from 0 to 63"),
];

#[test]
fn overflowing_operations_panic_with_their_location() {
    let results = parallel_map(PANICS, |&(name, body, message)| (name, message, run(&format!("overflow_{}", name), body, &[])));
    for (name, message, (success, stderr)) in results {
        assert!(!success, "{}: expected a panic", name);
        // Located: <path>/overflow_<name>.pep:<line>:<column>: panic: <message>.
        let line = stderr.lines().find(|l| l.contains(message)).unwrap_or_else(|| panic!("{}: no '{}' in:\n{}", name, message, stderr));
        let at = format!("overflow_{}.pep:", name);
        let position = line.split_once(&at).map(|(_, rest)| rest).unwrap_or_else(|| panic!("{}: '{}' is not located", name, line));
        let numbers: Vec<&str> = position.splitn(3, ':').take(2).collect();
        assert!(numbers.iter().all(|n| n.parse::<u32>().is_ok()), "{}: '{}' is not located", name, line);
    }
}

#[test]
fn panic_names_the_operator_position() {
    let (success, stderr) = run("overflow_position", "    int x = 2147483647;\n    var y = x + n;", &[]);
    assert!(!success);
    assert!(stderr.contains("overflow_position.pep:6:15: panic: integer overflow in 'int' addition"), "{}", stderr);
}

#[test]
fn in_range_arithmetic_does_not_panic() {
    let (success, stderr) = run(
        "overflow_in_range",
        "    int x = 2147483646 + n;\n    uint u = 1;\n    u = u - n;\n    long m = -9223372036854775807 - n;\n    assert(m / 1 == m && 7 % -n == 0, \"min / 1\");\n    assert((1 << 31) == -2147483648, \"shift into the sign\");\n    assert(x == 2147483647 && u == 0, \"edges\");\n    byte b = 255;\n    b++;\n    assert(b == 0, \"narrow types step at int and keep the low bits\");\n    assert(2 ** 30 == 1073741824 && (-2) ** 31 == -2147483648, \"powers at the edge\");",
        &[],
    );
    assert!(success, "{}", stderr);
}

#[test]
fn removed_checks_wrap_and_mask_from_o1() {
    let body = "    int x = 2147483647;\n    x = x + n;\n    assert(x == -2147483648, \"wrapped\");\n    int s = 1 << (n * 33);\n    assert(s == 2, \"the count is masked to 1\");";
    let (success, stderr) = run("overflow_removed", body, &["-O1", "--no-runtime-checks=overflow,shift"]);
    assert!(success, "{}", stderr);
    let (success, stderr) = run("overflow_removed_all", body, &["-O2", "--no-runtime-checks=all"]);
    assert!(success, "{}", stderr);
    // The other checks stay.
    let (success, stderr) = run("overflow_removed_shift", body, &["-O2", "--no-runtime-checks=shift"]);
    assert!(!success && stderr.contains("integer overflow in 'int' addition"), "{}", stderr);
}

#[test]
fn removed_bounds_check_skips_the_index_check() {
    // Reading one past the end of a buffer with spare capacity reads the
    // (zeroed) spare slot instead of panicking.
    let body = "    var a = Array<int>();\n    a.append(1);\n    a.append(2);\n    a.pop();\n    var x = a[n as ulong];\n    assert(x == 2 || x == 0, \"read the spare slot\");";
    let (success, stderr) = run("bounds_removed", body, &["-O2", "--no-runtime-checks=bounds"]);
    assert!(success, "{}", stderr);
    let (success, stderr) = run("bounds_kept", body, &["-O2"]);
    assert!(!success && stderr.contains("Array index read out of bounds"), "{}", stderr);
}

/// A program whose `[Unsafe("...")]` functions overflow and index out of
/// range, and whose last call overflows in a function that keeps its
/// checks.
const UNSAFE_PROGRAM: &str = r#"import process;

[Unsafe("overflow")]
wrap(x: int): int {
    return x + 1;
}

[Unsafe("bounds")]
peek(a: Array<int>, index: ulong): int {
    var read = (): int => a[index];
    return read() + a[index];
}

struct Counter {
    var value: int = 2147483647;

    [Unsafe("overflow")]
    step() {
        value += 1;
    }
}

checked(x: int): int {
    return x + 1;
}

main(): int {
    var n = process.arguments().count > 1 ? 2 : 1;
    assert(wrap(2147483646 + n) == -2147483648, "wrapped");
    var counter = Counter();
    counter.step();
    assert(counter.value == -2147483648, "the method wrapped");
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a.pop();
    # One past the end: the zeroed spare slot, or the popped value.
    var x = peek(a, n as ulong);
    assert(x == 4 || x == 0, "read the spare slot");
    print("unchecked");
    return checked(2147483646 + n);
}
"#;

#[test]
fn unsafe_removes_checks_from_its_function_only() {
    let runs: &[(&str, &[&str])] = &[("unsafe_o0", &[]), ("unsafe_o2", &["-O2"])];
    for (name, args) in parallel_map(runs, |&(name, args)| (name, run_linked_with(name, UNSAFE_PROGRAM, args, |_| {}))) {
        let output = format!("{}{}", String::from_utf8_lossy(&args.stdout), String::from_utf8_lossy(&args.stderr));
        assert!(!args.status.success(), "{}: expected the checked function to panic:\n{}", name, output);
        assert!(output.contains("unchecked"), "{}: the unsafe functions panicked:\n{}", name, output);
        assert!(output.contains(&format!("{}.pep:24:14: panic: integer overflow in 'int' addition", name)), "{}:\n{}", name, output);
    }
}

#[test]
fn removing_checks_at_o0_is_ignored_with_a_warning() {
    use clap::Parser;
    let (success, output) = run("overflow_o0", "    int x = 2147483647;\n    x = x + n;", &["--no-runtime-checks=overflow"]);
    assert!(!success);
    assert!(output.contains("integer overflow in 'int' addition"), "{}", output);
    let options = |args: &[&str]| pepper_driver::Options::parse_from(pepper_driver::options::normalize_args(args.iter().map(std::ffi::OsString::from)));
    let at_o0 = options(&["pepper", "main.pep", "--no-runtime-checks=overflow"]);
    assert_eq!(at_o0.runtime_checks_warning().as_deref(), Some("warning: '--no-runtime-checks' has no effect at -O0"));
    assert_eq!(at_o0.effective_runtime_checks(), Ok(pepper_codegen::checks::RuntimeChecks::ALL));
    let at_o2 = options(&["pepper", "-O", "main.pep", "--no-runtime-checks=overflow"]);
    assert_eq!(at_o2.runtime_checks_warning(), None);
    assert!(!at_o2.effective_runtime_checks().unwrap().overflow);
}

#[test]
fn unknown_check_name_is_an_error() {
    use clap::Parser;
    let error = pepper_driver::Options::try_parse_from(["pepper", "main.pep", "--no-runtime-checks=overflow,speed"]).unwrap_err();
    assert!(
        error.to_string().contains("unknown runtime check 'speed' in '--no-runtime-checks': expected 'overflow', 'divide', 'shift', 'bounds', 'null' or 'all'"),
        "{}",
        error
    );
}

#[test]
fn wrapping_checked_saturating_and_overflowing_methods() {
    let source = r#"
test(): int {
    int big = 2147483647;
    assert(big.wrapping_add(1) == -2147483648, "int wrapping_add");
    assert(big.wrapping_mul(2) == -2, "int wrapping_mul");
    assert((-2147483647 - 1).wrapping_sub(1) == big, "int wrapping_sub");
    assert(big.checked_add(1).is_empty() && big.checked_add(0).value() == big, "int checked_add");
    assert(big.checked_mul(-1).value() == -big, "int checked_mul");
    assert(big.saturating_add(1) == big && (-big).saturating_sub(5) == -2147483648, "int saturating");
    assert((-3).saturating_mul(big) == -2147483648 && (-3).saturating_mul(-big) == big, "int saturating_mul");
    var (product, overflowed) = big.overflowing_mul(2);
    assert(product == -2 && overflowed, "int overflowing_mul");
    var (sum, wrapped) = big.overflowing_add(-1);
    assert(sum == 2147483646 && !wrapped, "int overflowing_add");

    byte b = 200;
    assert(b.wrapping_add(100) == 44 && b.wrapping_mul(2) == 144, "byte wrapping");
    assert(b.checked_add(100).is_empty() && b.checked_add(55).value() == 255, "byte checked at its own width");
    assert(b.saturating_add(100) == 255 && b.saturating_sub(201) == 0, "byte saturating");
    char c = -128;
    assert(c.wrapping_sub(1) == 127 && c.checked_sub(1).is_empty(), "char");
    short s = 32767;
    assert(s.saturating_add(1) == 32767 && s.overflowing_add(1).1, "short");
    ushort us = 0;
    assert(us.wrapping_sub(1) == 65535 && us.saturating_sub(1) == 0, "ushort");
    uint u = 0;
    assert(u.wrapping_sub(1) == 4294967295 && u.checked_sub(1).is_empty(), "uint");
    long l = -9223372036854775807 - 1;
    assert(l.checked_sub(1).is_empty() && l.saturating_sub(1) == l && l.wrapping_sub(1) == 9223372036854775807, "long");
    ulong ul = 0xFFFFFFFFFFFFFFFF;
    assert(ul.wrapping_add(2) == 1 && ul.saturating_mul(2) == ul && ul.checked_add(0).value() == ul, "ulong");
    return 7;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 7);
}
