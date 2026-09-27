//! Port of `source/Sema/SpecializeFunctions.h`: clone a generic function into
//! a specialized instance `name<args>` with substituted types.

use crate::model::*;
use crate::type_name::TypeName;

pub fn specialize_functions(module: &mut Module) {
    let specs: Vec<TypeName> = module.func_specs.clone();
    for spec in specs {
        // Skip constructor-shaped specs (they are struct specs).
        if module
            .structs
            .iter()
            .any(|st| st.name == spec.name || st.ty.to_string() == spec.to_string())
        {
            continue;
        }
        // Existing specialization?
        if module.functions.iter().any(|f| f.name == spec.to_string()) {
            continue;
        }
        let Some(base) = module
            .functions
            .iter()
            .find(|f| f.name == spec.name && f.is_generic_func)
            .cloned()
        else {
            continue;
        };
        // map base generic_params[idx] -> spec sub_types[idx]
        let mut type_map: Vec<(String, TypeName)> = vec![];
        for (idx, param) in base.generic_params.iter().enumerate() {
            if let Some(arg) = spec.sub_types.get(idx) {
                type_map.push((param.name.clone(), arg.clone()));
            }
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
        module.functions.push(specialized);
    }
}

fn replace_body_types(block: &mut Block, type_map: &[(String, TypeName)]) {
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
        Statement::LoopBreak(_) => {}
    }
}

fn replace_expr_types(expr: &mut Expression, type_map: &[(String, TypeName)]) {
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
            | Expression::Cast { ty, .. } => crate::type_name::replace_map(ty, type_map),
            Expression::RefCount(ty, _) => crate::type_name::replace_map(ty, type_map),
            Expression::Address(ty, _) => crate::type_name::replace_map(ty, type_map),
            Expression::AtomicLoad(ty, _)
            | Expression::AtomicStore(ty, _, _)
            | Expression::AtomicCmpXchg(ty, _, _, _) => {
                crate::type_name::replace_map(ty, type_map)
            }
            Expression::AtomicFetch(_, ty, _, _) => crate::type_name::replace_map(ty, type_map),
            _ => {}
        }
        // Generic calls inside bodies (`__address<T>(v)` → `__address<int>(v)`).
        if let Expression::FunctionCall { function, .. } = e {
            let mut parsed = crate::passes::gather_generics::parse_type_string(function);
            crate::type_name::replace_map(&mut parsed, type_map);
            *function = parsed.to_string();
        }
        if let Expression::SymbolRef { ty, .. } = e {
            crate::type_name::replace_map(ty, type_map);
        }
    });
}
