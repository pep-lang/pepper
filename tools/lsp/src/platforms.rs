//! Code for other platforms: the parts of a document a `[Target(...)]`
//! attribute leaves out on the platform the server runs on (the build
//! target), which the editor shows dimmed, as clang does for an inactive
//! `#if`. It mirrors what `passes::platform` drops, no more: constructors,
//! destructors and fields are always compiled. Attributed blocks are dropped
//! wherever statements are, `for`, `with` and `match` bodies included (the
//! builder lowers those to blocks, branches and loops first).

use pepper_parser::ast::{self, Span};
use pepper_sema::passes::platform::keep;

/// Whether `attributes` leave their target out on this platform. A
/// malformed `Target(...)` is reported by sema, not dimmed.
fn inactive(attributes: &[ast::Attribute]) -> bool {
    keep(attributes) == Ok(false)
}

/// From the first of `attributes` (or `span`'s start) to `span`'s end.
fn with_attributes(attributes: &[ast::Attribute], span: Span) -> Span {
    let start = attributes.iter().map(|a| a.span.start).chain([span.start]).min().unwrap_or(span.start);
    Span { start, end: span.end }
}

/// Every span of `text` (parsed as `module`) its `[Target(...)]` attributes
/// leave out on this platform, outermost only, in source order, without the
/// whitespace after each.
pub fn inactive_regions(text: &str, module: &ast::Module) -> Vec<Span> {
    let mut out = vec![];
    for import in &module.imports {
        if inactive(&import.attributes) {
            out.push(import.span);
        }
    }
    for export in &module.exports {
        if inactive(&export.attributes) {
            out.push(export.span);
        }
    }
    for decl in &module.declarations {
        if inactive(decl.attributes()) {
            out.push(with_attributes(decl.attributes(), decl.span()));
            continue;
        }
        match decl {
            ast::Declaration::Function(f) => function(f, &mut out),
            ast::Declaration::Struct(s) => {
                for case in s.enumeration.iter().flat_map(|e| &e.cases) {
                    if inactive(&case.attributes) {
                        out.push(with_attributes(&case.attributes, case.span));
                    }
                }
                for f in &s.methods {
                    function(f, &mut out);
                }
                // Never dropped, whatever their attributes: only the blocks
                // inside.
                for body in s.constructors.iter().filter_map(|c| c.body.as_ref()).chain(&s.destructor) {
                    statements(body, &mut out);
                }
            }
            ast::Declaration::Trait(t) => t.methods.iter().for_each(|f| function(f, &mut out)),
            ast::Declaration::Extend(e) => e.methods.iter().for_each(|f| function(f, &mut out)),
            ast::Declaration::Variable(_) | ast::Declaration::TypeAlias(_) => {}
        }
    }
    out.sort_by_key(|s| s.start);
    for span in &mut out {
        let end = span.end.min(text.len());
        span.end = span.start.max(text[..end].trim_end().len());
    }
    out
}

/// A function, method or constructor: all of it, or its inactive blocks.
fn function(f: &ast::FunctionDecl, out: &mut Vec<Span>) {
    if inactive(&f.attributes) {
        // A method's span starts after its name.
        let span = Span { start: f.span.start.min(f.name_span.start), end: f.span.end };
        out.push(with_attributes(&f.attributes, span));
    } else if let Some(body) = &f.body {
        statements(body, out);
    }
}

/// A block: all of it (its span includes its attributes), or the inactive
/// blocks inside.
fn block(b: &ast::Block, out: &mut Vec<Span>) {
    if inactive(&b.attributes) {
        out.push(b.span);
    } else {
        statements(b, out);
    }
}

/// The inactive blocks among `b`'s statements and the bodies nested in them.
fn statements(b: &ast::Block, out: &mut Vec<Span>) {
    for statement in &b.statements {
        match statement {
            ast::Statement::Block(inner) => block(inner, out),
            ast::Statement::Branch(br) => {
                block(&br.if_block, out);
                if let Some(e) = &br.else_block {
                    block(e, out);
                }
            }
            ast::Statement::While(w) => block(&w.block, out),
            ast::Statement::For(f) => block(&f.block, out),
            ast::Statement::With(w) => {
                block(&w.block, out);
                if let Some(e) = &w.else_block {
                    block(e, out);
                }
            }
            ast::Statement::Match(m) => {
                for arm in &m.arms {
                    block(&arm.body, out);
                }
                if let Some((_, e)) = &m.else_arm {
                    block(e, out);
                }
            }
            _ => {}
        }
    }
}
