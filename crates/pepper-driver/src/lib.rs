//! Pepper driver: options, import resolution, runtime discovery, compile
//! pipeline, linking, and JIT execution.

pub mod cache;
pub mod compiler;
pub mod keys;
pub mod linker;
pub mod options;
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
/// AST, `--emit-llvm` writes IR, otherwise emit obj and link.
pub fn run(options: Options) -> Result<i32, String> {
    let module_name = options.module_name()?;

    if options.emit_ast {
        return run_emit_ast(&options);
    }

    if options.msvc {
        return Err("the MSVC linker path is not ported".to_string());
    }

    let build_dir = options.effective_build_dir();
    let compiler::ForObjects { module: sema_module, program, trial, interfaces } = if options.emit_llvm {
        compiler::compile_program(&options).map(|(module, program)| compiler::ForObjects { module, program, trial: None, interfaces: vec![] })?
    } else {
        compiler::compile_for_objects(&options, &units_dir(&build_dir, &module_name))?
    };
    let mut timer = StageTimer::new(options.tracing("time"));
    let link_libraries = link_libraries(&sema_module);
    let namespaces: Vec<String> = program.files.iter().map(|f| f.namespace.clone()).collect();
    std::fs::create_dir_all(&build_dir).map_err(|e| format!("cannot create build dir: {}", e))?;

    // --emit-llvm: write the whole program's IR as one module, optimized at
    // the `-O` level.
    if options.emit_llvm {
        let ctx = inkwell::context::Context::create();
        let mut generator = CodeGenerator::new(&ctx, &module_name);
        generator.file_namespaces = namespaces;
        generator.generate(&sema_module).map_err(|d| sema_module.sources.render(&d))?;
        timer.stage("codegen");
        pepper_codegen::target::optimize(&generator.module, options.effective_opt_level()?)?;
        timer.stage("optimize");
        let ir_path = build_dir.join(format!("{}.ll", module_name));
        std::fs::write(&ir_path, generator.module.to_string())
            .map_err(|e| format!("cannot write {}: {}", ir_path.display(), e))?;
        return Ok(0);
    }

    // Full pipeline: one object per unit (from the build cache when the
    // unit is unchanged), the program object, then link.
    let out_path = options.output_path()?;
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
    let objects: Vec<PathBuf> = built.into_iter().map(|o| o.path).collect();
    timer.stage("codegen and emission");

    // Discover runtime libs for linking.
    let (_sources, runtime_libs, _dirs) = runtime::discover();
    let mut libraries: Vec<String> = options.libraries.clone();
    let mut library_dirs: Vec<PathBuf> = vec![];
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

    linker::link(&objects, &out_path, &libraries, &library_dirs)?;
    timer.stage("link");

    Ok(0)
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
    let keys = keys::Keys::new(program);
    let units = &keys.units;
    let opt_level = options.effective_opt_level()?;
    let cache = options.effective_cache_dir().map(|root| cache::Cache::open(&root, opt_level)).transpose()?;
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
                object: build_units.join(format!("{}.o", u.name)),
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
        object: build_dir.join(format!("{}.o", name)),
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
        opt_level,
    };
    // Register the backend once, before the threads use it.
    default_target_machine()?;
    let outcomes = parallel(&jobs, |job| compile_unit(&setup, job))?;
    Ok(jobs.into_iter().zip(outcomes).map(|(job, outcome)| UnitObject { unit: job.name, path: job.object, outcome }).collect())
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
    opt_level: pepper_codegen::target::OptLevel,
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
        generator.unit = Some(pepper_codegen::partition::UnitFilter {
            unit_of_file: setup.unit_of_file.clone(),
            unit: job.unit,
            inputs: job.inputs.clone(),
        });
        generator.generate(module).map_err(|d| module.sources.render(&d))?;
        pepper_codegen::partition::finish(&generator.module, &generator.owners)?;
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
        _ => cache::emit(&generate()?, &job.object, setup.opt_level).map(|_| None),
    }
}

/// `f` over `items` on up to one thread per CPU, results in item order; the
/// first error in item order wins.
fn parallel<T: Sync, R: Send>(items: &[T], f: impl Fn(&T) -> Result<R, String> + Sync) -> Result<Vec<R>, String> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    let threads = std::thread::available_parallelism().map_or(1, |n| n.get()).clamp(1, items.len().max(1));
    let next = AtomicUsize::new(0);
    let mut results: Vec<(usize, Result<R, String>)> = std::thread::scope(|scope| {
        let workers: Vec<_> = (0..threads)
            .map(|_| {
                std::thread::Builder::new()
                    .stack_size(STACK_SIZE)
                    .spawn_scoped(scope, || {
                        let mut done = vec![];
                        loop {
                            let i = next.fetch_add(1, Ordering::Relaxed);
                            let Some(item) = items.get(i) else { break };
                            done.push((i, f(item)));
                        }
                        done
                    })
                    .expect("spawn a codegen thread")
            })
            .collect();
        workers.into_iter().flat_map(|w| w.join().expect("a codegen thread panicked")).collect()
    });
    results.sort_by_key(|(i, _)| *i);
    results.into_iter().map(|(_, r)| r).collect()
}

/// Libraries named by `[Link("name")]` on surviving externs, deduplicated in
/// declaration order. Shared by the CLI pipeline and the corpus harness so a
/// fixture's link flags can't drift from the driver's.
pub fn link_libraries(module: &pepper_sema::model::Module) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for ext in &module.externs {
        for attr in &ext.attributes {
            if let pepper_parser::ast::Expression::FunctionCall { function, arguments, .. } = &attr.body {
                if let pepper_parser::ast::Expression::SymbolRef { id, .. } = function.as_ref() {
                    if id == "Link" {
                        if let Some(pepper_parser::ast::Expression::Literal { value: pepper_parser::ast::Literal::String(s), .. }) = arguments.first() {
                            if !out.contains(s) {
                                out.push(s.clone());
                            }
                        }
                    }
                }
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
    println!("{}", ast);
    Ok(0)
}


/// Machine for object emission: the host, CPU `generic`.
///
/// Delegated to `pepper_codegen::target` so the backend registration lives in
/// one place; registering only x86 here is what left the CLI unable to compile
/// anything on Apple silicon while the suite stayed green.
pub(crate) fn default_target_machine() -> Result<inkwell::targets::TargetMachine, String> {
    pepper_codegen::target::host_machine()
}
