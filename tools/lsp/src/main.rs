//! Pepper language server.
//!
//! Speaks LSP over stdio. Diagnostics come from the parser (precise, via AST
//! spans) and from a full semantic check of the merged program (runtime
//! prelude + resolved imports + the open document). Hover, completion,
//! go-to-definition, and document symbols are computed from the parsed AST
//! plus the sema model; names reached through imports are followed using
//! what linking recorded (see `imports`).

mod imports;
#[cfg(test)]
mod tests;

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

use pepper_parser::ast::{self, Span};
use pepper_parser::diagnostic::{self as diag, FileId};
use pepper_parser::parser::parse_source;
use pepper_parser::namespace::{demangle, demangle_known, demangle_name};
use pepper_sema::model::{Conversion, FunctionDef, Module as SemaModule, StructDef};
use tower_lsp::jsonrpc::Result as LspResult;
use tower_lsp::lsp_types::*;
use tower_lsp::{async_trait, Client, LanguageServer, LspService, Server};

const KEYWORDS: &[&str] = &[
    "import", "from", "struct", "var", "const", "if", "else", "while", "for", "in", "return", "extern",
    "and", "or", "construct", "destruct", "static", "sizeof", "true", "false", "trait",
    "extend", "export", "shared", "enum", "match",
];

// ── Position conversion ───────────────────────────────────────────────────────

/// Convert an (LSP line, UTF-16 column) to a byte offset in `source`.
fn line_col_to_byte(source: &str, line: u32, col: u32) -> usize {
    let mut cur_line = 0u32;
    let mut remaining = col;
    for (i, ch) in source.char_indices() {
        if cur_line == line {
            let units: u32 = if (ch as u32) < 0x10000 { 1 } else { 2 };
            if units > remaining {
                return i;
            }
            remaining -= units;
        }
        if ch == '\n' {
            cur_line += 1;
        }
    }
    source.len()
}

/// Convert a byte offset to an LSP (line, UTF-16 column) position.
fn byte_to_lsp_pos(source: &str, offset: usize) -> Position {
    let offset = offset.min(source.len());
    let before = &source[..offset];
    let line = before.bytes().filter(|&b| b == b'\n').count() as u32;
    let col_start = match before.rfind('\n') {
        Some(i) => i + 1,
        None => 0,
    };
    let mut units = 0u32;
    for ch in before[col_start..].chars() {
        units += if (ch as u32) < 0x10000 { 1 } else { 2 };
    }
    Position::new(line, units)
}

fn span_to_range(source: &str, span: Span) -> Range {
    Range::new(byte_to_lsp_pos(source, span.start), byte_to_lsp_pos(source, span.end))
}

/// A document symbol. `DocumentSymbol` has no constructor or `Default`, and its
/// `deprecated` field (superseded by `tags`) must still be named in a struct
/// literal, so the literal lives here, once.
#[allow(deprecated)]
fn new_symbol(
    name: String,
    detail: String,
    kind: SymbolKind,
    range: Range,
    selection_range: Range,
    children: Option<Vec<DocumentSymbol>>,
) -> DocumentSymbol {
    DocumentSymbol {
        name,
        detail: Some(detail),
        kind,
        tags: None,
        deprecated: None,
        range,
        selection_range,
        children,
    }
}

// ── Symbols & scopes ──────────────────────────────────────────────────────────

#[derive(Clone)]
struct Symbol {
    name: String,
    /// Span of the declared name token.
    name_span: Span,
    /// Rendered type (`int`, `Array<int>`, function signature).
    ty: String,
}

fn type_string(ty: &ast::TypeName) -> String {
    ty.to_string()
}

fn function_signature(f: &ast::FunctionDecl) -> String {
    let params = f
        .parameters
        .iter()
        .map(|p| format!("{}: {}", p.name, type_string(&p.type_name)))
        .collect::<Vec<_>>()
        .join(", ");
    format!("{}({}): {}", f.name, params, type_string(&f.return_type))
}

fn collect_struct_members(s: &ast::StructDecl) -> Vec<Symbol> {
    let mut out = vec![];
    for case in s.enumeration.iter().flat_map(|e| &e.cases) {
        out.push(Symbol { name: case.name.clone(), name_span: case.name_span, ty: format!("{}.{}", s.name, case.name) });
    }
    for field in &s.fields {
        out.push(Symbol {
            name: field.name.clone(),
            name_span: field.name_span,
            ty: type_string(&field.type_name),
        });
    }
    if let Some(ctor) = &s.constructor {
        let params = ctor
            .parameters
            .iter()
            .map(|p| format!("{}: {}", p.name, type_string(&p.type_name)))
            .collect::<Vec<_>>()
            .join(", ");
        out.push(Symbol { name: "construct".to_string(), name_span: ctor.name_span, ty: format!("construct({})", params) });
    }
    for m in &s.methods {
        out.push(Symbol { name: m.name.clone(), name_span: m.name_span, ty: function_signature(m) });
    }
    out
}

/// Rendered type of a variable declaration; `__auto` locals are inferred
/// from a literal initializer when one is present.
fn variable_type(v: &ast::VariableDecl) -> String {
    if v.type_name.name == "__auto"
        && let Some(init) = &v.default_value
    {
        return match init {
            ast::Expression::Literal { value, .. } => match value {
                ast::Literal::String(_) => "String".to_string(),
                ast::Literal::Integer(_) => "int".to_string(),
                ast::Literal::Float(_) => "float".to_string(),
                ast::Literal::Bool(_) => "bool".to_string(),
                ast::Literal::Char(_) => "byte".to_string(),
                ast::Literal::Null => "__null".to_string(),
            },
            _ => "unknown".to_string(),
        };
    }
    type_string(&v.type_name)
}

/// Collect top-level symbols of a parsed module.
fn collect_globals(module: &ast::Module) -> Vec<Symbol> {
    let mut out = vec![];
    for decl in &module.declarations {
        match decl {
            ast::Declaration::Variable(v) => out.push(Symbol {
                name: v.name.clone(),
                name_span: v.name_span,
                ty: variable_type(v),
            }),
            ast::Declaration::Function(f) => out.push(Symbol {
                name: f.name.clone(),
                name_span: f.name_span,
                ty: function_signature(f),
            }),
            ast::Declaration::Struct(s) => out.push(Symbol {
                name: s.name.clone(),
                name_span: s.name_span,
                ty: format!("{} {}", if s.enumeration.is_some() { "enum" } else { "struct" }, type_string(&ast::TypeName {
                    name: s.name.clone(),
                    generic_types: s.generic_params.iter().map(|p| ast::TypeName { name: p.name.clone(), generic_types: vec![], span: Span::none() }).collect(),
                    span: Span::none(),
                })),
            }),
            ast::Declaration::Trait(t) => out.push(Symbol {
                name: t.name.clone(),
                name_span: t.name_span,
                ty: "trait".to_string(),
            }),
            ast::Declaration::Extend(_) => {}
            ast::Declaration::TypeAlias(t) => {
                let params = t
                    .generic_params
                    .iter()
                    .map(|p| p.name.clone())
                    .collect::<Vec<_>>()
                    .join(", ");
                let ty = if params.is_empty() {
                    format!("type {} = {}", t.name, t.target)
                } else {
                    format!("type {}<{}> = {}", t.name, params, t.target)
                };
                out.push(Symbol {
                    name: t.name.clone(),
                    name_span: t.name_span,
                    ty,
                });
            }
        }
    }
    out
}

/// Local declarations visible at `offset` inside `block`, in source order.
fn locals_at(block: &ast::Block, offset: usize) -> Vec<Symbol> {
    let mut out = vec![];
    collect_locals_upto(block, offset, &mut out);
    out
}

fn collect_locals_upto(block: &ast::Block, offset: usize, out: &mut Vec<Symbol>) {
    for stmt in &block.statements {
        let s = stmt.span();
        if s.end <= offset {
            match stmt {
                ast::Statement::Declaration(ast::Declaration::Variable(v)) => {
                    out.push(Symbol {
                        name: v.name.clone(),
                        name_span: v.name_span,
                        ty: variable_type(v),
                    });
                }
                _ => {}
            }
        } else if s.start <= offset && offset < s.end {
            match stmt {
                ast::Statement::Block(b) => collect_locals_upto(b, offset, out),
                ast::Statement::Branch(br) => {
                    if br.if_block.span.start <= offset && offset < br.if_block.span.end {
                        collect_locals_upto(&br.if_block, offset, out);
                    } else if let Some(e) = &br.else_block
                        && e.span.start <= offset
                        && offset < e.span.end
                    {
                        collect_locals_upto(e, offset, out);
                    }
                }
                ast::Statement::While(w) => {
                    if w.block.span.start <= offset && offset < w.block.span.end {
                        collect_locals_upto(&w.block, offset, out);
                    }
                }
                ast::Statement::For(f) => {
                    if f.block.span.start <= offset && offset < f.block.span.end {
                        out.push(Symbol {
                            name: f.binding.name.clone(),
                            name_span: f.binding.name_span,
                            ty: variable_type(&f.binding),
                        });
                        collect_locals_upto(&f.block, offset, out);
                    }
                }
                ast::Statement::With(w) => {
                    if w.block.span.start <= offset && offset < w.block.span.end {
                        if let Some(b) = &w.binding {
                            out.push(Symbol { name: b.name.clone(), name_span: b.name_span, ty: variable_type(b) });
                        }
                        collect_locals_upto(&w.block, offset, out);
                    } else if let Some(e) = &w.else_block
                        && e.span.start <= offset
                        && offset < e.span.end
                    {
                        collect_locals_upto(e, offset, out);
                    }
                }
                ast::Statement::Match(m) => {
                    let arms = m.arms.iter().map(|a| &a.body).chain(m.else_arm.as_ref().map(|(_, b)| b));
                    for body in arms {
                        if body.span.start <= offset && offset < body.span.end {
                            collect_locals_upto(body, offset, out);
                        }
                    }
                }
                _ => {}
            }
        }
    }
}

/// The function body containing `offset`, if any, plus the enclosing struct.
fn body_at<'a>(module: &'a ast::Module, offset: usize) -> Option<(&'a ast::Block, Option<&'a ast::StructDecl>)> {
    for decl in &module.declarations {
        match decl {
            ast::Declaration::Function(f) => {
                if f.span.start <= offset && offset < f.span.end
                    && let Some(body) = &f.body
                {
                    return Some((body, None));
                }
            }
            ast::Declaration::Struct(s) => {
                if !(s.span.start <= offset && offset < s.span.end) {
                    continue;
                }
                for m in &s.methods {
                    if m.span.start <= offset && offset < m.span.end
                        && let Some(body) = &m.body
                    {
                        return Some((body, Some(s)));
                    }
                }
                if let Some(c) = &s.constructor
                    && c.span.start <= offset
                    && offset < c.span.end
                    && let Some(body) = &c.body
                {
                    return Some((body, Some(s)));
                }
            }
            _ => {}
        }
    }
    None
}

// ── Expression lookup ─────────────────────────────────────────────────────────

/// The innermost expression containing `offset`.
fn expr_at<'a>(expr: &'a ast::Expression, offset: usize) -> Option<&'a ast::Expression> {
    let s = expr.span();
    if !(s.start <= offset && offset < s.end) {
        return None;
    }
    match expr {
        ast::Expression::Binary { lhs, rhs, .. } => expr_at(lhs, offset).or_else(|| expr_at(rhs, offset)),
        ast::Expression::Unary { operand, .. } => expr_at(operand, offset),
        ast::Expression::Ternary { condition, true_expr, false_expr, .. } => {
            expr_at(condition, offset)
                .or_else(|| expr_at(true_expr, offset))
                .or_else(|| expr_at(false_expr, offset))
        }
        ast::Expression::Index { lhs, rhs, .. } => expr_at(lhs, offset).or_else(|| expr_at(rhs, offset)),
        ast::Expression::MemberAccess { lhs, name_span, .. } => {
            if name_span.start <= offset && offset < name_span.end {
                // The member *name* itself: report the whole access.
                Some(expr)
            } else {
                expr_at(lhs, offset)
            }
        }
        ast::Expression::FunctionCall { function, arguments, .. } => {
            if let Some(inner) = expr_at(function, offset) {
                return Some(inner);
            }
            for a in arguments {
                if let Some(inner) = expr_at(a, offset) {
                    return Some(inner);
                }
            }
            Some(expr)
        }
        _ => Some(expr),
    }
}

/// The innermost expression containing `offset` anywhere in the module.
fn find_expr<'a>(module: &'a ast::Module, offset: usize) -> Option<&'a ast::Expression> {
    let (body, _) = body_at(module, offset)?;
    find_expr_in_block(body, offset)
}

fn find_expr_in_block<'a>(block: &'a ast::Block, offset: usize) -> Option<&'a ast::Expression> {
    for stmt in &block.statements {
        let s = stmt.span();
        if !(s.start <= offset && offset < s.end) {
            continue;
        }
        match stmt {
            ast::Statement::Expression(e) | ast::Statement::Return(ast::ReturnStatement { expr: Some(e), .. }) => {
                if let Some(found) = expr_at(e, offset) {
                    return Some(found);
                }
            }
            ast::Statement::Declaration(ast::Declaration::Variable(v)) => {
                if let Some(found) = v.default_value.as_ref().and_then(|e| expr_at(e, offset)) {
                    return Some(found);
                }
            }
            ast::Statement::Block(b) => {
                if let Some(found) = find_expr_in_block(b, offset) {
                    return Some(found);
                }
            }
            ast::Statement::Branch(br) => {
                if let Some(found) = expr_at(&br.condition, offset) {
                    return Some(found);
                }
                if let Some(found) = find_expr_in_block(&br.if_block, offset) {
                    return Some(found);
                }
                if let Some(el) = &br.else_block
                    && let Some(found) = find_expr_in_block(el, offset)
                {
                    return Some(found);
                }
            }
            ast::Statement::While(w) => {
                if let Some(found) = expr_at(&w.condition, offset) {
                    return Some(found);
                }
                if let Some(found) = find_expr_in_block(&w.block, offset) {
                    return Some(found);
                }
            }
            ast::Statement::For(f) => {
                if let Some(found) = expr_at(&f.iterable, offset) {
                    return Some(found);
                }
                if let Some(found) = find_expr_in_block(&f.block, offset) {
                    return Some(found);
                }
            }
            ast::Statement::With(w) => {
                if let Some(found) = expr_at(&w.scope, offset) {
                    return Some(found);
                }
                if let Some(found) = find_expr_in_block(&w.block, offset) {
                    return Some(found);
                }
                if let Some(el) = &w.else_block
                    && let Some(found) = find_expr_in_block(el, offset)
                {
                    return Some(found);
                }
            }
            ast::Statement::Match(m) => {
                if let Some(found) = expr_at(&m.value, offset) {
                    return Some(found);
                }
                let arms = m.arms.iter().map(|a| &a.body).chain(m.else_arm.as_ref().map(|(_, b)| b));
                for body in arms {
                    if let Some(found) = find_expr_in_block(body, offset) {
                        return Some(found);
                    }
                }
            }
            _ => {}
        }
    }
    None
}

// ── Sema lookups (merged model; no spans needed) ──────────────────────────────

/// The quick fix for `match on 'E' does not handle ...` in the document:
/// an arm with an empty block for each case the `match` leaves out, before
/// its closing brace.
fn missing_arms_fix(uri: &Url, text: &str, program: &Program, error: &diag::Diagnostic, range: Range) -> Option<CodeActionOrCommand> {
    let loc = error.loc?;
    if loc.file != FileId(0) || !error.message.starts_with("match on '") || !error.message.contains("does not handle") {
        return None;
    }
    let lsp = lsp_diagnostic(error, uri, &[(uri.as_str(), text)]);
    if !(lsp.range.start <= range.end && range.start <= lsp.range.end) {
        return None;
    }
    let enum_name = error.message["match on '".len()..].split('\'').next()?;
    let ast = parse_source(uri.as_str(), text).ok()?;
    let found = find_match(&ast, loc.span.start)?;
    let cases = program.files.iter().find_map(|f| {
        f.module.declarations.iter().find_map(|d| match d {
            ast::Declaration::Struct(s) if s.name == enum_name || demangle_name(&s.name) == enum_name => s.enumeration.as_ref(),
            _ => None,
        })
    })?;
    let handled: Vec<&str> = found.arms.iter().flat_map(|a| &a.patterns).map(|p| p.case.as_str()).collect();
    let missing: Vec<&str> = cases.cases.iter().map(|c| c.name.as_str()).filter(|c| !handled.contains(c)).collect();
    if missing.is_empty() {
        return None;
    }
    let line_start = |at: usize| text[..at].rfind('\n').map_or(0, |i| i + 1);
    let indent: String = text[line_start(found.keyword_span.start)..].chars().take_while(|c| *c == ' ' || *c == '\t').collect();
    let close = found.span.end - 1;
    // Insert on the closing brace's own line when it has one.
    let close_line = line_start(close);
    let (at, prefix) = if text[close_line..close].trim().is_empty() { (close_line, "") } else { (close, "\n") };
    let arms: String = missing.iter().map(|c| format!("{}    {} => {{}}\n", indent, c)).collect();
    let replacement = if prefix.is_empty() { arms } else { format!("\n{}{}", arms, indent) };
    let edit = TextEdit { range: span_to_range(text, Span { start: at, end: at }), new_text: replacement };
    Some(CodeActionOrCommand::CodeAction(CodeAction {
        title: format!("Add the missing case{} of '{}'", if missing.len() == 1 { "" } else { "s" }, enum_name),
        kind: Some(CodeActionKind::QUICKFIX),
        diagnostics: Some(vec![lsp]),
        edit: Some(WorkspaceEdit { changes: Some(HashMap::from([(uri.clone(), vec![edit])])), ..Default::default() }),
        is_preferred: Some(true),
        ..Default::default()
    }))
}

/// The `match` statement whose keyword starts at `start`.
fn find_match(module: &ast::Module, start: usize) -> Option<&ast::Match> {
    fn in_block(b: &ast::Block, start: usize) -> Option<&ast::Match> {
        b.statements.iter().find_map(|s| in_statement(s, start))
    }
    fn in_statement(s: &ast::Statement, start: usize) -> Option<&ast::Match> {
        let span = s.span();
        if start < span.start || start >= span.end {
            return None;
        }
        match s {
            ast::Statement::Match(m) if m.keyword_span.start == start => Some(m),
            ast::Statement::Match(m) => m
                .arms
                .iter()
                .map(|a| &a.body)
                .chain(m.else_arm.as_ref().map(|(_, b)| b))
                .find_map(|b| in_block(b, start)),
            ast::Statement::Block(b) => in_block(b, start),
            ast::Statement::Branch(b) => in_block(&b.if_block, start).or_else(|| b.else_block.as_ref().and_then(|e| in_block(e, start))),
            ast::Statement::While(w) => in_block(&w.block, start),
            ast::Statement::For(f) => in_block(&f.block, start),
            ast::Statement::With(w) => in_block(&w.block, start).or_else(|| w.else_block.as_ref().and_then(|e| in_block(e, start))),
            _ => None,
        }
    }
    module.declarations.iter().find_map(|d| {
        let bodies: Vec<&ast::Block> = match d {
            ast::Declaration::Function(f) => f.body.iter().collect(),
            ast::Declaration::Struct(s) => s
                .methods
                .iter()
                .filter_map(|m| m.body.as_ref())
                .chain(s.constructor.as_ref().and_then(|c| c.body.as_ref()))
                .chain(s.destructor.as_ref())
                .collect(),
            ast::Declaration::Extend(e) => e.methods.iter().filter_map(|m| m.body.as_ref()).collect(),
            ast::Declaration::Trait(t) => t.methods.iter().filter_map(|m| m.body.as_ref()).collect(),
            _ => vec![],
        };
        bodies.into_iter().find_map(|b| in_block(b, start))
    })
}

/// What hover shows for `lhs.name` when `lhs` names an enum and `name` one
/// of its cases: `Color.Red = 0`.
fn enum_case_of(module: &SemaModule, lhs: &ast::Expression, name: &str) -> Option<String> {
    let ast::Expression::SymbolRef { id, .. } = lhs else {
        return None;
    };
    let e = module
        .enums
        .iter()
        .find(|e| e.loc.file == FileId(0) && demangle_name(&e.name) == id)
        .or_else(|| module.enums.iter().find(|e| e.name == *id))?;
    let case = e.case(name)?;
    Some(format!("{}.{} = {}", id, case.name, case.value))
}

/// The document parsed with a placeholder name after the `.` that ends the
/// text before `offset`, since `Color.` alone does not parse while it is
/// being typed.
fn parse_after_dot(uri: &Url, text: &str, offset: usize) -> Option<ast::Module> {
    if !text.get(..offset)?.ends_with('.') {
        return None;
    }
    parse_source(uri.as_str(), &format!("{}_{}", &text[..offset], &text[offset..])).ok()
}

/// [`enum_case_of`] from the document alone, while the program does not
/// build: `Color.Red`, without its value.
fn enum_case_in(ast: &ast::Module, lhs: &ast::Expression, name: &str) -> Option<String> {
    let ast::Expression::SymbolRef { id, .. } = lhs else {
        return None;
    };
    let body = ast.declarations.iter().find_map(|d| match d {
        ast::Declaration::Struct(s) if s.name == *id => s.enumeration.as_ref(),
        _ => None,
    })?;
    body.cases.iter().any(|c| c.name == name).then(|| format!("{}.{}", id, name))
}

/// The cases of the enum whose name ends the text before `offset` with a
/// `.` (`Color.|`), as completion items.
fn enum_cases_before(ast: &ast::Module, text: &str, offset: usize) -> Option<Vec<CompletionItem>> {
    let before = text.get(..offset)?;
    let before = before.strip_suffix('.')?;
    let start = before.rfind(|c: char| !(c.is_ascii_alphanumeric() || c == '_')).map_or(0, |i| i + 1);
    let name = &before[start..];
    let body = ast.declarations.iter().find_map(|d| match d {
        ast::Declaration::Struct(s) if s.name == name => s.enumeration.as_ref(),
        _ => None,
    })?;
    Some(
        body.cases
            .iter()
            .map(|c| CompletionItem {
                label: c.name.clone(),
                kind: Some(CompletionItemKind::ENUM_MEMBER),
                detail: Some(format!("{}.{}", name, c.name)),
                ..Default::default()
            })
            .collect(),
    )
}

/// The struct `name`, as the document spells it: the document's own (which
/// linking may have given a mangled name), else the one named `name`.
fn find_sema_struct<'a>(module: &'a SemaModule, name: &str) -> Option<&'a StructDef> {
    module
        .structs
        .iter()
        .find(|s| s.loc.file == FileId(0) && demangle_name(&s.name) == name)
        .or_else(|| module.structs.iter().find(|s| s.name == name))
}

fn struct_member_type(st: &StructDef, name: &str) -> Option<String> {
    st.field_members.iter().find(|f| f.name == name).map(|f| f.ty.to_string())
}

fn is_this(expr: &ast::Expression) -> bool {
    matches!(expr, ast::Expression::MemberAccess { lhs, .. } if matches!(&**lhs, ast::Expression::SymbolRef { id, .. } if id.as_str() == "this"))
}

// ── Doc comments ──────────────────────────────────────────────────────────────

/// Separates a hover's signature from the doc comment after it.
const DOC_SEPARATOR: &str = "\n\n---\n\n";

/// `value` followed by `doc`, the Markdown of a declaration's doc comment.
fn with_doc(value: String, doc: Option<String>) -> String {
    match doc {
        Some(doc) if !doc.is_empty() => format!("{}{}{}", value, DOC_SEPARATOR, doc),
        _ => value,
    }
}

/// The doc comment of the top-level declaration `name`, from the first
/// program file declaring it (the document, then its imports, then the
/// runtime), as Markdown. The document's own declaration may carry a
/// mangled name, and is matched as written.
fn declaration_doc(program: &Program, name: &str) -> Option<String> {
    program.files.iter().enumerate().find_map(|(i, f)| {
        let decl = f.module.declarations.iter().find(|d| {
            !matches!(d, ast::Declaration::Extend(_)) && (d.name() == name || (i == 0 && demangle_name(d.name()) == name))
        })?;
        Some(pepper_parser::doc::doc_comment_of(&f.source, decl)?.to_markdown())
    })
}

/// The doc comment of the top-level declaration in `program.files[file]`
/// whose name token is at `name_span`, as Markdown.
fn declaration_doc_at(program: &Program, file: usize, name_span: Span) -> Option<String> {
    let f = program.files.get(file)?;
    let decl = f.module.declarations.iter().find(|d| d.name_span() == name_span)?;
    Some(pepper_parser::doc::doc_comment_of(&f.source, decl)?.to_markdown())
}

/// The doc comment of member `name` (a field or method) of the struct,
/// trait, or extension of `owner`, as Markdown. With no known owner, only a
/// member name that one type alone declares has a doc to show.
fn member_doc(program: &Program, owner: Option<&str>, name: &str) -> Option<String> {
    // The document's own type first: it may carry a mangled name, and
    // shadows another file's type of the same name.
    if owner.is_some() && let Some(doc) = member_doc_in(&program.files[..1], owner, name, demangle_name) {
        return Some(doc);
    }
    member_doc_in(&program.files, owner, name, |n| n)
}

/// [`member_doc`] over `files`, with each type's name spelled by `spell`.
fn member_doc_in(
    files: &[pepper_sema::ProgramFile],
    owner: Option<&str>,
    name: &str,
    spell: fn(&str) -> &str,
) -> Option<String> {
    // (owner, source, offset of the member's first token)
    let mut found: Vec<(&str, &str, usize)> = vec![];
    for f in files {
        for decl in &f.module.declarations {
            let (type_name, fields, methods): (&str, &[ast::VariableDecl], &[ast::FunctionDecl]) = match decl {
                ast::Declaration::Struct(s) => (&s.name, &s.fields, &s.methods),
                ast::Declaration::Trait(t) => (&t.name, &[], &t.methods),
                ast::Declaration::Extend(e) => (&e.target.name, &[], &e.methods),
                _ => continue,
            };
            if owner.is_some_and(|o| o != spell(type_name)) {
                continue;
            }
            let case = match decl {
                ast::Declaration::Struct(s) => {
                    s.enumeration.iter().flat_map(|e| &e.cases).find(|c| c.name == name).map(|c| c.span.start)
                }
                _ => None,
            };
            let field = fields.iter().find(|v| v.name == name).map(|v| v.span.start).or(case);
            let method = methods
                .iter()
                .find(|m| m.name == name)
                .map(|m| m.attributes.iter().map(|a| a.span.start).chain([m.span.start]).min().unwrap_or(m.span.start));
            if let Some(start) = field.or(method) {
                found.push((type_name, &f.source, start));
            }
        }
    }
    match found.as_slice() {
        [(_, source, start)] => Some(pepper_parser::doc::doc_comment_before(source, *start)?.to_markdown()),
        _ => None,
    }
}

/// The struct name of a rendered type: `Array<int>` and `int[]` are
/// `Array`; `unknown` is none.
fn type_base_name(ty: &str) -> Option<String> {
    let ty = ty.trim();
    if ty.ends_with("[]") {
        return Some("Array".to_string());
    }
    let base = ty.split('<').next().unwrap_or(ty).trim();
    let base = base.rsplit('.').next().unwrap_or(base);
    (!base.is_empty() && base != "unknown").then(|| base.to_string())
}

// ── Server ────────────────────────────────────────────────────────────────────

struct PepperLsp {
    client: Client,
    /// Open documents, keyed by URI string.
    docs: Mutex<HashMap<String, String>>,
    /// Show `[Implicit]` constructor conversions as inlay hints: the
    /// client's `inlayHints.implicitConversions` initialization option,
    /// on unless it says `false`.
    conversion_hints: AtomicBool,
}

/// The overload a call or function value in the document resolved to, when
/// the name at `offset` names an overload set: the chosen member's
/// declaration and how many other members the set has.
fn overload_at(sema: &SemaModule, offset: usize) -> Option<(&FunctionDef, usize)> {
    let (_, callee) = sema
        .call_targets
        .iter()
        .filter(|(loc, _)| loc.file == FileId(0) && loc.span.start <= offset && offset <= loc.span.end)
        .min_by_key(|(loc, _)| loc.span.end - loc.span.start)?;
    // A method is `Struct.member` (`Point.move$2`).
    if let Some((owner, method)) = callee.rsplit_once('.') {
        let st = sema.structs.iter().find(|s| s.ty.to_string() == owner)?;
        let function = st.method_members.iter().find(|m| m.name == method)?;
        let set = pepper_sema::passes::overloads::set_name(method);
        let others = st.method_members.iter().filter(|m| pepper_sema::passes::overloads::set_name(&m.name) == set).count() - 1;
        return Some((function, others));
    }
    // A generic member's call names its specialization (`f$2<int>`).
    let member = callee.split_once('<').map_or(callee.as_str(), |(base, _)| base);
    let function = sema.functions.iter().find(|f| f.name == member)?;
    let others = sema.overload_sets.values().find(|m| m.iter().any(|n| n == member)).map_or(0, |m| m.len() - 1);
    Some((function, others))
}

/// The hover for an overloaded call's chosen member: its signature, how many
/// other overloads its set has, and its doc comment.
fn overload_hover(program: &Program, function: &FunctionDef, others: usize) -> String {
    let name = demangle_name(&function.name);
    let more = match others {
        1 => " (+1 overload)".to_string(),
        n => format!(" (+{} overloads)", n),
    };
    let file = function.loc.file.0 as usize;
    // The member as its file declares it (a free function, or a method of a
    // struct or extension), parameter names included, and its doc comment.
    let declared = program.files.get(file).and_then(|f| {
        f.module.declarations.iter().find_map(|d| {
            let methods: &[ast::FunctionDecl] = match d {
                ast::Declaration::Function(g) if g.name_span == function.loc.span => {
                    return Some((function_signature(g), g.attributes.iter().map(|a| a.span.start).chain([g.span.start]).min()));
                }
                ast::Declaration::Struct(s) => &s.methods,
                ast::Declaration::Extend(e) => &e.methods,
                _ => return None,
            };
            let m = methods.iter().find(|m| m.name_span == function.loc.span)?;
            // A method's span starts after its name.
            Some((function_signature(m), m.attributes.iter().map(|a| a.span.start).chain([m.span.start, m.name_span.start]).min()))
        })
    });
    let signature = declared.as_ref().map(|(s, _)| s.clone()).unwrap_or_else(|| function.ty.to_string());
    let doc = declared.and_then(|(_, start)| {
        let source = &program.files.get(file)?.source;
        Some(pepper_parser::doc::doc_comment_before(source, start?)?.to_markdown())
    });
    with_doc(format!("`{}` — `{}`{}", name, signature, more), doc)
}

/// The implicit conversions of the document (`program.files[0]`), in
/// source order.
fn document_conversions(sema: &SemaModule) -> Vec<&Conversion> {
    let mut found: Vec<&Conversion> = sema.conversions.iter().filter(|c| c.at.file == FileId(0)).collect();
    found.sort_by_key(|c| (c.at.span.start, c.at.span.end));
    found
}

/// The innermost implicit conversion of the document covering `offset`.
fn conversion_at(sema: &SemaModule, offset: usize) -> Option<&Conversion> {
    document_conversions(sema)
        .into_iter()
        .filter(|c| c.at.span.start <= offset && offset < c.at.span.end)
        .min_by_key(|c| c.at.span.end - c.at.span.start)
}

/// The hover line for a conversion.
fn conversion_note(c: &Conversion) -> String {
    format!(
        "Converted to `{}` by its `[Implicit]` constructor from `{}`.",
        c.to.display(),
        c.from.display()
    )
}

/// The inlay hints around each converted value: `Path(` before and `)`
/// after, so the call the compiler inserts is visible.
fn conversion_hints(text: &str, sema: &SemaModule) -> Vec<InlayHint> {
    let hint = |offset: usize, label: String| InlayHint {
        position: byte_to_lsp_pos(text, offset),
        label: InlayHintLabel::String(label),
        kind: None,
        text_edits: None,
        tooltip: None,
        padding_left: None,
        padding_right: None,
        data: None,
    };
    document_conversions(sema)
        .into_iter()
        .filter(|c| c.at.span.end <= text.len())
        .flat_map(|c| {
            let mut open = hint(c.at.span.start, format!("{}(", c.to.display()));
            open.tooltip = Some(InlayHintTooltip::String(conversion_note(c)));
            [open, hint(c.at.span.end, ")".to_string())]
        })
        .collect()
}

/// The loaded, linked program rooted at an open document, which is
/// `files[0]`.
type Program = pepper_sema::program::Program;

/// Merge `program` into one sema model and run the sema passes. Build errors
/// in the document (`program[0]`) are reported; other files that fail to
/// build are skipped. Locations carry the file's index in `program`.
fn sema_model_of(program: &Program) -> Result<SemaModule, diag::Diagnostic> {
    let mut module = SemaModule { linked: true, extension_scopes: program.extension_scopes(), ..SemaModule::default() };
    // Indexed like the files, as the passes that read source text expect.
    for file in &program.files {
        module.sources.add(&file.name, &file.source);
    }
    for (i, file) in program.files.iter().enumerate().skip(1) {
        if let Ok(m) = pepper_sema::builder::build_file(&file.module, FileId(i as u32)) {
            module.merge(m);
        }
    }
    module.merge(pepper_sema::builder::build_file(&program.files[0].module, FileId(0))?);

    // Run the sema passes under a panic guard: an LSP must never crash on
    // a user file, so a panicking pass degrades to "no semantic info".
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut m = module;
        pepper_sema::apply_platform_filters(&mut m)?;
        pepper_sema::struct_body::apply(&mut m)?;
        pepper_sema::transform_pass(&mut m)?;
        Ok(m)
    }));
    match result {
        Ok(Ok(m)) => Ok(m),
        Ok(Err(e)) => Err(e),
        Err(_) => Err(diag::Diagnostic::error("semantic analysis panicked")),
    }
}

/// Each file of `program` as (name, text), indexed like its diagnostics'
/// file ids.
fn program_names(program: &Program) -> Vec<(&str, &str)> {
    program.files.iter().map(|f| (f.name.as_str(), f.source.as_str())).collect()
}

/// A program file's path as hovers show it: its folder and file name
/// (`geo/module.pep`), which name a module file and its module.
fn file_label(name: &str) -> String {
    let path = std::path::Path::new(name);
    let file = path.file_name().map_or(name.into(), |f| f.to_string_lossy());
    match path.parent().and_then(|p| p.file_name()) {
        Some(dir) => format!("{}/{}", dir.to_string_lossy(), file),
        None => file.into_owned(),
    }
}

/// `d` as an LSP diagnostic on the document (`program[0]`, file id 0), with
/// its notes as related information. A location in another file, or none,
/// lands at the top of the document with that file's name in the message.
fn lsp_diagnostic(d: &diag::Diagnostic, uri: &Url, program: &[(&str, &str)]) -> Diagnostic {
    let (range, message) = match d.loc {
        Some(loc) if loc.file.0 == 0 => (span_to_range(program[0].1, loc.span), d.message.clone()),
        Some(loc) => {
            let name = program.get(loc.file.0 as usize).map_or("another file", |f| f.0);
            (Range::default(), format!("{}: {}", name, d.message))
        }
        None => (Range::default(), d.message.clone()),
    };
    let message = demangle(&message).into_owned();
    let related: Vec<DiagnosticRelatedInformation> = d
        .notes
        .iter()
        .filter_map(|note| {
            let loc = note.loc?;
            let (name, text) = program.get(loc.file.0 as usize)?;
            let uri = if loc.file.0 == 0 { uri.clone() } else { Url::from_file_path(name).ok()? };
            Some(DiagnosticRelatedInformation {
                location: Location::new(uri, span_to_range(text, loc.span)),
                message: demangle(&note.message).into_owned(),
            })
        })
        .collect();
    let severity = match d.severity {
        diag::Severity::Error => DiagnosticSeverity::ERROR,
        diag::Severity::Warning => DiagnosticSeverity::WARNING,
        diag::Severity::Note => DiagnosticSeverity::INFORMATION,
    };
    let deprecated = d.code == Some(diag::DEPRECATED);
    Diagnostic {
        range,
        severity: Some(severity),
        code: d.code.map(|c| NumberOrString::String(c.to_string())),
        source: d.code.map(|_| "pepper".to_string()),
        message,
        related_information: (!related.is_empty()).then_some(related),
        tags: deprecated.then(|| vec![DiagnosticTag::DEPRECATED]),
        ..Default::default()
    }
}

/// Uses of deprecated declarations in the program's document
/// (`program.files[0]`): the top-level names the program's check finds, then
/// the fields and methods `sema` (its model, when the passes succeeded)
/// found.
fn deprecation_warnings(program: &Program, sema: Option<&SemaModule>) -> Vec<diag::Diagnostic> {
    let in_document = |d: &diag::Diagnostic| d.loc.is_some_and(|l| l.file.0 == 0);
    let mut warnings: Vec<diag::Diagnostic> = program.deprecation_warnings().into_iter().filter(in_document).collect();
    if let Some(module) = sema {
        warnings.extend(module.warnings.iter().filter(|d| in_document(d)).cloned());
    }
    warnings
}

/// Every warning in `text`, the document `program` is rooted at (when it
/// loaded): the parser's, then [`deprecation_warnings`].
fn document_warnings(text: &str, program: Option<&Program>) -> Vec<diag::Diagnostic> {
    let Ok(module) = pepper_parser::parser::parse_source_diag(text) else { return vec![] };
    let mut warnings = module.warnings;
    if let Some(program) = program {
        let sema = sema_model_of(program).ok();
        warnings.extend(deprecation_warnings(program, sema.as_ref()));
    }
    warnings
}

/// The diagnostics of `text` (the program's document) that may carry
/// fixes: its warnings, and `sema_error` (the program's semantic error) when
/// it is in the document and carries one, such as the `Copyable` skeleton
/// for a struct that `copy` cannot copy.
fn fixable_diagnostics(text: &str, program: Option<&Program>, sema_error: Option<&diag::Diagnostic>) -> Vec<diag::Diagnostic> {
    let mut diagnostics = document_warnings(text, program);
    if let Some(error) = sema_error
        && error.loc.is_some_and(|loc| loc.file == FileId(0))
        && !error.fixes.is_empty()
    {
        diagnostics.push(error.clone());
    }
    diagnostics
}

/// The quick fixes for `warnings` (and errors) in `text`, the document
/// `uri`, whose range overlaps `range`: one code action per suggested fix.
fn quick_fixes(uri: &Url, text: &str, warnings: &[diag::Diagnostic], range: Range) -> Vec<CodeActionOrCommand> {
    let overlaps = |r: &Range| r.start <= range.end && range.start <= r.end;
    let mut actions = vec![];
    for warning in warnings {
        let lsp = lsp_diagnostic(warning, uri, &[(uri.as_str(), text)]);
        if !overlaps(&lsp.range) {
            continue;
        }
        for fix in &warning.fixes {
            let edits = fix
                .edits
                .iter()
                .map(|e| TextEdit { range: span_to_range(text, e.loc.span), new_text: e.replacement.clone() })
                .collect();
            actions.push(CodeActionOrCommand::CodeAction(CodeAction {
                title: fix.message.clone(),
                kind: Some(CodeActionKind::QUICKFIX),
                diagnostics: Some(vec![lsp.clone()]),
                edit: Some(WorkspaceEdit { changes: Some(HashMap::from([(uri.clone(), edits)])), ..Default::default() }),
                is_preferred: Some(true),
                ..Default::default()
            }));
        }
    }
    actions
}

impl PepperLsp {
    fn new(client: Client) -> Self {
        Self { client, docs: Mutex::new(HashMap::new()), conversion_hints: AtomicBool::new(true) }
    }

    fn doc(&self, uri: &Url) -> Option<String> {
        self.docs.lock().unwrap().get(uri.as_str()).cloned()
    }

    /// The file path behind a document URI.
    fn doc_path(&self, uri: &Url) -> Option<PathBuf> {
        uri.to_file_path().ok()
    }

    /// Every file of the program rooted at the open document `uri`, loaded
    /// and linked as the driver does: the document itself (possibly unsaved)
    /// first, then the files its imports reach, then the runtime prelude.
    /// Unreadable or unparseable imported files are skipped; a parse error in
    /// the document is returned.
    fn program(&self, uri: &Url) -> Result<Program, String> {
        let text = self.doc(uri).ok_or_else(|| "document not found".to_string())?;
        let root_path = self.doc_path(uri).ok_or_else(|| "not a file uri".to_string())?;
        let root = pepper_sema::program::Root { name: uri.to_string(), source: text, path: root_path };
        let setup = pepper_sema::program::Setup { mode: pepper_sema::program::Mode::Lenient, ..Default::default() };
        pepper_sema::program::load_program(root, &setup)
    }

    /// Import errors in the program's document (`program.files[0]`),
    /// references to symbols another file did not `export` or this file did
    /// not import, and private names it shares with other files.
    fn visibility_diagnostics(program: &Program, uri: &Url) -> Vec<Diagnostic> {
        let names = program_names(program);
        // The editor does not know the compile's `-I` directories, so an
        // import it cannot find may still resolve for the compiler.
        let mut diags: Vec<Diagnostic> = program
            .errors
            .iter()
            .filter(|e| e.file == 0)
            .map(|e| {
                let mut d = lsp_diagnostic(&e.to_diagnostic(), uri, &names);
                if e.unresolved {
                    d.severity = Some(DiagnosticSeverity::WARNING);
                }
                d
            })
            .collect();
        let files = program.source_files();
        // Same panic guard as the sema passes.
        let Ok(errors) = std::panic::catch_unwind(|| pepper_sema::check_visibility(&files)) else { return diags };
        // A reference that failed to link already has its diagnostic.
        let linked_errors: HashSet<usize> =
            program.errors.iter().filter(|e| e.file == 0).map(|e| e.span.start).collect();
        diags.extend(
            errors
                .iter()
                .filter(|e| e.file == 0 && !linked_errors.contains(&e.span.start))
                .map(|e| lsp_diagnostic(&e.to_diagnostic(&files), uri, &names)),
        );
        diags
    }

    /// Publish diagnostics for `uri`: parse errors (precise) + sema errors.
    async fn publish_diagnostics(&self, uri: &Url) {
        let mut diags = vec![];
        let Some(text) = self.doc(uri) else { return };
        // A parse error, or one found after parsing (a late import, `T*`
        // outside an extern).
        let parsed = pepper_parser::parser::parse_source_diag(&text);
        match &parsed {
            Err(d) => diags.push(lsp_diagnostic(d, uri, &[(uri.as_str(), &text)])),
            // Warnings (deprecated syntax) come with quick fixes; see `quick_fixes`.
            Ok(module) => diags.extend(module.warnings.iter().map(|w| lsp_diagnostic(w, uri, &[(uri.as_str(), &text)]))),
        }
        if parsed.is_ok() && let Ok(program) = self.program(uri) {
            // Read and parse the program once for both the sema and
            // visibility checks.
            let names = program_names(&program);
            let sema = sema_model_of(&program);
            if let Err(d) = &sema {
                diags.push(lsp_diagnostic(d, uri, &names));
            }
            // Uses of `[Deprecated]` declarations, with their quick fixes.
            let deprecated = deprecation_warnings(&program, sema.as_ref().ok());
            diags.extend(deprecated.iter().map(|w| lsp_diagnostic(w, uri, &names)));
            diags.extend(Self::visibility_diagnostics(&program, uri));
        }
        self.client.publish_diagnostics(uri.clone(), diags, None).await;
    }

    /// Hover at `offset` in document `uri`.
    fn hover(&self, uri: &Url, offset: usize) -> Option<Hover> {
        let text = self.doc(uri)?;
        Self::hover_at(uri, &text, self.program(uri).ok().as_ref(), offset)
    }

    /// Hover at `offset` in `text`, the document `uri`, which is
    /// `program.files[0]` when its program loaded. A value an `[Implicit]`
    /// constructor converts says so below what the hover shows for it.
    fn hover_at(uri: &Url, text: &str, program: Option<&Program>, offset: usize) -> Option<Hover> {
        let sema = program.and_then(|p| sema_model_of(p).ok());
        let hover = Self::hover_expression(uri, text, program, sema.as_ref(), offset);
        let Some(conversion) = sema.as_ref().and_then(|m| conversion_at(m, offset)) else {
            return hover;
        };
        let note = conversion_note(conversion);
        let value = match hover.map(|h| h.contents) {
            Some(HoverContents::Markup(m)) => format!("{}\n\n---\n\n{}", m.value, note),
            _ => note,
        };
        Some(Hover { contents: HoverContents::Markup(MarkupContent { kind: MarkupKind::Markdown, value }), range: None })
    }

    /// What hover shows for the expression or type at `offset`.
    fn hover_expression(uri: &Url, text: &str, program: Option<&Program>, sema: Option<&SemaModule>, offset: usize) -> Option<Hover> {
        let ast = parse_source(uri.as_str(), text).ok()?;
        // Private names are mangled in the linked program; hovers spell them
        // as written. Only the signature before a doc comment is rewritten,
        // and only with the program's own namespaces.
        let namespaces: Vec<&str> = program.map(|p| p.files.iter().map(|f| f.namespace.as_str()).collect()).unwrap_or_default();
        let md = |content: String| {
            let (head, doc) = content.split_once(DOC_SEPARATOR).map_or((content.as_str(), None), |(h, d)| (h, Some(d)));
            let mut value = demangle_known(head, &namespaces).into_owned();
            if let Some(doc) = doc {
                value.push_str(DOC_SEPARATOR);
                value.push_str(doc);
            }
            HoverContents::Markup(MarkupContent { kind: MarkupKind::Markdown, value })
        };
        let imported = |(spelled, target): (String, imports::Target)| {
            let program = program?;
            let value = match target {
                imports::Target::Declaration { file, symbol } if file == 0 => {
                    with_doc(format!("`{}` — `{}`", spelled, symbol.ty), declaration_doc_at(program, file, symbol.name_span))
                }
                imports::Target::Declaration { file, symbol } => with_doc(
                    format!("`{}` — `{}`\n\nfrom `{}`", spelled, symbol.ty, file_label(&program.files[file].name)),
                    declaration_doc_at(program, file, symbol.name_span),
                ),
                imports::Target::File(file) => format!("`{}` — `{}`", spelled, file_label(&program.files[file].name)),
            };
            Some(Hover { contents: md(value), range: None })
        };
        if let Some(program) = program
            && let Some(found) =
                imports::in_imports(program, &ast, offset).or_else(|| imports::in_type(program, &ast, offset))
        {
            return imported(found);
        }
        // A name that resolved to one overload of a set shows that member.
        if let Some(program) = program
            && let Some((function, others)) = sema.and_then(|m| overload_at(m, offset))
        {
            return Some(Hover { contents: md(overload_hover(program, function, others)), range: None });
        }
        let expr = find_expr(&ast, offset)?;

        let Some((body, enclosing_struct)) = body_at(&ast, offset) else {
            return None;
        };
        let locals: Vec<Symbol> = locals_at(body, offset);
        let globals = collect_globals(&ast);
        let struct_members: Vec<Symbol> = enclosing_struct.map(collect_struct_members).unwrap_or_default();
        let is_local = |id: &str| locals.iter().chain(&struct_members).chain(&globals).any(|s| s.name == id);
        if let Some(program) = program
            && let Some(found) = imports::in_expression(program, &ast, expr, is_local)
        {
            return imported(found);
        }
        // Docs of a name that is not a local, parameter, or member.
        let global_doc = |id: &str| {
            let local = locals.iter().chain(&struct_members).any(|s| s.name == id);
            if local { None } else { program.and_then(|p| declaration_doc(p, id)) }
        };
        // Docs of member `name` of `lhs`: its type when the hover can tell
        // (`this`, a typed variable, a type name for a static call).
        let member_docs = |lhs: &ast::Expression, name: &str| {
            let program = program?;
            let owner = match lhs {
                ast::Expression::SymbolRef { id, .. } if id == "this" => enclosing_struct.map(|s| s.name.clone()),
                ast::Expression::SymbolRef { id, .. } => {
                    match locals.iter().rev().chain(&struct_members).chain(&globals).find(|s| s.name == *id) {
                        Some(symbol) => type_base_name(&symbol.ty),
                        None => Some(id.clone()),
                    }
                }
                ast::Expression::FunctionCall { function, .. } => match &**function {
                    ast::Expression::SymbolRef { id, .. } => Some(id.clone()),
                    ast::Expression::TypeLiteral(t) => Some(t.name.clone()),
                    _ => None,
                },
                _ => None,
            };
            member_doc(program, owner.as_deref(), name)
        };

        match expr {
            ast::Expression::Literal { value, .. } => {
                let ty = match value {
                    ast::Literal::String(_) => "String",
                    ast::Literal::Integer(_) => "int",
                    ast::Literal::Float(_) => "float",
                    ast::Literal::Bool(_) => "bool",
                    ast::Literal::Char(_) => "byte",
                    ast::Literal::Null => "__null",
                };
                Some(Hover { contents: md(format!("`{}` — `{}`", value, ty)), range: None })
            }
            ast::Expression::SymbolRef { id, .. } => {
                let rendered = locals.iter().find(|s| s.name == *id)
                    .or_else(|| struct_members.iter().find(|s| s.name == *id))
                    .or_else(|| globals.iter().find(|s| s.name == *id))
                    .map(|s| s.ty.clone())
                    .or_else(|| {
                        // Cross-file: look up in the sema model.
                        sema.and_then(|m| {
                            m.functions.iter().find(|f| f.name == *id).map(|f| f.ty.to_string())
                                .or_else(|| m.structs.iter().find(|s| s.name == *id).map(|s| format!("struct {}", s.ty.to_string())))
                                .or_else(|| m.enums.iter().find(|e| e.name == *id).map(|e| format!("enum {}", demangle_name(&e.name))))
                                .or_else(|| m.traits.iter().find(|t| t.name == *id).map(|_| "trait".to_string()))
                                .or_else(|| m.externs.iter().find(|e| e.name == *id).map(|_| "extern function".to_string()))
                        })
                    })
                    .unwrap_or_else(|| "unknown".to_string());
                Some(Hover { contents: md(with_doc(format!("`{}` — `{}`", id, rendered), global_doc(id))), range: None })
            }
            ast::Expression::MemberAccess { lhs, name, .. } => {
                let rendered = if is_this(expr) {
                    struct_members.iter().find(|s| s.name == *name).map(|s| s.ty.clone())
                        .or_else(|| {
                            sema
                                .and_then(|m| enclosing_struct.and_then(|s| find_sema_struct(m, &s.name)))
                                .and_then(|st| struct_member_type(st, name))
                        })
                        .unwrap_or_else(|| "unknown".to_string())
                } else if let Some(case) = sema.and_then(|m| enum_case_of(m, lhs, name)).or_else(|| enum_case_in(&ast, lhs, name)) {
                    case
                } else {
                    sema
                        .and_then(|m| m.structs.iter().find_map(|st| struct_member_type(st, name)))
                        .unwrap_or_else(|| "unknown".to_string())
                };
                Some(Hover { contents: md(with_doc(format!("`.`{}` — `{}`", name, rendered), member_docs(lhs, name))), range: None })
            }
            ast::Expression::FunctionCall { function, .. } => match &**function {
                ast::Expression::SymbolRef { id, .. } => {
                    let rendered = globals.iter().find(|s| s.name == *id).map(|s| s.ty.clone())
                        .or_else(|| sema.and_then(|m| m.functions.iter().find(|f| f.name == *id).map(|f| f.ty.to_string())))
                        .unwrap_or_else(|| "unknown".to_string());
                    Some(Hover { contents: md(with_doc(format!("`{}` — `{}`", id, rendered), global_doc(id))), range: None })
                }
                ast::Expression::MemberAccess { lhs, name, .. } => {
                    let rendered = sema
                        .and_then(|m| m.structs.iter().find_map(|st| struct_member_type(st, name)))
                        .unwrap_or_else(|| "unknown".to_string());
                    Some(Hover { contents: md(with_doc(format!(".`{}` — `{}`", name, rendered), member_docs(lhs, name))), range: None })
                }
                _ => None,
            },
            _ => None,
        }
    }

    /// Go-to-definition at `offset`.
    fn definition(&self, uri: &Url, offset: usize) -> Option<Vec<Location>> {
        let text = self.doc(uri)?;
        Self::definition_at(uri, &text, self.program(uri).ok().as_ref(), offset)
    }

    /// Go-to-definition at `offset` in `text`, the document `uri`, which is
    /// `program.files[0]` when its program loaded.
    fn definition_at(uri: &Url, text: &str, program: Option<&Program>, offset: usize) -> Option<Vec<Location>> {
        let ast = parse_source(uri.as_str(), text).ok()?;
        let imported = |(_, target): (String, imports::Target)| {
            let program = program?;
            let (file, span) = match target {
                imports::Target::Declaration { file, symbol } => (file, symbol.name_span),
                imports::Target::File(file) => (file, Span::none()),
            };
            let f = &program.files[file];
            let target_uri = if file == 0 { uri.clone() } else { Url::from_file_path(&f.name).ok()? };
            Some(vec![Location::new(target_uri, span_to_range(&f.source, span))])
        };
        if let Some(program) = program
            && let Some(found) =
                imports::in_imports(program, &ast, offset).or_else(|| imports::in_type(program, &ast, offset))
        {
            return imported(found);
        }
        // A name that resolved to one overload of a set goes to that member.
        if let Some(program) = program
            && let Ok(sema) = sema_model_of(program)
            && let Some((function, _)) = overload_at(&sema, offset)
        {
            let file = function.loc.file.0 as usize;
            let f = program.files.get(file)?;
            let target_uri = if file == 0 { uri.clone() } else { Url::from_file_path(&f.name).ok()? };
            return Some(vec![Location::new(target_uri, span_to_range(&f.source, function.loc.span))]);
        }
        let expr = find_expr(&ast, offset)?;

        let Some((body, enclosing_struct)) = body_at(&ast, offset) else {
            return None;
        };
        let locals: Vec<Symbol> = locals_at(body, offset);
        let globals = collect_globals(&ast);
        let struct_members: Vec<Symbol> = enclosing_struct.map(collect_struct_members).unwrap_or_default();
        let is_local = |id: &str| locals.iter().chain(&struct_members).chain(&globals).any(|s| s.name == id);
        if let Some(program) = program
            && let Some(found) = imports::in_expression(program, &ast, expr, is_local)
        {
            return imported(found);
        }

        let target_span = match expr {
            ast::Expression::SymbolRef { id, .. } => locals.iter().find(|s| s.name == *id)
                .or_else(|| struct_members.iter().find(|s| s.name == *id))
                .or_else(|| globals.iter().find(|s| s.name == *id))
                .map(|s| s.name_span),
            ast::Expression::MemberAccess { name, .. } => {
                if is_this(expr) {
                    enclosing_struct?.fields.iter().find(|f| f.name == *name).map(|f| f.name_span)
                } else {
                    None
                }
            }
            _ => None,
        }?;

        Some(vec![Location::new(uri.clone(), span_to_range(text, target_span))])
    }

    /// Document symbols for `uri`.
    fn document_symbols(&self, uri: &Url) -> Option<Vec<DocumentSymbol>> {
        let text = self.doc(uri)?;
        let ast = parse_source(uri.as_str(), &text).ok()?;
        let mut out = vec![];
        for decl in &ast.declarations {
            match decl {
                ast::Declaration::Function(f) => {
                    out.push(new_symbol(
                        f.name.clone(),
                        function_signature(f),
                        SymbolKind::FUNCTION,
                        span_to_range(&text, f.span),
                        span_to_range(&text, f.name_span),
                        None,
                    ));
                }
                ast::Declaration::Struct(s) => {
                    let mut children = vec![];
                    for case in s.enumeration.iter().flat_map(|e| &e.cases) {
                        children.push(new_symbol(
                            case.name.clone(),
                            format!("{}.{}", s.name, case.name),
                            SymbolKind::ENUM_MEMBER,
                            span_to_range(&text, case.span),
                            span_to_range(&text, case.name_span),
                            None,
                        ));
                    }
                    for field in &s.fields {
                        children.push(new_symbol(
                            field.name.clone(),
                            type_string(&field.type_name),
                            SymbolKind::FIELD,
                            span_to_range(&text, field.span),
                            span_to_range(&text, field.name_span),
                            None,
                        ));
                    }
                    for m in &s.methods {
                        children.push(new_symbol(
                            m.name.clone(),
                            function_signature(m),
                            SymbolKind::METHOD,
                            span_to_range(&text, m.span),
                            span_to_range(&text, m.name_span),
                            None,
                        ));
                    }
                    let (detail, kind) =
                        if s.enumeration.is_some() { ("enum", SymbolKind::ENUM) } else { ("struct", SymbolKind::STRUCT) };
                    out.push(new_symbol(
                        s.name.clone(),
                        detail.to_string(),
                        kind,
                        span_to_range(&text, s.span),
                        span_to_range(&text, s.name_span),
                        if children.is_empty() { None } else { Some(children) },
                    ));
                }
                ast::Declaration::Variable(v) => out.push(new_symbol(
                    v.name.clone(),
                    variable_type(v),
                    SymbolKind::VARIABLE,
                    span_to_range(&text, v.span),
                    span_to_range(&text, v.name_span),
                    None,
                )),
                ast::Declaration::Trait(t) => out.push(new_symbol(
                    t.name.clone(),
                    "trait".to_string(),
                    SymbolKind::INTERFACE,
                    span_to_range(&text, t.span),
                    span_to_range(&text, t.name_span),
                    None,
                )),
                ast::Declaration::Extend(e) => out.push(new_symbol(
                    e.target.to_string(),
                    "extend".to_string(),
                    SymbolKind::NAMESPACE,
                    span_to_range(&text, e.span),
                    span_to_range(&text, e.target.span),
                    None,
                )),
                ast::Declaration::TypeAlias(t) => out.push(new_symbol(
                    t.name.clone(),
                    "type".to_string(),
                    SymbolKind::STRUCT,
                    span_to_range(&text, t.span),
                    span_to_range(&text, t.name_span),
                    None,
                )),
            }
        }
        Some(out)
    }

    /// Completion at `offset`: keywords plus local/struct/global symbols.
    fn completion(&self, uri: &Url, offset: usize) -> Vec<CompletionItem> {
        let mut items = vec![];
        for kw in KEYWORDS {
            items.push(CompletionItem { label: kw.to_string(), kind: Some(CompletionItemKind::KEYWORD), ..Default::default() });
        }
        if let Some(text) = self.doc(uri)
            && let Ok(ast) = parse_source(uri.as_str(), &text).or_else(|e| parse_after_dot(uri, &text, offset).ok_or(e))
        {
            let scope = body_at(&ast, offset);
            let locals: Vec<Symbol> = scope.as_ref().map(|(b, _)| locals_at(b, offset)).unwrap_or_default();
            let globals = collect_globals(&ast);
            let struct_members: Vec<Symbol> = scope
                .as_ref()
                .and_then(|(_, s)| *s)
                .map(collect_struct_members)
                .unwrap_or_default();

            // After `Enum.`, the enum's cases alone.
            if let Some(cases) = enum_cases_before(&ast, &text, offset) {
                return cases;
            }
            for s in locals.iter().chain(struct_members.iter()).chain(globals.iter()) {
                items.push(CompletionItem {
                    label: s.name.clone(),
                    kind: Some(if s.ty.contains('(') {
                        CompletionItemKind::FUNCTION
                    } else if s.ty.starts_with("enum") {
                        CompletionItemKind::ENUM
                    } else if s.ty.starts_with("struct") {
                        CompletionItemKind::STRUCT
                    } else {
                        CompletionItemKind::VARIABLE
                    }),
                    detail: Some(s.ty.clone()),
                    ..Default::default()
                });
            }
        }
        items
    }
}

#[async_trait]
impl LanguageServer for PepperLsp {
    async fn initialize(&self, params: InitializeParams) -> LspResult<InitializeResult> {
        let hints = params
            .initialization_options
            .as_ref()
            .and_then(|o| o.pointer("/inlayHints/implicitConversions"))
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        self.conversion_hints.store(hints, Ordering::Relaxed);
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                inlay_hint_provider: Some(OneOf::Left(true)),
                hover_provider: Some(HoverProviderCapability::Simple(true)),
                completion_provider: Some(CompletionOptions {
                    trigger_characters: Some(vec![".".to_string(), "(".to_string()]),
                    ..Default::default()
                }),
                definition_provider: Some(OneOf::Left(true)),
                document_symbol_provider: Some(OneOf::Left(true)),
                code_action_provider: Some(CodeActionProviderCapability::Simple(true)),
                text_document_sync: Some(TextDocumentSyncCapability::Kind(TextDocumentSyncKind::FULL)),
                ..Default::default()
            },
            server_info: Some(ServerInfo {
                name: "pepper-lsp".to_string(),
                version: Some(env!("CARGO_PKG_VERSION").to_string()),
            }),
        })
    }

    async fn shutdown(&self) -> LspResult<()> {
        Ok(())
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let uri = params.text_document.uri.clone();
        self.docs.lock().unwrap().insert(uri.as_str().to_string(), params.text_document.text);
        self.publish_diagnostics(&uri).await;
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        let uri = params.text_document.uri.clone();
        if let Some(change) = params.content_changes.into_iter().next() {
            self.docs.lock().unwrap().insert(uri.as_str().to_string(), change.text);
        }
        self.publish_diagnostics(&uri).await;
    }

    async fn did_close(&self, params: DidCloseTextDocumentParams) {
        let uri = params.text_document.uri.clone();
        self.docs.lock().unwrap().remove(uri.as_str());
        self.client.publish_diagnostics(uri, vec![], None).await;
    }

    async fn inlay_hint(&self, params: InlayHintParams) -> LspResult<Option<Vec<InlayHint>>> {
        if !self.conversion_hints.load(Ordering::Relaxed) {
            return Ok(None);
        }
        let uri = params.text_document.uri;
        let Some(text) = self.doc(&uri) else {
            return Ok(None);
        };
        let Some(sema) = self.program(&uri).ok().and_then(|p| sema_model_of(&p).ok()) else {
            return Ok(None);
        };
        let range = params.range;
        let hints = conversion_hints(&text, &sema)
            .into_iter()
            .filter(|h| h.position >= range.start && h.position <= range.end)
            .collect();
        Ok(Some(hints))
    }

    async fn hover(&self, params: HoverParams) -> LspResult<Option<Hover>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        if let Some(text) = self.doc(&uri) {
            let offset = line_col_to_byte(&text, pos.line, pos.character);
            return Ok(self.hover(&uri, offset));
        }
        Ok(None)
    }

    async fn completion(&self, params: CompletionParams) -> LspResult<Option<CompletionResponse>> {
        let uri = params.text_document_position.text_document.uri;
        let pos = params.text_document_position.position;
        if let Some(text) = self.doc(&uri) {
            let offset = line_col_to_byte(&text, pos.line, pos.character);
            return Ok(Some(CompletionResponse::Array(self.completion(&uri, offset))));
        }
        Ok(None)
    }

    async fn goto_definition(&self, params: GotoDefinitionParams) -> LspResult<Option<GotoDefinitionResponse>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        if let Some(text) = self.doc(&uri) {
            let offset = line_col_to_byte(&text, pos.line, pos.character);
            return Ok(self.definition(&uri, offset).map(Into::into));
        }
        Ok(None)
    }

    async fn code_action(&self, params: CodeActionParams) -> LspResult<Option<CodeActionResponse>> {
        let uri = params.text_document.uri;
        let Some(text) = self.doc(&uri) else { return Ok(None) };
        let program = self.program(&uri).ok();
        // One semantic analysis serves both kinds of fix: those a
        // diagnostic carries (a `Copyable` skeleton) and the missing arms of
        // a `match`.
        let sema_error = program.as_ref().and_then(|p| sema_model_of(p).err());
        let diagnostics = fixable_diagnostics(&text, program.as_ref(), sema_error.as_ref());
        let mut actions = quick_fixes(&uri, &text, &diagnostics, params.range);
        if let (Some(program), Some(error)) = (&program, &sema_error) {
            actions.extend(missing_arms_fix(&uri, &text, program, error, params.range));
        }
        Ok((!actions.is_empty()).then_some(actions))
    }

    async fn document_symbol(&self, params: DocumentSymbolParams) -> LspResult<Option<DocumentSymbolResponse>> {
        let uri = params.text_document.uri;
        Ok(self.document_symbols(&uri).map(DocumentSymbolResponse::Nested))
    }
}

#[tokio::main]
async fn main() {
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();
    let (service, socket) = LspService::new(PepperLsp::new);
    Server::new(stdin, stdout, socket).serve(service).await;
}
