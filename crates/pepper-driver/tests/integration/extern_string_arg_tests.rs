//! A string literal passed to an extern (a C function) is its NUL-terminated
//! global, as `assert`'s message already was: `strlen("hello")` is 5.
//! convert_string_literals turns every literal into a `String(...)` ctor
//! call, so C used to receive a pointer to the String object and read its
//! fields as characters.

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
