//! Panics name the source location of the failure (#354): `assert`,
//! `panic`, the runtime's checking methods (which report their caller
//! through a `__caller_location()` default) and compiler-generated checks
//! write `file:line:col: panic: message` to standard error.

use crate::support::{parallel_map, run_linked_with};

/// Each case's program and the `line:col: panic: message` its standard
/// error must end with, after the source's path.
const PANICS: &[(&str, &str, &str)] = &[
    ("assert", "main(): int {\n    var n = 3;\n    assert(n == 4, \"n must be 4\");\n    return 0;\n}\n", "3:5: panic: n must be 4"),
    ("assert_string", "main(): int {\n    var n = 3;\n    assert(n == 4, $\"n is {n}\");\n    return 0;\n}\n", "3:5: panic: n is 3"),
    ("panic", "main(): int {\n    if (true) {\n        panic(\"unreachable\");\n    }\n    return 0;\n}\n", "3:9: panic: unreachable"),
    ("index", "main(): int {\n    var a = Array<int>();\n    a.append(1);\n    return a[7];\n}\n", "4:12: panic: Array index read out of bounds"),
    ("index_write", "main(): int {\n    var a = Array<int>();\n    a[0] = 1;\n    return 0;\n}\n", "3:10: panic: Array index write out of bounds"),
    ("pop", "main(): int {\n    var a = Array<int>();\n    return a.pop();\n}\n", "3:14: panic: Array pop on empty Array"),
    ("string_index", "main(): int {\n    var s = \"ab\";\n    print(s[2]);\n    return 0;\n}\n", "3:11: panic: String[] idx must be < length"),
    ("optional", "main(): int {\n    var o = Optional<int>.none();\n    return o.value();\n}\n", "3:14: panic: Optional.value on a None value"),
    ("overflow", "main(): int {\n    var x = 2147483647;\n    var n = x / x;\n    x = x + n;\n    return 0;\n}\n", "4:11: panic: integer overflow in 'int' addition"),
    (
        "forwarded",
        "check(value: int, location: __ptr<char> = __caller_location()) {\n    assert(value > 0, \"not positive\", location);\n}\nmain(): int {\n    check(1);\n    check(-1);\n    return 0;\n}\n",
        "6:5: panic: not positive",
    ),
];

#[test]
fn panics_report_their_location_on_standard_error() {
    let results = parallel_map(PANICS, |&(name, source, expected)| {
        (name, expected, run_linked_with(&format!("panic_location_{}", name), source, &[], |_| {}))
    });
    for (name, expected, output) in results {
        assert!(!output.status.success(), "{}: expected a panic", name);
        let stdout = String::from_utf8_lossy(&output.stdout).replace('\r', "");
        let stderr = String::from_utf8_lossy(&output.stderr).replace('\r', "");
        assert!(!stdout.contains("panic:"), "{}: the panic went to standard output:\n{}", name, stdout);
        let line = stderr.lines().find(|l| l.contains("panic:")).unwrap_or_else(|| panic!("{}: no panic in:\n{}", name, stderr));
        let at = format!("panic_location_{}.pep:{}", name, expected);
        assert!(line.ends_with(&at), "{}: expected '...{}', got '{}'", name, at, line);
    }
}

#[test]
fn output_printed_before_a_panic_is_kept() {
    let output = run_linked_with(
        "panic_location_flush",
        "main(): int {\n    print(\"before\");\n    panic(\"stop\");\n    return 0;\n}\n",
        &[],
        |_| {},
    );
    assert!(!output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout).replace('\r', ""), "before\n");
    assert!(String::from_utf8_lossy(&output.stderr).contains("panic_location_flush.pep:3:5: panic: stop"));
}

#[test]
fn a_null_location_prints_the_message_alone() {
    let output = run_linked_with(
        "panic_location_none",
        "main(): int {\n    panic(\"no place\", __null);\n    return 0;\n}\n",
        &[],
        |_| {},
    );
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr).replace('\r', "");
    assert!(stderr.lines().any(|l| l == "panic: no place"), "{}", stderr);
}
