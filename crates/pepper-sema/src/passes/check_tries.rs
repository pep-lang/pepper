//! Checks each `?` (lowered by the builder's `tries` module) once its
//! operand's type is known: the operand is a `Result` or an `Optional`, the
//! enclosing function returns the same kind, and a `Result`'s error converts
//! to the function's error type. Without this check the lowered calls
//! (`_propagates`, `_from_residual`) would fail with errors that name them.

use crate::builder::TRY_LOCAL;
use crate::errors::report;
use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::diagnostic::Diagnostic;

const RESULT: &str = "Result";
const OPTIONAL: &str = "Optional";

/// Runs on the concrete code: generic bases are checked in their
/// specializations, by the run after the specialization loop.
pub fn check_tries(module: &Module) {
    let methods = module
        .structs
        .iter()
        .filter(|s| s.generic_params.is_empty())
        .flat_map(|s| s.method_members.iter().chain(&s.constructors).chain([&s.destructor]));
    for function in module.functions.iter().chain(methods) {
        if function.is_generic_func {
            continue;
        }
        if let Some(body) = &function.body {
            check_block(module, function, body);
        }
    }
}

fn check_block(module: &Module, function: &FunctionDef, block: &Block) {
    for item in &block.items {
        match item {
            Statement::Declaration(Declaration::Variable(v)) if v.hidden && v.name.starts_with(TRY_LOCAL) => {
                check(module, function, v);
            }
            Statement::Block(b) => check_block(module, function, b),
            Statement::Branch(b) => {
                check_block(module, function, &b.if_block);
                if let Some(e) = &b.else_block {
                    check_block(module, function, e);
                }
            }
            Statement::While(w) => check_block(module, function, &w.block),
            _ => {}
        }
    }
}

/// The base name of `ty` (`Result` of `Result<int, Error>`), if it is a
/// `Result` or an `Optional`.
fn kind(ty: &TypeName) -> Option<&'static str> {
    [RESULT, OPTIONAL].into_iter().find(|k| ty.name == *k)
}

/// A `Result`'s error type: its second argument, else the default `Error`.
fn error_type(ty: &TypeName) -> TypeName {
    ty.sub_types.get(1).cloned().unwrap_or_else(|| TypeName::new("Error"))
}

fn check(module: &Module, function: &FunctionDef, hidden: &VariableDef) {
    let operand = &hidden.ty;
    if operand.contains_auto() {
        return;
    }
    let at = hidden.loc;
    let Some(operand_kind) = kind(operand) else {
        report(Diagnostic::error(format!("'?' requires a Result or an Optional, not '{}'", operand.display())).at(at));
        return;
    };
    let returns = &function.ty;
    if returns.contains_auto() {
        return;
    }
    if kind(returns) != Some(operand_kind) {
        let article = if operand_kind == RESULT { "a" } else { "an" };
        report(
            Diagnostic::error(format!("'?' requires the enclosing function to return {} {}", article, operand_kind))
                .at(at)
                .with_note(format!("'{}' returns '{}'", function.name, returns.display()), Some(function.loc)),
        );
        return;
    }
    if operand_kind == OPTIONAL {
        return;
    }
    let (from, to) = (error_type(operand), error_type(returns));
    if from == to || converts(module, &from, &to) {
        return;
    }
    report(
        Diagnostic::error(format!("cannot convert error type '{}' to '{}'", from.display(), to.display()))
            .at(at)
            .with_note(format!("an [Implicit] constructor of '{}' from '{}' would convert it", to.display(), from.display()), None),
    );
}

/// Whether a `from` converts to `to` where a `to` is expected: through an
/// `[Implicit]` constructor of struct `to`, or as a value of a type that is
/// not a struct (numbers widen; traits, pointers and the rest are left to
/// the argument checks).
fn converts(module: &Module, from: &TypeName, to: &TypeName) -> bool {
    match module.structs.iter().find(|s| s.ty == *to) {
        Some(target) => target.implicit_from() == Some(from),
        None => true,
    }
}
