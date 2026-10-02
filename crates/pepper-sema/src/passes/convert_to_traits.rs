//! Conversions at the places a value flows into a typed slot (variable
//! initializer, assignment, argument, return).
//!
//! Implicit constructors: a value flowing into a slot of struct type `B`
//! whose constructor is `[Implicit]` from type `A` becomes the call `B(value)`
//! when the value is an `A`, or reaches `A` by promotion (integer widening, a
//! literal that fits, `f32` to `f64`, a struct to a trait it declares). One
//! conversion per value: the constructor's own argument never converts again
//! through another constructor. The call is an ordinary constructor call, an
//! owned rvalue, so the refcount rules need nothing new.
//!
//! Struct-to-trait conversions. Wherever a value of struct type `S` flows
//! into a slot of trait type `Tr`, wrap it in `ToTrait { S → Tr }`: the same object, seen
//! through the vtable of `S`'s conformance to `Tr`. This is C++'s
//! `shared_ptr<Derived>` → `shared_ptr<Base>`: the slot acquires (or an owned
//! rvalue moves in) exactly as it would for an `S`, so the refcount rules
//! need nothing new.
//!
//! Conformance is nominal: `S` must declare `extend S with Tr`. Calls through
//! a trait value are checked here too: only the trait's dispatchable members
//! (see `traits::is_dispatchable`) can be called. Finally the pass records
//! every trait type the program uses, for codegen.

use crate::literals;
use crate::model::*;
use crate::static_type::{self, StructTable};
use crate::traits;
use crate::type_name::TypeName;
use std::collections::HashMap;

struct StructFacts {
    methods: HashMap<String, Vec<TypeName>>,
    traits: Vec<TypeName>,
    loc: Loc,
}

/// A struct whose constructor is `[Implicit]`.
#[derive(Clone)]
struct Implicit {
    /// The constructor's parameter type.
    from: TypeName,
    /// The constructor call's name (`Path`, `Box<int>`, `Path$2`).
    callee: String,
    /// The constructor, for the language server.
    constructor: Loc,
}

struct Converter {
    implicit: HashMap<String, Implicit>,
    conversions: Vec<Conversion>,
    table: StructTable,
    trait_defs: Vec<TraitDef>,
    /// Each conformance of a value type (`extend int with Tr`): the type's
    /// key (`value_types::key`), the trait, and the extension.
    value_conformances: Vec<(String, TypeName, Loc)>,
    /// Present when an extension adds constraints: says which condition of
    /// a conditional conformance a struct does not meet.
    conformance: Option<crate::passes::constraints::Conformance>,
    trait_types: HashMap<String, TraitType>,
    functions: HashMap<String, Vec<TypeName>>,
    structs: HashMap<String, StructFacts>,
}

impl Converter {
    fn trait_type(&mut self, ty: &TypeName) -> Option<&TraitType> {
        let def = traits::trait_def(&self.trait_defs, ty)?;
        let key = ty.to_string();
        if !self.trait_types.contains_key(&key) {
            let instance = traits::instance(def, ty);
            self.trait_types.insert(key.clone(), instance);
        }
        self.trait_types.get(&key)
    }

    /// `value` flows into a slot of type `expected`.
    fn convert(
        &mut self,
        value: &mut Expression,
        expected: &TypeName,
        current: Option<&TypeName>,
        fallback: Loc,
    ) {
        if is_c_string_type(expected) {
            unwrap_string_literal(value);
            return;
        }
        if expected.is_tuple() {
            self.convert_tuple(value, expected, current, fallback);
            return;
        }
        if let Some(element) = array_element(expected)
            && is_array_literal(value)
        {
            self.convert_array_literal(value, expected, &element, current, fallback);
            return;
        }
        if let Some((key, map_value)) = map_types(expected)
            && is_map_literal(value)
        {
            self.convert_map_literal(value, expected, &key, &map_value, current, fallback);
            return;
        }
        // A `match` expression's value is its body's (a long collection
        // literal is a `WithSubject` too, handled above).
        if let Expression::WithSubject(with) = value {
            self.convert(&mut with.body, expected, current, fallback);
            return;
        }
        // A null weak trait value (`__weak<Shape>`, an object and a vtable,
        // like a trait value) is its zero pair.
        if matches!(value, Expression::PointerLiteral)
            && expected.weak_target().is_some_and(|t| traits::is_trait_type(&self.trait_defs, t))
        {
            *value = Expression::Default(expected.clone());
            return;
        }
        let to_trait = traits::is_trait_type(&self.trait_defs, expected);
        if matches!(value, Expression::ToTrait { .. })
            || !(to_trait || self.implicit.contains_key(&expected.to_string()))
        {
            return;
        }
        // Each arm converts on its own: they may be different structs.
        if let Expression::Ternary {
            true_expr,
            false_expr,
            ..
        } = value
        {
            self.convert(true_expr, expected, current, fallback);
            self.convert(false_expr, expected, current, fallback);
            return;
        }
        let loc = if value.loc().is_none() {
            fallback
        } else {
            value.loc()
        };
        if !to_trait {
            self.convert_implicit(value, expected, current, loc);
            return;
        }
        let from =
            if matches!(value, Expression::PointerLiteral) {
                TypeName::void_ptr()
            } else {
                let Some(actual) = static_type::of(value, &self.table, current) else {
                    return;
                };
                if traits::is_trait_type(&self.trait_defs, &actual) {
                    // A trait value of the same type needs nothing; converting
                    // one trait to another needs supertraits, which do not exist.
                    if crate::passes::check_function_types::canonical(&actual)
                        != crate::passes::check_function_types::canonical(expected)
                    {
                        crate::errors::report(
                            Diagnostic::error(format!(
                                "cannot convert a value of trait type '{}' to trait type '{}'",
                                actual.display(),
                                expected.display()
                            ))
                            .at(loc),
                        );
                    }
                    return;
                }
                let Some(facts) = self.structs.get(&actual.to_string()) else {
                    // A number, `bool` or enum may conform to the trait, for
                    // constraints, but is never a trait value.
                    if crate::value_types::is_value_type(&actual) {
                        let key = crate::value_types::key(&actual.name);
                        let declared = self
                            .value_conformances
                            .iter()
                            .find(|(k, t, _)| Some(k) == key.as_ref() && *t == crate::passes::check_function_types::canonical(expected))
                            .map(|(_, _, at)| *at);
                        let shown = crate::passes::constraints::spelled(&actual);
                        let error = Diagnostic::error(format!(
                            "'{}' cannot be converted to trait '{}': only structs and enums whose cases carry values can be trait values",
                            shown,
                            expected.display()
                        ))
                        .at(loc);
                        crate::errors::report(match declared {
                            Some(at) => error.with_note(
                                format!("'{}' conforms to '{}' here, which makes it meet the constraint, not a trait value", shown, expected.display()),
                                Some(at),
                            ),
                            None => error,
                        });
                    }
                    // Anything else: the type checks report the mismatch.
                    return;
                };
                let expected_canonical = crate::passes::check_function_types::canonical(expected);
                if !facts.traits.iter().any(|t| {
                    crate::passes::check_function_types::canonical(t) == expected_canonical
                }) {
                    let error = Diagnostic::error(format!(
                        "'{}' does not conform to trait '{}'",
                        actual.display(),
                        expected.display()
                    ))
                    .at(loc);
                    // A conditional conformance names the condition missed.
                    let condition = self.conformance.as_ref().and_then(|c| c.condition_note(&actual, expected));
                    let error = match condition {
                        Some((note, at)) => error.with_note(note, Some(at)),
                        None => error.with_note(
                            format!("declare it with 'extend {} with {}'", actual.display(), expected.display()),
                            Some(facts.loc),
                        ),
                    };
                    crate::errors::report(error);
                    return;
                }
                actual
            };
        self.trait_type(expected);
        let inner = std::mem::replace(value, Expression::PointerLiteral);
        *value = Expression::ToTrait {
            value: Box::new(inner),
            from,
            to: expected.clone(),
            loc,
        };
    }

    /// `value` flows into a slot of tuple type `expected`. A tuple literal
    /// of as many elements takes the slot's type, and each element then flows
    /// into its element's slot (`(0, square)` returned as a `(ulong, Shape)`
    /// is `__tuple<ulong, Shape>(0, ToTrait(square))`). Any other value is
    /// left to the type checks.
    fn convert_tuple(&mut self, value: &mut Expression, expected: &TypeName, current: Option<&TypeName>, fallback: Loc) {
        match value {
            Expression::Ternary { true_expr, false_expr, .. } => {
                self.convert_tuple(true_expr, expected, current, fallback);
                self.convert_tuple(false_expr, expected, current, fallback);
            }
            Expression::FunctionCall { function, args, loc }
                if crate::passes::tuples::is_literal(function) && args.len() == expected.tuple_elements().len() =>
            {
                *function = expected.to_string();
                let loc = if loc.is_none() { fallback } else { *loc };
                self.arguments(expected.tuple_elements(), args, current, loc);
            }
            _ => {}
        }
    }

    /// An array literal flowing into a slot of type `expected`, an
    /// `Array<element>`: the literal is built as that type, from `Array<element>()`
    /// rather than from its first element, so its elements convert to
    /// `element` (`long[] a = [1, 2]`, `Shape[] s = [circle, square]`).
    fn convert_array_literal(
        &mut self,
        value: &mut Expression,
        expected: &TypeName,
        element: &TypeName,
        current: Option<&TypeName>,
        fallback: Loc,
    ) {
        let literal = std::mem::replace(value, Expression::PointerLiteral);
        let (start, steps, loc) = literals::parts(literal);
        let Expression::FunctionCall { args: first, .. } = start else { unreachable!("checked by is_array_literal") };
        let loc = if loc.is_none() { fallback } else { loc };
        let mut steps: Vec<Vec<Expression>> = std::iter::once(first).chain(steps).collect();
        for item in steps.iter_mut().flatten() {
            self.convert(item, element, current, loc);
        }
        let start = Expression::FunctionCall { function: expected.to_string(), args: vec![], loc };
        *value = literals::build(start, steps, "_literal_append", expected.clone(), loc);
    }

    /// A map literal flowing into a slot of type `expected`, a
    /// `HashMap<key, value>`: built from `HashMap<key, value>()`, as
    /// `convert_array_literal` does for arrays.
    fn convert_map_literal(
        &mut self,
        value: &mut Expression,
        expected: &TypeName,
        key: &TypeName,
        map_value: &TypeName,
        current: Option<&TypeName>,
        fallback: Loc,
    ) {
        let literal = std::mem::replace(value, Expression::PointerLiteral);
        let (start, steps, loc) = literals::parts(literal);
        let Expression::FunctionCall { args: first, .. } = start else { unreachable!("checked by is_map_literal") };
        let loc = if loc.is_none() { fallback } else { loc };
        let mut entries: Vec<Vec<Expression>> = std::iter::once(first).chain(steps).collect();
        for entry in &mut entries {
            self.convert(&mut entry[0], key, current, loc);
            self.convert(&mut entry[1], map_value, current, loc);
        }
        let start = Expression::FunctionCall { function: expected.to_string(), args: vec![], loc };
        *value = literals::build(start, entries, "_literal_insert", expected.clone(), loc);
    }

    /// `value` flows into a slot of struct type `expected`, which has an
    /// `[Implicit]` constructor: call it when the value is not already an
    /// `expected` and fits the constructor's parameter.
    fn convert_implicit(
        &mut self,
        value: &mut Expression,
        expected: &TypeName,
        current: Option<&TypeName>,
        loc: Loc,
    ) {
        // `__null` is a null reference of any struct type.
        if matches!(value, Expression::PointerLiteral) {
            return;
        }
        let Some(implicit) = self.implicit.get(&expected.to_string()).cloned() else {
            return;
        };
        let Some(actual) = static_type::of(value, &self.table, current) else {
            return;
        };
        let canonical = crate::passes::check_function_types::canonical;
        // Already the struct. Type arguments are not compared, as in
        // `check_function_types`: one specialization may be spelled two ways.
        if canonical(&actual).name == canonical(expected).name {
            return;
        }
        if !self.fits(value, &actual, &implicit.from) {
            return;
        }
        // A specialized body converts once per specialization; the source
        // location is one place.
        let at = value.loc();
        let record = Conversion {
            at,
            from: actual.clone(),
            to: expected.clone(),
            constructor: implicit.constructor,
        };
        if !at.is_none() && !self.conversions.contains(&record) {
            self.conversions.push(record);
        }
        let inner = std::mem::replace(value, Expression::PointerLiteral);
        *value = Expression::FunctionCall {
            function: implicit.callee,
            args: vec![inner],
            loc,
        };
        // A struct reaching a trait parameter still needs its `ToTrait`.
        if let Expression::FunctionCall { args, .. } = value {
            self.convert(&mut args[0], &implicit.from, current, loc);
        }
    }

    /// Whether `value`, of type `actual`, reaches `to` exactly or by
    /// promotion: the conversions an implicit constructor's argument may take.
    fn fits(&self, value: &Expression, actual: &TypeName, to: &TypeName) -> bool {
        // An array literal becomes whatever `Array` it flows into.
        if is_array_literal(value) && array_element(to).is_some() {
            return true;
        }
        let canonical = crate::passes::check_function_types::canonical;
        let (from_c, to_c) = (canonical(actual), canonical(to));
        if from_c == to_c {
            return true;
        }
        if traits::is_trait_type(&self.trait_defs, to) {
            return self
                .structs
                .get(&actual.to_string())
                .is_some_and(|facts| facts.traits.iter().any(|t| canonical(t) == to_c));
        }
        let (from_name, to_name) = (from_c.to_string(), to_c.to_string());
        if let Expression::IntLiteral(v) = value {
            return integer_range(&to_name).is_some_and(|(min, max)| (*v as i128) >= min && (*v as i128) <= max);
        }
        promotes(&from_name, &to_name)
    }

    /// A trait method implemented with a struct return type where the trait
    /// returns a trait type (see `apply_extensions::check_signature`): that
    /// struct must conform to the declared trait type.
    fn check_covariant_returns(&mut self, module: &Module) {
        let canonical = crate::passes::check_function_types::canonical;
        for st in module
            .structs
            .iter()
            .filter(|st| !(st.ty.is_generic() && st.name == st.ty.name))
        {
            for declared in &st.traits {
                let Some(def) = traits::trait_def(&self.trait_defs, declared) else {
                    continue;
                };
                let instance = traits::instance(def, declared);
                for required in &instance.methods {
                    if !traits::is_trait_type(&self.trait_defs, &required.ty) {
                        continue;
                    }
                    let Some(have) = st.method_members.iter().find(|m| m.name == required.name)
                    else {
                        continue;
                    };
                    if traits::is_trait_type(&self.trait_defs, &have.ty) {
                        continue;
                    }
                    let conforms = self.structs.get(&have.ty.to_string()).is_some_and(|facts| {
                        facts
                            .traits
                            .iter()
                            .any(|t| canonical(t) == canonical(&required.ty))
                    });
                    if !conforms {
                        crate::errors::report(
                            Diagnostic::error(format!(
                                "'{}' in '{}' returns '{}', which does not conform to '{}' as trait '{}' requires",
                                have.name,
                                st.ty.display(),
                                have.ty.display(),
                                required.ty.display(),
                                declared.display()
                            ))
                            .at(have.loc)
                            .with_note(format!("'{}' declared here", required.name), Some(required.loc)),
                        );
                    }
                }
            }
        }
    }

    fn arguments(
        &mut self,
        params: &[TypeName],
        args: &mut [Expression],
        current: Option<&TypeName>,
        call: Loc,
    ) {
        for (param, arg) in params.iter().zip(args.iter_mut()) {
            self.convert(arg, param, current, call);
        }
    }

    /// Parameter types of a call through a trait value, reporting a member
    /// the value cannot call.
    fn trait_method_params(
        &mut self,
        receiver: &TypeName,
        method: &str,
        loc: Loc,
    ) -> Option<Vec<TypeName>> {
        // The synthesized refcount members dispatch like any other.
        if method == "__acquire" || method == "__release" {
            return Some(vec![]);
        }
        let def = traits::trait_def(&self.trait_defs, receiver)?.clone();
        let instance = self.trait_type(receiver)?.clone();
        if let Some(m) = instance.methods.iter().find(|m| m.name == method) {
            return Some(m.parameters.iter().map(|p| p.ty.clone()).collect());
        }
        let message = match def.methods.iter().find(|m| m.name == method) {
            Some(m) if m.is_static => format!(
                "'{}' is static and cannot be called on a value of trait type '{}'",
                method,
                receiver.display()
            ),
            Some(_) => format!(
                "'{}' uses 'this' as a type and cannot be called on a value of trait type '{}'",
                method,
                receiver.display()
            ),
            None => format!("no member named '{}' in '{}'", method, receiver.display()),
        };
        let mut diagnostic = Diagnostic::error(message).at(loc);
        if let Some(m) = def.methods.iter().find(|m| m.name == method) {
            diagnostic = diagnostic.with_note(format!("'{}' declared here", method), Some(m.loc));
        }
        crate::errors::report(diagnostic);
        None
    }

    fn expression(&mut self, expr: &mut Expression, current: Option<&TypeName>) {
        // Children first, so a nested call's arguments are converted before
        // the enclosing node reads their types.
        match expr {
            Expression::MemberRef { lhs, .. } => self.expression(lhs, current),
            Expression::Binary { lhs, rhs, .. } => {
                self.expression(lhs, current);
                self.expression(rhs, current);
            }
            Expression::Unary { operand, .. } => self.expression(operand, current),
            // `s as Trait` is the conversion a trait-typed slot makes.
            Expression::Cast { expr: inner, ty, kind: CastKind::Static, .. } if traits::is_trait_type(&self.trait_defs, ty) => {
                self.expression(inner, current);
                let ty = ty.clone();
                self.convert(inner, &ty, current, Loc::NONE);
                if matches!(inner.as_ref(), Expression::ToTrait { .. }) {
                    *expr = std::mem::replace(inner.as_mut(), Expression::PointerLiteral);
                }
            }
            Expression::Cast { expr, .. } => self.expression(expr, current),
            Expression::Ternary {
                condition,
                true_expr,
                false_expr,
            } => {
                self.expression(condition, current);
                self.expression(true_expr, current);
                self.expression(false_expr, current);
            }
            Expression::Index { lhs, rhs, .. } | Expression::ArrayIndex { lhs, rhs, .. } => {
                self.expression(lhs, current);
                self.expression(rhs, current);
            }
            Expression::RefCount(_, arg)
            | Expression::Address(_, arg)
            | Expression::AtomicLoad(_, arg) => self.expression(arg, current),
            Expression::AtomicStore(_, a, b) | Expression::AtomicFetch(_, _, a, b) | Expression::ConstructAt(a, b) => {
                self.expression(a, current);
                self.expression(b, current);
            }
            Expression::AtomicCmpXchg(_, a, b, c) => {
                self.expression(a, current);
                self.expression(b, current);
                self.expression(c, current);
            }
            Expression::FunctionCall { args, .. } => {
                for arg in args.iter_mut() {
                    self.expression(arg, current);
                }
            }
            Expression::MethodCall { this, args, .. } => {
                self.expression(this, current);
                for arg in args.iter_mut() {
                    self.expression(arg, current);
                }
            }
            Expression::Invoke { callee, args } => {
                self.expression(callee, current);
                for arg in args.iter_mut() {
                    self.expression(arg, current);
                }
            }
            Expression::ForIterator(inner) | Expression::WithEntered(inner) => {
                self.expression(inner, current)
            }
            Expression::ToTrait { value, .. } => self.expression(value, current),
            Expression::WithSubject(with) => {
                self.expression(&mut with.subject, current);
                self.expression(&mut with.body, current);
            }
            Expression::MatchArm(test) => {
                self.expression(&mut test.subject, current);
                for literal in test.patterns.iter_mut().flat_map(|p| p.literals_mut()) {
                    self.expression(literal, current);
                }
            }
            _ => {}
        }
        match expr {
            Expression::FunctionCall {
                function,
                args,
                loc,
            } => {
                // Constructors are listed with the functions, by name.
                let params = self.functions.get(function.as_str()).cloned();
                if let Some(params) = params {
                    let loc = *loc;
                    self.arguments(&params, args, current, loc);
                }
            }
            Expression::MethodCall {
                this,
                method,
                args,
                loc,
            } => {
                let Some(receiver) = static_type::of(this, &self.table, current) else {
                    return;
                };
                let loc = *loc;
                let params = if traits::is_trait_type(&self.trait_defs, &receiver) {
                    self.trait_method_params(&receiver, method, loc)
                } else {
                    self.structs
                        .get(&receiver.to_string())
                        .and_then(|s| s.methods.get(method.as_str()).cloned())
                };
                if let Some(params) = params {
                    self.arguments(&params, args, current, loc);
                }
            }
            Expression::Invoke { callee, args } => {
                if let Some(fn_ty) =
                    static_type::of(callee, &self.table, current).filter(|t| t.is_callable())
                {
                    let params = fn_ty.function_params().to_vec();
                    let loc = callee.loc();
                    self.arguments(&params, args, current, loc);
                }
            }
            Expression::Binary {
                op: BinaryOp::Assign,
                lhs,
                rhs,
                loc,
            } => {
                if let Some(lhs_type) = static_type::of(lhs, &self.table, current) {
                    let loc = *loc;
                    self.convert(rhs, &lhs_type, current, loc);
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
                    let fallback = if var.type_loc.is_none() {
                        var.loc
                    } else {
                        var.type_loc
                    };
                    if let Some(default) = &mut var.default {
                        self.expression(default, current);
                        self.convert(default, &ty, current, fallback);
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
                    let loc = ret.loc;
                    if let Some(expr) = &mut ret.expr {
                        self.expression(expr, current);
                        self.convert(expr, returns, current, loc);
                    }
                }
                Statement::LoopBreak(_) | Statement::Static(_) => {}
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

/// A pointer to characters, bytes, or `void`: a slot a string literal fills
/// with its NUL-terminated bytes rather than a `String`.
fn is_c_string_type(ty: &TypeName) -> bool {
    let text = ty.to_string();
    let pointee = match text.strip_prefix("__ptr<").and_then(|t| t.strip_suffix('>')) {
        Some(inner) => inner,
        None => match text.strip_suffix('*') {
            Some(inner) => inner,
            None => return false,
        },
    };
    matches!(pointee.trim(), "char" | "i8" | "byte" | "u8" | "void")
}

/// A string literal flowing into a character pointer is its raw global, as
/// it is for an `extern`'s argument: `String("hi")`,
/// `__ptr<char> p = "hi";`. `convert_string_literals` made the literal a
/// `String(raw, size, length)` call, which would pass the `String` object
/// itself, and the pointer would read its fields as characters. Each arm of
/// a ternary unwraps on its own. Anything else, a `String` variable
/// included, is left for the type checks.
fn unwrap_string_literal(value: &mut Expression) {
    match value {
        Expression::Ternary {
            true_expr,
            false_expr,
            ..
        } => {
            unwrap_string_literal(true_expr);
            unwrap_string_literal(false_expr);
        }
        // The synthesized call carries its literal's location; a
        // `String(...)` the user wrote has its own.
        Expression::FunctionCall { function, args, loc }
            if function == "String"
                && matches!(args.first(), Some(Expression::StringLiteral { is_raw: true, loc: literal, .. }) if literal == loc) =>
        {
            *value = args.swap_remove(0);
        }
        _ => {}
    }
}

/// The range of an integer type, by canonical name.
fn integer_range(ty: &str) -> Option<(i128, i128)> {
    let bits = |b: u32, signed: bool| {
        if signed {
            (-(1i128 << (b - 1)), (1i128 << (b - 1)) - 1)
        } else {
            (0, (1i128 << b) - 1)
        }
    };
    Some(match ty {
        "i8" => bits(8, true),
        "i16" => bits(16, true),
        "i32" => bits(32, true),
        "i64" => bits(64, true),
        "u8" => bits(8, false),
        "u16" => bits(16, false),
        "u32" => bits(32, false),
        "u64" => bits(64, false),
        _ => return None,
    })
}

/// Whether every value of numeric type `from` is a value of `to` (canonical
/// names): integer widening, and `f32` to `f64`.
fn promotes(from: &str, to: &str) -> bool {
    if from == "f32" && to == "f64" {
        return true;
    }
    match (integer_range(from), integer_range(to)) {
        (Some((from_min, from_max)), Some((to_min, to_max))) => from_min >= to_min && from_max <= to_max,
        _ => false,
    }
}

pub fn convert_to_traits(module: &mut Module) {
    let concrete = |st: &StructDef| !(st.ty.is_generic() && st.name == st.ty.name);
    let mut implicit = HashMap::new();
    for st in module.structs.iter().filter(|st| concrete(st)) {
        if let Some(ctor) = st.implicit_constructor()
            && let Some(from) = st.implicit_from()
        {
            let entry = Implicit {
                from: from.clone(),
                callee: ctor.name.clone(),
                constructor: ctor.loc,
            };
            implicit.insert(st.name.clone(), entry.clone());
            implicit.insert(st.ty.to_string(), entry);
        }
    }
    if module.traits.is_empty() && implicit.is_empty() {
        return;
    }
    let mut converter = Converter {
        implicit,
        conversions: vec![],
        table: StructTable::build(module),
        trait_defs: module.traits.clone(),
        value_conformances: module
            .extensions
            .iter()
            .filter(|e| crate::value_types::is_value_type(&e.target))
            .flat_map(|e| {
                let key = crate::value_types::key(&e.target.name).unwrap_or_default();
                e.traits.iter().map(move |t| (key.clone(), crate::passes::check_function_types::canonical(t), e.loc))
            })
            .collect(),
        conformance: module
            .extensions
            .iter()
            .any(|e| !e.restated.is_empty())
            .then(|| crate::passes::constraints::Conformance::of(module)),
        trait_types: HashMap::new(),
        functions: module
            .functions
            .iter()
            .filter(|f| !f.is_generic_func)
            .map(|f| {
                (
                    f.name.clone(),
                    f.parameters.iter().map(|p| p.ty.clone()).collect(),
                )
            })
            .chain(
                module
                    .structs
                    .iter()
                    .filter(|st| concrete(st))
                    .flat_map(|st| st.constructors.iter())
                    .map(|c| (c.name.clone(), c.parameters.iter().map(|p| p.ty.clone()).collect())),
            )
            .collect(),
        structs: module
            .structs
            .iter()
            .filter(|st| concrete(st))
            .map(|st| {
                let facts = StructFacts {
                    methods: st
                        .method_members
                        .iter()
                        .map(|m| {
                            (
                                m.name.clone(),
                                m.parameters.iter().map(|p| p.ty.clone()).collect(),
                            )
                        })
                        .collect(),
                    traits: st.traits.clone(),
                    loc: st.loc,
                };
                (st.name.clone(), facts)
            })
            .collect(),
    };
    converter.check_covariant_returns(module);
    for function in &mut module.functions {
        converter.function(function, None);
    }
    for st in &mut module.structs {
        if !concrete(st) || st.ty.is_function_type() {
            continue;
        }
        let current = st.ty.clone();
        for constructor in &mut st.constructors {
            converter.function(constructor, Some(&current));
        }
        for method in &mut st.method_members {
            converter.function(method, Some(&current));
        }
    }
    for var in &mut module.globals {
        let ty = var.ty.clone();
        let fallback = if var.type_loc.is_none() {
            var.loc
        } else {
            var.type_loc
        };
        if let Some(default) = &mut var.default {
            converter.expression(default, None);
            converter.convert(default, &ty, None, fallback);
        }
    }
    // Every trait type in use, for codegen: the declared ones and those the
    // conversions above introduced.
    for ty in traits::used_trait_types(module) {
        converter.trait_type(&ty);
    }
    let mut trait_types: Vec<TraitType> = converter.trait_types.into_values().collect();
    trait_types.sort_by_key(|t| t.ty.to_string());
    module.trait_types = trait_types;
    module.conversions = converter.conversions;
}

/// The element type of an `Array<T>` slot.
fn array_element(ty: &TypeName) -> Option<TypeName> {
    let parsed = crate::passes::gather_generics::parse_type_string(&ty.to_string());
    (parsed.name == "Array" && parsed.sub_types.len() == 1).then(|| parsed.sub_types[0].clone())
}

/// The key and value types of a `HashMap<K, V>` slot.
fn map_types(ty: &TypeName) -> Option<(TypeName, TypeName)> {
    let parsed = crate::passes::gather_generics::parse_type_string(&ty.to_string());
    (parsed.name == "HashMap" && parsed.sub_types.len() == 2).then(|| (parsed.sub_types[0].clone(), parsed.sub_types[1].clone()))
}

/// Whether `value` is an array literal as the builder lowers it (see
/// `literals.rs`).
fn is_array_literal(value: &Expression) -> bool {
    literals::is(value, "_array_literal", "_literal_append", 1)
}

/// Whether `value` is a map literal as the builder lowers it (see
/// `literals.rs`).
fn is_map_literal(value: &Expression) -> bool {
    literals::is(value, "_map_literal", "_literal_insert", 2)
}
