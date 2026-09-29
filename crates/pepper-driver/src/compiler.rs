//! Compile pipeline: load the entry file, the runtime prelude, and every
//! file their imports reach; link imports and check visibility; merge into
//! one `Module`; run the transform passes.

use crate::options::Options;
use pepper_parser::diagnostic::FileId;
use pepper_sema::builder::build_file;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::program::{self, Program, Root, Setup};
use pepper_sema::struct_body;
use std::path::{Path, PathBuf};

/// Compiled sema module: parse + merge + transform complete.
pub type Compiled = SemaModule;

/// Load, link, and visibility-check the program rooted at `entry_source`,
/// then merge every file into one sema module.
pub fn compile_sources(options: &Options, entry_source: &Path) -> Result<SemaModule, String> {
    let setup = Setup {
        import_dirs: &options.import_paths,
        forced_imports: &options.forced_imports,
        runtime: !options.no_runtime,
        ..Setup::default()
    };
    let program = program::load_program(Root::from_file(entry_source)?, &setup)?;
    crate::report_warnings(&program.render_warnings());
    merge(&program)
}

/// Check `program` and merge its files, in load order, into one module. The
/// module's source map holds every file, so `FileId(i)` is `program.files[i]`.
pub fn merge(program: &Program) -> Result<SemaModule, String> {
    program.check()?;
    let mut module = SemaModule::default();
    for file in &program.files {
        module.sources.add(&file.name, &file.source);
    }
    for (i, file) in program.files.iter().enumerate() {
        let built = build_file(&file.module, FileId(i as u32)).map_err(|d| module.sources.render(&d))?;
        module.merge(built);
    }
    Ok(module)
}

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
/// passes. For test harnesses that JIT the result.
pub fn compile_with_runtime(name: &str, source: &str) -> Result<Compiled, String> {
    let mut module = merge(&load_with_runtime(name, source)?)?;
    run_passes(&mut module)?;
    Ok(module)
}

/// Full compile: parse + sema + codegen. Returns the generator for JIT or
/// emission.
pub fn compile(
    options: &Options,
    _module_name: &str,
) -> Result<Compiled, String> {
    let entry_source = options
        .source_files
        .first()
        .ok_or_else(|| "no source files".to_string())?;

    let mut module = compile_sources(options, entry_source)?;
    run_passes(&mut module)?;
    Ok(module)
}

/// Platform selection, struct bodies, the transform passes, then the
/// function-type check, on a merged module; errors are rendered against its
/// sources.
fn run_passes(module: &mut SemaModule) -> Result<(), String> {
    pepper_sema::apply_platform_filters(module).map_err(|d| module.sources.render(&d))?;
    struct_body::apply(module).map_err(|d| module.sources.render(&d))?;
    transform_pass(module).map_err(|d| module.sources.render(&d))?;
    pepper_sema::passes::check_function_types::check_function_types(module)?;
    Ok(())
}
