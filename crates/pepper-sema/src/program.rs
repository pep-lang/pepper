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

/// A loaded, linked program. `files[0]` is the root.
pub struct Program {
    pub files: Vec<ProgramFile>,
    pub scopes: Vec<FileScope>,
    /// Unresolved imports and linking errors.
    pub errors: Vec<ModuleError>,
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
    /// their locations and fixes pointing at the file they came from.
    pub fn warnings(&self) -> Vec<Diagnostic> {
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
}

impl Default for Setup<'_> {
    fn default() -> Self {
        Setup { import_dirs: &[], forced_imports: &[], runtime: true, mode: Mode::Strict }
    }
}

/// Load the program rooted at `root` as the compiler, the language server,
/// and test harnesses all do: discover the runtime, build the search paths,
/// resolve forced imports into the prelude, then [`load`].
pub fn load_program(root: Root, setup: &Setup) -> Result<Program, String> {
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
    load(root, &prelude, &search_paths, setup.mode)
}

/// Load `root`, the `prelude` files, and everything their imports reach,
/// resolving module imports against `search_paths`; then link. The root is
/// `files[0]`, followed by the files it reaches, then the prelude.
pub fn load(root: Root, prelude: &[PathBuf], search_paths: &[PathBuf], mode: Mode) -> Result<Program, String> {
    let mut files: Vec<ProgramFile> = vec![];
    let mut index: HashMap<String, usize> = HashMap::new();
    // Resolved import paths per file, mapped to indices once all are loaded.
    let mut resolved: Vec<Vec<Option<String>>> = vec![];
    let mut errors: Vec<ModuleError> = vec![];
    // Lenient mode: files that could not be loaded, by key -> why.
    let mut failed: HashMap<String, String> = HashMap::new();
    // Module folders, looked up once per directory for this load.
    let roots = ModuleRoots::default();

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
                    continue;
                }
            }
        } else {
            break;
        };
        let module = match parse_source(&name, &source) {
            Ok(m) => m,
            Err(e) if mode == Mode::Strict || files.is_empty() => return Err(e),
            Err(e) => {
                failed.insert(key, e);
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
                    errors.push(ModuleError { unresolved: false, file, span: imp.span, message });
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
                        errors.push(ModuleError { unresolved: false, file, span: imp.name_span, message });
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
                    errors.push(ModuleError { unresolved: !imp.is_local, file, span: imp.name_span, message });
                    targets.push(None);
                }
            }
        }
        index.insert(key, file);
        resolved.push(targets);
        files.push(ProgramFile {
            name,
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
                errors.push(ModuleError {
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
    let (scopes, link_errors) = link(&mut files);
    errors.extend(link_errors);
    errors.sort_by_key(|e| (e.file, e.span.start));
    Ok(Program { files, scopes, errors })
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
