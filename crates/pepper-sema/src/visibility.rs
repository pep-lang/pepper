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
//! Linking has already given private declarations names no other file can
//! spell (see [`pepper_parser::namespace`]), so two files may each declare a
//! private `helper`. A reference that names another file's private
//! declaration is left unrenamed by linking; it is matched here by its
//! demangled name and reported as private. What keeps its name in the merged
//! program must still be unique: an exported declaration of a non-prelude
//! file, and a concrete override (`hash<String>` of `hash<T>`, as
//! `type_name::is_concrete_override` defines it), which takes its generic's
//! name. Externs are exempt, since every `extern` of a name is the same C
//! symbol. Anything else with generic parameters is a generic base, compared
//! by parameter count, not spelling: `pick<T>` and `pick<U>` collide, and so
//! do `hash<Point>` and `hash<T>`, since a user type is not an override.
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
use crate::scope_walk::{ScopeWalk, Scopes};
use pepper_parser::ast::{Declaration, Module, Span, StructDecl, TypeName};
use pepper_parser::diagnostic::{Diagnostic, FileId, Loc, Sources};
use pepper_parser::namespace::{SEPARATOR, demangle_name};
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
    /// A private concrete override (`hash<int>`) another file also declares.
    DuplicateOverride,
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
            VisibilityErrorKind::DuplicateOverride => format!(
                "override '{}' is also declared in {}; a generic may be overridden for the same types in only one file",
                self.name, other
            ),
        }
    }

    /// The error, with a note at the declaration in the other file. File
    /// ids are indices into `files`.
    pub fn to_diagnostic(&self, files: &[SourceFile]) -> Diagnostic {
        let note = match self.kind {
            VisibilityErrorKind::DuplicateOverride => "also declared here",
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
        d if demangle_name(d.name()) == name => Some(d.name_span()),
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
    // Mangled private declarations, by the name the user wrote.
    let mut private: HashMap<String, Vec<Decl>> = HashMap::new();
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
                    members.struct_params.insert(&s.name, s.generic_params.iter().map(|g| g.name.as_str()).collect());
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

    for (name, entries) in &decls {
        if name.contains(SEPARATOR) {
            private.entry(demangle_name(name).to_string()).or_default().extend(entries.iter().cloned());
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
        // Private declarations are mangled apart, except overrides.
        let kept_name = |d: &&Decl| d.exported || is_override(d.generics.iter().copied());
        for d in entries.iter().filter(|d| !d.external && (!d.exported || !exempt[d.file])).filter(kept_name) {
            if let Some(other) = entries.iter().find(|o| o.file != d.file && shape(o) == shape(d)) {
                let (name, kind) = if d.exported {
                    (name.to_string(), VisibilityErrorKind::DuplicateExport)
                } else {
                    (format!("{}<{}>", name, d.generics.join(", ")), VisibilityErrorKind::DuplicateOverride)
                };
                errors.push(VisibilityError { file: d.file, span: d.span, name, declared_in: other.file, kind });
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
            // The base may be private under its own name (in the root file)
            // or mangled.
            let private_bases = entries.iter().filter(|e| !e.exported).chain(private.get(*name).into_iter().flatten());
            if let Some(base) = private_bases.into_iter().find(|e| e.file != d.file && is_base_of_d(e)) {
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
            private: &private,
            members: &members,
            scopes: Scopes::default(),
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
    /// Struct name -> its generic parameter names.
    struct_params: HashMap<&'a str, Vec<&'a str>>,
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
    /// Other files' private declarations, by the name the user wrote.
    private: &'a HashMap<String, Vec<Decl<'a>>>,
    members: &'a Members<'a>,
    scopes: Scopes,
    errors: &'e mut Vec<VisibilityError>,
}

impl Checker<'_, '_> {
    fn module(&mut self, module: &Module) {
        // What platform selection drops is never compiled, and linking did
        // not look at it either.
        for decl in module.declarations.iter().filter(|d| keep(d.attributes()).unwrap_or(true)) {
            self.walk_declaration(decl);
        }
    }

    /// Check a reference not bound locally.
    fn check_reference(&mut self, name: &str, span: Span) {
        if self.own.contains(name) {
            return;
        }
        let Some(entries) = self.decls.get(name) else {
            // Linking leaves a reference to another file's private
            // declaration unrenamed.
            if let Some(d) = self.private.get(name).and_then(|p| p.iter().find(|d| d.file != self.file)) {
                let kind = VisibilityErrorKind::Private;
                self.errors.push(VisibilityError { file: self.file, span, name: name.to_string(), declared_in: d.file, kind });
                return;
            }
            // Not a top-level name: possibly a bare extension method in a method body.
            return self.visit_member(name, span);
        };
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
}

impl ScopeWalk for Checker<'_, '_> {
    fn scopes(&self) -> &Scopes {
        &self.scopes
    }

    fn scopes_mut(&mut self) -> &mut Scopes {
        &mut self.scopes
    }

    /// The members of `struct_name` visible in this file: its body's, plus
    /// methods of exported extensions and of this file's own.
    fn is_member(&self, struct_name: &str, name: &str) -> bool {
        self.members.of_struct.get(struct_name).is_some_and(|m| m.contains(name))
            || self.members.of_extensions.get(struct_name).is_some_and(|ext| {
                ext.iter().any(|&(m, file, exported)| m == name && (exported || file == self.file))
            })
    }

    /// `extend Foo<T>` introduces T as a generic parameter. A name the
    /// program declares as a type specializes instead (`extend
    /// Array<Point>`), and is checked like any reference, unless it is the
    /// struct's own parameter at that position (`extend Box<T>` of
    /// `struct Box<T>`), which always extends the generic base.
    fn extend_params(&self, target: &TypeName) -> HashSet<String> {
        let own_params = self.members.struct_params.get(target.name.as_str());
        target
            .generic_types
            .iter()
            .enumerate()
            .filter(|(i, t)| {
                t.generic_types.is_empty()
                    && (!self.types.contains(t.name.as_str())
                        || own_params.is_some_and(|p| p.get(*i).is_some_and(|p| *p == t.name.as_str())))
            })
            .map(|(_, t)| t)
            .map(|t| t.name.clone())
            .collect()
    }

    fn visit_symbol(&mut self, id: &String, span: Span) {
        if !self.is_local(id) {
            self.check_reference(id, span);
        }
    }

    fn visit_type_name(&mut self, ty: &TypeName) {
        let base = ty.name.trim_end_matches(|c| c == '*' || c == '[' || c == ']');
        // Only a generic parameter hides a type: a local or member named
        // `Point` is a value, as linking also treats it.
        if !self.scopes.is_type_local(base) {
            self.check_reference(base, ty.span);
        }
        self.walk_type_name(ty);
    }

    /// A member name (`x.name`, or bare `name` in a method body) that some
    /// extension declares: rejected unless a struct body or an extension
    /// visible to this file declares it too.
    fn visit_member(&mut self, name: &str, span: Span) {
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
    fn private_names_may_repeat_across_files() {
        // Linking mangles each file's private names apart.
        let errors = check(&[
            ("a.pep", "helper(): int { return 1; }\nvar counter = 1;\nextern int puts(char* s);\nexport f(): int { return 0; }"),
            ("b.pep", "helper(): int { return 2; }\nexport var counter = 2;\nextern int puts(char* s);\nexport f(): int { return 0; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
    }

    #[test]
    fn a_private_override_may_be_declared_in_only_one_file() {
        // An override keeps its generic's name, so two would collide.
        let errors = check(&[
            ("lib.pep", "export hash<T>(T value): u64 { return 0; }"),
            ("a.pep", "hash<int>(int v): u64 { return 1; }"),
            ("b.pep", "hash<int>(int v): u64 { return 2; }\nhash<u64>(u64 v): u64 { return 3; }"),
        ]);
        assert_eq!(
            errors,
            vec![
                "a.pep:1:1: override 'hash<int>' is also declared in b.pep; a generic may be overridden for the same types in only one file",
                "b.pep:1:1: override 'hash<int>' is also declared in a.pep; a generic may be overridden for the same types in only one file",
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
    fn private_generics_may_repeat_across_files() {
        // `hash<Point>` is a second generic base whose parameter is named
        // `Point`, not an override; private, it is mangled apart from the
        // exported `hash<T>` like any private name.
        let errors = check(&[
            ("a.pep", "pick<T>(v: T): int { return 1; }"),
            ("b.pep", "pick<U>(v: U): int { return 2; }\nexport hash<T>(v: T): u64 { return 0; }\nexport hash<int>(v: int): u64 { return 1; }"),
            ("c.pep", "struct Point { }\nhash<Point>(Point p): u64 { return 42; }\nhash<u64>(v: u64): u64 { return 3; }"),
        ]);
        assert!(errors.is_empty(), "{:?}", errors);
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
