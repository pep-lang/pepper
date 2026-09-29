//! Pepper language server.
//!
//! Speaks LSP over stdio. Diagnostics come from the parser (precise, via AST
//! spans) and from a full semantic check of the merged program (runtime
//! prelude + resolved imports + the open document). Hover, completion,
//! go-to-definition, and document symbols are computed from the parsed AST
//! plus the sema model.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use pepper_parser::ast::{self, Span};
use pepper_parser::parser::parse_source;
use pepper_sema::model::{Module as SemaModule, StructDef};
use tower_lsp::jsonrpc::Result as LspResult;
use tower_lsp::lsp_types::*;
use tower_lsp::{async_trait, Client, LanguageServer, LspService, Server};

const KEYWORDS: &[&str] = &[
    "import", "from", "struct", "var", "const", "if", "else", "while", "for", "in", "return", "extern",
    "and", "or", "new", "construct", "destruct", "static", "sizeof", "true", "false", "trait",
    "extend", "export",
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
        out.push(Symbol { name: "new".to_string(), name_span: ctor.name_span, ty: format!("new({})", params) });
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
                ty: format!("struct {}", type_string(&ast::TypeName {
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
            ast::Statement::Expression(e) => {
                if let Some(found) = expr_at(e, offset) {
                    return Some(found);
                }
            }
            ast::Statement::Block(b) => {
                if let Some(found) = find_expr_in_block(b, offset) {
                    return Some(found);
                }
            }
            ast::Statement::Branch(br) => {
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
                if let Some(found) = find_expr_in_block(&w.block, offset) {
                    return Some(found);
                }
            }
            ast::Statement::For(f) => {
                if let Some(found) = find_expr_in_block(&f.block, offset) {
                    return Some(found);
                }
            }
            _ => {}
        }
    }
    None
}

// ── Sema lookups (merged model; no spans needed) ──────────────────────────────

fn find_sema_struct<'a>(module: &'a SemaModule, name: &str) -> Option<&'a StructDef> {
    module.structs.iter().find(|s| s.name == name)
}

fn struct_member_type(st: &StructDef, name: &str) -> Option<String> {
    st.field_members.iter().find(|f| f.name == name).map(|f| f.ty.to_string())
}

fn is_this(expr: &ast::Expression) -> bool {
    matches!(expr, ast::Expression::MemberAccess { lhs, .. } if matches!(&**lhs, ast::Expression::SymbolRef { id, .. } if id.as_str() == "this"))
}

// ── Server ────────────────────────────────────────────────────────────────────

struct PepperLsp {
    client: Client,
    /// Open documents, keyed by URI string.
    docs: Mutex<HashMap<String, String>>,
}

/// The loaded, linked program rooted at an open document, which is
/// `files[0]`.
type Program = pepper_sema::program::Program;

/// Merge `program` into one sema model and run the sema passes. Build errors
/// in the document (`program[0]`) are reported; other files that fail to
/// build are skipped.
fn sema_model_of(program: &Program) -> Result<SemaModule, String> {
    let mut module = SemaModule::default();
    for file in &program.files[1..] {
        if let Ok(m) = pepper_sema::build(&file.module) {
            module.merge(m);
        }
    }
    module.merge(pepper_sema::build(&program.files[0].module)?);

    // Run the sema passes under a panic guard: an LSP must never crash on
    // a user file, so a panicking pass degrades to "no semantic info".
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut m = module;
        pepper_sema::apply_platform_filters(&mut m)?;
        pepper_sema::struct_body::apply(&mut m)?;
        pepper_sema::transform_pass(&mut m);
        Ok(m)
    }));
    match result {
        Ok(Ok(m)) => Ok(m),
        Ok(Err(e)) => Err(e),
        Err(_) => Err("semantic analysis panicked".to_string()),
    }
}

impl PepperLsp {
    fn new(client: Client) -> Self {
        Self { client, docs: Mutex::new(HashMap::new()) }
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

    /// Build the merged sema model for `uri`: runtime prelude + resolved
    /// imports + the open document.
    fn sema_model(&self, uri: &Url) -> Result<SemaModule, String> {
        sema_model_of(&self.program(uri)?)
    }

    /// Import errors in the program's document (`program.files[0]`),
    /// references to symbols another file did not `export` or this file did
    /// not import, and private names it shares with other files.
    fn visibility_diagnostics(program: &Program) -> Vec<Diagnostic> {
        let text = &program.files[0].source;
        let diagnostic = |span: Span, message: String, severity| Diagnostic {
            range: span_to_range(text, span),
            severity: Some(severity),
            message,
            ..Default::default()
        };
        // The editor does not know the compile's `-I` directories, so an
        // import it cannot find may still resolve for the compiler.
        let mut diags: Vec<Diagnostic> = program
            .errors
            .iter()
            .filter(|e| e.file == 0)
            .map(|e| {
                let severity = if e.unresolved { DiagnosticSeverity::WARNING } else { DiagnosticSeverity::ERROR };
                diagnostic(e.span, e.message.clone(), severity)
            })
            .collect();
        let files = program.source_files();
        // Same panic guard as the sema passes.
        let Ok(errors) = std::panic::catch_unwind(|| pepper_sema::check_visibility(&files)) else { return diags };
        // A reference that failed to link already has its diagnostic.
        let linked_errors: std::collections::HashSet<usize> =
            program.errors.iter().filter(|e| e.file == 0).map(|e| e.span.start).collect();
        diags.extend(
            errors
                .iter()
                .filter(|e| e.file == 0 && !linked_errors.contains(&e.span.start))
                .map(|e| diagnostic(e.span, e.message(&files), DiagnosticSeverity::ERROR)),
        );
        diags
    }

    /// Publish diagnostics for `uri`: parse errors (precise) + sema errors.
    async fn publish_diagnostics(&self, uri: &Url) {
        let mut diags = vec![];
        if let Some(text) = self.doc(uri) {
            if let Err(msg) = parse_source(uri.as_str(), &text) {
                // `msg` is `<name>:<line>:<col>: <message>` (1-based), for a
                // parse error or one found after parsing (a late import, `T*`
                // outside an extern). The name is the URI, which itself holds
                // colons, so strip it rather than splitting on them.
                let located = msg.strip_prefix(uri.as_str()).and_then(|rest| rest.strip_prefix(':')).and_then(|rest| {
                    let (l, rest) = rest.split_once(':')?;
                    let (c, message) = rest.split_once(':')?;
                    Some((l.parse::<u32>().ok()?, c.parse::<u32>().ok()?, message.trim().to_string()))
                });
                if let Some((l, c, message)) = located {
                    diags.push(Diagnostic {
                        range: Range::new(
                            Position::new(l.saturating_sub(1), c.saturating_sub(1)),
                            Position::new(l.saturating_sub(1), c.saturating_sub(1)),
                        ),
                        severity: Some(DiagnosticSeverity::ERROR),
                        message,
                        ..Default::default()
                    });
                } else {
                    diags.push(Diagnostic {
                        range: Range::new(Position::new(0, 0), Position::new(0, 0)),
                        severity: Some(DiagnosticSeverity::ERROR),
                        message: msg,
                        ..Default::default()
                    });
                }
            }
        }
        // Read and parse the program once for both the sema and visibility
        // checks.
        let program = self.program(uri);
        // The program fails to load only when the document itself does not
        // parse, which already produced a diagnostic above; only surface
        // genuine semantic errors.
        if let Ok(p) = &program
            && let Err(e) = sema_model_of(p)
        {
            diags.push(Diagnostic {
                range: Range::new(Position::new(0, 0), Position::new(0, 0)),
                severity: Some(DiagnosticSeverity::ERROR),
                message: format!("semantic error: {}", e),
                ..Default::default()
            });
        }
        if let Ok(program) = &program {
            diags.extend(Self::visibility_diagnostics(program));
        }
        self.client.publish_diagnostics(uri.clone(), diags, None).await;
    }

    /// Hover at `offset` in document `uri`.
    fn hover(&self, uri: &Url, offset: usize) -> Option<Hover> {
        let text = self.doc(uri)?;
        let ast = parse_source(uri.as_str(), &text).ok()?;
        let expr = find_expr(&ast, offset)?;

        let Some((body, enclosing_struct)) = body_at(&ast, offset) else {
            return None;
        };
        let locals: Vec<Symbol> = locals_at(body, offset);
        let globals = collect_globals(&ast);
        let struct_members: Vec<Symbol> = enclosing_struct.map(collect_struct_members).unwrap_or_default();
        let sema = self.sema_model(uri).ok();

        let md = |content: String| HoverContents::Markup(MarkupContent { kind: MarkupKind::Markdown, value: content });

        match expr {
            ast::Expression::Literal { value, .. } => {
                let ty = match value {
                    ast::Literal::String(_) => "String",
                    ast::Literal::Integer(_) => "int",
                    ast::Literal::Float(_) => "float",
                    ast::Literal::Bool(_) => "bool",
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
                        sema.as_ref().and_then(|m| {
                            m.functions.iter().find(|f| f.name == *id).map(|f| f.ty.to_string())
                                .or_else(|| m.structs.iter().find(|s| s.name == *id).map(|s| format!("struct {}", s.ty.to_string())))
                                .or_else(|| m.traits.iter().find(|t| t.name == *id).map(|_| "trait".to_string()))
                                .or_else(|| m.externs.iter().find(|e| e.name == *id).map(|_| "extern function".to_string()))
                        })
                    })
                    .unwrap_or_else(|| "unknown".to_string());
                Some(Hover { contents: md(format!("`{}` — `{}`", id, rendered)), range: None })
            }
            ast::Expression::MemberAccess { name, .. } => {
                let rendered = if is_this(expr) {
                    struct_members.iter().find(|s| s.name == *name).map(|s| s.ty.clone())
                        .or_else(|| {
                            sema.as_ref()
                                .and_then(|m| enclosing_struct.and_then(|s| find_sema_struct(m, &s.name)))
                                .and_then(|st| struct_member_type(st, name))
                        })
                        .unwrap_or_else(|| "unknown".to_string())
                } else {
                    sema.as_ref()
                        .and_then(|m| m.structs.iter().find_map(|st| struct_member_type(st, name)))
                        .unwrap_or_else(|| "unknown".to_string())
                };
                Some(Hover { contents: md(format!("`.`{}` — `{}`", name, rendered)), range: None })
            }
            ast::Expression::FunctionCall { function, .. } => match &**function {
                ast::Expression::SymbolRef { id, .. } => {
                    let rendered = globals.iter().find(|s| s.name == *id).map(|s| s.ty.clone())
                        .or_else(|| sema.as_ref().and_then(|m| m.functions.iter().find(|f| f.name == *id).map(|f| f.ty.to_string())))
                        .unwrap_or_else(|| "unknown".to_string());
                    Some(Hover { contents: md(format!("`{}` — `{}`", id, rendered)), range: None })
                }
                ast::Expression::MemberAccess { name, .. } => {
                    let rendered = sema.as_ref()
                        .and_then(|m| m.structs.iter().find_map(|st| struct_member_type(st, name)))
                        .unwrap_or_else(|| "unknown".to_string());
                    Some(Hover { contents: md(format!(".`{}` — `{}`", name, rendered)), range: None })
                }
                _ => None,
            },
            _ => None,
        }
    }

    /// Go-to-definition at `offset`.
    fn definition(&self, uri: &Url, offset: usize) -> Option<Vec<Location>> {
        let text = self.doc(uri)?;
        let ast = parse_source(uri.as_str(), &text).ok()?;
        let expr = find_expr(&ast, offset)?;

        let Some((body, enclosing_struct)) = body_at(&ast, offset) else {
            return None;
        };
        let locals: Vec<Symbol> = locals_at(body, offset);
        let globals = collect_globals(&ast);
        let struct_members: Vec<Symbol> = enclosing_struct.map(collect_struct_members).unwrap_or_default();

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

        Some(vec![Location::new(uri.clone(), span_to_range(&text, target_span))])
    }

    /// Document symbols for `uri`.
    fn document_symbols(&self, uri: &Url) -> Option<Vec<DocumentSymbol>> {
        let text = self.doc(uri)?;
        let ast = parse_source(uri.as_str(), &text).ok()?;
        let mut out = vec![];
        for decl in &ast.declarations {
            match decl {
                ast::Declaration::Function(f) => {
                    out.push(DocumentSymbol {
                        name: f.name.clone(),
                        detail: Some(function_signature(f)),
                        kind: SymbolKind::FUNCTION,
                        tags: None,
                        deprecated: None,
                        range: span_to_range(&text, f.span),
                        selection_range: span_to_range(&text, f.name_span),
                        children: None,
                    });
                }
                ast::Declaration::Struct(s) => {
                    let mut children = vec![];
                    for field in &s.fields {
                        children.push(DocumentSymbol {
                            name: field.name.clone(),
                            detail: Some(type_string(&field.type_name)),
                            kind: SymbolKind::FIELD,
                            tags: None,
                            deprecated: None,
                            range: span_to_range(&text, field.span),
                            selection_range: span_to_range(&text, field.name_span),
                            children: None,
                        });
                    }
                    for m in &s.methods {
                        children.push(DocumentSymbol {
                            name: m.name.clone(),
                            detail: Some(function_signature(m)),
                            kind: SymbolKind::METHOD,
                            tags: None,
                            deprecated: None,
                            range: span_to_range(&text, m.span),
                            selection_range: span_to_range(&text, m.name_span),
                            children: None,
                        });
                    }
                    out.push(DocumentSymbol {
                        name: s.name.clone(),
                        detail: Some("struct".to_string()),
                        kind: SymbolKind::STRUCT,
                        tags: None,
                        deprecated: None,
                        range: span_to_range(&text, s.span),
                        selection_range: span_to_range(&text, s.name_span),
                        children: if children.is_empty() { None } else { Some(children) },
                    });
                }
                ast::Declaration::Variable(v) => out.push(DocumentSymbol {
                    name: v.name.clone(),
                    detail: Some(variable_type(v)),
                    kind: SymbolKind::VARIABLE,
                    tags: None,
                    deprecated: None,
                    range: span_to_range(&text, v.span),
                    selection_range: span_to_range(&text, v.name_span),
                    children: None,
                }),
                ast::Declaration::Trait(t) => out.push(DocumentSymbol {
                    name: t.name.clone(),
                    detail: Some("trait".to_string()),
                    kind: SymbolKind::INTERFACE,
                    tags: None,
                    deprecated: None,
                    range: span_to_range(&text, t.span),
                    selection_range: span_to_range(&text, t.name_span),
                    children: None,
                }),
                ast::Declaration::Extend(e) => out.push(DocumentSymbol {
                    name: e.target.to_string(),
                    detail: Some("extend".to_string()),
                    kind: SymbolKind::NAMESPACE,
                    tags: None,
                    deprecated: None,
                    range: span_to_range(&text, e.span),
                    selection_range: span_to_range(&text, e.target.span),
                    children: None,
                }),
                ast::Declaration::TypeAlias(t) => out.push(DocumentSymbol {
                    name: t.name.clone(),
                    detail: Some("type".to_string()),
                    kind: SymbolKind::STRUCT,
                    tags: None,
                    deprecated: None,
                    range: span_to_range(&text, t.span),
                    selection_range: span_to_range(&text, t.name_span),
                    children: None,
                }),
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
            && let Ok(ast) = parse_source(uri.as_str(), &text)
        {
            let scope = body_at(&ast, offset);
            let locals: Vec<Symbol> = scope.as_ref().map(|(b, _)| locals_at(b, offset)).unwrap_or_default();
            let globals = collect_globals(&ast);
            let struct_members: Vec<Symbol> = scope
                .as_ref()
                .and_then(|(_, s)| *s)
                .map(collect_struct_members)
                .unwrap_or_default();

            for s in locals.iter().chain(struct_members.iter()).chain(globals.iter()) {
                items.push(CompletionItem {
                    label: s.name.clone(),
                    kind: Some(if s.ty.contains('(') {
                        CompletionItemKind::FUNCTION
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
    async fn initialize(&self, _params: InitializeParams) -> LspResult<InitializeResult> {
        Ok(InitializeResult {
            capabilities: ServerCapabilities {
                hover_provider: Some(HoverProviderCapability::Simple(true)),
                completion_provider: Some(CompletionOptions {
                    trigger_characters: Some(vec![".".to_string(), "(".to_string()]),
                    ..Default::default()
                }),
                definition_provider: Some(OneOf::Left(true)),
                document_symbol_provider: Some(OneOf::Left(true)),
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
