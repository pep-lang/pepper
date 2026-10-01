//! Program loading: read and parse the entry file, the prelude, and every
//! file their imports reach, then link them (see [`crate::modules`]) and
//! check visibility. Shared by the driver and the language server.

use crate::modules::{FileScope, ModuleError, ProgramFile, link};
use crate::visibility::{SourceFile, check_visibility};
use crate::passes::platform::keep;
use pepper_files::imports::{
    LocalImport, ModuleRoots, Placement, path_key, resolve_forced, resolve_local, resolve_module, search_paths,
};
use pepper_parser::diagnostic::{Diagnostic, FileId, Loc, Sources};
use pepper_parser::parser::parse_source;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// The file a program is rooted at. Its text is given, so an editor's
/// unsaved buffer can be the root.
pub struct Root {
    pub name: String,
    pub source: String,
    pub path: PathBuf,
}

impl Root {
    /// The file at `path`, read from disk.
    pub fn from_file(path: &Path) -> Result<Root, String> {
        let source = std::fs::read_to_string(path).map_err(|e| format!("cannot read {}: {}", path.display(), e))?;
        Ok(Root { name: path.to_string_lossy().into_owned(), source, path: path.to_path_buf() })
    }
}

/// How to treat an imported file that cannot be read or parsed.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Fail the load (the compiler).
    Strict,
    /// Skip the file (the language server, mid-edit).
    Lenient,
}

/// A compilation unit: files compiled into one object (see
/// [`Program::units`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Unit {
    /// The unit's name, also its path in the build cache (`io/file`,
    /// `prelude`, `main`).
    pub name: String,
    /// Its files, as indices into [`Program::files`].
    pub files: Vec<usize>,
}

/// A loaded, linked program. `files[0]` is the root.
pub struct Program {
    pub files: Vec<ProgramFile>,
    pub scopes: Vec<FileScope>,
    /// Unresolved imports and linking errors.
    pub errors: Vec<ModuleError>,
    /// Files the load found but could not read or parse, and so left out
    /// (lenient mode only): an editor watches them for a fix.
    pub failed: Vec<PathBuf>,
    /// The overload sets that span files of one module, from linking: each
    /// union's name -> the functions or single-file sets it joins.
    pub overload_unions: std::collections::BTreeMap<String, Vec<String>>,
}

impl Program {
    /// Render `errors` clang-style (see [`pepper_parser::diagnostic`]).
    pub fn render(&self, errors: &[ModuleError]) -> String {
        errors.iter().map(|e| e.to_diagnostic().render(self)).collect::<Vec<_>>().join("\n")
    }

    /// Linking errors, then visibility errors, every one rendered; empty
    /// when the program is well-formed.
    pub fn check(&self) -> Result<(), String> {
        if !self.errors.is_empty() {
            return Err(self.render(&self.errors));
        }
        let sources = self.source_files();
        let errors = check_visibility(&sources);
        if errors.is_empty() {
            return Ok(());
        }
        Err(errors.iter().map(|e| e.render(&sources)).collect::<Vec<_>>().join("\n"))
    }

    /// Warnings the parser found in every file (deprecated syntax, ...),
    /// their locations and fixes pointing at the file they came from, then
    /// [`Program::deprecation_warnings`].
    pub fn warnings(&self) -> Vec<Diagnostic> {
        let mut out = self.parser_warnings();
        out.extend(self.deprecation_warnings());
        out
    }

    /// Uses of top-level declarations marked `[Deprecated]` (see
    /// [`crate::deprecation`]). Uses of deprecated members are found later,
    /// by the sema passes, in `Module::warnings`.
    pub fn deprecation_warnings(&self) -> Vec<Diagnostic> {
        crate::deprecation::check_uses(&self.files, &self.scopes)
    }

    /// The warnings the parser found in every file, relocated to it.
    pub fn parser_warnings(&self) -> Vec<Diagnostic> {
        let mut out = vec![];
        for (i, f) in self.files.iter().enumerate() {
            let file = FileId(i as u32);
            let relocate = |loc: &mut Loc| loc.file = file;
            for w in &f.module.warnings {
                let mut w = w.clone();
                w.loc.iter_mut().for_each(relocate);
                for note in &mut w.notes {
                    note.loc.iter_mut().for_each(relocate);
                }
                for edit in w.fixes.iter_mut().flat_map(|fix| &mut fix.edits) {
                    relocate(&mut edit.loc);
                }
                out.push(w);
            }
        }
        out
    }

    /// [`Program::warnings`], rendered clang-style; empty when there are none.
    pub fn render_warnings(&self) -> String {
        self.warnings().iter().map(|w| w.render(self)).collect::<Vec<_>>().join("\n")
    }

    /// The order in which the files' module-scope variables are
    /// initialized: every file after the files it imports, and every file
    /// after the prelude. Prelude files go in reverse load order, since the
    /// runtime is loaded after the forced imports that build on it. Import
    /// cycles are broken at the file first reached.
    pub fn initialization_order(&self) -> Vec<usize> {
        fn visit(file: usize, files: &[ProgramFile], visited: &mut [bool], order: &mut Vec<usize>) {
            if visited[file] {
                return;
            }
            visited[file] = true;
            for &import in files[file].imports.iter().flatten() {
                visit(import, files, visited, order);
            }
            order.push(file);
        }
        let mut visited = vec![false; self.files.len()];
        let mut order = vec![];
        let prelude = (0..self.files.len()).rev().filter(|&i| self.files[i].prelude);
        for file in prelude.chain(0..self.files.len()) {
            visit(file, &self.files, &mut visited, &mut order);
        }
        order
    }

    /// The program's compilation units (see the build cache design,
    /// INTERNALS.md §4.3), sorted by name: the runtime's top-level files
    /// (prelude files outside any module) form the unit `prelude`; every
    /// other file is in the unit of its import cycle, a strongly connected
    /// component of the import graph, named after its first file's
    /// namespace in path order. A unit's name depends only on its files'
    /// paths, so it is the same in every program.
    pub fn units(&self) -> Vec<Unit> {
        let n = self.files.len();
        let in_prelude = |i: usize| self.files[i].prelude && self.files[i].module_root.is_none();
        // Tarjan's algorithm over the files outside the prelude unit.
        struct Tarjan {
            edges: Vec<Vec<usize>>,
            index: Vec<Option<usize>>,
            low: Vec<usize>,
            on_stack: Vec<bool>,
            stack: Vec<usize>,
            next: usize,
            components: Vec<Vec<usize>>,
        }
        impl Tarjan {
            fn visit(&mut self, v: usize) {
                self.index[v] = Some(self.next);
                self.low[v] = self.next;
                self.next += 1;
                self.stack.push(v);
                self.on_stack[v] = true;
                for w in self.edges[v].clone() {
                    match self.index[w] {
                        None => {
                            self.visit(w);
                            self.low[v] = self.low[v].min(self.low[w]);
                        }
                        Some(index) if self.on_stack[w] => self.low[v] = self.low[v].min(index),
                        Some(_) => {}
                    }
                }
                if Some(self.low[v]) == self.index[v] {
                    let mut component = vec![];
                    while let Some(w) = self.stack.pop() {
                        self.on_stack[w] = false;
                        component.push(w);
                        if w == v {
                            break;
                        }
                    }
                    self.components.push(component);
                }
            }
        }
        let edges = (0..n)
            .map(|i| self.files[i].imports.iter().flatten().copied().filter(|&t| !in_prelude(t) && !in_prelude(i)).collect())
            .collect();
        let mut tarjan = Tarjan {
            edges,
            index: vec![None; n],
            low: vec![0; n],
            on_stack: vec![false; n],
            stack: vec![],
            next: 0,
            components: vec![],
        };
        let prelude: Vec<usize> = (0..n).filter(|&i| in_prelude(i)).collect();
        for i in (0..n).filter(|&i| !in_prelude(i)) {
            if tarjan.index[i].is_none() {
                tarjan.visit(i);
            }
        }
        let mut units: Vec<Unit> = vec![];
        if !prelude.is_empty() {
            units.push(Unit { name: "prelude".to_string(), files: prelude });
        }
        for mut files in tarjan.components {
            files.sort_by(|&a, &b| self.files[a].namespace.cmp(&self.files[b].namespace));
            units.push(Unit { name: self.files[files[0]].namespace.clone(), files });
        }
        units.sort_by(|a, b| a.name.cmp(&b.name));
        // A user file named like the prelude keeps its own unit.
        let mut taken = std::collections::HashSet::new();
        for unit in &mut units {
            let base = unit.name.clone();
            let mut k = 1;
            while !taken.insert(unit.name.clone()) {
                k += 1;
                unit.name = format!("{}#{}", base, k);
            }
        }
        units
    }

    /// The files whose text a unit's generated code can depend on, in
    /// namespace order: its own files, every prelude file (visible everywhere), the
    /// files they import or take extensions from, transitively, and every
    /// file that declares a concrete override (`hash<Point>`), since sema
    /// honours an override wherever its generic is instantiated.
    pub fn unit_inputs(&self, unit: &Unit) -> Vec<usize> {
        let mut seen = vec![false; self.files.len()];
        let mut stack: Vec<usize> = unit.files.clone();
        stack.extend((0..self.files.len()).filter(|&i| {
            let file = &self.files[i];
            file.prelude || file.prelude_part || declares_override(&file.module)
        }));
        while let Some(file) = stack.pop() {
            if std::mem::replace(&mut seen[file], true) {
                continue;
            }
            stack.extend(self.files[file].imports.iter().flatten().copied());
            if let Some(scope) = self.scopes.get(file) {
                stack.extend(scope.extensions.iter().copied());
            }
        }
        // By namespace, not index: the index follows the order this
        // program loaded the files in, which the key must not depend on.
        let mut inputs: Vec<usize> = (0..self.files.len()).filter(|&i| seen[i]).collect();
        inputs.sort_by(|&a, &b| self.files[a].namespace.cmp(&self.files[b].namespace));
        inputs
    }

    /// Which files' extensions each file sees (see [`crate::model::ExtensionScopes`]).
    pub fn extension_scopes(&self) -> crate::model::ExtensionScopes {
        crate::model::ExtensionScopes {
            prelude: (0..self.files.len()).filter(|&i| self.files[i].prelude || self.files[i].prelude_part).map(|i| i as u32).collect(),
            visible: self.scopes.iter().map(|scope| scope.extensions.iter().map(|&i| i as u32).collect()).collect(),
        }
    }

    /// The files as the visibility check sees them.
    pub fn source_files(&self) -> Vec<SourceFile<'_>> {
        self.files
            .iter()
            .zip(&self.scopes)
            .map(|(f, scope)| SourceFile {
                name: &f.name,
                source: &f.source,
                module: &f.module,
                prelude: f.prelude,
                duplicate_exempt: f.prelude || f.prelude_part,
                imported: &scope.imported,
                extensions: &scope.extensions,
                module_root: f.module_root.as_deref(),
                bound: &scope.bound,
            })
            .collect()
    }
}

impl Sources for Program {
    fn get(&self, file: FileId) -> Option<(&str, &str)> {
        self.files.get(file.0 as usize).map(|f| (f.name.as_str(), f.source.as_str()))
    }
}

/// Where a program's files come from, beyond its root.
pub struct Setup<'a> {
    /// `-I` directories, searched first for modules.
    pub import_dirs: &'a [PathBuf],
    /// `--import` names: modules (or files) added to the prelude.
    pub forced_imports: &'a [String],
    /// Load the discovered runtime as the prelude.
    pub runtime: bool,
    pub mode: Mode,
    /// Syntax trees kept from earlier compiles, used in place of parsing.
    pub parsed: Option<&'a dyn ParseCache>,
}

impl Default for Setup<'_> {
    fn default() -> Self {
        Setup { import_dirs: &[], forced_imports: &[], runtime: true, mode: Mode::Strict, parsed: None }
    }
}

/// Syntax trees kept between compiles (the build cache's `.pepi` files), so
/// a file whose text has not changed is not parsed again.
pub trait ParseCache {
    /// The tree `source`, the text of the file at `path`, parses to, if one
    /// was kept for exactly that text.
    fn get(&self, path: &Path, source: &str) -> Option<pepper_parser::ast::Module>;
    /// Keep the tree `source` parsed to. Only a tree without warnings is
    /// kept, since its warnings are not.
    fn put(&self, path: &Path, source: &str, module: &pepper_parser::ast::Module);
}

/// Load the program rooted at `root` as the compiler, the language server,
/// and test harnesses all do: discover the runtime, build the search paths,
/// resolve forced imports into the prelude, then [`load`].
pub fn load_program(root: Root, setup: &Setup) -> Result<Program, String> {
    crate::reset_program_counters();
    let (runtime_sources, _libs, runtime_dirs) =
        if setup.runtime { pepper_files::runtime::discover() } else { (vec![], vec![], vec![]) };
    if setup.runtime && setup.mode == Mode::Strict && runtime_sources.is_empty() {
        let env = pepper_files::runtime::RUNTIME_ENV;
        return Err(match std::env::var_os(env).filter(|d| !d.is_empty()) {
            Some(dir) => format!("cannot find the Pepper runtime: {} ({}) has no .pep files", env, dir.to_string_lossy()),
            None => format!(
                "cannot find the Pepper runtime: no runtime directory near {} or the compiler; set {} to its path",
                std::env::current_dir().unwrap_or_default().display(),
                env
            ),
        });
    }
    let search_paths = search_paths(setup.import_dirs, &runtime_dirs);
    // Forced imports join the prelude ahead of the runtime: where one
    // redefines a runtime export (`panic`), the merged program keeps the
    // first definition, so the forced import's wins.
    let mut prelude = vec![];
    for name in setup.forced_imports {
        let path = resolve_forced(name, &search_paths).ok_or_else(|| {
            let stem = name.strip_suffix(".pep").unwrap_or(name);
            format!(
                "--import {}: cannot find module '{}' (no {}/module.pep) or file {}.pep in {}",
                name,
                stem,
                stem,
                stem,
                describe_paths(&search_paths)
            )
        })?;
        prelude.push(path);
    }
    prelude.extend(runtime_sources);
    load_with(root, &prelude, &search_paths, setup.mode, setup.parsed)
}

/// Load `root`, the `prelude` files, and everything their imports reach,
/// resolving module imports against `search_paths`; then link. The root is
/// `files[0]`, followed by the files it reaches, then the prelude.
pub fn load(root: Root, prelude: &[PathBuf], search_paths: &[PathBuf], mode: Mode) -> Result<Program, String> {
    load_with(root, prelude, search_paths, mode, None)
}

/// [`load`], taking each file's syntax tree from `parsed` when it has one
/// for the file's text.
pub fn load_with(root: Root, prelude: &[PathBuf], search_paths: &[PathBuf], mode: Mode, parsed: Option<&dyn ParseCache>) -> Result<Program, String> {
    let mut files: Vec<ProgramFile> = vec![];
    let mut index: HashMap<String, usize> = HashMap::new();
    // Resolved import paths per file, mapped to indices once all are loaded.
    let mut resolved: Vec<Vec<Option<String>>> = vec![];
    let mut errors: Vec<ModuleError> = vec![];
    // Lenient mode: files that could not be loaded, by key -> why.
    let mut failed: HashMap<String, String> = HashMap::new();
    let mut failed_paths: Vec<PathBuf> = vec![];
    // Module folders, looked up once per directory for this load.
    let roots = ModuleRoots::for_project(std::env::current_dir().ok().as_deref());

    // A stack: the root is popped first, and each file's imports are loaded
    // before the prelude.
    // Each path's key is computed once, when it is queued.
    let root_key = path_key(&root.path);
    let prelude_keys: Vec<String> = prelude.iter().map(|p| path_key(p)).collect();
    let mut stack: Vec<(PathBuf, String, bool)> = vec![];
    let mut queued: std::collections::HashSet<String> = std::collections::HashSet::new();
    queued.insert(root_key.clone());
    for (p, k) in prelude.iter().zip(&prelude_keys).rev() {
        if queued.insert(k.clone()) {
            stack.push((p.clone(), k.clone(), true));
        }
    }
    let mut pending_root = Some(root);

    loop {
        let (name, source, path, prelude, key) = if let Some(root) = pending_root.take() {
            let prelude = prelude_keys.contains(&root_key);
            (root.name, root.source, root.path, prelude, root_key.clone())
        } else if let Some((path, key, prelude)) = stack.pop() {
            match std::fs::read_to_string(&path) {
                Ok(s) => (path.to_string_lossy().into_owned(), s, path, prelude, key),
                Err(e) if mode == Mode::Strict => return Err(format!("cannot read {}: {}", path.display(), e)),
                Err(e) => {
                    failed.insert(key, format!("cannot read it: {}", e));
                    failed_paths.push(path);
                    continue;
                }
            }
        } else {
            break;
        };
        let kept = parsed.and_then(|cache| cache.get(&path, &source));
        let module = match kept.map_or_else(|| parse_source(&name, &source).map(|m| (m, true)), |m| Ok((m, false))) {
            Ok((m, fresh)) => {
                if let Some(cache) = parsed.filter(|_| fresh && m.warnings.is_empty()) {
                    cache.put(&path, &source, &m);
                }
                m
            }
            Err(e) if mode == Mode::Strict || files.is_empty() => return Err(e),
            Err(e) => {
                failed.insert(key, e);
                failed_paths.push(path);
                continue;
            }
        };
        let file = files.len();
        let mut targets = vec![];
        // Per import: resolved to a module folder, for diagnostics.
        let mut folders = vec![];
        for imp in &module.imports {
            folders.push(false);
            // An import platform selection drops is never resolved.
            match keep(&imp.attributes) {
                Ok(true) => {}
                Ok(false) => {
                    targets.push(None);
                    continue;
                }
                Err(message) => {
                    errors.push(ModuleError { note: None, unresolved: false, file, span: imp.span, message });
                    targets.push(None);
                    continue;
                }
            }
            let found = if imp.is_local {
                match resolve_local(&path, imp.stem()) {
                    // A file of another module is reached through that
                    // module, not directly.
                    Some(LocalImport::File(p))
                        if let placement = roots.placement(&path, &p)
                            && placement != Placement::SameModule =>
                    {
                        let message = match placement {
                            Placement::OtherModule => format!(
                                "{} belongs to another module; import that module's folder instead",
                                imp.describe()
                            ),
                            Placement::OutsideModule => format!(
                                "{} is outside this file's module; a module imports only its own files",
                                imp.describe()
                            ),
                            _ => format!(
                                "{} is outside this file's folder; a file outside any module imports only files in its folder or below",
                                imp.describe()
                            ),
                        };
                        errors.push(ModuleError { note: None, unresolved: false, file, span: imp.name_span, message });
                        targets.push(None);
                        continue;
                    }
                    found => {
                        if let (Some(LocalImport::Module(_)), Some(f)) = (&found, folders.last_mut()) {
                            *f = true;
                        }
                        found.map(|l| l.path().to_path_buf())
                    }
                }
            } else {
                resolve_module(&imp.name, search_paths)
            };
            match found {
                Some(p) => {
                    let k = path_key(&p);
                    if queued.insert(k.clone()) {
                        stack.push((p, k.clone(), false));
                    }
                    targets.push(Some(k));
                }
                None => {
                    let message = if imp.is_local {
                        format!(
                            "cannot find {} or the module folder \"{}\" next to this file",
                            imp.describe(),
                            imp.stem()
                        )
                    } else {
                        format!(
                            "cannot find module '{}': no {}/module.pep in {}",
                            imp.name,
                            imp.name,
                            describe_paths(search_paths)
                        )
                    };
                    // Only a module search depends on `-I`, which an editor
                    // may not know; a missing file is missing everywhere.
                    errors.push(ModuleError { note: None, unresolved: !imp.is_local, file, span: imp.name_span, message });
                    targets.push(None);
                }
            }
        }
        index.insert(key, file);
        resolved.push(targets);
        let namespace = roots.namespace_of(&path);
        let module_root = roots.module_of(&path);
        files.push(ProgramFile {
            name,
            namespace,
            module_root,
            source,
            module,
            prelude,
            prelude_part: false,
            imports: vec![],
            folder_imports: folders,
        });
    }

    for (i, (file, targets)) in files.iter_mut().zip(resolved).enumerate() {
        // A target that failed to load in lenient mode stays unresolved, and
        // the import says why rather than every use of it.
        for ((imp, target), folder) in file.module.imports.iter().zip(&targets).zip(&file.folder_imports) {
            if let Some(why) = target.as_ref().and_then(|k| failed.get(k)) {
                errors.push(ModuleError { note: None,
                    unresolved: false,
                    file: i,
                    span: imp.name_span,
                    message: format!("cannot load {}: {}", imp.describe_as(*folder), why),
                });
            }
        }
        file.imports = targets.into_iter().map(|t| t.and_then(|k| index.get(&k).copied())).collect();
    }
    // The files prelude files reach through local imports belong to them (a
    // forced module's other files): they share the duplicate-export
    // exemption, whatever order they were loaded in.
    let mut part: Vec<usize> = (0..files.len()).filter(|&i| files[i].prelude).collect();
    while let Some(i) = part.pop() {
        let reached: Vec<usize> = files[i]
            .module
            .imports
            .iter()
            .zip(&files[i].imports)
            .zip(&files[i].folder_imports)
            // Only its files: a module folder it imports is a module of its own.
            .filter_map(|((imp, t), folder)| t.filter(|_| imp.is_local && !folder))
            .collect();
        for t in reached {
            if !files[t].prelude && !files[t].prelude_part {
                files[t].prelude_part = true;
                part.push(t);
            }
        }
    }
    // Namespaces must be unique. Paths already make them so, except for
    // files outside the project directory and any module, which fall back
    // to their name: two such `util.pep`s are told apart by load order.
    let mut taken = std::collections::HashSet::new();
    for f in &mut files {
        let base = f.namespace.clone();
        let mut n = 1;
        while !taken.insert(f.namespace.clone()) {
            n += 1;
            f.namespace = format!("{}#{}", base, n);
        }
    }
    let linked = link(&mut files);
    errors.extend(linked.errors);
    errors.sort_by_key(|e| (e.file, e.span.start));
    Ok(Program { files, scopes: linked.scopes, errors, failed: failed_paths, overload_unions: linked.overload_unions })
}

fn describe_paths(paths: &[PathBuf]) -> String {
    if paths.is_empty() {
        return "(no search paths)".to_string();
    }
    paths.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", ")
}

/// Load a program rooted at the file `path`.
pub fn load_file(path: &Path, prelude: &[PathBuf], search_paths: &[PathBuf], mode: Mode) -> Result<Program, String> {
    load(Root::from_file(path)?, prelude, search_paths, mode)
}

/// Whether `module` declares a concrete override of a generic function
/// (module linking marked its generic parameters as type arguments).
pub fn declares_override(module: &pepper_parser::ast::Module) -> bool {
    module.declarations.iter().any(|d| match d {
        pepper_parser::ast::Declaration::Function(f) => f.generic_params.iter().any(|p| p.is_argument),
        _ => false,
    })
}
