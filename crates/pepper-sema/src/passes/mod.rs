//! Transform passes: port of `source/Sema/Transform.cpp:20-53` — one
//! `fn run(module, symbols)` per pass, in the exact C++ order. Silent (no
//! debug tracing).

use crate::model::*;
use crate::symbols::SymbolTable;
use crate::type_name::{self, TypeName};
use std::mem;

pub mod resolve_literals;
pub mod resolve_type_aliases;
pub mod tag_generics;
pub mod convert_string_literals;
pub mod gather_generics;
pub mod resolve_implicit_types;
pub mod resolve_resolvables;
pub mod apply_extensions;
pub mod specialize_structs;
pub mod specialize_functions;
pub mod convert_intrinsics;
pub mod convert_member_refs;
pub mod resolve_operators;
pub mod release_field_refs;
pub mod convert_print_calls;
pub mod platform;
pub mod function_types;
pub mod check_function_types;
pub mod check_bindings;
pub mod lower_with_blocks;

use apply_extensions::apply_extensions;
use convert_member_refs::convert_member_refs;
use convert_intrinsics::convert_intrinsics;
use convert_string_literals::convert_string_literals;
use gather_generics::gather_generics;
use release_field_refs::release_field_refs;
use resolve_literals::resolve_literals;
use resolve_implicit_types::resolve_implicit_types;
use resolve_operators::resolve_operators;
use resolve_resolvables::resolve_resolvables;
use specialize_functions::specialize_functions;
use specialize_structs::specialize_structs;
use tag_generics::tag_generics;
use convert_print_calls::convert_print_calls;
use function_types::synthesize_function_types;
use lower_with_blocks::lower_with_blocks;

/// Run every pass in the ported order (25 entries, repeats included),
/// stopping at the first pass that reports an error.
pub fn transform_pass(module: &mut Module) -> Result<(), Diagnostic> {
    // A pass that reports an error leaves the model partly unresolved, so
    // later passes would only trip over it.
    macro_rules! step {
        ($pass:expr) => {{
            $pass;
            if let Some(error) = crate::errors::take() {
                return Err(error);
            }
        }};
    }
    crate::errors::take(); // each run starts fresh
    apply_extensions::reset_applied(); // each run starts fresh (set is process-global)
    // First pass
    step!(check_bindings::check_bindings(module));
    step!(synthesize_function_types(module));
    step!(resolve_literals(module));
    step!(tag_generics(module));
    step!(convert_string_literals(module));
    step!(gather_generics(module));
    step!(resolve_implicit_types(module));
    step!(resolve_resolvables(module, false)); // resolve as much as possible
    step!(apply_extensions(module, false)); // apply generic/concrete extensions
    step!(specialize_structs(module));
    step!(specialize_functions(module));
    step!(synthesize_function_types(module));
    step!(convert_intrinsics(module));
    step!(resolve_resolvables(module, false)); // resolve what remains
    step!(apply_extensions(module, true)); // apply specialized extensions
    step!(convert_member_refs(module));
    step!(resolve_implicit_types(module));
    step!(resolve_operators(module));

    // Second pass, resolve dependent types/calls. Specializing can expose
    // further generic uses (`Map<String, int>` → field `Array<String>` →
    // `Array<String>.iterate()` returning `ArrayIterator<String>`), so repeat
    // until no new specialization appears. Bounded, since a type that nests
    // itself (`Foo<T>` holding a `Foo<Array<T>>`) never reaches a fixpoint.
    for _ in 0..16 {
        let before = (module.structs.len(), module.functions.len());
        step!(gather_generics(module));
        step!(specialize_structs(module));
        step!(specialize_functions(module));
        if (module.structs.len(), module.functions.len()) == before {
            break;
        }
    }
    step!(convert_intrinsics(module));
    step!(resolve_resolvables(module, false));
    step!(convert_member_refs(module));
    step!(synthesize_function_types(module));

    // final pass
    step!(release_field_refs(module));
    step!(resolve_implicit_types(module));
    step!(resolve_operators(module)); // once implicit types are resolved, operator overloading may exist
    step!(convert_print_calls(module));
    step!(resolve_resolvables(module, true));
    // Types inferred by the final resolve (e.g. `var f = square;`).
    step!(synthesize_function_types(module));
    step!(check_function_types::check_function_types(module));
    // `with` conditions need the final types of `enter()`.
    step!(lower_with_blocks(module));
    Ok(())
}

// ── Shared walk helpers ──────────────────────────────────────────────────────

/// Apply `f` to every expression in a block, in place.
pub fn walk_block(block: &mut Block, f: &mut impl FnMut(&mut Expression)) {
    for stmt in &mut block.items {
        walk_statement(stmt, f);
    }
}

pub fn walk_statement(stmt: &mut Statement, f: &mut impl FnMut(&mut Expression)) {
    match stmt {
        Statement::Expression(expr) => walk_expression(expr, f),
        Statement::Block(inner) => walk_block(inner, f),
        Statement::Declaration(Declaration::Variable(var)) => {
            if let Some(default) = &mut var.default {
                walk_expression(default, f);
            }
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            walk_expression(&mut branch.condition, f);
            walk_block(&mut branch.if_block, f);
            if let Some(else_block) = &mut branch.else_block {
                walk_block(else_block, f);
            }
        }
        Statement::While(wh) => {
            walk_expression(&mut wh.condition, f);
            walk_block(&mut wh.block, f);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                walk_expression(expr, f);
            }
        }
        Statement::LoopBreak(_) => {}
    }
}

pub fn walk_expression(expr: &mut Expression, f: &mut impl FnMut(&mut Expression)) {
    f(expr);
    match expr {
        Expression::SymbolRef { .. } | Expression::ThisRef => {}
        Expression::MemberRef { lhs, .. } => walk_expression(lhs, f),
        Expression::BoolLiteral(_)
        | Expression::IntLiteral(_)
        | Expression::FloatLiteral(_)
        | Expression::StringLiteral { .. }
        | Expression::PointerLiteral => {}
        Expression::Binary { lhs, rhs, .. } => {
            walk_expression(lhs, f);
            walk_expression(rhs, f);
        }
        Expression::Unary { operand, .. } => walk_expression(operand, f),
        Expression::Cast { expr, .. } => walk_expression(expr, f),
        Expression::Ternary {
            condition,
            true_expr,
            false_expr,
        } => {
            walk_expression(condition, f);
            walk_expression(true_expr, f);
            walk_expression(false_expr, f);
        }
        Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
            walk_expression(lhs, f);
            walk_expression(rhs, f);
        }
        Expression::SizeOf(_) | Expression::IsPod(_) | Expression::Default(_) => {}
        Expression::RefCount(_, arg) | Expression::Address(_, arg) => walk_expression(arg, f),
        Expression::AtomicLoad(_, arg) => walk_expression(arg, f),
        Expression::AtomicStore(_, ptr, val) => {
            walk_expression(ptr, f);
            walk_expression(val, f);
        }
        Expression::AtomicCmpXchg(_, ptr, expected, desired) => {
            walk_expression(ptr, f);
            walk_expression(expected, f);
            walk_expression(desired, f);
        }
        Expression::AtomicFetch(_, _, ptr, val) => {
            walk_expression(ptr, f);
            walk_expression(val, f);
        }
        Expression::FunctionCall { args, .. } => {
            for arg in args {
                walk_expression(arg, f);
            }
        }
        Expression::MethodCall { this, args, .. } => {
            walk_expression(this, f);
            for arg in args {
                walk_expression(arg, f);
            }
        }
        Expression::FunctionRef { .. } => {}
        Expression::Invoke { callee, args } => {
            walk_expression(callee, f);
            for arg in args {
                walk_expression(arg, f);
            }
        }
        Expression::ForIterator(source) | Expression::WithEntered(source) => walk_expression(source, f),
    }
}

/// Apply `f` to every expression inside a function body.
pub fn walk_function(function: &mut FunctionDef, f: &mut impl FnMut(&mut Expression)) {
    if let Some(body) = &mut function.body {
        walk_block(body, f);
    }
}

/// Apply `f` to a global variable's default initializer (if any).
pub fn walk_global(var: &mut VariableDef, f: &mut impl FnMut(&mut Expression)) {
    if let Some(default) = &mut var.default {
        walk_expression(default, f);
    }
}

/// Replace `expr` with the value `f` returns, continuing on the replacement.
pub fn replace_expression(expr: &mut Expression, f: &mut impl FnMut(&mut Expression)) {
    let old = mem::replace(expr, Expression::PointerLiteral);
    *expr = old;
    f(expr);
}
