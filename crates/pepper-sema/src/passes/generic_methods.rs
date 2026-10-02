//! Methods with type parameters of their own: `map<U>(f: (T) => U)`.
//!
//! A struct keeps its generic methods in `generic_methods`, which no other
//! pass compiles. A call `x.map<long>(f)` (the type arguments written, or
//! inferred by `resolve_implicit_types` from the arguments), or the method
//! as a value (`x.map<long>`, written or inferred from the expected
//! function type), makes
//! [`specialize_methods`] add `map<long>`, the method with `U` replaced, to
//! `method_members` of `x`'s struct, where it is compiled like any method.
//! A generic struct's specialization (`Box<int>`) gets its own copies of the
//! generic methods with the struct's parameters already replaced, so each
//! method specialization only substitutes the method's own parameters.

use crate::model::*;
use crate::type_name::TypeName;
use std::collections::HashMap;

/// Whether any struct declares a generic method.
pub fn has_generic_methods(module: &Module) -> bool {
    module.structs.iter().any(|s| !s.generic_methods.is_empty())
}

/// Add the method specializations that calls name (see the module docs).
/// Returns whether any was added.
pub fn specialize_methods(module: &mut Module) -> bool {
    // Built on the first call naming a generic method: most runs find none.
    let statics = std::cell::OnceCell::new();
    // Each call's receiver type and method, and where it is: the method
    // name and each argument.
    let mut wanted: Vec<(TypeName, String, Loc, Vec<Loc>)> = vec![];
    {
        let mut visit = |e: &Expression, current: Option<&TypeName>| {
            // A call, or the method as a value (`b.map<long>`).
            let (this, method, loc, args) = match e {
                Expression::MethodCall { this, method, args, loc } => (this, method, loc, args.iter().map(Expression::loc).collect()),
                Expression::MemberRef { lhs, name, loc } => (lhs, name, loc, vec![]),
                _ => return,
            };
            if method.contains('<') {
                let statics = statics.get_or_init(|| crate::static_type::StructTable::build(module));
                if let Some(owner) = crate::static_type::of(this, statics, current) {
                    if !owner.contains_auto() {
                        wanted.push((owner, method.clone(), *loc, args));
                    }
                }
            }
        };
        for st in module.structs.iter().filter(|s| s.generic_params.is_empty()) {
            let current = Some(&st.ty);
            for method in st.method_members.iter().chain(st.constructors.iter()).chain([&st.destructor]) {
                if let Some(body) = &method.body {
                    crate::passes::visit_block(body, &mut |e| visit(e, current));
                }
            }
        }
        for function in module.functions.iter().filter(|f| !f.is_generic_func) {
            if let Some(body) = &function.body {
                crate::passes::visit_block(body, &mut |e| visit(e, None));
            }
        }
        for var in &module.globals {
            if let Some(default) = &var.default {
                crate::passes::visit_expression(default, &mut |e| visit(e, None));
            }
        }
    }

    // A generic method's constraints are checked before it is cloned.
    let constrained = crate::passes::constraints::has_constraints(module);
    let conformance = std::cell::OnceCell::new();
    let mut added = false;
    for (owner, method, loc, args) in wanted {
        let key = owner.to_string();
        let key = key.trim_end_matches('*');
        let Some(index) = module.structs.iter().position(|s| s.ty.is_spelled(key)) else { continue };
        let st = &module.structs[index];
        if st.method_members.iter().any(|m| m.name == method) {
            continue;
        }
        let spec = crate::passes::gather_generics::parse_type_string(&method);
        let Some(base) = st.generic_methods.iter().find(|m| m.name == spec.name) else { continue };
        // `s.count_all<int>(it)` for `count_all<T, I>`: the rest come from
        // the arguments (`resolve_implicit_types`) first.
        if base.generic_params[spec.sub_types.len().min(base.generic_params.len())..].iter().any(|p| p.default.is_none()) {
            continue;
        }
        if constrained {
            let conformance = conformance.get_or_init(|| crate::passes::constraints::Conformance::of(module));
            if let Some(error) = conformance.check_call(module, base, &spec, loc, &args) {
                crate::errors::report(error);
                return false;
            }
        }
        let specialized = specialize(base, &spec);
        module.structs[index].method_members.push(specialized);
        added = true;
    }
    added
}

/// `base` with its type parameters replaced by `spec`'s arguments, named
/// `spec` (`map<long>`).
fn specialize(base: &FunctionDef, spec: &TypeName) -> FunctionDef {
    let type_map: Vec<(String, TypeName)> = base
        .generic_params
        .iter()
        .enumerate()
        .filter_map(|(i, p)| Some((p.name.clone(), spec.sub_types.get(i).cloned().or_else(|| p.default.clone())?)))
        .collect();
    let mut method = base.clone();
    method.name = spec.to_string();
    method.generic_params = vec![];
    method.is_generic_func = false;
    crate::type_name::replace_map(&mut method.ty, &type_map);
    for param in &mut method.parameters {
        crate::type_name::replace_map(&mut param.ty, &type_map);
        if let Some(default) = &mut param.default {
            crate::passes::specialize_functions::replace_expr_types(default, &type_map);
        }
    }
    if let Some(body) = &mut method.body {
        crate::passes::specialize_functions::replace_body_types(body, &type_map);
    }
    crate::passes::specialize_functions::rewrite_static_calls(&mut method, &type_map, &[]);
    method
}

/// Name each generic method written as a value without type arguments
/// where a function type is expected (`var m: ((int) => long) => Box<long>
/// = b.map;`) by the specialization that type picks (`b.map<long>`), which
/// [`specialize_methods`] then adds. An unbound method (`Box<int>.map`)
/// takes its receiver as the first parameter, which picks nothing. Runs in
/// `resolve_implicit_types`' loop; returns whether it named any.
pub fn bind_generic_method_values(module: &mut Module) -> bool {
    if !has_generic_methods(module) {
        return false;
    }
    let generic_names: std::collections::HashSet<String> =
        module.structs.iter().flat_map(|s| s.generic_methods.iter().map(|m| m.name.clone())).collect();
    let mut candidate = false;
    crate::passes::closures::for_each_expression_mut(module, &mut |e| {
        candidate |= matches!(e, Expression::MemberRef { name, .. } if generic_names.contains(name.as_str()));
    });
    if !candidate {
        return false;
    }
    let statics = crate::static_type::StructTable::build(module);
    let mut bound: HashMap<(String, Loc), String> = HashMap::new();
    crate::passes::closures::for_each_site(module, &mut |expr, expected, current| {
        let Expression::MemberRef { lhs, name, loc } = expr else { return };
        if !generic_names.contains(name.as_str()) {
            return;
        }
        let Some(expected) = expected.filter(|t| t.is_callable() && !t.contains_auto()) else { return };
        let Some(owner) = crate::static_type::of(lhs, &statics, current).filter(|t| !t.contains_auto()) else { return };
        let key = owner.to_string();
        let Some(st) = module.structs.iter().find(|s| s.ty.is_spelled(key.trim_end_matches('*'))) else { return };
        if st.method_members.iter().any(|m| m.name == *name) {
            return;
        }
        let Some(base) = st.generic_methods.iter().find(|m| m.name == *name) else { return };
        let signature = crate::passes::type_arguments::GenericSignature::of(base);
        // `Box<int>.map`: the receiver comes first.
        let mut expected = expected.clone();
        if !base.is_static && expected.function_params().len() == base.parameters.len() + 1 {
            expected.sub_types.remove(1);
        }
        let Some(args) = signature.infer_from_function_type(&base.ty, &expected) else { return };
        bound.insert((name.clone(), *loc), crate::passes::type_arguments::specialization(name, args));
    });
    if bound.is_empty() {
        return false;
    }
    crate::passes::closures::for_each_expression_mut(module, &mut |e| {
        if let Expression::MemberRef { name, loc, .. } = e {
            if let Some(specialized) = bound.get(&(name.clone(), *loc)) {
                *name = specialized.clone();
            }
        }
    });
    true
}
