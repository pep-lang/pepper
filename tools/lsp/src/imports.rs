//! Following names through imports: `q.x` after `import m as q`, `y` after
//! `import [x as y] from m`, an unqualified export of `import "file"`, and
//! the imports and re-exports themselves. Linking records what each such
//! spelling denotes (see `pepper_sema::FileScope`); this module finds the
//! spelling under the cursor and the declaration or file it leads to.

use pepper_parser::ast::{self, Span};

use crate::{Program, Symbol, collect_globals};

/// Where a name reached through an import leads.
pub enum Target {
    /// A top-level declaration in `program.files[file]`.
    Declaration { file: usize, symbol: Symbol },
    /// An imported file (`import "shapes"`) or module (`import geo`, whose
    /// `module.pep` this is), named by an import or a qualifier.
    File(usize),
}

fn contains(span: Span, offset: usize) -> bool {
    span.start <= offset && offset < span.end
}

/// The top-level declaration `name` denotes, and the program file declaring
/// it. The merged program keeps the first definition of a name, so the first
/// file declaring it wins.
fn declaration(program: &Program, name: &str) -> Option<Target> {
    program.files.iter().enumerate().find_map(|(file, f)| {
        collect_globals(&f.module)
            .into_iter()
            .find(|s| s.name == name)
            .map(|symbol| Target::Declaration { file, symbol })
    })
}

/// The file the document's (`program.files[0]`) import `index` resolved to.
fn imported_file(program: &Program, index: usize) -> Option<Target> {
    program.files[0].imports.get(index).copied().flatten().map(Target::File)
}

/// The import of the document that binds the qualifier `q`.
fn qualifier_import(program: &Program, doc: &ast::Module, q: &str) -> Option<Target> {
    let index = doc.imports.iter().position(|imp| imp.qualifier() == Some(q))?;
    imported_file(program, index)
}

/// What the spelling at `span` denotes: a reference linking rewrote, or the
/// name of an `import [...]` entry or re-export.
fn linked(program: &Program, span: Span) -> Option<Target> {
    let scope = &program.scopes[0];
    let name = scope.imported.get(&span.start).or_else(|| scope.named.get(&span.start))?;
    declaration(program, name)
}

/// The name at `offset` in an import or re-export of the document `doc`
/// (the unlinked parse of `program.files[0]`): the spelling under the
/// cursor, and where it leads.
pub fn in_imports(program: &Program, doc: &ast::Module, offset: usize) -> Option<(String, Target)> {
    for (index, imp) in doc.imports.iter().enumerate() {
        if !contains(imp.span, offset) {
            continue;
        }
        if contains(imp.name_span, offset) {
            return Some((imp.name.clone(), imported_file(program, index)?));
        }
        for s in imp.symbols.iter().flatten() {
            if contains(s.span, offset) {
                return Some((s.local_name().to_string(), linked(program, s.span)?));
            }
        }
        return None;
    }
    let ea = doc.exports.iter().find(|ea| contains(ea.span, offset))?;
    // The qualifier of `export q.x as y` leads to the module.
    if let Some((q, _)) = ea.symbol.split_once('.')
        && offset < ea.symbol_span.start + q.len()
    {
        return Some((q.to_string(), qualifier_import(program, doc, q)?));
    }
    Some((ea.exported_name().to_string(), linked(program, ea.symbol_span)?))
}

/// The expression `expr` at `offset` as a name reached through an import:
/// a qualifier (`q` of `q.x`), a qualified reference, or an unqualified one.
/// `is_local`: the name is bound by a local, parameter, or member here, which
/// hides a qualifier of the same name.
pub fn in_expression(
    program: &Program,
    doc: &ast::Module,
    expr: &ast::Expression,
    is_local: impl Fn(&str) -> bool,
) -> Option<(String, Target)> {
    match expr {
        ast::Expression::SymbolRef { id, span } => {
            if !is_local(id)
                && let Some(target) = qualifier_import(program, doc, id)
            {
                return Some((id.clone(), target));
            }
            Some((id.clone(), linked(program, *span)?))
        }
        // Only a qualifier's member: `p.x` on an imported value `p` is a
        // struct member, recorded under the same span start as `p`.
        ast::Expression::MemberAccess { lhs, name, span, .. } => match &**lhs {
            ast::Expression::SymbolRef { id, .. } if !is_local(id) && qualifier_import(program, doc, id).is_some() => {
                Some((name.clone(), linked(program, *span)?))
            }
            _ => None,
        },
        _ => None,
    }
}

/// The type name at `offset` as a name reached through an import: `q` of
/// `q.Point` leads to the module, `q.Point`, an alias, or an unqualified
/// import to the declaration.
pub fn in_type(program: &Program, doc: &ast::Module, offset: usize) -> Option<(String, Target)> {
    let ty = type_at(doc, offset)?;
    let base = ty.name.trim_end_matches(['*', '[', ']']);
    if let Some((q, name)) = base.split_once('.') {
        if offset < ty.span.start + q.len() {
            return Some((q.to_string(), qualifier_import(program, doc, q)?));
        }
        return Some((name.to_string(), linked(program, ty.span)?));
    }
    Some((base.to_string(), linked(program, ty.span)?))
}

// ── Type names at an offset ───────────────────────────────────────────────────

/// The innermost type name written at `offset` anywhere in `module`.
fn type_at(module: &ast::Module, offset: usize) -> Option<&ast::TypeName> {
    module.declarations.iter().find_map(|d| in_declaration(d, offset))
}

fn in_type_name(ty: &ast::TypeName, offset: usize) -> Option<&ast::TypeName> {
    if !contains(ty.span, offset) || ty.name == "__auto" {
        return None;
    }
    ty.generic_types.iter().find_map(|g| in_type_name(g, offset)).or(Some(ty))
}

fn in_generics(params: &[ast::GenericParam], offset: usize) -> Option<&ast::TypeName> {
    params.iter().filter_map(|p| p.default.as_ref()).find_map(|d| in_type_name(d, offset))
}

fn in_declaration(decl: &ast::Declaration, offset: usize) -> Option<&ast::TypeName> {
    match decl {
        ast::Declaration::Variable(v) => in_variable(v, offset),
        ast::Declaration::Function(f) => in_function(f, offset),
        ast::Declaration::Struct(s) => in_generics(&s.generic_params, offset)
            .or_else(|| s.fields.iter().find_map(|f| in_variable(f, offset)))
            .or_else(|| s.constructors.iter().find_map(|c| in_function(c, offset)))
            .or_else(|| s.destructor.as_ref().and_then(|d| in_block(d, offset)))
            .or_else(|| s.methods.iter().find_map(|m| in_function(m, offset))),
        ast::Declaration::Trait(t) => {
            in_generics(&t.generic_params, offset).or_else(|| t.methods.iter().find_map(|m| in_function(m, offset)))
        }
        ast::Declaration::Extend(e) => in_type_name(&e.target, offset)
            .or_else(|| e.traits.iter().find_map(|t| in_type_name(t, offset)))
            .or_else(|| e.methods.iter().find_map(|m| in_function(m, offset))),
        ast::Declaration::TypeAlias(t) => in_generics(&t.generic_params, offset).or_else(|| in_type_name(&t.target, offset)),
    }
}

fn in_variable(v: &ast::VariableDecl, offset: usize) -> Option<&ast::TypeName> {
    in_type_name(&v.type_name, offset).or_else(|| v.default_value.as_ref().and_then(|e| in_expression_types(e, offset)))
}

fn in_function(f: &ast::FunctionDecl, offset: usize) -> Option<&ast::TypeName> {
    if !contains(f.span, offset) {
        return None;
    }
    in_generics(&f.generic_params, offset)
        .or_else(|| in_type_name(&f.return_type, offset))
        .or_else(|| f.parameters.iter().find_map(|p| in_variable(p, offset)))
        .or_else(|| f.body.as_ref().and_then(|b| in_block(b, offset)))
}

fn in_block(block: &ast::Block, offset: usize) -> Option<&ast::TypeName> {
    if !contains(block.span, offset) {
        return None;
    }
    block.statements.iter().find_map(|s| in_statement(s, offset))
}

fn in_statement(stmt: &ast::Statement, offset: usize) -> Option<&ast::TypeName> {
    if !contains(stmt.span(), offset) {
        return None;
    }
    match stmt {
        ast::Statement::Expression(e) => in_expression_types(e, offset),
        ast::Statement::Block(b) => in_block(b, offset),
        ast::Statement::Declaration(d) => in_declaration(d, offset),
        ast::Statement::Branch(b) => in_expression_types(&b.condition, offset)
            .or_else(|| in_block(&b.if_block, offset))
            .or_else(|| b.else_block.as_ref().and_then(|e| in_block(e, offset))),
        ast::Statement::While(w) => in_expression_types(&w.condition, offset).or_else(|| in_block(&w.block, offset)),
        ast::Statement::For(f) => in_variable(&f.binding, offset)
            .or_else(|| f.pattern.iter().flat_map(|b| b.leaves()).find_map(|b| in_type_name(&b.type_name, offset)))
            .or_else(|| in_expression_types(&f.iterable, offset))
            .or_else(|| in_block(&f.block, offset)),
        ast::Statement::With(w) => w
            .binding
            .as_ref()
            .and_then(|b| in_variable(b, offset))
            .or_else(|| in_expression_types(&w.scope, offset))
            .or_else(|| in_block(&w.block, offset))
            .or_else(|| w.else_block.as_ref().and_then(|e| in_block(e, offset))),
        ast::Statement::Return(r) => r.expr.as_ref().and_then(|e| in_expression_types(e, offset)),
        ast::Statement::LoopBreak(_) => None,
        ast::Statement::Destructure(d) => d
            .bindings
            .iter()
            .flat_map(|b| b.leaves())
            .find_map(|b| in_type_name(&b.type_name, offset))
            .or_else(|| in_expression_types(&d.value, offset)),
        ast::Statement::Match(m) => in_expression_types(&m.value, offset)
            .or_else(|| {
                m.arms.iter().find_map(|arm| {
                    arm.patterns
                        .iter()
                        .flat_map(|p| p.all())
                        .find_map(|p| p.qualifier.as_ref().and_then(|q| in_type_name(q, offset)))
                        .or_else(|| in_block(&arm.body, offset))
                })
            })
            .or_else(|| m.else_arm.as_ref().and_then(|(_, b)| in_block(b, offset))),
    }
}

fn in_expression_types(expr: &ast::Expression, offset: usize) -> Option<&ast::TypeName> {
    if !contains(expr.span(), offset) {
        return None;
    }
    match expr {
        ast::Expression::TypeLiteral(t) | ast::Expression::SizeOf(t) => in_type_name(t, offset),
        ast::Expression::Cast { expr, ty, .. } => in_expression_types(expr, offset).or_else(|| in_type_name(ty, offset)),
        ast::Expression::Unary { operand, .. } => in_expression_types(operand, offset),
        ast::Expression::Binary { lhs, rhs, .. } | ast::Expression::Index { lhs, rhs, .. } => {
            in_expression_types(lhs, offset).or_else(|| in_expression_types(rhs, offset))
        }
        ast::Expression::Ternary { condition, true_expr, false_expr, .. } => in_expression_types(condition, offset)
            .or_else(|| in_expression_types(true_expr, offset))
            .or_else(|| in_expression_types(false_expr, offset)),
        ast::Expression::MemberAccess { lhs, .. } => in_expression_types(lhs, offset),
        ast::Expression::FunctionCall { function, arguments, .. } => in_expression_types(function, offset)
            .or_else(|| arguments.iter().find_map(|a| in_expression_types(a, offset))),
        ast::Expression::Closure(c) => c
            .parameters
            .iter()
            .find_map(|p| in_variable(p, offset))
            .or_else(|| in_type_name(&c.return_type, offset))
            .or_else(|| in_block(&c.body, offset)),
        ast::Expression::Tuple { elements, .. } | ast::Expression::ArrayLiteral { elements, .. } => {
            elements.iter().find_map(|e| in_expression_types(e, offset))
        }
        ast::Expression::MapLiteral { entries, .. } => entries
            .iter()
            .find_map(|(key, value)| in_expression_types(key, offset).or_else(|| in_expression_types(value, offset))),
        ast::Expression::Match(m) => in_expression_types(&m.value, offset)
            .or_else(|| {
                m.arms.iter().find_map(|arm| {
                    arm.patterns
                        .iter()
                        .flat_map(|p| p.all())
                        .find_map(|p| p.qualifier.as_ref().and_then(|q| in_type_name(q, offset)))
                        .or_else(|| in_expression_types(&arm.value, offset))
                })
            })
            .or_else(|| m.else_arm.as_ref().and_then(|(_, v)| in_expression_types(v, offset))),
        ast::Expression::Is { value, pattern, .. } => in_expression_types(value, offset)
            .or_else(|| pattern.all().into_iter().find_map(|p| p.qualifier.as_ref().and_then(|q| in_type_name(q, offset)))),
        ast::Expression::Literal { .. } | ast::Expression::SymbolRef { .. } => None,
    }
}
