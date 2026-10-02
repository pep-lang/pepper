//! Inferring a generic function's type arguments from a call's arguments:
//! `larger(3, 9)` is `larger<int>(3, 9)`, and `apply((x) => x + 1, 2)` is
//! `apply<int>(...)`, the closure then taking its parameter type from
//! `apply<int>`'s.
//!
//! Each parameter's declared type is matched against its argument's type,
//! binding the generic parameters it mentions (`Array<T>` against
//! `Array<String>` binds `T = String`; `(T) => U` against a closure of type
//! `(int) => String` binds both). An argument whose type is not known yet (a
//! closure whose return type is still being inferred) binds what it can, and
//! the call is rewritten to its specialization once every parameter is
//! bound, by an argument or a default. `resolve_implicit_types` retries on
//! each run of its fixpoint loop, so closure bodies typed on one run can
//! complete a call on the next.

use crate::model::{Diagnostic, Expression, FunctionDef, GenericParam, Loc, Module};
use crate::type_name::TypeName;
use std::collections::HashMap;

thread_local! {
    /// The traits each struct declares (`extend S with Trait<X>`), by the
    /// struct's spelled type (`ArrayIterator<int>`) and, for a generic base,
    /// by its name with its parameters (`ArrayIterator`, `[T]`), so a
    /// parameter typed `Iterator<U>` can bind `U` from an `ArrayIterator<int>`
    /// argument. Set by [`record_conformances`] at the start of each pass that
    /// infers.
    static CONFORMANCES: std::cell::RefCell<HashMap<String, (Vec<String>, Vec<TypeName>)>> =
        std::cell::RefCell::new(HashMap::new());
}

/// Record the trait conformances of `module`'s structs for inference to see
/// through (see [`CONFORMANCES`]).
pub fn record_conformances(module: &Module) {
    let mut table = HashMap::new();
    for st in module.structs.iter().filter(|st| !st.traits.is_empty()) {
        if st.ty.is_generic() && st.name == st.ty.name {
            let params = st.generic_params.iter().map(|p| p.name.clone()).collect();
            table.insert(st.name.clone(), (params, st.traits.clone()));
        } else {
            table.insert(st.ty.to_string(), (vec![], st.traits.clone()));
        }
    }
    CONFORMANCES.with(|c| *c.borrow_mut() = table);
}

/// The traits `actual` declares, with its type arguments substituted.
fn conformances_of(actual: &TypeName) -> Vec<TypeName> {
    CONFORMANCES.with(|c| {
        let table = c.borrow();
        if let Some((_, traits)) = table.get(&actual.to_string()) {
            return traits.clone();
        }
        let Some((params, traits)) = table.get(&actual.name) else { return vec![] };
        if params.len() != actual.sub_types.len() {
            return vec![];
        }
        let map: Vec<(String, TypeName)> = params.iter().cloned().zip(actual.sub_types.iter().cloned()).collect();
        traits
            .iter()
            .map(|t| {
                let mut t = t.clone();
                crate::type_name::replace_map(&mut t, &map);
                t
            })
            .collect()
    })
}

/// A generic function's declaration, as the inference needs it.
#[derive(Clone, Debug)]
pub struct GenericSignature {
    pub params: Vec<GenericParam>,
    pub parameter_types: Vec<TypeName>,
    /// How many of the parameters (from the front) have no default value.
    pub required: usize,
}

impl GenericSignature {
    pub fn of(function: &crate::model::FunctionDef) -> Self {
        GenericSignature {
            params: function.generic_params.clone(),
            parameter_types: function.parameters.iter().map(|p| p.ty.clone()).collect(),
            required: function.parameters.iter().filter(|p| p.default.is_none()).count(),
        }
    }

    fn is_param(&self, name: &str) -> bool {
        self.params.iter().any(|p| p.name == name)
    }

    /// The bindings `arguments` (their types, where known) give, without
    /// defaults.
    pub fn bind(&self, arguments: &[Option<TypeName>]) -> HashMap<String, TypeName> {
        let mut bindings = HashMap::new();
        for (pattern, actual) in self.parameter_types.iter().zip(arguments) {
            if let Some(actual) = actual {
                self.unify(pattern, actual, &mut bindings);
            }
        }
        self.bind_through_bounds(&mut bindings);
        bindings
    }

    /// Bind the parameters a bound names from the bound parameter's type
    /// argument: in `<T, I: Iterator<T>>`, `I = ArrayIterator<int>` declares
    /// `Iterator<int>`, so `T = int`. Repeats until nothing new binds, since
    /// one bound can bind the parameter another bound needs.
    fn bind_through_bounds(&self, bindings: &mut HashMap<String, TypeName>) {
        loop {
            let before = bindings.len();
            for param in &self.params {
                let Some(actual) = bindings.get(&param.name).cloned() else { continue };
                for bound in &param.bounds {
                    self.unify(&bound.ty, &actual, bindings);
                }
            }
            if bindings.len() == before {
                break;
            }
        }
    }

    /// The type arguments for a call with `arguments`, when every generic
    /// parameter is bound (by an argument or its default).
    pub fn infer(&self, arguments: &[Option<TypeName>]) -> Option<Vec<TypeName>> {
        if arguments.len() < self.required || arguments.len() > self.parameter_types.len() {
            return None;
        }
        let bindings = self.bind(arguments);
        self.params
            .iter()
            .map(|p| bindings.get(&p.name).cloned().or_else(|| p.default.clone()))
            .collect()
    }

    /// The type arguments for a call that writes only the leading ones
    /// (`count_all<int>(it)` for `count_all<T, I>`): the written ones, then
    /// each missing one from its default, else from the arguments. `None`
    /// when every one is written, or one stays unbound.
    pub fn complete(&self, written: &[TypeName], arguments: &[Option<TypeName>]) -> Option<Vec<TypeName>> {
        if written.len() >= self.params.len() || self.params[written.len()..].iter().all(|p| p.default.is_some()) {
            return None;
        }
        if arguments.len() < self.required || arguments.len() > self.parameter_types.len() {
            return None;
        }
        let mut bindings: HashMap<String, TypeName> =
            self.params.iter().map(|p| p.name.clone()).zip(written.iter().cloned()).collect();
        for p in &self.params[written.len()..] {
            if let Some(default) = &p.default {
                bindings.insert(p.name.clone(), default.clone());
            }
        }
        for (pattern, actual) in self.parameter_types.iter().zip(arguments) {
            if let Some(actual) = actual {
                self.unify(pattern, actual, &mut bindings);
            }
        }
        self.bind_through_bounds(&mut bindings);
        self.params.iter().map(|p| bindings.get(&p.name).cloned()).collect()
    }

    /// The type arguments that make the function, whose declared return
    /// type is `ret`, a value of function type `expected`: each parameter
    /// type matched against the expected one, and the return type against
    /// the expected return type. `None` when the counts differ or a generic
    /// parameter stays unbound (with no default).
    pub fn infer_from_function_type(&self, ret: &TypeName, expected: &TypeName) -> Option<Vec<TypeName>> {
        let params = expected.function_params();
        if params.len() != self.parameter_types.len() {
            return None;
        }
        let mut bindings = HashMap::new();
        for (pattern, actual) in self.parameter_types.iter().zip(params) {
            self.unify(pattern, actual, &mut bindings);
        }
        if let Some(expected_ret) = expected.function_return() {
            self.unify(ret, expected_ret, &mut bindings);
        }
        self.bind_through_bounds(&mut bindings);
        self.params.iter().map(|p| bindings.get(&p.name).cloned().or_else(|| p.default.clone())).collect()
    }

    /// Parameter `index`'s type with the known bindings substituted and every
    /// unbound generic parameter left unknown (`auto`), for a closure
    /// argument to take its types from.
    pub fn expected(&self, index: usize, bindings: &HashMap<String, TypeName>) -> Option<TypeName> {
        let mut ty = self.parameter_types.get(index)?.clone();
        for param in &self.params {
            let with = bindings.get(&param.name).cloned().unwrap_or_else(TypeName::auto);
            ty.replace(&param.name, &with);
        }
        Some(ty)
    }

    fn unify(&self, pattern: &TypeName, actual: &TypeName, bindings: &mut HashMap<String, TypeName>) {
        if actual.is_auto() {
            return;
        }
        if pattern.sub_types.is_empty() && self.is_param(&pattern.name) {
            if !actual.contains_auto() {
                bindings.entry(pattern.name.clone()).or_insert_with(|| actual.clone());
            }
            return;
        }
        if pattern.name == actual.name && pattern.sub_types.len() == actual.sub_types.len() {
            for (p, a) in pattern.sub_types.iter().zip(&actual.sub_types) {
                self.unify(p, a, bindings);
            }
            return;
        }
        // A trait parameter (`other: Iterator<U>`) takes its arguments from
        // the trait the argument's struct declares (`ArrayIterator<int>` is an
        // `Iterator<int>`), as the conversion to the trait value will.
        if !pattern.sub_types.is_empty() {
            for conformance in conformances_of(actual) {
                if conformance.name == pattern.name && conformance.sub_types.len() == pattern.sub_types.len() {
                    for (p, a) in pattern.sub_types.iter().zip(&conformance.sub_types) {
                        self.unify(p, a, bindings);
                    }
                    return;
                }
            }
        }
    }
}

/// Name each generic function written without type arguments where a
/// function type is expected (`var f: (int, int) => int = larger;`) by
/// the specialization that type picks: a `FunctionRef` to `larger<int>`,
/// which `gather_generics` then specializes. Runs in
/// `resolve_implicit_types`' loop; returns whether it named any. Generic
/// code is left to its specializations, where the expected type is
/// concrete.
pub fn bind_generic_function_values(module: &mut Module) -> bool {
    let generics: HashMap<String, (GenericSignature, TypeName)> = module
        .functions
        .iter()
        .filter(|f| f.is_generic_func && !f.name.contains('<'))
        .map(|f| (f.name.clone(), (GenericSignature::of(f), f.ty.clone())))
        .collect();
    if generics.is_empty() {
        return false;
    }
    let unbound = |e: &Expression| matches!(e, Expression::SymbolRef { id, ty, .. } if (ty.is_empty() || ty.is_auto()) && generics.contains_key(id));
    let mut candidate = false;
    crate::passes::closures::for_each_expression_mut(module, &mut |e| candidate |= unbound(e));
    if !candidate {
        return false;
    }
    let generic_bases: std::collections::HashSet<&str> = module
        .functions
        .iter()
        .filter(|f| f.is_generic_func)
        .map(|f| f.name.as_str())
        .chain(module.structs.iter().filter(|s| !s.generic_params.is_empty() && s.name == s.ty.name).map(|s| s.name.as_str()))
        .collect();
    let shadowed = shadowed_names(module, &generics);
    let mut bound: HashMap<(String, Loc), (String, TypeName)> = HashMap::new();
    crate::passes::closures::for_each_applied_site_in(module, &mut |owner, expr, expected, _| {
        if owner.is_some_and(|o| generic_bases.contains(o)) || !unbound(expr) {
            return;
        }
        let Expression::SymbolRef { id, loc, .. } = expr else { return };
        if shadowed.contains(&(id.clone(), *loc)) {
            return;
        }
        let Some(expected) = expected.filter(|t| t.is_callable() && !t.contains_auto()) else { return };
        let (signature, ret) = &generics[id];
        let Some(args) = signature.infer_from_function_type(ret, expected) else { return };
        let mut ty = TypeName::function_type(ret.clone(), signature.parameter_types.clone());
        for (param, arg) in signature.params.iter().zip(&args) {
            ty.replace(&param.name, arg);
        }
        if ty.contains_auto() {
            return;
        }
        bound.insert((id.clone(), *loc), (specialization(id, args), ty));
    });
    if bound.is_empty() {
        return false;
    }
    crate::passes::closures::for_each_expression_mut(module, &mut |e| {
        if let Expression::SymbolRef { id, loc, .. } = e {
            if let Some((function, ty)) = bound.get(&(id.clone(), *loc)) {
                let loc = *loc;
                *e = Expression::FunctionRef { function: function.clone(), ty: ty.clone(), loc };
            }
        }
    });
    true
}

/// The uses of `generics`' names that a parameter, a local or a field of
/// the enclosing struct (a closure's capture) of the same name hides, by
/// name and location. Their types may still be unknown when
/// [`bind_generic_function_values`] runs.
fn shadowed_names<T>(module: &Module, generics: &HashMap<String, T>) -> std::collections::HashSet<(String, Loc)> {
    fn declared(block: &crate::model::Block, names: &mut Vec<String>) {
        use crate::model::{Declaration, Statement};
        for stmt in &block.items {
            match stmt {
                Statement::Declaration(Declaration::Variable(var)) => names.push(var.name.clone()),
                Statement::Block(b) => declared(b, names),
                Statement::Branch(b) => {
                    declared(&b.if_block, names);
                    if let Some(e) = &b.else_block {
                        declared(e, names);
                    }
                }
                Statement::While(w) => declared(&w.block, names),
                _ => {}
            }
        }
    }
    let mut shadowed = std::collections::HashSet::new();
    let mut visit = |function: &FunctionDef, fields: &[String]| {
        let Some(body) = &function.body else { return };
        let mut names: Vec<String> = function.parameters.iter().map(|p| p.name.clone()).chain(fields.iter().cloned()).collect();
        declared(body, &mut names);
        names.retain(|n| generics.contains_key(n));
        if names.is_empty() {
            return;
        }
        crate::passes::visit_block(body, &mut |e| {
            if let Expression::SymbolRef { id, loc, .. } = e {
                if names.contains(id) {
                    shadowed.insert((id.clone(), *loc));
                }
            }
        });
    };
    for function in &module.functions {
        visit(function, &[]);
    }
    for st in &module.structs {
        let fields: Vec<String> = st.field_members.iter().map(|f| f.name.clone()).collect();
        for method in st.method_members.iter().chain(&st.constructors).chain([&st.destructor]) {
            visit(method, &fields);
        }
    }
    shadowed
}

/// `name<args>`, the name call sites and specializations use.
pub fn specialization(name: &str, args: Vec<TypeName>) -> String {
    TypeName::with_args(name, args).to_string()
}

/// Report each call to a generic function or method whose type arguments
/// were neither written nor inferred. Runs after the last type inference;
/// generic bases are skipped (their specializations are checked).
pub fn check_type_arguments(module: &Module) {
    let generics: HashMap<&str, &FunctionDef> =
        module.functions.iter().filter(|f| f.is_generic_func).map(|f| (f.name.as_str(), f)).collect();
    let has_methods = module.structs.iter().any(|s| !s.generic_methods.is_empty());
    if generics.is_empty() && !has_methods {
        return;
    }
    // Built on the first method call that may name a generic method.
    let statics = std::cell::OnceCell::new();
    // An operator (`<`) is never a generic callee.
    let named = |callee: &str| callee.starts_with(|c: char| c.is_alphabetic() || c == '_');
    let report = |expr: &Expression, current: Option<&TypeName>| {
        let (callee, args, loc, base) = match expr {
            // A generic function named as a value where no function type
            // picked its specialization (`bind_generic_function_values`).
            Expression::SymbolRef { id, ty, loc } if ty.is_empty() || ty.is_auto() => {
                let Some(base) = generics.get(id.as_str()) else { return };
                let all = base.generic_params.iter().map(|p| p.name.as_str()).collect::<Vec<_>>().join(", ");
                crate::errors::report(
                    Diagnostic::error(format!(
                        "cannot infer the type arguments of '{}' used as a value; write them ({}<{}>) or give the value a function type",
                        id, id, all
                    ))
                    .at(*loc)
                    .with_note("declared here", Some(base.loc)),
                );
                return;
            }
            Expression::FunctionCall { function, args, loc } if named(function) => {
                let name = crate::passes::gather_generics::parse_type_string(function).name;
                let Some(base) = generics.get(name.as_str()) else { return };
                (function, args, loc, *base)
            }
            Expression::MethodCall { this, method, args, loc } if has_methods && named(method) => {
                let name = crate::passes::gather_generics::parse_type_string(method).name;
                if !module.structs.iter().any(|s| s.generic_methods.iter().any(|m| m.name == name)) {
                    return;
                }
                let statics = statics.get_or_init(|| crate::static_type::StructTable::build(module));
                let Some(owner) = crate::static_type::of(this, statics, current) else { return };
                let key = owner.to_string();
                let Some(st) = module.structs.iter().find(|s| s.ty.is_spelled(key.trim_end_matches('*'))) else { return };
                // A specialization the call already names is complete.
                if st.method_members.iter().any(|m| m.name == *method) {
                    return;
                }
                let Some(base) = st.generic_methods.iter().find(|m| m.name == name) else { return };
                (method, args, loc, base)
            }
            // A generic method as a value that no function type specialized
            // (`generic_methods::bind_generic_method_values`).
            Expression::MemberRef { lhs, name, loc } if has_methods && !name.contains('<') => {
                if !module.structs.iter().any(|s| s.generic_methods.iter().any(|m| m.name == *name)) {
                    return;
                }
                let statics = statics.get_or_init(|| crate::static_type::StructTable::build(module));
                let Some(owner) = crate::static_type::of(lhs, statics, current) else { return };
                let key = owner.to_string();
                let Some(st) = module.structs.iter().find(|s| s.ty.is_spelled(key.trim_end_matches('*'))) else { return };
                if st.method_members.iter().any(|m| m.name == *name) || st.field_members.iter().any(|f| f.name == *name) {
                    return;
                }
                let Some(base) = st.generic_methods.iter().find(|m| m.name == *name) else { return };
                let all = base.generic_params.iter().map(|p| p.name.as_str()).collect::<Vec<_>>().join(", ");
                crate::errors::report(
                    Diagnostic::error(format!(
                        "cannot infer the type arguments of method '{}' of '{}' used as a value; write them ({}<{}>) or give the value a function type",
                        name,
                        owner.display(),
                        name,
                        all
                    ))
                    .at(*loc)
                    .with_note("declared here", Some(base.loc)),
                );
                return;
            }
            _ => return,
        };
        // An argument naming nothing gives no type to infer from;
        // `resolve_resolvables` reports it as undeclared instead.
        let undeclared = args.iter().any(|a| matches!(a, Expression::SymbolRef { ty, .. } if ty.is_empty() || ty.is_auto()));
        if undeclared {
            return;
        }
        let written = crate::passes::gather_generics::parse_type_string(callee);
        let all = base.generic_params.iter().map(|p| p.name.as_str()).collect::<Vec<_>>().join(", ");
        let message = if written.sub_types.is_empty() {
            format!(
                "cannot infer the type arguments of '{}' from its arguments; write them: {}<{}>(...)",
                written.name, written.name, all
            )
        } else {
            // `count_all<int>(it)` for `count_all<T, I>` whose arguments did
            // not give the rest.
            let Some(unbound) = base.generic_params.get(written.sub_types.len()..).and_then(|m| m.iter().find(|p| p.default.is_none()))
            else {
                return;
            };
            format!(
                "cannot infer the type argument '{}' of '{}' from its arguments; write it: {}<{}>(...)",
                unbound.name, written.name, written.name, all
            )
        };
        crate::errors::report(Diagnostic::error(message).at(*loc).with_note("declared here", Some(base.loc)));
    };
    for st in module.structs.iter().filter(|s| s.generic_params.is_empty()) {
        let current = Some(&st.ty);
        for method in st.method_members.iter().chain(st.constructors.iter()) {
            if let Some(body) = &method.body {
                crate::passes::visit_block(body, &mut |e| report(e, current));
            }
        }
    }
    for function in module.functions.iter().filter(|f| !f.is_generic_func) {
        if let Some(body) = &function.body {
            crate::passes::visit_block(body, &mut |e| report(e, None));
        }
    }
}
