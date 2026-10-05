//! The checks `pep-doc check` runs besides the reference's: every public
//! runtime declaration has a doc comment (AGENTS.md's documentation
//! standard), and every command-line option of every tool is on the tool's
//! page in the book. Each takes the options from the tool itself (`--help`,
//! or a usage text the tool prints) and requires every spelling in the
//! page, so adding an option without documenting it fails and names the
//! page to update.
//!
//! | Tool | Options from | Page |
//! | --- | --- | --- |
//! | `pep-build` | `pep-build --help`, `TRACE_CHANNELS`, the environment variables the compiler reads | `docs/src/tools/pep-build.md` |
//! | `pepper`, `pep-fmt`, `pep-profile`, `pep-test` | the tool's `--help` | `docs/src/tools/<tool>.md` |
//! | `pep-package` | `pep-package --help` and each command's `--help` | `docs/src/tools/pep-package.md` |
//! | `pep-doc` | `tools/docgen/src/help.txt`, which it prints | `docs/src/tools/pep-doc.md` |
//! | `pep-lsp` | `tools/lsp/src/help.txt`, the server's initialization options and the VS Code settings | `docs/src/tools/pep-lsp.md` |
//! | `cargo setup` | `xtask/src/usage.txt`, which it prints | `docs/src/contributing/setup.md` |
//! | `install.sh` | its `usage` text | `docs/src/tools/install.md` |
//! | `install.ps1` | its `param()` block | `docs/src/tools/install.md` |
//!
//! The tools' `--help` comes from the built tools in one folder (`--tools`,
//! else the release build's folder when it holds `pep-build`, else the
//! debug build's). `scripts/pepper-tests.sh` builds the Pepper tools there.

use std::path::{Path, PathBuf};
use std::process::Command;

/// The Pepper tools whose `--help` lists options, built from
/// `tools/<tool>/main.pep`.
pub const PEPPER_TOOLS: &[&str] = &["pepper", "pep-fmt", "pep-profile", "pep-package", "pep-test"];

/// The `.pep` files under `dir`, leaving out tests (`test/` folders, which
/// are not part of any module) and hidden folders such as `.pep/`.
fn library_files(dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("cannot read {}: {}", dir.display(), e))?;
    for entry in entries {
        let path = entry.map_err(|e| e.to_string())?.path();
        if path.is_dir() {
            let name = path.file_name().unwrap_or_default().to_string_lossy();
            if name != "test" && !name.starts_with('.') {
                library_files(&path, out)?;
            }
        } else if path.extension().is_some_and(|e| e == "pep") {
            out.push(path);
        }
    }
    Ok(())
}

/// Every public declaration in `runtime/` and in the Pepper library under
/// `tools/syntax` without the doc comment AGENTS.md asks for, rendered as
/// clang-style errors.
pub fn undocumented_declarations(root: &Path) -> Result<Vec<String>, String> {
    let mut files = vec![];
    library_files(&root.join("runtime"), &mut files)?;
    let syntax = root.join("tools").join("syntax");
    if syntax.is_dir() {
        library_files(&syntax, &mut files)?;
    }
    files.sort();
    let mut errors = vec![];
    for path in &files {
        let source = std::fs::read_to_string(path).map_err(|e| format!("cannot read {}: {}", path.display(), e))?;
        let name = path.strip_prefix(root).unwrap_or(path).to_string_lossy().replace('\\', "/");
        let module = pepper_parser::parser::parse_source(&name, &source).map_err(|e| format!("{}: {:?}", name, e))?;
        for error in pepper_parser::doc::check_documented(&module, &source) {
            errors.push(error.render_in(&name, &source));
        }
    }
    Ok(errors)
}

/// The folder holding the built tools: `explicit`, else the release build's
/// folder when it holds `pep-build`, else the debug build's.
pub fn tools_dir(root: &Path, explicit: Option<PathBuf>) -> PathBuf {
    if let Some(dir) = explicit {
        return dir;
    }
    let target = std::env::var_os("CARGO_TARGET_DIR").map(PathBuf::from).unwrap_or_else(|| root.join("target"));
    let release = target.join("release");
    if release.join(executable("pep-build")).is_file() {
        return release;
    }
    target.join("debug")
}

fn executable(name: &str) -> String {
    if cfg!(windows) { format!("{name}.exe") } else { name.to_string() }
}

/// What `tool --help` (with `arguments` before `--help`) prints, from the
/// build in `dir`.
fn help_of(dir: &Path, tool: &str, arguments: &[&str]) -> Result<String, String> {
    let path = dir.join(executable(tool));
    if !path.is_file() {
        return Err(format!(
            "cannot find {} in {}: build the compiler with cargo and the Pepper tools with scripts/pepper-tests.sh, or name their folder with --tools",
            executable(tool),
            dir.display()
        ));
    }
    let output = Command::new(&path)
        .args(arguments)
        .arg("--help")
        .output()
        .map_err(|e| format!("cannot run {}: {}", path.display(), e))?;
    if !output.status.success() {
        return Err(format!("{} {} --help failed ({})", path.display(), arguments.join(" "), output.status));
    }
    Ok(String::from_utf8_lossy(&output.stdout).replace("\r\n", "\n"))
}

/// A file of the repository, by its path from the root, with LF line ends.
fn repository_file(root: &Path, path: &str) -> Result<String, String> {
    std::fs::read_to_string(root.join(path)).map(|t| t.replace("\r\n", "\n")).map_err(|e| format!("cannot read {}: {}", path, e))
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
/// `--site <DIR>` gives `--site`. A line indented deeper than an option's
/// (`      --lto`) continues a description.
fn help_options(help: &str) -> Vec<String> {
    let mut options = vec![];
    for line in section(help, "Options:") {
        let text = line.trim_start();
        if !text.starts_with('-') || line.len() - text.len() > 6 {
            continue;
        }
        let left = text.split("  ").next().unwrap_or("");
        for token in left.split([' ', ',']) {
            let token = token.trim_matches(|c| c == '[' || c == ']');
            let spelling = token.split(['=', '<', '[']).next().unwrap_or("");
            if spelling.starts_with('-') && spelling.len() > 1 && !options.iter().any(|o| o == spelling) {
                options.push(spelling.to_string());
            }
        }
    }
    options
}

/// Each `--option value` the `Options:` section of clap's `help` lists as
/// `[possible values: a, b]`.
fn help_values(help: &str) -> Vec<String> {
    let mut values = vec![];
    for line in section(help, "Options:") {
        let Some(at) = line.find("[possible values: ") else { continue };
        let Some(spelling) = help_options(&format!("Options:\n{line}")).pop() else { continue };
        let list = &line[at + "[possible values: ".len()..];
        let list = &list[..list.find(']').unwrap_or(list.len())];
        values.extend(list.split(", ").map(|value| format!("{spelling} {}", value.trim())));
    }
    values
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

/// The string literals in the Rust sources under `dir` that name a
/// `PEPPER_*` or other environment variable the tools read.
fn variables_read(dir: &Path, names: &mut Vec<String>) -> Result<(), String> {
    for entry in std::fs::read_dir(dir).map_err(|e| format!("cannot read {}: {}", dir.display(), e))? {
        let path = entry.map_err(|e| e.to_string())?.path();
        if path.is_dir() {
            variables_read(&path, names)?;
        } else if path.extension().is_some_and(|e| e == "rs") {
            let text = std::fs::read_to_string(&path).map_err(|e| format!("cannot read {}: {}", path.display(), e))?;
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
    Ok(())
}

/// The trace channels `-T` takes: `TRACE_CHANNELS` in the driver's
/// options.
fn trace_channels(root: &Path) -> Result<Vec<String>, String> {
    let options = repository_file(root, "crates/pepper-driver/src/options.rs")?;
    let start = options.find("pub const TRACE_CHANNELS").ok_or("no TRACE_CHANNELS in crates/pepper-driver/src/options.rs")?;
    let list = &options[start..];
    let list = &list[list.find("= [").ok_or("TRACE_CHANNELS is not an array")? + 3..];
    let list = &list[..list.find(']').ok_or("TRACE_CHANNELS is not an array")?];
    Ok(list.split(',').map(|c| c.trim().trim_matches('"').to_string()).filter(|c| !c.is_empty()).collect())
}

/// The problems with page `page_path`, for `tool`: each of `words` it does
/// not mention, as `what`.
fn undocumented(
    root: &Path,
    tool: &str,
    page_path: &str,
    what: &str,
    words: &[String],
    check: impl Fn(&str, &str) -> bool,
) -> Result<Vec<String>, String> {
    if words.is_empty() {
        return Err(format!("{tool}: found no {what}s to check against {page_path}"));
    }
    let text = repository_file(root, page_path)?;
    Ok(words
        .iter()
        .filter(|word| !check(&text, word))
        .map(|word| format!("{tool}: {what} '{word}' is not documented in {page_path}; add it there"))
        .collect())
}

/// Every option, command, setting and environment variable of the tools
/// that its page leaves out, one line each; the tools' `--help` comes from
/// the builds in `tools`.
pub fn undocumented_tool_options(root: &Path, tools: &Path) -> Result<Vec<String>, String> {
    let mut problems = vec![];

    // pep-build: its options and their values, trace channels, and every
    // environment variable a stage of the compiler reads.
    const PEP_BUILD: &str = "docs/src/tools/pep-build.md";
    let help = help_of(tools, "pep-build", &[])?;
    problems.extend(undocumented(root, "pep-build", PEP_BUILD, "option", &help_options(&help), mentions)?);
    // `--lto full` passes when the page says `--lto=full` or `--lto full`.
    problems.extend(undocumented(root, "pep-build", PEP_BUILD, "option value", &help_values(&help), |text, value| {
        mentions(text, value) || mentions(text, &value.replacen(' ', "=", 1))
    })?);
    let channels: Vec<String> = trace_channels(root)?.iter().map(|c| format!("-T {c}")).collect();
    problems.extend(undocumented(root, "pep-build", PEP_BUILD, "trace channel", &channels, mentions)?);
    let mut variables = vec![];
    variables_read(&root.join("src"), &mut variables)?;
    for entry in std::fs::read_dir(root.join("crates")).map_err(|e| e.to_string())? {
        let source = entry.map_err(|e| e.to_string())?.path().join("src");
        if source.is_dir() {
            variables_read(&source, &mut variables)?;
        }
    }
    problems.extend(undocumented(root, "pep-build", PEP_BUILD, "environment variable", &variables, mentions_variable)?);

    // The Pepper tools, from their --help.
    for tool in PEPPER_TOOLS {
        let page = format!("docs/src/tools/{tool}.md");
        let help = help_of(tools, tool, &[])?;
        problems.extend(undocumented(root, tool, &page, "option", &help_options(&help), mentions)?);
        if *tool != "pep-package" {
            continue;
        }
        let commands = help_commands(&help);
        problems.extend(undocumented(root, tool, &page, "command", &commands, mentions)?);
        for command in &commands {
            let options = help_options(&help_of(tools, tool, &[command])?);
            problems.extend(undocumented(root, tool, &page, &format!("'{command}' option"), &options, mentions)?);
        }
    }

    // pep-doc, from the help it prints.
    const PEP_DOC: &str = "docs/src/tools/pep-doc.md";
    let help = repository_file(root, "tools/docgen/src/help.txt")?;
    let commands: Vec<String> = help_commands(&help).iter().map(|c| format!("pep-doc {c}")).collect();
    problems.extend(undocumented(root, "pep-doc", PEP_DOC, "option", &help_options(&help), mentions)?);
    problems.extend(undocumented(root, "pep-doc", PEP_DOC, "command", &commands, mentions)?);

    // pep-lsp: its options, the initialization options the server reads (as
    // JSON pointers, `/inlayHints/parameterNames`, spelled with dots), and
    // the VS Code extension's settings and commands (`pepper.lspPath`).
    const PEP_LSP: &str = "docs/src/tools/pep-lsp.md";
    let help = repository_file(root, "tools/lsp/src/help.txt")?;
    let server = repository_file(root, "tools/lsp/src/main.rs")?;
    let mut initialization: Vec<String> = server
        .match_indices("pointer(\"/")
        .filter_map(|(at, found)| {
            let rest = &server[at + found.len()..];
            rest.find('"').map(|end| rest[..end].replace('/', "."))
        })
        .collect();
    initialization.dedup();
    let package = repository_file(root, "tools/vscode-pepper/package.json")?;
    let mut settings: Vec<String> = package
        .match_indices("\"pepper.")
        .map(|(at, _)| package[at + 1..].chars().take_while(|c| *c != '"').collect())
        .collect();
    settings.sort();
    settings.dedup();
    problems.extend(undocumented(root, "pep-lsp", PEP_LSP, "option", &help_options(&help), mentions)?);
    problems.extend(undocumented(root, "pep-lsp", PEP_LSP, "initialization option", &initialization, mentions)?);
    problems.extend(undocumented(root, "pep-lsp", PEP_LSP, "VS Code setting or command", &settings, mentions)?);

    // cargo setup, from the usage it prints.
    const SETUP: &str = "docs/src/contributing/setup.md";
    let usage = repository_file(root, "xtask/src/usage.txt")?;
    problems.extend(undocumented(root, "cargo setup", SETUP, "option", &help_options(&usage), mentions)?);
    problems.extend(undocumented(root, "cargo setup", SETUP, "environment variable", &variables_named(&usage), mentions)?);

    // The install scripts: install.sh's usage text and the variables it
    // reads, and install.ps1's `[string]$Version = ...` and `[switch]$Yes`
    // parameters.
    const INSTALL: &str = "docs/src/tools/install.md";
    let script = repository_file(root, "scripts/install.sh")?;
    let usage = script
        .split("<<'EOF'\n")
        .nth(1)
        .and_then(|rest| rest.split("\nEOF").next())
        .ok_or("scripts/install.sh has no usage text")?;
    problems.extend(undocumented(root, "install.sh", INSTALL, "option", &help_options(usage), mentions)?);
    problems.extend(undocumented(root, "install.sh", INSTALL, "environment variable", &variables_named(&script), mentions)?);
    let parameters: Vec<String> = repository_file(root, "scripts/install.ps1")?
        .lines()
        .skip_while(|line| !line.starts_with("param("))
        .take_while(|line| *line != ")")
        .filter_map(|line| line.trim().strip_prefix("[string]$").or_else(|| line.trim().strip_prefix("[switch]$")))
        .map(|rest| format!("-{}", rest.split([' ', ',']).next().unwrap_or_default()))
        .collect();
    problems.extend(undocumented(root, "install.ps1", INSTALL, "parameter", &parameters, mentions)?);
    Ok(problems)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn help_parsing_finds_every_spelling() {
        let help = "usage: tool\n\nOptions:\n  -w, --write  rewrite\n      --check  list\n  --site <DIR>  a\n                continued -x\n  -O[=LEVEL]  b\n      --lto <MODE>  c [possible values: full, off]\nAfter:\n  --not-an-option\n";
        assert_eq!(help_options(help), ["-w", "--write", "--check", "--site", "-O", "--lto"]);
        assert_eq!(help_values(help), ["--lto full", "--lto off"]);
        assert!(mentions("`-O` alone", "-O"));
        assert!(!mentions("`-O2` only", "-O"));
        assert!(!mentions("--lto only", "-l"));
        assert!(mentions("ends with -T time.", "-T time"));
        assert!(mentions_variable("`PEPPER_SYSROOT_<TRIPLE>`", "PEPPER_SYSROOT_AARCH64_APPLE_DARWIN"));
        assert_eq!(variables_named("set PEPPER_A or PEPPER_B_C, not XPEPPER_D"), ["PEPPER_A", "PEPPER_B_C"]);
    }
}
