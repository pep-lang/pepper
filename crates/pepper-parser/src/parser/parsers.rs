//! Full Pepper grammar implemented with winnow.
//!
//! Precedence (low → high):
//!   assignment  →  ternary  →  logical_or  →  logical_and  →
//!   bit_or      →  bit_and   →  equality    →  relational   →
//!   shift       →  add       →  mul         →  prefix       →
//!   unary       →  pow       →  postfix     →  atom

use crate::ast::*;
use crate::diagnostic::{Diagnostic, FileId, Fix, Loc};
use winnow::error::ErrMode;


// Error type for &str input (lifetime elided via associated type)
pub type Result<T> = std::result::Result<T, ErrMode<&'static str>>;

fn bt(_input: &mut &str) -> ErrMode<&'static str> {
    ErrMode::Backtrack("parse error")
}
fn cut(_input: &mut &str) -> ErrMode<&'static str> {
    ErrMode::Cut("parse error")
}
/// A hard failure that records `what` as expected at `input` (see
/// [`expected`]).
fn cut_expecting(input: &mut &str, what: &'static str) -> ErrMode<&'static str> {
    expected(input, what);
    cut(input)
}

// ── Source-location tracking ─────────────────────────────────────────────────

// Length of the source currently being parsed. Set by `parse_source` (and the
// test helpers) for the duration of one parse; `pos()` turns any remaining
// slice into a byte offset in that source.
thread_local! {
    static SRC_LEN: std::cell::Cell<Option<usize>> = const { std::cell::Cell::new(None) };
    /// Furthest byte offset reached during the current parse. PEG backtracking
    /// rewinds `input`, so the remaining-slice offset alone underreports where
    /// parsing stopped; this records the deepest point any rule reached.
    static MAX_POS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    /// Module qualifiers the file's imports have bound so far (`m` of
    /// `import m`, `q` of `import x as q`). `q.Box<int>()` is a generic
    /// construction only for these; otherwise `a.b < c, d > (e)` stays two
    /// comparisons.
    static QUALIFIERS: std::cell::RefCell<std::collections::HashSet<String>> = std::cell::RefCell::new(Default::default());
    /// Set while an expression is probed as a generic type literal.
    static EXPRESSION_PROBE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
    /// Warnings found so far in the current parse; `parse_module` moves them
    /// into the module.
    static WARNINGS: std::cell::RefCell<Vec<Diagnostic>> = const { std::cell::RefCell::new(vec![]) };
    /// A hard error that is not an unmet expectation (an out-of-range
    /// literal); it wins over the furthest expectation when the parse fails.
    static ERROR: std::cell::RefCell<Option<Diagnostic>> = const { std::cell::RefCell::new(None) };
}

/// Fail the parse with `message` at `span`. The first such error is the one
/// reported.
fn error_at(span: Span, message: String) -> ErrMode<&'static str> {
    fail_with(Diagnostic::error(message).at(Loc::new(FileId::default(), span)))
}

/// Fail the parse with `diagnostic` (see [`error_at`]).
fn fail_with(diagnostic: Diagnostic) -> ErrMode<&'static str> {
    ERROR.with(|e| {
        let mut e = e.borrow_mut();
        if e.is_none() {
            *e = Some(diagnostic);
        }
    });
    ErrMode::Cut("parse error")
}

/// The hard error recorded by the current parse, if any.
pub(crate) fn take_error() -> Option<Diagnostic> {
    ERROR.with(|e| e.borrow_mut().take())
}

/// Record a warning. Backtracking can parse the same text twice, so a
/// warning already recorded at the same location is dropped.
fn warn(diagnostic: Diagnostic) {
    WARNINGS.with(|w| {
        let mut w = w.borrow_mut();
        if !w.iter().any(|d| d.loc == diagnostic.loc && d.message == diagnostic.message) {
            w.push(diagnostic);
        }
    });
}

/// Report deprecated syntax at `span`: `what` is how the source spells it,
/// `instead` explains its replacement, and the fix rewrites the span to
/// `replacement`.
fn deprecated_syntax(span: Span, what: &str, instead: &str, replacement: &str) {
    let loc = Loc::new(FileId::default(), span);
    let fix = Fix::replace(format!("Replace {what} with `{replacement}`"), loc, replacement);
    warn(Diagnostic::deprecated(what, instead, loc, fix));
}

/// Parse a type where an expression could also start (a generic literal
/// probe, a `Type name` declaration): qualified names are limited to imported
/// qualifiers (see `qualified_tail`).
fn probe_type_name(input: &mut &str) -> Result<TypeName> {
    let outer = EXPRESSION_PROBE.with(|p| p.replace(true));
    let result = type_name(input);
    EXPRESSION_PROBE.with(|p| p.set(outer));
    result
}

/// Byte offset of `input`'s start within the tracked source, also recording it
/// as the furthest point reached so far.
fn pos(input: &str) -> usize {
    let p = SRC_LEN.with(|l| l.get().unwrap_or(0).saturating_sub(input.len()));
    MAX_POS.with(|m| {
        if p > m.get() {
            m.set(p);
        }
    });
    p
}


/// RAII guard that tracks the length of the source being parsed, so `pos()`
/// can convert remaining input slices into byte offsets. Restores the previous
/// value on drop (parsing is not reentrant per thread).
pub(crate) struct SourceGuard(Option<usize>);

impl SourceGuard {
    fn set(len: usize) -> Self {
        let prev = SRC_LEN.with(|l| l.replace(Some(len)));
        MAX_POS.with(|m| m.set(0));
        EXPECTATION.with(|e| *e.borrow_mut() = None);
        QUALIFIERS.with(|q| q.borrow_mut().clear());
        WARNINGS.with(|w| w.borrow_mut().clear());
        ERROR.with(|e| *e.borrow_mut() = None);
        SourceGuard(prev)
    }
}

impl Drop for SourceGuard {
    fn drop(&mut self) {
        SRC_LEN.with(|l| l.set(self.0));
    }
}

/// Begin tracking a source of `len` bytes for the duration of one parse.
pub(crate) fn track_source(len: usize) -> SourceGuard {
    SourceGuard::set(len)
}

/// Furthest byte offset reached during the current tracked parse — the best
/// available position to report a parse error, since PEG backtracking rewinds
/// the remaining input.
pub(crate) fn max_pos() -> usize {
    MAX_POS.with(|m| m.get())
}

// ── Parse-error expectations ─────────────────────────────────────────────────
//
// What the grammar wanted at the furthest point a rule failed, so a parse
// error can say `expected ')'` instead of just `parse error`. Rules record an
// expectation where they give up; only the furthest offset's survive.

/// The expectations recorded at the furthest failure of the current parse.
#[derive(Debug, Clone, Default)]
pub(crate) struct Expectation {
    /// Byte offset of the failure, after skipping whitespace and comments.
    pub offset: usize,
    /// What would have been accepted there, e.g. `')'` or `expression`.
    pub expected: Vec<&'static str>,
    /// A related location, e.g. the `{` an expected `}` would close.
    pub note: Option<(usize, &'static str)>,
}

thread_local! {
    static EXPECTATION: std::cell::RefCell<Option<Expectation>> = const { std::cell::RefCell::new(None) };
}

/// Record that `what` was expected at the start of `input`.
fn expected(input: &str, what: &'static str) {
    expected_with_note(input, what, None);
}

/// As [`expected`], with a note at a related byte offset.
fn expected_with_note(input: &str, what: &'static str, note: Option<(usize, &'static str)>) {
    let mut rest = input;
    let _ = ws(&mut rest);
    let offset = pos(rest);
    EXPECTATION.with(|e| {
        let mut e = e.borrow_mut();
        match e.as_mut() {
            Some(cur) if cur.offset > offset => {}
            Some(cur) if cur.offset == offset => {
                if !cur.expected.contains(&what) {
                    cur.expected.push(what);
                }
                if cur.note.is_none() {
                    cur.note = note;
                }
            }
            _ => *e = Some(Expectation { offset, expected: vec![what], note }),
        }
    });
}

/// The expectations recorded by the current parse.
pub(crate) fn expectation() -> Option<Expectation> {
    EXPECTATION.with(|e| e.borrow().clone())
}

/// Byte offset of the first non-trivia (whitespace, comment) at or after
/// `offset` in `source`.
pub(crate) fn skip_trivia(source: &str, offset: usize) -> usize {
    let mut rest = &source[offset.min(source.len())..];
    let before = rest.len();
    let _ = ws(&mut rest);
    offset.min(source.len()) + (before - rest.len())
}


// ── Keywords ──────────────────────────────────────────────────────────────────

/// The runtime type `T?` stands for (`runtime/optional.pep`).
const OPTIONAL_TYPE: &str = "Optional";

const RESERVED: &[&str] = &[
    "import", "struct", "var", "const",
    "if", "else", "while", "for", "return", "extern",
    "and", "or", "new", "construct", "destruct", "static",
    "sizeof", "true", "false",
    "trait", "extend", "type", "export", "with",
    "enum", "match",
];

/// Operators that may appear as method names (overloadable operators), longest first.
const OPERATORS: &[&str] = &[
    "<<=", ">>=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=",
    "++", "--", "<<", ">>", "**", "&&", "||", "&=", "|=", "^=",
    "+", "-", "*", "/", "%", "<", ">", "&", "|", "^", "!", "~",
];

/// Parse an operator token (used as an overloadable method name, e.g. `bool ==(x)`).
fn operator_name(input: &mut &str) -> Result<String> {
    for op in OPERATORS {
        if input.starts_with(op) {
            *input = &input[op.len()..];
            return Ok(op.to_string());
        }
    }
    Err(bt(input))
}

// ── Whitespace / comments ─────────────────────────────────────────────────────

fn ws(input: &mut &str) -> Result<()> {
    loop {
        // Compare lengths, not contents: `input` only ever shrinks from the
        // front, and a content comparison scans the rest of the file.
        let before = input.len();
        // skip whitespace chars
        *input = input.trim_start();
        // skip # comment to end of line
        if input.starts_with('#') {
            match input.find('\n') {
                Some(pos) => *input = &input[pos + 1..],
                None => *input = "",
            }
        }
        if input.len() == before { break; }
    }
    Ok(())
}

/// Whether a line break comes before the next token (after spaces and a
/// trailing comment). Line breaks mean nothing to the grammar; this only
/// places the `;` a declaration left out (see [`decl_boundary`]).
fn at_line_break(input: &str) -> bool {
    let rest = input.trim_start_matches(|c: char| c.is_whitespace() && c != '\n');
    rest.starts_with('\n') || rest.starts_with('#')
}

/// Take the `;` that ends a statement or declaration whose text ends at byte
/// `end`. A missing one is deprecated (see [`missing_semicolon`]).
fn semicolon(input: &mut &str, end: usize) -> Result<()> {
    let mut rest = *input;
    ws(&mut rest)?;
    if rest.starts_with(';') {
        *input = &rest[1..];
    } else {
        missing_semicolon(end);
    }
    Ok(())
}

/// Warn that the statement or declaration ending at byte `end` has no `;`,
/// with a fix that adds it.
fn missing_semicolon(end: usize) {
    let loc = Loc::new(FileId::default(), Span { start: end, end });
    let fix = Fix::replace("Insert ';'", loc, ";");
    warn(Diagnostic::deprecated("omitting ';'", "end the statement with ';'", loc, fix));
}

/// Skip to the next token when it satisfies `test`; otherwise leave `input`
/// where it is, so a span ends at the last token rather than after the
/// whitespace that follows it.
fn next_is(input: &mut &str, test: impl Fn(&str) -> bool) -> bool {
    let mut rest = *input;
    if ws(&mut rest).is_ok() && test(rest) {
        *input = rest;
        true
    } else {
        false
    }
}

/// `=`, not `==`.
fn is_assign(s: &str) -> bool {
    s.starts_with('=') && !s[1..].starts_with('=')
}

// ── Tokens ────────────────────────────────────────────────────────────────────

fn identifier(input: &mut &str) -> Result<String> {
    let start = *input;
    // first char: alpha or _
    match input.chars().next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {
            *input = &input[1..];
        }
        _ => return Err(bt(input)),
    }
    // rest: alnum or _
    while let Some(c) = input.chars().next() {
        if c.is_ascii_alphanumeric() || c == '_' {
            *input = &input[1..];
        } else {
            break;
        }
    }
    let id = start[..start.len() - input.len()].to_string();
    if RESERVED.contains(&id.as_str()) {
        *input = start; // restore
        return Err(bt(input));
    }
    Ok(id)
}

fn type_name(input: &mut &str) -> Result<TypeName> {
    if input.starts_with('(') {
        return function_type_name(input);
    }
    if let Some(ty) = shared_function_type_name(input)? {
        return Ok(ty);
    }
    if let Some(ty) = extern_function_type_name(input)? {
        return Ok(ty);
    }
    let mut ty = type_name_base(input)?;
    // End of the last token of the type, excluding trailing whitespace.
    let mut end = ty.span.end;

    // Array suffix: one or more `[]`  (e.g. int[], int[][], ptr<char>[])
    loop {
        let mut rest = *input;
        let _ = ws(&mut rest);
        if rest.starts_with('[') {
            rest = &rest[1..];
            ws(&mut rest)?;
            if rest.starts_with(']') {
                *input = &rest[1..];
                end = pos(input);
                ty.name.push_str("[]");
                continue;
            }
        }
        break;
    }

    // Optional suffix: `T?` is `Optional<T>` (`int[]?` is an optional array).
    loop {
        let mut probe: &str = input;
        ws(&mut probe)?;
        if !probe.starts_with('?') {
            break;
        }
        if EXPRESSION_PROBE.with(|p| p.get()) && !optional_suffix_in_probe(&probe[1..]) {
            break;
        }
        *input = &probe[1..];
        end = pos(input);
        let start = ty.span.start;
        ty = TypeName { name: OPTIONAL_TYPE.to_string(), generic_types: vec![ty], span: Span { start, end } };
    }

    // pointer suffix: one or more `*` (e.g. char*, void**). Parsed in every
    // type position so a misplaced `T*` gets a targeted error; it is legal only
    // in extern declarations (see `check_pointer_syntax`).
    loop {
        let mut rest = *input;
        let _ = ws(&mut rest);
        if rest.starts_with('*') {
            *input = &rest[1..];
            end = pos(input);
            ty.name.push('*');
        } else {
            break;
        }
    }

    ty.span.end = end;
    Ok(ty)
}

/// Whether the `?` just before `after` makes an optional type while an
/// expression is being probed for one (a C-style declaration such as
/// `Node? x;`, a type literal such as `Array<int?>()`), where `a ? b : c` may
/// be a ternary instead. It is a type when it closes or separates type
/// arguments (`?>`, `?,`), or when a name follows that ends the declaration
/// (`Node? x;`, `Node? x = y`, `Node? x` at the end of the line); a ternary's
/// first branch is followed by `:` instead.
fn optional_suffix_in_probe(after: &str) -> bool {
    let mut rest: &str = after;
    rest = rest.trim_start_matches([' ', '\t', '\r']);
    if rest.starts_with('>') || rest.starts_with(',') {
        return true;
    }
    // A name, scanned by hand: `identifier` would record how far the parse got.
    if !rest.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_') {
        return false;
    }
    rest = rest.trim_start_matches(|c: char| c.is_ascii_alphanumeric() || c == '_');
    rest = rest.trim_start_matches([' ', '\t', '\r']);
    rest.is_empty()
        || rest.starts_with(';')
        || rest.starts_with('\n')
        || rest.starts_with('}')
        || rest.starts_with('#')
        || (rest.starts_with('=') && !rest.starts_with("=="))
}

/// Function type `(P1, P2) => R`, lowered to `__function<R, P1, P2>` so
/// aliases, generic substitution and specialization treat it like any other
/// generic type. `=>` is right-associative: `(int) => (int) => int` returns a
/// function. A parenthesized list not followed by `=>` is not a type.
///
/// Without the `=>`, a list of two or more types is a tuple type `(A, B)`,
/// lowered to `__tuple<A, B>`.
fn function_type_name(input: &mut &str) -> Result<TypeName> {
    let before = *input;
    let start = pos(input);
    match function_type_of(input, type_name) {
        Err(ErrMode::Backtrack(_)) => {}
        other => return other,
    }
    // Not a function type: try `(A, B, ...)`.
    *input = &input[1..];
    let mut elements = vec![];
    loop {
        ws(input)?;
        match type_name(input) {
            Ok(ty) => elements.push(ty),
            Err(_) => {
                *input = before;
                return Err(bt(input));
            }
        }
        ws(input)?;
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with(')') && elements.len() >= 2 {
            *input = &input[1..];
            break;
        }
        *input = before;
        return Err(bt(input));
    }
    Ok(TypeName { name: TUPLE_TYPE.to_string(), generic_types: elements, span: Span { start, end: pos(input) } })
}

/// A function type whose parameter and return types `element` parses (C
/// types such as `void*` in an `extern` function type).
fn function_type_of(input: &mut &str, element: fn(&mut &str) -> Result<TypeName>) -> Result<TypeName> {
    let before = *input;
    let start = pos(input);
    *input = &input[1..];
    let mut params = vec![];
    loop {
        ws(input)?;
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        match element(input) {
            Ok(ty) => params.push(ty),
            Err(_) => {
                *input = before;
                return Err(bt(input));
            }
        }
        ws(input)?;
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        *input = before;
        return Err(bt(input));
    }
    ws(input)?;
    if !input.starts_with("=>") {
        *input = before;
        return Err(bt(input));
    }
    *input = &input[2..];
    ws(input)?;
    let ret = element(input)?;
    // End at the return type's last token, not the whitespace after it.
    let end = ret.span.end;
    let mut generic_types = vec![ret];
    generic_types.extend(params);
    Ok(TypeName { name: FUNCTION_TYPE.to_string(), generic_types, span: Span { start, end } })
}

/// Thread-safe function type `shared (P1, P2) => R`, lowered to
/// `__shared_function<R, P1, P2>`. `shared` is a contextual keyword: it is
/// one only directly before a function type, so it stays usable as a name.
/// Returns `None` (consuming nothing) when the input is not one.
fn shared_function_type_name(input: &mut &str) -> Result<Option<TypeName>> {
    prefixed_function_type_name(input, "shared", SHARED_FUNCTION_TYPE, type_name)
}

/// C function pointer type `extern (P1, P2) => R`, lowered to
/// `__extern_function<R, P1, P2>`. Its parameter and return types may be C
/// types (`void*`), as in an `extern` declaration. Returns `None` (consuming
/// nothing) when the input is not one.
fn extern_function_type_name(input: &mut &str) -> Result<Option<TypeName>> {
    prefixed_function_type_name(input, "extern", EXTERN_FUNCTION_TYPE, extern_type_name)
}

/// A function type written after `keyword`, renamed to `name`.
fn prefixed_function_type_name(
    input: &mut &str,
    keyword: &str,
    name: &str,
    element: fn(&mut &str) -> Result<TypeName>,
) -> Result<Option<TypeName>> {
    let Some(rest) = input.strip_prefix(keyword) else { return Ok(None) };
    if rest.starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(None);
    }
    let before = *input;
    let start = pos(input);
    *input = rest;
    ws(input)?;
    if !input.starts_with('(') {
        *input = before;
        return Ok(None);
    }
    match function_type_of(input, element) {
        Ok(mut ty) => {
            ty.name = name.to_string();
            ty.span.start = start;
            Ok(Some(ty))
        }
        Err(ErrMode::Backtrack(_)) => {
            *input = before;
            Ok(None)
        }
        Err(e) => Err(e),
    }
}

/// Extend `name` with `.segment`s written directly after it: a qualified
/// name, `module.Type`, resolved by module linking. While probing whether an
/// expression is a generic type literal, only a qualifier an import bound
/// counts, so `i < a.size, i > 0` stays two comparisons.
fn qualified_tail(input: &mut &str, name: &mut String) {
    if EXPRESSION_PROBE.with(|p| p.get()) && !QUALIFIERS.with(|q| q.borrow().contains(name.as_str())) {
        return;
    }
    while input.starts_with('.') && input[1..].starts_with(|c: char| c.is_ascii_alphabetic() || c == '_') {
        let before = *input;
        *input = &input[1..];
        match identifier(input) {
            Ok(segment) => {
                name.push('.');
                name.push_str(&segment);
            }
            Err(_) => {
                *input = before;
                break;
            }
        }
    }
}

/// Type name without a trailing Array suffix, so indexer methods
/// (`T [](params)`) are not mistaken for `T[]` Array types.
fn type_name_base(input: &mut &str) -> Result<TypeName> {
    let start = pos(input);
    let mut name = identifier(input)?;
    qualified_tail(input, &mut name);
    let mut end = pos(input);

    // generic types: < T, T, ... >
    let mut generic_types = vec![];
    let mut rest = *input;
    let _ = ws(&mut rest);
    if rest.starts_with('<') {
        *input = &rest[1..];
        loop {
            ws(input)?;
            generic_types.push(type_name(input)?);
            ws(input)?;
            if input.starts_with(',') {
                *input = &input[1..];
                continue;
            }
            if input.starts_with('>') {
                *input = &input[1..];
                end = pos(input);
                break;
            }
            return Err(cut_expecting(input, "'>'"));
        }
    }

    Ok(TypeName { name, generic_types, span: Span { start, end } })
}

fn string_constant(input: &mut &str) -> Result<Literal> {
    if !input.starts_with('"') {
        return Err(bt(input));
    }
    let open = pos(input);
    *input = &input[1..]; // consume opening quote
    let mut content = String::new();
    while let Some(c) = input.chars().next() {
        if c == '"' { break; }
        if c == '\\' {
            content.push(escape_sequence(input)?);
            continue;
        }
        content.push(c);
        *input = &input[c.len_utf8()..];
    }
    // consume closing quote
    if !input.starts_with('"') {
        expected_with_note(input, "'\"'", Some((open, "to match this '\"'")));
        return Err(cut(input));
    }
    *input = &input[1..];
    Ok(Literal::String(content))
}

/// A character literal: one ASCII character or escape sequence between single
/// quotes (`'a'`, `'"'`, `'\n'`). Its value is that character's byte; `\xHH`
/// may name any byte, including those above `\x7F`.
fn char_constant(input: &mut &str) -> Result<Literal> {
    let open = pos(input);
    *input = &input[1..]; // consume opening quote
    // As clang: an unclosed literal is reported at its opening quote.
    let unterminated = || error_at(Span { start: open, end: open + 1 }, "missing terminating ' character".to_string());
    let value = match input.chars().next() {
        None | Some('\n') | Some('\r') => return Err(unterminated()),
        Some('\'') => {
            return Err(error_at(Span { start: open, end: pos(input) + 1 }, "empty character literal".to_string()));
        }
        Some('\\') if input[1..].starts_with('x') => {
            let start = pos(input);
            *input = &input[2..];
            let digits: String = input.chars().take(2).take_while(|d| d.is_ascii_hexdigit()).collect();
            *input = &input[digits.len()..];
            match u8::from_str_radix(&digits, 16) {
                Ok(byte) if digits.len() == 2 => byte,
                _ => return Err(error_at(Span { start, end: pos(input) }, "'\\x' escape needs two hexadecimal digits".to_string())),
            }
        }
        Some(c) => {
            let start = pos(input);
            let c = if c == '\\' {
                escape_sequence(input)?
            } else {
                *input = &input[c.len_utf8()..];
                c
            };
            if !c.is_ascii() {
                return Err(error_at(
                    Span { start, end: pos(input) },
                    "character literal must be a single ASCII character; use a string for other characters".to_string(),
                ));
            }
            c as u8
        }
    };
    if !input.starts_with('\'') {
        let line_end = input.find(['\n', '\r']).unwrap_or(input.len());
        return match input[..line_end].find('\'') {
            Some(close) => Err(error_at(
                Span { start: open, end: pos(input) + close + 1 },
                "character literal may only contain one character; use a string for more".to_string(),
            )),
            None => Err(unterminated()),
        };
    }
    *input = &input[1..];
    Ok(Literal::Char(value))
}

/// One escape sequence at `input` (which starts at its backslash), as C and
/// Rust spell them: `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, `\'`, `\xHH` for an
/// ASCII byte and `\u{H...}` for a code point.
fn escape_sequence(input: &mut &str) -> Result<char> {
    let start = pos(input);
    *input = &input[1..];
    let Some(c) = input.chars().next() else {
        return Err(cut_expecting(input, "'\"'"));
    };
    *input = &input[c.len_utf8()..];
    let simple = match c {
        'n' => Some('\n'),
        't' => Some('\t'),
        'r' => Some('\r'),
        '0' => Some('\0'),
        '\\' => Some('\\'),
        '"' => Some('"'),
        '\'' => Some('\''),
        _ => None,
    };
    if let Some(simple) = simple {
        return Ok(simple);
    }
    let invalid = |input: &mut &str, message: String| Err(error_at(Span { start, end: pos(input) }, message));
    match c {
        'x' => {
            let digits: String = input.chars().take(2).take_while(|d| d.is_ascii_hexdigit()).collect();
            *input = &input[digits.len()..];
            match u8::from_str_radix(&digits, 16) {
                Ok(byte) if digits.len() == 2 && byte < 0x80 => Ok(byte as char),
                Ok(_) if digits.len() == 2 => invalid(input, "'\\x' escape must be ASCII (at most \\x7F); use '\\u{...}' for other characters".to_string()),
                _ => invalid(input, "'\\x' escape needs two hexadecimal digits".to_string()),
            }
        }
        'u' => {
            if !input.starts_with('{') {
                return invalid(input, "expected '{' after '\\u'".to_string());
            }
            let digits: String = input[1..].chars().take_while(|d| d.is_ascii_hexdigit()).collect();
            *input = &input[1 + digits.len()..];
            if !input.starts_with('}') || digits.is_empty() || digits.len() > 6 {
                return invalid(input, "'\\u{...}' escape needs 1 to 6 hexadecimal digits and a closing '}'".to_string());
            }
            *input = &input[1..];
            match u32::from_str_radix(&digits, 16).ok().and_then(char::from_u32) {
                Some(ch) => Ok(ch),
                None => invalid(input, format!("'\\u{{{}}}' is not a Unicode code point", digits)),
            }
        }
        other => invalid(input, format!("unknown escape sequence '\\{}'", other)),
    }
}

fn numeric_constant(input: &mut &str) -> Result<Literal> {
    let start = *input;
    let begin = pos(input);
    // A leading `-` belongs to the literal (`2 ** -1`, `[-1]`).
    let negative = input.starts_with('-');
    if negative {
        *input = &input[1..];
    }
    let too_large = |input: &mut &str| {
        error_at(Span { start: begin, end: pos(input) }, "integer literal is too large to be represented in a 64-bit integer".to_string())
    };

    // hex
    if input.starts_with("0x") {
        *input = &input[2..];
        while let Some(c) = input.chars().next() {
            if c.is_ascii_hexdigit() {
                *input = &input[1..];
            } else {
                break;
            }
        }
        let hex = &start[2 + negative as usize..start.len() - input.len()];
        if hex.is_empty() {
            return Err(cut_expecting(input, "hexadecimal digit"));
        }
        // Up to 64 bits of hex is a bit pattern: `0xFFFFFFFFFFFFFFFF` is -1.
        let bits = u64::from_str_radix(hex, 16).map_err(|_| too_large(input))?;
        let value = bits as i64;
        return Ok(Literal::Integer(if negative { value.wrapping_neg() } else { value }));
    }

    // integer part
    while let Some(c) = input.chars().next() {
        if c.is_ascii_digit() { *input = &input[1..]; } else { break; }
    }

    // fraction
    let has_frac = input.starts_with('.');
    if has_frac {
        *input = &input[1..];
        while let Some(c) = input.chars().next() {
            if c.is_ascii_digit() { *input = &input[1..]; } else { break; }
        }
    }

    // exponent
    let has_exp = input.starts_with('e') || input.starts_with('E');
    if has_exp {
        *input = &input[1..];
        if input.starts_with('+') || input.starts_with('-') { *input = &input[1..]; }
        while let Some(c) = input.chars().next() {
            if c.is_ascii_digit() { *input = &input[1..]; } else { break; }
        }
    }

    let s = &start[..start.len() - input.len()];
    if has_frac || has_exp {
        match s.parse() {
            Ok(value) => Ok(Literal::Float(value)),
            Err(_) => Err(error_at(Span { start: begin, end: pos(input) }, format!("invalid floating-point literal '{}'", s))),
        }
    } else {
        // `-9223372036854775808` is representable even though its magnitude
        // alone is not.
        s.parse().map(Literal::Integer).map_err(|_| too_large(input))
    }
}

// ── Expressions ───────────────────────────────────────────────────────────────

fn primary_expression(input: &mut &str) -> Result<Expression> {
    let start = pos(input);
    // true / false
    if input.starts_with("true") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[4..];
        return Ok(Expression::Literal { value: Literal::Bool(true), span: Span { start, end: pos(input) } });
    }
    if input.starts_with("false") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[5..];
        return Ok(Expression::Literal { value: Literal::Bool(false), span: Span { start, end: pos(input) } });
    }
    // numeric
    if input.starts_with(|c: char| c.is_ascii_digit()) || (input.starts_with('-') && input[1..].starts_with(|c: char| c.is_ascii_digit())) {
        let n = numeric_constant(input)?;
        return Ok(Expression::Literal { value: n, span: Span { start, end: pos(input) } });
    }
    // String
    if input.starts_with('"') || input.starts_with('@') {
        let s = string_constant(input)?;
        return Ok(Expression::Literal { value: s, span: Span { start, end: pos(input) } });
    }
    // Character: 'a'
    if input.starts_with('\'') {
        let c = char_constant(input)?;
        return Ok(Expression::Literal { value: c, span: Span { start, end: pos(input) } });
    }
    // __null
    if input.starts_with("__null") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        return Ok(Expression::Literal { value: Literal::Null, span: Span { start, end: pos(input) } });
    }
    // sizeof<TypeName>
    if input.starts_with("sizeof") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        ws(input)?;
        if !input.starts_with('<') { return Err(cut_expecting(input, "'<'")); }
        *input = &input[1..];
        ws(input)?;
        let ty = type_name(input).inspect_err(|_| expected(input, "type"))?;
        ws(input)?;
        if !input.starts_with('>') { return Err(cut_expecting(input, "'>'")); }
        *input = &input[1..];
        // `sizeof<T>()` is the same expression; absorb the call parens so we
        // don't wrap a `SizeOf` in an empty `FunctionCall`.
        let mut rest = *input;
        let _ = ws(&mut rest);
        if rest.starts_with('(') {
            *input = rest;
            *input = &input[1..];
            ws(input)?;
            if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
            *input = &input[1..];
        }
        return Ok(Expression::SizeOf(ty)); // span carried by ty
    }
    // symbol reference, or a generic type literal such as `Array<int>` in `Array<int>()`
    let before = *input;
    let name = identifier(input).inspect_err(|_| expected(input, "expression"))?;
    // A qualified generic construction, call, or member access,
    // `m.Box<int>()`, `m.Box<int>[]()`, `m.Result<int>.ok(1)`, where `m` is an
    // imported module: parsed whole as a type literal so the `<` is not read
    // as a comparison. Anything else, like `f(a.b < c, d > (e))`, stays two
    // comparisons.
    if input.starts_with('.') && QUALIFIERS.with(|q| q.borrow().contains(&name)) {
        let mut probe: &str = before;
        if let Ok(ty) = probe_type_name(&mut probe)
            && ty.name.contains('.')
            && !ty.generic_types.is_empty()
            && ws(&mut probe).is_ok()
            && (probe.starts_with('(') || probe.starts_with('.'))
        {
            *input = probe;
            return Ok(Expression::TypeLiteral(ty));
        }
    }
    // The span is the name alone, not the whitespace after it.
    let end = pos(input);
    let mut rest = *input;
    let _ = ws(&mut rest);
    if rest.starts_with('<') {
        let mut probe: &str = before;
        if let Ok(ty) = probe_type_name(&mut probe) {
            // The whole `Name<...>` parsed as a type; advance the real input past it.
            // (If it failed, this was a `<` comparison and `name` is a plain symbol.)
            *input = probe;
            return Ok(Expression::TypeLiteral(ty));
        }
    }
    Ok(Expression::SymbolRef { id: name, span: Span { start, end } })
}

/// A closure literal: `(params) [: R] => body`, where each parameter is
/// `name` or `name: Type` and the body is a block or an expression. Anything
/// that is not a closure up to its `=>` backtracks, so `(a + b)` and
/// `c ? (x) : y` stay ordinary expressions.
fn closure_literal(input: &mut &str) -> Result<Expression> {
    let before: &str = input;
    let start = pos(input);
    fn fail<'a>(input: &mut &'a str, before: &'a str) -> Result<Expression> {
        *input = before;
        Err(bt(input))
    }
    *input = &input[1..];
    let mut parameters = vec![];
    loop {
        ws(input)?;
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        let name_start = pos(input);
        let Ok(name) = identifier(input) else { return fail(input, before) };
        let name_span = Span { start: name_start, end: pos(input) };
        ws(input)?;
        let mut type_name = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            match type_name_parse(input) {
                Ok(ty) => type_name = ty,
                Err(_) => return fail(input, before),
            }
            ws(input)?;
        }
        parameters.push(VariableDecl {
            attributes: vec![],
            name,
            name_span,
            type_name,
            default_value: None,
            is_const: false,
            span: Span { start: name_start, end: pos(input) },
            is_exported: false,
        });
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        return fail(input, before);
    }
    ws(input)?;
    let mut return_type = TypeName::auto();
    if input.starts_with(':') {
        *input = &input[1..];
        ws(input)?;
        match type_name_parse(input) {
            Ok(ty) => return_type = ty,
            Err(_) => return fail(input, before),
        }
        ws(input)?;
    }
    if !input.starts_with("=>") {
        return fail(input, before);
    }
    *input = &input[2..];
    ws(input)?;
    let (body, expression_body) = if input.starts_with('{') {
        (block(input, vec![])?, false)
    } else {
        let expr = expression(input)?;
        let span = expr.span();
        let ret = Statement::Return(ReturnStatement { expr: Some(expr), span });
        (Block { statements: vec![ret], span, attributes: vec![] }, true)
    };
    Ok(Expression::Closure(Box::new(ClosureLiteral {
        parameters,
        return_type,
        body,
        expression_body,
        span: Span { start, end: pos(input) },
    })))
}

/// A type inside a closure's signature. Cut errors become backtracks, since
/// the text may turn out not to be a closure.
fn type_name_parse(input: &mut &str) -> Result<TypeName> {
    type_name(input).map_err(|_| bt(input))
}

fn atom(input: &mut &str) -> Result<Expression> {
    if input.starts_with('(') {
        match closure_literal(input) {
            Ok(closure) => return Ok(closure),
            Err(ErrMode::Backtrack(_)) => {}
            Err(e) => return Err(e),
        }
        let start = pos(input);
        *input = &input[1..];
        ws(input)?;
        let expr = expression(input)?;
        ws(input)?;
        // `(a, b, ...)`: a tuple.
        if input.starts_with(',') {
            let mut elements = vec![expr];
            while input.starts_with(',') {
                *input = &input[1..];
                ws(input)?;
                elements.push(expression(input)?);
                ws(input)?;
            }
            if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
            *input = &input[1..];
            return Ok(Expression::Tuple { elements, span: Span { start, end: pos(input) } });
        }
        if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
        *input = &input[1..];
        return Ok(expr);
    }
    primary_expression(input)
}

fn postfix(input: &mut &str) -> Result<Expression> {
    let mut expr = atom(input)?;
    loop {
        let before = *input;
        ws(input)?;
        if input.starts_with('.') {
            *input = &input[1..];
            ws(input)?;
            // `t.0`: a tuple element. Only digits, so `t.0.1` is two accesses.
            if input.starts_with(|c: char| c.is_ascii_digit()) {
                let digits = input.len() - input.trim_start_matches(|c: char| c.is_ascii_digit()).len();
                let name = input[..digits].to_string();
                let name_span = Span { start: pos(input), end: pos(input) + digits };
                *input = &input[digits..];
                let start = expr.span().start;
                expr = Expression::MemberAccess { lhs: Box::new(expr), name, name_span, span: Span { start, end: pos(input) } };
                continue;
            }
            let name_start: &str = input;
            let mut name = identifier(input).inspect_err(|_| expected(input, "member name"))?;
            let name_span = Span { start: pos(input) - name.len(), end: pos(input) };
            // `x.map<long>(f)`: a generic method called with its type
            // arguments, written with `<` right after the name and `(`
            // right after the `>`. Anything else is a comparison:
            // `f(a.b < c, d > (e))`.
            if input.starts_with('<') {
                let mut probe: &str = name_start;
                if let Ok(ty) = probe_type_name(&mut probe) {
                    if !ty.generic_types.is_empty() && probe.starts_with('(') {
                        name = ty.to_string();
                        *input = probe;
                    }
                }
            }
            let start = expr.span().start;
            expr = Expression::MemberAccess { lhs: Box::new(expr), name, name_span, span: Span { start, end: pos(input) } };
            continue;
        }
        if input.starts_with('[') {
            *input = &input[1..];
            ws(input)?;
            let rhs = expression(input)?;
            ws(input)?;
            if !input.starts_with(']') { return Err(cut_expecting(input, "']'")); }
            *input = &input[1..];
            let start = expr.span().start;
            expr = Expression::Index { lhs: Box::new(expr), rhs: Box::new(rhs), span: Span { start, end: pos(input) } };
            continue;
        }
        if input.starts_with('(') {
            *input = &input[1..];
            ws(input)?;
            let mut args = vec![];
            if !input.starts_with(')') {
                loop {
                    ws(input)?;
                    args.push(expression(input)?);
                    ws(input)?;
                    if input.starts_with(',') {
                        *input = &input[1..];
                        continue;
                    }
                    break;
                }
            }
            ws(input)?;
            if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
            *input = &input[1..];
            let start = expr.span().start;
            expr = Expression::FunctionCall { function: Box::new(expr), arguments: args, span: Span { start, end: pos(input) } };
            continue;
        }
        if input.starts_with("++") || input.starts_with("--") {
            let op = if input.starts_with("++") { "++" } else { "--" };
            *input = &input[op.len()..];
            let start = expr.span().start;
            expr = Expression::Unary { op: op.to_string(), prefix: false, operand: Box::new(expr), span: Span { start, end: pos(input) } };
            continue;
        }
        *input = before;
        break;
    }
    Ok(expr)
}

/// `**` — right-associative, operand is postfix (function-call level)
fn pow(input: &mut &str) -> Result<Expression> {
    let base = postfix(input)?;
    let before = *input;
    ws(input)?;
    if input.starts_with("**") {
        let start = pos(input);
        *input = &input[2..];
        ws(input)?;
        let rhs = pow(input)?; // right-assoc: rhs is another pow
        return Ok(Expression::Binary { lhs: Box::new(base), op: "**".into(), rhs: Box::new(rhs), span: Span { start, end: pos(input) } });
    }
    *input = before;
    Ok(base)
}

/// prefix `+`, `-`, `~`, `!` — operand is an `as` cast
fn unary(input: &mut &str) -> Result<Expression> {
    ws(input)?;
    // Never grab the operator part of compound assignments (`+=`, `-=`); those
    // belong to the assignment level. `++`/`--` are handled by `prefix_op` above.
    let op = if input.starts_with('+') && !input.starts_with("++") && !input.starts_with("+=") { Some("+") }
        else if input.starts_with('-') && !input.starts_with("--") && !input.starts_with("-=") { Some("-") }
        else if input.starts_with('~') { Some("~") }
        else if input.starts_with('!') { Some("!") }
        else { None };
    if let Some(op) = op {
        let start = pos(input);
        *input = &input[op.len()..];
        ws(input)?;
        let operand = cast(input)?;
        return Ok(Expression::Unary { op: op.to_string(), prefix: true, operand: Box::new(operand), span: Span { start, end: pos(input) } });
    }
    cast(input)
}

/// `expr as Type` — static cast (docs/src/language/types-and-variables.md). Sits between the unary
/// and `**` levels, so `as` binds tighter than unary: `-x as int` parses as
/// `-(x as int)` and `2 ** 3 as float` as `(2 ** 3) as float`. C-style
/// `(int)x` is NOT a cast.
fn cast(input: &mut &str) -> Result<Expression> {
    let expr = pow(input)?;
    let before = *input;
    ws(input)?;
    if input.starts_with("as") && !input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        let start = expr.span().start;
        *input = &input[2..];
        ws(input)?;
        let ty = type_name(input).inspect_err(|_| expected(input, "type"))?;
        return Ok(Expression::Cast { expr: Box::new(expr), ty, span: Span { start, end: pos(input) } });
    }
    *input = before;
    Ok(expr)
}

/// prefix `++`, `--` — operand is unary
fn prefix_op(input: &mut &str) -> Result<Expression> {
    ws(input)?;
    if input.starts_with("++") {
        let start = pos(input);
        *input = &input[2..];
        let operand = unary(input)?;
        return Ok(Expression::Unary { op: "++".into(), prefix: true, operand: Box::new(operand), span: Span { start, end: pos(input) } });
    }
    if input.starts_with("--") {
        let start = pos(input);
        *input = &input[2..];
        let operand = unary(input)?;
        return Ok(Expression::Unary { op: "--".into(), prefix: true, operand: Box::new(operand), span: Span { start, end: pos(input) } });
    }
    unary(input)
}

fn binary_left(
    input: &mut &str,
    operand: impl Fn(&mut &str) -> Result<Expression>,
    try_op: impl Fn(&str) -> Option<&str>,
) -> Result<Expression> {
    let mut lhs = operand(input)?;
    loop {
        let before = *input;
        ws(input)?;
        if let Some(op) = try_op(input) {
            let start = pos(input);
            *input = &input[op.len()..];
            let rhs = operand(input)?;
            lhs = Expression::Binary { lhs: Box::new(lhs), op: op.to_string(), rhs: Box::new(rhs), span: Span { start, end: pos(input) } };
        } else {
            *input = before;
            break;
        }
    }
    Ok(lhs)
}

fn binary_right(
    input: &mut &str,
    operand: impl Fn(&mut &str) -> Result<Expression>,
    try_op: impl Fn(&str) -> Option<&str>,
) -> Result<Expression> {
    let lhs = operand(input)?;
    let before = *input;
    ws(input)?;
    if let Some(op) = try_op(input) {
        let start = pos(input);
        *input = &input[op.len()..];
        let rhs = binary_right(input, operand, try_op)?;
        return Ok(Expression::Binary { lhs: Box::new(lhs), op: op.to_string(), rhs: Box::new(rhs), span: Span { start, end: pos(input) } });
    }
    *input = before;
    Ok(lhs)
}

fn mul(input: &mut &str) -> Result<Expression> {
    binary_left(input, prefix_op, |s: &str| {
        // `**` is handled by `pow`; `*=` / `/=` / `%=` belong to the assignment level
        if s.starts_with('*') && !s[1..].starts_with('*') && !s[1..].starts_with('=') { return Some("*"); }
        if s.starts_with('/') && !s[1..].starts_with('=') { return Some("/"); }
        if s.starts_with('%') && !s[1..].starts_with('=') { return Some("%"); }
        None
    })
}

fn add(input: &mut &str) -> Result<Expression> {
    binary_left(input, mul, |s: &str| {
        // `+=` / `-=` belong to the assignment level
        if s.starts_with('+') && !s.starts_with("++") && !s.starts_with("+=") { return Some("+"); }
        if s.starts_with('-') && !s.starts_with("--") && !s.starts_with("-=") { return Some("-"); }
        None
    })
}

fn shift(input: &mut &str) -> Result<Expression> {
    binary_left(input, add, |s: &str| {
        if s.starts_with("<<") && !s.starts_with("<<=") { return Some("<<"); }
        if s.starts_with(">>") && !s.starts_with(">>=") { return Some(">>"); }
        None
    })
}

fn relational(input: &mut &str) -> Result<Expression> {
    binary_left(input, shift, |s: &str| {
        if s.starts_with("<=") { return Some("<="); }
        if s.starts_with(">=") { return Some(">="); }
        // `<<` is handled by `shift` above
        if s.starts_with('<') && !s[1..].starts_with('=') && !s[1..].starts_with('<') { return Some("<"); }
        if s.starts_with('>') && !s[1..].starts_with('=') && !s[1..].starts_with('>') { return Some(">"); }
        None
    })
}

fn equality(input: &mut &str) -> Result<Expression> {
    binary_left(input, relational, |s: &str| {
        if s.starts_with("===") { return Some("==="); }
        if s.starts_with("!==") { return Some("!=="); }
        if s.starts_with("==") { return Some("=="); }
        if s.starts_with("!=") { return Some("!="); }
        None
    })
}

fn bit_and(input: &mut &str) -> Result<Expression> {
    binary_left(input, equality, |s: &str| {
        // `&&` is handled above; `&=` belongs to the assignment level
        if s.starts_with('&') && !s[1..].starts_with('&') && !s[1..].starts_with('=') { return Some("&"); }
        None
    })
}

fn bit_or(input: &mut &str) -> Result<Expression> {
    binary_left(input, bit_and, |s: &str| {
        // `||` is handled above; `|=` / `^=` belong to the assignment level
        if s.starts_with('|') && !s[1..].starts_with('|') && !s[1..].starts_with('=') { return Some("|"); }
        if s.starts_with('^') && !s[1..].starts_with('=') { return Some("^"); }
        None
    })
}

fn logical_and(input: &mut &str) -> Result<Expression> {
    binary_left(input, bit_or, |s: &str| {
        if s.starts_with("&&") { return Some("&&"); }
        if s.starts_with("and") && !s[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            return Some("and");
        }
        None
    })
}

fn logical_or(input: &mut &str) -> Result<Expression> {
    binary_left(input, logical_and, |s: &str| {
        if s.starts_with("||") { return Some("||"); }
        if s.starts_with("or") && !s[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            return Some("or");
        }
        None
    })
}

fn ternary(input: &mut &str) -> Result<Expression> {
    let cond = logical_or(input)?;
    let before = *input;
    ws(input)?;
    if !input.starts_with('?') {
        *input = before;
        return Ok(cond);
    }
    *input = &input[1..];
    ws(input)?;
    let true_expr = expression(input)?;
    ws(input)?;
    if !input.starts_with(':') { return Err(cut_expecting(input, "':'")); }
    *input = &input[1..];
    ws(input)?;
    let false_expr = expression(input)?;
    let start = cond.span().start;
    Ok(Expression::Ternary {
        condition: Box::new(cond),
        true_expr: Box::new(true_expr),
        false_expr: Box::new(false_expr),
        span: Span { start, end: pos(input) },
    })
}

fn assignment(input: &mut &str) -> Result<Expression> {
    binary_right(input, ternary, |s: &str| {
        if s.starts_with("*=") { return Some("*="); }
        if s.starts_with("/=") { return Some("/="); }
        if s.starts_with("%=") { return Some("%="); }
        if s.starts_with("+=") { return Some("+="); }
        if s.starts_with("-=") { return Some("-="); }
        if s.starts_with("<<=") { return Some("<<="); }
        if s.starts_with(">>=") { return Some(">>="); }
        if s.starts_with("&=") { return Some("&="); }
        if s.starts_with("^=") { return Some("^="); }
        if s.starts_with("|=") { return Some("|="); }
        if s.starts_with('=') && !s[1..].starts_with('=') { return Some("="); }
        None
    })
}

pub fn expression(input: &mut &str) -> Result<Expression> {
    assignment(input)
}

// ── Attributes ────────────────────────────────────────────────────────────────

/// A single attribute `[expr]`. The body is exactly one attribute: a bare
/// symbol (`[Export]`) or a call (`[Target(OS(Windows) && Arch(x64))]`,
/// `[Align(8)]`). There is no top-level boolean logic — `!`, `&&`, and `||`
/// are only meaningful inside `Target(...)`'s single argument.
fn attribute(input: &mut &str) -> Result<Attribute> {
    if !input.starts_with('[') { return Err(bt(input)); }
    let start = pos(input);
    *input = &input[1..];
    ws(input)?;
    // Inside the brackets, a failed body is a hard error: backtracking would
    // leave the dangling `[` to be misreported at the next declaration.
    let body = expression(input).map_err(|_| cut(input))?;
    // The body must be exactly one attribute (a symbol or a call); top-level
    // boolean logic (`!`, `&&`, `||`) and literals are hard errors.
    if !is_predicate_body(&body) { return Err(cut(input)); }
    // `OS(...)` / `Arch(...)` are only valid inside `Target(...)`; a top-level
    // use is rejected here so it fails on every host, including fields (which
    // the sema pass never validates).
    if let Expression::FunctionCall { function, .. } = &body {
        if let Expression::SymbolRef { id, .. } = function.as_ref() {
            if is_os_or_arch_name(&id) {
                return Err(cut(input));
            }
        }
    }
    ws(input)?;
    if !input.starts_with(']') { return Err(cut_expecting(input, "']'")); }
    *input = &input[1..];
    Ok(Attribute { body, span: Span { start, end: pos(input) } })
}

/// Attribute bodies are exactly one attribute: a bare symbol (`[Export]`) or
/// a `Name(args)` call. Top-level `!` / `&&` / `||` is not an attribute — it
/// has no context outside `Target(...)`'s argument.
fn is_predicate_body(e: &Expression) -> bool {
    match e {
        Expression::SymbolRef { .. } => true,
        // A `Name(arg, ...)` parses as a plain function call.
        Expression::FunctionCall { function, .. } => {
            matches!(function.as_ref(), Expression::SymbolRef { .. })
        }
        _ => false,
    }
}

/// True if the attribute body is a platform selection: a top-level
/// `Target(...)` call. Nested calls (`[Align(OS(Windows))]`) are not
/// selections and are not reported here, matching the evaluator, which also
/// ignores such arguments. Used to reject platform predicates on struct
/// fields, which have no per-platform semantics. Also used by the sema pass
/// to skip attributes that contain no predicate at all.
pub fn contains_platform_predicate(e: &Expression) -> bool {
    matches!(
        e,
        Expression::FunctionCall { function, .. }
            if matches!(function.as_ref(), Expression::SymbolRef { id, .. } if is_platform_predicate_name(&id))
    )
}

/// The platform-selection attribute name. Shared with the sema pass so the
/// parser's field rejection and the evaluator agree on the set.
pub fn is_platform_predicate_name(id: &str) -> bool {
    id.to_ascii_lowercase() == "target"
}

/// The predicate names valid inside a `Target(...)` argument. Shared with
/// the sema pass so the parser's top-level rejection and the evaluator agree
/// on the set.
pub fn is_os_or_arch_name(id: &str) -> bool {
    matches!(id.to_ascii_lowercase().as_str(), "os" | "arch")
}

/// Zero or more attributes preceding a declaration or block.
fn attributes(input: &mut &str) -> Result<Vec<Attribute>> {
    let mut out = vec![];
    // `[]` starts a Pepper-style indexer (`[](index: ulong): T`), not an attribute.
    while input.starts_with('[') && !input.starts_with("[]") {
        out.push(attribute(input)?);
        ws(input)?;
    }
    Ok(out)
}

// ── Statements ────────────────────────────────────────────────────────────────

/// Variable declaration — supports two syntaxes:
///   1. `[var|const] name [: TypeName] [= expr]`
///   2. `TypeName name [= expr]`  (struct field style)
fn variable_declaration(input: &mut &str, attributes: Vec<Attribute>) -> Result<VariableDecl> {
    // Widen the node span to cover any preceding attributes.
    let start = attributes.first().map(|a| a.span.start).unwrap_or(pos(input));
    let before = *input;

    // Case 1: explicit specifier (var / const)
    if input.starts_with("const") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[5..];
        ws(input)?;
        let name_span_start = pos(input);
        let name = identifier(input)?;
        let name_span_end = pos(input);
        let mut ty = TypeName::auto();
        if next_is(input, |s| s.starts_with(':')) {
            *input = &input[1..];
            ws(input)?;
            ty = type_name(input).inspect_err(|_| expected(input, "type"))?;
        }
        let mut dv = None;
        if next_is(input, is_assign) {
            *input = &input[1..];
            ws(input)?;
            dv = Some(expression(input)?);
        }
        return Ok(VariableDecl { attributes, name, name_span: Span { start: name_span_start, end: name_span_end }, type_name: ty, default_value: dv, is_const: true, span: Span { start, end: pos(input) }, is_exported: false });
    }
    if input.starts_with("var") && !input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[3..];
        ws(input)?;
        let name_span_start = pos(input);
        let name = identifier(input)?;
        let name_span_end = pos(input);
        let mut ty = TypeName::auto();
        if next_is(input, |s| s.starts_with(':')) {
            *input = &input[1..];
            ws(input)?;
            ty = type_name(input).inspect_err(|_| expected(input, "type"))?;
        }
        let mut dv = None;
        if next_is(input, is_assign) {
            *input = &input[1..];
            ws(input)?;
            dv = Some(expression(input)?);
        }
        return Ok(VariableDecl { attributes, name, name_span: Span { start: name_span_start, end: name_span_end }, type_name: ty, default_value: dv, is_const: false, span: Span { start, end: pos(input) }, is_exported: false });
    }

    // Case 2: type-name syntax — `TypeName name [= expr]`
    // Only valid when NOT followed by '(' (which would indicate a function call).
    // A qualified type must name an imported module, so `a.b * c;` stays an
    // expression rather than declaring `c`.
    let mut ty = probe_type_name(input)?;
    ws(input)?;

    // If the next token is '(' this is a function call, not a declaration
    if input.starts_with('(') {
        *input = before;
        return Err(bt(input));
    }

    let name_span_start = pos(input);
    let name = identifier(input)?;
    let name_span_end = pos(input);
    // Optional `: Type` annotation (parameter style: `a: int`).
    if next_is(input, |s| s.starts_with(':')) {
        *input = &input[1..];
        ws(input)?;
        ty = type_name(input).inspect_err(|_| expected(input, "type"))?;
    }

    let mut dv = None;
    if next_is(input, is_assign) {
        *input = &input[1..];
        ws(input)?;
        dv = Some(expression(input)?);
    }

    Ok(VariableDecl { attributes, name, name_span: Span { start: name_span_start, end: name_span_end }, type_name: ty, default_value: dv, is_const: false, span: Span { start, end: pos(input) }, is_exported: false })
}

fn block(input: &mut &str, attributes: Vec<Attribute>) -> Result<Block> {
    // Widen the node span to cover any preceding attributes.
    let start = attributes.first().map(|a| a.span.start).unwrap_or(pos(input));
    if !input.starts_with('{') { return Err(cut_expecting(input, "'{'")); }
    let open = pos(input);
    *input = &input[1..];

    let mut statements = vec![];
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        let stmt = statement(input)?;
        // A simple statement ends with a `;` (a missing one is deprecated);
        // one that ends in a block needs nothing more.
        let simple = matches!(stmt, Statement::Expression(_) | Statement::Declaration(_) | Statement::Return(_) | Statement::LoopBreak(_));
        if simple {
            semicolon(input, stmt.span().end)?;
        }
        statements.push(stmt);
    }
    ws(input)?;
    if !input.starts_with('}') {
        expected_with_note(input, "'}'", Some((open, "to match this '{'")));
        return Err(cut(input));
    }
    *input = &input[1..];
    Ok(Block { statements, span: Span { start, end: pos(input) }, attributes })
}

fn branch(input: &mut &str) -> Result<Branch> {
    let start = pos(input);
    if !input.starts_with("if") || input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[2..];
    ws(input)?;
    let condition = expression(input)?;
    ws(input)?;
    let if_block = block(input, vec![])?;
    ws(input)?;

    let mut else_block = None;
    if input.starts_with("else") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[4..];
        ws(input)?;
        // `else if` is an else block holding just the nested branch.
        if input.starts_with("if") && !input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            let inner = branch(input)?;
            let span = inner.span;
            else_block = Some(Block { statements: vec![Statement::Branch(inner)], span, attributes: vec![] });
        } else {
            else_block = Some(block(input, vec![])?);
        }
        ws(input)?;
    }

    let end = else_block.as_ref().map(|b| b.span.end).unwrap_or(if_block.span.end);
    Ok(Branch { condition, if_block, else_block, span: Span { start, end } })
}

fn while_loop(input: &mut &str) -> Result<While> {
    let start = pos(input);
    if !input.starts_with("while") || input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[5..];
    ws(input)?;
    let condition = expression(input)?;
    ws(input)?;
    let block = block(input, vec![])?;
    let end = block.span.end;
    ws(input)?;
    Ok(While { condition, block, span: Span { start, end } })
}

/// `for (var x in expr) { ... }` / `for (T x in expr) { ... }`. As with `if`
/// and `while` the parentheses are optional. `in` is contextual, not reserved.
fn for_loop(input: &mut &str) -> Result<For> {
    let start = pos(input);
    if !input.starts_with("for") || input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[3..];
    ws(input)?;
    let parenthesized = input.starts_with('(');
    if parenthesized {
        *input = &input[1..];
        ws(input)?;
    }
    // Past `for`, a malformed header is an error, not a different statement.
    let binding = variable_declaration(input, vec![]).map_err(|_| cut(input))?;
    if binding.is_const || binding.default_value.is_some() {
        return Err(cut(input));
    }
    ws(input)?;
    if !input.starts_with("in") || input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(cut(input));
    }
    *input = &input[2..];
    ws(input)?;
    let iterable = expression(input)?;
    ws(input)?;
    if parenthesized {
        if !input.starts_with(')') {
            return Err(cut(input));
        }
        *input = &input[1..];
        ws(input)?;
    }
    let block = block(input, vec![])?;
    let end = block.span.end;
    ws(input)?;
    Ok(For { binding, iterable, block, span: Span { start, end } })
}

/// `with (var x = scope) { ... } else { ... }`, `with (Type x = scope) ...`,
/// or `with (scope) { ... }`. As with `for` the parentheses are optional.
/// The binding receives `scope.enter()`; see `ast::With`.
fn with_statement(input: &mut &str) -> Result<With> {
    let start = pos(input);
    if !keyword(input, "with") {
        return Err(bt(input));
    }
    ws(input)?;
    let parenthesized = input.starts_with('(');
    if parenthesized {
        *input = &input[1..];
        ws(input)?;
    }
    // A declaration header must give the scope as its value; anything that
    // does not parse as `var x = e` / `Type x = e` is the bare scope form.
    let before = *input;
    let is_var = keyword(&mut { *input }, "var") || keyword(&mut { *input }, "const");
    let (binding, scope) = match variable_declaration(input, vec![]) {
        Ok(mut binding) if binding.default_value.is_some() && !binding.is_const => {
            let scope = binding.default_value.take().unwrap();
            (Some(binding), scope)
        }
        Ok(binding) if is_var => {
            // `with (const x = e)` or `with (var x)`: past `var`, commit.
            if binding.is_const {
                *input = before;
                expected(*input, "'var'");
            } else {
                expected(*input, "'='");
            }
            return Err(cut(input));
        }
        Err(e) if is_var => return Err(e),
        _ => {
            *input = before;
            (None, expression(input)?)
        }
    };
    ws(input)?;
    if parenthesized {
        if !input.starts_with(')') {
            return Err(cut_expecting(input, "')'"));
        }
        *input = &input[1..];
        ws(input)?;
    }
    let body = block(input, vec![])?;
    let mut end = body.span.end;
    ws(input)?;
    let mut else_block = None;
    if keyword(&mut { *input }, "else") {
        keyword(input, "else");
        ws(input)?;
        let b = block(input, vec![])?;
        end = b.span.end;
        else_block = Some(b);
        ws(input)?;
    }
    Ok(With { binding, scope, block: body, else_block, span: Span { start, end } })
}

/// `match (value) { Case, Case(x, _) => { ... } ... else => { ... } }`. As
/// with `if` the parentheses are optional.
fn match_statement(input: &mut &str) -> Result<Match> {
    let start = pos(input);
    if !keyword(input, "match") {
        return Err(bt(input));
    }
    let keyword_span = Span { start, end: pos(input) };
    ws(input)?;
    let value = expression(input)?;
    ws(input)?;
    if !input.starts_with('{') { return Err(cut_expecting(input, "'{'")); }
    let open = pos(input);
    *input = &input[1..];
    let mut arms = vec![];
    let mut else_arm = None;
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if else_arm.is_some() {
            // Nothing may follow the `else` arm.
            expected_with_note(input, "'}'", Some((open, "to match this '{'")));
            return Err(cut(input));
        }
        let arm_start = pos(input);
        if keyword(&mut { *input }, "else") {
            keyword(input, "else");
            let else_span = Span { start: arm_start, end: pos(input) };
            ws(input)?;
            match_arrow(input)?;
            let body = block(input, vec![])?;
            else_arm = Some((else_span, body));
            continue;
        }
        let mut patterns = vec![pattern(input)?];
        loop {
            ws(input)?;
            if !input.starts_with(',') { break; }
            *input = &input[1..];
            ws(input)?;
            patterns.push(pattern(input)?);
        }
        match_arrow(input)?;
        let body = block(input, vec![])?;
        let span = Span { start: arm_start, end: body.span.end };
        arms.push(MatchArm { patterns, body, span });
    }
    if !input.starts_with('}') { expected_with_note(input, "'}'", Some((open, "to match this '{'"))); return Err(cut(input)); }
    *input = &input[1..];
    let span = Span { start, end: pos(input) };
    ws(input)?;
    Ok(Match { value, arms, else_arm, keyword_span, span })
}

/// The `=>` between a match arm's patterns and its block, and the space after it.
fn match_arrow(input: &mut &str) -> Result<()> {
    ws(input)?;
    if !input.starts_with("=>") { return Err(cut_expecting(input, "'=>'")); }
    *input = &input[2..];
    ws(input)?;
    Ok(())
}

/// A case pattern: `Case`, `Enum.Case`, `module.Enum.Case`, or `Case(x, _)`.
fn pattern(input: &mut &str) -> Result<Pattern> {
    let start = pos(input);
    let mut segments = vec![];
    loop {
        let segment_start = pos(input);
        let segment = identifier(input).map_err(|_| cut_expecting(input, "a case name"))?;
        segments.push((segment, Span { start: segment_start, end: pos(input) }));
        if input.starts_with('.') && input[1..].starts_with(|c: char| c.is_ascii_alphabetic() || c == '_') {
            *input = &input[1..];
            continue;
        }
        break;
    }
    let (case, case_span) = segments.pop().expect("one segment");
    let qualifier = segments.first().map(|(_, first)| TypeName {
        name: segments.iter().map(|(n, _)| n.as_str()).collect::<Vec<_>>().join("."),
        generic_types: vec![],
        span: Span { start: first.start, end: segments.last().map(|(_, s)| s.end).unwrap_or(first.end) },
    });
    let mut rest = *input;
    ws(&mut rest)?;
    let mut bindings = None;
    if rest.starts_with('(') {
        *input = &rest[1..];
        let mut names = vec![];
        loop {
            ws(input)?;
            if input.starts_with(')') { break; }
            let binding_start = pos(input);
            let name = identifier(input).map_err(|_| cut_expecting(input, "a name to bind"))?;
            names.push((name, Span { start: binding_start, end: pos(input) }));
            ws(input)?;
            if input.starts_with(',') {
                *input = &input[1..];
                continue;
            }
            if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
            break;
        }
        *input = &input[1..];
        bindings = Some(names);
    }
    Ok(Pattern { qualifier, case, case_span, bindings, span: Span { start, end: pos(input) } })
}

fn return_statement(input: &mut &str) -> Result<ReturnStatement> {
    let start = pos(input);
    if !input.starts_with("return") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[6..];
    let keyword_end = pos(input);
    ws(input)?;
    // A bare `return;` (or `return }`) returns no value.
    if input.is_empty() || input.starts_with(';') || input.starts_with('}') {
        return Ok(ReturnStatement { expr: None, span: Span { start, end: keyword_end } });
    }
    let expr = expression(input)?;
    let end = expr.span().end;
    Ok(ReturnStatement { expr: Some(expr), span: Span { start, end } })
}

/// `var (a, b: T, _) = e` or `const (...) = e`. Returns `None` (consuming
/// nothing) unless `var`/`const` is followed by `(`.
fn destructure(input: &mut &str) -> Result<Option<Destructure>> {
    let start = pos(input);
    let is_const = keyword(&mut { *input }, "const");
    if !is_const && !keyword(&mut { *input }, "var") {
        return Ok(None);
    }
    let mut rest = &input[if is_const { 5 } else { 3 }..];
    ws(&mut rest)?;
    if !rest.starts_with('(') {
        return Ok(None);
    }
    *input = &rest[1..];
    let mut bindings = vec![];
    loop {
        ws(input)?;
        let name_start = pos(input);
        let name = identifier(input).inspect_err(|_| expected(input, "identifier"))?;
        let name_span = Span { start: name_start, end: pos(input) };
        ws(input)?;
        let mut ty = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            ty = type_name(input).inspect_err(|_| expected(input, "type"))?;
            ws(input)?;
        }
        bindings.push(DestructureBinding { name, name_span, type_name: ty });
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        return Err(cut_expecting(input, "')'"));
    }
    ws(input)?;
    if !input.starts_with('=') || input.starts_with("==") {
        return Err(cut_expecting(input, "'='"));
    }
    *input = &input[1..];
    ws(input)?;
    let value = expression(input)?;
    let span = Span { start, end: pos(input) };
    if !decl_boundary(input) {
        return Err(cut_expecting(input, "';'"));
    }
    Ok(Some(Destructure { bindings, value, is_const, span }))
}

/// After a `TypeName name` style declaration the next token must end the
/// statement (`;`, `}`, or end of input); otherwise it was an expression all
/// along. While a missing `;` is only deprecated, a line break also ends the
/// declaration, the one place a line break means anything.
fn decl_boundary(input: &mut &str) -> bool {
    if at_line_break(input) {
        return true;
    }
    let mut rest = *input;
    let _ = ws(&mut rest);
    rest.is_empty() || rest.starts_with(';') || rest.starts_with('}')
}

fn statement(input: &mut &str) -> Result<Statement> {
    ws(input)?;

    // An attributed block statement: `[Name(args)] { ... }`. No expression in the
    // grammar starts with `[`, so this cannot shadow a valid expression.
    if input.starts_with('[') {
        let attrs = attributes(input)?;
        let b = block(input, attrs)?;
        return Ok(Statement::Block(b));
    }
    if input.starts_with('{') {
        let b = block(input, vec![])?;
        return Ok(Statement::Block(b));
    }
    if input.starts_with("if") && !input[2..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Statement::Branch(branch(input)?));
    }
    if input.starts_with("while") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Statement::While(while_loop(input)?));
    }
    if input.starts_with("for") && !input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Statement::For(for_loop(input)?));
    }
    if keyword(&mut { *input }, "with") {
        return Ok(Statement::With(with_statement(input)?));
    }
    if keyword(&mut { *input }, "match") {
        return Ok(Statement::Match(match_statement(input)?));
    }
    if input.starts_with("return") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Statement::Return(return_statement(input)?));
    }
    if input.starts_with("break") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        let start = pos(input);
        *input = &input[5..];
        return Ok(Statement::LoopBreak(LoopBreak { kind: LoopBreakKind::Break, span: Span { start, end: pos(input) } }));
    }
    if input.starts_with("continue") && !input[8..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        let start = pos(input);
        *input = &input[8..];
        return Ok(Statement::LoopBreak(LoopBreak { kind: LoopBreakKind::Continue, span: Span { start, end: pos(input) } }));
    }
    // `var (a, b) = e;` / `const (a, b) = e;`: destructuring.
    if let Some(d) = destructure(input)? {
        return Ok(Statement::Destructure(d));
    }
    // Variable declaration: `var`/`const` prefix OR `TypeName name = value` form.
    // Keywords are matched as whole words, so a type or module qualifier that
    // merely starts with one (`ordered.Socket s`, `newton x`) still declares.
    let is_kw = |kw: &str| keyword(&mut { *input }, kw);
    let is_var_decl = is_kw("var")
        || is_kw("const")
        || starts_extern_function_type(input)
        || (input.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
            && ![
                "if", "while", "return", "break", "continue", "struct", "extern", "import", "true", "false",
                "sizeof", "and", "or", "new", "construct", "destruct", "static", "trait", "extend", "with",
                "enum", "match",
            ]
            .iter()
            .any(|kw| is_kw(kw)));
    if is_var_decl {
        let before = *input;
        if let Ok(v) = variable_declaration(input, vec![]) {
            // A real declaration must end at a boundary; otherwise what looked like
            // `type name` was really an expression such as `arr[idx] = 1`.
            if decl_boundary(input) {
                return Ok(Statement::Declaration(Declaration::Variable(v)));
            }
            expected(input, "';'");
        }
        *input = before;
    }
    // otherwise: expression statement
    let expr = expression(input)?;
    Ok(Statement::Expression(expr))
}

// ── Declarations ──────────────────────────────────────────────────────────────

fn function_parameters(input: &mut &str) -> Result<Vec<VariableDecl>> {
    if !input.starts_with('(') { return Err(cut_expecting(input, "'('")); }
    *input = &input[1..];
    let mut params = vec![];
    loop {
        ws(input)?;
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        // C++ param grammar (Parser.cpp:1094-1140): `name: Type [= expr]`,
        // or `this.<field> [= expr]` constructor params.
        if input.starts_with("this") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            params.push(constructor_parameter(input)?);
        } else {
            params.push(typed_parameter(input)?);
        }
        ws(input)?;
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with(')') {
            *input = &input[1..];
            break;
        }
        return Err(cut_expecting(input, "')'"));
    }
    Ok(params)
}

/// Parameter in C++ grammar: `name: Type [= expr]` (Parser.cpp:1106-1139),
/// or C-style `Type name [= expr]` (used by the corpus, e.g. lib.pep's
/// `int sum(int x, int y)`).
fn typed_parameter(input: &mut &str) -> Result<VariableDecl> {
    let start = pos(input);
    let before = *input;
    // Colon style: `name: Type`.
    let mut name_span_start = pos(input);
    let mut name_span_end = name_span_start;
    if let Ok(decl) = (|| {
        name_span_start = pos(input);
        let name = identifier(input)?;
        name_span_end = pos(input);
        ws(input)?;
        if !input.starts_with(':') {
            return Err(bt(input));
        }
        *input = &input[1..];
        ws(input)?;
        let ty = type_name(input)?;
        ws(input)?;
        Ok((name, ty))
    })() {
        let (name, ty) = decl;
        let mut dv = None;
        if input.starts_with('=') && !input[1..].starts_with('=') {
            *input = &input[1..];
            ws(input)?;
            dv = Some(expression(input)?);
        }
        return Ok(VariableDecl { attributes: vec![], name, name_span: Span { start: name_span_start, end: name_span_end }, type_name: ty, default_value: dv, is_const: false, span: Span { start, end: pos(input) }, is_exported: false });
    }
    // C style: `Type name`.
    *input = before;
    let ty = type_name(input)?;
    ws(input)?;
    let name_span_start = pos(input);
    let name = identifier(input)?;
    let name_span_end = pos(input);
    ws(input)?;
    let mut dv = None;
    if input.starts_with('=') && !input[1..].starts_with('=') {
        *input = &input[1..];
        ws(input)?;
        dv = Some(expression(input)?);
    }
    Ok(VariableDecl { attributes: vec![], name, name_span: Span { start: name_span_start, end: name_span_end }, type_name: ty, default_value: dv, is_const: false, span: Span { start, end: pos(input) }, is_exported: false })
}

fn generic_params(input: &mut &str) -> Result<Vec<GenericParam>> {
    if !input.starts_with('<') { return Err(cut_expecting(input, "'<'")); }
    *input = &input[1..];
    let mut params = vec![];
    loop {
        ws(input)?;
        if input.starts_with('>') {
            *input = &input[1..];
            break;
        }
        let start = pos(input);
        let name = identifier(input)?;
        let name_span = Span { start, end: pos(input) };
        ws(input)?;
        // Optional default: `T=Default` (a single `=`; `==` is an operator).
        let mut default = None;
        if input.starts_with('=') && !input[1..].starts_with('=') {
            *input = &input[1..];
            ws(input)?;
            default = Some(type_name(input)?);
            ws(input)?;
        }
        params.push(GenericParam { name, name_span, default, is_argument: false });
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if input.starts_with('>') {
            *input = &input[1..];
            break;
        }
        return Err(cut_expecting(input, "'>'"));
    }
    Ok(params)
}

/// Function declaration — supports two syntaxes:
///   1. `name [generic_params] (params) [: TypeName] { body }`
///   2. `TypeName name (params) { body }`  (return-type prefix style)
fn function_declaration(input: &mut &str, attributes: Vec<Attribute>) -> Result<FunctionDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attributes.first().map(|a| a.span.start).unwrap_or(start);
    let before = *input;

    // Parse first identifier: a name, or a return type (`g.Point origin()`).
    let name_span_start = pos(input);
    let mut first = identifier(input)?;
    qualified_tail(input, &mut first);
    let name_span_end = pos(input);
    ws(input)?;
    // Determine which syntax based on what follows
    if first.contains('.') && (input.starts_with('(') || input.starts_with('<')) {
        // A qualified name is a type, never a function's own name.
        *input = before;
        return Err(bt(input));
    }
    if input.starts_with('(') || input.starts_with('<') {
        // Syntax 1: `first` is the function name
        let generic_params = if input.starts_with('<') {
            generic_params(input)?
        } else {
            vec![]
        };
        ws(input)?;

        let parameters = if input.starts_with('(') {
            function_parameters(input)?
        } else {
            vec![]
        };
        ws(input)?;

        let mut return_type = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            return_type = type_name(input)?;
            ws(input)?;
        }
        let body = block(input, vec![])?;
        ws(input)?;

        return Ok(FunctionDecl {
            is_exported: false,
            name: first,
            name_span: Span { start: name_span_start, end: name_span_end },
            generic_params,
            return_type,
            parameters,
            external: false,
            body: Some(body),
            is_static: false,
            is_indexer: false,
            is_variadic: false,
            span: Span { start: decl_start, end: pos(input) },
            attributes,
        });
    }

    // Syntax 2: `first` is the return type, next identifier is the name.
    if input.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_') || input.starts_with('[') {
        let mut return_type = TypeName { name: first, generic_types: vec![], span: Span { start, end: pos(input) } };
        // Array suffix on the return type (`int[] echo(...)`).
        while input.starts_with('[') {
            *input = &input[1..];
            ws(input)?;
            if input.starts_with(']') {
                *input = &input[1..];
                ws(input)?;
                return_type.name.push_str("[]");
            } else {
                break;
            }
        }
        let name_span_start = pos(input);
        let name = identifier(input)?;
        let name_span_end = pos(input);
        ws(input)?;

        let parameters = if input.starts_with('(') {
            function_parameters(input)?
        } else {
            vec![]
        };
        ws(input)?;

        // Optional trailing `: Type` return annotation.
        let mut effective_return = return_type;
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            effective_return = type_name(input)?;
            ws(input)?;
        }

        let body = block(input, vec![])?;
        ws(input)?;

        return Ok(FunctionDecl {
            is_exported: false,
            name,
            name_span: Span { start: name_span_start, end: name_span_end },
            generic_params: vec![],
            return_type: effective_return,
            parameters,
            external: false,
            body: Some(body),
            is_static: false,
            is_indexer: false,
            is_variadic: false,
            span: Span { start: decl_start, end: pos(input) },
            attributes,
        });
    }

    *input = before;
    Err(bt(input))
}

/// `TypeName` with an optional C-style pointer suffix (`char*`, `int**`),
/// matching the C++ grammar's `ExternTypeName`.
fn extern_type_name(input: &mut &str) -> Result<TypeName> {
    let mut ty = type_name(input)?;
    loop {
        if input.starts_with('*') {
            *input = &input[1..];
            ty.name.push('*');
            ty.span.end = pos(input);
        } else {
            break;
        }
    }
    Ok(ty)
}

/// Extern function parameters: `ExternTypeName Identifier` pairs (`char* str`),
/// optionally ending in C's `...`. Returns the parameters and whether the
/// list ended in `...` (a variadic function such as `printf` or `open`).
fn extern_parameters(input: &mut &str) -> Result<(Vec<VariableDecl>, bool)> {
    if !input.starts_with('(') { return Err(cut_expecting(input, "'('")); }
    *input = &input[1..];
    let mut params = vec![];
    let mut variadic = false;
    loop {
        ws(input)?;
        if input.starts_with(')') { break; }
        if input.starts_with("...") {
            // `...` must be last and follow at least one named parameter, as in C.
            if params.is_empty() { return Err(cut(input)); }
            *input = &input[3..];
            ws(input)?;
            if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
            variadic = true;
            break;
        }
        let ty = extern_type_name(input)?;
        ws(input)?;
        let name_span_start = pos(input);
        let name = identifier(input)?;
        let name_span_end = pos(input);
        ws(input)?;
        let span_start = ty.span.start;
        params.push(VariableDecl { attributes: vec![], name, name_span: Span { start: name_span_start, end: name_span_end }, type_name: ty, default_value: None, is_const: false, span: Span { start: span_start, end: pos(input) }, is_exported: false });
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
        break;
    }
    *input = &input[1..];
    ws(input)?;
    Ok((params, variadic))
}

/// Whether the input starts with a C function pointer type (`extern (`),
/// which declares a variable or field, not an extern function.
fn starts_extern_function_type(input: &str) -> bool {
    let Some(rest) = input.strip_prefix("extern") else { return false };
    !rest.starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') && rest.trim_start().starts_with('(')
}

fn extern_function_declaration(input: &mut &str, attributes: Vec<Attribute>) -> Result<FunctionDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attributes.first().map(|a| a.span.start).unwrap_or(start);
    if !input.starts_with("extern") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }

    *input = &input[6..];
    ws(input)?;

    let return_type = extern_type_name(input)?;
    ws(input)?;
    let name_span_start = pos(input);
    let name = identifier(input)?;
    let name_span_end = pos(input);
    ws(input)?;
    let (parameters, is_variadic) = extern_parameters(input)?;
    // The caller takes the `;` (see `semicolon`).

    Ok(FunctionDecl {
        is_exported: false,
        name,
        name_span: Span { start: name_span_start, end: name_span_end },
        generic_params: vec![],
        return_type,
        parameters,
        external: true,
        body: None,
        is_static: false,
        is_indexer: false,
        is_variadic,
        span: Span { start: decl_start, end: pos(input) },
        attributes,
    })
}

/// Constructor parameter — either `this.<field> = value` or a normal declaration.
fn constructor_parameter(input: &mut &str) -> Result<VariableDecl> {
    ws(input)?;
    if input.starts_with("this") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        let start = pos(input);
        *input = &input[4..];
        if !input.starts_with('.') { return Err(cut_expecting(input, "'.'")); }
        *input = &input[1..];
        ws(input)?;
        let field_span_start = pos(input);
        let field = identifier(input)?;
        let field_span_end = pos(input);
        ws(input)?;
        if !input.starts_with('=') { return Err(cut_expecting(input, "'='")); }
        *input = &input[1..];
        ws(input)?;
        let value = expression(input)?;
        ws(input)?;
        return Ok(VariableDecl {
            name: format!("this.{}", field),
            name_span: Span { start: field_span_start, end: field_span_end },
            type_name: TypeName::auto(),
            default_value: Some(value),
            is_const: false,
            attributes: vec![],
            span: Span { start, end: pos(input) },
            is_exported: false,
        });
    }
    // `var x: T` / `const x = v`, else a parameter written either way:
    // `name: Type` or C-style `Type name`.
    let keyword = |k: &str| input.starts_with(k) && !input[k.len()..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_');
    if keyword("var") || keyword("const") {
        return variable_declaration(input, vec![]);
    }
    typed_parameter(input)
}

/// A function with an already-parsed name: `name (params) [: TypeName] { body }`.
/// `start` is where the declaration began (its `static`, or its name).
fn named_function(input: &mut &str, name: String, name_span: Span, start: usize, attributes: &[Attribute]) -> Result<FunctionDecl> {
    // Widen the node span to cover any preceding attributes.
    let decl_start = attributes.first().map(|a| a.span.start).unwrap_or(start);
    ws(input)?;
    let generic_params = if input.starts_with('<') {
        generic_params(input)?
    } else {
        vec![]
    };
    ws(input)?;
    let parameters = if input.starts_with('(') {
        function_parameters(input)?
    } else {
        vec![]
    };
    ws(input)?;
    let mut return_type = TypeName::auto();
    if input.starts_with(':') {
        *input = &input[1..];
        ws(input)?;
        return_type = type_name(input)?;
        ws(input)?;
    }
    let body = block(input, vec![])?;
    ws(input)?;
    Ok(FunctionDecl {
        is_exported: false,
        name,
        name_span,
        generic_params,
        return_type,
        parameters,
        external: false,
        body: Some(body),
        is_static: false,
        is_indexer: false,
        is_variadic: false,
        span: Span { start: decl_start, end: pos(input) },
        attributes: attributes.to_vec(),
    })
}

/// A method inside a struct or `extend` block:
///   - `static` modifier
///   - indexer method: `T [](params) { body }`
///   - operator overload: `bool ==(x) { ... }` / `String +=(x) { ... }`
///   - `name(params) [: type] { body }` or `ReturnType name(params) { body }`
fn struct_method(input: &mut &str, attributes: &[Attribute]) -> Result<FunctionDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attributes.first().map(|a| a.span.start).unwrap_or(start);
    ws(input)?;
    let is_static = if input.starts_with("static") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        ws(input)?;
        true
    } else {
        false
    };

    // Pepper-style indexer or operator method: `[](params) [: T] { body }`,
    // `==(params) [: T] { body }`.
    let before = *input;
    let op_start = pos(input);
    let mut after: &str = *input;
    let op_name = if after.starts_with("[]") {
        after = &after[2..];
        Some("[]".to_string())
    } else {
        operator_name(&mut after).ok()
    };
    if let Some(op) = op_name {
        let op_span = Span { start: op_start, end: pos(after) };
        ws(&mut after)?;
        if after.starts_with('(') {
            *input = after;
            let mut f = named_function(input, op.clone(), op_span, start, attributes)?;
            f.is_static = is_static;
            if op == "[]" {
                f.name = if f.parameters.len() >= 2 { "__index_set".into() } else { "__index_get".into() };
                f.is_indexer = true;
            }
            return Ok(f);
        }
    }

    // Indexer method: `T [](params) { body }`
    let mut after: &str = *input;
    if let Ok(ty) = type_name_base(&mut after) {
        ws(&mut after)?;
        if after.starts_with("[]") {
            after = &after[2..];
            ws(&mut after)?;
            if after.starts_with('(') {
                let parameters = function_parameters(&mut after)?;
                ws(&mut after)?;
                let body = block(&mut after, vec![])?;
                ws(&mut after)?;
                *input = after;
                return Ok(FunctionDecl {
                    is_exported: false,
                    name: if parameters.len() >= 2 { "__index_set".into() } else { "__index_get".into() },
                    name_span: ty.span,
                    generic_params: vec![],
                    return_type: ty,
                    parameters,
                    external: false,
                    body: Some(body),
                    is_static,
                    is_indexer: true,
                    is_variadic: false,
                    span: Span { start: decl_start, end: pos(after) },
                    attributes: attributes.to_vec(),
                });
            }
        }
    }

    let name_span_start = pos(input);
    let name = match identifier(input) {
        Ok(n) => n,
        Err(e) => {
            *input = before;
            return Err(e);
        }
    };
    let name_span_end = pos(input);
    ws(input)?;

    // `name<U>(params)`: a generic method. `Array<T> items()` also starts
    // with a name and `<`, but no `(` follows its `>`.
    let generic_method = input.starts_with('<') && {
        let mut probe: &str = input;
        generic_params(&mut probe).is_ok() && ws(&mut probe).is_ok() && probe.starts_with('(')
    };
    if input.starts_with('(') || generic_method {
        // `name[<params>](params) [: type] { body }`
        let mut f = named_function(input, name, Span { start: name_span_start, end: name_span_end }, start, attributes)?;
        f.is_static = is_static;
        return Ok(f);
    }

    // `ReturnType name(params) { body }` — the method name may be an overloadable
    // operator, and the return type may carry generic arguments (`__ptr<char> c_str()`).
    let mut after: &str = before;
    if let Ok(ty) = type_name_base(&mut after) {
        ws(&mut after)?;
        let name_ok = !after.is_empty()
            && (after.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
                || OPERATORS.iter().any(|op| after.starts_with(op)));
        if name_ok {
            let mname_span_start = pos(after);
            let mname = match identifier(&mut after) {
                Ok(n) => n,
                Err(_) => operator_name(&mut after)?,
            };
            let mname_span_end = pos(after);
            ws(&mut after)?;
            let parameters = if after.starts_with('(') {
                function_parameters(&mut after)?
            } else {
                vec![]
            };
            ws(&mut after)?;
            let body = block(&mut after, vec![])?;
            ws(&mut after)?;
            *input = after;
            return Ok(FunctionDecl {
                is_exported: false,
                name: mname,
                name_span: Span { start: mname_span_start, end: mname_span_end },
                generic_params: vec![],
                return_type: ty,
                parameters,
                external: false,
                body: Some(body),
                is_static,
                is_indexer: false,
                is_variadic: false,
                span: Span { start: decl_start, end: pos(after) },
                attributes: attributes.to_vec(),
            });
        }
    }

    *input = before;
    Err(bt(input))
}

/// A trait method: like `struct_method` but the body is optional (`int getX();`).
fn trait_method(input: &mut &str, attributes: Vec<Attribute>) -> Result<FunctionDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attributes.first().map(|a| a.span.start).unwrap_or(start);
    ws(input)?;
    let is_static = if input.starts_with("static") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[6..];
        ws(input)?;
        true
    } else {
        false
    };

    let before = *input;
    let name_span_start = pos(input);
    let mut first = match identifier(input) {
        Ok(n) => n,
        Err(e) => {
            *input = before;
            return Err(e);
        }
    };
    qualified_tail(input, &mut first);
    let name_span_end = pos(input);
    ws(input)?;

    fn optional_body(input: &mut &str) -> Result<Option<Block>> {
        if input.starts_with('{') {
            let b = block(input, vec![])?;
            ws(input)?;
            return Ok(Some(b));
        }
        if input.starts_with(';') {
            *input = &input[1..];
            ws(input)?;
            return Ok(None);
        }
        Err(cut_expecting(input, "'{' or ';'"))
    }

    // `name<U>(params)`: a generic default method.
    let generic_method = input.starts_with('<') && !first.contains('.') && {
        let mut probe: &str = input;
        generic_params(&mut probe).is_ok() && ws(&mut probe).is_ok() && probe.starts_with('(')
    };
    let generic_params = if generic_method {
        let params = generic_params(input)?;
        ws(input)?;
        params
    } else {
        vec![]
    };
    if input.starts_with('(') && !first.contains('.') {
        let parameters = function_parameters(input)?;
        ws(input)?;
        // optional return-type annotation: `name(params): Type` (lexy `[: type]`)
        let mut return_type = TypeName::auto();
        if input.starts_with(':') {
            *input = &input[1..];
            ws(input)?;
            return_type = type_name(input)?;
            ws(input)?;
        }
        let body = optional_body(input)?;
        return Ok(FunctionDecl {
            is_exported: false,
            name: first,
            name_span: Span { start: name_span_start, end: name_span_end },
            generic_params,
            return_type,
            parameters,
            external: false,
            body,
            is_static,
            is_indexer: false,
            is_variadic: false,
            span: Span { start: decl_start, end: pos(input) },
            attributes,
        });
    }

    let name_ok = input.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
        || OPERATORS.iter().any(|op| input.starts_with(op));
    if name_ok {
        let return_type = TypeName { name: first, generic_types: vec![], span: Span { start: name_span_start, end: name_span_end } };
        let name_span2_start = pos(input);
        let name = match identifier(input) {
            Ok(n) => n,
            Err(_) => operator_name(input)?,
        };
        let name_span2_end = pos(input);
        ws(input)?;
        let parameters = if input.starts_with('(') {
            function_parameters(input)?
        } else {
            vec![]
        };
        ws(input)?;
        let body = optional_body(input)?;
        return Ok(FunctionDecl {
            is_exported: false,
            name,
            name_span: Span { start: name_span2_start, end: name_span2_end },
            generic_params: vec![],
            return_type,
            parameters,
            external: false,
            body,
            is_static,
            is_indexer: false,
            is_variadic: false,
            span: Span { start: decl_start, end: pos(input) },
            attributes,
        });
    }

    *input = before;
    Err(bt(input))
}

/// `trait Name[<params>] { methods }`
fn trait_declaration(input: &mut &str, attrs: Vec<Attribute>) -> Result<TraitDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attrs.first().map(|a| a.span.start).unwrap_or(start);
    if !input.starts_with("trait") || input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[5..];
    ws(input)?;
    let name_span_start = pos(input);
    let name = identifier(input)?;
    let name_span_end = pos(input);
    ws(input)?;
    let generic_params = if input.starts_with('<') {
        generic_params(input)?
    } else {
        vec![]
    };
    ws(input)?;
    if !input.starts_with('{') { return Err(cut_expecting(input, "'{'")); }
    let open = pos(input);
    *input = &input[1..];

    let mut methods = vec![];
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        let m_attrs = attributes(input)?;
        methods.push(trait_method(input, m_attrs)?);
        ws(input)?;
        if input.starts_with(';') {
            *input = &input[1..];
        }
    }
    ws(input)?;
    if !input.starts_with('}') { expected_with_note(input, "'}'", Some((open, "to match this '{'"))); return Err(cut(input)); }
    *input = &input[1..];

    Ok(TraitDecl { attributes: attrs, name, name_span: Span { start: name_span_start, end: name_span_end }, generic_params, methods, span: Span { start: decl_start, end: pos(input) }, is_exported: false })
}

/// `extend TypeName[<...>] [with Trait, ...] { methods }`
fn extend_declaration(input: &mut &str, attrs: Vec<Attribute>) -> Result<ExtendDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attrs.first().map(|a| a.span.start).unwrap_or(start);
    if !input.starts_with("extend") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[6..];
    ws(input)?;
    let target = type_name(input)?;
    ws(input)?;

    let mut traits = vec![];
    if input.starts_with("with") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[4..];
        loop {
            ws(input)?;
            traits.push(type_name(input)?);
            ws(input)?;
            if input.starts_with(',') {
                *input = &input[1..];
                continue;
            }
            break;
        }
    }
    ws(input)?;
    if !input.starts_with('{') { return Err(cut_expecting(input, "'{'")); }
    let open = pos(input);
    *input = &input[1..];

    let mut methods = vec![];
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        let m_attrs = attributes(input)?;
        methods.push(struct_method(input, &m_attrs)?);
        ws(input)?;
        if input.starts_with(';') {
            *input = &input[1..];
        }
    }
    ws(input)?;
    if !input.starts_with('}') { expected_with_note(input, "'}'", Some((open, "to match this '{'"))); return Err(cut(input)); }
    *input = &input[1..];

    Ok(ExtendDecl { attributes: attrs, target, traits, methods, span: Span { start: decl_start, end: pos(input) }, is_exported: false })
}

fn struct_declaration(input: &mut &str, attrs: Vec<Attribute>) -> Result<StructDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attrs.first().map(|a| a.span.start).unwrap_or(start);
    if !input.starts_with("struct") || input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[6..];
    ws(input)?;

    let name_span_start = pos(input);
    let name = identifier(input)?;
    let name_span_end = pos(input);
    ws(input)?;
    let generic_params = if input.starts_with('<') {
        generic_params(input)?
    } else {
        vec![]
    };
    ws(input)?;

    if !input.starts_with('{') { return Err(cut_expecting(input, "'{'")); }
    let open = pos(input);
    *input = &input[1..];

    let mut fields = vec![];
    let mut methods = vec![];
    let mut constructor = None;
    let mut destructor = None;

    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        // `[Name(args)]` may precede any struct member: method, field, constructor, destructor, extern.
        let m_attrs = attributes(input)?;
        let after_attrs = *input;
        // `new` is the deprecated spelling of `construct`.
        let is_new = input.starts_with("new") && !input[3..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_');
        let is_construct = input.starts_with("construct") && !input[9..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_');
        if is_new || is_construct {
            let construct_span_start = pos(input);
            *input = if is_new { &input[3..] } else { &input[9..] };
            let keyword_span = Span { start: construct_span_start, end: pos(input) };
            if let Some(previous) = &constructor {
                let previous: &FunctionDecl = previous;
                return Err(fail_with(
                    Diagnostic::error(format!("redefinition of the constructor of '{}'", name))
                        .at(Loc::new(FileId::default(), keyword_span))
                        .with_note("previous definition is here", Some(Loc::new(FileId::default(), previous.name_span)))
                        .with_note("a struct has one constructor; give its parameters default values to allow shorter calls", None),
                ));
            }
            if is_new {
                let span = Span { start: construct_span_start, end: construct_span_start + 3 };
                deprecated_syntax(span, "`new`", "constructors are spelled `construct`, matching `destruct`", "construct");
            }
            ws(input)?;
            let construct_span_end = pos(input);
            if !input.starts_with('(') { return Err(cut_expecting(input, "'('")); }
            *input = &input[1..];
            let mut parameters = vec![];
            loop {
                ws(input)?;
                if input.starts_with(')') { break; }
                parameters.push(constructor_parameter(input)?);
                ws(input)?;
                if input.starts_with(',') {
                    *input = &input[1..];
                    continue;
                }
                if !input.starts_with(')') { return Err(cut_expecting(input, "')'")); }
                break;
            }
            *input = &input[1..];
            ws(input)?;
            let body = block(input, vec![])?;
            ws(input)?;
            constructor = Some(FunctionDecl {
                is_exported: false,
                name: "construct".into(),
                name_span: Span { start: construct_span_start, end: construct_span_end },
                generic_params: vec![],
                return_type: TypeName::auto(),
                parameters,
                external: false,
                body: Some(body),
                is_static: false,
                is_indexer: false,
                is_variadic: false,
                span: Span { start: m_attrs.first().map(|a| a.span.start).unwrap_or(construct_span_start), end: pos(input) },
                attributes: m_attrs,
            });
            continue;
        }

        // destructor: `destruct { ... }`
        if input.starts_with("destruct") && !input[8..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            let keyword_span = Span { start: pos(input), end: pos(input) + 8 };
            if destructor.is_some() {
                return Err(error_at(keyword_span, format!("redefinition of the destructor of '{}'", name)));
            }
            *input = &input[8..];
            ws(input)?;
            destructor = Some(block(input, m_attrs)?);
            ws(input)?;
            continue;
        }

        if keyword(&mut { *input }, "extern") && !starts_extern_function_type(input) {
            let m = extern_function_declaration(input, m_attrs)?;
            semicolon(input, m.span.end)?;
            methods.push(m);
            continue;
        }

        if let Ok(m) = struct_method(input, &m_attrs) {
            ws(input)?;
            methods.push(m);
            if input.starts_with(';') {
                *input = &input[1..];
            }
            continue;
        }
        // Method attempt failed (it may have consumed input past the name); restart at the post-attribute position.
        *input = after_attrs;
        // Platform predicates select whole declarations, not individual
        // fields — reject them here rather than silently ignoring them.
        if m_attrs.iter().any(|a| contains_platform_predicate(&a.body)) {
            return Err(cut(input));
        }
        let f = variable_declaration(input, m_attrs)?;
        let end = f.span.end;
        if !decl_boundary(input) {
            *input = after_attrs;
            return Err(bt(input));
        }
        semicolon(input, end)?;
        fields.push(f);
    }

    ws(input)?;
    if !input.starts_with('}') { expected_with_note(input, "'}'", Some((open, "to match this '{'"))); return Err(cut(input)); }
    *input = &input[1..];

    Ok(StructDecl { name, name_span: Span { start: name_span_start, end: name_span_end }, generic_params, fields, methods, constructor, destructor, span: Span { start: decl_start, end: pos(input) }, attributes: attrs, is_exported: false, enumeration: None })
}

/// `enum Name[<T, ...>] [: IntegerType] { Case, Case = value, Case(x: T), ... methods }`.
///
/// The cases come first, separated by commas (a trailing comma is allowed);
/// the list ends at the first case not followed by a comma. Methods follow.
/// A case is never followed by `:` or `{`, which is how `Name(x: T)` is told
/// apart from a method `Name(x: T): R { ... }`.
fn enum_declaration(input: &mut &str, attrs: Vec<Attribute>) -> Result<StructDecl> {
    let start = pos(input);
    let decl_start = attrs.first().map(|a| a.span.start).unwrap_or(start);
    if !keyword(input, "enum") {
        return Err(bt(input));
    }
    ws(input)?;
    let name_span_start = pos(input);
    let name = identifier(input).map_err(|_| cut_expecting(input, "an enum name"))?;
    let name_span = Span { start: name_span_start, end: pos(input) };
    ws(input)?;
    let generic_params = if input.starts_with('<') { generic_params(input)? } else { vec![] };
    ws(input)?;
    let representation = if input.starts_with(':') {
        *input = &input[1..];
        ws(input)?;
        let ty = type_name(input)?;
        ws(input)?;
        Some(ty)
    } else {
        None
    };
    if !input.starts_with('{') { return Err(cut_expecting(input, "'{'")); }
    let open = pos(input);
    *input = &input[1..];

    let mut cases = vec![];
    loop {
        ws(input)?;
        if input.starts_with('}') { break; }
        let checkpoint = *input;
        let case_attrs = attributes(input)?;
        ws(input)?;
        let case_start = case_attrs.first().map(|a| a.span.start).unwrap_or(pos(input));
        let name_start = pos(input);
        let is_static = keyword(&mut { *input }, "static");
        let case_name = match identifier(input) {
            Ok(n) if !is_static => n,
            _ => {
                *input = checkpoint;
                break;
            }
        };
        let case_name_span = Span { start: name_start, end: pos(input) };
        let mut rest = *input;
        ws(&mut rest)?;
        let mut payload = None;
        if rest.starts_with('(') {
            let mut probe = rest;
            let parameters = function_parameters(&mut probe);
            let mut after = probe;
            ws(&mut after)?;
            if parameters.is_err() || after.starts_with(':') || after.starts_with('{') {
                // A method: the cases are over.
                *input = checkpoint;
                break;
            }
            payload = Some(parameters?);
            rest = probe;
        } else if rest.starts_with(':') || rest.starts_with('{') || rest.starts_with('<') {
            *input = checkpoint;
            break;
        }
        *input = rest;
        ws(input)?;
        let mut value = None;
        if input.starts_with('=') && !input.starts_with("==") {
            *input = &input[1..];
            ws(input)?;
            value = Some(expression(input)?);
            ws(input)?;
        }
        cases.push(EnumCase {
            name: case_name,
            name_span: case_name_span,
            value,
            payload,
            attributes: case_attrs,
            span: Span { start: case_start, end: pos(input) },
        });
        if input.starts_with(',') {
            *input = &input[1..];
            continue;
        }
        break;
    }

    let mut methods = vec![];
    loop {
        ws(input)?;
        if input.is_empty() || input.starts_with('}') { break; }
        if input.starts_with(';') {
            *input = &input[1..];
            continue;
        }
        let m_attrs = attributes(input)?;
        ws(input)?;
        let after_attrs = *input;
        match struct_method(input, &m_attrs) {
            Ok(m) => {
                methods.push(m);
                ws(input)?;
            }
            Err(_) => {
                *input = after_attrs;
                expected(input, "a method");
                return Err(cut(input));
            }
        }
    }
    ws(input)?;
    if !input.starts_with('}') { expected_with_note(input, "'}'", Some((open, "to match this '{'"))); return Err(cut(input)); }
    *input = &input[1..];

    Ok(StructDecl {
        name,
        name_span,
        generic_params,
        fields: vec![],
        methods,
        constructor: None,
        destructor: None,
        span: Span { start: decl_start, end: pos(input) },
        attributes: attrs,
        is_exported: false,
        enumeration: Some(EnumBody { representation, cases }),
    })
}

fn type_alias_declaration(input: &mut &str, attrs: Vec<Attribute>) -> Result<TypeAliasDecl> {
    let start = pos(input);
    // Widen the node span to cover any preceding attributes.
    let decl_start = attrs.first().map(|a| a.span.start).unwrap_or(start);
    if !input.starts_with("type") || input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Err(bt(input));
    }
    *input = &input[4..];
    ws(input)?;

    let name_span_start = pos(input);
    let name = identifier(input)?;
    let name_span_end = pos(input);
    ws(input)?;
    let generic_params = if input.starts_with('<') {
        generic_params(input)?
    } else {
        vec![]
    };
    ws(input)?;

    if !input.starts_with('=') { return Err(cut_expecting(input, "'='")); }
    *input = &input[1..];
    ws(input)?;
    let target = type_name(input)?;

    Ok(TypeAliasDecl { name, name_span: Span { start: name_span_start, end: name_span_end }, generic_params, target, span: Span { start: decl_start, end: pos(input) }, attributes: attrs, is_exported: false })
}

/// Consume keyword `kw` if it is next (followed by a non-identifier char).
fn keyword(input: &mut &str, kw: &str) -> bool {
    if input.starts_with(kw) && !input[kw.len()..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        *input = &input[kw.len()..];
        true
    } else {
        false
    }
}

/// A top-level declaration, with an optional `export` modifier after its
/// attributes (`[A] export f()`; `export [A] f()` is an error). Every
/// top-level declaration is private to its file without `export`.
fn declaration(input: &mut &str) -> Result<Declaration> {
    ws(input)?;
    let start = pos(input);
    // Attributes may precede any top-level declaration.
    let leading = attributes(input)?;
    ws(input)?;
    let is_exported = keyword(input, "export");
    if is_exported {
        ws(input)?;
        // `export` goes after the attributes, never before them.
        if input.starts_with('[') {
            return Err(cut(input));
        }
    }
    let mut decl = declaration_body(input, leading)?;
    if is_exported {
        match &mut decl {
            Declaration::Function(f) => { f.is_exported = true; f.span.start = f.span.start.min(start); }
            Declaration::Struct(s) => { s.is_exported = true; s.span.start = s.span.start.min(start); }
            Declaration::TypeAlias(t) => { t.is_exported = true; t.span.start = t.span.start.min(start); }
            Declaration::Trait(t) => { t.is_exported = true; t.span.start = t.span.start.min(start); }
            Declaration::Extend(e) => { e.is_exported = true; e.span.start = e.span.start.min(start); }
            Declaration::Variable(v) => { v.is_exported = true; v.span.start = v.span.start.min(start); }
        }
    }
    Ok(decl)
}

fn declaration_body(input: &mut &str, leading: Vec<Attribute>) -> Result<Declaration> {

    if input.starts_with("struct") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::Struct(struct_declaration(input, leading)?));
    }
    if keyword(&mut { *input }, "enum") {
        return Ok(Declaration::Struct(enum_declaration(input, leading)?));
    }
    if input.starts_with("trait") && !input[5..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::Trait(trait_declaration(input, leading)?));
    }
    if input.starts_with("extend") && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::Extend(extend_declaration(input, leading)?));
    }
    if input.starts_with("type") && !input[4..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
        return Ok(Declaration::TypeAlias(type_alias_declaration(input, leading)?));
    }
    if input.starts_with("extern")
        && !input[6..].starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_')
        && !starts_extern_function_type(input)
    {
        return Ok(Declaration::Function(extern_function_declaration(input, leading)?));
    }
    let before = *input;
    if !leading.is_empty() {
        // Attributed declarations are functions or module-scope variables
        // (`[Target(OS(Windows))] var x = 1;`). Try the function first and
        // report its error if neither parses, so a malformed attributed
        // function keeps its diagnostic.
        let function_err = match function_declaration(input, leading.clone()) {
            Ok(f) => return Ok(Declaration::Function(f)),
            Err(e) => e,
        };
        *input = before;
        if let Ok(v) = variable_declaration(input, leading) {
            if decl_boundary(input) {
                return Ok(Declaration::Variable(v));
            }
        }
        *input = before;
        return Err(function_err);
    }
    if let Ok(f) = function_declaration(input, vec![]) {
        return Ok(Declaration::Function(f));
    }
    *input = before;

    let v = variable_declaration(input, vec![])?;
    if !decl_boundary(input) {
        return Err(bt(input));
    }
    Ok(Declaration::Variable(v))
}

// ── Imports ───────────────────────────────────────────────────────────────────

fn import(input: &mut &str) -> Result<Import> {
    source_import(input, false)
}

/// `export * from source` / `export [a, b as c] from source`: a re-export of
/// another file's or module's exports. Backtracks unless `*` or `[` follows
/// `export`.
fn reexport(input: &mut &str) -> Result<Import> {
    let mut probe = *input;
    ws(&mut probe)?;
    if !keyword(&mut probe, "export") {
        return Err(bt(input));
    }
    ws(&mut probe)?;
    if !probe.starts_with('*') && !probe.starts_with('[') {
        return Err(bt(input));
    }
    source_import(input, true)
}

/// An import, or with `reexport` an `export ... from` re-export, which
/// requires `*` or a symbol list and takes no alias.
fn source_import(input: &mut &str, reexport: bool) -> Result<Import> {
    let start = pos(input);
    ws(input)?;
    if !keyword(input, if reexport { "export" } else { "import" }) {
        return Err(bt(input));
    }
    ws(input)?;

    // `export * from source`
    let star = reexport && input.starts_with('*');
    if star {
        *input = &input[1..];
        ws(input)?;
        if !keyword(input, "from") {
            return Err(cut_expecting(input, "'from'"));
        }
        ws(input)?;
    }

    // `import [a, b as c] from source`
    let symbols = if !star && input.starts_with('[') {
        *input = &input[1..];
        let mut symbols = vec![];
        loop {
            ws(input)?;
            if input.starts_with(']') && symbols.is_empty() {
                break;
            }
            let sym_start = pos(input);
            let name = identifier(input).map_err(|_| cut(input))?;
            let name_span = Span { start: sym_start, end: pos(input) };
            ws(input)?;
            let alias = if keyword(input, "as") {
                ws(input)?;
                Some(identifier(input).map_err(|_| cut(input))?)
            } else {
                None
            };
            symbols.push(ImportedSymbol { name, name_span, alias, span: Span { start: sym_start, end: pos(input) } });
            ws(input)?;
            if input.starts_with(',') {
                *input = &input[1..];
                continue;
            }
            break;
        }
        if !input.starts_with(']') {
            return Err(cut(input));
        }
        *input = &input[1..];
        ws(input)?;
        if !keyword(input, "from") {
            return Err(cut(input));
        }
        ws(input)?;
        Some(symbols)
    } else {
        None
    };

    let name_span_start = pos(input);
    let (name, is_local) = if input.starts_with('"') {
        match string_constant(input)? {
            Literal::String(s) => (s, true),
            _ => return Err(cut(input)),
        }
    } else {
        (identifier(input).map_err(|_| cut(input))?, false)
    };
    let name_span = Span { start: name_span_start, end: pos(input) };
    let mut end = pos(input);

    let before_alias = *input;
    ws(input)?;
    let alias = if keyword(input, "as") {
        // An alias names a qualifier, which a symbol list or a re-export
        // does not bind.
        if symbols.is_some() || reexport {
            return Err(cut(input));
        }
        ws(input)?;
        let alias = identifier(input).map_err(|_| cut(input))?;
        end = pos(input);
        Some(alias)
    } else {
        *input = before_alias;
        None
    };

    Ok(Import { name, name_span, alias, is_local, symbols, reexport, attributes: vec![], span: Span { start, end } })
}

/// `export symbol as name` / `export symbol` / `export m.symbol as name`:
/// a re-export, as opposed to an `export` declaration. Backtracks unless the
/// symbol is followed by `as` or ends the statement.
fn export_alias(input: &mut &str) -> Result<ExportAlias> {
    ws(input)?;
    let start = pos(input);
    if !keyword(input, "export") {
        return Err(bt(input));
    }
    ws(input)?;
    let symbol_start = pos(input);
    let mut symbol = identifier(input)?;
    qualified_tail(input, &mut symbol);
    let symbol_span = Span { start: symbol_start, end: pos(input) };
    let mut end = pos(input);
    let before = *input;
    ws(input)?;
    let alias = if keyword(input, "as") {
        ws(input)?;
        let alias = identifier(input).map_err(|_| cut(input))?;
        end = pos(input);
        Some(alias)
    } else {
        *input = before;
        None
    };
    // A bare `export Box` needs its `;`: without it, `export P` followed by
    // `make() {...}` on the next line is a C-style declaration returning `P`.
    let mut probe = *input;
    ws(&mut probe)?;
    if alias.is_none() && !probe.starts_with(';') {
        return Err(bt(input));
    }
    Ok(ExportAlias { symbol, symbol_span, alias, attributes: vec![], span: Span { start, end } })
}

// ── Module ────────────────────────────────────────────────────────────────────

/// Parse a complete Pepper source file into a `Module` AST.
pub fn parse_module(input: &mut &str) -> Result<Module> {
    ws(input)?;

    let mut imports = vec![];
    let mut exports = vec![];
    let mut declarations = vec![];
    loop {
        ws(input)?;
        if input.is_empty() { break; }

        // Imports and re-exports, each optionally after attributes
        // (`[Target(OS(Linux))] import linux;`). Imports must precede every
        // declaration and re-export; `check_import_order` rejects a late one
        // after parsing.
        let before = *input;
        let attrs_start = pos(input);
        let attrs = if input.starts_with('[') { attributes(input)? } else { vec![] };
        ws(input)?;
        let with_attributes = |span: &mut Span, attributes: &mut Vec<Attribute>, attrs: Vec<Attribute>| {
            if !attrs.is_empty() {
                span.start = attrs_start;
            }
            *attributes = attrs;
        };
        if keyword(&mut { *input }, "import") {
            let mut imp = import(input)?;
            with_attributes(&mut imp.span, &mut imp.attributes, attrs);
            if let Some(q) = imp.qualifier() {
                QUALIFIERS.with(|qs| qs.borrow_mut().insert(q.to_string()));
            }
            semicolon(input, imp.span.end)?;
            imports.push(imp);
            continue;
        }
        if keyword(&mut { *input }, "export") {
            match reexport(input) {
                Ok(mut imp) => {
                    with_attributes(&mut imp.span, &mut imp.attributes, attrs);
                    semicolon(input, imp.span.end)?;
                    imports.push(imp);
                    continue;
                }
                Err(ErrMode::Cut(e)) => return Err(ErrMode::Cut(e)),
                Err(_) => {}
            }
            match export_alias(input) {
                Ok(mut exp) => {
                    with_attributes(&mut exp.span, &mut exp.attributes, attrs);
                    semicolon(input, exp.span.end)?;
                    exports.push(exp);
                    continue;
                }
                Err(ErrMode::Cut(e)) => return Err(ErrMode::Cut(e)),
                Err(_) => {}
            }
        }
        // A declaration parses its own attributes.
        *input = before;

        let at = *input;
        let decl = declaration(input).inspect_err(|_| expected(at, "declaration"))?;
        let needs_semicolon = match &decl {
            Declaration::Variable(_) | Declaration::TypeAlias(_) => true,
            Declaration::Function(f) => f.body.is_none(),
            _ => false,
        };
        if needs_semicolon {
            semicolon(input, decl.span().end)?;
        } else {
            ws(input)?;
            if input.starts_with(';') { *input = &input[1..]; }
        }
        declarations.push(decl);
    }

    // The entire input must have been consumed; a partial parse is an error.
    ws(input)?;
    if !input.is_empty() {
        return Err(cut_expecting(input, "declaration"));
    }

    let warnings = WARNINGS.with(|w| std::mem::take(&mut *w.borrow_mut()));
    Ok(Module { imports, exports, declarations, warnings })
}

// ── C pointer syntax check ───────────────────────────────────────────────────
//
// `T*` is C syntax and belongs only in `extern` declarations, whose parameter
// and return types mirror the C prototype. Everywhere else Pepper spells a
// pointer `__ptr<T>`. The grammar still parses the `*` suffix in every type
// position (so a misplaced `void*` gets this targeted message rather than a
// bare "parse error"); the rule is enforced on the finished AST because PEG
// probes (e.g. `a<b*c` tried as a generic type literal, or `a * b` tried as
// the declaration `a* b`) parse `*`-suffixed types that never reach the tree.

/// Imports must come before every declaration and re-export: qualified
/// generic constructions (`m.Box<int>()`) are recognized from the imports
/// parsed so far.
pub(crate) fn check_import_order(m: &Module) -> std::result::Result<(), PostParseError> {
    let first_item = m.declarations.iter().map(|d| d.span().start).chain(m.exports.iter().map(|e| e.span.start)).min();
    match m.imports.iter().find(|imp| first_item.is_some_and(|f| imp.span.start > f)) {
        Some(imp) => Err(PostParseError {
            offset: imp.span.start,
            message: "imports must come before all declarations".to_string(),
        }),
        None => Ok(()),
    }
}

/// An error found after parsing (a C-style pointer type outside `extern`, a
/// late import): byte offset of the offending node and the message.
pub(crate) struct PostParseError {
    pub offset: usize,
    pub message: String,
}

/// Reject `T*` in every type position outside `extern` function declarations.
pub(crate) fn check_pointer_syntax(m: &Module) -> std::result::Result<(), PostParseError> {
    m.declarations.iter().try_for_each(ptr_check_decl)
}

fn ptr_check_type(t: &TypeName) -> std::result::Result<(), PostParseError> {
    let stars = t.name.len() - t.name.trim_end_matches('*').len();
    if stars > 0 {
        let base = TypeName { name: t.name[..t.name.len() - stars].to_string(), ..t.clone() };
        let written = format!("{}{}", base, "*".repeat(stars));
        let suggested = format!("{}{}{}", "__ptr<".repeat(stars), base, ">".repeat(stars));
        return Err(PostParseError {
            offset: t.span.start,
            message: format!(
                "C pointer syntax `{}` is only allowed in extern declarations; use `{}`",
                written, suggested
            ),
        });
    }
    t.generic_types.iter().try_for_each(ptr_check_type)
}

fn ptr_check_attrs(attrs: &[Attribute]) -> std::result::Result<(), PostParseError> {
    attrs.iter().try_for_each(|a| ptr_check_expr(&a.body))
}

fn ptr_check_generic_params(ps: &[GenericParam]) -> std::result::Result<(), PostParseError> {
    ps.iter().filter_map(|p| p.default.as_ref()).try_for_each(ptr_check_type)
}

fn ptr_check_var(v: &VariableDecl) -> std::result::Result<(), PostParseError> {
    ptr_check_attrs(&v.attributes)?;
    ptr_check_type(&v.type_name)?;
    v.default_value.as_ref().map_or(Ok(()), ptr_check_expr)
}

fn ptr_check_fn(f: &FunctionDecl) -> std::result::Result<(), PostParseError> {
    ptr_check_attrs(&f.attributes)?;
    if f.external {
        // Extern prototypes mirror C and may use `T*` freely.
        return Ok(());
    }
    ptr_check_generic_params(&f.generic_params)?;
    ptr_check_type(&f.return_type)?;
    f.parameters.iter().try_for_each(ptr_check_var)?;
    f.body.as_ref().map_or(Ok(()), ptr_check_block)
}

fn ptr_check_decl(d: &Declaration) -> std::result::Result<(), PostParseError> {
    match d {
        Declaration::Variable(v) => ptr_check_var(v),
        Declaration::Function(f) => ptr_check_fn(f),
        Declaration::Struct(s) => {
            ptr_check_attrs(&s.attributes)?;
            ptr_check_generic_params(&s.generic_params)?;
            s.fields.iter().try_for_each(ptr_check_var)?;
            s.methods.iter().try_for_each(ptr_check_fn)?;
            s.constructor.as_ref().map_or(Ok(()), ptr_check_fn)?;
            for case in s.enumeration.iter().flat_map(|e| &e.cases) {
                ptr_check_attrs(&case.attributes)?;
                case.payload.iter().flatten().try_for_each(ptr_check_var)?;
            }
            s.destructor.as_ref().map_or(Ok(()), ptr_check_block)
        }
        Declaration::Trait(t) => {
            ptr_check_attrs(&t.attributes)?;
            ptr_check_generic_params(&t.generic_params)?;
            t.methods.iter().try_for_each(ptr_check_fn)
        }
        Declaration::Extend(e) => {
            ptr_check_attrs(&e.attributes)?;
            ptr_check_type(&e.target)?;
            e.traits.iter().try_for_each(ptr_check_type)?;
            e.methods.iter().try_for_each(ptr_check_fn)
        }
        Declaration::TypeAlias(a) => {
            ptr_check_attrs(&a.attributes)?;
            ptr_check_generic_params(&a.generic_params)?;
            ptr_check_type(&a.target)
        }
    }
}

fn ptr_check_block(b: &Block) -> std::result::Result<(), PostParseError> {
    ptr_check_attrs(&b.attributes)?;
    b.statements.iter().try_for_each(ptr_check_stmt)
}

fn ptr_check_stmt(s: &Statement) -> std::result::Result<(), PostParseError> {
    match s {
        Statement::Expression(e) => ptr_check_expr(e),
        Statement::Block(b) => ptr_check_block(b),
        Statement::Declaration(d) => ptr_check_decl(d),
        Statement::Branch(b) => {
            ptr_check_expr(&b.condition)?;
            ptr_check_block(&b.if_block)?;
            b.else_block.as_ref().map_or(Ok(()), ptr_check_block)
        }
        Statement::While(w) => {
            ptr_check_expr(&w.condition)?;
            ptr_check_block(&w.block)
        }
        Statement::For(fr) => {
            ptr_check_type(&fr.binding.type_name)?;
            ptr_check_expr(&fr.iterable)?;
            ptr_check_block(&fr.block)
        }
        Statement::With(w) => {
            if let Some(b) = &w.binding {
                ptr_check_type(&b.type_name)?;
            }
            ptr_check_expr(&w.scope)?;
            ptr_check_block(&w.block)?;
            w.else_block.as_ref().map_or(Ok(()), ptr_check_block)
        }
        Statement::Return(r) => r.expr.as_ref().map_or(Ok(()), ptr_check_expr),
        Statement::LoopBreak(_) => Ok(()),
        Statement::Destructure(d) => {
            for b in &d.bindings {
                ptr_check_type(&b.type_name)?;
            }
            ptr_check_expr(&d.value)
        }
        Statement::Match(m) => {
            ptr_check_expr(&m.value)?;
            m.arms.iter().try_for_each(|arm| ptr_check_block(&arm.body))?;
            m.else_arm.as_ref().map_or(Ok(()), |(_, b)| ptr_check_block(b))
        }
    }
}

fn ptr_check_expr(e: &Expression) -> std::result::Result<(), PostParseError> {
    match e {
        Expression::Literal { .. } | Expression::SymbolRef { .. } => Ok(()),
        Expression::TypeLiteral(t) | Expression::SizeOf(t) => ptr_check_type(t),
        Expression::Unary { operand, .. } => ptr_check_expr(operand),
        Expression::Cast { expr, ty, .. } => {
            ptr_check_expr(expr)?;
            ptr_check_type(ty)
        }
        Expression::Binary { lhs, rhs, .. } | Expression::Index { lhs, rhs, .. } => {
            ptr_check_expr(lhs)?;
            ptr_check_expr(rhs)
        }
        Expression::Ternary { condition, true_expr, false_expr, .. } => {
            ptr_check_expr(condition)?;
            ptr_check_expr(true_expr)?;
            ptr_check_expr(false_expr)
        }
        Expression::MemberAccess { lhs, .. } => ptr_check_expr(lhs),
        Expression::FunctionCall { function, arguments, .. } => {
            ptr_check_expr(function)?;
            arguments.iter().try_for_each(ptr_check_expr)
        }
        Expression::Closure(c) => {
            for p in &c.parameters {
                ptr_check_type(&p.type_name)?;
            }
            ptr_check_type(&c.return_type)?;
            ptr_check_block(&c.body)
        }
        Expression::Tuple { elements, .. } => elements.iter().try_for_each(ptr_check_expr),
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Module {
        let _guard = track_source(s.len());
        let mut input = s;
        parse_module(&mut input).expect("parse should succeed")
    }

    fn parse_expr(s: &str) -> Expression {
        let _guard = track_source(s.len());
        let mut input = s;
        expression(&mut input).expect("expression parse should succeed")
    }

    // ── Function types ──

    fn parse_type(s: &str) -> TypeName {
        let _guard = track_source(s.len());
        let mut input = s;
        type_name(&mut input).expect("type parse should succeed")
    }

    #[test]
    fn function_type_lowers_to_function_generic() {
        let ty = parse_type("(int, String) => bool");
        assert_eq!(ty.name, FUNCTION_TYPE);
        let args: Vec<String> = ty.generic_types.iter().map(|t| t.to_string()).collect();
        assert_eq!(args, ["bool", "int", "String"]);
        assert_eq!(ty.to_string(), "(int, String) => bool");
    }

    #[test]
    fn extern_function_types() {
        let ty = parse_type("extern (void*, int) => int");
        assert_eq!(ty.name, EXTERN_FUNCTION_TYPE);
        let args: Vec<String> = ty.generic_types.iter().map(|t| t.to_string()).collect();
        assert_eq!(args, ["int", "void*", "int"]);
        assert_eq!(ty.to_string(), "extern (void*, int) => int");
        assert_eq!(parse_type("extern () => void*").to_string(), "extern () => void*");
        // `extern (` starts a field or variable, not an extern function.
        assert!(starts_extern_function_type("extern (int) => int f;"));
        assert!(!starts_extern_function_type("extern int abs(int x);"));
        assert!(!starts_extern_function_type("externs"));
    }

    #[test]
    fn function_type_arrow_is_right_associative() {
        let ty = parse_type("(int) => (int) => int");
        assert_eq!(ty.to_string(), "(int) => (int) => int");
        assert_eq!(ty.generic_types[0].name, FUNCTION_TYPE);
        assert_eq!(parse_type("() => void").to_string(), "() => void");
        assert_eq!(parse_type("Array<(int) => int>").to_string(), "Array<(int) => int>");
    }

    #[test]
    fn function_types_in_declarations() {
        let m = parse("apply(f: (int) => int, x: int): (int) => int { var g: (int) => int = f; return g; }\n\
                       struct S { var op: (String) => void; }\n\
                       type Op = (int) => int;\n");
        let Declaration::Function(f) = &m.declarations[0] else { panic!("expected a function") };
        assert_eq!(f.parameters[0].type_name.to_string(), "(int) => int");
        assert_eq!(f.return_type.to_string(), "(int) => int");
    }

    #[test]
    fn shared_function_types() {
        let ty = parse_type("shared (int) => bool");
        assert_eq!(ty.name, SHARED_FUNCTION_TYPE);
        let args: Vec<String> = ty.generic_types.iter().map(|t| t.to_string()).collect();
        assert_eq!(args, ["bool", "int"]);
        assert_eq!(ty.to_string(), "shared (int) => bool");
        assert_eq!(ty.span.start, 0);
        assert_eq!(parse_type("shared() => void").to_string(), "shared () => void");
        assert_eq!(parse_type("Array<shared () => void>").to_string(), "Array<shared () => void>");
        assert_eq!(parse_type("shared (int) => shared () => int").to_string(), "shared (int) => shared () => int");
        // Anywhere else `shared` is an ordinary name.
        assert_eq!(parse_type("shared").to_string(), "shared");
        assert_eq!(parse_type("shared_thing").to_string(), "shared_thing");
        let m = parse("run(f: shared () => void): shared (int) => int { var g: shared () => void = f; var shared = 1; shared(shared); return h; }\n\
                       struct S { const op: shared (String) => void; }\n\
                       type Op = shared (int) => int;\n");
        let Declaration::Function(f) = &m.declarations[0] else { panic!("expected a function") };
        assert_eq!(f.parameters[0].type_name.to_string(), "shared () => void");
        assert_eq!(f.return_type.to_string(), "shared (int) => int");
    }

    #[test]
    fn parenthesized_expressions_are_not_function_types() {
        let m = parse("f(): int { var a = (1 + 2) * 3; (a) + 1; return (a); }\n");
        assert_eq!(m.declarations.len(), 1);
    }

    // ── Closure literals ──

    fn closure(s: &str) -> ClosureLiteral {
        match parse_expr(s) {
            Expression::Closure(c) => *c,
            other => panic!("expected a closure, got {:?}", other),
        }
    }

    #[test]
    fn closure_with_an_expression_body() {
        let c = closure("(x: int, y) => x + y");
        let params: Vec<String> = c.parameters.iter().map(|p| format!("{}:{}", p.name, p.type_name)).collect();
        assert_eq!(params, ["x:int", "y:__auto"]);
        assert!(c.expression_body);
        assert_eq!(c.return_type.name, AUTO_TYPE);
        assert_eq!(parse_expr("(x: int, y) => x + y").to_string(), "(x: int, y) => (x + y)");
    }

    #[test]
    fn closure_with_a_block_body_and_return_type() {
        let c = closure("(x): (int) => int => { return (y) => x + y; }");
        assert!(!c.expression_body);
        assert_eq!(c.return_type.to_string(), "(int) => int");
        assert_eq!(c.body.statements.len(), 1);
        let empty = closure("() => {}");
        assert!(empty.parameters.is_empty());
    }

    #[test]
    fn named_method_span_starts_at_its_declaration() {
        // The span covers `static` and the name, so a `##` doc comment
        // directly above the method is found.
        let source = "struct S {\n    ## Doc.\n    static make(): S { return S(); }\n    size(): int { return 0; }\n}";
        let module = parse(source);
        let Declaration::Struct(s) = &module.declarations[0] else { panic!("expected a struct") };
        assert_eq!(s.methods[0].span.start, source.find("static").unwrap());
        assert_eq!(s.methods[1].span.start, source.find("size").unwrap());
    }

    #[test]
    fn closure_body_extends_to_the_end_of_the_expression() {
        let c = closure("(a) => (b) => a + b");
        let [Statement::Return(ReturnStatement { expr: Some(Expression::Closure(inner)), .. })] = c.body.statements.as_slice() else {
            panic!("expected a closure returning a closure")
        };
        assert_eq!(inner.parameters[0].name, "b");
    }

    #[test]
    fn parenthesized_expressions_are_not_closures() {
        assert!(matches!(parse_expr("(a + b) * 2"), Expression::Binary { .. }));
        assert!(matches!(parse_expr("c ? (x) : y"), Expression::Ternary { .. }));
        assert!(matches!(parse_expr("(f)(1)"), Expression::FunctionCall { .. }));
        let m = parse("f(): int { apply((x) => x * 2, 3); return ((x: int) => x)(1); }\n");
        assert_eq!(m.declarations.len(), 1);
    }

    // ── Literals ──

    #[test]
    fn test_int_literal() {
        let e = parse_expr("42");
        match e {
            Expression::Literal { value: Literal::Integer(42), .. } => {}
            other => panic!("expected int 42, got {:?}", other),
        }
    }

    #[test]
    fn test_negative_int() {
        let e = parse_expr("-7");
        match e {
            Expression::Unary { op, prefix, operand, .. } => {
                assert_eq!(op, "-");
                assert!(prefix);
                match *operand {
                    Expression::Literal { value: Literal::Integer(7), .. } => {}
                    other => panic!("expected 7, got {:?}", other),
                }
            }
            other => panic!("expected unary, got {:?}", other),
        }
    }

    #[test]
    fn test_float_literal() {
        let e = parse_expr("3.14");
        match e {
            Expression::Literal { value: Literal::Float(v), .. } => assert!((v - 3.14).abs() < 1e-9),
            other => panic!("expected float, got {:?}", other),
        }
    }

    #[test]
    fn test_bool_literals() {
        match parse_expr("true") {
            Expression::Literal { value: Literal::Bool(true), .. } => {}
            other => panic!("expected true, got {:?}", other),
        }
        match parse_expr("false") {
            Expression::Literal { value: Literal::Bool(false), .. } => {}
            other => panic!("expected false, got {:?}", other),
        }
    }

    #[test]
    fn test_string_literal() {
        let e = parse_expr("\"hello world\"");
        match e {
            Expression::Literal { value: Literal::String(s), .. } => assert_eq!(s, "hello world"),
            other => panic!("expected String, got {:?}", other),
        }
    }

    #[test]
    fn test_char_literal() {
        for (source, byte) in [("'a'", b'a'), ("'\"'", b'"'), ("'#'", b'#'), ("'\\n'", b'\n'), ("'\\''", b'\''), ("'\\xFF'", 0xFF)] {
            match parse_expr(source) {
                Expression::Literal { value: Literal::Char(b), .. } => {
                    assert_eq!(b, byte, "{}", source);
                    let printed = Literal::Char(b).to_string();
                    assert!(matches!(parse_expr(&printed), Expression::Literal { value: Literal::Char(c), .. } if c == b), "{} round-trips", printed);
                }
                other => panic!("expected Char for {}, got {:?}", source, other),
            }
        }
    }


    // ── Identifiers & refs ──

    #[test]
    fn test_symbol_ref() {
        let e = parse_expr("my_var");
        match e {
            Expression::SymbolRef { id: name, .. } => assert_eq!(name, "my_var"),
            other => panic!("expected symbol ref, got {:?}", other),
        }
    }

    // ── Binary operators ──

    #[test]
    fn test_addition() {
        let e = parse_expr("1 + 2");
        match e {
            Expression::Binary { lhs, op, rhs, .. } => {
                assert_eq!(op, "+");
                match *lhs { Expression::Literal { value: Literal::Integer(1), .. } => {}, o => panic!("{:?}", o) }
                match *rhs { Expression::Literal { value: Literal::Integer(2), .. } => {}, o => panic!("{:?}", o) }
            }
            other => panic!("expected binary +, got {:?}", other),
        }
    }

    #[test]
    fn test_precedence_mul_before_add() {
        // 1 + 2 * 3 should parse as 1 + (2 * 3), not (1 + 2) * 3
        let e = parse_expr("1 + 2 * 3");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "+", "top-level should be +"),
            other => panic!("expected binary, got {:?}", other),
        }
    }

    #[test]
    fn test_powers_right_assoc() {
        // 2 ** 3 ** 2 should parse as 2 ** (3 ** 2)
        let e = parse_expr("2 ** 3 ** 2");
        match e {
            Expression::Binary { op, rhs, .. } => {
                assert_eq!(op, "**");
                match *rhs {
                    Expression::Binary { op: inner_op, .. } => assert_eq!(inner_op, "**"),
                    other => panic!("expected nested **, got {:?}", other),
                }
            }
            other => panic!("expected **, got {:?}", other),
        }
    }

    #[test]
    fn test_comparison_ops() {
        for (src, expected_op) in [
            ("a == b", "=="),
            ("a != b", "!="),
            ("a < b", "<"),
            ("a > b", ">"),
            ("a <= b", "<="),
            ("a >= b", ">="),
        ] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected binary {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    #[test]
    fn test_logical_ops() {
        for (src, expected_op) in [
            ("a && b", "&&"),
            ("a || b", "||"),
            ("a and b", "and"),
            ("a or b", "or"),
        ] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected binary {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    // ── Assignment ──

    #[test]
    fn test_assignment() {
        let e = parse_expr("x = 42");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "="),
            other => panic!("expected =, got {:?}", other),
        }
    }

    #[test]
    fn test_compound_assignment() {
        for (src, expected_op) in [
            ("x += 1", "+="),
            ("x -= 1", "-="),
            ("x *= 2", "*="),
            ("x /= 2", "/="),
            ("x <<= 1", "<<="),
            ("x >>= 1", ">>="),
            ("x &= 1", "&="),
            ("x |= 1", "|="),
            ("x ^= 1", "^="),
        ] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    #[test]
    fn test_shift_ops() {
        for (src, expected_op) in [("a << 2", "<<"), ("a >> 2", ">>"), ("a << b << c", "<<")] {
            let e = parse_expr(src);
            match e {
                Expression::Binary { op, .. } => assert_eq!(op, expected_op, "for src={}", src),
                other => panic!("expected {} for {}, got {:?}", expected_op, src, other),
            }
        }
    }

    #[test]
    fn test_shift_precedence() {
        // `a << b + c` binds `b + c` first
        let e = parse_expr("a << b + c");
        match e {
            Expression::Binary { op, rhs, .. } => {
                assert_eq!(op, "<<");
                match *rhs {
                    Expression::Binary { op, .. } => assert_eq!(op, "+"),
                    other => panic!("expected add in rhs, got {:?}", other),
                }
            }
            other => panic!("expected shift, got {:?}", other),
        }
    }

    #[test]
    fn test_compound_vs_binary_minus() {
        // `a - 1` must stay a binary minus, not trip over `-=` handling
        let e = parse_expr("a - 1");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "-"),
            other => panic!("expected binary minus, got {:?}", other),
        }
        // `a - -b` is binary minus applied to unary minus
        let e = parse_expr("a - -b");
        match e {
            Expression::Binary { op, rhs, .. } => {
                assert_eq!(op, "-");
                match *rhs {
                    Expression::Unary { .. } => {}
                    other => panic!("expected unary in rhs, got {:?}", other),
                }
            }
            other => panic!("expected binary minus, got {:?}", other),
        }
    }

    // ── Ternary ──

    #[test]
    fn test_ternary() {
        let e = parse_expr("a ? b : c");
        match e {
            Expression::Ternary { .. } => {}
            other => panic!("expected ternary, got {:?}", other),
        }
    }

    // ── Member access & indexing ──

    #[test]
    fn test_member_access() {
        let e = parse_expr("obj.field");
        match e {
            Expression::MemberAccess { name, .. } => assert_eq!(name, "field"),
            other => panic!("expected member access, got {:?}", other),
        }
    }

    #[test]
    fn test_index() {
        let e = parse_expr("arr[0]");
        match e {
            Expression::Index { .. } => {}
            other => panic!("expected index, got {:?}", other),
        }
    }

    // ── Function calls ──

    #[test]
    fn test_function_call_no_args() {
        let e = parse_expr("foo()");
        match e {
            Expression::FunctionCall { function, arguments, .. } => {
                assert!(arguments.is_empty());
                match *function {
                    Expression::SymbolRef { id: n, .. } => assert_eq!(n, "foo"),
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("expected call, got {:?}", other),
        }
    }

    #[test]
    fn test_function_call_with_args() {
        let e = parse_expr("foo(1, 2, 3)");
        match e {
            Expression::FunctionCall { arguments, .. } => assert_eq!(arguments.len(), 3),
            other => panic!("expected call, got {:?}", other),
        }
    }

    // ── Parentheses ──

    #[test]
    fn test_parenthesized_expr() {
        let e = parse_expr("(1 + 2) * 3");
        // Top-level should be * (multiplication), not +
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "*"),
            other => panic!("expected *, got {:?}", other),
        }
    }

    // ── sizeof ──

    #[test]
    fn test_sizeof() {
        let e = parse_expr("sizeof<int>");
        match e {
            Expression::SizeOf(ty) => assert_eq!(ty.name, "int"),
            other => panic!("expected sizeof, got {:?}", other),
        }
    }

    #[test]
    fn test_sizeof_with_parens() {
        // Both `sizeof<T>` and `sizeof<T>()` must parse to a `SizeOf` node.
        let e = parse_expr("sizeof<int>()");
        match e {
            Expression::SizeOf(ty) => assert_eq!(ty.name, "int"),
            other => panic!("expected sizeof, got {:?}", other),
        }
        // `sizeof<T>()` inside a larger expression
        let e = parse_expr("malloc(4 * sizeof<int>())");
        match e {
            Expression::FunctionCall { .. } => {}
            other => panic!("expected call, got {:?}", other),
        }
    }

    // ── Type names ──

    #[test]
    fn test_type_name_simple() {
        let mut input = "int";
        let ty = type_name(&mut input).unwrap();
        assert_eq!(ty.name, "int");
        assert!(ty.generic_types.is_empty());
    }

    #[test]
    fn test_type_name_optional() {
        let _guard = track_source(16);
        for (text, expected) in [
            ("int?", "Optional<int>"),
            ("Array<int?>", "Array<Optional<int>>"),
            ("int[]?", "Optional<int[]>"),
            ("int??", "Optional<Optional<int>>"),
        ] {
            let mut input = text;
            let ty = type_name(&mut input).unwrap();
            assert_eq!(ty.to_string(), expected, "{text}");
            assert!(input.is_empty(), "{text}: left {input:?}");
            assert_eq!(ty.span.end - ty.span.start, text.len(), "{text}: span");
        }
    }

    #[test]
    fn test_optional_declarations_and_ternaries() {
        let m = parse(
            "struct S {\n    Token? leaf;\n}\nf(x: int?): String? {\n    Node? a = x;\n    Node? b;\n    var c: Array<int?> = Array<int?>();\n    c ? d : e;\n    var g = h ? i : j;\n    return k < l ? m : n;\n}\n",
        );
        let text = format!("{:?}", m);
        // leaf, x, the result, a, b, and c's type and its literal.
        assert_eq!(text.matches("\"Optional\"").count(), 7, "optional types: {text}");
        assert_eq!(text.matches("Ternary").count(), 3, "ternaries: {text}");
    }

    #[test]
    fn test_type_name_generic() {
        let mut input = "Array<int>";
        let ty = type_name(&mut input).unwrap();
        assert_eq!(ty.name, "Array");
        assert_eq!(ty.generic_types.len(), 1);
        assert_eq!(ty.generic_types[0].name, "int");
    }

    #[test]
    fn test_type_name_array() {
        let mut input = "int[]";
        let ty = type_name(&mut input).unwrap();
        assert_eq!(ty.name, "int[]");
    }

    // ── Variable declarations ──

    #[test]
    fn test_var_declaration() {
        let mut input = "var x: int = 42";
        let decl = variable_declaration(&mut input, vec![]).unwrap();
        assert_eq!(decl.name, "x");
        assert_eq!(decl.type_name.name, "int");
        assert!(!decl.is_const);
        assert!(decl.default_value.is_some());
    }

    #[test]
    fn test_const_declaration() {
        let mut input = "const MAX = 100";
        let decl = variable_declaration(&mut input, vec![]).unwrap();
        assert_eq!(decl.name, "MAX");
        assert!(decl.is_const);
    }

    #[test]
    fn test_type_name_declaration() {
        let mut input = "int count = 0";
        let decl = variable_declaration(&mut input, vec![]).unwrap();
        assert_eq!(decl.name, "count");
        assert_eq!(decl.type_name.name, "int");
    }

    // ── Modules ──

    #[test]
    fn test_module_with_import() {
        let m = parse("import \"test\";\nfoo() {}");
        assert_eq!(m.imports.len(), 1);
        assert!(m.imports[0].is_local);
        assert_eq!(m.imports[0].name, "test");
    }

    #[test]
    fn test_module_with_package_import() {
        let m = parse("import mylib;\nfoo() {}");
        assert_eq!(m.imports.len(), 1);
        assert!(!m.imports[0].is_local);
        assert_eq!(m.imports[0].name, "mylib");
    }

    #[test]
    fn test_module_with_import_alias() {
        let m = parse("import mylib as m;\nfoo() {}");
        assert_eq!(m.imports.len(), 1);
        assert_eq!(m.imports[0].alias.as_deref(), Some("m"));
        assert_eq!(m.imports[0].qualifier(), Some("m"));
    }

    #[test]
    fn test_import_forms() {
        let m = parse(
            "import geometry\nimport \"shapes\";\nimport \"util\" as u;\n\
             import [sqrt, pow as power] from math;\nimport [a] from \"file\";\nfoo() {}",
        );
        assert_eq!(m.imports.len(), 5);
        assert_eq!(m.imports[0].qualifier(), Some("geometry"));
        assert!(m.imports[1].is_local && m.imports[1].qualifier().is_none());
        assert_eq!(m.imports[2].qualifier(), Some("u"));
        let symbols = m.imports[3].symbols.as_ref().expect("symbol list");
        assert_eq!(m.imports[3].name, "math");
        assert_eq!(symbols.iter().map(|s| s.local_name()).collect::<Vec<_>>(), vec!["sqrt", "power"]);
        assert_eq!(symbols[1].name, "pow");
        assert!(m.imports[3].qualifier().is_none());
        assert!(m.imports[4].is_local);
        assert_eq!(m.to_string().lines().nth(3), Some("import [sqrt, pow as power] from math;"));
        assert_eq!(m.declarations.len(), 1);
    }

    #[test]
    fn test_import_and_export_attributes() {
        let m = parse("[Target(OS(Linux))] import linux;\n[Target(OS(Linux))] export open as o;\n[Target(OS(Linux))] f() {}");
        assert_eq!(m.imports[0].attributes.len(), 1);
        assert_eq!(m.imports[0].span.start, 0);
        assert_eq!(m.exports[0].attributes.len(), 1);
        assert_eq!(m.exports[0].exported_name(), "o");
        assert_eq!(m.declarations.len(), 1);
        assert!(m.to_string().starts_with("[Target(OS(Linux))] import linux;"), "{}", m);
    }

    #[test]
    fn test_export_alias() {
        let m = parse("export helper as help;\nexport m.sqrt as root\nexport Box;\nexport f(): int { return 0; }\nexport var x = 1;");
        assert_eq!(m.exports.len(), 3);
        assert_eq!((m.exports[0].symbol.as_str(), m.exports[0].exported_name()), ("helper", "help"));
        assert_eq!((m.exports[1].symbol.as_str(), m.exports[1].exported_name()), ("m.sqrt", "root"));
        assert_eq!((m.exports[2].symbol.as_str(), m.exports[2].exported_name()), ("Box", "Box"));
        assert_eq!(m.declarations.len(), 2);
        assert!(matches!(&m.declarations[0], Declaration::Function(f) if f.is_exported));
        // A bare re-export needs its `;`; without one, a return type on its
        // own line starts an exported C-style declaration.
        let m = parse("export Box; # the box\nexport P\nmake() { return P(); }");
        assert_eq!(m.exports.iter().map(|e| e.symbol.as_str()).collect::<Vec<_>>(), vec!["Box"]);
        assert!(matches!(&m.declarations[0], Declaration::Function(f) if f.name == "make" && f.is_exported && f.return_type.name == "P"));
    }

    #[test]
    fn test_qualified_names() {
        let m = parse("import geo;\nf(p: geo.Point, b: geo.Box<geo.Point>[]): int { var q = geo.Box<int>(); return geo.area(1, 2); }");
        let Declaration::Function(f) = &m.declarations[0] else { panic!("function") };
        assert_eq!(f.parameters[0].type_name.name, "geo.Point");
        assert_eq!(f.parameters[1].type_name.to_string(), "geo.Box[]<geo.Point>");
        let Statement::Declaration(Declaration::Variable(v)) = &f.body.as_ref().unwrap().statements[0] else { panic!("var") };
        let Some(Expression::FunctionCall { function, .. }) = &v.default_value else { panic!("call") };
        assert!(matches!(function.as_ref(), Expression::TypeLiteral(t) if t.name == "geo.Box"));
        // A comparison after a member access is still a comparison.
        assert!(matches!(parse_expr("a.b < c"), Expression::Binary { .. }));
        let Expression::FunctionCall { arguments, .. } = parse_expr("f(a.b < c, d > e)") else { panic!("call") };
        assert_eq!(arguments.len(), 2);
        assert!(arguments.iter().all(|a| matches!(a, Expression::Binary { .. })));
        for src in ["g.Box<int> ()", "g.Box<int>[]()"] {
            let m = parse(&format!("import g;\nf() {{ var x = {}; }}", src));
            let Declaration::Function(f) = &m.declarations[0] else { panic!("function") };
            let Statement::Declaration(Declaration::Variable(v)) = &f.body.as_ref().unwrap().statements[0] else { panic!("var") };
            let Some(Expression::FunctionCall { function, .. }) = &v.default_value else { panic!("call: {}", src) };
            assert!(matches!(function.as_ref(), Expression::TypeLiteral(t) if t.name.starts_with("g.Box")), "{}", src);
        }
        // A member of a qualified generic type.
        let m = parse("import c;
f() { var r = c.Result<int>.ok(1); }");
        let Declaration::Function(f) = &m.declarations[0] else { panic!("function") };
        let Statement::Declaration(Declaration::Variable(v)) = &f.body.as_ref().unwrap().statements[0] else { panic!("var") };
        let Some(Expression::FunctionCall { function, .. }) = &v.default_value else { panic!("call") };
        let Expression::MemberAccess { lhs, name, .. } = function.as_ref() else { panic!("member") };
        assert!(name == "ok" && matches!(lhs.as_ref(), Expression::TypeLiteral(t) if t.name == "c.Result"));
        // Without an import of `a`, a generic-looking member comparison is
        // two comparisons, on either side of the `<`.
        for src in ["f(a.b < c, d > (e))", "g(i < a.size, i > 0)"] {
            let Expression::FunctionCall { arguments, .. } = parse_expr(src) else { panic!("call: {}", src) };
            assert_eq!(arguments.len(), 2, "{}", src);
        }
        assert!(matches!(parse_expr("x < p.mask >> 1"), Expression::Binary { op, .. } if op == "<"));
        // A qualified C-style return type.
        let m = parse("import g;\ng.Point origin() { return g.Point(); }\ntrait T { g.Point at(); }");
        let Declaration::Function(f) = &m.declarations[0] else { panic!("function") };
        assert_eq!((f.name.as_str(), f.return_type.name.as_str()), ("origin", "g.Point"));
        let Declaration::Trait(t) = &m.declarations[1] else { panic!("trait") };
        assert_eq!((t.methods[0].name.as_str(), t.methods[0].return_type.name.as_str()), ("at", "g.Point"));
    }

    #[test]
    fn test_import_errors() {
        for src in ["use \"lib\";", "import;", "import [a b] from m;", "import [a] m;", "import [a] from m as n;"] {
            let _guard = track_source(src.len());
            let mut input = src;
            assert!(parse_module(&mut input).is_err(), "should reject: {}", src);
        }
    }

    #[test]
    fn test_module_function() {
        let m = parse("main(): int {\n    return 42;\n}");
        assert_eq!(m.declarations.len(), 1);
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.name, "main");
                assert_eq!(f.return_type.name, "int");
            }
            other => panic!("expected function, got {:?}", other),
        }
    }

    #[test]
    fn test_module_struct() {
        let m = parse("struct Point {\n    int x = 0;\n    int y = 0;\n}");
        assert_eq!(m.declarations.len(), 1);
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.name, "Point");
                assert_eq!(s.fields.len(), 2);
            }
            other => panic!("expected struct, got {:?}", other),
        }
    }

    #[test]
    fn test_module_struct_generic() {
        let m = parse("struct Pair<A, B> {\n    A first;\n    B second;\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.name, "Pair");
                assert_eq!(s.generic_params.len(), 2);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_module_struct_generic_default_param() {
        let m = parse("struct Result<TValue, TError=MyError> {\n    TValue value;\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.generic_params.len(), 2);
                assert_eq!(s.generic_params[0].name, "TValue");
                assert!(s.generic_params[0].default.is_none());
                assert_eq!(s.generic_params[1].name, "TError");
                let d = s.generic_params[1].default.as_ref().expect("default present");
                assert_eq!(d.name, "MyError");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_module_type_alias() {
        let m = parse("type I = int;");
        assert_eq!(m.declarations.len(), 1);
        match &m.declarations[0] {
            Declaration::TypeAlias(t) => {
                assert_eq!(t.name, "I");
                assert!(t.generic_params.is_empty());
                assert_eq!(t.target.name, "int");
                assert!(t.target.generic_types.is_empty());
            }
            other => panic!("expected type alias, got {:?}", other),
        }
    }

    #[test]
    fn test_module_type_alias_generic_target() {
        let m = parse("type Pair = Result<int, Error>;");
        match &m.declarations[0] {
            Declaration::TypeAlias(t) => {
                assert_eq!(t.name, "Pair");
                assert_eq!(t.target.name, "Result");
                assert_eq!(t.target.generic_types.len(), 2);
                assert_eq!(t.target.generic_types[0].name, "int");
                assert_eq!(t.target.generic_types[1].name, "Error");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_module_type_alias_generic_params() {
        let m = parse("type R<T, E=Error> = Result<T, E>;");
        match &m.declarations[0] {
            Declaration::TypeAlias(t) => {
                assert_eq!(t.generic_params.len(), 2);
                assert_eq!(t.generic_params[0].name, "T");
                assert!(t.generic_params[0].default.is_none());
                assert_eq!(t.generic_params[1].name, "E");
                let d = t.generic_params[1].default.as_ref().expect("default present");
                assert_eq!(d.name, "Error");
                assert_eq!(t.target.name, "Result");
                assert_eq!(t.target.generic_types[0].name, "T");
                assert_eq!(t.target.generic_types[1].name, "E");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_type_alias_rejects_bad_forms() {
        for src in [
            "type X;",      // missing `= Target`
            "type X = ;",   // missing target
            "type = int;",  // missing alias name
        ] {
            let mut input = src;
            assert!(parse_module(&mut input).is_err(), "should reject: {}", src);
        }
    }

    #[test]
    fn test_module_comments() {
        let src = "# this is a comment\nfoo() {} # another comment\n";
        let m = parse(src);
        assert_eq!(m.declarations.len(), 1);
    }

    #[test]
    fn test_extern_function() {
        let m = parse("extern int my_func(int a, int b);");
        assert_eq!(m.declarations.len(), 1);
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert!(f.external);
                assert_eq!(f.name, "my_func");
                assert_eq!(f.parameters.len(), 2);
            }
            other => panic!("{:?}", other),
        }
    }

    // ── Statements ──

    #[test]
    fn test_if_else() {
        let mut input = "if x > 0 {\n    y = 1;\n} else {\n    y = 2;\n}";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::Branch(b) => {
                assert!(b.else_block.is_some());
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_while_loop() {
        let mut input = "while i < 10 {\n    i += 1;\n}";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::While(_) => {}
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_for_loop_forms() {
        for (src, name, ty) in [
            ("for (var x in nums) { total += x; }", "x", "__auto"),
            ("for var x in nums { total += x; }", "x", "__auto"),
            ("for (int x in nums) { total += x; }", "x", "int"),
            ("for (var x: int in nums) { total += x; }", "x", "int"),
            ("for (var p in make_points()) { }", "p", "__auto"),
        ] {
            let mut input = src;
            match statement(&mut input).unwrap_or_else(|e| panic!("{}: {:?}", src, e)) {
                Statement::For(f) => {
                    assert_eq!(f.binding.name, name, "{}", src);
                    assert_eq!(f.binding.type_name.to_string(), ty, "{}", src);
                }
                other => panic!("{}: {:?}", src, other),
            }
            assert!(input.trim().is_empty(), "{}: left {:?}", src, input);
        }
    }

    #[test]
    fn test_with_forms() {
        for (src, name, ty, scope, has_else) in [
            ("with (var p = this.parent) { p.touch(); }", Some("p"), "__auto", "this.parent", false),
            ("with var p = parent { } else { orphan(); }", Some("p"), "__auto", "parent", true),
            ("with (Node n = weak) { }", Some("n"), "Node", "weak", false),
            ("with (var n: Node = weak) { } else { }", Some("n"), "Node", "weak", true),
            ("with (lock) { count += 1; }", None, "", "lock", false),
            ("with (this.mutex.lock()) { }", None, "", "this.mutex.lock()", false),
            ("with (File.open(path)) { } else { }", None, "", "File.open(path)", true),
        ] {
            let _guard = track_source(src.len());
            let mut input = src;
            match statement(&mut input).unwrap_or_else(|e| panic!("{}: {:?}", src, e)) {
                Statement::With(w) => {
                    assert_eq!(w.binding.as_ref().map(|b| b.name.as_str()), name, "{}", src);
                    if let Some(b) = &w.binding {
                        assert_eq!(b.type_name.to_string(), ty, "{}", src);
                        assert!(b.default_value.is_none(), "{}", src);
                    }
                    assert_eq!(w.scope.to_string().replace(' ', ""), scope.replace(' ', ""), "{}", src);
                    assert_eq!(w.else_block.is_some(), has_else, "{}", src);
                }
                other => panic!("{}: {:?}", src, other),
            }
            assert!(input.trim().is_empty(), "{}: left {:?}", src, input);
        }
    }

    #[test]
    fn test_with_rejects_malformed_headers() {
        for src in [
            "with (var x) { }",          // a binding needs the scope: `var x = scope`
            "with (const x = s) { }",    // the binding is not const
            "with (var x = s { }",       // unclosed header
            "with (s) ",                 // no body
        ] {
            let _guard = track_source(src.len());
            let mut input = src;
            assert!(statement(&mut input).is_err(), "{} should not parse", src);
        }
    }

    #[test]
    fn test_for_loop_rejects_malformed_headers() {
        for src in [
            "for (x in nums) { }",          // binding needs `var` or a type
            "for (var x = 1 in nums) { }",  // no default value
            "for (const x in nums) { }",    // loop variable is not const
            "for (var x of nums) { }",      // `in`, not `of`
            "for (var x in nums { }",       // unclosed header
        ] {
            let mut input = src;
            assert!(statement(&mut input).is_err(), "{} should not parse", src);
        }
    }

    #[test]
    fn test_for_prefixed_identifiers_are_not_loops() {
        let mut input = "format(x)";
        assert!(matches!(statement(&mut input).unwrap(), Statement::Expression(_)));
        let mut input = "var forward = 1";
        assert!(matches!(statement(&mut input).unwrap(), Statement::Declaration(_)));
    }

    #[test]
    fn test_return_statement() {
        let mut input = "return 42;";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::Return(r) => {
                match r.expr {
                    Some(Expression::Literal { value: Literal::Integer(42), .. }) => {}
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_expression_statement() {
        let mut input = "print(\"hello\");";
        let stmt = statement(&mut input).unwrap();
        match stmt {
            Statement::Expression(e) => {
                match e {
                    Expression::FunctionCall { .. } => {}
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    // ── Semicolons and line breaks ──

    /// The statements of a function whose body is `body`.
    fn statements_of(body: &str) -> Vec<Statement> {
        let src = format!("f() {{\n{body}\n}}\n");
        let m = parse(&src);
        match &m.declarations[0] {
            Declaration::Function(f) => f.body.clone().unwrap().statements,
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn line_breaks_never_end_an_expression() {
        for body in [
            "x = a\n    + b;",
            "x = a +\n    b;",
            "x = y\n-z;",
            "foo\n(bar);",
            "n = items\n    .filter(p)\n    .count();",
            "x = c\n    ? a\n    : b;",
            "x = a # why\n    + b;",
            "return\n    x;",
        ] {
            assert_eq!(statements_of(body).len(), 1, "{body:?}");
        }
    }

    #[test]
    fn statements_are_separated_by_semicolons() {
        assert_eq!(statements_of("x = 1; y = 2;").len(), 2);
        let statements = statements_of("return;");
        assert!(matches!(&statements[0], Statement::Return(ReturnStatement { expr: None, .. })));
        // Leaving the `;` out still separates them, with a warning each.
        let m = parse("f() {\n    x = 1 y = 2\n    var z = 3\n    z = 4\n}\n");
        let Declaration::Function(f) = &m.declarations[0] else { panic!() };
        assert_eq!(f.body.as_ref().unwrap().statements.len(), 4);
        assert_eq!(m.warnings.len(), 4);
    }

    #[test]
    fn a_missing_semicolon_is_deprecated() {
        let m = parse("import io\nvar x = 1  # one\nstruct S {\n    int y\n}\nf() {\n    x = 2\n    if x > 1 { return }\n}\n");
        let at: Vec<usize> = m.warnings.iter().map(|w| w.loc.unwrap().span.start).collect();
        // After `io`, `1`, `y`, `2` and `return`.
        assert_eq!(at, vec![9, 19, 47, 65, 87]);
        assert!(m.warnings.iter().all(|w| w.fixes[0].edits[0].replacement == ";"));
        let m = parse("import io;\nvar x = 1;\nstruct S {\n    int y;\n}\nf() {\n    x = 2;\n    if x > 1 { return; }\n}\n");
        assert!(m.warnings.is_empty(), "{:?}", m.warnings);
    }

    #[test]
    fn a_declaration_missing_its_semicolon_ends_at_its_line() {
        let m = parse("var x = 1  # note\nvar y = x\n");
        assert_eq!(m.declarations.len(), 2);
        assert_eq!(m.warnings.len(), 2);
    }

    // ── Struct features: constructors, destructors, static, indexers, operator overloads ──

    #[test]
    fn test_constructor_with_this_initializers() {
        let m = parse("struct S {\n    int x;\n    construct(this.x = 0) {\n        x += 1;\n    }\n    destruct {\n        x = 0;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.name, "S");
                let c = s.constructor.as_ref().expect("constructor");
                assert_eq!(c.name, "construct");
                assert_eq!(c.parameters.len(), 1);
                assert_eq!(c.parameters[0].name, "this.x");
                assert!(c.parameters[0].default_value.is_some());
                assert!(s.destructor.is_some());
                assert_eq!(s.destructor.as_ref().unwrap().statements.len(), 1);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_new_constructor_is_deprecated() {
        // `new` still parses, with a warning whose fix spells it `construct`
        let src = "struct S {\n    int x;\n    new(this.x = 1) {}\n}";
        let m = parse(src);
        match &m.declarations[0] {
            Declaration::Struct(s) => assert_eq!(s.constructor.as_ref().expect("constructor").name, "construct"),
            other => panic!("{:?}", other),
        }
        assert_eq!(m.warnings.len(), 1);
        let w = &m.warnings[0];
        assert_eq!(w.code, Some(crate::diagnostic::DEPRECATED));
        let start = src.find("new").unwrap();
        assert_eq!(w.fixes[0].edits[0].loc.span, Span { start, end: start + 3 });
        assert_eq!(w.fixes[0].edits[0].replacement, "construct");
        assert_eq!(
            w.render_in("t.pep", src),
            "t.pep:3:5: warning: `new` is deprecated; constructors are spelled `construct`, matching `destruct` [deprecated]\n\
             \x20   3 |     new(this.x = 1) {}\n\
             \x20     |     ^~~\n\
             \x20     |     construct"
        );
        assert!(parse("struct S {\n    construct() {}\n}").warnings.is_empty());
    }

    #[test]
    fn test_static_and_indexer_methods() {
        let m = parse("struct S {\n    static helper(int v): int {\n        return v;\n    }\n    int [](int i) {\n        return i;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.methods.len(), 2);
                assert!(s.methods[0].is_static);
                assert_eq!(s.methods[0].name, "helper");
                assert!(!s.methods[1].is_static);
                assert!(s.methods[1].is_indexer);
                assert_eq!(s.methods[1].name, "__index_get");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_operator_named_methods() {
        let m = parse("struct S {\n    int v;\n    bool ==(int o) {\n        return o;\n    }\n    S +=(int o) {\n        v += o;\n        return v;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.methods.len(), 2);
                assert_eq!(s.methods[0].name, "==");
                assert_eq!(s.methods[1].name, "+=");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn pepper_style_operators_indexers_and_constructor_parameters() {
        // `name: Type` everywhere, and the same AST as the C-style forms.
        let pepper = "struct S {\n    int v;\n    construct(a: int = 1, this.v = 0, int b = 2) {}\n    ==(o: S): bool { return true; }\n    \
                      static +(a: S, b: S): S { return a; }\n    <(o: S): bool { return false; }\n    >>=(n: int): S { return this; }\n    \
                      [](i: ulong): int { return v; }\n    [](i: ulong, x: int): void { v = x; }\n}\n";
        let c_style = "struct S {\n    int v;\n    construct(int a = 1, this.v = 0, int b = 2) {}\n    bool ==(S o) { return true; }\n    \
                       static S +(S a, S b) { return a; }\n    <(o: S): bool { return false; }\n    S >>=(int n) { return this; }\n    \
                       int [](ulong i) { return v; }\n    void [](ulong i, int x) { v = x; }\n}\n";
        let m = parse(pepper);
        let Declaration::Struct(s) = &m.declarations[0] else { panic!("expected a struct") };
        let names: Vec<&str> = s.methods.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(names, ["==", "+", "<", ">>=", "__index_get", "__index_set"]);
        assert!(s.methods[1].is_static);
        assert!(s.methods[4].is_indexer && s.methods[5].is_indexer);
        assert_eq!(s.methods[0].span.start, pepper.find("==(").unwrap());
        assert_eq!(m.to_string(), parse(c_style).to_string());
    }

    #[test]
    fn test_as_cast() {
        let e = parse_expr("x as int");
        match e {
            Expression::Cast { expr, ty, .. } => {
                assert_eq!(ty.to_string(), "int");
                match *expr {
                    Expression::SymbolRef { id, .. } => assert_eq!(id, "x"),
                    other => panic!("expected x, got {:?}", other),
                }
            }
            other => panic!("expected cast, got {:?}", other),
        }
    }

    #[test]
    fn test_as_cast_precedence() {
        // Casts bind tighter than unary (C-style): `-x as int` is `-(x as int)`.
        // With truncation-toward-zero this is observationally identical to
        // `(-x) as int`; the grouping only matters in the AST.
        let e = parse_expr("-x as int");
        match e {
            Expression::Unary { op, operand, .. } => {
                assert_eq!(op, "-");
                match *operand {
                    Expression::Cast { ty, .. } => assert_eq!(ty.to_string(), "int"),
                    other => panic!("expected cast, got {:?}", other),
                }
            }
            other => panic!("expected unary -, got {:?}", other),
        }

        let e = parse_expr("2 ** 3 as float");
        match e {
            Expression::Cast { expr, ty, .. } => {
                assert_eq!(ty.to_string(), "float");
                match *expr {
                    Expression::Binary { op, .. } => assert_eq!(op, "**"),
                    other => panic!("expected ** binary, got {:?}", other),
                }
            }
            other => panic!("expected cast, got {:?}", other),
        }
    }

    #[test]
    fn test_null_literal() {
        let e = parse_expr("x = __null");
        match e {
            Expression::Binary { rhs, .. } => match *rhs {
                Expression::Literal { value: Literal::Null, .. } => {}
                other => panic!("{:?}", other),
            },
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_identity_operator() {
        let e = parse_expr("a === b");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "==="),
            other => panic!("{:?}", other),
        }
        // `a == b` must not swallow a third `=` and vice versa
        let e = parse_expr("a == b");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "=="),
            other => panic!("{:?}", other),
        }
        // `!==` is one operator, not `!=` followed by `=`
        let e = parse_expr("a !== b");
        match e {
            Expression::Binary { op, .. } => assert_eq!(op, "!=="),
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_trait_and_extend() {
        let m = parse("trait XGetter {\n    getX(): int;\n}\nstruct Test {\n    int x;\n}\nextend Test with XGetter {\n    getX(): int {\n        return x;\n    }\n}");
        assert_eq!(m.declarations.len(), 3);
        match &m.declarations[0] {
            Declaration::Trait(t) => {
                assert_eq!(t.name, "XGetter");
                assert_eq!(t.methods.len(), 1);
                assert!(t.methods[0].body.is_none());
            }
            other => panic!("{:?}", other),
        }
        match &m.declarations[2] {
            Declaration::Extend(e) => {
                assert_eq!(e.target.name, "Test");
                assert_eq!(e.traits.len(), 1);
                assert_eq!(e.traits[0].name, "XGetter");
                assert_eq!(e.methods.len(), 1);
                assert!(e.methods[0].body.is_some());
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_generic_constructor_call() {
        // `Array<int>()` is a type-literal call with generic argument
        let e = parse_expr("Array<int>()");
        match e {
            Expression::FunctionCall { function, arguments, .. } => {
                assert!(arguments.is_empty());
                match *function {
                    Expression::TypeLiteral(t) => {
                        assert_eq!(t.name, "Array");
                        assert_eq!(t.generic_types.len(), 1);
                        assert_eq!(t.generic_types[0].name, "int");
                    }
                    other => panic!("{:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_extern_pointer_params() {
        let m = parse("extern int strncmp(char* a, char* b, uint n)");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert!(f.external);
                assert!(f.body.is_none());
                assert_eq!(f.parameters.len(), 3);
                assert_eq!(f.parameters[0].type_name.name, "char*");
                assert_eq!(f.parameters[1].type_name.name, "char*");
                assert_eq!(f.parameters[2].type_name.name, "uint");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_parse_rejects_garbage() {
        // `parse_module` must fail loudly instead of skipping over bad tokens
        let bad_sources = [
            "int x = 1 junk leftover",
            "struct S { int x = }",
            "int x = ;",
            "while { }",
        ];
        for src in bad_sources {
            let mut input = src;
            assert!(parse_module(&mut input).is_err(), "should reject: {}", src);
        }
        // and a valid program must still succeed
        let mut input = "int x = 1;";
        assert!(parse_module(&mut input).is_ok());
    }

    // ── Attributes ──

    fn assert_int_arg(e: &Expression, n: i64) {
        match e {
            Expression::Literal { value: Literal::Integer(v), .. } => assert_eq!(*v, n),
            other => panic!("expected int literal {}, got {:?}", n, other),
        }
    }
    #[test]
    fn test_function_attributes() {
        // Syntax 1: `name(params) : ret { body }` — multiple attributes, mixed args.
        let m = parse("[A(1, 2)] [B] main(): int {\n    return 42;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.name, "main");
                assert_eq!(f.attributes.len(), 2);
                let (name, args) = attr_call_name_args(&f.attributes[0].body);
                assert_eq!(name, "A");
                assert_eq!(args.len(), 2);
                assert_int_arg(&args[0], 1);
                assert_int_arg(&args[1], 2);
                assert_bare_attr(&f.attributes[1].body, "B");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_function_attributes_return_type_prefix() {
        // Syntax 2: `TypeName name(params) { body }` — attributes still attach to the function.
        let m = parse("[Export(\"x\")] String hello() {\n    return \"\";\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.name, "hello");
                assert_eq!(f.attributes.len(), 1);
                let (name, args) = attr_call_name_args(&f.attributes[0].body);
                assert_eq!(name, "Export");
                assert_eq!(args.len(), 1);
                match &args[0] {
                    Expression::Literal { value: Literal::String(s), .. } => assert_eq!(s, "x"),
                    other => panic!("expected String arg, got {:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_extern_function_attributes() {
        let m = parse("[Export(\"x\")] extern int my_func(int a);");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert!(f.external);
                assert_eq!(f.name, "my_func");
                assert_eq!(f.attributes.len(), 1);
                let (name, args) = attr_call_name_args(&f.attributes[0].body);
                assert_eq!(name, "Export");
                assert_eq!(args.len(), 1);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_struct_attributes() {
        let m = parse("[Align(16)] struct Point {\n    int x = 0;\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.name, "Point");
                assert_eq!(s.attributes.len(), 1);
                let (name, args) = attr_call_name_args(&s.attributes[0].body);
                assert_eq!(name, "Align");
                assert_int_arg(&args[0], 16);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_struct_member_attributes() {
        let m = parse("struct S {\n    [ReadOnly] int x = 0;\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.fields.len(), 1);
                assert_eq!(s.fields[0].name, "x");
                assert_eq!(s.fields[0].attributes.len(), 1);
                assert_bare_attr(&s.fields[0].attributes[0].body, "ReadOnly");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_block_attributes() {
        let m = parse("main(): int {\n    var y = 1;\n    [Scope] {\n        y = 2;\n    }\n    return y;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                let body = f.body.as_ref().expect("body");
                assert_eq!(body.statements.len(), 3);
                match &body.statements[1] {
                    Statement::Block(b) => {
                        assert_eq!(b.attributes.len(), 1);
                        assert_bare_attr(&b.attributes[0].body, "Scope");
                    }
                    other => panic!("expected attributed block, got {:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_trait_attributes() {
        let m = parse("[Cacheable] trait Shape {\n    int area();\n}");
        match &m.declarations[0] {
            Declaration::Trait(t) => {
                assert_eq!(t.name, "Shape");
                assert_eq!(t.attributes.len(), 1);
                assert_bare_attr(&t.attributes[0].body, "Cacheable");
                assert_eq!(t.methods.len(), 1);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_extend_attributes() {
        let m = parse("[Inline] extend Point with Shape {\n    int area() {\n        return 1;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Extend(e) => {
                assert_eq!(e.target.name, "Point");
                assert_eq!(e.attributes.len(), 1);
                assert_bare_attr(&e.attributes[0].body, "Inline");
                assert_eq!(e.traits.len(), 1);
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_method_attributes() {
        // Struct method (named form, via `named_function`).
        let m = parse("struct S {\n    [Inline] [Opt(2)] area(): int {\n        return 1;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.methods.len(), 1);
                assert_eq!(s.methods[0].name, "area");
                assert_eq!(s.methods[0].attributes.len(), 2);
                assert_bare_attr(&s.methods[0].attributes[0].body, "Inline");
                let (name, _) = attr_call_name_args(&s.methods[0].attributes[1].body);
                assert_eq!(name, "Opt");
                assert_eq!(s.to_string(), "struct S {\n    [Inline] [Opt(2)] area(): int {\n    return 1;\n}\n}");
            }
            other => panic!("{:?}", other),
        }

        // Trait method (return-type prefix form, bodyless).
        let m = parse("trait Shape {\n    [Cacheable] int area();\n}");
        match &m.declarations[0] {
            Declaration::Trait(t) => {
                assert_eq!(t.methods[0].name, "area");
                assert_eq!(t.methods[0].attributes.len(), 1);
                assert_bare_attr(&t.methods[0].attributes[0].body, "Cacheable");
                assert_eq!(t.to_string(), "trait Shape {\n    [Cacheable] area(): int;\n}");
            }
            other => panic!("{:?}", other),
        }

        // Extend method (return-type prefix form).
        let m = parse("extend Point with Shape {\n    [Inline] int area() {\n        return 1;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Extend(e) => {
                assert_eq!(e.methods.len(), 1);
                assert_eq!(e.methods[0].name, "area");
                assert_eq!(e.methods[0].attributes.len(), 1);
                assert_bare_attr(&e.methods[0].attributes[0].body, "Inline");
                assert_eq!(e.to_string(), "extend Point with Shape {\n    [Inline] area(): int {\n    return 1;\n}\n}");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_struct_ctor_destructor_extern_attributes() {
        // Attributes on constructor, destructor, and extern members.
        let m = parse("struct S {\n    int x;\n    [Export] construct(this.x = 0) {\n        x += 1;\n    }\n    [Cleanup(1)] destruct {\n        x = 0;\n    }\n    [Inline] extern int helper(int a);\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                let c = s.constructor.as_ref().expect("constructor present");
                assert_eq!(c.attributes.len(), 1);
                assert_bare_attr(&c.attributes[0].body, "Export");
                assert_eq!(s.destructor.as_ref().unwrap().attributes.len(), 1);
                let (name, _) = attr_call_name_args(&s.destructor.as_ref().unwrap().attributes[0].body);
                assert_eq!(name, "Cleanup");
                assert_eq!(s.methods.len(), 1);
                assert_eq!(s.methods[0].name, "helper");
                assert_eq!(s.methods[0].attributes.len(), 1);
                assert_bare_attr(&s.methods[0].attributes[0].body, "Inline");
                assert_eq!(s.to_string(), "struct S {\n    var x: int\n    [Export] construct(var this.x: __auto = 0) {\n    (x += 1);\n}\n    [Cleanup(1)] destruct {\n    (x = 0);\n}\n    [Inline] extern int helper(var a: int)\n}");
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_attribute_display() {
        // Bare attributes must not gain empty parens.
        let m = parse("[A(1, 2)] [B] main(): int {\n    return 42;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => assert_eq!(f.to_string(), "[A(1, 2)] [B] main(): int {\n    return 42;\n}"),
            other => panic!("{:?}", other),
        }
        let m = parse("[Export(\"x\")] extern int my_func(int a);");
        match &m.declarations[0] {
            Declaration::Function(f) => assert_eq!(f.to_string(), "[Export(\"x\")] extern int my_func(var a: int)"),
            other => panic!("{:?}", other),
        }
        let m = parse("[Align(16)] struct Point {\n    int x = 0;\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => assert_eq!(s.to_string(), "[Align(16)] struct Point {\n    var x: int = 0\n}"),
            other => panic!("{:?}", other),
        }
        let m = parse("[Cacheable] trait Shape {\n    int area();\n}");
        match &m.declarations[0] {
            Declaration::Trait(t) => assert_eq!(t.to_string(), "[Cacheable] trait Shape {\n    area(): int;\n}"),
            other => panic!("{:?}", other),
        }
        let m = parse("[Inline] extend Point with Shape {\n    int area() {\n        return 1;\n    }\n}");
        match &m.declarations[0] {
            Declaration::Extend(e) => assert_eq!(e.to_string(), "[Inline] extend Point with Shape {\n    area(): int {\n    return 1;\n}\n}"),
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_attributed_module_variable() {
        // Module-scope variables take attributes (for `[Target(...)]`).
        let m = parse("[Target(OS(Windows))] var x = 1;\n[Target(!OS(Windows))] int y = 2;");
        for (decl, name) in m.declarations.iter().zip(["x", "y"]) {
            match decl {
                Declaration::Variable(v) => {
                    assert_eq!(v.name, name);
                    assert_eq!(v.attributes.len(), 1);
                }
                other => panic!("{:?}", other),
            }
        }
    }

    #[test]
    fn test_attribute_errors() {
        // Malformed attributes and attributes in unsupported positions must be rejected.
        let bad_sources = [
            "[A(1] f() {}",
            "[A f() {}",
            "[] f() {}",
            "[1] f() {}",
            "[A] { }",
            "[A(1+] f() {}",
        ];
        for src in bad_sources {
            let mut input = src;
            assert!(parse_module(&mut input).is_err(), "should reject: {}", src);
        }
    }

    // ── Platform selection attribute (Target) ───────────────────────────────
    /// Returns `(name, args)` for an attribute body that is a `Name(args)` call.
    fn attr_call_name_args(body: &Expression) -> (&str, &[Expression]) {
        match body {
            Expression::FunctionCall { function, arguments, .. } => match function.as_ref() {
                Expression::SymbolRef { id, .. } => (id.as_str(), arguments),
                other => panic!("expected call target symbol, got {:?}", other),
            },
            other => panic!("expected attribute call, got {:?}", other),
        }
    }

    fn assert_bare_attr(body: &Expression, name: &str) {
        match body {
            Expression::SymbolRef { id, .. } => assert_eq!(id, name),
            other => panic!("expected bare attribute {}, got {:?}", name, other),
        }
    }

    /// Asserts `e` is a `Target(...)` call with exactly one argument and
    /// returns that argument.
    fn target_argument(e: &Expression) -> &Expression {
        let (name, args) = attr_call_name_args(e);
        assert_eq!(name, "Target");
        assert_eq!(args.len(), 1, "Target takes exactly one value");
        &args[0]
    }

    fn assert_os_call(e: &Expression, value: &str) {
        let (name, args) = attr_call_name_args(e);
        assert_eq!(name, "OS");
        assert_eq!(args.len(), 1);
        match &args[0] {
            Expression::SymbolRef { id, .. } => assert_eq!(id, value),
            other => panic!("expected SymbolRef {}, got {:?}", value, other),
        }
    }

    #[test]
    fn test_platform_target_wraps_os_or() {
        // `[Target(OS(Windows) || OS(Mac))]` is one attribute whose single
        // argument is a binary OR over two OS calls.
        let m = parse("[Target(OS(Windows) || OS(Mac))] main(): int {\n    return 42;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.attributes.len(), 1);
                match target_argument(&f.attributes[0].body) {
                    Expression::Binary { op, lhs, rhs, .. } => {
                        assert_eq!(op.as_str(), "||");
                        assert_os_call(lhs, "Windows");
                        assert_os_call(rhs, "Mac");
                    }
                    other => panic!("expected || binary, got {:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_platform_negated_os_inside_target() {
        // `[Target(!OS(Windows))]` is a single unary-`!` inside the argument.
        let m = parse("[Target(!OS(Windows))] main(): int {\n    return 42;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.attributes.len(), 1);
                match target_argument(&f.attributes[0].body) {
                    Expression::Unary { op, prefix, operand, .. } => {
                        assert_eq!(op.as_str(), "!");
                        assert!(*prefix);
                        assert_os_call(operand, "Windows");
                    }
                    other => panic!("expected unary !, got {:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_platform_target_composite() {
        // `[Target(OS(Windows) && Arch(x64))]` combines OS and Arch inside.
        let m = parse("[Target(OS(Windows) && Arch(x64))] main(): int {\n    return 42;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.attributes.len(), 1);
                match target_argument(&f.attributes[0].body) {
                    Expression::Binary { op, lhs, rhs, .. } => {
                        assert_eq!(op.as_str(), "&&");
                        assert_os_call(lhs, "Windows");
                        let (name, args) = attr_call_name_args(rhs);
                        assert_eq!(name, "Arch");
                        match &args[0] {
                            Expression::SymbolRef { id, .. } => assert_eq!(id, "x64"),
                            other => panic!("expected SymbolRef x64, got {:?}", other),
                        }
                    }
                    other => panic!("expected && binary, got {:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_platform_block_in_body() {
        // Attributed block inside a body carries the platform predicate.
        let m = parse("main(): int {\n    [Target(OS(Windows))] {\n        return 1;\n    }\n    return 2;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                let body = f.body.as_ref().expect("body");
                assert_eq!(body.statements.len(), 2);
                match &body.statements[0] {
                    Statement::Block(b) => {
                        assert_eq!(b.attributes.len(), 1);
                        assert_os_call(target_argument(&b.attributes[0].body), "Windows");
                    }
                    other => panic!("expected attributed block, got {:?}", other),
                }
            }
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn test_malformed_attribute_body_is_hard_error() {
        // A body that fails to parse inside `[...]` is a hard error at the
        // brackets (cut), not a backtrack that leaves a dangling `[` to be
        // misreported on the next declaration. Top-level boolean logic is
        // also rejected: there is no context for it outside Target(...).
        for s in [
            "[]\ntest(): int {\n    return 0;\n}",
            "[*]\ntest(): int {\n    return 0;\n}",
            "[if x { }]\ntest(): int {\n    return 0;\n}",
            // Top-level boolean logic is not an attribute.
            "[OS(Windows) || OS(Mac)]\ntest(): int {\n    return 0;\n}",
            "[!OS(Windows)]\ntest(): int {\n    return 0;\n}",
            "[Target(OS(Windows)) && Export]\ntest(): int {\n    return 0;\n}",
        ] {
            let _guard = track_source(s.len());
            let mut input = s;
            assert!(parse_module(&mut input).is_err(), "expected parse error for: {s}");
        }
    }

    #[test]
    fn test_field_platform_predicate_rejected() {
        // Platform predicates select whole declarations, not individual
        // fields — a predicate on a field is a hard parse error.
        for s in [
            "struct S {\n    [Target(OS(Windows))] int x;\n}",
            "struct S {\n    [Target(Arch(x64))] int x;\n}",
            "struct S {\n    [Target(!OS(Linux) || OS(Mac))] int x;\n}",
        ] {
            let _guard = track_source(s.len());
            let mut input = s;
            assert!(parse_module(&mut input).is_err(), "expected parse error for: {s}");
        }
    }

    #[test]
    fn test_field_non_predicate_attribute_allowed() {
        // Non-predicate attributes on fields keep working.
        let m = parse("struct S {\n    [Export] int x;\n}");
        match &m.declarations[0] {
            Declaration::Struct(s) => {
                assert_eq!(s.fields.len(), 1);
                assert_eq!(s.fields[0].attributes.len(), 1);
            }
            other => panic!("expected struct, got {:?}", other),
        }
    }

    #[test]
    fn test_attribute_display_no_outer_parens() {
        // The argument prints bare inside the call parens — the diagnostic
        // must quote what the user typed, without doubled parens.
        let m = parse("[Target(OS(Windows) || OS(Mac))] f(): int {\n    return 0;\n}");
        match &m.declarations[0] {
            Declaration::Function(f) => {
                assert_eq!(f.attributes.len(), 1);
                assert_eq!(f.attributes[0].to_string(), "[Target(OS(Windows) || OS(Mac))]");
            }
            other => panic!("expected function, got {:?}", other),
        }
    }

    #[test]
    fn test_export_modifier() {
        let m = parse(
            "export struct S { }
struct P { }
export type T = int;
type U = int;
             export f(): int { return 0; }
g(): int { return 0; }
             [Target(OS(Linux))] export h() { }
             export extern void abort();
extern int puts(char* s);
             export trait Tr { }
trait Tq { }
export extend S { }
extend P { }
             export var x = 1;
var y = 2;
export const z = 3;",
        );
        let exported: Vec<(String, bool)> = m
            .declarations
            .iter()
            .map(|d| match d {
                Declaration::Struct(s) => (s.name.clone(), s.is_exported),
                Declaration::TypeAlias(t) => (t.name.clone(), t.is_exported),
                Declaration::Function(f) => (f.name.clone(), f.is_exported),
                Declaration::Trait(t) => (t.name.clone(), t.is_exported),
                Declaration::Extend(e) => (format!("extend {}", e.target.name), e.is_exported),
                Declaration::Variable(v) => (v.name.clone(), v.is_exported),
            })
            .collect();
        let expected: Vec<(String, bool)> = [
            ("S", true), ("P", false), ("T", true), ("U", false), ("f", true), ("g", false),
            ("h", true), ("abort", true), ("puts", false), ("Tr", true), ("Tq", false),
            ("extend S", true), ("extend P", false), ("x", true), ("y", false), ("z", true),
        ]
        .iter()
        .map(|&(n, e)| (n.to_string(), e))
        .collect();
        assert_eq!(exported, expected);
        // Display round-trips the modifier, after any attributes.
        let text = m.to_string();
        for needle in [
            "export struct S", "export type T = int", "[Target(OS(Linux))] export h()", "export trait Tr",
            "export extend S", "export var x", "export const z",
        ] {
            assert!(text.contains(needle), "missing {:?} in {}", needle, text);
        }
    }

    #[test]
    fn test_export_before_attributes_is_rejected() {
        assert!(crate::parser::parse_source("t.pep", "export [Target(OS(Linux))] f() { }").is_err());
        assert!(crate::parser::parse_source("t.pep", "[Target(OS(Linux))] export f() { }").is_ok());
    }

    // ── Enums and match ──

    fn enum_of(m: &Module) -> (&StructDecl, &EnumBody) {
        match &m.declarations[0] {
            Declaration::Struct(s) => (s, s.enumeration.as_ref().expect("an enum")),
            other => panic!("not an enum: {:?}", other),
        }
    }

    #[test]
    fn enum_cases_are_a_comma_separated_list() {
        let m = parse("export enum Kind: u8 { A, B = 5, [Target(OS(Linux))] C, }");
        let (decl, body) = enum_of(&m);
        assert_eq!(decl.name, "Kind");
        assert!(decl.is_exported);
        assert_eq!(body.representation.as_ref().map(|t| t.to_string()).as_deref(), Some("u8"));
        let names: Vec<&str> = body.cases.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, ["A", "B", "C"]);
        assert!(body.cases[1].value.is_some());
        assert_eq!(body.cases[2].attributes.len(), 1);
        // No trailing comma, and payloads.
        let m = parse("enum Shape { Circle(radius: int), Square(side: int) }");
        let (_, body) = enum_of(&m);
        assert_eq!(body.cases[0].payload.as_ref().map(|p| p.len()), Some(1));
    }

    #[test]
    fn methods_follow_the_cases() {
        let m = parse("enum Color { Red, Green\n    name(): String { return \"\"; }\n}");
        let (decl, body) = enum_of(&m);
        assert_eq!(body.cases.len(), 2);
        assert_eq!(decl.methods.len(), 1);
        assert!(crate::parser::parse_source("t.pep", "enum Color { Red Green }").is_err());
    }

    #[test]
    fn match_statement_arms_and_else() {
        let m = parse("f(c: Color) { match (c) { Red, Color.Green => { } Blue => { } else => { } } }");
        let Declaration::Function(f) = &m.declarations[0] else { panic!() };
        let Statement::Match(found) = &f.body.as_ref().unwrap().statements[0] else { panic!() };
        assert_eq!(found.arms.len(), 2);
        let patterns: Vec<String> = found.arms[0].patterns.iter().map(|p| p.to_string()).collect();
        assert_eq!(patterns, ["Red", "Color.Green"]);
        assert!(found.else_arm.is_some());
        let shown = found.to_string();
        assert!(shown.starts_with("match (c) {"), "{}", shown);
        // `match` and `enum` are reserved.
        assert!(crate::parser::parse_source("t.pep", "f() { var match = 1; }").is_err());
        assert!(crate::parser::parse_source("t.pep", "f() { var enum = 1; }").is_err());
    }
}
