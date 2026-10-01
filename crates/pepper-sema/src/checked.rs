//! Checking a program against declarations already checked (a reused,
//! checked runtime; see `design-notes/sema/canonical-specialization.md`):
//! their bodies are kept out of the passes, which walk bodies, until the
//! checks that read callee bodies (`check_confinement`) run, then put back.

use crate::builder::build_file;
use crate::model::{Checked, Module, TypeAliasDef};
use crate::program::Program;
use pepper_parser::diagnostic::{Diagnostic, FileId, Loc};
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, LazyLock, Mutex};

/// Where a stashed body goes back.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum BodyOf {
    Function(String),
    Member(String, &'static str, String),
}

/// Take the bodies of the checked declarations out of `module`.
pub fn stash_bodies(module: &mut Module) {
    for f in module.functions.iter_mut().filter(|f| module.checked.has_function(&f.name)) {
        if let Some(body) = f.body.take() {
            module.stashed_bodies.insert(BodyOf::Function(f.name.clone()), body);
        }
    }
    for st in module.structs.iter_mut().filter(|st| module.checked.has_struct(&st.name)) {
        let owner = st.name.clone();
        for (kind, f) in st
            .method_members
            .iter_mut()
            .map(|m| ("method", m))
            .chain(st.constructors.iter_mut().map(|c| ("constructor", c)))
            .chain([("destructor", &mut st.destructor), ("acquire", &mut st.acquire), ("release", &mut st.release)])
        {
            if let Some(body) = f.body.take() {
                module.stashed_bodies.insert(BodyOf::Member(owner.clone(), kind, f.name.clone()), body);
            }
        }
    }
}

/// Put back what [`stash_bodies`] took.
pub fn restore_bodies(module: &mut Module) {
    let mut stash = std::mem::take(&mut module.stashed_bodies);
    if stash.is_empty() {
        return;
    }
    for f in &mut module.functions {
        if let Some(body) = stash.remove(&BodyOf::Function(f.name.clone())) {
            f.body = Some(body);
        }
    }
    for st in &mut module.structs {
        let owner = st.name.clone();
        for (kind, f) in st
            .method_members
            .iter_mut()
            .map(|m| ("method", m))
            .chain(st.constructors.iter_mut().map(|c| ("constructor", c)))
            .chain([("destructor", &mut st.destructor), ("acquire", &mut st.acquire), ("release", &mut st.release)])
        {
            if let Some(body) = stash.remove(&BodyOf::Member(owner.clone(), kind, f.name.clone())) {
                f.body = Some(body);
            }
        }
    }
}


/// A runtime checked alone (see [`checked_runtime`]): the module the passes
/// left, its declarations marked checked.
#[derive(serde::Serialize, serde::Deserialize)]
pub struct CheckedRuntime {
    pub module: Module,
    /// The link summaries `check_confinement` recorded for it.
    pub summaries: HashMap<Loc, String>,
    /// Its type aliases as built: sema expands them away, and the other
    /// files use them.
    pub aliases: Vec<TypeAliasDef>,
}

/// What identifies a checked runtime: the target platform, whose
/// `[Target(...)]` filters it went through, and each runtime file's place in
/// the program, name, namespace (which its mangled names carry, and which
/// depends on where the compiler runs) and text. Programs that load the
/// same runtime files in the same places for one platform share one.
type RuntimeKey = ((String, String), Vec<(usize, String, String, String)>);

/// The runtimes checked so far in this process: the test harnesses and the
/// language server check many programs against one runtime.
static CHECKED_RUNTIMES: LazyLock<Mutex<HashMap<RuntimeKey, Arc<CheckedRuntime>>>> = LazyLock::new(Default::default);

/// Where checked runtimes are kept between processes (the build cache).
pub trait RuntimeStore {
    /// The runtime stored under `key`, its locations' files translated from
    /// the stored list to `files` (the program's runtime files, in order).
    fn load(&self, key: &str, files: &[u32]) -> Option<CheckedRuntime>;
    /// Store `runtime` under `key`, its locations' files (`files`, in
    /// order) translated to their places in that list.
    fn save(&self, key: &str, files: &[u32], runtime: &CheckedRuntime);
}

/// How many checked runtimes [`CHECKED_RUNTIMES`] keeps.
const KEPT_RUNTIMES: usize = 8;

/// Which of `program`'s files are runtime: the prelude, forced imports, and
/// files under a runtime folder. `None` when the runtime cannot be checked
/// alone because another file overrides a runtime declaration.
pub fn runtime_files(program: &Program) -> Option<Vec<bool>> {
    let (_, _, runtime_dirs) = pepper_files::runtime::discover();
    let dirs: Vec<String> = runtime_dirs.iter().map(|d| pepper_files::imports::path_key(d)).collect();
    let in_runtime: Vec<bool> = program
        .files
        .iter()
        .map(|f| f.prelude || f.prelude_part || dirs.iter().any(|d| pepper_files::imports::path_key(Path::new(&f.name)).starts_with(d.as_str())))
        .collect();
    let overrides = program.files.iter().enumerate().any(|(i, f)| !in_runtime[i] && crate::program::declares_override(&f.module));
    // A runtime file that imports a file outside it (a module nested in a
    // forced one) cannot be checked without that file.
    let reaches_out = program.files.iter().enumerate().any(|(i, f)| in_runtime[i] && f.imports.iter().flatten().any(|&j| !in_runtime[j]));
    (in_runtime.iter().any(|&r| r) && !overrides && !reaches_out).then_some(in_runtime)
}

/// The sema passes, as the driver runs them on a merged module.
pub fn run_passes(module: &mut Module) -> Result<(), Diagnostic> {
    crate::apply_platform_filters(module)?;
    crate::struct_body::apply(module)?;
    crate::transform_pass(module)
}

/// An empty module for `program`: its files' sources and namespaces, and
/// its extension scopes.
fn empty(program: &Program) -> Module {
    let mut module = Module { linked: true, extension_scopes: program.extension_scopes(), ..Module::default() };
    for file in &program.files {
        module.sources.add(&file.name, &file.source);
        module.namespaces.push(file.namespace.clone());
    }
    module
}

/// Check `program`'s runtime files (`in_runtime`, from [`runtime_files`])
/// alone, or reuse the result of checking the same files before: in this
/// process, else from `store`.
pub fn checked_runtime(program: &Program, in_runtime: &[bool], store: Option<&dyn RuntimeStore>) -> Result<Arc<CheckedRuntime>, Diagnostic> {
    let files = program.files.iter().enumerate().filter(|(i, _)| in_runtime[*i]).map(|(i, f)| (i, f.name.clone(), f.namespace.clone(), f.source.clone()));
    let key: RuntimeKey = ((crate::passes::platform::host_os(), crate::passes::platform::host_arch()), files.collect());
    // With a store (the CLI), the store is the cache: a process checks one
    // program.
    if store.is_none()
        && let Some(found) = CHECKED_RUNTIMES.lock().unwrap_or_else(|e| e.into_inner()).get(&key)
    {
        return Ok(found.clone());
    }
    let ids: Vec<u32> = key.1.iter().map(|(i, _, _, _)| *i as u32).collect();
    // Stored by the files' names, namespaces and texts, not their places in
    // a program.
    let stored = store.map(|_| {
        let mut hasher = blake3::Hasher::new();
        hasher.update(b"pepper checked runtime 1\0");
        for part in [&key.0 .0, &key.0 .1] {
            hasher.update(part.as_bytes());
            hasher.update(&[0]);
        }
        for (_, name, namespace, source) in &key.1 {
            for part in [name, namespace] {
                hasher.update(part.as_bytes());
                hasher.update(&[0]);
            }
            hasher.update(&(source.len() as u64).to_le_bytes());
            hasher.update(source.as_bytes());
        }
        hasher.finalize().to_hex().to_string()
    });
    if let (Some(store), Some(stored)) = (store, &stored)
        && let Some(runtime) = store.load(stored, &ids)
    {
        return Ok(Arc::new(runtime));
    }
    let mut runtime = empty(program);
    for (i, file) in program.files.iter().enumerate().filter(|(i, _)| in_runtime[*i]) {
        runtime.merge(build_file(&file.module, FileId(i as u32))?);
    }
    runtime.record_summaries = true;
    let aliases = runtime.type_aliases.clone();
    crate::reset_program_counters();
    run_passes(&mut runtime)?;
    // An extension of a struct that is not generic has been applied to it
    // for good; its bodies, lowered now, would only be walked again (an
    // `E.Case` resolved to its value reads as an `as E` the user wrote).
    for extension in runtime.extensions.iter_mut().filter(|e| !e.target.is_generic()) {
        for method in &mut extension.methods {
            method.body = None;
        }
    }
    runtime.checked = Checked::all(&runtime);
    runtime.record_summaries = false;
    let summaries = std::mem::take(&mut runtime.summaries_to_record).into_iter().collect();
    let checked = CheckedRuntime { module: runtime, summaries, aliases };
    if let (Some(store), Some(stored)) = (store, &stored) {
        store.save(stored, &ids, &checked);
        return Ok(Arc::new(checked));
    }
    Ok(keep(key, checked))
}

/// Keep `runtime` in this process under `key`.
fn keep(key: RuntimeKey, runtime: CheckedRuntime) -> Arc<CheckedRuntime> {
    let checked = Arc::new(runtime);
    let mut runtimes = CHECKED_RUNTIMES.lock().unwrap_or_else(|e| e.into_inner());
    // Editing a runtime file in the language server checks a new runtime
    // per change: keep only a few.
    if runtimes.len() >= KEPT_RUNTIMES {
        runtimes.clear();
    }
    runtimes.insert(key, checked.clone());
    checked
}

/// How [`on_checked_runtime`] builds the files outside the runtime.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Build {
    /// Any file that fails to build fails the program (the compiler).
    Strict,
    /// Only `files[0]`, the open document, must build: it is merged last,
    /// and the other files that fail are left out (the language server).
    Document,
}

/// `program`'s module, ready for [`run_passes`], on its runtime checked
/// alone ([`checked_runtime`], from `store` when it has it): the passes read the runtime's declarations
/// and check only the other files.
pub fn on_checked_runtime(program: &Program, in_runtime: &[bool], build: Build, store: Option<&dyn RuntimeStore>) -> Result<Module, Diagnostic> {
    let runtime = checked_runtime(program, in_runtime, store)?;
    let mut module = runtime.module.clone();
    let fresh = empty(program);
    module.sources = fresh.sources;
    module.namespaces = fresh.namespaces;
    module.extension_scopes = fresh.extension_scopes;
    module.type_aliases = runtime.aliases.clone();
    module.recorded_summaries = runtime.summaries.clone();
    let mut order: Vec<usize> = (0..program.files.len()).filter(|&i| !in_runtime[i]).collect();
    if build == Build::Document {
        let document = order.iter().position(|&i| i == 0).map_or(0, |p| p + 1);
        order.rotate_left(document);
    }
    for i in order {
        match build_file(&program.files[i].module, FileId(i as u32)) {
            Ok(built) => module.merge(built),
            Err(e) if build == Build::Strict || i == 0 => return Err(e),
            Err(_) => {}
        }
    }
    let mut rank = vec![0; program.files.len()];
    for (position, file) in program.initialization_order().into_iter().enumerate() {
        rank[file] = position;
    }
    module.globals.sort_by_key(|global| rank.get(global.loc.file.0 as usize).copied().unwrap_or(0));
    // Externs are first-wins by C name, in file order, as when the whole
    // program is merged at once.
    module.externs.sort_by_key(|e| e.loc.file.0);
    crate::reset_program_counters();
    Ok(module)
}
