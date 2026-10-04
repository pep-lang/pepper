//! `[Cold]` (#640): a function rarely called, such as a slow path, which
//! codegen keeps out of line (LLVM `cold` and `noinline`) so the callers'
//! fast paths stay small.

use crate::model::{FunctionDef, Module};
use pepper_parser::ast::{self, Expression};
use pepper_parser::diagnostic::{Diagnostic, Loc};

/// The attribute that keeps a function out of line.
pub const COLD_ATTRIBUTE: &str = "Cold";

/// Whether a function whose attributes are `attributes` is marked `[Cold]`.
pub fn is_cold(attributes: &[ast::Attribute]) -> bool {
    attributes.iter().any(|a| a.name() == Some(COLD_ATTRIBUTE))
}

/// Reports a `[Cold]` with arguments, and one on anything but a function,
/// method or constructor.
pub fn check_cold(module: &Module) -> Result<(), Diagnostic> {
    let function = |f: &FunctionDef| -> Result<(), Diagnostic> {
        for attribute in f.attributes.iter().filter(|a| a.name() == Some(COLD_ATTRIBUTE)) {
            if !matches!(attribute.body, Expression::SymbolRef { .. }) {
                return Err(Diagnostic::error("'Cold' takes no arguments").at(Loc::new(f.loc.file, attribute.body.span())));
            }
        }
        Ok(())
    };
    for f in &module.functions {
        function(f)?;
    }
    for st in &module.structs {
        for f in st.method_members.iter().chain(&st.constructors).chain(&st.generic_methods) {
            function(f)?;
        }
        let misplaced = st.attributes.iter().map(|a| (a, st.loc)).chain(st.field_members.iter().flat_map(|field| field.attributes.iter().map(move |a| (a, field.loc))));
        for (attribute, loc) in misplaced {
            if attribute.name() == Some(COLD_ATTRIBUTE) {
                let name = match &attribute.body {
                    Expression::FunctionCall { function, .. } => function.span(),
                    body => body.span(),
                };
                return Err(Diagnostic::error("'Cold' applies only to a function, method or constructor").at(Loc::new(loc.file, name)));
            }
        }
    }
    for f in module.traits.iter().flat_map(|t| &t.methods).chain(module.extensions.iter().flat_map(|e| &e.methods)) {
        function(f)?;
    }
    Ok(())
}
