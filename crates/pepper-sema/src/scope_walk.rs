//! The scope walk that module linking, the visibility check, and the
//! deprecation check share: one
//! traversal of a file's AST that tracks the names bound locally at each
//! point (parameters, locals, generic parameters, and the members of the
//! struct being defined or extended), which hide top-level names.
//!
//! Linking rewrites the AST as it walks, and the checks only read it, so the walk is written once and instantiated twice by
//! `scope_walker!`: [`ScopeWalkMut`] over `&mut` nodes and [`ScopeWalk`]
//! over `&` nodes. Each pass implements the hooks: what a reference, a
//! member name, or a type name means to it, and which struct members and
//! `extend` parameters are in scope.
//!
//! The deprecation check (`crate::deprecation`) reads it as well, and uses
//! the `enter_declaration`/`exit_declaration` hooks to know when it is
//! inside a declaration marked `[Deprecated]`.
//!
//! What platform selection drops is never compiled, so the walk skips it: a
//! function or block whose `[Target(...)]` is false. Constructors and
//! destructors are always walked, since platform selection never drops them.

use crate::passes::platform::keep;
use pepper_parser::ast::{Attribute, Block, Declaration, Expression, FunctionDecl, GenericParam, Span, Statement, TypeName};
use std::collections::HashSet;

/// One level of names bound inside a declaration.
pub(crate) enum Scope {
    /// Parameters and locals: they hide top-level names used as values.
    Values(HashSet<String>),
    /// Generic parameters: they hide top-level names as values and as types.
    Generics(HashSet<String>),
    /// The members of a struct visible in this file, looked up through the
    /// walker's `is_member` rather than copied.
    Members(String),
    /// A trait whose default method bodies are being walked. It binds no
    /// names.
    Trait(String),
}

/// The locally bound names at one point of the walk, innermost last, each
/// scope with the names bound in it that its walker marked (see
/// `visit_binding`).
#[derive(Default)]
pub(crate) struct Scopes(Vec<Scope>, Vec<HashSet<String>>);

impl Scopes {
    /// `name` is bound locally where a value is expected: a parameter,
    /// local, generic parameter, or a member `is_member` accepts.
    pub(crate) fn is_local(&self, name: &str, is_member: impl Fn(&str, &str) -> bool) -> bool {
        self.0.iter().any(|s| match s {
            Scope::Values(names) | Scope::Generics(names) => names.contains(name),
            Scope::Members(st) => is_member(st, name),
            Scope::Trait(_) => false,
        })
    }

    /// `name` is bound locally where a type is expected (a type position,
    /// or a generic call such as `f<int>()`): only generic parameters. A
    /// local or member is a value, and sema never binds a type or a generic
    /// call to it.
    pub(crate) fn is_type_local(&self, name: &str) -> bool {
        self.0.iter().any(|s| matches!(s, Scope::Generics(names) if names.contains(name)))
    }

    /// `name` is bound here as a parameter or local.
    pub(crate) fn is_value_bound(&self, name: &str) -> bool {
        self.0.iter().any(|s| matches!(s, Scope::Values(names) if names.contains(name)))
    }

    /// The value `name` refers to here (the innermost binding of it) was
    /// marked when it was bound.
    pub(crate) fn is_marked_value(&self, name: &str) -> bool {
        self.0
            .iter()
            .zip(&self.1)
            .rev()
            .find(|(s, _)| matches!(s, Scope::Values(names) if names.contains(name)))
            .is_some_and(|(_, marked)| marked.contains(name))
    }

    /// The struct whose body or extension is being walked, if any.
    pub(crate) fn current_struct(&self) -> Option<&str> {
        self.0.iter().rev().find_map(|s| match s {
            Scope::Members(st) => Some(st.as_str()),
            _ => None,
        })
    }

    /// The trait whose default method bodies are being walked, if any.
    pub(crate) fn current_trait(&self) -> Option<&str> {
        self.0.iter().rev().find_map(|s| match s {
            Scope::Trait(t) => Some(t.as_str()),
            _ => None,
        })
    }

    fn push(&mut self, scope: Scope) {
        self.0.push(scope);
        self.1.push(HashSet::new());
    }

    fn pop(&mut self) {
        self.0.pop();
        self.1.pop();
    }

    /// Bind the value `name` in the innermost scope, marked or not.
    fn bind_value(&mut self, name: &str, marked: bool) {
        self.bind(name);
        if let Some(m) = self.1.last_mut() {
            if marked {
                m.insert(name.to_string());
            } else {
                m.remove(name);
            }
        }
    }

    fn bind(&mut self, name: &str) {
        if let Some(Scope::Values(names) | Scope::Generics(names)) = self.0.last_mut() {
            names.insert(name.to_string());
        }
    }
}

/// Defines one walker trait: `$Walk` over nodes borrowed as `&$($m)?`.
macro_rules! scope_walker {
    ($(#[$doc:meta])* $Walk:ident $(, $m:ident)?) => {
        $(#[$doc])*
        pub(crate) trait $Walk {
            fn scopes(&self) -> &Scopes;
            fn scopes_mut(&mut self) -> &mut Scopes;

            /// `name` is a member of `struct_name` visible to this file.
            fn is_member(&self, struct_name: &str, name: &str) -> bool;

            /// The names `extend target` introduces as generic parameters:
            /// in `extend Box<T>`, a `T` that names no type.
            fn extend_params(&self, target: &TypeName) -> HashSet<String>;

            /// A bare name used as a value.
            fn visit_symbol(&mut self, id: &$($m)? String, span: Span);

            /// A type name, generic arguments included. The default walks
            /// only the arguments.
            fn visit_type_name(&mut self, ty: &$($m)? TypeName) {
                self.walk_type_name(ty);
            }

            /// A function, before its generic parameters are bound. True
            /// when they are types, not parameters (`describe<Point>`, a
            /// concrete override): then they bind no names.
            fn visit_function_generics(&mut self, _f: &$($m)? FunctionDecl) -> bool {
                false
            }

            /// A value is about to be bound (a parameter, local, loop or
            /// `with` binding, or closure parameter), with its declared type
            /// and initializer. True marks the binding (see
            /// `Scopes::is_marked_value`).
            fn visit_binding(&mut self, _ty: &TypeName, _init: Option<&Expression>) -> bool {
                false
            }

            /// The callee of a call, before it is walked.
            fn visit_callee(&mut self, _function: &Expression) {}

            /// The member name of `x.name`, after `x` is walked.
            fn visit_member(&mut self, _name: &str, _name_span: Span) {}

            /// An expression. The default walks it.
            fn visit_expression(&mut self, expr: &$($m)? Expression) {
                self.walk_expression(expr);
            }

            /// Entering a declaration (a top-level or local one, a field,
            /// a function or method) that carries `attributes`; each call
            /// is paired with an [`exit_declaration`](Self::exit_declaration).
            fn enter_declaration(&mut self, _attributes: &[Attribute]) {}

            /// Leaving the declaration the matching `enter_declaration`
            /// entered.
            fn exit_declaration(&mut self) {}

            /// `name` is bound locally where a value is expected.
            fn is_local(&self, name: &str) -> bool {
                self.scopes().is_local(name, |st, n| self.is_member(st, n))
            }

            fn walk_type_name(&mut self, ty: &$($m)? TypeName) {
                for g in &$($m)? ty.generic_types {
                    self.visit_type_name(g);
                }
            }

            fn walk_declaration(&mut self, decl: &$($m)? Declaration) {
                self.enter_declaration(decl.attributes());
                match decl {
                    Declaration::Variable(v) => {
                        self.visit_type_name(&$($m)? v.type_name);
                        if let Some(e) = &$($m)? v.default_value {
                            self.visit_expression(e);
                        }
                        let marked = self.visit_binding(&v.type_name, v.default_value.as_ref());
                        self.scopes_mut().bind_value(&v.name, marked);
                    }
                    Declaration::Function(f) => self.walk_function(f),
                    Declaration::Struct(s) => {
                        self.push_generics(&$($m)? s.generic_params);
                        self.scopes_mut().push(Scope::Members(s.name.clone()));
                        if let Some(e) = &$($m)? s.enumeration {
                            if let Some(r) = &$($m)? e.representation {
                                self.visit_type_name(r);
                            }
                            for case in &$($m)? e.cases {
                                self.enter_declaration(&case.attributes);
                                if let Some(payload) = &$($m)? case.payload {
                                    for p in payload {
                                        self.visit_type_name(&$($m)? p.type_name);
                                    }
                                }
                                if let Some(v) = &$($m)? case.value {
                                    self.visit_expression(v);
                                }
                                self.exit_declaration();
                            }
                        }
                        for field in &$($m)? s.fields {
                            self.enter_declaration(&field.attributes);
                            self.visit_type_name(&$($m)? field.type_name);
                            if let Some(e) = &$($m)? field.default_value {
                                self.visit_expression(e);
                            }
                            self.exit_declaration();
                        }
                        // Platform selection never drops a constructor or
                        // destructor, whatever its attributes.
                        if let Some(c) = &$($m)? s.constructor {
                            self.walk_function_body(c);
                        }
                        if let Some(d) = &$($m)? s.destructor {
                            self.walk_block_body(d);
                        }
                        for m in &$($m)? s.methods {
                            self.walk_function(m);
                        }
                        self.scopes_mut().pop();
                        self.scopes_mut().pop();
                    }
                    Declaration::Trait(t) => {
                        self.push_generics(&$($m)? t.generic_params);
                        self.scopes_mut().push(Scope::Trait(t.name.clone()));
                        // In a default method, the trait's methods are
                        // members of `this`: a bare call binds to them.
                        let methods = t
                            .methods
                            .iter()
                            .filter(|m| keep(&m.attributes).unwrap_or(true))
                            .map(|m| m.name.clone())
                            .collect();
                        self.scopes_mut().push(Scope::Values(methods));
                        for m in &$($m)? t.methods {
                            self.walk_function(m);
                        }
                        self.scopes_mut().pop();
                        self.scopes_mut().pop();
                        self.scopes_mut().pop();
                    }
                    Declaration::Extend(e) => {
                        // `extend Box<T>` introduces T; bind it before the
                        // target and traits that mention it.
                        let params = self.extend_params(&e.target);
                        self.scopes_mut().push(Scope::Generics(params));
                        self.visit_type_name(&$($m)? e.target);
                        for t in &$($m)? e.traits {
                            self.visit_type_name(t);
                        }
                        self.scopes_mut().push(Scope::Members(e.target.name.clone()));
                        for m in &$($m)? e.methods {
                            self.walk_function(m);
                        }
                        self.scopes_mut().pop();
                        self.scopes_mut().pop();
                    }
                    Declaration::TypeAlias(t) => {
                        self.push_generics(&$($m)? t.generic_params);
                        self.visit_type_name(&$($m)? t.target);
                        self.scopes_mut().pop();
                    }
                }
                self.exit_declaration();
            }

            /// A function, unless platform selection drops it.
            fn walk_function(&mut self, f: &$($m)? FunctionDecl) {
                if keep(&f.attributes).unwrap_or(true) {
                    self.walk_function_body(f);
                }
            }

            fn walk_function_body(&mut self, f: &$($m)? FunctionDecl) {
                self.enter_declaration(&f.attributes);
                if self.visit_function_generics(f) {
                    self.scopes_mut().push(Scope::Generics(HashSet::new()));
                } else {
                    self.push_generics(&$($m)? f.generic_params);
                }
                self.visit_type_name(&$($m)? f.return_type);
                self.scopes_mut().push(Scope::Values(HashSet::new()));
                for p in &$($m)? f.parameters {
                    self.visit_type_name(&$($m)? p.type_name);
                    if let Some(e) = &$($m)? p.default_value {
                        self.visit_expression(e);
                    }
                    let marked = self.visit_binding(&p.type_name, None);
                    self.scopes_mut().bind_value(&p.name, marked);
                }
                if let Some(body) = &$($m)? f.body {
                    self.walk_block(body);
                }
                self.scopes_mut().pop();
                self.scopes_mut().pop();
                self.exit_declaration();
            }

            /// A block, unless platform selection drops it.
            fn walk_block(&mut self, block: &$($m)? Block) {
                if keep(&block.attributes).unwrap_or(true) {
                    self.walk_block_body(block);
                }
            }

            fn walk_block_body(&mut self, block: &$($m)? Block) {
                self.scopes_mut().push(Scope::Values(HashSet::new()));
                for stmt in &$($m)? block.statements {
                    self.walk_statement(stmt);
                }
                self.scopes_mut().pop();
            }

            fn walk_statement(&mut self, stmt: &$($m)? Statement) {
                match stmt {
                    Statement::Expression(e) => self.visit_expression(e),
                    Statement::Block(b) => self.walk_block(b),
                    Statement::Declaration(d) => self.walk_declaration(d),
                    Statement::Branch(b) => {
                        self.visit_expression(&$($m)? b.condition);
                        self.walk_block(&$($m)? b.if_block);
                        if let Some(e) = &$($m)? b.else_block {
                            self.walk_block(e);
                        }
                    }
                    Statement::While(w) => {
                        self.visit_expression(&$($m)? w.condition);
                        self.walk_block(&$($m)? w.block);
                    }
                    Statement::For(f) => {
                        // The iterable is evaluated outside the loop
                        // variable's scope.
                        self.visit_expression(&$($m)? f.iterable);
                        self.scopes_mut().push(Scope::Values(HashSet::new()));
                        self.visit_type_name(&$($m)? f.binding.type_name);
                        let marked = self.visit_binding(&f.binding.type_name, Some(&f.iterable));
                        self.scopes_mut().bind_value(&f.binding.name, marked);
                        self.walk_block(&$($m)? f.block);
                        self.scopes_mut().pop();
                    }
                    Statement::With(w) => {
                        // The scope is evaluated outside the binding's scope;
                        // the binding is visible in the body only, not in
                        // `else`.
                        self.visit_expression(&$($m)? w.scope);
                        self.scopes_mut().push(Scope::Values(HashSet::new()));
                        if let Some(b) = &$($m)? w.binding {
                            self.visit_type_name(&$($m)? b.type_name);
                            let marked = self.visit_binding(&b.type_name, Some(&w.scope));
                            self.scopes_mut().bind_value(&b.name, marked);
                        }
                        self.walk_block(&$($m)? w.block);
                        self.scopes_mut().pop();
                        if let Some(e) = &$($m)? w.else_block {
                            self.walk_block(e);
                        }
                    }
                    Statement::Return(r) => {
                        if let Some(expr) = &$($m)? r.expr {
                            self.visit_expression(expr)
                        }
                    }
                    Statement::LoopBreak(_) => {}
                    Statement::Destructure(d) => {
                        // The value is evaluated before the bindings exist;
                        // they belong to the enclosing block.
                        self.visit_expression(&$($m)? d.value);
                        for b in &$($m)? d.bindings {
                            self.visit_type_name(&$($m)? b.type_name);
                            let marked = self.visit_binding(&b.type_name, None);
                            if b.name != "_" {
                                self.scopes_mut().bind_value(&b.name, marked);
                            }
                        }
                    }
                    Statement::Match(m) => {
                        self.visit_expression(&$($m)? m.value);
                        for arm in &$($m)? m.arms {
                            // A pattern's bindings are visible in its arm only.
                            self.scopes_mut().push(Scope::Values(HashSet::new()));
                            for p in &$($m)? arm.patterns {
                                if let Some(q) = &$($m)? p.qualifier {
                                    self.visit_type_name(q);
                                }
                                for (name, _) in p.bindings.iter().flatten() {
                                    if name != "_" {
                                        self.scopes_mut().bind_value(name, false);
                                    }
                                }
                            }
                            self.walk_block(&$($m)? arm.body);
                            self.scopes_mut().pop();
                        }
                        if let Some((_, b)) = &$($m)? m.else_arm {
                            self.walk_block(b);
                        }
                    }
                }
            }

            fn walk_expression(&mut self, expr: &$($m)? Expression) {
                match expr {
                    Expression::Literal { .. } => {}
                    Expression::SymbolRef { id, span } => {
                        let span = *span;
                        self.visit_symbol(id, span)
                    }
                    Expression::TypeLiteral(t) | Expression::SizeOf(t) => self.visit_type_name(t),
                    Expression::Unary { operand, .. } => self.visit_expression(operand),
                    Expression::Cast { expr, ty, .. } => {
                        self.visit_expression(expr);
                        self.visit_type_name(ty);
                    }
                    Expression::Binary { lhs, rhs, .. } | Expression::Index { lhs, rhs, .. } => {
                        self.visit_expression(lhs);
                        self.visit_expression(rhs);
                    }
                    Expression::Ternary { condition, true_expr, false_expr, .. } => {
                        self.visit_expression(condition);
                        self.visit_expression(true_expr);
                        self.visit_expression(false_expr);
                    }
                    Expression::MemberAccess { lhs, name, name_span, .. } => {
                        self.visit_expression(lhs);
                        self.visit_member(name, *name_span);
                    }
                    Expression::FunctionCall { function, arguments, .. } => {
                        self.visit_callee(&**function);
                        self.visit_expression(function);
                        for a in arguments {
                            self.visit_expression(a);
                        }
                    }
                    Expression::Closure(c) => {
                        // A closure's parameters hide outer names in its body.
                        self.scopes_mut().push(Scope::Values(HashSet::new()));
                        for p in &$($m)? c.parameters {
                            self.visit_type_name(&$($m)? p.type_name);
                            let marked = self.visit_binding(&p.type_name, None);
                            self.scopes_mut().bind_value(&p.name, marked);
                        }
                        self.visit_type_name(&$($m)? c.return_type);
                        self.walk_block(&$($m)? c.body);
                        self.scopes_mut().pop();
                    }
                    Expression::Tuple { elements, .. } => {
                        for e in elements {
                            self.visit_expression(e);
                        }
                    }
                }
            }

            /// Bind `params`, then walk their defaults, which may mention
            /// them (`R<T, E=T>`).
            fn push_generics(&mut self, params: &$($m)? [GenericParam]) {
                self.scopes_mut().push(Scope::Generics(params.iter().map(|p| p.name.clone()).collect()));
                for p in params {
                    if let Some(d) = &$($m)? p.default {
                        self.visit_type_name(d);
                    }
                }
            }
        }
    };
}

scope_walker!(
    /// The scope walk over a file's AST, read-only (the visibility check).
    ScopeWalk
);
scope_walker!(
    /// The scope walk over a file's AST, able to rewrite it (module linking).
    ScopeWalkMut,
    mut
);
