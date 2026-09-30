//! A string literal passed to an extern (a C function) is its NUL-terminated
//! global, as `assert`'s message already was: `strlen("hello")` is 5.
//! convert_string_literals turns every literal into a `String(...)` ctor
//! call, so C used to receive a pointer to the String object and read its
//! fields as characters.
//!
//! The same holds for any character or `void` pointer slot in Pepper code:
//! `String("hello")` passes the literal to the constructor's `__ptr<char>`,
//! which once copied one byte of the String object instead.

use pepper_codegen::CodeGenerator;

/// Compile + JIT; return (entry result, net live-allocation delta).
fn compile_jit_census(source: &str) -> (i32, i64) {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
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

#[test]
fn literal_to_extern_is_a_c_string() {
    let (result, leaked) = compile_jit_census(
        r#"
extern ulong strlen(char* s);
extern int strcmp(char* a, char* b);
test(): int {
    if (strlen("hello") != 5) { return 1; }
    if (strlen("") != 0) { return 2; }
    if (strcmp("abc", "abc") != 0) { return 3; }
    # A String value still goes through c_str().
    var s = "abc";
    if (strcmp(s.c_str(), "abc") != 0) { return 4; }
    return 0;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0, "a literal passed to C allocated a String");
}

#[test]
fn literal_to_pepper_function_is_still_a_string() {
    let (result, leaked) = compile_jit_census(
        r#"
size_of(s: String): int { return s.size(); }
test(): int {
    return size_of("four") - 4;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}

#[test]
fn literal_to_char_pointer_is_a_c_string() {
    let (result, leaked) = compile_jit_census(
        r#"
struct Holder {
    __ptr<char> P;
    construct(__ptr<char> p) { P = p; }
    __ptr<char> pick(bool a) {
        return a ? "yes" : "no";
    }
}
int test() {
    # The String constructor takes the literal's bytes.
    var s = String("hello");
    if (s.size() != 5) { return 1; }
    if (s.length() != 5) { return 2; }
    if (s != "hello") { return 3; }
    # Variable initializer and assignment.
    __ptr<char> p = "abc";
    if (String(p) != "abc") { return 4; }
    p = "wxyz";
    if (String(p).size() != 4) { return 5; }
    # Field through a constructor, return, and each arm of a ternary.
    var h = Holder("held");
    if (String(h.P) != "held") { return 6; }
    if (String(h.pick(true)) != "yes") { return 7; }
    if (String(h.pick(false)) != "no") { return 8; }
    if (String(s.size() == 0 ? "t" : "f") != "f") { return 9; }
    return 0;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0, "a literal passed as a pointer allocated a String");
}
