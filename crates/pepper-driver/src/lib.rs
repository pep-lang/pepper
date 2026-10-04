//! Pepper driver: options, import resolution, runtime discovery, compile
//! pipeline, linking, and JIT execution.

pub mod cache;
pub mod compiler;
pub mod emit_static;
pub mod fetch;
pub mod keys;
pub mod library;
pub mod lto;
pub mod linker;
pub mod options;
pub mod test_main;
/// Import resolution, now in `pepper-files` (shared with the LSP server).
pub use pepper_files::imports;
/// Runtime discovery, now in `pepper-files` (shared with the LSP server).
pub use pepper_files::runtime;

pub use options::Options;
pub use pepper_parser::parser;
pub use pepper_parser::diagnostic as parser_diagnostic;

use pepper_codegen::CodeGenerator;
use std::io::IsTerminal;
use std::path::PathBuf;

/// Stack for every thread that compiles: parsing, sema, and codegen recurse
/// over the syntax tree, which the parser keeps within
/// `parser::MAX_NESTING` levels. That fits in 8 MB; Windows gives the main
/// thread only 1 MB, so `run` belongs on a thread of this size.
pub const STACK_SIZE: usize = 8 << 20;

/// Whether diagnostics on stderr are colored, like clang: on a terminal,
/// unless `NO_COLOR` is set.
pub fn stderr_color() -> bool {
    std::io::stderr().is_terminal() && std::env::var_os("NO_COLOR").is_none_or(|v| v.is_empty())
}

/// Print rendered warnings to stderr (nothing when `rendered` is empty).
/// Warnings never stop the compile.
pub fn report_warnings(rendered: &str) {
    if rendered.is_empty() {
        return;
    }
    if stderr_color() {
        eprintln!("{}", parser_diagnostic::colorize(rendered));
    } else {
        eprintln!("{}", rendered);
    }
}

/// Prints how long each compile stage took, for `-T time`: one line per
/// stage on stderr, `time: <stage> <ms>`.
pub(crate) struct StageTimer {
    enabled: bool,
    last: std::time::Instant,
}

impl StageTimer {
    pub(crate) fn new(enabled: bool) -> Self {
        StageTimer { enabled, last: std::time::Instant::now() }
    }

    /// Report the time since the previous stage ended as `name`.
    pub(crate) fn stage(&mut self, name: &str) {
        if self.enabled {
            let now = std::time::Instant::now();
            eprintln!("time: {:<16} {:>9.3} ms", name, (now - self.last).as_secs_f64() * 1000.0);
            self.last = now;
        }
    }
}

/// Run the compile pipeline and act per the options: `--emit-ast` dumps the
/// AST, `--emit-static` writes the source with `static` blocks expanded,
/// `--emit-llvm` writes IR, otherwise emit obj and link. Everything
/// compiles for `--target`'s platform (see `pepper_sema::with_target`).
pub fn run(options: Options) -> Result<i32, String> {
    let target = options.effective_target()?;
    pepper_sema::with_target(target, || run_for_target(options))
}

/// [`run`] on the thread that compiles, with the target set.
fn run_for_target(options: Options) -> Result<i32, String> {
    let module_name = options.module_name()?;

    if options.emit_ast.is_some() {
        return run_emit_ast(&options);
    }

    if options.emit_linked {
        return run_emit_linked(&options);
    }

    if options.emit_checked {
        return run_emit_checked(&options);
    }

    if let Some(warning) = options.runtime_checks_warning() {
        report_warnings(&warning);
    }

    if options.msvc {
        return Err("the MSVC linker path is not ported".to_string());
    }

    // A project builds with what pep.lock lists: fetch what is missing.
    if let Some(entry) = options.source_files.first() {
        fetch::fetch_dependencies(entry)?;
    }

    if let Some(mode) = &options.emit_static {
        return emit_static::run(&options, mode == "keep");
    }

    let build_dir = options.effective_build_dir();
    let compiler::ForObjects { module: sema_module, program, trial, interfaces, cached } = if options.emit_llvm {
        compiler::compile_program(&options)
            .map(|(module, program)| compiler::ForObjects { module, program, trial: None, interfaces: vec![], cached: None })?
    } else {
        compiler::compile_for_objects(&options, &units_dir(&build_dir, &module_name))?
    };
    let mut timer = StageTimer::new(options.tracing("time"));
    let namespaces: Vec<String> = program.files.iter().map(|f| f.namespace.clone()).collect();
    std::fs::create_dir_all(&build_dir).map_err(|e| format!("cannot create build dir: {}", e))?;

    // --emit-llvm: write the whole program's IR as one module, optimized at
    // the `-O` level.
    if options.emit_llvm {
        let ctx = inkwell::context::Context::create();
        let mut generator = CodeGenerator::new(&ctx, &module_name);
        generator.file_namespaces = namespaces;
        generator.debug_info = options.emit_debug;
        generator.opt_level = options.effective_opt_level()?;
        generator.runtime_checks = options.effective_runtime_checks()?;
        generator.generate(&sema_module).map_err(|d| sema_module.sources.render(&d))?;
        timer.stage("codegen");
        let cpu = options.effective_cpu()?;
        cpu.stamp(&generator.module);
        if options.frame_pointers {
            pepper_codegen::target::keep_frame_pointers(&generator.module);
        }
        pepper_codegen::target::optimize_with(&generator.module, options.effective_opt_level()?, pepper_codegen::target::Pipeline::Default, &cpu)?;
        timer.stage("optimize");
        let ir_path = build_dir.join(format!("{}.ll", module_name));
        std::fs::write(&ir_path, generator.module.to_string())
            .map_err(|e| format!("cannot write {}: {}", ir_path.display(), e))?;
        return Ok(0);
    }

    // Full pipeline: one object per unit (from the build cache when the
    // unit is unchanged), the program object, then link.
    let out_path = options.output_path()?;
    let build = options.effective_build()?;
    let cache = options.effective_cache_dir().map(|root| cache::Cache::open(&root, build.clone())).transpose()?;
    let program_name = program.files[0].namespace.clone();
    let (mut objects, (link_libraries, link_library_dirs), program_key) = match cached {
        // Every unit and the program came from the cache: sema did not run.
        Some(record) => {
            let mut objects: Vec<PathBuf> =
                program.units().iter().map(|u| units_dir(&build_dir, &module_name).join(format!("{}.{}", u.name, build.extension()))).collect();
            objects.push(build_dir.join(format!("{}.{}", module_name, build.extension())));
            if options.tracing("cache") {
                for unit in program.units() {
                    eprintln!("cache: {} hit", unit.name);
                }
                eprintln!("cache: program hit");
            }
            let link = (record.libraries.clone(), record.library_dirs.iter().map(PathBuf::from).collect());
            (objects, link, Some(record))
        }
        None => {
            let built = objects(&options, &sema_module, trial.as_ref(), &interfaces, &program, &build_dir, &module_name)?;
            if options.tracing("cache") {
                for object in &built {
                    let outcome = match object.outcome {
                        Some(cache::Outcome::Hit) => "hit",
                        Some(cache::Outcome::SameCode) => "hit (same code)",
                        Some(cache::Outcome::Miss) => "miss",
                        None => continue,
                    };
                    eprintln!("cache: {} {}", object.unit, outcome);
                }
            }
            let libraries = link_libraries(&sema_module);
            let library_dirs = link_library_dirs(&sema_module);
            // The next build can skip sema when nothing changes.
            let keys: Option<Vec<String>> = built.iter().filter(|o| o.unit != "__program").map(|o| o.key.clone()).collect();
            let record = match (&cache, keys) {
                (Some(cache), Some(keys)) => {
                    let key = keys::Keys::new(&program).program_key(cache.compiler(), &keys);
                    let record = cache::ProgramRecord {
                        key,
                        libraries: libraries.clone(),
                        library_dirs: library_dirs.iter().map(|dir| dir.to_string_lossy().into_owned()).collect(),
                        header: pepper_sema::passes::exports::header_declarations(&sema_module.exports),
                        ..Default::default()
                    };
                    cache.store_program(&program_name, &record, &build_dir.join(format!("{}.{}", module_name, build.extension())))?;
                    Some(record)
                }
                _ => None,
            };
            (built.into_iter().map(|o| o.path).collect(), (libraries, library_dirs), record)
        }
    };
    timer.stage("codegen and emission");
    if build.lto {
        let object = build_dir.join(format!("{}.lto.o", module_name));
        lto::optimize(&objects, &object, &build)?;
        objects = vec![object];
        timer.stage("link-time optimization");
    }

    // Discover runtime libs for linking.
    let (_sources, runtime_libs, runtime_dirs) = runtime::discover();
    let mut libraries: Vec<String> = options.libraries.clone();
    // Search order: `-L`, then `[Link(path = ...)]`, then
    // `$PEPPER_LIBRARY_PATH`, then the runtime's folders.
    let mut library_dirs: Vec<PathBuf> = options.library_dirs.clone();
    library_dirs.extend(link_library_dirs);
    library_dirs.extend(options::environment_library_dirs());
    for lib in &runtime_libs {
        if let Some(parent) = lib.parent() {
            library_dirs.push(parent.to_path_buf());
        }
        if let Some(stem) = lib.file_stem() {
            let stem = stem.to_string_lossy();
            if let Some(name) = stem.strip_prefix("lib") {
                libraries.push(name.to_string());
            }
        }
    }
    libraries.extend(link_libraries);

    // A library gets its C header; a static one is an archive, not linked.
    if let Some(kind) = options.library_kind() {
        let declarations = match &program_key {
            Some(record) => record.header.clone(),
            None => pepper_sema::passes::exports::header_declarations(&sema_module.exports),
        };
        if declarations.is_empty() {
            report_warnings("warning: the library exports no functions; mark the functions C calls with '[Export]'");
        }
        // What a program linking the static library links too.
        let mut needs = vec![];
        if kind == library::LibraryKind::Static {
            for library in libraries.iter().map(String::as_str).chain(linker::default_system_libraries(&pepper_sema::current_target().os).iter().copied()) {
                if !needs.iter().any(|l| l == library) {
                    needs.push(library.to_string());
                }
            }
        }
        let header = library::header_path(&out_path);
        let file_name = header.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        std::fs::write(&header, pepper_sema::passes::exports::header(&file_name, &declarations, &needs))
            .map_err(|e| format!("cannot write {}: {}", header.display(), e))?;
        if kind == library::LibraryKind::Static {
            library::write_archive(&objects, &out_path)?;
            timer.stage("archive");
            return Ok(0);
        }
    }

    // With `-g` on Windows, the runtime's visualizers go into the `.pdb`.
    let windows = pepper_sema::current_target().os == "windows";
    let natvis = runtime_dirs.first().map(|dir| dir.join("debuggers").join("pepper.natvis")).filter(|path| options.emit_debug && windows && path.is_file());
    // An unchanged program linked into an unchanged file needs no link.
    let shared = options.library_kind() == Some(library::LibraryKind::Shared);
    let link = link_key(&objects, &out_path, &libraries, &library_dirs, shared);
    let unchanged = program_key.as_ref().is_some_and(|record| {
        !record.output.is_empty() && record.link == link && output_hash(&out_path).is_some_and(|h| h == record.output)
    });
    if !unchanged {
        let sysroot = options.effective_sysroot();
        linker::link(&objects, &out_path, &libraries, &library_dirs, options.emit_debug, natvis.as_deref(), sysroot.as_deref(), shared)?;
        if let (Some(cache), Some(record), Some(output)) = (&cache, &program_key, output_hash(&out_path)) {
            cache.record_link(&program_name, &record.key, &link, &output)?;
        }
    } else if options.tracing("cache") {
        eprintln!("cache: link skipped");
    }
    timer.stage("link");

    Ok(0)
}

/// The hash of a link's inputs: the objects (by path and contents), the
/// libraries, where it writes, and whether it makes a shared library.
fn link_key(objects: &[PathBuf], output: &std::path::Path, libraries: &[String], library_dirs: &[PathBuf], shared: bool) -> String {
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"pepper link 1\0");
    hasher.update(if shared { b"shared\0" } else { b"executable\0" });
    for object in objects {
        hasher.update(object.to_string_lossy().as_bytes());
        hasher.update(&[0]);
        hasher.update(blake3::hash(&std::fs::read(object).unwrap_or_default()).as_bytes());
    }
    for library in libraries {
        hasher.update(library.as_bytes());
        hasher.update(&[0]);
    }
    for dir in library_dirs {
        hasher.update(dir.to_string_lossy().as_bytes());
        hasher.update(&[0]);
    }
    hasher.update(output.to_string_lossy().as_bytes());
    hasher.finalize().to_hex().to_string()
}

/// The hash of the file at `path`, if it can be read.
fn output_hash(path: &std::path::Path) -> Option<String> {
    std::fs::read(path).ok().map(|bytes| blake3::hash(&bytes).to_hex().to_string())
}

/// An object [`objects`] built.
#[derive(Debug, Clone)]
pub struct UnitObject {
    /// The unit's name (see `Program::units`), or `__program` for the
    /// program module.
    pub unit: String,
    /// Where the object is, in the build directory.
    pub path: PathBuf,
    /// How the build cache supplied it; `None` when it was not looked up
    /// (the program module, or `--no-cache`).
    pub outcome: Option<cache::Outcome>,
    /// The unit's cache key; `None` for the program module, or without a
    /// cache.
    pub key: Option<String>,
}

/// Emit `program` (whose merged, checked module is `module`) as one object
/// per compilation unit, each on its own thread and through the build cache
/// unless `--no-cache`, plus the program object (`<build>/<name>.o`) that
/// runs every file's global initializer. Unit objects go in
/// `<build>/<name>.units/`. The objects to link, units first.
///
/// `trial` (from [`compiler::compile_for_objects`] when verifying) is the
/// module with the cached units' bodies skipped: each unit generated from
/// `module` must have the same code generated from it. `interfaces` holds
/// the interface hashes of the files whose bodies sema skipped, by file;
/// the rest are hashed here (see [`keys`]).
pub fn objects(
    options: &Options,
    module: &pepper_sema::model::Module,
    trial: Option<&pepper_sema::model::Module>,
    interfaces: &[Option<String>],
    program: &pepper_sema::program::Program,
    build_dir: &std::path::Path,
    name: &str,
) -> Result<Vec<UnitObject>, String> {
    let mut keys = keys::Keys::new(program);
    keys.exact_positions = options.emit_debug;
    let units = &keys.units;
    let build = options.effective_build()?;
    let cache = options.effective_cache_dir().map(|root| cache::Cache::open(&root, build.clone())).transpose()?;
    let interfaces = match cache {
        Some(_) => file_interfaces(module, program, interfaces)?,
        None => vec![],
    };
    let build_units = units_dir(build_dir, name);
    // Files with warnings; their units are checked again next time.
    let mut warned_files = vec![false; program.files.len()];
    for loc in module.warnings.iter().filter_map(|w| w.loc).filter(|l| !l.is_none()) {
        if let Some(warned) = warned_files.get_mut(loc.file.0 as usize) {
            *warned = true;
        }
    }
    let mut jobs: Vec<UnitJob> = units
        .iter()
        .enumerate()
        .map(|(i, u)| {
            let mut is_input = vec![false; program.files.len()];
            for &file in &keys.inputs[i] {
                is_input[file] = true;
            }
            let key = cache.as_ref().and_then(|c| keys.key(c.compiler(), i, |file| interfaces[file].as_deref()));
            UnitJob {
                unit: Some(i),
                name: u.name.clone(),
                object: build_units.join(format!("{}.{}", u.name, build.extension())),
                key,
                inputs: is_input,
                interfaces: match cache {
                    Some(_) => u.files.iter().map(|&f| (program.files[f].namespace.clone(), interfaces[f].clone().unwrap_or_default())).collect(),
                    None => vec![],
                },
                warned: u.files.iter().any(|&f| warned_files[f]),
                summaries: unit_summaries(module, program, &u.files),
                stripped: u.files.iter().any(|&f| module.cached_files.get(f).copied().unwrap_or(false)),
            }
        })
        .collect();
    jobs.push(UnitJob {
        unit: None,
        name: "__program".to_string(),
        object: build_dir.join(format!("{}.{}", name, build.extension())),
        key: None,
        inputs: vec![],
        interfaces: vec![],
        warned: false,
        summaries: String::new(),
        stripped: false,
    });
    let namespaces: Vec<String> = program.files.iter().map(|f| f.namespace.clone()).collect();
    let setup = UnitSetup {
        module,
        trial,
        namespaces: &namespaces,
        unit_of_file: keys.unit_of_file.clone(),
        cache: cache.as_ref(),
        verify: options.verifying_cache(),
        build,
        debug: options.emit_debug,
    };
    // Register the backend once, before the threads use it.
    default_target_machine()?;
    let outcomes = parallel(&jobs, |job| compile_unit(&setup, job))?;
    Ok(jobs.into_iter().zip(outcomes).map(|(job, outcome)| UnitObject { unit: job.name, path: job.object, outcome, key: job.key }).collect())
}

/// Where [`objects`] puts the unit objects of the program `name`.
pub fn units_dir(build_dir: &std::path::Path, name: &str) -> PathBuf {
    build_dir.join(format!("{}.units", name))
}

/// The link summaries sema recorded for the functions in `files`
/// (`Module::summaries_to_record`), as the cache stores them.
fn unit_summaries(module: &pepper_sema::model::Module, program: &pepper_sema::program::Program, files: &[usize]) -> String {
    module
        .summaries_to_record
        .iter()
        .filter(|(loc, _)| files.contains(&(loc.file.0 as usize)))
        .map(|(loc, summary)| cache::summary_line(&program.files[loc.file.0 as usize].namespace, loc.span, summary))
        .collect()
}

/// Each program file's interface hash (see [`keys`]): `known`'s, for the
/// files whose bodies sema skipped, else hashed from `program` and the link
/// summaries sema recorded in `module`.
fn file_interfaces(
    module: &pepper_sema::model::Module,
    program: &pepper_sema::program::Program,
    known: &[Option<String>],
) -> Result<Vec<Option<String>>, String> {
    let summaries: std::collections::HashMap<pepper_parser::diagnostic::Loc, &str> =
        module.summaries_to_record.iter().map(|(loc, summary)| (*loc, summary.as_str())).collect();
    let mut interfaces = vec![];
    for (i, file) in program.files.iter().enumerate() {
        let interface = match known.get(i).cloned().flatten() {
            Some(known) => known,
            None => pepper_sema::interface::interface_hash(&file.module, pepper_parser::diagnostic::FileId(i as u32), &summaries)
                .map_err(|d| module.sources.render(&d))?,
        };
        interfaces.push(Some(interface));
    }
    Ok(interfaces)
}

/// One object to build: a unit (`unit: Some(index into units)`) or the
/// program module (`None`), written to `object`.
struct UnitJob {
    unit: Option<usize>,
    name: String,
    object: PathBuf,
    /// The unit's key, when there is a cache.
    key: Option<String>,
    /// Per file, whether the unit's code may depend on it (see
    /// `Program::unit_inputs`); empty for the program module.
    inputs: Vec<bool>,
    /// Its files' interface hashes, by namespace, when there is a cache.
    interfaces: Vec<(String, String)>,
    /// Sema reported a warning in one of its files.
    warned: bool,
    /// Its functions' link summaries, for the cache (see
    /// [`cache::parse_summaries`]).
    summaries: String,
    /// Sema skipped its bodies (`Module::cached_files`): its object was
    /// put in place before sema ([`cache::Cache::reuse`]).
    stripped: bool,
}

/// What every [`compile_unit`] shares.
struct UnitSetup<'a> {
    module: &'a pepper_sema::model::Module,
    /// The module with the cached units' bodies skipped, to check against
    /// (see [`objects`]).
    trial: Option<&'a pepper_sema::model::Module>,
    namespaces: &'a [String],
    unit_of_file: Vec<usize>,
    cache: Option<&'a cache::Cache>,
    /// `--verify-cache`: generate hit units anyway and check their code
    /// matches the cached object's.
    verify: bool,
    /// The level objects are optimized at (`-O`).
    build: cache::Build,
    /// Emit debug info (`-g`).
    debug: bool,
}

/// Put one unit's object at `job.object`: from the cache when the unit's
/// sources are unchanged, else by generating its module (see
/// [`cache::Cache::object`]); the program module is always generated and
/// never cached. Each unit gets its own LLVM context, so units compile on
/// separate threads (and LLVM names struct types per context: a second
/// `String` in one context would become `String.0`).
fn compile_unit(setup: &UnitSetup<'_>, job: &UnitJob) -> Result<Option<cache::Outcome>, String> {
    let generate_in = |ctx, module: &pepper_sema::model::Module| -> Result<_, String> {
        let mut generator = CodeGenerator::new(ctx, &job.name);
        generator.file_namespaces = setup.namespaces.to_vec();
        generator.debug_info = setup.debug;
        generator.opt_level = setup.build.opt_level;
        generator.runtime_checks = setup.build.runtime_checks;
        generator.unit = Some(pepper_codegen::partition::UnitFilter {
            unit_of_file: setup.unit_of_file.clone(),
            unit: job.unit,
            inputs: job.inputs.clone(),
        });
        generator.generate(module).map_err(|d| module.sources.render(&d))?;
        pepper_codegen::partition::finish(&generator.module, &generator.owners, &generator.exported)?;
        Ok(generator.module)
    };
    if job.stripped {
        return Ok(Some(cache::Outcome::Hit));
    }
    let ctx = inkwell::context::Context::create();
    let generate = || generate_in(&ctx, setup.module);
    match (setup.cache, &job.key) {
        (Some(cache), Some(key)) => {
            let unit = cache::UnitRequest {
                name: &job.name,
                key,
                out: &job.object,
                verify: setup.verify,
                warned: job.warned,
                summaries: &job.summaries,
                interfaces: &job.interfaces,
            };
            let (outcome, code) = cache.object(&unit, generate)?;
            // A unit whose bodies the trial kept must come out the same:
            // skipping the others' bodies may not change its code.
            let kept = |trial: &pepper_sema::model::Module| {
                let file = job.unit.map(|u| setup.unit_of_file.iter().position(|&f| f == u));
                !file.flatten().is_some_and(|f| trial.cached_files.get(f).copied().unwrap_or(false))
            };
            if let Some(trial) = setup.trial.filter(|&t| kept(t)) {
                // Its own context, so its types keep their names.
                let trial_ctx = inkwell::context::Context::create();
                cache.check_code(&job.name, &code, &generate_in(&trial_ctx, trial)?)?;
            }
            Ok(Some(outcome))
        }
        _ => cache::emit(&generate()?, &job.object, &setup.build).map(|_| None),
    }
}

/// `f` over `items` on up to one thread per CPU, results in item order; the
/// first error in item order wins. Each thread compiles for the caller's
/// target.
fn parallel<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> Result<R, String> + Sync) -> Result<Vec<R>, String> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    let target = pepper_sema::current_target();
    let threads = std::thread::available_parallelism().map_or(1, |n| n.get()).clamp(1, items.len().max(1));
    let next = AtomicUsize::new(0);
    let mut results: Vec<(usize, Result<R, String>)> = std::thread::scope(|scope| {
        let workers: Vec<_> = (0..threads)
            .map(|_| {
                std::thread::Builder::new()
                    .stack_size(STACK_SIZE)
                    .spawn_scoped(scope, || {
                        pepper_sema::with_target(target.clone(), || {
                            let mut done = vec![];
                            loop {
                                let i = next.fetch_add(1, Ordering::Relaxed);
                                let Some(item) = items.get(i) else { break };
                                done.push((i, f(item)));
                            }
                            done
                        })
                    })
                    .expect("spawn a codegen thread")
            })
            .collect();
        workers.into_iter().flat_map(|w| w.join().expect("a codegen thread panicked")).collect()
    });
    results.sort_by_key(|(i, _)| *i);
    results.into_iter().map(|(_, r)| r).collect()
}

/// Libraries named by `[Link("name")]` (or `[Link(lib = "name")]`) on
/// surviving externs, deduplicated in declaration order. Shared by the CLI
/// pipeline and the corpus harness so a fixture's link flags can't drift
/// from the driver's.
pub fn link_libraries(module: &pepper_sema::model::Module) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for ext in &module.externs {
        for library in ext.link().map(|link| link.libraries).unwrap_or_default() {
            if !out.contains(&library) {
                out.push(library);
            }
        }
    }
    out
}

/// Library search directories named by `[Link(path = "dir")]` on surviving
/// externs, deduplicated in declaration order. A relative path is relative
/// to the folder of the file that declares the extern.
pub fn link_library_dirs(module: &pepper_sema::model::Module) -> Vec<PathBuf> {
    use pepper_parser::diagnostic::Sources;
    let mut out: Vec<PathBuf> = Vec::new();
    for ext in &module.externs {
        for path in ext.link().map(|link| link.paths).unwrap_or_default() {
            let file = module.sources.get(ext.loc.file).map(|(name, _)| std::path::Path::new(name).to_path_buf()).unwrap_or_default();
            let folder = file.parent().unwrap_or(std::path::Path::new(""));
            let dir = folder.join(&path);
            let dir = std::path::absolute(&dir).unwrap_or(dir);
            if !out.contains(&dir) {
                out.push(dir);
            }
        }
    }
    out
}

/// Parse the primary source and dump its AST.
fn run_emit_ast(options: &Options) -> Result<i32, String> {
    let entry_source = options
        .source_files
        .first()
        .ok_or_else(|| "no source files".to_string())?;
    let content = std::fs::read_to_string(entry_source)
        .map_err(|e| format!("cannot read {}: {}", entry_source.display(), e))?;
    let name = entry_source.to_string_lossy();
    let ast = pepper_parser::parser::parse_source(&name, &content)?;
    report_warnings(&ast.warnings.iter().map(|w| w.render_in(&name, &content)).collect::<Vec<_>>().join("\n"));
    if options.emit_ast.as_deref() == Some("json") {
        let json = serde_json::to_string(&ast).map_err(|e| format!("cannot write the AST as JSON: {}", e))?;
        println!("{}", json);
    } else {
        println!("{}", ast);
    }
    Ok(0)
}


/// Load and link the program, then print it as JSON: each file in load
/// order with its syntax tree after linking, then the linking errors, then
/// the overload sets that span files. Keys keep the order written here,
/// and the syntax trees serde's field order, so the Pepper compiler's
/// output can be compared byte for byte.
fn run_emit_linked(options: &Options) -> Result<i32, String> {
    let entry_source = options.source_files.first().ok_or_else(|| "no source files".to_string())?;
    let program = compiler::load_uncached(options, entry_source)?;
    macro_rules! json {
        ($value:expr) => {
            serde_json::to_string($value).map_err(|e| format!("cannot write the program as JSON: {}", e))?
        };
    }
    let span = |s: &pepper_parser::ast::Span| format!("{{\"start\":{},\"end\":{}}}", s.start, s.end);
    let mut files = vec![];
    for f in &program.files {
        files.push(format!(
            "{{\"name\":{},\"namespace\":{},\"module_root\":{},\"prelude\":{},\"prelude_part\":{},\"imports\":{},\"folder_imports\":{},\"module\":{}}}",
            json!(&f.name),
            json!(&f.namespace),
            json!(&f.module_root.as_ref().map(|p| p.to_string_lossy().into_owned())),
            f.prelude,
            f.prelude_part,
            json!(&f.imports),
            json!(&f.folder_imports),
            json!(&f.module),
        ));
    }
    let mut errors = vec![];
    for e in &program.errors {
        let note = match &e.note {
            Some((s, m)) => format!("[{},{}]", span(s), json!(m)),
            None => "null".to_string(),
        };
        errors.push(format!(
            "{{\"file\":{},\"span\":{},\"message\":{},\"unresolved\":{},\"note\":{}}}",
            e.file,
            span(&e.span),
            json!(&e.message),
            e.unresolved,
            note
        ));
    }
    println!(
        "{{\"files\":[{}],\"errors\":[{}],\"overload_unions\":{}}}",
        files.join(","),
        errors.join(","),
        json!(&program.overload_unions)
    );
    Ok(0)
}

/// Load, link and check the program, then print the rendered errors of
/// `Program::check`, if any, then its rendered warnings, so the Pepper
/// compiler's checks can be compared byte for byte.
fn run_emit_checked(options: &Options) -> Result<i32, String> {
    let entry_source = options.source_files.first().ok_or_else(|| "no source files".to_string())?;
    let program = compiler::load_uncached(options, entry_source)?;
    let mut out = vec![];
    if let Err(errors) = program.check() {
        out.push(errors);
    }
    let warnings = program.render_warnings();
    if !warnings.is_empty() {
        out.push(warnings);
    }
    println!("{}", out.join("\n"));
    Ok(0)
}

/// Machine for object emission: the target, with clang's default CPU.
///
/// Delegated to `pepper_codegen::target` so the backend registration lives in
/// one place; registering only x86 here is what left the CLI unable to compile
/// anything on Apple silicon while the suite stayed green.
pub(crate) fn default_target_machine() -> Result<inkwell::targets::TargetMachine, String> {
    pepper_codegen::target::target_machine()
}
