//! Port of `source/Sema/ConvertIntrinsics.h`: `__ptr<T>` → `T*` type rewrite;
//! `__is_pod`/`__default` calls become intrinsic expressions.

use crate::model::{Block, Declaration, Expression, FunctionDef, Module, Statement};
use crate::type_name::TypeName;

fn convert_type_string(ty: &mut TypeName) {
    if ty.name == "__ptr" {
        if ty.sub_types.len() != 1 {
            panic!("__ptr<T> takes only a single generic type argument");
        }
        let pointee = ty.sub_types[0].to_string();
        *ty = TypeName::new(&format!("{}*", pointee));
    }
}

fn convert_expression(expr: &mut Expression) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        if let Expression::FunctionCall { function, .. } = e {
            let base = function.split('<').next().unwrap_or(function);
            if base == "__is_pod" {
                *e = Expression::IsPod(TypeName::new(function));
            } else if base == "__default" {
                *e = Expression::Default(TypeName::new(function));
            }
        }
    });
}

fn convert_block_decls(block: &mut Block) {
    for stmt in &mut block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) => {
                convert_type_string(&mut var.ty);
                if let Some(default) = &mut var.default {
                    convert_expression(default);
                }
            }
            Statement::Declaration(_) => {}
            Statement::Block(inner) => convert_block_decls(inner),
            Statement::Branch(branch) => {
                convert_block_decls(&mut branch.if_block);
                if let Some(else_block) = &mut branch.else_block {
                    convert_block_decls(else_block);
                }
            }
            Statement::While(wh) => convert_block_decls(&mut wh.block),
            _ => {}
        }
    }
}

fn convert_function(function: &mut FunctionDef) {
    convert_type_string(&mut function.ty);
    for param in &mut function.parameters {
        convert_type_string(&mut param.ty);
    }
    if let Some(body) = &mut function.body {
        crate::passes::walk_block(body, &mut convert_expression);
        convert_block_decls(body);
    }
}

pub fn convert_intrinsics(module: &mut Module) {
    for function in &mut module.functions {
        convert_function(function);
    }
    for st in &mut module.structs {
        for field in &mut st.field_members {
            convert_type_string(&mut field.ty);
        }
        for method in &mut st.method_members {
            convert_function(method);
        }
        // Constructor params + return type.
        convert_type_string(&mut st.constructor.ty);
        for param in &mut st.constructor.parameters {
            convert_type_string(&mut param.ty);
        }
        if let Some(body) = &mut st.constructor.body {
            crate::passes::walk_block(body, &mut convert_expression);
        }
    }
}
