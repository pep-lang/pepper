//! Named arguments: `open_window("Editor", height = 400, width = 1200)`.
//!
//! The builder keeps each `name = value` argument as an
//! [`Expression::NamedArgument`] after the positional ones. Binding a call
//! rewrites its arguments into parameter order: each named one moves to its
//! parameter's position, and a parameter skipped before the last one given
//! becomes an [`Expression::DefaultArgument`] (codegen passes its default,
//! as it does for trailing parameters a call leaves out). After binding, a
//! call looks exactly as if it had been written positionally, so no later
//! pass knows about names.
//!
//! - [`bind_calls`] (an early step) binds the calls whose callee a name
//!   decides: free functions, constructors, and a method called bare inside
//!   its struct.
//! - [`bind_method_call`] (called from `resolve_implicit_types`) binds
//!   `value.method(...)` once the receiver's type is known.
//! - [`check_unbound`] reports a named argument still unbound once types are
//!   final.
//!
//! An overloaded callee binds when every member the names fit binds the
//! arguments to the same positions; overload resolution then picks among
//! them as usual (a skipped parameter fits any member that has a default
//! there).
//!
//! Arguments are evaluated in the order written. When binding reorders the
//! named arguments, a receiver that is a call and each argument that is not a
//! literal or a closure is evaluated first into a [`Expression::WithSubject`]
//! around the call, in the order written, and the call reads the
//! [`Expression::Subject`].
//!
//! `[Alias("alias", "parameter")]` gives a parameter a second name, and
//! `[Rename("old", "new")]` keeps a former name working behind a
//! deprecation warning.

use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::diagnostic::Diagnostic;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicUsize, Ordering};

/// The attribute that gives a parameter a second permanent name.
pub const ALIAS_ATTRIBUTE: &str = "Alias";
/// The attribute that keeps a parameter's former name working, deprecated.
pub const RENAME_ATTRIBUTE: &str = "Rename";

/// One parameter, as binding needs it.
#[derive(Clone, Debug)]
pub struct Parameter {
    pub name: String,
    pub has_default: bool,
    /// Its type, or `auto` where it names a generic parameter.
    pub ty: TypeName,
}

/// Another name for a parameter (`[Alias]` or `[Rename]`).
#[derive(Clone, Debug)]
pub struct OtherName {
    pub name: String,
    pub parameter: usize,
    /// A former name (`[Rename]`): using it warns.
    pub deprecated: bool,
}

/// A function a call may bind to.
#[derive(Clone, Debug)]
pub struct Callee {
    /// The name errors show.
    pub display: String,
    pub params: Vec<Parameter>,
    pub other_names: Vec<OtherName>,
    pub loc: Loc,
}

impl Callee {
    /// `function`'s parameters after the first `skip` (an enum method's
    /// value). `generic` names the type parameters in scope of its
    /// declaration (its own and its struct's).
    pub fn of(function: &FunctionDef, display: &str, skip: usize, generic: &[String]) -> Callee {
        let mut generic: Vec<&str> = generic.iter().map(String::as_str).collect();
        generic.extend(function.generic_params.iter().map(|p| p.name.as_str()));
        let params: Vec<Parameter> = function
            .parameters
            .iter()
            .skip(skip)
            .map(|p| Parameter {
                // A constructor's `this.x` parameter (`__init_x` once
                // `struct_body` names it) is named `x`.
                name: p.name.strip_prefix("this.").or_else(|| p.name.strip_prefix("__init_")).unwrap_or(&p.name).to_string(),
                has_default: p.default.is_some(),
                ty: if generic.iter().any(|g| p.ty.mentions(g)) || p.ty.contains_auto() { TypeName::auto() } else { p.ty.clone() },
            })
            .collect();
        let other_names = other_names(&function.attributes, &params, function.loc.file).into_iter().filter_map(Result::ok).collect();
        Callee { display: display.to_string(), params, other_names, loc: function.loc }
    }

    fn index_of(&self, name: &str) -> Option<(usize, bool)> {
        if let Some(i) = self.params.iter().position(|p| p.name == name) {
            return Some((i, false));
        }
        self.other_names.iter().find(|o| o.name == name).map(|o| (o.parameter, o.deprecated))
    }
}

/// The names `[Alias("alias", "parameter")]` and `[Rename("old", "new")]`
/// give `params`, or the error for each attribute that is wrong. The
/// attributes are in `file`.
pub fn other_names(
    attributes: &[pepper_parser::ast::Attribute],
    params: &[Parameter],
    file: pepper_parser::diagnostic::FileId,
) -> Vec<Result<OtherName, Diagnostic>> {
    let mut seen: Vec<String> = params.iter().map(|p| p.name.clone()).collect();
    let mut found = vec![];
    for attr in attributes {
        let Some((kind, arguments)) = attribute_call(attr) else { continue };
        let deprecated = match kind {
            RENAME_ATTRIBUTE => true,
            ALIAS_ATTRIBUTE => false,
            _ => continue,
        };
        found.push(other_name(kind, arguments, attr, params, &mut seen, file).map(|(name, parameter)| OtherName { name, parameter, deprecated }));
    }
    found
}

fn attribute_call(attr: &pepper_parser::ast::Attribute) -> Option<(&str, &[pepper_parser::ast::Expression])> {
    use pepper_parser::ast::Expression as E;
    match &attr.body {
        E::FunctionCall { function, arguments, .. } => match function.as_ref() {
            E::SymbolRef { id, .. } => Some((id.as_str(), arguments.as_slice())),
            _ => None,
        },
        E::SymbolRef { id, .. } => Some((id.as_str(), &[])),
        _ => None,
    }
}

fn other_name(
    kind: &str,
    arguments: &[pepper_parser::ast::Expression],
    attr: &pepper_parser::ast::Attribute,
    params: &[Parameter],
    seen: &mut Vec<String>,
    file: pepper_parser::diagnostic::FileId,
) -> Result<(String, usize), Diagnostic> {
    use pepper_parser::ast::{Expression as E, Literal};
    let at = |span: pepper_parser::ast::Span| Loc::new(file, span);
    let usage = if kind == RENAME_ATTRIBUTE { "[Rename(\"old\", \"new\")]" } else { "[Alias(\"alias\", \"parameter\")]" };
    let strings: Vec<(String, pepper_parser::ast::Span)> = arguments
        .iter()
        .filter_map(|a| match a {
            E::Literal { value: Literal::String(s), span } => Some((s.clone(), *span)),
            _ => None,
        })
        .collect();
    let [(name, name_span), (parameter, parameter_span)] = strings.as_slice() else {
        return Err(Diagnostic::error(format!("'{}' takes two strings: {}", kind, usage)).at(at(attr.span)));
    };
    let Some(index) = params.iter().position(|p| &p.name == parameter) else {
        return Err(Diagnostic::error(format!("no parameter named '{}'", parameter)).at(at(*parameter_span)));
    };
    if seen.contains(name) {
        let what = if params.iter().any(|p| &p.name == name) { "a parameter" } else { "already another name of a parameter" };
        return Err(Diagnostic::error(format!("'{}' is {}", name, what)).at(at(*name_span)));
    }
    seen.push(name.clone());
    Ok((name.clone(), index))
}

/// Report a wrong `[Alias]` or `[Rename]` on any function. Located in the
/// function's file.
pub fn check_attributes(module: &Module) {
    let mut check = |function: &FunctionDef| {
        if !function.attributes.iter().any(|a| matches!(attribute_call(a), Some((RENAME_ATTRIBUTE | ALIAS_ATTRIBUTE, _)))) {
            return;
        }
        let params = Callee::of(function, &function.name, 0, &[]).params;
        for result in other_names(&function.attributes, &params, function.loc.file) {
            if let Err(d) = result {
                crate::errors::report(d);
            }
        }
    };
    for function in &module.functions {
        check(function);
    }
    for st in &module.structs {
        st.constructors.iter().chain(&st.method_members).chain(&st.generic_methods).for_each(&mut check);
    }
    for ext in &module.extensions {
        ext.methods.iter().for_each(&mut check);
    }
}

/// Where each parameter's argument comes from: the index of the argument
/// as written, or `None` for a skipped parameter that takes its default.
type Plan = Vec<Option<usize>>;

/// Where the arguments of a call are: the call's location and where its
/// literal arguments are written (`Module::literal_args`), which carry none
/// of their own.
#[derive(Clone, Copy)]
struct Site<'a> {
    call: Loc,
    literals: &'a [(Loc, usize, Loc)],
}

/// The location of argument `index` of `args` (its name, if named).
fn argument_loc(args: &[Expression], index: usize, site: Site) -> Loc {
    match &args[index] {
        Expression::NamedArgument { loc, .. } => *loc,
        other => match other.loc() {
            Loc::NONE => site.literals.iter().find(|(c, i, _)| *c == site.call && *i == index).map_or(site.call, |(_, _, at)| *at),
            loc => loc,
        },
    }
}

/// Bind `args` to `callee`'s parameters. Also returns the former names
/// used, for their warnings.
fn plan(callee: &Callee, args: &[Expression], site: Site) -> Result<(Plan, Vec<(Loc, String, String)>), Diagnostic> {
    let mut slots: Plan = vec![None; callee.params.len()];
    let mut deprecated = vec![];
    for (written, arg) in args.iter().enumerate() {
        let index = match arg {
            Expression::NamedArgument { name, loc, .. } => match callee.index_of(name) {
                Some((index, renamed)) => {
                    if renamed {
                        deprecated.push((*loc, name.clone(), callee.params[index].name.clone()));
                    }
                    index
                }
                None => {
                    let mut message = format!("no parameter named '{}' in '{}'", name, callee.display);
                    let names = callee.params.iter().map(|p| p.name.as_str()).chain(callee.other_names.iter().filter(|o| !o.deprecated).map(|o| o.name.as_str()));
                    if let Some(close) = closest(name, names) {
                        message.push_str(&format!("; did you mean '{}'?", close));
                    }
                    return Err(Diagnostic::error(message).at(*loc).with_note("declared here", Some(callee.loc)));
                }
            },
            _ if written >= callee.params.len() => {
                return Err(Diagnostic::error(format!(
                    "too many arguments to '{}': expected at most {}, have {}",
                    callee.display,
                    callee.params.len(),
                    args.len()
                ))
                .at(argument_loc(args, written, site))
                .with_note("declared here", Some(callee.loc)));
            }
            _ => written,
        };
        if let Some(first) = slots[index] {
            return Err(Diagnostic::error(format!("argument for '{}' given twice", callee.params[index].name))
                .at(argument_loc(args, written, site))
                .with_note("first given here", Some(argument_loc(args, first, site))));
        }
        slots[index] = Some(written);
    }
    if let Some(missing) = slots.iter().zip(&callee.params).position(|(slot, p)| slot.is_none() && !p.has_default) {
        return Err(Diagnostic::error(format!(
            "missing argument for parameter '{}' in call to '{}'",
            callee.params[missing].name, callee.display
        ))
        .at(site.call)
        .with_note("declared here", Some(callee.loc)));
    }
    // Trailing parameters left out keep their defaults as usual.
    let used = slots.iter().rposition(Option::is_some).map_or(0, |i| i + 1);
    slots.truncate(used);
    Ok((slots, deprecated))
}

/// The candidate closest to `name` by edit distance, if close enough to be
/// a likely typo.
fn closest<'a>(name: &str, candidates: impl Iterator<Item = &'a str>) -> Option<&'a str> {
    let distance = |a: &str, b: &str| {
        let b: Vec<char> = b.chars().collect();
        let mut row: Vec<usize> = (0..=b.len()).collect();
        for (i, ca) in a.chars().enumerate() {
            let mut previous = row[0];
            row[0] = i + 1;
            for (j, cb) in b.iter().enumerate() {
                let current = row[j + 1];
                row[j + 1] = (previous + usize::from(ca != *cb)).min(row[j] + 1).min(current + 1);
                previous = current;
            }
        }
        row[b.len()]
    };
    candidates
        .map(|c| (distance(name, c), c))
        .filter(|(d, c)| *d <= name.len().max(c.len()).div_ceil(3))
        .min_by_key(|(d, _)| *d)
        .map(|(_, c)| c)
}

/// Whether `args` names any argument.
pub fn has_named(args: &[Expression]) -> bool {
    args.iter().any(|a| matches!(a, Expression::NamedArgument { .. }))
}

/// The location of the first named argument's name.
fn first_named(args: &[Expression]) -> Loc {
    args.iter()
        .find_map(|a| match a {
            Expression::NamedArgument { loc, .. } => Some(*loc),
            _ => None,
        })
        .unwrap_or(Loc::NONE)
}

thread_local! {
    /// Warnings binding found (former parameter names), until the pass that
    /// bound takes them into `Module::warnings`.
    static WARNINGS: std::cell::RefCell<Vec<Diagnostic>> = const { std::cell::RefCell::new(vec![]) };
}

/// Move the warnings binding found into `module`.
pub fn take_warnings(module: &mut Module) {
    WARNINGS.with(|w| module.warnings.append(&mut w.borrow_mut()));
}

/// A `WithSubject` id no `match` uses.
fn next_subject() -> usize {
    static NEXT: AtomicUsize = AtomicUsize::new(usize::MAX / 2);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// Whether `expr` stays in place when binding reorders arguments: a literal
/// (including a string literal `convert_string_literals` made a `String`),
/// or a closure, which takes its parameter types from its parameter.
/// Evaluating one later than written changes nothing a call can see, except
/// what a closure captures.
fn is_constant(expr: &Expression) -> bool {
    if crate::passes::overloads::is_string_literal(expr) {
        return true;
    }
    match expr {
        Expression::MakeClosure { .. } => true,
        Expression::BoolLiteral(_)
        | Expression::IntLiteral(_)
        | Expression::FloatLiteral(_)
        | Expression::StringLiteral { .. }
        | Expression::PointerLiteral
        | Expression::ClosureLiteral(_)
        | Expression::FunctionRef { .. } => true,
        Expression::Unary { op: UnaryOp::Neg | UnaryOp::Pos | UnaryOp::BitNot | UnaryOp::LogicalNot, operand, .. } => is_constant(operand),
        Expression::Cast { expr, .. } => is_constant(expr),
        _ => false,
    }
}

/// Bind the call `call` (a `FunctionCall` or `MethodCall` with named
/// arguments) to the one of `callees` its names fit, reporting an error when
/// none does.
pub fn bind(call: &mut Expression, callees: &[Callee], literals: &[(Loc, usize, Loc)]) {
    let (args, at) = match call {
        Expression::FunctionCall { args, loc, .. } | Expression::MethodCall { args, loc, .. } => (args, *loc),
        _ => return,
    };
    if !has_named(args) || callees.is_empty() {
        return;
    }
    let site = Site { call: at, literals };
    let results: Vec<_> = callees.iter().map(|c| plan(c, args, site)).collect();
    let viable: Vec<(usize, &(Plan, Vec<(Loc, String, String)>))> =
        results.iter().enumerate().filter_map(|(i, r)| r.as_ref().ok().map(|p| (i, p))).collect();
    let Some(&(first, (chosen, deprecated))) = viable.first() else {
        if let [Err(only)] = results.as_slice() {
            crate::errors::report(only.clone());
            return;
        }
        let mut error = Diagnostic::error(format!("no matching function for call to '{}'", callees[0].display)).at(first_named(args));
        for (callee, result) in callees.iter().zip(&results) {
            if let Err(why) = result {
                error = error.with_note(format!("candidate function not viable: {}", why.message), Some(callee.loc));
            }
        }
        crate::errors::report(error);
        return;
    };
    if viable.iter().any(|(_, (plan, _))| plan != chosen) {
        let mut error =
            Diagnostic::error(format!("named arguments bind differently in the overloads of '{}'", callees[first].display)).at(first_named(args));
        for (i, _) in &viable {
            error = error.with_note("candidate function", Some(callees[*i].loc));
        }
        crate::errors::report(error);
        return;
    }
    for (loc, old, new) in deprecated {
        let fix = pepper_parser::diagnostic::Fix::replace(format!("rename '{}' to '{}'", old, new), *loc, new.clone());
        WARNINGS.with(|w| w.borrow_mut().push(Diagnostic::deprecated(&format!("parameter name '{}'", old), &format!("use '{}' instead", new), *loc, fix)));
    }
    // A skipped parameter's type: its members' if they agree.
    let hole_type = |index: usize| {
        let mut types = viable.iter().map(|(i, _)| &callees[*i].params[index].ty);
        let ty = types.next().cloned().unwrap_or_else(TypeName::auto);
        if types.all(|t| *t == ty) { ty } else { TypeName::auto() }
    };
    let positional = args.iter().take_while(|a| !matches!(a, Expression::NamedArgument { .. })).count();
    // The parameter each named argument fills, in written order.
    let filled: Vec<usize> = (positional..args.len()).map(|w| chosen.iter().position(|s| *s == Some(w)).unwrap_or(0)).collect();
    let reordered = filled.windows(2).any(|w| w[0] > w[1]);
    let mut written: Vec<Option<Expression>> = std::mem::take(args)
        .into_iter()
        .map(|a| match a {
            Expression::NamedArgument { value, .. } => Some(*value),
            other => Some(other),
        })
        .collect();
    // Reordered arguments: evaluate the receiver when it is a call, then
    // every argument, first, in the order written.
    let mut hoisted: Vec<(usize, Expression, Loc)> = vec![];
    let mut hoist = |value: Expression| {
        let id = next_subject();
        let loc = match value.loc() {
            Loc::NONE => at,
            loc => loc,
        };
        hoisted.push((id, value, loc));
        Expression::Subject { id, ty: TypeName::auto(), loc }
    };
    if reordered {
        if let Expression::MethodCall { this, .. } = call
            && matches!(this.as_ref(), Expression::FunctionCall { .. } | Expression::MethodCall { .. } | Expression::Invoke { .. })
        {
            let receiver = std::mem::replace(this.as_mut(), Expression::NoMatch);
            **this = hoist(receiver);
        }
        for slot in &mut written {
            let value = slot.take().unwrap();
            *slot = Some(if is_constant(&value) { value } else { hoist(value) });
        }
    }
    let bound: Vec<Expression> = chosen
        .iter()
        .enumerate()
        .map(|(index, slot)| match slot {
            Some(w) => written[*w].take().unwrap(),
            None => Expression::DefaultArgument { ty: hole_type(index) },
        })
        .collect();
    if let Expression::FunctionCall { args, .. } | Expression::MethodCall { args, .. } = call {
        *args = bound;
    }
    for (id, subject, loc) in hoisted.into_iter().rev() {
        let body = std::mem::replace(call, Expression::NoMatch);
        *call = Expression::WithSubject(Box::new(WithSubject { id, subject, body, null_message: None, loc }));
    }
}

/// The callees of a module, by how calls name them.
#[derive(Default)]
pub struct Callees {
    /// Free functions (and enum and value-type methods, `E::m`) by name.
    functions: HashMap<String, Vec<Callee>>,
    externs: HashSet<String>,
    /// Constructors by struct name (`Point`, `Box<int>`, and a generic
    /// base's `Box`).
    constructors: HashMap<String, Vec<Callee>>,
    /// Methods by receiver type, then by overload set name.
    methods: HashMap<String, HashMap<String, Vec<Callee>>>,
    /// `Module::literal_args`.
    literals: Vec<(Loc, usize, Loc)>,
}

impl Callees {
    pub fn of(module: &Module) -> Self {
        let mut callees = Callees { literals: module.literal_args.clone(), ..Callees::default() };
        for function in &module.functions {
            let display = function.name.split('<').next().unwrap_or(&function.name);
            let set = crate::passes::overloads::set_name(display).to_string();
            callees.functions.entry(set).or_default().push(Callee::of(function, display, 0, &[]));
        }
        callees.externs = module.externs.iter().map(|e| e.name.clone()).collect();
        for st in &module.structs {
            let generic: Vec<String> =
                if st.name.contains('<') { vec![] } else { st.generic_params.iter().map(|p| p.name.clone()).collect() };
            let display = st.name.clone();
            let constructors: Vec<Callee> = st.constructors.iter().map(|c| Callee::of(c, &display, 0, &generic)).collect();
            callees.constructors.entry(st.name.clone()).or_default().extend(constructors.iter().cloned());
            if st.ty.to_string() != st.name {
                callees.constructors.entry(st.ty.to_string()).or_default().extend(constructors);
            }
            let methods = callees.methods.entry(st.ty.to_string()).or_default();
            for method in st.method_members.iter().chain(&st.generic_methods) {
                let base = method.name.split('<').next().unwrap_or(&method.name);
                let set = crate::passes::overloads::set_name(base).to_string();
                let display = format!("{}.{}", st.name, set);
                let list = methods.entry(set).or_default();
                // A specialized generic method (`map<long>`) repeats its base.
                if !method.name.contains('<') || !st.generic_methods.iter().any(|g| g.name == base) {
                    list.push(Callee::of(method, &display, 0, &generic));
                }
            }
        }
        for ty in crate::traits::used_trait_types(module) {
            if let Some(def) = crate::traits::trait_def(&module.traits, &ty) {
                let instance = crate::traits::instance(def, &ty);
                let methods = callees.methods.entry(ty.to_string()).or_default();
                for method in &instance.methods {
                    let display = format!("{}.{}", ty.display(), method.name);
                    methods.entry(method.name.clone()).or_default().push(Callee::of(method, &display, 0, &[]));
                }
            }
        }
        callees
    }

    /// The methods of set `method` on a receiver of type `receiver`.
    pub fn methods(&self, receiver: &str, method: &str) -> Option<&[Callee]> {
        let base = method.split('<').next().unwrap_or(method);
        self.methods.get(receiver)?.get(crate::passes::overloads::set_name(base)).map(Vec::as_slice)
    }

    /// The free functions named `name` (type arguments ignored).
    pub fn functions(&self, name: &str) -> Option<&[Callee]> {
        let base = name.split('<').next().unwrap_or(name);
        self.functions.get(crate::passes::overloads::set_name(base)).map(Vec::as_slice)
    }
}

/// Report naming arguments in a call to an extern.
fn report_extern(name: &str, args: &[Expression]) {
    crate::errors::report(
        Diagnostic::error(format!("cannot name arguments in a call to extern function '{}'", name)).at(first_named(args)),
    );
}

/// Report naming arguments in a call through a function value of type `ty`.
pub fn report_function_value(ty: &TypeName, args: &[Expression]) {
    crate::errors::report(
        Diagnostic::error(format!("cannot name arguments in a call through a function value of type '{}'", ty.display()))
            .at(first_named(args)),
    );
}

/// Every name declared in `function`: its parameters and locals. A call by
/// one of them goes through a value, not a function.
fn declared_names(function: &FunctionDef) -> HashSet<String> {
    let mut names: HashSet<String> = function.parameters.iter().map(|p| p.name.clone()).collect();
    fn block(b: &Block, names: &mut HashSet<String>) {
        for item in &b.items {
            statement(item, names);
        }
    }
    fn statement(s: &Statement, names: &mut HashSet<String>) {
        match s {
            Statement::Declaration(Declaration::Variable(v)) => {
                names.insert(v.name.clone());
            }
            Statement::Block(b) => block(b, names),
            Statement::Branch(branch) => {
                block(&branch.if_block, names);
                if let Some(e) = &branch.else_block {
                    block(e, names);
                }
            }
            Statement::While(w) => block(&w.block, names),
            _ => {}
        }
    }
    if let Some(body) = &function.body {
        block(body, &mut names);
    }
    names
}

/// Bind the calls a name decides (see the module docs).
pub fn bind_calls(module: &mut Module) {
    let callees = Callees::of(module);
    let globals: HashSet<String> = module.globals.iter().map(|g| g.name.clone()).collect();
    let bind_in = |function: &mut FunctionDef, own: Option<&HashMap<String, Vec<Callee>>>| {
        let locals = declared_names(function);
        let mut each = |e: &mut Expression| {
            let Expression::FunctionCall { function: name, args, .. } = e else { return };
            if !has_named(args) {
                return;
            }
            let base = name.split('<').next().unwrap_or(name).to_string();
            if locals.contains(&base) || globals.contains(&base) {
                return;
            }
            let set = crate::passes::overloads::set_name(&base).to_string();
            let found = own
                .and_then(|methods| methods.get(&set))
                .or_else(|| callees.functions.get(&set))
                .or_else(|| callees.constructors.get(name.as_str()))
                .or_else(|| callees.constructors.get(&base));
            match found {
                Some(list) => {
                    let list = list.clone();
                    bind(e, &list, &callees.literals);
                }
                None if callees.externs.contains(&base) => report_extern(&base, args),
                None => {}
            }
        };
        for parameter in &mut function.parameters {
            if let Some(default) = &mut parameter.default {
                crate::passes::walk_expression(default, &mut each);
            }
        }
        crate::passes::walk_function(function, &mut each);
    };
    for function in &mut module.functions {
        bind_in(function, None);
    }
    for st in &mut module.structs {
        let own = callees.methods.get(&st.ty.to_string()).cloned();
        for function in st.constructors.iter_mut().chain(&mut st.method_members).chain(&mut st.generic_methods).chain(std::iter::once(&mut st.destructor)) {
            bind_in(function, own.as_ref());
        }
    }
    for ext in &mut module.extensions {
        for function in &mut ext.methods {
            bind_in(function, None);
        }
    }
    for trait_def in &mut module.traits {
        for function in &mut trait_def.methods {
            bind_in(function, None);
        }
    }
    for global in &mut module.globals {
        crate::passes::walk_global(global, &mut |e| {
            let Expression::FunctionCall { function: name, args, .. } = e else { return };
            if !has_named(args) {
                return;
            }
            let base = name.split('<').next().unwrap_or(name).to_string();
            let found = callees.functions(&base).or_else(|| callees.constructors.get(&base).map(Vec::as_slice));
            if let Some(list) = found {
                let list = list.to_vec();
                bind(e, &list, &callees.literals);
            } else if callees.externs.contains(&base) {
                report_extern(&base, args);
            }
        });
    }
    take_warnings(module);
}

/// Bind `receiver.method(args)` (see the module docs), given the receiver's
/// type.
pub fn bind_method_call(e: &mut Expression, receiver: &TypeName, callees: &Callees) {
    let Expression::MethodCall { method, args, .. } = e else { return };
    if !has_named(args) || receiver.is_empty() || receiver.contains_auto() {
        return;
    }
    let receiver_name = receiver.to_string();
    // A method of an enum or another value type is the function `E::m`,
    // whose first parameter is the value.
    let key = crate::value_types::key(&receiver_name).unwrap_or_else(|| receiver_name.clone());
    if let Some(is_static) = crate::enums::method_is_static(&key, method) {
        let name = crate::enums::method_name(&key, method);
        if let Some(list) = callees.functions.get(&name) {
            let skip = usize::from(!is_static);
            let list: Vec<Callee> = list
                .iter()
                .map(|c| Callee { params: c.params.iter().skip(skip).cloned().collect(), other_names: shift(&c.other_names, skip), ..c.clone() })
                .collect();
            bind(e, &list, &callees.literals);
        }
        return;
    }
    if let Some(list) = callees.methods(&receiver_name, method) {
        let list = list.to_vec();
        bind(e, &list, &callees.literals);
    }
}

fn shift(names: &[OtherName], skip: usize) -> Vec<OtherName> {
    names
        .iter()
        .filter(|o| o.parameter >= skip)
        .map(|o| OtherName { parameter: o.parameter - skip, ..o.clone() })
        .collect()
}

/// Report a named argument left unbound once types are final, outside
/// generic code (only its specializations are compiled).
pub fn check_unbound(module: &Module) {
    let mut check = |function: &FunctionDef| {
        crate::passes::visit_function(function, &mut |e| {
            let (Expression::FunctionCall { args, .. } | Expression::MethodCall { args, .. } | Expression::Invoke { args, .. }) = e else {
                return;
            };
            if has_named(args) {
                crate::errors::report(Diagnostic::error("cannot name the arguments of this call").at(first_named(args)));
            }
        });
    };
    for function in module.functions.iter().filter(|f| !f.is_generic_func) {
        check(function);
    }
    for st in module.structs.iter().filter(|s| s.generic_params.is_empty() || s.name.contains('<')) {
        st.constructors.iter().chain(&st.method_members).for_each(&mut check);
    }
}
