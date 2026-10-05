//! The `[__Reads]` methods of a `[__Lazy]` struct (`Array<T>`) run on a
//! null `this` when the object is empty and not yet allocated, reading its
//! fields as zero (see `model::LAZY_ATTRIBUTE`). So such a method must not
//! write a field of `this`, nor call a method on `this` that is not
//! `[__Reads]` itself: either would write through null. Each is an error at
//! the write or the call.

use crate::model::*;
use pepper_parser::diagnostic::Diagnostic;
use std::collections::HashSet;

pub fn check_lazy(module: &mut Module) {
    let mut reported: HashSet<Loc> = HashSet::new();
    for st in module.structs.iter().filter(|st| st.is_lazy()) {
        let reads: HashSet<&str> = st
            .method_members
            .iter()
            .filter(|m| has_attribute(&m.attributes, READS_ATTRIBUTE))
            .map(|m| m.name.as_str())
            .collect();
        for method in st.method_members.iter().filter(|m| reads.contains(m.name.as_str())) {
            let Some(body) = &method.body else { continue };
            let mut errors = vec![];
            super::visit_block(body, &mut |e| match e {
                Expression::Binary { op, lhs, loc, .. } if op.is_assignment() && writes_this(lhs) => {
                    errors.push((*loc, "a '[__Reads]' method cannot write a field of 'this'".to_string()));
                }
                Expression::MethodCall { this, method: called, loc, .. }
                    if matches!(this.as_ref(), Expression::ThisRef) && !called.starts_with("__") && !reads.contains(called.as_str()) =>
                {
                    errors.push((*loc, format!("a '[__Reads]' method cannot call '{}', which is not '[__Reads]'", called)));
                }
                _ => {}
            });
            for (at, message) in errors {
                if reported.insert(at) {
                    crate::errors::report(Diagnostic::error(message).at(at).with_note(format!("'{}' is '[__Reads]'", method.name), Some(method.loc)));
                }
            }
        }
    }
}

/// Whether the assignment target `lhs` is a field of `this`, or a slot of
/// a buffer one holds (`_data[i]`).
fn writes_this(lhs: &Expression) -> bool {
    match lhs {
        Expression::MemberRef { lhs, .. } => matches!(lhs.as_ref(), Expression::ThisRef) || writes_this(lhs),
        Expression::Index { lhs, .. } | Expression::ArrayIndex { lhs, .. } => writes_this(lhs),
        _ => false,
    }
}
