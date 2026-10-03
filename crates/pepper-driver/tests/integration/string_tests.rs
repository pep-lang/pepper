//! String tests kept in Rust: the deprecated `math.parse_int` still parses
//! (a pep-test build would warn about it on every run). The String library
//! behaviour is tested in `runtime/test/string_test.pep`.

use crate::support::compile_jit_with_runtime;

#[test]
fn math_parse_int_is_deprecated_but_still_parses() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
import math;

test(): int {
    if (math.parse_int("ff", 16).value() != 255) { return -1; }
    if (math.parse_int("12x").is_value()) { return -2; }
    return 0;
}"#
        ),
        0
    );
}
