//! Module linking: binds each file's imports and re-exports, then rewrites
//! every imported spelling (`m.sqrt`, an alias `power`, a qualified type
//! `m.Point`) to the name of the declaration it denotes. Runs on the per-file
//! ASTs before they are merged into one sema `Module`, which still has a
//! single namespace: after linking, every reference is spelled the way the
//! rest of the compiler resolves it.
//!
//! A file's *exports* are its `export` declarations plus its `export x as y`
//! re-exports. A module's exports are those of its `module.pep`. What a file
//! can name from elsewhere:
//!
//! - the exports of prelude files (the runtime, forced imports), unqualified,
//!   with no import;
//! - `import m` / `import m as q` / `import "f" as q`: the target's exports as
//!   `m.x` / `q.x`;
//! - `import "f"`: the file's exports, unqualified;
//! - `import [x, y as z] from m`: those exports, as `x` and `z`.
//!
//! Locally bound names (parameters, locals, generic parameters, struct
//! members) shadow imports; a name the file declares itself may not also be
//! imported. The visibility check then rejects references to exports of
//! non-prelude files that the referencing file did not import.

use crate::passes::platform::keep;
use pepper_parser::ast::{
    Block, Declaration, Expression, FunctionDecl, GenericParam, Module, Span, Statement, TypeName,
};
use std::collections::{HashMap, HashSet};

/// One parsed file of a program, with its imports resolved to other files.
pub struct ProgramFile {
    /// Display name used in diagnostics (usually the path).
    pub name: String,
    pub source: String,
    pub module: Module,
    /// A runtime or forced-import file: its exports are visible to every file
    /// without an import.
    pub prelude: bool,
    /// A file a prelude file reaches through local imports (another file of
    /// a forced module): like the prelude, its exports may repeat the
    /// runtime's, but they are visible only through the module's own exports.
    pub prelude_part: bool,
    /// For each of `module.imports`, the index of the file it names, or
    /// `None` when it did not resolve (reported by the loader).
    pub imports: Vec<Option<usize>>,
    /// For each of `module.imports`: a local import that resolved to a
    /// module folder (`import "vec"` for `vec/module.pep`), for diagnostics.
    pub folder_imports: Vec<bool>,
}

/// What linking learned about one file, for the visibility check.
#[derive(Debug, Clone, Default)]
pub struct FileScope {
    /// The references linking rewrote, as span start -> declaration name:
    /// each was reached through an import, so it is visible whether or not
    /// the declaration is exported, since `export x as y` may publish a
    /// private `x`. The declaration's own name, written elsewhere in the
    /// file, gets no such pass.
    pub imported: HashMap<usize, String>,
}

/// A module-linking error, anchored in one file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModuleError {
    pub file: usize,
    pub span: Span,
    pub message: String,
    /// An import that names no module or file on the search paths. Fatal to
    /// a compile; an editor, which cannot see `-I`, may show it as a warning.
    pub unresolved: bool,
}

impl ModuleError {
    /// `<file>:<line>:<col>: <message>`
    pub fn render(&self, names: &[&str], sources: &[&str]) -> String {
        let p = self.span.start_position(sources[self.file]);
        format!("{}:{}:{}: {}", names[self.file], p.line + 1, p.col + 1, self.message)
    }
}

/// A name imported unqualified: the declaration it denotes, or `None` when
/// two imports bind it to different declarations.
type Unqualified = HashMap<String, Option<String>>;

/// One file's import bindings.
#[derive(Default)]
struct Bindings {
    unqualified: Unqualified,
    /// qualifier -> file whose exports it names.
    qualified: HashMap<String, usize>,
    /// Qualifiers and listed names of imports that did not resolve: already
    /// reported at the import, so their uses are not reported again.
    unresolved: HashSet<String>,
    /// A whole-file import did not resolve: any unknown name may be one of
    /// its exports, so re-exports of unknown names are not reported again.
    unresolved_whole_file: bool,
}

/// The names of a file's exported concrete overrides.
fn exported_overrides(module: &Module) -> impl Iterator<Item = &str> {
    named_decls(module).filter_map(|d| match d {
        Declaration::Function(f) if f.is_exported && is_override(f) => Some(f.name.as_str()),
        _ => None,
    })
}

/// The name a concrete override named `name` takes, when it overrides a
/// generic reached under another name: none when the file declares the
/// generic itself, else through an import, then the prelude
/// (`choose<int>` after `import [pick as choose]` becomes `pick<int>`).
/// Linking renames the declaration and its export by this one rule.
fn override_rename(
    name: &str,
    own: &HashSet<String>,
    bindings: &Bindings,
    prelude: &HashMap<String, String>,
) -> Option<String> {
    if own.contains(name) {
        return None;
    }
    match resolve_imported(name, bindings, prelude) {
        Resolution::Declared(c, _) if c != name => Some(c),
        _ => None,
    }
}

/// A concrete override of a generic function (`hash<int>` of `hash<T>`).
fn is_override(f: &FunctionDecl) -> bool {
    crate::type_name::is_override(f.generic_params.iter().map(|g| g.name.as_str()))
}

/// The named top-level declarations that survive platform selection.
fn named_decls(module: &Module) -> impl Iterator<Item = &Declaration> {
    module.declarations.iter().filter(|d| !matches!(d, Declaration::Extend(_)) && keep(d.attributes()).unwrap_or(true))
}

/// Bind every file's imports and re-exports and rewrite imported spellings
/// in place. Returns each file's scope and every linking error.
pub fn link(files: &mut [ProgramFile]) -> (Vec<FileScope>, Vec<ModuleError>) {
    let n = files.len();
    let names: Vec<String> = files.iter().map(|f| f.name.clone()).collect();
    // A file's own names. A concrete override (`f<int>` of a generic `f<T>`)
    // declares no new name: it may sit next to an import of the generic.
    let own: Vec<HashSet<String>> = files
        .iter()
        .map(|f| {
            named_decls(&f.module)
                .filter(|d| !matches!(d, Declaration::Function(func) if is_override(func)))
                .map(|d| d.name().to_string())
                .collect()
        })
        .collect();

    // Every type the program declares: in `extend Box<X>`, a declared `X`
    // specializes rather than introducing a parameter.
    let types: HashSet<String> = files
        .iter()
        .flat_map(|f| named_decls(&f.module))
        .filter(|d| matches!(d, Declaration::Struct(_) | Declaration::TypeAlias(_) | Declaration::Trait(_)))
        .map(|d| d.name().to_string())
        .collect();

    // Exports: direct `export` declarations first, then re-exports resolved to
    // a fixpoint, since a re-export may name another file's re-export (and
    // files of one module may import each other). Without re-exports, one
    // binding pass is the whole job.
    let direct: Vec<HashMap<String, String>> = files
        .iter()
        .map(|f| {
            named_decls(&f.module)
                .filter(|d| d.is_exported())
                .map(|d| (d.name().to_string(), d.name().to_string()))
                .collect()
        })
        .collect();
    // Files whose exports depend on their bindings: re-exports, and exported
    // concrete overrides, which take the name of the generic they override
    // (`export choose<int>` after `import [pick as choose]` exports `pick`).
    let override_counts: Vec<usize> = files.iter().map(|f| exported_overrides(&f.module).count()).collect();
    let reexporting: Vec<usize> =
        (0..n).filter(|&i| !files[i].module.exports.is_empty() || override_counts[i] > 0).collect();
    let is_reexporting: Vec<bool> =
        (0..n).map(|i| !files[i].module.exports.is_empty() || override_counts[i] > 0).collect();
    let mut exports = direct.clone();
    let prelude_reexports = reexporting.iter().any(|&i| files[i].prelude);
    let mut prelude = prelude_exports(files, &exports);
    // Per re-exporting file, from the round that last computed them: its
    // bindings with the errors binding reported, and the errors resolving
    // its re-exports reported. A file is rebound only when a file it imports
    // changed its exports, and re-resolved only then or when the prelude did.
    let mut bound: HashMap<usize, (Bindings, Vec<ModuleError>)> = HashMap::new();
    let mut resolve_errors: HashMap<usize, Vec<ModuleError>> = HashMap::new();
    // Files whose exports changed in the last round; `None` before the first.
    let mut changed: Option<HashSet<usize>> = None;
    let mut prelude_changed = false;
    let mut rounds = 0;
    // Each round settles at least one more re-export of a converging chain,
    // however the chain bounces between files.
    let max_rounds: usize = reexporting
        .iter()
        .map(|&i| files[i].module.exports.len() + override_counts[i])
        .sum::<usize>()
        + 1;
    let mut errors: Vec<ModuleError> = vec![];
    while !reexporting.is_empty() {
        let mut next: Vec<(usize, HashMap<String, String>)> = vec![];
        for &i in &reexporting {
            let inputs_changed =
                changed.as_ref().is_none_or(|c| files[i].imports.iter().flatten().any(|t| c.contains(t)));
            if !inputs_changed && !prelude_changed {
                continue;
            }
            if inputs_changed {
                let mut errs = vec![];
                let b = bind_imports(i, files, &exports, &own[i], &mut errs);
                bound.insert(i, (b, errs));
            }
            let mut errs = vec![];
            let table = resolve_reexports(i, files, &direct[i], &own[i], &bound[&i].0, &exports, &prelude, &mut errs);
            resolve_errors.insert(i, errs);
            if table != exports[i] {
                next.push((i, table));
            }
        }
        rounds += 1;
        if next.is_empty() {
            break;
        }
        if rounds > max_rounds {
            // Settling re-exports only ever adds links, unless an ambiguity
            // takes one away again: two files re-exporting through each
            // other can then flip forever. Report the re-exports still
            // changing, and link against the latest round.
            for (i, table) in &next {
                for ea in &files[*i].module.exports {
                    let name = ea.exported_name();
                    if table.get(name) != exports[*i].get(name) {
                        errors.push(ModuleError {
                            unresolved: false,
                            file: *i,
                            span: ea.span,
                            message: format!(
                                "cannot re-export '{}': it depends on itself through an import that is ambiguous",
                                name
                            ),
                        });
                    }
                }
            }
            for (i, table) in next {
                exports[i] = table;
            }
            // Bindings from before this last change are stale.
            bound.clear();
            resolve_errors.clear();
            prelude = prelude_exports(files, &exports);
            break;
        }
        prelude_changed = prelude_reexports && next.iter().any(|(i, _)| files[*i].prelude);
        changed = Some(next.iter().map(|(i, _)| *i).collect());
        for (i, table) in next {
            exports[i] = table;
        }
        if prelude_changed {
            prelude = prelude_exports(files, &exports);
        }
    }
    // A prelude re-export may not take the name of another prelude file's
    // export (`export quiet_assert as assert` beside the runtime's `assert`):
    // runtime files reach their own `assert` through their imports, so the
    // alias would replace it only for some callers. Replacing a runtime
    // export means declaring it under its own name, which wins everywhere.
    for i in (0..n).filter(|&i| files[i].prelude) {
        for ea in files[i].module.exports.iter().filter(|ea| keep(&ea.attributes).unwrap_or(true)) {
            let name = ea.exported_name();
            let renamed = exports[i].get(name).is_some_and(|c| c != name);
            if renamed && (0..n).any(|j| j != i && files[j].prelude && direct[j].contains_key(name)) {
                errors.push(ModuleError {
                    unresolved: false,
                    file: i,
                    span: ea.span,
                    message: format!(
                        "a forced import cannot replace '{}' with an alias, since the runtime's own files would still call theirs; declare 'export {}(...)' under that name instead",
                        name, name
                    ),
                });
            }
        }
    }

    // Every file bound against the settled exports: a re-exporting file's
    // last computation still holds, since nothing changed after it.
    let mut bindings: Vec<Bindings> = Vec::with_capacity(n);
    for i in 0..n {
        if let Some((b, errs)) = bound.remove(&i) {
            errors.extend(errs);
            errors.extend(resolve_errors.remove(&i).unwrap_or_default());
            bindings.push(b);
            continue;
        }
        let b = bind_imports(i, files, &exports, &own[i], &mut errors);
        if is_reexporting[i] {
            resolve_reexports(i, files, &direct[i], &own[i], &b, &exports, &prelude, &mut errors);
        }
        bindings.push(b);
    }

    // Struct members by struct name: inside a method, a member shadows an
    // import of the same name. Body members always count; an extension's
    // methods only where the extension is visible (its own file, or
    // exported). Its target may be spelled through an import (`extend m.S`,
    // an alias), so it is keyed by the declaration it names.
    // Only what platform selection keeps is a member at all.
    let mut members = Members::default();
    let kept_method = |m: &&FunctionDecl| keep(&m.attributes).unwrap_or(true);
    for (i, f) in files.iter().enumerate() {
        for d in f.module.declarations.iter().filter(|d| keep(d.attributes()).unwrap_or(true)) {
            match d {
                Declaration::Struct(s) => members.of_body.entry(s.name.clone()).or_default().extend(
                    s.fields.iter().map(|x| x.name.clone()).chain(s.methods.iter().filter(kept_method).map(|m| m.name.clone())),
                ),
                Declaration::Extend(e) => {
                    let target = resolve_top_level(&e.target.name, &own[i], &bindings[i], &exports, &prelude)
                        .unwrap_or_else(|_| e.target.name.clone());
                    members
                        .of_extensions
                        .entry(target)
                        .or_default()
                        .extend(e.methods.iter().filter(kept_method).map(|m| (m.name.clone(), i, e.is_exported)))
                }
                _ => {}
            }
        }
    }

    let mut scopes = vec![];
    for i in 0..n {
        let mut rewriter = Rewriter {
            file: i,
            own: &own[i],
            bindings: &bindings[i],
            exports: &exports,
            prelude: &prelude,
            types: &types,
            names: &names,
            members: &members,
            scopes: vec![],
            imported: HashMap::new(),
            current_struct: None,
            errors: &mut errors,
        };
        rewriter.module(&mut files[i].module);
        let imported = std::mem::take(&mut rewriter.imported);
        scopes.push(FileScope { imported });
    }
    errors.sort_by_key(|e| (e.file, e.span.start));
    errors.dedup();
    (scopes, errors)
}

/// File `i`'s exports: its `export` declarations (`direct`) plus its
/// `export x as y` re-exports, resolved against `bindings`.
#[allow(clippy::too_many_arguments)]
fn resolve_reexports(
    i: usize,
    files: &[ProgramFile],
    direct: &HashMap<String, String>,
    own: &HashSet<String>,
    bindings: &Bindings,
    exports: &[HashMap<String, String>],
    prelude: &HashMap<String, String>,
    errors: &mut Vec<ModuleError>,
) -> HashMap<String, String> {
    let mut out = direct.clone();
    // An exported override is exported under its generic's name, as linking
    // renames it: an alias of the generic resolves to that name.
    for name in exported_overrides(&files[i].module) {
        if let Some(c) = override_rename(name, own, bindings, prelude) {
            out.remove(name);
            out.insert(c.clone(), c);
        }
    }
    for ea in &files[i].module.exports {
        match keep(&ea.attributes) {
            Ok(true) => {}
            Ok(false) => continue,
            Err(message) => {
                errors.push(ModuleError { unresolved: false, file: i, span: ea.span, message });
                continue;
            }
        }
        let first = ea.symbol.split('.').next().unwrap_or(&ea.symbol);
        if bindings.unresolved.contains(first) && !own.contains(first) {
            continue;
        }
        match resolve_top_level(&ea.symbol, own, bindings, exports, prelude) {
            Ok(canonical) => {
                let name = ea.exported_name().to_string();
                match out.get(&name) {
                    Some(existing) if *existing != canonical => errors.push(ModuleError {
                        unresolved: false,
                        file: i,
                        span: ea.span,
                        message: format!("'{}' is exported twice, as '{}' and '{}'", name, existing, canonical),
                    }),
                    _ => {
                        out.insert(name, canonical);
                    }
                }
            }
            Err(_) if bindings.unresolved_whole_file && !ea.symbol.contains('.') => {}
            Err(message) => errors.push(ModuleError { unresolved: false, file: i, span: ea.symbol_span, message }),
        }
    }
    out
}

/// Every prelude file's exports, re-exports included: visible everywhere
/// without an import. Name -> the declaration it denotes.
fn prelude_exports(files: &[ProgramFile], exports: &[HashMap<String, String>]) -> HashMap<String, String> {
    // Forced imports load before the runtime, and the first definition of a
    // name wins, as it does when the program is merged.
    let mut out = HashMap::new();
    for (f, e) in files.iter().zip(exports) {
        if f.prelude {
            for (k, v) in e {
                out.entry(k.clone()).or_insert_with(|| v.clone());
            }
        }
    }
    out
}

/// Resolve a re-export's symbol (`x` or `q.x`) in file scope.
fn resolve_top_level(
    symbol: &str,
    own: &HashSet<String>,
    bindings: &Bindings,
    exports: &[HashMap<String, String>],
    prelude: &HashMap<String, String>,
) -> Result<String, String> {
    if let Some((q, name)) = symbol.split_once('.') {
        let Some(&target) = bindings.qualified.get(q) else {
            return Err(format!("'{}' is not an imported module", q));
        };
        return exports[target].get(name).cloned().ok_or_else(|| format!("'{}' is not exported by '{}'", name, q));
    }
    if own.contains(symbol) {
        return Ok(symbol.to_string());
    }
    match resolve_imported(symbol, bindings, prelude) {
        Resolution::Declared(c, _) => Ok(c),
        Resolution::Ambiguous => Err(ambiguous(symbol)),
        Resolution::Unknown => Err(format!("cannot export '{}': no such symbol in this file or its imports", symbol)),
    }
}

/// What an unqualified name that is not the file's own (or local) denotes.
enum Resolution {
    /// A declaration, by name: bound by an import, or a prelude export.
    Declared(String, Source),
    /// Two whole-file imports bind it to different declarations.
    Ambiguous,
    Unknown,
}

/// Where a resolved unqualified name came from.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Source {
    Import,
    Prelude,
}

/// Resolve an unqualified name through the file's imports, then the prelude.
fn resolve_imported(name: &str, bindings: &Bindings, prelude: &HashMap<String, String>) -> Resolution {
    match bindings.unqualified.get(name) {
        Some(Some(c)) => Resolution::Declared(c.clone(), Source::Import),
        Some(None) => Resolution::Ambiguous,
        None => prelude.get(name).map_or(Resolution::Unknown, |c| Resolution::Declared(c.clone(), Source::Prelude)),
    }
}

fn ambiguous(name: &str) -> String {
    format!("'{}' is ambiguous: more than one import provides it", name)
}

/// Bind file `i`'s imports against the current export tables. Whole-file
/// imports bind first, so a symbol named in an `import [...]` list always
/// wins over a whole-file import of the same name.
fn bind_imports(
    i: usize,
    files: &[ProgramFile],
    exports: &[HashMap<String, String>],
    own: &HashSet<String>,
    errors: &mut Vec<ModuleError>,
) -> Bindings {
    let mut b = Bindings::default();
    // An import platform selection drops binds nothing, and is no error.
    let kept = || {
        files[i].module.imports.iter().zip(&files[i].imports).filter(|(imp, _)| keep(&imp.attributes).unwrap_or(true))
    };
    // Whether each import resolved to a module folder, for diagnostics.
    let folder: HashMap<usize, bool> =
        files[i].module.imports.iter().zip(&files[i].folder_imports).map(|(imp, f)| (imp.span.start, *f)).collect();
    let imports = || kept().filter_map(|(imp, t)| t.map(|t| (imp, t)));
    for (imp, _) in kept().filter(|(_, t)| t.is_none()) {
        if let Some(q) = imp.qualifier() {
            b.unresolved.insert(q.to_string());
        }
        for s in imp.symbols.iter().flatten() {
            b.unresolved.insert(s.local_name().to_string());
        }
        if imp.symbols.is_none() && imp.qualifier().is_none() {
            b.unresolved_whole_file = true;
        }
    }

    // Qualifiers and whole-file imports. Two whole-file imports that bind a
    // name to different declarations make it ambiguous, reported on use.
    for (imp, target) in imports().filter(|(imp, _)| imp.symbols.is_none()) {
        if let Some(q) = imp.qualifier() {
            if own.contains(q) {
                errors.push(ModuleError {
                    unresolved: false,
                    file: i,
                    span: imp.span,
                    message: format!("'{}' is imported but also declared in this file", q),
                });
            } else if b.qualified.get(q).is_some_and(|&t| t != target) {
                errors.push(ModuleError {
                    unresolved: false,
                    file: i,
                    span: imp.span,
                    message: format!("'{}' is already imported", q),
                });
            } else {
                b.qualified.insert(q.to_string(), target);
            }
            continue;
        }
        // The merge is order-independent: equal keeps, different -> None.
        for (name, c) in &exports[target] {
            if own.contains(name) {
                continue;
            }
            match b.unqualified.get(name) {
                Some(Some(existing)) if existing != c => {
                    b.unqualified.insert(name.clone(), None);
                }
                Some(_) => {}
                None => {
                    b.unqualified.insert(name.clone(), Some(c.clone()));
                }
            }
        }
    }

    // Named symbols replace whatever a whole-file import bound.
    let mut explicit: HashMap<String, String> = HashMap::new();
    for (imp, target) in imports() {
        let Some(symbols) = &imp.symbols else { continue };
        for s in symbols {
            let Some(c) = exports[target].get(&s.name) else {
                errors.push(ModuleError {
                    unresolved: false,
                    file: i,
                    span: s.name_span,
                    message: format!("'{}' is not exported by {}", s.name, imp.describe_as(folder.get(&imp.span.start).copied().unwrap_or(false))),
                });
                continue;
            };
            let local = s.local_name();
            if own.contains(local) {
                errors.push(ModuleError {
                    unresolved: false,
                    file: i,
                    span: s.span,
                    message: format!("'{}' is imported but also declared in this file", local),
                });
                continue;
            }
            match explicit.get(local) {
                Some(existing) if existing != c => errors.push(ModuleError {
                    unresolved: false,
                    file: i,
                    span: s.span,
                    message: format!("'{}' is already imported as a different symbol", local),
                }),
                _ => {
                    explicit.insert(local.to_string(), c.clone());
                    b.unqualified.insert(local.to_string(), Some(c.clone()));
                }
            }
        }
    }

    // `import m;` with `import [m] from n;` would make `m.x` and a bare `m`
    // name different things.
    for (imp, _) in kept() {
        if let Some(q) = imp.qualifier()
            && b.unqualified.contains_key(q)
        {
            errors.push(ModuleError {
                unresolved: false,
                file: i,
                span: imp.span,
                message: format!("'{}' is imported both as a module and as a symbol", q),
            });
        }
    }
    b
}

/// One level of names bound inside a declaration.
enum Scope {
    /// Parameters and locals: they hide imports used as values.
    Values(HashSet<String>),
    /// Generic parameters: they hide imports as values and as types.
    Generics(HashSet<String>),
    /// The members of a struct visible in this file, looked up in
    /// [`Members`] rather than copied.
    Members(String),
}

/// Struct member names, for shadowing inside method bodies.
#[derive(Default)]
struct Members {
    /// struct -> names declared in its body (fields and methods).
    of_body: HashMap<String, HashSet<String>>,
    /// struct -> (method, declaring file, exported) from extensions.
    of_extensions: HashMap<String, Vec<(String, usize, bool)>>,
}

struct Rewriter<'a, 'e> {
    file: usize,
    own: &'a HashSet<String>,
    bindings: &'a Bindings,
    exports: &'a [HashMap<String, String>],
    /// Prelude exports: visible without an import.
    prelude: &'a HashMap<String, String>,
    /// Every type name declared at top level, in any file.
    types: &'a HashSet<String>,
    /// Every file's display name, for diagnostics.
    names: &'a [String],
    members: &'a Members,
    /// Locally bound names, innermost last.
    scopes: Vec<Scope>,
    imported: HashMap<usize, String>,
    /// The struct whose body or extension is being walked.
    current_struct: Option<String>,
    errors: &'e mut Vec<ModuleError>,
}

impl Rewriter<'_, '_> {
    fn module(&mut self, module: &mut Module) {
        for decl in &mut module.declarations {
            // A declaration this platform drops is never compiled, so what it
            // names from other modules need not exist here.
            if !keep(decl.attributes()).unwrap_or(true) {
                continue;
            }
            // A concrete override of an imported generic (`choose<int>` after
            // `import [pick as choose]`) takes the generic's name, as its
            // call sites do.
            if let Declaration::Function(f) = decl
                && is_override(f)
                && let Some(c) = override_rename(&f.name, self.own, self.bindings, self.prelude)
            {
                f.name = c;
            }
            self.declaration(decl);
        }
    }

    /// `name` is bound locally where a value is expected: a parameter,
    /// local, generic parameter, or visible member.
    fn is_local(&self, name: &str) -> bool {
        self.scopes.iter().any(|s| match s {
            Scope::Values(names) | Scope::Generics(names) => names.contains(name),
            Scope::Members(st) => self.is_visible_member(st, name),
        })
    }

    /// `name` is bound locally where a type is expected (a type position,
    /// or a generic call such as `f<int>()`): only generic parameters. A
    /// local or member is a value, and sema never binds a type or a generic
    /// call to it.
    fn is_type_local(&self, name: &str) -> bool {
        self.scopes.iter().any(|s| matches!(s, Scope::Generics(names) if names.contains(name)))
    }

    /// Hidden where it is used: as a value (`value`), or as a type.
    fn is_hidden(&self, name: &str, value: bool) -> bool {
        if value { self.is_local(name) } else { self.is_type_local(name) }
    }

    fn is_visible_member(&self, struct_name: &str, name: &str) -> bool {
        self.members.of_body.get(struct_name).is_some_and(|m| m.contains(name))
            || self.members.of_extensions.get(struct_name).is_some_and(|ext| {
                ext.iter().any(|(m, file, exported)| m == name && (*exported || *file == self.file))
            })
    }

    fn declaration(&mut self, decl: &mut Declaration) {
        match decl {
            Declaration::Variable(v) => {
                self.type_name(&mut v.type_name);
                if let Some(e) = &mut v.default_value {
                    self.expression(e);
                }
                self.bind(&v.name);
            }
            Declaration::Function(f) => self.function(f),
            Declaration::Struct(s) => {
                let outer = self.current_struct.replace(s.name.clone());
                self.push_generics(&mut s.generic_params);
                self.bind_members(&s.name.clone());
                for field in &mut s.fields {
                    self.type_name(&mut field.type_name);
                    if let Some(e) = &mut field.default_value {
                        self.expression(e);
                    }
                }
                // Platform selection never drops a constructor or destructor,
                // whatever its attributes, so both are always walked.
                if let Some(c) = &mut s.constructor {
                    self.function_body(c);
                }
                if let Some(d) = &mut s.destructor {
                    self.block_body(d);
                }
                for m in &mut s.methods {
                    self.function(m);
                }
                self.current_struct = outer;
                self.scopes.pop();
                self.scopes.pop();
            }
            Declaration::Trait(t) => {
                self.push_generics(&mut t.generic_params);
                for m in &mut t.methods {
                    self.function(m);
                }
                self.scopes.pop();
            }
            Declaration::Extend(e) => {
                // `extend Box<T>` introduces T; `extend Array<Pt>`, with `Pt`
                // imported or declared by any file, specializes and is
                // rewritten (or checked) like any reference.
                let params = e
                    .target
                    .generic_types
                    .iter()
                    .filter(|t| {
                        t.generic_types.is_empty()
                            && !self.own.contains(&t.name)
                            && !self.types.contains(&t.name)
                            && !self.bindings.qualified.contains_key(t.name.split('.').next().unwrap_or(""))
                            && matches!(resolve_imported(&t.name, self.bindings, self.prelude), Resolution::Unknown)
                    })
                    .map(|t| t.name.clone())
                    .collect();
                self.scopes.push(Scope::Generics(params));
                self.type_name(&mut e.target);
                for t in &mut e.traits {
                    self.type_name(t);
                }
                self.bind_members(&e.target.name.clone());
                let outer = self.current_struct.replace(e.target.name.clone());
                for m in &mut e.methods {
                    self.function(m);
                }
                self.current_struct = outer;
                self.scopes.pop();
                self.scopes.pop();
            }
            Declaration::TypeAlias(t) => {
                self.push_generics(&mut t.generic_params);
                self.type_name(&mut t.target);
                self.scopes.pop();
            }
        }
    }

    /// A function, unless platform selection drops it.
    fn function(&mut self, f: &mut FunctionDecl) {
        if keep(&f.attributes).unwrap_or(true) {
            self.function_body(f);
        }
    }

    fn function_body(&mut self, f: &mut FunctionDecl) {
        self.push_generics(&mut f.generic_params);
        self.type_name(&mut f.return_type);
        self.scopes.push(Scope::Values(HashSet::new()));
        for p in &mut f.parameters {
            self.type_name(&mut p.type_name);
            if let Some(e) = &mut p.default_value {
                self.expression(e);
            }
            self.bind(&p.name);
        }
        if let Some(body) = &mut f.body {
            self.block(body);
        }
        self.scopes.pop();
        self.scopes.pop();
    }

    /// A block, unless platform selection drops it.
    fn block(&mut self, block: &mut Block) {
        if keep(&block.attributes).unwrap_or(true) {
            self.block_body(block);
        }
    }

    fn block_body(&mut self, block: &mut Block) {
        self.scopes.push(Scope::Values(HashSet::new()));
        for stmt in &mut block.statements {
            self.statement(stmt);
        }
        self.scopes.pop();
    }

    fn statement(&mut self, stmt: &mut Statement) {
        match stmt {
            Statement::Expression(e) => self.expression(e),
            Statement::Block(b) => self.block(b),
            Statement::Declaration(d) => self.declaration(d),
            Statement::Branch(b) => {
                self.expression(&mut b.condition);
                self.block(&mut b.if_block);
                if let Some(e) = &mut b.else_block {
                    self.block(e);
                }
            }
            Statement::While(w) => {
                self.expression(&mut w.condition);
                self.block(&mut w.block);
            }
            Statement::For(f) => {
                self.expression(&mut f.iterable);
                self.scopes.push(Scope::Values(HashSet::new()));
                self.type_name(&mut f.binding.type_name);
                self.bind(&f.binding.name);
                self.block(&mut f.block);
                self.scopes.pop();
            }
            Statement::Return(r) => self.expression(&mut r.expr),
            Statement::LoopBreak(_) => {}
        }
    }

    /// The qualifier `q` names an imported module here (not shadowed).
    fn qualifier(&self, q: &str) -> Option<usize> {
        if self.own.contains(q) || self.is_local(q) {
            return None;
        }
        self.bindings.qualified.get(q).copied()
    }

    /// `q.name` for an imported qualifier `q`: the declaration it denotes.
    /// `value`: a reference in an expression (`q.f()`), not a type or a
    /// generic construction (`q.f<int>()`), which sema never binds to a method.
    fn qualified(&mut self, target: usize, q: &str, name: &str, span: Span, value: bool) -> Option<String> {
        let Some(c) = self.exports[target].get(name).cloned() else {
            self.errors.push(ModuleError {
                unresolved: false,
                file: self.file,
                span,
                message: format!("'{}' is not exported by '{}' ({})", name, q, self.names[target]),
            });
            return None;
        };
        self.denote(&format!("{}.{}", q, name), c, span, value, true)
    }

    /// An unqualified name: rewritten when an import (or a prelude
    /// re-export) binds it.
    fn unqualified(&mut self, name: &str, span: Span, value: bool) -> Option<String> {
        if self.own.contains(name) || self.is_hidden(name, value) {
            return None;
        }
        // A prelude name is recorded like an import even when it needs no
        // rewriting: a forced module's `export step` makes `step`, declared
        // in a file of that module, visible everywhere.
        match resolve_imported(name, self.bindings, self.prelude) {
            // Only an import can be captured by a hidden method: a prelude
            // name (`hash`) is not an import.
            Resolution::Declared(c, source) => self.denote(name, c, span, value, source == Source::Import),
            Resolution::Ambiguous => {
                self.errors.push(ModuleError { unresolved: false, file: self.file, span, message: ambiguous(name) });
                None
            }
            Resolution::Unknown => None,
        }
    }

    /// `spelled` denotes the declaration `c`: record the import, unless a
    /// local of that name would capture the rewritten reference.
    ///
    /// `value`: used where a value is expected, so a local, parameter, or
    /// member of the declaration's name would capture it; in a type position
    /// or a generic call only a generic parameter would. `imported`: reached
    /// through an import, not the prelude. An imported name used as a value
    /// is also captured by a method of the enclosing struct from an
    /// extension this file cannot see, since sema sees every extension, even
    /// when the spelling is unchanged (`import [area2] from geo`, then
    /// `area2()` in a method).
    fn denote(&mut self, spelled: &str, c: String, span: Span, value: bool, imported: bool) -> Option<String> {
        if value && imported && !self.is_local(&c) && self.is_any_extension_method(&c) {
            self.errors.push(ModuleError {
                unresolved: false,
                file: self.file,
                span,
                message: format!(
                    "'{}' refers to the imported '{}', but an extension in another file gives this struct a method '{}' that would be called instead; rename one",
                    spelled, c, c
                ),
            });
            return None;
        }
        if spelled != c && self.is_hidden(&c, value) {
            self.errors.push(ModuleError {
                unresolved: false,
                file: self.file,
                span,
                message: format!(
                    "'{}' refers to '{}', which a local, parameter, or member named '{}' hides here; rename it",
                    spelled, c, c
                ),
            });
            return None;
        }
        self.imported.insert(span.start, c.clone());
        Some(c)
    }

    fn expression(&mut self, expr: &mut Expression) {
        if let Expression::MemberAccess { lhs, name, span, .. } = expr
            && let Expression::SymbolRef { id, .. } = lhs.as_ref()
            && let Some(target) = self.qualifier(id)
        {
            let q = id.clone();
            let (name, span) = (name.clone(), *span);
            // The rewritten reference keeps the whole `q.name` span, which the
            // visibility check looks the import up by.
            if let Some(c) = self.qualified(target, &q, &name, span, true) {
                *expr = Expression::SymbolRef { id: c, span };
            }
            return;
        }
        match expr {
            Expression::Literal { .. } => {}
            Expression::SymbolRef { id, span } => {
                if let Some(c) = self.unqualified(id, *span, true) {
                    *id = c;
                }
            }
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
            Expression::MemberAccess { lhs, .. } => self.expression(lhs),
            Expression::FunctionCall { function, arguments, .. } => {
                self.expression(function);
                for a in arguments {
                    self.expression(a);
                }
            }
        }
    }

    fn type_name(&mut self, ty: &mut TypeName) {
        let base_len = ty.name.trim_end_matches(|c| c == '*' || c == '[' || c == ']').len();
        let (base, suffix) = ty.name.split_at(base_len);
        let (base, suffix) = (base.to_string(), suffix.to_string());
        let resolved = if let Some((q, name)) = base.split_once('.') {
            // Only a module can qualify a type, so a value named `q` (a local,
            // a field) does not hide the import here.
            match self.bindings.qualified.get(q).copied() {
                Some(target) => self.qualified(target, q, name, ty.span, false),
                None if self.bindings.unresolved.contains(q) => None,
                None => {
                    self.errors.push(ModuleError {
                        unresolved: false,
                        file: self.file,
                        span: ty.span,
                        message: format!("'{}' is not an imported module", q),
                    });
                    None
                }
            }
        } else {
            self.unqualified(&base, ty.span, false)
        };
        if let Some(c) = resolved {
            ty.name = c + &suffix;
        }
        for g in &mut ty.generic_types {
            self.type_name(g);
        }
    }

    fn bind(&mut self, name: &str) {
        if let Some(Scope::Values(names) | Scope::Generics(names)) = self.scopes.last_mut() {
            names.insert(name.to_string());
        }
    }

    fn push_generics(&mut self, params: &mut [GenericParam]) {
        self.scopes.push(Scope::Generics(params.iter().map(|p| p.name.clone()).collect()));
        for p in params {
            if let Some(d) = &mut p.default {
                self.type_name(d);
            }
        }
    }

    /// `name` is a method some extension (visible here or not) adds to the
    /// struct whose methods are being walked. Sema sees every extension, so
    /// a rewritten reference of that name would bind to the method.
    fn is_any_extension_method(&self, name: &str) -> bool {
        self.current_struct
            .as_ref()
            .and_then(|s| self.members.of_extensions.get(s))
            .is_some_and(|ext| ext.iter().any(|(m, _, _)| m == name))
    }

    /// Bind the members of `struct_name` visible in this file.
    fn bind_members(&mut self, struct_name: &str) {
        self.scopes.push(Scope::Members(struct_name.to_string()));
    }
}
