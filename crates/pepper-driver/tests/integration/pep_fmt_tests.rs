//! pep-fmt (`tools/pep-fmt`, written in Pepper) is compiled once and run on
//! every `.pep` file in the repository. For each file it must succeed, be
//! idempotent (formatting its own output changes nothing), and keep the
//! program's meaning: the compiler's parser must read the same AST from the
//! input and the output. The tool's own sources must already be formatted.
//! The golden tests that pin the style itself are Pepper tests in
//! `tools/pep-fmt/format_test.pep`; the ones here check the CLI and its
//! rendered errors.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::support;
use crate::support::repo_root;

/// pep-fmt, built once per test process.
fn pep_fmt() -> &'static Path {
    support::pepper_tool("pep-fmt")
}

/// Runs pep-fmt on `source`: Ok(stdout) on success, Err(stderr) on failure.
fn format(source: &str) -> Result<String, String> {
    let mut child = Command::new(pep_fmt())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("run pep-fmt");
    let mut stdin = child.stdin.take().unwrap();
    let input = source.to_string();
    let writer = std::thread::spawn(move || stdin.write_all(input.as_bytes()));
    let output = child.wait_with_output().expect("wait for pep-fmt");
    writer.join().unwrap().expect("write to pep-fmt");
    let stdout = String::from_utf8(output.stdout).expect("pep-fmt wrote UTF-8");
    if output.status.success() {
        Ok(stdout)
    } else {
        Err(String::from_utf8_lossy(&output.stderr).into_owned())
    }
}

/// The compiler's AST of `source`, printed, with imports sorted (pep-fmt
/// sorts imports, and their order has no meaning) and `: void` before a
/// body dropped (pep-fmt leaves it out, and the body infers it).
fn ast(name: &str, source: &str) -> String {
    let module = pepper_parser::parser::parse_source(name, source).unwrap_or_else(|e| panic!("{}", e));
    let printed = module.to_string();
    let printed = printed.replace("): void {", ") {");
    let (mut imports, rest): (Vec<&str>, Vec<&str>) = printed.lines().partition(|l| l.starts_with("import "));
    imports.sort();
    imports.into_iter().chain(rest).collect::<Vec<_>>().join("\n")
}

fn pep_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).unwrap().flatten() {
        let path = entry.path();
        if path.is_dir() {
            pep_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "pep") {
            out.push(path);
        }
    }
}

fn repo_pep_files(folders: &[&str]) -> Vec<PathBuf> {
    let root = repo_root();
    let mut files = vec![];
    for folder in folders {
        pep_files(&root.join(folder), &mut files);
    }
    files.sort();
    files
}

fn check_file(path: &Path) -> Option<String> {
    let name = path.strip_prefix(repo_root()).unwrap_or(path).display().to_string();
    let source = std::fs::read_to_string(path).unwrap();
    let formatted = match format(&source) {
        Ok(text) => text,
        Err(e) => return Some(format!("{}: pep-fmt failed: {}", name, e)),
    };
    match format(&formatted) {
        Ok(again) if again == formatted => {}
        Ok(_) => return Some(format!("{}: formatting is not idempotent", name)),
        Err(e) => return Some(format!("{}: pep-fmt cannot read its own output: {}", name, e)),
    }
    if ast(&name, &source) != ast(&name, &formatted) {
        return Some(format!("{}: formatting changed the AST", name));
    }
    None
}

#[test]
fn pep_fmt_keeps_every_repository_file_meaning_and_is_idempotent() {
    let files = repo_pep_files(&["runtime", "docs/examples", "tests", "tools"]);
    assert!(files.len() > 100, "found only {} .pep files", files.len());
    pep_fmt();
    let failures: Vec<String> = support::parallel_map(&files, |path| check_file(path)).into_iter().flatten().collect();
    assert!(failures.is_empty(), "{} of {} files failed:\n{}", failures.len(), files.len(), failures.join("\n"));
}

#[test]
fn pep_fmt_sources_are_formatted() {
    let files = repo_pep_files(&["tools", "runtime"]);
    let failures: Vec<String> = support::parallel_map(&files, |path| {
        let source = std::fs::read_to_string(path).unwrap();
        (format(&source).as_deref() != Ok(source.as_str())).then(|| path.display().to_string())
    })
    .into_iter()
    .flatten()
    .collect();
    assert!(failures.is_empty(), "not formatted with pep-fmt:\n{}", failures.join("\n"));
}

#[test]
fn pep_fmt_reports_a_missing_semicolon_after_the_statement() {
    // As the compiler does: right after the last token, not at the next line.
    let error = format("main(): int {\n    var total = 1\n    return total;\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:18: error: expected ';'\n");
    let error = format("import io\nvar x = 1;\n").unwrap_err();
    assert_eq!(error, "<stdin>:1:10: error: expected ';'\n");
    let error = format("struct S {\n    int x\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:10: error: expected ';'\n");
    let error = format("extern int puts(char* s)\n").unwrap_err();
    assert_eq!(error, "<stdin>:1:25: error: expected ';'\n");
}

#[test]
fn pep_fmt_reports_syntax_errors_with_their_location() {
    let error = format("main(): int {\n    return (1;\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:14: error: expected ')'\n");
}

#[test]
fn pep_fmt_reports_an_unterminated_character_literal() {
    let error = format("main(): int {\n    var c = 'a;\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:13: error: missing terminating ' character\n");
}

#[test]
fn pep_fmt_reports_an_unterminated_interpolated_string() {
    let error = format("main(): int {\n    var s = $\"a;\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:13: error: missing terminating '\"' character\n");
}

#[test]
fn pep_fmt_reports_errors_inside_interpolated_expressions() {
    let error = format("main(): int {\n    var s = $\"{a # b}\";\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:18: error: a comment cannot appear inside '{}' in an interpolated string\n");
    let error = format("main(): int {\n    var s = $\"{a;\n}\n").unwrap_err();
    assert_eq!(error, "<stdin>:2:18: error: expected '}'\n");
}

/// Runs pep-fmt with `arguments` in `directory`: (exit code, stdout, stderr).
fn run_in(directory: &Path, arguments: &[&str]) -> (i32, String, String) {
    let output = Command::new(pep_fmt()).args(arguments).current_dir(directory).output().expect("run pep-fmt");
    let text = |bytes: &[u8]| String::from_utf8_lossy(bytes).replace("\r\n", "\n");
    (output.status.code().unwrap_or(-1), text(&output.stdout), text(&output.stderr))
}

#[test]
fn pep_fmt_checks_and_rewrites_files_and_directories() {
    let root = std::env::temp_dir().join(format!("pepper_pep_fmt_files_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("src").join("nested")).unwrap();
    std::fs::create_dir_all(root.join("src").join(".cache")).unwrap();
    let messy = "main(): int {\nreturn 0;\n}\n";
    let tidy = "main(): int {\n    return 0;\n}\n";
    std::fs::write(root.join("src").join("b.pep"), messy).unwrap();
    std::fs::write(root.join("src").join("a.pep"), tidy).unwrap();
    std::fs::write(root.join("src").join("nested").join("c.pep"), messy).unwrap();
    std::fs::write(root.join("src").join(".cache").join("skipped.pep"), "not pepper (").unwrap();
    std::fs::write(root.join("src").join("notes.txt"), messy).unwrap();
    let separator = std::path::MAIN_SEPARATOR;

    // A file argument prints its formatted text.
    assert_eq!(run_in(&root, &["src/b.pep"]), (0, tidy.to_string(), String::new()));
    // --check lists what would change, in name order, and changes nothing.
    let listed = format!("src{separator}b.pep\nsrc{separator}nested{separator}c.pep\n");
    assert_eq!(run_in(&root, &["--check", "src"]), (1, listed, String::new()));
    assert_eq!(std::fs::read_to_string(root.join("src").join("b.pep")).unwrap(), messy);
    // -w rewrites them; afterwards --check is clean.
    assert_eq!(run_in(&root, &["-w", "src"]), (0, String::new(), String::new()));
    assert_eq!(std::fs::read_to_string(root.join("src").join("nested").join("c.pep")).unwrap(), tidy);
    assert_eq!(std::fs::read_to_string(root.join("src").join("notes.txt")).unwrap(), messy);
    assert_eq!(run_in(&root, &["--check", "src"]), (0, String::new(), String::new()));

    // A syntax error names the file and leaves it alone.
    std::fs::write(root.join("broken.pep"), "g(: int {}\n").unwrap();
    assert_eq!(run_in(&root, &["-w", "broken.pep"]), (1, String::new(), "broken.pep:1:3: error: expected a type\n".to_string()));
    assert_eq!(std::fs::read_to_string(root.join("broken.pep")).unwrap(), "g(: int {}\n");

    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn pep_fmt_rejects_bad_usage() {
    let directory = std::env::temp_dir();
    let (code, _, error) = run_in(&directory, &["--frobnicate"]);
    assert_eq!(code, 2);
    assert!(error.starts_with("pep-fmt: error: unknown option '--frobnicate'\nusage: pep-fmt"), "{error}");
    let (code, _, error) = run_in(&directory, &["-w"]);
    assert_eq!(code, 2);
    assert!(error.starts_with("pep-fmt: error: -w and --check need files\n"), "{error}");
    let (code, usage, _) = run_in(&directory, &["-h"]);
    assert_eq!(code, 0);
    assert!(usage.contains("\nusage: pep-fmt [OPTIONS] [paths]...\n"), "{usage}");
    assert!(usage.contains("  -w, --write  "), "{usage}");
}

#[test]
fn pep_fmt_version_is_the_workspace_version() {
    let output = Command::new(pep_fmt()).arg("--version").output().expect("run pep-fmt");
    assert_eq!(support::stdout_of(&output), format!("pep-fmt {}\n", env!("CARGO_PKG_VERSION")));
}
