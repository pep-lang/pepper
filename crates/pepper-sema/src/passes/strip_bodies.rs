//! Build cache phase 2b: a unit whose object comes from the cache needs no
//! code generated, so sema need not check its bodies either. After closures
//! are lifted (so every name synthesized from a file is already numbered),
//! the bodies of the cached files' non-generic functions and methods are
//! dropped, with the closure structs lifted out of them (whose parameter
//! types may only be known from where the dropped body passes them); the
//! declarations stay, so the rest of the program still resolves and calls
//! them.
//!
//! Kept whole: generic code (other units instantiate it), trait default
//! methods (copied into conforming structs), constructors and destructors
//! (whose bodies `struct_body` completes), and any function whose return
//! type is inferred from its body. And a function whose link summary the
//! cache did not record (`Module::recorded_summaries`): confinement checks
//! read it from the body otherwise.

use crate::model::*;
use std::collections::HashSet;

/// Drop the bodies [`Module::cached_files`] allows (see the module docs).
pub fn strip_bodies(module: &mut Module) {
    let cached = std::mem::take(&mut module.cached_files);
    if !cached.iter().any(|&c| c) {
        return;
    }
    // Only a function whose link summary was recorded: `check_confinement`
    // needs it in place of the body.
    let module_summaries = std::mem::take(&mut module.recorded_summaries);
    let in_cached = |loc: Loc| !loc.is_none() && cached.get(loc.file.0 as usize).copied().unwrap_or(false);
    let mut dropped = vec![];
    let mut strip = |function: &mut FunctionDef| {
        if in_cached(function.loc)
            && function.owner.is_none()
            && function.generic_params.is_empty()
            && !function.ty.is_auto()
            && module_summaries.contains_key(&function.loc)
        {
            dropped.extend(function.body.take());
        }
    };
    for function in &mut module.functions {
        strip(function);
    }
    for st in module.structs.iter_mut().filter(|st| st.generic_params.is_empty()) {
        st.method_members.iter_mut().for_each(&mut strip);
    }
    for ext in module.extensions.iter_mut().filter(|e| e.target.sub_types.is_empty()) {
        ext.methods.iter_mut().for_each(&mut strip);
    }
    // The closures those bodies made, and the closures those made.
    let mut closures = HashSet::new();
    while let Some(mut body) = dropped.pop() {
        crate::passes::walk_block(&mut body, &mut |expr| {
            if let Expression::MakeClosure { closure, .. } = expr {
                closures.insert(closure.clone());
            }
        });
        for st in module.structs.iter_mut().filter(|st| closures.contains(&st.name)) {
            for method in &mut st.method_members {
                dropped.extend(method.body.take());
            }
        }
    }
    module.structs.retain(|st| !closures.contains(&st.name));
    module.recorded_summaries = module_summaries;
    module.cached_files = cached;
}
