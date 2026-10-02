//! The build cache: one object per compilation unit under
//! `.pep/cache/v1/<target>/O<n>[-g]/` (a directory per `-O` level and `-g`), reused
//! without generating code when the unit's sources and inputs are
//! unchanged, or without emitting it when its LLVM bitcode is (build cache
//! phases 1, 2a and 2b; see INTERNALS.md §4.3).
//!
//! Each unit has three files, named by the unit's path (`io/file`):
//!
//! - `<unit>.o`: the object;
//! - `<unit>.json`: the record,
//!   `{"key": "<hex>", "bitcode": "<hex>", "warnings": "no", "interfaces": "<namespace>=<hex>;..."}`:
//!   the unit's key ([`crate::keys`]), the hash of the code the object was
//!   emitted from, whether compiling the unit warned, and its files'
//!   interface hashes (`pepper_sema::interface`), which other units' keys
//!   read;
//! - `<unit>.summaries`: its functions' link summaries (see
//!   [`parse_summaries`]), which a build that skips the unit's bodies uses
//!   in their place;
//! - `<unit>.lock`: an empty file that writers and readers lock.
//!
//! And per program, under `programs/`, named by its root file's namespace:
//!
//! - `<program>.o`: its program object (`__program`);
//! - `<program>.json`: its record,
//!   `{"key": "<hex>", "libraries": "<a>;<b>", "link": "<hex>", "output": "<hex>"}`:
//!   the program's key ([`crate::keys::Keys::program_key`]), its `[Link]`
//!   libraries, and the inputs and output hash of its last link. When every
//!   unit is a hit and the record's key matches, the driver skips sema and
//!   code generation; when the link's inputs and the output file are also
//!   unchanged, it skips the link too.
//!
//! And one file per source file, whatever its unit (phase 2c):
//!
//! - `parsed/<hash of its path>.pepi`, beside the `O<n>` directories (one
//!   for every level): its syntax tree, `postcard`-encoded
//!   after a 32-byte stamp (a hash of the compiler and the file's text), so
//!   an unchanged file is not parsed again (see [`ParseCache`]). Written
//!   through a temporary file and a rename, without a lock: every writer of
//!   one stamp writes the same tree, and a reader checks the stamp.
//!
//! And one file per checked runtime (canonical specialization phase 4):
//!
//! - `runtime/<key>.checked`, beside `parsed/`: the runtime checked alone
//!   (`pepper_sema::checked::CheckedRuntime`), `postcard`-encoded after a
//!   32-byte stamp (a hash of the compiler and the key, which hashes the
//!   target and the runtime files' names, namespaces and texts). Its
//!   locations number the runtime files in order, mapped to and from the
//!   program's (`with_file_map`). Written like the syntax trees.
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
use pepper_codegen::target::{Cpu, OptLevel};
use pepper_sema::checked::{CheckedRuntime, RuntimeStore};
use pepper_sema::program::ParseCache;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};

/// Cache format version: a new format ignores old directories.
const VERSION: &str = "v1";

/// How the units of a build are compiled: the `-O` level, and whether each
/// unit is kept as bitcode for link-time optimization (see [`crate::lto`])
/// rather than as an object.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Build {
    pub opt_level: OptLevel,
    pub lto: bool,
    /// The CPU to generate code for (`-march`, `-mcpu`, `-mtune`, `-m<feature>`).
    pub cpu: Cpu,
    /// Debug info (`-g`).
    pub debug: bool,
    /// The runtime checks the code performs (`--no-runtime-checks`).
    pub runtime_checks: pepper_codegen::checks::RuntimeChecks,
    /// The build options (`-D`), which choose what code exists.
    pub build_options: pepper_sema::BuildOptions,
}

impl Build {
    /// The extension of a unit's file: `bc` with LTO, else `o`.
    pub fn extension(&self) -> &'static str {
        if self.lto { "bc" } else { "o" }
    }

    /// How the options appear in the cache: `O2-x86-64@generic`,
    /// `O2-lto-apple-m1`, `O2-g-x86-64@generic`, `O2-nrc-overflow-x86-64@generic`,
    /// `O0-D1a2b3c4d5e6f-x86-64@generic`. A CPU name that is not a plain file name (from
    /// `-march=native`'s features, say) is hashed.
    pub(crate) fn name(&self) -> String {
        let cpu = self.cpu.key();
        let cpu = if cpu.len() <= 48 && cpu.chars().all(|c| c.is_ascii_alphanumeric() || "-_.+@".contains(c)) {
            cpu
        } else {
            blake3::hash(cpu.as_bytes()).to_hex()[..16].to_string()
        };
        // `-nrc-overflow-shift`: the checks `--no-runtime-checks` removed.
        let removed: String = self.runtime_checks.removed().iter().map(|name| format!("-{}", name)).collect();
        let removed = if removed.is_empty() { String::new() } else { format!("-nrc{}", removed) };
        // `-D<hash>`: the build options, hashed, since their values may be
        // anything.
        let options = if self.build_options.is_empty() {
            String::new()
        } else {
            let mut hasher = blake3::Hasher::new();
            for (name, value) in &self.build_options {
                for part in [name, value] {
                    hasher.update(&(part.len() as u64).to_le_bytes());
                    hasher.update(part.as_bytes());
                }
            }
            format!("-D{}", &hasher.finalize().to_hex()[..12])
        };
        format!("O{}{}{}{}{}-{}", self.opt_level.number(), if self.lto { "-lto" } else { "" }, if self.debug { "-g" } else { "" }, removed, options, cpu)
    }
}

/// An open build cache: the directory for this compiler's target.
pub struct Cache {
    dir: PathBuf,
    compiler: String,
    /// How units are compiled; part of [`Cache::compiler`].
    build: Build,
    /// Where syntax trees are kept, and the compiler they are stamped with:
    /// shared by every `-O` level, since parsing does not depend on it.
    parsed_dir: PathBuf,
    parser: String,
    /// Where checked runtimes are kept (see [`RuntimeStore`]), shared by
    /// every `-O` level like the syntax trees.
    runtime_dir: PathBuf,
}

impl Cache {
    /// The cache under `root` for the target, created if missing, for
    /// units compiled as `build` says.
    pub fn open(root: &Path, build: Build) -> Result<Cache, String> {
        let machine = crate::default_target_machine()?;
        let triple = machine.get_triple().as_str().to_string_lossy().into_owned();
        // A directory per level, LTO mode and CPU, so switching between
        // `-O0` and `-O2` builds keeps both levels' objects (a unit has one record per
        // directory).
        let target = root.join(VERSION).join(triple);
        let dir = target.join(build.name());
        std::fs::create_dir_all(&dir).map_err(|e| format!("cannot create {}: {}", dir.display(), e))?;
        let tag = root.join("CACHEDIR.TAG");
        if !tag.exists() {
            // Tells backup tools to skip the directory (https://bford.info/cachedir/).
            let _ = write_atomically(
                &tag,
                b"Signature: 8a477f597d28d172789f06886806bc55\n# The Pepper build cache (.pep/cache). It can be deleted.\n",
            );
        }
        // The options are part of the compiler's identity, so they are in
        // every key and code hash: an object built with others never hits,
        // nor counts as the same code. Parsing depends on neither.
        let parser = compiler_id();
        let compiler = format!("{} -{}", parser, build.name());
        Ok(Cache { dir, compiler, build, parsed_dir: target.join("parsed"), parser, runtime_dir: target.join("runtime") })
    }

    /// Reuse the unit `name` before sema, so sema may skip its bodies
    /// (phase 2b): when it is a hit for `key` and compiled without warnings
    /// (a unit that warned is checked again, so its warnings are reported
    /// on every build), its object is put at `out` now, under the lock, and
    /// this returns its recorded link summaries (see [`parse_summaries`]).
    /// Another program can replace the unit's object in the cache later in
    /// this build (a program with other overrides gives a unit another
    /// key), so the unit's object must not be looked up again.
    pub fn reuse(&self, name: &str, key: &str, out: &Path) -> Result<Option<String>, String> {
        if !self.record(name).is_some_and(|r| r.key == key && !r.warned) {
            return Ok(None);
        }
        let lock = self.lock_file(name)?;
        lock.lock().map_err(|e| format!("cannot lock the cache for '{}': {}", name, e))?;
        let object = self.path(name, self.build.extension());
        let mut reused = None;
        if object.is_file() && self.record(name).is_some_and(|r| r.key == key && !r.warned) {
            place(&object, out)?;
            reused = Some(std::fs::read_to_string(self.path(name, "summaries")).unwrap_or_default());
        }
        drop(lock);
        Ok(reused)
    }

    /// The program `name`'s record, when it has the key `key` and its object
    /// is there: its object is put at `out` (under the program's lock), and
    /// its record returned.
    pub fn program(&self, name: &str, key: &str, out: &Path) -> Result<Option<ProgramRecord>, String> {
        let unit = format!("programs/{}", name);
        let Some(record) = self.program_record(name).filter(|r| r.key == key) else { return Ok(None) };
        let lock = self.lock_file(&unit)?;
        lock.lock().map_err(|e| format!("cannot lock the cache for '{}': {}", unit, e))?;
        let object = self.path(&unit, self.build.extension());
        let found = object.is_file() && self.program_record(name).is_some_and(|r| r.key == key);
        if found {
            place(&object, out)?;
        }
        drop(lock);
        Ok(found.then_some(record))
    }

    /// Store the program `name`'s object (at `object`) and record.
    pub fn store_program(&self, name: &str, record: &ProgramRecord, object: &Path) -> Result<(), String> {
        let unit = format!("programs/{}", name);
        let lock = self.lock_file(&unit)?;
        lock.lock().map_err(|e| format!("cannot lock the cache for '{}': {}", unit, e))?;
        let stored = self.path(&unit, self.build.extension());
        let temporary = temporary_path(&stored);
        std::fs::copy(object, &temporary).map_err(|e| format!("cannot write {}: {}", temporary.display(), e))?;
        std::fs::rename(&temporary, &stored).map_err(|e| format!("cannot write {}: {}", stored.display(), e))?;
        write_atomically(&self.path(&unit, "json"), record.to_json().as_bytes())?;
        drop(lock);
        Ok(())
    }

    /// Record that the program `name`, with the key `key`, was last linked
    /// from the inputs hashed as `link` into a file hashed as `output`.
    pub fn record_link(&self, name: &str, key: &str, link: &str, output: &str) -> Result<(), String> {
        let unit = format!("programs/{}", name);
        let lock = self.lock_file(&unit)?;
        lock.lock().map_err(|e| format!("cannot lock the cache for '{}': {}", unit, e))?;
        if let Some(mut record) = self.program_record(name).filter(|r| r.key == key) {
            record.link = link.to_string();
            record.output = output.to_string();
            write_atomically(&self.path(&unit, "json"), record.to_json().as_bytes())?;
        }
        drop(lock);
        Ok(())
    }

    fn program_record(&self, name: &str) -> Option<ProgramRecord> {
        ProgramRecord::parse(&std::fs::read_to_string(self.path(&format!("programs/{}", name), "json")).ok()?)
    }

    /// The interface hashes of the unit `name`'s files, by namespace, when
    /// its record has the key `key`. Read without the lock: a record is
    /// replaced whole, and its interfaces follow from its key, so they are
    /// right for this program whichever writer wrote them.
    pub fn interfaces(&self, name: &str, key: &str) -> Option<Vec<(String, String)>> {
        self.record(name).filter(|r| r.key == key && !r.interfaces.is_empty()).map(|r| r.interfaces)
    }

    /// Put the object of `unit.name` at `unit.out`. A unit whose record has
    /// `unit.key` (its sources, see [`unit_key`]) is a hit: its object is
    /// reused without generating any code. Otherwise `generate` builds the
    /// unit's module; if its bitcode matches the record's (an edit that
    /// changed no code, such as a comment), the object is still reused,
    /// else it is emitted and stored. With `unit.verify`, a hit generates
    /// the module anyway and fails if its bitcode differs from the record's,
    /// which proves the key covers every input. Returns how the object was
    /// got and the hash of its code. Safe to call from several threads for different
    /// units.
    pub fn object<'ctx>(
        &self,
        unit: &UnitRequest<'_>,
        generate: impl FnOnce() -> Result<Module<'ctx>, String>,
    ) -> Result<(Outcome, String), String> {
        let UnitRequest { name, key, out, verify, warned, summaries, interfaces } = *unit;
        let lock = self.lock_file(name)?;
        lock.lock().map_err(|e| format!("cannot lock the cache for '{}': {}", name, e))?;
        let record = self.record(name);
        let object = self.path(name, self.build.extension());
        let present = object.is_file();
        let (outcome, code) = if present && let Some(record) = record.as_ref().filter(|r| r.key == key) {
            if verify {
                if record.interfaces != interfaces {
                    return Err(format!(
                        "build cache: unit '{}' matched its recorded key, but its files' interface hashes changed \
                         (recorded {}, now {}); an interface depends on something its key leaves out",
                        name,
                        encode_interfaces(&record.interfaces),
                        encode_interfaces(interfaces)
                    ));
                }
                let module = generate()?;
                let bitcode = self.bitcode_hash(&module);
                if record.bitcode != bitcode {
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
            (Outcome::Hit, record.bitcode.clone())
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
                emit(&module, &temporary, &self.build)?;
                std::fs::rename(&temporary, &object).map_err(|e| format!("cannot write {}: {}", object.display(), e))?;
            }
            write_atomically(&self.path(name, "summaries"), summaries.as_bytes())?;
            let record = Record { key: key.to_string(), bitcode: bitcode.clone(), warned, interfaces: interfaces.to_vec() };
            write_atomically(&self.path(name, "json"), record.to_json().as_bytes())?;
            (if same_code { Outcome::SameCode } else { Outcome::Miss }, bitcode)
        };
        place(&object, out)?;
        drop(lock);
        Ok((outcome, code))
    }

    /// Fail unless `module` has the code `code` (a hash [`Cache::object`]
    /// returned for the unit `name`): verifying, a unit generated with the
    /// cached units' bodies skipped must match the one generated from the
    /// whole program. Writes `<unit>.trial.ll` on a mismatch.
    pub fn check_code(&self, name: &str, code: &str, module: &Module<'_>) -> Result<(), String> {
        if self.bitcode_hash(module) == code {
            return Ok(());
        }
        let trial = self.path(name, "trial.ll");
        let _ = module.print_to_file(&trial);
        Err(format!(
            "build cache: unit '{}' has different code when sema skips the cached units' bodies (compare {} with {})",
            name,
            self.path(name, "ll").display(),
            trial.display()
        ))
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

    /// Where the syntax tree of the source file at `source` is kept.
    fn parsed_path(&self, source: &Path) -> PathBuf {
        let key = pepper_files::imports::path_key(source);
        self.parsed_dir.join(format!("{}.pepi", &blake3::hash(key.as_bytes()).to_hex()[..32]))
    }

    /// Where the checked runtime stored under `key` is kept.
    fn runtime_path(&self, key: &str) -> PathBuf {
        self.runtime_dir.join(format!("{}.checked", &key[..32.min(key.len())]))
    }

    /// What a checked runtime is stamped with: this compiler and its key.
    fn runtime_stamp(&self, key: &str) -> blake3::Hash {
        let mut hasher = blake3::Hasher::new();
        hasher.update(b"pepper checked 1\0");
        hasher.update(self.parser.as_bytes());
        hasher.update(&[0]);
        hasher.update(key.as_bytes());
        hasher.finalize()
    }

    /// What a kept tree is stamped with: this compiler and the text parsed.
    fn parsed_stamp(&self, text: &str) -> blake3::Hash {
        let mut hasher = blake3::Hasher::new();
        hasher.update(b"pepper pepi 1\0");
        hasher.update(self.parser.as_bytes());
        hasher.update(&[0]);
        hasher.update(text.as_bytes());
        hasher.finalize()
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

/// One unit for [`Cache::object`].
#[derive(Debug, Clone, Copy)]
pub struct UnitRequest<'a> {
    /// The unit's name, which names its cache files.
    pub name: &'a str,
    /// Its key ([`crate::keys`]).
    pub key: &'a str,
    /// Where to put its object.
    pub out: &'a Path,
    /// Generate a hit anyway and check its code (`--verify-cache`).
    pub verify: bool,
    /// Compiling it warned (recorded on a miss; see [`Cache::reuse`]).
    pub warned: bool,
    /// Its functions' link summaries, stored on a miss (see
    /// [`parse_summaries`]).
    pub summaries: &'a str,
    /// Its files' interface hashes, by namespace, stored on a miss.
    pub interfaces: &'a [(String, String)],
}

impl ParseCache for Cache {
    fn get(&self, path: &Path, source: &str) -> Option<pepper_parser::ast::Module> {
        let bytes = std::fs::read(self.parsed_path(path)).ok()?;
        let (stamp, tree) = bytes.split_at_checked(32)?;
        if stamp != self.parsed_stamp(source).as_bytes() {
            return None;
        }
        postcard::from_bytes(tree).ok()
    }

    fn put(&self, path: &Path, source: &str, module: &pepper_parser::ast::Module) {
        let Ok(tree) = postcard::to_stdvec(module) else { return };
        let mut bytes = self.parsed_stamp(source).as_bytes().to_vec();
        bytes.extend(tree);
        let at = self.parsed_path(path);
        // A cache that cannot be written only costs the next compile a parse.
        if let Some(parent) = at.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = write_atomically(&at, &bytes);
    }
}

impl RuntimeStore for Cache {
    fn load(&self, key: &str, files: &[u32]) -> Option<CheckedRuntime> {
        let bytes = std::fs::read(self.runtime_path(key)).ok()?;
        let (stamp, runtime) = bytes.split_at_checked(32)?;
        if stamp != self.runtime_stamp(key).as_bytes() {
            return None;
        }
        let map = files.iter().enumerate().map(|(i, &file)| (i as u32, file)).collect();
        pepper_parser::diagnostic::with_file_map(map, || postcard::from_bytes(runtime).ok())
    }

    fn save(&self, key: &str, files: &[u32], runtime: &CheckedRuntime) {
        let map = files.iter().enumerate().map(|(i, &file)| (file, i as u32)).collect();
        let Ok(encoded) = pepper_parser::diagnostic::with_file_map(map, || postcard::to_stdvec(runtime)) else { return };
        let mut bytes = self.runtime_stamp(key).as_bytes().to_vec();
        bytes.extend(encoded);
        let at = self.runtime_path(key);
        // A cache that cannot be written only costs the next compile a check.
        let _ = std::fs::create_dir_all(&self.runtime_dir);
        let _ = write_atomically(&at, &bytes);
    }
}

/// The lines of a unit's `<unit>.summaries`: each function's link summary
/// (`check_confinement`), by its file's namespace and its location's span:
/// `<namespace>\t<start>\t<end>\t<summary>`.
pub fn parse_summaries(text: &str) -> impl Iterator<Item = (&str, pepper_parser::ast::Span, &str)> {
    text.lines().filter_map(|line| {
        let mut fields = line.splitn(4, '\t');
        let namespace = fields.next()?;
        let start = fields.next()?.parse().ok()?;
        let end = fields.next()?.parse().ok()?;
        Some((namespace, pepper_parser::ast::Span { start, end }, fields.next()?))
    })
}

/// One line of a unit's summaries file (see [`parse_summaries`]).
pub fn summary_line(namespace: &str, span: pepper_parser::ast::Span, summary: &str) -> String {
    format!("{}\t{}\t{}\t{}\n", namespace, span.start, span.end, summary)
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
    /// The unit's key ([`crate::keys`]).
    key: String,
    /// The hash of the code its object was emitted from.
    bitcode: String,
    /// Compiling the unit reported warnings. A record without the field
    /// counts as warned, so its unit is checked again.
    warned: bool,
    /// Its files' interface hashes, by namespace. Empty in a record from
    /// before phase 2c, whose unit's dependents then miss.
    interfaces: Vec<(String, String)>,
}

impl Record {
    fn to_json(&self) -> String {
        let warned = if self.warned { "yes" } else { "no" };
        format!(
            "{{\"key\": \"{}\", \"bitcode\": \"{}\", \"warnings\": \"{}\", \"interfaces\": \"{}\"}}\n",
            self.key,
            self.bitcode,
            warned,
            encode_interfaces(&self.interfaces)
        )
    }

    fn parse(text: &str) -> Option<Record> {
        Some(Record {
            key: json_string(text, "key")?.to_string(),
            bitcode: json_string(text, "bitcode")?.to_string(),
            warned: json_string(text, "warnings") != Some("no"),
            interfaces: json_string(text, "interfaces").map(decode_interfaces).unwrap_or_default(),
        })
    }
}

/// A program's record, `programs/<program>.json`.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ProgramRecord {
    /// The program's key ([`crate::keys::Keys::program_key`]).
    pub key: String,
    /// Its `[Link]` libraries, in order.
    pub libraries: Vec<String>,
    /// Its `[Link(path = ...)]` folders, in order.
    pub library_dirs: Vec<String>,
    /// The hash of its last link's inputs (objects, libraries, output
    /// path), and of the file that link wrote; empty before a link.
    pub link: String,
    pub output: String,
    /// The declarations of its C header (`passes::exports::header_declarations`),
    /// empty when it exports nothing.
    pub header: String,
}

impl ProgramRecord {
    fn to_json(&self) -> String {
        format!(
            "{{\"key\": \"{}\", \"libraries\": \"{}\", \"library_dirs\": \"{}\", \"link\": \"{}\", \"output\": \"{}\", \"header\": \"{}\"}}\n",
            self.key,
            self.libraries.join(";"),
            std::env::join_paths(&self.library_dirs).map(|joined| joined.to_string_lossy().into_owned()).unwrap_or_default(),
            self.link,
            self.output,
            crate::library::to_hex(&self.header)
        )
    }

    fn parse(text: &str) -> Option<ProgramRecord> {
        let libraries = json_string(text, "libraries")?;
        Some(ProgramRecord {
            key: json_string(text, "key")?.to_string(),
            libraries: libraries.split(';').filter(|l| !l.is_empty()).map(str::to_string).collect(),
            library_dirs: std::env::split_paths(json_string(text, "library_dirs").unwrap_or_default())
                .filter(|dir| !dir.as_os_str().is_empty())
                .map(|dir| dir.to_string_lossy().into_owned())
                .collect(),
            link: json_string(text, "link").unwrap_or_default().to_string(),
            output: json_string(text, "output").unwrap_or_default().to_string(),
            header: crate::library::from_hex(json_string(text, "header").unwrap_or_default())?,
        })
    }
}

/// `<namespace>=<hash>;...`, as a record holds interface hashes. Neither a
/// namespace (a path) nor a hash has `=`, `;` or `"`.
fn encode_interfaces(interfaces: &[(String, String)]) -> String {
    interfaces.iter().map(|(namespace, hash)| format!("{}={}", namespace, hash)).collect::<Vec<_>>().join(";")
}

fn decode_interfaces(text: &str) -> Vec<(String, String)> {
    text.split(';').filter_map(|entry| entry.split_once('=')).map(|(n, h)| (n.to_string(), h.to_string())).collect()
}

/// The string value of `field` in a record (`{"key": "<hex>", ...}`).
fn json_string<'a>(record: &'a str, field: &str) -> Option<&'a str> {
    let quoted = format!("\"{}\"", field);
    let rest = &record[record.find(&quoted)? + quoted.len()..];
    let rest = &rest[rest.find('"')? + 1..];
    Some(&rest[..rest.find('"')?])
}

/// Write `module` at `path` as `build` says: optimized at its level, then
/// an object, or with LTO bitcode that only the link-time half of the
/// pipeline has yet to run over (see [`crate::lto`]). The cache hashes a
/// unit's code before this, so a unit whose code did not change is not
/// optimized again.
pub fn emit(module: &Module<'_>, path: &Path, build: &Build) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {}", parent.display(), e))?;
    }
    build.cpu.stamp(module);
    if build.lto {
        pepper_codegen::target::optimize_with(module, build.opt_level, pepper_codegen::target::Pipeline::PreLink, &build.cpu)?;
        return match module.write_bitcode_to_path(path) {
            true => Ok(()),
            false => Err(format!("cannot write {}", path.display())),
        };
    }
    pepper_codegen::target::optimize_with(module, build.opt_level, pepper_codegen::target::Pipeline::Default, &build.cpu)?;
    let machine = pepper_codegen::target::machine(build.opt_level, &build.cpu)?;
    pepper_codegen::target::write_object(&machine, module, path).map_err(|e| format!("obj emission failed: {}", e))
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
    fn program_records_round_trip() {
        let record = super::ProgramRecord {
            key: "ab12".to_string(),
            libraries: vec!["ssl".to_string(), "crypto".to_string()],
            library_dirs: vec!["/opt/vendor/lib".to_string(), "/usr/local/lib".to_string()],
            link: "cd34".to_string(),
            output: "ef56".to_string(),
            header: "int32_t add(int32_t a, int32_t b);\n".to_string(),
        };
        let read = super::ProgramRecord::parse(&record.to_json()).unwrap();
        assert_eq!(read, record);
        let older = super::ProgramRecord::parse("{\"key\": \"ab12\", \"libraries\": \"\"}").unwrap();
        assert!(older.libraries.is_empty() && older.library_dirs.is_empty() && older.header.is_empty());
    }

    #[test]
    fn records_round_trip() {
        for warned in [false, true] {
            let interfaces = vec![("io/file".to_string(), "ef56".to_string()), ("prelude".to_string(), "78ab".to_string())];
            let record = Record { key: "ab12".to_string(), bitcode: "cd34".to_string(), warned, interfaces: interfaces.clone() };
            let read = Record::parse(&record.to_json()).unwrap();
            assert_eq!((read.key.as_str(), read.bitcode.as_str(), read.warned), ("ab12", "cd34", warned));
            assert_eq!(read.interfaces, interfaces);
        }
        assert!(Record::parse("{\"key\": \"ab12\", \"bitcode\": \"cd34\"}\n").unwrap().warned);
        assert!(Record::parse("{\"key\": \"ab12\", \"bitcode\": \"cd34\"}\n").unwrap().interfaces.is_empty());
        assert!(Record::parse("{\"key\": \"ab12\"}\n").is_none());
        assert!(Record::parse("").is_none());
    }
}
