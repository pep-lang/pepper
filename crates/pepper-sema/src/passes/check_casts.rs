//! Reports a cast that converts what its kind may not (`crate::casts`): an
//! `x as T` that is not a static cast, an `unsafe_cast<T>(x)` that does not
//! reinterpret a pointer or number. Runs once every type is final and
//! `convert_to_traits` has turned each `s as Trait` into a `ToTrait`. A cast
//! whose operand has no static type here is left to codegen, which asks
//! `casts::check` again with the exact type.

use crate::model::*;
use crate::static_type::{self, StructTable};
use crate::type_name::TypeName;
use pepper_parser::diagnostic::Diagnostic;

pub fn check_casts(module: &mut Module) {
    let module = &*module;
    let table = StructTable::build(module);
    let traits = &module.traits;
    let mut errors = vec![];
    let mut check = |function: &FunctionDef, current: Option<&TypeName>, unbound: &[String]| {
        if let Some(body) = &function.body {
            super::visit_block(body, &mut |e| check_cast(e, &table, traits, current, unbound, &mut errors));
        }
    };
    for function in module.functions.iter().filter(|f| f.generic_params.is_empty()) {
        check(function, None, &super::check_function_types::base_params(module, &function.name, false));
    }
    for st in &module.structs {
        // Generic bases are checked through their specializations.
        if (st.ty.is_generic() && st.name == st.ty.name) || st.ty.is_function_type() || st.ty.is_weak() {
            continue;
        }
        let unbound = super::check_function_types::base_params(module, &st.name, true);
        for function in st.constructors.iter().chain(&st.method_members) {
            check(function, Some(&st.ty), &unbound);
        }
    }
    for var in &module.globals {
        if let Some(default) = &var.default {
            super::visit_expression(default, &mut |e| check_cast(e, &table, traits, None, &[], &mut errors));
        }
    }
    for error in errors {
        crate::errors::report(error);
    }
}

fn check_cast(
    e: &Expression,
    table: &StructTable,
    traits: &[TraitDef],
    current: Option<&TypeName>,
    unbound: &[String],
    errors: &mut Vec<Diagnostic>,
) {
    let Expression::Cast { expr, ty, loc, kind } = e else {
        return;
    };
    if *kind == CastKind::Synthesized {
        return;
    }
    let from = match expr.as_ref() {
        Expression::PointerLiteral => TypeName::void_ptr(),
        other => match static_type::of(other, table, current) {
            Some(from) if !from.contains_auto() && !unbound.iter().any(|p| from.mentions(p) || ty.mentions(p)) => from,
            _ => return,
        },
    };
    if let Err(message) = crate::casts::check(&from, ty, *kind) {
        // A trait value may hold something else: its conversion can fail.
        let message = if *kind == CastKind::Static && crate::traits::is_trait_type(traits, &from) {
            format!("{}; use 'as?' to convert a trait value, which gives '{}?'", message, crate::casts::spelled(ty))
        } else {
            message
        };
        errors.push(Diagnostic::error(message).at(*loc));
    }
}
