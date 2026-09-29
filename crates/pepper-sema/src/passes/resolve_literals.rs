//! Port of `source/Sema/ResolveLiterals.h`: Minus+literal folding.

use crate::model::{Expression, Module};
use crate::passes::walk_function;

pub fn resolve_literals(module: &mut Module) {
    let mut f = |expr: &mut Expression| {
        if let Expression::Unary {
            op: crate::model::UnaryOp::Neg,
            operand, ..
        } = expr
        {
            // Fold -literal into a negated literal.
            if let Expression::IntLiteral(value) = **operand {
                *expr = Expression::IntLiteral(-value);
                return;
            }
            if let Expression::FloatLiteral(value) = **operand {
                *expr = Expression::FloatLiteral(-value);
            }
        }
    };
    for st in &mut module.structs {
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
    for function in &mut module.functions {
        walk_function(function, &mut f);
    }
    for var in &mut module.globals {
        crate::passes::walk_global(var, &mut f);
    }
}
