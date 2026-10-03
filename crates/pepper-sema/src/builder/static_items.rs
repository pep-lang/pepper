//! Building a `static (captures) { ... }` block into a
//! [`StaticBlock`](crate::model::StaticBlock).
//!
//! Which statements run in the compiler and which are emitted is decided
//! here, from the names alone: a statement that uses a captured name, or a
//! runtime local the block declares, is emitted; the rest is compile-time
//! work, kept as written for `passes::static_blocks` to evaluate once the
//! block's type arguments are known. Inside an emitted statement, a
//! sub-expression that uses only compile-time names (`field.name`) becomes an
//! [`Expression::StaticValue`], and `field.get(value)`, `field.set(value, x)`
//! and `function.call(args)` become an [`Expression::StaticMember`].

use super::{call_arguments, expression, loc, statement};
use crate::model::*;
use pepper_parser::ast;
use pepper_parser::diagnostic::Diagnostic;
use std::cell::RefCell;
use std::collections::HashSet;

/// The compile-time API's name inside a `static` block.
pub(crate) const REFLECT: &str = "reflect";

/// The function an interpolated string (`$"{x}"`) calls on each value.
pub(crate) const INTERPOLATE: &str = "_pep_interpolate";

/// The methods of a reflected member, case or function that emit code.
pub(crate) const EMITTING_METHODS: [&str; 4] = ["get", "set", "call", "matches"];

thread_local! {
    /// The compile-time names visible where an emitted statement is being
    /// built, `reflect` included; `None` outside a `static` block.
    static COMPILE_TIME: RefCell<Option<HashSet<String>>> = const { RefCell::new(None) };
}

/// The names bound inside a `static` block, innermost scope last.
struct Names {
    compile_time: Vec<HashSet<String>>,
    runtime: Vec<HashSet<String>>,
    /// The compile-time `for` and `while` loops around the statement being
    /// built, which a compile-time `break` or `continue` leaves.
    loops: usize,
    /// The statement is in a branch of a runtime `if`, which a compile-time
    /// `break` cannot depend on.
    in_runtime_if: bool,
    /// The block is at module scope, where nothing is emitted.
    module_scope: bool,
}

impl Names {
    fn push(&mut self) {
        self.compile_time.push(HashSet::new());
        self.runtime.push(HashSet::new());
    }

    fn pop(&mut self) {
        self.compile_time.pop();
        self.runtime.pop();
    }

    /// The innermost binding of `name` is a runtime one: a capture or a
    /// runtime local of the block.
    fn is_runtime(&self, name: &str) -> bool {
        for (compile_time, runtime) in self.compile_time.iter().zip(&self.runtime).rev() {
            if runtime.contains(name) {
                return true;
            }
            if compile_time.contains(name) {
                return false;
            }
        }
        false
    }

    fn declare(&mut self, name: &str, runtime: bool) {
        let (add, remove) = if runtime { (&mut self.runtime, &mut self.compile_time) } else { (&mut self.compile_time, &mut self.runtime) };
        add.last_mut().unwrap().insert(name.to_string());
        remove.last_mut().unwrap().remove(name);
    }

    fn compile_time_names(&self) -> HashSet<String> {
        let mut names: HashSet<String> = HashSet::from([REFLECT.to_string()]);
        for (compile_time, runtime) in self.compile_time.iter().zip(&self.runtime) {
            names.extend(compile_time.iter().cloned());
            for name in runtime {
                names.remove(name);
            }
        }
        names
    }

    /// `expr` uses a runtime name of the block, or emits code itself
    /// (`check.call()`), so a statement with it is emitted.
    fn mentions_runtime(&self, expr: &ast::Expression) -> bool {
        // At module scope nothing is emitted: `case.get()` is evaluated.
        let mut found = !self.module_scope && emits(expr);
        symbols(expr, &mut |name| found |= self.is_runtime(name));
        found
    }
}

/// `expr` calls `get`, `set` or `call` on something: on a reflected
/// member or function, that emits code.
fn emits(expr: &ast::Expression) -> bool {
    use ast::Expression as E;
    match expr {
        E::FunctionCall { function, arguments, .. } => {
            matches!(function.as_ref(), E::MemberAccess { name, .. } if EMITTING_METHODS.contains(&name.as_str()))
                || emits(function)
                || arguments.iter().any(emits)
        }
        E::Unary { operand, .. } => emits(operand),
        E::Binary { lhs, rhs, .. } | E::Index { lhs, rhs, .. } => emits(lhs) || emits(rhs),
        E::Ternary { condition, true_expr, false_expr, .. } => emits(condition) || emits(true_expr) || emits(false_expr),
        E::MemberAccess { lhs, .. } => emits(lhs),
        E::NamedArgument { value, .. } => emits(value),
        _ => false,
    }
}

/// Every name `expr` refers to as a value, closure bodies included.
fn symbols(expr: &ast::Expression, f: &mut dyn FnMut(&str)) {
    use ast::Expression as E;
    match expr {
        E::Literal { .. } | E::SizeOf(_) => {}
        E::SymbolRef { id, .. } => f(id),
        E::TypeLiteral(ty) => {
            if let Some((root, _)) = ty.name.split_once('.') {
                f(root);
            }
        }
        E::Unary { operand, .. } => symbols(operand, f),
        E::Cast { expr, .. } => symbols(expr, f),
        E::Binary { lhs, rhs, .. } | E::Index { lhs, rhs, .. } => {
            symbols(lhs, f);
            symbols(rhs, f);
        }
        E::Ternary { condition, true_expr, false_expr, .. } => {
            symbols(condition, f);
            symbols(true_expr, f);
            symbols(false_expr, f);
        }
        E::MemberAccess { lhs, .. } => symbols(lhs, f),
        E::FunctionCall { function, arguments, .. } => {
            symbols(function, f);
            arguments.iter().for_each(|a| symbols(a, f));
        }
        E::NamedArgument { value, .. } => symbols(value, f),
        E::Closure(closure) => block_symbols(&closure.body, f),
        E::Tuple { elements, .. } | E::ArrayLiteral { elements, .. } => elements.iter().for_each(|e| symbols(e, f)),
        E::MapLiteral { entries, .. } => entries.iter().for_each(|(k, v)| {
            symbols(k, f);
            symbols(v, f);
        }),
        E::Match(m) => {
            symbols(&m.value, f);
            m.arms.iter().filter_map(|arm| arm.guard.as_ref()).for_each(|g| symbols(g, f));
            m.arms.iter().for_each(|arm| symbols(&arm.value, f));
            if let Some((_, value)) = &m.else_arm {
                symbols(value, f);
            }
        }
        E::Is { value, .. } => symbols(value, f),
    }
}

fn block_symbols(block: &ast::Block, f: &mut dyn FnMut(&str)) {
    for stmt in &block.statements {
        match stmt {
            ast::Statement::Expression(e) => symbols(e, f),
            ast::Statement::Declaration(ast::Declaration::Variable(v)) => {
                if let Some(value) = &v.default_value {
                    symbols(value, f);
                }
            }
            ast::Statement::Return(r) => {
                if let Some(value) = &r.expr {
                    symbols(value, f);
                }
            }
            ast::Statement::Block(b) => block_symbols(b, f),
            ast::Statement::Branch(b) => {
                symbols(&b.condition, f);
                block_symbols(&b.if_block, f);
                if let Some(e) = &b.else_block {
                    block_symbols(e, f);
                }
            }
            ast::Statement::While(w) => {
                symbols(&w.condition, f);
                block_symbols(&w.block, f);
            }
            ast::Statement::For(l) => {
                symbols(&l.iterable, f);
                block_symbols(&l.block, f);
            }
            _ => {}
        }
    }
}

/// `expr` uses at least one compile-time name and nothing else: no runtime
/// value, function, closure or `match`. `_pep_interpolate`, which `$"..."`
/// calls, is allowed, since interpolating compile-time values is itself
/// compile-time work.
pub(crate) fn is_compile_time(expr: &ast::Expression, names: &HashSet<String>) -> bool {
    fn only(expr: &ast::Expression, names: &HashSet<String>, any: &mut bool) -> bool {
        use ast::Expression as E;
        match expr {
            E::Literal { .. } => true,
            E::SymbolRef { id, .. } => {
                *any |= names.contains(id);
                names.contains(id)
            }
            E::TypeLiteral(ty) => match ty.name.split_once('.') {
                Some((root, _)) if names.contains(root) => {
                    *any = true;
                    true
                }
                _ => false,
            },
            E::Unary { operand, .. } => only(operand, names, any),
            E::Binary { lhs, rhs, .. } | E::Index { lhs, rhs, .. } => only(lhs, names, any) && only(rhs, names, any),
            E::Ternary { condition, true_expr, false_expr, .. } => {
                only(condition, names, any) && only(true_expr, names, any) && only(false_expr, names, any)
            }
            E::MemberAccess { lhs, .. } => only(lhs, names, any),
            E::FunctionCall { function, arguments, .. } => {
                let callee = matches!(function.as_ref(), E::SymbolRef { id, .. } if id == INTERPOLATE) || only(function, names, any);
                callee && arguments.iter().all(|a| only(a, names, any))
            }
            E::NamedArgument { value, .. } => only(value, names, any),
            _ => false,
        }
    }
    let mut any = false;
    only(expr, names, &mut any) && any
}

/// The placeholder for `expr` when it is part of a statement a `static`
/// block emits and uses only compile-time names; `None` otherwise, and
/// always outside a `static` block.
pub(super) fn placeholder(expr: &ast::Expression) -> Result<Option<Expression>, Diagnostic> {
    let Some(names) = COMPILE_TIME.with(|c| c.borrow().clone()) else { return Ok(None) };
    if let ast::Expression::FunctionCall { function, arguments, .. } = expr
        && let ast::Expression::MemberAccess { lhs, name, name_span, .. } = function.as_ref()
        && EMITTING_METHODS.contains(&name.as_str())
        && is_compile_time(lhs, &names)
    {
        return Ok(Some(Expression::StaticMember(Box::new(StaticMember {
            member: (**lhs).clone(),
            method: name.clone(),
            args: call_arguments(arguments)?,
            loc: loc(*name_span),
            span: expr.extent(),
            argument_spans: arguments.iter().map(|a| a.extent()).collect(),
        }))));
    }
    if is_compile_time(expr, &names) {
        return Ok(Some(Expression::StaticValue(Box::new(StaticValue { expr: expr.clone(), loc: loc(expr.span()) }))));
    }
    Ok(None)
}

/// Builds `static (captures) { ... }`.
pub(super) fn static_block(block: &ast::StaticBlock) -> Result<Statement, Diagnostic> {
    build_block(block, false)
}

fn build_block(block: &ast::StaticBlock, module_scope: bool) -> Result<Statement, Diagnostic> {
    if COMPILE_TIME.with(|c| c.borrow().is_some()) {
        return Err(Diagnostic::error("a 'static' block cannot be nested in another").at(loc(block.keyword_span)));
    }
    let mut names = Names { compile_time: vec![HashSet::new()], runtime: vec![HashSet::new()], loops: 0, in_runtime_if: false, module_scope };
    for (i, (name, span)) in block.captures.iter().enumerate() {
        if let Some((_, first)) = block.captures[..i].iter().find(|(other, _)| other == name) {
            return Err(Diagnostic::error(format!("'{}' is captured twice", name))
                .at(loc(*span))
                .with_note("first captured here", Some(loc(*first))));
        }
        names.declare(name, true);
    }
    let items = items(&block.block.statements, &mut names)?;
    Ok(Statement::Static(Box::new(StaticBlock {
        captures: block.captures.iter().map(|(name, _)| name.clone()).collect(),
        items,
        type_map: vec![],
        loc: loc(block.keyword_span),
        span: block.span,
    })))
}

/// Builds a module-scope `static { ... }`, whose top-level `const`
/// declarations the parser also declared as module-scope variables.
pub(super) fn module_static_block(block: &ast::StaticBlock) -> Result<ModuleStaticBlock, Diagnostic> {
    if let Some((_, span)) = block.captures.first() {
        return Err(Diagnostic::error("a module-scope 'static' block has no runtime values to capture").at(loc(*span)));
    }
    let Statement::Static(built) = build_block(block, true)? else { unreachable!("build_block builds a static block") };
    let constants = block
        .block
        .statements
        .iter()
        .filter_map(|stmt| match stmt {
            ast::Statement::Declaration(ast::Declaration::Variable(v)) if v.is_const && v.default_value.is_some() => {
                Some((v.name.clone(), loc(v.name_span)))
            }
            _ => None,
        })
        .collect();
    Ok(ModuleStaticBlock { block: *built, constants })
}

fn scoped(block: &ast::Block, names: &mut Names) -> Result<Vec<StaticItem>, Diagnostic> {
    names.push();
    let built = items(&block.statements, names);
    names.pop();
    built
}

fn items(statements: &[ast::Statement], names: &mut Names) -> Result<Vec<StaticItem>, Diagnostic> {
    let mut out = vec![];
    for stmt in statements {
        let item = match stmt {
            ast::Statement::Expression(e) if !names.mentions_runtime(e) => StaticItem::Evaluate(e.clone()),
            ast::Statement::Declaration(ast::Declaration::Variable(v)) => match &v.default_value {
                Some(value) if !names.mentions_runtime(value) => {
                    names.declare(&v.name, false);
                    StaticItem::Var { name: v.name.clone(), value: value.clone(), loc: loc(v.name_span) }
                }
                _ => {
                    let item = StaticItem::Emit(emit(stmt, names)?, written(stmt));
                    names.declare(&v.name, true);
                    item
                }
            },
            ast::Statement::Declaration(d) => {
                return Err(Diagnostic::error("only variables can be declared in a 'static' block").at(loc(d.span())));
            }
            ast::Statement::Branch(b) if !contains_is(&b.condition) => {
                let runtime = names.mentions_runtime(&b.condition);
                let (loops, in_runtime_if) = (names.loops, names.in_runtime_if);
                if runtime {
                    names.loops = 0;
                    names.in_runtime_if = true;
                }
                let then_items = scoped(&b.if_block, names);
                let else_items = match &b.else_block {
                    Some(e) => scoped(e, names),
                    None => Ok(vec![]),
                };
                (names.loops, names.in_runtime_if) = (loops, in_runtime_if);
                let (then_items, else_items) = (then_items?, else_items?);
                if runtime {
                    StaticItem::EmitIf { condition: emit_expression(&b.condition, names)?, then_items, else_items, span: b.condition.extent() }
                } else {
                    StaticItem::If { condition: b.condition.clone(), then_items, else_items, loc: loc(b.condition.span()) }
                }
            }
            ast::Statement::For(f) if f.pattern.is_empty() && !names.mentions_runtime(&f.iterable) => {
                names.push();
                names.declare(&f.binding.name, false);
                names.loops += 1;
                let body = items(&f.block.statements, names);
                names.loops -= 1;
                names.pop();
                StaticItem::For { name: f.binding.name.clone(), iterable: f.iterable.clone(), body: body?, loc: loc(f.iterable.span()) }
            }
            ast::Statement::While(w) if !names.mentions_runtime(&w.condition) => {
                names.loops += 1;
                let body = scoped(&w.block, names);
                names.loops -= 1;
                StaticItem::While {
                    condition: w.condition.clone(),
                    body: body?,
                    loc: loc(ast::Span { start: w.span.start, end: w.span.start + "while".len() }),
                }
            }
            ast::Statement::LoopBreak(jump) => {
                let word = if jump.kind == ast::LoopBreakKind::Break { "break" } else { "continue" };
                if names.loops == 0 {
                    let message = if names.in_runtime_if {
                        format!("'{}' in a runtime 'if' cannot leave a compile-time loop; the condition is not known while compiling", word)
                    } else {
                        format!("'{}' in a 'static' block must be in a compile-time 'for' or 'while'", word)
                    };
                    return Err(Diagnostic::error(message).at(loc(jump.span)));
                }
                StaticItem::Jump { kind: jump.kind, loc: loc(jump.span) }
            }
            ast::Statement::Block(b) => StaticItem::Block(scoped(b, names)?),
            ast::Statement::Static(s) => {
                return Err(Diagnostic::error("a 'static' block cannot be nested in another").at(loc(s.keyword_span)));
            }
            _ => StaticItem::Emit(emit(stmt, names)?, written(stmt)),
        };
        out.push(item);
    }
    Ok(out)
}

/// The source `stmt` covers, for `--emit-static`.
fn written(stmt: &ast::Statement) -> ast::Span {
    match stmt {
        ast::Statement::Expression(e) => e.extent(),
        other => other.span(),
    }
}

fn contains_is(expr: &ast::Expression) -> bool {
    match expr {
        ast::Expression::Is { .. } => true,
        ast::Expression::Binary { lhs, rhs, .. } => contains_is(lhs) || contains_is(rhs),
        ast::Expression::Unary { operand, .. } => contains_is(operand),
        _ => false,
    }
}

fn with_compile_time<T>(names: &Names, build: impl FnOnce() -> T) -> T {
    let previous = COMPILE_TIME.with(|c| c.replace(Some(names.compile_time_names())));
    let built = build();
    COMPILE_TIME.with(|c| *c.borrow_mut() = previous);
    built
}

fn emit(stmt: &ast::Statement, names: &Names) -> Result<Statement, Diagnostic> {
    if names.module_scope {
        return Err(Diagnostic::error("a module-scope 'static' block cannot emit code; declare a 'const' with what it computes").at(loc(stmt.span())));
    }
    with_compile_time(names, || statement(stmt))
}

fn emit_expression(expr: &ast::Expression, names: &Names) -> Result<Expression, Diagnostic> {
    if names.module_scope {
        return Err(Diagnostic::error("a module-scope 'static' block cannot emit code; declare a 'const' with what it computes").at(loc(expr.span())));
    }
    with_compile_time(names, || expression(expr))
}
