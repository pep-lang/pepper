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

struct Checker<'a> {
    module: &'a Module,
    table: StructTable,
    errors: Vec<String>,
}

impl<'a> Checker<'a> {
    /// `value` flows into a slot of type `expected` (described by `what`).
    fn flows_into(&mut self, value: &Expression, expected: &TypeName, current: Option<&TypeName>, what: &dyn Fn() -> String) {
        if !expected.is_function_type() {
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
            self.errors.push(format!("{} expects a function of type {}, but was given a value of type {}", what(), expected.display(), actual.display()));
        } else if !same_type(&actual, expected) {
            self.errors.push(format!("{} expects a function of type {}, but was given a function of type {}", what(), expected.display(), actual.display()));
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

    fn check_arguments(&mut self, label: &str, params: &[TypeName], args: &[Expression], current: Option<&TypeName>) {
        for (idx, (param, arg)) in params.iter().zip(args).enumerate() {
            let what = || label.replace("{}", &(idx + 1).to_string());
            self.flows_into(arg, param, current, &what);
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
                Expression::FunctionCall { function, args, .. } => {
                    if let Some((label, params)) = self.parameters_of_call(function) {
                        self.check_arguments(&label, &params, args, current);
                    }
                }
                Expression::MethodCall { this, method, args, .. } => {
                    if let Some(this_type) = static_type::of(this, &self.table, current) {
                        if let Some(params) = self.parameters_of_method(&this_type, method) {
                            let label = format!("argument {{}} of '{}'", method);
                            self.check_arguments(&label, &params, args, current);
                        }
                    }
                }
                Expression::Invoke { callee, args } => {
                    if let Some(fn_ty) = static_type::of(callee, &self.table, current).filter(|t| t.is_function_type()) {
                        if args.len() != fn_ty.function_params().len() {
                            self.errors.push(format!(
                                "a function of type {} takes {} argument(s), but {} were given",
                                fn_ty.display(),
                                fn_ty.function_params().len(),
                                args.len()
                            ));
                        } else {
                            let label = format!("argument {{}} of a call through {}", fn_ty.display());
                            self.check_arguments(&label, fn_ty.function_params(), args, current);
                        }
                    }
                }
                Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. } => {
                    if let Some(lhs_type) = static_type::of(lhs, &self.table, current) {
                        self.flows_into(rhs, &lhs_type, current, &|| "assignment".to_string());
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
                        let name = var.name.clone();
                        self.flows_into(default, &var.ty, current, &|| format!("variable '{}'", name));
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
                        self.flows_into(expr, &function.ty, current, &|| format!("the return value of '{}'", name));
                    }
                }
                Statement::LoopBreak(_) => {}
            }
        }
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

/// Reject function values whose signature does not match where they flow.
pub fn check_function_types(module: &Module) -> Result<(), String> {
    let mut checker = Checker { module, table: StructTable::build(module), errors: vec![] };
    for function in &module.functions {
        checker.function(function, None);
    }
    for st in &module.structs {
        // Generic bases are checked through their specializations; the
        // synthesized function-type structs hold no user code.
        if (st.ty.is_generic() && st.name == st.ty.name) || st.ty.is_function_type() {
            continue;
        }
        let current = st.ty.clone();
        checker.function(&st.constructor, Some(&current));
        for method in &st.method_members {
            checker.function(method, Some(&current));
        }
    }
    for var in &module.globals {
        if let Some(default) = &var.default {
            let name = var.name.clone();
            checker.flows_into(default, &var.ty, None, &|| format!("variable '{}'", name));
        }
    }
    let mut errors = checker.errors;
    errors.dedup();
    if errors.is_empty() { Ok(()) } else { Err(errors.join("\n")) }
}
