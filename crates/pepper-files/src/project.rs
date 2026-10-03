//! Projects: a `pep.toml` file marks the root of a project (or of a package,
//! which is a project other projects depend on) and declares its metadata,
//! how `pepper build` builds it, and its dependencies.
//!
//! ```toml
//! [package]
//! name = "my_app"
//! version = "0.1.0"
//!
//! [build]
//! entry = "src/main.pep"
//!
//! [dependencies]
//! geometry = { github = "someone/geometry", version = "1.2" }
//! ```
//!
//! Each key of `[dependencies]` is the name source code imports
//! (`import geometry`). A fetched dependency lives in the project's
//! `.pep/deps/<host>/<repository>` ([`Dependency::directory`]), and
//! [`Packages`] resolves the imports of every file of a program against the
//! dependencies of the package that file belongs to.

use std::cell::RefCell;
use std::collections::HashMap;
use std::ops::Range;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use toml::de::{DeTable, DeValue};
use toml::Spanned;

/// The file that marks a project's root.
pub const MANIFEST_FILE: &str = "pep.toml";

/// The folder, in a project's `.pep`, that holds its fetched dependencies.
pub const DEPS_DIR: &str = "deps";

/// The file, beside `pep.toml`, that records the exact revision of every
/// dependency in the graph (`pepper package` writes it).
pub const LOCK_FILE: &str = "pep.lock";

/// A problem with a `pep.toml`, at a byte range of its text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestError {
    pub message: String,
    pub span: Range<usize>,
}

/// A parsed `pep.toml`.
#[derive(Debug, Clone)]
pub struct Manifest {
    /// The `pep.toml` file.
    pub path: PathBuf,
    /// Its text, for diagnostics.
    pub text: String,
    pub package: Package,
    pub build: Build,
    /// In the order they are written.
    pub dependencies: Vec<Dependency>,
    /// `[fetch]`'s `hosts`: where `pepper package add` looks a repository
    /// up, in order.
    pub hosts: Vec<Host>,
}

/// `[package]`: the project's metadata.
#[derive(Debug, Clone, Default)]
pub struct Package {
    /// Required.
    pub name: String,
    pub version: Option<String>,
    pub description: Option<String>,
    pub authors: Vec<String>,
    pub license: Option<String>,
    pub repository: Option<String>,
}

/// `[build]`: what `pepper build` with no file argument builds.
#[derive(Debug, Clone, Default)]
pub struct Build {
    /// The entry file, relative to the project; `main.pep` when absent.
    pub entry: Option<PathBuf>,
    /// The executable, relative to the project; the package's name when
    /// absent.
    pub output: Option<PathBuf>,
    /// Extra module search directories (`-I`), relative to the project.
    pub include: Vec<PathBuf>,
    /// Libraries to link (`-l`).
    pub link: Vec<String>,
}

/// Where a dependency comes from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Source {
    /// A repository (`owner/name`) on a Git host.
    Git { host: Host, repository: String },
    /// A folder on disk, relative to the `pep.toml` that names it.
    Path(PathBuf),
}

/// The Git hosts a dependency can come from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Host {
    GitHub,
    GitLab,
    Codeberg,
}

impl Host {
    pub const ALL: [Host; 3] = [Host::GitHub, Host::GitLab, Host::Codeberg];

    /// The key that names it in a dependency: `github`.
    pub fn key(self) -> &'static str {
        match self {
            Host::GitHub => "github",
            Host::GitLab => "gitlab",
            Host::Codeberg => "codeberg",
        }
    }

    /// Its domain: `github.com`.
    pub fn domain(self) -> &'static str {
        match self {
            Host::GitHub => "github.com",
            Host::GitLab => "gitlab.com",
            Host::Codeberg => "codeberg.org",
        }
    }

    /// The address git clones `repository` (`owner/name`) from:
    /// `https://github.com/owner/name.git`, or under the address in
    /// `PEPPER_PACKAGE_<HOST>_URL` when that is set (a mirror).
    pub fn clone_url(self, repository: &str) -> String {
        let variable = match self {
            Host::GitHub => "PEPPER_PACKAGE_GITHUB_URL",
            Host::GitLab => "PEPPER_PACKAGE_GITLAB_URL",
            Host::Codeberg => "PEPPER_PACKAGE_CODEBERG_URL",
        };
        let base = std::env::var(variable).ok().filter(|v| !v.is_empty()).unwrap_or_else(|| format!("https://{}", self.domain()));
        format!("{}/{}.git", base.trim_end_matches('/'), repository)
    }
}

/// Where a package's files live in the project `project`:
/// `<project>/.pep/deps/<host domain>/<owner>/<name>`.
pub fn package_directory(project: &Path, host: Host, repository: &str) -> PathBuf {
    let mut dir = project.join(".pep").join(DEPS_DIR).join(host.domain());
    dir.extend(repository.split('/'));
    dir
}

/// One package `pep.lock` lists.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LockedPackage {
    pub host: Host,
    /// `owner/name`.
    pub repository: String,
    /// The full commit to check out.
    pub commit: String,
}

impl LockedPackage {
    /// Its source as `pep.lock` writes it: `github:owner/name`.
    pub fn source(&self) -> String {
        format!("{}:{}", self.host.key(), self.repository)
    }
}

/// The packages the `pep.lock` at `path` lists; none when it does not
/// exist.
pub fn read_lock(path: &Path) -> Result<Vec<LockedPackage>, String> {
    let Ok(text) = std::fs::read_to_string(path) else { return Ok(vec![]) };
    let root = DeTable::parse(&text).map_err(|e| format!("{}: {}", path.display(), toml_message(e.message())))?;
    let invalid = || format!("{}: 'package' must be an array of tables with a 'source' and a 'commit'", path.display());
    let mut locked = vec![];
    let Some(packages) = root.get_ref().iter().find(|(k, _)| k.get_ref() == "package").map(|(_, v)| v) else { return Ok(vec![]) };
    let DeValue::Array(packages) = packages.get_ref() else { return Err(invalid()) };
    for package in packages {
        let DeValue::Table(package) = package.get_ref() else { return Err(invalid()) };
        let field = |key: &str| match package.iter().find(|(k, _)| k.get_ref() == key).map(|(_, v)| v.get_ref()) {
            Some(DeValue::String(s)) => Ok(s.to_string()),
            _ => Err(invalid()),
        };
        let (source, commit) = (field("source")?, field("commit")?);
        let (host, repository) = source.split_once(':').ok_or_else(invalid)?;
        let host = Host::ALL.into_iter().find(|h| h.key() == host).ok_or_else(invalid)?;
        locked.push(LockedPackage { host, repository: repository.to_string(), commit });
    }
    Ok(locked)
}

/// Which revision of a Git dependency to use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Revision {
    /// The newest tag in a semver range (`1.2`, `0.4.x`, `>=1.0, <2`).
    Version(String),
    Branch(String),
    Tag(String),
    Commit(String),
    /// None given: the default branch.
    Default,
}

/// One entry of `[dependencies]`.
#[derive(Debug, Clone)]
pub struct Dependency {
    /// The key: the name source code imports.
    pub name: String,
    /// The key's span in the manifest's text.
    pub name_span: Range<usize>,
    pub source: Source,
    pub revision: Revision,
}

impl Dependency {
    /// Where the dependency's files are, for a project rooted at `project`
    /// whose manifest (the one naming the dependency) is in `manifest_dir`:
    /// `<project>/.pep/deps/<host domain>/<repository>` for a Git
    /// dependency, the folder itself for a path dependency.
    pub fn directory(&self, project: &Path, manifest_dir: &Path) -> PathBuf {
        match &self.source {
            Source::Git { host, repository } => package_directory(project, *host, repository),
            Source::Path(path) => manifest_dir.join(path),
        }
    }

    /// Its source as `pep.lock` writes it (`github:owner/name`), for a Git
    /// dependency.
    pub fn locked_source(&self) -> Option<String> {
        match &self.source {
            Source::Git { host, repository } => Some(format!("{}:{}", host.key(), repository)),
            Source::Path(_) => None,
        }
    }
}

impl Manifest {
    /// Read and parse the `pep.toml` at `path`.
    pub fn read(path: &Path) -> Result<Manifest, ManifestFailure> {
        let text = std::fs::read_to_string(path).map_err(|e| ManifestFailure::Unreadable(format!("cannot read {}: {}", path.display(), e)))?;
        Manifest::parse(path, &text).map_err(|errors| ManifestFailure::Invalid { path: path.to_path_buf(), text, errors })
    }

    /// Parse `text`, the contents of the `pep.toml` at `path`. Every problem
    /// found is returned, in the order of the text.
    pub fn parse(path: &Path, text: &str) -> Result<Manifest, Vec<ManifestError>> {
        let root = match DeTable::parse(text) {
            Ok(root) => root,
            Err(e) => {
                let span = e.span().unwrap_or(0..0);
                let mut message = toml_message(e.message());
                if message == "duplicate key" && let Some(key) = text.get(span.clone()) {
                    message = format!("duplicate key '{}'", key.trim_matches('"'));
                }
                return Err(vec![ManifestError { message, span }]);
            }
        };
        let mut errors = vec![];
        let mut manifest = Manifest {
            path: path.to_path_buf(),
            text: text.to_string(),
            package: Package::default(),
            build: Build::default(),
            dependencies: vec![],
            hosts: Host::ALL.to_vec(),
        };
        let mut package_seen = false;
        for (key, value) in root.get_ref() {
            match key.get_ref().as_ref() {
                "package" => {
                    package_seen = true;
                    if let Some(table) = table(key, value, &mut errors) {
                        manifest.package = parse_package(key, table, &mut errors);
                    }
                }
                "build" => {
                    if let Some(table) = table(key, value, &mut errors) {
                        manifest.build = parse_build(table, &mut errors);
                    }
                }
                "dependencies" => {
                    if let Some(table) = table(key, value, &mut errors) {
                        manifest.dependencies = parse_dependencies(table, &mut errors);
                    }
                }
                "fetch" => {
                    if let Some(table) = table(key, value, &mut errors) {
                        manifest.hosts = parse_fetch(table, &mut errors);
                    }
                }
                other => errors.push(ManifestError {
                    message: format!("unknown table '{}'; a pep.toml has '[package]', '[build]', '[dependencies]' and '[fetch]'", other),
                    span: key.span(),
                }),
            }
        }
        if !package_seen {
            errors.push(ManifestError { message: "missing '[package]' table with the project's 'name'".to_string(), span: 0..0 });
        }
        if errors.is_empty() {
            Ok(manifest)
        } else {
            errors.sort_by_key(|e| e.span.start);
            Err(errors)
        }
    }

    /// The folder holding the `pep.toml`: the project's root.
    pub fn dir(&self) -> &Path {
        crate::imports::dir_of(&self.path)
    }

    /// The dependency named `name`, if any.
    pub fn dependency(&self, name: &str) -> Option<&Dependency> {
        self.dependencies.iter().find(|d| d.name == name)
    }

    /// The `[build]` entry file: `entry`, else `main.pep`, in the project.
    pub fn entry(&self) -> PathBuf {
        self.dir().join(self.build.entry.as_deref().unwrap_or(Path::new("main.pep")))
    }

    /// The `[build]` executable: `output`, else the package's name, in the
    /// project.
    pub fn output(&self) -> PathBuf {
        self.dir().join(self.build.output.clone().unwrap_or_else(|| PathBuf::from(&self.package.name)))
    }

    /// The `[build]` include directories, in the project.
    pub fn include_dirs(&self) -> Vec<PathBuf> {
        self.build.include.iter().map(|dir| self.dir().join(dir)).collect()
    }
}

/// Why a `pep.toml` could not be used.
#[derive(Debug, Clone)]
pub enum ManifestFailure {
    /// It could not be read.
    Unreadable(String),
    /// It was read, and has these problems.
    Invalid { path: PathBuf, text: String, errors: Vec<ManifestError> },
}

/// The toml crate's message, worded like a compiler error: its first line,
/// lowercase, with names in single quotes.
fn toml_message(message: &str) -> String {
    let line = message.lines().find(|l| !l.trim().is_empty()).unwrap_or("invalid TOML").trim();
    let line = line.trim_end_matches('.').replace('`', "'");
    let mut chars = line.chars();
    match chars.next() {
        Some(c) => c.to_lowercase().chain(chars).collect(),
        None => line,
    }
}

type Key<'a> = Spanned<std::borrow::Cow<'a, str>>;
type Value<'a> = Spanned<DeValue<'a>>;

/// What a value is, for "expected" messages.
fn kind(value: &DeValue) -> &'static str {
    match value {
        DeValue::String(_) => "a string",
        DeValue::Integer(_) => "an integer",
        DeValue::Float(_) => "a float",
        DeValue::Boolean(_) => "a boolean",
        DeValue::Datetime(_) => "a date-time",
        DeValue::Array(_) => "an array",
        DeValue::Table(_) => "a table",
    }
}

fn table<'a, 'b>(key: &Key, value: &'b Value<'a>, errors: &mut Vec<ManifestError>) -> Option<&'b DeTable<'a>> {
    match value.get_ref() {
        DeValue::Table(t) => Some(t),
        other => {
            errors.push(ManifestError { message: format!("'{}' must be a table, not {}", key.get_ref(), kind(other)), span: value.span() });
            None
        }
    }
}

fn string(key: &Key, value: &Value, errors: &mut Vec<ManifestError>) -> Option<String> {
    match value.get_ref() {
        DeValue::String(s) => Some(s.to_string()),
        other => {
            errors.push(ManifestError { message: format!("'{}' must be a string, not {}", key.get_ref(), kind(other)), span: value.span() });
            None
        }
    }
}

fn strings(key: &Key, value: &Value, errors: &mut Vec<ManifestError>) -> Vec<String> {
    match value.get_ref() {
        DeValue::Array(items) => items
            .iter()
            .filter_map(|item| match item.get_ref() {
                DeValue::String(s) => Some(s.to_string()),
                other => {
                    errors.push(ManifestError {
                        message: format!("'{}' must be an array of strings; this is {}", key.get_ref(), kind(other)),
                        span: item.span(),
                    });
                    None
                }
            })
            .collect(),
        other => {
            errors.push(ManifestError { message: format!("'{}' must be an array of strings, not {}", key.get_ref(), kind(other)), span: value.span() });
            vec![]
        }
    }
}

fn unknown_key(key: &Key, table: &str, known: &[&str], errors: &mut Vec<ManifestError>) {
    let known: Vec<String> = known.iter().map(|k| format!("'{}'", k)).collect();
    errors.push(ManifestError {
        message: format!("unknown key '{}' in '[{}]'; expected one of {}", key.get_ref(), table, known.join(", ")),
        span: key.span(),
    });
}

/// Whether `name` can be imported: an identifier.
pub fn is_identifier(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_') && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn parse_package(header: &Key, table: &DeTable, errors: &mut Vec<ManifestError>) -> Package {
    const KEYS: [&str; 6] = ["name", "version", "description", "authors", "license", "repository"];
    let mut package = Package::default();
    let mut named = false;
    for (key, value) in table {
        match key.get_ref().as_ref() {
            "name" => {
                if let Some(name) = string(key, value, errors) {
                    named = true;
                    if !is_identifier(&name) {
                        errors.push(ManifestError {
                            message: format!("package name '{}' is not an identifier: use letters, digits and '_', not starting with a digit", name),
                            span: value.span(),
                        });
                    }
                    package.name = name;
                }
            }
            "version" => package.version = string(key, value, errors),
            "description" => package.description = string(key, value, errors),
            "authors" => package.authors = strings(key, value, errors),
            "license" => package.license = string(key, value, errors),
            "repository" => package.repository = string(key, value, errors),
            _ => unknown_key(key, "package", &KEYS, errors),
        }
    }
    if !named {
        errors.push(ManifestError { message: "'[package]' needs a 'name'".to_string(), span: header.span() });
    }
    package
}

fn parse_build(table: &DeTable, errors: &mut Vec<ManifestError>) -> Build {
    const KEYS: [&str; 4] = ["entry", "output", "include", "link"];
    let mut build = Build::default();
    for (key, value) in table {
        match key.get_ref().as_ref() {
            "entry" => build.entry = string(key, value, errors).map(PathBuf::from),
            "output" => build.output = string(key, value, errors).map(PathBuf::from),
            "include" => build.include = strings(key, value, errors).into_iter().map(PathBuf::from).collect(),
            "link" => build.link = strings(key, value, errors),
            _ => unknown_key(key, "build", &KEYS, errors),
        }
    }
    build
}

fn parse_fetch(table: &DeTable, errors: &mut Vec<ManifestError>) -> Vec<Host> {
    const KEYS: [&str; 1] = ["hosts"];
    let mut hosts = Host::ALL.to_vec();
    for (key, value) in table {
        match key.get_ref().as_ref() {
            "hosts" => {
                let DeValue::Array(items) = value.get_ref() else {
                    errors.push(ManifestError {
                        message: format!("'hosts' must be an array of strings, not {}", kind(value.get_ref())),
                        span: value.span(),
                    });
                    continue;
                };
                hosts = vec![];
                for item in items {
                    let host = match item.get_ref() {
                        DeValue::String(s) => Host::ALL.into_iter().find(|h| h.key() == s.as_ref()),
                        _ => None,
                    };
                    match host {
                        Some(host) => hosts.push(host),
                        None => errors.push(ManifestError {
                            message: "'hosts' lists 'github', 'gitlab' or 'codeberg'".to_string(),
                            span: item.span(),
                        }),
                    }
                }
            }
            _ => unknown_key(key, "fetch", &KEYS, errors),
        }
    }
    hosts
}

fn parse_dependencies(table: &DeTable, errors: &mut Vec<ManifestError>) -> Vec<Dependency> {
    let mut dependencies = vec![];
    for (key, value) in table {
        let name = key.get_ref().to_string();
        if !is_identifier(&name) {
            errors.push(ManifestError {
                message: format!("dependency name '{}' is not an identifier; it is the name 'import' uses", name),
                span: key.span(),
            });
            continue;
        }
        let Some(fields) = (match value.get_ref() {
            DeValue::Table(t) => Some(t),
            other => {
                errors.push(ManifestError {
                    message: format!(
                        "dependency '{}' must be a table, not {}: '{} = {{ github = \"owner/name\", version = \"1.0\" }}'",
                        name,
                        kind(other),
                        name
                    ),
                    span: value.span(),
                });
                None
            }
        }) else {
            continue;
        };
        if let Some(dependency) = parse_dependency(key, value, fields, errors) {
            dependencies.push(dependency);
        }
    }
    dependencies
}

fn parse_dependency(key: &Key, value: &Value, fields: &DeTable, errors: &mut Vec<ManifestError>) -> Option<Dependency> {
    const KEYS: [&str; 8] = ["github", "gitlab", "codeberg", "path", "version", "branch", "tag", "commit"];
    let name = key.get_ref().to_string();
    let before = errors.len();
    let mut source: Option<(Source, Range<usize>)> = None;
    let mut revision: Option<(Revision, Range<usize>)> = None;
    for (field, field_value) in fields {
        let field_name = field.get_ref().as_ref();
        if let Some(host) = Host::ALL.into_iter().find(|h| h.key() == field_name) {
            let Some(repository) = string(field, field_value, errors) else { continue };
            // GitLab nests groups: `group/subgroup/name`.
            let parts: Vec<&str> = repository.split('/').collect();
            let well_formed = parts.iter().all(|p| !p.is_empty() && *p != "." && *p != "..")
                && (parts.len() == 2 || host == Host::GitLab && parts.len() > 2);
            if !well_formed {
                errors.push(ManifestError {
                    message: format!("'{}' must name a repository as 'owner/name', not '{}'", field_name, repository),
                    span: field_value.span(),
                });
                continue;
            }
            set_source(&mut source, Source::Git { host, repository }, field, errors);
        } else if field_name == "path" {
            let Some(path) = string(field, field_value, errors) else { continue };
            set_source(&mut source, Source::Path(PathBuf::from(path)), field, errors);
        } else if let Some(make) = match field_name {
            "version" => Some(Revision::Version as fn(String) -> Revision),
            "branch" => Some(Revision::Branch as fn(String) -> Revision),
            "tag" => Some(Revision::Tag as fn(String) -> Revision),
            "commit" => Some(Revision::Commit as fn(String) -> Revision),
            _ => None,
        } {
            let Some(text) = string(field, field_value, errors) else { continue };
            if let Some((_, first)) = &revision {
                let first = &fields.keys().find(|k| k.span() == *first).map(|k| k.get_ref().to_string()).unwrap_or_default();
                errors.push(ManifestError {
                    message: format!("'{}' and '{}' both choose a revision; give one of 'version', 'branch', 'tag' or 'commit'", first, field_name),
                    span: field.span(),
                });
                continue;
            }
            revision = Some((make(text), field.span()));
        } else {
            unknown_key(field, "dependencies", &KEYS, errors);
        }
    }
    let Some((source, _)) = source else {
        if errors.len() == before {
            errors.push(ManifestError {
                message: format!("dependency '{}' needs a source: 'github', 'gitlab' or 'codeberg' (\"owner/name\"), or 'path'", name),
                span: value.span(),
            });
        }
        return None;
    };
    if let (Source::Path(_), Some((_, span))) = (&source, &revision) {
        errors.push(ManifestError {
            message: format!("dependency '{}' is a 'path'; a folder has no versions, branches, tags or commits", name),
            span: span.clone(),
        });
    }
    if errors.len() != before {
        return None;
    }
    Some(Dependency {
        name,
        name_span: key.span(),
        source,
        revision: revision.map(|(r, _)| r).unwrap_or(Revision::Default),
    })
}

fn set_source(slot: &mut Option<(Source, Range<usize>)>, source: Source, field: &Key, errors: &mut Vec<ManifestError>) {
    if slot.is_some() {
        errors.push(ManifestError {
            message: format!("'{}' is a second source; a dependency comes from one of 'github', 'gitlab', 'codeberg' or 'path'", field.get_ref()),
            span: field.span(),
        });
    } else {
        *slot = Some((source, field.span()));
    }
}

/// The `pep.toml` nearest `dir`: in it, or in the closest folder above it
/// that has one.
pub fn find_manifest(dir: &Path) -> Option<PathBuf> {
    let dir = std::path::absolute(dir).ok()?;
    dir.ancestors().map(|d| d.join(MANIFEST_FILE)).find(|p| p.is_file())
}

/// The project a program rooted at the file `root` belongs to: the folder of
/// the nearest `pep.toml` above it that is not itself inside a project's
/// `.pep` folder (a fetched dependency belongs to the project that fetched
/// it).
pub fn find_project(root: &Path) -> Option<PathBuf> {
    let file = std::path::absolute(root).ok()?;
    let start = crate::imports::dir_of(&file);
    // Above a `.pep` folder, if the file is inside one.
    let outside = start.ancestors().find(|d| d.file_name().is_some_and(|n| n == ".pep")).and_then(Path::parent).unwrap_or(start);
    outside.ancestors().find(|d| d.join(MANIFEST_FILE).is_file()).map(Path::to_path_buf)
}

/// What [`Packages::resolve`] found for `import name`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Resolution {
    /// The first part of the name is not a dependency of the importing
    /// file's package: search the search paths.
    NotADependency,
    /// The module's `module.pep`.
    Found(PathBuf),
    /// A dependency names it, but its module is not on disk. The message
    /// says what is missing.
    Missing(String),
    /// The importing file's `pep.toml` cannot be used.
    BadManifest(String),
}

/// The packages of a program: which `pep.toml` each file falls under, and
/// where the dependencies it names are.
pub struct Packages {
    /// The project's root folder, whose `.pep/deps` holds fetched
    /// dependencies.
    project: Option<PathBuf>,
    /// folder -> the manifest governing it (or why it could not be used).
    by_dir: RefCell<HashMap<PathBuf, Option<Rc<Result<Manifest, String>>>>>,
}

impl Packages {
    /// The packages of a program rooted at the file `root`.
    pub fn for_root(root: &Path) -> Packages {
        Packages { project: find_project(root), by_dir: RefCell::default() }
    }

    /// No project: every import searches the search paths.
    pub fn none() -> Packages {
        Packages { project: None, by_dir: RefCell::default() }
    }

    /// The project's root folder, if the program is in one.
    pub fn project(&self) -> Option<&Path> {
        self.project.as_deref()
    }

    fn manifest_for(&self, dir: &Path) -> Option<Rc<Result<Manifest, String>>> {
        if let Some(m) = self.by_dir.borrow().get(dir) {
            return m.clone();
        }
        let found = if dir.join(MANIFEST_FILE).is_file() {
            let path = dir.join(MANIFEST_FILE);
            Some(Rc::new(Manifest::read(&path).map_err(|failure| match failure {
                ManifestFailure::Unreadable(message) => message,
                ManifestFailure::Invalid { path, text, errors } => {
                    let first = &errors[0];
                    let (line, column) = line_column(&text, first.span.start);
                    format!("{}:{}:{}: {}", path.display(), line, column, first.message)
                }
            })))
        } else {
            dir.parent().and_then(|parent| self.manifest_for(parent))
        };
        self.by_dir.borrow_mut().insert(dir.to_path_buf(), found.clone());
        found
    }

    /// `import name` (`a`, or `a.b.c` for a module inside a package) in the
    /// file `from`: when `a` is a dependency of `from`'s package, the
    /// module `a` names there (its root `module.pep`, or `b/c/module.pep`
    /// inside it).
    pub fn resolve(&self, from: &Path, name: &str) -> Resolution {
        let Some(project) = &self.project else { return Resolution::NotADependency };
        let Ok(from) = std::path::absolute(from) else { return Resolution::NotADependency };
        let Some(manifest) = self.manifest_for(crate::imports::dir_of(&from)) else { return Resolution::NotADependency };
        let manifest = match &*manifest {
            Ok(m) => m,
            Err(message) => return Resolution::BadManifest(message.clone()),
        };
        let mut parts = name.split('.');
        let first = parts.next().unwrap_or(name);
        let Some(dependency) = manifest.dependency(first) else { return Resolution::NotADependency };
        let package = dependency.directory(project, manifest.dir());
        if !package.is_dir() {
            return Resolution::Missing(match &dependency.source {
                Source::Git { .. } => format!("dependency '{}' is not fetched: no {}", first, package.display()),
                Source::Path(_) => format!("dependency '{}' names the folder {}, which does not exist", first, package.display()),
            });
        }
        let mut module = package.clone();
        module.extend(parts);
        let file = module.join(crate::imports::MODULE_FILE);
        if file.is_file() {
            Resolution::Found(file)
        } else if module == package {
            Resolution::Missing(format!("package '{}' has no root module: no {}", first, file.display()))
        } else {
            Resolution::Missing(format!("package '{}' has no module '{}': no {}", first, name, file.display()))
        }
    }
}

/// The 1-based line and column of byte `offset` in `text`.
pub fn line_column(text: &str, offset: usize) -> (usize, usize) {
    let before = &text[..offset.min(text.len())];
    let line = before.matches('\n').count() + 1;
    let column = before.rfind('\n').map_or(before.len(), |nl| before.len() - nl - 1) + 1;
    (line, column)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(text: &str) -> Result<Manifest, Vec<ManifestError>> {
        Manifest::parse(Path::new("pep.toml"), text)
    }

    fn errors(text: &str) -> Vec<String> {
        parse(text).err().unwrap_or_default().into_iter().map(|e| format!("{}: {}", &text[e.span.clone()], e.message)).collect()
    }

    #[test]
    fn reads_a_manifest() {
        let m = parse(
            r#"
[package]
name = "my_app"
version = "0.1.0"
authors = ["A", "B"]

[build]
entry = "src/main.pep"
include = ["vendor"]
link = ["m"]

[dependencies]
geometry = { github = "someone/geometry", version = "1.2" }
json = { gitlab = "group/sub/pepper-json", tag = "v0.4.0" }
http = { codeberg = "someone/http", branch = "main" }
local = { path = "../local" }
"#,
        )
        .unwrap();
        assert_eq!(m.package.name, "my_app");
        assert_eq!(m.package.authors, ["A", "B"]);
        assert_eq!(m.build.entry.as_deref(), Some(Path::new("src/main.pep")));
        assert_eq!(m.build.link, ["m"]);
        let names: Vec<&str> = m.dependencies.iter().map(|d| d.name.as_str()).collect();
        assert_eq!(names, ["geometry", "json", "http", "local"]);
        assert_eq!(m.dependencies[0].revision, Revision::Version("1.2".into()));
        assert_eq!(m.dependencies[1].source, Source::Git { host: Host::GitLab, repository: "group/sub/pepper-json".into() });
        let dir = m.dependencies[0].directory(Path::new("/p"), Path::new("/p"));
        assert_eq!(dir, Path::new("/p/.pep/deps/github.com/someone/geometry"));
        assert_eq!(m.dependencies[3].directory(Path::new("/p"), Path::new("/p")), Path::new("/p/../local"));
    }

    #[test]
    fn reports_problems_at_the_key() {
        assert_eq!(
            errors("[package]\nname = \"a\"\n[dependencies]\njson = { github = \"x/json\" }\njson = { github = \"y/json\" }\n"),
            ["json: duplicate key 'json'"]
        );
        assert_eq!(
            errors("[package]\nname = \"a\"\n[dependencies]\nfast-json = { github = \"x/json\" }\n"),
            ["fast-json: dependency name 'fast-json' is not an identifier; it is the name 'import' uses"]
        );
        assert_eq!(
            errors("[package]\nname = \"a\"\n[dependencies]\njson = { github = \"x/json\", path = \"y\" }\n"),
            ["path: 'path' is a second source; a dependency comes from one of 'github', 'gitlab', 'codeberg' or 'path'"]
        );
        assert_eq!(
            errors("[package]\nname = \"a\"\n[dependencies]\njson = { github = \"json\" }\n"),
            ["\"json\": 'github' must name a repository as 'owner/name', not 'json'"]
        );
        assert_eq!(
            errors("[package]\nname = \"a\"\n[dependencies]\njson = { github = \"x/json\", tag = \"v1\", branch = \"b\" }\n"),
            ["branch: 'tag' and 'branch' both choose a revision; give one of 'version', 'branch', 'tag' or 'commit'"]
        );
        assert_eq!(errors("[package]\nversion = \"1\"\n"), ["package: '[package]' needs a 'name'"]);
        assert_eq!(
            errors("[package]\nname = \"a\"\n[bulid]\n"),
            ["bulid: unknown table 'bulid'; a pep.toml has '[package]', '[build]', '[dependencies]' and '[fetch]'"]
        );
        assert_eq!(errors("[package]\nname = \"a\"\n[fetch]\nhosts = [\"codeberg\", \"gitub\"]\n"), ["\"gitub\": 'hosts' lists 'github', 'gitlab' or 'codeberg'"]);
        let fetch = parse("[package]\nname = \"a\"\n[fetch]\nhosts = [\"codeberg\", \"github\"]\n").unwrap();
        assert_eq!(fetch.hosts, [Host::Codeberg, Host::GitHub]);
        assert_eq!(
            errors("[package]\nname = \"a\"\n[build]\nentyr = \"x\"\n"),
            ["entyr: unknown key 'entyr' in '[build]'; expected one of 'entry', 'output', 'include', 'link'"]
        );
    }

    #[test]
    fn finds_line_and_column() {
        assert_eq!(line_column("ab\ncd", 4), (2, 2));
        assert_eq!(line_column("ab", 0), (1, 1));
    }
}
