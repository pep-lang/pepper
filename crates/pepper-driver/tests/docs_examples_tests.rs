//! The examples in the documentation (`docs/examples/`) are real programs:
//! each is compiled, linked and run, and must return 0. An example is a
//! single `name.pep`, or a folder `name/` whose entry point is `main.pep`
//! (for examples with several files, such as modules). The book includes the
//! files verbatim, so what a reader sees is what was tested here.

use clap::Parser;
use std::path::{Path, PathBuf};
use std::process::Command;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

/// (name, entry point) of every example.
fn examples() -> Vec<(String, PathBuf)> {
    let dir = repo_root().join("docs").join("examples");
    let mut out: Vec<(String, PathBuf)> = std::fs::read_dir(&dir)
        .unwrap_or_else(|e| panic!("cannot read {}: {}", dir.display(), e))
        .flatten()
        .filter_map(|e| {
            let path = e.path();
            let name = e.file_name().to_string_lossy().into_owned();
            if path.is_dir() {
                let main = path.join("main.pep");
                main.is_file().then_some((name, main))
            } else {
                name.strip_suffix(".pep").map(|stem| (stem.to_string(), path.clone()))
            }
        })
        .collect();
    out.sort();
    out
}

/// Compile, link and run `entry`: Err with the compile error or the
/// program's output when it fails.
fn run(name: &str, entry: &Path) -> Result<(), String> {
    let build = std::env::temp_dir().join(format!("pepper_docs_example_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&build);
    std::fs::create_dir_all(&build).unwrap();
    let out = build.join(if cfg!(windows) { "main.exe" } else { "main" });
    let options = pepper_driver::Options::parse_from([
        "pepper".to_string(),
        entry.to_string_lossy().into_owned(),
        "-o".to_string(),
        out.to_string_lossy().into_owned(),
        "--build".to_string(),
        build.join("obj").to_string_lossy().into_owned(),
    ]);
    let code = pepper_driver::run(options).map_err(|e| format!("compile failed:\n{}", e))?;
    if code != 0 {
        return Err(format!("the compiler exited with {}", code));
    }
    let output = Command::new(&out).current_dir(&build).output().map_err(|e| e.to_string())?;
    let _ = std::fs::remove_dir_all(&build);
    if !output.status.success() {
        return Err(format!(
            "exited with {}\nstdout:\n{}\nstderr:\n{}",
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(())
}

#[test]
fn documentation_examples_compile_and_run() {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    // `PEPPER_DOCS_EXAMPLE=structs` runs only the examples whose name
    // starts with `structs`.
    let only = std::env::var("PEPPER_DOCS_EXAMPLE").unwrap_or_default();
    let examples: Vec<_> = examples().into_iter().filter(|(name, _)| name.starts_with(&only)).collect();
    assert!(!examples.is_empty(), "no examples in docs/examples");
    let failures: Vec<String> = examples
        .iter()
        .filter_map(|(name, entry)| run(name, entry).err().map(|e| format!("docs/examples/{}: {}", name, e)))
        .collect();
    assert!(failures.is_empty(), "{} of {} examples failed:\n\n{}", failures.len(), examples.len(), failures.join("\n\n"));
}
