//! Pepper language server.
//!
//! Speaks LSP over stdio. Diagnostics come from the parser (precise, via AST
//! spans) and from a full semantic check of the merged program (runtime
//! prelude + resolved imports + the open document). Hover, completion,
//! go-to-definition, and document symbols are computed from the parsed AST
//! plus the sema model; names reached through imports are followed using
//! what linking recorded (see `imports`).

mod analysis;
mod imports;
mod infer;
mod platforms;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod sweep;

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use std::sync::atomic::{AtomicBool, Ordering};

use pepper_parser::ast::{self, Span};
use pepper_parser::diagnostic::{self as diag, FileId};
use pepper_parser::parser::parse_source;
use pepper_parser::namespace::{demangle, demangle_known, demangle_name};
use analysis::{Analysis, Documents, View};
use pepper_sema::passes::named_arguments::Parameter;
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
    for property in &s.properties {
        out.push(Symbol { name: property.name.clone(), name_span: property.name_span, ty: type_string(&property.type_name) });
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

/// A variable declaration as a symbol.
fn variable_symbol(v: &ast::VariableDecl) -> Symbol {
    Symbol { name: v.name.clone(), name_span: v.name_span, ty: variable_type(v) }
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
    if v.type_name.name == "__auto" {
        return "unknown".to_string();
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
            // Its constants are declared beside it, as variables.
            ast::Declaration::Extend(_) | ast::Declaration::Static(_) => {}
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
                // The name being declared, under the cursor.
                ast::Statement::Declaration(ast::Declaration::Variable(v))
                    if v.name_span.start <= offset && offset <= v.name_span.end =>
                {
                    out.push(Symbol { name: v.name.clone(), name_span: v.name_span, ty: variable_type(v) });
                }
                ast::Statement::Destructure(d) => {
                    let mut names = vec![];
                    push_pattern(&d.bindings, &mut names);
                    out.extend(names.into_iter().filter(|b| b.name_span.start <= offset && offset <= b.name_span.end));
                }
                ast::Statement::For(f) if f.binding.name_span.start <= offset && offset <= f.binding.name_span.end => {
                    out.push(Symbol { name: f.binding.name.clone(), name_span: f.binding.name_span, ty: variable_type(&f.binding) });
                }
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
                ast::Statement::Static(s) => {
                    if s.block.span.start <= offset && offset < s.block.span.end {
                        collect_locals_upto(&s.block, offset, out);
                    }
                }
                ast::Statement::Match(m) => {
                    for arm in &m.arms {
                        // The names the arm's patterns bind, in its guard and
                        // its block.
                        if arm.span.start <= offset && offset < arm.body.span.end {
                            for (name, span) in arm.patterns.iter().flat_map(|p| p.bound_names()) {
                                out.push(Symbol { name, name_span: span, ty: String::new() });
                            }
                        }
                        if arm.body.span.start <= offset && offset < arm.body.span.end {
                            collect_locals_upto(&arm.body, offset, out);
                        }
                    }
                    if let Some((_, body)) = &m.else_arm
                        && body.span.start <= offset
                        && offset < body.span.end
                    {
                        collect_locals_upto(body, offset, out);
                    }
                }
                _ => {}
            }
        }
    }
}

/// The function, method or constructor whose body contains `offset`, if
/// any, plus the enclosing struct (none for an extension's method).
fn function_at(module: &ast::Module, offset: usize) -> Option<(&ast::FunctionDecl, Option<&ast::StructDecl>)> {
    let inside = |f: &&ast::FunctionDecl| f.span.start <= offset && offset < f.span.end && f.body.is_some();
    for decl in &module.declarations {
        match decl {
            ast::Declaration::Function(f) if inside(&f) => return Some((f, None)),
            ast::Declaration::Struct(s) if s.span.start <= offset && offset < s.span.end => {
                let accessors = s.properties.iter().flat_map(|p| p.accessors());
                if let Some(f) = s.methods.iter().chain(&s.constructors).chain(accessors).find(inside) {
                    return Some((f, Some(s)));
                }
            }
            ast::Declaration::Extend(e) => {
                if let Some(f) = e.methods.iter().chain(e.properties.iter().flat_map(|p| p.accessors())).find(inside) {
                    return Some((f, None));
                }
            }
            // A trait's method with a default body.
            ast::Declaration::Trait(t) => {
                if let Some(f) = t.methods.iter().find(inside) {
                    return Some((f, None));
                }
            }
            _ => {}
        }
    }
    None
}

/// The function body containing `offset`, if any, plus the enclosing struct:
/// a function's, method's or constructor's, or a destructor.
fn body_at(module: &ast::Module, offset: usize) -> Option<(&ast::Block, Option<&ast::StructDecl>)> {
    if let Some((f, s)) = function_at(module, offset) {
        return Some((f.body.as_ref()?, s));
    }
    module.declarations.iter().find_map(|d| match d {
        ast::Declaration::Struct(s) => {
            let d = s.destructor.as_ref()?;
            (d.span.start <= offset && offset < d.span.end).then_some((d, Some(s)))
        }
        _ => None,
    })
}

/// The name of the type the extension around `offset` extends.
fn extended_at(module: &ast::Module, offset: usize) -> Option<String> {
    module.declarations.iter().find_map(|d| match d {
        ast::Declaration::Extend(e) if e.span.start <= offset && offset < e.span.end => Some(e.target.name.clone()),
        _ => None,
    })
}

/// The declaration whose name is at `offset`, and the struct, trait or
/// extended type it is a member of: a top-level declaration, a member
/// (field, method, enum case), or a local or parameter.
fn declared_at(module: &ast::Module, offset: usize) -> Option<(Symbol, Option<String>)> {
    let at = |s: &Symbol| s.name_span.start <= offset && offset <= s.name_span.end;
    let methods = |owner: &str, methods: &[ast::FunctionDecl]| {
        let found = methods.iter().find(|m| m.name_span.start <= offset && offset <= m.name_span.end)?;
        let symbol = Symbol { name: found.name.clone(), name_span: found.name_span, ty: function_signature(found) };
        Some((symbol, Some(owner.to_string())))
    };
    collect_globals(module)
        .into_iter()
        .find(at)
        .map(|s| (s, None))
        .or_else(|| {
            module.declarations.iter().find_map(|d| match d {
                ast::Declaration::Struct(s) => collect_struct_members(s)
                    .into_iter()
                    .find(at)
                    // A value an enum case carries (`Circle(radius: int)`).
                    .or_else(|| {
                        let cases = s.enumeration.iter().flat_map(|e| &e.cases);
                        cases.flat_map(|c| c.payload.iter().flatten()).find(|v| at(&variable_symbol(v))).map(variable_symbol)
                    })
                    .map(|m| (m, Some(s.name.clone()))),
                ast::Declaration::Trait(t) => methods(&t.name, &t.methods),
                ast::Declaration::Extend(e) => methods(&e.target.name, &e.methods),
                _ => None,
            })
        })
        .or_else(|| scope_locals(module, offset).into_iter().find(at).map(|s| (s, None)))
        .or_else(|| parameter_at(module, offset).map(|s| (s, None)))
        .or_else(|| generic_param_at(module, offset, |p| p.name_span.start <= offset && offset <= p.name_span.end))
        .or_else(|| variable_at(module, offset).map(|s| (s, None)))
}

/// The variable declared anywhere whose name is at `offset`: a parameter of
/// a closure in a default value, say.
fn variable_at(module: &ast::Module, offset: usize) -> Option<Symbol> {
    let mut found = None;
    infer::each(module, |item| {
        if let infer::Item::Variable(v) = item
            && v.name_span.start <= offset
            && offset <= v.name_span.end
        {
            found = Some(variable_symbol(v));
        }
    });
    found
}

/// Where the document first declares `label` of a tuple whose labels are
/// `labels`: in a tuple type, else a labeled tuple value.
fn label_declared(module: &ast::Module, text: &str, labels: &[String], label: &str) -> Option<Span> {
    let mut types: Vec<&ast::TypeName> = vec![];
    let mut values: Vec<Span> = vec![];
    let mut functions: Vec<&ast::FunctionDecl> = vec![];
    for d in &module.declarations {
        match d {
            ast::Declaration::Function(f) => functions.push(f),
            ast::Declaration::Struct(s) => functions.extend(s.methods.iter().chain(&s.constructors)),
            ast::Declaration::Extend(e) => functions.extend(&e.methods),
            ast::Declaration::Trait(t) => functions.extend(&t.methods),
            _ => {}
        }
    }
    types.extend(functions.iter().map(|f| &f.return_type));
    infer::each(module, |item| match item {
        infer::Item::Variable(v) => types.push(&v.type_name),
        infer::Item::Expression(ast::Expression::Tuple { labels: written, .. })
            if written.iter().map(|(l, _)| l).eq(labels.iter()) =>
        {
            values.extend(written.iter().filter(|(l, _)| l == label).map(|(_, s)| *s));
        }
        _ => {}
    });
    // A type's labels have no spans: find the label and its `:` in its text.
    let in_type = types.iter().filter(|t| t.name == ast::TUPLE_TYPE && t.labels == labels).find_map(|t| {
        let written = text.get(t.span.start..t.span.end)?;
        let part = |c: char| c.is_ascii_alphanumeric() || c == '_';
        written.match_indices(label).find_map(|(i, _)| {
            let before = written[..i].chars().next_back();
            let after = &written[i + label.len()..];
            (before.is_none_or(|c| !part(c)) && after.trim_start().starts_with(':'))
                .then(|| Span { start: t.span.start + i, end: t.span.start + i + label.len() })
        })
    });
    in_type.or_else(|| values.into_iter().min_by_key(|s| s.start))
}

/// A tuple's label where it is written at `offset`: in a tuple type
/// (`(line: int, column: int)`) or a labeled tuple (`(line: 3, column:
/// 7)`). Its name and span, and the element's type in a type or its value
/// in a tuple.
fn label_at<'a>(module: &'a ast::Module, text: &str, offset: usize) -> Option<(String, Span, Result<infer::Ty, &'a ast::Expression>)> {
    let mut found = None;
    infer::each(module, |item| {
        if let infer::Item::Expression(ast::Expression::Tuple { elements, labels, .. }) = item
            && let Some(i) = labels.iter().position(|(_, s)| s.start <= offset && offset <= s.end)
            && let Some(element) = elements.get(i)
        {
            found = Some((labels[i].0.clone(), labels[i].1, Err(element)));
        }
    });
    if found.is_some() {
        return found;
    }
    let ty = imports::type_at(module, offset).filter(|t| t.name == ast::TUPLE_TYPE && !t.labels.is_empty())?;
    let Span { start, end } = word_at(text, offset)?;
    // A label is followed by its `:`.
    if !text[end..].trim_start().starts_with(':') {
        return None;
    }
    let i = ty.labels.iter().position(|l| *l == text[start..end])?;
    Some((ty.labels[i].clone(), Span { start, end }, Ok(infer::Ty::from_ast(ty.generic_types.get(i)?))))
}

/// The parameter whose name is at `offset` in any function's signature,
/// bodiless ones included (`extern`, a trait's methods).
fn parameter_at(module: &ast::Module, offset: usize) -> Option<Symbol> {
    let functions = module.declarations.iter().flat_map(|d| -> Box<dyn Iterator<Item = &ast::FunctionDecl>> {
        match d {
            ast::Declaration::Function(f) => Box::new(std::iter::once(f)),
            ast::Declaration::Struct(s) => {
                Box::new(s.methods.iter().chain(&s.constructors).chain(s.properties.iter().flat_map(|p| p.accessors())))
            }
            ast::Declaration::Trait(t) => Box::new(t.methods.iter()),
            ast::Declaration::Extend(e) => Box::new(e.methods.iter().chain(e.properties.iter().flat_map(|p| p.accessors()))),
            _ => Box::new(std::iter::empty()),
        }
    });
    functions.flat_map(|f| &f.parameters).find(|p| p.name_span.start <= offset && offset <= p.name_span.end).map(|p| Symbol {
        name: p.name.clone(),
        name_span: p.name_span,
        ty: variable_type(p),
    })
}

/// A generic parameter of the declaration around `offset` that `matches`,
/// as a symbol whose type reads `type parameter`.
fn generic_param_at(
    module: &ast::Module,
    offset: usize,
    matches: impl Fn(&ast::GenericParam) -> bool,
) -> Option<(Symbol, Option<String>)> {
    let inside = |s: Span| s.start <= offset && offset < s.end;
    let mut scopes: Vec<&[ast::GenericParam]> = vec![];
    for d in &module.declarations {
        match d {
            ast::Declaration::Function(f) if inside(f.span) => scopes.push(&f.generic_params),
            ast::Declaration::Struct(s) if inside(s.span) => {
                scopes.push(&s.generic_params);
                scopes.extend(s.methods.iter().filter(|m| inside(m.span)).map(|m| m.generic_params.as_slice()));
            }
            ast::Declaration::Trait(t) if inside(t.span) => {
                scopes.push(&t.generic_params);
                scopes.extend(t.methods.iter().filter(|m| inside(m.span)).map(|m| m.generic_params.as_slice()));
            }
            ast::Declaration::Extend(e) if inside(e.span) => {
                scopes.extend(e.methods.iter().filter(|m| inside(m.span)).map(|m| m.generic_params.as_slice()));
            }
            ast::Declaration::TypeAlias(t) if inside(t.span) => scopes.push(&t.generic_params),
            _ => {}
        }
    }
    let p = scopes.into_iter().rev().flatten().find(|p| matches(p))?;
    let mut ty = "type parameter".to_string();
    if !p.bounds.is_empty() {
        ty += &format!(": {}", p.bounds.iter().map(type_string).collect::<Vec<_>>().join(" & "));
    }
    Some((Symbol { name: p.name.clone(), name_span: p.name_span, ty }, None))
}

/// A tuple type's element label at `offset` (`handle` in
/// `(handle: ulong, interest: int)`), as a symbol of its element's type.
fn tuple_label_at(module: &ast::Module, text: &str, offset: usize) -> Option<Symbol> {
    let ty = imports::type_at(module, offset)?;
    if ty.name != ast::TUPLE_TYPE || ty.labels.is_empty() {
        return None;
    }
    let is_name = |b: u8| b.is_ascii_alphanumeric() || b == b'_';
    let bytes = text.as_bytes();
    let start = (0..offset).rev().take_while(|&i| is_name(bytes[i])).last().unwrap_or(offset);
    let end = (offset..bytes.len()).find(|&i| !is_name(bytes[i])).unwrap_or(bytes.len());
    if start >= end || !text[end..].trim_start().starts_with(':') {
        return None;
    }
    let name = &text[start..end];
    let index = ty.labels.iter().position(|l| l == name)?;
    let element = ty.generic_types.get(index)?;
    Some(Symbol { name: name.to_string(), name_span: Span { start, end }, ty: element.to_string() })
}

/// A generic parameter named where `offset` writes a type (`T` in
/// `Array<T>`), from the declarations around it.
fn generic_param_used(module: &ast::Module, program: Option<&Program>, offset: usize) -> Option<Symbol> {
    let ty = imports::type_at(module, offset)?;
    let name = ty.name.trim_end_matches(['*', '[', ']']);
    generic_param_at(module, offset, |p| p.name == name).map(|(s, _)| s).or_else(|| {
        // `extend Box<T>` names its parameters in the extended type; a
        // primitive or a type a file declares is an argument
        // (`extend Array<int>`), not a parameter.
        let declared = |name: &str| {
            pepper_sema::type_name::INTEGRAL_TYPES.contains(name)
                || name == "String"
                || module.declarations.iter().any(|d| d.name() == name)
                || program.is_some_and(|p| imports::declares(p, name))
        };
        module.declarations.iter().find_map(|d| match d {
            ast::Declaration::Extend(e) if e.span.start <= offset && offset < e.span.end => {
                let param =
                    e.target.generic_types.iter().find(|g| g.name == name && g.generic_types.is_empty() && !declared(name))?;
                Some(Symbol { name: param.name.clone(), name_span: param.span, ty: "type parameter".to_string() })
            }
            _ => None,
        })
    })
}

/// The type argument written in a member's name at `offset` (`T` of
/// `copies.copy<T>(x)`): the parser keeps those in the member's name, after
/// its name's span.
fn type_argument_at(module: &ast::Module, text: &str, offset: usize) -> Option<String> {
    let mut found = None;
    infer::each(module, |item| {
        if let infer::Item::Expression(ast::Expression::MemberAccess { name, name_span, .. }) = item
            && name.contains('<')
            && name_span.end <= offset
            && text.get(name_span.end..offset).is_some_and(|between| between.trim_start().starts_with('<'))
        {
            // Inside the brackets: as many `<` before `offset` as `>`.
            let between = &text[name_span.end..offset];
            if !between.contains(['(', ')']) && between.matches('<').count() > between.matches('>').count() {
                found = Some(());
            }
        }
    });
    found?;
    word_at(text, offset).map(|s| text[s.start..s.end].to_string())
}

/// The span of the identifier around `offset` in `text`.
fn word_at(text: &str, offset: usize) -> Option<Span> {
    let part = |c: char| c.is_ascii_alphanumeric() || c == '_';
    // The name's characters are ASCII, but what precedes it may not be
    // (`# ─x`): trimming keeps `start` on a character boundary.
    let start = text.get(..offset)?.trim_end_matches(part).len();
    let end = text[offset..].find(|c: char| !part(c)).map_or(text.len(), |i| offset + i);
    (end > start).then_some(Span { start, end })
}

/// Which name of a `String.format(...)` call is at `offset`, `String` or
/// `format`: the parser lowers the call, so neither is in the tree.
fn string_format_at(text: &str, offset: usize) -> Option<&'static str> {
    let Span { start, end } = word_at(text, offset)?;
    let call_follows = |after: &str| after.trim_start().starts_with('(');
    match &text[start..end] {
        "String" => {
            let after = text[end..].trim_start().strip_prefix('.')?.trim_start().strip_prefix("format")?;
            call_follows(after).then_some("String")
        }
        "format" => {
            let before = text[..start].trim_end().strip_suffix('.')?.trim_end();
            (before.ends_with("String") && call_follows(&text[end..])).then_some("format")
        }
        _ => None,
    }
}

/// Whether `module` has a name (a reference or a member's name) at `offset`.
fn names_at(module: &ast::Module, offset: usize) -> bool {
    match find_expr(module, offset) {
        Some(ast::Expression::SymbolRef { span, .. }) => span.start <= offset && offset < span.end,
        Some(ast::Expression::MemberAccess { name_span, .. }) => name_span.start <= offset && offset < name_span.end,
        _ => false,
    }
}

/// Where enum `owner`'s case `name` is declared: the program file and the
/// case's name. Linking spells another module's declarations with its
/// namespace (`Backend@async`).
fn enum_case_declared(program: &Program, owner: &str, name: &str) -> Option<(usize, Span)> {
    program.files.iter().enumerate().find_map(|(i, f)| {
        f.module.declarations.iter().find_map(|d| match d {
            ast::Declaration::Struct(s) if demangle_name(&s.name) == owner => {
                let case = s.enumeration.as_ref()?.cases.iter().find(|c| c.name == name)?;
                Some((i, case.name_span))
            }
            _ => None,
        })
    })
}

/// The locals in scope at `offset`: the enclosing function's parameters,
/// then what its body declares before `offset`.
fn scope_locals(module: &ast::Module, offset: usize) -> Vec<Symbol> {
    let Some((f, _)) = function_at(module, offset) else {
        // A destructor has no parameters.
        if let Some((body, _)) = body_at(module, offset) {
            let mut out = locals_at(body, offset);
            push_match_bindings(body, offset, &mut out);
            return out;
        }
        // A closure in a module-scope variable's initializer.
        let mut out = vec![];
        let init = module.declarations.iter().find_map(|d| match d {
            ast::Declaration::Variable(v) => v.default_value.as_ref(),
            _ => None,
        }.filter(|e| expr_start(e) <= offset && offset < e.span().end));
        if let Some(c) = init.and_then(|e| closure_in_expression(e, offset)) {
            push_closure_locals(c, offset, &mut out);
        }
        return out;
    };
    let mut out: Vec<Symbol> = f
        .parameters
        .iter()
        .filter(|p| p.name != "this")
        .map(|p| Symbol { name: p.name.clone(), name_span: p.name_span, ty: variable_type(p) })
        .collect();
    if let Some(body) = &f.body {
        out.extend(locals_at(body, offset));
        if let Some(c) = closure_in_block(body, offset) {
            push_closure_locals(c, offset, &mut out);
        }
        push_match_bindings(body, offset, &mut out);
    }
    out
}

/// The names a `match` expression's arm binds (`Circle(r) => 3 * r * r`),
/// for each arm in `block` whose value contains `offset`.
fn push_match_bindings(block: &ast::Block, offset: usize, out: &mut Vec<Symbol>) {
    infer::each_in_block(block, |item| {
        if let infer::Item::Expression(ast::Expression::Match(m)) = item {
            // The arm's guard and value see them.
            for arm in m.arms.iter().filter(|a| a.span.start <= offset && offset < a.value.span().end) {
                // Not the hidden names `String.format`'s lowering binds.
                for (name, name_span) in arm.patterns.iter().flat_map(|p| p.bound_names()).filter(|(n, _)| !n.starts_with("_pep_")) {
                    out.push(Symbol { name, name_span, ty: String::new() });
                }
            }
        }
    });
}

/// The locals inside closure `c` at `offset`: its parameters, what its body
/// declares, and so on for each closure nested there.
fn push_closure_locals(c: &ast::ClosureLiteral, offset: usize, out: &mut Vec<Symbol>) {
    let mut closure = Some(c);
    while let Some(c) = closure {
        out.extend(c.parameters.iter().map(|p| Symbol { name: p.name.clone(), name_span: p.name_span, ty: variable_type(p) }));
        out.extend(locals_at(&c.body, offset));
        closure = closure_in_block(&c.body, offset);
    }
}

/// The outermost closure in `block` whose span contains `offset`.
fn closure_in_block(block: &ast::Block, offset: usize) -> Option<&ast::ClosureLiteral> {
    let inside = |s: Span| s.start <= offset && offset < s.end;
    block.statements.iter().find_map(|stmt| {
        let in_expr = |e| closure_in_expression(e, offset);
        match stmt {
            ast::Statement::Expression(e) => in_expr(e),
            ast::Statement::Return(ast::ReturnStatement { expr: Some(e), .. }) => in_expr(e),
            ast::Statement::Declaration(ast::Declaration::Variable(v)) => v.default_value.as_ref().and_then(in_expr),
            ast::Statement::Destructure(d) => in_expr(&d.value),
            ast::Statement::Block(b) if inside(b.span) => closure_in_block(b, offset),
            ast::Statement::Branch(b) => in_expr(&b.condition)
                .or_else(|| closure_in_block(&b.if_block, offset))
                .or_else(|| b.else_block.as_ref().and_then(|e| closure_in_block(e, offset))),
            ast::Statement::While(w) => in_expr(&w.condition).or_else(|| closure_in_block(&w.block, offset)),
            ast::Statement::For(f) => in_expr(&f.iterable).or_else(|| closure_in_block(&f.block, offset)),
            ast::Statement::With(w) => in_expr(&w.scope)
                .or_else(|| closure_in_block(&w.block, offset))
                .or_else(|| w.else_block.as_ref().and_then(|e| closure_in_block(e, offset))),
            ast::Statement::Static(s) => closure_in_block(&s.block, offset),
            ast::Statement::Match(m) => in_expr(&m.value).or_else(|| m.arms.iter().filter_map(|a| a.guard.as_ref()).find_map(in_expr)).or_else(|| {
                m.arms.iter().map(|a| &a.body).chain(m.else_arm.as_ref().map(|(_, b)| b)).find_map(|b| closure_in_block(b, offset))
            }),
            _ => None,
        }
    })
}

/// The outermost closure in `expr` whose span contains `offset`.
fn closure_in_expression(expr: &ast::Expression, offset: usize) -> Option<&ast::ClosureLiteral> {
    let s = Span { start: expr_start(expr), end: expr.span().end };
    if !(s.start <= offset && offset < s.end) {
        return None;
    }
    let children: Vec<&ast::Expression> = match expr {
        ast::Expression::Closure(c) => return Some(c),
        ast::Expression::Binary { lhs, rhs, .. } | ast::Expression::Index { lhs, rhs, .. } => vec![lhs, rhs],
        ast::Expression::Unary { operand, .. } => vec![operand],
        ast::Expression::Cast { expr: value, .. }
        | ast::Expression::Is { value, .. }
        | ast::Expression::NamedArgument { value, .. } => vec![value],
        ast::Expression::MemberAccess { lhs, .. } => vec![lhs],
        ast::Expression::Ternary { condition, true_expr, false_expr, .. } => vec![condition, true_expr, false_expr],
        ast::Expression::FunctionCall { function, arguments, .. } => std::iter::once(&**function).chain(arguments).collect(),
        ast::Expression::Tuple { elements, .. } | ast::Expression::ArrayLiteral { elements, .. } => elements.iter().collect(),
        ast::Expression::MapLiteral { entries, .. } => entries.iter().flat_map(|(k, v)| [k, v]).collect(),
        ast::Expression::Match(m) => {
            std::iter::once(&m.value)
                .chain(m.arms.iter().flat_map(|a| a.guard.iter().chain(std::iter::once(&a.value))))
                .chain(m.else_arm.as_ref().map(|(_, v)| v))
                .collect()
        }
        _ => vec![],
    };
    children.into_iter().find_map(|e| closure_in_expression(e, offset))
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
        ast::Expression::Match(m) => expr_at(&m.value, offset)
            .or_else(|| m.arms.iter().find_map(|a| a.guard.as_ref().and_then(|g| expr_at(g, offset)).or_else(|| expr_at(&a.value, offset))))
            .or_else(|| m.else_arm.as_ref().and_then(|(_, v)| expr_at(v, offset)))
            .or(Some(expr)),
        ast::Expression::Closure(c) => find_expr_in_block(&c.body, offset).or(Some(expr)),
        ast::Expression::Tuple { elements, .. } | ast::Expression::ArrayLiteral { elements, .. } => {
            elements.iter().find_map(|e| expr_at(e, offset)).or(Some(expr))
        }
        ast::Expression::MapLiteral { entries, .. } => {
            entries.iter().find_map(|(k, v)| expr_at(k, offset).or_else(|| expr_at(v, offset))).or(Some(expr))
        }
        ast::Expression::Cast { expr: value, .. } => expr_at(value, offset).or(Some(expr)),
        ast::Expression::NamedArgument { value, .. } => expr_at(value, offset),
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
    let found = find_expr_in_module(module, offset);
    let names_offset = |e: &ast::Expression| match e {
        ast::Expression::SymbolRef { span, .. } => span.start <= offset && offset < span.end,
        ast::Expression::MemberAccess { name_span, .. } => name_span.start <= offset && offset < name_span.end,
        _ => false,
    };
    if found.is_some_and(names_offset) {
        return found;
    }
    // Sugar the parser lowers (`String.format`'s arguments) can sit outside
    // the spans of the expressions made for it: the name itself.
    let mut name = None;
    infer::each(module, |item| {
        if let infer::Item::Expression(e) = item
            && names_offset(e)
        {
            name = Some(e);
        }
    });
    name.or(found)
}

fn find_expr_in_module<'a>(module: &'a ast::Module, offset: usize) -> Option<&'a ast::Expression> {
    if let Some((body, _)) = body_at(module, offset) {
        return find_expr_in_block(body, offset).or_else(|| {
            // A parameter's default value (`construct(this.op = square)`).
            let (f, _) = function_at(module, offset)?;
            f.parameters.iter().filter_map(|p| p.default_value.as_ref()).find_map(|e| expr_at(e, offset))
        });
    }
    // A module-scope variable's initializer.
    module.declarations.iter().find_map(|d| match d {
        ast::Declaration::Variable(v) => v.default_value.as_ref().and_then(|e| expr_at(e, offset)),
        _ => None,
    })
}

fn find_expr_in_block<'a>(block: &'a ast::Block, offset: usize) -> Option<&'a ast::Expression> {
    for stmt in &block.statements {
        let mut s = stmt.span();
        // An expression statement's span is its expression's: an
        // assignment's starts at the `=`. The `return` a closure's
        // expression body (`=> x * 2`) becomes need not span its value.
        if let ast::Statement::Expression(e) | ast::Statement::Return(ast::ReturnStatement { expr: Some(e), .. }) = stmt {
            s.start = s.start.min(expr_start(e));
            s.end = s.end.max(e.span().end);
        }
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
            ast::Statement::Destructure(d) => {
                if let Some(found) = expr_at(&d.value, offset) {
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
            ast::Statement::Static(s) => {
                if let Some(found) = find_expr_in_block(&s.block, offset) {
                    return Some(found);
                }
            }
            ast::Statement::Match(m) => {
                if let Some(found) = expr_at(&m.value, offset) {
                    return Some(found);
                }
                if let Some(found) = m.arms.iter().filter_map(|a| a.guard.as_ref()).find_map(|g| expr_at(g, offset)) {
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
    // A guarded arm may not run, so it handles nothing.
    let handled: Vec<&str> =
        found.arms.iter().filter(|a| a.guard.is_none()).flat_map(|a| &a.patterns).map(|p| p.case.as_str()).collect();
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
    find_match_by(module, start, &|m| m.keyword_span.start == start)
}

/// The case name of a `match` arm's pattern at `offset` (`Red` in
/// `Red => ...` or `Color.Red => ...`), and the enum the pattern names, if
/// it names one.
fn case_pattern_at(module: &ast::Module, offset: usize) -> Option<&ast::Pattern> {
    let on = |p: &ast::Pattern| !p.case.is_empty() && p.case_span.start <= offset && offset <= p.case_span.end;
    let m = find_match_by(module, offset, &|m| m.arms.iter().flat_map(|a| &a.patterns).any(on))?;
    m.arms.iter().flat_map(|a| &a.patterns).find(|p| on(p))
}

/// The innermost `match` statement around `offset` that `matches`.
fn find_match_by<'a>(module: &'a ast::Module, start: usize, matches: &dyn Fn(&ast::Match) -> bool) -> Option<&'a ast::Match> {
    fn in_block<'a>(b: &'a ast::Block, start: usize, matches: &dyn Fn(&ast::Match) -> bool) -> Option<&'a ast::Match> {
        b.statements.iter().find_map(|s| in_statement(s, start, matches))
    }
    fn in_statement<'a>(s: &'a ast::Statement, start: usize, matches: &dyn Fn(&ast::Match) -> bool) -> Option<&'a ast::Match> {
        let span = s.span();
        if start < span.start || start >= span.end {
            return None;
        }
        match s {
            ast::Statement::Match(m) if matches(m) => Some(m),
            ast::Statement::Match(m) => m
                .arms
                .iter()
                .map(|a| &a.body)
                .chain(m.else_arm.as_ref().map(|(_, b)| b))
                .find_map(|b| in_block(b, start, matches)),
            ast::Statement::Block(b) => in_block(b, start, matches),
            ast::Statement::Branch(b) => {
                in_block(&b.if_block, start, matches).or_else(|| b.else_block.as_ref().and_then(|e| in_block(e, start, matches)))
            }
            ast::Statement::While(w) => in_block(&w.block, start, matches),
            ast::Statement::For(f) => in_block(&f.block, start, matches),
            ast::Statement::With(w) => {
                in_block(&w.block, start, matches).or_else(|| w.else_block.as_ref().and_then(|e| in_block(e, start, matches)))
            }
            ast::Statement::Static(s) => in_block(&s.block, start, matches),
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
                .chain(s.properties.iter().flat_map(|p| p.accessors()).filter_map(|m| m.body.as_ref()))
                .collect(),
            ast::Declaration::Extend(e) => {
                e.methods.iter().chain(e.properties.iter().flat_map(|p| p.accessors())).filter_map(|m| m.body.as_ref()).collect()
            }
            ast::Declaration::Trait(t) => t.methods.iter().filter_map(|m| m.body.as_ref()).collect(),
            _ => vec![],
        };
        bodies.into_iter().find_map(|b| in_block(b, start, matches))
    })
}

/// The enum a `match` pattern's case belongs to: the one it names
/// (`Color.Red`), else the one enum in the program with a case of that
/// name.
fn pattern_enum<'a>(program: &'a Program, pattern: &'a ast::Pattern) -> Option<&'a str> {
    if let Some(qualifier) = &pattern.qualifier {
        return Some(qualifier.name.as_str());
    }
    let mut owners = program.files.iter().flat_map(|f| &f.module.declarations).filter_map(|d| match d {
        ast::Declaration::Struct(s) if s.enumeration.as_ref().is_some_and(|e| e.cases.iter().any(|c| c.name == pattern.case)) => {
            Some(s.name.as_str())
        }
        _ => None,
    });
    let owner = owners.next()?;
    owners.all(|o| o == owner).then_some(owner)
}

/// The enum `lhs` names in `lhs.case`: `Color`, or `_IoWait` in
/// `io._IoWait`, qualified by its module.
fn enum_named(lhs: &ast::Expression) -> Option<&str> {
    match lhs {
        ast::Expression::SymbolRef { id, .. } => Some(id),
        ast::Expression::MemberAccess { lhs, name, .. } if matches!(&**lhs, ast::Expression::SymbolRef { .. }) => Some(name),
        _ => None,
    }
}

/// What hover shows for `lhs.name` when `lhs` names an enum and `name` one
/// of its cases: `Color.Red = 0`, or `Doc.Text(text: String)` for a case
/// that carries values.
fn enum_case_of(module: &SemaModule, lhs: &ast::Expression, name: &str) -> Option<String> {
    enum_case_named(module, enum_named(lhs)?, name)
}

/// [`enum_case_of`] for the enum named `id`.
fn enum_case_named(module: &SemaModule, id: &str, name: &str) -> Option<String> {
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
        .or_else(|| module.enums.iter().find(|e| e.name == *id))
        .or_else(|| module.enums.iter().find(|e| demangle_name(&e.name) == id))?;
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
    let id = enum_named(lhs)?;
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
    let name = &before[before.trim_end_matches(|c: char| c.is_ascii_alphanumeric() || c == '_').len()..];
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
        // Another file's export, under its module's namespace.
        .or_else(|| module.structs.iter().find(|s| demangle_name(&s.name) == name))
}

fn struct_member_type(st: &StructDef, name: &str) -> Option<String> {
    st.field_members.iter().find(|f| f.name == name).map(|f| f.ty.to_string())
}

/// A symbol's type: as written, or as sema inferred it for a local
/// (`var worker = _async_worker()`); `unknown` when neither says.
fn symbol_type(sema: Option<&SemaModule>, s: &Symbol) -> String {
    if !s.ty.is_empty() && s.ty != "unknown" {
        return s.ty.clone();
    }
    sema.and_then(|m| pepper_sema::member_lookup::local_type(m, FileId(0), s.name_span.start))
        // Tuple and function types as written: `(int, int)`.
        .map(|t| infer::Ty::parse(&t.to_string()).map_or_else(|| t.to_string(), |t| t.to_string()))
        .unwrap_or_else(|| "unknown".to_string())
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

/// What hover shows for `print`, which no file declares.
const PRINT_HOVER: &str = "`print` — built-in function\n\nPrints each argument on a line of its own.";

/// What hover shows for a member the syntax found ([`infer::Found`]): a
/// field's type, a method's signature or a case, with its doc comment.
fn found_hover(program: Option<&Program>, text: &str, found: &infer::Found) -> String {
    let (name, start) = match &found.kind {
        infer::Kind::Field(v) => (format!(".{}", v.name), v.attributes.iter().map(|a| a.span.start).chain([v.span.start]).min()),
        infer::Kind::Property(p) => (format!(".{}", p.name), p.attributes.iter().map(|a| a.span.start).chain([p.span.start]).min()),
        infer::Kind::Method(f) => (
            demangle_name(&f.name).to_string(),
            f.attributes.iter().map(|a| a.span.start).chain([f.span.start, f.name_span.start]).min(),
        ),
        infer::Kind::Case(c) => (c.name.clone(), Some(c.span.start)),
        infer::Kind::EnumMethod(_, method) => (method.to_string(), None),
        infer::Kind::Element(label, _) => return format!("`.{}` — `{}`", label, found.describe()),
    };
    let source = match found.file {
        0 => Some(text),
        file => program.and_then(|p| p.files.get(file)).map(|f| f.source.as_str()),
    };
    let doc = source.zip(start).and_then(|(source, start)| Some(pepper_parser::doc::doc_comment_before(source, start)?.to_markdown()));
    with_doc(format!("`{}` — `{}`", name, found.describe()), doc)
}

/// Where `span` of program file `file` is: the document `uri` (`text`) for
/// file 0.
fn file_location(uri: &Url, text: &str, program: Option<&Program>, file: usize, span: Span) -> Option<Location> {
    if file == 0 {
        return Some(Location::new(uri.clone(), span_to_range(text, span)));
    }
    let f = program?.files.get(file)?;
    Some(Location::new(Url::from_file_path(&f.name).ok()?, span_to_range(&f.source, span)))
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
    /// The open documents and their analyses; shared with the background
    /// analyses the server schedules.
    documents: Arc<Documents>,
    /// Show `[Implicit]` constructor conversions as inlay hints: the
    /// client's `inlayHints.implicitConversions` initialization option,
    /// on unless it says `false`.
    conversion_hints: AtomicBool,
    /// Show parameter names before literal arguments as inlay hints
    /// (`width: 800`): the client's `inlayHints.parameterNames`
    /// initialization option, on unless it says `false`.
    parameter_hints: AtomicBool,
    /// The client can watch files for the server (`workspace/
    /// didChangeWatchedFiles` with dynamic registration).
    watches_files: AtomicBool,
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
        0 => String::new(),
        1 => " (+1 overload)".to_string(),
        n => format!(" (+{} overloads)", n),
    };
    let file = function.loc.file.0 as usize;
    // The member as its file declares it (a free function, or a method of a
    // struct, extension or trait), parameter names included, and its doc
    // comment.
    let declared = program.files.get(file).and_then(|f| {
        f.module.declarations.iter().find_map(|d| {
            let methods: &[ast::FunctionDecl] = match d {
                ast::Declaration::Function(g) if g.name_span == function.loc.span => {
                    return Some((function_signature(g), g.attributes.iter().map(|a| a.span.start).chain([g.span.start]).min()));
                }
                ast::Declaration::Struct(s) => &s.methods,
                ast::Declaration::Extend(e) => &e.methods,
                ast::Declaration::Trait(t) => &t.methods,
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
/// after, so the call the compiler inserts is visible. They come in pairs,
/// each conversion's two in a row.
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

/// The inlay hints naming the parameter before each literal argument passed
/// by position (`width: 800`), from `SemaModule::argument_names`.
fn parameter_hints(text: &str, sema: &SemaModule) -> Vec<InlayHint> {
    sema.argument_names
        .iter()
        .filter(|(at, _)| at.file == FileId(0) && at.span.start <= text.len())
        .map(|(at, name)| InlayHint {
            position: byte_to_lsp_pos(text, at.span.start),
            label: InlayHintLabel::String(format!("{}:", name)),
            kind: Some(InlayHintKind::PARAMETER),
            text_edits: None,
            tooltip: None,
            padding_left: None,
            padding_right: Some(true),
            data: None,
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
    // The runtime is checked once and reused (see `pepper_sema::checked`),
    // unless the document is part of it.
    let on_runtime = pepper_sema::checked::runtime_files(program).filter(|in_runtime| !in_runtime[0]).and_then(|in_runtime| {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| pepper_sema::checked::on_checked_runtime(program, &in_runtime, pepper_sema::checked::Build::Document, None))).ok()
    });
    let module = match on_runtime {
        Some(Ok(module)) => module,
        Some(Err(e)) if e.loc.is_some_and(|l| l.file == FileId(0)) => return Err(e),
        _ => merged(program)?,
    };
    // Run the sema passes under a panic guard: an LSP must never crash on
    // a user file, so a panicking pass degrades to "no semantic info".
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut m = module;
        pepper_sema::checked::run_passes(&mut m)?;
        Ok(m)
    }));
    match result {
        Ok(Ok(m)) => Ok(m),
        Ok(Err(e)) => Err(e),
        Err(_) => Err(diag::Diagnostic::error("semantic analysis panicked")),
    }
}

/// `program` merged into one sema model as it is: build errors in the
/// document (`program[0]`) are reported; other files that fail to build are
/// skipped.
fn merged(program: &Program) -> Result<SemaModule, diag::Diagnostic> {
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
    Ok(module)
}

/// A dimmed hint over each region of `text` (the document, parsed as
/// `module`) its `[Target(...)]` attributes leave out on the build target,
/// as a diagnostic with the `Unnecessary` tag, which editors show faded.
fn inactive_hints(text: &str, module: &ast::Module) -> Vec<Diagnostic> {
    let os = match pepper_sema::passes::platform::target_os().as_str() {
        "windows" => "Windows".to_string(),
        "linux" => "Linux".to_string(),
        "macos" => "macOS".to_string(),
        other => other.to_string(),
    };
    let target = format!("{} {}", os, pepper_sema::passes::platform::target_arch());
    platforms::inactive_regions(text, module)
        .into_iter()
        .map(|span| Diagnostic {
            range: span_to_range(text, span),
            severity: Some(DiagnosticSeverity::HINT),
            tags: Some(vec![DiagnosticTag::UNNECESSARY]),
            source: Some("pepper".to_string()),
            message: format!("inactive: not compiled for this target ({})", target),
            ..Default::default()
        })
        .collect()
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
            documents: Arc::new(Documents::default()),
            conversion_hints: AtomicBool::new(true),
            parameter_hints: AtomicBool::new(true),
            watches_files: AtomicBool::new(false),
        }
    }

    fn doc(&self, uri: &Url) -> Option<String> {
        self.documents.text(uri)
    }

    /// What requests read about `uri`: first, when a file its analysis read
    /// changed on disk, a fresh analysis is scheduled. Until it passes,
    /// requests answer from the current text without sema, since the last
    /// passed analysis would place and describe the changed files' names
    /// as they were.
    fn view(&self, uri: &Url) -> Option<View> {
        if let Some(analysis) = self.documents.refresh(uri) {
            schedule_analysis(self.client.clone(), self.documents.clone(), analysis, Duration::ZERO);
        }
        let mut view = self.documents.view(uri)?;
        if view.ready.as_ref().is_some_and(|(ready, _)| !ready.is_current()) {
            view.ready = None;
        }
        Some(view)
    }

    /// `f()` under `guarded`, logged to the editor's output (the "Pepper
    /// Language Server" channel) when it takes longer than `SLOW_REQUEST`.
    async fn answer<R>(&self, method: &str, f: impl FnOnce() -> Option<R>) -> Option<R> {
        let start = Instant::now();
        let result = guarded(f).flatten();
        let elapsed = start.elapsed();
        if elapsed > SLOW_REQUEST {
            self.client.log_message(MessageType::WARNING, format!("{} took {} ms", method, elapsed.as_millis())).await;
        }
        result
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

    /// Diagnostics for the text `analysis` is of: parse errors (precise),
    /// then sema's. Runs sema, which takes seconds: only the background
    /// analysis calls this.
    fn diagnostics(analysis: &Analysis) -> Vec<Diagnostic> {
        let mut diags = vec![];
        let (uri, text) = (&analysis.uri, &analysis.text);
        // A parse error, or one found after parsing (a late import, `T*`
        // outside an extern).
        let parsed = pepper_parser::parser::parse_source_diag(text);
        match &parsed {
            Err(d) => diags.push(lsp_diagnostic(d, uri, &[(uri.as_str(), text)])),
            // Warnings (deprecated syntax) come with quick fixes; see `quick_fixes`.
            Ok(module) => {
                diags.extend(module.warnings.iter().map(|w| lsp_diagnostic(w, uri, &[(uri.as_str(), text)])));
                diags.extend(inactive_hints(text, module));
            }
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
        diags
    }

    /// Hover at `offset` in document `uri`: from the newest analysis whose
    /// sema passed when the name at `offset` is outside what changed since,
    /// else from the current text without sema.
    fn hover(&self, uri: &Url, offset: usize) -> Option<Hover> {
        let view = self.view(uri)?;
        if let Some((ready, edits)) = &view.ready {
            // An answer from an older analysis says so: a declaration edited
            // since may read differently.
            let note = edits.is_some().then(|| {
                if view.latest.is_checked() {
                    "_From before your latest edit, which does not check yet._"
                } else {
                    "_Checking your latest edit; this may be out of date._"
                }
            });
            let at = |ready: &Analysis, at| {
                let hover = Self::hover_at(uri, &ready.text, ready.program().ok(), ready.sema_model(), at)?;
                Some(match (note, hover.contents) {
                    (Some(note), HoverContents::Markup(m)) => Hover {
                        contents: HoverContents::Markup(MarkupContent {
                            kind: m.kind,
                            value: format!("{}\n\n---\n\n{}", m.value, note),
                        }),
                        range: hover.range,
                    },
                    (_, contents) => Hover { contents, range: hover.range },
                })
            };
            match edits {
                None => return at(ready, offset),
                Some(edits) => {
                    let moved = |mut hover: Hover| {
                        if let Some(range) = hover.range {
                            hover.range = Some(edits.range_to_new(&ready.text, view.text(), range)?);
                        }
                        Some(hover)
                    };
                    if let Some(old) = edits.to_old(view.text(), offset)
                        && let Some(hover) = at(ready, old).and_then(moved)
                    {
                        return Some(hover);
                    }
                }
            }
        }
        let latest = &view.latest;
        Self::hover_at(uri, &latest.text, latest.program().ok(), None, offset)
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
        // A `match` arm's case (`Red =>`).
        if let Some(pattern) = case_pattern_at(&ast, offset)
            && let Some(owner) =
                program.and_then(|p| pattern_enum(p, pattern)).or(pattern.qualifier.as_ref().map(|q| q.name.as_str()))
        {
            let rendered =
                sema.and_then(|m| enum_case_named(m, owner, &pattern.case)).unwrap_or_else(|| format!("{}.{}", owner, pattern.case));
            return Some(Hover { contents: md(format!("`{}` — `{}`", pattern.case, rendered)), range: None });
        }
        let typer = infer::Typer::new(&ast, program, sema);
        let imported = |(spelled, target): (String, imports::Target)| {
            let program = program?;
            let value = match target {
                // A module-scope variable another file initializes.
                imports::Target::Declaration { file, mut symbol } if symbol.ty == "unknown" => {
                    if let Some(ty) = typer.global_type(file, symbol.name_span) {
                        symbol.ty = ty.to_string();
                    }
                    let from = if file == 0 { String::new() } else { format!("\n\nfrom `{}`", file_label(&program.files[file].name)) };
                    with_doc(format!("`{}` — `{}`{}", spelled, symbol.ty, from), declaration_doc_at(program, file, symbol.name_span))
                }
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
                imports::in_imports(program, &ast, offset).or_else(|| imports::named_type(program, &ast, offset))
        {
            return imported(found);
        }
        // A name that resolved to one overload of a set shows that member.
        if let Some(program) = program
            && let Some((function, others)) = sema.and_then(|m| overload_at(m, offset))
        {
            return Some(Hover { contents: md(overload_hover(program, function, others)), range: None });
        }
        // A name where it is declared: a type, function, member, local or
        // parameter, with its doc comment.
        // A built-in type (`int`, `u8`), which no file declares.
        if let Some(ty) = imports::type_at(&ast, offset)
            && let name = ty.name.trim_end_matches(['*', '[', ']'])
            && pepper_sema::type_name::INTEGRAL_TYPES.contains(name)
        {
            return Some(Hover { contents: md(format!("`{}` — built-in type", name)), range: None });
        }
        // The built-in constraint `T: Shared`, which no file declares.
        if let Some(ty) = imports::type_at(&ast, offset)
            && pepper_sema::passes::constraints::is_shared_bound(&pepper_sema::TypeName::new(&ty.name))
            && program.is_none_or(|p| imports::named_type(p, &ast, offset).is_none())
        {
            let value = "`Shared` — built-in constraint\n\nThe type is thread-safe: a `[Shared]` struct, a `shared` function type, or a value type.";
            return Some(Hover { contents: md(value.to_string()), range: None });
        }
        if let Some(symbol) = generic_param_used(&ast, program, offset).or_else(|| tuple_label_at(&ast, text, offset)) {
            return Some(Hover { contents: md(format!("`{}` — `{}`", symbol.name, symbol.ty)), range: None });
        }
        // A case a pattern names, or a name it binds.
        match typer.pattern_at(offset) {
            Some(infer::PatternHit::Case(found)) => {
                return Some(Hover { contents: md(found_hover(program, text, &found)), range: None });
            }
            Some(infer::PatternHit::Binding { name, ty, .. }) => {
                let ty = ty.map_or_else(|| "unknown".to_string(), |t| t.to_string());
                return Some(Hover { contents: md(format!("`{}` — `{}`", name, ty)), range: None });
            }
            None => {}
        }
        if let Some((label, _, ty)) = label_at(&ast, text, offset) {
            let ty = match ty {
                Ok(ty) => Some(ty),
                Err(value) => typer.type_of(value, offset),
            };
            let ty = ty.map_or_else(|| "unknown".to_string(), |t| t.to_string());
            return Some(Hover { contents: md(format!("`{}` — `{}`", label, ty)), range: None });
        }
        if let Some((symbol, owner)) = declared_at(&ast, offset) {
            let doc = program.and_then(|p| match &owner {
                Some(owner) => member_doc(p, Some(owner), &symbol.name),
                None => declaration_doc_at(p, 0, symbol.name_span),
            });
            let mut ty = symbol_type(sema, &symbol);
            if ty == "unknown"
                && let Some(t) = typer.local_type_of(&symbol)
            {
                ty = t.to_string();
            }
            let head = format!("`{}` — `{}`", symbol.name, ty);
            return Some(Hover { contents: md(with_doc(head, doc)), range: None });
        }
        // A type argument in a member's name (`T` of `copies.copy<T>(x)`).
        if let Some(name) = type_argument_at(&ast, text, offset) {
            if let Some((symbol, _)) = generic_param_at(&ast, offset, |p| p.name == name) {
                return Some(Hover { contents: md(format!("`{}` — `{}`", symbol.name, symbol.ty)), range: None });
            }
            if let Some(program) = program
                && let Some(target) = imports::declaration_named(program, &name)
            {
                return imported((name, target));
            }
        }
        // `String.format(...)`, which the parser lowers.
        if let Some(name) = string_format_at(text, offset)
            && !names_at(&ast, offset)
        {
            if name == "format" {
                let value = "`format` — `static format(format: String, values...): String`\n\nBuilt in: the format string with each `{index}` replaced by that value, formatted as in an interpolated string.";
                return Some(Hover { contents: md(value.to_string()), range: None });
            }
            return imported(("String".to_string(), imports::declaration_named(program?, "String")?));
        }
        let expr = find_expr(&ast, offset)?;

        // None at module scope (a variable's initializer).
        let enclosing_struct = body_at(&ast, offset).and_then(|(_, s)| s);
        let locals: Vec<Symbol> = scope_locals(&ast, offset);
        let globals = collect_globals(&ast);
        let struct_members: Vec<Symbol> = enclosing_struct.map(collect_struct_members).unwrap_or_default();
        // A bare member of `this` (in an extension's method) is no global.
        let bare_member = sema.and_then(|m| pepper_sema::member_lookup::member_at(m, FileId(0), offset)).is_some();
        let is_local = |id: &str| bare_member || locals.iter().chain(&struct_members).chain(&globals).any(|s| s.name == id);
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
        let symbol_type = |s: &Symbol| symbol_type(sema, s);
        // Docs of member `name` of `lhs`: its type when the hover can tell
        // (`this`, a typed variable, a type name for a static call).
        let member_docs = |lhs: &ast::Expression, name: &str| {
            let program = program?;
            let owner = match lhs {
                ast::Expression::SymbolRef { id, .. } if id == "this" => {
                    enclosing_struct.map(|s| s.name.clone()).or_else(|| extended_at(&ast, offset))
                }
                ast::Expression::SymbolRef { id, .. } => {
                    match locals.iter().rev().chain(&struct_members).chain(&globals).find(|s| s.name == *id) {
                        Some(symbol) => type_base_name(&symbol_type(symbol)),
                        None => Some(id.clone()),
                    }
                }
                // A field's field (`worker.core.state`): the inner field's type.
                ast::Expression::MemberAccess { name_span, .. } => sema
                    .and_then(|m| pepper_sema::member_lookup::field_type(m, FileId(0), name_span.start))
                    .and_then(|t| type_base_name(&t.to_string())),
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
                // A type named as a value: the owner of a static call
                // (`i8.parse(...)`, `T.parse(...)`).
                if typer.named_type(expr, offset).is_some() {
                    if pepper_sema::type_name::INTEGRAL_TYPES.contains(id.as_str()) {
                        return Some(Hover { contents: md(format!("`{}` — built-in type", id)), range: None });
                    }
                    if let Some((symbol, _)) = generic_param_at(&ast, offset, |p| p.name == *id) {
                        return Some(Hover { contents: md(format!("`{}` — `{}`", symbol.name, symbol.ty)), range: None });
                    }
                }
                // A bare member of `this` the document cannot see (in an
                // extension's method), by the type sema gave `this`.
                if !locals.iter().chain(&struct_members).any(|s| s.name == *id)
                    && let Some(program) = program
                    && let Some(member) = sema.and_then(|m| pepper_sema::member_lookup::member_at(m, FileId(0), offset))
                {
                    let value = match member {
                        pepper_sema::member_lookup::Member::Method(m) => overload_hover(program, m, 0),
                        pepper_sema::member_lookup::Member::Field(f) => {
                            let owner = extended_at(&ast, offset);
                            with_doc(format!("`{}` — `{}`", id, f.ty), member_doc(program, owner.as_deref(), id))
                        }
                    };
                    return Some(Hover { contents: md(value), range: None });
                }
                let rendered = locals.iter().rev().find(|s| s.name == *id)
                    .or_else(|| struct_members.iter().find(|s| s.name == *id))
                    .or_else(|| globals.iter().find(|s| s.name == *id))
                    .map(symbol_type)
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
                    .filter(|t| t != "unknown")
                    .or_else(|| typer.symbol_type(id, offset).map(|t| t.to_string()));
                // A method of `this` sema did not check (in generic code).
                if rendered.is_none()
                    && let Some(found) = typer.bare_member(id, offset)
                {
                    return Some(Hover { contents: md(found_hover(program, text, &found)), range: None });
                }
                if rendered.is_none() && id == "print" {
                    return Some(Hover { contents: md(PRINT_HOVER.to_string()), range: None });
                }
                let rendered = rendered.unwrap_or_else(|| "unknown".to_string());
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
                // A method (`a.count` of `a.count()`), as its type declares it;
                // an enum's case is shown below.
                let is_case = sema.and_then(|m| enum_case_of(m, lhs, name)).or_else(|| enum_case_in(&ast, lhs, name)).is_some();
                if let Some(program) = program
                    && !is_case
                    && let Some(pepper_sema::member_lookup::Member::Method(m)) =
                        sema.and_then(|s| pepper_sema::member_lookup::member_at(s, FileId(0), offset))
                {
                    return Some(Hover { contents: md(overload_hover(program, m, 0)), range: None });
                }
                let rendered = if is_this(expr) {
                    struct_members.iter().find(|s| s.name == *name).map(|s| s.ty.clone())
                        .or_else(|| {
                            sema
                                .and_then(|m| enclosing_struct.and_then(|s| find_sema_struct(m, &s.name)))
                                .and_then(|st| struct_member_type(st, name))
                        })
                        // In an extension's method, by the extended type.
                        .or_else(|| sema.and_then(|m| pepper_sema::member_lookup::field_type(m, FileId(0), offset)).map(|t| t.to_string()))
                        .or_else(|| typer.member_access(lhs, name, offset).map(|f| f.describe()))
                        .unwrap_or_else(|| "unknown".to_string())
                } else if let Some(case) = sema.and_then(|m| enum_case_of(m, lhs, name)).or_else(|| enum_case_in(&ast, lhs, name)) {
                    case
                } else {
                    // The field of the owner's type, as sema or the syntax
                    // types the owner; failing that, any struct's field of
                    // that name.
                    let typed = typer.member_access(lhs, name, offset);
                    if let Some(found) = typed.as_ref().filter(|f| matches!(f.kind, infer::Kind::Method(_))) {
                        return Some(Hover { contents: md(found_hover(program, text, found)), range: None });
                    }
                    sema.and_then(|m| pepper_sema::member_lookup::field_type(m, FileId(0), offset))
                        .map(|t| t.to_string())
                        .or_else(|| typed.map(|f| f.describe()))
                        .or_else(|| sema.and_then(|m| m.structs.iter().find_map(|st| struct_member_type(st, name))))
                        .unwrap_or_else(|| "unknown".to_string())
                };
                Some(Hover { contents: md(with_doc(format!("`.{}` — `{}`", name, rendered), member_docs(lhs, name))), range: None })
            }
            ast::Expression::FunctionCall { function, .. } => match &**function {
                ast::Expression::SymbolRef { id, .. } => {
                    let rendered = globals.iter().find(|s| s.name == *id).map(|s| s.ty.clone())
                        .or_else(|| sema.and_then(|m| m.functions.iter().find(|f| f.name == *id).map(|f| f.ty.to_string())))
                        // A local or field holding a function.
                        .or_else(|| typer.symbol_type(id, offset).map(|t| t.to_string()));
                    // A method of `this` sema did not check (in generic code).
                    if rendered.is_none()
                        && let Some(found) = typer.bare_member(id, offset)
                    {
                        return Some(Hover { contents: md(found_hover(program, text, &found)), range: None });
                    }
                    let rendered = rendered.unwrap_or_else(|| "unknown".to_string());
                    Some(Hover { contents: md(with_doc(format!("`{}` — `{}`", id, rendered), global_doc(id))), range: None })
                }
                ast::Expression::MemberAccess { lhs, name, .. } => {
                    // The method the owner's type has, as declared.
                    if let Some(program) = program
                        && let Some(pepper_sema::member_lookup::Member::Method(m)) =
                            sema.and_then(|s| pepper_sema::member_lookup::member_at(s, FileId(0), offset))
                    {
                        return Some(Hover { contents: md(overload_hover(program, m, 0)), range: None });
                    }
                    // The member as the syntax types the owner (in generic
                    // code sema did not check, or a static call).
                    if let Some(found) = typer.member_access(lhs, name, offset) {
                        return Some(Hover { contents: md(found_hover(program, text, &found)), range: None });
                    }
                    let rendered = sema
                        .and_then(|m| m.structs.iter().find_map(|st| struct_member_type(st, name)))
                        .or_else(|| sema.and_then(|m| enum_method_signature(m, name)))
                        .unwrap_or_else(|| "unknown".to_string());
                    Some(Hover { contents: md(with_doc(format!("`.{}` — `{}`", name, rendered), member_docs(lhs, name))), range: None })
                }
                _ => None,
            },
            _ => None,
        }
    }

    /// Go-to-definition at `offset` in document `uri`, answered as
    /// [`PepperLsp::hover`] is. A place in the document found in an older
    /// text moves with the edits since.
    fn definition(&self, uri: &Url, offset: usize) -> Option<Vec<Location>> {
        let view = self.view(uri)?;
        if let Some((ready, edits)) = &view.ready {
            let at = |ready: &Analysis, at| Self::definition_at(uri, &ready.text, ready.program().ok(), ready.sema_model(), at);
            match edits {
                None => return at(ready, offset),
                Some(edits) => {
                    let moved = |mut location: Location| {
                        if location.uri == *uri {
                            location.range = edits.range_to_new(&ready.text, view.text(), location.range)?;
                        }
                        Some(location)
                    };
                    if let Some(old) = edits.to_old(view.text(), offset)
                        && let Some(locations) = at(ready, old)
                        && let Some(locations) = locations.into_iter().map(moved).collect::<Option<Vec<_>>>()
                    {
                        return Some(locations);
                    }
                }
            }
        }
        let latest = &view.latest;
        Self::definition_at(uri, &latest.text, latest.program().ok(), None, offset)
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
                imports::in_imports(program, &ast, offset).or_else(|| imports::named_type(program, &ast, offset))
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
        let typer = infer::Typer::new(&ast, program, sema);
        // A case a pattern names goes to the case; a name it binds, to itself.
        match typer.pattern_at(offset) {
            Some(infer::PatternHit::Case(found)) => {
                return file_location(uri, text, program, found.file, found.name_span()?).map(|l| vec![l]);
            }
            Some(infer::PatternHit::Binding { span, .. }) => {
                return Some(vec![Location::new(uri.clone(), span_to_range(text, span))]);
            }
            None => {}
        }
        // `String.format(...)`, which the parser lowers: both names go to
        // `String`.
        if string_format_at(text, offset).is_some()
            && !names_at(&ast, offset)
            && let Some(program) = program
        {
            return imported(("String".to_string(), imports::declaration_named(program, "String")?));
        }
        // A tuple's label where it is written.
        if let Some((_, span, _)) = label_at(&ast, text, offset) {
            return Some(vec![Location::new(uri.clone(), span_to_range(text, span))]);
        }
        // A type argument in a member's name (`T` of `copies.copy<T>(x)`).
        if let Some(name) = type_argument_at(&ast, text, offset) {
            if let Some((symbol, _)) = generic_param_at(&ast, offset, |p| p.name == name) {
                return Some(vec![Location::new(uri.clone(), span_to_range(text, symbol.name_span))]);
            }
            if let Some(program) = program
                && let Some(target) = imports::declaration_named(program, &name)
            {
                return imported((name, target));
            }
        }
        // A name where it is declared goes to itself; a generic parameter
        // used as a type, to the parameter.
        if let Some((symbol, _)) = declared_at(&ast, offset)
            .or_else(|| generic_param_used(&ast, program, offset).or_else(|| tuple_label_at(&ast, text, offset)).map(|s| (s, None))) {
            return Some(vec![Location::new(uri.clone(), span_to_range(text, symbol.name_span))]);
        }
        // A `match` arm's case (`Red =>`), declared in any file.
        if let Some(program) = program
            && let Some(pattern) = case_pattern_at(&ast, offset)
            && let Some(owner) = pattern_enum(program, pattern)
            && let Some((file, span)) = enum_case_declared(program, owner, &pattern.case)
        {
            let f = &program.files[file];
            let target_uri = if file == 0 { uri.clone() } else { Url::from_file_path(&f.name).ok()? };
            return Some(vec![Location::new(target_uri, span_to_range(&f.source, span))]);
        }
        // An enum's case (`Backend.Automatic`), declared in any file.
        if let Some(program) = program
            && let Some(ast::Expression::MemberAccess { lhs, name, name_span, .. }) = find_expr(&ast, offset)
            && name_span.start <= offset
            && let Some(id) = enum_named(lhs)
            && let Some((file, span)) = enum_case_declared(program, id, name)
        {
            let f = &program.files[file];
            let target_uri = if file == 0 { uri.clone() } else { Url::from_file_path(&f.name).ok()? };
            return Some(vec![Location::new(target_uri, span_to_range(&f.source, span))]);
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

        // None at module scope (a variable's initializer).
        let enclosing_struct = body_at(&ast, offset).and_then(|(_, s)| s);
        let locals: Vec<Symbol> = scope_locals(&ast, offset);
        let globals = collect_globals(&ast);
        let struct_members: Vec<Symbol> = enclosing_struct.map(collect_struct_members).unwrap_or_default();
        // A bare member of `this` (in an extension's method) is no global.
        let bare_member = sema.and_then(|m| pepper_sema::member_lookup::member_at(m, FileId(0), offset)).is_some();
        let is_local = |id: &str| bare_member || locals.iter().chain(&struct_members).chain(&globals).any(|s| s.name == id);
        if let Some(program) = program
            && let Some(found) = imports::in_expression(program, &ast, expr, is_local)
        {
            return imported(found);
        }

        let target_span = match expr {
            ast::Expression::SymbolRef { id, .. } => locals.iter().rev().find(|s| s.name == *id)
                .or_else(|| struct_members.iter().find(|s| s.name == *id))
                .or_else(|| globals.iter().find(|s| s.name == *id))
                .map(|s| s.name_span),
            ast::Expression::MemberAccess { name, .. } if is_this(expr) => {
                enclosing_struct.and_then(|s| s.fields.iter().find(|f| f.name == *name)).map(|f| f.name_span)
            }
            _ => None,
        };
        if let Some(span) = target_span {
            return Some(vec![Location::new(uri.clone(), span_to_range(text, span))]);
        }
        // A type parameter named as a value (`T.parse(...)`).
        if let ast::Expression::SymbolRef { id, .. } = expr
            && typer.named_type(expr, offset).is_some()
            && let Some((symbol, _)) = generic_param_at(&ast, offset, |p| p.name == *id)
        {
            return Some(vec![Location::new(uri.clone(), span_to_range(text, symbol.name_span))]);
        }
        // What the syntax finds where sema has no answer: a member of an
        // owner it types (in generic code sema did not check, or a static
        // call), or a member of `this` named bare.
        let found = match expr {
            ast::Expression::SymbolRef { id, .. } => typer.bare_member(id, offset),
            ast::Expression::MemberAccess { lhs, name, name_span, .. } if name_span.start <= offset => {
                typer.member_access(lhs, name, offset)
            }
            _ => None,
        }?;
        // A tuple's label: where the document writes a tuple type or value
        // with the owner's labels.
        if let infer::Kind::Element(label, _) = &found.kind {
            let span = label_declared(&ast, text, &typer.member_owner_labels(expr, offset)?, label)?;
            return Some(vec![Location::new(uri.clone(), span_to_range(text, span))]);
        }
        file_location(uri, text, program, found.file, found.name_span()?).map(|l| vec![l])
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
                // Its constants are listed beside it, as variables.
                ast::Declaration::Static(_) => {}
            }
        }
        Some(out)
    }

    /// The parameter names (`width = `) a call's argument list can name at
    /// `offset`, where an argument starts: right after its `(` or a `,`.
    /// Each parameter not yet named, and its `[Alias]` names.
    fn argument_names(&self, uri: &Url, text: &str, offset: usize) -> Vec<CompletionItem> {
        let before = text.get(..offset).unwrap_or_default();
        let head = before.trim_end_matches(|c: char| c.is_ascii_alphanumeric() || c == '_');
        // A number is not a name being typed.
        let typed = &before[head.len()..];
        if !head.trim_end().ends_with(['(', ',']) || typed.starts_with(|c: char| c.is_ascii_digit()) {
            return vec![];
        }
        // `f(a, |)` does not parse until the argument is written.
        let Some(ast) = parse_source(uri.as_str(), text)
            .ok()
            .or_else(|| parse_source(uri.as_str(), &format!("{}_{}", before, &text[offset..])).ok())
        else {
            return vec![];
        };
        let mut call: Option<(&ast::Expression, &[ast::Expression], ast::Span)> = None;
        infer::each(&ast, |item| {
            if let infer::Item::Expression(ast::Expression::FunctionCall { function, arguments, span }) = item
                && function.span().end < offset
                && offset < span.end
                && call.is_none_or(|(_, _, inner)| inner.start <= span.start)
            {
                call = Some((function, arguments, *span));
            }
        });
        let Some((function, arguments, _)) = call else { return vec![] };
        let view = self.view(uri);
        let program = view.as_ref().and_then(|v| {
            v.latest.program().ok().or_else(|| v.ready.as_ref().and_then(|(ready, _)| ready.program().ok()))
        });
        let typer = infer::Typer::new(&ast, program, None);
        let callees: Vec<&ast::FunctionDecl> = match function {
            ast::Expression::SymbolRef { id, .. } => typer.callees_named(id, offset),
            ast::Expression::MemberAccess { lhs, name, .. } => match typer.member_access(lhs, name, offset) {
                Some(infer::Found { kind: infer::Kind::Method(f), .. }) => vec![f],
                _ => vec![],
            },
            _ => vec![],
        };
        let named: Vec<&str> = arguments
            .iter()
            .filter_map(|a| match a {
                ast::Expression::NamedArgument { name, name_span, .. } if name_span.end < offset || name_span.start > offset => {
                    Some(name.as_str())
                }
                _ => None,
            })
            .collect();
        let mut items: Vec<CompletionItem> = vec![];
        for f in callees {
            let params: Vec<Parameter> = f
                .parameters
                .iter()
                .filter(|p| p.name != "this")
                .map(|p| Parameter {
                    name: p.name.strip_prefix("this.").unwrap_or(&p.name).to_string(),
                    has_default: p.default_value.is_some(),
                    ty: pepper_sema::TypeName::auto(),
                })
                .collect();
            let aliases = pepper_sema::passes::named_arguments::other_names(&f.attributes, &params, FileId(0));
            let names = params
                .iter()
                .zip(f.parameters.iter().filter(|p| p.name != "this"))
                .map(|(p, decl)| (p.name.clone(), decl.type_name.to_string(), None))
                .chain(aliases.into_iter().filter_map(Result::ok).filter(|o| !o.deprecated).map(|o| {
                    (o.name, String::new(), Some(params[o.parameter].name.clone()))
                }));
            for (name, ty, alias_of) in names {
                if named.contains(&name.as_str()) || items.iter().any(|i| i.label == name) {
                    continue;
                }
                items.push(CompletionItem {
                    label: name.clone(),
                    kind: Some(CompletionItemKind::FIELD),
                    detail: Some(match alias_of {
                        Some(of) => format!("another name for '{}'", of),
                        None => format!("{}: {}", name, ty),
                    }),
                    insert_text: Some(format!("{} = ", name)),
                    sort_text: Some(format!("0{}", name)),
                    ..Default::default()
                });
            }
        }
        items
    }

    /// Completion at `offset`: keywords plus local/struct/global symbols.
    fn completion(&self, uri: &Url, offset: usize) -> Vec<CompletionItem> {
        let mut items = vec![];
        for kw in KEYWORDS {
            items.push(CompletionItem { label: kw.to_string(), kind: Some(CompletionItemKind::KEYWORD), ..Default::default() });
        }
        if let Some(text) = self.doc(uri) {
            items.extend(self.argument_names(uri, &text, offset));
        }
        if let Some(text) = self.doc(uri)
            && let Ok(ast) = parse_source(uri.as_str(), &text).or_else(|e| parse_after_dot(uri, &text, offset).ok_or(e))
        {
            let scope = body_at(&ast, offset);
            let locals: Vec<Symbol> = scope_locals(&ast, offset);
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
        let parameters = params
            .initialization_options
            .as_ref()
            .and_then(|o| o.pointer("/inlayHints/parameterNames"))
            .and_then(|v| v.as_bool())
            .unwrap_or(true);
        self.parameter_hints.store(parameters, Ordering::Relaxed);
        // `-D` options to analyze with, as the compiler takes them; one that
        // does not parse is left out.
        let build_options = params
            .initialization_options
            .as_ref()
            .and_then(|o| o.pointer("/buildOptions"))
            .and_then(|v| v.as_array())
            .map(|options| {
                options
                    .iter()
                    .filter_map(|o| o.as_str())
                    .filter_map(|o| pepper_sema::passes::platform::parse_build_option(o).ok())
                    .collect()
            })
            .unwrap_or_default();
        pepper_sema::passes::platform::set_default_build_options(build_options);
        let watches = params
            .capabilities
            .workspace
            .as_ref()
            .and_then(|w| w.did_change_watched_files.as_ref())
            .and_then(|w| w.dynamic_registration)
            .unwrap_or(false);
        self.watches_files.store(watches, Ordering::Relaxed);
        let refreshes_hints = params
            .capabilities
            .workspace
            .as_ref()
            .and_then(|w| w.inlay_hint.as_ref())
            .and_then(|h| h.refresh_support)
            .unwrap_or(false);
        self.documents.refreshes_hints.store(refreshes_hints, Ordering::Relaxed);
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
                name: "pep-lsp".to_string(),
                version: Some(env!("CARGO_PKG_VERSION").to_string()),
            }),
        })
    }

    async fn shutdown(&self) -> LspResult<()> {
        Ok(())
    }

    async fn initialized(&self, _: InitializedParams) {
        let started = format!("pep-lsp {} started", env!("CARGO_PKG_VERSION"));
        self.client.log_message(MessageType::INFO, started).await;
        // Analyses read imports from disk: ask the client, whatever editor
        // it is, to report `.pep` files that change.
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

    /// `.pep` files changed on disk (the client watches them for the
    /// server, see `initialized`): each open document whose analysis read
    /// one, or failed to load it, is analyzed again in the background (every
    /// one when a file was created or deleted). A request also notices a
    /// changed file on its own ([`Analysis::is_current`]); this covers the
    /// diagnostics, and imports a new file resolves differently.
    async fn did_change_watched_files(&self, params: DidChangeWatchedFilesParams) {
        let changed: Vec<PathBuf> = params.changes.iter().filter_map(|c| c.uri.to_file_path().ok()).collect();
        let added = params.changes.iter().any(|c| c.typ != FileChangeType::CHANGED);
        for analysis in self.documents.forget(&changed, added) {
            schedule_analysis(self.client.clone(), self.documents.clone(), analysis, SETTLE);
        }
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let analysis = self.documents.set(&params.text_document.uri, params.text_document.text);
        schedule_analysis(self.client.clone(), self.documents.clone(), analysis, Duration::ZERO);
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        let Some(change) = params.content_changes.into_iter().next() else { return };
        let analysis = self.documents.set(&params.text_document.uri, change.text);
        schedule_analysis(self.client.clone(), self.documents.clone(), analysis, SETTLE);
    }

    async fn did_close(&self, params: DidCloseTextDocumentParams) {
        let uri = params.text_document.uri.clone();
        self.documents.close(&uri);
        self.client.publish_diagnostics(uri, vec![], None).await;
    }

    // Each request computes under `guarded`: a bug that panics on one
    // document answers that request with nothing instead of ending the server.
    async fn inlay_hint(&self, params: InlayHintParams) -> LspResult<Option<Vec<InlayHint>>> {
        let conversions = self.conversion_hints.load(Ordering::Relaxed);
        let parameters = self.parameter_hints.load(Ordering::Relaxed);
        if !conversions && !parameters {
            return Ok(None);
        }
        let uri = params.text_document.uri;
        let range = params.range;
        Ok(self
            .answer("inlayHint", || {
                // The newest passed analysis's hints, moved by the edits
                // since; none inside what changed.
                let view = self.view(&uri)?;
                let (ready, edits) = view.ready.as_ref()?;
                // Each conversion's `To(` and `)` move as one span, so an
                // edit inside it drops both.
                let sema = ready.sema_model()?;
                let conversion = if conversions { conversion_hints(&ready.text, sema) } else { vec![] };
                let parameter = if parameters { parameter_hints(&ready.text, sema) } else { vec![] };
                let moved = |mut hint: InlayHint| {
                    if let Some(edits) = edits {
                        let span = edits.line_range_to_new(&ready.text, view.text(), Range::new(hint.position, hint.position))?;
                        hint.position = span.start;
                    }
                    Some(hint)
                };
                let parameter: Vec<InlayHint> = parameter.into_iter().filter_map(moved).collect();
                let hints: Vec<InlayHint> = conversion
                    .chunks(2)
                    .filter_map(|pair| {
                        let [open, close] = pair else { return None };
                        let (mut open, mut close) = (open.clone(), close.clone());
                        if let Some(edits) = edits {
                            let span = edits.line_range_to_new(&ready.text, view.text(), Range::new(open.position, close.position))?;
                            (open.position, close.position) = (span.start, span.end);
                        }
                        Some([open, close])
                    })
                    .flatten()
                    .chain(parameter)
                    .filter(|h| h.position >= range.start && h.position <= range.end)
                    .collect();
                Some(hints)
            })
            .await)
    }

    async fn hover(&self, params: HoverParams) -> LspResult<Option<Hover>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        Ok(self
            .answer("hover", || {
                let text = self.doc(&uri)?;
                self.hover(&uri, line_col_to_byte(&text, pos.line, pos.character))
            })
            .await)
    }

    async fn completion(&self, params: CompletionParams) -> LspResult<Option<CompletionResponse>> {
        let uri = params.text_document_position.text_document.uri;
        let pos = params.text_document_position.position;
        Ok(self
            .answer("completion", || {
                let text = self.doc(&uri)?;
                let offset = line_col_to_byte(&text, pos.line, pos.character);
                Some(CompletionResponse::Array(self.completion(&uri, offset)))
            })
            .await)
    }

    async fn goto_definition(&self, params: GotoDefinitionParams) -> LspResult<Option<GotoDefinitionResponse>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        Ok(self
            .answer("definition", || {
                let text = self.doc(&uri)?;
                self.definition(&uri, line_col_to_byte(&text, pos.line, pos.character)).map(Into::into)
            })
            .await)
    }

    async fn code_action(&self, params: CodeActionParams) -> LspResult<Option<CodeActionResponse>> {
        let uri = params.text_document.uri;
        Ok(self
            .answer("codeAction", || {
                // The current text's sema, when the background analysis has
                // run it, serves both kinds of fix: those a diagnostic carries
                // (a `Copyable` skeleton) and the missing arms of a `match`.
                // Until then, only the parser's and the program's fixes.
                let view = self.view(&uri)?;
                let analysis = match &view.ready {
                    Some((ready, None)) if view.latest.sema_if_done().is_none() => ready,
                    _ => &view.latest,
                };
                let text = &analysis.text;
                let program = analysis.program().ok();
                let sema = analysis.sema_if_done();
                let diagnostics = fixable_diagnostics(text, program, sema);
                let mut actions = quick_fixes(&uri, text, &diagnostics, params.range);
                if let (Some(program), Some(Err(error))) = (program, sema) {
                    actions.extend(missing_arms_fix(&uri, text, program, error, params.range));
                }
                (!actions.is_empty()).then_some(actions)
            })
            .await)
    }

    async fn document_symbol(&self, params: DocumentSymbolParams) -> LspResult<Option<DocumentSymbolResponse>> {
        let uri = params.text_document.uri;
        Ok(self.answer("documentSymbol", || self.document_symbols(&uri).map(DocumentSymbolResponse::Nested)).await)
    }
}

/// How long a document's text must stay unchanged before the server
/// analyzes it: typing does not start a sema run per keystroke.
const SETTLE: Duration = Duration::from_millis(250);

/// A request that takes longer is logged to the editor's output.
const SLOW_REQUEST: Duration = Duration::from_millis(200);

/// Analyze `analysis` in the background once its text has stayed the
/// document's for `settle`: run sema off the async workers, let requests
/// answer from it (`Documents::finished`), log how long it took, and publish
/// its diagnostics if its text is still the document's. One analysis runs
/// at a time, and one whose text was edited before its turn is skipped.
fn schedule_analysis(client: Client, documents: Arc<Documents>, analysis: Arc<Analysis>, settle: Duration) {
    // Outside a runtime (unit tests), the caller analyzes itself.
    let Ok(runtime) = tokio::runtime::Handle::try_current() else { return };
    runtime.spawn(async move {
        tokio::time::sleep(settle).await;
        let _turn = documents.running.lock().await;
        if !documents.is_latest(&analysis) {
            return;
        }
        let start = Instant::now();
        let diagnostics = {
            let (documents, analysis) = (documents.clone(), analysis.clone());
            tokio::task::spawn_blocking(move || analyze(&documents, &analysis)).await.ok().flatten()
        };
        let file = analysis.uri.path_segments().and_then(|mut s| s.next_back()).unwrap_or_default().to_string();
        let files = analysis.loaded_program().map_or(0, |p| p.files.len());
        let outcome = match analysis.sema_if_done() {
            Some(Ok(_)) => "passed",
            Some(Err(_)) => "found an error",
            None => "did not load",
        };
        // A file analyzed for another OS than the build target's says so.
        let os = analysis.os();
        let as_os = if os == pepper_sema::passes::platform::target_os() { String::new() } else { format!(" as {}", os) };
        let took = format!("analyzed {}{} ({} files): {} in {} ms", file, as_os, files, outcome, start.elapsed().as_millis());
        client.log_message(MessageType::LOG, took).await;
        // Hints come from the newest passed analysis: have the editor ask
        // again now there is one, when it says it can. In a task of its own,
        // so a slow answer holds up no other analysis.
        if analysis.sema_model().is_some() && documents.refreshes_hints.load(Ordering::Relaxed) {
            let client = client.clone();
            tokio::spawn(async move {
                let _ = client.inlay_hint_refresh().await;
            });
        }
        if let Some(diagnostics) = diagnostics
            && documents.is_latest(&analysis)
        {
            client.publish_diagnostics(analysis.uri.clone(), diagnostics, None).await;
            // Closed while they were sent: `did_close`'s clearing may have
            // gone first, so clear again.
            if documents.latest(&analysis.uri).is_none() {
                client.publish_diagnostics(analysis.uri.clone(), vec![], None).await;
            }
        }
    });
}

/// Run sema on `analysis` and compute its diagnostics, under `guarded`;
/// requests answer from it from now on when it passed.
fn analyze(documents: &Documents, analysis: &Arc<Analysis>) -> Option<Vec<Diagnostic>> {
    let diagnostics = guarded(|| PepperLsp::diagnostics(analysis));
    analysis.mark_checked();
    documents.finished(analysis);
    diagnostics
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

/// What `pep-lsp --help` prints. The book's tools/pep-lsp.md documents
/// each option it lists, and `tool_docs_tests` checks that it does.
const HELP: &str = include_str!("help.txt");

/// Answers `--help` and `--version`, and rejects an argument the server
/// does not take: `Some(exit code)` when the server should not start.
fn handle_arguments(args: &[String]) -> Option<i32> {
    for arg in args {
        match arg.as_str() {
            "--stdio" => {}
            "-h" | "--help" => {
                print!("{}", HELP);
                return Some(0);
            }
            "-V" | "--version" => {
                println!("pep-lsp {}", env!("CARGO_PKG_VERSION"));
                return Some(0);
            }
            other => {
                eprintln!("pep-lsp: error: unknown argument '{}'\nusage: pep-lsp [--stdio]; pep-lsp --help lists the options", other);
                return Some(2);
            }
        }
    }
    None
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Some(code) = handle_arguments(&args) {
        std::process::exit(code);
    }
    // The main thread's stack is fixed by the linker, so serve from a
    // thread that has `STACK_SIZE`, as the runtime's workers do.
    let server = std::thread::Builder::new()
        .name("pep-lsp".into())
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
            // A background analysis may still be running: exit now rather
            // than wait for it.
            runtime.shutdown_background();
        })
        .expect("start the server thread");
    // A panic outside `guarded` has already printed; exit as a crash.
    if server.join().is_err() {
        std::process::exit(101);
    }
}