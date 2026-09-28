//! Compile pipeline: port of `source/Compiler/Compiler.cpp:65-119`. BFS
//! import collection with a seen-set, parse each file, merge into one
//! `Module`, run the transform passes, codegen.

use pepper_files::imports::{path_key, resolve};
use crate::options::Options;
use pepper_codegen::CodeGenerator;
use pepper_parser::parser::parse_source;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;
use pepper_sema::SourceFile;
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// Compiled sema module: parse + merge + transform complete.
pub type Compiled = SemaModule;

/// Every parsed source in a compile, as (name, text, AST).
pub type ParsedSources = Vec<(String, String, pepper_parser::ast::Module)>;

/// Parse + merge all sources (BFS import collection, then any forced
/// imports) and check visibility.
pub fn compile_sources(options: &Options, entry_source: &Path, search_paths: &[PathBuf]) -> Result<SemaModule, String> {
    let (mut module, mut parsed) = collect_sources(options, entry_source, search_paths)?;

    // Apply forced imports when resolvable, skipping files already compiled.
    let mut compiled: HashSet<String> = parsed.iter().map(|(name, _, _)| path_key(Path::new(name))).collect();
    for forced in &options.forced_imports {
        let path = resolve(entry_source, forced, false, search_paths)
            .or_else(|| resolve(Path::new("."), forced, false, search_paths));
        if let Some(path) = path {
            if !compiled.insert(path_key(&path)) {
                continue;
            }
            if let Ok(content) = std::fs::read_to_string(&path) {
                let name = path.to_string_lossy().into_owned();
                let ast = parse_source(&name, &content)?;
                let mut built = build(&ast)?;
                module.merge(std::mem::take(&mut built));
                parsed.push((name, content, ast));
            }
        }
    }

    check_visibility(&parsed)?;
    Ok(module)
}

/// Parse + merge all sources (BFS import collection), returning the merged
/// module and every parsed file.
fn collect_sources(
    options: &Options,
    entry_source: &Path,
    search_paths: &[PathBuf],
) -> Result<(SemaModule, ParsedSources), String> {
    let mut module = SemaModule::default();
    let mut seen: HashSet<String> = HashSet::new();
    let mut queue: Vec<PathBuf> = vec![entry_source.to_path_buf()];
    seen.insert(path_key(entry_source));

    // Runtime discovery: prepend runtime sources to the compile set (the
    // entry stays last, so it is compiled first). A runtime file that is
    // itself the entry is compiled once.
    if !options.no_runtime {
        let (runtime_sources, _libs, runtime_dirs) = crate::runtime::discover();
        let mut combined: Vec<PathBuf> = runtime_sources.into_iter().filter(|p| seen.insert(path_key(p))).collect();
        combined.extend(queue.drain(..));
        queue = combined;
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
) -> Result<(SemaModule, ParsedSources), String> {
    // Every parsed file, kept for the cross-file visibility check.
    let mut parsed: ParsedSources = vec![];
    while let Some(source_file) = queue.pop() {
        let content = std::fs::read_to_string(&source_file)
            .map_err(|e| format!("cannot read {}: {}", source_file.display(), e))?;
        let name = source_file.to_string_lossy().into_owned();
        let ast = parse_source(&name, &content)?;
        let mut built = build(&ast)?;
        module.merge(std::mem::take(&mut built));
        parsed.push((name, content, ast));

        // Resolve this file's imports (relative to it) and queue new ones.
        for import in &parsed.last().expect("just pushed").2.imports {
            let path = resolve(&source_file, &import.name, import.is_local, search_paths)
                .ok_or_else(|| format!("Cannot resolve import {}", import.name))?;
            if seen.insert(path_key(&path)) {
                queue.push(path);
            }
        }
    }
    Ok((module.clone(), parsed))
}

/// Reject references to symbols another file did not `export`. `parsed` is
/// every source in the compile as (name, text, AST).
pub fn check_visibility(parsed: &[(String, String, pepper_parser::ast::Module)]) -> Result<(), String> {
    let files: Vec<SourceFile> = parsed
        .iter()
        .map(|(name, source, module)| SourceFile { name, source, module })
        .collect();
    let errors = pepper_sema::check_visibility(&files);
    if errors.is_empty() {
        return Ok(());
    }
    Err(errors.iter().map(|e| e.render(&files)).collect::<Vec<_>>().join("\n"))
}

/// Visibility-check `source` (named `name`) against the discovered runtime,
/// as `compile` does. For test harnesses that merge the runtime themselves.
pub fn check_with_runtime(name: &str, source: &str) -> Result<(), String> {
    let mut parsed: ParsedSources = vec![];
    for path in crate::runtime::discover().0 {
        let content = std::fs::read_to_string(&path).map_err(|e| format!("cannot read {}: {}", path.display(), e))?;
        let file = path.to_string_lossy().into_owned();
        let ast = parse_source(&file, &content)?;
        parsed.push((file, content, ast));
    }
    parsed.push((name.to_string(), source.to_string(), parse_source(name, source)?));
    check_visibility(&parsed)
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

    let mut search_paths: Vec<PathBuf> = options.import_paths.clone();

    let mut module = compile_sources(options, entry_source, &search_paths)?;

    pepper_sema::apply_platform_filters(&mut module)?;
    struct_body::apply(&mut module)?;
    transform_pass(&mut module);

    Ok(module)
}
