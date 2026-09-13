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
            .find(|f| f.name == spec.name && !f.ty.sub_types.is_empty())
            .cloned()
        else {
            continue;
        };
        // map base type sub_types[idx] -> spec sub_types[idx]
        let mut type_map: Vec<(String, TypeName)> = vec![];
        for (idx, param_type) in base.ty.sub_types.iter().enumerate() {
            if let Some(arg) = spec.sub_types.get(idx) {
                type_map.push((param_type.name.clone(), arg.clone()));
            }
        }
        let mut specialized = base.clone();
        specialized.ty = spec.clone();
        specialized.name = spec.to_string();
        specialized.is_generic_func = false;
        for param in &mut specialized.parameters {
            crate::type_name::replace_map(&mut param.ty, &type_map);
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
    }
}

fn replace_expr_types(expr: &mut Expression, type_map: &[(String, TypeName)]) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        if let Expression::SymbolRef { ty, .. } = e {
            crate::type_name::replace_map(ty, type_map);
        }
    });
}
