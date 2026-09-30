//! Compiler diagnostics, rendered in clang's format:
//!
//! ```text
//! main.pep:2:13: error: expected expression
//!     2 |     var x = ;
//!       |             ^
//! main.pep:1:1: note: in this function
//!     1 | main(): int {
//!       | ^~~~
//! ```
//!
//! A diagnostic may carry suggested [`Fix`]es: edits a tool can apply for
//! the user. The renderer shows an edit on the diagnostic's own line under
//! the caret, as clang does with fix-it hints, and the language server
//! offers each fix as a quick fix:
//!
//! ```text
//! main.pep:3:5: warning: `new` is deprecated; constructors are spelled `construct` [deprecated]
//!     3 |     new(this.x = 1) {}
//!       |     ^~~
//!       |     construct
//! ```
//!
//! Deprecated syntax is reported through [`Diagnostic::deprecated`], always
//! with the fix that migrates the code. A use of a declaration marked
//! `[Deprecated("message")]` is reported through
//! [`Diagnostic::deprecated_declaration`], with a fix when the attribute
//! names a replacement:
//!
//! ```text
//! main.pep:4:15: warning: 'clone' is deprecated: use 'copy' instead [deprecated]
//!     4 |     var b = a.clone();
//!       |               ^~~~~
//!       |               copy
//! ```
//!
//! A diagnostic points into a file through a [`Loc`]: a [`FileId`] plus a
//! byte [`Span`]. Whoever loaded the files owns the [`SourceMap`] that turns
//! the id back into a name and text; the parser and sema only ever see ids.
//!
//! Rendering spells private names as the user wrote them (see
//! [`crate::namespace`]).

use crate::ast::Span;
use crate::namespace::demangle;
use std::fmt::Write;

/// Index of a file in the [`SourceMap`] of a compile.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct FileId(pub u32);

/// A source location: a byte span in one file.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct Loc {
    pub file: FileId,
    pub span: Span,
}

impl Loc {
    /// No location: nodes synthesized by the compiler rather than parsed.
    pub const NONE: Loc = Loc { file: FileId(u32::MAX), span: Span { start: 0, end: 0 } };

    pub fn new(file: FileId, span: Span) -> Self {
        Loc { file, span }
    }

    pub fn is_none(&self) -> bool {
        self.file == Loc::NONE.file
    }

    /// `Some(self)` unless this is [`Loc::NONE`].
    pub fn known(self) -> Option<Loc> {
        if self.is_none() { None } else { Some(self) }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
    Note,
}

impl Severity {
    fn label(self) -> &'static str {
        match self {
            Severity::Error => "error",
            Severity::Warning => "warning",
            Severity::Note => "note",
        }
    }
}

/// Replace the text at `loc` with `replacement` (an empty span inserts).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Edit {
    pub loc: Loc,
    pub replacement: String,
}

/// A suggested fix: what it does, in the imperative ("replace `new` with
/// `construct`"), and the edits that do it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fix {
    pub message: String,
    pub edits: Vec<Edit>,
}

impl Fix {
    /// A fix that replaces the text at `loc` with `replacement`.
    pub fn replace(message: impl Into<String>, loc: Loc, replacement: impl Into<String>) -> Self {
        Fix { message: message.into(), edits: vec![Edit { loc, replacement: replacement.into() }] }
    }
}

/// The code of every deprecation warning.
pub const DEPRECATED: &str = "deprecated";

/// One diagnostic: a message at an optional location, followed by notes
/// (each a diagnostic of its own, usually pointing somewhere else) and any
/// suggested fixes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    pub severity: Severity,
    pub message: String,
    pub loc: Option<Loc>,
    pub notes: Vec<Diagnostic>,
    /// Which class of diagnostic this is (e.g. [`DEPRECATED`]), shown after
    /// the message as `[code]`.
    pub code: Option<&'static str>,
    pub fixes: Vec<Fix>,
}

impl Diagnostic {
    fn with_severity(severity: Severity, message: impl Into<String>) -> Self {
        Diagnostic { severity, message: message.into(), loc: None, notes: vec![], code: None, fixes: vec![] }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self::with_severity(Severity::Error, message)
    }

    pub fn warning(message: impl Into<String>) -> Self {
        Self::with_severity(Severity::Warning, message)
    }

    /// A warning that `what` (as written in the source, e.g. "`new`") at
    /// `loc` is deprecated. `instead` says what replaces it, and `fix`
    /// migrates the code; a deprecation always comes with one.
    pub fn deprecated(what: &str, instead: &str, loc: Loc, fix: Fix) -> Self {
        let mut d = Self::warning(format!("{what} is deprecated; {instead}")).at(loc).with_fix(fix);
        d.code = Some(DEPRECATED);
        d
    }

    /// A warning that the declaration `name`, used at `loc`, is marked
    /// `[Deprecated(message)]`: `'name' is deprecated: message`, or just
    /// `'name' is deprecated` when the message is empty. The caller attaches
    /// a fix when the attribute names a replacement.
    pub fn deprecated_declaration(name: &str, message: &str, loc: Loc) -> Self {
        let text = if message.is_empty() {
            format!("'{name}' is deprecated")
        } else {
            format!("'{name}' is deprecated: {message}")
        };
        let mut d = Self::warning(text).at(loc);
        d.code = Some(DEPRECATED);
        d
    }

    /// Attach a suggested fix.
    pub fn with_fix(mut self, fix: Fix) -> Self {
        self.fixes.push(fix);
        self
    }

    /// Place the diagnostic at `loc` (ignored when it is [`Loc::NONE`]).
    pub fn at(mut self, loc: Loc) -> Self {
        self.loc = loc.known();
        self
    }

    fn at_opt(mut self, loc: Option<Loc>) -> Self {
        self.loc = loc.and_then(Loc::known);
        self
    }

    /// Place the diagnostic at `loc` unless it already has a location.
    pub fn or_at(mut self, loc: Loc) -> Self {
        if self.loc.is_none() {
            self.loc = loc.known();
        }
        self
    }

    /// Append a note, optionally pointing at `loc`.
    pub fn with_note(mut self, message: impl Into<String>, loc: Option<Loc>) -> Self {
        self.notes.push(Diagnostic::with_severity(Severity::Note, message).at_opt(loc));
        self
    }

    /// Render against `sources`: a header line, the source line with a caret
    /// and underline under the span, then each note the same way.
    pub fn render(&self, sources: &dyn Sources) -> String {
        let mut out = String::new();
        self.render_into(sources, &mut out);
        out.truncate(out.trim_end_matches('\n').len());
        out
    }

    /// Render a diagnostic whose locations all refer to one file.
    pub fn render_in(&self, name: &str, text: &str) -> String {
        self.render(&OneFile { name, text })
    }

    fn render_into(&self, sources: &dyn Sources, out: &mut String) {
        match self.loc.and_then(|loc| sources.get(loc.file).map(|(n, t)| (loc, n, t))) {
            Some((loc, name, text)) => {
                let p = loc.span.start_position(text);
                let _ = writeln!(out, "{}:{}:{}: {}: {}{}", name, p.line + 1, p.col + 1, self.severity.label(), demangle(&self.message), self.code_suffix());
                snippet(text, loc.span, self.fix_on_line(loc, text), out);
            }
            None => {
                let _ = writeln!(out, "{}: {}{}", self.severity.label(), demangle(&self.message), self.code_suffix());
            }
        }
        for note in &self.notes {
            note.render_into(sources, out);
        }
    }
}

impl Diagnostic {
    fn code_suffix(&self) -> String {
        self.code.map(|c| format!(" [{c}]")).unwrap_or_default()
    }

    /// The first fix's edit, when the fix is a single edit on the same line
    /// as `loc` (the one line the snippet shows).
    fn fix_on_line<'a>(&'a self, loc: Loc, text: &str) -> Option<&'a Edit> {
        let fix = self.fixes.first()?;
        let [edit] = fix.edits.as_slice() else { return None };
        let line_of = |offset: usize| text[..offset.min(text.len())].bytes().filter(|&b| b == b'\n').count();
        let same_line = edit.loc.file == loc.file
            && line_of(edit.loc.span.start) == line_of(loc.span.start)
            && line_of(edit.loc.span.end) == line_of(loc.span.start)
            && !edit.replacement.contains('\n');
        same_line.then_some(edit)
    }
}

impl std::fmt::Display for Diagnostic {
    /// The message alone, without location or notes.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&demangle(&self.message))
    }
}

/// Width tabs expand to in snippets, so the caret lines up with the text.
const TAB_WIDTH: usize = 4;

/// The source line holding `span.start`, then a caret under the start and
/// `~` under the rest of the span (clipped to that line), then `fix`'s
/// replacement text under the text it replaces.
fn snippet(text: &str, span: Span, fix: Option<&Edit>, out: &mut String) {
    let start = span.start.min(text.len());
    let line_start = text[..start].rfind('\n').map_or(0, |i| i + 1);
    let line_end = text[start..].find('\n').map_or(text.len(), |i| start + i);
    let line = text[line_start..line_end].trim_end_matches('\r');
    let line_no = text[..line_start].bytes().filter(|&b| b == b'\n').count() + 1;
    // A span starting on a CRLF's '\n' lies past the line once its '\r' is
    // trimmed; the caret then goes at the line's end.
    let end = span.end.clamp(start, (line_start + line.len()).max(start));

    // Expand tabs, tracking the display columns of the span's ends.
    let mut shown = String::new();
    let (mut caret_col, mut end_col, mut fix_col) = (None, None, None);
    for (i, c) in line.char_indices() {
        let at = line_start + i;
        if at == start {
            caret_col = Some(shown.chars().count());
        }
        if fix.is_some_and(|e| e.loc.span.start == at) {
            fix_col = Some(shown.chars().count());
        }
        if at == end {
            end_col = Some(shown.chars().count());
        }
        if c == '\t' {
            let width = TAB_WIDTH - shown.chars().count() % TAB_WIDTH;
            shown.extend(std::iter::repeat_n(' ', width));
        } else {
            shown.push(c);
        }
    }
    let width = shown.chars().count();
    let caret_col = caret_col.unwrap_or(width);
    let end_col = end_col.unwrap_or(width).max(caret_col + 1);

    let gutter = line_no.to_string().len().max(5);
    let _ = writeln!(out, "{:>gutter$} | {}", line_no, shown);
    let _ = writeln!(out, "{:>gutter$} | {}^{}", "", " ".repeat(caret_col), "~".repeat(end_col - caret_col - 1));
    if let Some(edit) = fix.filter(|e| !e.replacement.is_empty()) {
        let fix_col = fix_col.unwrap_or(width);
        let _ = writeln!(out, "{:>gutter$} | {}{}", "", " ".repeat(fix_col), edit.replacement);
    }
}

/// Name and text of each file a diagnostic may point into.
pub trait Sources {
    fn get(&self, file: FileId) -> Option<(&str, &str)>;
}

/// A single file, whatever id a location names (the parser only ever sees
/// one file, so its locations use the default id).
struct OneFile<'a> {
    name: &'a str,
    text: &'a str,
}

impl Sources for OneFile<'_> {
    fn get(&self, _: FileId) -> Option<(&str, &str)> {
        Some((self.name, self.text))
    }
}

/// Every file of a compile, indexed by [`FileId`].
#[derive(Debug, Clone, Default)]
pub struct SourceMap {
    files: Vec<(String, String)>,
}

impl SourceMap {
    /// Register a file, returning the id its locations should carry.
    pub fn add(&mut self, name: impl Into<String>, text: impl Into<String>) -> FileId {
        self.files.push((name.into(), text.into()));
        FileId(self.files.len() as u32 - 1)
    }

    /// Render `diagnostic` against this map.
    pub fn render(&self, diagnostic: &Diagnostic) -> String {
        diagnostic.render(self)
    }
}

impl Sources for SourceMap {
    fn get(&self, file: FileId) -> Option<(&str, &str)> {
        self.files.get(file.0 as usize).map(|(n, t)| (n.as_str(), t.as_str()))
    }
}

// ── Terminal colors ──────────────────────────────────────────────────────────

const RESET: &str = "\x1b[0m";
const BOLD: &str = "\x1b[1m";
const RED: &str = "\x1b[1;31m";
const MAGENTA: &str = "\x1b[1;35m";
const CYAN: &str = "\x1b[1;36m";
const GREEN: &str = "\x1b[1;32m";

/// Color rendered diagnostics the way clang does on a terminal: bold
/// location and message, a red `error:`, a green caret and underline.
/// Works on the rendered text, so errors can travel as plain strings and
/// only the CLI decides whether to color them.
pub fn colorize(rendered: &str) -> String {
    let mut out = String::new();
    for line in rendered.lines() {
        if let Some((gutter, rest)) = line.split_once(" | ") {
            // The caret line and any fix-it line under it.
            if gutter.trim().is_empty() {
                let _ = writeln!(out, "{} | {}{}{}", gutter, GREEN, rest, RESET);
            } else {
                let _ = writeln!(out, "{}", line);
            }
            continue;
        }
        let mut colored = false;
        for (label, color) in [("error: ", RED), ("warning: ", MAGENTA), ("note: ", CYAN)] {
            if let Some(i) = header_label(line, label) {
                let (loc, rest) = line.split_at(i);
                let message = &rest[label.len()..];
                let _ = writeln!(out, "{BOLD}{loc}{color}{label}{RESET}{BOLD}{message}{RESET}");
                colored = true;
                break;
            }
        }
        if !colored {
            let _ = writeln!(out, "{}", line);
        }
    }
    out.truncate(out.trim_end_matches('\n').len());
    out
}

/// Whether `text` is already a rendered diagnostic (its first line is a
/// `[name:line:col: ]severity: message` header), as opposed to a bare message.
pub fn is_rendered(text: &str) -> bool {
    let first = text.lines().next().unwrap_or("");
    ["error: ", "warning: ", "note: "].iter().any(|label| header_label(first, label).is_some())
}

/// Byte index of `label` in a header line: at the start, or right after a
/// `name:line:col: ` prefix.
fn header_label(line: &str, label: &str) -> Option<usize> {
    if line.starts_with(label) {
        return Some(0);
    }
    let i = line.find(&format!(": {label}"))? + 2;
    let mut fields = line[..i - 2].rsplitn(3, ':');
    let col = fields.next()?;
    let row = fields.next()?;
    (col.parse::<usize>().is_ok() && row.parse::<usize>().is_ok()).then_some(i)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(file: u32, start: usize, end: usize) -> Loc {
        Loc::new(FileId(file), Span { start, end })
    }

    #[test]
    fn caret_and_underline() {
        let text = "main(): int {\n    return nope + 1;\n}\n";
        let start = text.find("nope").unwrap();
        let d = Diagnostic::error("use of undeclared identifier 'nope'").at(at(0, start, start + 4));
        assert_eq!(
            d.render_in("t.pep", text),
            "t.pep:2:12: error: use of undeclared identifier 'nope'\n\
             \x20   2 |     return nope + 1;\n\
             \x20     |            ^~~~"
        );
    }

    #[test]
    fn empty_span_is_a_single_caret() {
        let text = "var x = ;";
        let d = Diagnostic::error("expected expression").at(at(0, 8, 8));
        assert_eq!(d.render_in("t.pep", text), "t.pep:1:9: error: expected expression\n    1 | var x = ;\n      |         ^");
    }

    #[test]
    fn end_of_file_points_past_the_last_line() {
        let text = "main() {\n";
        let d = Diagnostic::error("expected '}'").at(at(0, text.len(), text.len()));
        assert_eq!(d.render_in("t.pep", text), "t.pep:2:1: error: expected '}'\n    2 | \n      | ^");
    }

    #[test]
    fn span_on_a_crlf_line_break_points_at_the_line_end() {
        let text = "var x = 1\r\nvar y = 2;";
        let d = Diagnostic::error("expected ';'").at(at(0, 10, 11));
        assert!(d.render_in("t.pep", text).ends_with("    1 | var x = 1\n      |          ^"));
    }

    #[test]
    fn tabs_keep_the_caret_aligned() {
        let text = "\tx\ty;";
        let d = Diagnostic::error("m").at(at(0, 3, 4));
        assert_eq!(d.render_in("t.pep", text), "t.pep:1:4: error: m\n    1 |     x   y;\n      |         ^");
    }

    #[test]
    fn multi_line_span_is_clipped_to_its_first_line() {
        let text = "f(a,\n  b)";
        let d = Diagnostic::error("m").at(at(0, 0, text.len()));
        assert_eq!(d.render_in("t.pep", text), "t.pep:1:1: error: m\n    1 | f(a,\n      | ^~~~");
    }

    #[test]
    fn notes_render_in_their_own_files() {
        let mut map = SourceMap::default();
        let a = map.add("a.pep", "helper(): int { return 1; }\n");
        let b = map.add("b.pep", "main(): int { return helper(); }\n");
        let d = Diagnostic::error("'helper' is private to a.pep")
            .at(Loc::new(b, Span { start: 21, end: 27 }))
            .with_note("declared here", Some(Loc::new(a, Span { start: 0, end: 6 })));
        assert_eq!(
            map.render(&d),
            "b.pep:1:22: error: 'helper' is private to a.pep\n\
             \x20   1 | main(): int { return helper(); }\n\
             \x20     |                      ^~~~~~\n\
             a.pep:1:1: note: declared here\n\
             \x20   1 | helper(): int { return 1; }\n\
             \x20     | ^~~~~~"
        );
    }

    #[test]
    fn unlocated_diagnostic_has_no_position() {
        assert_eq!(Diagnostic::error("no main").render(&SourceMap::default()), "error: no main");
        assert_eq!(Diagnostic::error("m").at(Loc::NONE).render_in("t.pep", ""), "error: m");
    }

    #[test]
    fn colorize_marks_header_and_caret() {
        let plain = "C:\\x:y.pep:2:3: error: bad: thing\n   2 | ab\n     |  ^\nnote: see";
        let colored = colorize(plain);
        assert!(colored.starts_with("\x1b[1mC:\\x:y.pep:2:3: \x1b[1;31merror: \x1b[0m\x1b[1mbad: thing\x1b[0m\n"), "{colored:?}");
        assert!(colored.contains("     | \x1b[1;32m ^\x1b[0m"), "{colored:?}");
        assert!(colored.ends_with("\x1b[1;36mnote: \x1b[0m\x1b[1msee\x1b[0m"), "{colored:?}");
    }
}
