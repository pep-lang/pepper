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

use crate::model::{Diagnostic, Expression, FunctionDef, GenericParam, Module};
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
        bindings
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

/// `name<args>`, the name call sites and specializations use.
pub fn specialization(name: &str, args: Vec<TypeName>) -> String {
    TypeName::with_args(name, args).to_string()
}

/// Report each call to a generic function whose type arguments were neither
/// written nor inferred. Runs after the last type inference; generic bases
/// are skipped (their specializations are checked).
pub fn check_type_arguments(module: &Module) {
    let generics: HashMap<&str, &FunctionDef> =
        module.functions.iter().filter(|f| f.is_generic_func).map(|f| (f.name.as_str(), f)).collect();
    if generics.is_empty() {
        return;
    }
    let report = |expr: &Expression| {
        if let Expression::FunctionCall { function, args, loc } = expr {
            // An argument naming nothing gives no type to infer from;
            // `resolve_resolvables` reports it as undeclared instead.
            let undeclared = args.iter().any(|a| matches!(a, Expression::SymbolRef { ty, .. } if ty.is_empty() || ty.is_auto()));
            if undeclared {
                return;
            }
            if let Some(base) = generics.get(function.as_str()) {
                let params: Vec<&str> = base.generic_params.iter().map(|p| p.name.as_str()).collect();
                crate::errors::report(
                    Diagnostic::error(format!(
                        "cannot infer the type arguments of '{}' from its arguments; write them: {}<{}>(...)",
                        function,
                        function,
                        params.join(", ")
                    ))
                    .at(*loc)
                    .with_note("declared here", Some(base.loc)),
                );
            }
        }
    };
    let visit = |function: &FunctionDef| {
        if let Some(body) = &function.body {
            crate::passes::visit_block(body, &mut |e| report(e));
        }
    };
    for st in module.structs.iter().filter(|s| s.generic_params.is_empty()) {
        for method in st.method_members.iter().chain(st.constructors.iter()) {
            visit(method);
        }
    }
    for function in module.functions.iter().filter(|f| !f.is_generic_func) {
        visit(function);
    }
}
