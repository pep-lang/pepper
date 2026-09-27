//! Platform selection: evaluates `Target(...)` attribute predicates against the
//! host (the compile target) and drops top-level declarations and attributed
//! blocks that do not match. Runs before `struct_body::apply` so filtered-out
//! code never reaches synthesis or codegen.
//!
//! The only platform-selection attribute is `Target(...)`, which takes exactly
//! one argument: a boolean expression built from `OS(v)` / `Arch(v)` calls,
//! combined with `&&`/`||` (and `and`/`or`) and negated with `!`. Example:
//! `[Target(OS(Windows) && Arch(x64))]`.

use crate::model::*;
use pepper_parser::ast::{self, Expression};
use pepper_parser::parser::parsers::{
    contains_platform_predicate, is_os_or_arch_name, is_platform_predicate_name,
};
use std::env::consts;

/// Evaluate one attribute body against the host platform.
///
/// - Bare symbols that are not predicates (`[Export]`, `[Inline]`) are ignored (true).
/// - A bare `Target` without a call is an error.
/// - `Target(expr)`: `expr` must be a single boolean predicate over `OS(v)` /
///   `Arch(v)`; the declaration is kept iff it evaluates true on this host.
/// - Calls with other names (`[Align(8)]`) are ignored (true).
fn evaluate(body: &Expression, attr: &ast::Attribute) -> Result<bool, String> {
    match body {
        Expression::SymbolRef { id, .. } => {
            if is_platform_predicate_name(&id) {
                Err(format!("platform predicate `{id}` used without a value in {attr}"))
            } else {
                Ok(true)
            }
        }
        Expression::FunctionCall { function, arguments, .. } => match function.as_ref() {
            Expression::SymbolRef { id, .. } if is_platform_predicate_name(&id) => {
                let [arg] = arguments.as_slice() else {
                    return Err(format!(
                        "Target takes exactly one value (a boolean over OS(...) and Arch(...)) in {attr}"
                    ));
                };
                evaluate_predicate(arg, attr)
            }
            // Non-predicate attribute call (`[Export("x")]`) — ignore.
            _ => Ok(true),
        },
        // Top-level `!` / `&&` / `||` is rejected by the parser; defensive.
        _ => Err(bad_body(attr)),
    }
}

/// Evaluate the single boolean argument of `Target(...)`: `OS(v)` / `Arch(v)`
/// calls, `!`, and `&&`/`||` (with `and`/`or`).
fn evaluate_predicate(e: &Expression, attr: &ast::Attribute) -> Result<bool, String> {
    match e {
        Expression::FunctionCall { function, arguments, .. } => match function.as_ref() {
            Expression::SymbolRef { id, .. } if is_os_or_arch_name(&id) => {
                if id.to_ascii_lowercase() == "os" {
                    os_matches(arguments, attr)
                } else {
                    arch_matches(arguments, attr)
                }
            }
            Expression::SymbolRef { id, .. } if is_platform_predicate_name(&id) => Err(format!(
                "`{id}` cannot be nested inside Target(...) in {attr}"
            )),
            Expression::SymbolRef { id, .. } => Err(format!(
                "unknown predicate `{id}` (expected OS or Arch) in {attr}"
            )),
            _ => Err(bad_body(attr)),
        },
        Expression::Unary { op, prefix, operand, .. } => {
            if *prefix && op == "!" {
                Ok(!evaluate_predicate(operand, attr)?)
            } else {
                Err(bad_body(attr))
            }
        }
        Expression::Binary { lhs, op, rhs, .. } => match op.as_str() {
            // Both operands are evaluated (no short-circuit) so a malformed
            // predicate in either half is reported on every host.
            "&&" | "and" => {
                let (l, r) = (evaluate_predicate(lhs, attr)?, evaluate_predicate(rhs, attr)?);
                Ok(l && r)
            }
            "||" | "or" => {
                let (l, r) = (evaluate_predicate(lhs, attr)?, evaluate_predicate(rhs, attr)?);
                Ok(l || r)
            }
            _ => Err(bad_body(attr)),
        },
        Expression::SymbolRef { id, .. } => Err(format!(
            "bare symbol `{id}` is not a predicate; expected OS(...) or Arch(...) in {attr}"
        )),
        _ => Err(bad_body(attr)),
    }
}

fn bad_body(attr: &ast::Attribute) -> String {
    format!("invalid platform predicate in {attr}")
}

fn os_matches(arguments: &[Expression], attr: &ast::Attribute) -> Result<bool, String> {
    let [value] = arguments else {
        return Err(format!("OS predicate takes exactly one value in {attr}"));
    };
    let Expression::SymbolRef { id, .. } = value else {
        return Err(format!(
            "OS predicate value must be a symbol (Windows, Mac, MacOS, Linux) in {attr}"
        ));
    };
    let host = match consts::OS {
        "windows" => Some("windows"),
        "macos" => Some("macos"),
        "linux" => Some("linux"),
        _ => None,
    };
    match host {
        // Supported host: validate the value (unknown values are a hard
        // error) and compare.
        Some(h) => matches_os_value(id, h, attr),
        // Unsupported host: no OS predicate can match.
        None => Ok(false),
    }
}

fn matches_os_value(value: &str, host: &str, attr: &ast::Attribute) -> Result<bool, String> {
    match value.to_ascii_lowercase().as_str() {
        "windows" => Ok(host == "windows"),
        "mac" | "macos" => Ok(host == "macos"),
        "linux" => Ok(host == "linux"),
        _ => Err(format!(
            "unknown OS value `{value}` (expected Windows, Mac, MacOS, Linux) in {attr}"
        )),
    }
}

fn arch_matches(arguments: &[Expression], attr: &ast::Attribute) -> Result<bool, String> {
    let [value] = arguments else {
        return Err(format!("Arch predicate takes exactly one value in {attr}"));
    };
    let Expression::SymbolRef { id, .. } = value else {
        return Err(format!(
            "Arch predicate value must be a symbol (x64, aarch64) in {attr}"
        ));
    };
    let host = match consts::ARCH {
        "x86_64" => Some("x64"),
        "aarch64" => Some("aarch64"),
        _ => None,
    };
    match host {
        // Supported host: validate the value (unknown values are a hard
        // error) and compare.
        Some(h) => {
            let v = id.to_ascii_lowercase();
            if v == h {
                Ok(true)
            } else if v == "x64" || v == "aarch64" {
                Ok(false)
            } else {
                Err(format!(
                    "unknown Arch value `{id}` (expected x64, aarch64) in {attr}"
                ))
            }
        }
        // Unsupported host: no Arch predicate can match.
        None => Ok(false),
    }
}

/// Keep a node iff every attribute on it evaluates true (AND semantics).
/// Attributes that are not `Target(...)` selections (`[Export]`, `[Align(8)]`)
/// never drop anything.
fn keep(attributes: &[ast::Attribute]) -> Result<bool, String> {
    for attr in attributes {
        if !contains_platform_predicate(&attr.body) {
            continue;
        }
        if !evaluate(&attr.body, attr)? {
            return Ok(false);
        }
    }
    Ok(true)
}

/// Validate every attribute, reporting a malformed one, without short-circuiting
/// on a false predicate — so a bad attribute later in the list is still reported.
fn validate(attributes: &[ast::Attribute]) -> Result<(), String> {
    for attr in attributes {
        let _ = evaluate(&attr.body, attr)?;
    }
    Ok(())
}

/// Drop attributed blocks that do not match the host, recursing into nested
/// blocks, branches, and loops.
fn filter_block(block: &mut Block) -> Result<(), String> {
    let mut i = 0;
    while i < block.items.len() {
        match &mut block.items[i] {
            Statement::Block(inner) => {
                validate(&inner.attributes)?;
                let matched = keep(&inner.attributes)?;
                // Walk the contents either way: a malformed predicate nested
                // inside a dropped block must still be reported on every host.
                filter_block(inner)?;
                if !matched {
                    // `remove` shifts the next item into `i`; don't skip it.
                    block.items.remove(i);
                    continue;
                }
            }
            Statement::Branch(br) => {
                filter_block(&mut br.if_block)?;
                if let Some(else_block) = &mut br.else_block {
                    filter_block(else_block)?;
                }
            }
            Statement::While(w) => filter_block(&mut w.block)?,
            _ => {}
        }
        i += 1;
    }
    Ok(())
}

/// Walk a function body, validating and filtering attributed blocks inside.
fn walk_function_body(function: &mut FunctionDef) -> Result<(), String> {
    if let Some(body) = &mut function.body {
        filter_block(body)?;
    }
    Ok(())
}

/// Validate a function's own attributes, then walk its body. Used for
/// functions that survive filtering (methods, constructors, …).
fn filter_function(function: &mut FunctionDef) -> Result<(), String> {
    validate(&function.attributes)?;
    walk_function_body(function)
}

/// Apply platform selection to the whole module. Runs before
/// `struct_body::apply` so filtered code is never synthesized over.
pub fn apply_platform_filters(module: &mut Module) -> Result<(), String> {
    // Validate every top-level predicate first so a bad attribute in dropped
    // code is still reported. `validate` evaluates each attribute (no
    // short-circuit on a false one) so a malformed later attribute is caught.
    for f in &module.functions {
        validate(&f.attributes)?;
    }
    for s in &module.structs {
        validate(&s.attributes)?;
    }
    for t in &module.traits {
        validate(&t.attributes)?;
    }
    for e in &module.extensions {
        validate(&e.attributes)?;
    }
    for x in &module.externs {
        validate(&x.attributes)?;
    }

    // Top-level functions: keep iff all attributes match. Bodies are walked
    // whether or not the function survives, so a malformed predicate inside is
    // reported on every host (attributes were already validated above).
    let mut kept = Vec::with_capacity(module.functions.len());
    for f in std::mem::take(&mut module.functions) {
        let mut f = f;
        walk_function_body(&mut f)?;
        if keep(&f.attributes).unwrap_or(false) {
            kept.push(f);
        }
    }
    module.functions = kept;

    // Members of about-to-be-dropped structs/traits/extensions are filtered
    // here (before `retain`), mirroring the top-level validate-then-retain, so
    // a misspelled predicate in dropped code is reported on every host.
    // `filter_function` validates the member's own attributes and walks its
    // body; for constructors/destructors/acquire/release (non-Option fields,
    // never dropped) this also validates their attributes.
    for s in &mut module.structs {
        for m in &mut s.method_members {
            filter_function(m)?;
        }
        filter_function(&mut s.constructor)?;
        filter_function(&mut s.destructor)?;
        filter_function(&mut s.acquire)?;
        filter_function(&mut s.release)?;
    }
    for t in &mut module.traits {
        for m in &mut t.methods {
            filter_function(m)?;
        }
    }
    for e in &mut module.extensions {
        for m in &mut e.methods {
            filter_function(m)?;
        }
    }

    module.structs.retain(|s| keep(&s.attributes).unwrap_or(false));
    module.traits.retain(|t| keep(&t.attributes).unwrap_or(false));
    module.extensions.retain(|e| keep(&e.attributes).unwrap_or(false));
    module.externs.retain(|x| keep(&x.attributes).unwrap_or(false));

    // Members of surviving declarations: drop the ones that don't match.
    for s in &mut module.structs {
        s.method_members.retain(|m| keep(&m.attributes).unwrap_or(false));
    }
    for t in &mut module.traits {
        t.methods.retain(|m| keep(&m.attributes).unwrap_or(false));
    }
    for e in &mut module.extensions {
        e.methods.retain(|m| keep(&m.attributes).unwrap_or(false));
    }
    Ok(())
}
