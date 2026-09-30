//! Resolve type aliases (`type Name<P1, P2=Default> = Target;`) before any
//! other pass: each use of an alias name is expanded into its target with the
//! alias's parameters substituted by the arguments given at the use site
//! (omitted arguments fall back to parameter defaults). Called from
//! `struct_body::apply` — the first pipeline stage after platform filters —
//! so struct synthesis and every transform pass see only real types. After
//! this pass no alias name remains in the model, so codegen needs no alias
//! awareness.

use crate::model::*;
use crate::type_name::{replace_map, TypeName};
use std::collections::{HashMap, HashSet};

/// Hard cap on expansion depth: legitimate chains are short; anything deeper
/// is a cycle the in-flight set should have caught — this is a backstop.
const MAX_EXPANSION_DEPTH: usize = 1024;

pub fn resolve_type_aliases(module: &mut Module) {
    if module.type_aliases.is_empty() {
        return;
    }
    // Later definitions shadow earlier ones (same convention as functions).
    let mut aliases: HashMap<String, &TypeAliasDef> = HashMap::new();
    for def in &module.type_aliases {
        aliases.insert(def.name.clone(), def);
    }
    if report_cycle(module, &aliases) {
        return;
    }

    // Value-symbol names visible at module scope. A name bound to a value
    // (global, function) must not be rewritten as an alias use in call
    // positions even if an alias shares the spelling.
    let mut global_values: HashSet<String> = HashSet::new();
    for var in &module.globals {
        global_values.insert(var.name.clone());
    }
    for function in &module.functions {
        global_values.insert(function.name.clone());
    }

    for var in &mut module.globals {
        subst(&mut var.ty, &aliases);
        if let Some(default) = &mut var.default {
            subst_expr(default, &aliases, &global_values);
        }
    }
    for function in &mut module.functions {
        subst_function(function, &aliases, global_values.clone());
    }
    for st in &mut module.structs {
        for param in &mut st.generic_params {
            if let Some(default) = &mut param.default {
                subst(default, &aliases);
            }
        }
        // Method bodies see the struct's fields as value symbols; field
        // default expressions see globals and the fields themselves.
        let mut struct_values = global_values.clone();
        for field in &st.field_members {
            struct_values.insert(field.name.clone());
        }
        for field in &mut st.field_members {
            subst(&mut field.ty, &aliases);
            if let Some(default) = &mut field.default {
                subst_expr(default, &aliases, &struct_values);
            }
        }
        for method in &mut st.method_members {
            subst_function(method, &aliases, struct_values.clone());
        }
        subst_function(&mut st.constructor, &aliases, struct_values.clone());
        subst_function(&mut st.destructor, &aliases, struct_values.clone());
        subst_function(&mut st.acquire, &aliases, struct_values.clone());
        subst_function(&mut st.release, &aliases, struct_values.clone());
    }
    for trait_def in &mut module.traits {
        for method in &mut trait_def.methods {
            subst_function(method, &aliases, global_values.clone());
        }
    }
    for ext in &mut module.extensions {
        subst(&mut ext.target, &aliases);
        for trait_name in &mut ext.traits {
            subst(trait_name, &aliases);
        }
        for method in &mut ext.methods {
            subst_function(method, &aliases, global_values.clone());
        }
    }
    for extern_function in &mut module.externs {
        subst(&mut extern_function.ty, &aliases);
        for param in &mut extern_function.parameters {
            subst(&mut param.ty, &aliases);
        }
    }
    for spec in &mut module.struct_specs {
        subst(spec, &aliases);
    }
    for spec in &mut module.func_specs {
        subst(spec, &aliases);
    }

    // Aliases are expanded away; the model no longer needs them.
    module.type_aliases.clear();
}

fn subst_function(function: &mut FunctionDef, aliases: &HashMap<String, &TypeAliasDef>, mut values: HashSet<String>) {
    for param in &mut function.generic_params {
        if let Some(default) = &mut param.default {
            subst(default, aliases);
        }
    }
    subst(&mut function.ty, aliases);
    for parameter in &mut function.parameters {
        subst(&mut parameter.ty, aliases);
        values.insert(parameter.name.clone());
    }
    if let Some(body) = &mut function.body {
        collect_value_names(body, &mut values);
        for stmt in &mut body.items {
            subst_stmt(stmt, aliases, &values);
        }
    }
}

/// Collect the names of every variable declared anywhere in a block tree.
/// Deliberately over-approximates scope (visible for the whole function):
/// at worst it skips an alias rewrite, never rewrites a value use.
fn collect_value_names(block: &Block, out: &mut HashSet<String>) {
    for item in &block.items {
        match item {
            Statement::Declaration(Declaration::Variable(var)) => {
                out.insert(var.name.clone());
            }
            Statement::Block(inner) => collect_value_names(inner, out),
            Statement::Branch(branch) => {
                collect_value_names(&branch.if_block, out);
                if let Some(else_block) = &branch.else_block {
                    collect_value_names(else_block, out);
                }
            }
            Statement::While(while_stmt) => collect_value_names(&while_stmt.block, out),
            _ => {}
        }
    }
}

fn subst_stmt(stmt: &mut Statement, aliases: &HashMap<String, &TypeAliasDef>, values: &HashSet<String>) {
    match stmt {
        Statement::Expression(expr) => subst_expr(expr, aliases, values),
        Statement::Block(block) => {
            for item in &mut block.items {
                subst_stmt(item, aliases, values);
            }
        }
        Statement::Declaration(Declaration::Variable(var)) => {
            subst(&mut var.ty, aliases);
            if let Some(default) = &mut var.default {
                subst_expr(default, aliases, values);
            }
        }
        Statement::Branch(branch) => {
            subst_expr(&mut branch.condition, aliases, values);
            for item in &mut branch.if_block.items {
                subst_stmt(item, aliases, values);
            }
            if let Some(else_block) = &mut branch.else_block {
                for item in &mut else_block.items {
                    subst_stmt(item, aliases, values);
                }
            }
        }
        Statement::While(while_stmt) => {
            subst_expr(&mut while_stmt.condition, aliases, values);
            for item in &mut while_stmt.block.items {
                subst_stmt(item, aliases, values);
            }
        }
        Statement::Return(return_stmt) => {
            if let Some(expr) = &mut return_stmt.expr {
                subst_expr(expr, aliases, values);
            }
        }
        Statement::LoopBreak(_) => {}
        _ => {}
    }
}

/// Every expression variant that carries a type name. `values` holds the
/// names of value symbols visible in the current scope; call-position
/// rewrites below must not touch a name bound to a value.
fn subst_expr(expr: &mut Expression, aliases: &HashMap<String, &TypeAliasDef>, values: &HashSet<String>) {
    match expr {
        Expression::SymbolRef { ty, .. } => subst(ty, aliases),
        Expression::ThisRef
        | Expression::BoolLiteral(_)
        | Expression::FloatLiteral(_)
        | Expression::IntLiteral(_)
        | Expression::StringLiteral { .. }
        | Expression::PointerLiteral => {}
        Expression::MemberRef { lhs, .. }
        | Expression::ForIterator(lhs)
        | Expression::WithEntered(lhs)
        | Expression::Destructure { value: lhs, .. } => subst_expr(lhs, aliases, values),
        Expression::MatchArm(test) => {
            subst_expr(&mut test.subject, aliases, values);
            for p in &mut test.patterns {
                if let Some(q) = &mut p.qualifier {
                    subst(q, aliases);
                }
            }
        }
        Expression::MakeClosure { value, ty, .. } => {
            subst(ty, aliases);
            subst_expr(value, aliases, values);
        }
        Expression::CallPointer { pointer, args } => {
            subst_expr(pointer, aliases, values);
            for arg in args {
                subst_expr(arg, aliases, values);
            }
        }
        // Lifted before aliases resolve.
        Expression::ClosureLiteral(_) | Expression::MethodAddress(_) => {}
        Expression::Binary { lhs, rhs, .. } => {
            subst_expr(lhs, aliases, values);
            subst_expr(rhs, aliases, values);
        }
        Expression::Unary { operand, .. } => subst_expr(operand, aliases, values),
        Expression::ToTrait {
            value, from, to, ..
        } => {
            subst_expr(value, aliases, values);
            subst(from, aliases);
            subst(to, aliases);
        }
        Expression::Cast {
            expr: inner, ty, ..
        } => {
            subst_expr(inner, aliases, values);
            subst(ty, aliases);
        }
        Expression::Ternary {
            condition,
            true_expr,
            false_expr,
        } => {
            subst_expr(condition, aliases, values);
            subst_expr(true_expr, aliases, values);
            subst_expr(false_expr, aliases, values);
        }
        Expression::Index { lhs, rhs, .. } => {
            subst_expr(lhs, aliases, values);
            subst_expr(rhs, aliases, values);
        }
        Expression::ArrayIndex { ty, lhs, rhs, .. } => {
            subst(ty, aliases);
            subst_expr(lhs, aliases, values);
            subst_expr(rhs, aliases, values);
        }
        Expression::SizeOf(ty) | Expression::IsPod(ty) | Expression::Default(ty) | Expression::Allocate(ty) => subst(ty, aliases),
        Expression::CountStep { .. } => {}
        Expression::FunctionPointer { owner, .. } => {
            if let Some(owner) = owner {
                subst(owner, aliases);
            }
        }
        Expression::RefCount(ty, operand) | Expression::Address(ty, operand) | Expression::Weak(_, ty, operand) => {
            subst(ty, aliases);
            subst_expr(operand, aliases, values);
        }
        Expression::AtomicLoad(ty, operand) => {
            subst(ty, aliases);
            subst_expr(operand, aliases, values);
        }
        Expression::AtomicStore(ty, lhs, rhs) => {
            subst(ty, aliases);
            subst_expr(lhs, aliases, values);
            subst_expr(rhs, aliases, values);
        }
        Expression::AtomicCmpXchg(ty, lhs, mid, rhs) => {
            subst(ty, aliases);
            subst_expr(lhs, aliases, values);
            subst_expr(mid, aliases, values);
            subst_expr(rhs, aliases, values);
        }
        Expression::AtomicFetch(_, ty, lhs, rhs) => {
            subst(ty, aliases);
            subst_expr(lhs, aliases, values);
            subst_expr(rhs, aliases, values);
        }
        Expression::FunctionCall { function, args, .. } => {
            // Type positions are encoded into the call string (static calls
            // like `Result<int>.ok(..)` and explicit generic args `g<I>(..)`).
            // Generic arguments are always type positions; the base name is a
            // type position only when no value symbol (e.g. a free function)
            // owns its spelling — codegen resolves free functions first too.
            let mut parsed = crate::passes::gather_generics::parse_type_string(function);
            for sub in &mut parsed.sub_types {
                subst(sub, aliases);
            }
            if aliases.contains_key(&parsed.name) && !values.contains(&parsed.name) {
                subst(&mut parsed, aliases);
            }
            *function = parsed.to_string();
            for arg in args {
                subst_expr(arg, aliases, values);
            }
        }
        Expression::MethodCall { this, args, .. } => {
            // A bare alias name as a static-call receiver (`Pair.ok(..)`)
            // arrives as a SymbolRef; rewrite it to the ctor-style call form
            // codegen resolves (`Result<int, Error>`). Skipped when a value
            // symbol owns the name — `S.m()` on a variable `S` is not an
            // alias use.
            if let Expression::SymbolRef { id, loc, .. } = this.as_ref() {
                if aliases.contains_key(id) && !values.contains(id) {
                    let mut expanded = TypeName::new(id);
                    subst(&mut expanded, aliases);
                    *this = Box::new(Expression::FunctionCall {
                        function: expanded.to_string(),
                        args: vec![],
                        loc: *loc,
                    });
                }
            }
            subst_expr(this, aliases, values);
            for arg in args {
                subst_expr(arg, aliases, values);
            }
        }
        Expression::FunctionRef { ty, .. } => subst(ty, aliases),
        Expression::Invoke { callee, args } => {
            subst_expr(callee, aliases, values);
            for arg in args {
                subst_expr(arg, aliases, values);
            }
        }
    }
}

/// Report the first alias (in declaration order) whose target refers back to
/// it, at its name, with a note at each alias the cycle passes through.
/// Returns whether a cycle was found; expansion is then skipped, since every
/// use of the cycle would report it again.
fn report_cycle(module: &Module, aliases: &HashMap<String, &TypeAliasDef>) -> bool {
    fn names<'a>(ty: &'a TypeName, out: &mut Vec<&'a str>) {
        out.push(&ty.name);
        for arg in &ty.sub_types {
            names(arg, out);
        }
    }
    // Depth-first from `name`, with `path` the aliases on the way; returns
    // the cycle back to `path[0]` if there is one.
    fn find<'a>(
        name: &'a str,
        aliases: &HashMap<String, &'a TypeAliasDef>,
        path: &mut Vec<&'a str>,
        done: &mut HashSet<&'a str>,
    ) -> bool {
        let Some(def) = aliases.get(name) else { return false };
        let mut targets = vec![];
        names(&def.target, &mut targets);
        for next in targets {
            if next == path[0] {
                return true;
            }
            if !aliases.contains_key(next) || path.contains(&next) || done.contains(next) {
                continue;
            }
            path.push(next);
            if find(next, aliases, path, done) {
                return true;
            }
            path.pop();
            done.insert(next);
        }
        false
    }
    for def in &module.type_aliases {
        let mut path = vec![def.name.as_str()];
        if find(&def.name, aliases, &mut path, &mut HashSet::new()) {
            let mut error = Diagnostic::error(format!("type alias '{}' refers to itself", def.name)).at(def.loc);
            for through in &path[1..] {
                let loc = aliases[*through].loc;
                error = error.with_note(format!("through type alias '{}', declared here", through), Some(loc));
            }
            crate::errors::report(error);
            return true;
        }
    }
    false
}

/// An error in a use of `def`. Type names carry no location, so it points
/// at the alias's declaration.
fn alias_error(def: &TypeAliasDef, message: String) -> Diagnostic {
    Diagnostic::error(message).with_note(format!("type alias '{}' declared here", def.name), Some(def.loc))
}

/// Expand one type name (and its nested arguments) to a non-alias type.
fn subst(ty: &mut TypeName, aliases: &HashMap<String, &TypeAliasDef>) {
    let mut inflight = HashSet::new();
    expand_node(ty, aliases, &mut inflight, 0);
}

/// Expand `ty` in place. `inflight` holds the strings currently being expanded
/// on this descent path: re-entering one means the alias graph is recursive.
fn expand_node(ty: &mut TypeName, aliases: &HashMap<String, &TypeAliasDef>, inflight: &mut HashSet<String>, depth: usize) {
    if depth > MAX_EXPANSION_DEPTH {
        crate::errors::report(Diagnostic::error(format!("type alias expansion too deep for '{}'", ty)));
        return;
    }
    // Nested arguments first; each is expanded independently.
    for arg in &mut ty.sub_types {
        expand_node(arg, aliases, inflight, depth + 1);
    }
    let Some(def) = aliases.get(&ty.name) else {
        return;
    };
    if ty.sub_types.len() > def.generic_params.len() {
        crate::errors::report(alias_error(
            def,
            format!(
                "type alias '{}' takes {} type argument(s), {} given",
                def.name,
                def.generic_params.len(),
                ty.sub_types.len()
            ),
        ));
        return;
    }
    let mut map: Vec<(String, TypeName)> = vec![];
    for (i, param) in def.generic_params.iter().enumerate() {
        let arg = if i < ty.sub_types.len() {
            ty.sub_types[i].clone()
        } else if let Some(default) = &param.default {
            default.clone()
        } else {
            crate::errors::report(alias_error(
                def,
                format!("type alias '{}' requires a type argument for parameter '{}'", def.name, param.name),
            ));
            return;
        };
        map.push((param.name.clone(), arg));
    }

    let current = ty.to_string();
    if !inflight.insert(current.clone()) {
        crate::errors::report(alias_error(def, format!("type alias '{}' is recursive: '{}'", def.name, current)));
        return;
    }
    let mut next = def.target.clone();
    replace_map(&mut next, &map);
    *ty = next;
    expand_node(ty, aliases, inflight, depth + 1);
    inflight.remove(&current);
}
