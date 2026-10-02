//! `[Equatable]`: a struct (or an enum whose cases carry values) that
//! compares and hashes by its fields, like a tuple of them, instead of by
//! identity.
//!
//! [`derive`] gives each such struct two synthesized methods, built from its
//! fields before any pass runs, so the rest of sema sees them as written:
//!
//! - `==(other: T): bool`, which compares the tuple of the fields of `this`
//!   with that of `other` (`(this.a, this.b) == (other.a, other.b)`); tuple
//!   `==` compares element by element and treats null as equal only to null.
//! - `__hash(): u64`, `hash((this.a, this.b))`. (A single field is paired
//!   with `true`, since a tuple has two elements or more.) Codegen's `__address<T>`,
//!   which the generic `hash<T>` returns, calls it for a non-null `T`, as a
//!   tuple element's hash does, so `HashMap` and `HashSet` find keys by
//!   content.
//!
//! A field marked `[Equatable(exclude = true)]` (or `include = false`) is
//! left out of both. A reference enum's fields are its tag and every case's
//! values; the values of the cases a value does not hold are zero or null,
//! so they compare equal.

use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;
use pepper_parser::diagnostic::Diagnostic;

/// The attribute that derives `==` and `hash` from the fields, and, on a
/// field, says whether that field takes part.
pub const EQUATABLE_ATTRIBUTE: &str = "Equatable";

/// The synthesized method that hashes an `[Equatable]` struct's fields.
pub const HASH_METHOD: &str = "__hash";

/// The `[Equatable]` or `[Equatable(...)]` among `attributes`.
fn find(attributes: &[ast::Attribute]) -> Option<&ast::Attribute> {
    attributes.iter().find(|a| a.name() == Some(EQUATABLE_ATTRIBUTE))
}

/// Give every `[Equatable]` struct of `module` its `==` and `__hash`, and
/// report a misplaced or contradictory `[Equatable]`.
pub fn derive(module: &mut Module) -> Result<(), Diagnostic> {
    for e in &module.enums {
        if let Some(attribute) = find(&e.attributes) {
            return Err(Diagnostic::error(format!(
                "'[{EQUATABLE_ATTRIBUTE}]' does not apply to enum '{}': its cases carry no values, so it already compares and hashes by case",
                e.name
            ))
            .at(Loc::new(e.loc.file, attribute.span)));
        }
    }
    for st in module.structs.iter_mut() {
        derive_struct(st)?;
    }
    Ok(())
}

/// Whether a field whose attributes are `attributes` takes part in the
/// derived `==` and hash: unless its `[Equatable(...)]` says `include =
/// false` or `exclude = true`. Positional arguments are `include`, then
/// `exclude`, as the attribute struct declares them.
fn included(attributes: &[ast::Attribute], file: pepper_parser::diagnostic::FileId) -> Result<bool, Diagnostic> {
    let Some(attribute) = find(attributes) else { return Ok(true) };
    let (mut include, mut exclude) = (None, None);
    for (index, argument) in attribute.arguments().iter().enumerate() {
        let name = argument.name.map_or(if index == 0 { "include" } else { "exclude" }, |(name, _)| name);
        let ast::Expression::Literal { value: ast::Literal::Bool(value), .. } = argument.value else {
            return Err(Diagnostic::error(format!("'{name}' of '[{EQUATABLE_ATTRIBUTE}]' must be 'true' or 'false'"))
                .at(Loc::new(file, argument.value.span())));
        };
        match name {
            "include" => include = Some((*value, argument.value.span())),
            _ => exclude = Some((*value, argument.value.span())),
        }
    }
    if let (Some((include, _)), Some((exclude, at))) = (include, exclude)
        && include == exclude
    {
        return Err(Diagnostic::error(format!(
            "'include = {include}' and 'exclude = {exclude}' contradict each other; give one of them"
        ))
        .at(Loc::new(file, at)));
    }
    Ok(include.is_none_or(|(include, _)| include) && !exclude.is_some_and(|(exclude, _)| exclude))
}

fn derive_struct(st: &mut StructDef) -> Result<(), Diagnostic> {
    let file = st.loc.file;
    let at = |attribute: &ast::Attribute| Loc::new(file, attribute.span);
    let Some(equatable) = find(&st.attributes) else {
        if let Some(attribute) = st.field_members.iter().find_map(|f| find(&f.attributes)) {
            return Err(Diagnostic::error(format!(
                "'[{EQUATABLE_ATTRIBUTE}]' on a field applies only to a field of an '[{EQUATABLE_ATTRIBUTE}]' struct"
            ))
            .at(at(attribute))
            .with_note(format!("mark '{}' '[{EQUATABLE_ATTRIBUTE}]' to derive '==' and 'hash' from its fields", st.name), Some(st.loc)));
        }
        return Ok(());
    };
    let attribute_loc = at(equatable);
    if !equatable.arguments().is_empty() {
        return Err(Diagnostic::error(format!(
            "'[{EQUATABLE_ATTRIBUTE}]' on '{}' takes no arguments; 'include' and 'exclude' apply to its fields",
            st.name
        ))
        .at(attribute_loc));
    }
    // Already derived (a module built once and applied again).
    if st.method_members.iter().any(|m| m.name == HASH_METHOD) {
        return Ok(());
    }
    if st.is_value() {
        return Err(Diagnostic::error(format!(
            "'[{EQUATABLE_ATTRIBUTE}]' does not apply to value type '{}': a value already compares and hashes by its fields",
            st.name
        ))
        .at(attribute_loc));
    }
    // An `==` taking another type is an overload beside the derived one.
    if let Some(own) = st.method_members.iter().find(|m| m.name == "==" && m.parameters.len() == 1 && m.parameters[0].ty == st.ty) {
        return Err(Diagnostic::error(format!(
            "'{}' is '[{EQUATABLE_ATTRIBUTE}]', so its '==' is derived and cannot be declared",
            st.name
        ))
        .at(own.loc)
        .with_note(format!("remove this '==', or remove '[{EQUATABLE_ATTRIBUTE}]' to declare both '==' and 'hash' by hand"), None)
        .with_note(format!("'[{EQUATABLE_ATTRIBUTE}]' is here"), Some(attribute_loc)));
    }
    let mut compared: Vec<&VariableDef> = vec![];
    for field in &st.field_members {
        if included(&field.attributes, file)? {
            compared.push(field);
        }
    }
    let member = |lhs: Expression, name: &str| Expression::MemberRef { lhs: Box::new(lhs), name: name.to_string(), loc: Loc::NONE };
    let other = || Expression::SymbolRef { id: "other".to_string(), ty: st.ty.clone(), loc: Loc::NONE };
    // A tuple has two elements or more, so one field is paired with `true`.
    let tuple = |lhs: &dyn Fn() -> Expression| {
        let mut args: Vec<Expression> = compared.iter().map(|f| member(lhs(), &f.name)).collect();
        if args.len() == 1 {
            args.push(Expression::BoolLiteral(true));
        }
        Expression::FunctionCall { function: crate::passes::tuples::constructor_name(std::iter::empty()), args, loc: Loc::NONE }
    };
    let (equal, hash) = if compared.is_empty() {
        (Expression::BoolLiteral(true), Expression::IntLiteral(0))
    } else {
        (
            Expression::Binary {
                op: BinaryOp::Equal,
                lhs: Box::new(tuple(&|| Expression::ThisRef)),
                rhs: Box::new(tuple(&other)),
                loc: Loc::NONE,
            },
            Expression::FunctionCall { function: "hash".to_string(), args: vec![tuple(&|| Expression::ThisRef)], loc: Loc::NONE },
        )
    };
    let method = |name: &str, ty: TypeName, parameters: Vec<VariableDef>, value: Expression| FunctionDef {
        trait_default: None,
        owner: Loc::NONE,
        name: name.to_string(),
        ty,
        generic_params: vec![],
        parameters,
        body: Some(Block {
            name: String::new(),
            items: vec![Statement::Return(ReturnStatement { expr: Some(value), loc: attribute_loc })],
            attributes: vec![],
        }),
        parent: Some(st.ty.name.clone()),
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
        attributes: vec![],
        loc: attribute_loc,
    };
    let parameter = VariableDef {
        name: "other".to_string(),
        ty: st.ty.clone(),
        default: None,
        hidden: false,
        kind: Kind::Param,
        attributes: vec![],
        loc: attribute_loc,
        type_loc: Loc::NONE,
        is_const: false,
    };
    let equal = method("==", TypeName::new("bool"), vec![parameter], equal);
    let hash = method(HASH_METHOD, TypeName::new("u64"), vec![], hash);
    st.method_members.push(equal);
    st.method_members.push(hash);
    Ok(())
}
