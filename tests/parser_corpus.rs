//! Integration test: every `.pep` file in the `tests/` corpus must parse
//! into a well-formed module (no errors, at least one declaration).
//! The corpus is the executable spec for the parser.

use std::path::{Path, PathBuf};

fn collect_pep_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries {
        let path = entry.expect("read_dir entry").path();
        if path.is_dir() {
            collect_pep_files(&path, out);
        } else if path.extension().map_or(false, |e| e == "pep") {
            out.push(path);
        }
    }
}

#[test]
fn corpus_files_parse() {
    let mut files = Vec::new();
    collect_pep_files(Path::new("tests"), &mut files);
    files.sort();
    assert!(!files.is_empty(), "no .pep corpus files found under tests/");

    for file in &files {
        let rel = file.to_string_lossy().to_string();
        let module = pepper::parser::parse_file(file)
            .unwrap_or_else(|e| panic!("failed to parse {}: {}", rel, e));
        assert!(!module.declarations.is_empty(), "{} parsed but produced no declarations", rel);
    }
}
