//! Compile pipeline: load the entry file, the runtime prelude, and every
//! file their imports reach; link imports and check visibility; merge into
//! one `Module`; run the transform passes.

use crate::options::Options;
use pepper_parser::diagnostic::FileId;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::program::{self, Program, Root, Setup};
use pepper_parser::diagnostic::Loc;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Compiled sema module: parse + merge + transform complete.
pub type Compiled = SemaModule;

/// Load, link, and visibility-check the program rooted at `entry_source`,
/// then merge every file into one sema module.
pub fn compile_sources(options: &Options, entry_source: &Path) -> Result<SemaModule, String> {
    let program = load(options, entry_source)?;
    merge(&program).inspect_err(|_| crate::report_warnings(&program.render_warnings()))
}

/// [`load`] without the build cache's syntax trees: every file is parsed.
pub(crate) fn load_uncached(options: &Options, entry_source: &Path) -> Result<Program, String> {
    let forced_imports = options.effective_forced_imports();
    let setup = Setup { import_dirs: &options.import_paths, forced_imports: &forced_imports, runtime: !options.no_runtime, ..Setup::default() };
    let mut root = Root::from_file(entry_source)?;
    if options.test {
        crate::test_main::add_test_main(&mut root);
    }
    program::load_program(root, &setup)
}

/// Load and link the program rooted at `entry_source` with the options'
/// search paths, forced imports and runtime.
fn load(options: &Options, entry_source: &Path) -> Result<Program, String> {
    // Files whose text is unchanged come from the build cache's syntax trees.
    let cache = options.effective_cache_dir().map(|root| crate::cache::Cache::open(&root, options.effective_build()?)).transpose()?;
    let forced_imports = options.effective_forced_imports();
    let setup = Setup {
        import_dirs: &options.import_paths,
        forced_imports: &forced_imports,
        runtime: !options.no_runtime,
        parsed: cache.as_ref().map(|c| c as &dyn program::ParseCache),
        ..Setup::default()
    };
    let mut root = Root::from_file(entry_source)?;
    if options.test {
        crate::test_main::add_test_main(&mut root);
    }
    program::load_program(root, &setup)
}

pub use pepper_sema::program::merge;

/// Load and link `source` (named `name`) with the discovered runtime as its
/// prelude, as `compile` does. For test harnesses that run the rest of the
/// pipeline themselves.
pub fn load_with_runtime(name: &str, source: &str) -> Result<Program, String> {
    let root = Root { name: name.to_string(), source: source.to_string(), path: PathBuf::from(name) };
    program::load_program(root, &Setup::default())
}

/// Link and visibility-check `source` (named `name`) against the discovered
/// runtime, as `compile` does.
pub fn check_with_runtime(name: &str, source: &str) -> Result<(), String> {
    load_with_runtime(name, source)?.check()
}

/// Compile `source` (named `name`) with the discovered runtime as its
/// prelude, as `compile` does: load, link, check, merge, and run the sema
/// passes. For test harnesses that JIT the result. The runtime is checked
/// once per process and reused (see [`on_checked_runtime`]).
pub fn compile_with_runtime(name: &str, source: &str) -> Result<Compiled, String> {
    let program = load_with_runtime(name, source)?;
    let mut module = on_checked_runtime(&program, None)?;
    run_passes(&mut module)?;
    Ok(module)
}

/// Full compile: parse + sema + codegen. Returns the generator for JIT or
/// emission.
pub fn compile(
    options: &Options,
    _module_name: &str,
) -> Result<Compiled, String> {
    compile_program(options).map(|(module, _)| module)
}

/// [`compile`], also returning the loaded program, whose files and units
/// ([`Program::units`]) the object pipeline splits the module by. Compiles
/// for this thread's target, with the options' build options (`-D`) when
/// they give any.
pub fn compile_program(options: &Options) -> Result<(Compiled, Program), String> {
    let mut target = pepper_sema::current_target();
    if !options.effective_build_options().is_empty() {
        target.build_options = options.effective_build_options();
    }
    pepper_sema::with_target(target, || compile_program_with(options, None, false)).map(|(module, program, _)| (module, program))
}

/// What [`compile_for_objects`] hands [`crate::objects`].
pub struct ForObjects {
    /// The checked module.
    pub module: Compiled,
    pub program: Program,
    /// Verifying the cache: the module with the cached units' bodies skipped
    /// (when any were), for `objects` to check that skipping them changes no
    /// other unit's code.
    pub trial: Option<Compiled>,
    /// Per program file, the interface hash its unit's cache record gave,
    /// for the units whose bodies sema skipped (`objects` computes the
    /// rest).
    pub interfaces: Vec<Option<String>>,
    /// Every unit was a cache hit, reused, and so was the program: its
    /// object is in place and `module` is empty, since sema did not run.
    pub cached: Option<crate::cache::ProgramRecord>,
}

/// [`compile_program`] for [`crate::objects`]: sema skips the bodies of the
/// units the build cache reuses (`Cache::reuse`, which puts their objects
/// in `units_dir` now, see [`crate::units_dir`]), so the module can only be
/// split into unit objects by `objects`, never compiled whole.
///
/// Verifying the cache (`--verify-cache`), the module is compiled whole,
/// since every hit is generated again, with a trial that skips the bodies.
pub fn compile_for_objects(options: &Options, units_dir: &Path) -> Result<ForObjects, String> {
    let record = options.effective_cache_dir().is_some();
    if !options.verifying_cache() {
        let (module, program, reused) = compile_program_with(options, Some(units_dir), record)?;
        return Ok(ForObjects { module, program, trial: None, interfaces: reused.interfaces, cached: reused.program });
    }
    let (module, program, _) = compile_program_with(options, None, record)?;
    let reused = reused(options, &program, units_dir)?;
    let mut done = ForObjects { module, program, trial: None, interfaces: vec![], cached: None };
    if !reused.files.iter().any(|&c| c) {
        return Ok(done);
    }
    // Numbered as if the program were compiled for the first time.
    pepper_sema::reset_program_counters();
    let cache = runtime_store(options)?;
    let mut trial = on_checked_runtime(&done.program, cache.as_ref().map(|c| c as _))?;
    trial.cached_files = reused.files;
    trial.recorded_summaries.extend(reused.summaries);
    run_passes(&mut trial).map_err(|e| format!("build cache: skipping the cached units' bodies broke sema:\n{}", e))?;
    done.trial = Some(trial);
    Ok(done)
}

/// [`compile_program`], skipping the bodies of the units the cache reuses
/// into `reuse` when it is given, and recording link summaries for the
/// cache (`Module::summaries_to_record`) when `record`. Also returns what
/// was reused.
fn compile_program_with(options: &Options, reuse: Option<&Path>, record: bool) -> Result<(Compiled, Program, Reused), String> {
    let entry_source = options
        .source_files
        .first()
        .ok_or_else(|| "no source files".to_string())?;

    let mut timer = crate::StageTimer::new(options.tracing("time"));
    if options.tracing("passes") {
        pepper_sema::pass_timer::enable();
    }
    let program = load(options, entry_source)?;
    timer.stage("load and parse");
    let mut reused_units = Reused::default();
    if let Some(units_dir) = reuse {
        reused_units = reused(options, &program, units_dir)?;
        if reused_units.program.is_some() {
            // Nothing changed: no unit needs checking or generating.
            timer.stage("check and build");
            return Ok((SemaModule::default(), program, reused_units));
        }
    }
    let cache = runtime_store(options)?;
    let mut module = on_checked_runtime(&program, cache.as_ref().map(|c| c as _)).inspect_err(|_| crate::report_warnings(&program.render_warnings()))?;
    module.record_summaries = record;
    module.cached_files = std::mem::take(&mut reused_units.files);
    module.recorded_summaries.extend(std::mem::take(&mut reused_units.summaries));
    timer.stage("check and build");
    // Warnings print whether or not the passes succeed, as clang prints
    // them beside errors.
    let result = if options.debug_static_expanded() {
        let (result, expansions) = pepper_sema::passes::static_source::record(|| run_passes(&mut module));
        result.and_then(|()| crate::emit_static::write_debug_sources(options, &mut module, &program, &expansions))
    } else {
        run_passes(&mut module)
    };
    crate::report_warnings(&module.render_warnings());
    result?;
    timer.stage("sema passes");
    if options.tracing("passes") {
        // The runtime's own passes too, when this compile checked it.
        for (pass, time, runs) in pepper_sema::pass_timer::take() {
            eprintln!("pass: {:>9.3} ms {:>4}x {}", time.as_secs_f64() * 1000.0, runs, pass);
        }
    }
    Ok((module, program, reused_units))
}

/// The build cache, where checked runtimes are kept; none with
/// `--no-cache`.
fn runtime_store(options: &Options) -> Result<Option<crate::cache::Cache>, String> {
    options.effective_cache_dir().map(|root| crate::cache::Cache::open(&root, options.effective_build()?)).transpose()
}

/// `program` merged into one module, ready for [`run_passes`]: on its
/// runtime checked alone when the runtime can be (see
/// `pepper_sema::checked`), so the passes check only the other files; else
/// every file, as [`merge`] does.
fn on_checked_runtime(program: &Program, store: Option<&dyn pepper_sema::checked::RuntimeStore>) -> Result<SemaModule, String> {
    let Some(in_runtime) = pepper_sema::checked::runtime_files(program) else {
        return merge(program);
    };
    program.check()?;
    let mut module = pepper_sema::checked::on_checked_runtime(program, &in_runtime, pepper_sema::checked::Build::Strict, store).map_err(|d| {
        let mut sources = pepper_parser::diagnostic::SourceMap::default();
        for file in &program.files {
            sources.add(&file.name, &file.source);
        }
        sources.render(&d)
    })?;
    module.warnings = program.warnings();
    Ok(module)
}

/// The units whose objects came from the cache before sema.
#[derive(Default)]
struct Reused {
    /// Per program file, whether its unit's object came from the cache
    /// (`Module::cached_files`).
    files: Vec<bool>,
    /// Their recorded link summaries (`Module::recorded_summaries`).
    summaries: HashMap<Loc, String>,
    /// Per program file, its interface hash, for the files of units that
    /// were cache hits (reused or not).
    interfaces: Vec<Option<String>>,
    /// When every unit was reused and the program's record matched: the
    /// record (its object is in place).
    program: Option<crate::cache::ProgramRecord>,
}

/// Reuse every unit the cache can supply ([`crate::cache::Cache::reuse`],
/// into `units_dir`); nothing when there is no cache. Units resolve bottom
/// up (see [`crate::keys`]): a unit's key is known once the units it reads
/// through interfaces are hits, whose records give those interfaces.
fn reused(options: &Options, program: &Program, units_dir: &Path) -> Result<Reused, String> {
    let Some(root) = options.effective_cache_dir() else {
        return Ok(Reused::default());
    };
    let build = options.effective_build()?;
    let cache = crate::cache::Cache::open(&root, build.clone())?;
    let n = program.files.len();
    let mut reused = Reused { files: vec![false; n], summaries: HashMap::new(), interfaces: vec![None; n], program: None };
    let mut unit_keys: Vec<Option<String>> = vec![None; program.units().len()];
    let file_of: HashMap<&str, usize> = program.files.iter().enumerate().map(|(i, f)| (f.namespace.as_str(), i)).collect();
    let mut keys = crate::keys::Keys::new(program);
    keys.exact_positions = options.emit_debug;
    let mut resolved = vec![false; keys.units.len()];
    let mut progress = true;
    while std::mem::take(&mut progress) {
        for (u, unit) in keys.units.iter().enumerate() {
            if resolved[u] {
                continue;
            }
            let Some(key) = keys.key(cache.compiler(), u, |file| reused.interfaces[file].as_deref()) else { continue };
            resolved[u] = true;
            progress = true;
            unit_keys[u] = Some(key.clone());
            // A miss: the units reading this one's interfaces wait for sema.
            let Some(interfaces) = cache.interfaces(&unit.name, &key) else { continue };
            for (namespace, hash) in interfaces {
                if let Some(&file) = file_of.get(namespace.as_str()) {
                    reused.interfaces[file] = Some(hash);
                }
            }
            let Some(summaries) = cache.reuse(&unit.name, &key, &units_dir.join(format!("{}.{}", unit.name, build.extension())))? else { continue };
            for &file in &unit.files {
                reused.files[file] = true;
            }
            for (namespace, loc, summary) in crate::cache::parse_summaries(&summaries) {
                if let Some(&file) = file_of.get(namespace) {
                    reused.summaries.insert(Loc::new(FileId(file as u32), loc), summary.to_string());
                }
            }
        }
    }
    // Every unit reused: the program object can come from the cache too.
    let every = keys.units.iter().all(|u| u.files.iter().all(|&f| reused.files[f]));
    if every && let Some(unit_keys) = unit_keys.into_iter().collect::<Option<Vec<String>>>() {
        let key = keys.program_key(cache.compiler(), &unit_keys);
        let name = &program.files[0].namespace;
        reused.program = cache.program(name, &key, &units_dir.with_extension(build.extension()))?;
    }
    // Only the reused units' interfaces are kept: sema checks the others'
    // bodies, and `objects` hashes their interfaces from those.
    for (file, interface) in reused.interfaces.iter_mut().enumerate() {
        if !reused.files[file] {
            *interface = None;
        }
    }
    Ok(reused)
}

/// Platform selection, struct bodies and the transform passes (the last of
/// which checks value types) on a merged module; errors are rendered against
/// its sources.
fn run_passes(module: &mut SemaModule) -> Result<(), String> {
    pepper_sema::checked::run_passes(module).map_err(|d| module.sources.render(&d))
}
