//! Port of `source/Sema/ConvertMemberRefs.h`: bare unresolved symbols in
//! struct methods become `this.<field>`; plain calls matching a method become
//! method calls; params exempt.

use crate::model::*;
use crate::type_name::TypeName;

fn convert_block(block: &mut Block, struct_name: &str, fields: &[VariableDef], methods: &[String], locals: &mut Vec<String>, globals: &std::collections::HashSet<String>) {
    for stmt in &mut block.items {
        convert_statement(stmt, struct_name, fields, methods, locals, globals);
    }
}

fn convert_statement(stmt: &mut Statement, struct_name: &str, fields: &[VariableDef], methods: &[String], locals: &mut Vec<String>, globals: &std::collections::HashSet<String>) {
    match stmt {
        Statement::Expression(expr) => convert_expression(expr, struct_name, fields, methods, locals, globals),
        Statement::Block(inner) => {
            let base = locals.len();
            convert_block(inner, struct_name, fields, methods, locals, globals);
            locals.truncate(base);
        }
        Statement::Declaration(Declaration::Variable(var)) => {
            // Record the local (params were pre-seeded by the caller).
            locals.push(var.name.clone());
            if let Some(default) = &mut var.default {
                convert_expression(default, struct_name, fields, methods, locals, globals);
            }
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            convert_expression(&mut branch.condition, struct_name, fields, methods, locals, globals);
            let base = locals.len();
            convert_block(&mut branch.if_block, struct_name, fields, methods, locals, globals);
            locals.truncate(base);
            if let Some(else_block) = &mut branch.else_block {
                let base = locals.len();
                convert_block(else_block, struct_name, fields, methods, locals, globals);
                locals.truncate(base);
            }
        }
        Statement::While(wh) => {
            convert_expression(&mut wh.condition, struct_name, fields, methods, locals, globals);
            let base = locals.len();
            convert_block(&mut wh.block, struct_name, fields, methods, locals, globals);
            locals.truncate(base);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                convert_expression(expr, struct_name, fields, methods, locals, globals);
            }
        }
        Statement::LoopBreak(_) => {}
    }
}

fn convert_expression(expr: &mut Expression, struct_name: &str, fields: &[VariableDef], methods: &[String], locals: &[String], globals: &std::collections::HashSet<String>) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        match e {
            Expression::SymbolRef { id, ty } => {
                if *id == "this" {
                    return;
                }
                if locals.contains(id) {
                    return;
                }
                // Unresolved bare symbol in a struct method: this.<field>.
                // Fields shadow file-scope globals (member-lookup order);
                // checking globals first would silently route field access
                // to the global.
                if fields.iter().any(|f| &f.name == id) {
                    *e = Expression::MemberRef {
                        lhs: Box::new(Expression::ThisRef),
                        name: id.clone(),
                    };
                    return;
                }
                // File-scope globals are visible from struct methods too, and
                // so are struct names: a bare struct name is the receiver of
                // a static call (`File.open(p)` inside another struct).
                if globals.contains(id) {
                    return;
                }
                if ty.is_empty() || ty.to_string() == crate::type_name::AUTO {
                    panic!("Unable to resolve symbol {} in struct {}", id, struct_name);
                }
            }
            Expression::FunctionCall { function, args } => {
                // Convert function calls that are actually method calls.
                if methods.contains(function) {
                    let method = function.clone();
                    let call_args = args.clone();
                    *e = Expression::MethodCall {
                        this: Box::new(Expression::SymbolRef {
                            id: "this".to_string(),
                            ty: TypeName::auto(),
                        }),
                        method,
                        args: call_args,
                    };
                }
            }
            _ => {}
        }
    });
}

pub fn convert_member_refs(module: &mut Module) {
    // Names a bare symbol in a method may resolve to outside the struct:
    // module globals, and struct names (the receiver of a static call).
    let globals: std::collections::HashSet<String> = module
        .globals
        .iter()
        .map(|v| v.name.clone())
        .chain(module.structs.iter().map(|s| s.name.clone()))
        .collect();
    let struct_count = module.structs.len();
    for st_idx in 0..struct_count {
        let (fields, method_names): (Vec<VariableDef>, Vec<String>) = {
            let st = &module.structs[st_idx];
            let fields: Vec<VariableDef> = st
                .field_members
                .iter()
                .filter(|f| f.kind == Kind::Field)
                .cloned()
                .collect();
            let methods: Vec<String> = st.method_members.iter().map(|m| m.name.clone()).collect();
            (fields, methods)
        };
        let st_name = module.structs[st_idx].name.clone();

        // Constructor: params exempt.
        {
            let st = &mut module.structs[st_idx];
            let mut locals: Vec<String> = st.constructor.parameters.iter().map(|p| p.name.clone()).collect();
            if let Some(body) = &mut st.constructor.body {
                convert_block(body, &st_name, &fields, &method_names, &mut locals, &globals);
            }
        }

        // Methods.
        for method_idx in 0..module.structs[st_idx].method_members.len() {
            let st = &mut module.structs[st_idx];
            let mut locals: Vec<String> = st.method_members[method_idx]
                .parameters
                .iter()
                .map(|p| p.name.clone())
                .collect();
            if let Some(body) = &mut st.method_members[method_idx].body {
                convert_block(body, &st_name, &fields, &method_names, &mut locals, &globals);
            }
        }
    }
}
