//! The examples in the documentation (`docs/examples/`) are real programs:
//! each is compiled, linked and run, and must return 0. An example is a
//! single `name.pep`, or a folder `name/` whose entry point is `main.pep`
//! (for examples with several files, such as modules). The book includes the
//! files verbatim, so what a reader sees is what was tested here.

use clap::Parser;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::support;
use crate::support::repo_root;

/// Compile (with the options `extra`), link and run `entry`: Err with the
/// compile error or the program's output when it fails.
fn run(name: &str, entry: &Path, extra: &[&str]) -> Result<(), String> {
    let build = std::env::temp_dir().join(format!("pepper_docs_example_{}{}_{}", name, extra.concat(), std::process::id()));
    let _ = std::fs::remove_dir_all(&build);
    std::fs::create_dir_all(&build).unwrap();
    let out = build.join(if cfg!(windows) { "main.exe" } else { "main" });
    let mut args = vec![
        "pepper".to_string(),
        entry.to_string_lossy().into_owned(),
        "-o".to_string(),
        out.to_string_lossy().into_owned(),
        "--build".to_string(),
        build.join("obj").to_string_lossy().into_owned(),
    ];
    args.extend(extra.iter().map(|a| a.to_string()));
    let options = pepper_driver::Options::parse_from(args);
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

/// Every example at the default `-O0` on Linux. Elsewhere a sample: the
/// optimized pass below runs every example on every platform, and the
/// unoptimized pipeline does not depend on the platform.
#[test]
fn documentation_examples_compile_and_run() {
    let examples = if cfg!(target_os = "linux") { support::docs_examples() } else { support::docs_example_sample() };
    run_examples(examples, &[]);
}

/// Every example again, optimized and with debug info: LLVM's verifier
/// checks the debug info of each unit, including the inlined-at chains
/// optimization creates.
#[test]
fn documentation_examples_compile_and_run_optimized_with_debug_info() {
    run_examples(support::docs_examples(), &["-O2", "-g"]);
}

fn run_examples(examples: Vec<(String, PathBuf)>, extra: &[&str]) {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    // `PEPPER_DOCS_EXAMPLE=structs` runs only the examples whose name
    // starts with `structs`.
    let only = std::env::var("PEPPER_DOCS_EXAMPLE").unwrap_or_default();
    let examples: Vec<_> = examples.into_iter().filter(|(name, _)| name.starts_with(&only)).collect();
    assert!(!examples.is_empty(), "no examples in docs/examples");
    let failures: Vec<String> =
        support::parallel_map(&examples, |(name, entry)| run(name, entry, extra).err().map(|e| format!("docs/examples/{}: {}", name, e)))
            .into_iter()
            .flatten()
            .collect();
    assert!(failures.is_empty(), "{} of {} examples failed:\n\n{}", failures.len(), examples.len(), failures.join("\n\n"));
}

/// Examples that need what WASI preview 1 lacks (threads, tasks, sockets,
/// processes; see docs/src/language/platform-selection.md#webassembly), as
/// name prefixes.
const NOT_ON_WASI: &[&str] = &[
    "threads-",
    "tasks-",
    "networking-",
    "processes-",
    "function-types-shared",  // a thread
    "generics-shared",        // a thread
    "http-basics",            // tasks
    "http-streaming",         // tasks
    "platform-declarations",  // asserts a 64-bit target
];

/// Every example that WASI can run, built for `wasm32-wasip1` and run under
/// wasmtime, when `WASI_SDK_PATH` names a wasi-sdk and wasmtime is on the
/// PATH (or `WASMTIME` names it); skipped otherwise.
#[test]
fn documentation_examples_run_under_wasmtime() {
    let Some(wasi) = support::wasi_tools() else {
        eprintln!("skipped: set WASI_SDK_PATH and put wasmtime on the PATH (or set WASMTIME) to run it");
        return;
    };
    std::env::set_current_dir(repo_root()).unwrap();
    let only = std::env::var("PEPPER_DOCS_EXAMPLE").unwrap_or_default();
    let examples: Vec<_> = support::docs_examples()
        .into_iter()
        .filter(|(name, _)| name.starts_with(&only) && !NOT_ON_WASI.iter().any(|prefix| name.starts_with(prefix)))
        .collect();
    let failures: Vec<String> = support::parallel_map(&examples, |(name, entry)| {
        let build = std::env::temp_dir().join(format!("pepper_docs_example_wasm_{}_{}", name, std::process::id()));
        let _ = std::fs::remove_dir_all(&build);
        std::fs::create_dir_all(&build).unwrap();
        let result = support::run_under_wasmtime(&wasi, entry, &[], &build);
        let _ = std::fs::remove_dir_all(&build);
        result.err().map(|e| format!("docs/examples/{}: {}", name, e))
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "{} of {} examples failed:\n\n{}", failures.len(), examples.len(), failures.join("\n\n"));
}
