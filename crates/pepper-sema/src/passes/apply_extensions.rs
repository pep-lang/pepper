//! Port of `source/Sema/ApplyExtensions.h`: clone extension methods onto the
//! target struct, record traits; two-pass applied-set.

use crate::model::{Diagnostic, ExtensionDef, FunctionDef, Module, StructDef, TraitDef};
use crate::passes::specialize_structs::{substitute, substitute_block};
use crate::type_name::TypeName;
use std::cell::RefCell;
use std::collections::HashSet;

/// Applied-extension dedup set. Thread-local: each transform_pass run owns its
/// own set, so concurrent compilations (test threads) never share indices.
thread_local! {
    static APPLIED: RefCell<HashSet<usize>> = RefCell::new(HashSet::new());
}

fn clone_method(method: &FunctionDef, parent: &str) -> FunctionDef {
    let mut m = method.clone();
    m.parent = Some(parent.to_string());
    m
}

fn apply_to_struct(st: &mut StructDef, ext: &ExtensionDef, traits: &[TraitDef]) {
    for method in &ext.methods {
        st.method_members.push(clone_method(method, &st.name));
    }
    for trait_name in &ext.traits {
        st.traits.push(trait_name.clone());
        if let Some(def) = traits.iter().find(|t| t.name == trait_name.name) {
            conform(st, ext, trait_name, def);
        }
    }
}

/// `extend S with Trait`: S must have every method the trait declares; a
/// trait method with a body is S's default when S has none of its own.
fn conform(st: &mut StructDef, ext: &ExtensionDef, trait_name: &TypeName, def: &TraitDef) {
    // The trait's parameters take the `with` clause's arguments; `this` in a
    // trait signature is the extended struct.
    let mut type_map: Vec<(String, TypeName)> = def
        .generic_params
        .iter()
        .zip(&trait_name.sub_types)
        .map(|(param, arg)| (param.name.clone(), arg.clone()))
        .collect();
    type_map.push(("this".to_string(), st.ty.clone()));
    for required in &def.methods {
        if st.method_members.iter().any(|m| m.name == required.name) {
            continue;
        }
        match &required.body {
            Some(_) => {
                let mut method = clone_method(required, &st.name);
                substitute(&mut method.ty, &type_map);
                for param in &mut method.parameters {
                    substitute(&mut param.ty, &type_map);
                }
                if let Some(body) = &mut method.body {
                    substitute_block(body, &type_map);
                }
                st.method_members.push(method);
            }
            None => crate::errors::report(
                Diagnostic::error(format!(
                    "'{}' does not implement '{}', required by trait '{}'",
                    st.ty.display(),
                    required.name,
                    trait_name.display()
                ))
                .at(ext.loc)
                .with_note(format!("'{}' declared here", required.name), Some(required.loc)),
            ),
        }
    }
}

pub fn apply_extensions(module: &mut Module, _specialized_pass: bool) {
    APPLIED.with(|applied_cell| {
        let mut applied = applied_cell.borrow_mut();
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
                    apply_to_struct(st, ext, &module.traits);
                }
            }
        }
    });
}

/// Reset the applied-set (each `TransformPass::run` starts fresh).
pub fn reset_applied() {
    APPLIED.with(|a| a.borrow_mut().clear());
}
