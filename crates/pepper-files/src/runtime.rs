//! Runtime discovery: port of `source/Compiler/Compiler.cpp:195-254`.

use std::path::PathBuf;

/// Search `runtime`, `.pep/runtime`, then 1..5 levels of `../runtime`;
/// collect `.pep` sources + `.a` libs + the dir for import search paths.
pub fn discover() -> (Vec<PathBuf>, Vec<PathBuf>, Vec<PathBuf>) {
    let cwd = std::env::current_dir().unwrap_or_default();
    let mut candidates: Vec<PathBuf> = vec![cwd.join("runtime"), cwd.join(".pep").join("runtime")];
    for level in 1..=5 {
        let mut dir = PathBuf::new();
        for _ in 0..level {
            dir.push("..");
        }
        dir.push("runtime");
        candidates.push(cwd.join(dir));
    }

    let mut sources: Vec<PathBuf> = vec![];
    let mut libs: Vec<PathBuf> = vec![];
    let mut import_dirs: Vec<PathBuf> = vec![];
    for candidate in candidates {
        let dir = candidate.canonicalize().unwrap_or(candidate.clone());
        if !dir.is_dir() {
            continue;
        }
        import_dirs.push(dir.clone());
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) == Some("pep") {
                sources.push(path);
            } else if path.extension().and_then(|e| e.to_str()) == Some("a") {
                libs.push(path);
            }
        }
    }
    (sources, libs, import_dirs)
}
