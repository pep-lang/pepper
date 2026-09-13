//! Port of `source/Sema/ConvertStringLiterals.h`: non-raw string literals
//! become `string(literal, length)` constructor calls.

use crate::model::{Expression, Module, UnaryOp};
use crate::passes::{walk_expression, walk_function};
use crate::struct_body;
use crate::type_name::TypeName;

fn convert(st: &mut crate::model::StructDef) {
    let mut f = |expr: &mut Expression| {
        if let Expression::StringLiteral { value, is_raw } = expr {
            if *is_raw {
                return;
            }
            *expr = Expression::FunctionCall {
                function: "string".to_string(),
                args: vec![
                    Expression::StringLiteral {
                        value: value.clone(),
                        is_raw: true,
                    },
                    Expression::IntLiteral(value.chars().count() as i64),
                ],
            };
        }
    };
    for method in &mut st.method_members {
        walk_function(method, &mut f);
    }
    if let Some(body) = &mut st.constructor.body {
        crate::passes::walk_block(body, &mut f);
    }
    if let Some(body) = &mut st.destructor.body {
        crate::passes::walk_block(body, &mut f);
    }
}

pub fn convert_string_literals(module: &mut Module) {
    let _ = UnaryOp::Neg; // keep import surface minimal
    let _ = TypeName::auto();
    let _ = struct_body::apply;
    for st in &mut module.structs {
        convert(st);
    }
    for function in &mut module.functions {
        walk_function(function, &mut f_convert());
    }
}

fn f_convert() -> impl FnMut(&mut Expression) {
    |expr: &mut Expression| {
        if let Expression::StringLiteral { value, is_raw } = expr {
            if *is_raw {
                return;
            }
            *expr = Expression::FunctionCall {
                function: "string".to_string(),
                args: vec![
                    Expression::StringLiteral {
                        value: value.clone(),
                        is_raw: true,
                    },
                    Expression::IntLiteral(value.chars().count() as i64),
                ],
            };
        }
    }
}
