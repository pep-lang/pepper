//! Unary operators and truth tests on structs.
//!
//! A struct may declare `-()`, `~()`, `!()` and the truth test `!!()` as
//! instance methods without parameters. `dispatch` (run by
//! `resolve_operators`) turns `-x`, `~x` and `!x` on such a struct into
//! zero-argument method calls named after the operator, and a struct value
//! in a boolean context (an `if`/`while` condition, a ternary condition, an
//! operand of `&&`/`||`, the operand of `!`) into `x.!!()`. Without its own
//! `!`, `!x` is `!(x.!!())`, and `!!x` is `x.!!()`.
//!
//! `check_conditions` runs once types are final and reports a struct value
//! left in a boolean context: a struct is not a pointer, so it has no
//! implicit null test. A trait value is reported the same way (unless its
//! trait declares `!!`). Pointers, numbers, `bool` and function values keep
//! their truthiness.

use std::collections::{HashMap, HashSet};

use pepper_parser::diagnostic::Diagnostic;

use crate::model::*;
use crate::static_type::{self, StructInfo, StructTable};
use crate::type_name::TypeName;

/// The unary operators a struct can overload.
const UNARY_OPERATORS: &[&str] = &["-", "~", "!", "!!"];

/// The truth-test operator.
const TRUTH_TEST: &str = "!!";

/// The unary operators among `methods`: instance methods without parameters
/// named `-`, `~`, `!` or `!!` (or a member of such an overload set, `-$2`).
pub(crate) fn declared(methods: &[FunctionDef]) -> HashSet<String> {
    methods
        .iter()
        .filter(|m| !m.is_static && m.parameters.is_empty())
        .map(|m| m.name.split('$').next().unwrap_or_default())
        .filter(|name| UNARY_OPERATORS.contains(name))
        .map(str::to_string)
        .collect()
}

/// Rewrite unary operators and truth tests on structs in `body` into method
/// calls. The call names the operator (`-`), so an overload set holding both
/// a unary and a binary `-` resolves to the member by its arity.
pub(crate) fn dispatch(body: &mut Block, table: &StructTable, current: Option<&TypeName>) {
    let truth_test = |expr: &mut Expression| {
        if declares(expr, TRUTH_TEST, table, current) {
            let loc = expr.loc();
            *expr = call(take(expr), TRUTH_TEST, loc);
        }
    };
    statement_conditions(body, &mut |condition| truth_test(condition));
    crate::passes::walk_block(body, &mut |expr: &mut Expression| match expr {
        Expression::Unary { op, operand, loc } => {
            let loc = *loc;
            // An enum declaring the operator: `-a` is `E::-(a)`.
            let name = match op {
                UnaryOp::Neg => "-",
                UnaryOp::BitNot => "~",
                UnaryOp::LogicalNot => "!",
                _ => "",
            };
            if !name.is_empty()
                && let Some(ty) = static_type::of(operand, table, current)
                && crate::enums::declares_operator(&ty, name)
            {
                *expr = crate::enums::operator_call(&ty, name, vec![take(operand)], loc);
                return;
            }
            match op {
                UnaryOp::Neg | UnaryOp::BitNot => {
                    let name = if *op == UnaryOp::Neg { "-" } else { "~" };
                    if declares(operand, name, table, current) {
                        *expr = call(take(operand), name, loc);
                    }
                }
                UnaryOp::LogicalNot => {
                    // `!!x` is the truth test itself.
                    if let Expression::Unary { op: UnaryOp::LogicalNot, operand: inner, .. } = &mut **operand {
                        if declares(inner, TRUTH_TEST, table, current) {
                            *expr = call(take(inner), TRUTH_TEST, loc);
                            return;
                        }
                    }
                    if declares(operand, "!", table, current) {
                        *expr = call(take(operand), "!", loc);
                    } else {
                        truth_test(operand);
                    }
                }
                _ => {}
            }
        }
        Expression::Ternary { condition, .. } => truth_test(condition),
        Expression::Binary { op: op @ (BinaryOp::LogicalAnd | BinaryOp::LogicalOr), lhs, rhs, .. } => {
            // A struct declaring `&&` or `||` takes the whole operation.
            let overloaded = struct_of(lhs, table, current).is_some_and(|info| info.methods.contains(&op.op_name()));
            if !overloaded {
                truth_test(lhs);
                truth_test(rhs);
            }
        }
        _ => {}
    });
}

/// Report each struct value left in a boolean context: one whose struct does
/// not declare `!!`.
pub fn check_conditions(module: &mut Module) {
    let table = StructTable::build(module);
    // Declared structs and traits by type, and by base name for generic
    // ones. Function types, weak references and closures (`__function<…>`,
    // `__weak<…>`, `__closure_N`) are synthesized and keep their null test.
    let mut declared_at: HashMap<String, Loc> = HashMap::new();
    for st in module.structs.iter().filter(|st| !st.ty.name.starts_with("__")) {
        declared_at.insert(st.ty.to_string(), st.loc);
        declared_at.entry(st.ty.name.clone()).or_insert(st.loc);
    }
    for tr in &module.traits {
        declared_at.entry(tr.name.clone()).or_insert(tr.loc);
    }
    let check = |expr: &mut Expression, current: Option<&TypeName>| {
        let Some(ty) = type_of(expr, &table, current) else { return };
        let Some(declared_at) =
            declared_at.get(&ty.to_string()).or_else(|| declared_at.get(&StructTable::base_name(&ty)))
        else {
            return;
        };
        if table.lookup(&ty).is_some_and(|info| info.unary_operators.contains(TRUTH_TEST)) {
            return;
        }
        crate::errors::report(
            Diagnostic::error(format!(
                "'{}' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'",
                ty.display()
            ))
            .at(expr.loc())
            .with_note(format!("'{}' declared here", StructTable::base_name(&ty)), Some(*declared_at)),
        );
    };
    let check_body = |body: &mut Block, current: Option<&TypeName>| {
        statement_conditions(body, &mut |condition| check(condition, current));
        crate::passes::walk_block(body, &mut |expr: &mut Expression| match expr {
            Expression::Unary { op: UnaryOp::LogicalNot, operand, .. } => check(operand, current),
            Expression::Ternary { condition, .. } => check(condition, current),
            Expression::Binary { op: BinaryOp::LogicalAnd | BinaryOp::LogicalOr, lhs, rhs, .. } => {
                check(lhs, current);
                check(rhs, current);
            }
            _ => {}
        });
    };
    for st in &mut module.structs {
        // Generic bases are checked in their specializations.
        if st.ty.is_generic() && st.name == st.ty.name {
            continue;
        }
        let current = st.ty.clone();
        for body in st.constructors.iter_mut().filter_map(|c| c.body.as_mut()) {
            check_body(body, Some(&current));
        }
        for method in &mut st.method_members {
            if let Some(body) = &mut method.body {
                check_body(body, Some(&current));
            }
        }
    }
    for function in &mut module.functions {
        if let Some(body) = &mut function.body {
            check_body(body, None);
        }
    }
    for var in &mut module.globals {
        if let Some(default) = var.default.take() {
            let mut block = Block { name: String::new(), items: vec![Statement::Expression(default)], attributes: vec![] };
            check_body(&mut block, None);
            if let Some(Statement::Expression(default)) = block.items.pop() {
                var.default = Some(default);
            }
        }
    }
}

/// Apply `f` to the condition of every `if` and `while` in `block`, nested
/// blocks included. A `with` block's condition is its own (`lower_with_blocks`).
fn statement_conditions(block: &mut Block, f: &mut impl FnMut(&mut Expression)) {
    for statement in &mut block.items {
        match statement {
            Statement::Block(inner) => statement_conditions(inner, f),
            Statement::Branch(branch) => {
                if !matches!(branch.condition, Expression::WithEntered(_)) {
                    f(&mut branch.condition);
                }
                statement_conditions(&mut branch.if_block, f);
                if let Some(else_block) = &mut branch.else_block {
                    statement_conditions(else_block, f);
                }
            }
            Statement::While(wh) => {
                f(&mut wh.condition);
                statement_conditions(&mut wh.block, f);
            }
            _ => {}
        }
    }
}

/// True when `expr` is a struct value whose struct declares the unary `op`.
fn declares(expr: &Expression, op: &str, table: &StructTable, current: Option<&TypeName>) -> bool {
    struct_of(expr, table, current).is_some_and(|info| info.unary_operators.contains(op))
}

/// The struct (or trait) of `expr`'s static type.
fn struct_of<'a>(expr: &Expression, table: &'a StructTable, current: Option<&TypeName>) -> Option<&'a StructInfo> {
    table.lookup(&type_of(expr, table, current)?)
}

/// The static type of `expr`; a bare field in a method (not yet `this.f`)
/// types from the enclosing struct.
fn type_of(expr: &Expression, table: &StructTable, current: Option<&TypeName>) -> Option<TypeName> {
    static_type::of(expr, table, current).or_else(|| {
        let Expression::SymbolRef { id, .. } = expr else { return None };
        let info = table.lookup(current?)?;
        info.fields.iter().find(|(f, _)| f == id).map(|(_, ty)| ty.clone())
    })
}

/// `this.op()`, located at the operator use.
fn call(this: Expression, op: &str, loc: Loc) -> Expression {
    Expression::MethodCall { this: Box::new(this), method: op.to_string(), args: vec![], loc }
}

/// Move `expr` out, leaving a placeholder the caller overwrites.
fn take(expr: &mut Expression) -> Expression {
    std::mem::replace(expr, Expression::BoolLiteral(false))
}
