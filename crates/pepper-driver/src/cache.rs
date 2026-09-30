//! The build cache: one object per compilation unit under
//! `.pep/cache/v1/<target>/`, reused without generating code when the
//! unit's sources and inputs are unchanged, or without emitting it when its
//! LLVM bitcode is (build cache phases 1 and 2a; see INTERNALS.md §4.3).
//!
//! Each unit has three files, named by the unit's path (`io/file`):
//!
//! - `<unit>.o`: the object;
//! - `<unit>.json`: the record, `{"key": "<hex>", "bitcode": "<hex>"}`: the
//!   unit's source key ([`unit_key`]) and the hash of the code the object
//!   was emitted from;
//! - `<unit>.lock`: an empty file that writers and readers lock.
//!
//! **Locking.** A compiler holds an exclusive OS lock on `<unit>.lock`
//! while it checks the record and, on a miss, generates the unit and writes
//! the object and the record. Each file is written under a temporary name and renamed into
//! place, the record last, so a crash never leaves a partial file under a
//! real name. The OS releases a lock when its file is closed, so it is
//! released when the write finishes and also when the process exits or
//! crashes. Before releasing the lock, the compiler hard-links (or copies)
//! the object into its build directory and links that, so another compiler
//! replacing the cached object later cannot change what this one links.
//! Units are independent: no compiler waits for one lock while holding
//! another, so two compilers cannot deadlock.

use inkwell::module::Module;
use pepper_sema::program::{Program, Unit};
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

    /// Put the object of the unit `name` at `out`. A unit whose record has
    /// `key` (its sources, see [`unit_key`]) is a hit: its object is reused
    /// without generating any code. Otherwise `generate` builds the unit's
    /// module; if its bitcode matches the record's (an edit that changed no
    /// code, such as a comment), the object is still reused, else it is
    /// emitted and stored. With `verify`, a hit generates the module anyway
    /// and fails if its bitcode differs from the record's, which proves the
    /// key covers every input. Safe to call from several threads for
    /// different units.
    pub fn object<'ctx>(
        &self,
        name: &str,
        key: &str,
        out: &Path,
        verify: bool,
        generate: impl FnOnce() -> Result<Module<'ctx>, String>,
    ) -> Result<Outcome, String> {
        let lock = self.lock_file(name)?;
        lock.lock().map_err(|e| format!("cannot lock the cache for '{}': {}", name, e))?;
        let record = self.record(name);
        let object = self.path(name, "o");
        let present = object.is_file();
        let outcome = if present && record.as_ref().is_some_and(|r| r.key == key) {
            if verify {
                let module = generate()?;
                let bitcode = self.bitcode_hash(&module);
                if record.as_ref().map(|r| r.bitcode.as_str()) != Some(bitcode.as_str()) {
                    let now = self.path(name, "verify.ll");
                    let _ = module.print_to_file(&now);
                    return Err(format!(
                        "build cache: unit '{}' matched its recorded sources, but its code changed; the cache key misses an input \
                         (compare {} with {})",
                        name,
                        self.path(name, "ll").display(),
                        now.display()
                    ));
                }
            }
            Outcome::Hit
        } else {
            let module = generate()?;
            let bitcode = self.bitcode_hash(&module);
            let same_code = present && record.as_ref().is_some_and(|r| r.bitcode == bitcode);
            if verify {
                // What a later verifying hit compares against.
                let _ = module.print_to_file(self.path(name, "ll"));
            }
            if !same_code {
                let temporary = temporary_path(&object);
                emit(&module, &temporary)?;
                std::fs::rename(&temporary, &object).map_err(|e| format!("cannot write {}: {}", object.display(), e))?;
            }
            write_atomically(&self.path(name, "json"), Record { key: key.to_string(), bitcode }.to_json().as_bytes())?;
            if same_code { Outcome::SameCode } else { Outcome::Miss }
        };
        place(&object, out)?;
        drop(lock);
        Ok(outcome)
    }

    /// The hash of a unit's code: its bitcode and the compiler that made it.
    fn bitcode_hash(&self, module: &Module<'_>) -> String {
        let mut hasher = blake3::Hasher::new();
        hasher.update(self.compiler.as_bytes());
        hasher.update(&[0]);
        hasher.update(module.write_bitcode_to_memory().as_slice());
        hasher.finalize().to_hex().to_string()
    }

    /// This compiler's identity, which every key includes.
    pub fn compiler(&self) -> &str {
        &self.compiler
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

    /// The unit's record, if it has a readable one.
    fn record(&self, unit: &str) -> Option<Record> {
        Record::parse(&std::fs::read_to_string(self.path(unit, "json")).ok()?)
    }
}

/// The source key of `unit`: a hash of the compiler, the unit's files,
/// and `inputs`, every file its code can depend on
/// ([`Program::unit_inputs`](pepper_sema::program::Program::unit_inputs)),
/// each by name, namespace and text. `source_hashes` holds each program
/// file's BLAKE3 hash, indexed like `program.files`.
pub fn unit_key(compiler: &str, program: &Program, unit: &Unit, inputs: &[usize], source_hashes: &[blake3::Hash]) -> String {
    let mut hasher = blake3::Hasher::new();
    let mut field = |bytes: &[u8]| {
        hasher.update(&(bytes.len() as u64).to_le_bytes());
        hasher.update(bytes);
    };
    field(b"pepper unit key 1");
    field(compiler.as_bytes());
    field(unit.name.as_bytes());
    for &file in &unit.files {
        field(program.files[file].name.as_bytes());
    }
    for &file in inputs {
        let f = &program.files[file];
        field(f.name.as_bytes());
        field(f.namespace.as_bytes());
        field(&[f.prelude as u8, f.prelude_part as u8]);
        field(source_hashes[file].as_bytes());
    }
    hasher.finalize().to_hex().to_string()
}

/// How [`Cache::object`] got a unit's object.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// The unit's sources were unchanged: no code was generated.
    Hit,
    /// The sources changed but the generated code did not: the code was
    /// generated, and the stored object reused.
    SameCode,
    /// The code changed: it was generated, emitted and stored.
    Miss,
}

/// A unit's record, `<unit>.json`.
struct Record {
    /// The unit's source key ([`unit_key`]).
    key: String,
    /// The hash of the code its object was emitted from.
    bitcode: String,
}

impl Record {
    fn to_json(&self) -> String {
        format!("{{\"key\": \"{}\", \"bitcode\": \"{}\"}}\n", self.key, self.bitcode)
    }

    fn parse(text: &str) -> Option<Record> {
        Some(Record { key: json_string(text, "key")?.to_string(), bitcode: json_string(text, "bitcode")?.to_string() })
    }
}

/// The string value of `field` in a record (`{"key": "<hex>", ...}`).
fn json_string<'a>(record: &'a str, field: &str) -> Option<&'a str> {
    let quoted = format!("\"{}\"", field);
    let rest = &record[record.find(&quoted)? + quoted.len()..];
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
    use super::Record;

    #[test]
    fn records_round_trip() {
        let record = Record { key: "ab12".to_string(), bitcode: "cd34".to_string() };
        let read = Record::parse(&record.to_json()).unwrap();
        assert_eq!((read.key.as_str(), read.bitcode.as_str()), ("ab12", "cd34"));
        assert!(Record::parse("{\"key\": \"ab12\"}\n").is_none());
        assert!(Record::parse("").is_none());
    }
}
