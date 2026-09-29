//! Regression tests for the bugs found by the documentation audit
//! (compiler crashes, wrong results, missing checks). Each test pins the
//! behavior its fix restored.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::PathBuf;
use std::process::Command;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

/// Compile with the runtime and JIT `test()`, or return the compile error.
fn try_jit(source: &str) -> Result<i32, String> {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source)?;
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test")
}

/// `_pep_live_allocs()` is a process-wide counter: serialize the census.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Compile + JIT `test()`; return (result, net live-allocation delta).
fn jit_census(source: &str) -> (i32, i64) {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).unwrap_or_else(|e| panic!("compile error: {e}"));
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs = unsafe {
        ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs")
            .expect("_pep_live_allocs")
    };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    (result, after - before)
}

fn jit(source: &str) -> i32 {
    try_jit(source).unwrap_or_else(|e| panic!("compile error: {e}"))
}

/// Compile and link to a real executable, run it, and return (success, stdout).
fn run_binary(name: &str, source: &str) -> (bool, String) {
    run_binary_with_env(name, source, &[])
}

/// [`run_binary`] with extra environment variables for the child.
fn run_binary_with_env(name: &str, source: &str, env: &[(&str, &str)]) -> (bool, String) {
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_audit_{name}"));
    std::fs::create_dir_all(&dir).unwrap();
    let src_path = dir.join(format!("{name}.pep"));
    let out_path = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    std::fs::write(&src_path, source).unwrap();
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src_path.to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
    ]);
    pepper_driver::run(options).expect("compile + link");
    let output = Command::new(&out_path).envs(env.iter().copied()).output().expect("spawn linked binary");
    // Windows' C runtime writes text-mode stdout with CRLF line endings.
    (output.status.success(), String::from_utf8_lossy(&output.stdout).replace("\r\n", "\n"))
}

/// Compile `source` as `main.pep` through codegen and return the rendered
/// error, with the temp directory stripped from paths.
#[allow(dead_code)]
fn error_of(test: &str, source: &str) -> String {
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_audit_diagnostic_{}", test));
    std::fs::create_dir_all(&dir).unwrap();
    let main_path = dir.join("main.pep");
    std::fs::write(&main_path, source).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main_path.to_str().unwrap()]);
    let error = match pepper_driver::compiler::compile(&options, "main") {
        Err(e) => e,
        Ok(mut module) => {
            let ctx = inkwell::context::Context::create();
            let mut generator = CodeGenerator::new(&ctx, "main");
            match generator.generate(&mut module) {
                Err(d) => module.sources.render(&d),
                Ok(()) => panic!("expected {} to fail to compile", test),
            }
        }
    };
    error.replace(&format!("{}{}", dir.display(), std::path::MAIN_SEPARATOR), "")
}

#[test]
fn bit_or_assign() {
    assert_eq!(jit("test(): int { var x = 4; x |= 3; return x; }"), 7);
}

#[test]
fn bit_xor_assign() {
    assert_eq!(jit("test(): int { var x = 6; x ^= 3; return x; }"), 5);
}

#[test]
fn pow_negative_and_variable_exponents() {
    assert_eq!(jit("test(): int { return 2 ** -1; }"), 0);
    assert_eq!(jit("test(): int { return (-1) ** -3; }"), -1);
    assert_eq!(jit("test(): int { return 1 ** -5; }"), 1);
    assert_eq!(jit("test(): int { var e = 10; return 2 ** e; }"), 1024);
    assert_eq!(jit("test(): int { var e = 3; return (-3) ** e; }"), -27);
    assert_eq!(jit("test(): int { var e = 0; return 7 ** e; }"), 1);
}

#[test]
fn integer_literal_out_of_range_is_an_error() {
    assert_eq!(
        error_of("int_literal_too_large", "main(): int {\n    var x = 99999999999999999999;\n    return 0;\n}\n"),
        "main.pep:2:13: error: integer literal is too large to be represented in a 64-bit integer\n\
         \x20   2 |     var x = 99999999999999999999;\n\
         \x20     |             ^~~~~~~~~~~~~~~~~~~~"
    );
    assert_eq!(
        error_of("hex_literal_without_digits", "main(): int {\n    var x = 0x;\n    return 0;\n}\n"),
        "main.pep:2:15: error: expected hexadecimal digit\n\
         \x20   2 |     var x = 0x;\n\
         \x20     |               ^"
    );
    assert_eq!(jit("test(): int { var x: long = 0xFFFFFFFFFFFFFFFF; return x == -1 ? 1 : 0; }"), 1);
}

#[test]
fn return_type_inferred_from_returns() {
    let (ok, out) = run_binary(
        "inferred_return",
        r#"
struct P {
    int x;
    construct(this.x = 0) {}
}
make() {
    return P(3);
}
big(): long {
    return 5000000000;
}
wide() {
    return big();
}
half() {
    return 0.5;
}
name() {
    return "hi";
}
nothing() {
    print("side effect");
}
main() {
    var p = make();
    print(p.x);
    print(wide());
    print(half() * 4.0);
    print(name());
    nothing();
}
"#,
    );
    assert!(ok);
    assert_eq!(out, "3\n5000000000\n2.000000\nhi\nside effect\n");
}

#[test]
fn large_integer_literal_infers_long() {
    assert_eq!(jit("test(): int { var x = 5000000000; return x / 1000000000 == 5 ? 1 : 0; }"), 1);
}

#[test]
fn comparison_overload_must_return_bool() {
    assert_eq!(
        error_of(
            "comparison_returns_string",
            "struct V {\n    int x;\n    construct(this.x = 0) {}\n    String ==(other: V) { return \"x\"; }\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:4:5: error: comparison operator '==' must return 'bool', not 'String'\n\
         \x20   4 |     String ==(other: V) { return \"x\"; }\n\
         \x20     |     ^~~~~~"
    );
}

#[test]
fn logical_operators_short_circuit() {
    // The right side must not run when the left decides the result.
    assert_eq!(
        jit(r#"
var calls = 0;
bump(result: bool): bool {
    calls += 1;
    return result;
}
test(): int {
    var a = Array<int>();
    if (a.count() > 0 && a[0] == 1) { return 100; }
    if (bump(false) && bump(true)) { return 101; }
    if (!(bump(true) || bump(true))) { return 102; }
    if (!(bump(false) or bump(true))) { return 103; }
    var both = bump(true) and bump(false);
    if (both) { return 104; }
    return calls;
}
"#),
        6
    );
    // Non-bool operands are tested for truth, not combined bitwise.
    assert_eq!(jit("test(): int { return (2 && 4) ? 1 : 0; }"), 1);
    assert_eq!(jit("test(): int { var x = 0; return (x || 0.5) ? 1 : 0; }"), 1);
}

#[test]
fn float_printing() {
    let (ok, out) = run_binary(
        "float_printing",
        r#"
main(): int {
    print(0.5);
    print(1.25);
    print(-2.75);
    print(3.0);
    print(0.9999996);
    print(-0.001);
    print(123456.000001);
    return 0;
}
"#,
    );
    assert!(ok);
    assert_eq!(out, "0.500000\n1.250000\n-2.750000\n3.000000\n1.000000\n-0.001000\n123456.000001\n");
}

#[test]
fn arithmetic_var_infers_promoted_type() {
    // `1 + 0.5` is a double, not the int of its left operand.
    assert_eq!(jit("test(): int { var m = 1 + 0.5; return (m * 2.0) as int; }"), 3);
    // `u8 + 10` promotes to int instead of wrapping at 8 bits.
    assert_eq!(jit("test(): int { u8 b = 250; var s = b + 10; return s; }"), 260);
    // A shift keeps its left operand's promoted type.
    assert_eq!(jit("test(): int { long one = 1; var big = one << 40; return (big >> 38) as int; }"), 4);
}

#[test]
fn not_equal_derived_from_equal() {
    assert_eq!(
        jit(r#"
struct P {
    int x;
    construct(this.x = 0) {}
    bool ==(other: P) { return x == other.x; }
}
test(): int {
    var a = P(1);
    var b = P(1);
    var c = P(2);
    var result = 0;
    if (a != b) { result += 1; }
    if (!(a != c)) { result += 2; }
    var s1 = "same";
    var s2 = "sa";
    s2 += "me";
    if (s1 != s2) { result += 4; }
    return result;
}
"#),
        0
    );
}

#[test]
fn arithmetic_overload_result_type() {
    assert_eq!(
        jit(r#"
struct V {
    int x;
    construct(this.x = 0) {}
    int +(other: V) { return x + other.x; }
    double *(k: double) { return x * k; }
}
test(): int {
    var a = V(1);
    var b = V(2);
    var sum = a + b;
    var scaled = a * 2.5;
    return sum * 10 + (scaled * 2.0) as int + (a + b + 1);
}
"#),
        39
    );
}

const BOX_EXTENDED_FOR_INT: &str = r#"
struct Box<T> {
    T value;
    construct(this.value = T()) {}
}
extend Box<int> {
    int doubled() { return value * 2; }
}
"#;

#[test]
fn specialized_extension_applies_only_to_its_specialization() {
    assert_eq!(
        jit(&format!("{BOX_EXTENDED_FOR_INT}\ntest(): int {{ var a = Box<int>(4); var b = Box<String>(\"x\"); return a.doubled(); }}")),
        8
    );
    assert_eq!(
        error_of(
            "specialized_extension",
            &format!("{BOX_EXTENDED_FOR_INT}main(): int {{\n    var b = Box<String>(\"x\");\n    return b.doubled();\n}}\n")
        ),
        "main.pep:11:14: error: no member named 'doubled' in 'Box<String>'\n\
         \x20  11 |     return b.doubled();\n\
         \x20     |              ^~~~~~~"
    );
}

#[test]
fn string_to_extern_pointer_parameter_is_an_error() {
    assert_eq!(
        error_of(
            "string_to_extern_pointer",
            "extern ulong strlen(char* s);\nmain(): int {\n    var s = \"abc\";\n    return strlen(s) as int;\n}\n"
        ),
        "main.pep:4:19: error: cannot pass 'String' to parameter 1 of extern 'strlen' of type 'char*'; pass its 'c_str()'\n\
         \x20   4 |     return strlen(s) as int;\n\
         \x20     |                   ^"
    );
    assert_eq!(jit("extern ulong strlen(char* s);\ntest(): int { var s = \"abc\"; return strlen(s.c_str()) as int; }"), 3);
}

#[test]
fn string_append_to_itself() {
    assert_eq!(
        jit(r#"
test(): int {
    var s = "abc";
    s += s;
    if (s != "abcabc") { return 1; }
    s.append(s);
    if (s != "abcabcabcabc") { return 2; }
    if (s.length() != 12 || s.size() != 12) { return 3; }
    return 0;
}
"#),
        0
    );
}

#[test]
fn string_substr_empty_and_pointer_length() {
    assert_eq!(
        jit(r#"
test(): int {
    var s = "hello";
    var none = s.substr(1, 0);
    if (none.size() != 0 || none.length() != 0 || !none.empty()) { return 1; }
    var from_ptr = String(s.c_str());
    if (from_ptr.length() != 5 || from_ptr.size() != 5) { return 2; }
    var sized = String(s.c_str(), 3);
    if (sized.length() != 3 || sized != "hel") { return 3; }
    var utf8 = "héllo";
    var copy = String(utf8.c_str());
    if (copy.length() != 5 || copy.size() != 6) { return 4; }
    return 0;
}
"#),
        0
    );
}

#[test]
fn atomic_releases_its_struct_reference() {
    let (result, leaked) = jit_census(
        r#"
[Shared]
struct Point {
    const x: int;
    construct(this.x = 0) {}
}
keep(): int {
    var a = Atomic<Point>(Point(1));
    a.store(Point(2));
    var empty = Atomic<Point>();
    var n = Atomic<int>(5);
    return a.load().x + n.load();
}
test(): int {
    var p = Point(3);
    {
        var a = Atomic<Point>(p);
        if (__refcount<Point>(p) != 2) { return -1; }
    }
    if (__refcount<Point>(p) != 1) { return -2; }
    return keep();
}
"#,
    );
    assert_eq!(result, 7);
    assert_eq!(leaked, 0, "Atomic<T> leaked its stored reference");
}

#[test]
fn trace_and_print_free_their_buffers() {
    let (ok, out) = run_binary_with_env(
        "trace_leaks",
        r#"
main(): int {
    var word = _pep_malloc(8);
    word[0] = 2;
    word[1] = 1;
    var answer = "answer";
    var nothing = "nothing";
    var name = "word";
    var before = _pep_live_allocs();
    trace_int(-42, answer.c_str());
    trace_ptr(__null, nothing.c_str());
    trace_region(word, 8, name.c_str());
    print(7);
    print(0.5);
    print(_pep_live_allocs() - before);
    _pep_free(word);
    return 0;
}
"#,
        &[("PEP_TRACE", "1")],
    );
    assert!(ok);
    // Refcount tracing adds its own lines (String constructors, ...).
    let lines: Vec<&str> = out.lines().collect();
    let line = |prefix: &str| *lines.iter().find(|l| l.starts_with(prefix)).unwrap_or_else(|| panic!("no {prefix} line in {out}"));
    assert_eq!(line("answer: "), "answer: -42");
    assert_eq!(line("nothing: "), "nothing: 0000000000000000");
    let word = line("word: ");
    assert!(word.ends_with("0000000000000102") && word.len() == 6 + 32, "{out}");
    let printed: Vec<&str> = lines.iter().copied().filter(|l| !l.contains(": ")).collect();
    assert_eq!(printed, ["7", "0.500000", "0"]);
}

#[test]
fn const_is_enforced() {
    assert_eq!(
        error_of("const_local", "main(): int {\n    const x = 1;\n    x = 2;\n    return x;\n}\n"),
        "main.pep:3:5: error: cannot assign to const variable 'x'\n\
         \x20   3 |     x = 2;\n\
         \x20     |     ^\n\
         main.pep:2:11: note: 'x' declared const here\n\
         \x20   2 |     const x = 1;\n\
         \x20     |           ^"
    );
    let compound = error_of("const_global", "const limit = 10;\nmain(): int {\n    limit += 1;\n    return limit;\n}\n");
    assert!(compound.starts_with("main.pep:3:5: error: cannot assign to const variable 'limit'"), "{compound}");
    let increment = error_of("const_increment", "main(): int {\n    const n = 1;\n    n++;\n    return n;\n}\n");
    assert!(increment.starts_with("main.pep:3:5: error: cannot assign to const variable 'n'"), "{increment}");
    // A local or parameter of the same name shadows the const; initializing is fine.
    assert_eq!(
        jit("const x = 5;\nbump(x: int): int { x += 1; return x; }\ntest(): int { const y = 2; var z = y; z += 1; { var x = 1; x = 2; } return bump(x) + z; }"),
        9
    );
}

#[test]
fn block_locals_go_out_of_scope() {
    // A block's `var` shadows an outer name only inside the block.
    assert_eq!(
        jit(r#"
var g = 5;
test(): int {
    { var g = 1; }
    var h = 7;
    { var h = 1; }
    var i = 100;
    var n = 0;
    while (n < 3) {
        var i = n;
        n += 1;
    }
    if (n == 3) { var h = 2; } else { var h = 3; }
    return g + h + i;
}
"#),
        112
    );
    // Using a loop's local after the loop is a clean error, not an LLVM
    // verification failure.
    assert_eq!(
        error_of("local_after_loop", "main(): int {\n    var i = 0;\n    while (i < 3) {\n        var inner = i;\n        i += 1;\n    }\n    return inner;\n}\n"),
        "main.pep:7:12: error: use of undeclared identifier 'inner'\n\
         \x20   7 |     return inner;\n\
         \x20     |            ^~~~~"
    );
}

#[test]
fn value_type_mismatches_are_errors() {
    assert_eq!(
        error_of("int_from_string", "main(): int {\n    int x = \"hello\";\n    return x;\n}\n"),
        "main.pep:2:5: error: cannot initialize variable 'x' of type 'int' with a value of type 'String'\n\
         \x20   2 |     int x = \"hello\";\n\
         \x20     |     ^~~"
    );
    assert_eq!(
        error_of("return_string_from_int", "f(): int {\n    return \"a\";\n}\nmain(): int { return f(); }\n"),
        "main.pep:2:12: error: cannot return a value of type 'String' from 'f', which returns 'int'\n\
         \x20   2 |     return \"a\";\n\
         \x20     |            ^~~"
    );
    assert_eq!(
        error_of("string_from_int_call", "add(a: int, b: int): int { return a + b; }\nmain(): int {\n    var s: String = add(1, 2);\n    return 0;\n}\n"),
        "main.pep:3:21: error: cannot initialize variable 's' of type 'String' with a value of type 'int'\n\
         \x20   3 |     var s: String = add(1, 2);\n\
         \x20     |                     ^~~"
    );
    let argument = error_of("struct_argument", "struct P { int x; construct(this.x = 0) {} }\nuse_p(p: P): int { return p.x; }\nmain(): int {\n    var s = \"no\";\n    return use_p(s);\n}\n");
    assert!(argument.starts_with("main.pep:5:18: error: cannot pass a value of type 'String' as argument 1 of 'use_p', which has type 'P'"), "{argument}");
    // Numbers still convert among themselves.
    assert_eq!(jit("half(x: double): double { return x / 2.0; }\ntest(): int { double d = 3; long l = d as long; return (half(l) * 2.0) as int; }"), 3);
}

#[test]
fn duplicate_local_is_an_error() {
    assert_eq!(
        error_of("duplicate_local", "main(): int {\n    var x = 1;\n    var x = 2;\n    return x;\n}\n"),
        "main.pep:3:9: error: redefinition of 'x'\n\
         \x20   3 |     var x = 2;\n\
         \x20     |         ^\n\
         main.pep:2:9: note: previous definition is here\n\
         \x20   2 |     var x = 1;\n\
         \x20     |         ^"
    );
    // Shadowing in an inner block, and a loop redeclaring per iteration, are fine.
    assert_eq!(jit("test(): int { var x = 1; { var x = 2; } var n = 0; while (n < 2) { var y = n; n += 1; } var a = Array<int>(); a.append(1); a.append(2); for (var i in a) { var z = i; } return x; }"), 1);
}

#[test]
fn second_constructor_is_an_error() {
    assert_eq!(
        error_of(
            "two_constructors",
            "struct P {\n    int x;\n    construct(this.x = 0) {}\n    construct(y: int) { x = y; }\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:4:5: error: redefinition of the constructor of 'P'\n\
         \x20   4 |     construct(y: int) { x = y; }\n\
         \x20     |     ^~~~~~~~~\n\
         main.pep:3:5: note: previous definition is here\n\
         \x20   3 |     construct(this.x = 0) {}\n\
         \x20     |     ^~~~~~~~~\n\
         note: a struct has one constructor; give its parameters default values to allow shorter calls"
    );
    let destructors = error_of("two_destructors", "struct P {\n    destruct {}\n    destruct {}\n}\nmain(): int { return 0; }\n");
    assert!(destructors.starts_with("main.pep:3:5: error: redefinition of the destructor of 'P'"), "{destructors}");
}

#[test]
fn trait_conformance_is_checked() {
    assert_eq!(
        error_of(
            "missing_trait_method",
            "trait Shape {\n    double area();\n}\nstruct Square {\n    double side;\n    construct(this.side = 1.0) {}\n}\nextend Square with Shape {}\nmain(): int { return 0; }\n"
        ),
        "main.pep:8:8: error: 'Square' does not implement 'area', required by trait 'Shape'\n\
         \x20   8 | extend Square with Shape {}\n\
         \x20     |        ^~~~~~\n\
         main.pep:2:12: note: 'area' declared here\n\
         \x20   2 |     double area();\n\
         \x20     |            ^~~~"
    );
}

#[test]
fn trait_default_methods_apply() {
    assert_eq!(
        jit(r#"
trait Describe<T> {
    T twice() { return value() * 2; }
    T value();
}
struct Seven {
    construct() {}
    int value() { return 7; }
}
struct Custom {
    construct() {}
    int value() { return 1; }
    int twice() { return 100; }
}
extend Seven with Describe<int> {}
extend Custom with Describe<int> {}
test(): int {
    return Seven().twice() + Custom().twice();
}
"#),
        114
    );
}

#[test]
fn struct_override_replaces_generic_body() {
    assert_eq!(
        jit(r#"
struct Point {
    int x;
}
describe<T>(T value): int { return 1; }
describe<int>(int value): int { return 3; }
describe<Point>(Point value): int { return 2; }
test(): int {
    return describe<Point>(Point()) * 100 + describe<int>(5) * 10 + describe<bool>(true);
}
"#),
        231
    );
}


#[test]
fn else_if_chains() {
    assert_eq!(
        jit(r#"
classify(x: int): int {
    if (x < 0) {
        return 1;
    } else if (x == 0) {
        return 2;
    } else if (x < 10) {
        return 3;
    } else {
        return 4;
    }
}
test(): int {
    return classify(-5) * 1000 + classify(0) * 100 + classify(5) * 10 + classify(50);
}
"#),
        1234
    );
}

#[test]
fn bare_return_leaves_a_void_function() {
    assert_eq!(
        jit(r#"
struct Counter {
    int n;
}
bump(c: Counter, times: int): void {
    var i = 0;
    while (true) {
        if (i == times) {
            return;
        }
        c.n += 1;
        i += 1;
    }
}
skip_negative(c: Counter, x: int) {
    if (x < 0) {
        return;
    }
    c.n += x;
}
test(): int {
    var c = Counter();
    bump(c, 3);
    skip_negative(c, -5);
    skip_negative(c, 10);
    return c.n;
}
"#),
        13
    );
}

#[test]
fn string_escape_sequences() {
    assert_eq!(
        jit(r#"
test(): int {
    var s = "a\tb\"c\\d\n\u{e9}\x41\0";
    # a, tab, b, quote, c, backslash, d, newline, two bytes of e-acute, A, NUL
    if (s.size() != 12 || s.length() != 11) {
        return 1;
    }
    var p = s.c_str();
    if (p[1] != 9 || p[3] != 34 || p[5] != 92 || p[7] != 10 || p[10] != 65 || p[11] != 0) {
        return 2;
    }
    return 0;
}
"#),
        0
    );
}
