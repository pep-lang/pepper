//! End-to-end compile tests: JIT value tests (entry `test`) and a full
//! obj+link+spawn run (entry `main`), ported from `unittests/*`.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;
use crate::support::compile_jit_with_runtime;

fn compile_jit(source: &str) -> i32 {
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast).expect("build");
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module).expect("sema");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

// ── IntMath (unittests/IntMath.cpp shapes) ──────────────────────────────────

#[test]
fn int_add() {
    assert_eq!(compile_jit("test(): int { return 2 + 3; }"), 5);
}

#[test]
fn int_sub() {
    assert_eq!(compile_jit("test(): int { return 2 - 4; }"), -2);
}

#[test]
fn int_mul() {
    assert_eq!(compile_jit("test(): int { return 3 * 4; }"), 12);
}

#[test]
fn int_div() {
    assert_eq!(compile_jit("test(): int { return 9 / 3; }"), 3);
}

#[test]
fn int_mod() {
    assert_eq!(compile_jit("test(): int { return 9 % 4; }"), 1);
}

#[test]
fn int_pow() {
    assert_eq!(compile_jit("test(): int { return 2 ** 5; }"), 32);
}

#[test]
fn int_precedence() {
    assert_eq!(compile_jit("test(): int { return 2 + 3 * 4; }"), 14);
}

// ── FloatMath (unittests/FloatMath.cpp shapes) ──────────────────────────────

#[test]
fn float_add() {
    // 2.5 + 2.5 = 5.0 → coerce to int 5 for the i32 return.
    assert_eq!(compile_jit("test(): int { return 2.5 + 2.5; }"), 5);
}

#[test]
fn float_mul() {
    assert_eq!(compile_jit("test(): int { return 1.5 * 4.0; }"), 6);
}

// ── Branches (unittests/Branches.cpp shapes) ────────────────────────────────

#[test]
fn branch_then() {
    assert_eq!(
        compile_jit(
            r#"
test(): int {
    if (1 == 1) {
        return 42;
    }
    return 0;
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

// ── Function (unittests/Function.cpp shapes) ────────────────────────────────

#[test]
fn function_call_args() {
    assert_eq!(
        compile_jit(
            r#"
add(a: int, b: int): int {
    return a + b;
}
test(): int {
    return add(20, 22);
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
    var x: int = 40;
    x += 2;
    return x;
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
    var i: int = 0;
    var acc: int = 0;
    while (i < 6) {
        acc += i;
        i += 1;
    }
    return acc;
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
    return 0;
}
"#;
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast).expect("build");
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module).expect("sema");

    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut module).expect("gen");

    // Emit obj.
    let build_dir = std::env::temp_dir().join(format!("pepper_link_test_{}", std::process::id()));
    std::fs::create_dir_all(&build_dir).unwrap();
    let obj_path = build_dir.join("test.o");
    let out_path = build_dir.join(if cfg!(windows) { "test_bin.exe" } else { "test_bin" });

    // Fix linkage and linker spellings as every driver build does.
    pepper_codegen::partition::finish(&generator.module, &generator.owners).expect("finish");
    let machine = pepper_codegen::target::host_machine().unwrap();
    machine
        .write_to_file(&generator.module, inkwell::targets::FileType::Object, &obj_path)
        .unwrap();

    // Link through the driver's own linker so this test exercises the real
    // link path instead of a hand-rolled duplicate of it.
    pepper_driver::linker::link(&[obj_path], &out_path, &[], &[]).expect("link");

    let run = std::process::Command::new(&out_path).status().unwrap();
    assert!(run.success(), "spawned binary failed");
}

// ── Nested blocks with returns ─────────────────────────────────────────────

#[test]
fn return_in_nested_block() {
    assert_eq!(
        compile_jit("test(): int {\n\
                     var r = 0;\n\
                     {\n\
                         r = 5;\n\
                         return r;\n\
                     }\n\
                     return 9;\n\
                 }"),
        5
    );
}

#[test]
fn nested_block_fallthrough_continues() {
    // No return inside: the block's path falls through to the continuation.
    assert_eq!(
        compile_jit("test(): int {\n\
                     var r = 0;\n\
                     {\n\
                         r = 5;\n\
                     }\n\
                     r = r + 1;\n\
                     return r;\n\
                 }"),
        6
    );
}

#[test]
fn deeply_nested_block_return() {
    assert_eq!(
        compile_jit("test(): int {\n\
                     var r = 0;\n\
                     {\n\
                         {\n\
                             {\n\
                                 r = 7;\n\
                                 return r;\n\
                             }\n\
                         }\n\
                     }\n\
                     return 9;\n\
                 }"),
        7
    );
}

#[test]
fn nested_block_return_inside_if() {
    // Return in the branch body, block continues after the branch.
    assert_eq!(
        compile_jit("test(): int {\n\
                     var r = 0;\n\
                     {\n\
                         if true {\n\
                             return 3;\n\
                         }\n\
                         r = 8;\n\
                     }\n\
                     return r;\n\
                 }"),
        3
    );
}

// ── Runtime-backed language features (void* byte indexing, break/continue) ─

#[test]
fn void_ptr_byte_index() {
    // `void*` indexes at byte granularity: p[1] is the second byte, not the
    // second i32.
    assert_eq!(
        compile_jit_with_runtime("test(): int {\n\
                                 var p = _pep_malloc(16);\n\
                                 p[0] = 7;\n\
                                 p[1] = 9;\n\
                                 return p[1];\n\
                             }"),
        9
    );
}

#[test]
fn break_exits_loop() {
    assert_eq!(
        compile_jit("test(): int {\n\
                     var i = 0;\n\
                     while (i < 10) {\n\
                         if (i == 3) { break; }\n\
                         i = i + 1;\n\
                     }\n\
                     return i;\n\
                 }"),
        3
    );
}

#[test]
fn continue_skips_iteration() {
    // The increment runs before the continue check, so s = 1 + 3 + 4 + 5.
    assert_eq!(
        compile_jit("test(): int {\n\
                     var i = 0;\n\
                     var s = 0;\n\
                     while (i < 5) {\n\
                         i = i + 1;\n\
                         if (i == 2) { continue; }\n\
                         s = s + i;\n\
                     }\n\
                     return s;\n\
                 }"),
        13
    );
}

// ── Implicit numeric conversions (var init, argument, return) ──────────────

#[test]
fn implicit_conversions_follow_source_signedness() {
    // Initialization, argument passing and return convert as C does: an
    // unsigned source zero-extends and an int converts to float by value.
    // Each of these used to sign-extend (`u8 200` became -56) or store the
    // raw integer bits into a double slot.
    assert_eq!(
        compile_jit_with_runtime(
            r#"widen(long v): long { return v; }
to_double(double v): double { return v; }
ret_u8(u8 v): long { return v; }
ret_int(int v): double { return v; }

test(): int {
    u8 a = 200;
    long la = a;
    if (la != 200) { return 1; }
    int i = 3;
    double d = i;
    if (d != 3.0) { return 2; }
    uint u = 4294967295;
    double du = u;
    if (du != 4294967295.0) { return 3; }
    if (widen(a) != 200) { return 4; }
    if (to_double(i) != 3.0) { return 5; }
    if (ret_u8(200) != 200) { return 6; }
    if (ret_int(5) != 5.0) { return 7; }
    char c = -1;
    long lc = c;
    if (lc != -1 || widen(c) != -1) { return 8; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn float_arguments_convert_to_integer_parameters() {
    // A float argument to an integer parameter truncates toward zero, as
    // `int n = 2.7;` does. This used to pass the double through unchanged,
    // and LLVM rejected the call ("Call parameter type does not match").
    assert_eq!(
        compile_jit_with_runtime(
            r#"to_int(x: int): int { return x; }
to_uint(x: uint): uint { return x; }
to_u8(x: u8): u8 { return x; }
to_bool(x: bool): bool { return x; }
to_long(x: long): long { return x; }
struct Box {
    var value: int = 0;
    set(x: int) { value = x; }
    static twice(x: short): short { return x * 2; }
}

test(): int {
    if (to_int(3.5) != 3) { return 1; }
    if (to_int(-7.9) != -7) { return 2; }
    if (to_uint(3000000000.0) != 3000000000) { return 3; }
    if (to_u8(200.7) != 200) { return 4; }
    if (!to_bool(0.5) || to_bool(0.0)) { return 5; }
    if (to_long(1e12) != 1000000000000) { return 6; }
    var b = Box();
    b.set(9.9);
    if (b.value != 9) { return 7; }
    if (Box.twice(2.5) != 4) { return 8; }
    var f = to_int;
    if (f(4.2) != 4) { return 9; }
    var a = Array<int>();
    a.append(3.5);
    if (a[0] != 3) { return 10; }
    return 0;
}"#
        ),
        0
    );
}

// ── [Target] on type aliases and module-scope variables ────────────────────

#[test]
fn target_selects_type_alias() {
    // Only the matching alias may survive: with both, the later one would
    // win on every platform. The pairs are declared in opposite orders so
    // one of them puts the non-matching alias last on every host.
    let src = r#"
[Target(!OS(Windows))] type Handle = int;
[Target(OS(Windows))] type Handle = long;
[Target(OS(Windows))] type Other = int;
[Target(!OS(Windows))] type Other = long;
test(): int { return (sizeof<Handle>() * 10 + sizeof<Other>()) as int; }
"#;
    let expected = if cfg!(windows) { 84 } else { 48 };
    assert_eq!(compile_jit(src), expected);
}

#[test]
fn target_selects_module_variable() {
    let src = r#"
[Target(!OS(Windows))] const code = 2;
[Target(OS(Windows))] const code = 1;
[Target(OS(Windows))] const other = 3;
[Target(!OS(Windows))] const other = 4;
test(): int { return code * 10 + other; }
"#;
    // Opposite declaration orders, as in `target_selects_type_alias`.
    assert_eq!(compile_jit(src), if cfg!(windows) { 13 } else { 24 });
}

#[test]
fn target_on_alias_and_variable_is_validated_when_dropped() {
    for src in [
        "[Target(OS(Plan9))] type H = int;\ntest(): int { return 0; }",
        "[Target(OS(Plan9))] const v = 1;\ntest(): int { return 0; }",
    ] {
        let ast = pepper_parser::parser::parse_source("test.pep", src).expect("parse error");
        let mut module: SemaModule = build(&ast).expect("build");
        let err = pepper_sema::apply_platform_filters(&mut module).expect_err(src);
        assert!(err.message.contains("Plan9"), "{src}: unexpected error: {err}");
    }
}
