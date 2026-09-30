//! Conversions between plain and thread-safe function types.
//!
//! A plain function type `(P...) => R` counts its references with plain
//! increments and may capture anything, so its values stay on one thread. A
//! `shared (P...) => R` counts atomically and holds only thread-safe state
//! (see `check_shared_types`). Wherever a function value flows into a typed
//! slot (variable initializer, assignment, argument, return), this pass
//! applies the one conversion allowed in each direction:
//!
//! - **To `shared`**, only a value that is thread-safe by construction: a
//!   named function (`FunctionRef`, no state at all), or a closure creation
//!   (`MakeClosure`: a closure literal, or a method, constructor or generic
//!   function reference) whose captured values are all thread-safe. The
//!   value is retyped to the slot's `shared` type, so its object counts
//!   atomically from the start. A capture that is not thread-safe is an
//!   error at its first use in the closure, with a note at the captured
//!   variable. Any other plain value (a variable, a call result) keeps its
//!   plain type, and `check_function_types` reports the mismatch.
//! - **From `shared` to plain** (same signature), always: the value is
//!   wrapped in a new plain closure that holds it and forwards calls to it
//!   (`(args) => inner(args)`). A plain slot steps the adapter's counts
//!   with plain increments, and the adapter holds one atomic reference to
//!   the shared object, like any struct holding a `shared_ptr` field. Using
//!   the shared object itself through plain steps would race with the
//!   threads that also hold it.
//!
//! A C function pointer slot (`extern (P...) => R`) takes a value that has
//! no object at all: a named function (`FunctionRef`), or a closure
//! creation that captures nothing (a closure literal, a static method or
//! an unbound method reference), whose `__call` is copied into a free
//! function. Either becomes that function's address, `FunctionPointer`,
//! typed with the slot's type. A closure that captures a value cannot
//! convert: C calls the function with its arguments alone.
//!
//! Runs once every type is final (after the last `resolve_resolvables` and
//! `synthesize_function_types`), before `check_function_types`, which then
//! sees matching types wherever a conversion applied. The adapters it adds
//! are complete structs; their capture is released by their destructor
//! here, since `release_field_refs` has already run.

use crate::model::*;
use crate::passes::check_function_types::canonical;
use crate::passes::check_shared_types::{ThreadSafeStructs, unsafe_part_in};
use crate::passes::closures::{THIS_FIELD, closure_name, closure_struct, field};
use crate::passes::function_references::RECEIVER_FIELD;
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;
use std::collections::HashMap;

/// The field of an adapter holding the `shared` value it forwards to.
const INNER_FIELD: &str = "__inner";

/// How a value reaches its slot, for messages.
#[derive(Clone, Copy)]
enum Site {
    Argument,
    Stored,
    Returned,
}

impl Site {
    fn verb(self) -> &'static str {
        match self {
            Site::Argument => "passed as",
            Site::Stored => "stored as",
            Site::Returned => "returned as",
        }
    }
}

/// Same parameter and return types, whether each side is `shared` or not.
fn same_signature(a: &TypeName, b: &TypeName) -> bool {
    canonical(&a.with_sharing(false)) == canonical(&b.with_sharing(false))
}

/// A type some passes carry as a flat name (`__function<void>`), parsed.
fn parsed(ty: &TypeName) -> TypeName {
    let s = ty.to_string();
    if ty.sub_types.is_empty() && s.contains('<') && s.ends_with('>') {
        crate::passes::gather_generics::parse_type_string(&s)
    } else {
        ty.clone()
    }
}

struct Converter {
    table: StructTable,
    safe: ThreadSafeStructs,
    /// Free function → parameter types.
    functions: HashMap<String, Vec<TypeName>>,
    /// Concrete struct → constructor parameter types.
    constructors: HashMap<String, Vec<TypeName>>,
    /// Concrete struct → method → parameter types.
    methods: HashMap<String, HashMap<String, Vec<TypeName>>>,
    /// Closure struct (by name and by type) → its capture fields.
    captures: HashMap<String, Vec<VariableDef>>,
    /// Closure struct (by name and by type) → its `__call` method.
    calls: HashMap<String, FunctionDef>,
    added: Vec<StructDef>,
    /// Free functions made from closures converted to C function pointers.
    added_functions: Vec<FunctionDef>,
}

impl Converter {
    /// `value` flows into a slot of type `expected`.
    fn convert(&mut self, value: &mut Expression, expected: &TypeName, current: Option<&TypeName>, site: Site) {
        let expected = parsed(expected);
        if expected.is_extern_function_type() {
            if let Expression::Ternary { true_expr, false_expr, .. } = value {
                self.convert(true_expr, &expected, current, site);
                self.convert(false_expr, &expected, current, site);
                return;
            }
            self.to_extern(value, &expected, site);
            return;
        }
        if !expected.is_function_type() {
            return;
        }
        // Each arm converts on its own.
        if let Expression::Ternary { true_expr, false_expr, .. } = value {
            self.convert(true_expr, &expected, current, site);
            self.convert(false_expr, &expected, current, site);
            return;
        }
        if expected.is_shared_function_type() {
            self.to_shared(value, &expected, site);
            return;
        }
        let Some(actual) = static_type::of(value, &self.table, current).map(|t| parsed(&t)) else { return };
        if actual.is_shared_function_type() && same_signature(&actual, &expected) {
            let loc = value.loc();
            let inner = std::mem::replace(value, Expression::PointerLiteral);
            *value = self.adapter(inner, &actual, &expected, loc);
        }
    }

    /// Retype a value that is thread-safe by construction to the `shared`
    /// function type `expected`, checking a closure's captures.
    fn to_shared(&mut self, value: &mut Expression, expected: &TypeName, site: Site) {
        match value {
            Expression::FunctionRef { ty, .. } if same_signature(&parsed(ty), expected) => {
                *ty = parsed(ty).with_sharing(true);
            }
            Expression::MakeClosure { closure, ty, loc, .. } if same_signature(&parsed(ty), expected) => {
                if !parsed(ty).is_shared_function_type() {
                    self.check_captures(closure, expected, *loc, site);
                }
                *ty = parsed(ty).with_sharing(true);
            }
            _ => {}
        }
    }

    /// Replace a value with no state (a named function, a closure that
    /// captures nothing) by the address of a function, typed as the C
    /// function pointer type `expected`. Any other value is left for
    /// `check_function_types` to report.
    fn to_extern(&mut self, value: &mut Expression, expected: &TypeName, site: Site) {
        let Some(signature) = expected.extern_as_function() else { return };
        let loc = value.loc();
        let function = match value {
            Expression::FunctionRef { function, ty, .. } if same_signature(&parsed(ty), &signature) => function.clone(),
            Expression::MakeClosure { closure, ty, loc, .. } if same_signature(&parsed(ty), &signature) => {
                if let Some(capture) = self.captures.get(closure.as_str()).and_then(|c| c.first()) {
                    let at = if capture.loc.is_none() { *loc } else { capture.loc };
                    let captured = match capture.name.as_str() {
                        RECEIVER_FIELD => "its receiver".to_string(),
                        THIS_FIELD => "'this'".to_string(),
                        name => format!("'{}'", name),
                    };
                    let what = if capture.name == RECEIVER_FIELD { "method value" } else { "closure" };
                    let message = format!(
                        "{} {} C function pointer type '{}' captures {}; a C function pointer cannot hold captured values",
                        what,
                        site.verb(),
                        expected.display(),
                        captured
                    );
                    let advice = "pass what the callback needs through the C function's context argument instead";
                    let declared = (!capture.type_loc.is_none()).then_some(capture.type_loc);
                    crate::errors::report(Diagnostic::error(message).at(at).with_note(advice, declared));
                    return;
                }
                let Some(call) = self.calls.get(closure.as_str()) else { return };
                // A free function: a `.` in the name would read as a method.
                let spelled: String = closure.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
                let name = format!("{}_c_function", spelled);
                if !self.added_functions.iter().any(|f| f.name == name) {
                    let mut function = call.clone();
                    function.name = name.clone();
                    function.parent = None;
                    function.is_static = false;
                    self.added_functions.push(function);
                }
                name
            }
            _ => return,
        };
        *value = Expression::Cast {
            expr: Box::new(Expression::FunctionPointer { owner: None, function, loc }),
            ty: expected.clone(),
            loc,
        };
    }

    /// Every value closure `closure` captures must be thread-safe.
    fn check_captures(&self, closure: &str, expected: &TypeName, closure_loc: Loc, site: Site) {
        let Some(fields) = self.captures.get(closure) else { return };
        for capture in fields {
            if unsafe_part_in(&capture.ty, &self.safe).is_none() {
                continue;
            }
            let at = if capture.loc.is_none() { closure_loc } else { capture.loc };
            let (what, captured) = match capture.name.as_str() {
                RECEIVER_FIELD => ("method value", "its receiver".to_string()),
                THIS_FIELD => ("closure", "'this'".to_string()),
                name => ("closure", format!("'{}'", name)),
            };
            let message = format!(
                "{} {} '{}' captures {} of type '{}', which is not thread-safe",
                what,
                site.verb(),
                expected.display(),
                captured,
                capture.ty.display()
            );
            let advice = "capture a thread-safe value instead, such as an 'Atomic<T>' or a '[Shared]' struct";
            let declared = (!capture.type_loc.is_none()).then_some(capture.type_loc);
            crate::errors::report(Diagnostic::error(message).at(at).with_note(advice, declared));
            return;
        }
    }

    /// A new plain closure of type `to` that holds `inner` (of the `shared`
    /// type `from`) and forwards every call to it.
    fn adapter(&mut self, inner: Expression, from: &TypeName, to: &TypeName, loc: Loc) -> Expression {
        let (base, ty) = closure_name(&[]);
        let mut parameters = vec![];
        let mut forwarded = vec![];
        for (i, param_ty) in to.function_params().iter().enumerate() {
            let name = format!("__arg{}", i);
            parameters.push(VariableDef { kind: Kind::Param, ..field(&name, param_ty.clone(), None, loc) });
            forwarded.push(Expression::SymbolRef { id: name, ty: param_ty.clone(), loc });
        }
        let ret = to.function_return().cloned().unwrap_or_else(TypeName::void);
        let callee = Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: INNER_FIELD.to_string(), loc };
        let call = Expression::Invoke { callee: Box::new(callee), args: forwarded };
        let body = Block {
            name: String::new(),
            items: vec![if ret.to_string() == crate::type_name::VOID {
                Statement::Expression(call)
            } else {
                Statement::Return(ReturnStatement { expr: Some(call), loc })
            }],
            attributes: vec![],
        };
        let captures = vec![field(INNER_FIELD, from.clone(), None, loc)];
        let mut st = closure_struct(&base, &ty, &[], captures, parameters, ret, body, loc);
        crate::struct_body::apply_synthesized(&mut st);
        if let Err(e) = crate::struct_body::finish(&mut st) {
            crate::errors::report(Diagnostic::error(e).at(loc));
            return inner;
        }
        // `release_field_refs` has run: release the held value here.
        if let Some(body) = st.method_members.iter_mut().find(|m| m.name == "__dtor").and_then(|d| d.body.as_mut()) {
            body.items.push(Statement::Expression(Expression::MethodCall {
                this: Box::new(Expression::MemberRef {
                    lhs: Box::new(Expression::ThisRef),
                    name: INNER_FIELD.to_string(),
                    loc: Loc::NONE,
                }),
                method: "__release".to_string(),
                args: vec![],
                loc: Loc::NONE,
            }));
        }
        self.added.push(st);
        Expression::MakeClosure {
            value: Box::new(Expression::FunctionCall { function: ty.to_string(), args: vec![inner], loc }),
            closure: ty.to_string(),
            ty: to.clone(),
            loc,
        }
    }

    fn arguments(&mut self, params: &[TypeName], args: &mut [Expression], current: Option<&TypeName>) {
        for (param, arg) in params.iter().zip(args.iter_mut()) {
            self.convert(arg, param, current, Site::Argument);
        }
    }

    fn expression(&mut self, expr: &mut Expression, current: Option<&TypeName>) {
        // Children first, so a nested call's arguments are converted before
        // the enclosing node reads their types.
        for child in crate::passes::children_mut(expr) {
            self.expression(child, current);
        }
        match expr {
            Expression::FunctionCall { function, args, .. } => {
                let params = self.functions.get(function.as_str()).or_else(|| self.constructors.get(function.as_str())).cloned();
                if let Some(params) = params {
                    self.arguments(&params, args, current);
                }
            }
            Expression::MethodCall { this, method, args, .. } => {
                let Some(receiver) = static_type::of(this, &self.table, current) else { return };
                let params = self.methods.get(&receiver.to_string()).and_then(|m| m.get(method.as_str())).cloned();
                if let Some(params) = params {
                    self.arguments(&params, args, current);
                }
            }
            Expression::Invoke { callee, args } => {
                if let Some(fn_ty) = static_type::of(callee, &self.table, current).map(|t| parsed(&t)).filter(|t| t.is_function_type()) {
                    let params = fn_ty.function_params().to_vec();
                    self.arguments(&params, args, current);
                }
            }
            Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. } => {
                if let Some(lhs_type) = static_type::of(lhs, &self.table, current) {
                    self.convert(rhs, &lhs_type, current, Site::Stored);
                }
            }
            _ => {}
        }
    }

    fn block(&mut self, block: &mut Block, returns: &TypeName, current: Option<&TypeName>) {
        for stmt in &mut block.items {
            match stmt {
                Statement::Expression(expr) => self.expression(expr, current),
                Statement::Block(inner) => self.block(inner, returns, current),
                Statement::Declaration(Declaration::Variable(var)) => {
                    let ty = var.ty.clone();
                    if let Some(default) = &mut var.default {
                        self.expression(default, current);
                        self.convert(default, &ty, current, Site::Stored);
                    }
                }
                Statement::Declaration(_) => {}
                Statement::Branch(branch) => {
                    self.expression(&mut branch.condition, current);
                    self.block(&mut branch.if_block, returns, current);
                    if let Some(else_block) = &mut branch.else_block {
                        self.block(else_block, returns, current);
                    }
                }
                Statement::While(wh) => {
                    self.expression(&mut wh.condition, current);
                    self.block(&mut wh.block, returns, current);
                }
                Statement::Return(ret) => {
                    if let Some(expr) = &mut ret.expr {
                        self.expression(expr, current);
                        self.convert(expr, returns, current, Site::Returned);
                    }
                }
                Statement::LoopBreak(_) => {}
            }
        }
    }

    fn function(&mut self, function: &mut FunctionDef, current: Option<&TypeName>) {
        if function.is_generic_func {
            return;
        }
        let returns = function.ty.clone();
        if let Some(body) = &mut function.body {
            self.block(body, &returns, current);
        }
    }
}

/// Whether C can pass or return a value of type `ty` directly: a number,
/// `bool`, a pointer, or another C function pointer.
fn is_c_type(ty: &TypeName) -> bool {
    let name = canonical(ty).to_string();
    crate::arithmetic::is_numeric_type(&name) || name.ends_with('*') || parsed(ty).is_extern_function_type()
}

/// The first part of a C function pointer type nested anywhere in `ty`
/// that C cannot pass, with the C function pointer type it is part of.
fn non_c_part(ty: &TypeName) -> Option<(TypeName, TypeName)> {
    let ty = parsed(ty);
    for sub in &ty.sub_types {
        if let Some(found) = non_c_part(sub) {
            return Some(found);
        }
    }
    if !ty.is_extern_function_type() {
        return None;
    }
    let ret = ty.function_return().filter(|r| r.to_string() != crate::type_name::VOID && !is_c_type(r));
    ret.into_iter().chain(ty.function_params().iter().filter(|p| !is_c_type(p))).next().map(|part| (part.clone(), ty.clone()))
}

/// Every local variable declared in `block`, nested blocks included.
fn locals(block: &Block, visit: &mut dyn FnMut(&VariableDef)) {
    for stmt in &block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) => visit(var),
            Statement::Block(inner) => locals(inner, visit),
            Statement::Branch(branch) => {
                locals(&branch.if_block, visit);
                if let Some(else_block) = &branch.else_block {
                    locals(else_block, visit);
                }
            }
            Statement::While(wh) => locals(&wh.block, visit),
            _ => {}
        }
    }
}

/// Report a C function pointer type, wherever a variable, field or
/// parameter declares one, whose signature has a type C cannot pass.
fn check_c_signatures(module: &Module) {
    let mut reported = false;
    let mut check = |var: &VariableDef| {
        if reported {
            return;
        }
        if let Some((part, whole)) = non_c_part(&var.ty) {
            let message = format!(
                "C function pointer type '{}' cannot use '{}'; C passes only numbers, 'bool' and pointers",
                whole.display(),
                part.display()
            );
            let at = if var.type_loc.is_none() { var.loc } else { var.type_loc };
            crate::errors::report(Diagnostic::error(message).at(at));
            reported = true;
        }
    };
    let function = |f: &FunctionDef, check: &mut dyn FnMut(&VariableDef)| {
        for param in &f.parameters {
            check(param);
        }
        if let Some(body) = &f.body {
            locals(body, check);
        }
    };
    for f in module.functions.iter().filter(|f| !f.is_generic_func) {
        function(f, &mut check);
    }
    for st in module.structs.iter().filter(|st| st.generic_params.is_empty()) {
        for field in &st.field_members {
            check(field);
        }
        for m in st.method_members.iter().chain([&st.constructor]) {
            function(m, &mut check);
        }
    }
    for e in &module.externs {
        for param in &e.parameters {
            check(param);
        }
    }
    for var in &module.globals {
        check(var);
    }
}

/// Apply the conversions between plain and `shared` function types (see
/// the module docs).
pub fn shared_functions(module: &mut Module) {
    check_c_signatures(module);
    let concrete = |st: &StructDef| !(st.ty.is_generic() && st.name == st.ty.name);
    let params = |f: &FunctionDef| -> Vec<TypeName> { f.parameters.iter().map(|p| p.ty.clone()).collect() };
    let mut captures = HashMap::new();
    let mut calls = HashMap::new();
    for st in module.structs.iter().filter(|st| crate::passes::closures::is_closure_struct(&st.name)) {
        if let Some(call) = st.method_members.iter().find(|m| m.name == crate::passes::closures::CALL_METHOD) {
            calls.insert(st.ty.to_string(), call.clone());
            calls.insert(st.name.clone(), call.clone());
        }
        let fields: Vec<VariableDef> = st
            .field_members
            .iter()
            .filter(|f| !f.name.starts_with("__") || f.name == THIS_FIELD || f.name == RECEIVER_FIELD)
            .cloned()
            .collect();
        captures.insert(st.ty.to_string(), fields.clone());
        captures.insert(st.name.clone(), fields);
    }
    let mut converter = Converter {
        table: StructTable::build(module),
        safe: ThreadSafeStructs::of(module),
        functions: module
            .functions
            .iter()
            .filter(|f| !f.is_generic_func)
            .map(|f| (f.name.clone(), params(f)))
            .chain(module.externs.iter().map(|e| (e.name.clone(), e.parameters.iter().map(|p| p.ty.clone()).collect())))
            .collect(),
        constructors: module
            .structs
            .iter()
            .filter(|st| concrete(st))
            .map(|st| (st.name.clone(), params(&st.constructor)))
            .collect(),
        methods: module
            .structs
            .iter()
            .filter(|st| concrete(st))
            .map(|st| (st.name.clone(), st.method_members.iter().map(|m| (m.name.clone(), params(m))).collect()))
            .collect(),
        captures,
        calls,
        added: vec![],
        added_functions: vec![],
    };
    for function in &mut module.functions {
        converter.function(function, None);
    }
    for st in &mut module.structs {
        if !concrete(st) || st.ty.is_function_type() || st.ty.is_weak() {
            continue;
        }
        let current = st.ty.clone();
        converter.function(&mut st.constructor, Some(&current));
        for method in &mut st.method_members {
            converter.function(method, Some(&current));
        }
    }
    for var in &mut module.globals {
        let ty = var.ty.clone();
        if let Some(default) = &mut var.default {
            converter.expression(default, None);
            converter.convert(default, &ty, None, Site::Stored);
        }
    }
    module.structs.extend(converter.added);
    module.functions.extend(converter.added_functions);
}
