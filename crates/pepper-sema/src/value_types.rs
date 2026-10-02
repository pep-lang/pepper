//! Extensions of value types: numbers, `char`, `bool` and enums whose cases
//! carry no values (`extend int with Doubled { doubled(): int { ... } }`).
//!
//! A value type has no object to hang methods on, so its methods are free
//! functions named `X::m`, as an enum's own methods are (see `enums`): an
//! instance method takes the value as a first parameter `this`, and a call
//! on a value, `x.doubled()`, becomes `int::doubled(x)`. Dispatch is static.
//! A conformance (`extend int with Doubled`) makes the type meet the
//! constraint `T: Doubled` (`passes::constraints`); it never makes a trait
//! value (`convert_to_traits` reports one).
//!
//! [`lower_extensions`] runs first in `enums::resolve_enum_cases`: it turns
//! each such extension's methods, and the trait defaults its conformances
//! need, into those functions, checks that every required member is
//! there, and leaves the extension in `module.extensions` with no methods,
//! so the conformance is still declared there.

use crate::errors::report;
use crate::model::*;
use crate::passes::overloads::set_name;
use crate::type_name::{replace_map, TypeName};

/// The name a value type's methods are filed under: the enum's name, or a
/// number type's canonical spelling (`i32` for `int`). `None` for any other
/// type.
pub fn key(name: &str) -> Option<String> {
    if crate::enums::is_enum(name) {
        return Some(name.to_string());
    }
    let canonical = match name {
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
        "i8" | "u8" | "i16" | "u16" | "i32" | "u32" | "i64" | "u64" | "f32" | "f64" | "bool" => name,
        _ => return None,
    };
    Some(canonical.to_string())
}

/// The keys of the number types and `bool` (see [`key`]).
pub const NUMBER_KEYS: [&str; 11] = ["i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f32", "f64", "bool"];

/// Whether `ty` is a value type an extension may target: a number type,
/// `char`, `bool`, or an enum whose cases carry no values.
pub fn is_value_type(ty: &TypeName) -> bool {
    ty.sub_types.is_empty() && key(&ty.name).is_some()
}

/// Lowers every extension of a value type (see the module docs).
pub fn lower_extensions(module: &mut Module) {
    let mut added: Vec<FunctionDef> = vec![];
    for i in 0..module.extensions.len() {
        let ext = &module.extensions[i];
        if !is_value_type(&ext.target) {
            continue;
        }
        let Some(key) = key(&ext.target.name) else { continue };
        let shown = pepper_parser::namespace::demangle_name(&ext.target.name).to_string();
        // An enum declares its own methods; an extension of one only
        // declares conformances.
        if crate::enums::is_enum(&ext.target.name) && ext.traits.is_empty() {
            report(
                Diagnostic::error(format!(
                    "cannot extend enum '{}' without a trait: declare its methods inside the enum",
                    shown
                ))
                .at(ext.loc),
            );
            return;
        }
        if !crate::enums::is_enum(&ext.target.name)
            && let Some(error) = ext.methods.iter().find_map(|m| number_operator_error(m, &shown))
        {
            report(error);
            return;
        }
        let mut functions: Vec<FunctionDef> = ext.methods.iter().map(|m| as_function(m, &key)).collect();
        for trait_name in &ext.traits {
            let Some(def) = module.traits.iter().find(|t| t.name == trait_name.name) else { continue };
            let mut map: Vec<(String, TypeName)> =
                def.generic_params.iter().map(|p| p.name.clone()).zip(trait_name.sub_types.iter().cloned()).collect();
            map.push(("this".to_string(), TypeName::new(&key)));
            map.push((crate::passes::closures::TRAIT_SELF.to_string(), TypeName::new(&key)));
            for required in &def.methods {
                // Only trait values are copied through this member, and a
                // value type is never one.
                if required.name == crate::passes::copies::COPY_TRAIT_METHOD {
                    continue;
                }
                let set = set_name(&required.name);
                let declared = |ty: &TypeName| {
                    let mut ty = ty.clone();
                    replace_map(&mut ty, &map);
                    crate::passes::check_function_types::canonical(&ty)
                };
                let wanted: Vec<TypeName> = required.parameters.iter().map(|p| declared(&p.ty)).collect();
                let has = ext.methods.iter().any(|m| {
                    set_name(&m.name) == set
                        && m.is_static == required.is_static
                        && m.parameters.len() == wanted.len()
                        && m.parameters.iter().zip(&wanted).all(|(p, w)| crate::passes::check_function_types::canonical(&p.ty) == *w)
                });
                if has || functions.iter().any(|f| f.name == crate::enums::method_name(&key, set) && f.trait_default.is_some()) {
                    continue;
                }
                if required.body.is_none() {
                    report(
                        Diagnostic::error(format!(
                            "'{}' does not implement '{}', required by trait '{}'",
                            shown,
                            set,
                            trait_name.display()
                        ))
                        .at(ext.loc)
                        .with_note(format!("'{}' declared here", set), Some(required.loc)),
                    );
                    return;
                }
                // The trait's default, for this type.
                let mut copy = required.clone();
                replace_map(&mut copy.ty, &map);
                for bound in copy.generic_params.iter_mut().flat_map(|p| &mut p.bounds) {
                    replace_map(&mut bound.ty, &map);
                }
                for p in &mut copy.parameters {
                    replace_map(&mut p.ty, &map);
                }
                if let Some(body) = &mut copy.body {
                    crate::passes::specialize_structs::substitute_block(body, &map);
                }
                copy.name = set.to_string();
                copy.owner = ext.loc;
                let mut function = as_function(&copy, &key);
                function.trait_default = Some(def.methods.iter().map(|m| set_name(&m.name).to_string()).collect());
                functions.push(function);
            }
        }
        added.extend(functions);
        let ext = &mut module.extensions[i];
        ext.methods.clear();
        // Nothing for `resolve_resolvables` or `apply_extensions` to find:
        // the methods are functions now.
        ext.resolved = Some(key);
    }
    module.functions.extend(added);
}

/// Why operator `m` cannot be declared in an extension of number type
/// `shown`, or `None` when it can (or is not an operator). Such an operator
/// is for a number on the left of a type that has no built-in operator
/// (`2.0 * v`), so it takes exactly one operand, and not a number, `bool`,
/// enum or pointer, for which the built-in operator applies.
fn number_operator_error(m: &FunctionDef, shown: &str) -> Option<Diagnostic> {
    let name = set_name(&m.name);
    if name.is_empty() || !name.bytes().all(|b| b.is_ascii_punctuation()) {
        return None;
    }
    if m.is_static || m.parameters.len() != 1 {
        return Some(
            Diagnostic::error(format!(
                "operator '{}' in an extension of '{}' must take one operand: the '{}' is the left operand",
                name, shown, shown
            ))
            .at(m.loc),
        );
    }
    let operand = &m.parameters[0];
    if operand.ty.is_pointer() || is_value_type(&operand.ty) || crate::enums::is_enum(&operand.ty.to_string()) {
        let at = if operand.type_loc.is_none() { m.loc } else { operand.type_loc };
        return Some(
            Diagnostic::error(format!(
                "operator '{}' of '{}' cannot take an operand of type '{}': the built-in operator applies",
                name,
                shown,
                crate::casts::spelled(&operand.ty)
            ))
            .at(at),
        );
    }
    None
}

/// Method `m` of value type `key` as its function `key::m`: an instance
/// method takes the value as its first parameter, `this`.
fn as_function(m: &FunctionDef, key: &str) -> FunctionDef {
    let mut f = m.clone();
    f.name = crate::enums::method_name(key, &m.name);
    f.parent = None;
    if !m.is_static {
        f.parameters.insert(0, crate::enums::this_parameter(key));
    }
    f
}

/// Turns a static call on a value type written by its name (`int.zero()`)
/// into its function, `i32::zero()`; an enum's are turned by
/// `enums::resolve_enum_cases`.
pub fn resolve_static_calls(module: &mut Module) {
    if !module.functions.iter().any(|f| f.name.contains("::") && !f.name.split("::").next().is_some_and(crate::enums::is_enum)) {
        return;
    }
    crate::passes::closures::for_each_expression_mut(module, &mut |e: &mut Expression| {
        if let Expression::MethodCall { this, method, args, loc } = e
            && let Expression::SymbolRef { id, .. } = this.as_ref()
            && !crate::enums::is_enum(id)
            && let Some(key) = key(id)
            && crate::enums::method_is_static(&key, method) == Some(true)
        {
            *e = Expression::FunctionCall { function: crate::enums::method_name(&key, method), args: std::mem::take(args), loc: *loc };
        }
    });
}
