//! What a `static` block expands to, written back out as source, for
//! `--emit-static` (Pepper's `cc -E`).
//!
//! While [`record`] runs, `static_blocks::expand` renders each block it
//! expands as text beside the statements it builds: every emitted
//! statement is its source as written, with each placeholder
//! ([`Expression::StaticValue`](crate::model::Expression::StaticValue),
//! [`Expression::StaticMember`](crate::model::Expression::StaticMember))
//! replaced by the source of what it became ([`Edit`]), and each `x.Type`
//! and type parameter by the type it names. The driver splices the result
//! into a copy of the file.

use pepper_parser::ast::Span;
use pepper_parser::diagnostic::Loc;
use std::cell::RefCell;

/// One expansion of one `static` block: a block in concrete code expands
/// once, a block in generic code once per specialization.
#[derive(Debug, Clone)]
pub struct Expansion {
    /// The block's `static` keyword.
    pub loc: Loc,
    /// The whole block, from `static` to its `}`.
    pub span: Span,
    /// The specialization's type arguments, by parameter (`T` → `Point`);
    /// empty in concrete code.
    pub type_arguments: Vec<(String, String)>,
    /// What it emits: a `{ ... }` block, indented four spaces a level from
    /// column 0.
    pub lines: Vec<String>,
}

thread_local! {
    /// The expansions recorded so far; `None` when not recording.
    static RECORDED: RefCell<Option<Vec<Expansion>>> = const { RefCell::new(None) };
}

/// Runs `run` (which runs the sema passes) recording every `static` block
/// expansion, and returns them with its result.
pub fn record<T>(run: impl FnOnce() -> T) -> (T, Vec<Expansion>) {
    let previous = RECORDED.with(|r| r.replace(Some(vec![])));
    let result = run();
    let recorded = RECORDED.with(|r| r.replace(previous)).unwrap_or_default();
    (result, recorded)
}

pub(crate) fn recording() -> bool {
    RECORDED.with(|r| r.borrow().is_some())
}

pub(crate) fn add(expansion: Expansion) {
    RECORDED.with(|r| {
        if let Some(recorded) = r.borrow_mut().as_mut() {
            recorded.push(expansion);
        }
    });
}

/// Emitted code, as it will be written.
#[derive(Debug, Clone)]
pub(crate) enum Rendered {
    /// A statement: its first line, and the others indented relative to it.
    Code(Vec<String>),
    /// `{ ... }`: a pass of a loop, the branch a compile-time `if` kept, or
    /// a nested block.
    Block(Vec<Rendered>),
    /// A runtime `if`.
    Branch { condition: String, then_items: Vec<Rendered>, else_items: Option<Vec<Rendered>> },
}

/// `items` as lines, at `depth` levels of indentation.
pub(crate) fn write_lines(items: &[Rendered], depth: usize, out: &mut Vec<String>) {
    let indent = "    ".repeat(depth);
    for item in items {
        match item {
            Rendered::Code(lines) => out.extend(lines.iter().map(|line| if line.is_empty() { String::new() } else { format!("{}{}", indent, line) })),
            Rendered::Block(inner) => {
                // A block holding only a block is that block, and an empty
                // one changes nothing.
                let mut inner = inner;
                while let [Rendered::Block(only)] = inner.as_slice() {
                    inner = only;
                }
                if !inner.is_empty() {
                    out.push(format!("{}{{", indent));
                    write_lines(inner, depth + 1, out);
                    out.push(format!("{}}}", indent));
                }
            }
            Rendered::Branch { condition, then_items, else_items } => {
                out.push(format!("{}if ({}) {{", indent, without_parentheses(condition)));
                write_lines(then_items, depth + 1, out);
                match else_items {
                    Some(else_items) => {
                        out.push(format!("{}}} else {{", indent));
                        write_lines(else_items, depth + 1, out);
                        out.push(format!("{}}}", indent));
                    }
                    None => out.push(format!("{}}}", indent)),
                }
            }
        }
    }
}

/// `text` without the parentheses around all of it, if it has them.
fn without_parentheses(text: &str) -> &str {
    let Some(inner) = text.strip_prefix('(').and_then(|t| t.strip_suffix(')')) else { return text };
    let mut depth = 0;
    for c in inner.chars() {
        match c {
            '(' => depth += 1,
            ')' if depth == 0 => return text,
            ')' => depth -= 1,
            _ => {}
        }
    }
    inner
}

/// A placeholder's replacement: its span, and the source that replaces it.
#[derive(Debug, Clone)]
pub(crate) struct Edit {
    pub span: Span,
    pub pieces: Vec<Piece>,
    /// The text to write in place of the whole `{...}` when the placeholder
    /// fills a hole of an interpolated string (`$"{field.name} = "` writes
    /// `$"x = "`); `None` to keep the hole.
    pub inline: Option<String>,
}

#[derive(Debug, Clone)]
pub(crate) enum Piece {
    Text(String),
    /// An argument as written, with its own placeholders replaced.
    Argument(Span),
}

/// What part of the source a byte is in.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Region {
    Code,
    /// A string or character literal, or a comment: never substituted.
    Text,
    /// An interpolated string, holes included.
    Interpolated,
}

/// The region of each byte of `source[span]`.
fn regions(source: &str, span: Span) -> Vec<Region> {
    let bytes = source.as_bytes();
    let mut out = vec![Region::Code; span.end - span.start];
    let mut i = span.start;
    while i < span.end {
        let start = i;
        let kind = match bytes[i] {
            b'#' => {
                while i < span.end && bytes[i] != b'\n' {
                    i += 1;
                }
                Region::Text
            }
            b'$' if bytes.get(i + 1) == Some(&b'"') => {
                i = string_end(bytes, i + 1, true);
                Region::Interpolated
            }
            b'"' => {
                i = string_end(bytes, i, false);
                Region::Text
            }
            b'\'' => {
                i = quoted_end(bytes, i, b'\'');
                Region::Text
            }
            _ => {
                i += 1;
                continue;
            }
        };
        let end = i.min(span.end);
        for region in &mut out[start - span.start..end - span.start] {
            *region = kind;
        }
    }
    out
}

/// The end of the string literal whose `"` is at `at`.
fn string_end(bytes: &[u8], at: usize, interpolated: bool) -> usize {
    let mut i = at + 1;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' => i += 2,
            b'"' => return i + 1,
            b'{' if interpolated && bytes.get(i + 1) == Some(&b'{') => i += 2,
            b'{' if interpolated => i = hole_end(bytes, i + 1),
            _ => i += 1,
        }
    }
    bytes.len()
}

/// The end of the interpolation hole whose code starts at `at`: past its
/// `}`, stepping over the strings and braces inside it.
fn hole_end(bytes: &[u8], at: usize) -> usize {
    let mut depth = 0;
    let mut i = at;
    while i < bytes.len() {
        match bytes[i] {
            b'"' => i = string_end(bytes, i, false),
            b'$' if bytes.get(i + 1) == Some(&b'"') => i = string_end(bytes, i + 1, true),
            b'\'' => i = quoted_end(bytes, i, b'\''),
            b'{' => {
                depth += 1;
                i += 1;
            }
            b'}' if depth == 0 => return i + 1,
            b'}' => {
                depth -= 1;
                i += 1;
            }
            _ => i += 1,
        }
    }
    bytes.len()
}

fn quoted_end(bytes: &[u8], at: usize, quote: u8) -> usize {
    let mut i = at + 1;
    while i < bytes.len() && bytes[i] != b'\n' {
        match bytes[i] {
            b'\\' => i += 2,
            b if b == quote => return i + 1,
            _ => i += 1,
        }
    }
    i
}

/// `source[span]` with each name in `names` replaced where it is code: a
/// type parameter (`T` → `Point`, not after a `.`), or a member's type
/// (`field.Type` → `int`). Strings and comments are left alone.
pub fn substitute_names(source: &str, span: Span, names: &[(String, String)]) -> String {
    let regions = regions(source, span);
    substitute(source, span, &regions, span.start, names)
}

/// [`substitute_names`] over `source[span]`, with `regions` computed from
/// `origin`.
fn substitute(source: &str, span: Span, regions: &[Region], origin: usize, names: &[(String, String)]) -> String {
    let text = &source[span.start..span.end];
    if names.is_empty() {
        return text.to_string();
    }
    let bytes = source.as_bytes();
    let is_word = |b: u8| b.is_ascii_alphanumeric() || b == b'_';
    let mut out = String::with_capacity(text.len());
    let mut i = span.start;
    let mut copied = span.start;
    while i < span.end {
        if regions[i - origin] != Region::Code || !(bytes[i].is_ascii_alphabetic() || bytes[i] == b'_') || (i > 0 && is_word(bytes[i - 1])) {
            i += 1;
            continue;
        }
        let mut end = i;
        while end < span.end && is_word(bytes[end]) {
            end += 1;
        }
        let after_dot = source[..i].trim_end().ends_with('.');
        let word = &source[i..end];
        let with_type = format!("{}.Type", word);
        let type_end = end + ".Type".len();
        let found = if !after_dot
            && source[end..].starts_with(".Type")
            && type_end <= span.end
            && !bytes.get(type_end).is_some_and(|b| is_word(*b))
            && let Some((_, ty)) = names.iter().find(|(name, _)| *name == with_type)
        {
            Some((ty, type_end))
        } else if !after_dot && let Some((_, ty)) = names.iter().find(|(name, _)| name == word) {
            Some((ty, end))
        } else {
            None
        };
        match found {
            Some((ty, replaced_end)) => {
                out.push_str(&source[copied..i]);
                out.push_str(ty);
                copied = replaced_end;
                i = replaced_end;
            }
            None => i = end,
        }
    }
    out.push_str(&source[copied..span.end]);
    out
}

/// `span` widened over the parentheses around its start or end that it
/// closes or opens without the other: an operand's extent leaves out the
/// parentheses around a part of it (`a + b) * c`).
fn balanced(source: &str, span: Span) -> Span {
    let bytes = source.as_bytes();
    let (mut start, mut end) = (span.start, span.end);
    let mut depth: i64 = 0;
    let mut lowest: i64 = 0;
    let mut i = start;
    while i < end {
        match bytes[i] {
            b'"' => i = string_end(bytes, i, false).min(end) - 1,
            b'(' | b'[' => depth += 1,
            b')' | b']' => {
                depth -= 1;
                lowest = lowest.min(depth);
            }
            _ => {}
        }
        i += 1;
    }
    // Each closer with no opener inside: take in the opener before.
    let mut missing = -lowest;
    while missing > 0 && start > 0 {
        start -= 1;
        match bytes[start] {
            b'(' | b'[' => missing -= 1,
            b')' | b']' => missing += 1,
            _ => {}
        }
    }
    // Each opener with no closer inside: take in the closer after.
    let mut open = depth - lowest;
    while open > 0 && end < bytes.len() {
        match bytes[end] {
            b'(' | b'[' => open += 1,
            b')' | b']' => open -= 1,
            _ => {}
        }
        end += 1;
    }
    Span { start, end }
}

/// `edits` with their spans, and their arguments', [`balanced`].
fn balance(source: &str, edits: &[Edit]) -> Vec<Edit> {
    edits
        .iter()
        .map(|edit| Edit {
            span: balanced(source, edit.span),
            pieces: edit
                .pieces
                .iter()
                .map(|piece| match piece {
                    Piece::Argument(span) => Piece::Argument(balanced(source, *span)),
                    text => text.clone(),
                })
                .collect(),
            inline: edit.inline.clone(),
        })
        .collect()
}

/// An emitted statement as written at `span`, with `edits` applied and
/// `names` substituted, as lines indented relative to its first.
pub(crate) fn statement(source: &str, span: Span, edits: &[Edit], names: &[(String, String)]) -> Vec<String> {
    let span = balanced(source, span);
    // A statement's span ends before its `;`.
    let rest = &source[span.end..];
    let trimmed = rest.trim_start_matches([' ', '\t']);
    let span = if trimmed.starts_with(';') { Span { start: span.start, end: span.end + (rest.len() - trimmed.len()) + 1 } } else { span };
    let text = expression(source, span, edits, names);
    let line_start = source[..span.start].rfind('\n').map_or(0, |i| i + 1);
    let indent = source[line_start..span.start].len() - source[line_start..span.start].trim_start().len();
    text.lines()
        .enumerate()
        .map(|(i, line)| {
            if i == 0 {
                return line.trim_end().to_string();
            }
            let leading = line.len() - line.trim_start().len();
            line[leading.min(indent)..].trim_end().to_string()
        })
        .collect()
}

/// `source[span]` with `edits` applied and `names` substituted.
pub(crate) fn expression(source: &str, span: Span, edits: &[Edit], names: &[(String, String)]) -> String {
    let span = balanced(source, span);
    let regions = regions(source, span);
    apply(source, span, &balance(source, edits), names, &regions, span.start)
}

fn apply(source: &str, span: Span, edits: &[Edit], names: &[(String, String)], regions: &[Region], origin: usize) -> String {
    let mut inside: Vec<&Edit> = edits.iter().filter(|e| e.span.start >= span.start && e.span.end <= span.end).collect();
    inside.sort_by_key(|e| (e.span.start, std::cmp::Reverse(e.span.end)));
    let mut out = String::new();
    let mut at = span.start;
    for edit in inside {
        if edit.span.start < at {
            continue; // inside an edit already applied
        }
        let (start, end, text) = match (&edit.inline, hole(source, edit.span, regions, origin, span)) {
            (Some(inline), Some((open, close))) => (open, close, inline.clone()),
            _ => {
                let text = edit
                    .pieces
                    .iter()
                    .map(|piece| match piece {
                        Piece::Text(text) => text.clone(),
                        Piece::Argument(argument) => apply(source, *argument, edits, names, regions, origin),
                    })
                    .collect();
                (edit.span.start, edit.span.end, text)
            }
        };
        out.push_str(&substitute(source, Span { start: at, end: start }, regions, origin, names));
        out.push_str(&text);
        at = end;
    }
    out.push_str(&substitute(source, Span { start: at, end: span.end }, regions, origin, names));
    out
}

/// When `span` is part of an interpolated string, what to replace with its
/// text: the hole with its braces when `span` is a hole's expression, else
/// `span` itself, a run of the string's text and holes (`{field.name} = `).
fn hole(source: &str, span: Span, regions: &[Region], origin: usize, within: Span) -> Option<(usize, usize)> {
    if regions[span.start - origin] != Region::Interpolated || source[span.start..].starts_with("$\"") {
        return None;
    }
    let before = source[..span.start].trim_end();
    let after = &source[span.end..];
    let open = before.len().checked_sub(1)?;
    let close = span.end + (after.len() - after.trim_start().len());
    // `{{` is a literal brace, not a hole.
    let is_hole = before.ends_with('{') && !before.ends_with("{{") && source[close..].starts_with('}');
    if !is_hole {
        return Some((span.start, span.end));
    }
    (open >= within.start && close < within.end).then_some((open, close + 1))
}

/// `text` as a Pepper string literal.
pub(crate) fn string_literal(text: &str) -> String {
    format!("\"{}\"", escape(text, false))
}

/// `text` escaped for a string literal, or for the text of an interpolated
/// string, where braces are doubled.
pub(crate) fn escape(text: &str, interpolated: bool) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            '\0' => out.push_str("\\0"),
            '{' if interpolated => out.push_str("{{"),
            '}' if interpolated => out.push_str("}}"),
            c if c.is_control() => out.push_str(&format!("\\u{{{:x}}}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn span(source: &str) -> Span {
        Span { start: 0, end: source.len() }
    }

    #[test]
    fn substitutes_names_outside_strings_and_comments() {
        let source = "var x: T = parse<field.Type>(\"T\"); # T";
        let names = [("T".to_string(), "Point".to_string()), ("field.Type".to_string(), "int".to_string())];
        assert_eq!(substitute_names(source, span(source), &names), "var x: Point = parse<int>(\"T\"); # T");
    }

    #[test]
    fn leaves_members_named_like_a_parameter() {
        let source = "a.T + T";
        let names = [("T".to_string(), "int".to_string())];
        assert_eq!(substitute_names(source, span(source), &names), "a.T + int");
    }

    #[test]
    fn applies_nested_edits_and_inlines_holes() {
        // out.append($"{field.name} = {field.get(value)}");
        let source = "out.append($\"{field.name} = {field.get(value)}\");";
        let at = |text: &str| {
            let start = source.find(text).unwrap();
            Span { start, end: start + text.len() }
        };
        let edits = vec![
            Edit { span: at("field.name"), pieces: vec![Piece::Text("\"x\"".to_string())], inline: Some("x".to_string()) },
            Edit { span: at("field.get(value)"), pieces: vec![Piece::Argument(at("value")), Piece::Text(".x".to_string())], inline: None },
        ];
        assert_eq!(statement(source, at("out.append($\"{field.name} = {field.get(value)}\")"), &edits, &[]), vec!["out.append($\"x = {value.x}\");"]);
    }

    #[test]
    fn widens_over_parentheses_around_a_part() {
        let source = "x = (a + b) * c;";
        let at = |text: &str| {
            let start = source.find(text).unwrap();
            Span { start, end: start + text.len() }
        };
        assert_eq!(balanced(source, at("a + b) * c")), at("(a + b) * c"));
        assert_eq!(balanced(source, at("x = (a + b")), at("x = (a + b)"));
        assert_eq!(balanced(source, at("a + b")), at("a + b"));
    }

    #[test]
    fn escapes_strings() {
        assert_eq!(string_literal("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"");
        assert_eq!(escape("{x}", true), "{{x}}");
    }
}
