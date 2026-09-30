//! The build cache: one object per compilation unit under
//! `.pep/cache/v1/<target>/`, reused when the unit's LLVM bitcode is
//! unchanged (build cache phase 1; see INTERNALS.md §4.3).
//!
//! Each unit has three files, named by the unit's path (`io/file`):
//!
//! - `<unit>.o`: the object;
//! - `<unit>.json`: the record, `{"key": "<hex>"}`, where the key hashes the
//!   compiler's identity and the unit's bitcode;
//! - `<unit>.lock`: an empty file that writers and readers lock.
//!
//! **Locking.** A compiler holds an exclusive OS lock on `<unit>.lock`
//! while it checks the record and, on a miss, writes the object and the
//! record. Each file is written under a temporary name and renamed into
//! place, the record last, so a crash never leaves a partial file under a
//! real name. The OS releases a lock when its file is closed, so it is
//! released when the write finishes and also when the process exits or
//! crashes. Before releasing the lock, the compiler hard-links (or copies)
//! the object into its build directory and links that, so another compiler
//! replacing the cached object later cannot change what this one links.
//! Units are independent: no compiler waits for one lock while holding
//! another, so two compilers cannot deadlock.

use inkwell::module::Module;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};

/// Cache format version: a new format ignores old directories.
const VERSION: &str = "v1";

/// An open build cache: the directory for this compiler's target.
pub struct Cache {
    dir: PathBuf,
    compiler: String,
}

impl Cache {
    /// The cache under `root` for the host target, created if missing.
    pub fn open(root: &Path) -> Result<Cache, String> {
        let machine = crate::default_target_machine()?;
        let triple = machine.get_triple().as_str().to_string_lossy().into_owned();
        let dir = root.join(VERSION).join(triple);
        std::fs::create_dir_all(&dir).map_err(|e| format!("cannot create {}: {}", dir.display(), e))?;
        let tag = root.join("CACHEDIR.TAG");
        if !tag.exists() {
            // Tells backup tools to skip the directory (https://bford.info/cachedir/).
            let _ = write_atomically(
                &tag,
                b"Signature: 8a477f597d28d172789f06886806bc55\n# The Pepper build cache (.pep/cache). It can be deleted.\n",
            );
        }
        Ok(Cache { dir, compiler: compiler_id() })
    }

    /// Put the object of the unit `name` at `out`: from the cache when its
    /// bitcode is unchanged, else emitted and stored first. Returns whether
    /// it was a hit. Safe to call from several threads for different units.
    pub fn object(&self, name: &str, module: &Module<'_>, out: &Path) -> Result<bool, String> {
        let key = self.key(module);
        let lock = self.lock_file(name)?;
        lock.lock().map_err(|e| format!("cannot lock the cache for '{}': {}", name, e))?;
        let hit = self.hit(name, &key);
        if !hit {
            self.store(name, module, &key)?;
        }
        place(&self.path(name, "o"), out)?;
        drop(lock);
        Ok(hit)
    }

    /// The cache key of a unit: its bitcode and the compiler that made it.
    fn key(&self, module: &Module<'_>) -> String {
        let mut hasher = blake3::Hasher::new();
        hasher.update(self.compiler.as_bytes());
        hasher.update(&[0]);
        hasher.update(module.write_bitcode_to_memory().as_slice());
        hasher.finalize().to_hex().to_string()
    }

    fn path(&self, unit: &str, extension: &str) -> PathBuf {
        self.dir.join(format!("{}.{}", unit, extension))
    }

    fn lock_file(&self, unit: &str) -> Result<File, String> {
        let path = self.path(unit, "lock");
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {}", parent.display(), e))?;
        }
        std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(&path)
            .map_err(|e| format!("cannot open {}: {}", path.display(), e))
    }

    /// Whether the unit's record has `key` and its object exists.
    fn hit(&self, unit: &str, key: &str) -> bool {
        let record = std::fs::read_to_string(self.path(unit, "json")).unwrap_or_default();
        record_key(&record) == Some(key) && self.path(unit, "o").is_file()
    }

    /// Emit the unit's object and record, each through a temporary file.
    fn store(&self, unit: &str, module: &Module<'_>, key: &str) -> Result<(), String> {
        let object = self.path(unit, "o");
        let temporary = temporary_path(&object);
        emit(module, &temporary)?;
        std::fs::rename(&temporary, &object).map_err(|e| format!("cannot write {}: {}", object.display(), e))?;
        write_atomically(&self.path(unit, "json"), format!("{{\"key\": \"{}\"}}\n", key).as_bytes())
    }
}

/// The key in a record, `{"key": "<hex>"}`.
fn record_key(record: &str) -> Option<&str> {
    let rest = &record[record.find("\"key\"")? + 5..];
    let rest = &rest[rest.find('"')? + 1..];
    Some(&rest[..rest.find('"')?])
}

/// Write an object file for `module` at `path`.
pub fn emit(module: &Module<'_>, path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {}", parent.display(), e))?;
    }
    crate::default_target_machine()?
        .write_to_file(module, inkwell::targets::FileType::Object, path)
        .map_err(|e| format!("obj emission failed: {}", e))
}

/// Make `to` a link to (or, across file systems, a copy of) `from`.
fn place(from: &Path, to: &Path) -> Result<(), String> {
    if let Some(parent) = to.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {}", parent.display(), e))?;
    }
    let _ = std::fs::remove_file(to);
    if std::fs::hard_link(from, to).is_ok() {
        return Ok(());
    }
    std::fs::copy(from, to).map(|_| ()).map_err(|e| format!("cannot copy {} to {}: {}", from.display(), to.display(), e))
}

/// A name beside `path` that no other process (or thread) uses.
fn temporary_path(path: &Path) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(format!(".{}.{:?}.tmp", std::process::id(), std::thread::current().id()).replace(['(', ')'], ""));
    path.with_file_name(name)
}

/// Write `bytes` to `path` through a temporary file and a rename.
fn write_atomically(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let temporary = temporary_path(path);
    let mut file = File::create(&temporary).map_err(|e| format!("cannot write {}: {}", temporary.display(), e))?;
    file.write_all(bytes).map_err(|e| format!("cannot write {}: {}", temporary.display(), e))?;
    drop(file);
    std::fs::rename(&temporary, path).map_err(|e| format!("cannot write {}: {}", path.display(), e))
}

/// Identifies the compiler: its version, the LLVM it was built with, and
/// the size and modification time of the running executable, so every
/// rebuild of the compiler invalidates the cache.
fn compiler_id() -> String {
    let (major, minor, patch) = inkwell::support::get_llvm_version();
    let exe = std::env::current_exe()
        .ok()
        .and_then(|path| std::fs::metadata(&path).ok().map(|m| (path, m)))
        .map(|(path, m)| {
            let modified = m.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).unwrap_or_default();
            format!("{} {} {}", path.display(), m.len(), modified.as_nanos())
        })
        .unwrap_or_default();
    format!("pepper {} llvm {}.{}.{} {}", env!("CARGO_PKG_VERSION"), major, minor, patch, exe)
}

#[cfg(test)]
mod tests {
    use super::record_key;

    #[test]
    fn reads_the_record_key() {
        assert_eq!(record_key("{\"key\": \"ab12\"}\n"), Some("ab12"));
        assert_eq!(record_key(""), None);
    }
}
