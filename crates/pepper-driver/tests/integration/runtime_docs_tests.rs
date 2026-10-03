//! The documentation standard for library code (see AGENTS.md): every public
//! declaration in `runtime/` and in the Pepper libraries under `tools/`
//! (`tools/syntax`) carries a `##` doc comment that describes it and tags
//! each parameter, generic parameter, and returned value. New files in those
//! folders are covered automatically.

use std::path::{Path, PathBuf};

/// The `.pep` files under `dir`, leaving out tests (`test/` folders, which
/// are not part of any module) and hidden folders such as `.pep/`.
fn runtime_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            let name = path.file_name().unwrap().to_string_lossy();
            if name != "test" && !name.starts_with('.') {
                runtime_files(&path, out);
            }
        } else if path.extension().is_some_and(|e| e == "pep") {
            out.push(path);
        }
    }
}

#[test]
fn every_public_runtime_declaration_is_documented() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut files = vec![];
    runtime_files(&root.join("runtime"), &mut files);
    runtime_files(&root.join("tools").join("syntax"), &mut files);
    files.sort();
    assert!(!files.is_empty());
    let mut report = String::new();
    for path in &files {
        let source = std::fs::read_to_string(path).unwrap();
        let name = path.strip_prefix(&root).unwrap().to_string_lossy().replace('\\', "/");
        let module = pepper_parser::parser::parse_source(&name, &source).unwrap();
        for error in pepper_parser::doc::check_documented(&module, &source) {
            report.push_str(&error.render_in(&name, &source));
            report.push('\n');
        }
    }
    assert!(report.is_empty(), "undocumented runtime API:\n{}", report);
}
