//! Every command-line option of every Pepper tool is documented in the
//! book. Each test takes a tool's options from the tool itself (clap's
//! definition for `pep-build`; the `--help` text for the others) and
//! requires every spelling in the tool's page, so adding an option without
//! documenting it fails here and names the page to update.
//!
//! | Tool | Options from | Page |
//! | --- | --- | --- |
//! | `pep-build` | `Options::command()`, `TRACE_CHANNELS`, the environment variables the compiler reads | `docs/src/tools/pep-build.md` |
//! | `pepper` | `pepper --help` (built from `tools/pepper`) | `docs/src/tools/pepper.md` |
//! | `pep-fmt` | `pep-fmt --help` (built from `tools/pep-fmt`) | `docs/src/tools/pep-fmt.md` |
//! | `pep-profile` | `pep-profile --help` (built from `tools/pep-profile`) | `docs/src/tools/pep-profile.md` |
//! | `pep-package` | `pep-package --help` and each command's `--help` (built from `tools/pep-package`) | `docs/src/tools/pep-package.md` |
//! | `pep-test` | `pep-test --help` (built from `tools/pep-test`) | `docs/src/tools/pep-test.md` |
//! | `pep-doc` | `tools/docgen/src/help.txt`, which it prints | `docs/src/tools/pep-doc.md` |
//! | `pep-lsp` | `tools/lsp/src/help.txt`, the server's initialization options and the VS Code settings | `docs/src/tools/pep-lsp.md` |
//! | `cargo setup` | `xtask/src/usage.txt`, which it prints | `docs/src/contributing/setup.md` |
//! | `install.sh` | its `usage` text | `docs/src/tools/install.md` |
//! | `install.ps1` | its `param()` block | `docs/src/tools/install.md` |

use std::path::Path;
use std::process::Command;

use crate::support;
use crate::support::{repo_root, stdout_of};

/// A page of the book, by its path from the repository root.
fn page(path: &str) -> String {
    std::fs::read_to_string(repo_root().join(path)).unwrap_or_else(|e| panic!("cannot read {}: {}", path, e))
}

/// A file of the repository, by its path from the root.
fn repository_file(path: &str) -> String {
    std::fs::read_to_string(repo_root().join(path))
        .unwrap_or_else(|e| panic!("cannot read {}: {}", path, e))
        .replace("\r\n", "\n")
}

/// Whether `text` mentions `word` on its own: `-O` in "`-O`" or "-O,", but
/// not inside `-O2`, `--Off` or `X_O`.
fn mentions(text: &str, word: &str) -> bool {
    let part = |c: char| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.';
    text.match_indices(word).any(|(at, _)| {
        let before = text[..at].chars().next_back();
        let after = text[at + word.len()..].chars().next();
        !before.is_some_and(part) && !after.is_some_and(|c| part(c) && c != '.')
    })
}

/// Whether `text` documents the environment variable `name`: by name, or
/// for one with a part chosen at run time (`PEPPER_SYSROOT_<TRIPLE>`,
/// `LLVM_SYS_<major>1_PREFIX`) by its fixed start followed by `<`.
fn mentions_variable(text: &str, name: &str) -> bool {
    mentions(text, name) || name.match_indices('_').any(|(at, _)| text.contains(&format!("{}<", &name[..=at])))
}

/// The lines of the section of `help` headed `heading` (`Options:`), up to
/// the next line that is not indented.
fn section<'a>(help: &'a str, heading: &str) -> Vec<&'a str> {
    help.lines()
        .skip_while(|line| line.trim_end() != heading)
        .skip(1)
        .take_while(|line| line.is_empty() || line.starts_with(' '))
        .filter(|line| !line.trim().is_empty())
        .collect()
}

/// Every option spelling the `Options:` section of `help` lists, from the
/// left column of each line: `-w, --write` gives `-w` and `--write`, and
/// `--site <DIR>` gives `--site`.
fn help_options(help: &str) -> Vec<String> {
    let mut options = vec![];
    for line in section(help, "Options:") {
        let line = line.trim_start();
        if !line.starts_with('-') {
            continue; // a description's continuation line
        }
        let left = line.split("  ").next().unwrap_or("");
        for token in left.split([' ', ',']) {
            let token = token.trim_matches(|c| c == '[' || c == ']');
            let spelling = token.split(['=', '<', '[']).next().unwrap_or("");
            if spelling.starts_with('-') && spelling.len() > 1 && !options.iter().any(|o| o == spelling) {
                options.push(spelling.to_string());
            }
        }
    }
    assert!(!options.is_empty(), "no options found in this help:\n{}", help);
    options
}

/// The command names the `Commands:` section of `help` lists.
fn help_commands(help: &str) -> Vec<String> {
    section(help, "Commands:").iter().filter_map(|line| line.split_whitespace().next()).map(str::to_string).collect()
}

/// The environment variables (`PEPPER_*`) that `text` names.
fn variables_named(text: &str) -> Vec<String> {
    let mut names: Vec<String> = text
        .match_indices("PEPPER_")
        .filter(|(at, _)| !text[..*at].ends_with(|c: char| c.is_ascii_alphanumeric() || c == '_'))
        .map(|(at, _)| text[at..].chars().take_while(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || *c == '_').collect())
        .collect();
    names.sort();
    names.dedup();
    names
}

/// The problems with `tool`'s page `page_path`: each of `words` it does not
/// mention, as `what`.
fn undocumented(tool: &str, page_path: &str, what: &str, words: &[String], check: impl Fn(&str, &str) -> bool) -> Vec<String> {
    let text = page(page_path);
    words
        .iter()
        .filter(|word| !check(&text, word))
        .map(|word| format!("{tool}: {what} '{word}' is not documented in {page_path}; add it there"))
        .collect()
}

fn assert_documented(problems: Vec<String>) {
    assert!(problems.is_empty(), "undocumented:\n{}", problems.join("\n"));
}

/// The string literals in the Rust sources under `dir` that name a
/// `PEPPER_*` or other environment variable the tools read.
fn variables_read(dir: &Path, names: &mut Vec<String>) {
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            variables_read(&path, names);
        } else if path.extension().is_some_and(|e| e == "rs") {
            let text = std::fs::read_to_string(&path).unwrap();
            for (at, _) in text.match_indices('"') {
                let name: String =
                    text[at + 1..].chars().take_while(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || *c == '_').collect();
                let known = name.starts_with("PEPPER_") || name.starts_with("LLVM_SYS_") || name == "NO_COLOR";
                if known && !names.contains(&name) {
                    names.push(name);
                }
            }
        }
    }
}

#[test]
fn pep_build_options_are_documented() {
    use clap::CommandFactory;
    const PAGE: &str = "docs/src/tools/pep-build.md";
    let mut command = pepper_driver::Options::command();
    command.build();
    let mut options = vec![];
    let mut values = vec![];
    for argument in command.get_arguments().filter(|a| !a.is_positional()) {
        let spellings: Vec<String> = argument
            .get_short()
            .map(|s| format!("-{s}"))
            .into_iter()
            .chain(argument.get_long().map(|l| format!("--{l}")))
            .collect();
        if argument.get_action().takes_values() {
            let spelling = spellings.last().unwrap();
            values.extend(argument.get_possible_values().iter().map(|v| format!("{} {}", spelling, v.get_name())));
        }
        options.extend(spellings);
    }
    let channels: Vec<String> = pepper_driver::options::TRACE_CHANNELS.iter().map(|c| format!("-T {c}")).collect();
    // Every environment variable a stage of the compiler reads.
    let root = repo_root();
    let mut variables = vec![];
    variables_read(&root.join("src"), &mut variables);
    for entry in std::fs::read_dir(root.join("crates")).unwrap() {
        let source = entry.unwrap().path().join("src");
        if source.is_dir() {
            variables_read(&source, &mut variables);
        }
    }
    let mut problems = undocumented("pep-build", PAGE, "option", &options, mentions);
    // `--lto full` passes when the page says `--lto=full` or `--lto full`.
    problems.extend(undocumented("pep-build", PAGE, "option value", &values, |text, value| {
        mentions(text, value) || mentions(text, &value.replacen(' ', "=", 1))
    }));
    problems.extend(undocumented("pep-build", PAGE, "trace channel", &channels, mentions));
    problems.extend(undocumented("pep-build", PAGE, "environment variable", &variables, mentions_variable));
    assert_documented(problems);
}

#[test]
fn pepper_options_are_documented() {
    let output = Command::new(support::pepper_tool("pepper")).arg("--help").output().expect("run pepper --help");
    let help = stdout_of(&output);
    assert_documented(undocumented("pepper", "docs/src/tools/pepper.md", "option", &help_options(&help), mentions));
}

#[test]
fn pep_fmt_options_are_documented() {
    let output = Command::new(support::pepper_tool("pep-fmt")).arg("--help").output().expect("run pep-fmt --help");
    let help = stdout_of(&output);
    assert_documented(undocumented("pep-fmt", "docs/src/tools/pep-fmt.md", "option", &help_options(&help), mentions));
}

#[test]
fn pep_profile_options_are_documented() {
    let output = Command::new(support::pepper_tool("pep-profile")).arg("--help").output().expect("run pep-profile --help");
    let help = stdout_of(&output);
    assert_documented(undocumented("pep-profile", "docs/src/tools/pep-profile.md", "option", &help_options(&help), mentions));
}

#[test]
fn pep_package_commands_and_options_are_documented() {
    const PAGE: &str = "docs/src/tools/pep-package.md";
    let help = |arguments: &[&str]| {
        let output = Command::new(support::pepper_tool("pep-package")).args(arguments).output().expect("run pep-package --help");
        stdout_of(&output)
    };
    let top = help(&["--help"]);
    let commands = help_commands(&top);
    assert!(!commands.is_empty(), "no commands in pep-package --help");
    let mut problems = undocumented("pep-package", PAGE, "command", &commands, mentions);
    problems.extend(undocumented("pep-package", PAGE, "option", &help_options(&top), mentions));
    for command in &commands {
        let options = help_options(&help(&[command, "--help"]));
        problems.extend(undocumented("pep-package", PAGE, &format!("'{command}' option"), &options, mentions));
    }
    assert_documented(problems);
}

#[test]
fn pep_doc_commands_and_options_are_documented() {
    const PAGE: &str = "docs/src/tools/pep-doc.md";
    let help = repository_file("tools/docgen/src/help.txt");
    let commands: Vec<String> = help_commands(&help).iter().map(|c| format!("pep-doc {c}")).collect();
    assert!(!commands.is_empty(), "no commands in tools/docgen/src/help.txt");
    let mut problems = undocumented("pep-doc", PAGE, "option", &help_options(&help), mentions);
    problems.extend(undocumented("pep-doc", PAGE, "command", &commands, mentions));
    assert_documented(problems);
}

#[test]
fn pep_lsp_options_and_settings_are_documented() {
    const PAGE: &str = "docs/src/tools/pep-lsp.md";
    let help = repository_file("tools/lsp/src/help.txt");
    // The initialization options the server reads, as JSON pointers
    // (`/inlayHints/parameterNames`), spelled with dots.
    let server = repository_file("tools/lsp/src/main.rs");
    let mut initialization: Vec<String> = server
        .match_indices("pointer(\"/")
        .map(|(at, found)| {
            let rest = &server[at + found.len()..];
            rest[..rest.find('"').unwrap()].replace('/', ".")
        })
        .collect();
    initialization.dedup();
    assert!(!initialization.is_empty(), "no initialization options found in tools/lsp/src/main.rs");
    // The VS Code extension's settings and commands (`pepper.lspPath`).
    let package = repository_file("tools/vscode-pepper/package.json");
    let mut settings: Vec<String> = package
        .match_indices("\"pepper.")
        .map(|(at, _)| package[at + 1..].chars().take_while(|c| *c != '"').collect())
        .collect();
    settings.sort();
    settings.dedup();
    let mut problems = undocumented("pep-lsp", PAGE, "option", &help_options(&help), mentions);
    problems.extend(undocumented("pep-lsp", PAGE, "initialization option", &initialization, mentions));
    problems.extend(undocumented("pep-lsp", PAGE, "VS Code setting or command", &settings, mentions));
    assert_documented(problems);
}

#[test]
fn cargo_setup_options_are_documented() {
    const PAGE: &str = "docs/src/contributing/setup.md";
    let usage = repository_file("xtask/src/usage.txt");
    let mut problems = undocumented("cargo setup", PAGE, "option", &help_options(&usage), mentions);
    problems.extend(undocumented("cargo setup", PAGE, "environment variable", &variables_named(&usage), mentions));
    assert_documented(problems);
}

#[test]
fn install_script_options_are_documented() {
    const PAGE: &str = "docs/src/tools/install.md";
    let script = repository_file("scripts/install.sh");
    let usage = script.split("<<'EOF'\n").nth(1).and_then(|rest| rest.split("\nEOF").next()).expect("install.sh has a usage text");
    let mut problems = undocumented("install.sh", PAGE, "option", &help_options(usage), mentions);
    problems.extend(undocumented("install.sh", PAGE, "environment variable", &variables_named(&script), mentions));
    // `[string]$Version = ...` and `[switch]$Yes` in the param() block.
    let parameters: Vec<String> = repository_file("scripts/install.ps1")
        .lines()
        .skip_while(|line| !line.starts_with("param("))
        .take_while(|line| *line != ")")
        .filter_map(|line| line.trim().strip_prefix("[string]$").or_else(|| line.trim().strip_prefix("[switch]$")))
        .map(|rest| format!("-{}", rest.split([' ', ',']).next().unwrap_or_default()))
        .collect();
    assert!(parameters.len() >= 5, "no parameters found in install.ps1's param() block");
    problems.extend(undocumented("install.ps1", PAGE, "parameter", &parameters, mentions));
    assert_documented(problems);
}

#[test]
fn help_parsing_finds_every_spelling() {
    let help = "usage: tool\n\nOptions:\n  -w, --write  rewrite\n      --check  list\n  --site <DIR>  a\n                continued -x\n  -O[=LEVEL]  b\nAfter:\n  --not-an-option\n";
    assert_eq!(help_options(help), ["-w", "--write", "--check", "--site", "-O"]);
    assert!(mentions("`-O` alone", "-O"));
    assert!(!mentions("`-O2` only", "-O"));
    assert!(!mentions("--lto only", "-l"));
    assert!(mentions("ends with -T time.", "-T time"));
    assert!(mentions_variable("`PEPPER_SYSROOT_<TRIPLE>`", "PEPPER_SYSROOT_AARCH64_APPLE_DARWIN"));
    assert_eq!(variables_named("set PEPPER_A or PEPPER_B_C, not XPEPPER_D"), ["PEPPER_A", "PEPPER_B_C"]);
}

#[test]
fn pep_test_options_are_documented() {
    let output = Command::new(support::pepper_tool("pep-test")).arg("--help").output().expect("run pep-test --help");
    let help = stdout_of(&output);
    assert_documented(undocumented("pep-test", "docs/src/tools/pep-test.md", "option", &help_options(&help), mentions));
}
