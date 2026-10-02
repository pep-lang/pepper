//! Collection literals as the builder lowers them. `[a, b, c]` is
//! `_array_literal(a)._literal_append(b)._literal_append(c)` (runtime/array.pep)
//! and `[k1: v1, k2: v2]` is `_map_literal(k1, v1)._literal_insert(k2, v2)`
//! (runtime/hash.pep): a start call, then one step per later element.
//!
//! A chain nests one level per element, and every pass and codegen recurse
//! down it, so a literal of tens of thousands of elements would overflow the
//! stack. A literal with more than [`CHUNK`] steps is instead a balanced tree
//! of short chains over one collection:
//!
//! ```text
//! WithSubject(start,
//!     (Subject.step(e1)...step(e16))._literal_then(Subject.step(e17)...))
//! ```
//!
//! Each `_literal_then` evaluates its receiver, then its argument, and returns
//! the argument; all of them are the subject. The depth is at most
//! `CHUNK + log2(steps / CHUNK)`, whatever the length.

use crate::model::*;
use crate::type_name::TypeName;

/// The most steps one chain holds.
pub const CHUNK: usize = 16;

/// The method that joins two chains of a long literal.
const THEN: &str = "_literal_then";

/// The literal `start` followed by `steps`, each the arguments of one call of
/// method `step`, at `loc`. `subject` is the type of the collection a long
/// literal builds (auto until `resolve_implicit_types` types it).
pub fn build(start: Expression, steps: Vec<Vec<Expression>>, step: &str, subject: TypeName, loc: Loc) -> Expression {
    let chain = |this: Expression, steps: Vec<Vec<Expression>>| {
        steps.into_iter().fold(this, |this, args| Expression::MethodCall {
            this: Box::new(this),
            method: step.to_string(),
            args,
            loc,
        })
    };
    if steps.len() <= CHUNK {
        return chain(start, steps);
    }
    let id = subject_id(loc);
    let mut level: Vec<Expression> = vec![];
    let mut steps = steps.into_iter().peekable();
    while steps.peek().is_some() {
        let chunk: Vec<Vec<Expression>> = steps.by_ref().take(CHUNK).collect();
        level.push(chain(Expression::Subject { id, ty: subject.clone(), loc }, chunk));
    }
    while level.len() > 1 {
        let mut next = Vec::with_capacity(level.len().div_ceil(2));
        let mut nodes = level.into_iter();
        while let Some(left) = nodes.next() {
            next.push(match nodes.next() {
                Some(right) => Expression::MethodCall { this: Box::new(left), method: THEN.to_string(), args: vec![right], loc },
                None => left,
            });
        }
        level = next;
    }
    let body = level.pop().unwrap();
    Expression::WithSubject(Box::new(WithSubject { id, subject: start, body, null_message: None, loc }))
}

/// Whether `value` is a literal [`build`] made from a call of `start` (or of
/// a specialization `start<...>`) with `arity` arguments and steps `step`.
pub fn is(value: &Expression, start: &str, step: &str, arity: usize) -> bool {
    let (first, body) = match value {
        Expression::WithSubject(with) => (&with.subject, Some(&with.body)),
        other => (chain_start(other, step), None),
    };
    let started = match first {
        Expression::FunctionCall { function, args, .. } => {
            args.len() == arity && (function == start || function.strip_prefix(start).is_some_and(|rest| rest.starts_with('<')))
        }
        _ => false,
    };
    started && body.is_none_or(|body| matches!(body, Expression::MethodCall { method, .. } if method == THEN || method == step))
}

/// The start call of a literal [`is`] accepts, its steps' arguments in
/// order, and its location.
pub fn parts(value: Expression) -> (Expression, Vec<Vec<Expression>>, Loc) {
    match value {
        Expression::WithSubject(with) => {
            let WithSubject { subject, body, loc, .. } = *with;
            let mut steps = vec![];
            // Leaves left to right; the tree is shallow, but a stack keeps
            // this flat anyway.
            let mut pending = vec![body];
            while let Some(node) = pending.pop() {
                match node {
                    Expression::MethodCall { this, method, mut args, .. } if method == THEN => {
                        pending.push(args.pop().unwrap());
                        pending.push(*this);
                    }
                    leaf => steps.extend(chain_steps(leaf).1),
                }
            }
            (subject, steps, loc)
        }
        chain => {
            let (start, steps) = chain_steps(chain);
            let loc = start.loc();
            (start, steps, loc)
        }
    }
}

/// The receiver a chain of method calls starts from.
fn chain_start<'e>(mut value: &'e Expression, step: &str) -> &'e Expression {
    while let Expression::MethodCall { this, method, .. } = value
        && method == step
    {
        value = this;
    }
    value
}

/// A chain's start and the arguments of each of its calls, in order.
fn chain_steps(mut value: Expression) -> (Expression, Vec<Vec<Expression>>) {
    let mut steps = vec![];
    while let Expression::MethodCall { this, args, .. } = value {
        steps.push(args);
        value = *this;
    }
    steps.reverse();
    (value, steps)
}

/// The id of a long literal's `WithSubject`: made from its location, so a
/// program compiles the same way every time, with a bit no `match` site
/// (numbered from 0) or compound assignment (`properties::subject_id`) sets.
fn subject_id(at: Loc) -> usize {
    (1 << 61) | ((at.file.0 as usize) << 32) | at.span.start
}
