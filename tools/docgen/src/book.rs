//! Checks on the book's own chapters that mdBook does not make: Markdown
//! that renders without an error but comes out broken.

use std::path::Path;

/// Every `.md` file under `dir`, as paths relative to `root`.
fn chapters(dir: &Path, root: &Path, out: &mut Vec<(String, String)>) -> Result<(), String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("cannot read {}: {}", dir.display(), e))?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            chapters(&path, root, out)?;
        } else if path.extension().is_some_and(|e| e == "md") {
            let text = std::fs::read_to_string(&path).map_err(|e| format!("cannot read {}: {}", path.display(), e))?;
            let name = path.strip_prefix(root).unwrap_or(&path).to_string_lossy().replace('\\', "/");
            out.push((name, text.replace("\r\n", "\n")));
        }
    }
    Ok(())
}

/// The problems in one chapter, each as `file:line:col: error: message`.
///
/// An indented `{{#include}}` (one inside a list item) pastes the file's
/// lines at column 0, which ends the list item and the code block around
/// it: the rest of the example renders as prose, and its `#` comments as
/// headings.
pub fn lint_chapter(file: &str, text: &str) -> Vec<String> {
    let mut errors = vec![];
    for (i, line) in text.lines().enumerate() {
        let trimmed = line.trim_start();
        let indent = line.len() - trimmed.len();
        if indent > 0 && (trimmed.starts_with("{{#include") || trimmed.starts_with("{{#rustdoc_include")) {
            errors.push(format!(
                "{}:{}:{}: error: an indented include breaks the code block it sits in; move the example out of the list to column 0",
                file,
                i + 1,
                indent + 1
            ));
        }
    }
    errors
}

/// The problems in every chapter under `src_dir`.
pub fn lint(src_dir: &Path) -> Result<Vec<String>, String> {
    // Paths read from the repository root: `docs/src/...`.
    let root = src_dir.parent().and_then(Path::parent).unwrap_or(src_dir);
    let mut files = vec![];
    chapters(src_dir, root, &mut files)?;
    files.sort();
    Ok(files.iter().flat_map(|(name, text)| lint_chapter(name, text)).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_include_inside_a_list_item_is_an_error() {
        let text = "- item:\n\n  ```pepper\n  {{#include ../examples/a.pep}}\n  ```\n";
        assert_eq!(
            lint_chapter("src/a.md", text),
            vec!["src/a.md:4:3: error: an indented include breaks the code block it sits in; move the example out of the list to column 0"]
        );
        assert!(lint_chapter("src/a.md", "```pepper\n{{#include ../examples/a.pep}}\n```\n").is_empty());
    }

    #[test]
    fn the_book_has_no_broken_markdown() {
        let errors = lint(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/src")).unwrap();
        assert!(errors.is_empty(), "{}", errors.join("\n"));
    }
}
