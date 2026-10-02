//! Lowering `e?`, the propagation operator (docs/src/language/results.md).
//!
//! A statement that uses `?` is preceded by one hidden local and one early
//! return per `?`, in evaluation order, and each `?` reads its local:
//!
//! ```text
//! var x = f(g()?)?;
//! ```
//!
//! becomes
//!
//! ```text
//! var __try_0 = g();
//! if (__try_0._propagates()) { return R._from_residual(__try_0._residual()); }
//! var __try_1 = f(__try_0.value());
//! if (__try_1._propagates()) { return R._from_residual(__try_1._residual()); }
//! var x = __try_1.value();
//! ```
//!
//! where `R` is the enclosing function's declared return type. `Result` and
//! `Optional` declare the three `_` members (runtime/result.pep,
//! runtime/optional.pep), so the lowering needs no types: an error of
//! another type converts as `_from_residual`'s argument, through an
//! `[Implicit]` constructor. `passes::check_tries` reports a `?` whose
//! operand or enclosing function is neither, before the calls are resolved.
//!
//! Hoisting runs each `?` operand before the rest of its statement, so a `?`
//! must not follow a call in the same statement (that call would run after
//! it), nor sit where it might not run at all (the right of `&&`, a branch
//! of `?:`, a `match` arm). A `while` whose condition uses `?` becomes
//! `while (true) { if (condition) { body } else { break; } }`, so the
//! condition's operands run on every iteration.
//!
//! A statement other than a declaration is wrapped in a block with its
//! hidden locals, which are released when it ends; a declaration's locals
//! live as long as the variable it declares.

use super::{RETURN_TYPE, block, expression, loc, statement};
use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;
use pepper_parser::diagnostic::Diagnostic;

/// The name of the hidden local that holds a `?` operand.
pub(crate) const TRY_LOCAL: &str = "__try_";

thread_local! {
    /// Numbers each `?`'s hidden local.
    pub(super) static TRIES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// The statements `stmt` lowers to when an expression it evaluates first
/// uses `?`, else `None`.
pub(super) fn lift(stmt: &ast::Statement) -> Result<Option<Vec<Statement>>, Diagnostic> {
    if let ast::Statement::While(wh) = stmt {
        return if has_try(&wh.condition) { while_loop(wh).map(Some) } else { Ok(None) };
    }
    if !head(stmt).is_some_and(has_try) {
        return Ok(None);
    }
    let mut stmt = stmt.clone();
    let mut lifter = Lifter { tries: vec![], effect: None };
    lifter.walk(head_mut(&mut stmt).expect("head checked above"), None)?;
    let mut items = vec![];
    for (name, operand, at) in lifter.tries {
        items.extend(check(&name, &operand, at)?);
    }
    let declares = matches!(stmt, ast::Statement::Declaration(_) | ast::Statement::Destructure(_));
    match &stmt {
        ast::Statement::Destructure(d) => items.extend(super::destructure(d)?),
        _ => items.push(statement(&stmt)?),
    }
    if declares {
        return Ok(Some(items));
    }
    Ok(Some(vec![Statement::Block(Block { name: String::new(), items, attributes: vec![] })]))
}

/// `while (c) { body }` with a `?` in `c`: `while (true) { if (c) { body }
/// else { break; } }`.
fn while_loop(wh: &ast::While) -> Result<Vec<Statement>, Diagnostic> {
    let span = wh.condition.span();
    let stop = ast::Statement::LoopBreak(ast::LoopBreak { kind: ast::LoopBreakKind::Break, span });
    let branch = ast::Statement::Branch(ast::Branch {
        condition: wh.condition.clone(),
        if_block: wh.block.clone(),
        else_block: Some(ast::Block { statements: vec![stop], span, attributes: vec![] }),
        span,
    });
    let body = ast::Block { statements: vec![branch], span: wh.block.span, attributes: vec![] };
    Ok(vec![Statement::While(While { condition: Expression::BoolLiteral(true), block: block(&body)? })])
}

/// The expression a statement evaluates before anything else, where its
/// `?`s are lifted from.
fn head(stmt: &ast::Statement) -> Option<&ast::Expression> {
    match stmt {
        ast::Statement::Expression(e) => Some(e),
        ast::Statement::Declaration(ast::Declaration::Variable(v)) => v.default_value.as_ref(),
        ast::Statement::Branch(b) => Some(&b.condition),
        ast::Statement::For(f) => Some(&f.iterable),
        ast::Statement::With(w) => Some(&w.scope),
        ast::Statement::Return(r) => r.expr.as_ref(),
        ast::Statement::Destructure(d) => Some(&d.value),
        ast::Statement::Match(m) => Some(&m.value),
        _ => None,
    }
}

fn head_mut(stmt: &mut ast::Statement) -> Option<&mut ast::Expression> {
    match stmt {
        ast::Statement::Expression(e) => Some(e),
        ast::Statement::Declaration(ast::Declaration::Variable(v)) => v.default_value.as_mut(),
        ast::Statement::Branch(b) => Some(&mut b.condition),
        ast::Statement::For(f) => Some(&mut f.iterable),
        ast::Statement::With(w) => Some(&mut w.scope),
        ast::Statement::Return(r) => r.expr.as_mut(),
        ast::Statement::Destructure(d) => Some(&mut d.value),
        ast::Statement::Match(m) => Some(&mut m.value),
        _ => None,
    }
}

/// Whether `e` uses `?` outside a closure body (a closure's body is its own
/// function, lowered when its block is built).
fn has_try(e: &ast::Expression) -> bool {
    use ast::Expression as E;
    match e {
        E::Unary { op, operand, .. } => op == "?" || has_try(operand),
        E::Binary { lhs, rhs, .. } | E::Index { lhs, rhs, .. } => has_try(lhs) || has_try(rhs),
        E::Ternary { condition, true_expr, false_expr, .. } => {
            has_try(condition) || has_try(true_expr) || has_try(false_expr)
        }
        E::MemberAccess { lhs, .. } => has_try(lhs),
        E::Cast { expr, .. } => has_try(expr),
        E::FunctionCall { function, arguments, .. } => has_try(function) || arguments.iter().any(has_try),
        E::NamedArgument { value, .. } | E::Is { value, .. } => has_try(value),
        E::Tuple { elements, .. } | E::ArrayLiteral { elements, .. } => elements.iter().any(has_try),
        E::MapLiteral { entries, .. } => entries.iter().any(|(k, v)| has_try(k) || has_try(v)),
        E::Match(m) => {
            has_try(&m.value) || m.arms.iter().any(|a| has_try(&a.value)) || m.else_arm.as_ref().is_some_and(|(_, v)| has_try(v))
        }
        E::Literal { .. } | E::SymbolRef { .. } | E::TypeLiteral(_) | E::SizeOf(_) | E::Closure(_) => false,
    }
}

/// Collects a statement's `?`s in evaluation order, replacing each with a
/// read of its hidden local.
struct Lifter {
    /// Each `?`: its hidden local, its operand, and the `?` token.
    tries: Vec<(String, ast::Expression, ast::Span)>,
    /// The last call (or `++`/`--`) the statement makes so far outside a
    /// `?` operand: a `?` after it would run before it.
    effect: Option<ast::Span>,
}

impl Lifter {
    /// Walks `e` in evaluation order. `conditional` names the construct
    /// when `e` may not be evaluated at all.
    fn walk(&mut self, e: &mut ast::Expression, conditional: Option<&str>) -> Result<(), Diagnostic> {
        use ast::Expression as E;
        match e {
            E::Unary { op, operand, span, .. } if op == "?" => {
                let at = ast::Span { start: span.end - 1, end: span.end };
                if let Some(construct) = conditional {
                    return Err(Diagnostic::error(format!("'?' cannot be used in {}", construct))
                        .at(loc(at))
                        .with_note("it may not run; check the value with 'if' or 'match' instead", None));
                }
                if let Some(call) = self.effect {
                    return Err(Diagnostic::error("'?' cannot follow a call in the same statement")
                        .at(loc(at))
                        .with_note("the '?' would run before this call; call it in a statement of its own", Some(loc(call))));
                }
                self.walk(operand, None)?;
                // The operand's calls run first, with it, so they do not
                // count as earlier calls for what follows.
                self.effect = None;
                let name = format!("{}{}", TRY_LOCAL, next_try());
                let operand = std::mem::replace(operand.as_mut(), E::SymbolRef { id: name.clone(), span: at });
                self.tries.push((name.clone(), operand, at));
                *e = method_call(E::SymbolRef { id: name, span: at }, "value", vec![], at);
            }
            E::Unary { op, operand, span, .. } => {
                self.walk(operand, conditional)?;
                if op == "++" || op == "--" {
                    self.effect = Some(*span);
                }
            }
            E::Binary { lhs, op, rhs, .. } => {
                self.walk(lhs, conditional)?;
                match op.as_str() {
                    "&&" | "||" | "and" | "or" => {
                        let construct = format!("the right operand of '{}'", op);
                        self.walk(rhs, Some(conditional.unwrap_or(&construct)))?;
                    }
                    _ => self.walk(rhs, conditional)?,
                }
            }
            E::Ternary { condition, true_expr, false_expr, .. } => {
                self.walk(condition, conditional)?;
                self.walk(true_expr, Some(conditional.unwrap_or("a branch of '?:'")))?;
                self.walk(false_expr, Some(conditional.unwrap_or("a branch of '?:'")))?;
            }
            E::Match(m) => {
                self.walk(&mut m.value, conditional)?;
                for arm in &mut m.arms {
                    self.walk(&mut arm.value, Some(conditional.unwrap_or("a 'match' arm")))?;
                }
                if let Some((_, value)) = &mut m.else_arm {
                    self.walk(value, Some(conditional.unwrap_or("a 'match' arm")))?;
                }
            }
            E::FunctionCall { function, arguments, .. } => {
                let callee = match function.as_mut() {
                    E::MemberAccess { lhs, name_span, .. } => {
                        self.walk(lhs, conditional)?;
                        *name_span
                    }
                    other => {
                        self.walk(other, conditional)?;
                        other.span()
                    }
                };
                for argument in arguments {
                    self.walk(argument, conditional)?;
                }
                self.effect = Some(callee);
            }
            E::Index { lhs, rhs, .. } => {
                self.walk(lhs, conditional)?;
                self.walk(rhs, conditional)?;
            }
            E::MemberAccess { lhs, .. } => self.walk(lhs, conditional)?,
            E::Cast { expr, .. } => self.walk(expr, conditional)?,
            E::NamedArgument { value, .. } | E::Is { value, .. } => self.walk(value, conditional)?,
            E::Tuple { elements, .. } | E::ArrayLiteral { elements, .. } => {
                for element in elements {
                    self.walk(element, conditional)?;
                }
            }
            E::MapLiteral { entries, .. } => {
                for (key, value) in entries {
                    self.walk(key, conditional)?;
                    self.walk(value, conditional)?;
                }
            }
            E::Literal { .. } | E::SymbolRef { .. } | E::TypeLiteral(_) | E::SizeOf(_) | E::Closure(_) => {}
        }
        Ok(())
    }
}

fn next_try() -> usize {
    TRIES.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    })
}

/// `receiver.method(arguments)`, located at `at`.
fn method_call(receiver: ast::Expression, method: &str, arguments: Vec<ast::Expression>, at: ast::Span) -> ast::Expression {
    ast::Expression::FunctionCall {
        function: Box::new(ast::Expression::MemberAccess {
            lhs: Box::new(receiver),
            name: method.to_string(),
            name_span: at,
            span: at,
        }),
        arguments,
        span: at,
    }
}

/// `var name = operand;` and `if (name._propagates()) { return
/// R._from_residual(name._residual()); }` for the `?` at `at`.
fn check(name: &str, operand: &ast::Expression, at: ast::Span) -> Result<Vec<Statement>, Diagnostic> {
    let returns = return_type(at)?;
    let local = || ast::Expression::SymbolRef { id: name.to_string(), span: at };
    let owner = ast::Expression::TypeLiteral(ast::TypeName { span: at, ..returns });
    let residual = method_call(owner, "_from_residual", vec![method_call(local(), "_residual", vec![], at)], at);
    let hidden = VariableDef {
        name: name.to_string(),
        ty: TypeName::auto(),
        default: Some(expression(operand)?),
        hidden: true,
        kind: Kind::Variable,
        attributes: vec![],
        loc: loc(at),
        type_loc: Loc::NONE,
        is_const: false,
    };
    let exit = Statement::Branch(Branch {
        condition: expression(&method_call(local(), "_propagates", vec![], at))?,
        if_block: Block {
            name: String::new(),
            items: vec![Statement::Return(ReturnStatement { expr: Some(expression(&residual)?), loc: loc(at) })],
            attributes: vec![],
        },
        else_block: None,
    });
    Ok(vec![Statement::Declaration(Declaration::Variable(hidden)), exit])
}

/// The declared return type of the function a `?` at `at` returns from.
fn return_type(at: ast::Span) -> Result<ast::TypeName, Diagnostic> {
    let Some(returns) = RETURN_TYPE.with(|r| r.borrow().clone()) else {
        return Err(Diagnostic::error("'?' can be used only in a function body").at(loc(at)));
    };
    match returns.name.as_str() {
        "" | "auto" | crate::type_name::AUTO => {
            Err(Diagnostic::error("'?' requires the enclosing function to declare its return type").at(loc(at)).with_note(
                "a Result or an Optional, as in 'f(): Result<int>' or, for a closure, '(x): Result<int> => ...'",
                None,
            ))
        }
        "void" => Err(Diagnostic::error("'?' requires the enclosing function to return a Result or an Optional").at(loc(at))),
        _ => Ok(returns),
    }
}
