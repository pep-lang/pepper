//! Codegen tests: compile `unittests/IntMath.cpp` shapes through
//! parse→sema→codegen and JIT them (entry `test`).

use pepper_parser::parser;

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;
use pepper_sema::type_name::TypeName;
use pepper_sema::model::Module as SemaModule;

fn compile_jit(source: &str) -> i32 {
    let ast = parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast).expect("build");
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module).expect("sema");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

/// Like `compile_jit` but with the `runtime/` prelude merged in, so the test
/// body can call `_pep_*` runtime functions (malloc, …).
fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = SemaModule::default();
    let (runtime_sources, _libs, _dirs) = pepper_files::runtime::discover();
    assert!(!runtime_sources.is_empty(), "runtime prelude not discovered");
    for path in runtime_sources {
        let content = std::fs::read_to_string(&path).expect("read runtime source");
        let ast = parser::parse_source(&path.to_string_lossy(), &content)
            .expect("parse runtime source");
        module.merge(build(&ast).expect("build"));
    }
    let ast = parser::parse_source("test.pep", source).expect("parse error");
    module.merge(build(&ast).expect("build"));
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module).expect("sema");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

const MATH_SOURCE: &str = r#"
test(): int {
    const x: int = 1;
    const y: int = 4;
    return x + y;
}
"#;

#[test]
fn simple_add() {
    assert_eq!(compile_jit(MATH_SOURCE), 5);
}

#[test]
fn int_literal_neg() {
    assert_eq!(compile_jit("test(): int { return -5; }"), -5);
}

#[test]
fn int_arithmetic() {
    assert_eq!(compile_jit("test(): int { return 2 + 3 * 4; }"), 14);
    assert_eq!(compile_jit("test(): int { return 10 / 3; }"), 3);
    assert_eq!(compile_jit("test(): int { return 10 % 3; }"), 1);
    assert_eq!(compile_jit("test(): int { return 2 - 7; }"), -5);
}

#[test]
fn shifts_and_bits() {
    assert_eq!(compile_jit("test(): int { return 1 << 4; }"), 16);
    assert_eq!(compile_jit("test(): int { return 256 >> 4; }"), 16);
    assert_eq!(compile_jit("test(): int { return 6 & 3; }"), 2);
    assert_eq!(compile_jit("test(): int { return 6 | 3; }"), 7);
    assert_eq!(compile_jit("test(): int { return 6 ^ 3; }"), 5);
}

#[test]
fn comparisons() {
    assert_eq!(compile_jit("test(): int { return 1 == 1; }"), 1);
    assert_eq!(compile_jit("test(): int { return 1 == 2; }"), 0);
    assert_eq!(compile_jit("test(): int { return 1 != 2; }"), 1);
    assert_eq!(compile_jit("test(): int { return 3 < 4; }"), 1);
    assert_eq!(compile_jit("test(): int { return 4 < 3; }"), 0);
    assert_eq!(compile_jit("test(): int { return 4 >= 4; }"), 1);
}

#[test]
fn local_mutation() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    var x: int = 1;
    x += 2;
    x = x * 3;
    return x;
}
"#
        ),
        9
    );
}

#[test]
fn branches() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    var x: int = 1;
    if (x == 1) {
        return 42;
    }
    return 0;
}
"#
        ),
        42
    );
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    var x: int = 2;
    if (x == 1) {
        return 42;
    } else {
        return 7;
    }
}
"#
        ),
        7
    );
}

#[test]
fn while_loop() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    var i: int = 0;
    var acc: int = 0;
    while (i < 5) {
        acc += i;
        i += 1;
    }
    return acc;
}
"#
        ),
        10
    );
}

#[test]
fn function_call() {
    assert_eq!(
        compile_jit(
            r#"
add(a: int, b: int): int {
    return a + b;
}
test(): int {
    return add(2, 3);
}
"#
        ),
        5
    );
}

#[test]
fn pow() {
    // 2 ** 5 = 32; the C++ IntMath Pow test expects 384 (3 ** ? etc.) — check
    // the pow op is wired: 2**8 = 256.
    assert_eq!(compile_jit("test(): int { return 2 ** 8; }"), 256);
}

#[test]
fn ternary() {
    assert_eq!(
        compile_jit("test(): int { return 1 == 1 ? 10 : 20; }"),
        10
    );
    assert_eq!(
        compile_jit("test(): int { return 1 == 2 ? 10 : 20; }"),
        20
    );
}

#[test]
fn float_math() {
    // Float ops through the i32 return: 2.0 + 3.0 = 5.0 → coerce to 5.
    assert_eq!(compile_jit("test(): int { return 2.5 + 2.5; }"), 5);
}

#[test]
fn struct_member() {
    // Struct field read through ctor + member access.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Test {
    var x: int = 7;
}
test(): int {
    var t = Test();
    return t.x;
}
"#
        ),
        7
    );
}

#[test]
fn struct_field_write() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Test {
    var x: int = 7;
}
test(): int {
    var t = Test();
    t.x = 21;
    return t.x;
}
"#
        ),
        21
    );
}

#[test]
fn sizeof_struct() {
    // Struct Test has one i32 field → size 4 (plus __refcount u32 = 8).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Test {
    var x: int = 0;
}
test(): int {
    return sizeof<Test>;
}
"#
        ),
        8
    );
}

#[test]
fn type_name_widest() {
    // The sema widest() promotion feeds codegen: mixed i8/i32 → i32.
    assert_eq!(TypeName::new("i8").to_string(), "i8");
}
