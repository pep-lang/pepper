//! CompileTest corpus: iterate `tests/*/test.pep` with the rule from
//! `unittests/main.cpp:27-35` — entry `main`, runtime on; assert exit code 0.

use pepper_codegen::CodeGenerator;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;
use std::path::{Path, PathBuf};

use crate::support;

fn tests_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join("tests")
}

/// Load and link `entry`, everything it imports (modules from tests/ and
/// runtime/), and the runtime sources: the program a CLI compile of it sees.
fn load(entry: &Path) -> Result<pepper_sema::program::Program, String> {
    // Runtime discovery uses the CWD; chdir to the repo root.
    let repo_root = tests_dir().parent().unwrap().to_path_buf();
    std::env::set_current_dir(&repo_root).unwrap();

    // As the CLI with `-I tests`.
    let import_dirs = [tests_dir()];
    let setup = pepper_sema::program::Setup { import_dirs: &import_dirs, ..Default::default() };
    pepper_sema::program::load_program(pepper_sema::program::Root::from_file(entry)?, &setup)
}

/// Every `tests/*/test.pep` fixture.
fn corpus_fixtures() -> Vec<(String, PathBuf)> {
    let Ok(entries) = std::fs::read_dir(tests_dir()) else {
        return vec![]; // tests/ not present in a subcrate checkout
    };
    let mut out: Vec<(String, PathBuf)> = entries
        .flatten()
        .map(|e| (e.file_name().to_string_lossy().into_owned(), e.path().join("test.pep")))
        .filter(|(_, p)| p.is_file())
        .collect();
    out.sort();
    out
}

/// This process's build directory; each fixture builds in its own
/// subdirectory.
fn corpus_build_root() -> PathBuf {
    std::env::temp_dir().join(format!("pepper_corpus_test_{}", std::process::id()))
}

/// Compile a `.pep` source with the runtime discovery ON (imports resolved
/// from tests/ and runtime/), emit + link, then spawn the binary.
fn compile_and_run(name: &str, entry: &Path) -> Result<std::process::ExitStatus, String> {
    let mut merged = pepper_driver::compiler::merge(&load(entry)?)?;

    pepper_sema::apply_platform_filters(&mut merged).map_err(|d| d.to_string())?;
    struct_body::apply(&mut merged).map_err(|d| d.to_string())?;
    transform_pass(&mut merged).map_err(|d| d.to_string())?;

    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut merged).map_err(|d| d.to_string())?;

    // Emit + link. The directory is per process and per fixture: CI runs
    // several jobs on one host at once, and fixtures build in parallel, so a
    // shared path lets one build overwrite or exec another's binary mid-link
    // ("Text file busy", "file truncated").
    let build_dir = corpus_build_root().join(name);
    std::fs::create_dir_all(&build_dir).unwrap();
    let obj_path = build_dir.join("corpus.o");
    let out_path = build_dir.join(if cfg!(windows) { "corpus_bin.exe" } else { "corpus_bin" });

    // Fix linkage and linker spellings as every driver build does (a plain
    // Pepper name such as `exit` must not reach the linker as C's symbol).
    pepper_codegen::partition::finish(&generator.module, &generator.owners, &generator.exported)?;
    let machine = pepper_codegen::target::target_machine().unwrap();
    pepper_codegen::target::write_object(&machine, &generator.module, &obj_path).unwrap();

    // Link through the driver's own linker so this test exercises the real
    // link path instead of a hand-rolled duplicate of it. `[Link("name")]`
    // attributes on surviving externs add their libraries, same as the CLI.
    let libraries = pepper_driver::link_libraries(&merged);
    pepper_driver::linker::link(&[obj_path], &out_path, &libraries, &[], false, None, None, false)?;

    std::process::Command::new(&out_path)
        .status()
        .map_err(|e| format!("spawn failed: {}", e))
}

/// Compiles, links, and runs every `tests/<Name>/test.pep` fixture; each must
/// exit 0.
#[test]
fn corpus_files_compile_and_run() {
    let fixtures = corpus_fixtures();
    let tested = fixtures.len();
    let failures: Vec<String> = support::parallel_map(&fixtures, |(name, test_path)| {
        match compile_and_run(name, test_path) {
            Ok(status) if status.success() => None,
            Ok(status) => Some(format!("{}: exited with {}", name, status)),
            Err(e) => Some(format!("{}: {}", name, e)),
        }
    })
    .into_iter()
    .flatten()
    .collect();
    let _ = std::fs::remove_dir_all(corpus_build_root());
    assert!(tested > 0, "no corpus tests found");
    assert!(
        failures.is_empty(),
        "{} corpus failures:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

