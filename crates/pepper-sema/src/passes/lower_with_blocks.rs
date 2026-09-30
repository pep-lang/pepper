//! Finish lowering `with` blocks (see `builder::with_block`) once types are
//! known. The builder leaves
//!
//! ```text
//! var x = __with_scope_N.enter();
//! if (<WithEntered(x)>) { body } else { other }
//! ```
//!
//! and this pass picks by `enter()`'s type:
//!
//! - struct or pointer: `if (!(x === __null)) { body } else { other }`, so a
//!   null result (an expired `Weak<T>`) skips the body;
//! - `void` (nothing to hand out): the hidden value becomes an expression
//!   statement and the body runs unconditionally;
//! - any other type: the body runs unconditionally.
//!
//! It also reports the `with`-specific errors: binding a `void` result,
//! `else` on a result that can never be null, and assigning to the binding.

use crate::errors::report;
use crate::model::*;
use crate::type_name::{self, TypeName};
use std::collections::{HashMap, HashSet};

pub fn lower_with_blocks(module: &mut Module) {
    let structs: HashSet<String> = module.structs.iter().map(|st| st.name.clone()).collect();
    let enter_types: HashMap<String, TypeName> = module
        .structs
        .iter()
        .filter_map(|st| st.method_members.iter().find(|m| m.name == "enter").map(|m| (st.name.clone(), m.ty.clone())))
        .collect();
    let types = Types { structs, enter_types };
    for st in &mut module.structs {
        // Generic bases never reach codegen; their `enter()` types are
        // still template parameters.
        if st.ty.is_generic() && st.name == st.ty.name {
            continue;
        }
        for method in st.method_members.iter_mut().chain([&mut st.constructor, &mut st.destructor]) {
            if let Some(body) = &mut method.body {
                lower_block(body, &types);
            }
        }
    }
    for function in &mut module.functions {
        if function.is_generic_func {
            continue;
        }
        if let Some(body) = &mut function.body {
            lower_block(body, &types);
        }
    }
}

struct Types {
    /// Every concrete struct name (function types included): nullable.
    structs: HashSet<String>,
    /// Struct name → what its `enter()` returns.
    enter_types: HashMap<String, TypeName>,
}

impl Types {
    fn nullable(&self, ty: &TypeName) -> bool {
        ty.is_pointer() || self.structs.contains(&ty.to_string())
    }
}

fn lower_block(block: &mut Block, types: &Types) {
    for stmt in &mut block.items {
        lower_statement(stmt, types);
    }
    // A lowered `with` is a block of [scope, value, Branch(WithEntered)].
    let [Statement::Declaration(Declaration::Variable(scope)), Statement::Declaration(Declaration::Variable(value)), Statement::Branch(branch)] =
        &mut block.items[..]
    else {
        return;
    };
    if !matches!(branch.condition, Expression::WithEntered(_)) {
        return;
    }
    if types.structs.contains(&scope.ty.to_string()) && !types.enter_types.contains_key(&scope.ty.to_string()) {
        report(
            Diagnostic::error(format!("'{}' cannot be used in a 'with' block: it has no 'enter()' method", scope.ty))
                .at(scope.loc)
                .with_note("a 'with' scope implements Scoped<T>: 'T enter()' and 'exit()'", None),
        );
        return;
    }
    let hidden = value.hidden;
    // Inference leaves a local initialized from a `void` call untyped: ask
    // the scope's struct what `enter()` returns. A method declared without
    // a return type (`enter() { ... }`) returns nothing.
    let mut ty = value.ty.clone();
    if ty.is_auto()
        && let Some(returns) = types.enter_types.get(&scope.ty.to_string())
    {
        ty = if returns.is_auto() { TypeName::void() } else { returns.clone() };
    }
    let at = value.loc;
    let name = value.name.clone();
    if ty.is_auto() {
        report(Diagnostic::error("cannot determine the type 'enter()' returns in this 'with' block").at(at));
        return;
    }
    let is_void = ty.to_string() == type_name::VOID;
    if is_void && !hidden {
        report(
            Diagnostic::error(format!("cannot bind '{}': 'enter()' returns 'void'", name))
                .at(at)
                .with_note("remove the binding: 'with (scope) { ... }'", None),
        );
        return;
    }
    if !hidden && let Some(assignment) = assignment_to(&branch.if_block, &name) {
        report(
            Diagnostic::error(format!("cannot assign to '{}': it is bound by a 'with' block", name))
                .at(assignment)
                .with_note(format!("'{}' is bound here", name), Some(at)),
        );
        return;
    }
    if types.nullable(&ty) {
        branch.condition = Expression::Unary {
            op: UnaryOp::LogicalNot,
            operand: Box::new(Expression::Binary {
                op: BinaryOp::Identical,
                lhs: Box::new(Expression::SymbolRef { id: name, ty: ty.clone(), loc: at }),
                rhs: Box::new(Expression::PointerLiteral),
                loc: at,
            }),
            loc: at,
        };
        return;
    }
    if branch.else_block.is_some() {
        report(
            Diagnostic::error(format!(
                "'else' requires 'enter()' to return a struct reference, but it returns '{}'",
                ty
            ))
            .at(at),
        );
        return;
    }
    // Never skipped: the body runs as a plain block.
    let body = std::mem::replace(&mut branch.if_block, Block { name: String::new(), items: vec![], attributes: vec![] });
    block.items[2] = Statement::Block(body);
    if is_void {
        let Statement::Declaration(Declaration::Variable(value)) = &mut block.items[1] else { unreachable!() };
        let call = value.default.take().expect("the builder gives the hidden value its enter() call");
        block.items[1] = Statement::Expression(call);
    }
}

fn lower_statement(stmt: &mut Statement, types: &Types) {
    match stmt {
        Statement::Block(inner) => lower_block(inner, types),
        Statement::Branch(branch) => {
            lower_block(&mut branch.if_block, types);
            if let Some(e) = &mut branch.else_block {
                lower_block(e, types);
            }
        }
        Statement::While(wh) => lower_block(&mut wh.block, types),
        Statement::Expression(_) | Statement::Declaration(_) | Statement::Return(_) | Statement::LoopBreak(_) => {}
    }
}

/// Where `block` assigns to the local `name`, if it does (a declaration of
/// the same name inside it shadows the binding from there on).
fn assignment_to(block: &Block, name: &str) -> Option<Loc> {
    let mut found = None;
    let mut probe = block.clone();
    for stmt in &mut probe.items {
        if let Statement::Declaration(Declaration::Variable(v)) = stmt
            && v.name == name
        {
            break;
        }
        crate::passes::walk_statement(stmt, &mut |e| {
            if let Expression::Binary { op, lhs, .. } = e
                && op.is_assignment()
                && let Expression::SymbolRef { id, loc, .. } = lhs.as_ref()
                && id == name
                && found.is_none()
            {
                found = Some(*loc);
            }
        });
    }
    found
}
