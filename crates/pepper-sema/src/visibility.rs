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
use crate::type_name::is_concrete_override;
use pepper_parser::ast::{
    Attribute, Block, Declaration, Expression, FunctionDecl, GenericParam, Module, Span, Statement,
    StructDecl, TypeName,
};
use std::collections::{HashMap, HashSet};

/// One parsed source file.
pub struct SourceFile<'a> {
    /// Display name used in diagnostics (usually the path).
    pub name: &'a str,
    /// The file's text, for turning spans into line/column positions.
    pub source: &'a str,
    pub module: &'a Module,
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
            VisibilityErrorKind::Duplicate => format!(
                "private '{}' is also declared in {}; top-level names must be unique across files",
                self.name, other
            ),
        }
    }

    /// `<file>:<line>:<col>: <message>`
    pub fn render(&self, files: &[SourceFile]) -> String {
        let file = &files[self.file];
        let p = self.span.start_position(file.source);
        format!("{}:{}:{}: {}", file.name, p.line + 1, p.col + 1, self.message(files))
    }
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

/// Check every file's references against the other files' exports.
pub fn check_visibility(files: &[SourceFile]) -> Vec<VisibilityError> {
    let mut decls: HashMap<&str, Vec<Decl>> = HashMap::new();
    let mut members = Members::default();
    for (i, file) in files.iter().enumerate() {
        let decl = |exported, span| Decl { file: i, exported, external: false, span, generics: vec![] };
        for d in &file.module.declarations {
            // A malformed attribute is reported by platform filtering itself.
            if !keep(attributes(d)).unwrap_or(true) {
                continue;
            }
            match d {
                Declaration::Function(f) => decls.entry(&f.name).or_default().push(Decl {
                    external: f.external,
                    generics: f.generic_params.iter().map(|g| g.name.as_str()).collect(),
                    ..decl(f.is_exported, f.name_span)
                }),
                Declaration::Struct(s) => {
                    decls.entry(&s.name).or_default().push(decl(s.is_exported, s.name_span));
                    members.of_struct.entry(&s.name).or_default().extend(struct_member_names(s));
                    for m in struct_member_names(s) {
                        members.in_struct_bodies.entry(m).or_default().push((i, s.is_exported));
                    }
                }
                Declaration::TypeAlias(t) => decls.entry(&t.name).or_default().push(decl(t.is_exported, t.name_span)),
                Declaration::Trait(t) => decls.entry(&t.name).or_default().push(decl(t.is_exported, t.name_span)),
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

    let mut errors = vec![];
    for (name, entries) in &decls {
        for d in entries.iter().filter(|d| !d.exported && !d.external) {
            if let Some(other) = entries.iter().find(|o| o.file != d.file && shape(o) == shape(d)) {
                errors.push(VisibilityError {
                    file: d.file,
                    span: d.span,
                    name: name.to_string(),
                    declared_in: other.file,
                    kind: VisibilityErrorKind::Duplicate,
                });
            }
        }
    }
    // HashMap order is arbitrary; report duplicates in source order.
    errors.sort_by_key(|e| (e.file, e.span.start));

    for (i, file) in files.iter().enumerate() {
        // An extension declares no name of its own; its target's name belongs
        // to the file that declares the struct.
        let own: HashSet<&str> = file
            .module
            .declarations
            .iter()
            .filter(|d| !matches!(d, Declaration::Extend(_)))
            .map(|d| d.name())
            .collect();
        let mut checker = Checker { file: i, own, decls: &decls, members: &members, scopes: vec![], errors: &mut errors };
        checker.module(file.module);
    }
    errors
}

fn attributes(d: &Declaration) -> &[Attribute] {
    match d {
        Declaration::Variable(v) => &v.attributes,
        Declaration::Function(f) => &f.attributes,
        Declaration::Struct(s) => &s.attributes,
        Declaration::Trait(t) => &t.attributes,
        Declaration::Extend(e) => &e.attributes,
        Declaration::TypeAlias(t) => &t.attributes,
    }
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
    decls: &'a HashMap<&'a str, Vec<Decl<'a>>>,
    members: &'a Members<'a>,
    /// Locally bound names, innermost last.
    scopes: Vec<HashSet<String>>,
    errors: &'e mut Vec<VisibilityError>,
}

impl<'a> Checker<'a, '_> {
    fn module(&mut self, module: &'a Module) {
        for decl in &module.declarations {
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
                if let Some(c) = &s.constructor {
                    self.function(c);
                }
                if let Some(d) = &s.destructor {
                    self.block(d);
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
                // before checking the target and traits that mention it.
                self.scopes.push(e.target.generic_types.iter().map(|t| t.name.clone()).collect());
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

    fn function(&mut self, f: &'a FunctionDecl) {
        self.push_generics(&f.generic_params);
        self.type_name(&f.return_type);
        self.scopes.push(HashSet::new());
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

    fn block(&mut self, block: &'a Block) {
        self.scopes.push(HashSet::new());
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
        self.reference(base, ty.span);
        for g in &ty.generic_types {
            self.type_name(g);
        }
    }

    fn reference(&mut self, name: &str, span: Span) {
        if self.own.contains(name) || self.scopes.iter().any(|s| s.contains(name)) {
            return;
        }
        // Not a top-level name: possibly a bare extension method in a method body.
        let Some(entries) = self.decls.get(name) else { return self.member(name, span) };
        if entries.iter().any(|d| d.exported || d.file == self.file) {
            return;
        }
        self.errors.push(VisibilityError {
            file: self.file,
            span,
            name: name.to_string(),
            declared_in: entries[0].file,
            kind: VisibilityErrorKind::Private,
        });
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
        if let Some(scope) = self.scopes.last_mut() {
            scope.insert(name.to_string());
        }
    }

    /// Bind `params`, then check their defaults, which may mention them
    /// (`R<T, E=T>`).
    fn push_generics(&mut self, params: &[GenericParam]) {
        self.scopes.push(params.iter().map(|p| p.name.clone()).collect());
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
        self.scopes.push(names);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pepper_parser::parser::parse_source;

    fn check(files: &[(&str, &str)]) -> Vec<String> {
        let modules: Vec<Module> = files.iter().map(|(n, s)| parse_source(n, s).expect("parse")).collect();
        let sources: Vec<SourceFile> = files
            .iter()
            .zip(&modules)
            .map(|((name, source), module)| SourceFile { name, source, module })
            .collect();
        check_visibility(&sources).iter().map(|e| e.render(&sources)).collect()
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
            ("lib.pep", "struct T { }\nexport struct Box<U> { var v: U; }"),
            ("main.pep", "extend Box<T> { get(): T { return v; } }\nstruct R<T, E=T> { var e: E; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
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
