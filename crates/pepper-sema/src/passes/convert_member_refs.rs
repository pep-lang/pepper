//! Port of `source/Sema/ConvertMemberRefs.h`: bare unresolved symbols in
//! struct methods become `this.<field>`; plain calls matching a method become
//! method calls (on `this`, or on the struct for a static method, as
//! `S.f()` would be written); params exempt.

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
        Statement::LoopBreak(_) | Statement::Static(_) => {}
    }
}

fn convert_expression(expr: &mut Expression, struct_name: &str, fields: &[VariableDef], methods: &[String], locals: &[String], globals: &std::collections::HashSet<String>) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        match e {
            Expression::SymbolRef { id, ty, loc } => {
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
                        loc: *loc,
                    };
                    return;
                }
                // File-scope globals are visible from struct methods too, and
                // so are struct names: a bare struct name is the receiver of
                // a static call (`File.open(p)` inside another struct).
                if globals.contains(id) {
                    return;
                }
                if ty.is_empty() || ty.is_auto() {
                    crate::errors::report(
                        Diagnostic::error(format!("use of undeclared identifier '{}' in a method of '{}'", id, struct_name))
                            .at(*loc),
                    );
                }
            }
            Expression::FunctionCall { function, args, loc } => {
                // Convert function calls that are actually method calls. A
                // static method is called on the struct, so a static
                // method can call another by its bare name (there is no
                // `this` there). A converted string literal constructs the
                // `String` type even beside a method (or enum case) named
                // `String`.
                if methods.contains(function) && !crate::passes::convert_string_literals::is_converted_literal(function, args, *loc) {
                    let method = function.clone();
                    let call_args = args.clone();
                    // A sibling static is called on the struct's name; any
                    // other method on `this` as written (`ThisRef`), so the
                    // receiver types as the enclosing struct: an untyped
                    // `this` symbol left the call's type unknown, and an
                    // operator on it (`label() + label()`) never resolved to
                    // its overload.
                    let receiver = if methods.contains(&format!("{}{}", STATIC_MARK, function)) {
                        // A generic base has no name to call on; its
                        // specializations, copied from it, convert the call.
                        if methods.contains(&GENERIC_BASE.to_string()) {
                            return;
                        }
                        Expression::SymbolRef { id: struct_name.to_string(), ty: TypeName::auto(), loc: Loc::NONE }
                    } else {
                        Expression::ThisRef
                    };
                    *e = Expression::MethodCall {
                        this: Box::new(receiver),
                        method,
                        args: call_args,
                        loc: *loc,
                    };
                }
            }
            _ => {}
        }
    });
}

/// Marks a static method's name in the method list [`convert_expression`]
/// is given; no identifier contains it.
const STATIC_MARK: &str = "static ";

/// In the method list, marks a generic base struct (`Array` of `Array<T>`).
const GENERIC_BASE: &str = "generic base";

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
        // Only bodies change (a checked runtime's are stashed).
        let st = &module.structs[st_idx];
        if st.constructors.iter().chain(&st.method_members).all(|f| f.body.is_none()) {
            continue;
        }
        let (fields, method_names): (Vec<VariableDef>, Vec<String>) = {
            let st = &module.structs[st_idx];
            let fields: Vec<VariableDef> = st
                .field_members
                .iter()
                .filter(|f| f.kind == Kind::Field)
                .cloned()
                .collect();
            // An overloaded method is also called by its set's name. A static
            // method's names are listed again behind `STATIC_MARK`.
            let mut methods: Vec<String> = st
                .method_members
                .iter()
                .flat_map(|m| [m.name.clone(), crate::passes::overloads::set_name(&m.name).to_string()])
                .collect();
            let statics: Vec<String> = st
                .method_members
                .iter()
                .filter(|m| m.is_static)
                .flat_map(|m| [m.name.clone(), crate::passes::overloads::set_name(&m.name).to_string()])
                .map(|name| format!("{}{}", STATIC_MARK, name))
                .collect();
            methods.extend(statics);
            if !st.generic_params.is_empty() {
                methods.push(GENERIC_BASE.to_string());
            }
            (fields, methods)
        };
        // A bare property whose storage is not a field of its name (see
        // `passes::properties`) is `this.p` too, which the next
        // `resolve_implicit_types` rewrites.
        let fields = {
            let mut fields = fields;
            let st = &module.structs[st_idx];
            for property in module.properties.iter().filter(|p| p.owner == st.ty.name && !p.in_trait) {
                if !fields.iter().any(|f| f.name == property.name) {
                    fields.push(VariableDef {
                        name: property.name.clone(),
                        ty: TypeName::auto(),
                        default: None,
                        hidden: true,
                        kind: Kind::Field,
                        attributes: vec![],
                        loc: property.loc,
                        type_loc: Loc::NONE,
                        is_const: false,
                    });
                }
            }
            fields
        };
        let st_name = module.structs[st_idx].name.clone();
        // A generic base's own type parameters name types, not members: the
        // receiver of a static call through one (`T.zero()`), which each
        // specialization rewrites to its type argument.
        let type_params: Vec<String> = module.structs[st_idx]
            .generic_params
            .iter()
            .map(|p| p.name.clone())
            .filter(|p| !fields.iter().any(|f| f.name == *p))
            .collect();

        // Constructor: params exempt.
        {
            let st = &mut module.structs[st_idx];
            for c in &mut st.constructors {
                let mut locals: Vec<String> = c.parameters.iter().map(|p| p.name.clone()).chain(type_params.iter().cloned()).collect();
                if let Some(body) = &mut c.body {
                    convert_block(body, &st_name, &fields, &method_names, &mut locals, &globals);
                }
            }
        }

        // Methods.
        for method_idx in 0..module.structs[st_idx].method_members.len() {
            let st = &mut module.structs[st_idx];
            if st.method_members[method_idx].body.is_none() {
                continue;
            }
            let mut locals: Vec<String> = st.method_members[method_idx]
                .parameters
                .iter()
                .map(|p| p.name.clone())
                .chain(type_params.iter().cloned())
                .collect();
            // A trait's default method sees only the trait: its methods, on
            // `this`, and no fields. What its author wrote could not name
            // members a conforming struct happens to have.
            let (fields, method_names) = match &st.method_members[method_idx].trait_default {
                Some(trait_methods) => (vec![], trait_methods.clone()),
                None => (fields.clone(), method_names.clone()),
            };
            if let Some(body) = &mut st.method_members[method_idx].body {
                convert_block(body, &st_name, &fields, &method_names, &mut locals, &globals);
            }
        }
    }
}
