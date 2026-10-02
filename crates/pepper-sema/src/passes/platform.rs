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
use pepper_parser::diagnostic::FileId;
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
        // A qualified attribute (`[serialize.Ignore]`) is never a predicate.
        Expression::MemberAccess { .. } | Expression::TypeLiteral(_) => Ok(true),
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

thread_local! {
    /// `(std::env::consts::OS, std::env::consts::ARCH)` values that replace the
    /// real host's while `with_simulated_host` runs.
    static SIMULATED_HOST: std::cell::RefCell<Option<(String, String)>> =
        const { std::cell::RefCell::new(None) };
}

/// Evaluate `Target(...)` predicates inside `f` as if the host were `os` /
/// `arch` (spelled as `std::env::consts` spells them: `"windows"`,
/// `"macos"`, `"linux"`; `"x86_64"`, `"aarch64"`). For tests that push
/// another platform's code through the platform filter, sema and codegen on
/// this host, to check it compiles; the result can be neither linked nor
/// run here. Thread-local, so concurrent tests do not see each other's host.
pub fn with_simulated_host<R>(os: &str, arch: &str, f: impl FnOnce() -> R) -> R {
    let previous = SIMULATED_HOST.with(|h| h.replace(Some((os.to_string(), arch.to_string()))));
    // Restore on unwind too, so a failing test does not leak its host.
    struct Restore(Option<(String, String)>);
    impl Drop for Restore {
        fn drop(&mut self) {
            let previous = self.0.take();
            SIMULATED_HOST.with(|h| *h.borrow_mut() = previous);
        }
    }
    let _restore = Restore(previous);
    f()
}

/// The OS `Target(...)` predicates evaluate against: the real host's, or
/// the simulated one inside `with_simulated_host`.
pub fn host_os() -> String {
    SIMULATED_HOST
        .with(|h| h.borrow().as_ref().map(|(os, _)| os.clone()))
        .unwrap_or_else(|| consts::OS.to_string())
}

/// The architecture `Target(...)` predicates evaluate against (see
/// `host_os`).
pub fn host_arch() -> String {
    SIMULATED_HOST
        .with(|h| h.borrow().as_ref().map(|(_, arch)| arch.clone()))
        .unwrap_or_else(|| consts::ARCH.to_string())
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
    let host = match host_os().as_str() {
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
    let host = match host_arch().as_str() {
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
pub fn keep(attributes: &[ast::Attribute]) -> Result<bool, String> {
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
fn validate(attributes: &[ast::Attribute], file: FileId) -> Result<(), Diagnostic> {
    for attr in attributes {
        evaluate(&attr.body, attr).map_err(|e| Diagnostic::error(e).at(Loc::new(file, attr.span)))?;
    }
    Ok(())
}

/// Drop attributed blocks that do not match the host, recursing into nested
/// blocks, branches, and loops.
fn filter_block(block: &mut Block, file: FileId) -> Result<(), Diagnostic> {
    let mut i = 0;
    while i < block.items.len() {
        match &mut block.items[i] {
            Statement::Block(inner) => {
                validate(&inner.attributes, file)?;
                let matched = keep(&inner.attributes).map_err(Diagnostic::error)?;
                // Walk the contents either way: a malformed predicate nested
                // inside a dropped block must still be reported on every host.
                filter_block(inner, file)?;
                if !matched {
                    // `remove` shifts the next item into `i`; don't skip it.
                    block.items.remove(i);
                    continue;
                }
            }
            Statement::Branch(br) => {
                filter_block(&mut br.if_block, file)?;
                if let Some(else_block) = &mut br.else_block {
                    filter_block(else_block, file)?;
                }
            }
            Statement::While(w) => filter_block(&mut w.block, file)?,
            _ => {}
        }
        i += 1;
    }
    Ok(())
}

/// Walk a function body, validating and filtering attributed blocks inside.
fn walk_function_body(function: &mut FunctionDef, file: FileId) -> Result<(), Diagnostic> {
    if let Some(body) = &mut function.body {
        filter_block(body, file)?;
    }
    Ok(())
}

/// Validate a function's own attributes, then walk its body. Used for
/// functions that survive filtering (methods, constructors, …).
fn filter_function(function: &mut FunctionDef, file: FileId) -> Result<(), Diagnostic> {
    // Synthesized members carry no location; their errors point into the
    // owner's file.
    let file = function.loc.known().map_or(file, |l| l.file);
    validate(&function.attributes, file)?;
    walk_function_body(function, file)
}

/// Apply platform selection to the whole module. Runs before
/// `struct_body::apply` so filtered code is never synthesized over.
pub fn apply_platform_filters(module: &mut Module) -> Result<(), Diagnostic> {
    // Validate every top-level predicate first so a bad attribute in dropped
    // code is still reported. `validate` evaluates each attribute (no
    // short-circuit on a false one) so a malformed later attribute is caught.
    for f in &module.functions {
        validate(&f.attributes, f.loc.file)?;
    }
    for s in &module.structs {
        validate(&s.attributes, s.loc.file)?;
    }
    for t in &module.traits {
        validate(&t.attributes, t.loc.file)?;
    }
    for e in &module.extensions {
        validate(&e.attributes, e.loc.file)?;
    }
    for x in &module.externs {
        validate(&x.attributes, x.loc.file)?;
    }
    for g in &module.globals {
        validate(&g.attributes, g.loc.file)?;
    }
    for a in &module.type_aliases {
        validate(&a.attributes, a.loc.file)?;
    }
    for e in &module.enums {
        validate(&e.attributes, e.loc.file)?;
        for case in &e.cases {
            validate(&case.attributes, e.loc.file)?;
        }
    }

    // Top-level functions: keep iff all attributes match. Bodies are walked
    // whether or not the function survives, so a malformed predicate inside is
    // reported on every host (attributes were already validated above).
    let mut kept = Vec::with_capacity(module.functions.len());
    for f in std::mem::take(&mut module.functions) {
        let mut f = f;
        let file = f.loc.file;
        walk_function_body(&mut f, file)?;
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
        let file = s.loc.file;
        for m in &mut s.method_members {
            filter_function(m, file)?;
        }
        for constructor in &mut s.constructors {
            filter_function(constructor, file)?;
        }
        filter_function(&mut s.destructor, file)?;
        filter_function(&mut s.acquire, file)?;
        filter_function(&mut s.release, file)?;
    }
    for t in &mut module.traits {
        let file = t.loc.file;
        for m in &mut t.methods {
            filter_function(m, file)?;
        }
    }
    for e in &mut module.extensions {
        let file = e.loc.file;
        for m in &mut e.methods {
            filter_function(m, file)?;
        }
    }

    module.structs.retain(|s| keep(&s.attributes).unwrap_or(false));
    module.traits.retain(|t| keep(&t.attributes).unwrap_or(false));
    module.extensions.retain(|e| keep(&e.attributes).unwrap_or(false));
    module.externs.retain(|x| keep(&x.attributes).unwrap_or(false));
    // Aliases resolve after this pass with "last definition wins", so a
    // per-platform pair (`[Target(OS(Windows))] type H = ...;` and its
    // `!OS(Windows)` twin) must lose its dropped half here.
    module.globals.retain(|g| keep(&g.attributes).unwrap_or(false));
    module.type_aliases.retain(|a| keep(&a.attributes).unwrap_or(false));
    // A dropped case keeps the others' values: the builder numbered them all.
    module.enums.retain(|e| keep(&e.attributes).unwrap_or(false));
    for e in &mut module.enums {
        e.cases.retain(|c| keep(&c.attributes).unwrap_or(false));
    }

    // Members of surviving declarations: drop the ones that don't match.
    for s in &mut module.structs {
        s.method_members.retain(|m| keep(&m.attributes).unwrap_or(false));
        // A reference enum's case goes with its static method, which carries
        // the case's attributes; its fields stay, holding their defaults.
        if let Some(cases) = &mut s.enum_cases {
            cases.retain(|c| keep(&c.attributes).unwrap_or(false));
        }
    }
    for t in &mut module.traits {
        t.methods.retain(|m| keep(&m.attributes).unwrap_or(false));
    }
    for e in &mut module.extensions {
        e.methods.retain(|m| keep(&m.attributes).unwrap_or(false));
    }
    Ok(())
}
