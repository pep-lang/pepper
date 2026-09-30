//! The compiler's output is a function of its input: compiling the same
//! program again, on another thread or after other programs, gives the same
//! LLVM IR. The build cache (see INTERNALS.md) relies on it, and so does
//! anyone comparing two builds.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::{Path, PathBuf};

use crate::support;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

/// Every documentation example's entry point, sorted.
fn examples() -> Vec<PathBuf> {
    let dir = repo_root().join("docs").join("examples");
    let mut out: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter_map(|path| {
            if path.is_dir() {
                Some(path.join("main.pep")).filter(|main| main.is_file())
            } else {
                (path.extension().is_some_and(|e| e == "pep")).then_some(path)
            }
        })
        .collect();
    out.sort();
    out
}

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
    let examples = examples();
    assert!(!examples.is_empty(), "no examples in docs/examples");
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
