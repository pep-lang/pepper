//! Tuples: `(A, B, ...)`, spelled `__tuple<A, B, ...>`.
//!
//! A tuple is a value made of its elements, like a
//! `std::tuple<shared_ptr<A>, shared_ptr<B>>`: copying one copies each
//! element (acquiring the references among them) and dropping one releases
//! each. Elements are immutable; a tuple changes only by assigning a whole
//! new one.
//!
//! Sema sees each distinct tuple type as a synthesized struct (made by
//! `synthesize_function_types`, next to function types) with one `const`
//! field per element, named `0`, `1`, ..., and a constructor taking the
//! elements in order. So typing, element reads (`t.0` is a field read) and
//! the conversions at the constructor's arguments need nothing new. Codegen
//! gives the struct its value representation (see `pepper-codegen`).
//!
//! - A tuple literal `(a, b)` is built as a call of `__tuple`, which
//!   `resolve_implicit_types` renames to the literal's type once its
//!   elements' types are known (`__tuple<int, String>(a, b)`).
//!   `convert_to_traits` retypes a literal to the tuple type of the slot it
//!   flows into, so `(0, s)` can be returned as a `(ulong, Shape)`.
//! - A destructuring (`var (a, b) = e;`, `(a, b) = e;`) is lowered by the
//!   builder to a hidden `__tuple_N` local initialized with
//!   `Destructure(e, count)` and one read per binding; `lower_destructures`
//!   checks the count here once `e`'s type is known.

use crate::model::*;
use crate::type_name::{TypeName, TUPLE};

/// The type of a tuple literal whose elements have `types`, or `None` while
/// one is unknown.
pub(crate) fn literal_type(types: impl Iterator<Item = TypeName>) -> Option<TypeName> {
    let elements: Vec<TypeName> = types.collect();
    if elements.len() < 2 || elements.iter().any(|t| t.is_empty() || t.contains_auto() || t.name == "void") {
        return None;
    }
    Some(TypeName::with_args(TUPLE, elements))
}

/// The constructor a tuple literal calls before its type is known:
/// `__tuple`, or `__tuple(line,column)` for a labeled literal.
pub(crate) fn constructor_name<'a>(labels: impl Iterator<Item = &'a str>) -> String {
    let labels: Vec<&str> = labels.collect();
    if labels.is_empty() {
        TUPLE.to_string()
    } else {
        format!("{}({})", TUPLE, labels.join(","))
    }
}

/// The labels of an unspelled tuple constructor (`__tuple`, or
/// `__tuple(line,column)`), or `None` when `function` is not one.
pub(crate) fn constructor_labels(function: &str) -> Option<Vec<String>> {
    let rest = function.strip_prefix(TUPLE)?;
    if rest.is_empty() {
        return Some(vec![]);
    }
    let labels = rest.strip_prefix('(')?.strip_suffix(')')?;
    Some(labels.split(',').map(str::to_string).collect())
}

/// The type of a tuple literal calling `function` (see
/// [`constructor_labels`]) with arguments of `types`: [`literal_type`],
/// labeled like the literal.
pub(crate) fn labeled_literal_type(function: &str, types: impl Iterator<Item = TypeName>) -> Option<TypeName> {
    let labels = constructor_labels(function)?;
    let mut ty = literal_type(types)?;
    if labels.len() == ty.sub_types.len() {
        ty.labels = labels;
    }
    Some(ty)
}

/// Whether `function` names a tuple constructor (`__tuple<int, String>`):
/// the call is a tuple literal.
pub fn is_literal(function: &str) -> bool {
    function.starts_with("__tuple<")
}

/// The struct sema uses for tuple type `ty`, before
/// `apply_synthesized`/`finish`: a `const` field per element, named by its
/// position, and a constructor that takes them in order.
pub fn tuple_struct(ty: &TypeName) -> StructDef {
    let name = ty.to_string();
    let field = |index: usize, element: &TypeName| VariableDef {
        name: index.to_string(),
        ty: element.clone(),
        default: None,
        hidden: false,
        kind: Kind::Field,
        attributes: vec![],
        loc: Loc::NONE,
        type_loc: Loc::NONE,
        is_const: true,
    };
    let mut constructor = crate::passes::function_types::empty_function(&name, ty.clone(), &name);
    constructor.parameters = ty
        .tuple_elements()
        .iter()
        .enumerate()
        .map(|(index, element)| VariableDef {
            name: format!("this.{}", index),
            kind: Kind::Param,
            ..field(index, element)
        })
        .collect();
    let mut st = StructDef {
        enum_cases: None,
        name: name.clone(),
        ty: ty.clone(),
        generic_params: vec![],
        field_members: ty.tuple_elements().iter().enumerate().map(|(i, e)| field(i, e)).collect(),
        method_members: vec![],
        generic_methods: vec![],
        constructors: vec![constructor],
        destructor: crate::passes::function_types::empty_function("__dtor", TypeName::void(), &name),
        acquire: crate::passes::function_types::empty_function("__acquire", TypeName::void(), &name),
        release: crate::passes::function_types::empty_function("__release", TypeName::void(), &name),
        traits: vec![],
        attributes: vec![],
        loc: Loc::NONE,
    };
    crate::struct_body::apply_synthesized(&mut st);
    crate::struct_body::finish(&mut st).expect("tuple struct");
    // The constructor sets every element from its parameters, so it needs
    // no zero stores (and a tuple element is never null).
    if let Some(body) = &mut st.constructors[0].body {
        body.items.retain(|item| {
            !matches!(item, Statement::Expression(Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. })
                if matches!(lhs.as_ref(), Expression::MemberRef { lhs: this, name, .. }
                    if matches!(this.as_ref(), Expression::ThisRef) && name.parse::<usize>().is_ok())
                && matches!(rhs.as_ref(), Expression::PointerLiteral | Expression::Default(_) | Expression::IntLiteral(0) | Expression::FloatLiteral(_)))
        });
    }
    st
}

/// Check each destructuring against its value's type and replace its
/// `Destructure` node with the value; report an element that does not exist
/// (`t.2` of a pair) and an element write (`t.0 = x`), since elements are
/// immutable.
pub fn lower_destructures(module: &mut Module) {
    let table = crate::static_type::StructTable::build(module);
    let check = |e: &mut Expression, current: Option<&TypeName>| match e {
        Expression::Destructure { value, count, loc } => {
            let (count, loc) = (*count, *loc);
            let inner = std::mem::replace(value.as_mut(), Expression::PointerLiteral);
            match crate::static_type::of(&inner, &table, current) {
                Some(ty) if ty.is_tuple() && ty.tuple_elements().len() != count => {
                    crate::errors::report(
                        Diagnostic::error(format!(
                            "cannot destructure '{}' into {} {}: it has {} elements",
                            ty.display(),
                            count,
                            if count == 1 { "value" } else { "values" },
                            ty.tuple_elements().len()
                        ))
                        .at(loc),
                    );
                }
                Some(ty) if !ty.is_tuple() => {
                    crate::errors::report(
                        Diagnostic::error(format!("cannot destructure '{}': it is not a tuple", ty.display())).at(loc),
                    );
                }
                _ => {}
            }
            *e = inner;
        }
        Expression::MemberRef { lhs, name, loc } => {
            if let Some(ty) = crate::static_type::of(lhs, &table, current).filter(|t| t.is_tuple()) {
                // A label (`t.line`) names its position from here on.
                if let Some(index) = ty.tuple_index(name) {
                    *name = index.to_string();
                } else {
                    let count = ty.tuple_elements().len();
                    crate::errors::report(Diagnostic::error(format!(
                        "no member named '{}' in '{}': its elements are '0' to '{}'",
                        name,
                        ty.display(),
                        count - 1
                    ))
                    .at(*loc));
                }
            }
        }
        Expression::Binary { op, lhs, .. } if op.is_assignment() => {
            if let Expression::MemberRef { lhs: tuple, name, loc } = lhs.as_ref() {
                if let Some(ty) = crate::static_type::of(tuple, &table, current).filter(|t| t.tuple_element(name).is_some()) {
                    crate::errors::report(
                        Diagnostic::error(format!(
                            "cannot assign to element {} of tuple '{}': tuple elements are immutable",
                            name,
                            ty.display()
                        ))
                        .at(*loc),
                    );
                }
            }
        }
        _ => {}
    };
    // A tuple's own constructor is what sets its elements.
    for st in module.structs.iter_mut().filter(|st| !st.ty.is_tuple()) {
        let current = st.ty.clone();
        for method in st.method_members.iter_mut().chain(st.constructors.iter_mut()).chain([&mut st.destructor]) {
            crate::passes::walk_function(method, &mut |e| check(e, Some(&current)));
        }
    }
    for function in &mut module.functions {
        crate::passes::walk_function(function, &mut |e| check(e, None));
    }
    for var in &mut module.globals {
        crate::passes::walk_global(var, &mut |e| check(e, None));
    }
}
