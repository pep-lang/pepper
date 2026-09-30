//! Interpolated strings, `$"n = {n}"`: each snippet is compiled with the
//! runtime and JIT-executed through `test`. Their errors are in
//! `diagnostic_tests`.

use pepper_codegen::CodeGenerator;

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

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
