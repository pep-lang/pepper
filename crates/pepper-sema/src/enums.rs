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
    /// Reference enum name (without type arguments) → its cases and the
    /// location of its name, for this run. Filled by [`resolve_enum_cases`].
    static REFERENCE_ENUMS: RefCell<HashMap<String, (Vec<EnumCaseDef>, Loc)>> = RefCell::new(HashMap::new());
}

/// Make the reference enums among `structs` the ones [`reference_cases`]
/// knows, replacing any earlier run's.
pub fn install_reference_enums(structs: &[StructDef]) {
    REFERENCE_ENUMS.with(|r| {
        let mut r = r.borrow_mut();
        r.clear();
        for st in structs {
            if let Some(cases) = &st.enum_cases {
                r.entry(st.ty.name.clone()).or_insert_with(|| (cases.clone(), st.loc));
            }
        }
    });
}

/// The cases of reference enum `ty` (any specialization of it) and the
/// location of its name, or `None` when `ty` is not a reference enum.
pub fn reference_cases(ty: &TypeName) -> Option<(Vec<EnumCaseDef>, Loc)> {
    REFERENCE_ENUMS.with(|r| r.borrow().get(&ty.name).cloned())
}

/// `ty` is a reference enum.
pub fn is_reference_enum(ty: &TypeName) -> bool {
    REFERENCE_ENUMS.with(|r| r.borrow().contains_key(&ty.name))
}

fn shown(ty: &TypeName) -> String {
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
    format!("{}::{}", enum_name, method)
}

/// The enum and method a function named by [`method_name`] belongs to.
pub fn method_of(function: &str) -> Option<(&str, &str)> {
    let (enum_name, method) = function.split_once("::")?;
    is_enum(enum_name).then_some((enum_name, method))
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
    METHODS.with(|m| m.borrow().get(&(enum_name.to_string(), method.to_string())).copied())
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
    Some(Expression::Cast { expr: Box::new(Expression::IntLiteral(value)), ty: ty.clone(), loc: Loc::NONE })
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
    Expression::Cast { expr: Box::new(Expression::IntLiteral(case.value)), ty: TypeName::new(&e.name), loc }
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
    if module.enums.is_empty() && !module.structs.iter().any(|st| st.enum_cases.is_some()) {
        return;
    }
    for ext in &module.extensions {
        if is_enum(&ext.target.name) {
            report(
                Diagnostic::error(format!(
                    "cannot extend enum '{}': declare its methods inside the enum",
                    pepper_parser::namespace::demangle_name(&ext.target.name)
                ))
                .at(ext.loc),
            );
        }
    }
    add_built_in_methods(module);
    install_methods(module);
    method_bodies(module);
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
        // Every located `as E` here is one the user wrote: the cases below
        // are not resolved yet, and synthesized defaults have no location.
        if let Expression::Cast { ty, loc, .. } = expr
            && !loc.is_none()
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
            None => report(no_case(name, e, *loc)),
        }
    };
    let mut in_block = |block: &mut Block, _generic: bool| {
        give_defaults(block);
        crate::passes::walk_block(block, &mut resolve)
    };
    for_each_body(module, &mut in_block);
    for st in &mut module.structs {
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
    for function in &mut module.functions {
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
/// - after the subject (`__match_N`) of a reference enum, a check that it is
///   not null;
/// - a binding's local gets the matched case's value: the payload field
///   itself when one pattern binds it, else a chain of assignments that
///   picks the field by the object's tag (alternatives, `A(x), B(x)`).
fn lower_declaration(var: &mut VariableDef, subjects: &HashMap<String, TypeName>) -> Vec<Statement> {
    if var.hidden && var.name.starts_with("__match_") && is_reference_enum(&var.ty) {
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
    let ty = match &value.subject {
        Expression::SymbolRef { id, .. } => subjects.get(id)?.clone(),
        Expression::Subject { ty, .. } => ty.clone(),
        _ => return None,
    };
    let (cases, _) = reference_cases(&ty)?;
    let picks: Vec<(EnumCaseDef, usize)> = value
        .choices
        .iter()
        .filter_map(|c| cases.iter().find(|case| case.name == c.case).map(|case| (case.clone(), c.index)))
        .filter(|(case, index)| *index < case.payload.len())
        .collect();
    Some((typed(&value.subject, &ty), picks))
}

/// A binding inside a `match` expression's arm value: the payload field, or
/// `?:` on the tag when alternatives bind it.
fn lower_case_value(value: &CaseValue) -> Option<Expression> {
    let (subject, picks) = case_picks(value, &HashMap::new())?;
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
            if let Expression::MatchArm(test) = &branch.condition {
                let test = test.clone();
                if let Some(condition) = lower_arm(&test, enums, subjects, coverage) {
                    branch.condition = condition;
                }
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
        Statement::LoopBreak(_) => {}
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
            *expr = lower_arm(&test, enums, subjects, coverage).unwrap_or(Expression::BoolLiteral(false));
            return;
        }
        Expression::CaseValue(value) => {
            if let Some(lowered) = lower_case_value(value) {
                *expr = lowered;
            }
            return;
        }
        Expression::WithSubject(with) => {
            let ty = subject_type(&with.body, with.id);
            if let Some(ty) = &ty
                && is_reference_enum(ty)
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
    let mut body = body.clone();
    crate::passes::walk_expression(&mut body, &mut |e| {
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
fn lower_arm(
    test: &MatchArmTest,
    enums: &HashMap<String, EnumDef>,
    subjects: &HashMap<String, TypeName>,
    coverage: &mut BTreeMap<usize, Coverage>,
) -> Option<Expression> {
    let (ty, subject_loc) = match &test.subject {
        Expression::SymbolRef { id, loc, .. } => (subjects.get(id).cloned().unwrap_or_else(TypeName::auto), *loc),
        Expression::Subject { ty, loc, .. } => (ty.clone(), *loc),
        _ => return None,
    };
    let subject = typed(&test.subject, &ty);
    let entry = coverage.entry(test.site.id).or_default();
    entry.site = Some(test.site.clone());
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
        entry.handled.insert(p.case.clone(), p.loc);
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
/// not mix: it has the first arm's type. Numbers mix (they convert), and
/// `__null` fits any reference.
fn check_arm_types(block: &mut Block, table: &crate::static_type::StructTable, current: Option<&TypeName>) {
    crate::passes::walk_block(block, &mut |e| {
        let Expression::WithSubject(with) = e else { return };
        let mut arms: Vec<&Expression> = vec![];
        let mut at = &with.body;
        while let Expression::Ternary { condition, true_expr, false_expr } = at {
            if !matches!(condition.as_ref(), Expression::MatchArm(_)) {
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
