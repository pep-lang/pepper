//! Port of `source/Sema/ResolveOperators.h`: index operations become
//! `__index_get`/`__index_set` method calls or POD array indexing; binary
//! operator overloads become method calls.

use crate::model::*;
use crate::type_name::TypeName;

pub fn resolve_operators(module: &mut Module) {
    // Index operations need to be resolved first so that indexed sets vs gets
    // can be resolved. Struct bodies are walked per-struct; free functions are
    // walked after a snapshot of the method tables (immutable during walk).
    for st_idx in 0..module.structs.len() {
        let is_generic = module.structs[st_idx].ty.is_generic();
        if is_generic {
            continue;
        }
        let method_names: Vec<String> = module.structs[st_idx]
            .method_members
            .iter()
            .map(|m| m.name.clone())
            .collect();

        let st = &mut module.structs[st_idx];
        if let Some(body) = &mut st.constructor.body {
            resolve_block(body, &method_names);
        }
        for method in &mut st.method_members {
            if let Some(body) = &mut method.body {
                resolve_block(body, &method_names);
            }
        }
    }

    // Snapshot method tables for free-function operator resolution.
    let struct_method_names: Vec<(String, Vec<String>)> = module
        .structs
        .iter()
        .map(|st| {
            (
                st.ty.to_string(),
                st.method_members.iter().map(|m| m.name.clone()).collect(),
            )
        })
        .collect();

    for function in &mut module.functions {
        // Operator overloads on struct-typed lhs: replace with method calls.
        if let Some(body) = &mut function.body {
            resolve_free_block(body, &struct_method_names);
        }
    }
}

fn resolve_block(block: &mut Block, method_names: &[String]) {
    for stmt in &mut block.items {
        resolve_stmt(stmt, method_names);
    }
}

fn resolve_stmt(stmt: &mut Statement, method_names: &[String]) {
    match stmt {
        Statement::Expression(expr) => resolve_expr(expr, method_names),
        Statement::Block(inner) => resolve_block(inner, method_names),
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            resolve_expr(&mut branch.condition, method_names);
            resolve_block(&mut branch.if_block, method_names);
            if let Some(else_block) = &mut branch.else_block {
                resolve_block(else_block, method_names);
            }
        }
        Statement::While(wh) => {
            resolve_expr(&mut wh.condition, method_names);
            resolve_block(&mut wh.block, method_names);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                resolve_expr(expr, method_names);
            }
        }
    }
}

fn resolve_expr(expr: &mut Expression, method_names: &[String]) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        match e {
            Expression::Binary { op, lhs, rhs } if op.is_assignment() => {
                // Special case assign to index operations → __index_set:
                // x[y] = z  →  x.__index_set(y, z)
                if let Expression::Index { lhs: container, rhs: index } = &**lhs {
                    let container = (**container).clone();
                    let index = (**index).clone();
                    let rhs_value = (**rhs).clone();
                    *e = Expression::MethodCall {
                        this: Box::new(container),
                        method: "__index_set".to_string(),
                        args: vec![index, rhs_value],
                    };
                    return;
                }
                // Compound assigns with an overload method (`str += x` →
                // `str.+=(x)`): only when the lhs is a struct-typed symbol
                // (resolve_implicit_types annotated its ty).
                let op_name = op.op_name();
                let lhs_is_struct = match &**lhs {
                    Expression::SymbolRef { ty, .. } => {
                        !ty.is_empty()
                            && ty.to_string() != "__auto"
                            && crate::type_name::INTEGRAL_TYPES
                                .contains(ty.to_string().as_str())
                            == false
                    }
                    Expression::ThisRef => true,
                    _ => false,
                };
                if !op_name.is_empty()
                    && method_names.iter().any(|m| *m == op_name)
                    && lhs_is_struct
                {
                    let lhs = (**lhs).clone();
                    let rhs = (**rhs).clone();
                    *e = Expression::MethodCall {
                        this: Box::new(lhs),
                        method: op_name,
                        args: vec![rhs],
                    };
                }
            }
            Expression::Index { lhs, rhs } => {
                if method_names.iter().any(|m| m == "__index_get") {
                    // Replace the index op with a call to the index method.
                    let lhs = (**lhs).clone();
                    let rhs = (**rhs).clone();
                    *e = Expression::MethodCall {
                        this: Box::new(lhs),
                        method: "__index_get".to_string(),
                        args: vec![rhs],
                    };
                } else {
                    // POD array indexing (type resolved at codegen).
                    let lhs = (**lhs).clone();
                    let rhs = (**rhs).clone();
                    *e = Expression::ArrayIndex {
                        ty: TypeName::auto(),
                        lhs: Box::new(lhs),
                        rhs: Box::new(rhs),
                    };
                }
            }
            Expression::Binary { op, lhs, rhs } => {
                // Resolve overloads on lhs: x + y → x.operator+(y).
                let op_name = op.op_name();
                if !op_name.is_empty() && method_names.iter().any(|m| *m == op_name) {
                    let lhs = (**lhs).clone();
                    let rhs = (**rhs).clone();
                    *e = Expression::MethodCall {
                        this: Box::new(lhs),
                        method: op_name,
                        args: vec![rhs],
                    };
                }
            }
            _ => {}
        }
    });
}

fn resolve_free_block(block: &mut Block, struct_method_names: &[(String, Vec<String>)]) {
    // Free functions can overload operators on struct types. Walk all
    // statements (declarations can nest operator expressions).
    for stmt in &mut block.items {
        resolve_free_stmt(stmt, struct_method_names);
    }
}

fn resolve_free_stmt(stmt: &mut Statement, struct_method_names: &[(String, Vec<String>)]) {
    match stmt {
        Statement::Expression(expr) => resolve_free_expr(expr, struct_method_names),
        Statement::Block(inner) => resolve_free_block(inner, struct_method_names),
        Statement::Declaration(Declaration::Variable(var)) => {
            if let Some(default) = &mut var.default {
                resolve_free_expr(default, struct_method_names);
            }
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            resolve_free_expr(&mut branch.condition, struct_method_names);
            resolve_free_block(&mut branch.if_block, struct_method_names);
            if let Some(else_block) = &mut branch.else_block {
                resolve_free_block(else_block, struct_method_names);
            }
        }
        Statement::While(wh) => {
            resolve_free_expr(&mut wh.condition, struct_method_names);
            resolve_free_block(&mut wh.block, struct_method_names);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                resolve_free_expr(expr, struct_method_names);
            }
        }
    }
}

fn resolve_free_expr(expr: &mut Expression, struct_method_names: &[(String, Vec<String>)]) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        if let Expression::Binary { op, lhs, rhs } = e {
            let op_name = op.op_name();
            if op_name.is_empty() {
                return;
            }
            // Determine lhs struct type from resolved symbol type.
            let lhs_ty = match &**lhs {
                Expression::SymbolRef { ty, .. }
                    if !ty.is_empty() && ty.to_string() != crate::type_name::AUTO =>
                {
                    ty.clone()
                }
                _ => return,
            };
            if lhs_ty.is_empty() || lhs_ty.to_string() == crate::type_name::AUTO {
                return;
            }
            let methods = match struct_method_names
                .iter()
                .find(|(ty, _)| *ty == lhs_ty.to_string())
            {
                Some((_, methods)) => methods,
                None => return,
            };
            if methods.iter().any(|m| *m == op_name) {
                let lhs = (**lhs).clone();
                let rhs = (**rhs).clone();
                *e = Expression::MethodCall {
                    this: Box::new(lhs),
                    method: op_name,
                    args: vec![rhs],
                };
            }
        }
    });
}
