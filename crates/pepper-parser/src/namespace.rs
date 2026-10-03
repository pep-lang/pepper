//! Per-file namespaces. Every file of a program is merged into one sema
//! module, so module linking gives each private top-level declaration a name
//! no other file can spell: its own name, `@`, then its file's namespace, the
//! module-qualified path of the file without its extension (`helper@io/file`
//! for `helper` in `io/file.pep`). Exports, externs, and concrete overrides
//! keep their names.
//!
//! Overloads of one name in one file take names of their own too: sema
//! renames them `name$1`, `name$2`, ... (after the namespace, so a private
//! set's members are `name@ns$1`); [`OVERLOAD_SEPARATOR`] marks that suffix.
//!
//! A mangled name never reaches the user. Diagnostics quote names and types
//! in single quotes, and [`demangle`] strips namespaces only there, so a path
//! or a string that happens to hold an `@` is left alone.

use std::borrow::Cow;

/// Separates a declaration's name from its file's namespace.
pub const SEPARATOR: char = '@';

/// Separates an overloaded function's name from its member number.
pub const OVERLOAD_SEPARATOR: char = '$';

/// The name `name`, declared privately in the file whose namespace is
/// `namespace`, takes in the merged program.
pub fn mangle(name: &str, namespace: &str) -> String {
    format!("{}{}{}", name, SEPARATOR, namespace)
}

/// A character a namespace may hold.
pub fn is_namespace_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '/' || c == '#'
}

/// A declaration's name as it was written: `helper@io/file` and `helper$2`
/// are `helper`.
pub fn demangle_name(name: &str) -> &str {
    name.split_once([SEPARATOR, OVERLOAD_SEPARATOR]).map_or(name, |(base, _)| base)
}

/// A whole mangled name as the user would write it, with every namespace and
/// overload member number removed wherever it appears:
/// `Box<Point@geo/shapes>.area$2` is `Box<Point>.area`. For names (symbols,
/// debug info), not messages: a message's paths keep their `@` only through
/// [`demangle`].
pub fn display_name(name: &str) -> String {
    let quoted = format!("'{}'", name);
    let shown = demangle(&quoted);
    shown[1..shown.len() - 1].to_string()
}

/// The message `text` with every mangled name inside single quotes spelled
/// as the user wrote it: `no member named 'x' in 'Box<Point@geo/shapes>'`
/// becomes `no member named 'x' in 'Box<Point>'`. An apostrophe inside a
/// word (`runtime's`) opens no quote.
pub fn demangle(text: &str) -> Cow<'_, str> {
    if !text.contains([SEPARATOR, OVERLOAD_SEPARATOR]) {
        return Cow::Borrowed(text);
    }
    let mut out = String::with_capacity(text.len());
    let mut quoted = false;
    let mut rest = text;
    while let Some(c) = rest.chars().next() {
        let prev = out.chars().last().unwrap_or(' ');
        if c == '\'' && (quoted || !is_name_char(prev)) {
            quoted = !quoted;
        } else if quoted && c == SEPARATOR && is_name_char(prev) {
            let len = namespace_len(&rest[1..]);
            if len > 0 {
                rest = &rest[1 + len..];
                continue;
            }
        } else if quoted && c == OVERLOAD_SEPARATOR && is_name_char(prev) {
            let len = member_len(&rest[1..]);
            if len > 0 {
                rest = &rest[1 + len..];
                continue;
            }
        }
        out.push(c);
        rest = &rest[c.len_utf8()..];
    }
    Cow::Owned(out)
}

/// `text` with each `@namespace` that follows a name and is one of
/// `namespaces`, and each overload member number (`$2`), removed anywhere in
/// the text: for editor text built from declarations (a hover's signature),
/// where names are not quoted.
pub fn demangle_known<'t>(text: &'t str, namespaces: &[&str]) -> Cow<'t, str> {
    if !text.contains([SEPARATOR, OVERLOAD_SEPARATOR]) {
        return Cow::Borrowed(text);
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(c) = rest.chars().next() {
        let prev = out.chars().last().unwrap_or(' ');
        if c == SEPARATOR && is_name_char(prev) {
            let len = namespace_len(&rest[1..]);
            if namespaces.contains(&&rest[1..1 + len]) {
                rest = &rest[1 + len..];
                continue;
            }
        } else if c == OVERLOAD_SEPARATOR && is_name_char(prev) {
            let len = member_len(&rest[1..]);
            if len > 0 {
                rest = &rest[1 + len..];
                continue;
            }
        }
        out.push(c);
        rest = &rest[c.len_utf8()..];
    }
    Cow::Owned(out)
}

fn is_name_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// The byte length of the overload member number at the start of `text`.
fn member_len(text: &str) -> usize {
    text.find(|c: char| !c.is_ascii_digit()).unwrap_or(text.len())
}

/// The byte length of the namespace at the start of `text`.
fn namespace_len(text: &str) -> usize {
    text.find(|c: char| !is_namespace_char(c)).unwrap_or(text.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn demangle_strips_namespaces_of_quoted_names() {
        assert_eq!(demangle("no member named 'x' in 'Box<Point@geo/shapes>'"), "no member named 'x' in 'Box<Point>'");
        assert_eq!(demangle(&format!("'{}'", mangle("helper", "io/file"))), "'helper'");
        assert_eq!(demangle("missing '@param x'"), "missing '@param x'");
        // Paths and strings outside single quotes keep their `@`.
        assert_eq!(demangle("'s' is private to /home/jane@corp/lib.pep"), "'s' is private to /home/jane@corp/lib.pep");
        assert_eq!(demangle("cannot find \"nope@x.pep\""), "cannot find \"nope@x.pep\"");
        // An apostrophe inside a word opens no quote.
        assert_eq!(demangle("the runtime's files, like 'f@a'"), "the runtime's files, like 'f'");
    }

    #[test]
    fn display_name_strips_every_namespace() {
        assert_eq!(display_name("Box<Point@geo/shapes>.area$2"), "Box<Point>.area");
        assert_eq!(display_name("__closure_0@hot.__call"), "__closure_0.__call");
        assert_eq!(display_name("main"), "main");
    }

    #[test]
    fn demangle_strips_overload_member_numbers() {
        assert_eq!(demangle("too many arguments to 'f$2'"), "too many arguments to 'f'");
        assert_eq!(demangle("'f@geo/shapes$1' and 'g$10<int>'"), "'f' and 'g<int>'");
        assert_eq!(demangle("costs $5, not 'x'"), "costs $5, not 'x'");
        assert_eq!(demangle_name("f@a$3"), "f");
        assert_eq!(demangle_name("f$3"), "f");
        assert_eq!(demangle_known("f$2(x: int): int", &[]), "f(x: int): int");
    }

    #[test]
    fn demangle_known_strips_only_program_namespaces() {
        assert_eq!(demangle_known("tally(): Tally@util", &["util"]), "tally(): Tally");
        assert_eq!(demangle_known("mail user@example.com", &["util"]), "mail user@example.com");
        assert_eq!(demangle_name("helper@io/file"), "helper");
    }
}
