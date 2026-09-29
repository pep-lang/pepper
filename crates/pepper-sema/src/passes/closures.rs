//! Closure literals (`(x: int) => x * 2`).
//!
//! A closure is a function value (see `function_types`) whose object also
//! holds the values it captured. [`lift_closures`] runs before any other
//! sema step and turns each literal into a synthesized struct plus a
//! creation expression:
//!
//! ```text
//! struct __closure_N<generic params of the enclosing code> {
//!     u32 __refcount;          # added by struct_body, like any struct
//!     u32 __weakcount;
//!     void* __invoke = <address of __call>;
//!     void* __destroy = <address of __dtor>;
//!     <one field per captured local>;
//!     <__this, when the body uses `this` or a member of the enclosing struct>;
//!     construct(this.<capture>, ...) {}
//!     __call(<the literal's parameters>): <its return type> { <its body> }
//! }
//! ```
//!
//! The head matches the function type struct `__function<R, P...>`, so the
//! object is used as a value of the closure's function type: `Invoke` calls
//! `__invoke` (`__call`, whose `this` is the object), and when the last
//! reference goes the function type's destructor calls `__destroy` (the
//! closure's destructor, which releases the captured values). The literal
//! becomes `MakeClosure { value: __closure_N(<captured values>), ty }`,
//! which is exactly a constructor call (`make_shared`): the reference-counting
//! model needs nothing new.
//!
//! Captures are by value, and a captured local may never be assigned, before
//! or after the closure, inside or outside it (Java's "effectively final"),
//! so a copy and the variable can never differ. Shared mutable state goes
//! through a captured struct (`Atomic<int>`, a `Counter`).
//!
//! Types the literal leaves out are inferred by [`sync_closures`], which the
//! transform passes run alongside `resolve_implicit_types`: parameter and
//! return types from the function type the closure flows into (a typed
//! variable, a parameter, a return, an assignment), capture types from the
//! captured locals, and the return type from the body. [`check_closures`]
//! reports what is still unknown at the end.

use crate::model::*;
use crate::passes::children_mut;
use crate::passes::function_types::empty_function;
use crate::type_name::{self, TypeName};
use std::collections::{HashMap, HashSet};

/// The method holding a closure's body.
pub const CALL_METHOD: &str = "__call";
/// The field holding the captured `this` of the enclosing method.
pub const THIS_FIELD: &str = "__this";
/// Name prefix of the synthesized closure structs.
pub const CLOSURE_PREFIX: &str = "__closure_";

thread_local! {
    /// Numbers the closure structs; never reset, it only keeps names unique.
    static CLOSURES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// Whether `name` (a struct name or type string) is a synthesized closure.
pub fn is_closure_struct(name: &str) -> bool {
    name.starts_with(CLOSURE_PREFIX)
}

// ── Lifting ───────────────────────────────────────────────────────────────────

/// What the code around a literal provides: its generic parameters and, in
/// a method, the struct `this` refers to and that struct's member names.
#[derive(Default, Clone)]
struct Context {
    generics: Vec<GenericParam>,
    this_ty: Option<TypeName>,
    fields: HashSet<String>,
    methods: HashSet<String>,
    /// A trait's default method: `this` has no single struct type yet.
    in_trait: bool,
}

struct Var {
    name: String,
    ty: TypeName,
    /// How many closure literals enclose the declaration (0: the function).
    level: usize,
    /// Where it is declared.
    loc: Loc,
}

/// A closure literal being lifted.
struct Frame {
    level: usize,
    /// Captured locals, each with where this closure first uses it.
    captures: Vec<(usize, Loc)>,
    uses_this: bool,
    /// Where this closure first uses `this` or a member, when known.
    this_use: Loc,
}

struct Lifter<'a> {
    ctx: &'a Context,
    vars: Vec<Var>,
    scopes: Vec<Vec<usize>>,
    level: usize,
    frames: Vec<Frame>,
    /// Assignments to locals: (variable, location of the assigned name).
    assignments: Vec<(usize, Loc)>,
    /// Captured locals and where a closure first uses each.
    captured: HashMap<usize, Loc>,
    lifted: Vec<StructDef>,
}

impl<'a> Lifter<'a> {
    fn new(ctx: &'a Context) -> Self {
        Lifter {
            ctx,
            vars: vec![],
            scopes: vec![vec![]],
            level: 0,
            frames: vec![],
            assignments: vec![],
            captured: HashMap::new(),
            lifted: vec![],
        }
    }

    fn declare(&mut self, name: &str, ty: &TypeName, loc: Loc) {
        self.vars.push(Var { name: name.to_string(), ty: ty.clone(), level: self.level, loc });
        let id = self.vars.len() - 1;
        self.scopes.last_mut().expect("scope").push(id);
    }

    fn resolve(&self, name: &str) -> Option<usize> {
        self.scopes.iter().rev().flat_map(|s| s.iter().rev()).copied().find(|&id| self.vars[id].name == name)
    }

    /// A use of local `id`: every closure between it and its declaration
    /// captures it.
    fn use_var(&mut self, id: usize, loc: Loc) {
        let level = self.vars[id].level;
        let mut any = false;
        for frame in &mut self.frames {
            if frame.level > level {
                any = true;
                if !frame.captures.iter().any(|&(c, _)| c == id) {
                    frame.captures.push((id, loc));
                }
            }
        }
        if any {
            self.captured.entry(id).or_insert(loc);
        }
    }

    /// A use of `this` inside a closure: every enclosing closure captures it.
    fn use_this(&mut self, loc: Loc) {
        if self.ctx.in_trait {
            crate::errors::report(
                Diagnostic::error("a closure in a trait's default method cannot use 'this' or the members of the struct yet")
                    .at(loc),
            );
        }
        for frame in &mut self.frames {
            frame.uses_this = true;
            if frame.this_use.is_none() {
                frame.this_use = loc;
            }
        }
    }

    fn this_ref(loc: Loc) -> Expression {
        Expression::SymbolRef { id: THIS_FIELD.to_string(), ty: TypeName::auto(), loc }
    }

    fn walk_block(&mut self, block: &mut Block) {
        self.scopes.push(vec![]);
        for stmt in &mut block.items {
            self.walk_statement(stmt);
        }
        self.scopes.pop();
    }

    fn walk_statement(&mut self, stmt: &mut Statement) {
        match stmt {
            Statement::Expression(e) => self.walk_expression(e),
            Statement::Block(b) => self.walk_block(b),
            Statement::Declaration(Declaration::Variable(var)) => {
                if let Some(default) = &mut var.default {
                    self.walk_expression(default);
                }
                self.declare(&var.name, &var.ty, var.loc);
            }
            Statement::Declaration(_) => {}
            Statement::Branch(branch) => {
                self.walk_expression(&mut branch.condition);
                self.walk_block(&mut branch.if_block);
                if let Some(else_block) = &mut branch.else_block {
                    self.walk_block(else_block);
                }
            }
            Statement::While(wh) => {
                self.walk_expression(&mut wh.condition);
                self.walk_block(&mut wh.block);
            }
            Statement::Return(ret) => {
                if let Some(e) = &mut ret.expr {
                    self.walk_expression(e);
                }
            }
            Statement::LoopBreak(_) => {}
        }
    }

    /// The local an assignment target names, if any.
    fn assigned_local(&self, target: &Expression) -> Option<(usize, Loc)> {
        match target {
            Expression::SymbolRef { id, loc, .. } => self.resolve(id).map(|v| (v, *loc)),
            _ => None,
        }
    }

    fn walk_expression(&mut self, expr: &mut Expression) {
        let inside = self.level > 0;
        match expr {
            Expression::ClosureLiteral(_) => {
                self.lift(expr);
                return;
            }
            Expression::SymbolRef { id, loc, .. } => {
                if let Some(v) = self.resolve(id) {
                    self.use_var(v, *loc);
                } else if inside && self.ctx.this_ty.is_some() && self.ctx.fields.contains(id.as_str()) {
                    // A bare field of the enclosing struct: `__this.field`.
                    let loc = *loc;
                    self.use_this(loc);
                    *expr = Expression::MemberRef { lhs: Box::new(Self::this_ref(loc)), name: id.clone(), loc };
                }
                return;
            }
            Expression::ThisRef => {
                if inside {
                    self.use_this(Loc::NONE);
                    *expr = Self::this_ref(Loc::NONE);
                }
                return;
            }
            Expression::FunctionCall { function, loc, .. } => {
                let loc = *loc;
                if let Some(v) = self.resolve(function) {
                    // A call through a local of function type.
                    self.use_var(v, loc);
                } else if inside
                    && self.ctx.this_ty.is_some()
                    && (self.ctx.methods.contains(function.as_str()) || self.ctx.fields.contains(function.as_str()))
                {
                    // A bare method of the enclosing struct (or a call
                    // through one of its fields): `__this.m(...)`.
                    self.use_this(loc);
                    let Expression::FunctionCall { function, args, loc } = std::mem::replace(expr, Expression::PointerLiteral) else {
                        unreachable!()
                    };
                    *expr = Expression::MethodCall { this: Box::new(Self::this_ref(loc)), method: function, args, loc };
                }
            }
            Expression::Binary { op, lhs, .. } if op.is_assignment() => {
                if let Some(assigned) = self.assigned_local(lhs) {
                    self.assignments.push(assigned);
                }
            }
            Expression::Unary { op: UnaryOp::PreInc | UnaryOp::PostInc | UnaryOp::PreDec | UnaryOp::PostDec, operand, .. } => {
                if let Some(assigned) = self.assigned_local(operand) {
                    self.assignments.push(assigned);
                }
            }
            _ => {}
        }
        for child in children_mut(expr) {
            self.walk_expression(child);
        }
        if let Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. } = expr {
            self.check_this_cycle(lhs, rhs);
        }
    }

    /// `this.field = <closure capturing this>` in a method: the object would
    /// hold the closure and the closure the object, a cycle reference
    /// counting never frees.
    fn check_this_cycle(&self, lhs: &Expression, rhs: &Expression) {
        if self.level > 0 || self.ctx.this_ty.is_none() {
            return;
        }
        let field = match lhs {
            Expression::MemberRef { lhs, name, loc } if matches!(lhs.as_ref(), Expression::ThisRef) => Some((name, *loc)),
            Expression::SymbolRef { id, loc, .. } if self.resolve(id).is_none() && self.ctx.fields.contains(id.as_str()) => Some((id, *loc)),
            _ => None,
        };
        let Some((field, loc)) = field else { return };
        let Expression::MakeClosure { value, loc: closure_loc, .. } = rhs else { return };
        let Expression::FunctionCall { args, .. } = value.as_ref() else { return };
        if args.iter().any(|a| matches!(a, Expression::ThisRef)) {
            crate::errors::report(
                Diagnostic::error(format!(
                    "storing a closure that captures 'this' in field '{}' of 'this' creates a reference cycle that is never freed",
                    field
                ))
                .at(loc)
                .with_note("the closure captures 'this' here; capture a 'Weak' reference to it instead", Some(*closure_loc)),
            );
        }
    }

    /// Replace the closure literal `expr` with its creation expression, and
    /// record the struct it becomes.
    fn lift(&mut self, expr: &mut Expression) {
        let Expression::ClosureLiteral(literal) = std::mem::replace(expr, Expression::PointerLiteral) else {
            unreachable!()
        };
        let mut literal = *literal;
        self.level += 1;
        self.frames.push(Frame { level: self.level, captures: vec![], uses_this: false, this_use: Loc::NONE });
        self.scopes.push(vec![]);
        for param in &literal.parameters {
            self.declare(&param.name, &param.ty, param.loc);
        }
        self.walk_block(&mut literal.body);
        self.scopes.pop();
        let frame = self.frames.pop().expect("frame");
        self.level -= 1;

        let (base, ty) = closure_name(&self.ctx.generics);
        let loc = literal.loc;

        // Captured values, then `this`. Each capture field is located at the
        // closure's first use of the value, and its `type_loc` is where the
        // captured local is declared (for `check_shared_types`).
        let mut captures = vec![];
        let mut args = vec![];
        for &(id, used) in &frame.captures {
            let var = &self.vars[id];
            let used = if used.is_none() { loc } else { used };
            captures.push(VariableDef { type_loc: var.loc, ..field(&var.name, var.ty.clone(), None, used) });
            args.push(Expression::SymbolRef { id: var.name.clone(), ty: TypeName::auto(), loc });
        }
        if frame.uses_this {
            if let Some(this_ty) = &self.ctx.this_ty {
                let used = if frame.this_use.is_none() { loc } else { frame.this_use };
                captures.push(field(THIS_FIELD, this_ty.clone(), None, used));
                args.push(if self.level == 0 { Expression::ThisRef } else { Self::this_ref(loc) });
            }
        }
        let signature = TypeName::function_type(
            literal.ty.clone(),
            literal.parameters.iter().map(|p| p.ty.clone()).collect(),
        );
        self.lifted.push(closure_struct(&base, &ty, &self.ctx.generics, captures, literal.parameters, literal.ty, literal.body, loc));
        *expr = Expression::MakeClosure {
            value: Box::new(Expression::FunctionCall { function: ty.to_string(), args, loc }),
            closure: ty.to_string(),
            ty: signature,
            loc,
        };
    }

    /// A captured local that is assigned anywhere is an error.
    fn check_assignments(&self) {
        for (id, loc) in &self.assignments {
            if let Some(captured) = self.captured.get(id) {
                crate::errors::report(
                    Diagnostic::error(format!("cannot assign to '{}' because a closure captures it", self.vars[*id].name))
                        .at(*loc)
                        .with_note("captured here; a closure keeps a copy, so the variable must not change", Some(*captured)),
                );
                return;
            }
        }
    }
}

/// A fresh closure struct name, and its type over `generics`.
pub(crate) fn closure_name(generics: &[GenericParam]) -> (String, TypeName) {
    let n = CLOSURES.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    });
    let base = format!("{}{}", CLOSURE_PREFIX, n);
    let ty = if generics.is_empty() {
        TypeName::new(&base)
    } else {
        TypeName::with_args(&base, generics.iter().map(|g| TypeName::new(&g.name)).collect())
    };
    (base, ty)
}

/// The struct a closure becomes (see the module docs): the function-type
/// head, one field per captured value (`captures`, initialized by the
/// constructor in order), and `__call` running `body`.
#[allow(clippy::too_many_arguments)]
pub(crate) fn closure_struct(
    base: &str,
    ty: &TypeName,
    generics: &[GenericParam],
    captures: Vec<VariableDef>,
    parameters: Vec<VariableDef>,
    ret: TypeName,
    body: Block,
    loc: Loc,
) -> StructDef {
    let mut fields = vec![
        field(crate::passes::function_types::INVOKE_FIELD, TypeName::void_ptr(), Some(Expression::MethodAddress(CALL_METHOD.to_string())), loc),
        field(crate::passes::function_types::DESTROY_FIELD, TypeName::void_ptr(), Some(Expression::MethodAddress("__dtor".to_string())), loc),
    ];
    fields.extend(captures);
    let ctor_params: Vec<VariableDef> = fields[2..]
        .iter()
        .map(|f| VariableDef { name: format!("this.{}", f.name), kind: Kind::Param, default: None, ..f.clone() })
        .collect();
    let mut constructor = empty_function(&ty.to_string(), ty.clone(), base);
    constructor.parameters = ctor_params;
    constructor.loc = loc;
    let call = FunctionDef {
        name: CALL_METHOD.to_string(),
        ty: ret,
        generic_params: vec![],
        parameters,
        body: Some(body),
        parent: Some(base.to_string()),
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
        attributes: vec![],
        loc,
    };
    StructDef {
        name: base.to_string(),
        ty: ty.clone(),
        generic_params: generics.to_vec(),
        field_members: fields,
        method_members: vec![call],
        generic_methods: vec![],
        constructor,
        destructor: empty_function("__dtor", TypeName::void(), base),
        acquire: empty_function("__acquire", TypeName::void(), base),
        release: empty_function("__release", TypeName::void(), base),
        traits: vec![],
        attributes: vec![],
        loc,
    }
}

pub(crate) fn field(name: &str, ty: TypeName, default: Option<Expression>, loc: Loc) -> VariableDef {
    VariableDef {
        name: name.to_string(),
        ty,
        default,
        hidden: false,
        kind: Kind::Field,
        attributes: vec![],
        loc,
        type_loc: Loc::NONE,
        is_const: false,
    }
}

/// Lift the literals in `function`, whose parameters are locals.
fn lift_function(function: &mut FunctionDef, ctx: &Context, lifted: &mut Vec<StructDef>) {
    let mut ctx = ctx.clone();
    ctx.generics.extend(function.generic_params.iter().cloned());
    let mut lifter = Lifter::new(&ctx);
    for param in &mut function.parameters {
        if let Some(default) = &mut param.default {
            lifter.walk_expression(default);
        }
    }
    for param in &function.parameters {
        if !param.name.starts_with("this.") {
            lifter.declare(&param.name, &param.ty, param.loc);
        }
    }
    if let Some(body) = &mut function.body {
        lifter.walk_block(body);
    }
    lifter.check_assignments();
    lifted.append(&mut lifter.lifted);
}

/// Lift a literal outside any function (a global or field default).
fn lift_default(expr: &mut Expression, ctx: &Context, lifted: &mut Vec<StructDef>) {
    let ctx = Context { this_ty: None, ..ctx.clone() };
    let mut lifter = Lifter::new(&ctx);
    lifter.walk_expression(expr);
    lifted.append(&mut lifter.lifted);
}

/// Turn every closure literal in the module into a synthesized struct and a
/// `MakeClosure` (see the module docs). Runs first in `struct_body::apply`,
/// so the new structs get their bodies synthesized with the rest.
pub fn lift_closures(module: &mut Module) {
    let mut lifted = vec![];
    // Every name a type can have: an `extend Box<T>` parameter is one that
    // names none of them.
    let mut types: HashSet<String> = module.structs.iter().map(|s| s.ty.name.clone()).collect();
    types.extend(module.type_aliases.iter().map(|a| a.name.clone()));
    types.extend(module.traits.iter().map(|t| t.name.clone()));
    let extension_methods = |name: &str, module: &Module| -> HashSet<String> {
        module
            .extensions
            .iter()
            .filter(|e| e.target.name == name)
            .flat_map(|e| e.methods.iter().map(|m| m.name.clone()))
            .collect()
    };
    let struct_contexts: Vec<Context> = module
        .structs
        .iter()
        .map(|st| {
            let mut methods: HashSet<String> = st.method_members.iter().map(|m| m.name.clone()).collect();
            methods.extend(extension_methods(&st.ty.name, module));
            Context {
                generics: st.generic_params.clone(),
                this_ty: Some(st.ty.clone()),
                fields: st.field_members.iter().map(|f| f.name.clone()).collect(),
                methods,
                in_trait: false,
            }
        })
        .collect();
    let extension_contexts: Vec<Context> = module
        .extensions
        .iter()
        .map(|ext| {
            let generics = ext
                .target
                .sub_types
                .iter()
                .filter(|t| t.sub_types.is_empty() && !types.contains(&t.name) && !type_name::INTEGRAL_TYPES.contains(t.name.as_str()))
                .map(|t| GenericParam { name: t.name.clone(), default: None })
                .collect();
            let target = module.structs.iter().find(|s| s.ty.name == ext.target.name);
            let mut methods: HashSet<String> = target.map(|s| s.method_members.iter().map(|m| m.name.clone()).collect()).unwrap_or_default();
            methods.extend(extension_methods(&ext.target.name, module));
            Context {
                generics,
                this_ty: Some(ext.target.clone()),
                fields: target.map(|s| s.field_members.iter().map(|f| f.name.clone()).collect()).unwrap_or_default(),
                methods,
                in_trait: false,
            }
        })
        .collect();

    let plain = Context::default();
    for function in &mut module.functions {
        lift_function(function, &plain, &mut lifted);
    }
    for (st, ctx) in module.structs.iter_mut().zip(&struct_contexts) {
        for field in &mut st.field_members {
            if let Some(default) = &mut field.default {
                lift_default(default, ctx, &mut lifted);
            }
        }
        lift_function(&mut st.constructor, ctx, &mut lifted);
        lift_function(&mut st.destructor, ctx, &mut lifted);
        for method in st.method_members.iter_mut().chain(st.generic_methods.iter_mut()) {
            lift_function(method, ctx, &mut lifted);
        }
    }
    for (ext, ctx) in module.extensions.iter_mut().zip(&extension_contexts) {
        for method in &mut ext.methods {
            lift_function(method, ctx, &mut lifted);
        }
    }
    for tr in &mut module.traits {
        let ctx = Context {
            generics: tr.generic_params.clone(),
            in_trait: true,
            this_ty: Some(TypeName::new("this")),
            ..Context::default()
        };
        for method in &mut tr.methods {
            lift_function(method, &ctx, &mut lifted);
        }
    }
    for var in &mut module.globals {
        if let Some(default) = &mut var.default {
            lift_default(default, &plain, &mut lifted);
        }
    }
    module.structs.extend(lifted);
}

// ── Type inference ────────────────────────────────────────────────────────────

/// What `sync_closures` learned about one closure struct.
#[derive(Default)]
struct Learned {
    /// Expected function type (from where the closure flows).
    expected: Option<TypeName>,
    /// Types of the constructor arguments (the captured values).
    captures: Vec<Option<TypeName>>,
}

/// Fill in closure types the literals left out (see the module docs), and
/// keep each `MakeClosure`'s function type in step with its `__call`.
/// Returns whether anything changed.
pub fn sync_closures(module: &mut Module) -> bool {
    if !module.structs.iter().any(|s| is_closure_struct(&s.name)) {
        return false;
    }
    let table = Table::build(module);
    let mut learned: HashMap<String, Learned> = HashMap::new();
    {
        let mut visit = |expr: &Expression, expected: Option<&TypeName>, current: Option<&TypeName>| {
            let Expression::MakeClosure { value, closure, .. } = expr else { return };
            let entry = learned.entry(closure.clone()).or_default();
            if let Some(ty) = expected.filter(|t| t.is_function_type()) {
                // A fully known type wins over a partly known one.
                if entry.expected.as_ref().is_none_or(|e| e.contains_auto() && !ty.contains_auto()) {
                    entry.expected = Some(ty.clone());
                }
            }
            if let Expression::FunctionCall { args, .. } = value.as_ref() {
                if entry.captures.len() < args.len() {
                    entry.captures.resize(args.len(), None);
                }
                for (slot, arg) in entry.captures.iter_mut().zip(args) {
                    if slot.is_none() {
                        *slot = table.type_of(arg, current).filter(|t| !t.contains_auto());
                    }
                }
            }
        };
        for_each_closure_site(module, &table, &mut visit);
    }

    let mut changed = false;
    for st in &mut module.structs {
        if !is_closure_struct(&st.name) {
            continue;
        }
        let key = st.ty.to_string();
        let learned = learned.get(&key).or_else(|| learned.get(&st.name));
        if let Some(learned) = learned {
            changed |= apply_learned(st, learned);
        }
        // An expression body of a closure that returns nothing is a
        // statement, not a returned value.
        if let Some(call) = st.method_members.iter_mut().find(|m| m.name == CALL_METHOD) {
            if call.ty.to_string() == type_name::VOID {
                if let Some(body) = &mut call.body {
                    if let [Statement::Return(ReturnStatement { expr: Some(_), .. })] = body.items.as_slice() {
                        let Some(Statement::Return(ReturnStatement { expr: Some(e), .. })) = body.items.pop() else { unreachable!() };
                        body.items.push(Statement::Expression(e));
                        changed = true;
                    }
                }
            }
        }
    }

    // Each creation's function type follows its closure's `__call`.
    let signatures: HashMap<String, TypeName> = module
        .structs
        .iter()
        .filter(|s| is_closure_struct(&s.name))
        .filter_map(|s| {
            let call = s.method_members.iter().find(|m| m.name == CALL_METHOD)?;
            let sig = TypeName::function_type(call.ty.clone(), call.parameters.iter().map(|p| p.ty.clone()).collect());
            Some((s.ty.to_string(), sig))
        })
        .collect();
    for_each_expression_mut(module, &mut |e| {
        if let Expression::MakeClosure { closure, ty, .. } = e {
            if let Some(sig) = signatures.get(closure.as_str()) {
                if ty != sig {
                    *ty = sig.clone();
                    changed = true;
                }
            }
        }
    });
    changed
}

/// Give the closure struct the types `learned` found for it.
fn apply_learned(st: &mut StructDef, learned: &Learned) -> bool {
    let mut changed = false;
    // Captured values: fields after `__invoke` and `__destroy`, in order,
    // and the constructor parameters that initialize them.
    let capture_fields: Vec<usize> = (0..st.field_members.len())
        .filter(|&i| {
            let name = &st.field_members[i].name;
            !name.starts_with("__") || name == THIS_FIELD
        })
        .collect();
    for (k, &i) in capture_fields.iter().enumerate() {
        if !st.field_members[i].ty.contains_auto() {
            continue;
        }
        let Some(Some(ty)) = learned.captures.get(k) else { continue };
        st.field_members[i].ty = ty.clone();
        let name = st.field_members[i].name.clone();
        let init = format!("__init_{}", name);
        for param in &mut st.constructor.parameters {
            if param.name == init {
                param.ty = ty.clone();
            }
        }
        // The constructor zero-initializes every field first; the zero was
        // chosen while the type was unknown.
        if let Some(body) = &mut st.constructor.body {
            for stmt in &mut body.items {
                if let Statement::Expression(Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. }) = stmt {
                    let zeroes_field = matches!(lhs.as_ref(), Expression::MemberRef { lhs, name: n, .. } if matches!(lhs.as_ref(), Expression::ThisRef) && *n == name);
                    if zeroes_field && matches!(rhs.as_ref(), Expression::IntLiteral(0) | Expression::FloatLiteral(_) | Expression::PointerLiteral) {
                        **rhs = crate::struct_body::zero_for(ty);
                    }
                }
            }
        }
        changed = true;
    }
    let Some(expected) = &learned.expected else { return changed };
    let Some(call) = st.method_members.iter_mut().find(|m| m.name == CALL_METHOD) else { return changed };
    let params = expected.function_params();
    if params.len() == call.parameters.len() {
        for (param, ty) in call.parameters.iter_mut().zip(params) {
            if param.ty.contains_auto() && !ty.contains_auto() {
                param.ty = ty.clone();
                changed = true;
            }
        }
    }
    if let Some(ret) = expected.function_return() {
        if call.ty.to_string() == type_name::AUTO && !ret.contains_auto() {
            call.ty = ret.clone();
            changed = true;
        }
    }
    changed
}

/// Report closure types nothing could infer. Runs after the last type
/// inference; generic bases are skipped (their specializations are checked).
pub fn check_closures(module: &Module) {
    for st in &module.structs {
        if !is_closure_struct(&st.name) || !st.generic_params.is_empty() {
            continue;
        }
        let Some(call) = st.method_members.iter().find(|m| m.name == CALL_METHOD) else { continue };
        for param in &call.parameters {
            if param.ty.contains_auto() {
                crate::errors::report(
                    Diagnostic::error(format!(
                        "cannot infer the type of parameter '{}'; write it: ({}: Type) => ...",
                        param.name, param.name
                    ))
                    .at(param.loc),
                );
                return;
            }
        }
        if call.ty.contains_auto() {
            crate::errors::report(
                Diagnostic::error("cannot infer the return type of this closure; write it after the parameters: (...): Type => ...")
                    .at(call.loc),
            );
            return;
        }
        for field in &st.field_members {
            if field.ty.contains_auto() {
                crate::errors::report(
                    Diagnostic::error(format!("cannot infer the type of '{}', which this closure captures", field.name))
                        .at(field.loc),
                );
                return;
            }
        }
    }
}

// ── Walking closure creations with the type they flow into ────────────────────

/// Declared types the expected-type walk needs.
struct Table {
    /// Free function or struct constructor name → parameter types.
    callables: HashMap<String, Vec<TypeName>>,
    /// Struct type string → (field name → type).
    fields: HashMap<String, HashMap<String, TypeName>>,
    /// Struct type string → (method name → parameter types).
    methods: HashMap<String, HashMap<String, Vec<TypeName>>>,
    globals: HashMap<String, TypeName>,
    /// Generic free functions, for calls whose type arguments are inferred.
    generics: HashMap<String, crate::passes::type_arguments::GenericSignature>,
    /// Struct type string → generic methods, likewise.
    generic_methods: HashMap<String, HashMap<String, crate::passes::type_arguments::GenericSignature>>,
    statics: crate::static_type::StructTable,
}

impl Table {
    fn build(module: &Module) -> Self {
        let mut callables = HashMap::new();
        // A generic base's parameter types name its own type parameters,
        // which mean nothing at the call site; only its specializations
        // (`apply<int>`) give a closure argument its types.
        for f in module.functions.iter().filter(|f| !f.is_generic_func) {
            callables.insert(f.name.clone(), f.parameters.iter().map(|p| p.ty.clone()).collect());
        }
        for e in &module.externs {
            callables.insert(e.name.clone(), e.parameters.iter().map(|p| p.ty.clone()).collect());
        }
        let mut fields = HashMap::new();
        let mut methods = HashMap::new();
        for st in module.structs.iter().filter(|s| s.generic_params.is_empty()) {
            callables.insert(st.ty.to_string(), st.constructor.parameters.iter().map(|p| p.ty.clone()).collect());
            fields.insert(st.ty.to_string(), st.field_members.iter().map(|f| (f.name.clone(), f.ty.clone())).collect());
            methods.insert(
                st.ty.to_string(),
                st.method_members.iter().map(|m| (m.name.clone(), m.parameters.iter().map(|p| p.ty.clone()).collect())).collect(),
            );
        }
        let globals = module.globals.iter().map(|g| (g.name.clone(), g.ty.clone())).collect();
        let generics = module
            .functions
            .iter()
            .filter(|f| f.is_generic_func)
            .map(|f| (f.name.clone(), crate::passes::type_arguments::GenericSignature::of(f)))
            .collect();
        let generic_methods = module
            .structs
            .iter()
            .filter(|s| s.generic_params.is_empty() && !s.generic_methods.is_empty())
            .map(|s| {
                let methods = s
                    .generic_methods
                    .iter()
                    .map(|m| (m.name.clone(), crate::passes::type_arguments::GenericSignature::of(m)))
                    .collect();
                (s.ty.to_string(), methods)
            })
            .collect();
        Table { callables, fields, methods, globals, generics, generic_methods, statics: crate::static_type::StructTable::build(module) }
    }

    fn field(&self, owner: &TypeName, name: &str) -> Option<TypeName> {
        let owner = owner.to_string();
        self.fields.get(owner.trim_end_matches('*'))?.get(name).cloned()
    }

    /// A generic call's parameter types, with what its arguments bind.
    fn generic_parameters(
        &self,
        signature: &crate::passes::type_arguments::GenericSignature,
        args: &[Expression],
        current: Option<&TypeName>,
    ) -> Option<Vec<TypeName>> {
        let types: Vec<Option<TypeName>> = args
            .iter()
            .map(|arg| match arg {
                Expression::MakeClosure { ty, .. } => Some(ty.clone()),
                _ => self.type_of(arg, current),
            })
            .collect();
        let bindings = signature.bind(&types);
        (0..signature.parameter_types.len()).map(|i| signature.expected(i, &bindings)).collect()
    }

    /// Best-effort static type of `expr` in a body of struct `current`.
    fn type_of(&self, expr: &Expression, current: Option<&TypeName>) -> Option<TypeName> {
        let ty = match expr {
            Expression::SymbolRef { id, ty, .. } if ty.contains_auto() => {
                current.and_then(|c| self.field(c, id)).or_else(|| self.globals.get(id).cloned())
            }
            Expression::MemberRef { lhs, name, .. } => self.type_of(lhs, current).and_then(|t| self.field(&t, name)),
            Expression::MakeClosure { ty, .. } => Some(ty.clone()),
            _ => crate::static_type::of(expr, &self.statics, current),
        };
        ty.filter(|t| !t.is_empty() && !t.contains_auto())
    }
}

/// Call `visit(creation, expected type, current struct)` for every
/// `MakeClosure`, with the type of the slot it flows into when known.
fn for_each_closure_site(module: &Module, table: &Table, visit: &mut impl FnMut(&Expression, Option<&TypeName>, Option<&TypeName>)) {
    for st in &module.structs {
        let current = Some(&st.ty);
        for field in &st.field_members {
            if let Some(default) = &field.default {
                sites_in_expression(default, Some(&field.ty), table, current, visit);
            }
        }
        for method in st.method_members.iter().chain([&st.constructor, &st.destructor]) {
            sites_in_function(method, table, current, visit);
        }
    }
    for function in &module.functions {
        sites_in_function(function, table, None, visit);
    }
    for ext in &module.extensions {
        for method in &ext.methods {
            sites_in_function(method, table, Some(&ext.target), visit);
        }
    }
    for var in &module.globals {
        if let Some(default) = &var.default {
            sites_in_expression(default, Some(&var.ty), table, None, visit);
        }
    }
}

fn sites_in_function(
    function: &FunctionDef,
    table: &Table,
    current: Option<&TypeName>,
    visit: &mut impl FnMut(&Expression, Option<&TypeName>, Option<&TypeName>),
) {
    for param in &function.parameters {
        if let Some(default) = &param.default {
            sites_in_expression(default, Some(&param.ty), table, current, visit);
        }
    }
    if let Some(body) = &function.body {
        let mut locals: Vec<HashMap<String, TypeName>> =
            vec![function.parameters.iter().map(|p| (p.name.clone(), p.ty.clone())).collect()];
        sites_in_block(body, &function.ty, table, current, &mut locals, visit);
    }
}

fn sites_in_block(
    block: &Block,
    ret: &TypeName,
    table: &Table,
    current: Option<&TypeName>,
    locals: &mut Vec<HashMap<String, TypeName>>,
    visit: &mut impl FnMut(&Expression, Option<&TypeName>, Option<&TypeName>),
) {
    locals.push(HashMap::new());
    for stmt in &block.items {
        match stmt {
            Statement::Expression(e) => sites_in_expression(e, None, table, current, visit),
            Statement::Block(b) => sites_in_block(b, ret, table, current, locals, visit),
            Statement::Declaration(Declaration::Variable(var)) => {
                if let Some(default) = &var.default {
                    sites_in_expression(default, Some(&var.ty), table, current, visit);
                }
                locals.last_mut().expect("scope").insert(var.name.clone(), var.ty.clone());
            }
            Statement::Declaration(_) => {}
            Statement::Branch(branch) => {
                sites_in_expression(&branch.condition, None, table, current, visit);
                sites_in_block(&branch.if_block, ret, table, current, locals, visit);
                if let Some(else_block) = &branch.else_block {
                    sites_in_block(else_block, ret, table, current, locals, visit);
                }
            }
            Statement::While(wh) => {
                sites_in_expression(&wh.condition, None, table, current, visit);
                sites_in_block(&wh.block, ret, table, current, locals, visit);
            }
            Statement::Return(r) => {
                if let Some(e) = &r.expr {
                    sites_in_expression(e, Some(ret), table, current, visit);
                }
            }
            Statement::LoopBreak(_) => {}
        }
    }
    locals.pop();
}

/// Visit `expr`, which flows into a slot of type `expected` when known, and
/// every closure creation inside it.
fn sites_in_expression(
    expr: &Expression,
    expected: Option<&TypeName>,
    table: &Table,
    current: Option<&TypeName>,
    visit: &mut impl FnMut(&Expression, Option<&TypeName>, Option<&TypeName>),
) {
    // A function type may be partly known (a generic call's parameter
    // before every type argument is bound): its known parts still type the
    // closure.
    let known = |t: &TypeName| (!t.contains_auto() || t.is_function_type()).then(|| t.clone());
    visit(expr, expected.and_then(known).as_ref(), current);
    // The parameter types a call's arguments flow into.
    let params: Option<Vec<TypeName>> = match expr {
        Expression::FunctionCall { function, args, .. } => table.callables.get(function).cloned().or_else(|| {
            // A generic function called without type arguments: the
            // parameter types, with what the other arguments bind.
            table.generic_parameters(table.generics.get(function)?, args, current)
        }),
        Expression::MethodCall { this, method, args, .. } => table.type_of(this, current).and_then(|t| {
            let owner = t.to_string();
            table.methods.get(&owner).and_then(|m| m.get(method)).cloned().or_else(|| {
                let signature = table.generic_methods.get(&owner)?.get(method)?;
                table.generic_parameters(signature, args, current)
            })
        }),
        Expression::Invoke { callee, .. } => table.type_of(callee, current).map(|t| t.function_params().to_vec()),
        _ => None,
    };
    match expr {
        Expression::FunctionCall { args, .. } | Expression::MethodCall { args, .. } | Expression::Invoke { args, .. } => {
            if let Expression::MethodCall { this, .. } = expr {
                sites_in_expression(this, None, table, current, visit);
            }
            if let Expression::Invoke { callee, .. } = expr {
                sites_in_expression(callee, None, table, current, visit);
            }
            for (i, arg) in args.iter().enumerate() {
                let slot = params.as_ref().and_then(|p| p.get(i));
                sites_in_expression(arg, slot, table, current, visit);
            }
        }
        Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. } => {
            sites_in_expression(lhs, None, table, current, visit);
            let slot = table.type_of(lhs, current);
            sites_in_expression(rhs, slot.as_ref(), table, current, visit);
        }
        Expression::Ternary { condition, true_expr, false_expr } => {
            sites_in_expression(condition, None, table, current, visit);
            sites_in_expression(true_expr, expected, table, current, visit);
            sites_in_expression(false_expr, expected, table, current, visit);
        }
        _ => {
            // Other nodes pass no expected type down. `children_mut` needs
            // `&mut`, so walk a clone (closure sites are few and small).
            let mut copy = expr.clone();
            for child in children_mut(&mut copy) {
                sites_in_expression(child, None, table, current, visit);
            }
        }
    }
}

/// Apply `f` to every expression in the module, in place.
fn for_each_expression_mut(module: &mut Module, f: &mut impl FnMut(&mut Expression)) {
    for st in &mut module.structs {
        for field in &mut st.field_members {
            if let Some(default) = &mut field.default {
                crate::passes::walk_expression(default, f);
            }
        }
        for method in st.method_members.iter_mut().chain([&mut st.constructor, &mut st.destructor]) {
            for param in &mut method.parameters {
                if let Some(default) = &mut param.default {
                    crate::passes::walk_expression(default, f);
                }
            }
            crate::passes::walk_function(method, f);
        }
    }
    for function in &mut module.functions {
        for param in &mut function.parameters {
            if let Some(default) = &mut param.default {
                crate::passes::walk_expression(default, f);
            }
        }
        crate::passes::walk_function(function, f);
    }
    for ext in &mut module.extensions {
        for method in &mut ext.methods {
            crate::passes::walk_function(method, f);
        }
    }
    for var in &mut module.globals {
        crate::passes::walk_global(var, f);
    }
}
