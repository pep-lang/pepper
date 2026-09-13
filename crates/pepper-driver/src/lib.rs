//! Pepper driver: options, import resolution, runtime discovery, compile
//! pipeline, linking, and JIT execution.

pub mod compiler;
pub mod imports;
pub mod linker;
pub mod options;
pub mod runtime;

pub use options::Options;
pub use pepper_parser::parser;

use pepper_codegen::CodeGenerator;
use std::path::PathBuf;

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

    let mut sema_module = compiler::compile(&options, &module_name)?;
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, &module_name);
    generator.generate(&mut sema_module)?;

    let build_dir = options.effective_build_dir();
    std::fs::create_dir_all(&build_dir).map_err(|e| format!("cannot create build dir: {}", e))?;

    // --emit-llvm: write IR.
    if options.emit_llvm {
        let ir_path = build_dir.join(format!("{}.ll", module_name));
        std::fs::write(&ir_path, generator.module.to_string())
            .map_err(|e| format!("cannot write {}: {}", ir_path.display(), e))?;
        return Ok(0);
    }

    // Full pipeline: emit obj and link.
    let out_path = options.output_path()?;
    let obj_path = build_dir.join(format!("{}.o", module_name));
    let machine = default_target_machine()?;
    machine
        .write_to_file(
            &generator.module,
            inkwell::targets::FileType::Object,
            &obj_path,
        )
        .map_err(|e| format!("obj emission failed: {}", e))?;

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

    // Link the pepper-support staticlib (built alongside this binary) so
    // the JIT'd/generated code resolves _pep_* symbols.
    let mut objects: Vec<PathBuf> = vec![obj_path];
    if let Some(staticlib) = support_staticlib() {
        objects.push(staticlib);
    }

    linker::link(&objects, &out_path, &libraries, &library_dirs)?;

    Ok(0)
}

/// Parse the primary source and dump its AST.
fn run_emit_ast(options: &Options) -> Result<i32, String> {
    let entry_source = options
        .source_files
        .first()
        .ok_or_else(|| "no source files".to_string())?;
    let content = std::fs::read_to_string(entry_source)
        .map_err(|e| format!("cannot read {}: {}", entry_source.display(), e))?;
    let ast = pepper_parser::parser::parse_source(&entry_source.to_string_lossy(), &content)?;
    println!("{}", ast);
    Ok(0)
}

/// Locate the pepper-support staticlib next to this binary's target dir.
fn support_staticlib() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    // target/debug/pepper → target/debug/libpepper_support.a
    exe.parent()?.join("libpepper_support.a").canonicalize().ok()
}

/// Default-target machine for obj emission (cpu "generic" per
/// `LLVMCodeGenerator.cpp:245-258`).
fn default_target_machine() -> Result<inkwell::targets::TargetMachine, String> {
    inkwell::targets::Target::initialize_x86(&inkwell::targets::InitializationConfig::default());
    let triple = inkwell::targets::TargetMachine::get_default_triple();
    let target =
        inkwell::targets::Target::from_triple(&triple).map_err(|e| e.to_string())?;
    target
        .create_target_machine(
            &triple,
            "generic",
            "",
            inkwell::OptimizationLevel::None,
            inkwell::targets::RelocMode::Default,
            inkwell::targets::CodeModel::Default,
        )
        .ok_or_else(|| "target machine".to_string())
}
