//! Compile pipeline: port of `source/Compiler/Compiler.cpp:65-119`. BFS
//! import collection with a seen-set, parse each file, merge into one
//! `Module`, run the transform passes, codegen.

use pepper_files::imports::resolve;
use crate::options::Options;
use pepper_codegen::CodeGenerator;
use pepper_parser::parser::parse_source;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// Compiled sema module: parse + merge + transform complete.
pub type Compiled = SemaModule;

/// Parse + merge all sources (BFS import collection) and run sema.
pub fn compile_sources(
    options: &Options,
    entry_source: &Path,
    module_name: &str,
    search_paths: &[PathBuf],
) -> Result<SemaModule, String> {
    let mut module = SemaModule::default();
    let mut seen: HashSet<String> = HashSet::new();
    let mut queue: Vec<PathBuf> = vec![entry_source.to_path_buf()];
    seen.insert(entry_source.to_string_lossy().into_owned());

    // Runtime discovery: prepend runtime sources to the compile set.
    if !options.no_runtime {
        let (runtime_sources, _libs, runtime_dirs) = crate::runtime::discover();
        let mut combined: Vec<PathBuf> = runtime_sources;
        combined.extend(queue.drain(..));
        queue = combined;
        for p in &queue {
            seen.insert(p.to_string_lossy().into_owned());
        }
        let mut paths: Vec<PathBuf> = runtime_dirs;
        paths.extend(search_paths.iter().cloned());
        // NOTE: runtime import dirs must be visible to the resolver for
        // nested imports; rebuild the search path list via recursion below.
        return compile_queue(&mut module, &mut queue, &mut seen, &paths);
    }

    compile_queue(&mut module, &mut queue, &mut seen, search_paths)
}

fn compile_queue(
    module: &mut SemaModule,
    queue: &mut Vec<PathBuf>,
    seen: &mut HashSet<String>,
    search_paths: &[PathBuf],
) -> Result<SemaModule, String> {
    while let Some(source_file) = queue.pop() {
        let content = std::fs::read_to_string(&source_file)
            .map_err(|e| format!("cannot read {}: {}", source_file.display(), e))?;
        let ast = parse_source(&source_file.to_string_lossy(), &content)?;
        let mut built = build(&ast)?;
        module.merge(std::mem::take(&mut built));

        // Resolve all imports and add them to the queue if necessary.
        for import in &module.imports {
            let path = resolve(&source_file, &import.name, import.is_local, search_paths)
                .ok_or_else(|| format!("Cannot resolve import {}", import.name))?;
            let key = path.to_string_lossy().into_owned();
            if !seen.contains(&key) {
                seen.insert(key.clone());
                queue.push(path);
            }
        }
    }
    Ok(module.clone())
}

/// Full compile: parse + sema + codegen. Returns the generator for JIT or
/// emission.
pub fn compile(
    options: &Options,
    module_name: &str,
) -> Result<Compiled, String> {
    let entry_source = options
        .source_files
        .first()
        .ok_or_else(|| "no source files".to_string())?;

    let mut search_paths: Vec<PathBuf> = options.import_paths.clone();

    let mut module = compile_sources(options, entry_source, module_name, &search_paths)?;

    // Apply forced imports when resolvable.
    for forced in &options.forced_imports {
        let path = resolve(entry_source, forced, false, &search_paths)
            .or_else(|| resolve(Path::new("."), forced, false, &search_paths));
        if let Some(path) = path {
            if std::fs::read_to_string(&path).is_ok() {
                let ast = parse_source(&path.to_string_lossy(), &std::fs::read_to_string(&path).unwrap())?;
                let mut built = build(&ast)?;
                module.merge(std::mem::take(&mut built));
            }
        }
    }

    pepper_sema::apply_platform_filters(&mut module)?;
    struct_body::apply(&mut module)?;
    transform_pass(&mut module);

    Ok(module)
}
