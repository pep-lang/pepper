//! Pepper driver: options, import resolution, runtime discovery, compile
//! pipeline, linking, and JIT execution.

pub mod cache;
pub mod compiler;
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

    let (sema_module, program) = compiler::compile_program(&options)?;
    let mut timer = StageTimer::new(options.tracing("time"));
    let link_libraries = link_libraries(&sema_module);
    let namespaces: Vec<String> = program.files.iter().map(|f| f.namespace.clone()).collect();
    let build_dir = options.effective_build_dir();
    std::fs::create_dir_all(&build_dir).map_err(|e| format!("cannot create build dir: {}", e))?;

    // --emit-llvm: write the whole program's IR as one module.
    if options.emit_llvm {
        let ctx = inkwell::context::Context::create();
        let mut generator = CodeGenerator::new(&ctx, &module_name);
        generator.file_namespaces = namespaces;
        generator.generate(&sema_module).map_err(|d| sema_module.sources.render(&d))?;
        timer.stage("codegen");
        let ir_path = build_dir.join(format!("{}.ll", module_name));
        std::fs::write(&ir_path, generator.module.to_string())
            .map_err(|e| format!("cannot write {}: {}", ir_path.display(), e))?;
        return Ok(0);
    }

    // Full pipeline: one object per unit (from the build cache when the
    // unit is unchanged), the program object, then link.
    let out_path = options.output_path()?;
    let built = objects(&options, &sema_module, &program, &build_dir, &module_name)?;
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
pub fn objects(
    options: &Options,
    module: &pepper_sema::model::Module,
    program: &pepper_sema::program::Program,
    build_dir: &std::path::Path,
    name: &str,
) -> Result<Vec<UnitObject>, String> {
    let units = program.units();
    let cache = options.effective_cache_dir().map(|root| cache::Cache::open(&root)).transpose()?;
    let build_units = build_dir.join(format!("{}.units", name));
    let source_hashes: Vec<blake3::Hash> = program.files.iter().map(|f| blake3::hash(f.source.as_bytes())).collect();
    let mut jobs: Vec<UnitJob> = units
        .iter()
        .enumerate()
        .map(|(i, u)| {
            let inputs = program.unit_inputs(u);
            let mut is_input = vec![false; program.files.len()];
            for &file in &inputs {
                is_input[file] = true;
            }
            UnitJob {
                unit: Some(i),
                name: u.name.clone(),
                object: build_units.join(format!("{}.o", u.name)),
                key: cache.as_ref().map(|c| cache::unit_key(c.compiler(), program, u, &inputs, &source_hashes)),
                inputs: is_input,
            }
        })
        .collect();
    jobs.push(UnitJob {
        unit: None,
        name: "__program".to_string(),
        object: build_dir.join(format!("{}.o", name)),
        key: None,
        inputs: vec![],
    });
    let namespaces: Vec<String> = program.files.iter().map(|f| f.namespace.clone()).collect();
    let setup = UnitSetup {
        module,
        namespaces: &namespaces,
        unit_of_file: unit_files(&units, program.files.len()),
        cache: cache.as_ref(),
        verify: options.verifying_cache(),
    };
    // Register the backend once, before the threads use it.
    default_target_machine()?;
    let outcomes = parallel(&jobs, |job| compile_unit(&setup, job))?;
    Ok(jobs.into_iter().zip(outcomes).map(|(job, outcome)| UnitObject { unit: job.name, path: job.object, outcome }).collect())
}

/// One object to build: a unit (`unit: Some(index into units)`) or the
/// program module (`None`), written to `object`.
struct UnitJob {
    unit: Option<usize>,
    name: String,
    object: PathBuf,
    /// The unit's source key, when there is a cache.
    key: Option<String>,
    /// Per file, whether the unit's code may depend on it (see
    /// `Program::unit_inputs`); empty for the program module.
    inputs: Vec<bool>,
}

/// What every [`compile_unit`] shares.
struct UnitSetup<'a> {
    module: &'a pepper_sema::model::Module,
    namespaces: &'a [String],
    unit_of_file: Vec<usize>,
    cache: Option<&'a cache::Cache>,
    /// `--verify-cache`: generate hit units anyway and check their code
    /// matches the cached object's.
    verify: bool,
}

/// Each file's index in `units`.
fn unit_files(units: &[pepper_sema::program::Unit], files: usize) -> Vec<usize> {
    let mut unit_of_file = vec![0; files];
    for (index, unit) in units.iter().enumerate() {
        for &file in &unit.files {
            unit_of_file[file] = index;
        }
    }
    unit_of_file
}

/// Put one unit's object at `job.object`: from the cache when the unit's
/// sources are unchanged, else by generating its module (see
/// [`cache::Cache::object`]); the program module is always generated and
/// never cached. Each unit gets its own LLVM context, so units compile on
/// separate threads (and LLVM names struct types per context: a second
/// `String` in one context would become `String.0`).
fn compile_unit(setup: &UnitSetup<'_>, job: &UnitJob) -> Result<Option<cache::Outcome>, String> {
    let ctx = inkwell::context::Context::create();
    let generate = || -> Result<inkwell::module::Module<'_>, String> {
        let mut generator = CodeGenerator::new(&ctx, &job.name);
        generator.file_namespaces = setup.namespaces.to_vec();
        generator.unit = Some(pepper_codegen::partition::UnitFilter {
            unit_of_file: setup.unit_of_file.clone(),
            unit: job.unit,
            inputs: job.inputs.clone(),
        });
        generator.generate(setup.module).map_err(|d| setup.module.sources.render(&d))?;
        pepper_codegen::partition::finish(&generator.module, &generator.owners)?;
        Ok(generator.module)
    };
    match (setup.cache, &job.key) {
        (Some(cache), Some(key)) => cache.object(&job.name, key, &job.object, setup.verify, generate).map(Some),
        _ => cache::emit(&generate()?, &job.object).map(|_| None),
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
                    // As much stack as the main thread: codegen recurses over
                    // the program.
                    .stack_size(8 << 20)
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
