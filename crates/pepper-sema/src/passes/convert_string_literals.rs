//! Port of `source/Sema/ConvertStringLiterals.h`: string literals become
//! `string(literal, size, length)` constructor calls. The first argument is a
//! raw literal (kept as a `char*` global) that the ctor copies from; the
//! second is the byte size, the third the character count.

use crate::model::{Expression, Module, VariableDef};

fn convert(expr: &mut Expression) {
    if let Expression::StringLiteral { value, is_raw } = expr {
        // Raw literals are `char*` globals (synthesized ctor tracing and the
        // first ctor argument); they must not become ctor calls.
        if *is_raw {
            return;
        }
        *expr = Expression::FunctionCall {
            function: "String".to_string(),
            args: vec![
                Expression::StringLiteral {
                    value: value.clone(),
                    is_raw: true,
                },
                Expression::IntLiteral(value.len() as i64),
                Expression::IntLiteral(value.chars().count() as i64),
            ],
            loc: crate::model::Loc::NONE,
        };
    }
}

fn walk_body(body: &mut crate::model::Block) {
    crate::passes::walk_block(body, &mut |expr: &mut Expression| convert(expr));
}

/// A `String` parameter's literal default (`new(String name = "")`) is
/// evaluated at each call site that omits the argument, so it must be a
/// String like any other literal. Other parameter types keep their literal
/// (a `__ptr<char>` default stays the raw global).
fn convert_defaults(parameters: &mut [VariableDef]) {
    for param in parameters {
        if param.ty.to_string() != "String" {
            continue;
        }
        if let Some(default) = &mut param.default {
            convert(default);
        }
    }
}

pub fn convert_string_literals(module: &mut Module) {
    for function in &mut module.functions {
        convert_defaults(&mut function.parameters);
        if let Some(body) = &mut function.body {
            walk_body(body);
        }
    }
    for var in &mut module.globals {
        crate::passes::walk_global(var, &mut |expr: &mut Expression| convert(expr));
    }

    // Struct method bodies and ctor.
    for st in &mut module.structs {
        convert_defaults(&mut st.constructor.parameters);
        if let Some(body) = &mut st.constructor.body {
            walk_body(body);
        }
        for method in &mut st.method_members {
            convert_defaults(&mut method.parameters);
            if let Some(body) = &mut method.body {
                walk_body(body);
            }
        }
    }

    // Extension methods.
    for ext in &mut module.extensions {
        for method in &mut ext.methods {
            convert_defaults(&mut method.parameters);
            if let Some(body) = &mut method.body {
                walk_body(body);
            }
        }
    }
}
