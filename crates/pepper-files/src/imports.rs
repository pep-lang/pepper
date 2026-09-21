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
