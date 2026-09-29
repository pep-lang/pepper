//! A string literal passed to an extern (a C function) is its NUL-terminated
//! global, as `assert`'s message already was: `strlen("hello")` is 5.
//! convert_string_literals turns every literal into a `String(...)` ctor
//! call, so C used to receive a pointer to the String object and read its
//! fields as characters.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

/// `_pep_live_allocs()` is a process-wide counter: serialize the census.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Compile + JIT; return (entry result, net live-allocation delta).
fn compile_jit_census(source: &str) -> (i32, i64) {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mut module = SemaModule::default();
    let (runtime_sources, _libs, _dirs) = pepper_driver::runtime::discover();
    assert!(!runtime_sources.is_empty(), "runtime prelude not discovered");
    for path in runtime_sources {
        let content = std::fs::read_to_string(&path).expect("read runtime source");
        let ast = pepper_parser::parser::parse_source(&path.to_string_lossy(), &content)
            .expect("parse runtime source");
        module.merge(build(&ast).expect("build"));
    }
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    pepper_driver::compiler::check_with_runtime("test.pep", source).expect("visibility");
    module.merge(build(&ast).expect("build"));
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module);
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
