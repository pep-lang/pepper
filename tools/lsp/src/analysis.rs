//! What the server knows about each open document, and how requests read it
//! without waiting for semantic analysis.
//!
//! Sema takes seconds on a program that pulls in much of the runtime, and
//! the editor asks for code actions on every cursor move and hovers on every
//! mouse move. So sema never runs on a request: an edit makes a new
//! [`Analysis`] of the new text, which the server analyzes in the background
//! once typing pauses. Requests read a [`View`]: the current text, its
//! analysis (whose program loads in milliseconds), and the newest analysis
//! whose sema has passed. When the text changed since that one, an
//! [`EditMap`] carries offsets between the two texts, so a name outside the
//! edited region is still answered at once from the old sema model, and one
//! inside it from the current text's parse and linked program.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock, Mutex, OnceLock};
use std::time::SystemTime;

use pepper_parser::ast;
use pepper_parser::diagnostic as diag;
use tower_lsp::lsp_types::{Range, Url};

use crate::{Program, SemaModule, byte_to_lsp_pos, line_col_to_byte, sema_model_of};

/// One version of a document, analyzed: the program rooted at it and that
/// program's sema model. Each is computed once, on first use, and shared by
/// every reader of the same version.
pub struct Analysis {
    pub uri: Url,
    pub text: String,
    /// Counts the document's versions; a later edit has a larger one.
    pub generation: u64,
    program: OnceLock<Result<Program, String>>,
    /// Every file the program read from disk, or found and failed to load,
    /// with its [`file_key`] and its modification time then: the analysis
    /// is stale once one differs.
    read: OnceLock<Vec<(PathBuf, String, Option<SystemTime>)>>,
    sema: OnceLock<Option<Result<SemaModule, diag::Diagnostic>>>,
    /// See [`Analysis::os`].
    os: OnceLock<String>,
    /// The background analysis has finished with it, whatever it found.
    checked: std::sync::atomic::AtomicBool,
}

/// Syntax trees of the files the server loaded, by path, with the text each
/// was parsed from: an analysis loads its program again, but parses only
/// the files that changed (the runtime's never do).
pub struct Parsed(pub Mutex<HashMap<PathBuf, (String, ast::Module)>>);

impl pepper_sema::program::ParseCache for Parsed {
    fn get(&self, path: &Path, source: &str) -> Option<ast::Module> {
        self.0.lock().unwrap().get(path).filter(|(text, _)| text == source).map(|(_, tree)| tree.clone())
    }

    fn put(&self, path: &Path, source: &str, module: &ast::Module) {
        self.0.lock().unwrap().insert(path.to_path_buf(), (source.to_string(), module.clone()));
    }
}

static PARSED: LazyLock<Parsed> = LazyLock::new(|| Parsed(Mutex::new(HashMap::new())));

/// `f()` with `Target(...)` evaluated for `os` (and the build target's
/// architecture).
fn as_target<R>(os: &str, f: impl FnOnce() -> R) -> R {
    use pepper_sema::passes::platform::{host_arch, host_os, with_simulated_host};
    if os == host_os() { f() } else { with_simulated_host(os, &host_arch(), f) }
}

/// The OS to analyze `text` for: the build target's, unless its build
/// leaves out most of the document and none of what it keeps is another
/// OS's to drop, as for a file of Linux-only code on Windows; then the OS
/// whose build leaves out the least of it. A mostly portable file stays on
/// the build target, so the errors its build would report still show.
fn target_os(text: &str) -> String {
    use pepper_sema::passes::platform::{host_arch, host_os, with_simulated_host};
    let host = host_os();
    let Ok(module) = pepper_parser::parser::parse_source("document", text) else { return host };
    let left_out = |os: &str| with_simulated_host(os, &host_arch(), || crate::platforms::inactive_regions(text, &module));
    let at_host = left_out(&host);
    if at_host.is_empty() {
        return host;
    }
    let others: Vec<(&str, Vec<pepper_parser::ast::Span>)> =
        ["windows", "linux", "macos"].into_iter().filter(|os| *os != host).map(|os| (os, left_out(os))).collect();
    // Code the build target keeps and another OS drops is the build
    // target's own: analyze for it.
    let dropped_at_host = |s: &pepper_parser::ast::Span| at_host.iter().any(|h| h.start <= s.start && s.end <= h.end);
    if others.iter().any(|(_, regions)| regions.iter().any(|s| !dropped_at_host(s))) {
        return host;
    }
    // Code measured alike everywhere: trimmed lines, comments and blank
    // lines aside.
    let code_in = |part: &str| -> usize {
        part.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('#')).map(str::len).sum()
    };
    let bytes = |regions: &[pepper_parser::ast::Span]| regions.iter().map(|s| code_in(&text[s.start..s.end])).sum::<usize>();
    let code = code_in(text);
    if bytes(&at_host) * 2 <= code {
        return host;
    }
    others
        .iter()
        .map(|(os, regions)| (bytes(regions), *os))
        .filter(|(n, _)| *n < bytes(&at_host))
        .min()
        .map_or(host, |(_, os)| os.to_string())
}

/// When `path` was last modified; `None` when it cannot be read.
fn modified(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path).and_then(|m| m.modified()).ok()
}

/// A file's identity, the same however a path spells it: the editor writes
/// a Windows drive letter in lowercase (`d:`), and the loader may keep the
/// `\\?\D:` form `canonicalize` returns.
pub fn file_key(path: &Path) -> String {
    pepper_files::imports::path_key(path)
}

impl Analysis {
    pub fn new(uri: Url, text: String, generation: u64) -> Self {
        Self { uri, text, generation, program: OnceLock::new(), read: OnceLock::new(), sema: OnceLock::new(), os: OnceLock::new(), checked: Default::default() }
    }

    /// Whether every file the program read from disk, or failed to load, is
    /// as it was: a saved import, a runtime edit, or a change in another
    /// editor makes it stale. Stats the files, which takes about a
    /// millisecond. A new file that would satisfy a missing import is
    /// noticed only through the client's file watcher.
    pub fn is_current(&self) -> bool {
        self.read.get().is_none_or(|read| read.iter().all(|(path, _, time)| modified(path) == *time))
    }

    /// Whether its program has loaded (or failed to).
    pub fn has_loaded(&self) -> bool {
        self.program.get().is_some()
    }

    /// The program, when it has loaded; never loads it.
    pub fn loaded_program(&self) -> Option<&Program> {
        self.program.get()?.as_ref().ok()
    }

    /// Whether a change to the files `changed` (their [`file_key`]s) may
    /// change this analysis: its program read one of them, or failed to
    /// load it. The document's own text is the editor's, never the file's.
    pub fn affected_by(&self, changed: &HashSet<String>) -> bool {
        // Still loading: it may have read the file before the change.
        let Some(program) = self.program.get() else { return true };
        if program.is_err() {
            return false;
        }
        self.read.get().is_some_and(|read| read.iter().any(|(_, key, _)| changed.contains(key)))
    }

    /// Every file of the program rooted at the document, loaded and linked
    /// as the driver does: the document itself (possibly unsaved) first,
    /// then the files its imports reach, then the runtime prelude.
    /// Unreadable or unparseable imported files are skipped; a parse error
    /// in the document is returned.
    pub fn program(&self) -> Result<&Program, &String> {
        self.program
            .get_or_init(|| as_target(self.os(), || {
                let path = self.uri.to_file_path().map_err(|_| "not a file uri".to_string())?;
                let root = pepper_sema::program::Root { name: self.uri.to_string(), source: self.text.clone(), path };
                let setup = pepper_sema::program::Setup {
                    mode: pepper_sema::program::Mode::Lenient,
                    parsed: Some(&*PARSED),
                    ..Default::default()
                };
                // File times come from a coarser clock than `now`, up to
                // tens of milliseconds behind: start the window earlier.
                let started = SystemTime::now() - std::time::Duration::from_millis(100);
                let program = pepper_sema::program::load_program(root, &setup)?;
                // Every file read, and every file that did not load (which
                // changes time once it is fixed), with its time now.
                let paths = program.files[1..].iter().map(|f| PathBuf::from(&f.name)).chain(program.failed.iter().cloned());
                let stamped: Vec<(PathBuf, Option<SystemTime>)> = paths.map(|path| (path.clone(), modified(&path))).collect();
                // A file modified between the load's start and the stamping
                // may have been read before or after the change: it gets no
                // time, so the analysis is stale at once. (Rereading every
                // file to check doubled the load.) A time in the future,
                // from another clock, is kept: an edit would change it.
                let ended = SystemTime::now();
                let read = stamped
                    .into_iter()
                    .map(|(path, time)| {
                        let key = file_key(&path);
                        (path, key, time.filter(|t| !(started..=ended).contains(t)))
                    })
                    .collect();
                let _ = self.read.set(read);
                Ok(program)
            }))
            .as_ref()
    }

    /// The OS the document is analyzed for: the build target's, unless more
    /// of the document is code for another (a file of `[Target(OS(Linux))]`
    /// declarations seen on Windows), so that its names resolve. What the
    /// editor dims still follows the build target.
    pub fn os(&self) -> &str {
        self.os.get_or_init(|| target_os(&self.text))
    }

    /// The program's sema model, or its semantic error; `None` when the
    /// program did not load. Runs sema on first use, which takes seconds:
    /// only the background analysis calls this.
    pub fn sema(&self) -> Option<&Result<SemaModule, diag::Diagnostic>> {
        self.sema.get_or_init(|| self.program().ok().map(|p| as_target(self.os(), || sema_model_of(p)))).as_ref()
    }

    /// Note that the background analysis has finished with it.
    pub fn mark_checked(&self) {
        self.checked.store(true, std::sync::atomic::Ordering::Relaxed);
    }

    /// Whether the background analysis has finished with it: its text
    /// passed ([`Analysis::sema_model`]), or did not parse, load or check.
    pub fn is_checked(&self) -> bool {
        self.checked.load(std::sync::atomic::Ordering::Relaxed)
    }

    /// What [`Analysis::sema`] found, when it has already run.
    pub fn sema_if_done(&self) -> Option<&Result<SemaModule, diag::Diagnostic>> {
        self.sema.get()?.as_ref()
    }

    /// The sema model, when sema has run and passed.
    pub fn sema_model(&self) -> Option<&SemaModule> {
        self.sema_if_done()?.as_ref().ok()
    }
}

/// The one region where a later text of a document differs from an earlier
/// one, found as their common prefix (whole lines) and suffix:
/// `old[prefix..old_end]` became `new[prefix..new_end]`. Several edits in
/// different places make one region spanning them all, which only maps
/// fewer offsets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EditMap {
    prefix: usize,
    old_end: usize,
    new_end: usize,
    /// The edit ends at the end of a line in both texts, so the text after
    /// it starts a line.
    ends_line: bool,
}

impl EditMap {
    pub fn between(old: &str, new: &str) -> Self {
        let common = old.bytes().zip(new.bytes()).take_while(|(a, b)| a == b).count();
        // From the start of the line the edit is on: a line inserted after
        // `var a;` into `var b;` would otherwise share `var ` with it, and
        // the edit would land inside `b`.
        let prefix = old.as_bytes()[..common].iter().rposition(|&b| b == b'\n').map_or(0, |i| i + 1);
        let limit = old.len().min(new.len()) - prefix;
        let mut suffix = old.bytes().rev().zip(new.bytes().rev()).take(limit).take_while(|(a, b)| a == b).count();
        while !old.is_char_boundary(old.len() - suffix) {
            suffix -= 1;
        }
        let (old_end, new_end) = (old.len() - suffix, new.len() - suffix);
        let line_start = |text: &str, at: usize| at == 0 || text.as_bytes()[at - 1] == b'\n';
        Self { prefix, old_end, new_end, ends_line: line_start(old, old_end) && line_start(new, new_end) }
    }

    /// `offset` in the new text, carried to the old one, when its line is
    /// wholly outside the edit: what a name means depends on the rest of its
    /// expression (`p.x` edited to `q.x` changes what `x` is), which rarely
    /// leaves the line.
    pub fn to_old(&self, new: &str, offset: usize) -> Option<usize> {
        let offset = offset.min(new.len());
        // `prefix` starts a line, so an offset before it is on an earlier one.
        if offset < self.prefix {
            Some(offset)
        } else if offset >= self.new_end
            && (self.ends_line || new.as_bytes()[self.new_end..offset].contains(&b'\n'))
        {
            Some(offset - self.new_end + self.old_end)
        } else {
            None
        }
    }

    /// The range `range` of the old text `old` in the new text `new`, when
    /// it lies outside the edit.
    pub fn range_to_new(&self, old: &str, new: &str, range: Range) -> Option<Range> {
        let start = line_col_to_byte(old, range.start.line, range.start.character);
        let end = line_col_to_byte(old, range.end.line, range.end.character);
        // After the edit first: an empty range where text was inserted (a
        // hint at the start of a line a new line went above) moves with it.
        let (start, end) = if start >= self.old_end {
            (start - self.old_end + self.new_end, end - self.old_end + self.new_end)
        } else if end <= self.prefix {
            (start, end)
        } else {
            return None;
        };
        Some(Range::new(byte_to_lsp_pos(new, start), byte_to_lsp_pos(new, end)))
    }

    /// [`EditMap::range_to_new`] for something that depends on its whole
    /// line, as an answer computed at the old text does: only a range on a
    /// line the edit left alone.
    pub fn line_range_to_new(&self, old: &str, new: &str, range: Range) -> Option<Range> {
        let start = line_col_to_byte(old, range.start.line, range.start.character);
        let end = line_col_to_byte(old, range.end.line, range.end.character);
        // `prefix` starts a line, so a range ending before it is on earlier
        // ones; one after the edit must start on a later line than its end.
        let after = start >= self.old_end && (self.ends_line || old.as_bytes()[self.old_end..start].contains(&b'\n'));
        if end < self.prefix || after { self.range_to_new(old, new, range) } else { None }
    }
}

/// What a request reads about a document: its current text and analysis,
/// and the newest analysis whose sema passed (`ready`), with the edits since
/// when its text is not the current one.
pub struct View {
    pub latest: Arc<Analysis>,
    pub ready: Option<(Arc<Analysis>, Option<EditMap>)>,
}

impl View {
    pub fn text(&self) -> &str {
        &self.latest.text
    }
}

/// An open document.
struct Open {
    latest: Arc<Analysis>,
    ready: Option<Arc<Analysis>>,
    /// The generation of the last renewal that found the files behind the
    /// document changed: an older analysis passing later is out of date.
    renewed: u64,
}

/// Every open document, keyed by URI string.
#[derive(Default)]
pub struct Documents {
    open: Mutex<HashMap<String, Open>>,
    generations: Mutex<u64>,
    /// Held by the background analysis that is running, so that one runs
    /// at a time.
    pub running: tokio::sync::Mutex<()>,
    /// The client can be asked to fetch inlay hints again
    /// (`workspace/inlayHint/refresh`).
    pub refreshes_hints: std::sync::atomic::AtomicBool,
}

impl Documents {
    /// Record `text` as the document's contents, opening it if need be, and
    /// return the analysis of that text for the caller to schedule.
    pub fn set(&self, uri: &Url, text: String) -> Arc<Analysis> {
        // Numbered under the lock, so a renewal cannot slip a later number
        // in before this text lands.
        let mut open = self.open.lock().unwrap();
        let analysis = Arc::new(Analysis::new(uri.clone(), text, self.next_generation()));
        match open.get_mut(uri.as_str()) {
            Some(document) => document.latest = analysis.clone(),
            None => {
                open.insert(uri.as_str().to_string(), Open { latest: analysis.clone(), ready: None, renewed: 0 });
            }
        }
        analysis
    }

    fn next_generation(&self) -> u64 {
        let mut generations = self.generations.lock().unwrap();
        *generations += 1;
        *generations
    }

    /// A fresh analysis of `stale`'s text in its place, when it is still its
    /// document's current one: an edit or a close since wins. When the files
    /// behind it changed (`changed`), the passed analysis no longer answers,
    /// nor does one older than the fresh one that passes later.
    fn renew(open: &mut HashMap<String, Open>, stale: &Analysis, generation: u64, changed: bool) -> Option<Arc<Analysis>> {
        let document = open.get_mut(stale.uri.as_str()).filter(|d| d.latest.generation == stale.generation)?;
        document.latest = Arc::new(Analysis::new(stale.uri.clone(), stale.text.clone(), generation));
        if changed {
            document.ready = None;
            document.renewed = generation;
        }
        Some(document.latest.clone())
    }

    /// When a file the document's current analysis read has changed on
    /// disk, a fresh analysis of the same text, for the caller to schedule.
    pub fn refresh(&self, uri: &Url) -> Option<Arc<Analysis>> {
        let latest = self.latest(uri)?;
        if latest.is_current() {
            return None;
        }
        let mut open = self.open.lock().unwrap();
        let generation = self.next_generation();
        Self::renew(&mut open, &latest, generation, true)
    }

    /// Replace the analysis of each open document that a change to the
    /// files `changed` may change ([`Analysis::affected_by`]), or of every
    /// one when a file was created or deleted (`added`), which can change
    /// what an import resolves to. Returns the new analyses, for the caller
    /// to schedule. A document whose program was still loading is renewed
    /// in case it read the file first, but keeps its passed analysis, which
    /// [`Analysis::is_current`] judges on its own.
    pub fn forget(&self, changed: &[PathBuf], added: bool) -> Vec<Arc<Analysis>> {
        // Resolved once, before taking the lock every request needs.
        let changed: HashSet<String> = changed.iter().map(|path| file_key(path)).collect();
        let mut open = self.open.lock().unwrap();
        let stale: Vec<(Arc<Analysis>, bool)> = open
            .values()
            .filter(|d| added || d.latest.affected_by(&changed))
            .map(|d| (d.latest.clone(), added || d.latest.has_loaded()))
            .collect();
        stale
            .iter()
            .filter_map(|(analysis, changed)| {
                let generation = self.next_generation();
                Self::renew(&mut open, analysis, generation, *changed)
            })
            .collect()
    }

    pub fn close(&self, uri: &Url) {
        self.open.lock().unwrap().remove(uri.as_str());
    }

    pub fn text(&self, uri: &Url) -> Option<String> {
        Some(self.latest(uri)?.text.clone())
    }

    /// The analysis of the document's current text.
    pub fn latest(&self, uri: &Url) -> Option<Arc<Analysis>> {
        Some(self.open.lock().unwrap().get(uri.as_str())?.latest.clone())
    }

    /// Whether `analysis` is of the document's current text.
    pub fn is_latest(&self, analysis: &Analysis) -> bool {
        self.latest(&analysis.uri).is_some_and(|latest| latest.generation == analysis.generation)
    }

    /// Note that `analysis` has run sema: when it passed, requests answer
    /// from it until a newer one passes.
    pub fn finished(&self, analysis: &Arc<Analysis>) {
        if analysis.sema_model().is_none() {
            return;
        }
        let mut open = self.open.lock().unwrap();
        if let Some(document) = open.get_mut(analysis.uri.as_str())
            && analysis.generation >= document.renewed
            && document.ready.as_ref().is_none_or(|ready| ready.generation < analysis.generation)
        {
            document.ready = Some(analysis.clone());
        }
    }

    pub fn view(&self, uri: &Url) -> Option<View> {
        let open = self.open.lock().unwrap();
        let document = open.get(uri.as_str())?;
        let ready = document.ready.clone().map(|ready| {
            let edits = (ready.text != document.latest.text).then(|| EditMap::between(&ready.text, &document.latest.text));
            (ready, edits)
        });
        Some(View { latest: document.latest.clone(), ready })
    }
}
