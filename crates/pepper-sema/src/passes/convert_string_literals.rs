//! Port of `source/Sema/ConvertStringLiterals.h`: string literals become
//! `string(literal, size, length)` constructor calls. The first argument is a
//! raw literal (kept as a `char*` global) that the ctor copies from; the
//! second is the byte size, the third the character count.

use crate::model::{Expression, Loc, Module, VariableDef};

pub(crate) fn convert(expr: &mut Expression) {
    if let Expression::StringLiteral { value, is_raw, loc } = expr {
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
                    loc: *loc,
                },
                Expression::IntLiteral(value.len() as i64),
                Expression::IntLiteral(value.chars().count() as i64),
            ],
            // The literal's own location, so errors about the String
            // point at it.
            loc: *loc,
        };
    }
}

/// Whether the call `function(args)` at `loc` is one [`convert`] made from a
/// string literal: it gives the call its literal's location, while a
/// `String(...)` the user wrote has its own. Such a call always constructs
/// the `String` type, even where a method or enum case named `String` is in
/// scope.
pub fn is_converted_literal(function: &str, args: &[Expression], loc: Loc) -> bool {
    function == "String" && matches!(args.first(), Some(Expression::StringLiteral { is_raw: true, loc: literal, .. }) if *literal == loc)
}

fn walk_body(body: &mut crate::model::Block) {
    crate::passes::walk_block(body, &mut |expr: &mut Expression| convert(expr));
}

/// A `String` parameter's literal default (`construct(String name = "")`) is
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
        for c in &mut st.constructors {
            convert_defaults(&mut c.parameters);
        }
        for body in st.constructors.iter_mut().filter_map(|c| c.body.as_mut()) {
            walk_body(body);
        }
        // Generic methods too (`add<T>`): `generic_methods::specialize_methods`
        // clones them into `method_members` after this pass, so a literal
        // left raw here reached codegen as a bare `char*` where a String was
        // due.
        for method in st.method_members.iter_mut().chain(st.generic_methods.iter_mut()) {
            convert_defaults(&mut method.parameters);
            if let Some(body) = &mut method.body {
                walk_body(body);
            }
        }
    }

    // Trait default bodies: `apply_extensions` copies each into the
    // structs that take it, after this pass, so a literal left raw here
    // reached codegen as a bare `char*` returned where a String was due.
    for tr in &mut module.traits {
        for method in &mut tr.methods {
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
