//! Which runtime checks generated code makes (#265): the build's
//! (`--no-runtime-checks`), and those one function turns off with
//! `[Unsafe("overflow,bounds")]`, whose argument names checks as the
//! command-line option does.

use crate::model::{FunctionDef, Module};
use pepper_parser::ast::{self, Expression, Literal};
use pepper_parser::diagnostic::{Diagnostic, Loc};

/// The attribute that turns runtime checks off in one function's body.
pub const UNSAFE_ATTRIBUTE: &str = "Unsafe";

/// Which runtime checks the generated code performs. Every check is on by
/// default; `--no-runtime-checks` turns kinds off from `-O1` up.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct RuntimeChecks {
    /// `+`, `-`, `*`, `**`, unary `-`, `++`, `--` and compound assignment
    /// overflowing their type.
    pub overflow: bool,
    /// Division or remainder by zero, and `MIN / -1` of a signed type.
    pub divide: bool,
    /// A shift count of at least the type's width.
    pub shift: bool,
    /// Array and string indexing out of range (`_pep_check_bounds`).
    pub bounds: bool,
    /// Calling through, or matching on, a null reference.
    pub null: bool,
}

impl Default for RuntimeChecks {
    fn default() -> Self {
        RuntimeChecks::ALL
    }
}

impl RuntimeChecks {
    /// Every check on.
    pub const ALL: RuntimeChecks = RuntimeChecks { overflow: true, divide: true, shift: true, bounds: true, null: true };

    /// The names `--no-runtime-checks` accepts, besides `all`.
    pub const NAMES: [&'static str; 5] = ["overflow", "divide", "shift", "bounds", "null"];

    /// Every check on except those named in `list`, a comma-separated list
    /// of [`Self::NAMES`] or `all` (`--no-runtime-checks=overflow,shift`).
    pub fn without(list: &str) -> Result<RuntimeChecks, String> {
        Self::without_in(list, "'--no-runtime-checks'")
    }

    /// [`Self::without`], naming `what` (`'--no-runtime-checks'`,
    /// `'Unsafe'`) in the error for an unknown name.
    pub fn without_in(list: &str, what: &str) -> Result<RuntimeChecks, String> {
        let mut checks = RuntimeChecks::ALL;
        for name in list.split(',').map(str::trim) {
            match name {
                "overflow" => checks.overflow = false,
                "divide" => checks.divide = false,
                "shift" => checks.shift = false,
                "bounds" => checks.bounds = false,
                "null" => checks.null = false,
                "all" => checks = RuntimeChecks::NONE,
                _ => {
                    return Err(format!(
                        "unknown runtime check '{}' in {}: expected {} or 'all'",
                        name,
                        what,
                        Self::NAMES.map(|n| format!("'{}'", n)).join(", ")
                    ));
                }
            }
        }
        Ok(checks)
    }

    /// Every check off.
    pub const NONE: RuntimeChecks = RuntimeChecks { overflow: false, divide: false, shift: false, bounds: false, null: false };

    /// The checks both `self` and `other` keep: a build's checks less those
    /// a function's `[Unsafe("...")]` turns off.
    pub fn and(self, other: RuntimeChecks) -> RuntimeChecks {
        RuntimeChecks {
            overflow: self.overflow && other.overflow,
            divide: self.divide && other.divide,
            shift: self.shift && other.shift,
            bounds: self.bounds && other.bounds,
            null: self.null && other.null,
        }
    }

    /// The names of the checks that are off, in [`Self::NAMES`] order: empty
    /// with every check on. Part of the build cache's key.
    pub fn removed(&self) -> Vec<&'static str> {
        let on = [self.overflow, self.divide, self.shift, self.bounds, self.null];
        Self::NAMES.iter().zip(on).filter(|&(_, on)| !on).map(|(name, _)| *name).collect()
    }
}


/// The checks a function whose attributes are `attributes` keeps, as its
/// `[Unsafe("...")]` says; every check when it has none. An invalid list
/// (which `check_unsafe` reports) keeps every check.
pub fn function_checks(attributes: &[ast::Attribute]) -> RuntimeChecks {
    attributes
        .iter()
        .filter(|a| a.name() == Some(UNSAFE_ATTRIBUTE))
        .filter_map(|a| unsafe_list(a).and_then(|(list, _)| RuntimeChecks::without_in(&list, "'Unsafe'").ok()))
        .fold(RuntimeChecks::ALL, RuntimeChecks::and)
}

/// The list an `[Unsafe("...")]` names and the span of its string.
fn unsafe_list(attribute: &ast::Attribute) -> Option<(String, ast::Span)> {
    let arguments = attribute.arguments();
    let [argument] = arguments.as_slice() else { return None };
    match argument.value {
        Expression::Literal { value: Literal::String(text), span, .. } if argument.name.is_none_or(|(name, _)| name == "checks") => {
            Some((text.clone(), *span))
        }
        _ => None,
    }
}

/// Reports an `[Unsafe]` whose argument is not one string naming known
/// checks, and one on anything but a function, method or constructor.
pub fn check_unsafe(module: &Module) -> Result<(), Diagnostic> {
    let function = |f: &FunctionDef| -> Result<(), Diagnostic> {
        for attribute in f.attributes.iter().filter(|a| a.name() == Some(UNSAFE_ATTRIBUTE)) {
            let at = Loc::new(f.loc.file, attribute.body.span());
            let Some((list, span)) = unsafe_list(attribute) else {
                return Err(Diagnostic::error("'Unsafe' takes one string naming the checks to remove, such as 'Unsafe(\"overflow,bounds\")'").at(at));
            };
            RuntimeChecks::without_in(&list, "'Unsafe'").map_err(|message| Diagnostic::error(message).at(Loc::new(f.loc.file, span)))?;
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
            if attribute.name() == Some(UNSAFE_ATTRIBUTE) {
                let name = match &attribute.body {
                    Expression::FunctionCall { function, .. } => function.span(),
                    body => body.span(),
                };
                return Err(Diagnostic::error("'Unsafe' applies only to a function, method or constructor").at(Loc::new(loc.file, name)));
            }
        }
    }
    for f in module.traits.iter().flat_map(|t| &t.methods).chain(module.extensions.iter().flat_map(|e| &e.methods)) {
        function(f)?;
    }
    Ok(())
}
