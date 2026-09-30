//! Transform passes: port of `source/Sema/Transform.cpp:20-53` — one
//! `fn run(module, symbols)` per pass, in the exact C++ order. Silent (no
//! debug tracing).

use crate::model::*;
use std::mem;

pub mod resolve_literals;
pub mod resolve_type_aliases;
pub mod overloads;
pub mod convert_string_literals;
pub mod gather_generics;
pub mod check_shared_types;
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
pub mod check_deprecated_members;
pub mod lower_with_blocks;
pub mod weak_types;
pub mod closures;
pub mod function_references;
pub mod generic_methods;
pub mod type_arguments;
pub mod convert_to_traits;
pub mod shared_functions;
pub mod tuples;
pub mod copies;

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
use convert_print_calls::convert_print_calls;
use function_types::synthesize_function_types;
use lower_with_blocks::lower_with_blocks;

/// Run every pass in order (repeats included),
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
    // Enum cases (`Color.Red`) before anything infers a type from them.
    step!(crate::enums::resolve_enum_cases(module));
    step!(check_bindings::check_bindings(module));
    step!(synthesize_function_types(module));
    step!(resolve_literals(module));
    step!(overloads::name_overloads(module));
    step!(convert_string_literals(module));
    step!(gather_generics(module));
    step!(resolve_implicit_types(module));
    step!(resolve_resolvables(module, false)); // resolve as much as possible
    step!(apply_extensions(module, false)); // apply generic/concrete extensions
    step!(specialize_structs(module));
    step!(specialize_functions(module));
    step!(generic_methods::specialize_methods(module));
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
        // A generic method call on a value whose type the round just
        // specialized (`c.map(f)` with `c: Box<long>`) is typed, and its type
        // arguments inferred, only now.
        // Likewise a call to an overloaded function whose arguments the
        // round just typed (`f(x)` with `x: T`, now `int`).
        if generic_methods::has_generic_methods(module) || !module.overload_sets.is_empty() || !module.method_overload_sets.is_empty() {
            step!(resolve_implicit_types(module));
        }
        let methods_added = generic_methods::specialize_methods(module);
        // `copy` of a type whose specialization just appeared: its `_pep_copy`
        // methods call `copies.copy<F>` for each field, specialized next round.
        let copies_added = copies::synthesize_copies(module);
        if let Some(error) = crate::errors::take() {
            return Err(error);
        }
        if (module.structs.len(), module.functions.len()) == before && !methods_added && !copies_added {
            break;
        }
    }
    step!(convert_intrinsics(module));
    step!(resolve_resolvables(module, false));
    step!(convert_member_refs(module));
    step!(synthesize_function_types(module));

    // final pass
    // Methods, constructors and generic functions used as values, once every
    // type is known; before `release_field_refs`, which releases a bound
    // method's receiver.
    step!(function_references::reference_functions(module));
    step!(release_field_refs(module));
    step!(resolve_implicit_types(module));
    step!(type_arguments::check_type_arguments(module));
    step!(overloads::check_overloads(module));
    step!(resolve_operators(module)); // once implicit types are resolved, operator overloading may exist
    step!(convert_print_calls(module));
    step!(resolve_resolvables(module, true));
    // Destructurings, once the tuples they read are typed.
    step!(tuples::lower_destructures(module));
    // Types inferred by the final resolve (e.g. `var f = square;`).
    step!(synthesize_function_types(module));
    step!(closures::check_closures(module));
    // Plain and `shared` function values flowing into each other's slots,
    // once every type is final.
    step!(shared_functions::shared_functions(module));
    step!(synthesize_function_types(module));
    // Struct values flowing into trait-typed slots, once every type is final.
    step!(convert_to_traits::convert_to_traits(module));
    step!(check_function_types::check_function_types(module));
    step!(check_shared_types::check_shared_types(module));
    // `with` conditions need the final types of `enter()`.
    step!(lower_with_blocks(module));
    // `match` arms need the final type of the value matched.
    step!(crate::enums::lower_matches(module));
    // Warnings only: uses of deprecated fields and methods, by final type.
    step!(check_deprecated_members::check_deprecated_members(module));
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
        Expression::SizeOf(_) | Expression::IsPod(_) | Expression::Default(_) | Expression::Allocate(_) => {}
        Expression::CountStep { .. } | Expression::FunctionPointer { .. } => {}
        Expression::RefCount(_, arg) | Expression::Address(_, arg) | Expression::Weak(_, _, arg) => walk_expression(arg, f),
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
        Expression::Destructure { value, .. } => walk_expression(value, f),
        Expression::MatchArm(test) => walk_expression(&mut test.subject, f),
        Expression::ClosureLiteral(closure) => walk_block(&mut closure.body, f),
        Expression::MakeClosure { value, .. } => walk_expression(value, f),
        Expression::ToTrait { value, .. } => walk_expression(value, f),
        Expression::MethodAddress(_) => {}
        Expression::CallPointer { pointer, args } => {
            walk_expression(pointer, f);
            for arg in args {
                walk_expression(arg, f);
            }
        }
    }
}

/// The direct sub-expressions of `expr`, for walks that need to decide per
/// node whether to descend (a closure literal's body is a block, not listed).
pub fn children_mut(expr: &mut Expression) -> Vec<&mut Expression> {
    match expr {
        Expression::SymbolRef { .. }
        | Expression::ThisRef
        | Expression::BoolLiteral(_)
        | Expression::IntLiteral(_)
        | Expression::FloatLiteral(_)
        | Expression::StringLiteral { .. }
        | Expression::PointerLiteral
        | Expression::SizeOf(_)
        | Expression::IsPod(_)
        | Expression::Default(_)
        | Expression::Allocate(_)
        | Expression::FunctionRef { .. }
        | Expression::MethodAddress(_)
        | Expression::CountStep { .. }
        | Expression::FunctionPointer { .. }
        | Expression::ClosureLiteral(_) => vec![],
        Expression::MemberRef { lhs, .. } => vec![lhs.as_mut()],
        Expression::Binary { lhs, rhs, .. }
        | Expression::Index { lhs, rhs, .. }
        | Expression::ArrayIndex { lhs, rhs, .. } => vec![lhs.as_mut(), rhs.as_mut()],
        Expression::Unary { operand, .. } => vec![operand.as_mut()],
        Expression::Cast { expr, .. } => vec![expr.as_mut()],
        Expression::Ternary { condition, true_expr, false_expr } => {
            vec![condition.as_mut(), true_expr.as_mut(), false_expr.as_mut()]
        }
        Expression::RefCount(_, arg)
        | Expression::Address(_, arg)
        | Expression::Weak(_, _, arg)
        | Expression::AtomicLoad(_, arg)
        | Expression::ForIterator(arg)
        | Expression::WithEntered(arg) => vec![arg.as_mut()],
        Expression::MatchArm(test) => vec![&mut test.subject],
        Expression::AtomicStore(_, ptr, val) | Expression::AtomicFetch(_, _, ptr, val) => vec![ptr.as_mut(), val.as_mut()],
        Expression::AtomicCmpXchg(_, ptr, expected, desired) => vec![ptr.as_mut(), expected.as_mut(), desired.as_mut()],
        Expression::FunctionCall { args, .. } => args.iter_mut().collect(),
        Expression::MethodCall { this, args, .. } => {
            let mut children = vec![this.as_mut()];
            children.extend(args.iter_mut());
            children
        }
        Expression::Invoke { callee, args } => {
            let mut children = vec![callee.as_mut()];
            children.extend(args.iter_mut());
            children
        }
        Expression::CallPointer { pointer, args } => {
            let mut children = vec![pointer.as_mut()];
            children.extend(args.iter_mut());
            children
        }
        Expression::MakeClosure { value, .. }
        | Expression::ToTrait { value, .. }
        | Expression::Destructure { value, .. } => vec![value.as_mut()],
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
