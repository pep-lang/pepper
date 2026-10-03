//! Value structs (`[Value]`, design: `value-structs-proposal.md`): a struct
//! stored inline in whatever holds it (a local, a field, an array element)
//! and copied like a tuple. It has no heap object, no counts and no
//! identity; its reference fields are still counted, so copying one
//! acquires them and dropping one releases them.
//!
//! Sema gives a value struct no count fields and no `__acquire`/`__release`
//! bodies (`struct_body`), and its constructors build `this` in place
//! rather than allocating it. Codegen lays it out without a header, passes
//! and stores it by value, and passes the address of the receiver's storage
//! as `this`.

use crate::checked::BodyOf;
use crate::model::*;
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;
use pepper_parser::diagnostic::Diagnostic;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};

thread_local! {
    /// The generic base names (`Span`, `Optional`) of the value structs, for
    /// this run.
    static VALUES: RefCell<HashSet<String>> = RefCell::new(HashSet::new());
    /// Each value struct's name with every omitted type argument filled in
    /// from its default (`Result<int>` → `Result<int, Error>`), for the
    /// names that differ.
    static CANONICAL: RefCell<HashMap<String, String>> = RefCell::new(HashMap::new());
}

/// Make `module`'s value structs the ones [`is_value`] knows, replacing
/// any earlier run's.
pub fn install(module: &Module) {
    VALUES.with(|v| {
        let mut v = v.borrow_mut();
        v.clear();
        v.extend(module.structs.iter().filter(|st| st.is_value()).map(|st| st.ty.name.clone()));
    });
    let params = defaulted_params(module);
    let canonical = module
        .structs
        .iter()
        .filter(|st| st.is_value() && !is_generic_base(st))
        .filter_map(|st| {
            let mut ty = st.ty.clone();
            fill_defaults(&mut ty, &params);
            let name = ty.to_string();
            (name != st.name).then(|| (st.name.clone(), name))
        })
        .collect();
    CANONICAL.with(|c| *c.borrow_mut() = canonical);
}

/// The name that every spelling of value struct `name` shares, so
/// `Result<int>`, `Result<int, Error>` and `Result<__ptr<int>>` /
/// `Result<int*>` get one layout in codegen.
pub fn canonical(name: &str) -> String {
    CANONICAL.with(|c| c.borrow().get(name).cloned()).unwrap_or_else(|| name.to_string())
}

/// Each generic struct with a defaulted parameter, by base name: what
/// [`fill_defaults`] reads.
pub(crate) fn defaulted_params(module: &Module) -> HashMap<&str, &[GenericParam]> {
    module
        .structs
        .iter()
        .filter(|st| st.generic_params.iter().any(|p| p.default.is_some()))
        .map(|st| (st.ty.name.as_str(), st.generic_params.as_slice()))
        .collect()
}

/// Spell `ty` one way: every omitted type argument filled in from the
/// generic parameter's default, and `__ptr<T>` as `T*`. Type names nest
/// only as deep as the program spells them, so this recursion is bounded by
/// the source.
pub(crate) fn fill_defaults(ty: &mut TypeName, params: &HashMap<&str, &[GenericParam]>) {
    for arg in &mut ty.sub_types {
        fill_defaults(arg, params);
    }
    if ty.name == "__ptr" && ty.sub_types.len() == 1 {
        *ty = TypeName::new(&format!("{}*", ty.sub_types[0]));
        return;
    }
    let Some(generic) = params.get(ty.name.as_str()) else { return };
    let mut map: Vec<(String, TypeName)> =
        generic.iter().zip(&ty.sub_types).map(|(p, a)| (p.name.clone(), a.clone())).collect();
    for p in generic.iter().skip(ty.sub_types.len()) {
        let Some(default) = &p.default else { return };
        let mut arg = default.clone();
        crate::type_name::replace_map(&mut arg, &map);
        fill_defaults(&mut arg, params);
        map.push((p.name.clone(), arg.clone()));
        ty.sub_types.push(arg);
    }
}

/// Whether the type named `name` (`Span`, `Optional<int>`) is a value
/// struct. A pointer to one (`Optional<int>*`) is not.
pub fn is_value(name: &str) -> bool {
    if name.ends_with('*') {
        return false;
    }
    let base = name.split('<').next().unwrap_or(name);
    VALUES.with(|v| v.borrow().contains(base))
}

/// Check how the program uses its value structs, once every type is final:
/// what needs an object (identity, `__null`, `__weak`, `__refcount`, C), a value that contains itself, and changes that would
/// land in a copy and be lost (a field of a temporary, a mutating method
/// called on one) or that a `const` forbids.
pub fn check(module: &mut Module) {
    install(module);
    if VALUES.with(|v| v.borrow().is_empty()) {
        return;
    }
    check_recursion(module);
    check_types(module);
    let table = StructTable::build(module);
    let mutating = mutating_methods(module, &table);
    let globals: Vec<Binding> = module.globals.iter().map(|v| (v.name.clone(), v.is_const.then_some(v.loc))).collect();
    // Only bodies are walked (a checked runtime's are stashed).
    for st in module.structs.iter().filter(|st| !is_generic_base(st)) {
        if st.constructors.iter().chain(&st.method_members).all(|f| f.body.is_none()) {
            continue;
        }
        let fields: HashSet<String> = st.field_members.iter().map(|f| f.name.clone()).collect();
        for function in st.constructors.iter().chain(&st.method_members).filter(|f| f.body.is_some()) {
            let mut uses = Uses::new(&table, Some(&st.ty), fields.clone(), &globals, function);
            uses.function(function, &mut |found| found.report(&mutating));
        }
    }
    for function in module.functions.iter().filter(|f| f.body.is_some()) {
        let mut uses = Uses::new(&table, None, HashSet::new(), &globals, function);
        uses.function(function, &mut |found| found.report(&mutating));
    }
}

/// A generic struct's unspecialized declaration: its specializations are
/// checked instead.
fn is_generic_base(st: &StructDef) -> bool {
    st.ty.is_generic() && st.name == st.ty.name
}

/// A value struct stored in itself would be infinitely large. Follows
/// fields of value struct type with an explicit stack, since a chain can
/// be as long as the program makes it.
fn check_recursion(module: &Module) {
    let by_name: HashMap<String, &StructDef> = module
        .structs
        .iter()
        .filter(|st| st.is_value() && !is_generic_base(st))
        .map(|st| (st.ty.to_string(), st))
        .collect();
    // In declaration order, so the first one reported is stable.
    for st in module.structs.iter().filter(|st| st.is_value() && !is_generic_base(st)) {
        let name = &st.ty.to_string();
        // Each entry: the struct reached, and the chain of fields that led
        // to it.
        let mut stack: Vec<(&StructDef, Vec<&VariableDef>)> = vec![(st, vec![])];
        let mut seen: HashSet<String> = HashSet::new();
        while let Some((at, chain)) = stack.pop() {
            for field in &at.field_members {
                let field_type = field.ty.to_string();
                let Some(next) = by_name.get(&field_type) else { continue };
                let mut path = chain.clone();
                path.push(field);
                if field_type == **name {
                    report_recursion(st, &path);
                    return;
                }
                if seen.insert(field_type) {
                    stack.push((next, path));
                }
            }
        }
    }
}

fn report_recursion(st: &StructDef, path: &[&VariableDef]) {
    let first = path[0];
    let mut diagnostic = Diagnostic::error(format!(
        "value struct '{}' contains itself through field '{}'",
        st.ty.display(),
        first.name
    ))
    .at(type_loc(first));
    for field in &path[1..] {
        diagnostic = diagnostic.with_note(
            format!("which holds field '{}' of type '{}'", field.name, field.ty.display()),
            Some(type_loc(field)),
        );
    }
    crate::errors::report(diagnostic);
}

/// Where `var`'s type is written, else its name.
fn type_loc(var: &VariableDef) -> Loc {
    if var.type_loc.is_none() {
        var.loc
    } else {
        var.type_loc
    }
}

/// `__weak<V>` anywhere a type is written, and a value struct in an
/// `extern` signature.
fn check_types(module: &Module) {
    // Synthesized declarations (a specialization's hidden parameters) have
    // no location; the source that asked for them is reported instead.
    let weak = |var: &VariableDef| {
        if let Some(value) = weak_of_value(&var.ty).filter(|_| !type_loc(var).is_none()) {
            crate::errors::report(weak_error(&value).at(type_loc(var)));
        }
    };
    for st in module.structs.iter().filter(|st| !is_generic_base(st)) {
        st.field_members.iter().for_each(weak);
        for function in st.constructors.iter().chain(&st.method_members) {
            function.parameters.iter().for_each(weak);
        }
    }
    module.functions.iter().flat_map(|f| &f.parameters).for_each(weak);
    module.globals.iter().for_each(weak);
    for ext in &module.externs {
        for param in &ext.parameters {
            if is_value(&param.ty.to_string()) {
                crate::errors::report(extern_error(&param.ty).at(type_loc(param)));
            }
        }
        if is_value(&ext.ty.to_string()) {
            crate::errors::report(extern_error(&ext.ty).at(ext.loc));
        }
    }
}

fn extern_error(ty: &TypeName) -> Diagnostic {
    Diagnostic::error(format!("value struct '{}' cannot be passed to C; pass a pointer", ty.display()))
}

fn weak_error(value: &TypeName) -> Diagnostic {
    Diagnostic::error(format!("'__weak' needs a reference type; '{}' is a value struct", value.display()))
}

/// The value struct `ty` holds weakly (`Span` in `Array<__weak<Span>>`).
fn weak_of_value(ty: &TypeName) -> Option<TypeName> {
    let mut stack = vec![ty];
    while let Some(ty) = stack.pop() {
        if ty.name == "__weak" {
            if let Some(inner) = ty.sub_types.first().filter(|t| is_value(&t.to_string())) {
                return Some(inner.clone());
            }
        }
        stack.extend(&ty.sub_types);
    }
    None
}

/// A visible binding: its name, and where it was declared `const` if it was.
type Binding = (String, Option<Loc>);

/// The storage an expression of value struct type lives in, which a change
/// through it changes.
enum Root {
    /// The method's receiver.
    This,
    /// A local, parameter or module-scope variable; the location is that of
    /// its `const` declaration when it is const.
    Variable(String, Option<Loc>),
    /// A copy: the result of the call named, at the location, which nothing
    /// keeps.
    Temporary(String, Loc),
    /// Memory behind a reference or a pointer, which keeps the change.
    Place,
    /// A closure's copy of the receiver of the method that made it.
    ClosureThis,
}

/// A change to a value: an assignment to one of its fields, or a call of
/// one of its mutating methods.
struct Change<'a> {
    root: Root,
    /// The value struct changed.
    ty: TypeName,
    /// The field assigned, or the method called.
    member: &'a str,
    method: bool,
    at: Loc,
}

/// What a walk over a function finds: a change to a value, or a use that
/// needs an object.
enum Found<'a> {
    Change(Change<'a>),
    Error(Diagnostic),
}

impl Found<'_> {
    fn report(self, mutating: &HashMap<(String, String), Loc>) {
        match self {
            Found::Error(diagnostic) => crate::errors::report(diagnostic),
            Found::Change(change) => {
                let first_change = if change.method {
                    match mutating_at(mutating, &change.ty, change.member) {
                        Some(loc) => Some(loc),
                        None => return,
                    }
                } else {
                    None
                };
                let what = if change.method {
                    format!("call mutating method '{}'", crate::passes::overloads::set_name(change.member))
                } else {
                    format!("assign to field '{}'", change.member)
                };
                let diagnostic = match &change.root {
                    Root::Temporary(source, made) => Diagnostic::error(format!(
                        "cannot {} {} a temporary '{}'",
                        what,
                        if change.method { "on" } else { "of" },
                        change.ty.display()
                    ))
                    .at(change.at)
                    .with_note(
                        format!("'{}' returns a copy; store it in a variable, change it, and assign it back", source),
                        Some(*made),
                    ),
                    Root::ClosureThis => Diagnostic::error(format!(
                        "cannot change 'this' in a closure: the closure holds a copy of '{}'",
                        change.ty.display()
                    ))
                    .at(change.at),
                    Root::Variable(name, Some(declared)) => Diagnostic::error(format!(
                        "cannot {} {} const variable '{}'",
                        what,
                        if change.method { "on" } else { "of" },
                        name
                    ))
                    .at(change.at)
                    .with_note(format!("'{}' declared const here", name), Some(*declared)),
                    _ => return,
                };
                let diagnostic = match first_change {
                    Some(loc) => diagnostic.with_note(
                        format!("'{}' changes 'this' here", crate::passes::overloads::set_name(change.member)),
                        Some(loc),
                    ),
                    None => diagnostic,
                };
                crate::errors::report(diagnostic);
            }
        }
    }
}

/// Where method `method` of value struct `ty` first changes `this`, if it
/// does. A call still named by its overload set (`grow`) is mutating when
/// any member of the set is.
fn mutating_at(mutating: &HashMap<(String, String), Loc>, ty: &TypeName, method: &str) -> Option<Loc> {
    let ty = ty.to_string();
    if let Some(loc) = mutating.get(&(ty.clone(), method.to_string())) {
        return Some(*loc);
    }
    mutating
        .iter()
        .find(|((t, m), _)| *t == ty && crate::passes::overloads::set_name(m) == method)
        .map(|(_, loc)| *loc)
}

/// The methods of value structs that change `this`, by (struct, method),
/// with where each first does: one that assigns to a field of `this` (or of
/// a value field of it), or calls a mutating method on `this` or a value
/// field. A fixpoint, since one method can make another mutating.
fn mutating_methods(module: &Module, table: &StructTable) -> HashMap<(String, String), Loc> {
    let mut mutating: HashMap<(String, String), Loc> = HashMap::new();
    let globals: Vec<Binding> = vec![];
    loop {
        let before = mutating.len();
        for st in module.structs.iter().filter(|st| st.is_value() && !is_generic_base(st)) {
            let fields: HashSet<String> = st.field_members.iter().map(|f| f.name.clone()).collect();
            for method in st.method_members.iter().filter(|m| !m.is_static) {
                let key = (st.ty.to_string(), method.name.clone());
                if mutating.contains_key(&key) {
                    continue;
                }
                // A checked runtime struct's bodies are stashed while the
                // passes run; its methods change `this` all the same.
                let stashed = module.stashed_bodies.get(&BodyOf::Member(st.name.clone(), "method", method.name.clone()));
                let Some(body) = method.body.as_ref().or(stashed) else { continue };
                let mut first: Option<Loc> = None;
                let mut uses = Uses::new(table, Some(&st.ty), fields.clone(), &globals, method);
                uses.block(body, &mut |found| {
                    let Found::Change(change) = found else { return };
                    if !matches!(change.root, Root::This) || first.is_some() {
                        return;
                    }
                    if !change.method || mutating_at(&mutating, &change.ty, change.member).is_some() {
                        first = Some(change.at);
                    }
                });
                if let Some(loc) = first {
                    mutating.insert(key, loc);
                }
            }
        }
        if mutating.len() == before {
            return mutating;
        }
    }
}

/// A walk over one function's body that tracks the bindings in scope and
/// reports what it finds about value structs.
struct Uses<'a> {
    table: &'a StructTable,
    current: Option<&'a TypeName>,
    /// The enclosing struct's fields: a bare name that is not a local is one.
    fields: HashSet<String>,
    /// Innermost last; index 0 holds the module-scope variables.
    scopes: Vec<Vec<Binding>>,
}

impl<'a> Uses<'a> {
    fn new(
        table: &'a StructTable,
        current: Option<&'a TypeName>,
        fields: HashSet<String>,
        globals: &[Binding],
        function: &FunctionDef,
    ) -> Self {
        let parameters = function.parameters.iter().map(|p| (p.name.clone(), None)).collect();
        Uses { table, current, fields, scopes: vec![globals.to_vec(), parameters] }
    }

    fn function<'e>(&mut self, function: &'e FunctionDef, found: &mut impl FnMut(Found<'e>)) {
        if let Some(body) = &function.body {
            self.block(body, found);
        }
    }

    fn block<'e>(&mut self, block: &'e Block, found: &mut impl FnMut(Found<'e>)) {
        self.scopes.push(vec![]);
        // An explicit stack of statements still to visit, so nesting depth
        // is not bounded by Rust's stack; `None` closes a scope.
        let mut stack: Vec<Option<&'e Statement>> = block.items.iter().rev().map(Some).collect();
        while let Some(item) = stack.pop() {
            let Some(statement) = item else {
                self.scopes.pop();
                continue;
            };
            let open = |stack: &mut Vec<Option<&'e Statement>>, scopes: &mut Vec<Vec<Binding>>, block: &'e Block| {
                scopes.push(vec![]);
                stack.push(None);
                stack.extend(block.items.iter().rev().map(Some));
            };
            match statement {
                Statement::Expression(expr) => self.expression(expr, found),
                Statement::Block(inner) => open(&mut stack, &mut self.scopes, inner),
                Statement::Declaration(Declaration::Variable(var)) => {
                    if let Some(default) = &var.default {
                        self.expression(default, found);
                        if matches!(default, Expression::PointerLiteral) && is_value(&var.ty.to_string()) {
                            found(Found::Error(null_error(&var.ty).at(var.loc)));
                        }
                    }
                    if let Some(value) = weak_of_value(&var.ty).filter(|_| !type_loc(var).is_none()) {
                        found(Found::Error(weak_error(&value).at(type_loc(var))));
                    }
                    self.scopes.last_mut().expect("scope").push((var.name.clone(), var.is_const.then_some(var.loc)));
                }
                Statement::Declaration(_) | Statement::LoopBreak(_) | Statement::Static(_) | Statement::StaticPass(_) => {}
                Statement::Branch(branch) => {
                    self.expression(&branch.condition, found);
                    if let Some(else_block) = &branch.else_block {
                        open(&mut stack, &mut self.scopes, else_block);
                    }
                    open(&mut stack, &mut self.scopes, &branch.if_block);
                }
                Statement::While(w) => {
                    self.expression(&w.condition, found);
                    open(&mut stack, &mut self.scopes, &w.block);
                }
                Statement::Return(ret) => {
                    if let Some(expr) = &ret.expr {
                        self.expression(expr, found);
                    }
                }
            }
        }
        self.scopes.pop();
    }

    fn binding(&self, name: &str) -> Option<&Binding> {
        self.scopes[1..]
            .iter()
            .rev()
            .find_map(|scope| scope.iter().rev().find(|(n, _)| n == name))
    }

    fn type_of(&self, expr: &Expression) -> Option<TypeName> {
        static_type::of(expr, self.table, self.current).or_else(|| {
            let Expression::SymbolRef { id, .. } = expr else { return None };
            let info = self.table.lookup(self.current?)?;
            info.fields.iter().find(|(f, _)| f == id).map(|(_, ty)| ty.clone())
        })
    }

    /// The value struct type of `expr`, if it has one.
    fn value_type(&self, expr: &Expression) -> Option<TypeName> {
        self.type_of(expr).filter(|ty| is_value(&ty.to_string()))
    }

    /// The storage that `expr`, a value, lives in.
    fn root(&self, expr: &Expression) -> Root {
        let mut expr = expr;
        loop {
            match expr {
                Expression::ThisRef => return Root::This,
                Expression::SymbolRef { id, .. } => {
                    if let Some((_, declared)) = self.binding(id) {
                        return Root::Variable(id.clone(), *declared);
                    }
                    if id == crate::passes::closures::THIS_FIELD && self.fields.contains(id) {
                        return Root::ClosureThis;
                    }
                    if self.fields.contains(id) {
                        return Root::This;
                    }
                    let global = self.scopes[0].iter().find(|(n, _)| n == id);
                    return match global {
                        Some((_, declared)) => Root::Variable(id.clone(), *declared),
                        None => Root::Place,
                    };
                }
                Expression::MemberRef { lhs, name, .. }
                    if name == crate::passes::closures::THIS_FIELD && matches!(**lhs, Expression::ThisRef) =>
                {
                    return Root::ClosureThis
                }
                // A field of a value lives in that value; a field of an
                // object lives in the object.
                Expression::MemberRef { lhs, .. } if self.value_type(lhs).is_some() => expr = lhs,
                Expression::MemberRef { .. } | Expression::Index { .. } | Expression::ArrayIndex { .. } => {
                    return Root::Place
                }
                Expression::MethodCall { method, loc, .. } => return Root::Temporary(call_name(method), *loc),
                Expression::FunctionCall { function, loc, .. } => return Root::Temporary(call_name(function), *loc),
                _ => return Root::Place,
            }
        }
    }

    fn expression<'e>(&self, expr: &'e Expression, found: &mut impl FnMut(Found<'e>)) {
        crate::passes::visit_expression(expr, &mut |e: &'e Expression| match e {
            Expression::Binary { op, lhs, rhs, loc } => {
                let null = matches!(**lhs, Expression::PointerLiteral) || matches!(**rhs, Expression::PointerLiteral);
                let value = self.value_type(lhs).or_else(|| self.value_type(rhs));
                let compares = matches!(
                    op,
                    BinaryOp::Assign | BinaryOp::Equal | BinaryOp::NotEqual | BinaryOp::Identical | BinaryOp::NotIdentical
                );
                if let Some(value) = value.as_ref().filter(|_| null && compares) {
                    found(Found::Error(null_error(value).at(*loc)));
                } else if let Some(value) =
                    value.as_ref().filter(|_| matches!(op, BinaryOp::Identical | BinaryOp::NotIdentical))
                {
                    found(Found::Error(
                        Diagnostic::error(format!(
                            "'{}' is a value struct and has no identity; use '{}' to compare values",
                            value.display(),
                            if *op == BinaryOp::Identical { "==" } else { "!=" }
                        ))
                        .at(*loc),
                    ));
                }
                if op.is_assignment() {
                    self.assigned(lhs, found);
                }
            }
            Expression::Unary { op: UnaryOp::PreInc | UnaryOp::PostInc | UnaryOp::PreDec | UnaryOp::PostDec, operand, .. } => {
                self.assigned(operand, found)
            }
            // `__address` of a value hashes its fields, as for a tuple: the
            // generic `hash<T>` is built on it.
            Expression::RefCount(_, arg) => {
                if let Some(value) = self.value_type(arg) {
                    found(Found::Error(
                        Diagnostic::error(format!("'{}' is a value struct and has no object", value.display()))
                            .at(arg.loc()),
                    ));
                }
            }
            // `for` over a value iterator (no `iterate()`) drives it with
            // `next()` in place, which a `const` forbids.
            Expression::ForIterator(source) => {
                let Some(ty) = self.value_type(source) else { return };
                if self.table.lookup(&ty).is_some_and(|info| info.methods.contains("iterate")) {
                    return;
                }
                let root = self.root(source);
                if matches!(root, Root::Variable(_, Some(_))) {
                    found(Found::Change(Change { root, ty, member: "next", method: true, at: source.loc() }));
                }
            }
            Expression::Weak(_, ty, arg) if is_value(&ty.to_string()) => {
                found(Found::Error(weak_error(ty).at(arg.loc())));
            }
            Expression::MethodCall { this, method, loc, .. } => {
                if let Some(ty) = self.value_type(this) {
                    found(Found::Change(Change { root: self.root(this), ty, member: method, method: true, at: *loc }));
                }
            }
            _ => {}
        });
    }

    /// `target` is assigned: a field of a value changes that value.
    fn assigned<'e>(&self, target: &'e Expression, found: &mut impl FnMut(Found<'e>)) {
        match target {
            Expression::MemberRef { lhs, name, loc } => {
                if let Some(ty) = self.value_type(lhs) {
                    found(Found::Change(Change { root: self.root(lhs), ty, member: name, method: false, at: *loc }));
                }
            }
            // A bare field in a method is `this.field`.
            Expression::SymbolRef { id, loc, .. } if self.binding(id).is_none() && self.fields.contains(id) => {
                if let Some(ty) = self.current.filter(|ty| is_value(&ty.to_string())) {
                    found(Found::Change(Change { root: Root::This, ty: ty.clone(), member: id, method: false, at: *loc }));
                }
            }
            _ => {}
        }
    }
}

/// A called function or method as the source spells it: `[]` for an
/// indexer, an overload by its set's name.
fn call_name(name: &str) -> String {
    let name = crate::passes::overloads::set_name(name);
    if name.starts_with("__index") {
        "[]".to_string()
    } else {
        name.split('<').next().unwrap_or(name).to_string()
    }
}

fn null_error(ty: &TypeName) -> Diagnostic {
    Diagnostic::error(format!("value struct '{}' cannot be null", ty.display()))
}
