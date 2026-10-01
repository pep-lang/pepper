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
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::SystemTime;
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
    "extend", "export", "shared", "enum", "match", "is",
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

/// Generic parameters as written, constraints and defaults included:
/// `<T: Shape & Named = Square>`, or nothing without any.
fn generics_string(params: &[ast::GenericParam]) -> String {
    if params.is_empty() {
        return String::new();
    }
    let params: Vec<String> = params
        .iter()
        .map(|p| {
            let mut out = p.name.clone();
            if !p.bounds.is_empty() {
                out += ": ";
                out += &p.bounds.iter().map(type_string).collect::<Vec<_>>().join(" & ");
            }
            if let Some(d) = &p.default {
                out += if p.bounds.is_empty() { "=" } else { " = " };
                out += &type_string(d);
            }
            out
        })
        .collect();
    format!("<{}>", params.join(", "))
}

fn function_signature(f: &ast::FunctionDecl) -> String {
    let params = f
        .parameters
        .iter()
        .map(|p| format!("{}: {}", p.name, type_string(&p.type_name)))
        .collect::<Vec<_>>()
        .join(", ");
    format!("{}{}({}): {}", f.name, generics_string(&f.generic_params), params, type_string(&f.return_type))
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
    for ctor in &s.constructors {
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
                ty: format!(
                    "{} {}{}",
                    if s.enumeration.is_some() { "enum" } else { "struct" },
                    s.name,
                    generics_string(&s.generic_params)
                ),
            }),
            ast::Declaration::Trait(t) => out.push(Symbol {
                name: t.name.clone(),
                name_span: t.name_span,
                ty: format!("trait {}{}", t.name, generics_string(&t.generic_params)),
            }),
            ast::Declaration::Extend(_) => {}
            ast::Declaration::TypeAlias(t) => {
                let ty = format!("type {}{} = {}", t.name, generics_string(&t.generic_params), t.target);
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

/// The named bindings of a destructuring pattern, nested ones included.
fn push_pattern(bindings: &[ast::DestructureBinding], out: &mut Vec<Symbol>) {
    for b in bindings.iter().flat_map(|b| b.leaves()).filter(|b| b.name != "_") {
        let ty = if b.type_name.name == "__auto" { String::new() } else { b.type_name.to_string() };
        out.push(Symbol { name: b.name.clone(), name_span: b.name_span, ty });
    }
}

/// The names `if (x is P(a))` or `while (x is P(a))` binds in its block.
fn push_is_bindings(condition: &ast::Expression, out: &mut Vec<Symbol>) {
    if let ast::Expression::Is { pattern, .. } = condition {
        for (name, span) in pattern.bound_names() {
            out.push(Symbol { name, name_span: span, ty: String::new() });
        }
    }
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
                ast::Statement::Destructure(d) => push_pattern(&d.bindings, out),
                _ => {}
            }
        } else if s.start <= offset && offset < s.end {
            match stmt {
                ast::Statement::Block(b) => collect_locals_upto(b, offset, out),
                ast::Statement::Branch(br) => {
                    if br.if_block.span.start <= offset && offset < br.if_block.span.end {
                        push_is_bindings(&br.condition, out);
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
                        push_is_bindings(&w.condition, out);
                        collect_locals_upto(&w.block, offset, out);
                    }
                }
                ast::Statement::For(f) => {
                    if f.block.span.start <= offset && offset < f.block.span.end {
                        if f.pattern.is_empty() {
                            out.push(Symbol {
                                name: f.binding.name.clone(),
                                name_span: f.binding.name_span,
                                ty: variable_type(&f.binding),
                            });
                        } else {
                            push_pattern(&f.pattern, out);
                        }
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
                if let Some(c) = s.constructors.iter().find(|c| c.span.start <= offset && offset < c.span.end)
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

/// Where `expr`'s text starts. The parser starts a binary expression's
/// span at its operator (where its errors point), after its left operand,
/// and an expression that starts with one (a ternary's condition, an `is`
/// test's value, a member's, index's or call's owner, a cast's value, a
/// postfix operator's operand) inherits that.
fn expr_start(expr: &ast::Expression) -> usize {
    let first = match expr {
        ast::Expression::Binary { lhs, .. }
        | ast::Expression::Index { lhs, .. }
        | ast::Expression::MemberAccess { lhs, .. } => lhs,
        ast::Expression::Ternary { condition, .. } => condition,
        ast::Expression::Is { value, .. } => value,
        ast::Expression::Cast { expr: value, .. } => value,
        ast::Expression::FunctionCall { function, .. } => function,
        ast::Expression::Unary { operand, prefix: false, .. } => operand,
        _ => return expr.span().start,
    };
    expr.span().start.min(expr_start(first))
}

/// The innermost expression containing `offset`.
fn expr_at<'a>(expr: &'a ast::Expression, offset: usize) -> Option<&'a ast::Expression> {
    let s = Span { start: expr_start(expr), end: expr.span().end };
    if !(s.start <= offset && offset < s.end) {
        return None;
    }
    match expr {
        ast::Expression::Binary { lhs, rhs, .. } => expr_at(lhs, offset).or_else(|| expr_at(rhs, offset)),
        ast::Expression::Unary { operand, .. } => expr_at(operand, offset),
        ast::Expression::Is { value, .. } => expr_at(value, offset).or(Some(expr)),
        ast::Expression::Cast { expr: value, .. } => expr_at(value, offset).or(Some(expr)),
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
    // A generic enum's `match` names its specialization (`Tree<int>`).
    let base_name = enum_name.split('<').next()?;
    let ast = parse_source(uri.as_str(), text).ok()?;
    let found = find_match(&ast, loc.span.start)?;
    let cases = program.files.iter().find_map(|f| {
        f.module.declarations.iter().find_map(|d| match d {
            ast::Declaration::Struct(s) if s.name == base_name || demangle_name(&s.name) == base_name => s.enumeration.as_ref(),
            _ => None,
        })
    })?;
    let handled: Vec<&str> = found.arms.iter().flat_map(|a| &a.patterns).map(|p| p.case.as_str()).collect();
    // A case that carries values gets a binding for each, named as declared.
    let missing: Vec<String> = cases
        .cases
        .iter()
        .filter(|c| !handled.contains(&c.name.as_str()))
        .map(|c| match &c.payload {
            Some(values) => format!("{}({})", c.name, values.iter().map(|v| v.name.as_str()).collect::<Vec<_>>().join(", ")),
            None => c.name.clone(),
        })
        .collect();
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
                .chain(s.constructors.iter().filter_map(|c| c.body.as_ref()))
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
/// of its cases: `Color.Red = 0`, or `Doc.Text(text: String)` for a case
/// that carries values.
fn enum_case_of(module: &SemaModule, lhs: &ast::Expression, name: &str) -> Option<String> {
    let ast::Expression::SymbolRef { id, .. } = lhs else {
        return None;
    };
    if let Some(st) = find_sema_struct(module, id)
        && let Some(cases) = &st.enum_cases
    {
        let case = cases.iter().find(|c| c.name == name)?;
        let values: Vec<String> = case
            .payload
            .iter()
            .map(|(value, _)| {
                let field = pepper_sema::model::payload_field(&case.name, value);
                let ty = st.field_members.iter().find(|f| f.name == field).map(|f| f.ty.display()).unwrap_or_default();
                format!("{}: {}", value, ty)
            })
            .collect();
        return Some(if values.is_empty() {
            format!("{}.{}", id, case.name)
        } else {
            format!("{}.{}({})", id, case.name, values.join(", "))
        });
    }
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
    let case = body.cases.iter().find(|c| c.name == name)?;
    Some(match &case.payload {
        Some(values) => format!("{}.{}({})", id, name, values.iter().map(|v| format!("{}: {}", v.name, v.type_name)).collect::<Vec<_>>().join(", ")),
        None => format!("{}.{}", id, name),
    })
}

/// The signature of an enum method named `name` (`name(): String`), as its
/// caller writes it: without the value it is called on.
fn enum_method_signature(module: &SemaModule, name: &str) -> Option<String> {
    let f = module.functions.iter().find(|f| pepper_sema::enums::method_of(&f.name).is_some_and(|(_, m)| m == name))?;
    let parameters: Vec<String> =
        f.parameters.iter().filter(|p| p.name != "this").map(|p| format!("{}: {}", p.name, p.ty)).collect();
    let is_static = f.parameters.first().is_none_or(|p| p.name != "this");
    Some(format!("{}{}({}): {}", if is_static { "static " } else { "" }, name, parameters.join(", "), f.ty))
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
    let methods = ast.declarations.iter().find_map(|d| match d {
        ast::Declaration::Struct(s) if s.name == name => Some(&s.methods),
        _ => None,
    })?;
    let cases = body.cases.iter().map(|c| CompletionItem {
        label: c.name.clone(),
        kind: Some(CompletionItemKind::ENUM_MEMBER),
        detail: Some(match &c.payload {
            Some(values) => format!("{}.{}({})", name, c.name, values.iter().map(|v| format!("{}: {}", v.name, v.type_name)).collect::<Vec<_>>().join(", ")),
            None => format!("{}.{}", name, c.name),
        }),
        ..Default::default()
    });
    // Its static methods, and `from_value` when its cases are integers.
    let is_value_enum = body.cases.iter().all(|c| c.payload.is_none());
    let statics = methods
        .iter()
        .filter(|m| m.is_static)
        .map(|m| (m.name.clone(), m.to_string()))
        .chain(is_value_enum.then(|| ("from_value".to_string(), format!("static from_value(value): Result<{}>", name))))
        .map(|(label, detail)| CompletionItem {
            label,
            kind: Some(CompletionItemKind::METHOD),
            detail: Some(detail),
            ..Default::default()
        });
    Some(cases.chain(statics).collect())
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
    /// The latest analysis of each open document, keyed by URI string.
    analyses: Mutex<HashMap<String, Arc<Analysis>>>,
    /// The client can watch files for the server (`workspace/
    /// didChangeWatchedFiles` with dynamic registration).
    watches_files: AtomicBool,
}

/// One version of a document, analyzed: the program rooted at it and that
/// program's sema model. Each is computed once, on first use, and shared by
/// every request on the same text. Sema takes seconds on a program that
/// pulls in much of the runtime, and the editor asks for code actions on
/// every cursor move and hovers on every mouse move, so recomputing it per
/// request queues a go-to-definition behind a minute of stale work.
struct Analysis {
    uri: Url,
    text: String,
    program: OnceLock<Result<Program, String>>,
    /// Every file the program read from disk, or found and failed to load,
    /// with its [`file_key`] and its modification time then: the analysis
    /// is stale once one differs.
    read: OnceLock<Vec<(PathBuf, String, Option<SystemTime>)>>,
    sema: OnceLock<Option<Result<SemaModule, diag::Diagnostic>>>,
}

/// When `path` was last modified; `None` when it cannot be read.
fn modified(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path).and_then(|m| m.modified()).ok()
}

/// A file's identity, the same however a path spells it: the editor writes
/// a Windows drive letter in lowercase (`d:`), and the loader may keep the
/// `\\?\D:` form `canonicalize` returns.
fn file_key(path: &Path) -> String {
    pepper_files::imports::path_key(path)
}

impl Analysis {
    fn new(uri: Url, text: String) -> Self {
        Self { uri, text, program: OnceLock::new(), read: OnceLock::new(), sema: OnceLock::new() }
    }

    /// Whether every file the program read from disk, or failed to load, is
    /// as it was: a saved import, a runtime edit, or a change in another
    /// editor makes it stale. Stats the files, which takes about a
    /// millisecond. A new file that would satisfy a missing import is
    /// noticed only through the client's file watcher.
    fn is_current(&self) -> bool {
        self.read.get().is_none_or(|read| read.iter().all(|(path, _, time)| modified(path) == *time))
    }

    /// Whether a change to the files `changed` (their [`file_key`]s) may
    /// change this analysis: its program read one of them, or failed to
    /// load it. The document's own text is the editor's, never the file's.
    fn affected_by(&self, changed: &HashSet<String>) -> bool {
        // Still loading: it may have read the file before the change.
        let Some(program) = self.program.get() else { return true };
        if program.is_err() {
            return false;
        }
        self.read.get().is_some_and(|read| read.iter().any(|(_, key, _)| changed.contains(key)))
    }

    /// Every file of the program rooted at the document, loaded and linked
    /// as the driver does: the document itself (possibly unsaved) first,
    /// then the files its imports reach, then the runtime prelude.
    /// Unreadable or unparseable imported files are skipped; a parse error
    /// in the document is returned.
    fn program(&self) -> Result<&Program, &String> {
        self.program
            .get_or_init(|| {
                let path = self.uri.to_file_path().map_err(|_| "not a file uri".to_string())?;
                let root = pepper_sema::program::Root { name: self.uri.to_string(), source: self.text.clone(), path };
                let setup = pepper_sema::program::Setup { mode: pepper_sema::program::Mode::Lenient, ..Default::default() };
                let program = pepper_sema::program::load_program(root, &setup)?;
                // Each file's time, then whether it still holds what was
                // loaded: a file saved while the program loaded has no time,
                // so the analysis is stale at once.
                let loaded = program.files[1..].iter().map(|f| {
                    let path = PathBuf::from(&f.name);
                    let time = modified(&path).filter(|_| std::fs::read_to_string(&path).is_ok_and(|s| s == f.source));
                    (path, time)
                });
                // A file that did not load changes time once it is fixed.
                let failed = program.failed.iter().map(|path| (path.clone(), modified(path)));
                let read = loaded
                    .chain(failed)
                    .map(|(path, time)| {
                        let key = file_key(&path);
                        (path, key, time)
                    })
                    .collect();
                let _ = self.read.set(read);
                Ok(program)
            })
            .as_ref()
    }

    /// The program's sema model, or its semantic error; `None` when the
    /// program did not load.
    fn sema(&self) -> Option<&Result<SemaModule, diag::Diagnostic>> {
        self.sema.get_or_init(|| self.program().ok().map(sema_model_of)).as_ref()
    }

    /// The sema model, when the program loaded and passed semantic analysis.
    fn sema_model(&self) -> Option<&SemaModule> {
        self.sema()?.as_ref().ok()
    }
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
/// loaded), whose sema model is `sema` (when it passed): the parser's, then
/// [`deprecation_warnings`]. When `text` does not parse, its parse error
/// instead, if it carries a fix (a missing `;`).
fn document_warnings(text: &str, program: Option<&Program>, sema: Option<&SemaModule>) -> Vec<diag::Diagnostic> {
    let module = match pepper_parser::parser::parse_source_diag(text) {
        Ok(module) => module,
        Err(error) if !error.fixes.is_empty() => return vec![error],
        Err(_) => return vec![],
    };
    let mut warnings = module.warnings;
    if let Some(program) = program {
        warnings.extend(deprecation_warnings(program, sema));
    }
    warnings
}

/// The diagnostics of `text` (the program's document) that may carry
/// fixes: its warnings, and the program's semantic error (from `sema`) when
/// it is in the document and carries one, such as the `Copyable` skeleton
/// for a struct that `copy` cannot copy.
fn fixable_diagnostics(
    text: &str,
    program: Option<&Program>,
    sema: Option<&Result<SemaModule, diag::Diagnostic>>,
) -> Vec<diag::Diagnostic> {
    let mut diagnostics = document_warnings(text, program, sema.and_then(|s| s.as_ref().ok()));
    if let Some(Err(error)) = sema
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
        Self {
            client,
            docs: Mutex::new(HashMap::new()),
            conversion_hints: AtomicBool::new(true),
            watches_files: AtomicBool::new(false),
            analyses: Mutex::new(HashMap::new()),
        }
    }

    fn doc(&self, uri: &Url) -> Option<String> {
        self.docs.lock().unwrap().get(uri.as_str()).cloned()
    }

    /// The analysis of the open document `uri` as it reads now: the cached
    /// one while its text is unchanged, else a fresh one that replaces it.
    fn analysis(&self, uri: &Url) -> Option<Arc<Analysis>> {
        let mut analyses = self.analyses.lock().unwrap();
        // Read under `analyses`: `did_close` removes the text before the
        // analysis, so a document closed meanwhile is never cached again.
        let text = self.doc(uri)?;
        if let Some(analysis) = analyses.get(uri.as_str())
            && analysis.text == text
            && analysis.is_current()
        {
            return Some(analysis.clone());
        }
        let analysis = Arc::new(Analysis::new(uri.clone(), text));
        analyses.insert(uri.as_str().to_string(), analysis.clone());
        Some(analysis)
    }

    /// Drop the cached analyses the files `changed` may change
    /// ([`Analysis::affected_by`]), or every one when a file was created or
    /// deleted (`added`), which can change what an import resolves to; and
    /// return their documents.
    fn forget_analyses(&self, changed: &[PathBuf], added: bool) -> Vec<Url> {
        // Resolved once, before taking the lock every request needs.
        let changed: HashSet<String> = changed.iter().map(|path| file_key(path)).collect();
        let mut analyses = self.analyses.lock().unwrap();
        let stale: Vec<String> =
            analyses.iter().filter(|(_, a)| added || a.affected_by(&changed)).map(|(uri, _)| uri.clone()).collect();
        stale.iter().filter_map(|uri| analyses.remove(uri)).map(|a| a.uri.clone()).collect()
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

    /// Publish diagnostics for `uri`. A panic computing them leaves the ones
    /// already published in place.
    async fn publish_diagnostics(&self, uri: &Url) {
        let Some(Some(diags)) = guarded(|| self.diagnostics(uri)) else { return };
        self.client.publish_diagnostics(uri.clone(), diags, None).await;
    }

    /// Diagnostics for `uri`: parse errors (precise) + sema errors.
    fn diagnostics(&self, uri: &Url) -> Option<Vec<Diagnostic>> {
        let mut diags = vec![];
        let analysis = self.analysis(uri)?;
        let text = &analysis.text;
        // A parse error, or one found after parsing (a late import, `T*`
        // outside an extern).
        let parsed = pepper_parser::parser::parse_source_diag(text);
        match &parsed {
            Err(d) => diags.push(lsp_diagnostic(d, uri, &[(uri.as_str(), text)])),
            // Warnings (deprecated syntax) come with quick fixes; see `quick_fixes`.
            Ok(module) => diags.extend(module.warnings.iter().map(|w| lsp_diagnostic(w, uri, &[(uri.as_str(), text)]))),
        }
        if parsed.is_ok() && let Ok(program) = analysis.program() {
            let names = program_names(program);
            if let Some(Err(d)) = analysis.sema() {
                diags.push(lsp_diagnostic(d, uri, &names));
            }
            // Uses of `[Deprecated]` declarations, with their quick fixes.
            let deprecated = deprecation_warnings(program, analysis.sema_model());
            diags.extend(deprecated.iter().map(|w| lsp_diagnostic(w, uri, &names)));
            diags.extend(Self::visibility_diagnostics(program, uri));
        }
        Some(diags)
    }

    /// Hover at `offset` in document `uri`.
    fn hover(&self, uri: &Url, offset: usize) -> Option<Hover> {
        let analysis = self.analysis(uri)?;
        Self::hover_at(uri, &analysis.text, analysis.program().ok(), analysis.sema_model(), offset)
    }

    /// Hover at `offset` in `text`, the document `uri`, which is
    /// `program.files[0]` when its program loaded; `sema` is that program's
    /// model when it passed. A value an `[Implicit]` constructor converts
    /// says so below what the hover shows for it.
    fn hover_at(uri: &Url, text: &str, program: Option<&Program>, sema: Option<&SemaModule>, offset: usize) -> Option<Hover> {
        let hover = Self::hover_expression(uri, text, program, sema, offset);
        let Some(conversion) = sema.and_then(|m| conversion_at(m, offset)) else {
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
                let mut head = format!("`{}` — `{}`", id, rendered);
                // A function whose result shares nothing with its inputs
                // may cross a lock or go to a `[Move]` parameter.
                if !locals.iter().chain(&struct_members).any(|s| s.name == *id)
                    && sema.and_then(|m| pepper_sema::passes::check_confinement::returns_fresh(m, id)) == Some(true)
                {
                    head.push_str("

Returns a fresh value: it shares nothing with the arguments.");
                }
                Some(Hover { contents: md(with_doc(head, global_doc(id))), range: None })
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
                        .or_else(|| sema.and_then(|m| enum_method_signature(m, name)))
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
        let analysis = self.analysis(uri)?;
        Self::definition_at(uri, &analysis.text, analysis.program().ok(), analysis.sema_model(), offset)
    }

    /// Go-to-definition at `offset` in `text`, the document `uri`, which is
    /// `program.files[0]` when its program loaded; `sema` is that program's
    /// model when it passed.
    fn definition_at(uri: &Url, text: &str, program: Option<&Program>, sema: Option<&SemaModule>, offset: usize) -> Option<Vec<Location>> {
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
            && let Some(sema) = sema
            && let Some((function, _)) = overload_at(sema, offset)
        {
            let file = function.loc.file.0 as usize;
            let f = program.files.get(file)?;
            let target_uri = if file == 0 { uri.clone() } else { Url::from_file_path(&f.name).ok()? };
            return Some(vec![Location::new(target_uri, span_to_range(&f.source, function.loc.span))]);
        }
        // A member of any expression (`x.y.z`, `f().m()`), by its owner's
        // type in the sema model.
        if let Some(program) = program
            && let Some(sema) = sema
            && let Some(loc) = pepper_sema::member_lookup::member_declaration(sema, FileId(0), offset)
        {
            let file = loc.file.0 as usize;
            let f = program.files.get(file)?;
            let target_uri = if file == 0 { uri.clone() } else { Url::from_file_path(&f.name).ok()? };
            return Some(vec![Location::new(target_uri, span_to_range(&f.source, loc.span))]);
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
        let watches = params
            .capabilities
            .workspace
            .as_ref()
            .and_then(|w| w.did_change_watched_files.as_ref())
            .and_then(|w| w.dynamic_registration)
            .unwrap_or(false);
        self.watches_files.store(watches, Ordering::Relaxed);
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

    async fn initialized(&self, _: InitializedParams) {
        // Cached analyses read imports from disk: ask the client, whatever
        // editor it is, to report `.pep` files that change.
        if self.watches_files.load(Ordering::Relaxed) {
            let watcher = FileSystemWatcher { glob_pattern: GlobPattern::String("**/*.pep".to_string()), kind: None };
            let options = DidChangeWatchedFilesRegistrationOptions { watchers: vec![watcher] };
            let registration = Registration {
                id: "pep-files".to_string(),
                method: "workspace/didChangeWatchedFiles".to_string(),
                register_options: serde_json::to_value(options).ok(),
            };
            let _ = self.client.register_capability(vec![registration]).await;
        }
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

    /// `.pep` files changed on disk (the client watches them for the
    /// server, see `initialized`): analyses whose programs read one, or failed to load an
    /// import one may satisfy, are dropped (all of them when a file was
    /// created or deleted), to be analyzed again when a request needs them.
    /// Not here: a `git checkout` would otherwise hold every request behind
    /// a sema run per open document. A request also notices a changed
    /// loaded file on its own ([`Analysis::is_current`]); this covers
    /// imports that did not load, and imports a new file resolves
    /// differently, in clients that watch files.
    async fn did_change_watched_files(&self, params: DidChangeWatchedFilesParams) {
        let changed: Vec<PathBuf> = params.changes.iter().filter_map(|c| c.uri.to_file_path().ok()).collect();
        let added = params.changes.iter().any(|c| c.typ != FileChangeType::CHANGED);
        self.forget_analyses(&changed, added);
    }

    async fn did_close(&self, params: DidCloseTextDocumentParams) {
        let uri = params.text_document.uri.clone();
        self.docs.lock().unwrap().remove(uri.as_str());
        self.analyses.lock().unwrap().remove(uri.as_str());
        self.client.publish_diagnostics(uri, vec![], None).await;
    }

    // Each request computes under `guarded`: a bug that panics on one
    // document answers that request with nothing instead of ending the server.
    async fn inlay_hint(&self, params: InlayHintParams) -> LspResult<Option<Vec<InlayHint>>> {
        if !self.conversion_hints.load(Ordering::Relaxed) {
            return Ok(None);
        }
        let uri = params.text_document.uri;
        let range = params.range;
        Ok(guarded(|| {
            let analysis = self.analysis(&uri)?;
            let hints = conversion_hints(&analysis.text, analysis.sema_model()?)
                .into_iter()
                .filter(|h| h.position >= range.start && h.position <= range.end)
                .collect();
            Some(hints)
        })
        .flatten())
    }

    async fn hover(&self, params: HoverParams) -> LspResult<Option<Hover>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        Ok(guarded(|| {
            let text = self.doc(&uri)?;
            self.hover(&uri, line_col_to_byte(&text, pos.line, pos.character))
        })
        .flatten())
    }

    async fn completion(&self, params: CompletionParams) -> LspResult<Option<CompletionResponse>> {
        let uri = params.text_document_position.text_document.uri;
        let pos = params.text_document_position.position;
        Ok(guarded(|| {
            let text = self.doc(&uri)?;
            let offset = line_col_to_byte(&text, pos.line, pos.character);
            Some(CompletionResponse::Array(self.completion(&uri, offset)))
        })
        .flatten())
    }

    async fn goto_definition(&self, params: GotoDefinitionParams) -> LspResult<Option<GotoDefinitionResponse>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        Ok(guarded(|| {
            let text = self.doc(&uri)?;
            self.definition(&uri, line_col_to_byte(&text, pos.line, pos.character)).map(Into::into)
        })
        .flatten())
    }

    async fn code_action(&self, params: CodeActionParams) -> LspResult<Option<CodeActionResponse>> {
        let uri = params.text_document.uri;
        Ok(guarded(|| {
            // The document's one semantic analysis serves both kinds of fix:
            // those a diagnostic carries (a `Copyable` skeleton) and the
            // missing arms of a `match`.
            let analysis = self.analysis(&uri)?;
            let text = &analysis.text;
            let program = analysis.program().ok();
            let diagnostics = fixable_diagnostics(text, program, analysis.sema());
            let mut actions = quick_fixes(&uri, text, &diagnostics, params.range);
            if let (Some(program), Some(Err(error))) = (program, analysis.sema()) {
                actions.extend(missing_arms_fix(&uri, text, program, error, params.range));
            }
            (!actions.is_empty()).then_some(actions)
        })
        .flatten())
    }

    async fn document_symbol(&self, params: DocumentSymbolParams) -> LspResult<Option<DocumentSymbolResponse>> {
        let uri = params.text_document.uri;
        Ok(guarded(|| self.document_symbols(&uri).map(DocumentSymbolResponse::Nested)).flatten())
    }
}

/// `f()`, or `None` when it panics. The panic message still reaches stderr,
/// which the editor shows in the server's output.
fn guarded<R>(f: impl FnOnce() -> R) -> Option<R> {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)).ok()
}

/// Stack for every thread that analyzes a document: as much as the
/// compiler's sema threads. Parsing and sema recurse over the syntax tree,
/// which the parser keeps within `MAX_NESTING` levels; Windows' 1 MB main
/// thread is too small even so, and a stack overflow cannot be caught.
const STACK_SIZE: usize = 8 << 20;

fn main() {
    // The main thread's stack is fixed by the linker, so serve from a
    // thread that has `STACK_SIZE`, as the runtime's workers do.
    let server = std::thread::Builder::new()
        .name("pepper-lsp".into())
        .stack_size(STACK_SIZE)
        .spawn(|| {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .thread_stack_size(STACK_SIZE)
                .enable_all()
                .build()
                .expect("start the async runtime");
            runtime.block_on(async {
                let stdin = tokio::io::stdin();
                let stdout = tokio::io::stdout();
                let (service, socket) = LspService::new(PepperLsp::new);
                Server::new(stdin, stdout, socket).serve(service).await;
            });
        })
        .expect("start the server thread");
    // A panic outside `guarded` has already printed; exit as a crash.
    if server.join().is_err() {
        std::process::exit(101);
    }
}