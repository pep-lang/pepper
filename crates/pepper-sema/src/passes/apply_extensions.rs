//! Port of `source/Sema/ApplyExtensions.h`: clone extension methods onto the
//! target struct, record traits; two-pass applied-set.

use crate::model::{Diagnostic, ExtensionDef, FunctionDef, Module, StructDef, TraitDef};
use crate::passes::specialize_structs::{substitute, substitute_block};
use crate::type_name::TypeName;
use std::cell::RefCell;
use std::collections::HashSet;

// Applied-extension dedup set. Thread-local: each transform_pass run owns its
// own set, so concurrent compilations (test threads) never share indices.
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
        let method = clone_method(method, &st.name);
        if method.is_generic_func {
            st.generic_methods.push(method);
        } else {
            st.method_members.push(method);
        }
    }
    for trait_name in &ext.traits {
        st.traits.push(trait_name.clone());
        if let Some(def) = traits.iter().find(|t| t.name == trait_name.name) {
            conform(st, ext, trait_name, def, traits);
        }
    }
}

/// `extend S with Trait`: S must have every method the trait declares; a
/// trait method with a body is S's default when S has none of its own.
fn conform(
    st: &mut StructDef,
    ext: &ExtensionDef,
    trait_name: &TypeName,
    def: &TraitDef,
    traits: &[TraitDef],
) {
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
        if required.is_generic_func && st.generic_methods.iter().any(|m| m.name == required.name) {
            continue;
        }
        if let Some(have) = st.method_members.iter().find(|m| m.name == required.name) {
            check_signature(st, have, required, trait_name, &type_map, traits);
            continue;
        }
        match &required.body {
            Some(_) => {
                let mut method = clone_method(required, &st.name);
                method.trait_default = Some(def.methods.iter().map(|m| m.name.clone()).collect());
                substitute(&mut method.ty, &type_map);
                for param in &mut method.parameters {
                    substitute(&mut param.ty, &type_map);
                }
                if let Some(body) = &mut method.body {
                    substitute_block(body, &type_map);
                }
                // A generic default method (`map<U>`) is specialized per call.
                if method.is_generic_func {
                    st.generic_methods.push(method);
                } else {
                    st.method_members.push(method);
                }
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

/// A trait method's implementation must have the declared signature: a call
/// through a value of the trait type passes the declared argument types and
/// expects the declared result. One exception: where the trait returns a
/// trait type, the implementation may return a struct that conforms to it
/// (`EvensIterator iterate()` for `iterate(): Iterator<int>`), which keeps
/// direct calls static; `convert_to_traits` checks that conformance once
/// every extension is applied, and codegen converts the result in the
/// vtable.
fn check_signature(
    st: &StructDef,
    have: &FunctionDef,
    required: &FunctionDef,
    trait_name: &TypeName,
    type_map: &[(String, TypeName)],
    traits: &[TraitDef],
) {
    use crate::passes::check_function_types::canonical;
    let declared = |ty: &TypeName| {
        let mut ty = ty.clone();
        substitute(&mut ty, type_map);
        // A method declared without a return type returns nothing.
        if ty.to_string() == crate::type_name::AUTO {
            TypeName::void()
        } else {
            ty
        }
    };
    let actual = |ty: &TypeName| {
        if ty.to_string() == crate::type_name::AUTO {
            TypeName::void()
        } else {
            ty.clone()
        }
    };
    let signature =
        |ret: TypeName, params: Vec<TypeName>| TypeName::function_type(ret, params).display();
    let expected = signature(
        declared(&required.ty),
        required
            .parameters
            .iter()
            .map(|p| declared(&p.ty))
            .collect(),
    );
    let found = signature(
        actual(&have.ty),
        have.parameters.iter().map(|p| actual(&p.ty)).collect(),
    );
    let (have_ret, declared_ret) = (actual(&have.ty), declared(&required.ty));
    let covariant = crate::traits::is_trait_type(traits, &declared_ret)
        && !crate::traits::is_trait_type(traits, &have_ret)
        && have_ret.is_struct()
        && !have_ret.is_pointer();
    let same = have.is_static == required.is_static
        && have.parameters.len() == required.parameters.len()
        && (covariant || canonical(&have_ret) == canonical(&declared_ret))
        && have
            .parameters
            .iter()
            .zip(&required.parameters)
            .all(|(h, r)| canonical(&actual(&h.ty)) == canonical(&declared(&r.ty)));
    if !same {
        crate::errors::report(
            Diagnostic::error(format!(
                "'{}' in '{}' has type '{}', but trait '{}' declares '{}'",
                have.name,
                st.ty.display(),
                found,
                trait_name.display(),
                expected
            ))
            .at(have.loc)
            .with_note(
                format!("'{}' declared here", required.name),
                Some(required.loc),
            ),
        );
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
