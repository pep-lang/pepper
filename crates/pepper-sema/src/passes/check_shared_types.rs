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
//!   weak reference to one, or a tuple of thread-safe types.
//!
//! Every other struct is not thread-safe, and neither is a plain function
//! type (`(P...) => R`): its counts are plain and a closure of that type may
//! hold anything. `shared_functions` checks what a closure converted to a
//! `shared` function type captures, with [`unsafe_part`] too.
//!
//! Every module-scope variable, exported or not, is implicitly shared: any
//! function can hand it to any thread, so it follows the same two rules as a
//! field of a `[Shared]` struct. The `const` rule is checked on the
//! declaration (generic bases included); the type rule on concrete structs,
//! so a generic shared struct is checked per specialization
//! (`Atomic<String>` is an error, `Atomic<int>` is not) and the error points
//! at the code that named the specialization.

use crate::model::*;
use crate::passes::gather_generics::parse_type_string;
use crate::type_name::TypeName;

/// The first type inside `ty` that is not thread-safe, if any.
fn unsafe_part(ty: &TypeName, module: &Module) -> Option<TypeName> {
    unsafe_part_in(ty, &ThreadSafeStructs::of(module))
}

/// The names of the structs whose references are thread-safe: `[Shared]`
/// structs and `shared` function types.
pub(crate) struct ThreadSafeStructs(std::collections::HashSet<String>);

impl ThreadSafeStructs {
    pub(crate) fn of(module: &Module) -> Self {
        ThreadSafeStructs(
            module
                .structs
                .iter()
                .filter(|st| st.is_shared() || st.ty.is_shared_function_type())
                .map(|st| st.name.clone())
                .collect(),
        )
    }
}

/// [`unsafe_part`], given the thread-safe structs.
pub(crate) fn unsafe_part_in(ty: &TypeName, safe: &ThreadSafeStructs) -> Option<TypeName> {
    let name = ty.to_string();
    // A C function pointer is a code address, the same on every thread.
    if crate::type_name::is_integral_name(&name) || ty.is_shared_function_type() || ty.is_extern_function_type() {
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
        let mut expr = expr.clone();
        let mut found = None;
        crate::passes::walk_expression(&mut expr, &mut |e: &mut Expression| {
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
    if !check_shared_structs(module) {
        return;
    }
    check_globals(module);
}

/// Module-scope variables must be `const` and thread-safe, like the fields
/// of a `[Shared]` struct.
fn check_globals(module: &Module) {
    for global in &module.globals {
        if !global.is_const {
            crate::errors::report(
                Diagnostic::error(format!("module-scope variable '{}' must be 'const'", global.name))
                    .at(global.loc)
                    .with_note(
                        "every thread can reach a module-scope variable; change its state through a thread-safe type such as 'Atomic<T>' or 'ThreadLocal<T>'",
                        None,
                    ),
            );
            return;
        }
        let Some(offender) = unsafe_part(&global.ty, module) else { continue };
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

/// Every `[Shared]` struct's fields must be `const` and thread-safe. Returns
/// whether they all are.
fn check_shared_structs(module: &Module) -> bool {
    for st in module.structs.iter().filter(|st| st.is_shared()) {
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
                            "threads change a shared struct's state through a thread-safe member such as 'Atomic<T>'",
                            None,
                        ),
                );
                return false;
            }
            if is_generic_base {
                continue;
            }
            let Some(offender) = unsafe_part(&field.ty, module) else { continue };
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
