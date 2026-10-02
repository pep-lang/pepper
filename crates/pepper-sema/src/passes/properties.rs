//! Property accesses (`docs/src/language/properties.md`). The builder lowers
//! each property to plain members (see [`PropertyDef`]): its storage field,
//! a getter method and, with a `set`, a setter method. This rewrites the
//! accesses, once the receiver's type is known:
//!
//! - a read `x.p` is the storage (`x.p` itself, for a default `get`) or the
//!   call `x.__get_p()`;
//! - an assignment `x.p = v` is a store to the storage (default `set`, or no
//!   `set` inside the struct's own code) or the call `x.__set_p(v)`;
//! - a compound assignment `x.p += v` (and `++`/`--`) reads, then writes,
//!   evaluating `x` once;
//! - a bare `p` in the struct's methods is `this.p`.
//!
//! It runs inside `resolve_implicit_types` (which types the receivers), so
//! every round of that pass, generic specializations included, lowers what
//! it newly types. A rewritten access is a method call or a storage access,
//! which a later round leaves alone.

use crate::model::*;
use crate::type_name::TypeName;
use std::collections::HashMap;

/// The program's properties, by owner (struct or trait base name).
#[derive(Default)]
pub(crate) struct Properties {
    by_owner: HashMap<String, Vec<PropertyDef>>,
    /// Where every extension method is declared: an extension's methods are
    /// not their struct's own code, even once copied into it.
    extension_methods: std::collections::HashSet<Loc>,
}

impl Properties {
    pub(crate) fn of(module: &Module) -> Self {
        let mut by_owner: HashMap<String, Vec<PropertyDef>> = HashMap::new();
        for property in &module.properties {
            by_owner.entry(property.owner.clone()).or_default().push(property.clone());
        }
        let extension_methods = module.extensions.iter().flat_map(|e| e.methods.iter().map(|m| m.loc)).collect();
        Properties { by_owner, extension_methods }
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.by_owner.is_empty()
    }

    /// Property `name` of a value of type `ty`, if it has one.
    pub(crate) fn find(&self, ty: &TypeName, name: &str) -> Option<&PropertyDef> {
        if self.by_owner.is_empty() || ty.is_pointer() {
            return None;
        }
        self.by_owner.get(ty.name.as_str())?.iter().find(|p| p.name == name)
    }
}

/// Where an access is written: the struct whose code it is in, if any, and
/// whether that code is a constructor.
pub(crate) struct Site<'a> {
    pub(crate) current: Option<&'a TypeName>,
    pub(crate) in_constructor: bool,
    /// The name of the function or method the code is in.
    pub(crate) function: &'a str,
    /// Where that function is declared.
    pub(crate) function_loc: Loc,
}

impl Site<'_> {
    /// Whether `this.name` here is `property`'s storage rather than the
    /// property: in its own accessors, where `field` became `this.name`
    /// when the storage keeps the property's name (a default `get`).
    fn is_own_storage(&self, receiver: &Expression, property: &PropertyDef) -> bool {
        matches!(receiver, Expression::ThisRef)
            && property.storage.as_deref() == Some(property.name.as_str())
            && (self.function == getter_name(&property.name) || self.function == setter_name(&property.name))
    }
}

/// Rewrite the property access at `e`, if it is one (see the module
/// documentation). `type_of` types an expression in the walk's scope, and
/// `is_local` says whether a name is a parameter or local there.
pub(crate) fn lower(
    e: &mut Expression,
    properties: &Properties,
    site: &Site,
    type_of: &dyn Fn(&Expression) -> TypeName,
    is_local: &dyn Fn(&str) -> bool,
) {
    if properties.is_empty() {
        return;
    }
    match e {
        Expression::Binary { op, lhs, rhs, loc } if op.is_assignment() => {
            // Code the compiler synthesizes (a constructor's field
            // initializations, `_pep_copy`) has no location and initializes
            // the storage itself. A constructor's `this.p` parameter, which
            // assigns the property, is the exception.
            let init_parameter = matches!(rhs.as_ref(), Expression::SymbolRef { id, .. } if id.starts_with("__init_"));
            if *loc == Loc::NONE && !init_parameter {
                return;
            }
            bare_to_member(lhs, properties, site, is_local);
            let Expression::MemberRef { lhs: receiver, name, loc: name_loc } = lhs.as_mut() else { return };
            let Some(property) = properties.find(&type_of(receiver), name) else { return };
            if site.is_own_storage(receiver, property) {
                return;
            }
            let property = property.clone();
            let at = *name_loc;
            if *op != BinaryOp::Assign && is_direct(&property, site, properties) {
                if let Some(storage) = &property.storage {
                    *name = storage.clone();
                }
                return;
            }
            if *op == BinaryOp::Assign {
                let receiver = std::mem::replace(receiver.as_mut(), Expression::ThisRef);
                let value = std::mem::replace(rhs.as_mut(), Expression::ThisRef);
                *e = write(receiver, &property, value, at, site, properties);
                return;
            }
            let Some(base) = compound_base(*op) else { return };
            let operand = std::mem::replace(rhs.as_mut(), Expression::ThisRef);
            let receiver = std::mem::replace(receiver.as_mut(), Expression::ThisRef);
            *e = read_modify_write(receiver, &property, base, operand, at, *loc, site, properties);
        }
        Expression::Unary { op, operand, loc } if matches!(op, UnaryOp::PreInc | UnaryOp::PostInc | UnaryOp::PreDec | UnaryOp::PostDec) => {
            bare_to_member(operand, properties, site, is_local);
            let Expression::MemberRef { lhs: receiver, name, loc: name_loc } = operand.as_mut() else { return };
            let Some(property) = properties.find(&type_of(receiver), name) else { return };
            if site.is_own_storage(receiver, property) {
                return;
            }
            let property = property.clone();
            let at = *name_loc;
            let base = if matches!(op, UnaryOp::PreInc | UnaryOp::PostInc) { BinaryOp::Add } else { BinaryOp::Sub };
            if is_direct(&property, site, properties) {
                if let Some(storage) = &property.storage {
                    *name = storage.clone();
                }
                return;
            }
            let receiver = std::mem::replace(receiver.as_mut(), Expression::ThisRef);
            *e = read_modify_write(receiver, &property, base, Expression::IntLiteral(1), at, *loc, site, properties);
        }
        Expression::SymbolRef { .. } => {
            if bare_to_member(e, properties, site, is_local) {
                lower(e, properties, site, type_of, is_local);
            }
        }
        // `x.count()` where `count` is a property: it is read without `()`.
        Expression::MethodCall { this, method, args, loc } if args.is_empty() => {
            let Some(property) = properties.find(&type_of(this), method) else { return };
            // A property of function type is called through: `x.callback()`.
            let read = Expression::MemberRef { lhs: this.clone(), name: method.clone(), loc: *loc };
            if type_of(&read).is_callable() {
                return;
            }
            crate::errors::report(
                Diagnostic::error(format!("'{}' is a property, not a method; read it without '()'", method))
                    .at(*loc)
                    .with_note(format!("'{}' declared here", method), Some(property.loc)),
            );
        }
        Expression::MemberRef { lhs: receiver, name, loc } => {
            let Some(property) = properties.find(&type_of(receiver), name) else { return };
            if site.is_own_storage(receiver, property) {
                return;
            }
            let receiver = std::mem::replace(receiver.as_mut(), Expression::ThisRef);
            *e = read(receiver, &property.clone(), *loc);
        }
        _ => {}
    }
}

/// A bare `p` in the methods of a struct with a property `p` (and no local
/// or parameter of that name) is `this.p`. A property with a default `get`
/// is left alone: its storage is the field `p`, which `convert_member_refs`
/// binds like any other.
fn bare_to_member(e: &mut Expression, properties: &Properties, site: &Site, is_local: &dyn Fn(&str) -> bool) -> bool {
    let Expression::SymbolRef { id, loc, .. } = e else { return false };
    // An instance method of an enum whose cases carry nothing is the free
    // function `E::m`, whose `this` is its first parameter.
    if site.current.is_none()
        && let Some((enum_name, _)) = crate::enums::method_of(site.function)
    {
        let ty = TypeName::new(enum_name);
        if properties.find(&ty, id).is_none() || is_local(id) || !is_local("this") {
            return false;
        }
        let this = Expression::SymbolRef { id: "this".to_string(), ty, loc: Loc::NONE };
        *e = Expression::MemberRef { lhs: Box::new(this), name: id.clone(), loc: *loc };
        return true;
    }
    let Some(current) = site.current else { return false };
    let Some(property) = properties.find(current, id) else { return false };
    if property.get == AccessorKind::Default && property.set != Some(AccessorKind::Body) || is_local(id) {
        return false;
    }
    *e = Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: id.clone(), loc: *loc };
    true
}

/// Whether code at `site` belongs to the struct that declares `property`:
/// its constructors and the methods in its body, not an extension's.
fn inside(property: &PropertyDef, site: &Site, properties: &Properties) -> bool {
    !property.in_trait
        && site.current.is_some_and(|c| c.name == property.owner)
        && !properties.extension_methods.contains(&site.function_loc)
}

/// Whether both reading and writing `property` at `site` go straight to its
/// storage.
fn is_direct(property: &PropertyDef, site: &Site, properties: &Properties) -> bool {
    property.storage.is_some()
        && property.get == AccessorKind::Default
        && match property.set {
            Some(AccessorKind::Default) => true,
            Some(AccessorKind::Body) => false,
            None => inside(property, site, properties) && (!property.shared || site.in_constructor),
        }
}

/// The value of `receiver.p`.
fn read(receiver: Expression, property: &PropertyDef, at: Loc) -> Expression {
    match (&property.storage, property.get) {
        (Some(storage), AccessorKind::Default) if !property.in_trait => {
            Expression::MemberRef { lhs: Box::new(receiver), name: storage.clone(), loc: at }
        }
        _ => Expression::MethodCall { this: Box::new(receiver), method: getter_name(&property.name), args: vec![], loc: at },
    }
}

/// `receiver.p = value`.
fn write(receiver: Expression, property: &PropertyDef, value: Expression, at: Loc, site: &Site, properties: &Properties) -> Expression {
    let store = |storage: &str, receiver: Expression, value: Expression| Expression::Binary {
        op: BinaryOp::Assign,
        lhs: Box::new(Expression::MemberRef { lhs: Box::new(receiver), name: storage.to_string(), loc: at }),
        rhs: Box::new(value),
        loc: at,
    };
    let call = |receiver: Expression, value: Expression| Expression::MethodCall {
        this: Box::new(receiver),
        method: setter_name(&property.name),
        args: vec![value],
        loc: at,
    };
    match (property.set, &property.storage) {
        (Some(AccessorKind::Default), Some(storage)) if !property.in_trait => store(storage, receiver, value),
        (Some(_), _) => call(receiver, value),
        (None, Some(storage)) if inside(property, site, properties) => {
            if property.shared && !site.in_constructor {
                crate::errors::report(
                    Diagnostic::error(format!(
                        "cannot assign to '{}' outside a constructor: the storage of a '[{}]' struct's property is 'const'",
                        property.name, SHARED_ATTRIBUTE
                    ))
                    .at(at)
                    .with_note(format!("'{}' declared here", property.name), Some(property.loc)),
                );
            }
            store(storage, receiver, value)
        }
        (None, _) => {
            crate::errors::report(
                Diagnostic::error(format!("cannot assign to '{}': it has no 'set' accessor", property.name))
                    .at(at)
                    .with_note(format!("'{}' declared here", property.name), Some(property.loc)),
            );
            Expression::MemberRef { lhs: Box::new(receiver), name: property.name.clone(), loc: at }
        }
    }
}

/// The id of the `WithSubject` that evaluates the receiver of the compound
/// assignment at `at` once: made from its location, so a program compiles
/// the same way every time, and with the top bit set, so it never meets a
/// `match` site's (numbered from 0).
fn subject_id(at: Loc) -> usize {
    (1 << 62) | ((at.file.0 as usize) << 32) | at.span.start
}

/// `receiver.p op= operand`: read `p`, combine, write it back, evaluating
/// `receiver` once.
fn read_modify_write(
    receiver: Expression,
    property: &PropertyDef,
    op: BinaryOp,
    operand: Expression,
    at: Loc,
    op_loc: Loc,
    site: &Site,
    properties: &Properties,
) -> Expression {
    let update = |receiver: Expression| {
        let current = read(receiver.clone(), property, at);
        let value = Expression::Binary { op, lhs: Box::new(current), rhs: Box::new(operand), loc: op_loc };
        write(receiver, property, value, at, site, properties)
    };
    match receiver {
        Expression::ThisRef | Expression::SymbolRef { .. } => update(receiver),
        subject => {
            let id = subject_id(at);
            let body = update(Expression::Subject { id, ty: TypeName::auto(), loc: at });
            Expression::WithSubject(Box::new(WithSubject { id, subject, body, null_message: None, loc: at }))
        }
    }
}

/// The operator a compound assignment applies (`+` for `+=`).
fn compound_base(op: BinaryOp) -> Option<BinaryOp> {
    Some(match op {
        BinaryOp::AddAssign => BinaryOp::Add,
        BinaryOp::SubAssign => BinaryOp::Sub,
        BinaryOp::MulAssign => BinaryOp::Mul,
        BinaryOp::DivAssign => BinaryOp::Div,
        BinaryOp::ModAssign => BinaryOp::Mod,
        BinaryOp::LShiftAssign => BinaryOp::LShift,
        BinaryOp::RShiftAssign => BinaryOp::RShift,
        BinaryOp::BitAndAssign => BinaryOp::BitAnd,
        BinaryOp::BitOrAssign => BinaryOp::BitOr,
        BinaryOp::BitXorAssign => BinaryOp::BitXor,
        _ => return None,
    })
}
