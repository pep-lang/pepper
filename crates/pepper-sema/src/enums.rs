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
    for st in &mut module.structs {
        let generic_base = st.ty.is_generic() && st.name == st.ty.name;
        for method in st
            .method_members
            .iter_mut()
            .chain(st.generic_methods.iter_mut())
            .chain(st.constructors.iter_mut())
            .chain([&mut st.destructor, &mut st.acquire, &mut st.release])
        {
            if let Some(body) = &mut method.body {
                f(body, generic_base || method.is_generic_func);
            }
        }
    }
    for extension in &mut module.extensions {
        for method in &mut extension.methods {
            if let Some(body) = &mut method.body {
                f(body, true);
            }
        }
    }
    for tr in &mut module.traits {
        for method in &mut tr.methods {
            if let Some(body) = &mut method.body {
                f(body, true);
            }
        }
    }
    for function in &mut module.functions {
        let generic = function.is_generic_func;
        if let Some(body) = &mut function.body {
            f(body, generic);
        }
    }
}

/// Replace every `Enum.Case` (a member of a name that is an enum) with the
/// case's value, and resolve the qualifiers of `match` patterns
/// (`Color.Red => ...`). Reports `no case named 'X' in 'E'`.
pub fn resolve_enum_cases(module: &mut Module) {
    install(&module.enums);
    if module.enums.is_empty() {
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
    let mut resolve = |expr: &mut Expression| {
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

/// What one `match` handles: each case to the first pattern naming it.
#[derive(Default)]
struct Coverage {
    site: Option<MatchSite>,
    enum_name: Option<String>,
    handled: BTreeMap<String, Loc>,
}

/// Turn each `match` arm test into `==` tests on the `match`'s subject, and
/// check each `match` handles every case of its enum. Runs once every type
/// is final. Generic bodies are skipped: they never reach codegen, and their
/// specializations are lowered in their place.
pub fn lower_matches(module: &mut Module) {
    let enums: HashMap<String, EnumDef> = module.enums.iter().map(|e| (e.name.clone(), e.clone())).collect();
    let mut warnings: Vec<Diagnostic> = vec![];
    for_each_body(module, |block, generic| {
        if generic {
            return;
        }
        // Per body: a generic function's specializations each hold a copy
        // of its `match`es.
        let mut coverage: BTreeMap<usize, Coverage> = BTreeMap::new();
        lower_block(block, &enums, &mut HashMap::new(), &mut coverage);
        for c in coverage.values() {
            if let Some(w) = check_exhaustive(c, &enums)
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
    for stmt in &mut block.items {
        lower_statement(stmt, enums, subjects, coverage);
    }
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

/// Lower the `match` statements inside closure literals an expression holds
/// (lifted closures are methods, reached through `for_each_body`; this
/// covers any still inline).
fn lower_expressions(
    expr: &mut Expression,
    enums: &HashMap<String, EnumDef>,
    subjects: &mut HashMap<String, TypeName>,
    coverage: &mut BTreeMap<usize, Coverage>,
) {
    crate::passes::walk_expression(expr, &mut |e| {
        if let Expression::ClosureLiteral(c) = e {
            lower_block(&mut c.body, enums, &mut subjects.clone(), coverage);
        }
    });
}

/// The `==` tests one arm stands for, or `None` after reporting an error.
fn lower_arm(
    test: &MatchArmTest,
    enums: &HashMap<String, EnumDef>,
    subjects: &HashMap<String, TypeName>,
    coverage: &mut BTreeMap<usize, Coverage>,
) -> Option<Expression> {
    let Expression::SymbolRef { id, loc: subject_loc, .. } = &test.subject else {
        return None;
    };
    let ty = subjects.get(id).cloned().unwrap_or_else(TypeName::auto);
    let entry = coverage.entry(test.site.id).or_default();
    entry.site = Some(test.site.clone());
    let Some(e) = enums.get(&ty.to_string()) else {
        let shown = if ty.is_auto() { "an unknown type".to_string() } else { format!("'{}'", ty) };
        report(
            Diagnostic::error(format!("cannot match on a value of {}: 'match' needs an enum", shown))
                .at(*subject_loc),
        );
        return None;
    };
    entry.enum_name = Some(e.name.clone());
    let mut condition: Option<Expression> = None;
    for p in &test.patterns {
        if let Some(q) = &p.qualifier
            && q.to_string() != e.name
        {
            report(
                Diagnostic::error(format!("'{}' is not the type of the value matched, '{}'", q, e.name))
                    .at(p.loc)
                    .with_note("the value matched is here", Some(*subject_loc)),
            );
            return None;
        }
        let Some(case) = e.case(&p.case) else {
            report(no_case(&p.case, e, p.loc));
            return None;
        };
        if let Some(bindings) = &p.bindings {
            let at = bindings.first().map_or(p.loc, |(_, l)| *l);
            report(
                Diagnostic::error(format!("case '{}' of '{}' carries no values to bind", case.name, e.name))
                    .at(at)
                    .with_note(format!("'{}' declared here", case.name), Some(case.loc)),
            );
            return None;
        }
        if let Some(first) = entry.handled.get(&case.name) {
            report(
                Diagnostic::error(format!("case '{}' is already handled", case.name))
                    .at(p.loc)
                    .with_note("first handled here", Some(*first)),
            );
            return None;
        }
        entry.handled.insert(case.name.clone(), p.loc);
        let equal = Expression::Binary {
            op: BinaryOp::Equal,
            lhs: Box::new(Expression::SymbolRef { id: id.clone(), ty: ty.clone(), loc: *subject_loc }),
            rhs: Box::new(case_value(e, case, p.loc)),
            loc: p.loc,
        };
        condition = Some(match condition {
            None => equal,
            Some(c) => Expression::Binary { op: BinaryOp::LogicalOr, lhs: Box::new(c), rhs: Box::new(equal), loc: p.loc },
        });
    }
    Some(condition.unwrap_or(Expression::BoolLiteral(false)))
}

/// Report a `match` that leaves cases unhandled; return the warning for an
/// `else` that nothing reaches.
fn check_exhaustive(c: &Coverage, enums: &HashMap<String, EnumDef>) -> Option<Diagnostic> {
    let (Some(site), Some(name)) = (&c.site, &c.enum_name) else {
        return None;
    };
    let e = &enums[name];
    let missing: Vec<&EnumCaseDef> = e.cases.iter().filter(|case| !c.handled.contains_key(&case.name)).collect();
    match site.else_arm {
        Some(else_loc) if missing.is_empty() && !e.cases.is_empty() => {
            return Some(
                Diagnostic::warning(format!("'else' is unreachable: every case of '{}' is handled", e.name)).at(else_loc),
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
            let mut diagnostic = Diagnostic::error(format!("match on '{}' does not handle {}{}", e.name, listed, more))
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
