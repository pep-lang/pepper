//! Import resolution. A module is a folder that contains a `module.pep`; the
//! module is named after the folder.
//!
//! - `import name` finds a module on the search paths: the `-I` directories
//!   (a program's dependencies) and the runtime directory.
//! - `import "path"` is local, relative to the importing file: the file
//!   `path.pep`, which must belong to the same module, or else the module
//!   folder `path/module.pep`.

use std::path::{Path, PathBuf};

/// The file a module's exports come from.
pub const MODULE_FILE: &str = "module.pep";

/// The directory holding the file `path`; `.` for a bare file name.
pub fn dir_of(path: &Path) -> &Path {
    match path.parent() {
        Some(d) if !d.as_os_str().is_empty() => d,
        _ => Path::new("."),
    }
}

/// What a local import (`import "x"`) names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalImport {
    /// `<from's dir>/x.pep`: a file, which must belong to the importing
    /// file's module.
    File(PathBuf),
    /// `<from's dir>/x/module.pep`: a module folder, anywhere.
    Module(PathBuf),
}

impl LocalImport {
    pub fn path(&self) -> &Path {
        match self {
            LocalImport::File(p) | LocalImport::Module(p) => p,
        }
    }
}

/// `import "x"` from `from`: the file `x.pep` next to it, or else the module
/// folder `x/` next to it. `stem` is the import's name without a trailing
/// `.pep` ([`Import::stem`](../../pepper_parser/ast/struct.Import.html#method.stem)).
pub fn resolve_local(from: &Path, stem: &str) -> Option<LocalImport> {
    let dir = dir_of(from);
    let file = dir.join(format!("{}.pep", stem));
    if file.is_file() {
        return Some(LocalImport::File(file));
    }
    let module = dir.join(stem).join(MODULE_FILE);
    module.is_file().then_some(LocalImport::Module(module))
}

/// `path`, canonical. A file not on disk (an editor's unsaved buffer) is
/// normalized through its folder, so it compares equal to canonical paths
/// of real files next to it (on Windows, `\\?\D:\...`).
fn normalized(path: &Path) -> PathBuf {
    if let Ok(p) = path.canonicalize() {
        return p;
    }
    match (dir_of(path).canonicalize(), path.file_name()) {
        (Ok(d), Some(name)) => d.join(name),
        _ => std::path::absolute(path).unwrap_or_else(|_| path.to_path_buf()),
    }
}

/// Where `import name` looks, in order: the `-I` directories (a program's
/// dependencies), then the runtime directories. Local modules are imported
/// by path (`import "geometry"`) instead.
pub fn search_paths(import_dirs: &[PathBuf], runtime_dirs: &[PathBuf]) -> Vec<PathBuf> {
    let mut paths: Vec<PathBuf> = import_dirs.to_vec();
    paths.extend(runtime_dirs.iter().cloned());
    paths
}

/// Module folders: which module a file belongs to, and whether a file import
/// stays inside it. Remembers each directory's module folder, so loading a
/// program looks each one up once.
#[derive(Default)]
pub struct ModuleRoots {
    /// directory (normalized) -> its module folder.
    by_dir: std::cell::RefCell<std::collections::HashMap<PathBuf, Option<PathBuf>>>,
    /// path as given -> normalized.
    normalized: std::cell::RefCell<std::collections::HashMap<PathBuf, PathBuf>>,
}

impl ModuleRoots {
    fn normalized(&self, path: &Path) -> PathBuf {
        if let Some(p) = self.normalized.borrow().get(path) {
            return p.clone();
        }
        let p = normalized(path);
        self.normalized.borrow_mut().insert(path.to_path_buf(), p.clone());
        p
    }

    fn of_dir(&self, dir: &Path) -> Option<PathBuf> {
        if let Some(root) = self.by_dir.borrow().get(dir) {
            return root.clone();
        }
        let root = if dir.join(MODULE_FILE).is_file() {
            Some(dir.to_path_buf())
        } else {
            dir.parent().and_then(|parent| self.of_dir(parent))
        };
        self.by_dir.borrow_mut().insert(dir.to_path_buf(), root.clone());
        root
    }

    /// The module folder the file `path` belongs to, if any.
    pub fn module_of(&self, path: &Path) -> Option<PathBuf> {
        let path = self.normalized(path);
        self.of_dir(path.parent()?)
    }

    /// The namespace of the file `path` (see
    /// `pepper_parser::namespace`): for a file of a module, the module's
    /// name and the file's path inside it (`io/file` for `io/file.pep`);
    /// otherwise the file's name. Without its extension, and with any
    /// character a namespace cannot hold replaced by `_`.
    pub fn namespace_of(&self, path: &Path) -> String {
        let normalized = self.normalized(path);
        let stem = normalized.with_extension("");
        let key = match self.module_of(path) {
            Some(root) => {
                let module = root.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                let inner = stem.strip_prefix(&root).unwrap_or(&stem);
                let parts: Vec<String> = inner.iter().map(|c| c.to_string_lossy().into_owned()).collect();
                format!("{}/{}", module, parts.join("/"))
            }
            None => stem.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        };
        key.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' || c == '/' { c } else { '_' }).collect()
    }

    /// Where a file import from `from` to the file `target` lands. Only
    /// [`Placement::SameModule`] is allowed: the target lies under the
    /// module's folder (for a file outside any module, its own folder) and
    /// not in another module nested there.
    pub fn placement(&self, from: &Path, target: &Path) -> Placement {
        let (from, target) = (self.normalized(from), self.normalized(target));
        let (Some(from_dir), Some(target_dir)) = (from.parent(), target.parent()) else {
            return Placement::OutsideFolder;
        };
        let from_root = self.of_dir(from_dir);
        let target_root = self.of_dir(target_dir);
        let scope = from_root.clone().unwrap_or_else(|| from_dir.to_path_buf());
        match (&from_root, &target_root) {
            _ if target.starts_with(&scope) && target_root == from_root => Placement::SameModule,
            (_, Some(_)) => Placement::OtherModule,
            (Some(_), None) => Placement::OutsideModule,
            (None, None) => Placement::OutsideFolder,
        }
    }
}

/// Where a file import lands relative to the importing file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Placement {
    /// In the importing file's module (or folder, outside any module).
    SameModule,
    /// In another module.
    OtherModule,
    /// Outside the importing file's module, in no module.
    OutsideModule,
    /// Outside the folder of an importing file that belongs to no module.
    OutsideFolder,
}

/// `import x` -> the first `<search path>/x/module.pep` that exists.
pub fn resolve_module(module_name: &str, search_paths: &[PathBuf]) -> Option<PathBuf> {
    search_paths.iter().map(|dir| dir.join(module_name).join(MODULE_FILE)).find(|p| p.is_file())
}

/// `--import NAME`: a module `NAME`, else a file `NAME.pep` on the search
/// paths.
pub fn resolve_forced(name: &str, search_paths: &[PathBuf]) -> Option<PathBuf> {
    // As for `import "util.pep"`, a trailing `.pep` is optional.
    let stem = name.strip_suffix(".pep").unwrap_or(name);
    resolve_module(stem, search_paths)
        .or_else(|| search_paths.iter().map(|dir| dir.join(format!("{}.pep", stem))).find(|p| p.is_file()))
}

/// A path's identity for "already loaded" checks: canonical when the file
/// exists, so `runtime/x.pep`, `D:\src\runtime\x.pep`, and the `\\?\`
/// form `canonicalize` returns on Windows all compare equal.
pub fn path_key(path: &Path) -> String {
    normalized(path).to_string_lossy().into_owned()
}
