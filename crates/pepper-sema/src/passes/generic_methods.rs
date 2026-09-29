//! Methods with type parameters of their own: `map<U>(f: (T) => U)`.
//!
//! A struct keeps its generic methods in `generic_methods`, which no other
//! pass compiles. A call `x.map<long>(f)` (the type arguments written, or
//! inferred by `resolve_implicit_types` from the arguments) makes
//! [`specialize_methods`] add `map<long>`, the method with `U` replaced, to
//! `method_members` of `x`'s struct, where it is compiled like any method.
//! A generic struct's specialization (`Box<int>`) gets its own copies of the
//! generic methods with the struct's parameters already replaced, so each
//! method specialization only substitutes the method's own parameters.

use crate::model::*;
use crate::type_name::TypeName;

/// Whether any struct declares a generic method.
pub fn has_generic_methods(module: &Module) -> bool {
    module.structs.iter().any(|s| !s.generic_methods.is_empty())
}

/// Add the method specializations that calls name (see the module docs).
/// Returns whether any was added.
pub fn specialize_methods(module: &mut Module) -> bool {
    let statics = crate::static_type::StructTable::build(module);
    let mut wanted: Vec<(TypeName, String)> = vec![];
    {
        let mut visit = |expr: &mut Expression, current: Option<&TypeName>| {
            crate::passes::walk_expression(expr, &mut |e| {
                if let Expression::MethodCall { this, method, .. } = e {
                    if method.contains('<') {
                        if let Some(owner) = crate::static_type::of(this, &statics, current) {
                            if !owner.contains_auto() {
                                wanted.push((owner, method.clone()));
                            }
                        }
                    }
                }
            });
        };
        for st in module.structs.iter().filter(|s| s.generic_params.is_empty()) {
            let current = Some(&st.ty);
            for method in st.method_members.iter().chain([&st.constructor, &st.destructor]) {
                if let Some(body) = &method.body {
                    let mut body = body.clone();
                    crate::passes::walk_block(&mut body, &mut |e| visit(e, current));
                }
            }
        }
        for function in module.functions.iter().filter(|f| !f.is_generic_func) {
            if let Some(body) = &function.body {
                let mut body = body.clone();
                crate::passes::walk_block(&mut body, &mut |e| visit(e, None));
            }
        }
        for var in &module.globals {
            if let Some(default) = &var.default {
                visit(&mut default.clone(), None);
            }
        }
    }

    let mut added = false;
    for (owner, method) in wanted {
        let key = owner.to_string();
        let key = key.trim_end_matches('*');
        let Some(st) = module.structs.iter_mut().find(|s| s.ty.to_string() == key) else { continue };
        if st.method_members.iter().any(|m| m.name == method) {
            continue;
        }
        let spec = crate::passes::gather_generics::parse_type_string(&method);
        let Some(base) = st.generic_methods.iter().find(|m| m.name == spec.name) else { continue };
        st.method_members.push(specialize(base, &spec));
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
    method
}
