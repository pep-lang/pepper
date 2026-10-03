//! The standard library reference: one Markdown page per runtime file,
//! generated from its `##` doc comments (see `pepper_parser::doc`).
//!
//! A page lists the file's public declarations (exported, not `_`-prefixed)
//! in source order, each with its signature as written and its doc comment;
//! a struct or trait lists its public fields, constructor, and methods
//! below it. A `##` block at the very top of a file, followed by a blank
//! line, introduces the page.

use std::path::{Path, PathBuf};

use pepper_parser::ast::{BUILT_IN_ATTRIBUTE, Declaration, FunctionDecl, Import, Module, PropertyDecl, VariableDecl};
use pepper_parser::doc::{DocComment, doc_comment_before, doc_comment_of, file_doc, is_caller_location, is_public_member, member_name};

/// Page titles for the runtime files, in the order the reference lists them.
/// Every runtime file that gets a page must be named here: `generate` fails
/// on one that is not, so a new file cannot land at the end of the list
/// under whatever module happens to come last. A module's files follow its
/// `module.pep`, which the summary nests them under.
const PAGES: &[(&str, &str)] = &[
    ("internals.pep", "Built-in functions"),
    ("attributes.pep", "Built-in attributes"),
    ("reflect.pep", "The reflect module (compile time)"),
    ("process.pep", "Arguments and exit (deprecated)"),
    ("string.pep", "String"),
    ("number.pep", "Numbers"),
    ("range.pep", "Ranges"),
    ("array.pep", "Array"),
    ("hash.pep", "HashMap and HashSet"),
    ("map.pep", "Map and Set"),
    ("ordered_map.pep", "OrderedMap"),
    ("iterator.pep", "Iterators"),
    ("scoped.pep", "Scoped"),
    ("weak.pep", "Weak"),
    ("handle.pep", "Handle"),
    ("result.pep", "Result"),
    ("optional.pep", "Optional"),
    ("copy.pep", "Copying"),
    ("uri.pep", "URI"),
    ("io/module.pep", "The io module"),
    ("io/types.pep", "Errors and platform types"),
    ("io/stream.pep", "Reader and Writer"),
    ("io/path.pep", "Path"),
    ("io/file.pep", "File"),
    ("io/directory.pep", "Directory"),
    ("io/address.pep", "Network addresses"),
    ("io/socket.pep", "Sockets"),
    ("io/unix.pep", "Unix domain sockets"),
    ("io/memory.pep", "Streams in memory"),
    ("io/print.pep", "Print"),
    ("async/module.pep", "The async module"),
    ("async/atomic.pep", "Atomic"),
    ("async/thread.pep", "Thread"),
    ("async/thread_local.pep", "ThreadLocal"),
    ("async/mutex.pep", "Mutex and Condition"),
    ("async/once.pep", "Once and Lazy"),
    ("async/channel.pep", "Channel"),
    ("async/select.pep", "Select"),
    ("async/cpus.pep", "Processor counts"),
    ("async/task.pep", "Tasks"),
    ("async/task_local.pep", "TaskLocal"),
    ("async/driver.pep", "I/O backends"),
    ("process/module.pep", "The process module"),
    ("process/command.pep", "Command"),
    ("process/child.pep", "Child"),
    ("process/current.pep", "The running process"),
    ("os/module.pep", "The os module"),
    ("os/environment.pep", "Environment"),
    ("os/time.pep", "Time"),
    ("os/machine.pep", "Machine"),
    ("os/user.pep", "User"),
    ("math/module.pep", "The math module"),
    ("math/parse.pep", "Parsing integers"),
    ("hint/module.pep", "The hint module"),
    ("text/module.pep", "The text module"),
    ("text/utf8.pep", "UTF-8"),
    ("text/utf16.pep", "UTF-16"),
    ("text/ascii.pep", "ASCII"),
    ("regex/module.pep", "The regex module"),
    ("regex/regex.pep", "Regex and Match"),
    ("json/module.pep", "The json module"),
    ("json/value.pep", "JsonValue"),
    ("json/parse.pep", "Parsing"),
    ("json/document.pep", "Documents with comments"),
    ("json/convert.pep", "Struct conversion"),
    ("serialize/module.pep", "The serialize module"),
    ("compress/module.pep", "The compress module"),
    ("compress/format.pep", "Formats and streams"),
    ("compress/checksum.pep", "Checksums"),
    ("archive/module.pep", "The archive module"),
    ("archive/tar.pep", "Tar archives"),
    ("digest/module.pep", "The digest module"),
    ("digest/sha256.pep", "SHA-256"),
    ("digest/sha1.pep", "SHA-1"),
    ("digest/blake3.pep", "BLAKE3"),
    ("digest/hex.pep", "Hexadecimal"),
    ("cli/module.pep", "The cli module"),
    ("cli/parser.pep", "Parser"),
    ("cli/options.pep", "Options"),
    ("http/module.pep", "The http module"),
    ("http/message.pep", "Requests and responses"),
    ("http/client.pep", "Client"),
    ("http/server.pep", "Server"),
    ("tls/module.pep", "The tls module"),
    ("tls/stream.pep", "Connectors and streams"),
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
        let body = format!("{}{}", reexports(&module, &file), page_body(&module, &source));
        let intro = file_doc(&source);
        if body.is_empty() && intro.is_none() {
            continue;
        }
        let title = PAGES.iter().find(|(p, _)| *p == file).map(|(_, t)| t.to_string()).ok_or_else(|| {
            format!(
                "runtime/{} has public declarations but no reference page; give it a title and a place in PAGES in tools/docgen/src/reference.rs",
                file
            )
        })?;
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
    pages.insert(0, prelude_page(&pages));
    Ok(pages)
}

/// The page every prelude page nests under: the runtime files outside any
/// module, which every program gets without an import.
const PRELUDE_PAGE: &str = "prelude.md";

/// The first sentence of a page's prose: its introduction, else the
/// description of its first declaration.
fn first_sentence(markdown: &str) -> String {
    let mut in_code = false;
    let mut paragraph = vec![];
    for line in markdown.lines() {
        if line.starts_with("```") {
            in_code = !in_code;
            continue;
        }
        let skip = in_code || line.starts_with('#') || line.starts_with("<!--") || line.starts_with("Source:");
        if skip || line.trim().is_empty() {
            if !paragraph.is_empty() {
                break;
            }
            continue;
        }
        paragraph.push(line.trim());
    }
    let text = paragraph.join(" ");
    // The first ". " outside a code span ends the sentence.
    let mut in_code = false;
    for (i, c) in text.char_indices() {
        match c {
            '`' => in_code = !in_code,
            '.' if !in_code && text[i + 1..].starts_with(' ') => return text[..=i].to_string(),
            _ => {}
        }
    }
    text
}

/// The prelude's page: what it is, and a line per page in it.
fn prelude_page(pages: &[Page]) -> Page {
    let mut markdown = format!(
        "<!-- Generated by `cargo run -p pepper-docgen -- reference`. Do not edit. -->\n\n# The prelude\n\n\
         The prelude is the part of the standard library every program gets without an import: the files at the top of \
         `runtime/`. Each module after it (`io`, `async`, `json`, ...) is brought in with an import.\n\n"
    );
    for page in pages.iter().filter(|p| !p.file.contains('-')) {
        markdown.push_str(&format!("- [{}]({}): {}\n", page.title, page.file, first_sentence(&page.markdown)));
    }
    Page { file: PRELUDE_PAGE.to_string(), title: "The prelude".to_string(), markdown }
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
    let end = end.max(start);
    // Leave out the parameters the compiler fills in
    // (`location: __ptr<char> = __caller_location()`): callers never pass
    // them. Each goes with the `, ` before it, or the one after it when it
    // comes first.
    let mut text = String::new();
    let mut from = start;
    for (i, p) in f.parameters.iter().enumerate().filter(|(_, p)| is_caller_location(p)) {
        let (cut_start, cut_end) = if i > 0 {
            (source[..p.span.start].rfind(',').unwrap_or(p.span.start), p.span.end)
        } else {
            let after = source[p.span.end..end].find(|c: char| c != ',' && !c.is_whitespace()).map_or(p.span.end, |n| p.span.end + n);
            let after = if source[p.span.end..after].contains(',') { after } else { p.span.end };
            (p.span.start, after)
        };
        if cut_start < from || cut_end > end {
            continue;
        }
        text.push_str(&source[from..cut_start]);
        from = cut_end;
    }
    text.push_str(&source[from..end]);
    signature(&text, 0, text.len())
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

/// A property's entry: its declaration with the accessors' bodies left out
/// (`var count: ulong { get; }`).
fn property(out: &mut String, source: &str, p: &PropertyDecl) {
    let doc = doc_comment_before(source, p.span.start);
    let accessors: Vec<&str> = [("get;", &p.get), ("set;", &p.set)].into_iter().filter(|(_, a)| a.is_some()).map(|(k, _)| k).collect();
    let ty = source.get(p.type_name.span.start..p.type_name.span.end).map_or_else(|| p.type_name.to_string(), str::to_string);
    entry(out, 4, &p.name, &format!("var {}: {} {{ {} }}", p.name, ty, accessors.join(" ")), doc);
}

fn members(
    out: &mut String,
    source: &str,
    owner: &str,
    fields: &[VariableDecl],
    properties: &[PropertyDecl],
    constructors: &[FunctionDecl],
    methods: &[FunctionDecl],
) {
    let fields: Vec<_> = fields.iter().filter(|f| is_public(&f.name)).collect();
    if !fields.is_empty() {
        out.push_str("\n### Fields\n");
        for f in fields {
            field(out, source, f);
        }
    }
    let properties: Vec<_> = properties.iter().filter(|p| is_public(&p.name)).collect();
    if !properties.is_empty() {
        out.push_str("\n### Properties\n");
        for p in properties {
            property(out, source, p);
        }
    }
    if !constructors.is_empty() {
        out.push_str(if constructors.len() == 1 { "\n### Constructor\n" } else { "\n### Constructors\n" });
        for c in constructors {
            method(out, source, owner, c);
        }
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

/// The page of the file or module an `export ... from` names, relative to
/// the runtime file `file`: `io-types.md` for `"types"` in `io/module.pep`,
/// `async-module.md` for the module `async`.
fn source_page(file: &str, import: &Import) -> String {
    if !import.is_local {
        return format!("{}-module.md", import.name);
    }
    let dir = file.rsplit_once('/').map_or(String::new(), |(d, _)| format!("{}/", d));
    format!("{}{}.md", dir, import.stem()).replace('/', "-")
}

/// A "Re-exports" section listing the file's `export * from` and `export
/// [...] from` lines, each linking to the page of the file or module that
/// declares the names. Empty without any.
fn reexports(module: &Module, file: &str) -> String {
    let mut out = String::new();
    for import in module.imports.iter().filter(|i| i.reexport) {
        let source = if import.is_local { format!("`{}.pep`", import.stem()) } else { format!("the `{}` module", import.name) };
        let link = format!("[{}]({})", source, source_page(file, import));
        match &import.symbols {
            None => out.push_str(&format!("- Everything {} exports.
", link)),
            Some(symbols) => {
                for s in symbols {
                    let named = match &s.alias {
                        Some(alias) => format!("`{}` (as `{}`)", s.name, alias),
                        None => format!("`{}`", s.name),
                    };
                    out.push_str(&format!("- {} from {}.
", named, link));
                }
            }
        }
    }
    if out.is_empty() { out } else { format!("\n## Re-exports\n\n{}", out) }
}

/// `signature` of a `[__BuiltIn]` declaration named `name`, which declares
/// the built-in `built_in`: without the attribute, and with the built-in's
/// name in place of its own (`reflect.name<T>(): String`).
fn built_in_signature(signature: &str, name: &str, built_in: &str) -> String {
    let mut text = signature.to_string();
    if let Some(start) = text.find(&format!("[{}", BUILT_IN_ATTRIBUTE)) {
        let end = text[start..].find(']').map_or(text.len(), |i| start + i + 1);
        let end = end + text[end..].len() - text[end..].trim_start().len();
        text.replace_range(start..end, "");
    }
    let is_word = |c: char| c.is_alphanumeric() || c == '_';
    let mut from = 0;
    while let Some(i) = text[from..].find(name).map(|i| from + i) {
        let before = text[..i].chars().next_back();
        let after = text[i + name.len()..].chars().next();
        if !before.is_some_and(is_word) && !after.is_some_and(is_word) {
            text.replace_range(i..i + name.len(), built_in);
            break;
        }
        from = i + name.len();
    }
    text
}

fn page_body(module: &Module, source: &str) -> String {
    let mut out = String::new();
    for decl in &module.declarations {
        if !decl.is_exported() {
            continue;
        }
        let doc = doc_comment_of(source, decl);
        let start = first_attribute(decl.attributes(), decl.span().start);
        // A `[__BuiltIn]` declaration is public whatever its name (`__ptr`),
        // and reads as the built-in it declares.
        let built_in = decl.built_in_name();
        let public = |name: &str| built_in.is_some() || is_public(name);
        let title = |name: &str| built_in.clone().unwrap_or_else(|| name.to_string());
        let shown = |signature: String| match &built_in {
            Some(built_in) => built_in_signature(&signature, decl.name(), built_in),
            None => signature,
        };
        match decl {
            Declaration::Function(f) if public(&f.name) => {
                entry(&mut out, 2, &title(&f.name), &shown(function_signature(source, f)), doc);
            }
            Declaration::Struct(s) if public(&s.name) => {
                let end = source[s.name_span.end..].find('{').map_or(s.span.end, |i| s.name_span.end + i);
                entry(&mut out, 2, &title(&s.name), &shown(signature(source, start, end)), doc);
                let cases = s.enumeration.iter().flat_map(|e| &e.cases).collect::<Vec<_>>();
                if !cases.is_empty() {
                    out.push_str("\n### Cases\n");
                    for case in cases {
                        let start = first_attribute(&case.attributes, case.span.start);
                        let doc = doc_comment_before(source, start);
                        entry(&mut out, 4, &case.name, &signature(source, start, case.span.end), doc);
                    }
                }
                members(&mut out, source, &s.name, &s.fields, &s.properties, &s.constructors, &s.methods);
            }
            Declaration::Trait(t) if public(&t.name) => {
                let end = source[t.name_span.end..].find('{').map_or(t.span.end, |i| t.name_span.end + i);
                entry(&mut out, 2, &title(&t.name), &shown(signature(source, start, end)), doc);
                members(&mut out, source, &t.name, &[], &t.properties, &[], &t.methods);
            }
            Declaration::Extend(e) => {
                let end = source[e.target.span.end..].find('{').map_or(e.span.end, |i| e.target.span.end + i);
                entry(&mut out, 2, &format!("extend {}", e.target), &signature(source, start, end), doc);
                members(&mut out, source, &e.target.name, &[], &e.properties, &[], &e.methods);
            }
            Declaration::TypeAlias(t) if public(&t.name) => {
                entry(&mut out, 2, &title(&t.name), &shown(signature(source, start, t.span.end)), doc);
            }
            Declaration::Variable(v) if public(&v.name) => {
                entry(&mut out, 2, &title(&v.name), &shown(signature(source, start, v.span.end)), doc);
            }
            _ => {}
        }
    }
    out
}

/// The reference's part of `SUMMARY.md`: a line per page, nested under
/// `reference/README.md`.
pub fn summary_lines(pages: &[Page]) -> String {
    let mut out = String::new();
    for p in pages {
        // A module's other files (`io-path.md`) nest under its
        // `module.pep` page (`io-module.md`).
        let module = p.file.split_once('-').map(|(module, _)| module);
        // The prelude's files (`string.md`) nest under its page.
        let nested = match module {
            Some(module) => {
                p.file != format!("{}-module.md", module) && pages.iter().any(|q| q.file == format!("{}-module.md", module))
            }
            None => p.file != PRELUDE_PAGE,
        };
        out.push_str(&format!("{}- [{}](reference/{})\n", if nested { "    " } else { "  " }, p.title, p.file));
    }
    out
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

#[cfg(test)]
mod tests {
    use super::*;

    /// The module a runtime file belongs to (`io` for `io/path.pep`), or
    /// `None` for a file at the top of the runtime.
    fn module_of(file: &str) -> Option<&str> {
        file.split_once('/').map(|(module, _)| module)
    }

    #[test]
    fn pages_keep_each_module_together_under_its_module_file() {
        let mut seen: Vec<&str> = vec![];
        let mut current: Option<&str> = None;
        for (file, _) in PAGES {
            let module = module_of(file);
            assert!(module.is_some() || seen.is_empty(), "{} must come before the modules in PAGES", file);
            if module != current {
                if let Some(m) = module {
                    assert!(!seen.contains(&m), "the {} module's pages are split up in PAGES at {}", m, file);
                    assert_eq!(*file, format!("{}/module.pep", m), "the {} module's pages must start with its module.pep", m);
                    seen.push(m);
                }
                current = module;
            }
        }
    }

    #[test]
    fn every_runtime_file_with_a_page_has_a_title() {
        generate(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../runtime")).unwrap();
    }

    /// The names in the match arms of the function `name` in `source`: each
    /// `"x"` before a `=>` on a line that starts with one.
    fn arm_names(source: &str, function: &str) -> Vec<String> {
        let start = source.find(function).unwrap_or_else(|| panic!("no {} in static_blocks.rs", function));
        let body = &source[start..];
        let body = &body[..body[1..].find("\n    fn ").map_or(body.len(), |i| i + 1)];
        let mut names = vec![];
        for line in body.lines().map(str::trim) {
            let Some((arm, _)) = line.split_once("=>") else { continue };
            for part in arm.split('|') {
                let part = part.trim();
                let quoted = part.rsplit_once(", \"").map(|(_, q)| q).or_else(|| part.strip_prefix('"'));
                if let Some(name) = quoted.and_then(|q| q.split('"').next())
                    && !name.is_empty()
                    && name.chars().all(|c| c.is_ascii_lowercase() || c == '_')
                {
                    names.push(name.to_string());
                }
            }
        }
        names
    }

    /// The `[__BuiltIn]` declarations of `runtime/reflect.pep` and what
    /// each declares: its built-in name, with its fields and methods.
    fn reflect_declarations(root: &Path) -> Vec<(String, Vec<String>)> {
        let source = std::fs::read_to_string(root.join("runtime/reflect.pep")).unwrap();
        let module = pepper_parser::parser::parse_source("runtime/reflect.pep", &source).unwrap();
        module
            .declarations
            .iter()
            .map(|d| {
                let built_in = d.built_in_name().unwrap_or_else(|| panic!("runtime/reflect.pep: '{}' is not [__BuiltIn]", d.name()));
                let members = match d {
                    Declaration::Struct(s) => {
                        s.fields.iter().map(|f| f.name.clone()).chain(s.methods.iter().map(|m| m.name.clone())).collect()
                    }
                    _ => vec![],
                };
                (built_in, members)
            })
            .collect()
    }

    /// `runtime/reflect.pep` declares every `reflect` function the
    /// compiler has, and every property of what they return, and nothing
    /// the compiler does not have.
    #[test]
    fn reflect_declarations_match_the_compiler() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let source = std::fs::read_to_string(root.join("crates/pepper-sema/src/passes/static_blocks.rs")).unwrap();
        let declared = reflect_declarations(&root);
        let functions = arm_names(&source, "fn reflect(");
        assert!(functions.contains(&"properties".to_string()), "{:?}", functions);
        let declared_functions: Vec<&str> =
            declared.iter().filter_map(|(name, _)| name.strip_prefix("reflect.")).filter(|n| n.starts_with(char::is_lowercase)).collect();
        for name in &functions {
            assert!(declared_functions.contains(&name.as_str()), "runtime/reflect.pep does not declare 'reflect.{}'; add it", name);
        }
        for name in &declared_functions {
            assert!(functions.iter().any(|f| f == name), "runtime/reflect.pep declares 'reflect.{}', which the compiler does not have", name);
        }
        let mut properties = arm_names(&source, "fn member(");
        properties.extend(arm_names(&source, "fn method("));
        assert!(properties.contains(&"is_last".to_string()), "{:?}", properties);
        let members: Vec<&String> = declared.iter().flat_map(|(_, members)| members).collect();
        for name in &properties {
            assert!(members.contains(&name), "runtime/reflect.pep does not declare the property or method '{}'; add it", name);
        }
    }

    #[test]
    fn signatures_leave_out_caller_location_parameters() {
        let signature_of = |source: &str| {
            let module = pepper_parser::parser::parse_source("runtime/t.pep", source).unwrap();
            let Some(Declaration::Function(f)) = module.declarations.first() else { panic!("no function") };
            function_signature(source, f)
        };
        assert_eq!(signature_of("export f(x: int, location: __ptr<char> = __caller_location()): int { return x; }"), "f(x: int): int");
        assert_eq!(signature_of("export g(location: __ptr<char> = __caller_location(), y: int = 0) {}"), "g(y: int = 0)");
        assert_eq!(signature_of("export h(location: __ptr<char> = __caller_location()) {}"), "h()");
    }

    #[test]
    fn re_exports_link_to_their_sources() {
        let source = "export * from \"types\";\nexport [Path, join as combine] from \"path\";\nexport * from async;\n";
        let module = pepper_parser::parser::parse_source("runtime/io/module.pep", source).unwrap();
        assert_eq!(
            reexports(&module, "io/module.pep"),
            "\n## Re-exports\n\n\
             - Everything [`types.pep`](io-types.md) exports.\n\
             - `Path` from [`path.pep`](io-path.md).\n\
             - `join` (as `combine`) from [`path.pep`](io-path.md).\n\
             - Everything [the `async` module](async-module.md) exports.\n"
        );
    }
}
