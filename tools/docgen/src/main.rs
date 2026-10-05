//! Pepper documentation builder: `pep-doc`, run as `pepper doc` or
//! `cargo run -p pepper-docgen -- <command>`. `help.txt` is its `--help`,
//! listing each command and option; the book's tools/pep-doc.md documents
//! them, and `pep-doc check` checks that it does (`checks.rs`).
//!
//! mdBook must be on PATH (`cargo install mdbook --locked`).

mod book;
mod checks;
mod reference;
mod site;

use std::path::{Path, PathBuf};
use std::process::Command;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize().expect("repository root")
}

/// A text file with CRLF line endings read as LF, as a Windows checkout
/// with `core.autocrlf` may have written it.
fn read_normalized(path: &Path) -> Option<String> {
    std::fs::read_to_string(path).ok().map(|t| t.replace("\r\n", "\n"))
}

fn regenerate(root: &Path) -> Result<Vec<PathBuf>, String> {
    let pages = reference::generate(&root.join("runtime"))?;
    reference::write(&root.join("docs"), &pages)
}

fn mdbook(args: &[&str], root: &Path) -> Result<(), String> {
    let status = Command::new("mdbook")
        .args(args)
        .current_dir(root)
        .status()
        .map_err(|e| format!("cannot run mdbook ({}); install it with `cargo install mdbook --locked`", e))?;
    if !status.success() {
        return Err(format!("mdbook {} failed ({})", args.join(" "), status));
    }
    Ok(())
}

/// What `pep-doc --help` prints.
const HELP: &str = include_str!("help.txt");

fn run(args: &[String]) -> Result<(), String> {
    let command = args.first().map(String::as_str).unwrap_or("build");
    match command {
        "help" | "--help" | "-h" => {
            print!("{}", HELP);
            return Ok(());
        }
        "--version" | "-V" => {
            println!("pep-doc {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        _ => {}
    }
    let root = repo_root();
    let option = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    match command {
        "reference" => {
            for path in regenerate(&root)? {
                println!("updated {}", path.strip_prefix(&root).unwrap_or(&path).display());
            }
            Ok(())
        }
        "check" => {
            let pages = reference::generate(&root.join("runtime"))?;
            let dir = root.join("docs/src/reference");
            let mut stale: Vec<String> = pages
                .iter()
                .filter(|p| read_normalized(&dir.join(&p.file)).as_deref() != Some(p.markdown.as_str()))
                .map(|p| format!("docs/src/reference/{}", p.file))
                .collect();
            let summary = read_normalized(&root.join("docs/src/SUMMARY.md")).ok_or("cannot read docs/src/SUMMARY.md")?;
            if reference::update_summary(&summary, &pages)? != summary {
                stale.push("docs/src/SUMMARY.md".to_string());
            }
            let broken = book::lint(&root.join("docs/src"))?;
            for e in &broken {
                eprintln!("{}", e);
            }
            let undocumented = checks::undocumented_declarations(&root)?;
            for e in &undocumented {
                eprintln!("{}", e);
            }
            let tools = checks::tools_dir(&root, option("--tools").map(PathBuf::from));
            let unlisted = checks::undocumented_tool_options(&root, &tools)?;
            for e in &unlisted {
                eprintln!("{}", e);
            }
            let mut errors = vec![];
            if !undocumented.is_empty() {
                errors.push(format!("{} public runtime declaration(s) without a doc comment", undocumented.len()));
            }
            if !unlisted.is_empty() {
                errors.push(format!("{} tool option(s) missing from their pages", unlisted.len()));
            }
            if !broken.is_empty() {
                errors.push(format!("{} problem(s) in the book's chapters", broken.len()));
            }
            if !stale.is_empty() {
                errors.push(format!(
                    "the standard library reference is out of date: {}\nrun `cargo run -p pepper-docgen -- reference`",
                    stale.join(", ")
                ));
            }
            if errors.is_empty() { Ok(()) } else { Err(errors.join("\n")) }
        }
        "build" => {
            let version = match option("--version").as_deref() {
                None | Some(site::DEV) => site::DEV.to_string(),
                Some(v) => site::Version::parse(v)?.to_string(),
            };
            let site_dir = option("--site").map(PathBuf::from).unwrap_or_else(|| root.join("target/docs-site"));
            std::fs::create_dir_all(&site_dir).map_err(|e| e.to_string())?;
            let site_dir = site_dir.canonicalize().map_err(|e| e.to_string())?;
            regenerate(&root)?;
            let out = site_dir.join(&version);
            let _ = std::fs::remove_dir_all(&out);
            mdbook(&["build", "docs", "--dest-dir", out.to_str().ok_or("non-UTF-8 site path")?], &root)?;
            site::write_index(&site_dir)?;
            println!("built docs {} into {}", version, out.display());
            Ok(())
        }
        "serve" => {
            regenerate(&root)?;
            mdbook(&["serve", "docs", "--open"], &root)
        }
        other => Err(format!("unknown command '{}': expected reference, check, build, serve, or help", other)),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(e) = run(&args) {
        eprintln!("error: {}", e);
        std::process::exit(1);
    }
}
