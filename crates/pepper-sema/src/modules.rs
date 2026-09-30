//! Module linking: binds each file's imports and re-exports, then rewrites
//! every imported spelling (`m.sqrt`, an alias `power`, a qualified type
//! `m.Point`) to the name of the declaration it denotes. Runs on the per-file
//! ASTs before they are merged into one sema `Module`, which has a single
//! namespace: after linking, every reference is spelled the way the rest of
//! the compiler resolves it. So linking also gives each file's private
//! declarations, and the references to them, names no other file can spell
//! (see [`pepper_parser::namespace`] and [`own_names`]).
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
use crate::scope_walk::{ScopeWalkMut, Scopes};
use pepper_parser::ast::{Declaration, Expression, FunctionDecl, Module, Span, TypeName};
use pepper_parser::diagnostic::{Diagnostic, FileId, Loc};
use pepper_parser::namespace;
use std::collections::{HashMap, HashSet};

/// One parsed file of a program, with its imports resolved to other files.
pub struct ProgramFile {
    /// Display name used in diagnostics (usually the path).
    pub name: String,
    /// The namespace its private names are mangled with (see
    /// [`pepper_parser::namespace`]), unique in the program.
    pub namespace: String,
    /// The folder of the module the file belongs to, if any.
    pub module_root: Option<std::path::PathBuf>,
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
    /// The names the file's `import [...]` lists and `export x as y`
    /// re-exports bind, as span start (of the list entry, or of the
    /// re-exported symbol) -> declaration name, for the editor to follow.
    pub named: HashMap<usize, String>,
    /// The other files whose exported extensions this file may use: prelude
    /// files and the files of a forced module, the files it imports, and
    /// every file of a module it imports.
    pub extensions: HashSet<usize>,
    /// The declarations the file's imports bind, by the names they take in
    /// the merged program, whether or not the file spells them.
    pub bound: HashSet<String>,
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
    /// A second place in the same file that explains the error, with its
    /// message ("also exported here").
    pub note: Option<(Span, String)>,
}

impl ModuleError {
    /// The error as a diagnostic, located in `files[self.file]` of the
    /// program it came from.
    pub fn to_diagnostic(&self) -> Diagnostic {
        let file = FileId(self.file as u32);
        let diagnostic = Diagnostic::error(self.message.clone()).at(Loc::new(file, self.span));
        match &self.note {
            Some((span, message)) => diagnostic.with_note(message.clone(), Some(Loc::new(file, *span))),
            None => diagnostic,
        }
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

/// A function's parameter types as written, with its generic parameters
/// named by position: `describe<T>(T)` and `describe<Point>(Point)` have one
/// shape.
fn parameter_shape(function: &FunctionDecl) -> Vec<String> {
    fn spell(ty: &TypeName, generics: &[&str]) -> String {
        let name = match generics.iter().position(|g| *g == ty.name) {
            Some(i) => format!("${}", i),
            None => ty.name.clone(),
        };
        let args: Vec<String> = ty.generic_types.iter().map(|t| spell(t, generics)).collect();
        if args.is_empty() { name } else { format!("{}<{}>", name, args.join(",")) }
    }
    let generics: Vec<&str> = function.generic_params.iter().map(|g| g.name.as_str()).collect();
    function.parameters.iter().map(|p| spell(&p.type_name, &generics)).collect()
}

/// The names of a file's exported concrete overrides.
fn exported_overrides<'m>(module: &'m Module, file: usize, overrides: &Overrides) -> impl Iterator<Item = &'m str> {
    named_decls(module).filter_map(move |d| match d {
        Declaration::Function(f) if f.is_exported && overrides.is(f, file) => Some(f.name.as_str()),
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
    own: &Own,
    bindings: &Bindings,
    prelude: &HashMap<String, String>,
) -> Option<String> {
    if own.contains_key(name) {
        return None;
    }
    match resolve_imported(name, bindings, prelude) {
        Resolution::Declared(c, _) if c != name => Some(c),
        _ => None,
    }
}

/// Which generic functions are concrete overrides (`hash<int>`,
/// `hash<Point>` of `hash<T>`): every generic parameter names a primitive,
/// `String`, or a type the declaring file can see, and either all are
/// primitives or `String`, or a generic base of that name and parameter
/// count exists (one with a parameter that names no type its file can see).
/// Otherwise a struct's name is just a generic parameter's name. Linking
/// marks the parameters of what it decides is an override
/// ([`GenericParam::is_argument`](pepper_parser::ast::GenericParam)), and
/// sema and the visibility check follow that mark.
pub(crate) struct Overrides {
    /// Per file, the names that denote a type there (struct, alias, trait).
    types: Vec<HashSet<String>>,
    /// Per file, the names that denote a struct or type alias there.
    value_types: Vec<HashSet<String>>,
    /// Per file, the generic bases its imports and the prelude give it.
    imported_bases: Vec<Names>,
    /// Per file, the generic bases it can call, by every name it has for
    /// them: parameter counts.
    bases: Vec<Names>,
}

/// Names a file declares, exports, or can see, each with the parameter
/// counts of the generics it names (empty for a type).
type Names = HashMap<String, HashSet<usize>>;

/// Add `name` with `counts` to `to`; whether that changed it.
fn add_names(to: &mut Names, name: &str, counts: &HashSet<usize>) -> bool {
    let new = !to.contains_key(name);
    let entry = to.entry(name.to_string()).or_default();
    let before = entry.len();
    entry.extend(counts);
    new || before != entry.len()
}

/// Per file, the names it can see: its `own`, the prelude's exports, and
/// what its imports bind (a whole-file import binds every export of its
/// target, an import list the names it lists, under their local names). A
/// file exports its `exported` names and whatever `export x as y` publishes
/// of what it sees; a module's exports are its `module.pep`'s. Iterated
/// until re-exports settle.
fn visible_names(files: &[ProgramFile], own: &[Names], exported: &[Names], shadow: &[HashSet<String>]) -> Vec<Names> {
    let n = files.len();
    let mut exports: Vec<Names> = exported.to_vec();
    let mut visible: Vec<Names> = own.to_vec();
    loop {
        let mut changed = false;
        let prelude: Vec<usize> = (0..n).filter(|&j| files[j].prelude).collect();
        for i in 0..n {
            let mut seen = own[i].clone();
            // The other prelude files' exports: a file's own exports reach
            // it only as its own names.
            for &j in prelude.iter().filter(|&&j| j != i) {
                for (k, v) in exports[j].clone() {
                    if !shadow[i].contains(&k) {
                        add_names(&mut seen, &k, &v);
                    }
                }
            }
            // qualifier -> the file whose exports it names.
            let mut qualified: HashMap<&str, usize> = HashMap::new();
            let imports = files[i].module.imports.iter().zip(&files[i].imports);
            for (imp, target) in imports.filter(|(imp, _)| keep(&imp.attributes).unwrap_or(true)) {
                let Some(t) = *target else { continue };
                // `export ... from` publishes names and binds none here.
                if imp.reexport {
                    let published: Vec<(String, HashSet<usize>)> = match &imp.symbols {
                        Some(symbols) => symbols
                            .iter()
                            .filter_map(|s| exports[t].get(&s.name).map(|v| (s.local_name().to_string(), v.clone())))
                            .collect(),
                        None => exports[t].iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
                    };
                    for (k, v) in published {
                        changed |= add_names(&mut exports[i], &k, &v);
                    }
                    continue;
                }
                if imp.symbols.is_none()
                    && let Some(q) = imp.qualifier()
                {
                    qualified.insert(q, t);
                }
                match &imp.symbols {
                    Some(symbols) => {
                        for s in symbols {
                            if let Some(v) = exports[t].get(&s.name)
                                && !shadow[i].contains(s.local_name())
                            {
                                add_names(&mut seen, s.local_name(), &v.clone());
                            }
                        }
                    }
                    None if imp.qualifier().is_none() => {
                        for (k, v) in exports[t].clone() {
                            if !shadow[i].contains(&k) {
                                add_names(&mut seen, &k, &v);
                            }
                        }
                    }
                    None => {}
                }
            }
            for ea in files[i].module.exports.iter().filter(|ea| keep(&ea.attributes).unwrap_or(true)) {
                // `export q.x` names the export `x` of the file `q` names.
                let found = match ea.symbol.split_once('.') {
                    Some((q, x)) => qualified.get(q).and_then(|&t| exports[t].get(x)).cloned(),
                    None => seen.get(&ea.symbol).cloned(),
                };
                if let Some(v) = found {
                    changed |= add_names(&mut exports[i], ea.exported_name(), &v);
                }
            }
            if seen != visible[i] {
                visible[i] = seen;
                changed = true;
            }
        }
        if !changed {
            return visible;
        }
    }
}

impl Overrides {
    /// The rule over the files of a program, before linking.
    fn of(files: &[ProgramFile]) -> Overrides {
        // Per file, the visible names of the declarations `kind` accepts.
        let visible = |kind: fn(&Declaration) -> bool| -> Vec<HashSet<String>> {
            let names_of = |f: &ProgramFile, exported_only: bool| -> Names {
                named_decls(&f.module)
                    .filter(|d| kind(d) && (!exported_only || d.is_exported()))
                    .map(|d| (d.name().to_string(), HashSet::new()))
                    .collect()
            };
            let own: Vec<Names> = files.iter().map(|f| names_of(f, false)).collect();
            let exported: Vec<Names> = files.iter().map(|f| names_of(f, true)).collect();
            let own_names: Vec<HashSet<String>> = own.iter().map(|o| o.keys().cloned().collect()).collect();
            visible_names(files, &own, &exported, &own_names).into_iter().map(|v| v.into_keys().collect()).collect()
        };
        // An override's type argument may name any type, and is an error
        // unless it names a struct; a generic base is a function with a
        // parameter that names no struct or alias its file can see (a trait
        // name there is a type parameter's name, as before traits were
        // types).
        let types = visible(|d| matches!(d, Declaration::Struct(_) | Declaration::TypeAlias(_) | Declaration::Trait(_)));
        let value_types = visible(|d| matches!(d, Declaration::Struct(_) | Declaration::TypeAlias(_)));
        let bases_of = |i: usize, exported_only: bool| -> Names {
            let mut out = Names::new();
            for d in named_decls(&files[i].module) {
                if let Declaration::Function(f) = d
                    && (!exported_only || f.is_exported)
                    && f.generic_params.iter().any(|p| !p.bounds.is_empty() || !names_type(&value_types[i], &p.name))
                {
                    out.entry(f.name.clone()).or_default().insert(f.generic_params.len());
                }
            }
            out
        };
        let own: Vec<Names> = (0..files.len()).map(|i| bases_of(i, false)).collect();
        let exported: Vec<Names> = (0..files.len()).map(|i| bases_of(i, true)).collect();
        // A file's own declaration of a name hides what its imports bind
        // under that name, as linking resolves it: a plain function, or a
        // generic base (but not an override, which names the import).
        let plain: Vec<HashSet<String>> = files
            .iter()
            .map(|f| {
                named_decls(&f.module)
                    .filter(|d| !matches!(d, Declaration::Function(func) if !func.generic_params.is_empty()))
                    .map(|d| d.name().to_string())
                    .collect()
            })
            .collect();
        let shadow: Vec<HashSet<String>> =
            plain.iter().zip(&own).map(|(p, o)| p.iter().cloned().chain(o.keys().cloned()).collect()).collect();
        let bases = visible_names(files, &own, &exported, &shadow);
        let none: Vec<Names> = vec![Names::new(); files.len()];
        let imported_bases = visible_names(files, &none, &exported, &plain);
        Overrides { types, value_types, bases, imported_bases }
    }

    /// A function named `name` (possibly mangled) with these generic
    /// parameters, declared in `file`, is a concrete override.
    fn is_named(&self, name: &str, params: &[&str], file: usize) -> bool {
        if crate::type_name::is_override(params.iter().copied()) {
            return true;
        }
        if params.is_empty() || !params.iter().all(|p| names_type(&self.types[file], p)) {
            return false;
        }
        // A parameter named like a trait makes the function a base itself;
        // it is an override (with an error at the trait) only of a base
        // the file imports.
        let name = namespace::demangle_name(name);
        let bases = if params.iter().all(|p| names_type(&self.value_types[file], p)) {
            &self.bases[file]
        } else {
            &self.imported_bases[file]
        };
        bases.get(name).is_some_and(|n| n.contains(&params.len()))
    }

    /// `f`, declared in `file`, is a concrete override. A constrained name
    /// (`describe<T: Shape>`) is always a parameter.
    fn is(&self, f: &FunctionDecl, file: usize) -> bool {
        if f.generic_params.iter().any(|g| !g.bounds.is_empty()) {
            return false;
        }
        let params: Vec<&str> = f.generic_params.iter().map(|g| g.name.as_str()).collect();
        self.is_named(&f.name, &params, file)
    }
}

/// `param` names a primitive, `String`, or one of `types`.
fn names_type(types: &HashSet<String>, param: &str) -> bool {
    crate::type_name::is_concrete_override(std::iter::once(param)) || types.contains(param)
}

/// The named top-level declarations that survive platform selection.
fn named_decls(module: &Module) -> impl Iterator<Item = &Declaration> {
    module.declarations.iter().filter(|d| !matches!(d, Declaration::Extend(_)) && keep(d.attributes()).unwrap_or(true))
}

/// A file's own names, each mapped to the name its declaration takes in the
/// merged program: a private one mangled with the file's namespace (see
/// [`pepper_parser::namespace`]), any other its own.
type Own = HashMap<String, String>;

/// Whether `d` keeps its name in the merged program: an export, whose
/// importers spell it that way; an extern, which names a C symbol; or a
/// concrete override (`hash<int>`), which takes its generic's name.
fn keeps_name(d: &Declaration, file: usize, overrides: &Overrides) -> bool {
    d.is_exported() || matches!(d, Declaration::Function(f) if f.external || overrides.is(f, file))
}

/// Every file's [`Own`] names. A concrete override (`f<int>` of a generic
/// `f<T>`) declares no new name: it may sit next to an import of the
/// generic.
///
/// The root file's private names are mangled only where another file keeps
/// the same name, which would collide with them: otherwise its entry point
/// (`main`) and its other functions keep the names a host or test harness
/// looks them up by. Every other file's private names are mangled.
fn own_names(files: &[ProgramFile], overrides: &Overrides) -> Vec<Own> {
    let kept: HashSet<&str> = files
        .iter()
        .enumerate()
        .skip(1)
        .flat_map(|(i, f)| named_decls(&f.module).map(move |d| (i, d)))
        .filter(|&(i, d)| keeps_name(d, i, overrides))
        .map(|(_, d)| d)
        .map(|d| d.name())
        .collect();
    files
        .iter()
        .enumerate()
        .map(|(i, f)| {
            // One name, one declaration in the merged program: when a file
            // declares a name more than once (an exported generic and a
            // private override of it for a struct), all take the public
            // name. A private override (`describe<int>`) makes none public.
            let kept_here: HashSet<&str> = named_decls(&f.module)
                .filter(|d| d.is_exported() || matches!(d, Declaration::Function(func) if func.external))
                .map(|d| d.name())
                .collect();
            named_decls(&f.module)
                .filter(|d| !matches!(d, Declaration::Function(func) if overrides.is(func, i)))
                .map(|d| {
                    let name = d.name();
                    let mangled = !kept_here.contains(name) && (i > 0 || kept.contains(name));
                    (name.to_string(), if mangled { namespace::mangle(name, &f.namespace) } else { name.to_string() })
                })
                .collect()
        })
        .collect()
}

/// Bind every file's imports and re-exports and rewrite imported spellings
/// in place. Returns each file's scope and every linking error.
pub fn link(files: &mut [ProgramFile]) -> (Vec<FileScope>, Vec<ModuleError>) {
    let n = files.len();
    let names: Vec<String> = files.iter().map(|f| f.name.clone()).collect();
    let overrides = Overrides::of(files);
    let own = own_names(files, &overrides);

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
    let override_counts: Vec<usize> = files.iter().enumerate().map(|(i, f)| exported_overrides(&f.module, i, &overrides).count()).collect();
    // `export ... from` lines count once per name they may publish: a
    // whole-file one once per export of any file.
    let reexport_counts: Vec<usize> = files
        .iter()
        .map(|f| {
            f.module.imports.iter().filter(|imp| imp.reexport).map(|imp| imp.symbols.as_ref().map_or(1, |s| s.len())).sum()
        })
        .collect();
    let is_reexporting: Vec<bool> = (0..n)
        .map(|i| !files[i].module.exports.is_empty() || override_counts[i] > 0 || reexport_counts[i] > 0)
        .collect();
    let reexporting: Vec<usize> = (0..n).filter(|&i| is_reexporting[i]).collect();
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
        .map(|&i| files[i].module.exports.len() + override_counts[i] + reexport_counts[i])
        .sum::<usize>()
        * if reexport_counts.iter().any(|&c| c > 0) { direct.iter().map(|d| d.len()).sum::<usize>().max(1) } else { 1 }
        + 1;
    let mut errors: Vec<ModuleError> = vec![];
    // Two functions of one name in one file overload each other, unless a
    // generic and another function have the same parameters: the generic
    // is then usually a meant override whose type argument the file cannot
    // see (`describe<Point>(Point)` with no `Point` here, beside
    // `describe<T>(T)`), or of a generic the file's own declaration hides.
    for (i, f) in files.iter().enumerate() {
        let functions: Vec<&FunctionDecl> = named_decls(&f.module)
            .filter_map(|d| match d {
                Declaration::Function(func) if !overrides.is(func, i) => Some(func),
                _ => None,
            })
            .collect();
        for (k, func) in functions.iter().enumerate() {
            let earlier = || functions[..k].iter().filter(|g| g.name == func.name && parameter_shape(g) == parameter_shape(func));
            // A generic whose parameters all name structs this file sees
            // meant to override a generic its own declarations hide.
            let names_types = !func.generic_params.is_empty()
                && func.generic_params.iter().all(|p| overrides.value_types[i].contains(&p.name));
            let clashes = earlier().next().is_some()
                && (!func.generic_params.is_empty() || earlier().any(|g| !g.generic_params.is_empty()));
            if clashes || (names_types && functions.iter().any(|g| g.name == func.name && !std::ptr::eq(*g, *func))) {
                errors.push(ModuleError { note: None,
                    unresolved: false,
                    file: i,
                    span: func.name_span,
                    message: format!(
                        "redefinition of generic '{}'; to override it for a type, each type argument must name a struct this file can see",
                        func.name
                    ),
                });
            }
        }
    }
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
            let table = resolve_reexports(i, files, &direct[i], &own[i], &overrides, &bound[&i].0, &exports, &prelude, &mut errs);
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
                        errors.push(ModuleError { note: None,
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
                errors.push(ModuleError { note: None,
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
            resolve_reexports(i, files, &direct[i], &own[i], &overrides, &b, &exports, &prelude, &mut errors);
        }
        bindings.push(b);
    }

    // Struct members by struct name: inside a method, a member shadows an
    // import of the same name. Body members always count; an extension's
    // methods only where the extension is visible (its own file, or
    // exported by a file this one imports, or by the prelude). Its target may be spelled through an import (`extend m.S`,
    // an alias), so it is keyed by the declaration it names.
    // Only what platform selection keeps is a member at all.
    let mut members = Members::default();
    let kept_method = |m: &&FunctionDecl| keep(&m.attributes).unwrap_or(true);
    let resolve = |i: usize, name: &str| {
        resolve_top_level(name, &own[i], &bindings[i], &exports, &prelude).unwrap_or_else(|_| name.to_string())
    };
    // An extension may name its target or its traits through a type alias
    // (`extend C` after `type C = S`).
    for (i, f) in files.iter().enumerate() {
        for d in f.module.declarations.iter().filter(|d| keep(d.attributes()).unwrap_or(true)) {
            if let Declaration::TypeAlias(t) = d {
                members.aliases.insert(resolve(i, &t.name), resolve(i, &t.target.name));
            }
        }
    }
    for (i, f) in files.iter().enumerate() {
        for d in f.module.declarations.iter().filter(|d| keep(d.attributes()).unwrap_or(true)) {
            match d {
                Declaration::Struct(s) => members.of_body.entry(own[i].get(&s.name).unwrap_or(&s.name).clone()).or_default().extend(
                    s.fields.iter().map(|x| x.name.clone()).chain(s.methods.iter().filter(kept_method).map(|m| m.name.clone())),
                ),
                Declaration::Extend(e) => {
                    let target = members.resolve(&resolve(i, &e.target.name)).to_string();
                    for t in &e.traits {
                        let t = members.resolve(&resolve(i, &t.name)).to_string();
                        members.adopters.entry(t).or_default().push(target.clone());
                    }
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

    let extensions = visible_extensions(files);
    // Every struct by the name it takes in the merged program.
    let linked_structs: HashSet<String> = files
        .iter()
        .enumerate()
        .flat_map(|(i, f)| {
            let own = &own[i];
            named_decls(&f.module).filter_map(move |d| match d {
                Declaration::Struct(s) => Some(own.get(&s.name).unwrap_or(&s.name).clone()),
                _ => None,
            })
        })
        .collect();
    let mut scopes = vec![];
    for i in 0..n {
        let named = named_bindings(i, files, &own[i], &bindings[i], &exports, &prelude);
        let mut rewriter = Rewriter {
            overrides: &overrides,
            override_decls: HashSet::new(),
            structs: &linked_structs,
            file: i,
            own: &own[i],
            bindings: &bindings[i],
            exports: &exports,
            prelude: &prelude,
            types: &types,
            names: &names,
            members: &members,
            extensions: &extensions[i],
            scopes: Scopes::default(),
            imported: HashMap::new(),
            errors: &mut errors,
        };
        rewriter.module(&mut files[i].module);
        let imported = std::mem::take(&mut rewriter.imported);
        let bound = bindings[i]
            .unqualified
            .values()
            .flatten()
            .cloned()
            .chain(bindings[i].qualified.values().flat_map(|&t| exports[t].values().cloned()))
            .collect();
        scopes.push(FileScope { imported, named, extensions: extensions[i].clone(), bound });
    }
    errors.sort_by_key(|e| (e.file, e.span.start));
    errors.dedup();
    (scopes, errors)
}

/// Per file, the other files whose exported extensions it may use (see
/// [`FileScope::extensions`]). An import of a module (`import m`, or a
/// local import of a module folder) reaches every file of that module; an
/// import of a file reaches that file.
fn visible_extensions(files: &[ProgramFile]) -> Vec<HashSet<usize>> {
    let everywhere: HashSet<usize> = (0..files.len()).filter(|&j| files[j].prelude || files[j].prelude_part).collect();
    files
        .iter()
        .map(|f| {
            let mut out = everywhere.clone();
            let kept = f.module.imports.iter().zip(&f.imports).zip(&f.folder_imports);
            for ((imp, target), folder) in kept.filter(|((imp, _), _)| !imp.reexport && keep(&imp.attributes).unwrap_or(true)) {
                let Some(t) = *target else { continue };
                out.insert(t);
                if (!imp.is_local || *folder) && let Some(root) = &files[t].module_root {
                    out.extend((0..files.len()).filter(|&j| files[j].module_root.as_ref() == Some(root)));
                }
            }
            out
        })
        .collect()
}

/// File `i`'s import-list entries and re-exports that denote a declaration,
/// for [`FileScope::named`]. The others were reported while binding.
fn named_bindings(
    i: usize,
    files: &[ProgramFile],
    own: &Own,
    bindings: &Bindings,
    exports: &[HashMap<String, String>],
    prelude: &HashMap<String, String>,
) -> HashMap<usize, String> {
    let mut named = HashMap::new();
    for (imp, target) in files[i].module.imports.iter().zip(&files[i].imports) {
        let (Some(symbols), Some(target)) = (&imp.symbols, target) else { continue };
        for s in symbols {
            if let Some(c) = exports[*target].get(&s.name) {
                named.insert(s.span.start, c.clone());
            }
        }
    }
    for ea in &files[i].module.exports {
        if let Ok(c) = resolve_top_level(&ea.symbol, own, bindings, exports, prelude) {
            named.insert(ea.symbol_span.start, c);
        }
    }
    named
}

/// File `i`'s exports: its `export` declarations (`direct`) plus its
/// `export x as y` re-exports, resolved against `bindings`.
#[allow(clippy::too_many_arguments)]
fn resolve_reexports(
    i: usize,
    files: &[ProgramFile],
    direct: &HashMap<String, String>,
    own: &Own,
    overrides: &Overrides,
    bindings: &Bindings,
    exports: &[HashMap<String, String>],
    prelude: &HashMap<String, String>,
    errors: &mut Vec<ModuleError>,
) -> HashMap<String, String> {
    let mut out = direct.clone();
    // An exported override is exported under its generic's name, as linking
    // renames it: an alias of the generic resolves to that name.
    for name in exported_overrides(&files[i].module, i, overrides) {
        if let Some(c) = override_rename(name, own, bindings, prelude) {
            out.remove(name);
            out.insert(c.clone(), c);
        }
    }
    // Where each name `out` publishes came from, for "also exported here".
    let mut origins: HashMap<String, Span> = named_decls(&files[i].module)
        .filter(|d| d.is_exported())
        .map(|d| (d.name().to_string(), d.name_span()))
        .collect();
    let mut publish = |out: &mut HashMap<String, String>, name: &str, canonical: &str, span: Span, errors: &mut Vec<ModuleError>| {
        match out.get(name) {
            Some(existing) if existing != canonical => errors.push(ModuleError {
                note: origins.get(name).map(|&at| (at, "also exported here".to_string())),
                unresolved: false,
                file: i,
                span,
                message: format!("'{}' is exported twice by {}", name, describe_file(&files[i])),
            }),
            Some(_) => {}
            None => {
                out.insert(name.to_string(), canonical.to_string());
                origins.insert(name.to_string(), span);
            }
        }
    };
    // `export * from source` and `export [...] from source`, in order. The
    // loader reported the ones that did not resolve.
    let reexports = files[i].module.imports.iter().zip(&files[i].imports).zip(&files[i].folder_imports);
    for ((imp, target), folder) in reexports.filter(|((imp, _), _)| imp.reexport) {
        let (Ok(true), Some(t)) = (keep(&imp.attributes), *target) else { continue };
        match &imp.symbols {
            None => {
                let mut names: Vec<(&String, &String)> = exports[t].iter().collect();
                names.sort();
                for (name, canonical) in names {
                    publish(&mut out, name, canonical, imp.span, errors);
                }
            }
            Some(symbols) => {
                for s in symbols {
                    match exports[t].get(&s.name) {
                        Some(canonical) => publish(&mut out, s.local_name(), canonical, s.span, errors),
                        None => errors.push(ModuleError {
                            note: None,
                            unresolved: false,
                            file: i,
                            span: s.name_span,
                            message: format!("'{}' is not exported by {}", s.name, imp.describe_as(*folder)),
                        }),
                    }
                }
            }
        }
    }
    for ea in &files[i].module.exports {
        match keep(&ea.attributes) {
            Ok(true) => {}
            Ok(false) => continue,
            Err(message) => {
                errors.push(ModuleError { note: None, unresolved: false, file: i, span: ea.span, message });
                continue;
            }
        }
        let first = ea.symbol.split('.').next().unwrap_or(&ea.symbol);
        if bindings.unresolved.contains(first) && !own.contains_key(first) {
            continue;
        }
        match resolve_top_level(&ea.symbol, own, bindings, exports, prelude) {
            Ok(canonical) => {
                let name = ea.exported_name().to_string();
                match out.get(&name) {
                    Some(existing) if *existing != canonical => errors.push(ModuleError { note: None,
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
            Err(message) => errors.push(ModuleError { note: None, unresolved: false, file: i, span: ea.symbol_span, message }),
        }
    }
    out
}

/// How diagnostics name the file whose exports are meant: `module
/// 'geometry'` for a module's `module.pep`, else `"shapes.pep"`.
fn describe_file(file: &ProgramFile) -> String {
    let path = std::path::Path::new(&file.name);
    let stem = |p: &std::path::Path| p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    match &file.module_root {
        Some(root) if path.file_name().is_some_and(|n| n == "module.pep") => format!("module '{}'", stem(root)),
        _ => format!("\"{}\"", stem(path)),
    }
}

/// Give the named declaration `decl` the name `name`.
fn rename(decl: &mut Declaration, name: String) {
    match decl {
        Declaration::Function(f) => f.name = name,
        Declaration::Struct(s) => s.name = name,
        Declaration::TypeAlias(t) => t.name = name,
        Declaration::Trait(t) => t.name = name,
        Declaration::Variable(v) => v.name = name,
        Declaration::Extend(_) => {}
    }
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
    own: &Own,
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
    if let Some(c) = own.get(symbol) {
        return Ok(c.clone());
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
    own: &Own,
    errors: &mut Vec<ModuleError>,
) -> Bindings {
    let mut b = Bindings::default();
    // An import platform selection drops binds nothing, and is no error.
    let kept = || {
        files[i]
            .module
            .imports
            .iter()
            .zip(&files[i].imports)
            .filter(|(imp, _)| !imp.reexport && keep(&imp.attributes).unwrap_or(true))
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
            if own.contains_key(q) {
                errors.push(ModuleError { note: None,
                    unresolved: false,
                    file: i,
                    span: imp.span,
                    message: format!("'{}' is imported but also declared in this file", q),
                });
            } else if b.qualified.get(q).is_some_and(|&t| t != target) {
                errors.push(ModuleError { note: None,
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
            if own.contains_key(name) {
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
                errors.push(ModuleError { note: None,
                    unresolved: false,
                    file: i,
                    span: s.name_span,
                    message: format!("'{}' is not exported by {}", s.name, imp.describe_as(folder.get(&imp.span.start).copied().unwrap_or(false))),
                });
                continue;
            };
            let local = s.local_name();
            if own.contains_key(local) {
                errors.push(ModuleError { note: None,
                    unresolved: false,
                    file: i,
                    span: s.span,
                    message: format!("'{}' is imported but also declared in this file", local),
                });
                continue;
            }
            match explicit.get(local) {
                Some(existing) if existing != c => errors.push(ModuleError { note: None,
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
            errors.push(ModuleError { note: None,
                unresolved: false,
                file: i,
                span: imp.span,
                message: format!("'{}' is imported both as a module and as a symbol", q),
            });
        }
    }
    b
}

/// Struct member names, for shadowing inside method bodies.
#[derive(Default)]
struct Members {
    /// struct -> names declared in its body (fields and methods).
    of_body: HashMap<String, HashSet<String>>,
    /// struct -> (method, declaring file, exported) from extensions.
    of_extensions: HashMap<String, Vec<(String, usize, bool)>>,
    /// trait -> the structs extensions make conform to it.
    adopters: HashMap<String, Vec<String>>,
    /// type alias -> the type it names (its base name, for a generic one).
    aliases: HashMap<String, String>,
}

impl Members {
    /// The type `name` denotes, through any aliases.
    fn resolve<'s>(&'s self, mut name: &'s str) -> &'s str {
        // An alias cycle is reported elsewhere; stop rather than loop.
        for _ in 0..=self.aliases.len() {
            match self.aliases.get(name) {
                Some(target) => name = target,
                None => break,
            }
        }
        name
    }
}

struct Rewriter<'a, 'e> {
    file: usize,
    own: &'a Own,
    bindings: &'a Bindings,
    exports: &'a [HashMap<String, String>],
    /// Prelude exports: visible without an import.
    prelude: &'a HashMap<String, String>,
    /// Every type name declared at top level, in any file.
    types: &'a HashSet<String>,
    /// Every file's display name, for diagnostics.
    names: &'a [String],
    members: &'a Members,
    overrides: &'a Overrides,
    /// The name span starts of this file's top-level concrete overrides,
    /// decided before `module` renames them.
    override_decls: HashSet<usize>,
    /// Every struct of the program, by its linked (possibly mangled) name.
    structs: &'a HashSet<String>,
    /// Other files whose exported extensions this file may use.
    extensions: &'a HashSet<usize>,
    scopes: Scopes,
    imported: HashMap<usize, String>,
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
                && self.overrides.is(f, self.file)
            {
                // Decided by the name the file spells it with.
                self.override_decls.insert(f.name_span.start);
                if let Some(c) = override_rename(&f.name, self.own, self.bindings, self.prelude) {
                    f.name = c;
                } else if let Some(c) = self.own.get(&f.name) {
                    // An override of this file's own generic takes its name.
                    f.name = c.clone();
                }
            } else if let Some(c) = self.own.get(decl.name()) {
                // A private declaration takes its mangled name.
                let c = c.clone();
                rename(decl, c);
            }
            self.walk_declaration(decl);
        }
    }

    /// Hidden where it is used: as a value (`value`), or as a type.
    fn is_hidden(&self, name: &str, value: bool) -> bool {
        if value { self.is_local(name) } else { self.scopes.is_type_local(name) }
    }

    /// The qualifier `q` names an imported module here (not shadowed).
    fn qualifier(&self, q: &str) -> Option<usize> {
        if self.own.contains_key(q) || self.is_local(q) {
            return None;
        }
        self.bindings.qualified.get(q).copied()
    }

    /// `q.name` for an imported qualifier `q`: the declaration it denotes.
    /// `value`: a reference in an expression (`q.f()`), not a type or a
    /// generic construction (`q.f<int>()`), which sema never binds to a method.
    fn qualified(&mut self, target: usize, q: &str, name: &str, span: Span, value: bool) -> Option<String> {
        let Some(c) = self.exports[target].get(name).cloned() else {
            self.errors.push(ModuleError { note: None,
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
        if self.is_hidden(name, value) {
            return None;
        }
        // The file's own declaration: renamed when it is private.
        if let Some(c) = self.own.get(name) {
            return (c != name).then(|| c.clone());
        }
        // A prelude name is recorded like an import even when it needs no
        // rewriting: a forced module's `export step` makes `step`, declared
        // in a file of that module, visible everywhere.
        match resolve_imported(name, self.bindings, self.prelude) {
            // Only an import can be captured by a hidden method: a prelude
            // name (`hash`) is not an import.
            Resolution::Declared(c, source) => self.denote(name, c, span, value, source == Source::Import),
            Resolution::Ambiguous => {
                self.errors.push(ModuleError { note: None, unresolved: false, file: self.file, span, message: ambiguous(name) });
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
            self.errors.push(ModuleError { note: None,
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
            self.errors.push(ModuleError { note: None,
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

    /// `name` is a method some extension (visible here or not) adds to the
    /// struct whose methods are being walked. Sema sees every extension, so
    /// a rewritten reference of that name would bind to the method.
    /// In a trait's default methods, that is any struct an extension makes
    /// conform to the trait.
    fn is_any_extension_method(&self, name: &str) -> bool {
        let structs: Vec<&str> = match (self.scopes.current_struct(), self.scopes.current_trait()) {
            (Some(st), _) => vec![self.members.resolve(st)],
            (None, Some(t)) => self
                .members
                .adopters
                .get(self.members.resolve(t))
                .map(|a| a.iter().map(String::as_str).collect())
                .unwrap_or_default(),
            _ => vec![],
        };
        structs
            .into_iter()
            .any(|st| self.members.of_extensions.get(st).is_some_and(|ext| ext.iter().any(|(m, _, _)| m == name)))
    }
}

impl ScopeWalkMut for Rewriter<'_, '_> {
    fn scopes(&self) -> &Scopes {
        &self.scopes
    }

    fn scopes_mut(&mut self) -> &mut Scopes {
        &mut self.scopes
    }

    fn is_member(&self, struct_name: &str, name: &str) -> bool {
        let struct_name = self.members.resolve(struct_name);
        self.members.of_body.get(struct_name).is_some_and(|m| m.contains(name))
            || self.members.of_extensions.get(struct_name).is_some_and(|ext| {
                ext.iter().any(|(m, file, exported)| {
                    m == name && (*file == self.file || (*exported && self.extensions.contains(file)))
                })
            })
    }

    /// `extend Box<T>` introduces T; `extend Array<Pt>`, with `Pt` imported
    /// or declared by any file, specializes and is rewritten (or checked)
    /// like any reference.
    fn extend_params(&self, target: &TypeName) -> HashSet<String> {
        target
            .generic_types
            .iter()
            .filter(|t| {
                t.generic_types.is_empty()
                    && !self.own.contains_key(&t.name)
                    && !self.types.contains(&t.name)
                    && !self.bindings.qualified.contains_key(t.name.split('.').next().unwrap_or(""))
                    && matches!(resolve_imported(&t.name, self.bindings, self.prelude), Resolution::Unknown)
            })
            .map(|t| t.name.clone())
            .collect()
    }

    /// An override's parameters are types (`describe<Point>` overrides
    /// `describe<T>` for `Point`), so each takes the name of the struct it
    /// denotes, mangled or imported, as sema compares them by name.
    fn visit_function_generics(&mut self, f: &mut FunctionDecl) -> bool {
        // `module` has already given the override its generic's name, which
        // may be mangled.
        if !self.override_decls.contains(&f.name_span.start) {
            return false;
        }
        for p in &mut f.generic_params {
            p.is_argument = true;
            if crate::type_name::is_concrete_override(std::iter::once(p.name.as_str())) {
                continue;
            }
            // A struct this file declares, or one an import or the prelude
            // reaches; not another file's private struct.
            let c = match self.own.get(&p.name) {
                Some(c) => Some(c.clone()),
                None => self.unqualified(&p.name, p.name_span, false),
            };
            let message = match c {
                Some(c) if self.structs.contains(&c) => {
                    p.name = c;
                    continue;
                }
                Some(_) => format!("'{}' is not a struct; an override's type argument must name a struct", p.name),
                None => format!("unknown type name '{}'", p.name),
            };
            self.errors.push(ModuleError { note: None, unresolved: false, file: self.file, span: p.name_span, message });
        }
        true
    }

    fn visit_expression(&mut self, expr: &mut Expression) {
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
        self.walk_expression(expr);
    }

    fn visit_symbol(&mut self, id: &mut String, span: Span) {
        if let Some(c) = self.unqualified(id, span, true) {
            *id = c;
        }
    }

    fn visit_type_name(&mut self, ty: &mut TypeName) {
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
                    self.errors.push(ModuleError { note: None,
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
        self.walk_type_name(ty);
    }
}
