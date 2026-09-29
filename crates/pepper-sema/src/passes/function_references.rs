//! Methods, constructors and generic functions used as values.
//!
//! Each form becomes a closure (see `closures`) whose `__call` forwards to
//! what it names:
//!
//! | Source | Function type | Forwards to |
//! |---|---|---|
//! | `p.norm` (bound method) | `(P...) => R` | `this.__receiver.norm(...)`, `__receiver` = `p` |
//! | `Point.norm` (unbound method) | `(Point, P...) => R` | `self.norm(...)` |
//! | `Point`, `Box<int>` (constructor) | `(P...) => Point` | `Point(...)` |
//! | `identity<int>` (generic function) | `(P...) => R` | `identity<int>(...)` |
//!
//! Which form an expression is depends on its types (whether `p.norm` is a
//! field or a method), so [`reference_functions`] runs once every type is
//! known and every generic is specialized, just before `release_field_refs`.
//! The structs it adds are complete, like the ones `function_types`
//! synthesizes: their constructor and destructor bodies come from
//! `struct_body`, and `release_field_refs` releases the captured receiver.
//!
//! A bound method captures its receiver by value, exactly like a closure
//! literal: `p.norm` is `() => p.norm()` evaluated once, so storing a bound
//! method of `this` in a field of `this` is the same reference cycle, and
//! the same error.

use crate::model::*;
use crate::passes::closures::{closure_name, closure_struct, field};
use crate::static_type::StructTable;
use crate::type_name::TypeName;
use std::collections::HashMap;

/// The field holding a bound method's receiver.
pub const RECEIVER_FIELD: &str = "__receiver";

/// A callable's signature, with its parameter names.
#[derive(Clone)]
struct Signature {
    params: Vec<(String, TypeName)>,
    ret: TypeName,
    is_static: bool,
    /// Whether a call must pass at least one argument (a parameter without
    /// a default), so a zero-argument "call" can only be a reference.
    requires_arguments: bool,
}

impl Signature {
    fn of(function: &FunctionDef) -> Self {
        Signature {
            params: function
                .parameters
                .iter()
                .map(|p| (p.name.trim_start_matches("this.").to_string(), p.ty.clone()))
                .collect(),
            ret: function.ty.clone(),
            is_static: function.is_static,
            requires_arguments: function.parameters.iter().any(|p| p.default.is_none()),
        }
    }
}

/// What the module declares, by concrete type string.
struct Declared {
    /// Struct or trait type → method name → signature.
    methods: HashMap<String, HashMap<String, Signature>>,
    /// Struct type → field names.
    fields: HashMap<String, Vec<String>>,
    /// Struct type → constructor signature (returning the struct).
    constructors: HashMap<String, Signature>,
    /// Non-generic struct name → its type, for a bare `Point`.
    plain_structs: HashMap<String, TypeName>,
    /// Specialized generic function (`identity<int>`) → signature.
    generic_functions: HashMap<String, Signature>,
    statics: StructTable,
}

impl Declared {
    fn build(module: &Module) -> Self {
        let mut methods: HashMap<String, HashMap<String, Signature>> = HashMap::new();
        let mut fields = HashMap::new();
        let mut constructors = HashMap::new();
        let mut plain_structs = HashMap::new();
        for st in module.structs.iter().filter(|s| s.generic_params.is_empty()) {
            let key = st.ty.to_string();
            let own = methods.entry(key.clone()).or_default();
            for m in st.method_members.iter().filter(|m| !m.name.starts_with("__")) {
                own.entry(m.name.clone()).or_insert_with(|| Signature::of(m));
            }
            fields.insert(key.clone(), st.field_members.iter().map(|f| f.name.clone()).collect());
            let mut ctor = Signature::of(&st.constructor);
            ctor.ret = st.ty.clone();
            // `this.x` parameters take their field's type.
            for (name, ty) in &mut ctor.params {
                if ty.contains_auto() || ty.is_empty() {
                    if let Some(f) = st.field_members.iter().find(|f| f.name == *name) {
                        *ty = f.ty.clone();
                    }
                }
            }
            constructors.insert(key.clone(), ctor);
            if !st.name.starts_with("__") && !key.contains('<') {
                plain_structs.insert(st.name.clone(), st.ty.clone());
            }
        }
        for ty in crate::traits::used_trait_types(module) {
            if let Some(def) = crate::traits::trait_def(&module.traits, &ty) {
                let instance = crate::traits::instance(def, &ty);
                methods
                    .entry(ty.to_string())
                    .or_insert_with(|| instance.methods.iter().map(|m| (m.name.clone(), Signature::of(m))).collect());
            }
        }
        let generic_functions = module
            .functions
            .iter()
            .filter(|f| !f.is_generic_func && f.name.contains('<') && f.body.is_some())
            .map(|f| (f.name.clone(), Signature::of(f)))
            .collect();
        Declared { methods, fields, constructors, plain_structs, generic_functions, statics: StructTable::build(module) }
    }

    fn method(&self, owner: &TypeName, name: &str) -> Option<&Signature> {
        self.methods.get(owner.to_string().trim_end_matches('*'))?.get(name)
    }

    fn has_field(&self, owner: &TypeName, name: &str) -> bool {
        self.fields.get(owner.to_string().trim_end_matches('*')).is_some_and(|f| f.iter().any(|n| n == name))
    }

    /// The struct a type-name expression names: a bare `Point` that is not
    /// a variable, or a generic `Box<int>` (the zero-argument call the
    /// builder makes of a type in value position).
    fn named_struct(&self, expr: &Expression) -> Option<TypeName> {
        match expr {
            Expression::SymbolRef { id, .. } => self.plain_structs.get(id).cloned(),
            Expression::FunctionCall { function, args, .. } if args.is_empty() && function.contains('<') => {
                self.constructors.contains_key(function).then(|| crate::passes::gather_generics::parse_type_string(function))
            }
            _ => None,
        }
    }
}

/// What a reference forwards to.
enum Target {
    /// `receiver.method(...)`, with the receiver captured.
    Bound { receiver: Expression, receiver_ty: TypeName, method: String },
    /// `self.method(...)`, the receiver being the first parameter; or
    /// `Type.method(...)` for a static method.
    Unbound { owner: TypeName, method: String },
    /// `function(...)`: a constructor or a generic function specialization.
    Call { function: String },
}

/// Turn every method, constructor and generic function reference into a
/// closure (see the module docs).
pub fn reference_functions(module: &mut Module) {
    let declared = Declared::build(module);
    let mut added = vec![];
    {
        let mut replacer = Replacer { declared: &declared, added: &mut added, current: None, retyped: HashMap::new(), locals: vec![] };
        for st in module.structs.iter_mut().filter(|s| s.generic_params.is_empty()) {
            replacer.current = Some(st.ty.clone());
            for field in &mut st.field_members {
                if let Some(default) = &mut field.default {
                    replacer.expression(default, false);
                }
            }
            for method in st.method_members.iter_mut().chain([&mut st.constructor, &mut st.destructor]) {
                replacer.function(method);
            }
        }
        replacer.current = None;
        for function in module.functions.iter_mut().filter(|f| !f.is_generic_func) {
            replacer.function(function);
        }
        for var in &mut module.globals {
            if let Some(default) = &mut var.default {
                replacer.expression(default, false);
            }
        }
    }
    module.structs.extend(added);
}

struct Replacer<'a> {
    declared: &'a Declared,
    added: &'a mut Vec<StructDef>,
    current: Option<TypeName>,
    /// Locals of the current function retyped as function values.
    retyped: HashMap<String, TypeName>,
    /// Names of the locals and parameters in scope, which shadow a struct
    /// of the same name.
    locals: Vec<Vec<String>>,
}

impl Replacer<'_> {
    fn function(&mut self, function: &mut FunctionDef) {
        for param in &mut function.parameters {
            if let Some(default) = &mut param.default {
                self.expression(default, false);
            }
        }
        if let Some(body) = &mut function.body {
            self.retyped.clear();
            self.locals = vec![function.parameters.iter().map(|p| p.name.clone()).collect()];
            self.block(body);
            self.locals.clear();
            // A local whose type was inferred from what is now a function
            // value (`var f = Point;` was typed `Point`) takes the new type,
            // and so does every use of it.
            if !self.retyped.is_empty() {
                let retyped = std::mem::take(&mut self.retyped);
                crate::passes::walk_block(body, &mut |e| {
                    if let Expression::SymbolRef { id, ty, .. } = e {
                        if let Some(new) = retyped.get(id.as_str()) {
                            *ty = new.clone();
                        }
                    }
                });
            }
        }
    }

    fn block(&mut self, block: &mut Block) {
        self.locals.push(vec![]);
        self.block_items(block);
        self.locals.pop();
    }

    fn block_items(&mut self, block: &mut Block) {
        for stmt in &mut block.items {
            match stmt {
                Statement::Expression(e) => self.expression(e, false),
                Statement::Block(b) => self.block(b),
                Statement::Declaration(Declaration::Variable(var)) => {
                    if let Some(default) = &mut var.default {
                        let was_reference = matches!(default, Expression::MakeClosure { .. });
                        self.expression(default, false);
                        if let Expression::MakeClosure { ty, .. } = default {
                            if !was_reference && var.type_loc == Loc::NONE && var.ty != *ty {
                                var.ty = ty.clone();
                                self.retyped.insert(var.name.clone(), ty.clone());
                            }
                        }
                    }
                    if let Some(scope) = self.locals.last_mut() {
                        scope.push(var.name.clone());
                    }
                }
                Statement::Declaration(_) => {}
                Statement::Branch(branch) => {
                    self.expression(&mut branch.condition, false);
                    self.block(&mut branch.if_block);
                    if let Some(else_block) = &mut branch.else_block {
                        self.block(else_block);
                    }
                }
                Statement::While(wh) => {
                    self.expression(&mut wh.condition, false);
                    self.block(&mut wh.block);
                }
                Statement::Return(r) => {
                    if let Some(e) = &mut r.expr {
                        self.expression(e, false);
                    }
                }
                Statement::LoopBreak(_) => {}
            }
        }
    }

    /// The struct `expr` names, unless a local of that name shadows it.
    fn named_struct(&self, expr: &Expression) -> Option<TypeName> {
        if let Expression::SymbolRef { id, .. } = expr {
            if self.locals.iter().flatten().any(|l| l == id) {
                return None;
            }
        }
        self.declared.named_struct(expr)
    }

    /// `receiver`: `expr` is the left side of a member access or method
    /// call, where a type name is the type itself, not its constructor.
    fn expression(&mut self, expr: &mut Expression, receiver: bool) {
        match expr {
            Expression::MemberRef { lhs, name, loc } => {
                let (name, loc) = (name.clone(), *loc);
                if let Some(owner) = self.named_struct(lhs) {
                    if self.declared.method(&owner, &name).is_some() {
                        self.replace(expr, Target::Unbound { owner, method: name }, loc);
                    }
                    return;
                }
                self.expression(lhs, true);
                let Some(receiver_ty) = crate::static_type::of(lhs, &self.declared.statics, self.current.as_ref()) else { return };
                if receiver_ty.contains_auto() || self.declared.has_field(&receiver_ty, &name) {
                    return;
                }
                let Some(signature) = self.declared.method(&receiver_ty, &name) else { return };
                if signature.is_static {
                    return;
                }
                let Expression::MemberRef { lhs, .. } = std::mem::replace(expr, Expression::PointerLiteral) else { unreachable!() };
                self.replace(expr, Target::Bound { receiver: *lhs, receiver_ty, method: name }, loc);
                return;
            }
            Expression::MethodCall { this, args, .. } => {
                self.expression(this, true);
                for arg in args {
                    self.expression(arg, false);
                }
                return;
            }
            Expression::SymbolRef { loc, .. } if !receiver => {
                let loc = *loc;
                if let Some(owner) = self.named_struct(expr) {
                    self.replace(expr, Target::Call { function: owner.to_string() }, loc);
                }
                return;
            }
            Expression::FunctionCall { function, args, loc } if args.is_empty() && !receiver => {
                let (function, loc) = (function.clone(), *loc);
                let takes_arguments = |s: Option<&Signature>| s.is_some_and(|s| s.requires_arguments);
                if takes_arguments(self.declared.generic_functions.get(&function))
                    || (function.contains('<') && takes_arguments(self.declared.constructors.get(&function)))
                {
                    self.replace(expr, Target::Call { function }, loc);
                }
                return;
            }
            _ => {}
        }
        for child in crate::passes::children_mut(expr) {
            self.expression(child, false);
        }
        if let Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. } = expr {
            check_this_cycle(lhs, rhs);
        }
    }

    /// Replace `expr` with a closure forwarding to `target`.
    fn replace(&mut self, expr: &mut Expression, target: Target, loc: Loc) {
        let signature = match &target {
            Target::Bound { receiver_ty, method, .. } => self.declared.method(receiver_ty, method),
            Target::Unbound { owner, method } => self.declared.method(owner, method),
            Target::Call { function } => {
                self.declared.generic_functions.get(function).or_else(|| self.declared.constructors.get(function))
            }
        };
        let Some(signature) = signature.cloned() else { return };
        let (base, ty) = closure_name(&[]);

        let param = |name: &str, ty: &TypeName| VariableDef { kind: Kind::Param, ..field(name, ty.clone(), None, loc) };
        let symbol = |name: &str, ty: &TypeName| Expression::SymbolRef { id: name.to_string(), ty: ty.clone(), loc };
        // `__call`'s parameters are the target's, renamed so none can clash
        // with `self`.
        let mut parameters = vec![];
        let mut forwarded = vec![];
        for (i, (_, ty)) in signature.params.iter().enumerate() {
            let name = format!("__arg{}", i);
            parameters.push(param(&name, ty));
            forwarded.push(symbol(&name, ty));
        }
        let mut captures = vec![];
        let mut args = vec![];
        let call = match target {
            Target::Bound { receiver, receiver_ty, method } => {
                captures.push(field(RECEIVER_FIELD, receiver_ty, None, loc));
                args.push(receiver);
                let this = Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: RECEIVER_FIELD.to_string(), loc };
                Expression::MethodCall { this: Box::new(this), method, args: forwarded, loc }
            }
            Target::Unbound { owner, method } if signature.is_static => {
                let this = Expression::SymbolRef { id: owner.to_string(), ty: TypeName::auto(), loc };
                Expression::MethodCall { this: Box::new(this), method, args: forwarded, loc }
            }
            Target::Unbound { owner, method } => {
                parameters.insert(0, param("self", &owner));
                Expression::MethodCall { this: Box::new(symbol("self", &owner)), method, args: forwarded, loc }
            }
            Target::Call { function } => Expression::FunctionCall { function, args: forwarded, loc },
        };
        let body = Block {
            name: String::new(),
            items: vec![if signature.ret.to_string() == crate::type_name::VOID {
                Statement::Expression(call)
            } else {
                Statement::Return(ReturnStatement { expr: Some(call), loc })
            }],
            attributes: vec![],
        };
        let function_type = TypeName::function_type(signature.ret.clone(), parameters.iter().map(|p| p.ty.clone()).collect());
        let mut st = closure_struct(&base, &ty, &[], captures, parameters, signature.ret, body, loc);
        crate::struct_body::apply_synthesized(&mut st);
        if let Err(e) = crate::struct_body::finish(&mut st) {
            crate::errors::report(Diagnostic::error(e).at(loc));
            return;
        }
        self.added.push(st);
        *expr = Expression::MakeClosure {
            value: Box::new(Expression::FunctionCall { function: ty.to_string(), args, loc }),
            closure: ty.to_string(),
            ty: function_type,
            loc,
        };
    }
}

/// `this.f = this.m` in a method: the object would hold the bound method
/// and the bound method the object.
fn check_this_cycle(lhs: &Expression, rhs: &Expression) {
    let Expression::MemberRef { lhs: owner, name: field, loc } = lhs else { return };
    if !matches!(owner.as_ref(), Expression::ThisRef) {
        return;
    }
    let Expression::MakeClosure { value, loc: closure_loc, .. } = rhs else { return };
    let Expression::FunctionCall { args, .. } = value.as_ref() else { return };
    if matches!(args.as_slice(), [Expression::ThisRef]) {
        crate::errors::report(
            Diagnostic::error(format!(
                "storing a method of 'this' in field '{}' of 'this' creates a reference cycle that is never freed",
                field
            ))
            .at(*loc)
            .with_note("the method value captures 'this' here; capture a 'Weak' reference to it in a closure instead", Some(*closure_loc)),
        );
    }
}
