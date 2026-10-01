//! The resolution sweep: open real Pepper files as the editor would, hover
//! and go to the definition of every name in them, and report each that does
//! not resolve. Run it with
//!
//!     cargo test --release -p pepper-lsp resolution_sweep -- --ignored --nocapture
//!
//! `PEPPER_SWEEP` limits it to the files whose path contains that text.

use super::*;

/// A name in `text` the sweep asks about: its offset and the name.
fn names(text: &str) -> Vec<(usize, &str)> {
    let bytes = text.as_bytes();
    let mut out = vec![];
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            // A comment runs to the end of its line.
            b'#' => {
                while i < bytes.len() && bytes[i] != b'\n' {
                    i += 1;
                }
            }
            // A string, which may span lines, or a character, escapes
            // included.
            quote @ (b'"' | b'\'') => {
                i += 1;
                while i < bytes.len() && bytes[i] != quote && (quote == b'"' || bytes[i] != b'\n') {
                    i += if bytes[i] == b'\\' { 2 } else { 1 };
                }
                i += 1;
            }
            b if b.is_ascii_alphabetic() || b == b'_' => {
                let start = i;
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                    i += 1;
                }
                // Not part of a number (`0x1F`, `1e5`).
                if start == 0 || !bytes[start - 1].is_ascii_digit() {
                    out.push((start, &text[start..i]));
                }
            }
            _ => i += 1,
        }
    }
    out
}

/// Names that have no declaration to go to: keywords and built-in types.
const BUILT_IN: &[&str] = &[
    "this", "null", "auto", "void", "bool", "byte", "char", "short", "ushort", "int", "uint", "long", "ulong",
    "float", "double", "sbyte", "__ptr", "__weak", "__null", "sizeof", "assert", "panic", "as", "with",
    "break", "continue", "not", "async", "await", "yield", "type", "extend", "with", "__default",
    "__function_pointer", "__weak_from", "__weak_upgrade", "__move", "__unreachable", "_", "print",
];

/// The line of `text` around `offset`, trimmed, with the name marked.
fn context(text: &str, offset: usize, name: &str) -> String {
    let start = text[..offset].rfind('\n').map_or(0, |i| i + 1);
    let end = text[offset..].find('\n').map_or(text.len(), |i| offset + i);
    let line = text[start..end].trim_end_matches('\r');
    let at = offset - start;
    format!("{}«{}»{}", &line[..at], name, &line[at + name.len()..]).trim().to_string()
}

#[derive(Default)]
struct Report {
    names: usize,
    hover_missing: Vec<String>,
    hover_unknown: Vec<String>,
    definition_missing: Vec<String>,
    /// Files that could not be read or did not load.
    unloaded: Vec<String>,
}

/// Sweep one file.
fn sweep_file(path: &std::path::Path, report: &mut Report) {
    let Ok(text) = std::fs::read_to_string(path) else {
        report.unloaded.push(path.display().to_string());
        return;
    };
    let uri = Url::from_file_path(path).unwrap();
    // As the server analyzes it: for the OS the file targets.
    let analysis = analysis::Analysis::new(uri.clone(), text.clone(), 0);
    let Ok(program) = analysis.program() else {
        report.unloaded.push(path.display().to_string());
        return;
    };
    let sema = analysis.sema().and_then(|s| s.as_ref().ok());
    let label = path.to_string_lossy().replace('\\', "/");
    let label = label.rsplit_once("/runtime/").map(|(_, r)| format!("runtime/{r}")).unwrap_or(label);
    let line_of = |offset: usize| text[..offset].bytes().filter(|&b| b == b'\n').count() + 1;
    let declared = |offset: usize| {
        // A name being declared (`var x`, `struct S`, `f(`, `x:`) has no
        // definition to go to but itself; skip the definition check there.
        let before = text[..offset].trim_end();
        before.ends_with("var") || before.ends_with("const") || before.ends_with("struct") || before.ends_with("trait")
            || before.ends_with("enum") || before.ends_with("export") || before.ends_with("static")
            || before.ends_with("import") || before.ends_with('\n') || before.ends_with('{') || before.ends_with(';')
            || before.ends_with('}')
    };
    for (offset, name) in names(&text) {
        if KEYWORDS.contains(&name) || BUILT_IN.contains(&name) || name.starts_with("__") {
            continue;
        }
        // Attributes (`[Target(OS(Windows))]`) name no declarations.
        let line_start = text[..offset].rfind('\n').map_or(0, |i| i + 1);
        let before = &text[line_start..offset];
        let item = before.rsplit(['(', ',']).next().unwrap_or(before);
        if before.trim_start().starts_with('[') || item.trim_start().starts_with('[') {
            continue;
        }
        report.names += 1;
        let at = format!("{}:{}: {}", label, line_of(offset), context(&text, offset, name));
        let hover = guarded(|| PepperLsp::hover_at(&uri, &text, Some(&program), sema, offset)).flatten();
        match hover.map(|h| h.contents) {
            None => report.hover_missing.push(at.clone()),
            Some(HoverContents::Markup(m)) if m.value.lines().next().is_some_and(|l| l.contains("unknown")) => {
                report.hover_unknown.push(at.clone())
            }
            _ => {}
        }
        // A built-in type or constraint has a hover but no declaration.
        if !declared(offset) && name != "Shared" && !pepper_sema::type_name::INTEGRAL_TYPES.contains(name)
            && guarded(|| PepperLsp::definition_at(&uri, &text, Some(&program), sema, offset)).flatten().is_none()
        {
            report.definition_missing.push(at);
        }
    }
}

/// Files where every name resolves today, in each kind of code: the runtime
/// (structs, generics, closures, extensions, trait-typed fields, other
/// files' helpers, generic bodies nothing instantiates) and examples
/// (patterns, enum methods, constrained generics, lowered calls, tuple
/// labels). Any name in them that stops resolving fails
/// this test, with the sweep's line for it.
const CLEAN: &[&str] = &[
    "runtime/async/task.pep",
    "runtime/async/task_local.pep",
    "runtime/async/once.pep",
    "runtime/async/thread_local.pep",
    "runtime/optional.pep",
    "runtime/scoped.pep",
    "runtime/weak.pep",
    "runtime/io/directory.pep",
    "runtime/async/mutex.pep",
    "runtime/async/channel.pep",
    "runtime/result.pep",
    "docs/examples/atomics-patterns.pep",
    "docs/examples/c-callbacks.pep",
    "docs/examples/collection-literals.pep",
    "docs/examples/generics-structs.pep",
    "docs/examples/iteration-arrays.pep",
    "docs/examples/memory-sharing.pep",
    "docs/examples/enums-match-values.pep",
    "docs/examples/enums-methods.pep",
    "docs/examples/generics-constrained-bodies.pep",
    "docs/examples/interpolation-string-format.pep",
    "docs/examples/tuples-labels.pep",
];

#[test]
fn clean_files_resolve() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize().unwrap();
    let mut report = Report::default();
    for file in CLEAN {
        sweep_file(&root.join(file), &mut report);
    }
    let failures: Vec<String> = [
        ("no hover", &report.hover_missing),
        ("hover unknown", &report.hover_unknown),
        ("no definition", &report.definition_missing),
    ]
    .iter()
    .flat_map(|(what, list)| list.iter().map(move |l| format!("{what}: {l}")))
    .collect();
    assert!(report.unloaded.is_empty(), "files that did not load: {:?}", report.unloaded);
    assert!(report.names > 2500, "the sweep found only {} names", report.names);
    assert!(failures.is_empty(), "{} names stopped resolving:
{}", failures.len(), failures.join("
"));
}

#[test]
#[ignore]
fn resolution_sweep() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize().unwrap();
    let filter = std::env::var("PEPPER_SWEEP").unwrap_or_default();
    let mut files = vec![];
    let mut stack = vec![root.join("runtime"), root.join("docs/examples"), root.join("tests")];
    while let Some(dir) = stack.pop() {
        for entry in std::fs::read_dir(&dir).into_iter().flatten().flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "pep") && path.to_string_lossy().replace('\\', "/").contains(&filter) {
                files.push(path);
            }
        }
    }
    files.sort();
    let mut report = Report::default();
    for file in &files {
        sweep_file(file, &mut report);
    }
    let out = root.join("target/resolution-sweep.txt");
    let mut text = format!(
        "{} files, {} names: {} without a hover, {} hovering unknown, {} without a definition\n",
        files.len(),
        report.names,
        report.hover_missing.len(),
        report.hover_unknown.len(),
        report.definition_missing.len()
    );
    for (title, list) in [
        ("no hover", &report.hover_missing),
        ("hover unknown", &report.hover_unknown),
        ("no definition", &report.definition_missing),
    ] {
        text += &format!("\n== {} ({})\n", title, list.len());
        for line in list {
            text += line;
            text += "\n";
        }
    }
    std::fs::write(&out, &text).unwrap();
    eprintln!("{}", text.lines().next().unwrap());
    eprintln!("report: {}", out.display());
}
