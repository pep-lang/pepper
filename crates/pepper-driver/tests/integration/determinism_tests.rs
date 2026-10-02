//! The compiler's output is a function of its input: compiling the same
//! program again, on another thread or after other programs, gives the same
//! LLVM IR. The build cache (see INTERNALS.md) relies on it, and so does
//! anyone comparing two builds.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::{Path, PathBuf};

use crate::support;
use crate::support::repo_root;

/// The LLVM IR of the program rooted at `entry`.
fn ir(entry: &Path) -> String {
    let options = pepper_driver::Options::parse_from(["pepper".to_string(), entry.to_string_lossy().into_owned()]);
    let mut module = pepper_driver::compiler::compile(&options, "main")
        .unwrap_or_else(|e| panic!("{} does not compile:\n{}", entry.display(), e));
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "main");
    generator.generate(&mut module).unwrap_or_else(|d| panic!("{}: {}", entry.display(), module.sources.render(&d)));
    generator.module.print_to_string().to_string()
}

#[test]
fn same_program_compiles_to_the_same_ir() {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    // Nondeterminism comes from the compiler's own state, not from any one
    // program, so a sample that reaches most of the compiler suffices.
    let examples: Vec<PathBuf> = support::docs_example_sample().into_iter().map(|(_, entry)| entry).collect();
    // The second round runs in the opposite order, so each program follows
    // different ones on its thread (thread-local counters) and every hash
    // map gets a different seed.
    let first = support::parallel_map(&examples, |entry| ir(entry));
    let reversed: Vec<PathBuf> = examples.iter().rev().cloned().collect();
    let mut second = support::parallel_map(&reversed, |entry| ir(entry));
    second.reverse();
    let differing: Vec<String> = examples
        .iter()
        .zip(first.iter().zip(&second))
        .filter(|(_, (a, b))| a != b)
        .map(|(entry, (a, b))| {
            let name = entry.strip_prefix(repo_root()).unwrap_or(entry).display().to_string();
            let (x, y) = a.lines().zip(b.lines()).find(|(x, y)| x != y).unwrap_or(("<end>", "<end>"));
            format!("{name}\n  first: {x}\n  second: {y}")
        })
        .collect();
    assert!(differing.is_empty(), "compiled twice to different IR: {}", differing.join("\n"));
}
