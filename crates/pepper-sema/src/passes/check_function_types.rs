//! Signature checks for function values. Codegen passes every function value
//! as an opaque pointer and calls through it with the signature of the static
//! type, so a mismatch that reached codegen would call a function with the
//! wrong arguments. This pass rejects, wherever a function value flows into a
//! typed slot (variable initializer, assignment, argument, return), a value
//! whose function type differs from the slot's. It also rejects a call that
//! returns `void` used as a value: stored, passed, returned, as an operand,
//! or as a condition.

use crate::model::*;
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;

/// Canonical spelling of a type for comparison: primitive aliases collapse
/// (`int` and `i32` are one type), recursively through generic arguments.
/// Types some passes carry as a flat string (`__function<int, int>` as a
/// bare name) are re-parsed first.
pub(crate) fn canonical(ty: &TypeName) -> TypeName {
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

/// A type as Pepper code spells it: `T*` (the model's pointer spelling,
/// legal only in extern declarations) is `__ptr<T>`.
fn pepper_spelling(ty: &TypeName) -> String {
    match ty.name.strip_suffix('*') {
        Some(pointee) if ty.sub_types.is_empty() => format!("__ptr<{}>", pepper_spelling(&TypeName::new(pointee))),
        _ => ty.display(),
    }
}

fn is_void_ptr(ty: &TypeName) -> bool {
    canonical(ty).to_string() == "void*"
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
    /// A raw pointer (`__ptr<T>`, `T*`). Pointers convert among themselves
    /// (C interop needs `void*`), but a pointer is never a struct reference.
    Pointer,
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
        self.report_with(Diagnostic::error(message), value, slot);
    }

    fn report_with(&mut self, diagnostic: Diagnostic, value: &Expression, slot: &Slot) {
        let at = if value.loc().is_none() { slot.fallback } else { value.loc() };
        let diagnostic = diagnostic.at(at);
        if !self.errors.iter().any(|d| d.message == diagnostic.message && d.loc == diagnostic.loc) {
            self.errors.push(diagnostic);
        }
    }

    /// What a type certainly is, or `None` when unknown here (unresolved,
    /// a generic parameter, a function).
    fn kind_of(&self, ty: &TypeName) -> Option<Kind> {
        let name = ty.to_string();
        if name == crate::type_name::AUTO || name.is_empty() || ty.is_function_type() {
            return None;
        }
        if name.ends_with('*') || (ty.name == "__ptr" && ty.sub_types.len() == 1) {
            return Some(Kind::Pointer);
        }
        if self.unbound.iter().any(|p| *p == ty.name) {
            return None;
        }
        if crate::arithmetic::is_numeric_type(&canonical(ty).to_string()) {
            return Some(Kind::Numeric);
        }
        // A trait used as a type is a reference too: struct values reach it
        // only through `convert_to_traits`, which checked conformance.
        let reference = self.module.structs.iter().any(|s| s.name == name)
            || crate::traits::is_trait_type(&self.module.traits, ty);
        reference.then_some(Kind::Struct)
    }

    /// A non-function `value` flowing into a non-function slot: numbers
    /// convert among themselves, but a number is never a struct, one struct
    /// is never another, and a pointer is never a struct (a `char*` passed
    /// as a `String` would be read as a `String` object).
    fn value_flows_into(
        &mut self,
        value: &Expression,
        expected: &TypeName,
        current: Option<&TypeName>,
        slot: &Slot,
    ) {
        // Raw buffer reads (`Data[i]`) carry no reliable static type.
        if matches!(
            value,
            Expression::PointerLiteral
                | Expression::Default(_)
                | Expression::ArrayIndex { .. }
                | Expression::Index { .. }
        ) {
            return;
        }
        let Some(expected_kind) = self.kind_of(expected) else {
            return;
        };
        // A raw literal is the `char*` global a `String` is built from, and
        // a literal passed where a pointer is expected is passed as that
        // global (`strlen("hi")`).
        let literal = match value {
            Expression::StringLiteral { is_raw: true, .. } => true,
            // `convert_string_literals` gives the call its literal's location;
            // a `String(...)` the user wrote has its own.
            Expression::FunctionCall { function, args, loc } => {
                function == "String" && matches!(args.first(), Some(Expression::StringLiteral { is_raw: true, loc: literal, .. }) if literal == loc)
            }
            _ => false,
        };
        let actual = if literal && (matches!(value, Expression::StringLiteral { .. }) || matches!(self.kind_of(expected), Some(Kind::Pointer))) {
            Some(TypeName::new("char*"))
        } else {
            static_type::of(value, &self.table, current)
        };
        let Some(actual) = actual else {
            return;
        };
        let Some(actual_kind) = self.kind_of(&actual) else {
            return;
        };
        let mismatch = match (expected_kind, actual_kind) {
            (Kind::Numeric, Kind::Numeric) => false,
            // Different structs; type arguments are not compared, since
            // defaults (`Result<int>` is `Result<int, Error>`) and
            // aliases may spell one specialization two ways.
            (Kind::Struct, Kind::Struct) => canonical(expected).name != canonical(&actual).name,
            (Kind::Pointer, Kind::Pointer) => false,
            // Integers and pointers mix in C interop (`__null`, handles).
            (Kind::Pointer, Kind::Numeric) | (Kind::Numeric, Kind::Pointer) => false,
            // A struct reference is an opaque `void*` to C and the runtime,
            // but no pointer, `void*` included, is a struct reference.
            (Kind::Pointer, Kind::Struct) => !is_void_ptr(expected),
            (Kind::Struct, Kind::Pointer) => true,
            _ => true,
        };
        if mismatch {
            let mut message = (slot.mismatch)(&pepper_spelling(expected), &pepper_spelling(&actual));
            let c_string = matches!(actual_kind, Kind::Pointer) && expected.to_string() == "String";
            if c_string {
                message += "; use 'String(...)' to copy a C string";
            }
            let mut diagnostic = Diagnostic::error(message);
            // The C-string hint already names the constructor.
            if let Some(note) = self.constructor_hint(expected, &actual).filter(|_| !c_string) {
                diagnostic = diagnostic.with_note(note.0, Some(note.1));
            }
            self.report_with(diagnostic, value, slot);
        }
    }

    /// A call that returns nothing (`f()` on a `void` function, `r.value()`
    /// on a `Result<void>`) used as a value: reports it and returns true.
    fn void_used(&mut self, value: &Expression, current: Option<&TypeName>, slot: &Slot) -> bool {
        let void = matches!(value, Expression::FunctionCall { .. } | Expression::MethodCall { .. } | Expression::Invoke { .. })
            && static_type::of(value, &self.table, current)
                .is_some_and(|t| t.name == crate::type_name::VOID && t.sub_types.is_empty());
        if void {
            let message = format!("cannot use a value of type 'void' as {}", (slot.what)());
            self.report(message, value, slot);
        }
        void
    }

    /// When `expected`'s constructor takes one `actual` but is not
    /// `[Implicit]`, a note at the constructor saying how to convert.
    fn constructor_hint(&self, expected: &TypeName, actual: &TypeName) -> Option<(String, Loc)> {
        let st = self.module.structs.iter().find(|s| s.name == expected.to_string() || s.ty.to_string() == expected.to_string())?;
        let (first, rest) = st.constructor.parameters.split_first()?;
        if st.implicit_from().is_some() || rest.iter().any(|p| p.default.is_none()) || !same_type(&first.ty, actual) {
            return None;
        }
        Some((
            format!(
                "'{}' has a constructor from '{}': call '{}(...)', or mark the constructor [Implicit]",
                expected.display(),
                actual.display(),
                expected.display()
            ),
            st.constructor.loc,
        ))
    }

    /// `value` flows into a slot of type `expected`.
    fn flows_into(&mut self, value: &Expression, expected: &TypeName, current: Option<&TypeName>, slot: &Slot) {
        if self.void_used(value, current, slot) {
            return;
        }
        if self.weak_flows_into(value, expected, current, slot) {
            return;
        }
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
            if !known || actual.is_auto() || actual.is_pointer() {
                return;
            }
            let message = format!("{} expects a function of type '{}', but was given a value of type '{}'", (slot.what)(), expected.display(), actual.display());
            self.report(message, value, slot);
        } else if !same_type(&actual, expected) && same_type(&actual.with_sharing(false), &expected.with_sharing(false)) {
            // Same signature, but a plain value where a `shared` one is
            // expected (`shared_functions` converted every value that can
            // be), or the reverse inside code no conversion reaches.
            let message = (slot.mismatch)(&expected.display(), &actual.display());
            self.report(message, value, slot);
        } else if !same_type(&actual, expected) {
            let message = format!("{} expects a function of type '{}', but was given a function of type '{}'", (slot.what)(), expected.display(), actual.display());
            self.report(message, value, slot);
        }
    }

    /// A `__weak<T>` and a `T` hold different counts (weak and strong), so
    /// neither converts to the other implicitly: `__weak_from<T>` and
    /// `__weak_upgrade<T>` do it. Returns true when either side is a weak
    /// reference, which this check then covers entirely.
    fn weak_flows_into(&mut self, value: &Expression, expected: &TypeName, current: Option<&TypeName>, slot: &Slot) -> bool {
        // Some passes carry `__weak<T>` as a flat name: re-parse those (and
        // only those; `parse_type_string` does not take pointer spellings).
        let weak = |ty: &TypeName| {
            let s = ty.to_string();
            if s.starts_with("__weak<") && s.ends_with('>') { crate::passes::gather_generics::parse_type_string(&s) } else { ty.clone() }
        };
        let expected = weak(expected);
        if matches!(value, Expression::PointerLiteral) {
            return expected.is_weak();
        }
        let Some(actual) = static_type::of(value, &self.table, current) else {
            return expected.is_weak();
        };
        let actual = weak(&actual);
        if !actual.is_weak() && !expected.is_weak() {
            return false;
        }
        if actual.is_auto() || expected.is_auto() || same_type(&actual, &expected) {
            return true;
        }
        let hint = match (expected.weak_target(), actual.weak_target()) {
            (Some(target), None) => format!("; use '__weak_from<{}>(...)' to make one", target.display()),
            (None, Some(target)) => format!("; use '__weak_upgrade<{}>(...)' to get a strong reference", target.display()),
            _ => String::new(),
        };
        let message = (slot.mismatch)(&expected.display(), &actual.display()) + &hint;
        self.report(message, value, slot);
        true
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
            if matches!(e, Expression::FunctionCall { .. } | Expression::MethodCall { .. } | Expression::Invoke { .. } | Expression::Binary { .. } | Expression::Unary { .. }) {
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
                Expression::Binary { op, lhs, rhs, loc } if *op != BinaryOp::Assign => {
                    let what = || "an operand".to_string();
                    let mismatch = |_: &str, _: &str| String::new();
                    let slot = Slot { what: &what, mismatch: &mismatch, fallback: *loc };
                    self.void_used(lhs, current, &slot);
                    self.void_used(rhs, current, &slot);
                }
                Expression::Unary { operand, loc, .. } => {
                    let what = || "an operand".to_string();
                    let mismatch = |_: &str, _: &str| String::new();
                    self.void_used(operand, current, &Slot { what: &what, mismatch: &mismatch, fallback: *loc });
                }
                Expression::Binary { op: BinaryOp::Assign, lhs, rhs, loc } => {
                    // A raw buffer slot (`Data[i] = v`) has no reliable
                    // static type.
                    let raw_slot = matches!(**lhs, Expression::Index { .. } | Expression::ArrayIndex { .. });
                    if let Some(lhs_type) = static_type::of(lhs, &self.table, current).filter(|t| !raw_slot || t.is_function_type()) {
                        let mismatch = |expected: &str, actual: &str| format!("cannot assign a value of type '{}' to a variable of type '{}'", actual, expected);
                        self.flows_into(rhs, &lhs_type, current, &Slot { what: &|| "the value of an assignment".to_string(), mismatch: &mismatch, fallback: *loc });
                    }
                }
                _ => {}
            }
        }
    }

    fn block(&mut self, block: &Block, function: &FunctionDef, current: Option<&TypeName>) {
        // A `with` block is [scope, value = scope.enter(), Branch(WithEntered)]
        // until `lower_with_blocks`, which explains a `void` binding itself.
        let with_value = match &block.items[..] {
            [Statement::Declaration(Declaration::Variable(_)), Statement::Declaration(Declaration::Variable(value)), Statement::Branch(branch)]
                if matches!(branch.condition, Expression::WithEntered(_)) =>
            {
                Some(value.name.clone())
            }
            _ => None,
        };
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
                        if with_value.as_deref() != Some(var.name.as_str()) {
                            self.variable(var, default, current);
                        }
                    }
                }
                Statement::Declaration(_) => {}
                Statement::Branch(branch) => {
                    self.expression(&branch.condition, current);
                    self.condition(&branch.condition, current);
                    self.block(&branch.if_block, function, current);
                    if let Some(else_block) = &branch.else_block {
                        self.block(else_block, function, current);
                    }
                }
                Statement::While(wh) => {
                    self.expression(&wh.condition, current);
                    self.condition(&wh.condition, current);
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

    /// A `void` call cannot be an `if` or `while` condition.
    fn condition(&mut self, condition: &Expression, current: Option<&TypeName>) {
        let what = || "a condition".to_string();
        let mismatch = |_: &str, _: &str| String::new();
        self.void_used(condition, current, &Slot { what: &what, mismatch: &mismatch, fallback: condition.loc() });
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
/// Runs near the end of `transform_pass`, before `lower_with_blocks`, so the
/// language server reports it too.
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
        if (st.ty.is_generic() && st.name == st.ty.name) || st.ty.is_function_type() || st.ty.is_weak() {
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
