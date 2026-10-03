//! Port of `source/Sema/SpecializeFunctions.h`: clone a generic function into
//! a specialized instance `name<args>` with substituted types.

use crate::model::*;
use crate::type_name::TypeName;

pub fn specialize_functions(module: &mut Module) {
    let specs: Vec<TypeName> = module.func_specs.clone();
    // Looked up once per spec, and a checked runtime brings many.
    let structs: std::collections::HashSet<String> =
        module.structs.iter().flat_map(|st| [st.name.clone(), st.ty.to_string()]).collect();
    let mut functions: std::collections::HashSet<String> = module.functions.iter().map(|f| f.name.clone()).collect();
    for spec in specs {
        // Skip constructor-shaped specs (they are struct specs).
        if structs.contains(&spec.name) || structs.contains(&spec.to_string()) {
            continue;
        }
        // Existing specialization?
        if functions.contains(&spec.to_string()) {
            continue;
        }
        if crate::passes::gather_generics::specialization_too_deep(module, &spec) {
            return;
        }
        let bases = if module.templates.frozen { &module.templates.functions } else { &module.functions };
        let Some(base) = bases.iter().find(|f| f.name == spec.name && f.is_generic_func).cloned() else {
            continue;
        };
        // map base generic_params[idx] -> spec sub_types[idx]
        let mut type_map: Vec<(String, TypeName)> = vec![];
        for (idx, param) in base.generic_params.iter().enumerate() {
            // Missing arguments fall back to the parameter's default.
            let arg = spec.sub_types.get(idx).cloned().or_else(|| param.default.clone());
            if let Some(arg) = arg {
                type_map.push((param.name.clone(), arg));
            }
        }
        // `count_all<int>(it)` for `count_all<T, I>`: the rest come from the
        // arguments (`resolve_implicit_types`), or `check_type_arguments`
        // reports the call.
        if type_map.len() < base.generic_params.len() {
            continue;
        }
        let mut specialized = base.clone();
        // The instance's declared return type is the base's, with the
        // generic arguments substituted (`hash<T>` → `u64`).
        crate::type_name::replace_map(&mut specialized.ty, &type_map);
        specialized.name = spec.to_string();
        specialized.is_generic_func = false;
        for param in &mut specialized.parameters {
            crate::type_name::replace_map(&mut param.ty, &type_map);
            if let Some(default) = &mut param.default {
                replace_expr_types(default, &type_map);
            }
        }
        if let Some(body) = &mut specialized.body {
            replace_body_types(body, &type_map);
        }
        rewrite_static_calls(&mut specialized, &type_map, &[]);
        functions.insert(specialized.name.clone());
        module.functions.push(specialized);
    }
}

/// Rewrites each static call through a type parameter in `function`'s body
/// (`T.unit()`) to name its type argument, as the builder writes a type
/// there: `Square.unit()`, and `Box<int>.make()` as a type literal. A
/// parameter, local or field (`fields`) of that name is a value, not the
/// type, anywhere in the function.
pub(crate) fn rewrite_static_calls(function: &mut FunctionDef, type_map: &[(String, TypeName)], fields: &[String]) {
    let Some(body) = &mut function.body else { return };
    let mut values: std::collections::HashSet<String> = fields.iter().cloned().collect();
    values.extend(function.parameters.iter().map(|p| p.name.trim_start_matches("this.").to_string()));
    collect_locals(body, &mut values);
    let map: Vec<&(String, TypeName)> = type_map.iter().filter(|(p, _)| !values.contains(p)).collect();
    if map.is_empty() {
        return;
    }
    crate::passes::walk_block(body, &mut |e: &mut Expression| {
        // A constructor through a type parameter: `T()` is `Point()`.
        if let Expression::FunctionCall { function, .. } = e
            && let Some((_, ty)) = map.iter().find(|(p, _)| p == function)
        {
            *function = ty.to_string();
            return;
        }
        // A value type's static method is its function `X::m`.
        if let Expression::MethodCall { this, method, args, loc } = e
            && let Expression::SymbolRef { id, .. } = this.as_ref()
            && let Some((_, ty)) = map.iter().find(|(p, _)| p == id)
            && let Some(key) = crate::value_types::key(&ty.to_string())
            && crate::enums::method_is_static(&key, method) == Some(true)
        {
            *e = Expression::FunctionCall { function: crate::enums::method_name(&key, method), args: std::mem::take(args), loc: *loc };
            return;
        }
        if let Expression::MethodCall { this, .. } = e
            && let Expression::SymbolRef { id, loc, .. } = this.as_mut()
            && let Some((_, ty)) = map.iter().find(|(p, _)| p == id)
        {
            if ty.sub_types.is_empty() {
                *id = ty.to_string();
            } else {
                let loc = *loc;
                **this = Expression::FunctionCall { function: ty.to_string(), args: vec![], loc };
            }
        }
    });
}

/// The names of the locals declared anywhere in `block`.
fn collect_locals(block: &Block, out: &mut std::collections::HashSet<String>) {
    for stmt in &block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) => {
                out.insert(var.name.clone());
            }
            Statement::Block(inner) => collect_locals(inner, out),
            Statement::Branch(branch) => {
                collect_locals(&branch.if_block, out);
                if let Some(else_block) = &branch.else_block {
                    collect_locals(else_block, out);
                }
            }
            Statement::While(wh) => collect_locals(&wh.block, out),
            _ => {}
        }
    }
}

pub(crate) fn replace_body_types(block: &mut Block, type_map: &[(String, TypeName)]) {
    for stmt in &mut block.items {
        replace_stmt_types(stmt, type_map);
    }
}

fn replace_stmt_types(stmt: &mut Statement, type_map: &[(String, TypeName)]) {
    match stmt {
        Statement::Expression(expr) => replace_expr_types(expr, type_map),
        Statement::Block(inner) => replace_body_types(inner, type_map),
        Statement::Declaration(Declaration::Variable(var)) => {
            crate::type_name::replace_map(&mut var.ty, type_map);
            if let Some(default) = &mut var.default {
                replace_expr_types(default, type_map);
            }
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            replace_expr_types(&mut branch.condition, type_map);
            replace_body_types(&mut branch.if_block, type_map);
            if let Some(else_block) = &mut branch.else_block {
                replace_body_types(else_block, type_map);
            }
        }
        Statement::While(wh) => {
            replace_expr_types(&mut wh.condition, type_map);
            replace_body_types(&mut wh.block, type_map);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                replace_expr_types(expr, type_map);
            }
        }
        Statement::Static(block) => {
            block.substitute(type_map);
            block.for_each_emitted_mut(&mut |s| replace_stmt_types(s, type_map), &mut |e| replace_expr_types(e, type_map));
        }
        Statement::LoopBreak(_) | Statement::StaticPass(_) => {}
    }
}

pub(crate) fn replace_expr_types(expr: &mut Expression, type_map: &[(String, TypeName)]) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        // `SizeOf<T>` in specialized bodies: substitute the generic arg.
        if let Expression::SizeOf(ty) = e {
            crate::type_name::replace_map(ty, type_map);
        }
        // Intrinsic nodes carry a TypeName that may still reference a
        // generic param (`Address(T)` from `__address<T>(v)`):
        // substitute those too.
        match e {
            Expression::ArrayIndex { ty, .. }
            | Expression::IsPod(ty)
            | Expression::Default(ty)
            | Expression::StaticCase { ty, .. }
            | Expression::Subject { ty, .. }
            | Expression::Allocate(ty)
            | Expression::Cast { ty, .. } => crate::type_name::replace_map(ty, type_map),
            Expression::RefCount(ty, _) | Expression::Weak(_, ty, _) => crate::type_name::replace_map(ty, type_map),
            Expression::Address(ty, _) => crate::type_name::replace_map(ty, type_map),
            Expression::AtomicLoad(ty, _)
            | Expression::AtomicStore(ty, _, _)
            | Expression::AtomicCmpXchg(ty, _, _, _) => {
                crate::type_name::replace_map(ty, type_map)
            }
            Expression::AtomicFetch(_, ty, _, _) | Expression::Simd { ty, .. } => crate::type_name::replace_map(ty, type_map),
            Expression::MakeClosure { closure, ty, .. } => {
                crate::type_name::replace_map(ty, type_map);
                let mut parsed = crate::passes::gather_generics::parse_type_string(closure);
                crate::type_name::replace_map(&mut parsed, type_map);
                *closure = parsed.to_string();
            }
            _ => {}
        }
        // Generic calls inside bodies (`__address<T>(v)` → `__address<int>(v)`,
        // `copies.copy<T>(v)` → `copies.copy<int>(v)`).
        if let Expression::FunctionCall { function, .. } | Expression::MethodCall { method: function, .. } = e
            && function.contains('<')
        {
            let mut parsed = crate::passes::gather_generics::parse_type_string(function);
            crate::type_name::replace_map(&mut parsed, type_map);
            *function = parsed.to_string();
        }
        if let Expression::SymbolRef { ty, .. } = e {
            crate::type_name::replace_map(ty, type_map);
        }
    });
}
