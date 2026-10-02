//! Enums whose cases carry no values (`enum Color { Red, Green }`) and the
//! `match` statement over them.
//!
//! An enum is an integer type that keeps its own name (`Color`) through sema,
//! so the compiler can tell it from other integers: a `Color` never converts
//! to or from an `int` implicitly (`check_function_types`), and a `match` on a
//! `Color` must handle every case. Everything that only needs to know how the
//! value is stored asks [`representation`], which maps the name to its integer
//! type (`int` unless the enum says `enum Kind: u8`): the arithmetic helpers,
//! `TypeName::is_integral`, and codegen's type table. The table is
//! thread-local and filled by [`install`] at the start of each sema run (and
//! again by codegen), like the other per-run state (INTERNALS.md §3).
//!
//! Two passes finish what the builder started:
//!
//! - [`resolve_enum_cases`] (first, before any type is inferred) turns every
//!   `Color.Red` into `Red`'s value, typed `Color`.
//! - [`lower_matches`] (last, once every type is final) turns each arm test
//!   the builder made (`Expression::MatchArm`) into `==` tests on the hidden
//!   `__match_N` local, and checks that each `match` handles every case.

use crate::errors::report;
use crate::model::*;
use crate::type_name::TypeName;
use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};

thread_local! {
    /// Enum name → its representation's integer type name and its default
    /// value, for this run.
    static REPRESENTATIONS: RefCell<HashMap<String, (String, i64)>> = RefCell::new(HashMap::new());
    /// (enum name, method name) → whether the method is static, for this
    /// run. Filled by [`resolve_enum_cases`].
    static METHODS: RefCell<HashMap<(String, String), bool>> = RefCell::new(HashMap::new());
    /// Reference enum name (without type arguments) → its declaration, for
    /// this run. Filled by [`resolve_enum_cases`].
    static REFERENCE_ENUMS: RefCell<HashMap<String, ReferenceEnum>> = RefCell::new(HashMap::new());
}

/// What [`reference_cases`] knows of a reference enum.
#[derive(Clone)]
struct ReferenceEnum {
    cases: Vec<EnumCaseDef>,
    /// Location of the enum's name.
    loc: Loc,
    /// The enum's type parameters.
    generic_params: Vec<GenericParam>,
    /// Each case's values' declared types, in `cases` order.
    payload_types: Vec<Vec<TypeName>>,
}

/// Make the reference enums among `structs` the ones [`reference_cases`]
/// knows, replacing any earlier run's.
pub fn install_reference_enums(structs: &[StructDef]) {
    REFERENCE_ENUMS.with(|r| {
        let mut r = r.borrow_mut();
        r.clear();
        for st in structs {
            if let Some(cases) = &st.enum_cases {
                r.entry(st.ty.name.clone()).or_insert_with(|| {
                    let field = |case: &EnumCaseDef, name: &str| {
                        let field = payload_field(&case.name, name);
                        st.field_members.iter().find(|f| f.name == field).map_or_else(TypeName::auto, |f| f.ty.clone())
                    };
                    ReferenceEnum {
                        cases: cases.clone(),
                        loc: st.loc,
                        generic_params: st.generic_params.clone(),
                        payload_types: cases.iter().map(|c| c.payload.iter().map(|(n, _)| field(c, n)).collect()).collect(),
                    }
                });
            }
        }
    });
}

/// The cases of reference enum `ty` (any specialization of it) and the
/// location of its name, or `None` when `ty` is not a reference enum.
///
/// A value whose type is a type parameter that `ty` sets to `void`
/// (`Ok(value: TValue)` in `Result<void>`) is erased, as a `void` field is
/// (`specialize_structs::erase_void`), so that case carries one value fewer.
pub fn reference_cases(ty: &TypeName) -> Option<(Vec<EnumCaseDef>, Loc)> {
    let found = REFERENCE_ENUMS.with(|r| r.borrow().get(&ty.name).cloned())?;
    let mut cases = found.cases;
    for (case, types) in cases.iter_mut().zip(&found.payload_types) {
        let mut types = types.iter();
        case.payload.retain(|_| !types.next().is_some_and(|t| is_erased_parameter(t, &found.generic_params, ty)));
    }
    Some((cases, found.loc))
}

/// `declared` is a type parameter among `params` that `ty`'s arguments (or
/// the parameter's default) set to `void`.
fn is_erased_parameter(declared: &TypeName, params: &[GenericParam], ty: &TypeName) -> bool {
    if !declared.sub_types.is_empty() || ty.sub_types.is_empty() {
        return false;
    }
    let Some(index) = params.iter().position(|p| p.name == declared.name) else {
        return false;
    };
    let argument = ty.sub_types.get(index).or(params[index].default.as_ref());
    argument.is_some_and(|a| a.name == crate::type_name::VOID && a.sub_types.is_empty())
}

/// `ty` is a reference enum.
pub fn is_reference_enum(ty: &TypeName) -> bool {
    REFERENCE_ENUMS.with(|r| r.borrow().contains_key(&ty.name))
}

fn shown(ty: &TypeName) -> String {
    if ty.is_tuple() {
        let elements: Vec<String> = ty.tuple_elements().iter().map(shown).collect();
        return format!("({})", elements.join(", "));
    }
    pepper_parser::namespace::demangle_name(&ty.to_string()).to_string()
}

/// The case named `name` among `cases`, or the `no case named` error at
/// `at`.
fn find_case<'c>(cases: &'c [EnumCaseDef], name: &str, ty: &TypeName, declared: Loc, at: Loc) -> Result<&'c EnumCaseDef, Diagnostic> {
    cases.iter().find(|c| c.name == name).ok_or_else(|| {
        Diagnostic::error(format!("no case named '{}' in '{}'", name, shown(ty)))
            .at(at)
            .with_note(format!("'{}' declared here", shown(ty)), Some(declared))
    })
}

/// Check a pattern's binding count against its case: `count` bindings, the
/// first extra one at `extra` (when there is one).
fn check_binding_count(case: &EnumCaseDef, count: usize, extra: Option<Loc>, pattern: Loc) -> Result<(), Diagnostic> {
    let expected = case.payload.len();
    if count > expected {
        return Err(Diagnostic::error(format!(
            "too many bindings for case '{}': expected {}, have {}",
            case.name, expected, count
        ))
        .at(extra.unwrap_or(pattern))
        .with_note(format!("'{}' declared here", case.name), Some(case.loc)));
    }
    if count < expected {
        return Err(Diagnostic::error(format!(
            "too few bindings for case '{}': expected {}, have {}",
            case.name, expected, count
        ))
        .at(pattern)
        .with_note(format!("'{}' declared here", case.name), Some(case.loc)));
    }
    Ok(())
}

/// The type of a value a pattern binds, once the `match`'s subject has
/// type `subject`: `Ok(None)` while that type is unknown, the error when
/// the patterns do not fit the enum. `field` gives the type of a field of
/// the subject's struct.
pub fn case_value_type(
    value: &CaseValue,
    subject: &TypeName,
    field: impl Fn(&str) -> Option<TypeName>,
) -> Result<Option<TypeName>, Diagnostic> {
    if subject.is_auto() || subject.is_empty() {
        return Ok(None);
    }
    let Some((cases, declared)) = reference_cases(subject) else {
        let first = &value.choices[0];
        if is_enum(&subject.to_string()) {
            return Err(Diagnostic::error(format!(
                "case '{}' of '{}' carries no values to bind",
                first.case,
                shown(subject)
            ))
            .at(first.loc));
        }
        if is_literal_type(subject) {
            return Err(Diagnostic::error(format!(
                "'{}' is not a literal: a 'match' on '{}' takes literal patterns",
                first.case,
                shown(subject)
            ))
            .at(first.case_loc));
        }
        return Err(Diagnostic::error(format!(
            "cannot match on a value of '{}': 'match' needs an enum, an integer, 'char', 'bool' or 'String'",
            shown(subject)
        ))
        .at(value.subject.loc()));
    };
    let mut found: Option<(TypeName, &CaseChoice)> = None;
    for choice in &value.choices {
        let case = find_case(&cases, &choice.case, subject, declared, choice.case_loc)?;
        let extra = choice.bindings.get(case.payload.len()).copied();
        check_binding_count(case, choice.bindings.len(), extra, choice.case_loc)?;
        let Some(ty) = field(&payload_field(&case.name, &case.payload[choice.index].0)) else {
            return Ok(None);
        };
        match &found {
            Some((first, first_choice)) if *first != ty => {
                return Err(Diagnostic::error(format!(
                    "'{}' has type '{}' here but '{}' in '{}'",
                    value.name,
                    shown(&ty),
                    shown(first),
                    first_choice.case
                ))
                .at(choice.loc));
            }
            Some(_) => {}
            None => found = Some((ty, choice)),
        }
    }
    Ok(found.map(|(ty, _)| ty))
}

/// The methods every enum has without declaring them.
pub const BUILT_IN_METHODS: [&str; 2] = ["name", "from_value"];

/// The free function a method `method` of enum `enum_name` becomes:
/// `Color::name`. An instance method takes the value as its first
/// parameter, `this` ([`this_parameter`]).
pub fn method_name(enum_name: &str, method: &str) -> String {
    format!("{}::{}", enum_name, spelled_in_name(method))
}

/// `method` as the part of a function name after `::`: an operator's `<` and
/// `>` become `{` and `}`, since a `<` in a function name reads as type
/// arguments (`f64::<` is the operator `<` of `double`, not a generic).
fn spelled_in_name(method: &str) -> std::borrow::Cow<'_, str> {
    if method.contains(['<', '>']) {
        method.replace('<', "{").replace('>', "}").into()
    } else {
        method.into()
    }
}

/// The enum (or other value type, see `value_types`) and method a function
/// named by [`method_name`] belongs to.
pub fn method_of(function: &str) -> Option<(&str, &str)> {
    let (enum_name, method) = function.split_once("::")?;
    (crate::value_types::key(enum_name).as_deref() == Some(enum_name)).then_some((enum_name, method))
}

/// The `this` parameter of an instance method of enum `enum_name`: the
/// value, passed by value like any integer.
pub fn this_parameter(enum_name: &str) -> VariableDef {
    VariableDef {
        name: "this".to_string(),
        ty: TypeName::new(enum_name),
        default: None,
        hidden: false,
        kind: Kind::Param,
        attributes: vec![],
        loc: Loc::NONE,
        type_loc: Loc::NONE,
        is_const: true,
    }
}

/// Whether enum `enum_name` has a method `method`, and if so whether it is
/// static.
pub fn method_is_static(enum_name: &str, method: &str) -> Option<bool> {
    METHODS.with(|m| m.borrow().get(&(enum_name.to_string(), spelled_in_name(method).into_owned())).copied())
}

/// A call of method `method` on a value of enum `enum_name`, as a call of
/// its function: `c.name()` is `Color::name(c)`. Reports a method the enum
/// lacks, or a static one called on a value, at `loc`, and returns `None`
/// then.
pub fn call_on_value(enum_name: &str, method: &str, this: Expression, args: Vec<Expression>, loc: Loc) -> Option<Expression> {
    match method_is_static(enum_name, method) {
        Some(false) => {
            let mut all = vec![this];
            all.extend(args);
            Some(Expression::FunctionCall { function: method_name(enum_name, method), args: all, loc })
        }
        Some(true) => {
            report(Diagnostic::error(format!(
                "'{}' is a static method of '{}': call it as '{}.{}(...)'",
                method, enum_name, enum_name, method
            ))
            .at(loc));
            None
        }
        None => {
            report(Diagnostic::error(format!("no member named '{}' in '{}'", method, enum_name)).at(loc));
            None
        }
    }
}

/// The error for a method of enum (or other value type) `enum_name` read
/// without a call, `c.name`: a value type's methods are free functions,
/// which no value stands for. `None` when `method` is not one of its
/// methods.
pub fn method_read(enum_name: &str, method: &str, loc: Loc) -> Option<Diagnostic> {
    let call = if method_is_static(enum_name, method)? {
        format!("'{}.{}(...)'", enum_name, method)
    } else {
        format!("'{}()'", method)
    };
    Some(Diagnostic::error(format!("'{}' is a method of '{}': call it as {}", method, enum_name, call)).at(loc))
}

/// Make `enums` the enums [`representation`] knows, replacing any earlier
/// run's.
pub fn install(enums: &[EnumDef]) {
    REPRESENTATIONS.with(|r| {
        let mut r = r.borrow_mut();
        r.clear();
        for e in enums {
            r.insert(e.name.clone(), (e.representation.name.clone(), e.default_value()));
        }
    });
}

/// The integer type an enum named `name` is stored as, or `None` when
/// `name` is not an enum.
pub fn representation(name: &str) -> Option<String> {
    REPRESENTATIONS.with(|r| r.borrow().get(name).map(|(repr, _)| repr.clone()))
}

/// The value a slot of enum `name` holds before anything is stored in it
/// (see [`EnumDef::default_value`]), or `None` when `name` is not an enum.
pub fn default_value(name: &str) -> Option<i64> {
    REPRESENTATIONS.with(|r| r.borrow().get(name).map(|(_, value)| *value))
}

/// `name`'s default value as an expression of its type, when `name` is an
/// enum.
pub fn default_expression(ty: &TypeName) -> Option<Expression> {
    let value = default_value(&ty.to_string())?;
    Some(Expression::Cast { expr: Box::new(Expression::IntLiteral(value)), ty: ty.clone(), loc: Loc::NONE, kind: CastKind::Synthesized })
}

/// `name` names an enum.
pub fn is_enum(name: &str) -> bool {
    REPRESENTATIONS.with(|r| r.borrow().contains_key(name))
}

/// `name`, or the integer type it is stored as when it names an enum.
pub fn stored_as(name: &str) -> std::borrow::Cow<'_, str> {
    match representation(name) {
        Some(r) => std::borrow::Cow::Owned(r),
        None => std::borrow::Cow::Borrowed(name),
    }
}

/// A case's value as an expression of the enum's type: `Color.Red` is
/// `0 as Color`.
fn case_value(e: &EnumDef, case: &EnumCaseDef, loc: Loc) -> Expression {
    Expression::Cast { expr: Box::new(Expression::IntLiteral(case.value)), ty: TypeName::new(&e.name), loc, kind: CastKind::Synthesized }
}

/// Every function body, method body and initializer in the module.
fn for_each_body(module: &mut Module, mut f: impl FnMut(&mut Block, bool)) {
    for_each_body_in(module, |body, generic, _| f(body, generic));
}

/// [`for_each_body`], with the struct whose method each body is (its
/// `this`), if any.
fn for_each_body_in(module: &mut Module, mut f: impl FnMut(&mut Block, bool, Option<&TypeName>)) {
    for st in &mut module.structs {
        let generic_base = st.ty.is_generic() && st.name == st.ty.name;
        let current = st.ty.clone();
        for method in st
            .method_members
            .iter_mut()
            .chain(st.generic_methods.iter_mut())
            .chain(st.constructors.iter_mut())
            .chain([&mut st.destructor, &mut st.acquire, &mut st.release])
        {
            if let Some(body) = &mut method.body {
                f(body, generic_base || method.is_generic_func, Some(&current));
            }
        }
    }
    for extension in &mut module.extensions {
        let current = extension.target.clone();
        for method in &mut extension.methods {
            if let Some(body) = &mut method.body {
                f(body, true, Some(&current));
            }
        }
    }
    for tr in &mut module.traits {
        for method in &mut tr.methods {
            if let Some(body) = &mut method.body {
                f(body, true, None);
            }
        }
    }
    for function in &mut module.functions {
        let generic = function.is_generic_func;
        if let Some(body) = &mut function.body {
            f(body, generic, None);
        }
    }
}

/// Replace every `Enum.Case` (a member of a name that is an enum) with the
/// case's value, and resolve the qualifiers of `match` patterns
/// (`Color.Red => ...`). Reports `no case named 'X' in 'E'`.
pub fn resolve_enum_cases(module: &mut Module) {
    install(&module.enums);
    install_reference_enums(&module.structs);
    // Extensions of numbers, `bool` and enums become functions `X::m`.
    crate::value_types::lower_extensions(module);
    if module.enums.is_empty() && !module.structs.iter().any(|st| st.enum_cases.is_some()) {
        install_methods(module);
        method_bodies(module);
        crate::value_types::resolve_static_calls(module);
        return;
    }
    add_built_in_methods(module);
    install_methods(module);
    method_bodies(module);
    crate::value_types::resolve_static_calls(module);
    let enums: HashMap<String, EnumDef> = module.enums.iter().map(|e| (e.name.clone(), e.clone())).collect();
    // The types named as receivers (`Tree<int>` in `Tree<int>.Leaf`), which
    // the walk meets as calls right after the member they are the receiver
    // of.
    let mut receivers: std::collections::HashSet<Loc> = std::collections::HashSet::new();
    let mut resolve = |expr: &mut Expression| {
        if let Expression::MethodCall { this, .. } | Expression::MemberRef { lhs: this, .. } = expr
            && let Expression::FunctionCall { loc, .. } = this.as_ref()
        {
            receivers.insert(*loc);
        }
        // `Doc(...)`: a reference enum's values are made by its cases only.
        if let Expression::FunctionCall { function, loc, .. } = expr
            && !loc.is_none()
            && !receivers.contains(loc)
            && let ty = crate::passes::gather_generics::parse_type_string(function)
            && let Some((cases, _)) = reference_cases(&ty)
        {
            report(
                Diagnostic::error(format!("cannot construct enum '{}' directly: its values are made by its cases", shown(&ty)))
                    .at(*loc)
                    .with_note(
                        format!("use a case, such as '{}.{}'", shown(&ty), cases.first().map_or("Case", |c| c.name.as_str())),
                        None,
                    ),
            );
            return;
        }
        // `Doc.Line`: a reference enum's case that carries no values is a
        // call of its static method, `Doc.Line()`.
        if let Expression::MemberRef { lhs, name, loc } = expr
            && let Some(ty) = named_type(lhs)
            && let Some((cases, declared)) = reference_cases(&ty)
        {
            match find_case(&cases, name, &ty, declared, *loc) {
                Ok(case) if case.payload.is_empty() => {
                    *expr = Expression::MethodCall { this: lhs.clone(), method: name.clone(), args: vec![], loc: *loc }
                }
                Ok(case) => report(
                    Diagnostic::error(format!(
                        "case '{}' of '{}' takes {} value{}: '{}.{}({})'",
                        case.name,
                        shown(&ty),
                        case.payload.len(),
                        if case.payload.len() == 1 { "" } else { "s" },
                        shown(&ty),
                        case.name,
                        case.payload.iter().map(|(n, _)| n.as_str()).collect::<Vec<_>>().join(", ")
                    ))
                    .at(*loc)
                    .with_note(format!("'{}' declared here", case.name), Some(case.loc)),
                ),
                Err(d) => report(d),
            }
            return;
        }
        // `Color.from_value(1)`: a static method called on the enum.
        if let Expression::MethodCall { this, method, args, loc } = expr
            && let Expression::SymbolRef { id, .. } = this.as_ref()
            && let Some(e) = enums.get(id)
        {
            match method_is_static(&e.name, method) {
                Some(true) => {
                    *expr = Expression::FunctionCall {
                        function: method_name(&e.name, method),
                        args: std::mem::take(args),
                        loc: *loc,
                    }
                }
                Some(false) => report(
                    Diagnostic::error(format!(
                        "'{}' is not static: call it on a value of '{}', such as '{}.{}.{}()'",
                        method,
                        e.name,
                        e.name,
                        e.cases.first().map_or("Case", |c| c.name.as_str()),
                        method
                    ))
                    .at(*loc),
                ),
                None => report(
                    Diagnostic::error(format!("no member named '{}' in '{}'", method, e.name))
                        .at(*loc)
                        .with_note(format!("'{}' declared here", e.name), Some(e.loc)),
                ),
            }
            return;
        }
        if let Expression::Cast { ty, loc, kind: CastKind::Static, .. } = expr
            && let Some(e) = enums.get(&ty.to_string())
        {
            report(
                Diagnostic::error(format!("cannot convert a value to enum '{}' with 'as'", e.name))
                    .at(*loc)
                    .with_note(
                        format!("name a case instead, such as '{}.{}'", e.name, e.cases.first().map_or("Case", |c| c.name.as_str())),
                        None,
                    ),
            );
            return;
        }
        let Expression::MemberRef { lhs, name, loc } = expr else {
            return;
        };
        let Expression::SymbolRef { id, .. } = lhs.as_ref() else {
            return;
        };
        let Some(e) = enums.get(id) else {
            return;
        };
        match e.case(name) {
            Some(case) => *expr = case_value(e, case, *loc),
            None => report(method_read(&e.name, name, *loc).unwrap_or_else(|| no_case(name, e, *loc))),
        }
    };
    let mut in_block = |block: &mut Block, _generic: bool| {
        give_defaults(block);
        crate::passes::walk_block(block, &mut resolve)
    };
    for_each_body(module, &mut in_block);
    // A checked runtime's defaults were resolved when it was checked, and
    // the cases they hold are located casts now, which the walk would
    // report as written by the user.
    let checked = &module.checked;
    for st in module.structs.iter_mut().filter(|st| !checked.has_struct(&st.name)) {
        for field in &mut st.field_members {
            if let Some(default) = &mut field.default {
                crate::passes::walk_expression(default, &mut resolve);
            }
        }
        for method in st.method_members.iter_mut().chain(st.constructors.iter_mut()) {
            for p in &mut method.parameters {
                if let Some(default) = &mut p.default {
                    crate::passes::walk_expression(default, &mut resolve);
                }
            }
        }
    }
    for function in module.functions.iter_mut().filter(|f| !checked.has_function(&f.name)) {
        for p in &mut function.parameters {
            if let Some(default) = &mut p.default {
                crate::passes::walk_expression(default, &mut resolve);
            }
        }
    }
    for global in &mut module.globals {
        if global.default.is_none() {
            global.default = default_expression(&global.ty);
        }
        crate::passes::walk_global(global, &mut resolve);
    }
}

/// The type an expression names when it is a type used as a value's
/// receiver: `Doc` in `Doc.Line`, `Tree<int>` in `Tree<int>.Leaf`.
fn named_type(e: &Expression) -> Option<TypeName> {
    match e {
        Expression::SymbolRef { id, .. } => Some(TypeName::new(id)),
        Expression::FunctionCall { function, args, .. } if args.is_empty() => {
            Some(crate::passes::gather_generics::parse_type_string(function))
        }
        _ => None,
    }
}

/// Add each enum's built-in methods (`BUILT_IN_METHODS`), from the cases
/// that survived platform selection:
///
/// - `name(): String`, the case's name as written (`""` for a value that
///   names no case, which only `as`-free code cannot make);
/// - `static from_value(value: R): Result<E>`, the case whose value is
///   `value`, or an error when none has it.
fn add_built_in_methods(module: &mut Module) {
    let mut added = vec![];
    for e in &module.enums {
        let ty = TypeName::new(&e.name);
        let this = || Expression::SymbolRef { id: "this".to_string(), ty: ty.clone(), loc: Loc::NONE };
        let returns = |value: Expression| Statement::Return(ReturnStatement { expr: Some(value), loc: Loc::NONE });
        let text = |value: &str| Expression::StringLiteral { value: value.to_string(), is_raw: false, loc: Loc::NONE };
        let when = |condition: Expression, then: Statement| {
            Statement::Branch(Branch {
                condition,
                if_block: Block { name: String::new(), items: vec![then], attributes: vec![] },
                else_block: None,
            })
        };
        let equal = |lhs: Expression, rhs: Expression| Expression::Binary {
            op: BinaryOp::Equal,
            lhs: Box::new(lhs),
            rhs: Box::new(rhs),
            loc: Loc::NONE,
        };
        let function = |name: &str, ty: TypeName, parameters: Vec<VariableDef>, items: Vec<Statement>, is_static: bool| FunctionDef {
            trait_default: None,
            name: method_name(&e.name, name),
            ty,
            generic_params: vec![],
            parameters,
            body: Some(Block { name: String::new(), items, attributes: vec![] }),
            parent: None,
            is_static,
            is_indexer: false,
            is_generic_func: false,
            attributes: vec![],
            loc: e.loc,
            owner: Loc::NONE,
        };

        let mut items: Vec<Statement> =
            e.cases.iter().map(|c| when(equal(this(), case_value(e, c, Loc::NONE)), returns(text(&c.name)))).collect();
        items.push(returns(text("")));
        added.push(function("name", TypeName::new("String"), vec![this_parameter(&e.name)], items, false));

        let result = format!("Result<{}>", e.name);
        let make = |method: &str, arg: Expression| Expression::MethodCall {
            this: Box::new(Expression::FunctionCall { function: result.clone(), args: vec![], loc: Loc::NONE }),
            method: method.to_string(),
            args: vec![arg],
            loc: Loc::NONE,
        };
        let value = || Expression::SymbolRef { id: "value".to_string(), ty: e.representation.clone(), loc: Loc::NONE };
        let mut items: Vec<Statement> = e
            .cases
            .iter()
            .map(|c| {
                let literal = Expression::Cast {
                    expr: Box::new(Expression::IntLiteral(c.value)),
                    ty: e.representation.clone(),
                    loc: Loc::NONE,
                    kind: CastKind::Synthesized,
                };
                when(equal(value(), literal), returns(make("ok", case_value(e, c, Loc::NONE))))
            })
            .collect();
        let message = format!("no case of '{}' has this value", pepper_parser::namespace::demangle_name(&e.name));
        items.push(returns(make("err", text(&message))));
        let mut parameter = this_parameter(&e.name);
        parameter.name = "value".to_string();
        parameter.ty = e.representation.clone();
        added.push(function("from_value", TypeName::new(&result), vec![parameter], items, true));
    }
    // A checked module's enums have theirs already.
    added.retain(|f| !module.functions.iter().any(|g| g.name == f.name));
    module.functions.extend(added);
}

/// Record every enum method (the functions named `E::m`) for
/// [`method_is_static`].
pub fn install_methods(module: &Module) {
    METHODS.with(|m| {
        let mut m = m.borrow_mut();
        m.clear();
        for f in &module.functions {
            if let Some((enum_name, method)) = method_of(&f.name) {
                let is_static = !f.parameters.first().is_some_and(|p| p.name == "this" && p.ty.name == enum_name);
                m.insert((enum_name.to_string(), method.to_string()), is_static);
            }
        }
    });
}

/// Inside an enum's methods, `this` is the value parameter, and a bare call
/// of another method of the enum (`name()`) calls it on `this`.
fn method_bodies(module: &mut Module) {
    for f in &mut module.functions {
        let Some((enum_name, _)) = method_of(&f.name) else { continue };
        let enum_name = enum_name.to_string();
        let has_this = f.parameters.first().is_some_and(|p| p.name == "this");
        let locals: Vec<String> = f.parameters.iter().map(|p| p.name.clone()).collect();
        let Some(body) = &mut f.body else { continue };
        crate::passes::walk_block(body, &mut |e: &mut Expression| match e {
            Expression::ThisRef => {
                *e = Expression::SymbolRef { id: "this".to_string(), ty: TypeName::new(&enum_name), loc: Loc::NONE }
            }
            Expression::FunctionCall { function, args, .. } if !locals.contains(function) => {
                match method_is_static(&enum_name, function) {
                    Some(true) => *function = method_name(&enum_name, function),
                    Some(false) if has_this => {
                        *function = method_name(&enum_name, function);
                        args.insert(0, Expression::SymbolRef { id: "this".to_string(), ty: TypeName::new(&enum_name), loc: Loc::NONE });
                    }
                    _ => {}
                }
            }
            _ => {}
        });
    }
}

/// A local of an enum type declared without a value starts as the enum's
/// default.
fn give_defaults(block: &mut Block) {
    for stmt in &mut block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) if var.default.is_none() => {
                var.default = default_expression(&var.ty);
            }
            Statement::Block(inner) => give_defaults(inner),
            Statement::Branch(b) => {
                give_defaults(&mut b.if_block);
                if let Some(e) = &mut b.else_block {
                    give_defaults(e);
                }
            }
            Statement::While(w) => give_defaults(&mut w.block),
            _ => {}
        }
    }
}

fn no_case(name: &str, e: &EnumDef, at: Loc) -> Diagnostic {
    Diagnostic::error(format!("no case named '{}' in '{}'", name, e.name))
        .at(at)
        .with_note(format!("'{}' declared here", e.name), Some(e.loc))
}

/// What one `match` handles: each case (or literal) to the first pattern
/// naming it.
#[derive(Default)]
struct Coverage {
    site: Option<MatchSite>,
    /// The enum matched (as shown) and its cases; for a literal match, the
    /// type matched and no cases.
    matched: Option<(String, Vec<EnumCaseDef>)>,
    /// The `match` is over a type with literal patterns (`int`, `String`).
    literal: bool,
    handled: BTreeMap<String, Loc>,
    /// For a `match` over a tuple: its type, the case names of each enum
    /// (and `bool`) inside it, and every pattern so far.
    tuple: Option<TupleCoverage>,
}

struct TupleCoverage {
    ty: TypeName,
    domains: Domains,
    rows: Vec<Space>,
}

/// What a `match` is over: a value enum, a reference enum's cases, or a type
/// matched by literals.
enum Matched<'e> {
    Value(&'e EnumDef),
    Reference { ty: TypeName, cases: Vec<EnumCaseDef>, declared: Loc },
    Literal(TypeName),
}

impl Matched<'_> {
    fn of<'e>(ty: &TypeName, enums: &'e HashMap<String, EnumDef>) -> Option<Matched<'e>> {
        if let Some(e) = enums.get(&ty.to_string()) {
            return Some(Matched::Value(e));
        }
        if is_literal_type(ty) {
            return Some(Matched::Literal(ty.clone()));
        }
        reference_cases(ty).map(|(cases, declared)| Matched::Reference { ty: ty.clone(), cases, declared })
    }

    fn name(&self) -> String {
        match self {
            Matched::Value(e) => e.name.clone(),
            Matched::Reference { ty, .. } | Matched::Literal(ty) => shown(ty),
        }
    }

    fn cases(&self) -> &[EnumCaseDef] {
        match self {
            Matched::Value(e) => &e.cases,
            Matched::Reference { cases, .. } => cases,
            Matched::Literal(_) => &[],
        }
    }
}

/// A type `match` compares with literal patterns: an integer, `char`,
/// `bool`, or `String`.
fn is_literal_type(ty: &TypeName) -> bool {
    ty.is_scalar()
        && (ty.name == "String"
            || (crate::type_name::INTEGRAL_TYPES.contains(ty.name.as_str())
                && !ty.name.ends_with('*')
                && !matches!(ty.name.as_str(), "void" | "__auto" | "f32" | "float" | "f64" | "double")))
}

/// The subject of a lowered `match` or `is` test, typed as `ty`: its hidden
/// `__match_N` local, or the `Subject` of a `match` expression.
fn typed(subject: &Expression, ty: &TypeName) -> Expression {
    let mut subject = subject.clone();
    if let Expression::SymbolRef { ty: slot, .. } | Expression::Subject { ty: slot, .. } = &mut subject {
        *slot = ty.clone();
    }
    subject
}

/// `subject.__tag`, the case of a reference enum's object.
fn tag_of(subject: &Expression, at: Loc) -> Expression {
    Expression::MemberRef { lhs: Box::new(subject.clone()), name: TAG_FIELD.to_string(), loc: at }
}

fn tag_is(subject: &Expression, case: &EnumCaseDef, at: Loc) -> Expression {
    Expression::Binary {
        op: BinaryOp::Equal,
        lhs: Box::new(tag_of(subject, at)),
        rhs: Box::new(Expression::IntLiteral(case.value)),
        loc: at,
    }
}

/// The payload field a pattern's binding reads: `subject.Text.text`.
fn case_field(subject: &Expression, case: &EnumCaseDef, index: usize, at: Loc) -> Expression {
    Expression::MemberRef {
        lhs: Box::new(subject.clone()),
        name: payload_field(&case.name, &case.payload[index].0),
        loc: at,
    }
}

/// Turn each `match` arm test into `==` tests on the `match`'s subject, and
/// check each `match` handles every case of its enum. Runs once every type
/// is final. Generic bodies are skipped: they never reach codegen, and their
/// specializations are lowered in their place.
pub fn lower_matches(module: &mut Module) {
    let enums: HashMap<String, EnumDef> = module.enums.iter().map(|e| (e.name.clone(), e.clone())).collect();
    let table = crate::static_type::StructTable::build(module);
    let mut warnings: Vec<Diagnostic> = vec![];
    for_each_body_in(module, |block, generic, current| {
        if generic {
            return;
        }
        check_arm_types(block, &table, current);
        // Per body: a generic function's specializations each hold a copy
        // of its `match`es.
        let mut coverage: BTreeMap<usize, Coverage> = BTreeMap::new();
        lower_block(block, &enums, &mut HashMap::new(), &mut coverage);
        for c in coverage.values() {
            if let Some(w) = check_exhaustive(c)
                && !warnings.iter().any(|seen| seen.loc == w.loc)
            {
                warnings.push(w);
            }
        }
    });
    module.warnings.extend(warnings);
}

fn lower_block(
    block: &mut Block,
    enums: &HashMap<String, EnumDef>,
    subjects: &mut HashMap<String, TypeName>,
    coverage: &mut BTreeMap<usize, Coverage>,
) {
    let mut items = Vec::with_capacity(block.items.len());
    for mut stmt in std::mem::take(&mut block.items) {
        lower_statement(&mut stmt, enums, subjects, coverage);
        let after = match &mut stmt {
            Statement::Declaration(Declaration::Variable(var)) => lower_declaration(var, subjects),
            _ => vec![],
        };
        items.push(stmt);
        items.extend(after);
    }
    block.items = items;
}

/// What follows a declaration in a lowered `match`:
///
/// - after the subject (`__match_N`) of a reference enum that is not a
///   `[Value]` enum, a check that it is not null;
/// - a binding's local gets the matched case's value: the payload field
///   itself when one pattern binds it, else a chain of assignments that
///   picks the field by the object's tag (alternatives, `A(x), B(x)`).
fn lower_declaration(var: &mut VariableDef, subjects: &HashMap<String, TypeName>) -> Vec<Statement> {
    // A `[Value]` enum is never null.
    if var.hidden
        && var.name.starts_with("__match_")
        && is_reference_enum(&var.ty)
        && !crate::value_structs::is_value(&var.ty.to_string())
    {
        let message = format!("match on a null '{}'", shown(&var.ty));
        let not_null = Expression::Binary {
            op: BinaryOp::NotIdentical,
            lhs: Box::new(Expression::SymbolRef { id: var.name.clone(), ty: var.ty.clone(), loc: var.loc }),
            rhs: Box::new(Expression::PointerLiteral),
            loc: var.loc,
        };
        let check = Expression::FunctionCall {
            function: "_pep_assert".to_string(),
            args: vec![not_null, Expression::StringLiteral { value: message, is_raw: true, loc: var.loc }],
            loc: var.loc,
        };
        return vec![Statement::Expression(check)];
    }
    let Some(Expression::CaseValue(value)) = var.default.clone() else {
        return vec![];
    };
    let Some((subject, picks)) = case_picks(&value, subjects) else {
        return vec![];
    };
    let at = value.loc;
    if let [(case, index)] = &picks[..] {
        var.default = Some(case_field(&subject, case, *index, at));
        return vec![];
    }
    // `var x; if (tag == A) { x = subject.A.x; } else if ... else { x = subject.Z.x; }`
    var.default = None;
    let assign = |case: &EnumCaseDef, index: usize| Block {
        name: String::new(),
        items: vec![Statement::Expression(Expression::Binary {
            op: BinaryOp::Assign,
            lhs: Box::new(Expression::SymbolRef { id: var.name.clone(), ty: var.ty.clone(), loc: at }),
            rhs: Box::new(case_field(&subject, case, index, at)),
            loc: at,
        })],
        attributes: vec![],
    };
    let mut chain: Option<Block> = None;
    for (i, (case, index)) in picks.iter().enumerate().rev() {
        chain = Some(if i + 1 == picks.len() {
            assign(case, *index)
        } else {
            Block {
                name: String::new(),
                items: vec![Statement::Branch(Branch {
                    condition: tag_is(&subject, case, at),
                    if_block: assign(case, *index),
                    else_block: chain.take(),
                })],
                attributes: vec![],
            }
        });
    }
    chain.map(|b| b.items).unwrap_or_default()
}

/// The typed subject a binding reads, and each case it may read from with
/// the binding's position there.
fn case_picks(value: &CaseValue, subjects: &HashMap<String, TypeName>) -> Option<(Expression, Vec<(EnumCaseDef, usize)>)> {
    let (subject, ty) = typed_path(&value.subject, subjects)?;
    let (cases, _) = reference_cases(&ty)?;
    let picks: Vec<(EnumCaseDef, usize)> = value
        .choices
        .iter()
        .filter_map(|c| cases.iter().find(|case| case.name == c.case).map(|case| (case.clone(), c.index)))
        .filter(|(case, index)| *index < case.payload.len())
        .collect();
    Some((subject, picks))
}

/// A `match`'s subject, or an element of it (`__match_N.0.1`), with the
/// subject typed, and the type of what it reads.
fn typed_path(path: &Expression, subjects: &HashMap<String, TypeName>) -> Option<(Expression, TypeName)> {
    match path {
        Expression::SymbolRef { id, .. } => {
            let ty = subjects.get(id)?.clone();
            Some((typed(path, &ty), ty))
        }
        Expression::Subject { ty, .. } => Some((path.clone(), ty.clone())),
        Expression::MemberRef { lhs, name, loc } => {
            let index: usize = name.parse().ok()?;
            let (lhs, ty) = typed_path(lhs, subjects)?;
            let element = ty.is_tuple().then(|| ty.tuple_elements().get(index).cloned()).flatten()?;
            Some((Expression::MemberRef { lhs: Box::new(lhs), name: name.clone(), loc: *loc }, element))
        }
        _ => None,
    }
}

/// The arm test a condition holds: `MatchArm(...)`, or the left side of a
/// guarded arm's `MatchArm(...) && guard`.
pub fn arm_test(condition: &Expression) -> Option<&MatchArmTest> {
    match condition {
        Expression::MatchArm(test) => Some(test),
        Expression::Binary { op: BinaryOp::LogicalAnd, lhs, .. } => match lhs.as_ref() {
            Expression::MatchArm(test) if test.guarded => Some(test),
            _ => None,
        },
        _ => None,
    }
}

/// A binding inside a `match` expression's arm value or an arm's guard: the
/// payload field, or `?:` on the tag when alternatives bind it.
fn lower_case_value(value: &CaseValue, subjects: &HashMap<String, TypeName>) -> Option<Expression> {
    let (subject, picks) = case_picks(value, subjects)?;
    let at = value.loc;
    let (last, rest) = picks.split_last()?;
    let mut chain = case_field(&subject, &last.0, last.1, at);
    for (case, index) in rest.iter().rev() {
        chain = Expression::Ternary {
            condition: Box::new(tag_is(&subject, case, at)),
            true_expr: Box::new(case_field(&subject, case, *index, at)),
            false_expr: Box::new(chain),
        };
    }
    Some(chain)
}

fn lower_statement(
    stmt: &mut Statement,
    enums: &HashMap<String, EnumDef>,
    subjects: &mut HashMap<String, TypeName>,
    coverage: &mut BTreeMap<usize, Coverage>,
) {
    match stmt {
        Statement::Declaration(Declaration::Variable(var)) => {
            if var.hidden && var.name.starts_with("__match_") {
                subjects.insert(var.name.clone(), var.ty.clone());
            }
            if let Some(default) = &mut var.default {
                lower_expressions(default, enums, subjects, coverage);
            }
        }
        Statement::Declaration(_) => {}
        Statement::Block(inner) => lower_block(inner, enums, subjects, coverage),
        Statement::Expression(e) => lower_expressions(e, enums, subjects, coverage),
        Statement::Branch(branch) => {
            if let Some(test) = arm_test(&branch.condition) {
                let test = test.clone();
                let mut cases = vec![];
                if let Some(condition) = lower_arm(&test, enums, subjects, coverage, &mut cases) {
                    match &mut branch.condition {
                        Expression::Binary { lhs, rhs, .. } => {
                            **lhs = condition;
                            lower_expressions(rhs, enums, subjects, coverage);
                        }
                        other => *other = condition,
                    }
                }
                // A bare element name that is a case binds nothing: drop the
                // local the builder declared for it.
                branch.if_block.items.retain(|item| {
                    !matches!(item, Statement::Declaration(Declaration::Variable(v)) if cases.contains(&v.name))
                });
            } else {
                lower_expressions(&mut branch.condition, enums, subjects, coverage);
            }
            lower_block(&mut branch.if_block, enums, subjects, coverage);
            if let Some(else_block) = &mut branch.else_block {
                lower_block(else_block, enums, subjects, coverage);
            }
        }
        Statement::While(wh) => {
            lower_expressions(&mut wh.condition, enums, subjects, coverage);
            lower_block(&mut wh.block, enums, subjects, coverage);
        }
        Statement::Return(ret) => {
            if let Some(e) = &mut ret.expr {
                lower_expressions(e, enums, subjects, coverage);
            }
        }
        Statement::LoopBreak(_) | Statement::Static(_) => {}
    }
}

/// Lower the `match` expressions and `is` tests in an expression, and the
/// `match` statements inside closure literals it holds (lifted closures are
/// methods, reached through `for_each_body`; this covers any still inline).
fn lower_expressions(
    expr: &mut Expression,
    enums: &HashMap<String, EnumDef>,
    subjects: &mut HashMap<String, TypeName>,
    coverage: &mut BTreeMap<usize, Coverage>,
) {
    match expr {
        Expression::ClosureLiteral(c) => {
            lower_block(&mut c.body, enums, &mut subjects.clone(), coverage);
            return;
        }
        Expression::MatchArm(test) => {
            let test = test.clone();
            *expr = lower_arm(&test, enums, subjects, coverage, &mut vec![]).unwrap_or(Expression::BoolLiteral(false));
            return;
        }
        Expression::CaseValue(value) => {
            if let Some(lowered) = lower_case_value(value, subjects) {
                *expr = lowered;
            }
            return;
        }
        Expression::WithSubject(with) => {
            let ty = subject_type(&with.body, with.id);
            if let Some(ty) = &ty
                && is_reference_enum(ty)
                && !crate::value_structs::is_value(&ty.to_string())
            {
                with.null_message = Some(format!("match on a null '{}'", shown(ty)));
            }
            lower_expressions(&mut with.subject, enums, subjects, coverage);
            lower_expressions(&mut with.body, enums, subjects, coverage);
            drop_no_match(&mut with.body);
            return;
        }
        _ => {}
    }
    for child in crate::passes::children_mut(expr) {
        lower_expressions(child, enums, subjects, coverage);
    }
}

/// A `match` expression without `else`, once its tests are lowered: the
/// last arm's value stands on its own (`check_exhaustive` reports a case no
/// arm handles), so `test ? value : NoMatch` becomes `value`.
fn drop_no_match(chain: &mut Expression) {
    let mut at = chain;
    loop {
        match at {
            Expression::Ternary { true_expr, false_expr, .. } if matches!(false_expr.as_ref(), Expression::NoMatch) => {
                let value = std::mem::replace(true_expr.as_mut(), Expression::NoMatch);
                *at = value;
                return;
            }
            Expression::Ternary { false_expr, .. } => at = false_expr,
            _ => return,
        }
    }
}

/// The type `resolve_implicit_types` gave the `Subject`s of the
/// `WithSubject` numbered `id`.
fn subject_type(body: &Expression, id: usize) -> Option<TypeName> {
    let mut found = None;
    crate::passes::visit_expression(body, &mut |e| {
        if let Expression::Subject { id: n, ty, .. } = e
            && *n == id
            && found.is_none()
        {
            found = Some(ty.clone());
        }
    });
    found
}

/// The `==` tests one arm stands for, or `None` after reporting an error.
///
/// `cases` receives each declared bare element name that turned out to be a
/// case, whose local the caller drops.
fn lower_arm(
    test: &MatchArmTest,
    enums: &HashMap<String, EnumDef>,
    subjects: &HashMap<String, TypeName>,
    coverage: &mut BTreeMap<usize, Coverage>,
    cases: &mut Vec<String>,
) -> Option<Expression> {
    let (ty, subject_loc) = match &test.subject {
        Expression::SymbolRef { id, loc, .. } => (subjects.get(id).cloned().unwrap_or_else(TypeName::auto), *loc),
        Expression::Subject { ty, loc, .. } => (ty.clone(), *loc),
        _ => return None,
    };
    let subject = typed(&test.subject, &ty);
    let entry = coverage.entry(test.site.id).or_default();
    entry.site = Some(test.site.clone());
    if ty.is_tuple() {
        return lower_tuple_arm(test, &subject, &ty, subject_loc, enums, entry, cases);
    }
    if let Some(p) = test.patterns.iter().find(|p| p.elements.is_some()) {
        let shown = if ty.is_auto() { "a value of an unknown type".to_string() } else { format!("a value of '{}'", shown(&ty)) };
        report(Diagnostic::error(format!("a tuple pattern cannot match {}", shown)).at(p.loc).with_note("the value matched is here", Some(subject_loc)));
        return None;
    }
    let Some(matched) = Matched::of(&ty, enums) else {
        let shown = if ty.is_auto() { "an unknown type".to_string() } else { format!("'{}'", ty) };
        report(
            Diagnostic::error(format!(
                "cannot match on a value of {}: 'match' needs an enum, an integer, 'char', 'bool' or 'String'",
                shown
            ))
            .at(subject_loc),
        );
        return None;
    };
    entry.matched = Some((matched.name(), matched.cases().to_vec()));
    entry.literal = matches!(matched, Matched::Literal(_));
    let mut condition: Option<Expression> = None;
    for p in &test.patterns {
        if let Some(first) = entry.handled.get(&p.case) {
            let what = if p.literal.is_some() { "value" } else { "case" };
            report(
                Diagnostic::error(format!("{} '{}' is already handled", what, p.case))
                    .at(p.loc)
                    .with_note("first handled here", Some(*first)),
            );
            return None;
        }
        let equal = match (&matched, &p.literal) {
            (Matched::Literal(_), Some(literal)) => literal.clone(),
            (Matched::Literal(ty), None) => {
                report(
                    Diagnostic::error(format!(
                        "'{}' is not a literal: a 'match' on '{}' takes literal patterns",
                        p.case,
                        shown(ty)
                    ))
                    .at(p.loc),
                );
                return None;
            }
            (_, Some(_)) => {
                report(
                    Diagnostic::error(format!(
                        "a literal cannot match a value of '{}': name its cases",
                        matched.name()
                    ))
                    .at(p.loc),
                );
                return None;
            }
            (_, None) => enum_test(p, &matched, &subject, subject_loc)?,
        };
        // A guarded arm may not run, so it handles nothing.
        if !test.guarded {
            entry.handled.insert(p.case.clone(), p.loc);
        }
        condition = Some(match condition {
            None => equal,
            Some(c) => Expression::Binary { op: BinaryOp::LogicalOr, lhs: Box::new(c), rhs: Box::new(equal), loc: p.loc },
        });
    }
    Some(condition.unwrap_or(Expression::BoolLiteral(false)))
}

/// The test of a case pattern over an enum, or `None` after reporting an
/// error.
fn enum_test(p: &CasePattern, matched: &Matched, subject: &Expression, subject_loc: Loc) -> Option<Expression> {
    let qualifier_fits = |q: &TypeName| match matched {
        Matched::Value(e) => q.to_string() == e.name,
        Matched::Reference { ty, .. } => q.name == ty.name,
        Matched::Literal(_) => false,
    };
    if let Some(q) = &p.qualifier
        && !qualifier_fits(q)
    {
        report(
            Diagnostic::error(format!("'{}' is not the type of the value matched, '{}'", q, matched.name()))
                .at(p.loc)
                .with_note("the value matched is here", Some(subject_loc)),
        );
        return None;
    }
    let case = match matched {
        Matched::Value(e) => match e.case(&p.case) {
            Some(case) => case,
            None => {
                report(no_case(&p.case, e, p.loc));
                return None;
            }
        },
        Matched::Reference { ty, cases, declared } => match find_case(cases, &p.case, ty, *declared, p.loc) {
            Ok(case) => case,
            Err(d) => {
                report(d);
                return None;
            }
        },
        Matched::Literal(_) => return None,
    };
    match (matched, &p.bindings) {
        (Matched::Value(e), Some(bindings)) => {
            let at = bindings.first().map_or(p.loc, |(_, l)| *l);
            report(
                Diagnostic::error(format!("case '{}' of '{}' carries no values to bind", case.name, e.name))
                    .at(at)
                    .with_note(format!("'{}' declared here", case.name), Some(case.loc)),
            );
            return None;
        }
        (Matched::Reference { .. }, Some(bindings)) => {
            let extra = bindings.get(case.payload.len()).map(|(_, l)| *l);
            if let Err(d) = check_binding_count(case, bindings.len(), extra, p.loc) {
                report(d);
                return None;
            }
        }
        _ => {}
    }
    Some(match matched {
        Matched::Value(e) => Expression::Binary {
            op: BinaryOp::Equal,
            lhs: Box::new(subject.clone()),
            rhs: Box::new(case_value(e, case, p.loc)),
            loc: p.loc,
        },
        _ => tag_is(subject, case, p.loc),
    })
}

/// Report a `match` that leaves cases unhandled; return the warning for an
/// `else` that nothing reaches. An `is` test handles what it names.
fn check_exhaustive(c: &Coverage) -> Option<Diagnostic> {
    let (Some(site), Some((name, cases))) = (&c.site, &c.matched) else {
        return None;
    };
    if site.partial {
        return None;
    }
    if let Some(tuple) = &c.tuple {
        let rows: Vec<Vec<Space>> = tuple.rows.iter().map(|r| vec![r.clone()]).collect();
        let missing = useful(&rows, &[Space::Any], std::slice::from_ref(&tuple.ty), &tuple.domains);
        match (site.else_arm, missing) {
            (Some(else_loc), None) => {
                return Some(Diagnostic::warning(format!("'else' is unreachable: every value of '{}' is handled", name)).at(else_loc));
            }
            (None, Some(witness)) => report(
                Diagnostic::error(format!("match on '{}' does not handle '{}'", name, witness[0]))
                    .at(site.keyword)
                    .with_note("handle it with another arm, or add an 'else' arm", None),
            ),
            _ => {}
        }
        return None;
    }
    if c.literal {
        let every_bool = name == "bool" && c.handled.contains_key("true") && c.handled.contains_key("false");
        match site.else_arm {
            Some(else_loc) if every_bool => {
                return Some(Diagnostic::warning("'else' is unreachable: 'true' and 'false' are both handled").at(else_loc));
            }
            None if !every_bool => report(
                Diagnostic::error(format!("match on '{}' needs an 'else' arm", name))
                    .at(site.keyword)
                    .with_note("literal patterns cannot handle every value", None),
            ),
            _ => {}
        }
        return None;
    }
    let missing: Vec<&EnumCaseDef> = cases.iter().filter(|case| !c.handled.contains_key(&case.name)).collect();
    match site.else_arm {
        Some(else_loc) if missing.is_empty() && !cases.is_empty() => {
            return Some(
                Diagnostic::warning(format!("'else' is unreachable: every case of '{}' is handled", name)).at(else_loc),
            );
        }
        Some(_) => {}
        None if missing.is_empty() => {}
        None => {
            const SHOWN: usize = 5;
            let names: Vec<String> = missing.iter().take(SHOWN).map(|m| format!("'{}'", m.name)).collect();
            let listed = match names.len() {
                1 => names[0].clone(),
                n => format!("{} and {}", names[..n - 1].join(", "), names[n - 1]),
            };
            let more = if missing.len() > SHOWN { format!(" and {} more", missing.len() - SHOWN) } else { String::new() };
            let mut diagnostic = Diagnostic::error(format!("match on '{}' does not handle {}{}", name, listed, more))
                .at(site.keyword)
                .with_note("handle each case, or add an 'else' arm", None);
            for m in missing.iter().take(SHOWN) {
                diagnostic = diagnostic.with_note(format!("'{}' declared here", m.name), Some(m.loc));
            }
            report(diagnostic);
        }
    }
    None
}

/// Report a `match` expression whose arms produce values of types that do
/// not mix: it has the first arm's type, or, when the arms are numbers, their
/// common type (`arithmetic::conditional_result`). Numbers mix (they
/// convert), and `__null` fits any reference.
fn check_arm_types(block: &mut Block, table: &crate::static_type::StructTable, current: Option<&TypeName>) {
    crate::passes::walk_block(block, &mut |e| {
        let Expression::WithSubject(with) = e else { return };
        let mut arms: Vec<&Expression> = vec![];
        let mut at = &with.body;
        while let Expression::Ternary { condition, true_expr, false_expr } = at {
            if arm_test(condition).is_none() {
                break;
            }
            arms.push(true_expr);
            at = false_expr;
        }
        if arms.is_empty() {
            return;
        }
        if !matches!(at, Expression::NoMatch) {
            arms.push(at);
        }
        let first = arms[0];
        let Some(expected) = crate::static_type::of(first, table, current) else { return };
        for arm in &arms[1..] {
            if matches!(arm, Expression::PointerLiteral) {
                continue;
            }
            let Some(actual) = crate::static_type::of(arm, table, current) else { continue };
            let primitive = |t: &TypeName| t.is_scalar() && crate::type_name::INTEGRAL_TYPES.contains(t.name.as_str());
            if actual == expected || (primitive(&actual) && primitive(&expected)) {
                continue;
            }
            let mut diagnostic = Diagnostic::error(format!(
                "'match' arm has a value of type '{}', but the first arm's is '{}'",
                shown(&actual),
                shown(&expected)
            ))
            .at(arm.loc());
            if !first.loc().is_none() {
                diagnostic = diagnostic.with_note("the first arm's value is here", Some(first.loc()));
            }
            report(diagnostic);
            return;
        }
    });
}

// ── Tuple patterns ───────────────────────────────────────────────────────────
//
// A tuple pattern `(Circle, 0, r)` tests each element on its own path from
// the subject (`__match_N.0 == Shape.Circle && __match_N.1 == 0`); a bare
// name there binds its element unless the element's enum has a case of that
// name. Which values an arm's patterns cover is a `Space`, and a `match`
// over a tuple is exhaustive when no value escapes every arm (`useful`, the
// usefulness check of Maranget's "Warnings for pattern matching").

/// The values a pattern covers, for exhaustiveness.
#[derive(Debug, Clone, PartialEq)]
enum Space {
    /// Every value: `_` or a name that binds.
    Any,
    /// One case, or one literal (as written).
    Case(String),
    /// A tuple of the element spaces.
    Tuple(Vec<Space>),
}

impl std::fmt::Display for Space {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Space::Any => write!(f, "_"),
            Space::Case(c) => write!(f, "{}", c),
            Space::Tuple(elements) => {
                let shown: Vec<String> = elements.iter().map(|e| e.to_string()).collect();
                write!(f, "({})", shown.join(", "))
            }
        }
    }
}

/// Every case of each enum (and of `bool`) in a tuple type, by type as
/// written; a type missing here has too many values to list.
type Domains = HashMap<String, Vec<String>>;

fn collect_domains(ty: &TypeName, enums: &HashMap<String, EnumDef>, out: &mut Domains) {
    if ty.is_tuple() {
        for element in ty.tuple_elements() {
            collect_domains(element, enums, out);
        }
        return;
    }
    let cases: Option<Vec<String>> = match Matched::of(ty, enums) {
        Some(Matched::Literal(t)) if t.name == "bool" => Some(vec!["true".to_string(), "false".to_string()]),
        Some(Matched::Literal(_)) | None => None,
        Some(m) => Some(m.cases().iter().map(|c| c.name.clone()).collect()),
    };
    if let Some(cases) = cases {
        out.insert(ty.to_string(), cases);
    }
}

/// A value no row covers that `v` does, as a witness, or `None` when the
/// rows cover everything `v` does. `tys` are the columns' types.
fn useful(rows: &[Vec<Space>], v: &[Space], tys: &[TypeName], domains: &Domains) -> Option<Vec<Space>> {
    let Some((head, rest)) = v.split_first() else {
        return rows.is_empty().then(Vec::new);
    };
    let ty = &tys[0];
    if ty.is_tuple() {
        let elements = ty.tuple_elements();
        let expand = |s: &Space| match s {
            Space::Tuple(es) if es.len() == elements.len() => es.clone(),
            _ => vec![Space::Any; elements.len()],
        };
        let rows: Vec<Vec<Space>> = rows
            .iter()
            .map(|r| {
                let mut e = expand(&r[0]);
                e.extend(r[1..].iter().cloned());
                e
            })
            .collect();
        let mut v = expand(head);
        v.extend(rest.iter().cloned());
        let mut tys2 = elements.to_vec();
        tys2.extend(tys[1..].iter().cloned());
        let witness = useful(&rows, &v, &tys2, domains)?;
        let (inner, tail) = witness.split_at(elements.len());
        let mut out = vec![Space::Tuple(inner.to_vec())];
        out.extend(tail.iter().cloned());
        return Some(out);
    }
    let specialize = |case: &str| -> Vec<Vec<Space>> {
        rows.iter()
            .filter(|r| matches!(&r[0], Space::Any) || matches!(&r[0], Space::Case(c) if c == case))
            .map(|r| r[1..].to_vec())
            .collect()
    };
    let with_head = |head: Space, tail: Vec<Space>| {
        let mut out = vec![head];
        out.extend(tail);
        out
    };
    match head {
        Space::Case(case) => useful(&specialize(case), rest, &tys[1..], domains).map(|w| with_head(head.clone(), w)),
        Space::Any => {
            let used: Vec<&String> = rows
                .iter()
                .filter_map(|r| match &r[0] {
                    Space::Case(c) => Some(c),
                    _ => None,
                })
                .collect();
            let domain = domains.get(&ty.to_string());
            if let Some(all) = domain
                && !all.is_empty()
                && all.iter().all(|c| used.contains(&c))
            {
                return all.iter().find_map(|case| {
                    useful(&specialize(case), rest, &tys[1..], domains).map(|w| with_head(Space::Case(case.clone()), w))
                });
            }
            let defaults: Vec<Vec<Space>> =
                rows.iter().filter(|r| matches!(&r[0], Space::Any)).map(|r| r[1..].to_vec()).collect();
            let witness = useful(&defaults, rest, &tys[1..], domains)?;
            let missing = domain.and_then(|all| all.iter().find(|c| !used.contains(c)));
            Some(with_head(missing.map_or(Space::Any, |c| Space::Case(c.clone())), witness))
        }
        Space::Tuple(_) => None,
    }
}

/// Lower an arm of a `match` over a tuple (see [`lower_arm`]).
fn lower_tuple_arm(
    test: &MatchArmTest,
    subject: &Expression,
    ty: &TypeName,
    subject_loc: Loc,
    enums: &HashMap<String, EnumDef>,
    entry: &mut Coverage,
    cases: &mut Vec<String>,
) -> Option<Expression> {
    entry.matched = Some((shown(ty), vec![]));
    let coverage = entry.tuple.get_or_insert_with(|| {
        let mut domains = Domains::new();
        collect_domains(ty, enums, &mut domains);
        TupleCoverage { ty: ty.clone(), domains, rows: vec![] }
    });
    // Each bare element name, by location: whether it named a case.
    let mut names: Vec<(Loc, bool)> = vec![];
    let mut condition: Option<Expression> = None;
    for p in &test.patterns {
        if p.elements.is_none() {
            report(
                Diagnostic::error(format!(
                    "'{}' cannot match a value of '{}': match a tuple with a tuple pattern, such as '(a, _)'",
                    p.case,
                    shown(ty)
                ))
                .at(p.loc)
                .with_note("the value matched is here", Some(subject_loc)),
            );
            return None;
        }
        let tested = element_test(p, subject, ty, subject_loc, enums, &mut names)?;
        let space = space_of(p, ty, enums);
        if !test.site.partial
            && useful(
                &coverage.rows.iter().map(|r| vec![r.clone()]).collect::<Vec<_>>(),
                std::slice::from_ref(&space),
                std::slice::from_ref(ty),
                &coverage.domains,
            )
            .is_none()
        {
            report(
                Diagnostic::error(format!("pattern '{}' is already handled", p.case))
                    .at(p.loc)
                    .with_note("the patterns before it match every value it does", None),
            );
            return None;
        }
        if !test.guarded {
            coverage.rows.push(space);
        }
        let tested = tested.unwrap_or(Expression::BoolLiteral(true));
        condition = Some(match condition {
            None => tested,
            Some(c) => Expression::Binary { op: BinaryOp::LogicalOr, lhs: Box::new(c), rhs: Box::new(tested), loc: p.loc },
        });
    }
    for name in &test.element_names {
        let Some((_, is_case)) = names.iter().find(|(at, _)| *at == name.loc) else { continue };
        if !is_case {
            if test.site.no_bindings {
                report(
                    Diagnostic::error(format!(
                        "cannot bind '{}' here: 'is' binds names only as the whole condition of an 'if' or 'while'",
                        name.name
                    ))
                    .at(name.loc),
                );
                return None;
            }
            if !name.declared {
                report(
                    Diagnostic::error(format!(
                        "'{}' binds an element here, but not once at the same element in every pattern of the arm",
                        name.name
                    ))
                    .at(name.loc)
                    .with_note("bind it once in each pattern, at the same element, or use '_'", None),
                );
                return None;
            }
        }
    }
    // A declared name must be a case everywhere or a binding everywhere.
    for name in test.element_names.iter().filter(|n| n.declared) {
        let resolved: Vec<bool> = test
            .element_names
            .iter()
            .filter(|n| n.name == name.name)
            .filter_map(|n| names.iter().find(|(at, _)| *at == n.loc).map(|(_, c)| *c))
            .collect();
        if resolved.iter().all(|c| *c) {
            if !cases.contains(&name.name) {
                cases.push(name.name.clone());
            }
        } else if resolved.iter().any(|c| *c) {
            report(
                Diagnostic::error(format!(
                    "'{}' names a case in one pattern of the arm and binds an element in another: rename the binding",
                    name.name
                ))
                .at(name.loc),
            );
            return None;
        }
    }
    Some(condition.unwrap_or(Expression::BoolLiteral(false)))
}

/// The test of pattern `p` over `subject` of type `ty`: `None` inside when
/// it matches every value, `None` outside after reporting an error.
fn element_test(
    p: &CasePattern,
    subject: &Expression,
    ty: &TypeName,
    subject_loc: Loc,
    enums: &HashMap<String, EnumDef>,
    names: &mut Vec<(Loc, bool)>,
) -> Option<Option<Expression>> {
    if let Some(elements) = &p.elements {
        if !ty.is_tuple() {
            report(Diagnostic::error(format!("a tuple pattern cannot match a value of '{}'", shown(ty))).at(p.loc));
            return None;
        }
        let types = ty.tuple_elements();
        if types.len() != elements.len() {
            report(Diagnostic::error(format!(
                "pattern '{}' has {} elements, but '{}' has {}",
                p.case,
                elements.len(),
                shown(ty),
                types.len()
            ))
            .at(p.loc));
            return None;
        }
        let mut condition: Option<Expression> = None;
        for (i, (e, element_ty)) in elements.iter().zip(types).enumerate() {
            let path = Expression::MemberRef { lhs: Box::new(subject.clone()), name: i.to_string(), loc: e.loc };
            if let Some(tested) = element_test(e, &path, element_ty, subject_loc, enums, names)? {
                condition = Some(match condition {
                    None => tested,
                    Some(c) => Expression::Binary { op: BinaryOp::LogicalAnd, lhs: Box::new(c), rhs: Box::new(tested), loc: e.loc },
                });
            }
        }
        return Some(condition);
    }
    let matched = Matched::of(ty, enums);
    if let Some(literal) = &p.literal {
        if !matches!(matched, Some(Matched::Literal(_))) {
            report(Diagnostic::error(format!("a literal cannot match a value of '{}'", shown(ty))).at(p.loc));
            return None;
        }
        return Some(Some(literal.clone()));
    }
    let names_case = |m: &Matched| m.cases().iter().any(|c| c.name == p.case);
    if p.qualifier.is_none() && p.bindings.is_none() {
        if p.case == "_" {
            return Some(None);
        }
        let is_case = matched.as_ref().is_some_and(|m| !matches!(m, Matched::Literal(_)) && names_case(m));
        names.push((p.loc, is_case));
        if !is_case {
            return Some(None);
        }
    }
    match &matched {
        Some(m) if !matches!(m, Matched::Literal(_)) => enum_test(p, m, subject, subject_loc).map(Some),
        _ => {
            report(Diagnostic::error(format!("'{}' cannot match a value of '{}': it is not an enum", p.case, shown(ty))).at(p.loc));
            None
        }
    }
}

/// The values pattern `p` over a value of `ty` covers.
fn space_of(p: &CasePattern, ty: &TypeName, enums: &HashMap<String, EnumDef>) -> Space {
    if let Some(elements) = &p.elements {
        let types = ty.tuple_elements();
        return Space::Tuple(elements.iter().zip(types).map(|(e, t)| space_of(e, t, enums)).collect());
    }
    if p.literal.is_some() {
        return Space::Case(p.case.clone());
    }
    if p.qualifier.is_none() && p.bindings.is_none() {
        let is_case = Matched::of(ty, enums)
            .is_some_and(|m| !matches!(m, Matched::Literal(_)) && m.cases().iter().any(|c| c.name == p.case));
        if !is_case {
            return Space::Any;
        }
    }
    Space::Case(p.case.clone())
}
