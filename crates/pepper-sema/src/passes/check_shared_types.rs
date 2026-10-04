//! Thread safety of `[Shared]` structs.
//!
//! Reference counts are plain by default; a struct declared `[Shared]` gets
//! atomic counts (`struct_body`), so its objects may be referenced from
//! several threads at once. That is only safe if nothing reachable through
//! the object can race, so every field of a shared struct must be:
//!
//! - `const`: set once, by the constructor, and never assigned again
//!   (threads change shared state through a thread-safe member such as an
//!   `Atomic<T>`, not by assigning fields); and
//! - of a thread-safe type: a primitive, a raw pointer to a thread-safe type
//!   (`__ptr<void>` included: what raw memory holds is the code's own
//!   responsibility), a `shared` function type, a `[Shared]` struct, a
//!   weak reference to one, or a tuple or value struct (`[Value]`) of
//!   thread-safe types.
//!
//! Every other struct is not thread-safe, and neither is a plain function
//! type (`(P...) => R`): its counts are plain and a closure of that type may
//! hold anything. `shared_functions` checks what a closure converted to a
//! `shared` function type captures, with [`unsafe_part_in`] too.
//!
//! Every module-scope variable, exported or not, is implicitly shared: any
//! function can hand it to any thread, so it follows the same two rules as a
//! field of a `[Shared]` struct. The `const` rule is checked on the
//! declaration (generic bases included); the type rule on concrete structs,
//! so a generic shared struct is checked per specialization
//! (`Atomic<String>` is an error, `Atomic<int>` is not) and the error points
//! at the code that named the specialization.
//!
//! A `[ThreadLocal]` module-scope variable is the one exception to the
//! `const` rule: every thread has its own copy, so no two threads ever touch
//! the same one and assigning it cannot race. It keeps the type rule (a
//! non-thread-safe value could be parked there from under a lock, which
//! `check_confinement` does not follow; `async.ThreadLocal<T>` is the way to
//! hold one), and its initializer must be a constant ([`thread_local_constant`]),
//! the image every thread starts from.

use crate::model::*;
use crate::passes::gather_generics::parse_type_string;
use crate::type_name::TypeName;

/// The names of the structs whose references are thread-safe: `[Shared]`
/// structs and `shared` function types, and the value structs (`[Value]`)
/// whose fields all are, as a tuple's elements are.
pub(crate) struct ThreadSafeStructs(std::collections::HashSet<String>);

impl ThreadSafeStructs {
    pub(crate) fn of(module: &Module) -> Self {
        let mut safe = ThreadSafeStructs(
            module
                .structs
                .iter()
                .filter(|st| st.is_shared() || st.ty.is_shared_function_type())
                .map(|st| st.name.clone())
                .collect(),
        );
        // A value struct holding another counts once that one does.
        let values: Vec<&StructDef> = module.structs.iter().filter(|st| st.is_value() && !(st.ty.is_generic() && st.name == st.ty.name)).collect();
        loop {
            let found: Vec<String> = values
                .iter()
                .filter(|st| !safe.0.contains(&st.name) && st.field_members.iter().all(|f| unsafe_part_in(&f.ty, &safe).is_none()))
                .map(|st| st.name.clone())
                .collect();
            if found.is_empty() {
                return safe;
            }
            safe.0.extend(found);
        }
    }
}

/// The first type inside `ty` that is not thread-safe, if any, given the
/// thread-safe structs.
pub(crate) fn unsafe_part_in(ty: &TypeName, safe: &ThreadSafeStructs) -> Option<TypeName> {
    let name = ty.to_string();
    // A C function pointer is a code address, the same on every thread, and
    // a vector (`__simd<T, N>`) holds only numbers.
    if crate::type_name::is_integral_name(&name) || ty.is_simd() || ty.is_shared_function_type() || ty.is_extern_function_type() {
        return None;
    }
    if ty.is_function_type() {
        return Some(ty.clone());
    }
    if let Some(pointee) = name.strip_suffix('*') {
        return unsafe_part_in(&parse_type_string(pointee), safe);
    }
    if let Some(target) = ty.weak_target() {
        return unsafe_part_in(target, safe);
    }
    // A tuple is its elements, held by value.
    let parsed = parse_type_string(&name);
    if parsed.is_tuple() {
        return parsed.tuple_elements().iter().find_map(|e| unsafe_part_in(e, safe));
    }
    if safe.0.contains(&name) {
        return None;
    }
    // Some passes carry a type as a flat name (`__function<void>`).
    let parsed = parse_type_string(&name);
    if parsed.is_function_type() || parsed.is_extern_function_type() {
        return unsafe_part_in(&parsed, safe);
    }
    Some(ty.clone())
}

/// Where the program names type `spec` (a variable, field or parameter
/// type, or a constructor call), for errors about a specialization.
pub(crate) fn use_site(module: &Module, spec: &str) -> Option<Loc> {
    find_use_site(module, spec).map(|(loc, _)| loc)
}

/// [`use_site`], with the name of the free function it is in, if any.
fn find_use_site(module: &Module, spec: &str) -> Option<(Loc, Option<String>)> {
    fn var_loc(var: &VariableDef, spec: &str) -> Option<Loc> {
        let mentions = |ty: &TypeName| -> bool {
            fn walk(ty: &TypeName, spec: &str) -> bool {
                ty.to_string() == spec || ty.sub_types.iter().any(|t| walk(t, spec))
            }
            walk(ty, spec)
        };
        // An inferred type (`var a = Atomic<String>();`) has no type
        // location: the constructor call in the initializer names it.
        if !mentions(&var.ty) || var.type_loc.is_none() {
            return None;
        }
        Some(var.type_loc)
    }
    fn in_block(block: &Block, spec: &str) -> Option<Loc> {
        for stmt in &block.items {
            let found = match stmt {
                Statement::Declaration(Declaration::Variable(var)) => {
                    var_loc(var, spec).or_else(|| var.default.as_ref().and_then(|e| in_expression(e, spec)))
                }
                Statement::Block(inner) => in_block(inner, spec),
                Statement::Branch(branch) => in_expression(&branch.condition, spec)
                    .or_else(|| in_block(&branch.if_block, spec))
                    .or_else(|| branch.else_block.as_ref().and_then(|b| in_block(b, spec))),
                Statement::While(wh) => in_expression(&wh.condition, spec).or_else(|| in_block(&wh.block, spec)),
                Statement::Expression(e) => in_expression(e, spec),
                Statement::Return(ret) => ret.expr.as_ref().and_then(|e| in_expression(e, spec)),
                _ => None,
            };
            if found.is_some() {
                return found;
            }
        }
        None
    }
    fn in_expression(expr: &Expression, spec: &str) -> Option<Loc> {
        let mut found = None;
        crate::passes::visit_expression(expr, &mut |e: &Expression| {
            if found.is_none()
                && let Expression::FunctionCall { function, loc, .. } = e
                && function == spec
                && !loc.is_none()
            {
                found = Some(*loc);
            }
        });
        found
    }
    fn in_function(function: &FunctionDef, spec: &str) -> Option<Loc> {
        function
            .parameters
            .iter()
            .find_map(|p| var_loc(p, spec))
            .or_else(|| function.body.as_ref().and_then(|b| in_block(b, spec)))
    }
    module
        .globals
        .iter()
        .find_map(|g| var_loc(g, spec).or_else(|| g.default.as_ref().and_then(|e| in_expression(e, spec))))
        .map(|loc| (loc, None))
        .or_else(|| module.functions.iter().find_map(|f| in_function(f, spec).map(|loc| (loc, Some(f.name.clone())))))
        .or_else(|| {
            module.structs.iter().find_map(|st| {
                st.field_members
                    .iter()
                    .find_map(|f| var_loc(f, spec))
                    .or_else(|| st.method_members.iter().chain(st.constructors.iter()).chain([&st.destructor]).find_map(|m| in_function(m, spec)))
            })
            .map(|loc| (loc, None))
        })
}

/// [`use_site`], followed out of generic function specializations to the
/// code the user wrote: when `spec` is named inside a specialization such as
/// `spawn<String>`, the site is the call that asked for that specialization
/// (and so on outwards). Returns that site and, innermost first, each
/// specialization passed through with where it names the next inner thing.
pub(crate) fn user_use_site(module: &Module, spec: &str) -> Option<(Loc, Vec<(String, Loc)>)> {
    let (mut loc, mut function) = find_use_site(module, spec)?;
    let mut through = Vec::new();
    while let Some(name) = function {
        if !name.contains('<') || through.iter().any(|(seen, _)| *seen == name) {
            break;
        }
        let Some((call, caller)) = find_use_site(module, &name) else { break };
        through.push((name, loc));
        loc = call;
        function = caller;
    }
    Some((loc, through))
}

/// A note at `ty`'s declaration saying why it is not thread-safe.
pub(crate) fn not_shared_note(diagnostic: Diagnostic, ty: &TypeName, module: &Module) -> Diagnostic {
    if ty.is_function_type() {
        return diagnostic.with_note(
            format!("declare the function type '{}' to share it between threads", ty.with_sharing(true).display()),
            None,
        );
    }
    match module.structs.iter().find(|st| st.name == ty.to_string()) {
        Some(st) if !st.loc.is_none() => {
            diagnostic.with_note(format!("'{}' is not declared [Shared]", ty.display()), Some(st.loc))
        }
        _ => diagnostic,
    }
}

pub fn check_shared_types(module: &mut Module) {
    let module: &Module = module;
    // Built once: it walks every value struct to a fixed point.
    let safe = ThreadSafeStructs::of(module);
    if !check_shared_structs(module, &safe) {
        return;
    }
    check_globals(module, &safe);
}

/// The value of a thread-local's initializer, which every thread starts
/// from: a number, `bool` or `char` literal (negated, or cast to another
/// number or an enum, as an enum case is), or null.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ThreadLocalConstant {
    Int(i64),
    Float(f64),
    Null,
}

/// The constant `expr` stands for, if it is one a thread-local may start
/// from (see [`ThreadLocalConstant`]).
pub fn thread_local_constant(expr: &Expression) -> Option<ThreadLocalConstant> {
    match expr {
        Expression::IntLiteral(v) => Some(ThreadLocalConstant::Int(*v)),
        Expression::BoolLiteral(v) => Some(ThreadLocalConstant::Int(*v as i64)),
        Expression::FloatLiteral(v) => Some(ThreadLocalConstant::Float(*v)),
        Expression::PointerLiteral => Some(ThreadLocalConstant::Null),
        Expression::Unary { op: UnaryOp::Neg, operand, .. } => match thread_local_constant(operand)? {
            ThreadLocalConstant::Int(v) => Some(ThreadLocalConstant::Int(v.wrapping_neg())),
            ThreadLocalConstant::Float(v) => Some(ThreadLocalConstant::Float(-v)),
            ThreadLocalConstant::Null => None,
        },
        Expression::Unary { op: UnaryOp::Pos, operand, .. } => thread_local_constant(operand),
        Expression::Cast { expr, ty, .. } if ty.is_integral() && !ty.is_pointer() => match thread_local_constant(expr)? {
            ThreadLocalConstant::Int(v) if is_floating(ty) => Some(ThreadLocalConstant::Float(v as f64)),
            ThreadLocalConstant::Float(v) if !is_floating(ty) => Some(ThreadLocalConstant::Int(v as i64)),
            ThreadLocalConstant::Null => None,
            constant => Some(constant),
        },
        _ => None,
    }
}

fn is_floating(ty: &TypeName) -> bool {
    matches!(ty.name.as_str(), "float" | "double" | "f32" | "f64")
}

/// Module-scope variables must be `const` and thread-safe, like the fields
/// of a `[Shared]` struct; a `[ThreadLocal]` one need not be `const`, but
/// starts from a constant.
fn check_globals(module: &Module, safe: &ThreadSafeStructs) {
    // A checked runtime's were checked with it.
    for global in module.globals.iter().filter(|g| !module.checked.globals.contains(&g.name)) {
        if global.is_thread_local() {
            if !check_thread_local(module, global, safe) {
                return;
            }
            continue;
        }
        if !global.is_const {
            crate::errors::report(
                Diagnostic::error(format!("module-scope variable '{}' must be 'const'", global.name))
                    .at(global.loc)
                    .with_note(
                        "every thread can reach a module-scope variable; change its state through a thread-safe type such as 'async.Atomic<T>' (after 'import async'), or declare it '[ThreadLocal]' to give each thread its own copy",
                        None,
                    ),
            );
            return;
        }
        let Some(offender) = unsafe_part_in(&global.ty, safe) else { continue };
        let loc = [global.type_loc, global.loc].into_iter().find(|l| !l.is_none()).unwrap_or(Loc::NONE);
        let diagnostic = Diagnostic::error(format!(
            "module-scope variable '{}' has type '{}', which is not thread-safe",
            global.name,
            global.ty.display()
        ))
        .at(loc);
        crate::errors::report(not_shared_note(diagnostic, &offender, module));
        return;
    }
}

/// A `[ThreadLocal]` variable must be thread-safe and start from a
/// constant. Returns whether it does.
fn check_thread_local(module: &Module, global: &VariableDef, safe: &ThreadSafeStructs) -> bool {
    let name = pepper_parser::namespace::demangle_name(&global.name);
    if let Some(offender) = unsafe_part_in(&global.ty, safe) {
        let loc = [global.type_loc, global.loc].into_iter().find(|l| !l.is_none()).unwrap_or(Loc::NONE);
        let diagnostic = Diagnostic::error(format!(
            "thread-local variable '{}' has type '{}', which is not thread-safe",
            name,
            global.ty.display()
        ))
        .at(loc)
        .with_note("a per-thread value of any type is an 'async.ThreadLocal<T>' (after 'import async')", None);
        crate::errors::report(not_shared_note(diagnostic, &offender, module));
        return false;
    }
    if let Some(default) = &global.default
        && thread_local_constant(default).is_none()
    {
        let at = [default.loc(), global.loc].into_iter().find(|l| !l.is_none()).unwrap_or(Loc::NONE);
        crate::errors::report(
            Diagnostic::error(format!("thread-local variable '{}' must start from a constant", name))
                .at(at)
                .with_note("every thread starts from this value; leave it out and assign the value on the thread's first use instead", None),
        );
        return false;
    }
    true
}

/// Every `[Shared]` struct's fields must be `const` and thread-safe. Returns
/// whether they all are.
fn check_shared_structs(module: &Module, safe: &ThreadSafeStructs) -> bool {
    // A checked runtime's were checked with it; the specializations the
    // program adds are not checked yet.
    for st in module.structs.iter().filter(|st| st.is_shared() && !module.checked.has_struct(&st.name)) {
        let fields = st.field_members.iter().filter(|f| f.kind == Kind::Field && !f.name.starts_with("__"));
        let is_generic_base = st.name == st.ty.name && st.ty.is_generic();
        let is_specialization = st.name.contains('<');
        for field in fields {
            // Declared once per source struct: check it there, not again in
            // every specialization.
            if !is_specialization && !field.is_const {
                crate::errors::report(
                    Diagnostic::error(format!("field '{}' of shared struct '{}' must be 'const'", field.name, st.name))
                        .at(field.loc)
                        .with_note(
                            "threads change a shared struct's state through a thread-safe member such as 'async.Atomic<T>' (after 'import async')",
                            None,
                        ),
                );
                return false;
            }
            if is_generic_base {
                continue;
            }
            let Some(offender) = unsafe_part_in(&field.ty, safe) else { continue };
            let field_loc = [field.type_loc, field.loc].into_iter().find(|l| !l.is_none()).unwrap_or(Loc::NONE);
            // A reference enum's field holds a value of one of its cases.
            let (what, owner) = match field.name.split_once('.') {
                Some((case, value)) if st.enum_cases.is_some() => (format!("value '{}' of case '{}'", value, case), "enum"),
                _ => (format!("field '{}'", field.name), "struct"),
            };
            let diagnostic = if is_specialization {
                let (site, through) = user_use_site(module, &st.name).unwrap_or((field_loc, Vec::new()));
                // Name what the user wrote: the outermost specialization.
                let asked = match through.last() {
                    Some((function, _)) => format!("'{}'", function),
                    None => format!("shared struct '{}'", st.ty.display()),
                };
                let mut diagnostic = Diagnostic::error(format!(
                    "{} requires thread-safe type arguments; '{}' is not thread-safe",
                    asked,
                    offender.display()
                ))
                .at(site);
                // Outermost first: the specialization the user asked for,
                // then what it names, down to the struct.
                let mut required = st.ty.display();
                for (function, loc) in &through {
                    diagnostic = diagnostic
                        .with_note(format!("'{}' is required here, in '{}'", required, function), Some(*loc));
                    required = function.clone();
                }
                diagnostic.with_note(format!("required by {} declared here", what), Some(field_loc))
            } else {
                Diagnostic::error(format!(
                    "{} of shared {} '{}' has type '{}', which is not thread-safe",
                    what,
                    owner,
                    st.name,
                    field.ty.display()
                ))
                .at(field_loc)
            };
            crate::errors::report(not_shared_note(diagnostic, &offender, module));
            return false;
        }
    }
    true
}
