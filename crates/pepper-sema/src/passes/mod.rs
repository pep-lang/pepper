//! Transform passes: port of `source/Sema/Transform.cpp:20-53` — one
//! `fn run(module, symbols)` per pass, in the exact C++ order. Silent (no
//! debug tracing).

use crate::model::*;
use std::mem;

/// The intrinsic `__caller_location()`: a `__ptr<char>` holding
/// `file:line:col`. As a parameter's default it is the location of the call
/// that left the argument out, which is how `assert`, `panic` and the
/// runtime's checking methods report where they were called (#354).
pub const CALLER_LOCATION: &str = "__caller_location";

/// The runtime's directory, found on first use, to tell which files are
/// part of the runtime.
#[derive(Default)]
pub struct RuntimeDirectory(std::cell::OnceCell<Option<std::path::PathBuf>>);

impl RuntimeDirectory {
    /// Whether `file` is part of the runtime (under the discovered runtime
    /// directory). With no runtime or no source to compare with (a harness
    /// that registers none), everything is.
    pub fn contains(&self, module: &Module, file: pepper_parser::diagnostic::FileId) -> bool {
        use pepper_parser::diagnostic::Sources;
        let directory = self.0.get_or_init(|| {
            let (sources, _, _) = pepper_files::runtime::discover();
            sources.first().and_then(|s| s.parent()).and_then(|d| d.canonicalize().ok())
        });
        match (directory, module.sources.get(file)) {
            (Some(directory), Some((name, _))) => {
                std::path::Path::new(name).canonicalize().is_ok_and(|path| path.starts_with(directory.as_path()))
            }
            (Some(_), None) | (None, _) => true,
        }
    }
}

pub mod entry_point;
pub mod resolve_literals;
pub mod resolve_type_aliases;
pub mod overloads;
pub mod ranges;
pub mod convert_string_literals;
pub mod gather_generics;
pub mod constraints;
pub mod check_bounds;
pub mod check_shared_types;
pub mod check_tries;
pub mod resolve_implicit_types;
pub mod resolve_resolvables;
pub mod apply_extensions;
pub mod specialize_structs;
pub mod specialize_functions;
pub mod convert_intrinsics;
pub mod convert_member_refs;
pub mod resolve_operators;
pub mod unary_operators;
pub mod release_field_refs;
pub mod platform;
pub mod function_types;
pub mod check_function_types;
pub mod check_bindings;
pub mod check_casts;
pub mod check_deprecated_members;
pub mod check_hash_keys;
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
pub mod strip_bodies;
pub mod check_confinement;
pub mod interpolation;
pub mod properties;
pub mod named_arguments;
pub mod static_blocks;

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
use function_types::synthesize_function_types;
use lower_with_blocks::lower_with_blocks;

/// Run every pass in order (repeats included),
/// stopping at the first pass that reports an error.
pub fn transform_pass(module: &mut Module) -> Result<(), Diagnostic> {
    // A pass that reports an error leaves the model partly unresolved, so
    // later passes would only trip over it.
    macro_rules! step {
        ($pass:expr) => {{
            let started = std::time::Instant::now();
            $pass;
            crate::pass_timer::record(stringify!($pass), started);
            if let Some(error) = crate::errors::take() {
                return Err(error);
            }
        }};
    }
    crate::errors::take(); // each run starts fresh
    apply_extensions::reset_applied(); // each run starts fresh (set is process-global)
    // First pass
    // Attributes name a built-in attribute or an `[Attribute]` struct.
    step!(static_blocks::check_attributes(module));
    // Module-scope `static` blocks set their constants' initializers.
    step!(static_blocks::expand_module_blocks(module));
    // `static` blocks in concrete code, before the passes lower what they
    // emit; those in generic code wait for their specializations.
    step!(static_blocks::expand(module, false));
    // Enum cases (`Color.Red`) before anything infers a type from them.
    step!(crate::enums::resolve_enum_cases(module));
    // `main(args: String[])` becomes a `main()` that passes the arguments.
    step!(entry_point::lower_main_arguments(module));
    step!(check_bindings::check_bindings(module));
    // Named arguments to calls a name decides, before anything reads
    // arguments by position.
    step!(named_arguments::check_attributes(module));
    step!(check_link_attributes(module));
    step!(named_arguments::bind_calls(module));
    step!(synthesize_function_types(module));
    step!(resolve_literals(module));
    step!(overloads::name_overloads(module));
    step!(convert_string_literals(module));
    step!(gather_generics(module));
    step!(resolve_implicit_types(module));
    // Each `?`'s operand and function, before its lowered calls resolve.
    step!(check_tries::check_tries(module));
    step!(resolve_resolvables(module, false)); // resolve as much as possible
    step!(apply_extensions(module, false)); // apply generic/concrete extensions
    apply_extensions::check_parameter_names(module);
    // Values interpolated outside generic code, before specializing
    // `to_string<T>` for a type it cannot convert fails inside it.
    step!(interpolation::check_interpolations(module));
    // Generic constraints, before any specialization clones a body.
    step!(constraints::check_constraints(module));
    // Constrained generic code uses only what its constraints offer.
    step!(check_bounds::check_bounds(module));

    // The template stage ends here: every specialization is cloned from the
    // generic bases as they are now.
    module.templates = Templates::freeze(module);

    step!(specialize_structs(module));
    step!(specialize_functions(module));
    // `a..b` over a non-integer, before the runtime's `Range<T>` fails inside.
    step!(ranges::check_ranges(module));
    step!(generic_methods::specialize_methods(module));
    step!(static_blocks::expand(module, true));
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
    // until no new specialization appears. A type that nests itself (`Foo<T>`
    // holding a `Foo<Array<T>>`) never reaches a fixpoint: the specialization
    // depth limit reports it (`gather_generics::specialization_too_deep`);
    // the bound on rounds only backs that up.
    // A specialization made here gets the passes above after the loop.
    for _ in 0..4096 {
        let before = (module.structs.len(), module.functions.len());
        step!(gather_generics(module));
        step!(constraints::check_specializations(module));
        step!(specialize_structs(module));
        step!(specialize_functions(module));
        step!(ranges::check_ranges(module));
        // The `static` blocks of what the round specialized, now that their
        // type arguments are known.
        let expanded = static_blocks::expand(module, true);
        if let Some(error) = crate::errors::take() {
            return Err(error);
        }
        // A generic method call on a value whose type the round just
        // specialized (`c.map(f)` with `c: Box<long>`) is typed, and its type
        // arguments inferred, only now.
        // Likewise a call to an overloaded function whose arguments the
        // round just typed (`f(x)` with `x: T`, now `int`), and a call a
        // `static` block emitted (`to_json(value.x)`).
        if expanded || generic_methods::has_generic_methods(module) || overloads::has_overloads(module) {
            step!(resolve_implicit_types(module));
        }
        let methods_added = generic_methods::specialize_methods(module);
        let methods_expanded = static_blocks::expand(module, true);
        // `copy` of a type whose specialization just appeared: its `_pep_copy`
        // methods call `copies.copy<F>` for each field, specialized next round.
        let copies_added = copies::synthesize_copies(module);
        if let Some(error) = crate::errors::take() {
            return Err(error);
        }
        if (module.structs.len(), module.functions.len()) == before && !methods_added && !copies_added && !expanded && !methods_expanded {
            // The round's inference can still have named a new instance
            // (`wrap(u)` in a method specialized this round, now
            // `wrap<bool>`): done only when gathering asks for nothing new.
            let specs = (module.struct_specs.len(), module.func_specs.len());
            step!(gather_generics(module));
            if (module.struct_specs.len(), module.func_specs.len()) == specs {
                break;
            }
        }
    }
    // Every specialization expanded its `static` blocks; the generic
    // bases' are done with.
    static_blocks::remove_from_generic_code(module);
    // And those in the specializations of generic code.
    step!(interpolation::check_interpolations(module));
    // Calls of members a constrained extension withheld.
    step!(constraints::check_withheld(module));
    step!(convert_intrinsics(module));
    step!(resolve_resolvables(module, false));
    // Specialized extensions (`extend Box<int>`) of the instances the loop
    // made (once per extension and struct).
    step!(apply_extensions(module, true));
    // A trait's default method with a `static` block, copied into a struct
    // the loop made.
    step!(static_blocks::expand(module, true));
    step!(convert_member_refs(module));
    step!(synthesize_function_types(module));

    // final pass
    // Methods, constructors and generic functions used as values, once every
    // type is known; before `release_field_refs`, which releases a bound
    // method's receiver.
    step!(function_references::reference_functions(module));
    step!(release_field_refs(module));
    step!(resolve_implicit_types(module));
    step!(check_tries::check_tries(module));
    step!(named_arguments::check_unbound(module));
    named_arguments::record_argument_names(module);
    step!(type_arguments::check_type_arguments(module));
    step!(overloads::check_overloads(module));
    step!(resolve_operators(module)); // once implicit types are resolved, operator overloading may exist
    step!(unary_operators::check_conditions(module));
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
    // How value structs are used: identity, `const`, changes to copies.
    step!(crate::value_structs::check(module));
    // Struct values flowing into trait-typed slots, once every type is final.
    step!(convert_to_traits::convert_to_traits(module));
    step!(check_function_types::check_function_types(module));
    // `as` and `unsafe_cast` convert only what their kind allows.
    step!(check_casts::check_casts(module));
    step!(check_shared_types::check_shared_types(module));
    // What `with` blocks over `[Isolated]` guards may do, `[Move]`
    // arguments, and the guards' own rules, once every type is final.
    // Callee bodies (link summaries), checked ones included.
    crate::checked::restore_bodies(module);
    step!(check_confinement::check_confinement(module));
    // The rest lower bodies, which checked ones have been already.
    crate::checked::stash_bodies(module);
    // `with` conditions need the final types of `enter()`.
    step!(lower_with_blocks(module));
    // `match` arms need the final type of the value matched.
    step!(crate::enums::lower_matches(module));
    // Warnings only: uses of deprecated fields and methods, by final type.
    step!(check_deprecated_members::check_deprecated_members(module));
    // Struct keys whose `==` and `hash<T>` disagree.
    step!(check_hash_keys::check_hash_keys(module));
    crate::checked::restore_bodies(module);
    Ok(())
}

/// Report the first extern whose `[Link(...)]` attributes are wrong.
fn check_link_attributes(module: &Module) {
    if let Some(error) = module.externs.iter().find_map(|ext| ext.link().err()) {
        crate::errors::report(error);
    }
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
        // The statements a `static` block emits, so a generic base's are
        // lowered with the rest of it.
        Statement::Static(block) => walk_static_items(&mut block.items, f),
    }
}

fn walk_static_items(items: &mut [StaticItem], f: &mut impl FnMut(&mut Expression)) {
    for item in items {
        match item {
            StaticItem::For { body, .. } | StaticItem::While { body, .. } | StaticItem::Block(body) => walk_static_items(body, f),
            StaticItem::If { then_items, else_items, .. } => {
                walk_static_items(then_items, f);
                walk_static_items(else_items, f);
            }
            StaticItem::EmitIf { condition, then_items, else_items } => {
                walk_expression(condition, f);
                walk_static_items(then_items, f);
                walk_static_items(else_items, f);
            }
            StaticItem::Emit(statement) => walk_statement(statement, f),
            StaticItem::Var { .. } | StaticItem::Evaluate(_) | StaticItem::Jump { .. } => {}
        }
    }
}

pub fn walk_expression(expr: &mut Expression, f: &mut impl FnMut(&mut Expression)) {
    f(expr);
    match expr {
        Expression::SymbolRef { .. } | Expression::ThisRef | Expression::StaticCase { .. } => {}
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
        Expression::AtomicStore(_, ptr, val) | Expression::ConstructAt(ptr, val) => {
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
        Expression::Destructure { value, .. } | Expression::Move { value, .. } | Expression::NamedArgument { value, .. } => walk_expression(value, f),
        Expression::MatchArm(test) => {
            walk_expression(&mut test.subject, f);
            for literal in test.patterns.iter_mut().flat_map(|p| p.literals_mut()) {
                walk_expression(literal, f);
            }
        }
        Expression::CaseValue(value) => walk_expression(&mut value.subject, f),
        Expression::WithSubject(with) => {
            walk_expression(&mut with.subject, f);
            walk_expression(&mut with.body, f);
        }
        Expression::Subject { .. } | Expression::NoMatch | Expression::DefaultArgument { .. } => {}
        Expression::ClosureLiteral(closure) => walk_block(&mut closure.body, f),
        Expression::MakeClosure { value, .. } => walk_expression(value, f),
        Expression::ToTrait { value, .. } | Expression::FromTrait { value, .. } => walk_expression(value, f),
        Expression::MethodAddress(_) | Expression::StaticValue(_) => {}
        Expression::StaticMember(member) => {
            for arg in &mut member.args {
                walk_expression(arg, f);
            }
        }
        Expression::CallPointer { pointer, args } => {
            walk_expression(pointer, f);
            for arg in args {
                walk_expression(arg, f);
            }
        }
    }
}

/// [`walk_block`] for walks that only read: apply `f` to every expression in
/// a block, in the same order.
pub fn visit_block<'e>(block: &'e Block, f: &mut impl FnMut(&'e Expression)) {
    for stmt in &block.items {
        visit_statement(stmt, f);
    }
}

pub fn visit_statement<'e>(stmt: &'e Statement, f: &mut impl FnMut(&'e Expression)) {
    match stmt {
        Statement::Expression(expr) => visit_expression(expr, f),
        Statement::Block(inner) => visit_block(inner, f),
        Statement::Declaration(Declaration::Variable(var)) => {
            if let Some(default) = &var.default {
                visit_expression(default, f);
            }
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            visit_expression(&branch.condition, f);
            visit_block(&branch.if_block, f);
            if let Some(else_block) = &branch.else_block {
                visit_block(else_block, f);
            }
        }
        Statement::While(wh) => {
            visit_expression(&wh.condition, f);
            visit_block(&wh.block, f);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &ret.expr {
                visit_expression(expr, f);
            }
        }
        Statement::LoopBreak(_) => {}
        Statement::Static(block) => visit_static_items(&block.items, f),
    }
}

fn visit_static_items<'e>(items: &'e [StaticItem], f: &mut impl FnMut(&'e Expression)) {
    for item in items {
        match item {
            StaticItem::For { body, .. } | StaticItem::While { body, .. } | StaticItem::Block(body) => visit_static_items(body, f),
            StaticItem::If { then_items, else_items, .. } => {
                visit_static_items(then_items, f);
                visit_static_items(else_items, f);
            }
            StaticItem::EmitIf { condition, then_items, else_items } => {
                visit_expression(condition, f);
                visit_static_items(then_items, f);
                visit_static_items(else_items, f);
            }
            StaticItem::Emit(statement) => visit_statement(statement, f),
            StaticItem::Var { .. } | StaticItem::Evaluate(_) | StaticItem::Jump { .. } => {}
        }
    }
}

pub fn visit_expression<'e>(expr: &'e Expression, f: &mut impl FnMut(&'e Expression)) {
    f(expr);
    match expr {
        Expression::SymbolRef { .. } | Expression::ThisRef | Expression::StaticCase { .. } => {}
        Expression::MemberRef { lhs, .. } => visit_expression(lhs, f),
        Expression::BoolLiteral(_)
        | Expression::IntLiteral(_)
        | Expression::FloatLiteral(_)
        | Expression::StringLiteral { .. }
        | Expression::PointerLiteral => {}
        Expression::Binary { lhs, rhs, .. } => {
            visit_expression(lhs, f);
            visit_expression(rhs, f);
        }
        Expression::Unary { operand, .. } => visit_expression(operand, f),
        Expression::Cast { expr, .. } => visit_expression(expr, f),
        Expression::Ternary {
            condition,
            true_expr,
            false_expr,
        } => {
            visit_expression(condition, f);
            visit_expression(true_expr, f);
            visit_expression(false_expr, f);
        }
        Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
            visit_expression(lhs, f);
            visit_expression(rhs, f);
        }
        Expression::SizeOf(_) | Expression::IsPod(_) | Expression::Default(_) | Expression::Allocate(_) => {}
        Expression::CountStep { .. } | Expression::FunctionPointer { .. } => {}
        Expression::RefCount(_, arg) | Expression::Address(_, arg) | Expression::Weak(_, _, arg) => visit_expression(arg, f),
        Expression::AtomicLoad(_, arg) => visit_expression(arg, f),
        Expression::AtomicStore(_, ptr, val) | Expression::ConstructAt(ptr, val) => {
            visit_expression(ptr, f);
            visit_expression(val, f);
        }
        Expression::AtomicCmpXchg(_, ptr, expected, desired) => {
            visit_expression(ptr, f);
            visit_expression(expected, f);
            visit_expression(desired, f);
        }
        Expression::AtomicFetch(_, _, ptr, val) => {
            visit_expression(ptr, f);
            visit_expression(val, f);
        }
        Expression::FunctionCall { args, .. } => {
            for arg in args {
                visit_expression(arg, f);
            }
        }
        Expression::MethodCall { this, args, .. } => {
            visit_expression(this, f);
            for arg in args {
                visit_expression(arg, f);
            }
        }
        Expression::FunctionRef { .. } => {}
        Expression::Invoke { callee, args } => {
            visit_expression(callee, f);
            for arg in args {
                visit_expression(arg, f);
            }
        }
        Expression::ForIterator(source) | Expression::WithEntered(source) => visit_expression(source, f),
        Expression::Destructure { value, .. } | Expression::Move { value, .. } | Expression::NamedArgument { value, .. } => visit_expression(value, f),
        Expression::MatchArm(test) => {
            visit_expression(&test.subject, f);
            for literal in test.patterns.iter().flat_map(|p| p.all()).filter_map(|p| p.literal.as_ref()) {
                visit_expression(literal, f);
            }
        }
        Expression::CaseValue(value) => visit_expression(&value.subject, f),
        Expression::WithSubject(with) => {
            visit_expression(&with.subject, f);
            visit_expression(&with.body, f);
        }
        Expression::Subject { .. } | Expression::NoMatch | Expression::DefaultArgument { .. } => {}
        Expression::ClosureLiteral(closure) => visit_block(&closure.body, f),
        Expression::MakeClosure { value, .. } => visit_expression(value, f),
        Expression::ToTrait { value, .. } | Expression::FromTrait { value, .. } => visit_expression(value, f),
        Expression::MethodAddress(_) | Expression::StaticValue(_) => {}
        Expression::StaticMember(member) => {
            for arg in &member.args {
                visit_expression(arg, f);
            }
        }
        Expression::CallPointer { pointer, args } => {
            visit_expression(pointer, f);
            for arg in args {
                visit_expression(arg, f);
            }
        }
    }
}

/// The direct sub-expressions of an expression, in order, without
/// allocating: at most three fixed children, or one followed by a list
/// (a call's arguments).
pub enum Children<'a, R, I> {
    Fixed([Option<R>; 3], usize),
    Chain(Option<R>, I),
    /// A `match` arm's subject and its patterns' literals.
    Boxed(Box<dyn Iterator<Item = R> + 'a>),
}

impl<'a, R, I: Iterator<Item = R>> Children<'a, R, I> {
    fn none() -> Self {
        Children::Fixed([None, None, None], 0)
    }

    fn one(a: R) -> Self {
        Children::Fixed([Some(a), None, None], 0)
    }

    fn two(a: R, b: R) -> Self {
        Children::Fixed([Some(a), Some(b), None], 0)
    }

    fn three(a: R, b: R, c: R) -> Self {
        Children::Fixed([Some(a), Some(b), Some(c)], 0)
    }
}

impl<'a, R, I: Iterator<Item = R>> Iterator for Children<'a, R, I> {
    type Item = R;

    fn next(&mut self) -> Option<R> {
        match self {
            Children::Fixed(items, next) => {
                while *next < items.len() {
                    *next += 1;
                    if let Some(item) = items[*next - 1].take() {
                        return Some(item);
                    }
                }
                None
            }
            Children::Chain(first, rest) => first.take().or_else(|| rest.next()),
            Children::Boxed(items) => items.next(),
        }
    }
}

/// The direct sub-expressions of `expr`, for walks that need to decide per
/// node whether to descend (a closure literal's body is a block, not listed).
pub fn children_mut(expr: &mut Expression) -> Children<'_, &mut Expression, std::slice::IterMut<'_, Expression>> {
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
        | Expression::StaticCase { .. }
        | Expression::Subject { .. }
        | Expression::NoMatch
        | Expression::DefaultArgument { .. }
        | Expression::Allocate(_)
        | Expression::FunctionRef { .. }
        | Expression::MethodAddress(_)
        | Expression::CountStep { .. }
        | Expression::FunctionPointer { .. }
        | Expression::StaticValue(_)
        | Expression::ClosureLiteral(_) => Children::none(),
        Expression::StaticMember(member) => Children::Chain(None, member.args.iter_mut()),
        Expression::MemberRef { lhs, .. } => Children::one(lhs.as_mut()),
        Expression::Binary { lhs, rhs, .. }
        | Expression::Index { lhs, rhs, .. }
        | Expression::ArrayIndex { lhs, rhs, .. } => Children::two(lhs.as_mut(), rhs.as_mut()),
        Expression::Unary { operand, .. } => Children::one(operand.as_mut()),
        Expression::Cast { expr, .. } => Children::one(expr.as_mut()),
        Expression::Ternary { condition, true_expr, false_expr } => {
            Children::three(condition.as_mut(), true_expr.as_mut(), false_expr.as_mut())
        }
        Expression::RefCount(_, arg)
        | Expression::Address(_, arg)
        | Expression::Weak(_, _, arg)
        | Expression::AtomicLoad(_, arg)
        | Expression::ForIterator(arg)
        | Expression::WithEntered(arg) => Children::one(arg.as_mut()),
        Expression::MatchArm(test) => Children::Boxed(Box::new(
            std::iter::once(&mut test.subject).chain(test.patterns.iter_mut().flat_map(|p| p.literals_mut())),
        )),
        Expression::CaseValue(value) => Children::one(&mut value.subject),
        Expression::WithSubject(with) => Children::two(&mut with.subject, &mut with.body),
        Expression::AtomicStore(_, ptr, val) | Expression::AtomicFetch(_, _, ptr, val) | Expression::ConstructAt(ptr, val) => {
            Children::two(ptr.as_mut(), val.as_mut())
        }
        Expression::AtomicCmpXchg(_, ptr, expected, desired) => Children::three(ptr.as_mut(), expected.as_mut(), desired.as_mut()),
        Expression::FunctionCall { args, .. } => Children::Chain(None, args.iter_mut()),
        Expression::MethodCall { this, args, .. } => Children::Chain(Some(this.as_mut()), args.iter_mut()),
        Expression::Invoke { callee, args } => Children::Chain(Some(callee.as_mut()), args.iter_mut()),
        Expression::CallPointer { pointer, args } => Children::Chain(Some(pointer.as_mut()), args.iter_mut()),
        Expression::MakeClosure { value, .. }
        | Expression::ToTrait { value, .. }
        | Expression::FromTrait { value, .. }
        | Expression::Destructure { value, .. }
        | Expression::Move { value, .. }
        | Expression::NamedArgument { value, .. } => Children::one(value.as_mut()),
    }
}

/// The direct sub-expressions of `expr` ([`children_mut`] without `&mut`).
pub fn children(expr: &Expression) -> Children<'_, &Expression, std::slice::Iter<'_, Expression>> {
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
        | Expression::StaticCase { .. }
        | Expression::Subject { .. }
        | Expression::NoMatch
        | Expression::DefaultArgument { .. }
        | Expression::StaticValue(_)
        | Expression::ClosureLiteral(_) => Children::none(),
        Expression::StaticMember(member) => Children::Chain(None, member.args.iter()),
        Expression::CaseValue(case) => Children::one(&case.subject),
        Expression::WithSubject(with) => Children::two(&with.subject, &with.body),
        Expression::MemberRef { lhs, .. } => Children::one(lhs),
        Expression::Binary { lhs, rhs, .. } | Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => Children::two(lhs, rhs),
        Expression::Unary { operand, .. } => Children::one(operand),
        Expression::Cast { expr, .. } => Children::one(expr),
        Expression::Ternary { condition, true_expr, false_expr } => Children::three(condition, true_expr, false_expr),
        Expression::RefCount(_, arg)
        | Expression::Address(_, arg)
        | Expression::Weak(_, _, arg)
        | Expression::AtomicLoad(_, arg)
        | Expression::ForIterator(arg)
        | Expression::WithEntered(arg) => Children::one(arg),
        Expression::MatchArm(test) => {
            Children::Boxed(Box::new(std::iter::once(&test.subject).chain(test.patterns.iter().flat_map(|p| p.all()).filter_map(|p| p.literal.as_ref()))))
        }
        Expression::Destructure { value, .. } | Expression::Move { value, .. } | Expression::NamedArgument { value, .. } => Children::one(value),
        Expression::AtomicStore(_, a, b) | Expression::AtomicFetch(_, _, a, b) | Expression::ConstructAt(a, b) => Children::two(a, b),
        Expression::AtomicCmpXchg(_, a, b, c) => Children::three(a, b, c),
        Expression::FunctionCall { args, .. } => Children::Chain(None, args.iter()),
        Expression::MethodCall { this, args, .. } => Children::Chain(Some(this), args.iter()),
        Expression::Invoke { callee, args } => Children::Chain(Some(callee), args.iter()),
        Expression::CallPointer { pointer, args } => Children::Chain(Some(pointer), args.iter()),
        Expression::MakeClosure { value, .. } | Expression::ToTrait { value, .. } | Expression::FromTrait { value, .. } => {
            Children::one(value)
        }
    }
}

/// Apply `f` to every expression inside a function body.
pub fn walk_function(function: &mut FunctionDef, f: &mut impl FnMut(&mut Expression)) {
    if let Some(body) = &mut function.body {
        walk_block(body, f);
    }
}

/// [`walk_function`] for walks that only read.
pub fn visit_function<'e>(function: &'e FunctionDef, f: &mut impl FnMut(&'e Expression)) {
    if let Some(body) = &function.body {
        visit_block(body, f);
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
