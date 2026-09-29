//! Errors found by the transform passes. The passes rewrite the model in
//! place and return nothing, so an error is reported here instead; the pass
//! driver stops after the pass that reported one (see `transform_pass`).
//! Thread-local, like the passes' other per-run state: concurrent compiles
//! (test threads) never see each other's errors.

use pepper_parser::diagnostic::Diagnostic;
use std::cell::RefCell;

thread_local! {
    static FIRST: RefCell<Option<Diagnostic>> = const { RefCell::new(None) };
}

/// Record an error. Only the first of a run is kept: later ones are usually
/// fallout from it.
pub(crate) fn report(diagnostic: Diagnostic) {
    FIRST.with(|f| {
        f.borrow_mut().get_or_insert(diagnostic);
    });
}

/// The error reported since the last call, if any, clearing it.
pub(crate) fn take() -> Option<Diagnostic> {
    FIRST.with(|f| f.borrow_mut().take())
}
