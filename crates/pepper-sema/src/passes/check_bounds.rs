//! Definition checking of constrained generic code: inside `total_area<T:
//! Shape>`, a value of type `T` offers exactly what `Shape` offers, checked
//! in the generic itself, whether or not any specialization exists.
//!
//! A value of a constrained parameter's type may call the instance methods
//! and operators its constraints' traits declare, call their static members
//! through the parameter (`T.make()`), flow into a slot of one of those trait
//! types (`var s: Shape = value;`), and be stored, passed, returned and
//! compared (`==`, `!=`, `===`, `!==`). Anything else on it is an error at
//! the member or operator: a field, a method no constraint declares, a
//! constructor `T()`, a call with the wrong number or kind of arguments, and
//! a conversion to another type. An unconstrained parameter keeps the
//! template behavior: its uses are checked in each specialization.
//!
//! The pass only reports; it produces no code. Specializations still
//! dispatch statically to the type argument's own methods.

use crate::model::*;
use crate::passes::check_function_types::canonical;
use crate::passes::overloads::set_name;
use crate::static_type::StructTable;
use crate::type_name::{replace_map, TypeName};
use std::collections::HashMap;

/// A constrained parameter in scope: its constraints and their members.
struct Constrained {
    /// Each constraint's trait type and where it is written.
    bounds: Vec<(TypeName, Loc)>,
    /// Each member the constraints declare: which constraint (by index),
    /// and its signature with the trait's parameters and `this` replaced.
    members: Vec<(usize, FunctionDef)>,
}

impl Constrained {
    fn of(param: &GenericParam, traits: &[TraitDef]) -> Self {
        let mut members = vec![];
        for (index, bound) in param.bounds.iter().enumerate() {
            // The built-in `Shared` offers no members.
            if crate::passes::constraints::is_shared_bound(&bound.ty) {
                continue;
            }
            let Some(def) = traits.iter().find(|t| t.name == bound.ty.name) else { continue };
            let mut map: Vec<(String, TypeName)> = def
                .generic_params
                .iter()
                .enumerate()
                .filter_map(|(i, p)| Some((p.name.clone(), bound.ty.sub_types.get(i).cloned().or_else(|| p.default.clone())?)))
                .collect();
            map.push(("this".to_string(), TypeName::new(&param.name)));
            for method in &def.methods {
                // A generic member's own parameters (`put<U>`) shadow the
                // trait's.
                let own: Vec<(String, TypeName)> =
                    map.iter().filter(|(n, _)| !method.generic_params.iter().any(|p| p.name == *n)).cloned().collect();
                let mut m = method.clone();
                m.body = None;
                substitute_all(&mut m.ty, &own);
                for p in &mut m.parameters {
                    substitute_all(&mut p.ty, &own);
                }
                members.push((index, m));
            }
        }
        Constrained { bounds: param.bounds.iter().map(|b| (b.ty.clone(), b.loc)).collect(), members }
    }

    /// The members named `name` (an overload set's members too; a generic
    /// method by its name without type arguments).
    fn named(&self, name: &str) -> Vec<&(usize, FunctionDef)> {
        let base = without_type_arguments(name);
        self.members.iter().filter(|(_, m)| set_name(&m.name) == base).collect()
    }

    /// The note for a member `what` no constraint declares.
    fn missing(&self, param: &str, what: &str) -> (String, Option<Loc>) {
        let names: Vec<String> = self.bounds.iter().map(|(b, _)| format!("'{}'", b.display())).collect();
        let message = match names.as_slice() {
            [one] => format!("'{}' is constrained by {}, which has no {}", param, one, what),
            _ => format!("'{}' is constrained by {}, none of which has {}", param, names.join(" & "), what),
        };
        (message, self.bounds.first().map(|(_, l)| *l))
    }
}

/// `ty` with every name in `map` replaced by its type at once, so a
/// replacement is never replaced again (`T -> U, U -> int` maps `T` to `U`).
fn substitute_all(ty: &mut TypeName, map: &[(String, TypeName)]) {
    let pointee = ty.name.strip_suffix('*').filter(|_| ty.sub_types.is_empty());
    let found = map.iter().find(|(n, _)| Some(n.as_str()) == pointee || (ty.sub_types.is_empty() && *n == ty.name));
    if let Some((name, with)) = found {
        if *name == ty.name {
            *ty = with.clone();
        } else {
            ty.name = format!("{}*", with);
        }
        return;
    }
    for sub in &mut ty.sub_types {
        substitute_all(sub, map);
    }
}

/// `member`'s signature at a call spelled `method` (`put<int>`): its
/// parameter types and result, with its own type parameters replaced by
/// the written type arguments, or unknown (`None`) where they are not
/// written.
fn member_signature(member: &FunctionDef, method: &str) -> (Vec<Option<TypeName>>, Option<TypeName>) {
    let written = crate::passes::gather_generics::parse_type_string(method).sub_types;
    let map: Vec<(String, TypeName)> =
        member.generic_params.iter().map(|p| p.name.clone()).zip(written.iter().cloned()).collect();
    let resolve = |ty: &TypeName| {
        let mut ty = ty.clone();
        substitute_all(&mut ty, &map);
        let unknown = member.generic_params.iter().any(|p| mentions(&ty, &p.name)) || ty.is_auto();
        (!unknown).then_some(ty)
    };
    (member.parameters.iter().map(|p| resolve(&p.ty)).collect(), resolve(&member.ty))
}

fn mentions(ty: &TypeName, name: &str) -> bool {
    ty.name == name || ty.name.strip_suffix('*') == Some(name) || ty.sub_types.iter().any(|t| mentions(t, name))
}

/// Checks every generic base with a constrained parameter (see the module
/// docs). Runs before anything is specialized.
pub fn check_bounds(module: &Module) {
    let has = |params: &[GenericParam]| params.iter().any(|p| !p.bounds.is_empty());
    let generic = |f: &FunctionDef| has(&f.generic_params);
    let any = module.functions.iter().any(generic)
        || module.extensions.iter().any(|e| !e.restated.is_empty())
        || module.structs.iter().any(|st| has(&st.generic_params) || st.generic_methods.iter().any(generic))
        || module.traits.iter().any(|t| has(&t.generic_params) || t.methods.iter().any(generic));
    if !any {
        return;
    }
    let table = StructTable::build(module);
    let struct_params = module
        .structs
        .iter()
        .filter(|st| !st.generic_params.is_empty() && !st.name.contains('<'))
        .map(|st| (st.name.clone(), st.generic_params.iter().map(|p| p.name.clone()).collect()))
        .collect();
    let checker = Checker { traits: &module.traits, literal_args: &module.literal_args, table: &table, struct_params };
    for function in module.functions.iter().filter(|f| f.is_generic_func && generic(f)) {
        checker.function(function, &[], None);
    }
    for st in module.structs.iter().filter(|st| !st.name.contains('<')) {
        let current = Some(&st.ty);
        // Inside a constrained extension (`extend Box<T: Named>`), a
        // parameter offers the struct's constraints and the extension's.
        let extended: Vec<(std::collections::HashSet<Loc>, Vec<GenericParam>)> =
            crate::passes::constraints::constrained_extensions(module, &st.name)
                .into_iter()
                .map(|c| {
                    let mut params = st.generic_params.clone();
                    for (i, bound) in &c.added {
                        if let Some(p) = params.get_mut(*i) {
                            p.bounds.push((*bound).clone());
                        }
                    }
                    let locs = c.ext.methods.iter().map(|m| m.loc).collect();
                    (locs, params)
                })
                .collect();
        let params_of = |m: &FunctionDef| -> &[GenericParam] {
            extended.iter().find(|(locs, _)| locs.contains(&m.loc)).map_or(&st.generic_params, |(_, p)| p)
        };
        let methods = st.method_members.iter().chain(&st.constructors).chain([&st.destructor]);
        for method in methods.filter(|m| m.trait_default.is_none()) {
            let own = params_of(method);
            if has(own) {
                checker.function(method, own, current);
            }
        }
        for method in st.generic_methods.iter().filter(|m| m.trait_default.is_none()) {
            let own = params_of(method);
            if has(own) || generic(method) {
                checker.function(method, own, current);
            }
        }
    }
    for t in &module.traits {
        for method in t.methods.iter().filter(|m| m.body.is_some()) {
            if has(&t.generic_params) || generic(method) {
                let own = t.methods.iter().map(|m| (set_name(&m.name).to_string(), m.ty.clone())).collect();
                checker.function_with(method, &t.generic_params, None, own);
            }
        }
    }
}

struct Checker<'m> {
    traits: &'m [TraitDef],
    /// Where literal arguments are written (`Module::literal_args`).
    literal_args: &'m [(Loc, usize, Loc)],
    table: &'m StructTable,
    /// Each generic struct's parameter names, to read its members' types at
    /// a specialization (`Array<T>`'s `__index_get` returns `T`).
    struct_params: HashMap<String, Vec<String>>,
}

/// The state of one function's walk.
struct Walk<'c> {
    params: HashMap<String, Constrained>,
    /// Locals and parameters, innermost scope last.
    scopes: Vec<HashMap<String, TypeName>>,
    current: Option<&'c TypeName>,
    /// The return types of the methods a bare call names.
    own: HashMap<String, TypeName>,
    returns: TypeName,
    function: String,
}

impl Checker<'_> {
    fn function(&self, function: &FunctionDef, outer: &[GenericParam], current: Option<&TypeName>) {
        self.function_with(function, outer, current, HashMap::new());
    }

    /// [`Checker::function`], where a bare call of `own` (a trait's default
    /// method calling a sibling) returns its type.
    fn function_with(&self, function: &FunctionDef, outer: &[GenericParam], current: Option<&TypeName>, own: HashMap<String, TypeName>) {
        let Some(body) = &function.body else { return };
        let params: HashMap<String, Constrained> = outer
            .iter()
            .chain(&function.generic_params)
            .filter(|p| !p.bounds.is_empty() && !p.is_argument)
            .map(|p| (p.name.clone(), Constrained::of(p, self.traits)))
            .collect();
        if params.is_empty() {
            return;
        }
        let locals = function.parameters.iter().map(|p| (p.name.trim_start_matches("this.").to_string(), p.ty.clone())).collect();
        let mut walk = Walk {
            params,
            scopes: vec![locals],
            current,
            own,
            returns: function.ty.clone(),
            function: set_name(&function.name).to_string(),
        };
        for p in &function.parameters {
            if let Some(default) = &p.default {
                self.expression(default, &mut walk);
            }
        }
        self.block(body, &mut walk);
    }

    fn block(&self, block: &Block, walk: &mut Walk) {
        walk.scopes.push(HashMap::new());
        for stmt in &block.items {
            self.statement(stmt, walk);
        }
        walk.scopes.pop();
    }

    fn statement(&self, stmt: &Statement, walk: &mut Walk) {
        match stmt {
            Statement::Expression(e) => self.expression(e, walk),
            Statement::Block(b) => self.block(b, walk),
            Statement::Declaration(Declaration::Variable(var)) => {
                let mut ty = var.ty.clone();
                if let Some(default) = &var.default {
                    self.expression(default, walk);
                    let value = self.type_of(default, walk);
                    if ty.is_auto() {
                        ty = value.unwrap_or_else(TypeName::auto);
                    } else if let Some(value) = value {
                        let at = if default.loc().is_none() { var.loc } else { default.loc() };
                        if let Some(bad) = self.flows(&value, &ty, walk) {
                            report(
                                Diagnostic::error(format!(
                                    "cannot initialize variable '{}' of type '{}' with a value of type '{}'",
                                    var.name,
                                    ty.display(),
                                    value.display()
                                ))
                                .at(at),
                                bad,
                            );
                        }
                    }
                }
                walk.scopes.last_mut().expect("scope").insert(var.name.clone(), ty);
            }
            Statement::Declaration(_) | Statement::LoopBreak(_) | Statement::Static(_) | Statement::StaticPass(_) => {}
            Statement::Branch(branch) => {
                self.expression(&branch.condition, walk);
                self.block(&branch.if_block, walk);
                if let Some(else_block) = &branch.else_block {
                    self.block(else_block, walk);
                }
            }
            Statement::While(wh) => {
                self.expression(&wh.condition, walk);
                self.block(&wh.block, walk);
            }
            Statement::Return(ret) => {
                let Some(value) = &ret.expr else { return };
                self.expression(value, walk);
                if walk.returns.is_auto() {
                    return;
                }
                if let Some(ty) = self.type_of(value, walk)
                    && let Some(bad) = self.flows(&ty, &walk.returns, walk)
                {
                    let at = if value.loc().is_none() { ret.loc } else { value.loc() };
                    report(
                        Diagnostic::error(format!(
                            "cannot return a value of type '{}' from '{}', which returns '{}'",
                            ty.display(),
                            walk.function,
                            walk.returns.display()
                        ))
                        .at(at),
                        bad,
                    );
                }
            }
        }
    }

    /// The constrained parameter `ty` names, if it names one.
    fn constrained<'w>(&self, ty: &TypeName, walk: &'w Walk) -> Option<(&'w str, &'w Constrained)> {
        if !ty.sub_types.is_empty() {
            return None;
        }
        walk.params.get_key_value(&ty.name).map(|(k, c)| (k.as_str(), c))
    }

    fn local(&self, name: &str, walk: &Walk) -> Option<TypeName> {
        walk.scopes.iter().rev().find_map(|s| s.get(name).cloned())
    }

    /// Whether a value of type `value` may flow into a slot of type `slot`.
    /// `None` when it may; otherwise the note for a constrained `value`.
    fn flows(&self, value: &TypeName, slot: &TypeName, walk: &Walk) -> Option<(String, Option<Loc>)> {
        let (param, c) = self.constrained(value, walk)?;
        if slot.contains_auto() || canonical(slot) == canonical(value) {
            return None;
        }
        if c.bounds.iter().any(|(b, _)| canonical(b) == canonical(slot)) {
            return None;
        }
        // Another generic parameter, a pointer or a function type: left to
        // the specializations.
        if (slot.sub_types.is_empty() && walk.params.contains_key(&slot.name) && slot.name != value.name)
            || slot.is_pointer()
            || slot.name.starts_with("__")
        {
            return None;
        }
        let names: Vec<String> = c.bounds.iter().map(|(b, _)| format!("'{}'", b.display())).collect();
        Some((
            format!("'{}' converts only to its constraint{} {}", param, if names.len() == 1 { "" } else { "s" }, names.join(" & ")),
            c.bounds.first().map(|(_, l)| *l),
        ))
    }

    /// The type of `expr` where the walk can tell.
    fn type_of(&self, expr: &Expression, walk: &Walk) -> Option<TypeName> {
        match expr {
            Expression::SymbolRef { id, ty, .. } => self
                .local(id, walk)
                .or_else(|| self.field(id, walk))
                .or_else(|| (!ty.is_empty() && !ty.is_auto()).then(|| ty.clone()))
                .filter(|t| !t.is_auto()),
            Expression::MethodCall { this, method, .. } => {
                if let Some(c) = self.static_receiver(this, walk) {
                    return c.named(method).first().and_then(|(_, m)| member_signature(m, method).1);
                }
                let receiver = self.type_of(this, walk)?;
                if let Some((_, c)) = self.constrained(&receiver, walk) {
                    return c.named(method).first().and_then(|(_, m)| member_signature(m, method).1);
                }
                self.member_return(&receiver, method)
            }
            Expression::ForIterator(source) => {
                let source = self.type_of(source, walk)?;
                // A constrained parameter iterates as its constraints say:
                // through `iterate()` (`Iterable<T>`), or as an iterator.
                if let Some((_, c)) = self.constrained(&source, walk) {
                    let iterate = c.named("iterate").into_iter().find(|(_, m)| !m.is_static && m.parameters.is_empty());
                    return match iterate {
                        Some((_, m)) => member_signature(m, "iterate").1,
                        None => (!c.named("next").is_empty() && !c.named("current").is_empty()).then_some(source),
                    };
                }
                Some(self.member_return(&source, "iterate").unwrap_or(source))
            }
            Expression::Index { lhs, .. } => {
                let owner = self.type_of(lhs, walk)?;
                self.member_return(&owner, "__index_get")
            }
            Expression::MemberRef { lhs, name, .. } => {
                let owner = self.type_of(lhs, walk)?;
                if let Some(element) = owner.tuple_element(name) {
                    return Some(element.clone());
                }
                let info = self.table.lookup(&owner)?;
                let mut ty = info.fields.iter().find(|(f, _)| f == name).map(|(_, t)| t.clone())?;
                self.specialize(&owner, &mut ty);
                Some(ty)
            }
            Expression::Ternary { true_expr, .. } => self.type_of(true_expr, walk),
            Expression::Binary { op, lhs, .. } if op.is_assignment() => self.type_of(lhs, walk),
            // A bare call of a sibling method.
            Expression::FunctionCall { function, .. }
                if walk.own.contains_key(set_name(function))
                    || walk.current.is_some_and(|c| self.member_return(c, function).is_some()) =>
            {
                match walk.own.get(set_name(function)) {
                    Some(ty) => Some(ty.clone()).filter(|t| !t.is_auto()),
                    None => self.member_return(walk.current?, function),
                }
            }
            _ => crate::static_type::of(expr, self.table, walk.current),
        }
    }

    /// The type of field `name` of the struct whose method is walked.
    fn field(&self, name: &str, walk: &Walk) -> Option<TypeName> {
        let info = self.table.lookup(walk.current?)?;
        info.fields.iter().find(|(f, _)| f == name).map(|(_, t)| t.clone())
    }

    /// The type method `method` of a value of type `receiver` returns.
    fn member_return(&self, receiver: &TypeName, method: &str) -> Option<TypeName> {
        let mut ty = self.table.lookup(receiver)?.returns.get(method).cloned()?;
        self.specialize(receiver, &mut ty);
        Some(ty).filter(|t| !t.is_auto())
    }

    /// `ty`, a member type of generic struct `owner`'s base, at `owner`'s
    /// type arguments.
    fn specialize(&self, owner: &TypeName, ty: &mut TypeName) {
        if let Some(params) = self.struct_params.get(&owner.name) {
            let map: Vec<(String, TypeName)> = params.iter().cloned().zip(owner.sub_types.iter().cloned()).collect();
            replace_map(ty, &map);
        }
    }

    /// The constrained parameter a static call names: `T` in `T.make()`,
    /// when no local or field is called `T`.
    fn static_receiver<'w>(&self, this: &Expression, walk: &'w Walk) -> Option<&'w Constrained> {
        let Expression::SymbolRef { id, .. } = this else { return None };
        if self.local(id, walk).is_some() || self.field(id, walk).is_some() {
            return None;
        }
        walk.params.get(id)
    }

    fn expression(&self, expr: &Expression, walk: &mut Walk) {
        match expr {
            Expression::MethodCall { this, method, args, loc } => {
                if let Some(c) = self.static_receiver(this, walk) {
                    let Expression::SymbolRef { id, .. } = this.as_ref() else { unreachable!() };
                    self.call(id, c, method, args, *loc, true, walk);
                } else if let Some(receiver) = self.type_of(this, walk)
                    && let Some((param, c)) = self.constrained(&receiver, walk)
                {
                    let param = param.to_string();
                    self.call(&param, c, method, args, *loc, false, walk);
                }
            }
            Expression::MemberRef { lhs, name, loc } => {
                // A method used as a value (`x.value`) is a member too.
                if let Some(owner) = self.type_of(lhs, walk)
                    && let Some((param, c)) = self.constrained(&owner, walk)
                    && !c.named(name).iter().any(|(_, m)| !m.is_static)
                {
                    let note = c.missing(param, &format!("member '{}'", name));
                    report(Diagnostic::error(format!("no member named '{}' in '{}'", name, param)).at(*loc), note);
                }
            }
            Expression::FunctionCall { function, loc, .. } => {
                if let Some(c) = walk.params.get(function.as_str())
                    && self.local(function, walk).is_none()
                {
                    let note = c.missing(function, "constructor");
                    report(
                        Diagnostic::error(format!(
                            "cannot construct '{}': a constrained type parameter has no constructor",
                            function
                        ))
                        .at(*loc),
                        note,
                    );
                }
            }
            Expression::Binary { op, lhs, rhs, loc } => {
                let lhs_type = self.type_of(lhs, walk);
                let rhs_type = self.type_of(rhs, walk);
                let constrained = |t: &Option<TypeName>| t.as_ref().and_then(|t| self.constrained(t, walk));
                if matches!(op, BinaryOp::Assign) {
                    if let (Some(value), Some(slot)) = (&rhs_type, &lhs_type)
                        && let Some(bad) = self.flows(value, slot, walk)
                    {
                        report(
                            Diagnostic::error(format!(
                                "cannot assign a value of type '{}' to a variable of type '{}'",
                                value.display(),
                                slot.display()
                            ))
                            .at(rhs.loc().known().unwrap_or(*loc)),
                            bad,
                        );
                    }
                } else if !matches!(
                    op,
                    BinaryOp::Equal
                        | BinaryOp::NotEqual
                        | BinaryOp::Identical
                        | BinaryOp::NotIdentical
                        | BinaryOp::LogicalAnd
                        | BinaryOp::LogicalOr
                ) && let Some((param, c)) = constrained(&lhs_type).or_else(|| constrained(&rhs_type))
                {
                    // A compound assignment (`+=`) is its own operator: `+`
                    // does not provide it.
                    let name = op.op_name();
                    let declared = constrained(&lhs_type).is_some() && !c.named(&name).is_empty();
                    if !declared {
                        let note = c.missing(param, &format!("operator '{}'", name));
                        let show = |t: &Option<TypeName>| t.as_ref().map(crate::passes::constraints::spelled).unwrap_or_else(|| "?".to_string());
                        // The node's location runs on over the right operand.
                        let operator = Loc::new(loc.file, pepper_parser::ast::Span { start: loc.span.start, end: loc.span.start + name.len() });
                        report(
                            Diagnostic::error(format!(
                                "invalid operands to binary expression ('{}' and '{}')",
                                show(&lhs_type),
                                show(&rhs_type)
                            ))
                            .at(operator),
                            note,
                        );
                    }
                }
            }
            Expression::Unary { op: op @ (UnaryOp::Neg | UnaryOp::BitNot), operand, loc } => {
                if let Some(t) = self.type_of(operand, walk)
                    && let Some((param, c)) = self.constrained(&t, walk)
                {
                    let name = if matches!(op, UnaryOp::Neg) { "-" } else { "~" };
                    if !c.named(name).iter().any(|(_, m)| m.parameters.is_empty() && !m.is_static) {
                        let note = c.missing(param, &format!("operator '{}'", name));
                        let operator = Loc::new(loc.file, pepper_parser::ast::Span { start: loc.span.start, end: loc.span.start + 1 });
                        report(
                            Diagnostic::error(format!("invalid argument type '{}' to unary expression", param)).at(operator),
                            note,
                        );
                    }
                }
            }
            Expression::Index { lhs, loc, .. } => {
                if let Some(t) = self.type_of(lhs, walk)
                    && let Some((param, c)) = self.constrained(&t, walk)
                    && !c.members.iter().any(|(_, m)| m.is_indexer)
                {
                    let note = c.missing(param, "indexer");
                    report(Diagnostic::error(format!("type '{}' cannot be indexed", param)).at(*loc), note);
                }
            }
            _ => {}
        }
        for child in crate::passes::children(expr) {
            self.expression(child, walk);
        }
    }

    /// A call of `method` on a value of constrained type `param`, or through
    /// it as a static call.
    #[allow(clippy::too_many_arguments)]
    fn call(&self, param: &str, c: &Constrained, method: &str, args: &[Expression], loc: Loc, is_static: bool, walk: &Walk) {
        let base = without_type_arguments(method);
        let named: Vec<&(usize, FunctionDef)> =
            c.named(method).into_iter().filter(|(_, m)| m.is_static == is_static).collect();
        if named.is_empty() {
            let what = if is_static { format!("static member '{}'", base) } else { format!("member '{}'", base) };
            let note = c.missing(param, &what);
            report(Diagnostic::error(format!("no member named '{}' in '{}'", base, param)).at(loc), note);
            return;
        }
        // The same member from two constraints: which one is meant?
        let mut owners: Vec<usize> = named.iter().map(|(b, _)| *b).collect();
        owners.dedup();
        if owners.len() > 1 {
            let (first, second) = (&c.bounds[owners[0]], &c.bounds[owners[1]]);
            report(
                Diagnostic::error(format!(
                    "'{}' is declared by both '{}' and '{}'; call it through one of them",
                    base,
                    first.0.display(),
                    second.0.display()
                ))
                .at(loc),
                (format!("'{}' is constrained here", param), Some(first.1)),
            );
            return;
        }
        let fits: Vec<&FunctionDef> = named
            .iter()
            .map(|(_, m)| m)
            .filter(|m| {
                let required = m.parameters.iter().filter(|p| p.default.is_none()).count();
                args.len() >= required && args.len() <= m.parameters.len()
            })
            .collect();
        let [member] = fits.as_slice() else {
            if fits.is_empty()
                && let [(_, only)] = named.as_slice()
            {
                let (expected, many) = (only.parameters.len(), args.len() > only.parameters.len());
                report(
                    Diagnostic::error(format!(
                        "too {} arguments to '{}': expected {}, have {}",
                        if many { "many" } else { "few" },
                        base,
                        expected,
                        args.len()
                    ))
                    .at(loc),
                    (format!("'{}' declared here", base), Some(only.loc)),
                );
            }
            // Several overloads fit, or none: the specializations decide.
            return;
        };
        let (parameters, _) = member_signature(member, method);
        for (i, (arg, expected)) in args.iter().zip(&parameters).enumerate() {
            // A parameter typed by the member's own unwritten type parameter
            // takes what inference gives it.
            let Some(expected) = expected else { continue };
            let Some(actual) = self.type_of(arg, walk) else { continue };
            if incompatible(&actual, expected, walk) {
                report(
                    Diagnostic::error(format!(
                        "cannot pass a value of type '{}' as argument {} of '{}', which has type '{}'",
                        crate::passes::constraints::spelled(&actual),
                        i + 1,
                        base,
                        crate::passes::constraints::spelled(expected)
                    ))
                    .at(arg.loc().known().unwrap_or_else(|| {
                        self.literal_args.iter().find(|(c, j, _)| *c == loc && *j == i).map_or(loc, |(_, _, at)| *at)
                    })),
                    (format!("'{}' declared here", base), Some(member.loc)),
                );
                return;
            }
        }
    }
}

/// Whether a value of type `actual` clearly cannot be passed as `expected`:
/// both are known, and a struct is passed for a number, or they are
/// different generic parameters, or `actual` is a constrained parameter
/// the slot is not one of its constraints. Conversions the later passes
/// handle (between numbers, `[Implicit]` constructors, struct to trait)
/// are not judged.
fn incompatible(actual: &TypeName, expected: &TypeName, walk: &Walk) -> bool {
    if actual.contains_auto() || expected.contains_auto() || canonical(actual) == canonical(expected) {
        return false;
    }
    let is_param = |t: &TypeName| t.sub_types.is_empty() && walk.params.contains_key(&t.name);
    if is_param(actual) || is_param(expected) {
        let bounds = walk.params.get(&actual.name).map(|c| &c.bounds);
        return !(is_param(actual)
            && bounds.is_some_and(|b| b.iter().any(|(t, _)| canonical(t) == canonical(expected))));
    }
    let number = |t: &TypeName| t.is_integral() || matches!(t.name.as_str(), "f32" | "f64" | "float" | "double" | "bool");
    number(expected) && !number(actual) && !actual.is_pointer() && !expected.is_pointer()
}

/// A method's name without the type arguments a generic method call spells
/// (`map` for `map<long>`); an operator (`<`, `<=`) is its own name.
fn without_type_arguments(name: &str) -> &str {
    match name.find('<') {
        Some(i) if i > 0 => &name[..i],
        _ => name,
    }
}

/// Report `error` with `note`.
fn report(error: Diagnostic, (note, at): (String, Option<Loc>)) {
    crate::errors::report(error.with_note(note, at));
}
