//! Doc comments: the run of `##` lines written directly above a
//! declaration, in a JSDoc-like format.
//!
//! ```text
//! ## Removes and returns the last element.
//! ##
//! ## @returns the element that was last
//! ## @panics if the Array is empty
//! T pop() { ... }
//! ```
//!
//! Each line's text follows `## ` (one space is dropped). A plain `#`
//! comment, or a decorative `###...` line, is not documentation.
//!
//! The text before the first tag is the description (Markdown). Tags:
//!
//! - `@typeParam T description`: a generic parameter of the declaration.
//! - `@param name description`: a parameter of the function or constructor.
//! - `@returns description`: what a function that returns a value returns.
//! - `@panics description`: when the function panics instead of returning.
//! - `@example`: sample code, shown as a code block.
//! - `@see reference`, `@note text`: related declarations, remarks.
//!
//! A tag's text runs until the next tag. Attributes and `export`/`static`
//! may sit between the comment and the declaration; a blank line may not.
//!
//! [`check_documented`] is the standard every runtime library file meets:
//! each public declaration (exported, and not `_`-prefixed) and each public
//! member of one carries a doc comment that describes it and tags every
//! parameter, generic parameter, and returned value.

use crate::ast::{Declaration, Expression, FunctionDecl, GenericParam, Module, PropertyDecl, Span, VariableDecl};
use crate::diagnostic::{Diagnostic, FileId, Loc};

/// One tag of a doc comment: `@param count how many` is kind `param`, name
/// `count`, text `how many`. Tags that name nothing (`@returns`) have an
/// empty name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocTag {
    pub kind: String,
    pub name: String,
    pub text: String,
    /// Span of the tag's name in the source, or of `@kind` when it has no
    /// name.
    pub span: Span,
}

/// A parsed `##` doc comment.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct DocComment {
    /// The text before the first tag.
    pub description: String,
    pub tags: Vec<DocTag>,
    /// Span of the whole comment, from its first `##` to the end of its
    /// last line.
    pub span: Span,
}

/// Tags whose first word is the name of something (a parameter).
const NAMED_TAGS: &[&str] = &["param", "typeParam"];

impl DocComment {
    /// Parse the `##` lines spanning `span` in `source`.
    pub fn parse(source: &str, span: Span) -> DocComment {
        let mut description = String::new();
        let mut tags: Vec<DocTag> = vec![];
        let mut offset = span.start;
        for raw in source[span.start..span.end].split_inclusive('\n') {
            let line_start = offset;
            offset += raw.len();
            // Strip the `## ` gutter.
            let mut text = raw.trim_end_matches(['\n', '\r']);
            let mut column = line_start;
            let trimmed = text.trim_start();
            column += text.len() - trimmed.len();
            text = trimmed;
            if let Some(rest) = text.strip_prefix("##") {
                column += 2;
                text = rest;
                if let Some(rest) = text.strip_prefix(' ') {
                    column += 1;
                    text = rest;
                }
            }
            let text = text.trim_end();
            if let Some(tag) = text.strip_prefix('@') {
                let kind_len = tag.find(char::is_whitespace).unwrap_or(tag.len());
                let kind = &tag[..kind_len];
                let rest = tag[kind_len..].trim_start();
                let rest_column = column + 1 + kind_len + (tag.len() - kind_len - rest.len());
                let (name, text, span) = if NAMED_TAGS.contains(&kind) {
                    let name_len = rest.find(char::is_whitespace).unwrap_or(rest.len());
                    let name = &rest[..name_len];
                    let span = Span { start: rest_column, end: rest_column + name_len };
                    (name, rest[name_len..].trim_start(), span)
                } else {
                    ("", rest, Span { start: column, end: column + 1 + kind_len })
                };
                tags.push(DocTag { kind: kind.to_string(), name: name.to_string(), text: text.to_string(), span });
            } else if let Some(tag) = tags.last_mut() {
                // A continuation line of the current tag; `@example` keeps
                // its line breaks.
                if tag.kind == "example" || tag.text.is_empty() {
                    if !tag.text.is_empty() || !text.is_empty() {
                        if !tag.text.is_empty() {
                            tag.text.push('\n');
                        }
                        tag.text.push_str(text);
                    }
                } else if !text.is_empty() {
                    tag.text.push(' ');
                    tag.text.push_str(text.trim_start());
                }
            } else {
                description.push_str(text);
                description.push('\n');
            }
        }
        for tag in &mut tags {
            tag.text = tag.text.trim_end().to_string();
        }
        DocComment { description: description.trim().to_string(), tags, span }
    }

    /// The tags of `kind`, in order.
    pub fn tags_of<'a>(&'a self, kind: &'a str) -> impl Iterator<Item = &'a DocTag> + 'a {
        self.tags.iter().filter(move |t| t.kind == kind)
    }

    /// The comment as Markdown, for an editor hover.
    pub fn to_markdown(&self) -> String {
        let mut out = self.description.clone();
        let mut section = |title: &str, items: Vec<String>| {
            if items.is_empty() {
                return;
            }
            if !out.is_empty() {
                out.push_str("\n\n");
            }
            out.push_str(&format!("**{}**", title));
            for item in items {
                out.push_str("\n- ");
                out.push_str(&item);
            }
        };
        let named = |kind: &str| -> Vec<String> {
            self.tags_of(kind).map(|t| format!("`{}` — {}", t.name, t.text)).collect()
        };
        let plain = |kind: &str| -> Vec<String> { self.tags_of(kind).map(|t| t.text.clone()).collect() };
        section("Type parameters", named("typeParam"));
        section("Parameters", named("param"));
        section("Returns", plain("returns"));
        section("Panics", plain("panics"));
        // `@see hash<String>` names code: shown as code, so `<...>` is not
        // read as HTML.
        let see = self
            .tags_of("see")
            .map(|t| match t.text.split_once(char::is_whitespace) {
                _ if t.text.contains('`') => t.text.clone(),
                Some((name, rest)) => format!("`{}` {}", name, rest),
                None => format!("`{}`", t.text),
            })
            .collect();
        section("See also", see);
        section("Note", plain("note"));
        for example in self.tags_of("example") {
            out.push_str(&format!("\n\n**Example**\n```pepper\n{}\n```", dedent(&example.text)));
        }
        out
    }
}

/// `text` with the indentation its non-blank lines share removed, so an
/// `@example` written indented under its tag shows from the left margin.
fn dedent(text: &str) -> String {
    let indent = text.lines().filter(|l| !l.trim().is_empty()).map(|l| l.len() - l.trim_start().len()).min().unwrap_or(0);
    text.lines().map(|l| l.get(indent..).unwrap_or("").trim_end()).collect::<Vec<_>>().join("\n")
}

/// Whether parameter `p` defaults to `__caller_location()`: the compiler
/// fills it with the call's location so a panic reports the caller's line.
/// Callers never pass it, so the documentation leaves it out.
pub fn is_caller_location(p: &VariableDecl) -> bool {
    matches!(&p.default_value, Some(Expression::FunctionCall { function, arguments, .. })
        if arguments.is_empty() && matches!(function.as_ref(), Expression::SymbolRef { id, .. } if id == "__caller_location"))
}

/// The doc comment directly above a declaration starting at `offset`:
/// only line breaks and indentation, attributes (`[...]`), and
/// `export`/`static` may sit between its last `##` line and `offset`. A blank
/// line in between detaches the comment.
pub fn doc_comment_before(source: &str, offset: usize) -> Option<DocComment> {
    let bytes = source.as_bytes();
    let mut end = offset.min(source.len());
    loop {
        let mut newlines = 0;
        while end > 0 && bytes[end - 1].is_ascii_whitespace() {
            if bytes[end - 1] == b'\n' {
                newlines += 1;
            }
            end -= 1;
        }
        if newlines > 1 {
            return None;
        }
        let before = &source[..end];
        // Reached a comment line: stop (its `[...]` is text, not an
        // attribute).
        let line_start = before.rfind('\n').map_or(0, |i| i + 1);
        if before[line_start..].trim_start().starts_with('#') {
            break;
        }
        if let Some(rest) = ["export", "static"].iter().find_map(|kw| before.strip_suffix(kw)) {
            if rest.is_empty() || !is_word_byte(*rest.as_bytes().last().unwrap()) {
                end = rest.len();
                continue;
            }
        }
        if before.ends_with(']') {
            // Back over one attribute `[...]`.
            let mut depth = 0usize;
            let mut i = end;
            while i > 0 {
                i -= 1;
                match bytes[i] {
                    b']' => depth += 1,
                    b'[' => {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                    _ => {}
                }
            }
            if depth != 0 {
                return None;
            }
            end = i;
            continue;
        }
        break;
    }
    // `end` is now the end of the line above; gather the `##` lines that end
    // there, bottom to top.
    let block_end = end;
    let mut block_start = None;
    loop {
        let line_start = source[..end].rfind('\n').map_or(0, |i| i + 1);
        let line = &source[line_start..end];
        let trimmed = line.trim_start();
        if !is_doc_line(trimmed) {
            break;
        }
        block_start = Some(line_start + (line.len() - trimmed.len()));
        if line_start == 0 {
            break;
        }
        end = line_start - 1;
        if end > 0 && bytes[end - 1] == b'\r' {
            end -= 1;
        }
    }
    Some(DocComment::parse(source, Span { start: block_start?, end: block_end }))
}

/// A doc comment line: `##`, then anything but another `#` (`###...` is a
/// decorative rule, not documentation).
fn is_doc_line(trimmed: &str) -> bool {
    trimmed.trim_end().strip_prefix("##").is_some_and(|rest| !rest.starts_with('#'))
}

/// The `##` block that opens a file, before any code: the file's own
/// documentation. It must be followed by a blank line, which keeps it apart
/// from the doc comment of a declaration directly below.
pub fn file_doc(source: &str) -> Option<DocComment> {
    let mut end = 0;
    let mut offset = 0;
    for raw in source.split_inclusive('\n') {
        if !is_doc_line(raw.trim()) {
            if end == 0 || !raw.trim().is_empty() {
                return None;
            }
            break;
        }
        offset += raw.len();
        end = offset - (raw.len() - raw.trim_end().len());
    }
    (end > 0).then(|| DocComment::parse(source, Span { start: 0, end }))
}

fn is_word_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// The doc comment above `decl` in `source`, its file.
pub fn doc_comment_of(source: &str, decl: &Declaration) -> Option<DocComment> {
    let start = decl.attributes().iter().map(|a| a.span.start).chain([decl.span().start]).min()?;
    doc_comment_before(source, start)
}

/// Public: not `_`-prefixed. `_`-prefixed names (`_pep_malloc`,
/// `_io_sys_open`) are runtime internals exported only between runtime files.
fn is_public(name: &str) -> bool {
    !name.starts_with('_')
}

/// A public method: not `_`-prefixed, or an indexer (`T [](...)`, named
/// `__index_get`/`__index_set` internally).
pub fn is_public_member(f: &FunctionDecl) -> bool {
    f.is_indexer || is_public(&f.name)
}

/// The name a member is written as: `[]` for an indexer.
pub fn member_name(f: &FunctionDecl) -> &str {
    if f.is_indexer { "[]" } else { &f.name }
}

/// Errors for every public declaration of `module` (parsed from `source`)
/// that does not meet the documentation standard (see the module docs):
/// exported, non-`_` (or `[__BuiltIn]`) declarations and their non-`_`
/// members need a doc comment with a description, `@typeParam` for each
/// generic parameter, `@param` for each parameter, and `@returns` when they
/// return a value; and no tag may name a parameter that does not exist.
pub fn check_documented(module: &Module, source: &str) -> Vec<Diagnostic> {
    let mut checker = Checker { source, errors: vec![] };
    for decl in &module.declarations {
        if !decl.is_exported() {
            continue;
        }
        let doc = doc_comment_of(source, decl);
        // A `[__BuiltIn]` declaration is public whatever its name (`__ptr`).
        let built_in = crate::ast::is_built_in(decl.attributes());
        let is_public = |name: &str| built_in || is_public(name);
        match decl {
            Declaration::Function(f) => {
                if is_public(&f.name) {
                    // A concrete override (`hash<String>` after `hash<T>`)
                    // names types, not generic parameters. It has as many
                    // as the generic it overrides; an overload with a
                    // different count (`to_string<A, B>` beside
                    // `to_string<T>`) has parameters of its own.
                    let overrides = module.declarations.iter().any(|d| {
                        matches!(d, Declaration::Function(g) if g.name == f.name && !std::ptr::eq(g, f)
                            && g.span.start < f.span.start && !g.generic_params.is_empty()
                            && g.generic_params.len() == f.generic_params.len())
                    });
                    let generics: &[GenericParam] = if overrides { &[] } else { &f.generic_params };
                    checker.function(f, &f.name, doc, generics);
                }
            }
            Declaration::Struct(s) if is_public(&s.name) => {
                if checker.described(doc.as_ref(), &s.name, s.name_span) {
                    checker.generics(doc.as_ref().unwrap(), &s.name, &s.generic_params, s.name_span);
                }
                for case in s.enumeration.iter().flat_map(|e| &e.cases) {
                    let doc = doc_comment_before(source, case.span.start);
                    checker.described(doc.as_ref(), &format!("{}.{}", s.name, case.name), case.name_span);
                }
                for field in s.fields.iter().filter(|f| is_public(&f.name)) {
                    checker.field(field, &format!("{}.{}", s.name, field.name));
                }
                checker.properties(&s.name, &s.properties);
                for c in &s.constructors {
                    let doc = checker.member_doc(c);
                    checker.function(c, &format!("{}.{}", s.name, c.name), doc, &[]);
                }
                checker.methods(&s.name, &s.methods);
            }
            Declaration::Trait(t) if is_public(&t.name) => {
                if checker.described(doc.as_ref(), &t.name, t.name_span) {
                    checker.generics(doc.as_ref().unwrap(), &t.name, &t.generic_params, t.name_span);
                }
                checker.properties(&t.name, &t.properties);
                checker.methods(&t.name, &t.methods);
            }
            Declaration::Extend(e) => {
                checker.properties(&e.target.name, &e.properties);
                checker.methods(&e.target.name, &e.methods);
            }
            Declaration::TypeAlias(t) if is_public(&t.name) => {
                if checker.described(doc.as_ref(), &t.name, t.name_span) {
                    checker.generics(doc.as_ref().unwrap(), &t.name, &t.generic_params, t.name_span);
                }
            }
            Declaration::Variable(v) if is_public(&v.name) => {
                checker.described(doc.as_ref(), &v.name, v.name_span);
            }
            _ => {}
        }
    }
    checker.errors
}

struct Checker<'a> {
    source: &'a str,
    errors: Vec<Diagnostic>,
}

fn at(span: Span) -> Loc {
    Loc::new(FileId::default(), span)
}

impl Checker<'_> {
    fn error(&mut self, message: String, span: Span) {
        self.errors.push(Diagnostic::error(message).at(at(span)));
    }

    /// Report a missing comment or description; true when `doc` exists.
    fn described(&mut self, doc: Option<&DocComment>, what: &str, span: Span) -> bool {
        match doc {
            None => {
                self.error(format!("missing doc comment for '{}'", what), span);
                false
            }
            Some(doc) => {
                if doc.description.is_empty() {
                    self.error(format!("doc comment for '{}' has no description", what), doc_head(doc));
                }
                true
            }
        }
    }

    fn member_doc(&self, f: &FunctionDecl) -> Option<DocComment> {
        let start = f.attributes.iter().map(|a| a.span.start).chain([f.span.start]).min().unwrap_or(f.span.start);
        doc_comment_before(self.source, start)
    }

    fn methods(&mut self, owner: &str, methods: &[FunctionDecl]) {
        for m in methods.iter().filter(|m| is_public_member(m)) {
            let doc = self.member_doc(m);
            self.function(m, &format!("{}.{}", owner, member_name(m)), doc, &m.generic_params);
        }
    }

    fn properties(&mut self, owner: &str, properties: &[PropertyDecl]) {
        for p in properties.iter().filter(|p| is_public(&p.name)) {
            let doc = doc_comment_before(self.source, p.span.start);
            self.described(doc.as_ref(), &format!("{}.{}", owner, p.name), p.name_span);
        }
    }

    fn field(&mut self, field: &VariableDecl, what: &str) {
        let doc = doc_comment_before(self.source, field.span.start);
        self.described(doc.as_ref(), what, field.name_span);
    }

    fn generics(&mut self, doc: &DocComment, what: &str, params: &[GenericParam], span: Span) {
        for p in params {
            if !doc.tags_of("typeParam").any(|t| t.name == p.name) {
                self.error(format!("missing '@typeParam {}' in the doc comment for '{}'", p.name, what), span);
            }
        }
        for tag in doc.tags_of("typeParam") {
            if !params.iter().any(|p| p.name == tag.name) {
                self.error(format!("'@typeParam {}' names no generic parameter of '{}'", tag.name, what), tag.span);
            }
        }
    }

    fn function(&mut self, f: &FunctionDecl, what: &str, doc: Option<DocComment>, generics: &[GenericParam]) {
        if !self.described(doc.as_ref(), what, f.name_span) {
            return;
        }
        let doc = doc.unwrap();
        self.generics(&doc, what, generics, f.name_span);
        for p in f.parameters.iter().filter(|p| !is_caller_location(p)) {
            if !doc.tags_of("param").any(|t| t.name == p.name) {
                self.error(format!("missing '@param {}' in the doc comment for '{}'", p.name, what), p.name_span);
            }
        }
        for tag in doc.tags_of("param") {
            if f.parameters.iter().any(|p| p.name == tag.name && is_caller_location(p)) {
                self.error(
                    format!("'@param {}' documents a '__caller_location()' parameter, which callers never pass; remove it", tag.name),
                    tag.span,
                );
            } else if !f.parameters.iter().any(|p| p.name == tag.name) {
                self.error(format!("'@param {}' names no parameter of '{}'", tag.name, what), tag.span);
            }
        }
        // An omitted return type (`__auto`) is inferred from the body, so
        // either way is accepted there.
        let returns_value = match f.return_type.name.as_str() {
            _ if is_constructor(f) => Some(false),
            "void" => Some(false),
            "__auto" => None,
            _ => Some(true),
        };
        let returns = doc.tags_of("returns").next();
        match returns {
            None if returns_value == Some(true) => {
                let span = if f.return_type.span.is_empty() { f.name_span } else { f.return_type.span };
                self.error(format!("missing '@returns' in the doc comment for '{}'", what), span);
            }
            Some(tag) if returns_value == Some(false) => {
                self.error(format!("'@returns' on '{}', which returns nothing", what), tag.span);
            }
            _ => {}
        }
        for tag in &doc.tags {
            if tag.kind != "example" && tag.text.is_empty() {
                self.error(format!("'@{}' in the doc comment for '{}' has no description", tag.kind, what), tag.span);
            }
        }
    }
}

fn is_constructor(f: &FunctionDecl) -> bool {
    f.name == "new" || f.name == "construct"
}

/// The first `##` of a comment.
fn doc_head(doc: &DocComment) -> Span {
    Span { start: doc.span.start, end: doc.span.start + 2 }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::parse_source;

    fn errors(src: &str) -> Vec<String> {
        let module = parse_source("t.pep", src).unwrap();
        check_documented(&module, src).iter().map(|d| d.render_in("t.pep", src)).collect()
    }

    #[test]
    fn parses_description_and_tags() {
        let src = "## Adds two numbers.\n##\n## More text.\n## @param a the first\n##   continued\n## @returns the sum\n## @example\n##     add(1, 2);\nexport add(a: int, b: int): int { return a + b; }\n";
        let module = parse_source("t.pep", src).unwrap();
        let doc = doc_comment_of(src, &module.declarations[0]).unwrap();
        assert_eq!(doc.description, "Adds two numbers.\n\nMore text.");
        assert_eq!(doc.tags[0].name, "a");
        assert_eq!(doc.tags[0].text, "the first continued");
        assert_eq!(&src[doc.tags[0].span.start..doc.tags[0].span.end], "a");
        assert_eq!(doc.tags[1].kind, "returns");
        assert_eq!(doc.tags[2].text, "    add(1, 2);");
    }

    #[test]
    fn looks_past_attributes_export_and_static() {
        let src = "## Doc [with brackets]\n[Target(OS(Linux))] export f(): void {}\nexport struct S {\n    ## Makes one.\n    ## @returns it\n    static S make() { return S(); }\n}\n";
        let module = parse_source("t.pep", src).unwrap();
        assert_eq!(doc_comment_of(src, &module.declarations[0]).unwrap().description, "Doc [with brackets]");
        assert!(errors(src).iter().any(|e| e.contains("missing doc comment for 'S'")));
        assert!(!errors(src).iter().any(|e| e.contains("'S.make'")));
    }

    #[test]
    fn plain_comments_and_detached_blocks_are_not_doc_comments() {
        let src = "# not docs\nexport f(): void {}\n## detached\n\nexport g(): void {}\n### rule\nexport h(): void {}\n";
        let errs = errors(src);
        assert_eq!(errs.len(), 3, "{:#?}", errs);
        assert_eq!(errs[0], "t.pep:2:8: error: missing doc comment for 'f'\n    2 | export f(): void {}\n      |        ^");
    }

    #[test]
    fn caller_location_parameters_are_not_documented() {
        let src = "## Checks.\n##\n## @param x the value\nexport f(x: int, location: __ptr<char> = __caller_location()): void {}\n";
        assert!(errors(src).is_empty(), "{:#?}", errors(src));
        let src = "## Checks.\n##\n## @param x the value\n## @param location where\nexport f(x: int, location: __ptr<char> = __caller_location()): void {}\n";
        let errs = errors(src);
        assert_eq!(errs.len(), 1, "{:#?}", errs);
        assert!(errs[0].starts_with("t.pep:4:11: error: '@param location' documents a '__caller_location()' parameter"), "{}", errs[0]);
    }

    #[test]
    fn file_doc_needs_a_blank_line() {
        assert_eq!(file_doc("## The file.\n## More.\n\nimport \"x\";\n").unwrap().description, "The file.\nMore.");
        assert!(file_doc("## A function.\nexport f(): void {}\n").is_none());
        assert!(file_doc("# plain\n").is_none());
    }

    #[test]
    fn reports_missing_and_stale_tags() {
        let src = "##\n## Does it.\n## @param x an x\nexport f(y: int): int { return y; }\n";
        let errs = errors(src);
        assert_eq!(errs.len(), 3, "{:#?}", errs);
        assert!(errs[0].starts_with("t.pep:4:10: error: missing '@param y' in the doc comment for 'f'"));
        assert!(errs[1].starts_with("t.pep:3:11: error: '@param x' names no parameter of 'f'"));
        assert!(errs[2].starts_with("t.pep:4:19: error: missing '@returns' in the doc comment for 'f'"));
    }

    #[test]
    fn private_and_internal_declarations_need_no_docs() {
        let src = "f(): void {}\nexport _internal(): void {}\n## A box.\n## @typeParam T the item\nexport struct Box<T> {\n    ## The item.\n    T item;\n    ulong _cache;\n    _helper(): void {}\n}\n";
        assert_eq!(errors(src), Vec::<String>::new());
    }

    #[test]
    fn indexers_and_overrides() {
        let src = "## A box.\nexport struct Box {\n    int [](ulong index) { return 0; }\n}\n## Hash.\n## @typeParam T any\n## @param v it\n## @returns h\nexport h<T>(T v): int { return 0; }\n## Hash a String.\n## @param v it\n## @returns h\nexport h<String>(String v): int { return 1; }\n";
        let errs = errors(src);
        assert_eq!(errs.len(), 1, "{:#?}", errs);
        assert!(errs[0].contains("missing doc comment for 'Box.[]'"), "{}", errs[0]);
    }

    #[test]
    fn requires_type_params() {
        let src = "## A box.\nexport struct Box<T> {\n}\n";
        let errs = errors(src);
        assert_eq!(errs.len(), 1);
        assert!(errs[0].contains("missing '@typeParam T' in the doc comment for 'Box'"));
    }
}
