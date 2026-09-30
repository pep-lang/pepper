//! `[Deprecated("message")]` and `[Deprecated("message", "replacement")]`:
//! every use of a declaration marked deprecated is reported as a warning at
//! the used name, with a note at the declaration, as clang reports
//! `[[deprecated]]`. When the attribute names a replacement, the warning
//! carries a fix that renames the use to it.
//!
//! Two checks share the work, because they need different information:
//!
//! - [`check_uses`] walks each file's linked AST (after `modules::link`, so
//!   every reference is spelled as the declaration it denotes) for the
//!   top-level names: free functions and externs, structs and their
//!   constructors, traits, type aliases, and module variables, as values,
//!   as types, and in `import [...]` lists. Type names and aliases are gone
//!   or lose their locations in the sema model, so this must run on the AST.
//! - `passes::check_deprecated_members` runs on the sema model once every
//!   type is known, for the members (fields and methods, extension methods
//!   included): which struct `x.m` names depends on the type of `x`.
//!
//! Neither reports a use inside a declaration that is itself deprecated
//! (the declaration or anything it contains), nor the declaration itself.
//! The attribute's form is validated by the builder (see
//! [`deprecation_of`]), so both checks skip a malformed one silently.

use crate::modules::{FileScope, ProgramFile};
use crate::passes::platform::keep;
use crate::scope_walk::{ScopeWalk, Scopes};
use pepper_parser::ast::{Attribute, Declaration, Expression, Literal, Span, TypeName};
use pepper_parser::diagnostic::{Diagnostic, FileId, Fix, Loc};
use std::collections::{HashMap, HashSet};

/// The attribute's name.
pub const DEPRECATED_ATTRIBUTE: &str = "Deprecated";

/// What a `[Deprecated(...)]` attribute says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Deprecation {
    /// Why, or what to do instead; shown after `'name' is deprecated: `.
    pub message: String,
    /// The name uses should be renamed to, from the optional second
    /// argument.
    pub replacement: Option<String>,
}

/// A malformed `[Deprecated]` attribute: the message, and the span to report
/// it at (the attribute, or the argument that is wrong).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AttributeError {
    pub span: Span,
    pub message: String,
}

/// Whether `attribute` is a `[Deprecated]` attribute, well-formed or not.
pub fn is_deprecation(attribute: &Attribute) -> bool {
    let callee = match &attribute.body {
        Expression::FunctionCall { function, .. } => function.as_ref(),
        other => other,
    };
    matches!(callee, Expression::SymbolRef { id, .. } if id == DEPRECATED_ATTRIBUTE)
}

/// The `[Deprecated(...)]` among `attributes`, if any, or what is wrong
/// with it.
pub fn deprecation_of(attributes: &[Attribute]) -> Result<Option<Deprecation>, AttributeError> {
    let mut found: Option<Deprecation> = None;
    for attribute in attributes.iter().filter(|a| is_deprecation(a)) {
        let error = |span: Span, message: &str| AttributeError { span, message: message.to_string() };
        if found.is_some() {
            return Err(error(attribute.span, "duplicate 'Deprecated' attribute"));
        }
        let expects_message = "'Deprecated' expects a message string: [Deprecated(\"message\")]";
        let Expression::FunctionCall { arguments, .. } = &attribute.body else {
            return Err(error(attribute.span, expects_message));
        };
        let string = |e: &Expression| match e {
            Expression::Literal { value: Literal::String(s), .. } => Some(s.clone()),
            _ => None,
        };
        let message = match arguments.first() {
            None => return Err(error(attribute.span, expects_message)),
            Some(first) => string(first).ok_or_else(|| error(first.span(), expects_message))?,
        };
        let replacement = match arguments.get(1) {
            None => None,
            Some(second) => {
                let expects = "'Deprecated' expects the replacement as a string: [Deprecated(\"message\", \"replacement\")]";
                let name = string(second).ok_or_else(|| error(second.span(), expects))?;
                let is_name = name.chars().next().is_some_and(|c| c.is_alphabetic() || c == '_')
                    && name.chars().all(|c| c.is_alphanumeric() || c == '_');
                if !is_name {
                    return Err(error(second.span(), &format!("the replacement '{name}' is not a name")));
                }
                Some(name)
            }
        };
        if let Some(extra) = arguments.get(2) {
            let message = format!("too many arguments to 'Deprecated': expected at most 2, have {}", arguments.len());
            return Err(error(extra.span(), &message));
        }
        found = Some(Deprecation { message, replacement });
    }
    Ok(found)
}

/// The deprecation `attributes` declare, ignoring a malformed one (the
/// builder reports it).
pub(crate) fn declared(attributes: &[Attribute]) -> Option<Deprecation> {
    deprecation_of(attributes).ok().flatten()
}

/// The warning for a use of `name` at `used` (whose source text is
/// `spelled`), declared at `declared` with `deprecation`. The fix renames
/// the use only when it is spelled as the declaration (not through an
/// import alias, say), since the replacement is the declaration's new name.
pub(crate) fn warning(name: &str, deprecation: &Deprecation, used: Loc, spelled: &str, declared: Loc) -> Diagnostic {
    let mut d = Diagnostic::deprecated_declaration(name, &deprecation.message, used)
        .with_note(format!("'{name}' declared here"), declared.known());
    if let Some(replacement) = &deprecation.replacement
        && spelled == name
    {
        d = d.with_fix(Fix::replace(format!("Replace '{name}' with '{replacement}'"), used, replacement.clone()));
    }
    d
}

/// A deprecated top-level declaration (or constructor).
struct Entry {
    deprecation: Deprecation,
    /// The declared name.
    at: Loc,
}

/// Uses of deprecated top-level declarations in every file of a linked
/// program, as warnings located in the file that uses them. `scopes` are
/// the files' [`FileScope`]s, in the same order.
pub fn check_uses(files: &[ProgramFile], scopes: &[FileScope]) -> Vec<Diagnostic> {
    let mut deprecated: HashMap<&str, Entry> = HashMap::new();
    let mut constructors: HashMap<&str, Entry> = HashMap::new();
    let mut members: HashMap<&str, HashSet<&str>> = HashMap::new();
    let mut types: HashSet<&str> = HashSet::new();
    for (i, file) in files.iter().enumerate() {
        let at = |span| Loc::new(FileId(i as u32), span);
        for d in file.module.declarations.iter().filter(|d| keep(d.attributes()).unwrap_or(true)) {
            match d {
                Declaration::Struct(s) => {
                    types.insert(&s.name);
                    let names = members.entry(&s.name).or_default();
                    names.extend(s.fields.iter().map(|f| f.name.as_str()));
                    names.extend(s.methods.iter().map(|m| m.name.as_str()));
                    // Overloaded constructors are checked per call, once
                    // resolved (`passes::check_deprecated_members`).
                    if let [c] = s.constructors.as_slice()
                        && let Some(deprecation) = declared(&c.attributes)
                    {
                        constructors.entry(&s.name).or_insert(Entry { deprecation, at: at(c.name_span) });
                    }
                }
                Declaration::Trait(t) => {
                    types.insert(&t.name);
                }
                Declaration::TypeAlias(t) => {
                    types.insert(&t.name);
                }
                Declaration::Extend(e) => {
                    members.entry(&e.target.name).or_default().extend(e.methods.iter().map(|m| m.name.as_str()));
                }
                _ => {}
            }
            if matches!(d, Declaration::Extend(_)) {
                continue;
            }
            if let Some(deprecation) = declared(d.attributes()) {
                deprecated.entry(d.name()).or_insert(Entry { deprecation, at: at(d.name_span()) });
            }
        }
    }
    let mut warnings = vec![];
    if deprecated.is_empty() && constructors.is_empty() {
        return warnings;
    }
    for (i, file) in files.iter().enumerate() {
        let mut walker = Uses {
            file: FileId(i as u32),
            text: &file.source,
            deprecated: &deprecated,
            constructors: &constructors,
            members: &members,
            types: &types,
            scopes: Scopes::default(),
            context: vec![],
            warnings: &mut warnings,
        };
        for decl in file.module.declarations.iter().filter(|d| keep(d.attributes()).unwrap_or(true)) {
            walker.walk_declaration(decl);
        }
        // `import [name] from m` names the declaration too; `export [name]
        // from m` only passes it on.
        let named = scopes.get(i).map(|s| &s.named);
        for imp in file.module.imports.iter().filter(|imp| !imp.reexport && keep(&imp.attributes).unwrap_or(true)) {
            for symbol in imp.symbols.iter().flatten() {
                if let Some(name) = named.and_then(|n| n.get(&symbol.span.start)) {
                    walker.report(name, symbol.name_span);
                }
            }
        }
    }
    warnings
}

/// The walk of one file for [`check_uses`].
struct Uses<'a, 'w> {
    file: FileId,
    text: &'a str,
    deprecated: &'a HashMap<&'a str, Entry>,
    constructors: &'a HashMap<&'a str, Entry>,
    /// Struct name -> the member names its body and extensions declare,
    /// which hide top-level names inside its methods.
    members: &'a HashMap<&'a str, HashSet<&'a str>>,
    /// Every type name declared at top level.
    types: &'a HashSet<&'a str>,
    scopes: Scopes,
    /// For each declaration being walked, whether it is deprecated.
    context: Vec<bool>,
    warnings: &'w mut Vec<Diagnostic>,
}

impl Uses<'_, '_> {
    /// A use of top-level `name` at `span` (a reference, possibly
    /// qualified, or a type name with its arguments).
    fn report(&mut self, name: &str, span: Span) {
        if let Some(entry) = self.deprecated.get(name) {
            self.report_entry(name, entry, span);
        }
    }

    fn report_entry(&mut self, name: &str, entry: &Entry, span: Span) {
        if self.context.iter().any(|&d| d) {
            return;
        }
        let token = name_token(self.text, span);
        let used = Loc::new(self.file, token);
        if used == entry.at {
            return;
        }
        let spelled = self.text.get(token.start..token.end).unwrap_or("");
        self.warnings.push(warning(name, &entry.deprecation, used, spelled, entry.at));
    }
}

/// The name token of a use at `span`: the last segment of a qualified name
/// (`sqrt` in `m.sqrt`), without generic arguments or array brackets.
fn name_token(text: &str, span: Span) -> Span {
    let written = text.get(span.start..span.end.min(text.len())).unwrap_or("");
    let end = written.find(|c: char| !(c.is_alphanumeric() || c == '_' || c == '.')).unwrap_or(written.len());
    let start = written[..end].rfind('.').map_or(0, |i| i + 1);
    Span { start: span.start + start, end: span.start + end }
}

impl ScopeWalk for Uses<'_, '_> {
    fn scopes(&self) -> &Scopes {
        &self.scopes
    }

    fn scopes_mut(&mut self) -> &mut Scopes {
        &mut self.scopes
    }

    fn is_member(&self, struct_name: &str, name: &str) -> bool {
        self.members.get(struct_name).is_some_and(|m| m.contains(name))
    }

    fn extend_params(&self, target: &TypeName) -> HashSet<String> {
        target
            .generic_types
            .iter()
            .filter(|t| t.generic_types.is_empty() && !self.types.contains(t.name.as_str()))
            .map(|t| t.name.clone())
            .collect()
    }

    fn enter_declaration(&mut self, attributes: &[Attribute]) {
        self.context.push(declared(attributes).is_some());
    }

    fn exit_declaration(&mut self) {
        self.context.pop();
    }

    fn visit_symbol(&mut self, id: &String, span: Span) {
        if !self.is_local(id) {
            self.report(id, span);
        }
    }

    fn visit_type_name(&mut self, ty: &TypeName) {
        let base = ty.name.trim_end_matches(['*', '[', ']']);
        if !self.scopes.is_type_local(base) {
            self.report(base, ty.span);
        }
        self.walk_type_name(ty);
    }

    /// A construction `S(...)` also uses the constructor, which may be
    /// deprecated on its own; a deprecated struct is reported once, as the
    /// struct.
    fn visit_expression(&mut self, expr: &Expression) {
        if let Expression::FunctionCall { function, .. } = expr {
            let callee = match function.as_ref() {
                Expression::SymbolRef { id, span } if !self.is_local(id) => Some((id.as_str(), *span)),
                Expression::TypeLiteral(t) if !self.scopes.is_type_local(&t.name) => Some((t.name.as_str(), t.span)),
                _ => None,
            };
            if let Some((name, span)) = callee
                && !self.deprecated.contains_key(name)
                && let Some(entry) = self.constructors.get(name)
            {
                self.report_entry(name, entry, span);
            }
        }
        self.walk_expression(expr);
    }
}
