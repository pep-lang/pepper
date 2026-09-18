//! End-to-end compile tests: JIT value tests (entry `test`) and a full
//! obj+link+spawn run (entry `main`), ported from `unittests/*`.

mod common;

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

fn compile_jit(source: &str) -> i32 {
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast);
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module);
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

// ── IntMath (unittests/IntMath.cpp shapes) ──────────────────────────────────

#[test]
fn int_add() {
    assert_eq!(compile_jit("test(): int { return 2 + 3 }"), 5);
}

#[test]
fn int_sub() {
    assert_eq!(compile_jit("test(): int { return 2 - 4 }"), -2);
}

#[test]
fn int_mul() {
    assert_eq!(compile_jit("test(): int { return 3 * 4 }"), 12);
}

#[test]
fn int_div() {
    assert_eq!(compile_jit("test(): int { return 9 / 3 }"), 3);
}

#[test]
fn int_mod() {
    assert_eq!(compile_jit("test(): int { return 9 % 4 }"), 1);
}

#[test]
fn int_pow() {
    assert_eq!(compile_jit("test(): int { return 2 ** 5 }"), 32);
}

#[test]
fn int_precedence() {
    assert_eq!(compile_jit("test(): int { return 2 + 3 * 4 }"), 14);
}

// ── FloatMath (unittests/FloatMath.cpp shapes) ──────────────────────────────

#[test]
fn float_add() {
    // 2.5 + 2.5 = 5.0 → coerce to int 5 for the i32 return.
    assert_eq!(compile_jit("test(): int { return 2.5 + 2.5 }"), 5);
}

#[test]
fn float_mul() {
    assert_eq!(compile_jit("test(): int { return 1.5 * 4.0 }"), 6);
}

// ── Branches (unittests/Branches.cpp shapes) ────────────────────────────────

#[test]
fn branch_then() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    if (1 == 1) {
        return 42
    }
    return 0
}
"#
        ),
        42
    );
}

#[test]
fn branch_else() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    if (1 == 2) {
        return 42
    } else {
        return 7
    }
}
"#
        ),
        7
    );
}

// ── Function (unittests/Function.cpp shapes) ────────────────────────────────

#[test]
fn function_call_args() {
    assert_eq!(
        compile_jit(
            r#"
add(a: int, b: int): int {
    return a + b
}
test(): int {
    return add(20, 22)
}
"#
        ),
        42
    );
}

#[test]
fn function_local() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    var x: int = 40
    x += 2
    return x
}
"#
        ),
        42
    );
}

// ── Loops (unittests/Loops.cpp shapes) ──────────────────────────────────────

#[test]
fn while_sum() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    var i: int = 0
    var acc: int = 0
    while (i < 6) {
        acc += i
        i += 1
    }
    return acc
}
"#
        ),
        15
    );
}

// ── Full pipeline: obj + link + spawn (entry `main`) ────────────────────────

#[test]
fn full_pipeline_link_and_spawn() {
    let source = r#"
main(): int {
    return 0
}
"#;
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast);
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module);

    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut module).expect("gen");

    // Emit obj.
    let build_dir = std::env::temp_dir().join("pepper_link_test");
    std::fs::create_dir_all(&build_dir).unwrap();
    let obj_path = build_dir.join("test.o");
    let out_path = build_dir.join(if cfg!(windows) { "test_bin.exe" } else { "test_bin" });

    let machine = pepper_codegen::target::host_machine().unwrap();
    machine
        .write_to_file(&generator.module, inkwell::targets::FileType::Object, &obj_path)
        .unwrap();

    // Link through the driver's own linker so this test exercises the real
    // link path instead of a hand-rolled duplicate of it.
    let staticlib = common::support_staticlib();

    pepper_driver::linker::link(&[obj_path, staticlib], &out_path, &[], &[]).expect("link");

    let run = std::process::Command::new(&out_path).status().unwrap();
    assert!(run.success(), "spawned binary failed");
}
