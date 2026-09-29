//! Signature checks for function values. Codegen passes every function value
//! as an opaque pointer and calls through it with the signature of the static
//! type, so a mismatch that reached codegen would call a function with the
//! wrong arguments. This pass rejects, wherever a function value flows into a
//! typed slot (variable initializer, assignment, argument, return), a value
//! whose function type differs from the slot's.

use crate::model::*;
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;

/// Canonical spelling of a type for comparison: primitive aliases collapse
/// (`int` and `i32` are one type), recursively through generic arguments.
/// Types some passes carry as a flat string (`__function<int, int>` as a
/// bare name) are re-parsed first.
fn canonical(ty: &TypeName) -> TypeName {
    let ty = &crate::passes::gather_generics::parse_type_string(&ty.to_string());
    // `__ptr<T>` and `T*` are one type.
    if ty.name == "__ptr" && ty.sub_types.len() == 1 {
        return TypeName::new(&format!("{}*", canonical(&ty.sub_types[0])));
    }
    if let Some(pointee) = ty.name.strip_suffix('*') {
        if ty.sub_types.is_empty() {
            return TypeName::new(&format!("{}*", canonical(&TypeName::new(pointee))));
        }
    }
    let name = match ty.name.as_str() {
        "int" => "i32",
        "uint" => "u32",
        "long" => "i64",
        "ulong" => "u64",
        "short" => "i16",
        "ushort" => "u16",
        "char" => "i8",
        "byte" => "u8",
        "float" => "f32",
        "double" => "f64",
        other => other,
    };
    TypeName::with_args(name, ty.sub_types.iter().map(canonical).collect())
}

fn same_type(a: &TypeName, b: &TypeName) -> bool {
    canonical(a) == canonical(b)
}

/// Where a value flows: names the slot in a message, and locates the error
/// when the value itself has no location (a literal).
struct Slot<'s> {
    what: &'s dyn Fn() -> String,
    /// The message for a value of type `.1` where `.0` is expected.
    mismatch: &'s dyn Fn(&str, &str) -> String,
    fallback: Loc,
}

#[derive(Clone, Copy)]
enum Kind {
    Numeric,
    Struct,
}

struct Checker<'a> {
    module: &'a Module,
    table: StructTable,
    errors: Vec<Diagnostic>,
    /// The generic parameter names of the base being checked through a
    /// specialization. Specialized bodies may keep a parameter's spelling
    /// (`T`) in annotations, which says nothing about the type, even when a
    /// user struct happens to have that name.
    unbound: Vec<String>,
}

impl<'a> Checker<'a> {
    fn report(&mut self, message: String, value: &Expression, slot: &Slot) {
        let at = if value.loc().is_none() { slot.fallback } else { value.loc() };
        let diagnostic = Diagnostic::error(message).at(at);
        if !self.errors.iter().any(|d| d.message == diagnostic.message && d.loc == diagnostic.loc) {
            self.errors.push(diagnostic);
        }
    }

    /// What a type certainly is, or `None` when unknown here (unresolved,
    /// a generic parameter, a pointer, a function).
    fn kind_of(&self, ty: &TypeName) -> Option<Kind> {
        let name = ty.to_string();
        if name == crate::type_name::AUTO || name.is_empty() || ty.is_function_type() || name.ends_with('*') {
            return None;
        }
        if self.unbound.iter().any(|p| *p == ty.name) {
            return None;
        }
        if crate::arithmetic::is_numeric_type(&canonical(ty).to_string()) {
            return Some(Kind::Numeric);
        }
        self.module.structs.iter().any(|s| s.name == name).then_some(Kind::Struct)
    }

    /// A non-function `value` flowing into a non-function slot: numbers
    /// convert among themselves, but a number is never a struct, and one
    /// struct is never another.
    fn value_flows_into(&mut self, value: &Expression, expected: &TypeName, current: Option<&TypeName>, slot: &Slot) {
        // Raw buffer reads (`Data[i]`) carry no reliable static type.
        if matches!(value, Expression::PointerLiteral | Expression::Default(_) | Expression::ArrayIndex { .. } | Expression::Index { .. }) {
            return;
        }
        let Some(expected_kind) = self.kind_of(expected) else { return };
        let Some(actual) = static_type::of(value, &self.table, current) else { return };
        let Some(actual_kind) = self.kind_of(&actual) else { return };
        let mismatch = match (expected_kind, actual_kind) {
            (Kind::Numeric, Kind::Numeric) => false,
            // Different structs; type arguments are not compared, since
            // defaults (`Result<None>` is `Result<None, Error>`) and
            // aliases may spell one specialization two ways.
            (Kind::Struct, Kind::Struct) => canonical(expected).name != canonical(&actual).name,
            _ => true,
        };
        if mismatch {
            let message = (slot.mismatch)(&expected.display(), &actual.display());
            self.report(message, value, slot);
        }
    }

    /// `value` flows into a slot of type `expected`.
    fn flows_into(&mut self, value: &Expression, expected: &TypeName, current: Option<&TypeName>, slot: &Slot) {
        if !expected.is_function_type() {
            self.value_flows_into(value, expected, current, slot);
            return;
        }
        if matches!(value, Expression::PointerLiteral) {
            return;
        }
        let Some(actual) = static_type::of(value, &self.table, current) else {
            return;
        };
        let actual = crate::passes::gather_generics::parse_type_string(&actual.to_string());
        if !actual.is_function_type() {
            // Only a value whose type is certainly not a function is an
            // error: unsubstituted generic parameters and unresolved types
            // are left to codegen.
            let known = actual.is_integral() || self.module.structs.iter().any(|s| s.name == actual.to_string());
            if !known || actual.to_string() == crate::type_name::AUTO || actual.is_pointer() {
                return;
            }
            let message = format!("{} expects a function of type '{}', but was given a value of type '{}'", (slot.what)(), expected.display(), actual.display());
            self.report(message, value, slot);
        } else if !same_type(&actual, expected) {
            let message = format!("{} expects a function of type '{}', but was given a function of type '{}'", (slot.what)(), expected.display(), actual.display());
            self.report(message, value, slot);
        }
    }

    fn parameters_of_call(&self, function: &str) -> Option<(String, Vec<TypeName>)> {
        if let Some(f) = self.module.functions.iter().find(|f| f.name == function && !f.is_generic_func) {
            return Some((format!("argument {{}} of '{}'", function), f.parameters.iter().map(|p| p.ty.clone()).collect()));
        }
        let st = self.module.structs.iter().find(|s| s.name == function)?;
        Some((format!("argument {{}} of '{}'", function), st.constructor.parameters.iter().map(|p| p.ty.clone()).collect()))
    }

    fn parameters_of_method(&self, this_type: &TypeName, method: &str) -> Option<Vec<TypeName>> {
        let key = this_type.to_string();
        let st = self.module.structs.iter().find(|s| s.name == key)?;
        let m = st.method_members.iter().find(|m| m.name == method)?;
        Some(m.parameters.iter().map(|p| p.ty.clone()).collect())
    }

    fn check_arguments(&mut self, label: &str, params: &[TypeName], args: &[Expression], current: Option<&TypeName>, call: Loc) {
        for (idx, (param, arg)) in params.iter().zip(args).enumerate() {
            let what = || label.replace("{}", &(idx + 1).to_string());
            let mismatch = |expected: &str, actual: &str| format!("cannot pass a value of type '{}' as {}, which has type '{}'", actual, what(), expected);
            self.flows_into(arg, param, current, &Slot { what: &what, mismatch: &mismatch, fallback: call });
        }
    }

    fn expression(&mut self, expr: &Expression, current: Option<&TypeName>) {
        let mut copy = expr.clone();
        let mut nodes: Vec<Expression> = vec![];
        crate::passes::walk_expression(&mut copy, &mut |e: &mut Expression| {
            if matches!(e, Expression::FunctionCall { .. } | Expression::MethodCall { .. } | Expression::Invoke { .. } | Expression::Binary { op: BinaryOp::Assign, .. }) {
                nodes.push(e.clone());
            }
        });
        for node in nodes {
            match &node {
                Expression::FunctionCall { function, args, loc } => {
                    if let Some((label, params)) = self.parameters_of_call(function) {
                        self.check_arguments(&label, &params, args, current, *loc);
                    }
                }
                Expression::MethodCall { this, method, args, loc } => {
                    if let Some(this_type) = static_type::of(this, &self.table, current) {
                        if let Some(params) = self.parameters_of_method(&this_type, method) {
                            let label = format!("argument {{}} of '{}'", method);
                            self.check_arguments(&label, &params, args, current, *loc);
                        }
                    }
                }
                Expression::Invoke { callee, args } => {
                    if let Some(fn_ty) = static_type::of(callee, &self.table, current).filter(|t| t.is_function_type()) {
                        if args.len() != fn_ty.function_params().len() {
                            let message = format!(
                                "a function of type '{}' takes {} argument(s), but {} were given",
                                fn_ty.display(),
                                fn_ty.function_params().len(),
                                args.len()
                            );
                            let what = String::new;
                            let mismatch = |_: &str, _: &str| String::new();
                            self.report(message, callee, &Slot { what: &what, mismatch: &mismatch, fallback: callee.loc() });
                        } else {
                            let label = format!("argument {{}} of a call through '{}'", fn_ty.display());
                            self.check_arguments(&label, fn_ty.function_params(), args, current, callee.loc());
                        }
                    }
                }
                Expression::Binary { op: BinaryOp::Assign, lhs, rhs, loc } => {
                    // A raw buffer slot (`Data[i] = v`) has no reliable
                    // static type.
                    let raw_slot = matches!(**lhs, Expression::Index { .. } | Expression::ArrayIndex { .. });
                    if let Some(lhs_type) = static_type::of(lhs, &self.table, current).filter(|t| !raw_slot || t.is_function_type()) {
                        let mismatch = |expected: &str, actual: &str| format!("cannot assign a value of type '{}' to a variable of type '{}'", actual, expected);
                        self.flows_into(rhs, &lhs_type, current, &Slot { what: &|| "assignment".to_string(), mismatch: &mismatch, fallback: *loc });
                    }
                }
                _ => {}
            }
        }
    }

    fn block(&mut self, block: &Block, function: &FunctionDef, current: Option<&TypeName>) {
        for stmt in &block.items {
            match stmt {
                Statement::Expression(expr) => self.expression(expr, current),
                Statement::Block(inner) => self.block(inner, function, current),
                // A ctor's synthesized `this` is initialized from the raw
                // allocation.
                Statement::Declaration(Declaration::Variable(var)) if var.name == "this" => {}
                Statement::Declaration(Declaration::Variable(var)) => {
                    if let Some(default) = &var.default {
                        self.expression(default, current);
                        self.variable(var, default, current);
                    }
                }
                Statement::Declaration(_) => {}
                Statement::Branch(branch) => {
                    self.expression(&branch.condition, current);
                    self.block(&branch.if_block, function, current);
                    if let Some(else_block) = &branch.else_block {
                        self.block(else_block, function, current);
                    }
                }
                Statement::While(wh) => {
                    self.expression(&wh.condition, current);
                    self.block(&wh.block, function, current);
                }
                Statement::Return(ret) => {
                    if let Some(expr) = &ret.expr {
                        self.expression(expr, current);
                        let name = function.name.clone();
                        let what = || format!("the return value of '{}'", name);
                        let mismatch = |expected: &str, actual: &str| format!("cannot return a value of type '{}' from '{}', which returns '{}'", actual, name, expected);
                        self.flows_into(expr, &function.ty, current, &Slot { what: &what, mismatch: &mismatch, fallback: ret.loc });
                    } else if function.ty.to_string() != crate::type_name::VOID && !ret.loc.is_none() {
                        let message = format!("non-void function '{}' should return a value", function.name);
                        if !self.errors.iter().any(|d| d.message == message && d.loc == Some(ret.loc)) {
                            self.errors.push(Diagnostic::error(message).at(ret.loc));
                        }
                    }
                }
                Statement::LoopBreak(_) => {}
            }
        }
    }

    /// A variable's initializer flows into the variable.
    fn variable(&mut self, var: &VariableDef, default: &Expression, current: Option<&TypeName>) {
        let name = var.name.clone();
        let what = || format!("variable '{}'", name);
        let mismatch = |expected: &str, actual: &str| format!("cannot initialize variable '{}' of type '{}' with a value of type '{}'", name, expected, actual);
        let fallback = if var.type_loc.is_none() { var.loc } else { var.type_loc };
        self.flows_into(default, &var.ty, current, &Slot { what: &what, mismatch: &mismatch, fallback });
    }

    fn function(&mut self, function: &FunctionDef, current: Option<&TypeName>) {
        if function.is_generic_func {
            return;
        }
        if let Some(body) = &function.body {
            self.block(body, function, current);
        }
    }
}

/// Reject values whose type does not match the typed slot they flow into.
/// Runs as the last transform pass (so the language server reports it too).
pub fn check_function_types(module: &mut Module) {
    let module = &*module;
    let mut checker = Checker { module, table: StructTable::build(module), errors: vec![], unbound: vec![] };
    // The parameter names of the generic base a specialization came from.
    let base_params = |name: &str, is_struct: bool| -> Vec<String> {
        let base = name.split('<').next().unwrap_or(name);
        if base == name {
            return vec![];
        }
        let params: Vec<&crate::model::GenericParam> = if is_struct {
            module.structs.iter().filter(|b| b.ty.name == base).flat_map(|b| b.generic_params.iter()).collect()
        } else {
            module.functions.iter().filter(|f| f.name == base).flat_map(|f| f.generic_params.iter()).collect()
        };
        params.into_iter().map(|p| p.name.clone()).collect()
    };
    for function in &module.functions {
        checker.unbound = base_params(&function.name, false);
        checker.function(function, None);
    }
    for st in &module.structs {
        // Generic bases are checked through their specializations; the
        // synthesized function-type structs hold no user code.
        if (st.ty.is_generic() && st.name == st.ty.name) || st.ty.is_function_type() {
            continue;
        }
        let current = st.ty.clone();
        checker.unbound = base_params(&st.name, true);
        checker.function(&st.constructor, Some(&current));
        for method in &st.method_members {
            checker.function(method, Some(&current));
        }
    }
    checker.unbound = vec![];
    for var in &module.globals {
        if let Some(default) = &var.default {
            checker.variable(var, default, None);
        }
    }
    for error in checker.errors {
        crate::errors::report(error);
    }
}
