//! String literals as immortal static objects (#410).
//!
//! `convert_string_literals` makes every literal a `String(raw, size,
//! length)` constructor call, so each evaluation allocates a new `String`.
//! A `String` is a mutable reference type (`append` changes the object every
//! reference sees), so the literal cannot simply be one shared object: `var
//! s = "a"; s.append("b");` must leave the next evaluation of `"a"` alone.
//!
//! What a literal can share is every use that neither keeps nor changes
//! the object: an argument whose parameter is **free**, or the receiver of
//! a method whose `this` is. Such a literal becomes
//! [`Expression::StaticString`], one immortal object per literal in
//! constant storage (codegen's `static_string`), which nothing ever writes.
//!
//! A free parameter's copy is made by the caller, before the call, and
//! dropped after it, as the Itanium C++ ABI constructs and destroys a
//! by-value parameter (`Module::caller_copies`): the callee steps no count
//! for it. So a shared literal passes with no count step at all, and an
//! owned temporary is that copy. A function that passes its own free
//! parameter on to another free parameter may be passing a shared literal:
//! that copy steps with a guard that leaves a count at or above
//! `STATIC_REFCOUNT` alone. Only a direct call can make the caller's copy,
//! so the parameters of constructors, of `__` methods, of functions used as
//! values and of methods a trait's vtable calls are never free.
//!
//! An operand slot of type `String` (`this` of a `String` method, or a
//! parameter) is free when every use of it in the body is:
//!
//! - a read of a field that holds no reference (`text._size`, `_data`);
//! - an argument to a free parameter of a function or method the call
//!   resolves to (not an `extern`, a function value, or a trait method),
//!   or the receiver of a method whose `this` is free;
//! - a statement of its own, or a comparison with null.
//!
//! Anything else (a copy into a variable, field, element or result, a
//! capture, a conversion, `===`, `__refcount`, a write to a field or
//! through its buffer, an assignment to the parameter) keeps the slot. A
//! body that declares a local of the slot's name keeps it too. Freedom is
//! the greatest fixed point over the call graph, so recursion stays free.
//!
//! **Build cache.** A caller's code depends on its callees' bodies here, so
//! the facts ride in each function's recorded link summary (`|s=` and one
//! character per operand slot: `f` free, `k` kept, `-` not a `String`).
//! That puts them in the file's interface hash, and a function whose body
//! the cache skipped reads them back; without them, its slots are kept.

use crate::model::*;
use crate::static_type::StructTable;
use crate::type_name::TypeName;
use std::collections::HashMap;

/// What the recorded link summary carries after the confinement summary.
const FACTS: &str = "|s=";

/// A function with a body or recorded facts, by summary key.
struct Callee<'a> {
    function: &'a FunctionDef,
    /// The struct of a method or constructor.
    owner: Option<&'a StructDef>,
    /// Slot 0 is `this`.
    has_this: bool,
}

impl Callee<'_> {
    fn slot_types(&self) -> Vec<TypeName> {
        let this = self.has_this.then(|| self.owner.map(|st| st.ty.clone()).unwrap_or_else(TypeName::auto));
        this.into_iter().chain(self.function.parameters.iter().map(|p| p.ty.clone())).collect()
    }
}

fn is_string(ty: &TypeName) -> bool {
    ty.to_string() == "String"
}

/// A field whose value holds no reference: reading it lets nothing reach
/// the object.
fn is_plain(ty: &TypeName) -> bool {
    ty.is_pointer() || crate::arithmetic::is_numeric_type(&ty.to_string())
}

struct Program<'a> {
    module: &'a Module,
    table: StructTable,
    callees: HashMap<String, Callee<'a>>,
    /// Concrete structs by name.
    structs: HashMap<&'a str, &'a StructDef>,
    /// Constructor call names (`Point`, `Point$2`) to their keys.
    constructors: HashMap<&'a str, String>,
    /// Per key, per operand slot: kept (`true`) or free. Only keys with a
    /// `String` slot.
    kept: HashMap<String, Vec<bool>>,
}

fn method_key(owner: &str, method: &str) -> String {
    format!("{owner}.{method}")
}

impl<'a> Program<'a> {
    fn new(module: &'a Module) -> Self {
        let mut callees = HashMap::new();
        let mut structs = HashMap::new();
        let mut constructors = HashMap::new();
        for f in module.functions.iter().filter(|f| !f.is_generic_func) {
            callees.insert(f.name.clone(), Callee { function: f, owner: None, has_this: false });
        }
        for st in module.structs.iter().filter(|st| !(st.name == st.ty.name && st.ty.is_generic())) {
            structs.insert(st.name.as_str(), st);
            for m in st.method_members.iter().filter(|m| !m.is_generic_func) {
                callees.insert(method_key(&st.name, &m.name), Callee { function: m, owner: Some(st), has_this: !m.is_static });
            }
            for c in &st.constructors {
                let key = method_key(&c.name, "__ctor");
                constructors.insert(c.name.as_str(), key.clone());
                callees.insert(key, Callee { function: c, owner: Some(st), has_this: false });
            }
        }
        Program { module, table: StructTable::build(module), callees, structs, constructors, kept: HashMap::new() }
    }

    /// Seed every slot: a `String` slot of a function with a body starts
    /// free; one whose body the cache skipped takes its recorded fact.
    fn seed(&mut self) {
        let indirect = indirectly_called(self.module);
        for (key, callee) in &self.callees {
            let types = callee.slot_types();
            if !types.iter().any(is_string) {
                continue;
            }
            // Only a direct call can make the caller's copy.
            let method = callee.function.name.rsplit('.').next().unwrap_or("");
            // A property getter (`__get_p`) is called like any method.
            let internal = method.starts_with("__") && !method.starts_with("__get_");
            let kept = if key.ends_with(".__ctor") || internal || indirect.contains(key) {
                vec![true; types.len()]
            } else if callee.function.body.is_some() {
                types.iter().map(|t| !is_string(t)).collect()
            } else {
                recorded_facts(self.module, callee.function, types.len()).unwrap_or_else(|| vec![true; types.len()])
            };
            self.kept.insert(key.clone(), kept);
        }
    }

    /// Whether slot `slot` of `key` is free.
    fn is_free(&self, key: &str, slot: usize) -> bool {
        self.kept.get(key).and_then(|k| k.get(slot)).is_some_and(|kept| !kept)
    }

    /// The callee of `function(args)` and the slot of its first argument.
    fn resolve_function(&self, function: &str) -> Option<(String, usize)> {
        if self.module.externs.iter().any(|e| e.name == function) {
            return None;
        }
        if let Some(key) = self.constructors.get(function) {
            return Some((key.clone(), 0));
        }
        self.callees.contains_key(function).then(|| (function.to_string(), 0))
    }

    /// The callee of `this.method(args)` and the slot of `this` (`None`
    /// for a static method) and of its first argument.
    fn resolve_method(&self, scope: &Scope, this: &Expression, method: &str) -> Option<(String, Option<usize>, usize)> {
        if let Expression::SymbolRef { id, .. } = this
            && scope.local(id).is_none()
            && let Some(st) = self.structs.get(id.as_str())
        {
            let key = method_key(&st.name, method);
            let callee = self.callees.get(&key)?;
            return (!callee.has_this).then_some((key, None, 0));
        }
        let ty = scope.ty(this, &self.table)?;
        let st = self.structs.get(ty.to_string().as_str())?;
        let key = method_key(&st.name, method);
        let callee = self.callees.get(&key)?;
        Some(if callee.has_this { (key, Some(0), 1) } else { (key, None, 0) })
    }

    /// Whether the parameter at `slot` of `key` takes over its argument.
    fn takes_over(&self, key: &str, slot: usize) -> bool {
        let Some(callee) = self.callees.get(key) else { return true };
        let index = slot - usize::from(callee.has_this);
        callee.function.parameters.get(index).is_none_or(|p| crate::passes::check_confinement::takes_over(&p.attributes))
    }

    /// Whether an argument at `slot` of `key` may be a shared literal.
    fn argument_free(&self, key: &str, slot: usize) -> bool {
        self.is_free(key, slot) && !self.takes_over(key, slot)
    }

    /// Mark kept every `String` slot of `key` whose uses its body does not
    /// allow, under the current facts. Whether anything changed.
    fn refine(&mut self, key: &str) -> bool {
        let Some(kept) = self.kept.get(key) else { return false };
        let callee = &self.callees[key];
        let Some(body) = &callee.function.body else { return false };
        let names: Vec<String> = callee.has_this.then(|| "this".to_string()).into_iter().chain(callee.function.parameters.iter().map(|p| p.name.clone())).collect();
        let mut changed = vec![];
        for (slot, name) in names.iter().enumerate() {
            if kept[slot] {
                continue;
            }
            let mut uses = Uses { program: self, scope: Scope::new(callee), name, is_this: callee.has_this && slot == 0, kept: false };
            uses.block(body);
            if uses.kept {
                changed.push(slot);
            }
        }
        let kept = self.kept.get_mut(key).unwrap();
        for &slot in &changed {
            kept[slot] = true;
        }
        !changed.is_empty()
    }
}

/// The keys of the functions and methods a call can reach without naming
/// them: those used as function values (`FunctionRef`, a C callback's
/// `FunctionPointer`), and the methods that implement a trait's, which a
/// trait value's vtable calls. Their parameters keep the callee's copy.
fn indirectly_called(module: &Module) -> std::collections::HashSet<String> {
    let mut out = std::collections::HashSet::new();
    let mut note = |e: &Expression| match e {
        Expression::FunctionRef { function, .. } => {
            out.insert(function.clone());
        }
        Expression::FunctionPointer { owner, function, .. } => {
            out.insert(match owner {
                Some(owner) => method_key(&owner.to_string(), function),
                None => function.clone(),
            });
        }
        _ => {}
    };
    for f in &module.functions {
        crate::passes::visit_function(f, &mut note);
    }
    for st in &module.structs {
        for f in st.method_members.iter().chain(&st.constructors) {
            crate::passes::visit_function(f, &mut note);
        }
    }
    for var in &module.globals {
        if let Some(default) = &var.default {
            crate::passes::visit_expression(default, &mut note);
        }
    }
    for st in &module.structs {
        let slots: Vec<&str> = st
            .traits
            .iter()
            .filter_map(|t| module.traits.iter().find(|def| def.name == t.name))
            .flat_map(|def| def.methods.iter().map(|m| crate::passes::overloads::set_name(&m.name)))
            .collect();
        for m in st.method_members.iter().filter(|m| slots.contains(&crate::passes::overloads::set_name(&m.name))) {
            out.insert(method_key(&st.name, &m.name));
        }
    }
    out
}

/// The facts `|s=` recorded for `function`, whose body the cache skipped.
fn recorded_facts(module: &Module, function: &FunctionDef, slots: usize) -> Option<Vec<bool>> {
    let text = module.recorded_summaries.get(&function.loc)?;
    let (_, facts) = text.split_once(FACTS)?;
    let kept: Vec<bool> = facts.chars().map(|c| c != 'f').collect();
    (kept.len() == slots).then_some(kept)
}

/// The local types in scope, for resolving method calls.
struct Scope {
    locals: Vec<Vec<(String, TypeName)>>,
    current: Option<TypeName>,
}

impl Scope {
    fn new(callee: &Callee) -> Scope {
        let mut params: Vec<(String, TypeName)> = callee.function.parameters.iter().map(|p| (p.name.clone(), p.ty.clone())).collect();
        let current = callee.owner.map(|st| st.ty.clone());
        if let Some(owner) = &current {
            params.push(("this".to_string(), owner.clone()));
        }
        Scope { locals: vec![params], current }
    }

    fn global() -> Scope {
        Scope { locals: vec![vec![]], current: None }
    }

    fn local(&self, name: &str) -> Option<&TypeName> {
        self.locals.iter().rev().flat_map(|s| s.iter().rev()).find(|(n, _)| n == name).map(|(_, t)| t)
    }

    fn ty(&self, expr: &Expression, table: &StructTable) -> Option<TypeName> {
        match expr {
            Expression::SymbolRef { id, .. } if self.local(id).is_some() => self.local(id).cloned(),
            Expression::ThisRef => self.current.clone(),
            _ => crate::static_type::of(expr, table, self.current.as_ref()).filter(|t| !t.is_auto()),
        }
    }

    fn declare(&mut self, var: &VariableDef) {
        self.locals.last_mut().unwrap().push((var.name.clone(), var.ty.clone()));
    }
}

/// One walk over a body for the uses of one operand slot.
struct Uses<'p, 'a> {
    program: &'p Program<'a>,
    scope: Scope,
    name: &'p str,
    is_this: bool,
    kept: bool,
}

impl Uses<'_, '_> {
    fn is_slot(&self, expr: &Expression) -> bool {
        match expr {
            Expression::ThisRef => self.is_this,
            Expression::SymbolRef { id, .. } => id == self.name,
            _ => false,
        }
    }

    fn block(&mut self, block: &Block) {
        self.scope.locals.push(vec![]);
        for statement in &block.items {
            if self.kept {
                break;
            }
            self.statement(statement);
        }
        self.scope.locals.pop();
    }

    fn statement(&mut self, statement: &Statement) {
        match statement {
            Statement::Expression(expr) if self.is_slot(expr) => {}
            Statement::Expression(expr) => self.expression(expr, false),
            Statement::Block(inner) => self.block(inner),
            Statement::Declaration(Declaration::Variable(var)) => {
                if var.name == self.name {
                    self.kept = true;
                }
                if let Some(default) = &var.default {
                    self.expression(default, false);
                }
                self.scope.declare(var);
            }
            Statement::Declaration(_) => {}
            Statement::Branch(branch) => {
                self.expression(&branch.condition, false);
                self.block(&branch.if_block);
                if let Some(else_block) = &branch.else_block {
                    self.block(else_block);
                }
            }
            Statement::While(wh) => {
                self.expression(&wh.condition, false);
                self.block(&wh.block);
            }
            Statement::Return(ret) => {
                if let Some(expr) = &ret.expr {
                    self.expression(expr, false);
                }
            }
            Statement::LoopBreak(_) | Statement::StaticPass(_) => {}
            // Never reaches codegen.
            Statement::Static(_) => self.kept = true,
        }
    }

    /// An argument: the slot itself is allowed where its parameter is free.
    fn argument(&mut self, arg: &Expression, callee: Option<(&str, usize)>) {
        if self.is_slot(arg) {
            if !callee.is_some_and(|(key, slot)| self.program.argument_free(key, slot)) {
                self.kept = true;
            }
        } else {
            self.expression(arg, false);
        }
    }

    /// `expr`, which is written to (or through) when `write`.
    fn expression(&mut self, expr: &Expression, write: bool) {
        if self.kept {
            return;
        }
        if self.is_slot(expr) {
            // A use no rule below allows.
            self.kept = true;
            return;
        }
        match expr {
            Expression::MemberRef { lhs, name, .. } if self.is_slot(lhs) => {
                let plain = self
                    .scope
                    .ty(lhs, &self.program.table)
                    .and_then(|ty| self.program.structs.get(ty.to_string().as_str()).copied())
                    .and_then(|st| st.field_members.iter().find(|f| &f.name == name))
                    .is_some_and(|f| is_plain(&f.ty));
                if write || !plain {
                    self.kept = true;
                }
            }
            Expression::MemberRef { lhs, .. } => self.expression(lhs, write),
            Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
                self.expression(lhs, write);
                self.expression(rhs, false);
            }
            Expression::Binary { op, lhs, rhs, .. } if op.is_assignment() => {
                self.expression(lhs, true);
                self.expression(rhs, false);
            }
            Expression::Binary { op: BinaryOp::Equal | BinaryOp::NotEqual | BinaryOp::Identical | BinaryOp::NotIdentical, lhs, rhs, .. }
                if (self.is_slot(lhs) && matches!(**rhs, Expression::PointerLiteral))
                    || (self.is_slot(rhs) && matches!(**lhs, Expression::PointerLiteral)) => {}
            Expression::Unary { op: UnaryOp::PreInc | UnaryOp::PostInc | UnaryOp::PreDec | UnaryOp::PostDec, operand, .. } => {
                self.expression(operand, true)
            }
            Expression::ConstructAt(slot, value) => {
                self.expression(slot, true);
                self.expression(value, false);
            }
            Expression::AtomicStore(_, a, b) | Expression::AtomicFetch(_, _, a, b) => {
                self.expression(a, true);
                self.expression(b, false);
            }
            Expression::AtomicCmpXchg(_, a, b, c) => {
                self.expression(a, true);
                self.expression(b, false);
                self.expression(c, false);
            }
            Expression::FunctionCall { function, args, .. } => {
                let callee = self.program.resolve_function(function);
                for (i, arg) in args.iter().enumerate() {
                    self.argument(arg, callee.as_ref().map(|(key, first)| (key.as_str(), first + i)));
                }
            }
            Expression::MethodCall { this, method, args, .. } => {
                let callee = self.program.resolve_method(&self.scope, this, method);
                match &callee {
                    Some((key, Some(slot), _)) if self.is_slot(this) => {
                        if !self.program.is_free(key, *slot) {
                            self.kept = true;
                        }
                    }
                    _ if self.is_slot(this) => self.kept = true,
                    // A static call's receiver names a type.
                    Some((_, None, _)) => {}
                    _ => self.expression(this, false),
                }
                for (i, arg) in args.iter().enumerate() {
                    self.argument(arg, callee.as_ref().map(|(key, _, first)| (key.as_str(), first + i)));
                }
            }
            _ => {
                for child in crate::passes::children(expr) {
                    self.expression(child, false);
                }
            }
        }
    }
}

/// The value of a literal `convert_string_literals` made a constructor call.
fn literal_value(expr: &Expression) -> Option<(&str, Loc)> {
    match expr {
        Expression::FunctionCall { function, args, loc } if crate::passes::convert_string_literals::is_converted_literal(function, args, *loc) => {
            match args.first() {
                Some(Expression::StringLiteral { value, .. }) => Some((value.as_str(), *loc)),
                _ => None,
            }
        }
        _ => None,
    }
}

/// One walk over a body that finds the literals to share: each literal
/// argument to a free parameter, and each literal receiver of a method
/// whose `this` is free. They are found by address, then replaced once the
/// walk's borrow of the module ends.
struct Shared<'p, 'a> {
    program: &'p Program<'a>,
    scope: Scope,
    found: &'p mut std::collections::HashSet<*const Expression>,
}

impl Shared<'_, '_> {
    fn block(&mut self, block: &Block) {
        self.scope.locals.push(vec![]);
        for statement in &block.items {
            self.statement(statement);
        }
        self.scope.locals.pop();
    }

    fn statement(&mut self, statement: &Statement) {
        match statement {
            Statement::Expression(expr) => self.expression(expr),
            Statement::Block(inner) => self.block(inner),
            Statement::Declaration(Declaration::Variable(var)) => {
                if let Some(default) = &var.default {
                    self.expression(default);
                }
                self.scope.declare(var);
            }
            Statement::Declaration(_) | Statement::LoopBreak(_) | Statement::Static(_) | Statement::StaticPass(_) => {}
            Statement::Branch(branch) => {
                self.expression(&branch.condition);
                self.block(&branch.if_block);
                if let Some(else_block) = &branch.else_block {
                    self.block(else_block);
                }
            }
            Statement::While(wh) => {
                self.expression(&wh.condition);
                self.block(&wh.block);
            }
            Statement::Return(ret) => {
                if let Some(expr) = &ret.expr {
                    self.expression(expr);
                }
            }
        }
    }

    fn share(&mut self, expr: &Expression) {
        if literal_value(expr).is_some() {
            self.found.insert(expr as *const Expression);
        }
    }

    fn expression(&mut self, expr: &Expression) {
        match expr {
            Expression::FunctionCall { function, args, .. } => {
                if let Some((key, first)) = self.program.resolve_function(function) {
                    for (i, arg) in args.iter().enumerate() {
                        if self.program.argument_free(&key, first + i) {
                            self.share(arg);
                        }
                    }
                }
            }
            Expression::MethodCall { this, method, args, .. } => {
                if let Some((key, this_slot, first)) = self.program.resolve_method(&self.scope, this, method) {
                    if this_slot.is_some_and(|slot| self.program.is_free(&key, slot)) {
                        self.share(this);
                    }
                    for (i, arg) in args.iter().enumerate() {
                        if self.program.argument_free(&key, first + i) {
                            self.share(arg);
                        }
                    }
                }
            }
            _ => {}
        }
        for child in crate::passes::children(expr) {
            self.expression(child);
        }
    }
}

/// See the module docs.
pub fn share_string_literals(module: &mut Module) {
    let mut found = std::collections::HashSet::new();
    let (facts, caller_copies) = {
        let mut program = Program::new(module);
        program.seed();
        let mut keys: Vec<String> = program.kept.keys().cloned().collect();
        keys.sort();
        while keys.iter().fold(false, |changed, key| program.refine(key) | changed) {}
        for callee in program.callees.values() {
            if let Some(body) = &callee.function.body {
                Shared { program: &program, scope: Scope::new(callee), found: &mut found }.block(body);
            }
        }
        for var in &module.globals {
            if let Some(default) = &var.default {
                Shared { program: &program, scope: Scope::global(), found: &mut found }.expression(default);
            }
        }
        let caller_copies = program
            .callees
            .iter()
            .filter(|(key, _)| program.kept.contains_key(*key))
            .filter_map(|(key, callee)| {
                let first = usize::from(callee.has_this);
                let copies: Vec<bool> = (0..callee.function.parameters.len()).map(|i| program.argument_free(key, first + i)).collect();
                copies.iter().any(|c| *c).then(|| (key.clone(), copies))
            })
            .collect::<HashMap<String, Vec<bool>>>();
        (record_facts(&program), caller_copies)
    };
    module.caller_copies = caller_copies;
    for (loc, summary) in &mut module.summaries_to_record {
        if let Some(facts) = facts.get(loc) {
            summary.push_str(FACTS);
            summary.push_str(facts);
        }
    }
    if found.is_empty() {
        return;
    }
    let mut replace = |expr: &mut Expression| {
        if found.contains(&(expr as *const Expression))
            && let Some((value, loc)) = literal_value(expr)
        {
            *expr = Expression::StaticString { value: value.to_string(), loc };
        }
    };
    for f in &mut module.functions {
        crate::passes::walk_function(f, &mut replace);
    }
    for st in &mut module.structs {
        for f in st.method_members.iter_mut().chain(st.constructors.iter_mut()) {
            crate::passes::walk_function(f, &mut replace);
        }
    }
    for var in &mut module.globals {
        crate::passes::walk_global(var, &mut replace);
    }
}

/// The facts to record for each function with a body and a `String` slot,
/// by location.
fn record_facts(program: &Program) -> HashMap<Loc, String> {
    let mut at = HashMap::new();
    if program.module.summaries_to_record.is_empty() {
        return at;
    }
    for (key, callee) in &program.callees {
        let Some(kept) = program.kept.get(key) else { continue };
        if callee.function.body.is_none() {
            continue;
        }
        let facts: String = callee
            .slot_types()
            .iter()
            .zip(kept)
            .map(|(t, k)| if !is_string(t) { '-' } else if *k { 'k' } else { 'f' })
            .collect();
        at.insert(callee.function.loc, facts);
    }
    at
}
