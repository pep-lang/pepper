//! Deep copies for `copy(value)` (`runtime/copy.pep`).
//!
//! The runtime's `_Copies.copy<T>(value)` is `__copy<T>(value, this)`. Once
//! `T` is concrete, [`synthesize_copies`] (in the specialization loop)
//! replaces each such call by what copying a `T` means:
//!
//! - a thread-safe `T` (numbers, `[Shared]` structs, `shared` function
//!   values) is not copied: the call becomes `value`;
//! - a struct `T` becomes `copies._copy_object<T>(value)`, which returns
//!   null for null, reuses a copy already made of the same object, and
//!   otherwise calls `value.__copy()`. This pass gives `T` that `__copy()`
//!   method: `return this.copy();` when `T` implements `Copyable<T>`, else a
//!   field-by-field copy (below);
//! - a trait type `T` becomes `copies._copy_trait<T>(value)`, which returns
//!   null for null and otherwise calls `value._pep_copy_trait(copies)`
//!   through the vtable. This pass adds that member to the trait, and gives
//!   every struct that declares the trait (at any type arguments)
//!   `_pep_copy_trait(copies): S { return copies.copy<S>(this); }`, so the
//!   struct behind the value is copied as a copy of `S` would be, sharing
//!   included. A struct that cannot be copied gets one that panics, naming
//!   what blocks it: what a trait value holds is known only at run time;
//! - anything else is a "cannot copy" error.
//!
//! A struct is **trivially copyable** when it has no destructor, no raw
//! pointer field, and no `[NotCopyable("why")]` attribute. Its synthesized
//! `__copy()` finds the running copy's context (`copies = _pep_copies()`,
//! one thread-local read), allocates the copy without running a constructor
//! (`Expression::Allocate`), registers it with `copies` before copying any
//! field (so a cycle back to it finds the copy), copies thread-safe fields
//! as they are, and every other field with `copies.copy<F>(this.f)`. A weak
//! field whose target is not thread-safe keeps the original's target for
//! now; `copies._defer(made._pep_fix_weak)` then points it at the target's
//! copy, or null, once the whole value has been copied.
//!
//! The context is implicit: the outermost `copy(value)` on a thread installs
//! a `_Copies` as the thread's context and a nested `copy(x)` (in a
//! `Copyable<T>.copy()` implementation) continues it, so `Copyable<T>` is
//! `copy(): T`. A struct that still implements the deprecated
//! `copy(copies: Copies)` keeps working: its `__copy()` passes the context.
//!
//! The copies a program asks for are checked through everything they
//! reach: each `copy<T>(x)` call, and each `copies.copy<T>(x)` outside a
//! `Copyable` implementation. The error is reported at the code that asked
//! (a `copy(x)` call), with a note for each field on the way to the type
//! that blocks it. Every struct method
//! is compiled, so a `Copyable` implementation (`Array<T>.copy`) may hold a
//! `__copy<X>` that nothing asks for; one that cannot copy lowers to a call
//! of `_pep_copy_failed<X>`, which panics.
//!
//! `__census<T>(slot, waiting)` (in `MutexGuard.exit`) lowers here too: to
//! `_pep_check_sync<T>(slot, waiting, "Mutex<T>")`, which copies the locked value to
//! count the references inside it when `PEP_CHECK_SYNC` is set, for a `T`
//! that can be copied; to nothing for any other `T`.
//!
//! This stays compiler work rather than a `static` block over
//! `reflect.fields<T>()`: reflection cannot see another file's private
//! fields, allocate without a constructor, or see the struct behind a trait
//! value (#324).

use crate::model::*;
use crate::passes::check_shared_types::{ThreadSafeStructs, unsafe_part_in};
use crate::passes::gather_generics::parse_type_string;
use crate::passes::static_blocks::{attribute_name, attribute_string};
use crate::type_name::TypeName;
use pepper_parser::diagnostic::{Edit, Fix, Sources};
use std::collections::HashSet;

/// The intrinsic `_Copies.copy<T>` lowers to.
const COPY_INTRINSIC: &str = "__copy";

/// The intrinsic `_Copies._copy_object<T>` calls for a struct's new copy:
/// `__copy_object<T>(value)` lowers to `value.__copy()`, a method source
/// code cannot call by name.
const COPY_OBJECT_INTRINSIC: &str = "__copy_object";

/// The intrinsic `MutexGuard.exit` calls before it unlocks: a
/// `PEP_CHECK_SYNC` census of the locked value, done by copying it.
const CENSUS_INTRINSIC: &str = "__census";

/// The runtime function a census of a copyable `T` lowers to.
const CENSUS_FUNCTION: &str = "_pep_check_sync";

/// `[NotCopyable("why")]`: a struct that must never be copied, such as one
/// owning an operating-system handle. The message says why and what to do
/// instead.
pub const NOT_COPYABLE_ATTRIBUTE: &str = "NotCopyable";

/// The struct the runtime keeps copies in: a copy's context.
const COPIES: &str = "_Copies";

/// The runtime function that returns the running copy's context.
const CONTEXT_FUNCTION: &str = "_pep_copies";

/// The trait a struct declares to say how it is copied.
pub const COPYABLE_TRAIT: &str = "Copyable";

/// The synthesized method that copies a struct.
const COPY_METHOD: &str = "__copy";

/// The synthesized method that copies a value struct (`[Value]`): a copy
/// of the value whose fields that are not thread-safe are copied in turn.
const COPY_VALUE_METHOD: &str = "_pep_copy_value";

/// The synthesized method that points a copy's weak fields at copies.
const FIX_WEAK_METHOD: &str = "_pep_fix_weak";

/// The synthesized trait member that copies the struct behind a trait value,
/// and each implementing struct's method for it.
pub const COPY_TRAIT_METHOD: &str = "_pep_copy_trait";

/// Whether `name` is a method this pass synthesizes on demand. A program
/// gets one only for the types it copies, so no file owns it: the code
/// generator shares it between units like an instantiation, which keeps a
/// unit's object (a runtime unit's included) independent of the program.
pub fn is_synthesized_method(name: &str) -> bool {
    name == COPY_METHOD || name == FIX_WEAK_METHOD || name == COPY_VALUE_METHOD || name == COPY_TRAIT_METHOD
}

/// Why a type cannot be copied.
#[derive(Debug, Clone)]
enum Blocker {
    /// A struct with a destructor.
    Destructor { ty: TypeName, loc: Loc },
    /// A struct with a raw pointer field.
    RawPointerField { ty: TypeName, field: String, field_ty: TypeName, loc: Loc },
    /// A struct marked `[NotCopyable("why")]`.
    NotCopyable { ty: TypeName, why: String, loc: Loc },
    /// A plain function value, which may capture anything.
    PlainFunction(TypeName),
    /// A raw pointer.
    RawPointer(TypeName),
    /// A weak reference outside a struct field.
    Weak(TypeName),
}

impl Blocker {
    fn ty(&self) -> &TypeName {
        match self {
            Blocker::Destructor { ty, .. } | Blocker::RawPointerField { ty, .. } | Blocker::NotCopyable { ty, .. } => ty,
            Blocker::PlainFunction(ty) | Blocker::RawPointer(ty) | Blocker::Weak(ty) => ty,
        }
    }

    /// What the type is, after "which": `is not trivially copyable`.
    fn what(&self) -> &'static str {
        match self {
            Blocker::Destructor { .. } | Blocker::RawPointerField { .. } => "is not trivially copyable",
            Blocker::NotCopyable { .. } => "cannot be copied",
            Blocker::PlainFunction(_) => "is a plain function value",
            Blocker::RawPointer(_) => "is a raw pointer",
            Blocker::Weak(_) => "is a weak reference",
        }
    }
}

/// How a value of some type is copied.
enum Plan {
    /// Thread-safe: the value itself.
    Same,
    /// A struct copied by its `__copy()` method; `copyable` when the struct
    /// implements `Copyable<T>` itself, and how.
    Object { copyable: Option<CopyMethod> },
    /// A tuple with an element that is not thread-safe: a new tuple of each
    /// element's copy.
    Tuple,
    /// A trait value: the struct behind it, through the vtable. Whether that
    /// struct can be copied is known only at run time.
    Trait,
    Blocked(Blocker),
}

/// One step from a type to a type it contains.
#[derive(Debug, Clone)]
enum Hop {
    Field { owner: TypeName, field: String, loc: Loc },
    /// A `copy<X>(...)` call in the owner's `Copyable` method.
    Copies { owner: TypeName, copied: TypeName, loc: Loc },
}

fn struct_named<'a>(module: &'a Module, ty: &TypeName) -> Option<&'a StructDef> {
    let name = ty.to_string();
    module.structs.iter().find(|st| st.name == name)
}

fn is_raw_pointer(ty: &TypeName) -> bool {
    ty.is_pointer() || (ty.name == "__ptr" && ty.sub_types.len() == 1)
}

/// A raw pointer type as the programmer writes it (`__ptr<char>`).
fn pointer_display(ty: &TypeName) -> String {
    match ty.to_string().strip_suffix('*') {
        Some(pointee) => format!("__ptr<{}>", pointer_display(&parse_type_string(pointee))),
        None => ty.display(),
    }
}

/// The reason of `[NotCopyable("why")]`, when the struct has one: empty for
/// a bare `[NotCopyable]`. Read like `reflect.attribute<NotCopyable>()`, so
/// `reason = "..."` and joined strings work.
fn not_copyable(module: &Module, st: &StructDef) -> Option<String> {
    let attribute = st.attributes.iter().find(|a| attribute_name(a).as_deref() == Some(NOT_COPYABLE_ATTRIBUTE))?;
    Some(attribute_string(module, attribute, st.loc.file, "reason").unwrap_or_default())
}

/// How a struct implements `Copyable<T>`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CopyMethod {
    /// `copy(): T`, which copies what it holds with `copy(x)`.
    Current,
    /// The deprecated `copy(copies: Copies): T`, which takes the context.
    Deprecated,
}

/// Whether `method` is the deprecated `Copyable<T>` implementation
/// `copy(copies: Copies)`.
pub fn is_deprecated_copy_method(method: &FunctionDef) -> bool {
    method.name == "copy" && method.parameters.len() == 1 && method.parameters[0].ty.name == COPIES
}

/// Whether `st` declares `Copyable<T>`.
fn declares_copyable(st: &StructDef) -> bool {
    st.traits.iter().any(|t| t.name == COPYABLE_TRAIT)
}

/// Whether `method` of a struct that declares `Copyable<T>` implements it:
/// `copy()`.
fn is_current_copy_method(method: &FunctionDef) -> bool {
    method.name == "copy" && method.parameters.is_empty() && !method.is_static
}

/// How `st` implements `Copyable<T>`, if it does: `copy()` when it declares
/// the trait, else the deprecated `copy(copies: Copies)`.
fn copy_method(st: &StructDef) -> Option<CopyMethod> {
    if declares_copyable(st) && st.method_members.iter().any(is_current_copy_method) {
        return Some(CopyMethod::Current);
    }
    st.method_members.iter().any(is_deprecated_copy_method).then_some(CopyMethod::Deprecated)
}

/// Whether `method` of `st` is its `Copyable<T>` implementation.
fn is_copy_method_of(st: &StructDef, method: &FunctionDef) -> bool {
    match copy_method(st) {
        Some(CopyMethod::Current) => is_current_copy_method(method),
        Some(CopyMethod::Deprecated) => is_deprecated_copy_method(method),
        None => false,
    }
}

/// The `T` of each `copy<T>(...)` call (free function or method) in
/// `function`, with its location.
fn copy_calls(function: &FunctionDef) -> Vec<(TypeName, Loc)> {
    let mut found = vec![];
    crate::passes::visit_function(function, &mut |e: &Expression| match e {
        Expression::FunctionCall { function: name, loc, .. } | Expression::MethodCall { method: name, loc, .. }
            if name.starts_with("copy<") =>
        {
            if let Some(ty) = parse_type_string(name).sub_types.into_iter().next() {
                found.push((ty, *loc));
            }
        }
        _ => {}
    });
    found
}

/// The head counts and other synthesized fields every struct starts with.
fn is_head_field(field: &VariableDef) -> bool {
    field.name == "__refcount" || field.name == "__weakcount"
}

fn plan(module: &Module, safe: &ThreadSafeStructs, ty: &TypeName) -> Plan {
    if unsafe_part_in(ty, safe).is_none() {
        return Plan::Same;
    }
    if ty.is_weak() {
        return Plan::Blocked(Blocker::Weak(ty.clone()));
    }
    if ty.is_function_type() {
        return Plan::Blocked(Blocker::PlainFunction(ty.clone()));
    }
    if is_raw_pointer(ty) {
        return Plan::Blocked(Blocker::RawPointer(ty.clone()));
    }
    if crate::traits::is_trait_type(&module.traits, ty) {
        return Plan::Trait;
    }
    if ty.is_tuple() {
        return Plan::Tuple;
    }
    let Some(st) = struct_named(module, ty) else {
        return Plan::Same;
    };
    if let Some(why) = not_copyable(module, st) {
        return Plan::Blocked(Blocker::NotCopyable { ty: ty.clone(), why, loc: st.loc });
    }
    if let Some(how) = copy_method(st) {
        return Plan::Object { copyable: Some(how) };
    }
    if st.destructor.body.as_ref().is_some_and(|b| !b.items.is_empty()) {
        return Plan::Blocked(Blocker::Destructor { ty: ty.clone(), loc: st.loc });
    }
    if let Some(field) = st.field_members.iter().find(|f| is_raw_pointer(&f.ty)) {
        let loc = [field.type_loc, field.loc].into_iter().find(|l| !l.is_none()).unwrap_or(Loc::NONE);
        return Plan::Blocked(Blocker::RawPointerField { ty: ty.clone(), field: field.name.clone(), field_ty: field.ty.clone(), loc });
    }
    Plan::Object { copyable: None }
}

/// The types a copy of `ty` copies in turn, each with the step that
/// reaches it. A synthesized copy copies its fields (a weak field only maps
/// its target, so it is not followed); a `Copyable` struct copies what its
/// `copy` method passes to `copy(x)` (or the deprecated `copies.copy(x)`).
fn contained(module: &Module, ty: &TypeName, copyable: bool) -> Vec<(TypeName, Hop)> {
    let Some(st) = struct_named(module, ty) else { return vec![] };
    if copyable {
        return st
            .method_members
            .iter()
            .filter(|m| is_copy_method_of(st, m))
            .flat_map(copy_calls)
            .map(|(copied, loc)| (copied.clone(), Hop::Copies { owner: ty.clone(), copied, loc }))
            .collect();
    }
    st.field_members
        .iter()
        .filter(|f| !is_head_field(f) && !f.ty.is_weak())
        .map(|f| {
            let loc = [f.type_loc, f.loc].into_iter().find(|l| !l.is_none()).unwrap_or(Loc::NONE);
            (f.ty.clone(), Hop::Field { owner: ty.clone(), field: f.name.clone(), loc })
        })
        .collect()
}

/// The first type `ty` reaches that cannot be copied, with the steps from
/// `ty` to it.
fn first_blocker(module: &Module, safe: &ThreadSafeStructs, ty: &TypeName) -> Option<(Vec<Hop>, Blocker)> {
    fn visit(module: &Module, safe: &ThreadSafeStructs, ty: &TypeName, path: &mut Vec<Hop>, seen: &mut HashSet<String>) -> Option<Blocker> {
        if !seen.insert(ty.to_string()) {
            return None;
        }
        let copyable = match plan(module, safe, ty) {
            Plan::Same | Plan::Trait => return None,
            Plan::Blocked(blocker) => return Some(blocker),
            Plan::Object { copyable } => copyable.is_some(),
            Plan::Tuple => false,
        };
        for (inner, hop) in contained(module, ty, copyable) {
            path.push(hop);
            if let Some(blocker) = visit(module, safe, &inner, path, seen) {
                return Some(blocker);
            }
            path.pop();
        }
        None
    }
    let mut path = vec![];
    let blocker = visit(module, safe, ty, &mut path, &mut HashSet::new())?;
    Some((path, blocker))
}

// ── Model builders ───────────────────────────────────────────────────────────

fn symbol(id: &str, ty: TypeName) -> Expression {
    Expression::SymbolRef { id: id.to_string(), ty, loc: Loc::NONE }
}

fn member(lhs: Expression, name: &str) -> Expression {
    Expression::MemberRef { lhs: Box::new(lhs), name: name.to_string(), loc: Loc::NONE }
}

fn method_call(this: Expression, method: &str, args: Vec<Expression>) -> Expression {
    Expression::MethodCall { this: Box::new(this), method: method.to_string(), args, loc: Loc::NONE }
}

fn assign(lhs: Expression, rhs: Expression) -> Statement {
    Statement::Expression(Expression::Binary { op: BinaryOp::Assign, lhs: Box::new(lhs), rhs: Box::new(rhs), loc: Loc::NONE })
}

fn variable(name: &str, ty: TypeName, default: Option<Expression>, kind: Kind) -> VariableDef {
    VariableDef {
        name: name.to_string(),
        ty,
        default,
        hidden: false,
        kind,
        attributes: vec![],
        loc: Loc::NONE,
        type_loc: Loc::NONE,
        is_const: false,
    }
}

fn copies_type() -> TypeName {
    TypeName::new(COPIES)
}

/// A synthesized method of `st` that takes the copy's context as
/// `copies`.
fn method(st: &StructDef, name: &str, ty: TypeName, items: Vec<Statement>) -> FunctionDef {
    let mut method = method_without_context(st, name, ty, items);
    method.parameters.push(variable("copies", copies_type(), None, Kind::Param));
    method
}

/// A synthesized method of `st` with no parameters.
fn method_without_context(st: &StructDef, name: &str, ty: TypeName, items: Vec<Statement>) -> FunctionDef {
    FunctionDef {
        name: name.to_string(),
        ty,
        generic_params: vec![],
        parameters: vec![],
        body: Some(Block { name: name.to_string(), items, attributes: vec![] }),
        parent: Some(st.name.clone()),
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
        attributes: vec![],
        loc: st.loc,
        trait_default: None,
        owner: Loc::NONE,
    }
}

/// `_pep_copies()`: the context of the copy running on this thread.
fn context() -> Expression {
    Expression::FunctionCall { function: CONTEXT_FUNCTION.to_string(), args: vec![], loc: Loc::NONE }
}

/// The `__copy()` method of `st`, and its `_pep_fix_weak` when it has weak
/// fields to point at copies. Only a running copy calls `__copy()`.
fn copy_methods(st: &StructDef, safe: &ThreadSafeStructs, copyable: Option<CopyMethod>) -> Vec<FunctionDef> {
    let this_ty = TypeName::new(&st.name);
    let copies = || symbol("copies", copies_type());
    if let Some(how) = copyable {
        let args = match how {
            CopyMethod::Current => vec![],
            CopyMethod::Deprecated => vec![context()],
        };
        let body = vec![Statement::Return(ReturnStatement { expr: Some(method_call(Expression::ThisRef, "copy", args)), loc: Loc::NONE })];
        return vec![method_without_context(st, COPY_METHOD, this_ty, body)];
    }
    let made = || symbol("__made", this_ty.clone());
    let mut items = vec![
        Statement::Declaration(Declaration::Variable(variable("copies", copies_type(), Some(context()), Kind::Variable))),
        Statement::Declaration(Declaration::Variable(variable("__made", this_ty.clone(), Some(Expression::Allocate(this_ty.clone())), Kind::Variable))),
        Statement::Expression(method_call(copies(), &format!("register<{}>", st.name), vec![Expression::ThisRef, made()])),
    ];
    let mut weak_fields = vec![];
    for field in st.field_members.iter().filter(|f| !is_head_field(f)) {
        let original = member(Expression::ThisRef, &field.name);
        let value = if unsafe_part_in(&field.ty, safe).is_none() {
            original
        } else if let Some(target) = field.ty.weak_target() {
            weak_fields.push((field.name.clone(), target.clone()));
            original
        } else {
            method_call(copies(), &format!("copy<{}>", field.ty), vec![original])
        };
        items.push(assign(member(made(), &field.name), value));
    }
    let mut methods = vec![];
    if !weak_fields.is_empty() {
        items.push(Statement::Expression(method_call(copies(), "_defer", vec![member(made(), FIX_WEAK_METHOD)])));
        let fixes = weak_fields
            .iter()
            .map(|(field, target)| {
                let current = member(Expression::ThisRef, field);
                assign(member(Expression::ThisRef, field), method_call(copies(), &format!("_weak<{}>", target), vec![current]))
            })
            .collect();
        methods.push(method(st, FIX_WEAK_METHOD, TypeName::void(), fixes));
    }
    items.push(Statement::Return(ReturnStatement { expr: Some(made()), loc: Loc::NONE }));
    methods.insert(0, method_without_context(st, COPY_METHOD, this_ty, items));
    methods
}

/// The method that copies a value of a value struct, and whether it takes
/// the context: its own `copy()` when it implements `Copyable<T>`, else the
/// synthesized `_pep_copy_value(copies)`.
#[derive(Debug, Clone, Copy)]
struct ValueCopy {
    method: &'static str,
    takes_context: bool,
}

/// How a value of value struct `ty` is copied. `None` when `ty` is no value
/// struct.
fn value_copy_method(module: &Module, ty: &TypeName, copyable: Option<CopyMethod>) -> Option<ValueCopy> {
    struct_named(module, ty).filter(|st| st.is_value())?;
    Some(match copyable {
        Some(CopyMethod::Current) => ValueCopy { method: "copy", takes_context: false },
        Some(CopyMethod::Deprecated) => ValueCopy { method: "copy", takes_context: true },
        None => ValueCopy { method: COPY_VALUE_METHOD, takes_context: true },
    })
}

/// `value.method(copies)`, or `value.method()` when it takes no context.
fn call_value_copy(how: ValueCopy, value: Expression, copies: &Expression, loc: Loc) -> Expression {
    let args = if how.takes_context { vec![copies.clone()] } else { vec![] };
    Expression::MethodCall { this: Box::new(value), method: how.method.to_string(), args, loc }
}

/// The `_pep_copy_value` method of value struct `st`: a copy of `this`
/// whose fields that are not thread-safe hold copies. A weak field keeps
/// its target, which no copy of the value can point at.
fn copy_value_method(st: &StructDef, safe: &ThreadSafeStructs) -> FunctionDef {
    let this_ty = TypeName::new(&st.name);
    let copies = || symbol("copies", copies_type());
    let made = || symbol("__made", this_ty.clone());
    let mut items = vec![Statement::Declaration(Declaration::Variable(variable("__made", this_ty.clone(), Some(Expression::ThisRef), Kind::Variable)))];
    let copy_field = |field: &VariableDef| {
        if unsafe_part_in(&field.ty, safe).is_none() || field.ty.weak_target().is_some() {
            return None;
        }
        let original = member(Expression::ThisRef, &field.name);
        Some(assign(member(made(), &field.name), method_call(copies(), &format!("copy<{}>", field.ty), vec![original])))
    };
    match &st.enum_cases {
        // A value enum's cases share storage: only the case `this` holds
        // has values to copy.
        Some(cases) if st.has_union_layout() => {
            for case in cases.iter().filter(|c| !c.payload.is_empty()) {
                let stores: Vec<Statement> = st
                    .field_members
                    .iter()
                    .filter(|f| case.payload.iter().any(|(value, _)| payload_field(&case.name, value) == f.name))
                    .filter_map(copy_field)
                    .collect();
                if stores.is_empty() {
                    continue;
                }
                let is_case = Expression::Binary {
                    op: BinaryOp::Equal,
                    lhs: Box::new(member(Expression::ThisRef, TAG_FIELD)),
                    rhs: Box::new(Expression::IntLiteral(case.value)),
                    loc: Loc::NONE,
                };
                items.push(Statement::Branch(Branch {
                    condition: is_case,
                    if_block: Block { name: String::new(), items: stores, attributes: vec![] },
                    else_block: None,
                }));
            }
        }
        _ => items.extend(st.field_members.iter().filter_map(copy_field)),
    }
    items.push(Statement::Return(ReturnStatement { expr: Some(made()), loc: Loc::NONE }));
    method(st, COPY_VALUE_METHOD, this_ty, items)
}

// ── The pass ─────────────────────────────────────────────────────────────────

/// The `T` of a `__copy<T>(value, copies)` call.
fn copy_intrinsic(expr: &Expression) -> Option<TypeName> {
    let Expression::FunctionCall { function, args, .. } = expr else { return None };
    if args.len() != 2 || function.split('<').next() != Some(COPY_INTRINSIC) {
        return None;
    }
    parse_type_string(function).sub_types.into_iter().next()
}

/// Every function body that is compiled: not a generic base.
fn compiled_functions(module: &mut Module) -> Vec<&mut FunctionDef> {
    let mut out: Vec<&mut FunctionDef> = module.functions.iter_mut().filter(|f| !f.is_generic_func).collect();
    for st in module.structs.iter_mut().filter(|st| !(st.name == st.ty.name && st.ty.is_generic())) {
        out.extend(st.method_members.iter_mut().filter(|m| !m.is_generic_func));
        out.extend(st.constructors.iter_mut());
    }
    out
}

/// The copies the program asks for: each `copy<T>(x)` call in compiled
/// code outside a `Copyable` implementation, which only copies what a
/// request reaches.
fn requests(module: &mut Module) -> Vec<(TypeName, Loc)> {
    let mut found: Vec<(TypeName, Loc)> = vec![];
    let copyable: HashSet<String> =
        module.structs.iter().filter(|st| copy_method(st) == Some(CopyMethod::Current)).map(|st| st.name.clone()).collect();
    for function in compiled_functions(module) {
        let implements = is_deprecated_copy_method(function)
            || (is_current_copy_method(function) && function.parent.as_ref().is_some_and(|p| copyable.contains(p)));
        // The runtime's `copy<T>` copies for its caller, whose call is the
        // request (or is inside a `Copyable` implementation).
        let runtime_copy = function.parent.is_none() && function.name.starts_with("copy<");
        if implements || runtime_copy || function.name == COPY_METHOD || function.name == COPY_VALUE_METHOD || function.name == COPY_TRAIT_METHOD {
            continue;
        }
        for (ty, loc) in copy_calls(function) {
            if !found.iter().any(|(t, _)| *t == ty) {
                found.push((ty, loc));
            }
        }
    }
    found
}

/// Lower every concrete `__copy<T>` call and synthesize the `__copy()`
/// methods they need. Returns whether it added anything (the
/// specialization loop runs again to specialize what those call).
pub fn synthesize_copies(module: &mut Module) -> bool {
    let safe = ThreadSafeStructs::of(module);
    for (ty, loc) in requests(module) {
        if let Some((path, blocker)) = first_blocker(module, &safe, &ty) {
            crate::errors::report(cannot_copy(module, &ty, loc, path, blocker));
            return false;
        }
    }
    let censuses_added = lower_censuses(module, &safe);
    lower_copy_objects(module);
    let traits_added = add_trait_copies(module, &safe);
    let mut calls: Vec<(TypeName, Loc)> = vec![];
    for function in compiled_functions(module) {
        collect_calls(function, &mut calls);
    }
    if calls.is_empty() {
        return censuses_added || traits_added;
    }
    // What each `__copy<T>` becomes: the value, a `_copy_object<T>` call, or
    // a panic.
    let mut lowered: Vec<(TypeName, Lowering)> = vec![];
    let mut needed: Vec<(String, Option<CopyMethod>)> = vec![];
    for (ty, _) in &calls {
        let lowering = match plan(module, &safe, ty) {
            Plan::Same => Lowering::Same,
            Plan::Object { copyable } => {
                let name = ty.to_string();
                if !needed.iter().any(|(n, _)| *n == name) {
                    needed.push((name, copyable));
                }
                match value_copy_method(module, ty, copyable) {
                    Some(method) => Lowering::Value(method),
                    None => Lowering::Object,
                }
            }
            Plan::Tuple => match first_blocker(module, &safe, ty) {
                Some((_, blocker)) => Lowering::Fail(format!("cannot copy '{}', which {}", ty.display(), blocker.what())),
                None => Lowering::Tuple(tuple_parts(module, &safe, ty, &mut needed)),
            },
            Plan::Trait => Lowering::Trait,
            Plan::Blocked(blocker) => Lowering::Fail(format!("cannot copy '{}', which {}", ty.display(), blocker.what())),
        };
        lowered.push((ty.clone(), lowering));
    }
    let mut added = traits_added;
    for (name, copyable) in needed {
        let Some(index) = module.structs.iter().position(|st| st.name == name) else { continue };
        if module.structs[index].method_members.iter().any(|m| m.name == COPY_METHOD || m.name == COPY_VALUE_METHOD) {
            continue;
        }
        let methods = if module.structs[index].is_value() {
            if copyable.is_some() {
                continue;
            }
            vec![copy_value_method(&module.structs[index], &safe)]
        } else {
            copy_methods(&module.structs[index], &safe, copyable)
        };
        module.structs[index].method_members.extend(methods);
        added = true;
    }
    for function in compiled_functions(module) {
        crate::passes::walk_function(function, &mut |e: &mut Expression| {
            let Some(ty) = copy_intrinsic(e) else { return };
            let Some((_, lowering)) = lowered.iter().find(|(t, _)| *t == ty) else { return };
            let Expression::FunctionCall { args, loc, .. } = e else { return };
            let copies = args.pop().unwrap();
            let value = args.pop().unwrap();
            let loc = *loc;
            *e = match lowering {
                Lowering::Same => value,
                Lowering::Object => Expression::MethodCall { this: Box::new(copies), method: format!("_copy_object<{}>", ty), args: vec![value], loc },
                Lowering::Value(how) => call_value_copy(*how, value, &copies, loc),
                Lowering::Tuple(parts) => copy_tuple(&ty, parts, value, &copies, loc),
                Lowering::Trait => Expression::MethodCall { this: Box::new(copies), method: format!("_copy_trait<{}>", ty), args: vec![value], loc },
                Lowering::Fail(message) => Expression::FunctionCall {
                    function: format!("_pep_copy_failed<{}>", ty),
                    args: vec![Expression::StringLiteral { value: message.clone(), is_raw: true, loc: Loc::NONE }],
                    loc,
                },
            };
        });
    }
    added || censuses_added || lowered.iter().any(|(_, l)| matches!(l, Lowering::Fail(_)))
}

/// Lower every `__copy_object<T>(value)` whose `T` is a struct to
/// `value.__copy()`.
fn lower_copy_objects(module: &mut Module) {
    let structs: HashSet<String> = module.structs.iter().map(|st| st.name.clone()).collect();
    for function in compiled_functions(module) {
        crate::passes::walk_function(function, &mut |e: &mut Expression| {
            let Expression::FunctionCall { function, args, loc } = e else { return };
            if args.len() != 1 || function.split('<').next() != Some(COPY_OBJECT_INTRINSIC) {
                return;
            }
            let Some(ty) = parse_type_string(function).sub_types.into_iter().next() else { return };
            if !structs.contains(&ty.to_string()) {
                return;
            }
            let value = args.pop().unwrap();
            *e = Expression::MethodCall { this: Box::new(value), method: COPY_METHOD.to_string(), args: vec![], loc: *loc };
        });
    }
}

/// The `T` of a `__census<T>(slot, waiting)` call.
fn census_intrinsic(expr: &Expression) -> Option<TypeName> {
    let Expression::FunctionCall { function, args, .. } = expr else { return None };
    if args.len() != 2 || function.split('<').next() != Some(CENSUS_INTRINSIC) {
        return None;
    }
    parse_type_string(function).sub_types.into_iter().next()
}

/// Lower every concrete `__census<T>(slot, waiting)`: to a `_pep_check_sync<T>` call
/// when a `T` can be copied, and to the slot alone (which does nothing) when
/// `T` is thread-safe, so nothing outside can share it, or cannot be copied.
/// Returns whether it added a call to specialize.
fn lower_censuses(module: &mut Module, safe: &ThreadSafeStructs) -> bool {
    let mut types: Vec<TypeName> = vec![];
    for function in compiled_functions(module) {
        crate::passes::walk_function(function, &mut |e: &mut Expression| {
            if let Some(ty) = census_intrinsic(e)
                && !types.contains(&ty)
            {
                types.push(ty);
            }
        });
    }
    let checked: Vec<(TypeName, bool)> = types
        .into_iter()
        .map(|ty| {
            let can = !matches!(plan(module, safe, &ty), Plan::Same | Plan::Trait) && first_blocker(module, safe, &ty).is_none();
            (ty, can)
        })
        .collect();
    let mut added = false;
    for function in compiled_functions(module) {
        crate::passes::walk_function(function, &mut |e: &mut Expression| {
            let Some(ty) = census_intrinsic(e) else { return };
            let Some((_, can)) = checked.iter().find(|(t, _)| *t == ty) else { return };
            let Expression::FunctionCall { args, loc, .. } = e else { return };
            let waiting = args.pop().unwrap();
            let slot = args.pop().unwrap();
            let loc = *loc;
            *e = if *can {
                added = true;
                let locked = Expression::StringLiteral { value: format!("Mutex<{}>", ty.display()), is_raw: true, loc: Loc::NONE };
                Expression::FunctionCall { function: format!("{CENSUS_FUNCTION}<{ty}>"), args: vec![slot, waiting, locked], loc }
            } else {
                slot
            };
        });
    }
    added
}

/// What a `__copy<T>` call lowers to.
enum Lowering {
    Same,
    Object,
    /// A value struct, through this method of the value: its `copy` when
    /// it implements `Copyable<T>`, else the synthesized one.
    Value(ValueCopy),
    /// A new tuple of each element's copy.
    Tuple(Vec<Part>),
    /// A trait value, through `copies._copy_trait<T>`.
    Trait,
    /// A panic with this message: nothing the program asks for copies a `T`.
    Fail(String),
}

/// How a tuple copies one element.
enum Part {
    /// Thread-safe: the element itself.
    Same,
    /// A struct, through `copies._copy_object<T>`.
    Object(TypeName),
    /// A value struct, through this method of the element (see
    /// [`Lowering::Value`]).
    Value(ValueCopy),
    /// A nested tuple, element by element.
    Tuple(TypeName, Vec<Part>),
    /// A trait value, through `copies.copy<T>`, which lowers to
    /// `_copy_trait<T>`.
    Trait(TypeName),
}

/// How to copy each element of tuple `ty`, whose elements can all be
/// copied; records each struct element in `needed` so it gets `__copy()`.
fn tuple_parts(module: &Module, safe: &ThreadSafeStructs, ty: &TypeName, needed: &mut Vec<(String, Option<CopyMethod>)>) -> Vec<Part> {
    ty.sub_types
        .iter()
        .map(|element| match plan(module, safe, element) {
            Plan::Object { copyable } => {
                let name = element.to_string();
                if !needed.iter().any(|(n, _)| *n == name) {
                    needed.push((name, copyable));
                }
                match value_copy_method(module, element, copyable) {
                    Some(method) => Part::Value(method),
                    None => Part::Object(element.clone()),
                }
            }
            Plan::Tuple => Part::Tuple(element.clone(), tuple_parts(module, safe, element, needed)),
            Plan::Trait => Part::Trait(element.clone()),
            Plan::Same | Plan::Blocked(_) => Part::Same,
        })
        .collect()
}

/// `(copy of value.0, copy of value.1, ...)`. `value` is the parameter of
/// `_Copies.copy<T>`, so reading it once per element is safe.
fn copy_tuple(ty: &TypeName, parts: &[Part], value: Expression, copies: &Expression, loc: Loc) -> Expression {
    let args = parts
        .iter()
        .enumerate()
        .map(|(i, part)| {
            let element = Expression::MemberRef { lhs: Box::new(value.clone()), name: i.to_string(), loc };
            match part {
                Part::Same => element,
                Part::Object(t) => Expression::MethodCall {
                    this: Box::new(copies.clone()),
                    method: format!("_copy_object<{}>", t),
                    args: vec![element],
                    loc,
                },
                Part::Value(how) => call_value_copy(*how, element, copies, loc),
                Part::Tuple(t, inner) => copy_tuple(t, inner, element, copies, loc),
                Part::Trait(t) => Expression::MethodCall { this: Box::new(copies.clone()), method: format!("copy<{}>", t), args: vec![element], loc },
            }
        })
        .collect();
    Expression::FunctionCall { function: ty.to_string(), args, loc }
}

fn collect_calls(function: &mut FunctionDef, calls: &mut Vec<(TypeName, Loc)>) {
    crate::passes::walk_function(function, &mut |e: &mut Expression| {
        if let Some(ty) = copy_intrinsic(e)
            && !calls.iter().any(|(t, _)| *t == ty)
        {
            calls.push((ty, e.loc()));
        }
    });
}

/// Make every trait copyable through its values: give each trait a
/// `_pep_copy_trait(copies): Tr` member, and each concrete struct that
/// declares a trait the method that fills that vtable slot. Every trait gets
/// the slot, copied or not, so a vtable depends only on the trait's and the
/// struct's declarations: a unit's cached object stays valid when another
/// unit starts copying the trait. A struct specialized later gets its
/// method on a later round. Returns whether it added anything.
fn add_trait_copies(module: &mut Module, safe: &ThreadSafeStructs) -> bool {
    let mut added = false;
    for def in module.traits.iter_mut() {
        if !def.methods.iter().any(|m| m.name == COPY_TRAIT_METHOD) {
            def.methods.push(trait_copy_member(def));
            added = true;
        }
    }
    let wanting: Vec<usize> = (0..module.structs.len())
        .filter(|&i| {
            let st = &module.structs[i];
            !(st.name == st.ty.name && st.ty.is_generic())
                && st.traits.iter().any(|t| crate::traits::is_trait_type(&module.traits, t))
                && !st.method_members.iter().any(|m| m.name == COPY_TRAIT_METHOD)
        })
        .collect();
    for index in wanting {
        let this_ty = TypeName::new(&module.structs[index].name);
        // A struct that cannot be copied panics, naming what blocks it.
        let isolated = has_attribute(&module.structs[index].attributes, crate::passes::check_confinement::ISOLATED_ATTRIBUTE);
        let blocker = if isolated {
            // A guard never leaves its `with` block, so a copy of one would
            // be a second lock.
            Some((vec![], Blocker::NotCopyable { ty: this_ty.clone(), why: String::new(), loc: Loc::NONE }))
        } else {
            first_blocker(module, safe, &this_ty)
        };
        let copied = match blocker {
            None => method_call(symbol("copies", copies_type()), &format!("copy<{}>", this_ty), vec![Expression::ThisRef]),
            Some((path, blocker)) => {
                let message = if path.is_empty() {
                    format!("cannot copy the '{}' behind a trait value, which {}", this_ty.display(), blocker.what())
                } else {
                    format!(
                        "cannot copy the '{}' behind a trait value because it contains '{}', which {}",
                        this_ty.display(),
                        blocker.ty().display(),
                        blocker.what()
                    )
                };
                Expression::FunctionCall {
                    function: format!("_pep_copy_failed<{}>", this_ty),
                    args: vec![Expression::StringLiteral { value: message, is_raw: true, loc: Loc::NONE }],
                    loc: Loc::NONE,
                }
            }
        };
        let body = vec![Statement::Return(ReturnStatement { expr: Some(copied), loc: Loc::NONE })];
        let st = &mut module.structs[index];
        let copy = method(st, COPY_TRAIT_METHOD, this_ty, body);
        st.method_members.push(copy);
        added = true;
    }
    added
}

/// The trait member `_pep_copy_trait(copies: _Copies): Tr<T, ...>` of `def`,
/// which returns the trait type itself at the trait's own parameters.
fn trait_copy_member(def: &TraitDef) -> FunctionDef {
    let ty = TypeName::with_args(&def.name, def.generic_params.iter().map(|p| TypeName::new(&p.name)).collect());
    FunctionDef {
        name: COPY_TRAIT_METHOD.to_string(),
        ty,
        generic_params: vec![],
        parameters: vec![variable("copies", copies_type(), None, Kind::Param)],
        body: None,
        parent: None,
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
        attributes: vec![],
        loc: def.loc,
        trait_default: None,
        owner: Loc::NONE,
    }
}

// ── The error ────────────────────────────────────────────────────────────────

/// Where the program asks to copy a `ty`: a `copy(x)` call or a
/// `copies.copy(x)` call. The one
/// in the earliest file wins: the program's own files come before the
/// runtime's.
fn request_site(module: &Module, ty: &TypeName) -> Option<Loc> {
    let spec = format!("copy<{}>", ty);
    let mut found: Vec<Loc> = vec![];
    let mut look = |function: &FunctionDef| {
        crate::passes::visit_function(function, &mut |e: &Expression| match e {
            Expression::FunctionCall { function, loc, .. } | Expression::MethodCall { method: function, loc, .. }
                if *function == spec && !loc.is_none() =>
            {
                found.push(*loc)
            }
            _ => {}
        });
    };
    for function in &module.functions {
        look(function);
    }
    for st in &module.structs {
        for m in st.method_members.iter().chain(st.constructors.iter()) {
            look(m);
        }
    }
    found.into_iter().min_by_key(|loc| loc.file.0)
}

/// The end of the declaration of the struct named at `loc` (just past its
/// closing brace), found by matching braces in its source.
pub(crate) fn struct_end(module: &Module, loc: Loc) -> Option<usize> {
    let (_, text) = module.sources.get(loc.file)?;
    let bytes = text.as_bytes();
    let mut i = text[loc.span.start..].find('{')? + loc.span.start;
    let mut depth = 0usize;
    while i < bytes.len() {
        match bytes[i] {
            b'#' => {
                while i < bytes.len() && bytes[i] != b'\n' {
                    i += 1;
                }
            }
            b'"' => {
                i += 1;
                while i < bytes.len() && bytes[i] != b'"' {
                    if bytes[i] == b'\\' {
                        i += 1;
                    }
                    i += 1;
                }
            }
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(i + 1);
                }
            }
            _ => {}
        }
        i += 1;
    }
    None
}

/// The `Copyable` skeleton for `ty`, as the note shows it (indented) and as
/// the fix inserts it.
/// `ty` as the user writes it. Text outside single quotes (the skeleton, a
/// fix's title) is not demangled when the diagnostic renders, and a struct
/// that shares a runtime type's name (`Handle`) is mangled (`Handle@main`).
fn written(ty: &TypeName) -> String {
    pepper_parser::namespace::demangle(&format!("'{}'", ty.display())).trim_matches('\'').to_string()
}

fn skeleton(ty: &TypeName, indent: &str) -> String {
    let t = written(ty);
    [
        format!("extend {t} with Copyable<{t}> {{"),
        format!("    copy(): {t} {{"),
        "        # Build the copy; copy each struct field with copy(field).".to_string(),
        format!("        panic(\"copying '{t}' is not implemented\");"),
        "        return this;".to_string(),
        "    }".to_string(),
        "}".to_string(),
    ]
    .iter()
    .map(|line| format!("{indent}{line}"))
    .collect::<Vec<_>>()
    .join("\n")
}

fn cannot_copy(module: &Module, root: &TypeName, fallback: Loc, path: Vec<Hop>, blocker: Blocker) -> Diagnostic {
    let blocked = blocker.ty().clone();
    let message = if path.is_empty() {
        format!("cannot copy '{}', which {}", root.display(), blocker.what())
    } else {
        format!("cannot copy '{}' because it contains '{}', which {}", root.display(), blocked.display(), blocker.what())
    };
    let at = request_site(module, root).unwrap_or(fallback);
    let mut diagnostic = Diagnostic::error(message).at(at);
    for hop in &path {
        diagnostic = match hop {
            Hop::Field { owner, field, loc } => {
                let step = if owner.is_tuple() { format!("element {}", field) } else { format!("field '{}'", field) };
                diagnostic.with_note(format!("'{}' reaches it through {}", owner.display(), step), loc.known())
            }
            // A runtime container's `copy` method is not the program's to
            // change: point only at a `Copyable` method in the error's file.
            Hop::Copies { owner, copied, loc } if at.file == loc.file => {
                diagnostic.with_note(format!("'{}' copies a '{}' here", owner.display(), copied.display()), loc.known())
            }
            Hop::Copies { owner, copied, .. } => {
                diagnostic.with_note(format!("'{}' copies its values of type '{}'", owner.display(), copied.display()), None)
            }
        };
    }
    match &blocker {
        Blocker::Destructor { ty, loc } => {
            diagnostic = diagnostic.with_note(
                format!("'{}' has a destructor, so copying its fields would release what it owns twice", ty.display()),
                loc.known(),
            );
        }
        Blocker::RawPointerField { ty, field, field_ty, loc } => {
            diagnostic = diagnostic.with_note(
                format!("'{}' has raw pointer field '{}' of type '{}'", ty.display(), field, pointer_display(field_ty)),
                loc.known(),
            );
        }
        Blocker::NotCopyable { ty, why, loc } => {
            let why = if why.is_empty() { "cannot be copied".to_string() } else { why.clone() };
            return diagnostic.with_note(format!("'{}' {}", ty.display(), why), loc.known());
        }
        Blocker::PlainFunction(ty) => {
            return diagnostic.with_note(
                format!(
                    "a plain function value may capture values that are not thread-safe; declare the type '{}' to pass it by reference",
                    ty.with_sharing(true).display()
                ),
                None,
            );
        }
        Blocker::RawPointer(_) => {
            return diagnostic.with_note("the compiler cannot tell what a raw pointer points at; wrap it in a struct that implements 'Copyable<T>'", None);
        }
        Blocker::Weak(_) => {
            return diagnostic.with_note("keep the weak reference in a struct field, such as the one in 'Weak<T>', which copies it", None);
        }
    }
    // A struct that is not trivially copyable can say how it is copied.
    let (ty, decl) = match &blocker {
        Blocker::Destructor { ty, loc } => (ty, *loc),
        Blocker::RawPointerField { ty, .. } => (ty, struct_named(module, ty).map(|st| st.loc).unwrap_or(Loc::NONE)),
        _ => unreachable!(),
    };
    diagnostic = diagnostic.with_note(
        format!("implement 'Copyable<{}>' to say how to copy it:\n{}", written(ty), skeleton(ty, "    ")),
        None,
    );
    // The editor applies a fix to the file it shows: offer one when the
    // struct is declared in the file the error is in.
    if !decl.is_none()
        && diagnostic.loc.is_some_and(|l| l.file == decl.file)
        && let Some(end) = struct_end(module, decl)
    {
        let insert = Loc::new(decl.file, pepper_parser::ast::Span { start: end, end });
        diagnostic = diagnostic.with_fix(Fix {
            message: format!("Implement Copyable<{}>", written(ty)),
            edits: vec![Edit { loc: insert, replacement: format!("\n\n{}", skeleton(ty, "")) }],
        });
    }
    diagnostic
}
