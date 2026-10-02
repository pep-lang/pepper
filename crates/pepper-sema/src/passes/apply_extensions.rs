//! Port of `source/Sema/ApplyExtensions.h`: clone extension methods onto the
//! target struct, record traits; two-pass applied-set.

use crate::model::{BinaryOp, Block, Diagnostic, Expression, ExtensionDef, FunctionDef, Kind, Module, ReturnStatement, Statement, StructDef, TraitDef};
use crate::passes::overloads::set_name;
use crate::passes::specialize_structs::{substitute, substitute_block};
use crate::type_name::TypeName;
use std::cell::RefCell;
use std::collections::HashSet;

// Which extension (by index) has been applied to which struct (by name).
// Thread-local: each transform_pass run owns its own set, so concurrent
// compilations (test threads) never share indices. By struct, so an
// instance specialized after an extension first ran (`extend Box<int>`
// on a `Box<int>` a later round creates) gets it too.
thread_local! {
    static APPLIED: RefCell<HashSet<(usize, String)>> = RefCell::new(HashSet::new());
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
        // `copies` gives every struct that declares a trait this member.
        if required.name == crate::passes::copies::COPY_TRAIT_METHOD {
            continue;
        }
        if required.is_generic_func && st.generic_methods.iter().any(|m| m.name == required.name) {
            continue;
        }
        // The struct's methods of the member's name, overloads included; the
        // one with the declared parameter types implements it.
        let set = set_name(&required.name);
        let candidates: Vec<&FunctionDef> = st.method_members.iter().filter(|m| set_name(&m.name) == set).collect();
        if let Some(have) = candidates.iter().find(|m| same_parameters(m, required, &type_map)) {
            check_signature(st, have, required, trait_name, &type_map, traits);
            continue;
        }
        if let ([have], None, true) = (candidates.as_slice(), &required.body, set == required.name) {
            // Report how the one method of that name differs, unless the
            // trait overloads the name and that method is another member's.
            check_signature(st, have, required, trait_name, &type_map, traits);
            continue;
        }
        // A trait's property is met by a plain field of its name too: its
        // accessors read and write the field.
        if let Some(accessor) = field_accessor(st, required) {
            st.method_members.push(accessor);
            continue;
        }
        match &required.body {
            Some(_) => {
                let mut method = clone_method(required, &st.name);
                // A copied default joins the struct's overload set of its name.
                method.name = set.to_string();
                method.trait_default = Some(def.methods.iter().map(|m| set_name(&m.name).to_string()).collect());
                method.owner = ext.loc;
                substitute(&mut method.ty, &type_map);
                // `put_all<I: Iterator<T>>` of `Sink<int>`: `I: Iterator<int>`.
                for bound in method.generic_params.iter_mut().flat_map(|p| &mut p.bounds) {
                    substitute(&mut bound.ty, &type_map);
                }
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
            None => {
                // An overloaded member is named with its parameter types.
                let property = required.name.strip_prefix("__get_").or_else(|| required.name.strip_prefix("__set_"));
                let wanted = if let Some(property) = property {
                    property.to_string()
                } else if set == required.name {
                    set.to_string()
                } else {
                    let params: Vec<String> = required
                        .parameters
                        .iter()
                        .map(|p| {
                            let mut ty = p.ty.clone();
                            substitute(&mut ty, &type_map);
                            ty.display()
                        })
                        .collect();
                    format!("{}({})", set, params.join(", "))
                };
                crate::errors::report(
                    Diagnostic::error(format!(
                        "'{}' does not implement {}'{}', required by trait '{}'",
                        st.ty.display(),
                        if property.is_some() { "property " } else { "" },
                        wanted,
                        trait_name.display()
                    ))
                    .at(ext.loc)
                    .with_note(format!("'{}' declared here", wanted), Some(required.loc)),
                )
            }
        }
    }
}

/// For a trait property's accessor `required` (`__get_p` or `__set_p`), the
/// accessor of a plain field `p` of `st` that meets it.
fn field_accessor(st: &StructDef, required: &FunctionDef) -> Option<FunctionDef> {
    let (name, getter) = match (required.name.strip_prefix("__get_"), required.name.strip_prefix("__set_")) {
        (Some(name), _) => (name, true),
        (_, Some(name)) => (name, false),
        _ => return None,
    };
    let field = st.field_members.iter().find(|f| f.name == name && f.kind == Kind::Field && !f.hidden)?;
    let at = required.loc;
    let field_ref = Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: name.to_string(), loc: at };
    let statement = if getter {
        Statement::Return(ReturnStatement { expr: Some(field_ref), loc: at })
    } else {
        Statement::Expression(Expression::Binary {
            op: BinaryOp::Assign,
            lhs: Box::new(field_ref),
            rhs: Box::new(Expression::SymbolRef { id: "value".to_string(), ty: field.ty.clone(), loc: at }),
            loc: at,
        })
    };
    let mut accessor = clone_method(required, &st.name);
    accessor.ty = if getter { field.ty.clone() } else { TypeName::void() };
    if let Some(value) = accessor.parameters.first_mut() {
        value.ty = field.ty.clone();
    }
    accessor.body = Some(Block { name: String::new(), items: vec![statement], attributes: vec![] });
    Some(accessor)
}

/// Whether `have` takes the parameter types trait member `required`
/// declares (with the trait's type arguments substituted).
fn same_parameters(have: &FunctionDef, required: &FunctionDef, type_map: &[(String, TypeName)]) -> bool {
    use crate::passes::check_function_types::canonical;
    have.is_static == required.is_static
        && have.parameters.len() == required.parameters.len()
        && have.parameters.iter().zip(&required.parameters).all(|(h, r)| {
            let mut declared = r.ty.clone();
            substitute(&mut declared, type_map);
            canonical(&h.ty) == canonical(&declared)
        })
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
        if ty.is_auto() {
            TypeName::void()
        } else {
            ty
        }
    };
    let actual = |ty: &TypeName| {
        if ty.is_auto() {
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
            if ext.resolved.is_none() {
                // Unresolved targets are handled by resolve_resolvables; skip.
                continue;
            }
            let target_name = ext.resolved.clone().expect("resolved");
            // Apply to every struct matching the resolved name (concrete or
            // specialized instance), once each.
            // A checked struct has had the checked extensions applied.
            let done = ext_idx < module.checked.extensions;
            for st in module.structs.iter_mut().filter(|st| !(done && module.checked.has_struct(&st.name))) {
                if (st.name == target_name || st.ty.is_spelled(&target_name)) && applied.insert((ext_idx, st.name.clone())) {
                    apply_to_struct(st, ext, &module.traits);
                    // An extension's methods join the struct's overload sets.
                    let Some(sets) = crate::passes::overloads::group_methods(&mut st.method_members, &st.name) else { return };
                    if !sets.is_empty() {
                        module.method_overload_sets.insert(st.name.clone(), sets);
                    }
                }
            }
        }
    });
}

/// Reset the applied-set (each `TransformPass::run` starts fresh).
pub fn reset_applied() {
    APPLIED.with(|a| a.borrow_mut().clear());
}
