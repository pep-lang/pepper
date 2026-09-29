//! Module visibility: every top-level declaration — functions (including
//! externs), structs, type aliases, traits, extensions, and module variables
//! — is private to the file that declares it unless marked `export`. Checked
//! on the per-file ASTs before they are merged into one sema `Module`, since
//! the merged model no longer knows where a name came from.
//!
//! A name is resolved the way the rest of the compiler resolves it — by
//! spelling, program-wide — with two refinements: a name the referencing file
//! declares itself (or binds locally: parameters, locals, generic parameters,
//! and the members of the struct being defined or extended) is always
//! visible, and a name declared only in other files is visible only if one of
//! those declarations is exported. Names with no top-level declaration
//! (builtins, intrinsics, primitive types) are not this check's concern.
//!
//! Because the merged program still has one namespace, a private name must
//! not also be declared in another file: the two would silently merge.
//! Externs are exempt, since every `extern` of a name is the same C symbol,
//! and a concrete override (`hash<String>` of `hash<T>`, as
//! `type_name::is_concrete_override` defines it) is a distinct declaration.
//! Anything else with generic parameters is a generic base, compared by
//! parameter count, not spelling: `pick<T>` and `pick<U>` collide, and so do
//! `hash<Point>` and `hash<T>`, since a user type is not an override.
//!
//! Declarations that platform selection drops (a false `[Target(...)]`) are
//! ignored as declarations: they can never collide or be referenced.
//!
//! An extension's methods share the extension's visibility. Member names are
//! resolved by spelling too, since this check runs before types are known: a
//! member (`x.m`, or a bare `m` in a method body) that some extension
//! declares is accepted only if a struct body visible to the referencing file
//! (its own, or exported) declares it, or an extension visible to it (its
//! own, or exported) does.

use crate::passes::platform::keep;
use crate::type_name::{is_concrete_override, is_override};
use pepper_parser::ast::{
    Block, Declaration, Expression, FunctionDecl, GenericParam, Module, Span, Statement,
    StructDecl, TypeName,
};
use pepper_parser::diagnostic::{Diagnostic, FileId, Loc, Sources};
use std::collections::{HashMap, HashSet};

/// One parsed source file.
pub struct SourceFile<'a> {
    /// Display name used in diagnostics (usually the path).
    pub name: &'a str,
    /// The file's text, for turning spans into line/column positions.
    pub source: &'a str,
    pub module: &'a Module,
    /// A prelude file (the runtime, a forced import): its exports are visible
    /// everywhere without an import.
    pub prelude: bool,
    /// Its exports may repeat other exempt files' exports: prelude files, and
    /// the other files of a forced module.
    pub duplicate_exempt: bool,
    /// The references module linking rewrote from an import (span start ->
    /// declaration name), from its [`crate::modules::FileScope`].
    pub imported: &'a HashMap<usize, String>,
}

/// What a [`VisibilityError`] is about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VisibilityErrorKind {
    /// A reference to a private top-level declaration of another file.
    Private,
    /// A reference to a method of another file's private extension.
    PrivateExtension,
    /// A private declaration whose name another file also declares.
    Duplicate,
    /// A reference to another file's export that this file did not import.
    NotImported,
    /// An exported declaration of a non-prelude file whose name another file
    /// also declares: imports would resolve both to one of them.
    DuplicateExport,
}

/// A visibility violation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VisibilityError {
    /// Index into the `files` slice of the offending file.
    pub file: usize,
    /// Span of the reference (or, for `Duplicate`, the declared name) in
    /// that file.
    pub span: Span,
    /// The referenced or declared name.
    pub name: String,
    /// Index of the other file involved: the one that declares the name
    /// privately, or for `Duplicate`, the one that also declares it.
    pub declared_in: usize,
    pub kind: VisibilityErrorKind,
}

impl VisibilityError {
    /// The diagnostic text, without a position.
    pub fn message(&self, files: &[SourceFile]) -> String {
        let other = files[self.declared_in].name;
        match self.kind {
            VisibilityErrorKind::Private => {
                format!("'{}' is private to {}; declare it with 'export' to use it from another file", self.name, other)
            }
            VisibilityErrorKind::PrivateExtension => format!(
                "'{}' is declared in a private extension in {}; declare the extension with 'export' to use it from another file",
                self.name, other
            ),
            VisibilityErrorKind::NotImported => format!(
                "'{}' is exported by {}, which this file does not import; add an import for it",
                self.name, other
            ),
            VisibilityErrorKind::DuplicateExport => format!(
                "exported '{}' is also declared in {}; top-level names must be unique across files, even in different modules",
                self.name, other
            ),
            VisibilityErrorKind::Duplicate => format!(
                "private '{}' is also declared in {}; top-level names must be unique across files",
                self.name, other
            ),
        }
    }

    /// The error, with a note at the declaration in the other file. File
    /// ids are indices into `files`.
    pub fn to_diagnostic(&self, files: &[SourceFile]) -> Diagnostic {
        let note = match self.kind {
            VisibilityErrorKind::Duplicate => "also declared here",
            _ => "declared here",
        };
        let declared_at = declaration_span(files[self.declared_in].module, &self.name, self.kind)
            .map(|span| Loc::new(FileId(self.declared_in as u32), span));
        Diagnostic::error(self.message(files))
            .at(Loc::new(FileId(self.file as u32), self.span))
            .with_note(note, declared_at)
    }

    /// The rendered diagnostic (see [`pepper_parser::diagnostic`]).
    pub fn render(&self, files: &[SourceFile]) -> String {
        self.to_diagnostic(files).render(&Files(files))
    }
}

/// `files` as the name and text lookup diagnostics render against.
struct Files<'a, 'b>(&'a [SourceFile<'b>]);

impl Sources for Files<'_, '_> {
    fn get(&self, file: FileId) -> Option<(&str, &str)> {
        self.0.get(file.0 as usize).map(|f| (f.name, f.source))
    }
}

/// Span of the name `name` declares in `module`: a top-level declaration,
/// or for a private-extension error, the extension method.
fn declaration_span(module: &Module, name: &str, kind: VisibilityErrorKind) -> Option<Span> {
    module.declarations.iter().find_map(|d| match d {
        Declaration::Extend(e) if kind == VisibilityErrorKind::PrivateExtension => {
            e.methods.iter().find(|m| m.name == name).map(|m| m.name_span)
        }
        Declaration::Extend(_) => None,
        d if d.name() == name => Some(d.name_span()),
        _ => None,
    })
}

/// One named top-level declaration.
#[derive(Clone)]
struct Decl<'a> {
    file: usize,
    exported: bool,
    /// An `extern` function: every declaration of it names one C symbol.
    external: bool,
    /// The declared name's span.
    span: Span,
    /// A function's generic parameters as spelled, which tell a concrete
    /// override (`hash<Point>`) from the generic it specializes (`hash<T>`).
    generics: Vec<&'a str>,
}

/// A generic function a concrete override (`pick<int>`) would specialize:
/// it has generic parameters, and they are not all concrete.
fn is_generic_base(d: &Decl) -> bool {
    !d.generics.is_empty() && !is_override(d.generics.iter().copied())
}

/// Check every file's references against the other files' exports.
pub fn check_visibility(files: &[SourceFile]) -> Vec<VisibilityError> {
    let mut decls: HashMap<&str, Vec<Decl>> = HashMap::new();
    let mut types: HashSet<&str> = HashSet::new();
    let mut members = Members::default();
    for (i, file) in files.iter().enumerate() {
        let decl = |exported, span| Decl { file: i, exported, external: false, span, generics: vec![] };
        for d in &file.module.declarations {
            // A malformed attribute is reported by platform filtering itself.
            if !keep(d.attributes()).unwrap_or(true) {
                continue;
            }
            match d {
                Declaration::Function(f) => decls.entry(&f.name).or_default().push(Decl {
                    external: f.external,
                    generics: f.generic_params.iter().map(|g| g.name.as_str()).collect(),
                    ..decl(f.is_exported, f.name_span)
                }),
                Declaration::Struct(s) => {
                    types.insert(&s.name);
                    decls.entry(&s.name).or_default().push(decl(s.is_exported, s.name_span));
                    members.of_struct.entry(&s.name).or_default().extend(struct_member_names(s));
                    for m in struct_member_names(s) {
                        members.in_struct_bodies.entry(m).or_default().push((i, s.is_exported));
                    }
                }
                Declaration::TypeAlias(t) => {
                    types.insert(&t.name);
                    decls.entry(&t.name).or_default().push(decl(t.is_exported, t.name_span))
                }
                Declaration::Trait(t) => {
                    types.insert(&t.name);
                    decls.entry(&t.name).or_default().push(decl(t.is_exported, t.name_span))
                }
                Declaration::Variable(v) => decls.entry(&v.name).or_default().push(decl(v.is_exported, v.name_span)),
                Declaration::Extend(e) => {
                    for m in &e.methods {
                        members.of_extensions.entry(&e.target.name).or_default().push((&m.name, i, e.is_exported));
                        members.in_extensions.entry(&m.name).or_default().push((i, e.is_exported));
                    }
                }
            }
        }
    }

    // A concrete override is identified by its arguments; a generic base
    // only by how many parameters it has.
    let shape = |d: &Decl| -> Vec<Option<String>> {
        if is_concrete_override(d.generics.iter().copied()) {
            d.generics.iter().map(|&g| Some(g.to_string())).collect()
        } else {
            vec![None; d.generics.len()]
        }
    };

    let prelude: Vec<bool> = files.iter().map(|f| f.prelude).collect();
    let exempt: Vec<bool> = files.iter().map(|f| f.duplicate_exempt).collect();
    let mut errors = vec![];
    for (name, entries) in &decls {
        // Exports of prelude files (the runtime and `--import` modules) may
        // repeat each other, by design: the runtime is one unit, and a forced
        // import may supply its own definition of a runtime export. Every
        // other file's names must be unique.
        for d in entries.iter().filter(|d| !d.external && (!d.exported || !exempt[d.file])) {
            if let Some(other) = entries.iter().find(|o| o.file != d.file && shape(o) == shape(d)) {
                errors.push(VisibilityError {
                    file: d.file,
                    span: d.span,
                    name: name.to_string(),
                    declared_in: other.file,
                    kind: if d.exported { VisibilityErrorKind::DuplicateExport } else { VisibilityErrorKind::Duplicate },
                });
            }
        }
    }
    // A concrete override (`conv<int>`) of a generic base only another file
    // declares, privately, would replace that file's own instantiation of
    // it, whether or not this file ever calls it: the base is out of reach.
    for (name, entries) in &decls {
        for d in entries.iter().filter(|d| !d.external && is_override(d.generics.iter().copied())) {
            let is_base_of_d = |e: &&Decl| is_generic_base(e) && e.generics.len() == d.generics.len();
            if entries.iter().any(|e| e.file == d.file && is_base_of_d(&e)) {
                continue;
            }
            if let Some(base) = entries.iter().find(|e| e.file != d.file && !e.exported && is_base_of_d(e)) {
                errors.push(VisibilityError {
                    file: d.file,
                    span: d.span,
                    name: name.to_string(),
                    declared_in: base.file,
                    kind: VisibilityErrorKind::Private,
                });
            }
        }
    }
    // HashMap order is arbitrary; report duplicates in source order.
    errors.sort_by_key(|e| (e.file, e.span.start));

    for (i, file) in files.iter().enumerate() {
        // An extension declares no name of its own; its target's name belongs
        // to the file that declares the struct.
        // Nor does a concrete override (`pick<int>`): after linking it may
        // carry an imported generic's name, which it must not make visible.
        let own: HashSet<&str> = file
            .module
            .declarations
            .iter()
            .filter(|d| match d {
                Declaration::Extend(_) => false,
                Declaration::Function(f) => !is_override(f.generic_params.iter().map(|g| g.name.as_str())),
                _ => true,
            })
            // Nor does one platform selection drops: it is never compiled.
            .filter(|d| keep(d.attributes()).unwrap_or(true))
            .map(|d| d.name())
            .collect();
        let mut checker = Checker {
            file: i,
            own,
            imported: file.imported,
            types: &types,
            prelude: &prelude,
            decls: &decls,
            members: &members,
            scopes: vec![],
            errors: &mut errors,
        };
        checker.module(file.module);
    }
    errors
}

/// Member names across the program, for bare member refs in method bodies
/// and for `x.m` accesses. Each entry is (declaring file, exported).
#[derive(Default)]
struct Members<'a> {
    /// struct name -> names declared in its body (fields + methods).
    of_struct: HashMap<&'a str, HashSet<&'a str>>,
    /// member name -> the structs whose bodies declare it (fields + methods).
    in_struct_bodies: HashMap<&'a str, Vec<(usize, bool)>>,
    /// struct name -> (method, declaring file, exported) from extensions.
    of_extensions: HashMap<&'a str, Vec<(&'a str, usize, bool)>>,
    /// method name -> the extensions that declare it.
    in_extensions: HashMap<&'a str, Vec<(usize, bool)>>,
}

fn struct_member_names(s: &StructDecl) -> impl Iterator<Item = &str> {
    s.fields.iter().map(|f| f.name.as_str()).chain(s.methods.iter().map(|m| m.name.as_str()))
}

struct Checker<'a, 'e> {
    file: usize,
    own: HashSet<&'a str>,
    /// References linking rewrote from an import: span start -> name.
    imported: &'a HashMap<usize, String>,
    /// Every type name declared at top level (structs, aliases, traits).
    types: &'a HashSet<&'a str>,
    /// Per file: its exports are visible without an import.
    prelude: &'a [bool],
    decls: &'a HashMap<&'a str, Vec<Decl<'a>>>,
    members: &'a Members<'a>,
    /// Locally bound names, innermost last.
    /// Locally bound names, innermost last; `true` for generic parameters,
    /// the only names that hide a type.
    scopes: Vec<(HashSet<String>, bool)>,
    errors: &'e mut Vec<VisibilityError>,
}

impl<'a> Checker<'a, '_> {
    fn module(&mut self, module: &'a Module) {
        // What platform selection drops is never compiled, and linking did
        // not look at it either.
        for decl in module.declarations.iter().filter(|d| keep(d.attributes()).unwrap_or(true)) {
            self.declaration(decl);
        }
    }

    fn declaration(&mut self, decl: &'a Declaration) {
        match decl {
            Declaration::Variable(v) => {
                self.type_name(&v.type_name);
                if let Some(e) = &v.default_value {
                    self.expression(e);
                }
                self.bind(&v.name);
            }
            Declaration::Function(f) => self.function(f),
            Declaration::Struct(s) => {
                self.push_generics(&s.generic_params);
                self.bind_members(&s.name);
                for field in &s.fields {
                    self.type_name(&field.type_name);
                    if let Some(e) = &field.default_value {
                        self.expression(e);
                    }
                }
                // Platform selection never drops a constructor or destructor,
                // whatever its attributes, so both are always checked.
                if let Some(c) = &s.constructor {
                    self.function_body(c);
                }
                if let Some(d) = &s.destructor {
                    self.block_body(d);
                }
                for m in &s.methods {
                    self.function(m);
                }
                self.scopes.pop();
                self.scopes.pop();
            }
            Declaration::Trait(t) => {
                self.push_generics(&t.generic_params);
                for m in &t.methods {
                    self.function(m);
                }
                self.scopes.pop();
            }
            Declaration::Extend(e) => {
                // `extend Foo<T>` introduces T as a generic parameter; bind it
                // before checking the target and traits that mention it. A
                // name the program declares as a type specializes instead
                // (`extend Array<Point>`), and is checked like any reference.
                self.scopes.push((
                    e.target
                        .generic_types
                        .iter()
                        .filter(|t| t.generic_types.is_empty() && !self.types.contains(t.name.as_str()))
                        .map(|t| t.name.clone())
                        .collect(),
                    true,
                ));
                self.type_name(&e.target);
                for t in &e.traits {
                    self.type_name(t);
                }
                self.bind_members(&e.target.name);
                for m in &e.methods {
                    self.function(m);
                }
                self.scopes.pop();
                self.scopes.pop();
            }
            Declaration::TypeAlias(t) => {
                self.push_generics(&t.generic_params);
                self.type_name(&t.target);
                self.scopes.pop();
            }
        }
    }

    /// A function, unless platform selection drops it.
    fn function(&mut self, f: &'a FunctionDecl) {
        if keep(&f.attributes).unwrap_or(true) {
            self.function_body(f);
        }
    }

    fn function_body(&mut self, f: &'a FunctionDecl) {
        self.push_generics(&f.generic_params);
        self.type_name(&f.return_type);
        self.scopes.push((HashSet::new(), false));
        for p in &f.parameters {
            self.type_name(&p.type_name);
            if let Some(e) = &p.default_value {
                self.expression(e);
            }
            self.bind(&p.name);
        }
        if let Some(body) = &f.body {
            self.block(body);
        }
        self.scopes.pop();
        self.scopes.pop();
    }

    /// A block, unless platform selection drops it.
    fn block(&mut self, block: &'a Block) {
        if keep(&block.attributes).unwrap_or(true) {
            self.block_body(block);
        }
    }

    fn block_body(&mut self, block: &'a Block) {
        self.scopes.push((HashSet::new(), false));
        for stmt in &block.statements {
            self.statement(stmt);
        }
        self.scopes.pop();
    }

    fn statement(&mut self, stmt: &'a Statement) {
        match stmt {
            Statement::Expression(e) => self.expression(e),
            Statement::Block(b) => self.block(b),
            Statement::Declaration(d) => self.declaration(d),
            Statement::Branch(b) => {
                self.expression(&b.condition);
                self.block(&b.if_block);
                if let Some(e) = &b.else_block {
                    self.block(e);
                }
            }
            Statement::While(w) => {
                self.expression(&w.condition);
                self.block(&w.block);
            }
            Statement::For(f) => {
                // The iterable is evaluated outside the loop variable's scope.
                self.expression(&f.iterable);
                self.scopes.push((HashSet::new(), false));
                self.type_name(&f.binding.type_name);
                self.bind(&f.binding.name);
                self.block(&f.block);
                self.scopes.pop();
            }
            Statement::With(w) => {
                // The scope is evaluated outside the binding's scope; the
                // binding is visible in the body only, not in `else`.
                self.expression(&w.scope);
                self.scopes.push((HashSet::new(), false));
                if let Some(b) = &w.binding {
                    self.type_name(&b.type_name);
                    self.bind(&b.name);
                }
                self.block(&w.block);
                self.scopes.pop();
                if let Some(e) = &w.else_block {
                    self.block(e);
                }
            }
            Statement::Return(r) => self.expression(&r.expr),
            Statement::LoopBreak(_) => {}
        }
    }

    fn expression(&mut self, expr: &'a Expression) {
        match expr {
            Expression::Literal { .. } => {}
            Expression::SymbolRef { id, span } => self.reference(id, *span),
            Expression::TypeLiteral(t) | Expression::SizeOf(t) => self.type_name(t),
            Expression::Unary { operand, .. } => self.expression(operand),
            Expression::Cast { expr, ty, .. } => {
                self.expression(expr);
                self.type_name(ty);
            }
            Expression::Binary { lhs, rhs, .. } | Expression::Index { lhs, rhs, .. } => {
                self.expression(lhs);
                self.expression(rhs);
            }
            Expression::Ternary { condition, true_expr, false_expr, .. } => {
                self.expression(condition);
                self.expression(true_expr);
                self.expression(false_expr);
            }
            Expression::MemberAccess { lhs, name, name_span, .. } => {
                self.expression(lhs);
                self.member(name, *name_span);
            }
            Expression::FunctionCall { function, arguments, .. } => {
                self.expression(function);
                for a in arguments {
                    self.expression(a);
                }
            }
        }
    }

    fn type_name(&mut self, ty: &TypeName) {
        let base = ty.name.trim_end_matches(|c| c == '*' || c == '[' || c == ']');
        // Only a generic parameter hides a type: a local or member named
        // `Point` is a value, as linking also treats it.
        if self.scopes.iter().any(|(s, generic)| *generic && s.contains(base)) {
            for g in &ty.generic_types {
                self.type_name(g);
            }
            return;
        }
        self.check_reference(base, ty.span);
        for g in &ty.generic_types {
            self.type_name(g);
        }
    }

    fn reference(&mut self, name: &str, span: Span) {
        if self.scopes.iter().any(|(s, _)| s.contains(name)) {
            return;
        }
        self.check_reference(name, span);
    }

    /// Check a reference not bound locally.
    fn check_reference(&mut self, name: &str, span: Span) {
        if self.own.contains(name) {
            return;
        }
        // Not a top-level name: possibly a bare extension method in a method body.
        let Some(entries) = self.decls.get(name) else { return self.member(name, span) };
        if self.imported.get(&span.start).is_some_and(|n| n == name)
            // This file's own declaration counts, unless it is only a concrete
            // override (`pick<int>`) of a generic another file exports: that
            // would unlock the other file's name. (Overriding another file's
            // private generic is reported once, at the override.)
            || entries.iter().any(|d| {
                (d.file == self.file
                    && (!is_override(d.generics.iter().copied())
                        || !entries
                            .iter()
                            .any(|e| e.file != self.file && e.exported && is_generic_base(e))))
                    || (d.exported && self.prelude[d.file])
            })
        {
            return;
        }
        // Name the other file: the one whose declaration is out of reach.
        let elsewhere = entries.iter().find(|d| d.file != self.file).unwrap_or(&entries[0]);
        let (declared_in, kind) = match entries.iter().find(|d| d.exported && d.file != self.file) {
            Some(d) => (d.file, VisibilityErrorKind::NotImported),
            None => (elsewhere.file, VisibilityErrorKind::Private),
        };
        self.errors.push(VisibilityError { file: self.file, span, name: name.to_string(), declared_in, kind });
    }

    /// A member name (`x.name`, or bare `name` in a method body) that some
    /// extension declares: rejected unless a struct body or an extension
    /// visible to this file declares it too.
    fn member(&mut self, name: &str, span: Span) {
        let Some(entries) = self.members.in_extensions.get(name) else { return };
        let visible = |&(file, exported): &(usize, bool)| exported || file == self.file;
        if entries.iter().any(visible) || self.members.in_struct_bodies.get(name).is_some_and(|s| s.iter().any(visible)) {
            return;
        }
        self.errors.push(VisibilityError {
            file: self.file,
            span,
            name: name.to_string(),
            declared_in: entries[0].0,
            kind: VisibilityErrorKind::PrivateExtension,
        });
    }

    fn bind(&mut self, name: &str) {
        if let Some((scope, _)) = self.scopes.last_mut() {
            scope.insert(name.to_string());
        }
    }

    /// Bind `params`, then check their defaults, which may mention them
    /// (`R<T, E=T>`).
    fn push_generics(&mut self, params: &[GenericParam]) {
        self.scopes.push((params.iter().map(|p| p.name.clone()).collect(), true));
        for p in params {
            if let Some(d) = &p.default {
                self.type_name(d);
            }
        }
    }

    /// Bind the members of `struct_name` visible in this file: its body's,
    /// plus methods of exported extensions and of this file's own.
    fn bind_members(&mut self, struct_name: &str) {
        let mut names: HashSet<String> =
            self.members.of_struct.get(struct_name).map(|m| m.iter().map(|s| s.to_string()).collect()).unwrap_or_default();
        if let Some(ext) = self.members.of_extensions.get(struct_name) {
            names.extend(
                ext.iter().filter(|&&(_, file, exported)| exported || file == self.file).map(|&(m, _, _)| m.to_string()),
            );
        }
        self.scopes.push((names, false));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pepper_parser::parser::parse_source;

    fn check(files: &[(&str, &str)]) -> Vec<String> {
        let modules: Vec<Module> = files.iter().map(|(n, s)| parse_source(n, s).expect("parse")).collect();
        let none = HashMap::new();
        let sources: Vec<SourceFile> = files
            .iter()
            .zip(&modules)
            // Unlinked, as before modules: every file's exports are visible.
            .map(|((name, source), module)| SourceFile { name, source, module, prelude: true, duplicate_exempt: true, imported: &none })
            .collect();
        check_visibility(&sources).iter().map(|e| header(e, &sources)).collect()
    }

    /// `<file>:<line>:<col>: <message>`: where the error is and what it
    /// says, without the rendered snippet and note.
    fn header(e: &VisibilityError, files: &[SourceFile]) -> String {
        let file = &files[e.file];
        let p = e.span.start_position(file.source);
        format!("{}:{}:{}: {}", file.name, p.line + 1, p.col + 1, e.message(files))
    }

    #[test]
    fn rendered_error_notes_the_declaration() {
        let lib_src = "helper(): int { return 1; }\n";
        let lib = pepper_parser::parser::parse_source("lib.pep", lib_src).unwrap();
        let main_src = "main(): int {\n    return helper();\n}\n";
        let main = pepper_parser::parser::parse_source("main.pep", main_src).unwrap();
        let none = HashMap::new();
        let files = [
            SourceFile { name: "lib.pep", source: lib_src, module: &lib, prelude: true, duplicate_exempt: true, imported: &none },
            SourceFile { name: "main.pep", source: main_src, module: &main, prelude: true, duplicate_exempt: true, imported: &none },
        ];
        let rendered: Vec<String> = check_visibility(&files).iter().map(|e| e.render(&files)).collect();
        assert_eq!(
            rendered,
            ["main.pep:2:12: error: 'helper' is private to lib.pep; declare it with 'export' to use it from another file\n\
              \x20   2 |     return helper();\n\
              \x20     |            ^~~~~~\n\
              lib.pep:1:1: note: declared here\n\
              \x20   1 | helper(): int { return 1; }\n\
              \x20     | ^~~~~~"]
        );
    }

    #[test]
    fn private_function_is_hidden_from_other_files() {
        let errors = check(&[
            ("lib.pep", "sum(x: int, y: int): int { return x + y; }"),
            ("main.pep", "main(): int {\n    return sum(1, 2);\n}"),
        ]);
        assert_eq!(errors, vec!["main.pep:2:12: 'sum' is private to lib.pep; declare it with 'export' to use it from another file"]);
    }

    #[test]
    fn exported_function_is_visible() {
        let errors = check(&[
            ("lib.pep", "export sum(x: int, y: int): int { return x + y; }"),
            ("main.pep", "main(): int { return sum(1, 2); }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn private_symbols_are_visible_in_their_own_file() {
        let errors = check(&[(
            "lib.pep",
            "struct Point { var x: int; }\ntype P = Point;\nhelper(): P { return Point(); }\nexport api(): int { return helper().x; }",
        )]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn private_struct_and_alias_are_hidden_in_type_positions() {
        let errors = check(&[
            ("lib.pep", "struct Point { var x: int; }\ntype Id = int;\nexport struct Pub<T> { var v: T; }"),
            ("main.pep", "main(): int {\n    var p: Pub<Point> = Pub<Point>();\n    var i: Id = 0;\n    return i;\n}"),
        ]);
        assert_eq!(errors.len(), 3, "{:?}", errors);
        assert!(errors.iter().filter(|e| e.contains("'Point'")).count() == 2, "{:?}", errors);
        assert!(errors.iter().any(|e| e.contains("'Id'")), "{:?}", errors);
    }

    #[test]
    fn locals_parameters_and_generics_shadow_private_names() {
        let errors = check(&[
            ("lib.pep", "count(): int { return 0; }\nstruct T { }"),
            ("main.pep", "f<T>(value: T, count: int): int { var n = count; return n; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn extern_is_private_without_export() {
        let errors = check(&[
            ("lib.pep", "extern int puts(char* s);\nexport extern void abort();"),
            ("main.pep", "main(): int { abort(); puts(__null); return 0; }"),
        ]);
        assert_eq!(errors.len(), 1, "{:?}", errors);
        assert!(errors[0].contains("'puts'"), "{:?}", errors);
    }

    #[test]
    fn private_trait_and_module_variable_are_hidden() {
        let errors = check(&[
            ("lib.pep", "trait Hidden { }\nexport trait Shown { }\nvar secret = 1;\nexport var counter = 2;\nexport struct S { }"),
            ("main.pep", "extend S with Hidden, Shown { }\nmain(): int {\n    return secret + counter;\n}"),
        ]);
        assert_eq!(errors.len(), 2, "{:?}", errors);
        assert!(errors[0].starts_with("main.pep:1:15: 'Hidden' is private to lib.pep"), "{:?}", errors);
        assert!(errors[1].starts_with("main.pep:3:12: 'secret' is private to lib.pep"), "{:?}", errors);
    }

    #[test]
    fn private_extension_methods_are_hidden() {
        let errors = check(&[
            (
                "lib.pep",
                "export struct S { var x: int; }\nextend S { hidden(): int { return x; } }\n\
                 export extend S { shown(): int { return hidden(); } }",
            ),
            (
                "main.pep",
                "extend S { other(): int { return shown() + hidden(); } }\n\
                 main(): int {\n    var s = S();\n    return s.shown() + s.hidden() + s.x;\n}",
            ),
        ]);
        assert_eq!(errors.len(), 2, "{:?}", errors);
        assert!(errors[0].starts_with("main.pep:1:44: 'hidden' is declared in a private extension in lib.pep"), "{:?}", errors);
        assert!(errors[1].starts_with("main.pep:4:26: 'hidden'"), "{:?}", errors);
    }

    #[test]
    fn private_trait_conformance_and_unrelated_members_do_not_leak() {
        let errors = check(&[
            (
                "lib.pep",
                "export struct S { }\nexport trait Printable { print(): int; }\n\
                 extend S with Printable { print(): int { return 0; } }\nextend S { norm(): int { return 0; } }",
            ),
            ("other.pep", "struct Unrelated { var norm: int; }"),
            ("main.pep", "main(): int {\n    var s = S();\n    return s.print() + s.norm();\n}"),
        ]);
        assert_eq!(errors.len(), 2, "{:?}", errors);
        assert!(errors[0].contains("'print' is declared in a private extension"), "{:?}", errors);
        assert!(errors[1].contains("'norm' is declared in a private extension"), "{:?}", errors);
    }

    #[test]
    fn exported_struct_body_member_is_visible_despite_private_extension() {
        let errors = check(&[
            ("lib.pep", "export struct S { var n: int; }\nstruct Q { }\nextend Q { n(): int { return 0; } }"),
            ("main.pep", "main(): int { var s = S(); return s.n; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn private_names_must_be_unique_across_files() {
        let errors = check(&[
            ("a.pep", "helper(): int { return 1; }\nvar counter = 1;\nextern int puts(char* s);\nexport f(): int { return 0; }"),
            ("b.pep", "helper(): int { return 2; }\nexport var counter = 2;\nextern int puts(char* s);\nexport f(): int { return 0; }"),
        ]);
        assert_eq!(
            errors,
            vec![
                "a.pep:1:1: private 'helper' is also declared in b.pep; top-level names must be unique across files",
                "a.pep:2:5: private 'counter' is also declared in b.pep; top-level names must be unique across files",
                "b.pep:1:1: private 'helper' is also declared in a.pep; top-level names must be unique across files",
            ]
        );
    }

    #[test]
    fn private_concrete_override_is_not_a_duplicate() {
        let errors = check(&[
            ("lib.pep", "export hash<T>(T value): u64 { return 0; }"),
            ("main.pep", "hash<int>(int v): u64 { return 42; }\nmain(): int { return 0; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn user_type_argument_is_a_generic_base_not_an_override() {
        // The compiler reads `hash<Point>` as a second generic base whose
        // parameter is named `Point`; it would replace `hash<T>` everywhere.
        let errors = check(&[
            ("lib.pep", "export hash<T>(T value): u64 { return 0; }"),
            ("main.pep", "struct Point { }\nhash<Point>(Point p): u64 { return 42; }"),
        ]);
        assert_eq!(errors.len(), 1, "{:?}", errors);
        assert!(errors[0].starts_with("main.pep:2:1: private 'hash' is also declared in lib.pep"), "{:?}", errors);
    }

    #[test]
    fn generic_duplicates_collide_whatever_their_parameter_names() {
        let errors = check(&[
            ("a.pep", "pick<T>(v: T): int { return 1; }"),
            ("b.pep", "pick<U>(v: U): int { return 2; }\nexport hash<T>(v: T): u64 { return 0; }\nexport hash<int>(v: int): u64 { return 1; }"),
            ("c.pep", "hash<K>(v: K): u64 { return 2; }\nhash<u64>(v: u64): u64 { return 3; }"),
        ]);
        assert_eq!(errors.len(), 3, "{:?}", errors);
        assert!(errors[0].starts_with("a.pep:1:1: private 'pick' is also declared in b.pep"), "{:?}", errors);
        assert!(errors[1].starts_with("b.pep:1:1: private 'pick' is also declared in a.pep"), "{:?}", errors);
        assert!(errors[2].starts_with("c.pep:1:1: private 'hash' is also declared in b.pep"), "{:?}", errors);
    }

    #[test]
    fn declarations_filtered_out_for_this_platform_are_ignored() {
        // Exactly one of the two helpers survives platform selection.
        let errors = check(&[
            ("win.pep", "[Target(OS(Windows))] helper(): int { return 1; }"),
            ("other.pep", "[Target(!OS(Windows))] helper(): int { return 2; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn generic_parameters_shadow_private_names_in_extend_and_defaults() {
        let errors = check(&[
            ("lib.pep", "count(): int { return 0; }\nexport struct Box<U> { var v: U; }\nstruct T { }"),
            ("main.pep", "extend Box<V> { get(): V { return v; } }\nstruct R<T, E=T> { var e: E; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn a_declared_type_in_extend_specializes_and_is_checked() {
        // `T` names lib's private struct, so `extend Box<T>` specializes
        // `Box<T>` (as sema reads it) rather than introducing a parameter.
        let errors = check(&[
            ("lib.pep", "struct T { }\nexport struct Box<U> { var v: U; }"),
            ("main.pep", "extend Box<T> { get(): int { return 0; } }"),
        ]);
        assert_eq!(errors.len(), 1, "{:?}", errors);
        assert!(errors[0].contains("'T' is private to lib.pep"), "{:?}", errors);
    }

    #[test]
    fn extending_a_private_struct_does_not_make_it_visible() {
        let errors = check(&[
            ("lib.pep", "struct Hidden { }"),
            ("main.pep", "extend Hidden { f(): int { return 0; } }\nmain(): int { var h = Hidden(); return 0; }"),
        ]);
        assert_eq!(errors.len(), 2, "{:?}", errors);
        assert!(errors.iter().all(|e| e.contains("'Hidden' is private")), "{:?}", errors);
    }
}
