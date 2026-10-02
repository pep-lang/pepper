//! The reference-counting optimizer (#263): a copy from a slot that owns a
//! reference tells LLVM the object's count is at least 1, so the copy's
//! acquire and its matching release fold away once both are in one function.

use inkwell::values::AnyValue;
use pepper_codegen::CodeGenerator;

fn sema(source: &str) -> Result<pepper_sema::model::Module, String> {
    pepper_driver::compiler::compile_with_runtime("test.pep", source)
}

/// `source`'s `test()`, run unoptimized in the JIT.
fn run(source: &str) -> i32 {
    let mut module = sema(source).unwrap();
    let context = inkwell::context::Context::create();
    CodeGenerator::new(&context, "test").jit_execute(&mut module, "test").expect("jit")
}

// The sums wrap on purpose: an overflow check between a copy's acquire and
// its release splits the block, and `default<O2>` then folds the pair only
// in part (its last GVN runs before the check's other side simplifies).
const COPIES: &str = "struct Counter {\n    var hits: int;\n    construct() { this.hits = 0; }\n}\n\
total(c: Counter, n: int): int {\n    return c.hits.wrapping_add(n);\n}\n\
test(): int {\n    var c = Counter();\n    var sum = 0;\n    var i = 0;\n    while (i < 1000) {\n        var d = c;\n        sum = sum.wrapping_add(total(d, i));\n        i += 1;\n    }\n    return sum % 7;\n}\n";

/// `test`'s IR after LLVM's `default<O2>` pipeline.
fn optimized_test(source: &str) -> String {
    let module = sema(source).unwrap();
    let context = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&context, "optimizer");
    generator.generate(&module).unwrap();
    let machine = pepper_codegen::target::target_machine().unwrap();
    generator.module.run_passes("default<O2>", &machine, inkwell::passes::PassBuilderOptions::create()).unwrap();
    generator.module.get_function("test").expect("test").print_to_string().to_string()
}

#[test]
fn copies_of_an_owned_reference_fold_away() {
    let ir = optimized_test(COPIES);
    // Only `c`'s own release at the end of `test` can destroy anything: the
    // loop's copies, and `total`'s parameter, leave no test for 0 behind.
    assert_eq!(ir.matches("@Counter.__last_release").count(), 1, "{}", ir);
    // 0 + 1 + ... + 999 = 499500, and 499500 % 7 == 1.
    assert_eq!(run(COPIES), 1);
}

#[test]
fn the_last_release_stays() {
    // `b` copies an owned reference, so its own acquire and release fold
    // away; `a`'s release is the last one and must still destroy the object.
    let source = "struct Counter {\n    var hits: int;\n    construct() { this.hits = 0; }\n}\n\
test(): int {\n    var before = _pep_live_allocs();\n    {\n        var a = Counter();\n        var b = a;\n        b.hits = 2;\n    }\n    return (_pep_live_allocs() - before) as int;\n}\n";
    let ir = optimized_test(source);
    assert_eq!(ir.matches("@Counter.__last_release").count(), 1, "{}", ir);
    assert_eq!(run(source), 0);
}
