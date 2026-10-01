//! Checks the values interpolated strings convert. The parser lowers
//! `$"n = {n}"` to `"n = " + _pep_interpolate(n)`, and the runtime's
//! `_pep_interpolate<T>` returns `to_string(value)`: an integer or `bool`
//! overload, a concrete override `to_string<T>`, or the generic
//! `to_string<T>`, which calls `value.to_string()`. A type with none of
//! these would fail inside the runtime's generic body, so this pass reports
//! it at the `{name}` instead. A value with a format specification goes
//! through `_pep_format<T>`, which converts it the same way, or through
//! `_pep_format_integer<T>` when the specification needs an integer (a
//! sign, `0` or a type such as `x`); any other value is reported at the
//! character of the specification that needs one. A specification with a
//! precision (`{x:.2}`) goes through `_pep_format_float<T>`, which takes a
//! `float` or a `double` only. A tuple converts when each of its elements
//! does, through the runtime's `to_string<A, B, ...>` overloads (up to
//! [`MAX_TUPLE`] elements).

use crate::model::{Diagnostic, Expression, FunctionDef, Loc, Module};
use crate::passes::overloads::set_name;
use pepper_parser::namespace::{demangle, demangle_name};
use pepper_parser::parser::parsers::{FORMAT_FLOAT_FUNCTION, FORMAT_FUNCTION, FORMAT_INTEGER_FUNCTION, INTERPOLATE_FUNCTION};
use std::collections::HashSet;

const TO_STRING: &str = "to_string";
const PRINT: &str = "print";

/// The types the runtime's non-generic `to_string` overloads take, as
/// sema spells them.
const TO_STRING_OVERLOADS: &[&str] = &[
    "bool", "i8", "char", "u8", "byte", "i16", "short", "u16", "ushort", "i32", "int", "u32", "uint", "i64", "long", "u64",
    "ulong", "float", "f32", "double", "f64",
];

/// The floating-point types, which a precision (`{x:.2}`) formats.
const FLOATS: &[&str] = &["float", "f32", "double", "f64"];

/// The most elements a tuple the runtime's `to_string` overloads convert
/// can have.
const MAX_TUPLE: usize = 8;

/// The name of a specialization `f<A, B>` and its type arguments' text.
fn split_generic(name: &str) -> Option<(&str, &str)> {
    let (base, rest) = name.split_once('<')?;
    Some((base, rest.strip_suffix('>')?))
}

/// Whether `function` declares a `to_string()` an instance can call.
fn is_to_string_method(function: &FunctionDef) -> bool {
    set_name(&function.name) == TO_STRING && !function.is_static && function.parameters.is_empty()
}

pub fn check_interpolations(module: &mut Module) {
    // Every type argument with a concrete override `to_string<X>`. The
    // generic's own specializations (`to_string<Foo>` made for a call) keep
    // the generic's location, so they are not overrides.
    let generic_locs: Vec<_> = module
        .functions
        .iter()
        .filter(|f| f.is_generic_func && demangle_name(f.name.split('<').next().unwrap_or("")) == TO_STRING)
        .map(|f| f.loc)
        .collect();
    let overrides: HashSet<String> = module
        .functions
        .iter()
        .filter(|f| !f.is_generic_func && !generic_locs.contains(&f.loc))
        .filter_map(|f| split_generic(&f.name))
        .filter(|(base, _)| demangle_name(base) == TO_STRING)
        .map(|(_, args)| args.to_string())
        .collect();
    let base_of = |ty: &str| ty.split('<').next().unwrap_or(ty).to_string();
    let with_method: HashSet<String> = module
        .structs
        .iter()
        .filter(|s| s.method_members.iter().any(is_to_string_method))
        .map(|s| s.name.clone())
        .chain(module.traits.iter().filter(|t| t.methods.iter().any(is_to_string_method)).map(|t| base_of(&t.name)))
        .chain(
            module
                .functions
                .iter()
                .filter_map(|f| f.name.strip_suffix(&format!("::{}", TO_STRING)))
                .map(str::to_string),
        )
        .collect();
    let traits: HashSet<String> = module.traits.iter().map(|t| base_of(&t.name)).collect();
    let struct_locs: std::collections::HashMap<String, crate::model::Loc> =
        module.structs.iter().map(|s| (s.name.clone(), s.loc)).collect();
    fn convertible(
        ty: &str,
        overrides: &HashSet<String>,
        with_method: &HashSet<String>,
        traits: &HashSet<String>,
    ) -> bool {
        let base_of = |ty: &str| ty.split('<').next().unwrap_or(ty).to_string();
        if overrides.contains(ty) || with_method.contains(ty) {
            return true;
        }
        if ty.starts_with("__tuple<") {
            let tuple = crate::passes::gather_generics::parse_type_string(ty);
            return tuple.sub_types.len() <= MAX_TUPLE
                && tuple
                    .sub_types
                    .iter()
                    .all(|element| convertible(&element.to_string(), overrides, with_method, traits));
        }
        if traits.contains(&base_of(ty)) {
            return with_method.contains(&base_of(ty));
        }
        // The runtime's overloads: every number type and `bool`.
        TO_STRING_OVERLOADS.contains(&ty)
    }
    let convertible = |ty: &str| convertible(ty, &overrides, &with_method, &traits);
    let mut errors: Vec<Diagnostic> = vec![];
    let mut visit = |function: &mut FunctionDef| {
        crate::passes::walk_function(function, &mut |e| {
            let Expression::FunctionCall { function, args, loc } = e else { return };
            let Some((base, ty)) = split_generic(function) else { return };
            let shown = demangle(ty);
            // The runtime's `print<T>(value)` prints `to_string(value)`.
            if demangle_name(set_name(base)) == PRINT {
                if convertible(ty) {
                    return;
                }
                let at = args.first().map(|a| a.loc()).filter(|l| *l != Loc::NONE).unwrap_or(*loc);
                errors.push(
                    Diagnostic::error(format!(
                        "cannot print a value of type '{}': it has no 'to_string()' method and no 'to_string' overload",
                        shown
                    ))
                    .at(at),
                );
                return;
            }
            if base == FORMAT_FLOAT_FUNCTION {
                if FLOATS.contains(&ty) {
                    return;
                }
                errors.push(
                    Diagnostic::error(format!(
                        "cannot format a value of type '{}' with a precision; only 'float' and 'double' take one",
                        shown
                    ))
                    .at(*loc),
                );
                return;
            }
            if base == FORMAT_INTEGER_FUNCTION {
                if ty != "bool" && !FLOATS.contains(&ty) && TO_STRING_OVERLOADS.contains(&ty) {
                    return;
                }
                errors.push(
                    Diagnostic::error(format!(
                        "cannot format a value of type '{}' as an integer",
                        shown
                    ))
                    .at(*loc),
                );
                return;
            }
            if (base != INTERPOLATE_FUNCTION && base != FORMAT_FUNCTION) || convertible(ty) {
                return;
            }
            let mut error = Diagnostic::error(format!(
                "cannot interpolate a value of type '{}': it has no 'to_string()' method and no 'to_string' overload",
                shown
            ))
            .at(*loc);
            if let Some(declared) = struct_locs.get(ty) {
                error = error.with_note(
                    format!("declare 'to_string(): String' in '{}', or implement 'ToString' with 'extend {} with ToString'", shown, shown),
                    Some(*declared),
                );
            }
            errors.push(error);
        });
    };
    // Generic bases are checked through their specializations.
    for function in module.functions.iter_mut().filter(|f| !f.is_generic_func) {
        visit(function);
    }
    for st in module.structs.iter_mut().filter(|s| s.generic_params.is_empty()) {
        for method in st.method_members.iter_mut().chain(st.constructors.iter_mut()) {
            visit(method);
        }
    }
    for error in errors {
        crate::errors::report(error);
    }
}
