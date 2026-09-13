//! Port of `source/Sema/ApplyExtensions.h`: clone extension methods onto the
//! target struct, record traits; two-pass applied-set.

use crate::model::{ExtensionDef, FunctionDef, Module, StructDef};
use std::sync::{LazyLock, Mutex};
use std::collections::HashSet;

static APPLIED: LazyLock<Mutex<HashSet<usize>>> = LazyLock::new(|| Mutex::new(HashSet::new()));

fn applied() -> &'static Mutex<HashSet<usize>> {
    &APPLIED
}

fn clone_method(method: &FunctionDef, parent: &str) -> FunctionDef {
    let mut m = method.clone();
    m.parent = Some(parent.to_string());
    m
}

fn apply_to_struct(st: &mut StructDef, ext: &ExtensionDef) {
    for method in &ext.methods {
        st.method_members.push(clone_method(method, &st.name));
    }
    for trait_name in &ext.traits {
        st.traits.push(trait_name.clone());
    }
}

pub fn apply_extensions(module: &mut Module, _specialized_pass: bool) {
    let mut applied = applied().lock().expect("applied set");
    for (ext_idx, ext) in module.extensions.iter().enumerate() {
        if applied.contains(&ext_idx) {
            continue;
        }
        if ext.resolved.is_none() {
            // Unresolved targets are handled by resolve_resolvables; skip.
            continue;
        }
        applied.insert(ext_idx);
        let target_name = ext.resolved.clone().expect("resolved");
        // Apply to every struct matching the resolved name (concrete or
        // specialized instance).
        for st in &mut module.structs {
            if st.name == target_name || st.ty.to_string() == target_name {
                apply_to_struct(st, ext);
            }
        }
    }
}

/// Reset the applied-set (each `TransformPass::run` starts fresh).
pub fn reset_applied() {
    APPLIED.lock().expect("applied set").clear();
}
