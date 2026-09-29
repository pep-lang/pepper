//! The standard library reference: one Markdown page per runtime file,
//! generated from its `##` doc comments (see `pepper_parser::doc`).
//!
//! A page lists the file's public declarations (exported, not `_`-prefixed)
//! in source order, each with its signature as written and its doc comment;
//! a struct or trait lists its public fields, constructor, and methods
//! below it. A `##` block at the very top of a file, followed by a blank
//! line, introduces the page.

use std::path::{Path, PathBuf};

use pepper_parser::ast::{Declaration, FunctionDecl, Module, VariableDecl};
use pepper_parser::doc::{DocComment, doc_comment_before, doc_comment_of, file_doc, is_public_member, member_name};

/// Page titles for the runtime files, in the order the reference lists them.
/// A file not named here is listed after these, titled by its path.
const PAGES: &[(&str, &str)] = &[
    ("internals.pep", "Built-in functions"),
    ("string.pep", "String"),
    ("array.pep", "Array"),
    ("hash.pep", "HashMap and HashSet"),
    ("iterator.pep", "Iterators"),
    ("scoped.pep", "Scoped"),
    ("weak.pep", "Weak"),
    ("result.pep", "Result"),
    ("atomic.pep", "Atomic"),
    ("io/module.pep", "The io module"),
    ("io/types.pep", "Errors and platform types"),
    ("io/path.pep", "Path"),
    ("io/file.pep", "File"),
    ("io/directory.pep", "Directory"),
];

/// A generated page: its path under `reference/` and its Markdown.
pub struct Page {
    pub file: String,
    pub title: String,
    pub markdown: String,
}

/// Every `.pep` file under `dir`, as paths relative to it with `/`
/// separators.
fn pep_files(dir: &Path, prefix: &str, out: &mut Vec<String>) -> Result<(), String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("cannot read {}: {}", dir.display(), e))?;
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if path.is_dir() {
            pep_files(&path, &format!("{}{}/", prefix, name), out)?;
        } else if name.ends_with(".pep") {
            out.push(format!("{}{}", prefix, name));
        }
    }
    Ok(())
}

fn is_public(name: &str) -> bool {
    !name.starts_with('_')
}

/// The reference pages for the runtime in `runtime_dir`, in reading order.
/// Files with nothing public and no introduction get no page.
pub fn generate(runtime_dir: &Path) -> Result<Vec<Page>, String> {
    let mut files = vec![];
    pep_files(runtime_dir, "", &mut files)?;
    let rank = |f: &String| PAGES.iter().position(|(p, _)| p == f).unwrap_or(PAGES.len());
    files.sort_by(|a, b| rank(a).cmp(&rank(b)).then(a.cmp(b)));
    let mut pages = vec![];
    for file in files {
        let path: PathBuf = runtime_dir.join(&file);
        let source = std::fs::read_to_string(&path).map_err(|e| format!("cannot read {}: {}", path.display(), e))?;
        let module = pepper_parser::parser::parse_source(&format!("runtime/{}", file), &source)?;
        let title = PAGES.iter().find(|(p, _)| *p == file).map_or_else(|| file.clone(), |(_, t)| t.to_string());
        let body = page_body(&module, &source);
        let intro = file_doc(&source);
        if body.is_empty() && intro.is_none() {
            continue;
        }
        let mut markdown = format!(
            "<!-- Generated from runtime/{} by `cargo run -p pepper-docgen -- reference`. Do not edit. -->\n\n# {}\n\n",
            file, title
        );
        if let Some(intro) = intro {
            markdown.push_str(&intro.to_markdown());
            markdown.push_str("\n\n");
        }
        markdown.push_str(&format!("Source: `runtime/{}`\n", file));
        markdown.push_str(&body);
        let page_file = format!("{}.md", file.trim_end_matches(".pep").replace('/', "-"));
        pages.push(Page { file: page_file, title, markdown });
    }
    Ok(pages)
}

/// `text` with runs of whitespace collapsed to one space.
fn one_line(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The source of a declaration from `start` up to `end`, as one line,
/// without `export`.
fn signature(source: &str, start: usize, end: usize) -> String {
    let text = one_line(&source[start..end]);
    let text = text.trim_end_matches(['{', ';', ' ']).to_string();
    // `[Attr] export x` and `export x` read as `[Attr] x`.
    text.replacen("export ", "", 1)
}

fn first_attribute(attributes: &[pepper_parser::ast::Attribute], start: usize) -> usize {
    attributes.iter().map(|a| a.span.start).chain([start]).min().unwrap_or(start)
}

fn function_signature(source: &str, f: &FunctionDecl) -> String {
    let start = first_attribute(&f.attributes, f.span.start);
    // A declaration without a body (a trait method, an extern) ends at its
    // `;`; its span may run on over trivia.
    let end = match &f.body {
        Some(b) => b.span.start,
        None => source[f.name_span.end..f.span.end].find(';').map_or(f.span.end, |i| f.name_span.end + i),
    };
    signature(source, start, end.max(start))
}

/// The heading and anchor text for a member: operators and indexers read
/// as `operator ==`, `indexer []`.
fn member_title(name: &str) -> String {
    if name.chars().next().is_some_and(|c| c.is_alphabetic() || c == '_') {
        name.to_string()
    } else {
        format!("operator {}", name)
    }
}

fn entry(out: &mut String, level: usize, title: &str, signature: &str, doc: Option<DocComment>) {
    out.push_str(&format!("\n{} {}\n\n```pepper\n{}\n```\n", "#".repeat(level), title, signature));
    if let Some(doc) = doc {
        let md = doc.to_markdown();
        if !md.is_empty() {
            out.push('\n');
            out.push_str(&md);
            out.push('\n');
        }
    }
}

fn field(out: &mut String, source: &str, v: &VariableDecl) {
    let doc = doc_comment_before(source, v.span.start);
    entry(out, 4, &v.name, &signature(source, v.span.start, v.span.end), doc);
}

fn method(out: &mut String, source: &str, owner: &str, f: &FunctionDecl) {
    let start = first_attribute(&f.attributes, f.span.start);
    let doc = doc_comment_before(source, start);
    let title = if f.name == "new" || f.name == "construct" {
        format!("{}()", owner)
    } else {
        member_title(member_name(f))
    };
    entry(out, 4, &title, &function_signature(source, f), doc);
}

fn members(out: &mut String, source: &str, owner: &str, fields: &[VariableDecl], constructor: Option<&FunctionDecl>, methods: &[FunctionDecl]) {
    let fields: Vec<_> = fields.iter().filter(|f| is_public(&f.name)).collect();
    if !fields.is_empty() {
        out.push_str("\n### Fields\n");
        for f in fields {
            field(out, source, f);
        }
    }
    if let Some(c) = constructor {
        out.push_str("\n### Constructor\n");
        method(out, source, owner, c);
    }
    let (statics, instance): (Vec<_>, Vec<_>) =
        methods.iter().filter(|m| is_public_member(m)).partition(|m| m.is_static);
    if !statics.is_empty() {
        out.push_str("\n### Static methods\n");
        for m in statics {
            method(out, source, owner, m);
        }
    }
    if !instance.is_empty() {
        out.push_str("\n### Methods\n");
        for m in instance {
            method(out, source, owner, m);
        }
    }
}

fn page_body(module: &Module, source: &str) -> String {
    let mut out = String::new();
    for decl in &module.declarations {
        if !decl.is_exported() {
            continue;
        }
        let doc = doc_comment_of(source, decl);
        let start = first_attribute(decl.attributes(), decl.span().start);
        match decl {
            Declaration::Function(f) if is_public(&f.name) => {
                entry(&mut out, 2, &f.name, &function_signature(source, f), doc);
            }
            Declaration::Struct(s) if is_public(&s.name) => {
                let end = source[s.name_span.end..].find('{').map_or(s.span.end, |i| s.name_span.end + i);
                entry(&mut out, 2, &s.name, &signature(source, start, end), doc);
                members(&mut out, source, &s.name, &s.fields, s.constructor.as_ref(), &s.methods);
            }
            Declaration::Trait(t) if is_public(&t.name) => {
                let end = source[t.name_span.end..].find('{').map_or(t.span.end, |i| t.name_span.end + i);
                entry(&mut out, 2, &t.name, &signature(source, start, end), doc);
                members(&mut out, source, &t.name, &[], None, &t.methods);
            }
            Declaration::Extend(e) => {
                let end = source[e.target.span.end..].find('{').map_or(e.span.end, |i| e.target.span.end + i);
                entry(&mut out, 2, &format!("extend {}", e.target), &signature(source, start, end), doc);
                members(&mut out, source, &e.target.name, &[], None, &e.methods);
            }
            Declaration::TypeAlias(t) if is_public(&t.name) => {
                entry(&mut out, 2, &t.name, &signature(source, start, t.span.end), doc);
            }
            Declaration::Variable(v) if is_public(&v.name) => {
                entry(&mut out, 2, &v.name, &signature(source, start, v.span.end), doc);
            }
            _ => {}
        }
    }
    out
}

/// The reference's part of `SUMMARY.md`: a line per page, nested under
/// `reference/README.md`.
pub fn summary_lines(pages: &[Page]) -> String {
    pages
        .iter()
        .map(|p| {
            // A module's other files (`io-path.md`) nest under its
            // `module.pep` page (`io-module.md`).
            let nested = p.file.split_once('-').is_some_and(|(module, _)| {
                p.file != format!("{}-module.md", module) && pages.iter().any(|q| q.file == format!("{}-module.md", module))
            });
            format!("{}- [{}](reference/{})\n", if nested { "    " } else { "  " }, p.title, p.file)
        })
        .collect()
}

const SUMMARY_START: &str = "<!-- reference:start -->";
const SUMMARY_END: &str = "<!-- reference:end -->";

/// `summary` with the text between the reference markers replaced by the
/// page list.
pub fn update_summary(summary: &str, pages: &[Page]) -> Result<String, String> {
    let start = summary.find(SUMMARY_START).ok_or("SUMMARY.md has no reference:start marker")? + SUMMARY_START.len();
    let end = summary.find(SUMMARY_END).ok_or("SUMMARY.md has no reference:end marker")?;
    Ok(format!("{}\n{}{}", &summary[..start], summary_lines(pages), &summary[end..]))
}

/// Write the pages into `docs/src/reference/` (removing stale generated
/// pages) and their list into `SUMMARY.md`. Returns the files that changed.
pub fn write(docs_dir: &Path, pages: &[Page]) -> Result<Vec<PathBuf>, String> {
    let dir = docs_dir.join("src").join("reference");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let mut changed = vec![];
    let put = |path: PathBuf, text: &str, changed: &mut Vec<PathBuf>| -> Result<(), String> {
        if std::fs::read_to_string(&path).ok().as_deref() != Some(text) {
            std::fs::write(&path, text).map_err(|e| format!("cannot write {}: {}", path.display(), e))?;
            changed.push(path);
        }
        Ok(())
    };
    for page in pages {
        put(dir.join(&page.file), &page.markdown, &mut changed)?;
    }
    // A page whose runtime file is gone.
    for entry in std::fs::read_dir(&dir).map_err(|e| e.to_string())?.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name != "README.md" && name.ends_with(".md") && !pages.iter().any(|p| p.file == name) {
            let text = std::fs::read_to_string(entry.path()).unwrap_or_default();
            if text.starts_with("<!-- Generated from runtime/") {
                std::fs::remove_file(entry.path()).map_err(|e| e.to_string())?;
                changed.push(entry.path());
            }
        }
    }
    let summary_path = docs_dir.join("src").join("SUMMARY.md");
    let summary = std::fs::read_to_string(&summary_path).map_err(|e| format!("cannot read {}: {}", summary_path.display(), e))?;
    put(summary_path, &update_summary(&summary, pages)?, &mut changed)?;
    Ok(changed)
}
