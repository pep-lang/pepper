//! `[Likely]` and `[Unlikely]` above an `if` or a `match` arm: LLVM branch
//! weights on the branch, and no change to what the program computes.

use crate::support::{jit_cases, sema};

/// The LLVM IR of `source`'s `main.pep`.
fn ir(source: &str) -> String {
    let mut module = sema(source).unwrap_or_else(|e| panic!("compile:\n{}", e));
    let ctx = inkwell::context::Context::create();
    let mut generator = pepper_codegen::CodeGenerator::new(&ctx, "main");
    generator.generate(&mut module).expect("generate");
    generator.module.print_to_string().to_string()
}

/// The weights (taken, not taken) of each conditional branch in `function`
/// of `ir`, in order.
fn weights(ir: &str, function: &str) -> Vec<(u32, u32)> {
    let start = ir.find(&format!("@{}(", function)).unwrap_or_else(|| panic!("no {} in:\n{}", function, ir));
    let body = &ir[start..ir[start..].find("\n}\n").map(|e| start + e).unwrap()];
    body.lines()
        .filter(|l| l.contains("br i1") && l.contains("!prof"))
        .map(|l| {
            let id = l.rsplit("!prof ").next().unwrap().trim();
            let node = ir.lines().find(|m| m.starts_with(&format!("{} = ", id))).unwrap();
            let numbers: Vec<u32> = node.split("i32 ").skip(1).map(|n| n.trim_end_matches(['}', ',', ' ']).parse().unwrap()).collect();
            (numbers[0], numbers[1])
        })
        .collect()
}

const SOURCE: &str = r#"
enum Reading {
    Value(celsius: double),
    Missing,
}

classify(n: int): int {
    [Unlikely]
    if (n < 0) {
        return -1;
    } else [Likely] if (n > 0) {
        return 1;
    }
    return 0;
}

describe(reading: Reading): int {
    match (reading) {
        [Likely]
        Value(celsius) => {
            return 1;
        }
        Missing => {
            return 2;
        }
    }
}

fallback(n: int): int {
    match (n) {
        0 => {
            return 1;
        }
        [Unlikely]
        else => {
            return 2;
        }
    }
}

unmarked(n: int): int {
    if (n < 0) {
        return 1;
    }
    return 0;
}

test(): int {
    if (classify(-3) != -1 || classify(3) != 1 || classify(0) != 0) { return 1; }
    if (describe(Reading.Value(1.0)) != 1 || describe(Reading.Missing) != 2) { return 2; }
    if (fallback(0) != 1 || fallback(5) != 2) { return 3; }
    return 0;
}
"#;

#[test]
fn hints_become_branch_weights() {
    let ir = ir(SOURCE);
    assert_eq!(weights(&ir, "classify"), [(1, 2000), (2000, 1)], "{}", ir);
    assert_eq!(weights(&ir, "describe"), [(2000, 1)], "{}", ir);
    // An unlikely `else` makes the arm before it the likely side.
    assert_eq!(weights(&ir, "fallback"), [(2000, 1)], "{}", ir);
    assert_eq!(weights(&ir, "unmarked"), [], "{}", ir);
}

#[test]
fn hinted_branches_run_as_written() {
    jit_cases(SOURCE, &["test"]);
}
