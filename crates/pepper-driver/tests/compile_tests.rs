//! End-to-end compile tests: JIT value tests (entry `test`) and a full
//! obj+link+spawn run (entry `main`), ported from `unittests/*`.

use std::path::PathBuf;

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

fn compile_jit(source: &str) -> i32 {
    // Retain support symbols so JIT'd externs resolve from the host process.
    let _ = pepper_support::retain_support_symbols();
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast);
    struct_body::apply(&mut module);
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
    // Retain support symbols (same requirement as the CLI).
    let _ = pepper_support::retain_support_symbols();

    let source = r#"
main(): int {
    return 0
}
"#;
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast);
    struct_body::apply(&mut module);
    transform_pass(&mut module);

    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut module).expect("gen");

    // Emit obj.
    let build_dir = std::env::temp_dir().join("pepper_link_test");
    std::fs::create_dir_all(&build_dir).unwrap();
    let obj_path = build_dir.join("test.o");
    let out_path = build_dir.join("test_bin");

    inkwell::targets::Target::initialize_x86(&inkwell::targets::InitializationConfig::default());
    let triple = inkwell::targets::TargetMachine::get_default_triple();
    let target =
        inkwell::targets::Target::from_triple(&triple).map_err(|e| e.to_string()).unwrap();
    let machine = target
        .create_target_machine(
            &triple,
            "generic",
            "",
            inkwell::OptimizationLevel::None,
            inkwell::targets::RelocMode::Default,
            inkwell::targets::CodeModel::Default,
        )
        .unwrap();
    machine
        .write_to_file(&generator.module, inkwell::targets::FileType::Object, &obj_path)
        .unwrap();

    // Link with the support staticlib.
    let staticlib = std::env::var("PEPPER_SUPPORT_A")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            // target/debug/deps/... → target/debug/libpepper_support.a
            let mut dir = std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
            while dir.file_name().map(|n| n != "target").unwrap_or(true) {
                dir = dir.parent().unwrap().to_path_buf();
            }
            dir.join("debug").join("libpepper_support.a")
        });

    let status = std::process::Command::new("ld")
        .args([
            "-demangle",
            "-dynamic",
            "-arch",
            "x86_64",
            "-o",
            out_path.to_str().unwrap(),
        ])
        .args(if cfg!(target_os = "macos") {
            let sdk = std::process::Command::new("xcrun")
                .arg("--show-sdk-path")
                .output()
                .ok()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_default();
            vec![
                "-platform_version".to_string(),
                "macos".to_string(),
                "12.1.0".to_string(),
                "12.3".to_string(),
                "-syslibroot".to_string(),
                sdk,
            ]
        } else {
            vec![]
        })
        .arg(obj_path.to_str().unwrap())
        .arg(staticlib.to_str().unwrap())
        .arg("-lSystem")
        .status()
        .unwrap();
    assert!(status.success(), "link failed");

    let run = std::process::Command::new(&out_path).status().unwrap();
    assert!(run.success(), "spawned binary failed");
}
