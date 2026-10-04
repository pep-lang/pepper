//! `[Cold]` (#640): a function, method or constructor marked rarely called
//! gets LLVM's `cold` and `noinline`, and still runs as written.

use crate::support::{jit_cases, sema};

/// The LLVM IR of `source`'s `main.pep`.
fn ir(source: &str) -> String {
    let mut module = sema(source).unwrap_or_else(|e| panic!("compile:\n{}", e));
    let ctx = inkwell::context::Context::create();
    let mut generator = pepper_codegen::CodeGenerator::new(&ctx, "main");
    generator.generate(&mut module).expect("generate");
    generator.module.print_to_string().to_string()
}

/// The function attributes `define` line of `function` in `ir` names, as the
/// text of its attribute group.
fn attributes(ir: &str, function: &str) -> String {
    let define = ir.lines().find(|l| l.starts_with("define") && l.contains(&format!("@{}(", function))).unwrap_or_else(|| panic!("no {} in:\n{}", function, ir));
    let group = define.rsplit(" #").next().unwrap().split(' ').next().unwrap();
    ir.lines().find(|l| l.starts_with(&format!("attributes #{} = ", group))).map(str::to_string).unwrap_or_default()
}

const SOURCE: &str = r#"
struct Counter {
    var count: int;

    construct(count: int) {
        this.count = count;
    }

    [Cold]
    overflowed(): int {
        count = 0;
        return -1;
    }
}

[Cold]
slow_path(n: int): int {
    return n * 2;
}

fast_path(n: int): int {
    if (n > 100) {
        return slow_path(n);
    }
    return n;
}

test(): int {
    if (fast_path(3) != 3 || fast_path(200) != 400) { return 1; }
    var counter = Counter(5);
    if (counter.overflowed() != -1 || counter.count != 0) { return 2; }
    return 0;
}
"#;

#[test]
fn cold_functions_stay_out_of_line() {
    let ir = ir(SOURCE);
    for function in ["slow_path", "Counter.overflowed"] {
        let group = attributes(&ir, function);
        assert!(group.contains("cold") && group.contains("noinline"), "{}: {}\n{}", function, group, ir);
    }
    let group = attributes(&ir, "fast_path");
    assert!(!group.contains("cold") && !group.contains("noinline"), "{}\n{}", group, ir);
}

#[test]
fn cold_functions_run_as_written() {
    jit_cases(SOURCE, &["test"]);
}
