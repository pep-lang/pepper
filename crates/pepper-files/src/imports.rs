//! Import resolver: port of `source/Compiler/ImportResolver.cpp:26-43`.

use std::path::{Path, PathBuf};

/// Local `use "x"` → `<module dir>/x.pep`; global → first existing
/// `<search path>/x.pep`; empty result = resolve failure.
pub fn resolve(module_path: &Path, import_name: &str, local: bool, search_paths: &[PathBuf]) -> Option<PathBuf> {
    if local {
        let module_dir = module_path.parent().unwrap_or_else(|| Path::new("."));
        let import_path = module_dir.join(import_name).with_extension("pep");
        if import_path.exists() {
            return Some(import_path);
        }
        None
    } else {
        for search_path in search_paths {
            let path = search_path.join(import_name).with_extension("pep");
            if path.exists() {
                return Some(path);
            }
        }
        None
    }
}

/// A path's identity for "already loaded" checks: canonical when the file
/// exists, so `runtime/x.pep`, `D:\src\runtime\x.pep`, and the `\\?\`
/// form `canonicalize` returns on Windows all compare equal.
pub fn path_key(path: &Path) -> String {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf()).to_string_lossy().into_owned()
}
