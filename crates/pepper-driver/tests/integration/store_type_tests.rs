//! Every store codegen emits has the slot's own LLVM type. LLVM accepts a
//! store of any type through an opaque pointer, so a mismatch is silent: an
//! 8-byte `ptr null` stored into `Optional<int>`'s 4-byte `T _value` wrote
//! past the object, which glibc's malloc slack hid and macOS crashed on.
//! `address::check_store_type` turns such a store into an internal error;
//! these tests pin both the guard and the generic-field zero-init it caught.

use pepper_codegen::address::check_store_type;
use pepper_codegen::CodeGenerator;

/// A generic struct whose type-parameter field has no default, so the
/// synthesized constructor zero-initializes it per specialization.
const CELL: &str = r#"
struct Cell<T> {
    var value: T;
    var tag: int;
}

struct Point {
    var x: int;
}
"#;

/// Compile and JIT `test()` after `CELL`; assert it left no allocation
/// behind and return its result.
fn run(body: &str) -> i32 {
    let source = format!("{}{}", CELL, body);
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", &source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs =
        unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs") };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    assert_eq!(after - before, 0, "allocations leaked or double-released");
    result
}

/// The LLVM IR of the function `name` in `CELL` plus `body`.
fn function_ir(body: &str, name: &str) -> String {
    let source = format!("{}{}", CELL, body);
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", &source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut module).unwrap_or_else(|d| panic!("{}", module.sources.render(&d)));
    let ir = generator.module.print_to_string().to_string();
    let header = format!("@\"{}\"(", name);
    let start = ir
        .lines()
        .position(|line| line.starts_with("define") && line.contains(&header))
        .unwrap_or_else(|| panic!("no function {} in the IR", name));
    ir.lines().skip(start).take_while(|line| *line != "}").collect::<Vec<_>>().join("\n")
}

const USES: &str = r#"
test(): int {
    var a = Cell<int>();
    var b = Cell<bool>();
    var c = Cell<Point>();
    if (a.value != 0 || a.tag != 0) { return -1; }
    if (b.value) { return -2; }
    a.value = 7;
    b.value = true;
    c.value = Point();
    c.value.x = 3;
    if (a.value != 7 || !b.value || c.value.x != 3) { return -3; }
    return 0;
}
"#;

#[test]
fn generic_fields_zero_initialize_at_their_own_type() {
    assert_eq!(run(USES), 0);
}

#[test]
fn constructors_store_each_field_at_its_own_type() {
    // `value` is the field's GEP; its store must be the field's width.
    let cases = [("Cell<int>", "store i32 0, ptr %value"), ("Cell<bool>", "store i1 false, ptr %value"), ("Cell<Point>", "store ptr null, ptr %value")];
    for (ctor, expected) in cases {
        let ir = function_ir(USES, ctor);
        assert!(ir.contains(expected), "{} should zero `value` with `{}`:\n{}", ctor, expected, ir);
        if ctor != "Cell<Point>" {
            assert!(!ir.contains("store ptr null, ptr %value"), "{} stores a pointer into a non-pointer field:\n{}", ctor, ir);
        }
    }
}

#[test]
fn a_store_of_the_wrong_llvm_type_is_an_internal_error() {
    let ctx = inkwell::context::Context::create();
    let i32_type = ctx.i32_type();
    let null = ctx.ptr_type(inkwell::AddressSpace::default()).const_null();
    let error = check_store_type(i32_type.into(), null.into(), "_value", "int").unwrap_err();
    assert_eq!(error, "internal error: storing a value of LLVM type 'ptr' into '_value' ('int', LLVM type 'i32')");
    assert!(check_store_type(i32_type.into(), i32_type.const_zero().into(), "_value", "int").is_ok());
}
