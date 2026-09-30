//! Checks on local bindings:
//! - a scope declares each name once (`var x` twice in one block is an
//!   error; an inner block may shadow);
//! - `const` bindings are assigned once, by their initializer: assigning to
//!   one afterwards (`=`, a compound assignment, `++`/`--`) is an error.
//!   Covers local and module-scope variables and, outside the constructor,
//!   the struct's own fields (`x = ...` or `this.x = ...` in a method).

use crate::model::*;

/// A visible binding: (name, const declaration location if const).
type Binding = (String, Option<Loc>);

/// A local declared in the current scope: (name, declaration location).
type Declared = (String, Loc);

struct Scopes {
    /// Innermost last; index 0 holds the module-scope variables.
    scopes: Vec<Vec<Binding>>,
    /// The enclosing struct's fields, when checking a method.
    fields: Vec<Binding>,
    /// Per block scope (parallel to `scopes[2..]`), the names it declared.
    declared: Vec<Vec<Declared>>,
}

impl Scopes {
    fn declare(&mut self, var: &VariableDef) {
        // Synthesized locals (a loop's hidden iterator) carry no location.
        if let Some(names) = self.declared.last_mut().filter(|_| !var.loc.is_none()) {
            if let Some((_, previous)) = names.iter().find(|(n, _)| *n == var.name) {
                crate::errors::report(
                    Diagnostic::error(format!("redefinition of '{}'", var.name))
                        .at(var.loc)
                        .with_note("previous definition is here", Some(*previous)),
                );
            }
            names.push((var.name.clone(), var.loc));
        }
        let binding = (var.name.clone(), var.is_const.then_some(var.loc));
        self.scopes.last_mut().expect("scope").push(binding);
    }

    /// The const declaration `name` resolves to, if it is const. Locals and
    /// parameters shadow fields, which shadow module-scope variables.
    fn const_symbol(&self, name: &str) -> Option<Loc> {
        for scope in self.scopes[1..].iter().rev() {
            if let Some((_, c)) = scope.iter().rev().find(|(n, _)| n == name) {
                return *c;
            }
        }
        if let Some((_, c)) = self.fields.iter().find(|(n, _)| n == name) {
            return *c;
        }
        self.scopes[0].iter().rev().find(|(n, _)| n == name).and_then(|(_, c)| *c)
    }

    fn const_field(&self, name: &str) -> Option<Loc> {
        self.fields.iter().find(|(n, _)| n == name).and_then(|(_, c)| *c)
    }
}

pub fn check_bindings(module: &mut Module) {
    let globals: Vec<Binding> = module.globals.iter().map(|v| (v.name.clone(), v.is_const.then_some(v.loc))).collect();
    for function in &module.functions {
        check_function(function, &globals, vec![]);
    }
    for st in &module.structs {
        let fields: Vec<Binding> = st.field_members.iter().map(|f| (f.name.clone(), f.is_const.then_some(f.loc))).collect();
        // The constructor initializes the fields, const ones included.
        let unconstrained: Vec<Binding> = fields.iter().map(|(n, _)| (n.clone(), None)).collect();
        for constructor in &st.constructors {
            check_function(constructor, &globals, unconstrained.clone());
        }
        check_function(&st.destructor, &globals, fields.clone());
        for method in &st.method_members {
            check_function(method, &globals, fields.clone());
        }
    }
}

fn check_function(function: &FunctionDef, globals: &[Binding], fields: Vec<Binding>) {
    let Some(body) = &function.body else { return };
    let mut scopes = Scopes { scopes: vec![globals.to_vec()], fields, declared: vec![] };
    scopes.scopes.push(function.parameters.iter().map(|p| (p.name.clone(), None)).collect());
    check_block(body, &mut scopes);
}

fn check_block(block: &Block, scopes: &mut Scopes) {
    scopes.scopes.push(vec![]);
    scopes.declared.push(vec![]);
    for stmt in &block.items {
        check_statement(stmt, scopes);
    }
    scopes.declared.pop();
    scopes.scopes.pop();
}

fn check_statement(stmt: &Statement, scopes: &mut Scopes) {
    match stmt {
        Statement::Expression(expr) => check_expression(expr, scopes),
        Statement::Block(inner) => check_block(inner, scopes),
        Statement::Declaration(Declaration::Variable(var)) => {
            if let Some(default) = &var.default {
                check_expression(default, scopes);
            }
            scopes.declare(var);
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            check_expression(&branch.condition, scopes);
            check_block(&branch.if_block, scopes);
            if let Some(else_block) = &branch.else_block {
                check_block(else_block, scopes);
            }
        }
        Statement::While(w) => {
            check_expression(&w.condition, scopes);
            check_block(&w.block, scopes);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &ret.expr {
                check_expression(expr, scopes);
            }
        }
        Statement::LoopBreak(_) => {}
    }
}

fn check_expression(expr: &Expression, scopes: &Scopes) {
    let mut expr = expr.clone();
    crate::passes::walk_expression(&mut expr, &mut |e: &mut Expression| {
        let target = match e {
            Expression::Binary { op, lhs, .. } if op.is_assignment() => Some(&**lhs),
            Expression::Unary { op: UnaryOp::PreInc | UnaryOp::PostInc | UnaryOp::PreDec | UnaryOp::PostDec, operand, .. } => Some(&**operand),
            _ => None,
        };
        let Some(target) = target else { return };
        let (name, at, declared) = match target {
            Expression::SymbolRef { id, loc, .. } => (id, *loc, scopes.const_symbol(id)),
            Expression::MemberRef { lhs, name, loc } if matches!(**lhs, Expression::ThisRef) => (name, *loc, scopes.const_field(name)),
            _ => return,
        };
        if let Some(declared) = declared {
            crate::errors::report(
                Diagnostic::error(format!("cannot assign to const variable '{}'", name))
                    .at(at)
                    .with_note(format!("'{}' declared const here", name), Some(declared)),
            );
        }
    });
}
