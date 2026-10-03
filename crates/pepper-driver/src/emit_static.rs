//! `--emit-static`: the program's source with each `static` block replaced
//! by the code it emits, Pepper's `cc -E`.
//!
//! Sema records each expansion as source
//! (`pepper_sema::passes::static_source`); this writes a copy of every file
//! of the program under the entry file's folder (the runtime and other
//! libraries are left where they are) into the output folder, mirroring
//! the paths, so the copy builds as a whole program:
//!
//! - A block in concrete code becomes its expansion, a `{ ... }` block
//!   between `# static (...) expanded from file:line:col` and
//!   `# end static`.
//! - A block in a generic free function expands differently for each
//!   specialization, so the function stays as written and is followed by a
//!   concrete override per specialization the program uses
//!   (`describe<Point>(value: Point)`), with its blocks expanded.
//! - A block in any other generic code (a method of a generic struct, a
//!   generic method) stays, with each specialization's expansion above it
//!   as `#` comments.
//!
//! Every other byte of a file is copied as it is. Then `pep-fmt`, when it
//! is beside the compiler or on `PATH`, formats the copies.

use crate::compiler;
use crate::Options;
use pepper_parser::ast;
use pepper_sema::passes::static_source::{substitute_names, Expansion};
use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};

/// Compiles the program, recording its `static` blocks' expansions, and
/// writes the expanded copies. With `keep`, each block is also kept as a
/// `#` comment above its expansion.
pub fn run(options: &Options, keep: bool) -> Result<i32, String> {
    let entry = options.source_files.first().ok_or_else(|| "no source files".to_string())?;
    let (compiled, expansions) = pepper_sema::passes::static_source::record(|| compiler::compile_program(options));
    let (_, program) = compiled?;
    let root = match entry.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => absolute(parent),
        _ => absolute(Path::new(".")),
    };
    let out_dir = match &options.output {
        Some(dir) => dir.clone(),
        None => PathBuf::from(format!("{}.static", entry.file_stem().map_or("main".into(), |s| s.to_string_lossy()))),
    };
    let mut by_file: BTreeMap<usize, Vec<Expansion>> = BTreeMap::new();
    for expansion in expansions {
        by_file.entry(expansion.loc.file.0 as usize).or_default().push(expansion);
    }
    let mut written = vec![];
    for (index, file) in program.files.iter().enumerate() {
        if file.prelude || file.prelude_part {
            continue;
        }
        let path = absolute(Path::new(&file.name));
        let Some(relative) = path.strip_prefix(&root).ok().filter(|r| !r.components().any(|c| c == Component::Normal(".pep".as_ref()))) else {
            continue; // a library outside the program's folder: it builds from where it is
        };
        let display = relative.to_string_lossy().replace('\\', "/");
        let text = match by_file.get(&index) {
            Some(expansions) => expand_file(&file.source, &display, expansions, keep)?,
            None => file.source.clone(),
        };
        let target = out_dir.join(relative);
        if absolute(&target) == path {
            return Err(format!("--emit-static would overwrite {}; choose another folder with -o", file.name));
        }
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {}", parent.display(), e))?;
        }
        std::fs::write(&target, text).map_err(|e| format!("cannot write {}: {}", target.display(), e))?;
        written.push(target);
    }
    if let Some(formatter) = formatter()
        && !written.is_empty()
    {
        // The expansion is indented to fit; pep-fmt also wraps long lines.
        let formatted = std::process::Command::new(&formatter).arg("-w").args(&written).status();
        if !formatted.is_ok_and(|status| status.success()) {
            crate::report_warnings(&format!("warning: {} could not format the expanded files; they are written unformatted", formatter.display()));
        }
    }
    Ok(0)
}

/// `pep-fmt`: beside this compiler's executable, else on `PATH`.
fn formatter() -> Option<PathBuf> {
    let name = if cfg!(windows) { "pep-fmt.exe" } else { "pep-fmt" };
    let beside = std::env::current_exe().ok().and_then(|exe| exe.parent().map(|dir| dir.join(name)));
    let on_path = std::env::var_os("PATH").into_iter().flat_map(|path| std::env::split_paths(&path).map(|dir| dir.join(name)).collect::<Vec<_>>());
    beside.into_iter().chain(on_path).find(|candidate| candidate.is_file())
}

fn absolute(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).or_else(|_| std::path::absolute(path)).unwrap_or_else(|_| path.to_path_buf())
}

/// One block's expansions: a concrete block has one, with no type
/// arguments; a block in generic code one per specialization.
struct Block<'e> {
    span: ast::Span,
    expansions: Vec<&'e Expansion>,
}

/// `source` with its recorded blocks expanded (see the module comment).
/// `name` is the file's path as the output shows it.
fn expand_file(source: &str, name: &str, expansions: &[Expansion], keep: bool) -> Result<String, String> {
    let mut blocks: BTreeMap<usize, Block> = BTreeMap::new();
    for expansion in expansions {
        let block = blocks.entry(expansion.span.start).or_insert_with(|| Block { span: expansion.span, expansions: vec![] });
        if !block.expansions.iter().any(|e| e.type_arguments == expansion.type_arguments) {
            block.expansions.push(expansion);
        }
    }
    for block in blocks.values_mut() {
        block.expansions.sort_by(|a, b| a.type_arguments.cmp(&b.type_arguments));
    }
    let module = pepper_parser::parser::parse_source(name, source)?;
    // The generic free functions with a block, and where each ends.
    let mut overrides: Vec<(&ast::FunctionDecl, usize, Vec<&Block>)> = vec![];
    for declaration in &module.declarations {
        if let ast::Declaration::Function(function) = declaration
            && !function.generic_params.is_empty()
        {
            let inside: Vec<&Block> =
                blocks.values().filter(|b| b.span.start >= function.span.start && b.span.end <= function.span.end && is_generic(b)).collect();
            // A declaration's span runs on to the next one; its body ends at its `}`.
            if !inside.is_empty()
                && let Some(body) = &function.body
            {
                overrides.push((function, body.span.end, inside));
            }
        }
    }
    let mut out = String::with_capacity(source.len() * 2);
    let mut at = 0;
    let mut pending = overrides.iter().peekable();
    for block in blocks.values() {
        // Overrides go after their generic function, before any later block.
        while let Some((function, end, inside)) = pending.next_if(|(_, end, _)| *end <= block.span.start) {
            out.push_str(&source[at..*end]);
            out.push_str(&specializations(source, name, function, *end, inside));
            at = *end;
        }
        out.push_str(&source[at..block.span.start]);
        let indent = line_indent(source, block.span.start);
        if !is_generic(block) {
            out.push_str(&expanded(source, name, block.span, &block.expansions[0].lines, &indent, keep, &[]));
            at = block.span.end;
        } else if overrides.iter().any(|(_, _, inside)| inside.iter().any(|b| b.span.start == block.span.start)) {
            // Expanded in the overrides; the generic function stays as written.
            out.push_str(&source[block.span.start..block.span.end]);
            at = block.span.end;
        } else {
            out.push_str(&commented(source, name, block, &indent));
            at = block.span.start;
        }
    }
    for (function, end, inside) in pending {
        out.push_str(&source[at..*end]);
        out.push_str(&specializations(source, name, function, *end, inside));
        at = *end;
    }
    out.push_str(&source[at..]);
    Ok(out)
}

fn is_generic(block: &Block) -> bool {
    block.expansions.iter().any(|e| !e.type_arguments.is_empty())
}

/// The whitespace before the first non-blank character of the line `at` is on.
fn line_indent(source: &str, at: usize) -> String {
    let start = source[..at].rfind('\n').map_or(0, |i| i + 1);
    let line = &source[start..];
    line[..line.len() - line.trim_start_matches([' ', '\t']).len()].to_string()
}

/// `file:line:col` of `at`.
fn position(source: &str, name: &str, at: usize) -> String {
    let line = source[..at].matches('\n').count() + 1;
    let start = source[..at].rfind('\n').map_or(0, |i| i + 1);
    format!("{}:{}:{}", name, line, source[start..at].chars().count() + 1)
}

/// `static (out, value)`: the block's head, as written.
fn head(source: &str, span: ast::Span) -> String {
    let text = &source[span.start..span.end];
    text[..text.find('{').unwrap_or(text.len())].split_whitespace().collect::<Vec<_>>().join(" ").replace("( ", "(").replace(" )", ")")
}

/// The block at `span` replaced by `lines`, bracketed by comments, with
/// lines after the first at `indent`; with `keep`, the block as written
/// first, as `#` comments. `label` names a specialization's type arguments.
fn expanded(source: &str, name: &str, span: ast::Span, lines: &[String], indent: &str, keep: bool, label: &[(String, String)]) -> String {
    let mut out = vec![];
    if keep {
        for line in source[span.start..span.end].lines().enumerate().map(|(i, line)| if i == 0 { line } else { strip_indent(line, indent) }) {
            out.push(if line.trim().is_empty() { "#".to_string() } else { format!("# {}", line.trim_end()) });
        }
    }
    let mut first = format!("# {} expanded from {}", head(source, span), position(source, name, span.start));
    if !label.is_empty() {
        first.push_str(&format!(" for {}", arguments(label)));
    }
    out.push(first);
    out.extend(lines.iter().cloned());
    out.push("# end static".to_string());
    out.iter()
        .enumerate()
        .map(|(i, line)| if i == 0 || line.is_empty() { line.clone() } else { format!("{}{}", indent, line) })
        .collect::<Vec<_>>()
        .join("\n")
}

fn strip_indent<'l>(line: &'l str, indent: &str) -> &'l str {
    line.strip_prefix(indent).unwrap_or_else(|| line.trim_start())
}

/// `T = Point, U = int`.
fn arguments(type_arguments: &[(String, String)]) -> String {
    type_arguments.iter().map(|(param, ty)| format!("{} = {}", param, ty)).collect::<Vec<_>>().join(", ")
}

/// A block in generic code other than a free function: each
/// specialization's expansion as `#` comments, above the block, which
/// stays.
fn commented(source: &str, name: &str, block: &Block, indent: &str) -> String {
    let mut out = vec![format!("# {} at {} expands in each specialization:", head(source, block.span), position(source, name, block.span.start))];
    for expansion in &block.expansions {
        out.push(format!("# for {}", arguments(&expansion.type_arguments)));
        out.extend(expansion.lines.iter().map(|line| format!("# {}", line)));
    }
    out.push("# end static".to_string());
    let mut text: String = out.iter().enumerate().map(|(i, line)| if i == 0 { line.clone() } else { format!("{}{}", indent, line) }).collect::<Vec<_>>().join("\n");
    text.push('\n');
    text.push_str(indent);
    text
}

/// After generic `function`, which ends at `end`, a concrete override per specialization whose
/// blocks expanded, each with its type arguments in place of the type
/// parameters and its blocks expanded.
fn specializations(source: &str, name: &str, function: &ast::FunctionDecl, end: usize, blocks: &[&Block]) -> String {
    let mut by_arguments: BTreeMap<Vec<(String, String)>, Vec<(&Block, &Expansion)>> = BTreeMap::new();
    for block in blocks {
        for expansion in &block.expansions {
            by_arguments.entry(expansion.type_arguments.clone()).or_default().push((block, expansion));
        }
    }
    let params: Vec<&str> = function.generic_params.iter().map(|p| p.name.as_str()).collect();
    let indent = line_indent(source, function.name_span.start);
    let mut out = String::new();
    for (type_arguments, expanded_blocks) in by_arguments {
        // Only the function's own parameters name a specialization.
        let names: Vec<(String, String)> = type_arguments.iter().filter(|(param, _)| params.contains(&param.as_str())).cloned().collect();
        let Some(spelled) = params.iter().map(|p| names.iter().find(|(param, _)| param == p).map(|(_, ty)| ty.clone())).collect::<Option<Vec<_>>>() else {
            continue;
        };
        // The text from the name, with `<T>` spelled `<Point>`.
        let list_start = function.name_span.end;
        let Some(list_end) = generic_list_end(source, list_start) else { continue };
        let mut text = format!("\n\n{}# '{}' specialized for {}, with its static blocks expanded\n{}", indent, function.name, arguments(&names), indent);
        if function.is_exported {
            text.push_str("export ");
        }
        text.push_str(&source[function.name_span.start..list_start]);
        text.push_str(&format!("<{}>", spelled.join(", ")));
        let mut at = list_end;
        let mut inside = expanded_blocks.clone();
        inside.sort_by_key(|(block, _)| block.span.start);
        for (block, expansion) in inside {
            text.push_str(&substitute_names(source, ast::Span { start: at, end: block.span.start }, &names));
            let block_indent = line_indent(source, block.span.start);
            text.push_str(&expanded(source, name, block.span, &expansion.lines, &block_indent, false, &names));
            at = block.span.end;
        }
        text.push_str(&substitute_names(source, ast::Span { start: at, end }, &names));
        out.push_str(&text);
    }
    out
}

/// The end of the generic parameter list `<...>` starting at `at` (after
/// spaces), past its `>`.
fn generic_list_end(source: &str, at: usize) -> Option<usize> {
    let rest = &source[at..];
    let start = at + (rest.len() - rest.trim_start().len());
    if !source[start..].starts_with('<') {
        return None;
    }
    let mut depth = 0;
    for (i, c) in source[start..].char_indices() {
        match c {
            '<' => depth += 1,
            '>' => {
                depth -= 1;
                if depth == 0 {
                    return Some(start + i + 1);
                }
            }
            _ => {}
        }
    }
    None
}
