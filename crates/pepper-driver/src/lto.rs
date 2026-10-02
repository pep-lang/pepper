//! Link-time optimization (`--lto=full`, the default at `-O2` and `-O3`;
//! see INTERNALS.md §4.1).
//!
//! Each unit is optimized alone, so a call into another unit (user code
//! calling the runtime's `_pep_malloc`, or `String.__acquire`) stays a
//! call. With LTO, each unit is kept as bitcode that LLVM's pre-link
//! pipeline has run over (`cache::emit`, cached like an object), and this
//! links every unit into one module, makes every symbol but `main` internal
//! to it, runs the link-time pipeline over the whole program, and emits one
//! object. The program then links with the system linker as usual: no
//! linker plugin is involved, so it works on every platform the compiler
//! does.

use inkwell::context::Context;
use inkwell::module::{Linkage, Module};
use inkwell::values::{AsValueRef, GlobalValue};
use crate::cache::Build;
use pepper_codegen::target::Pipeline;
use std::path::{Path, PathBuf};

/// Link the units' bitcode files `bitcode` into one module, optimize it as
/// a whole as `build` says, and write it to `object`. Each unit's functions
/// already carry `build`'s CPU (`cache::emit`).
pub fn optimize(bitcode: &[PathBuf], object: &Path, build: &Build) -> Result<(), String> {
    let context = Context::create();
    let read = |path: &PathBuf| {
        Module::parse_bitcode_from_path(path, &context).map_err(|e| format!("cannot read {}: {}", path.display(), e.to_string()))
    };
    let mut paths = bitcode.iter();
    let first = paths.next().ok_or_else(|| "nothing to link".to_string())?;
    let program = read(first)?;
    for path in paths {
        program
            .link_in_module(read(path)?)
            .map_err(|e| format!("cannot link {}: {}", path.display(), e.to_string()))?;
    }
    internalize(&program);
    pepper_codegen::target::optimize_with(&program, build.opt_level, Pipeline::Link, &build.cpu)?;
    program.verify().map_err(|e| format!("the linked program does not verify: {}", e.to_string()))?;
    let machine = pepper_codegen::target::machine(build.opt_level, &build.cpu)?;
    pepper_codegen::target::write_object(&machine, &program, object)
}

/// Make every definition but `main` and the C entry points of `[Export]`ed
/// functions internal (the only definitions with default visibility):
/// nothing else outside the program calls Pepper code by name, so the
/// optimizer may inline, specialize or drop any of it. A definition leaves its comdat, which only told the
/// linker to keep one copy of it.
fn internalize(program: &Module<'_>) {
    let mut values: Vec<GlobalValue<'_>> = program.get_functions().map(|f| f.as_global_value()).collect();
    values.extend(program.get_globals());
    for value in values {
        let name = value.get_name().to_string_lossy();
        let visible = value.get_visibility() == inkwell::GlobalVisibility::Default && value.get_linkage() == Linkage::External;
        if value.is_declaration() || name == "main" || name.starts_with("llvm.") || visible {
            continue;
        }
        if matches!(value.get_linkage(), Linkage::Appending) {
            continue;
        }
        unsafe { inkwell::llvm_sys::comdat::LLVMSetComdat(value.as_value_ref(), std::ptr::null_mut()) };
        value.set_linkage(Linkage::Internal);
    }
}
