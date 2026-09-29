//! Port of `source/Sema/ConvertPrintCalls.h`: a `print` argument that is a
//! `string` instance becomes `arg.Data`, so codegen's char* print arm emits
//! the string's bytes. Arguments of other types are untouched, keeping the
//! int/float print arms for mixed calls.

use crate::model::{Expression, Module};
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;

fn convert(expr: &mut Expression, table: &StructTable, current: Option<&TypeName>) {
    if let Expression::FunctionCall { function, args, .. } = expr {
        if function == "print" {
            for arg in args.iter_mut() {
                // A raw literal needs no ctor call at all: it becomes the
                // global string pointer directly, so nothing is allocated.
                if let Expression::FunctionCall { function, args: ctor_args, .. } = arg {
                    if function == "String" && ctor_args.len() >= 1 {
                        if let Expression::StringLiteral { .. } = &ctor_args[0] {
                            let literal = std::mem::replace(&mut ctor_args[0], Expression::IntLiteral(0));
                            *arg = literal;
                            continue;
                        }
                    }
                }
                if static_type::of(arg, table, current).is_some_and(|ty| StructTable::base_name(&ty) == "String") {
                    let lhs = std::mem::replace(arg, Expression::IntLiteral(0));
                    let loc = lhs.loc();
                    *arg = Expression::MemberRef { lhs: Box::new(lhs), name: "Data".to_string(), loc };
                }
            }
        }
    }
}

fn walk_body(body: &mut crate::model::Block, table: &StructTable, current: Option<&TypeName>) {
    let mut f = |expr: &mut Expression| convert(expr, table, current);
    crate::passes::walk_block(body, &mut f);
}

pub fn convert_print_calls(module: &mut Module) {
    let table = StructTable::build(module);

    for function in &mut module.functions {
        if let Some(body) = &mut function.body {
            walk_body(body, &table, None);
        }
    }
    for var in &mut module.globals {
        crate::passes::walk_global(var, &mut |expr: &mut Expression| convert(expr, &table, None));
    }

    // Struct ctor and method bodies.
    for st in &mut module.structs {
        if let Some(body) = &mut st.constructor.body {
            walk_body(body, &table, Some(&st.ty));
        }
        for method in &mut st.method_members {
            if let Some(body) = &mut method.body {
                walk_body(body, &table, Some(&st.ty));
            }
        }
    }

    // Extension methods.
    for ext in &mut module.extensions {
        for method in &mut ext.methods {
            if let Some(body) = &mut method.body {
                walk_body(body, &table, Some(&ext.target));
            }
        }
    }
}
