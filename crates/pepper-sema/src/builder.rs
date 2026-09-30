//! AST → model builder: port of `source/Sema/ModelBuilder.cpp` (`SemaParser`),
//! without the C++ Builder scope machinery — the model tree is built directly.

use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;
use pepper_parser::diagnostic::{Diagnostic, FileId};

thread_local! {
    /// The file being built, whose id every location built carries. Set by
    /// [`build_file`] for the duration of one build.
    static FILE: std::cell::Cell<FileId> = const { std::cell::Cell::new(FileId(0)) };
    /// The first bad tuple label [`type_name_from`] met. It returns a plain
    /// type, so [`build_file`] reports this once the build finishes.
    static LABEL_ERROR: std::cell::RefCell<Option<Diagnostic>> = const { std::cell::RefCell::new(None) };
}

/// `span` in the file being built.
fn loc(span: ast::Span) -> Loc {
    Loc::new(FILE.with(|f| f.get()), span)
}

fn type_name_from(t: &ast::TypeName) -> TypeName {
    let args: Vec<TypeName> = t.generic_types.iter().map(type_name_from).collect();
    // `int[]` → `Array<int>`; applied innermost-first, so `int[][]` nests.
    if let Some(base) = t.name.strip_suffix("[]") {
        let element = type_name_from(&ast::TypeName {
            name: base.to_string(),
            generic_types: t.generic_types.clone(),
            span: ast::Span::none(),
            labels: t.labels.clone(),
        });
        return TypeName::with_args("Array", vec![element]);
    }
    // `Tuple<A, B>` is another spelling of the tuple type `(A, B)`.
    if t.name == "Tuple" && args.len() >= 2 {
        return TypeName::with_args(crate::type_name::TUPLE, args);
    }
    if args.is_empty() {
        TypeName::new(&t.name)
    } else {
        check_labels(t);
        let mut ty = TypeName::with_args(&t.name, args);
        ty.labels = t.labels.clone();
        ty
    }
}

/// Records an error for a tuple type that labels some elements but not all,
/// or uses one label twice. The parser has no label spans, so the error sits
/// on the element's type, just after its label.
fn check_labels(t: &ast::TypeName) {
    let error = if let Some(i) = t.labels.iter().position(String::is_empty) {
        let j = t.labels.iter().position(|l| !l.is_empty()).unwrap_or(0);
        Some(
            Diagnostic::error(format!("missing label for element {} of a labeled tuple: label every element or none", i))
                .at(loc(t.generic_types[i].span))
                .with_note(format!("element labeled '{}' here", t.labels[j]), Some(loc(t.generic_types[j].span))),
        )
    } else {
        t.labels.iter().enumerate().skip(1).find_map(|(i, label)| {
            let first = t.labels[..i].iter().position(|l| l == label)?;
            Some(
                Diagnostic::error(format!("duplicate label '{}' in tuple type", label))
                    .at(loc(t.generic_types[i].span))
                    .with_note("previous label here", Some(loc(t.generic_types[first].span))),
            )
        })
    };
    if let Some(error) = error {
        LABEL_ERROR.with(|e| {
            e.borrow_mut().get_or_insert(error);
        });
    }
}

fn generic_param_from(p: &ast::GenericParam) -> GenericParam {
    GenericParam {
        name: p.name.clone(),
        default: p.default.as_ref().map(type_name_from),
        is_argument: p.is_argument,
    }
}

fn binary_op(op: &str) -> Option<BinaryOp> {
    Some(match op {
        "+" => BinaryOp::Add,
        "-" => BinaryOp::Sub,
        "*" => BinaryOp::Mul,
        "/" => BinaryOp::Div,
        "%" => BinaryOp::Mod,
        "<<" => BinaryOp::LShift,
        ">>" => BinaryOp::RShift,
        "&" => BinaryOp::BitAnd,
        "&&" => BinaryOp::LogicalAnd,
        "and" => BinaryOp::LogicalAnd,
        "|" => BinaryOp::BitOr,
        "||" => BinaryOp::LogicalOr,
        "or" => BinaryOp::LogicalOr,
        "^" => BinaryOp::BitXor,
        "==" => BinaryOp::Equal,
        ">=" => BinaryOp::GreaterEqual,
        "<=" => BinaryOp::LessEqual,
        ">" => BinaryOp::Greater,
        "<" => BinaryOp::Less,
        "!=" => BinaryOp::NotEqual,
        "**" => BinaryOp::Pow,
        "===" => BinaryOp::Identical,
        "!==" => BinaryOp::NotIdentical,
        "=" => BinaryOp::Assign,
        "+=" => BinaryOp::AddAssign,
        "-=" => BinaryOp::SubAssign,
        "*=" => BinaryOp::MulAssign,
        "/=" => BinaryOp::DivAssign,
        "%=" => BinaryOp::ModAssign,
        "<<=" => BinaryOp::LShiftAssign,
        ">>=" => BinaryOp::RShiftAssign,
        "&=" => BinaryOp::BitAndAssign,
        "|=" => BinaryOp::BitOrAssign,
        "^=" => BinaryOp::BitXorAssign,
        _ => return None,
    })
}

fn unary_op(op: &str, prefix: bool) -> Option<UnaryOp> {
    Some(match op {
        "+" => UnaryOp::Pos,
        "-" => UnaryOp::Neg,
        "++" if prefix => UnaryOp::PreInc,
        "++" => UnaryOp::PostInc,
        "--" if prefix => UnaryOp::PreDec,
        "--" => UnaryOp::PostDec,
        "!" => UnaryOp::LogicalNot,
        "~" => UnaryOp::BitNot,
        _ => return None,
    })
}

fn expression(expr: &ast::Expression) -> Result<Expression, Diagnostic> {
    match expr {
        ast::Expression::Literal { value: lit, span } => match lit {
            ast::Literal::String(value) => Ok(Expression::StringLiteral {
                value: value.clone(),
                is_raw: false,
                loc: loc(*span),
            }),
            ast::Literal::Integer(v) => Ok(Expression::IntLiteral(*v)),
            ast::Literal::Float(v) => Ok(Expression::FloatLiteral(*v)),
            ast::Literal::Bool(v) => Ok(Expression::BoolLiteral(*v)),
            // A `byte`: the cast gives it that type where nothing else does,
            // and it widens to any integer it is compared with or passed as.
            ast::Literal::Char(v) => Ok(Expression::Cast {
                expr: Box::new(Expression::IntLiteral(*v as i64)),
                ty: TypeName::new("byte"),
                loc: loc(*span),
            }),
            ast::Literal::Null => Ok(Expression::PointerLiteral),
        },
        ast::Expression::SymbolRef { id, .. } => {
            if id == "this" {
                Ok(Expression::ThisRef)
            } else {
                Ok(Expression::SymbolRef {
                    id: id.clone(),
                    ty: TypeName::auto(),
                    loc: loc(expr.span()),
                })
            }
        }
        ast::Expression::TypeLiteral(ty) => Ok(Expression::FunctionCall {
            function: type_name_from(ty).to_string(),
            args: vec![],
            loc: loc(ty.span),
        }),
        ast::Expression::SizeOf(ty) => Ok(Expression::SizeOf(type_name_from(ty))),
        ast::Expression::Unary { op, prefix, operand, span } => Ok(Expression::Unary {
            op: unary_op(op, *prefix)
                .ok_or_else(|| Diagnostic::error(format!("unsupported unary operator '{}'", op)).at(loc(*span)))?,
            operand: Box::new(expression(operand)?),
            loc: loc(*span),
        }),
        ast::Expression::Cast { expr, ty, span } => Ok(Expression::Cast {
            expr: Box::new(expression(expr)?),
            ty: type_name_from(ty),
            loc: loc(*span),
        }),
        ast::Expression::Binary { lhs, op, rhs, span } => Ok(Expression::Binary {
            op: binary_op(op)
                .ok_or_else(|| Diagnostic::error(format!("unsupported binary operator '{}'", op)).at(loc(*span)))?,
            lhs: Box::new(expression(lhs)?),
            rhs: Box::new(expression(rhs)?),
            loc: loc(*span),
        }),
        ast::Expression::Ternary {
            condition,
            true_expr,
            false_expr,
            ..
        } => Ok(Expression::Ternary {
            condition: Box::new(expression(condition)?),
            true_expr: Box::new(expression(true_expr)?),
            false_expr: Box::new(expression(false_expr)?),
        }),
        ast::Expression::Index { lhs, rhs, span } => Ok(Expression::Index {
            lhs: Box::new(expression(lhs)?),
            rhs: Box::new(expression(rhs)?),
            loc: loc(*span),
        }),
        ast::Expression::MemberAccess { lhs, name, name_span, .. } => {
            if name.starts_with("__") && name != "__release" && name != "__acquire" {
                return Err(Diagnostic::error(format!(
                    "'{}' is a reserved (synthesized) member and cannot be accessed from source code",
                    name
                ))
                .at(loc(*name_span)));
            }
            Ok(Expression::MemberRef {
                lhs: Box::new(expression(lhs)?),
                name: name.clone(),
                loc: loc(*name_span),
            })
        }
        ast::Expression::FunctionCall { function, arguments, .. } => {
            // Method call `t.getX()`: the target is a member access.
            if let ast::Expression::MemberAccess { lhs, name, name_span, .. } = function.as_ref() {
                // `__release`/`__acquire` are deliberately callable from
                // source: explicit refcount control is the language's escape
                // hatch for object lifetimes.
                if name.starts_with("__") && name != "__release" && name != "__acquire" {
                    return Err(Diagnostic::error(format!(
                        "'{}' is a reserved (synthesized) method and cannot be called from source code",
                        name
                    ))
                    .at(loc(*name_span)));
                }
                return Ok(Expression::MethodCall {
                    this: Box::new(expression(lhs)?),
                    method: name.clone(),
                    args: arguments.iter().map(expression).collect::<Result<Vec<_>, _>>()?,
                    loc: loc(*name_span),
                });
            }
            // Constructor-style call `Name<args>(ctor_args)` keeps the generic
            // target name; the args become the call arguments.
            let target = function.as_ref();
            let function = match target {
                ast::Expression::TypeLiteral(ty) => type_name_from(ty).to_string(),
                ast::Expression::SymbolRef { id: name, .. } => name.clone(),
                ast::Expression::Literal { value: lit, .. } => lit.to_string(),
                // Any other callee (`fs[0](x)`, `make_adder(1)(2)`) is an
                // expression producing a function value.
                other => {
                    return Ok(Expression::Invoke {
                        callee: Box::new(expression(other)?),
                        args: arguments.iter().map(expression).collect::<Result<Vec<_>, _>>()?,
                    });
                }
            };
            Ok(Expression::FunctionCall {
                function,
                args: arguments.iter().map(expression).collect::<Result<Vec<_>, _>>()?,
                loc: loc(target.span()),
            })
        }
        // `(a, b)`: a call of the tuple constructor, whose type
        // `resolve_implicit_types` spells out once the elements' types are
        // known (`__tuple<int, String>(a, b)`).
        ast::Expression::Tuple { elements, span } => Ok(Expression::FunctionCall {
            function: crate::type_name::TUPLE.to_string(),
            args: elements.iter().map(expression).collect::<Result<Vec<_>, _>>()?,
            loc: loc(*span),
        }),
        ast::Expression::Closure(c) => Ok(Expression::ClosureLiteral(Box::new(ClosureLiteral {
            parameters: c.parameters.iter().map(|p| variable_def(p, Kind::Param)).collect::<Result<Vec<_>, _>>()?,
            ty: type_name_from(&c.return_type),
            body: block(&c.body)?,
            expression_body: c.expression_body,
            loc: loc(c.span),
        }))),
    }
}
/// Check the form of a `[Deprecated(...)]` among `attributes`, on a
/// declaration that may be deprecated.
fn check_deprecation(attributes: &[ast::Attribute]) -> Result<(), Diagnostic> {
    crate::deprecation::deprecation_of(attributes)
        .map(|_| ())
        .map_err(|e| Diagnostic::error(e.message).at(loc(e.span)))
}

/// Reject a `[Deprecated]` on `what`, which no code refers to by name.
fn reject_deprecation(attributes: &[ast::Attribute], what: &str) -> Result<(), Diagnostic> {
    match attributes.iter().find(|a| crate::deprecation::is_deprecation(a)) {
        Some(a) => Err(Diagnostic::error(format!("'Deprecated' cannot be applied to {what}")).at(loc(a.span))),
        None => Ok(()),
    }
}

fn variable_def(decl: &ast::VariableDecl, kind: Kind) -> Result<VariableDef, Diagnostic> {
    check_deprecation(&decl.attributes)?;
    reject_implicit(&decl.attributes)?;
    let ty = type_name_from(&decl.type_name);
    let mut default = decl.default_value.as_ref().map(expression).transpose()?;
    // An optional slot (`Token? leaf;`, `var n: int?;`) starts as None, not
    // null: it gets the default `Optional<T>()`.
    if default.is_none() && kind != Kind::Param && ty.name == "Optional" && ty.sub_types.len() == 1 {
        default = Some(Expression::FunctionCall { function: ty.to_string(), args: vec![], loc: loc(decl.type_name.span) });
    }
    Ok(VariableDef {
        name: decl.name.clone(),
        ty,
        default,
        hidden: false,
        kind,
        attributes: decl.attributes.clone(),
        loc: loc(decl.name_span),
        type_loc: if decl.type_name.span.is_empty() { Loc::NONE } else { loc(decl.type_name.span) },
        is_const: decl.is_const,
    })
}

fn block(block: &ast::Block) -> Result<Block, Diagnostic> {
    let mut items = vec![];
    for stmt in &block.statements {
        match stmt {
            // A destructuring declaration's locals belong to the enclosing
            // block, so it lowers to several statements in place.
            ast::Statement::Destructure(d) => items.extend(destructure(d)?),
            _ => items.push(statement(stmt)?),
        }
    }
    Ok(Block { name: String::new(), items, attributes: block.attributes.clone() })
}

fn statement(stmt: &ast::Statement) -> Result<Statement, Diagnostic> {
    match stmt {
        ast::Statement::Expression(ast::Expression::Binary { lhs, op, rhs, span })
            if op == "=" && matches!(lhs.as_ref(), ast::Expression::Tuple { .. }) =>
        {
            destructuring_assignment(lhs, rhs, *span)
        }
        ast::Statement::Expression(expr) => Ok(Statement::Expression(expression(expr)?)),
        ast::Statement::Destructure(d) => Ok(Statement::Block(Block {
            name: String::new(),
            items: destructure(d)?,
            attributes: vec![],
        })),
        ast::Statement::Block(inner) => Ok(Statement::Block(block(inner)?)),
        ast::Statement::Declaration(decl) => Ok(Statement::Declaration(declaration(decl)?)),
        ast::Statement::Branch(branch) => Ok(Statement::Branch(Branch {
            condition: expression(&branch.condition)?,
            if_block: block(&branch.if_block)?,
            else_block: branch.else_block.as_ref().map(block).transpose()?,
        })),
        ast::Statement::While(wh) => Ok(Statement::While(While {
            condition: expression(&wh.condition)?,
            block: block(&wh.block)?,
        })),
        ast::Statement::For(f) => for_loop(f),
        ast::Statement::With(w) => with_block(w),
        ast::Statement::Match(m) => match_statement(m),
        ast::Statement::Return(ret) => Ok(Statement::Return(ReturnStatement {
            expr: ret.expr.as_ref().map(expression).transpose()?,
            loc: loc(ret.expr.as_ref().map_or(ret.span, |e| e.span())),
        })),
        ast::Statement::LoopBreak(lb) => Ok(Statement::LoopBreak(LoopBreak {
            kind: match lb.kind {
                ast::LoopBreakKind::Break => LoopBreakKind::Break,
                ast::LoopBreakKind::Continue => LoopBreakKind::Continue,
            },
        })),
    }
}

/// The hidden local holding the tuple a destructuring reads:
/// `var __tuple_N = Destructure(value, count);`.
fn hidden_tuple(value: &ast::Expression, count: usize) -> Result<(VariableDef, String, Loc), Diagnostic> {
    let at = loc(value.span());
    let (hidden, name) = hidden_tuple_of(expression(value)?, count, at);
    Ok((hidden, name, at))
}

/// [`hidden_tuple`] of a value already built, located at `at`.
fn hidden_tuple_of(value: Expression, count: usize, at: Loc) -> (VariableDef, String) {
    let n = TUPLES.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    });
    let name = format!("__tuple_{}", n);
    let hidden = VariableDef {
        name: name.clone(),
        ty: TypeName::auto(),
        default: Some(Expression::Destructure { value: Box::new(value), count, loc: at }),
        hidden: true,
        kind: Kind::Variable,
        attributes: vec![],
        loc: at,
        type_loc: Loc::NONE,
        is_const: false,
    };
    (hidden, name)
}

/// Element `index` of the hidden tuple local `tuple`, located at `at`.
fn tuple_element(tuple: &str, index: usize, at: Loc) -> Expression {
    Expression::MemberRef {
        lhs: Box::new(Expression::SymbolRef { id: tuple.to_string(), ty: TypeName::auto(), loc: at }),
        name: index.to_string(),
        loc: at,
    }
}

/// Lower `var (a, b: T, _) = value;` to
///
/// ```text
/// var __tuple_N = <Destructure(value, 3)>;
/// var a = __tuple_N.0;
/// var b: T = __tuple_N.1;
/// ```
///
/// This is C++'s `auto [a, b, _] = value;`: codegen moves each element into
/// its binding (`destructured_element`), and the hidden local keeps only the
/// skipped ones until scope exit.
/// `tuples::lower_destructures` checks the count once the type is known.
fn destructure(d: &ast::Destructure) -> Result<Vec<Statement>, Diagnostic> {
    let (hidden, tuple, _) = hidden_tuple(&d.value, d.bindings.len())?;
    let mut items = vec![Statement::Declaration(Declaration::Variable(hidden))];
    items.extend(bind_elements(&tuple, &d.bindings, d.is_const)?);
    Ok(items)
}

/// `var name = tuple.index;` for each binding of a pattern over the hidden
/// tuple local `tuple`, skipping `_`. A nested pattern gets a hidden tuple
/// local of its own, initialized from its element.
fn bind_elements(tuple: &str, bindings: &[ast::DestructureBinding], is_const: bool) -> Result<Vec<Statement>, Diagnostic> {
    let mut items = vec![];
    for (index, binding) in bindings.iter().enumerate() {
        let at = loc(binding.name_span);
        if !binding.nested.is_empty() {
            let (hidden, inner) = hidden_tuple_of(tuple_element(tuple, index, at), binding.nested.len(), at);
            items.push(Statement::Declaration(Declaration::Variable(hidden)));
            items.extend(bind_elements(&inner, &binding.nested, is_const)?);
            continue;
        }
        if binding.name == "_" {
            continue;
        }
        items.push(Statement::Declaration(Declaration::Variable(VariableDef {
            name: binding.name.clone(),
            ty: type_name_from(&binding.type_name),
            default: Some(tuple_element(tuple, index, at)),
            hidden: false,
            kind: Kind::Variable,
            attributes: vec![],
            loc: at,
            type_loc: if binding.type_name.span.is_empty() { Loc::NONE } else { loc(binding.type_name.span) },
            is_const,
        })));
    }
    Ok(items)
}

/// Lower `(a, b.f, _) = value;` to
///
/// ```text
/// {
///     var __tuple_N = <Destructure(value, 3)>;
///     a = __tuple_N.0;
///     b.f = __tuple_N.1;
/// }
/// ```
///
/// This is C++'s `std::tie(a, b.f, std::ignore) = value;`: the whole right
/// side is evaluated first, so `(a, b) = (b, a)` swaps, and each store is an
/// ordinary assignment.
fn destructuring_assignment(lhs: &ast::Expression, rhs: &ast::Expression, span: ast::Span) -> Result<Statement, Diagnostic> {
    let ast::Expression::Tuple { elements, .. } = lhs else { unreachable!("checked by the caller") };
    let (hidden, tuple, _) = hidden_tuple(rhs, elements.len())?;
    let mut items = vec![Statement::Declaration(Declaration::Variable(hidden))];
    assign_elements(&tuple, elements, span, &mut items)?;
    Ok(Statement::Block(Block { name: String::new(), items, attributes: vec![] }))
}

/// `place = tuple.index;` for each place of `(a, b.f, _) = ...` over the
/// hidden tuple local `tuple`, skipping `_`. A nested `(c, d)` gets a hidden
/// tuple local of its own, initialized from its element.
fn assign_elements(tuple: &str, places: &[ast::Expression], span: ast::Span, items: &mut Vec<Statement>) -> Result<(), Diagnostic> {
    for (index, place) in places.iter().enumerate() {
        if matches!(place, ast::Expression::SymbolRef { id, .. } if id == "_") {
            continue;
        }
        let at = loc(place.span());
        if let ast::Expression::Tuple { elements, .. } = place {
            let (hidden, inner) = hidden_tuple_of(tuple_element(tuple, index, at), elements.len(), at);
            items.push(Statement::Declaration(Declaration::Variable(hidden)));
            assign_elements(&inner, elements, span, items)?;
            continue;
        }
        items.push(Statement::Expression(Expression::Binary {
            op: BinaryOp::Assign,
            lhs: Box::new(expression(place)?),
            rhs: Box::new(tuple_element(tuple, index, at)),
            loc: loc(span),
        }));
    }
    Ok(())
}

thread_local! {
    /// Numbers each destructuring's hidden tuple local.
    static TUPLES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    /// Numbers each lowered `for` loop's hidden iterator local.
    static FOR_LOOPS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    /// Numbers each lowered `with` block's hidden locals.
    static WITH_BLOCKS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    /// Numbers each lowered `match` statement's hidden subject local.
    static MATCHES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// Restart hidden-local numbering (see `crate::reset_program_counters`).
pub(crate) fn reset_counters() {
    FOR_LOOPS.with(|c| c.set(0));
    WITH_BLOCKS.with(|c| c.set(0));
    TUPLES.with(|c| c.set(0));
    MATCHES.with(|c| c.set(0));
}

/// Lower `for (var x in source) body` to
///
/// ```text
/// {
///     var __for_iterator_N = <ForIterator(source)>;
///     while (__for_iterator_N.next()) {
///         var x = __for_iterator_N.current();
///         { body }
///     }
/// }
/// ```
///
/// Refcounting needs nothing new: the iterator is an owned local of the outer
/// block (released at loop exit, `break` and `return` included) and `x` is a
/// while-body local (released at the end of every iteration and at
/// `continue`). The body keeps its own block so it may shadow `x`.
fn for_loop(f: &ast::For) -> Result<Statement, Diagnostic> {
    let n = FOR_LOOPS.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    });
    let iterator = format!("__for_iterator_{}", n);
    // The hidden code is located at the iterable, so an error in it (say,
    // a type without `next`) points at what the loop iterates.
    let at = loc(f.iterable.span());
    let iterator_ref = || Box::new(Expression::SymbolRef { id: iterator.clone(), ty: TypeName::auto(), loc: at });
    let hidden_iterator = VariableDef {
        name: iterator.clone(),
        ty: TypeName::auto(),
        default: Some(Expression::ForIterator(Box::new(expression(&f.iterable)?))),
        hidden: true,
        kind: Kind::Variable,
        attributes: vec![],
        loc: at,
        type_loc: Loc::NONE,
        is_const: false,
    };
    let current = Expression::MethodCall { this: iterator_ref(), method: "current".to_string(), args: vec![], loc: at };
    let mut items = vec![];
    if f.pattern.is_empty() {
        let mut element = variable_def(&f.binding, Kind::Variable)?;
        element.default = Some(current);
        items.push(Statement::Declaration(Declaration::Variable(element)));
    } else {
        // `for (var (k, v) in pairs)`: destructure each element.
        let (hidden, tuple) = hidden_tuple_of(current, f.pattern.len(), loc(f.binding.span));
        items.push(Statement::Declaration(Declaration::Variable(hidden)));
        items.extend(bind_elements(&tuple, &f.pattern, false)?);
    }
    items.push(Statement::Block(block(&f.block)?));
    let body = Block { name: String::new(), items, attributes: vec![] };
    Ok(Statement::Block(Block {
        name: String::new(),
        items: vec![
            Statement::Declaration(Declaration::Variable(hidden_iterator)),
            Statement::While(While {
                condition: Expression::MethodCall { this: iterator_ref(), method: "next".to_string(), args: vec![], loc: at },
                block: body,
            }),
        ],
        attributes: vec![],
    }))
}

/// Lower `with (var x = scope) body else other` to
///
/// ```text
/// {
///     var __with_scope_N = scope;
///     var x = __with_scope_N.enter();      # __with_value_N when unnamed
///     if (<WithEntered(x)>) { body } else { other }
/// }
/// ```
///
/// Refcounting needs nothing new: both are owned locals of the outer block,
/// released in reverse order on every path out of it, so the bound value goes
/// first and the scope object's destructor (which calls `exit()`) can run
/// last. `lower_with_blocks` resolves the condition once `enter()`'s type is
/// known.
/// `match (e) { A, B => { x } C => { y } else => { z } }` becomes
///
/// ```text
/// { var __match_N = e; if (MatchArm(__match_N is A, B)) { x } else if (MatchArm(... C)) { y } else { z } }
/// ```
///
/// `enums::lower_matches` turns each `MatchArm` test into `==` tests once
/// the subject's type is known. A `match` with no arms still gets one test,
/// with no patterns, so its exhaustiveness is checked.
fn match_statement(m: &ast::Match) -> Result<Statement, Diagnostic> {
    let n = MATCHES.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    });
    let subject = format!("__match_{}", n);
    let at = loc(m.value.span());
    let hidden = VariableDef {
        name: subject.clone(),
        ty: TypeName::auto(),
        default: Some(expression(&m.value)?),
        hidden: true,
        kind: Kind::Variable,
        attributes: vec![],
        loc: at,
        type_loc: Loc::NONE,
        is_const: false,
    };
    let site = MatchSite {
        id: n,
        keyword: loc(m.keyword_span),
        else_arm: m.else_arm.as_ref().map(|(span, _)| loc(*span)),
    };
    let test = |patterns: Vec<CasePattern>| {
        Expression::MatchArm(Box::new(MatchArmTest {
            subject: Expression::SymbolRef { id: subject.clone(), ty: TypeName::auto(), loc: at },
            patterns,
            site: site.clone(),
        }))
    };
    let mut chain: Option<Block> = match &m.else_arm {
        Some((_, b)) => Some(block(b)?),
        None => None,
    };
    let mut arms: Vec<(Vec<CasePattern>, Block)> = vec![];
    for arm in &m.arms {
        let patterns = arm
            .patterns
            .iter()
            .map(|p| CasePattern {
                qualifier: p.qualifier.as_ref().map(type_name_from),
                case: p.case.clone(),
                loc: loc(p.case_span),
                bindings: p.bindings.as_ref().map(|b| b.iter().map(|(n, s)| (n.clone(), loc(*s))).collect()),
            })
            .collect();
        arms.push((patterns, block(&arm.body)?));
    }
    if arms.is_empty() {
        arms.push((vec![], Block { name: String::new(), items: vec![], attributes: vec![] }));
    }
    for (patterns, body) in arms.into_iter().rev() {
        let branch = Statement::Branch(Branch { condition: test(patterns), if_block: body, else_block: chain.take() });
        chain = Some(Block { name: String::new(), items: vec![branch], attributes: vec![] });
    }
    let mut items = vec![Statement::Declaration(Declaration::Variable(hidden))];
    items.extend(chain.map(|b| b.items).unwrap_or_default());
    Ok(Statement::Block(Block { name: String::new(), items, attributes: vec![] }))
}

fn with_block(w: &ast::With) -> Result<Statement, Diagnostic> {
    let n = WITH_BLOCKS.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    });
    let scope = format!("__with_scope_{}", n);
    let at = loc(w.scope.span());
    let hidden_scope = VariableDef {
        name: scope.clone(),
        ty: TypeName::auto(),
        default: Some(expression(&w.scope)?),
        hidden: true,
        kind: Kind::Variable,
        attributes: vec![],
        loc: at,
        type_loc: Loc::NONE,
        is_const: false,
    };
    let enter = Expression::MethodCall {
        this: Box::new(Expression::SymbolRef { id: scope, ty: TypeName::auto(), loc: at }),
        method: "enter".to_string(),
        args: vec![],
        loc: at,
    };
    let value = match &w.binding {
        Some(binding) => {
            let mut value = variable_def(binding, Kind::Variable)?;
            value.default = Some(enter);
            value
        }
        None => VariableDef {
            name: format!("__with_value_{}", n),
            ty: TypeName::auto(),
            default: Some(enter),
            hidden: true,
            kind: Kind::Variable,
            attributes: vec![],
            loc: at,
            type_loc: Loc::NONE,
            is_const: false,
        },
    };
    let entered = Expression::WithEntered(Box::new(Expression::SymbolRef {
        id: value.name.clone(),
        ty: TypeName::auto(),
        loc: value.loc,
    }));
    Ok(Statement::Block(Block {
        name: String::new(),
        items: vec![
            Statement::Declaration(Declaration::Variable(hidden_scope)),
            Statement::Declaration(Declaration::Variable(value)),
            Statement::Branch(Branch {
                condition: entered,
                if_block: block(&w.block)?,
                else_block: w.else_block.as_ref().map(block).transpose()?,
            }),
        ],
        attributes: vec![],
    }))
}

fn function_def(decl: &ast::FunctionDecl, parent: Option<String>) -> Result<FunctionDef, Diagnostic> {
    reject_implicit(&decl.attributes)?;
    member_def(decl, parent)
}

/// `[Implicit]` is a constructor attribute: anywhere else it is an error, at
/// the attribute.
fn reject_implicit(attributes: &[ast::Attribute]) -> Result<(), Diagnostic> {
    match implicit_attribute(attributes) {
        Some(attr) => Err(Diagnostic::error(format!("'{}' applies only to constructors", IMPLICIT_ATTRIBUTE))
            .at(loc(attr.span))),
        None => Ok(()),
    }
}

fn implicit_attribute(attributes: &[ast::Attribute]) -> Option<&ast::Attribute> {
    attributes
        .iter()
        .find(|a| matches!(&a.body, ast::Expression::SymbolRef { id, .. } if id == IMPLICIT_ATTRIBUTE))
}

/// An `[Implicit]` constructor converts a value of its parameter's type into
/// the struct, so it must take exactly one argument, and that argument must
/// not already be the struct or one of its type parameters (which would make
/// every value convert).
fn check_implicit_constructor(decl: &ast::StructDecl, ctor: &ast::FunctionDecl) -> Result<(), Diagnostic> {
    let Some(attr) = implicit_attribute(&ctor.attributes) else {
        return Ok(());
    };
    let at = loc(attr.span);
    let one_argument = ctor
        .parameters
        .split_first()
        .is_some_and(|(_, rest)| rest.iter().all(|p| p.default_value.is_some()));
    if !one_argument {
        return Err(Diagnostic::error(format!(
            "'{}' constructor of '{}' must be callable with one argument",
            IMPLICIT_ATTRIBUTE, decl.name
        ))
        .at(at));
    }
    let first = &ctor.parameters[0];
    // `this.field = default` takes the field's type.
    let from = match first.name.strip_prefix("this.") {
        Some(field) => match decl.fields.iter().find(|f| f.name == field) {
            Some(f) => type_name_from(&f.type_name),
            None => return Ok(()),
        },
        None => type_name_from(&first.type_name),
    };
    if from.sub_types.is_empty() && decl.generic_params.iter().any(|g| g.name == from.name) {
        return Err(Diagnostic::error(format!(
            "'{}' constructor of '{}' cannot convert from its type parameter '{}'",
            IMPLICIT_ATTRIBUTE, decl.name, from.name
        ))
        .at(at));
    }
    if from.name == decl.name {
        return Err(Diagnostic::error(format!(
            "'{}' constructor of '{}' cannot convert from '{}'",
            IMPLICIT_ATTRIBUTE,
            decl.name,
            from.display()
        ))
        .at(at));
    }
    Ok(())
}

/// A function or struct member, with no check on its attributes.
fn member_def(decl: &ast::FunctionDecl, parent: Option<String>) -> Result<FunctionDef, Diagnostic> {
    check_deprecation(&decl.attributes)?;
    let parameters: Vec<VariableDef> = decl
        .parameters
        .iter()
        .map(|p| variable_def(p, Kind::Param))
        .collect::<Result<Vec<_>, _>>()?;
    let body = decl.body.as_ref().map(block).transpose()?;
    // A comparison's result is a condition; codegen tests it as an i1.
    let declared = &decl.return_type;
    if matches!(decl.name.as_str(), "==" | "!=" | "<" | "<=" | ">" | ">=")
        && declared.name != crate::type_name::AUTO
        && declared.name != "bool"
    {
        return Err(Diagnostic::error(format!(
            "comparison operator '{}' must return 'bool', not '{}'",
            decl.name,
            type_name_from(declared)
        ))
        .at(loc(declared.span)));
    }
    // `!` and the truth test `!!` are conditions too.
    if matches!(decl.name.as_str(), "!" | "!!")
        && declared.name != crate::type_name::AUTO
        && declared.name != "bool"
    {
        let kind = if decl.name == "!" { "logical" } else { "truth-test" };
        return Err(Diagnostic::error(format!(
            "{} operator '{}' must return 'bool', not '{}'",
            kind,
            decl.name,
            type_name_from(declared)
        ))
        .at(loc(declared.span)));
    }
    // Unary-only operators take their operand as `this`.
    if matches!(decl.name.as_str(), "!" | "!!" | "~") && !decl.is_static && !decl.parameters.is_empty() {
        return Err(Diagnostic::error(format!(
            "unary operator '{}' takes no parameters, have {}",
            decl.name,
            decl.parameters.len()
        ))
        .at(loc(decl.name_span)));
    }
    Ok(FunctionDef {
        trait_default: None,
        name: decl.name.clone(),
        ty: type_name_from(&decl.return_type),
        generic_params: decl.generic_params.iter().map(generic_param_from).collect(),
        parameters,
        body,
        parent,
        is_static: decl.is_static,
        is_indexer: decl.is_indexer,
        is_generic_func: !decl.generic_params.is_empty(),
        attributes: decl.attributes.clone(),
        loc: loc(decl.name_span),
    })
}

fn declaration(decl: &ast::Declaration) -> Result<Declaration, Diagnostic> {
    match decl {
        ast::Declaration::Variable(v) => {
            Ok(Declaration::Variable(variable_def(v, Kind::Variable)?))
        }
        ast::Declaration::Function(f) => Ok(Declaration::Function(function_def(f, None)?)),
        ast::Declaration::Struct(s) if s.enumeration.is_some() => {
            Err(Diagnostic::error("enums are top-level declarations").at(loc(s.name_span)))
        }
        ast::Declaration::Struct(s) => Ok(Declaration::Struct(struct_def(s)?)),
        ast::Declaration::Trait(t) => Ok(Declaration::Trait(trait_def(t)?)),
        ast::Declaration::Extend(e) => Ok(Declaration::Extension(extension_def(e)?)),
        ast::Declaration::TypeAlias(t) => {
            Err(Diagnostic::error("type aliases are top-level declarations").at(loc(t.name_span)))
        }
    }
}
fn trait_def(t: &ast::TraitDecl) -> Result<TraitDef, Diagnostic> {
    check_deprecation(&t.attributes)?;
    reject_implicit(&t.attributes)?;
    Ok(TraitDef {
        name: t.name.clone(),
        generic_params: t.generic_params.iter().map(generic_param_from).collect(),
        methods: t.methods.iter().map(|m| function_def(m, None)).collect::<Result<Vec<_>, _>>()?,
        attributes: t.attributes.clone(),
        loc: loc(t.name_span),
    })
}

fn extension_def(e: &ast::ExtendDecl) -> Result<ExtensionDef, Diagnostic> {
    reject_deprecation(&e.attributes, "an extension; deprecate its methods instead")?;
    reject_implicit(&e.attributes)?;
    Ok(ExtensionDef {
        target: type_name_from(&e.target),
        resolved: None,
        traits: e.traits.iter().map(type_name_from).collect(),
        methods: e.methods.iter().map(|m| function_def(m, None)).collect::<Result<Vec<_>, _>>()?,
        attributes: e.attributes.clone(),
        loc: loc(e.target.span),
        is_exported: e.is_exported,
    })
}

/// Build a `StructDef` from an AST struct declaration, including constructor
/// and destructor shells (filled in by `struct_body::finish`).
fn struct_def(decl: &ast::StructDecl) -> Result<StructDef, Diagnostic> {
    check_deprecation(&decl.attributes)?;
    reject_implicit(&decl.attributes)?;
    if let Some(body) = &decl.destructor {
        reject_deprecation(&body.attributes, "a destructor")?;
        reject_implicit(&body.attributes)?;
    }
    let generic_params: Vec<GenericParam> = decl.generic_params.iter().map(generic_param_from).collect();
    let base_name = decl.name.clone();
    let ty = if generic_params.is_empty() {
        TypeName::new(&base_name)
    } else {
        TypeName::with_args(&base_name, generic_params.iter().map(|p| TypeName::new(&p.name)).collect())
    };
    let field_members: Vec<VariableDef> = decl
        .fields
        .iter()
        .map(|f| variable_def(f, Kind::Field))
        .collect::<Result<Vec<_>, _>>()?;
    let (generic_methods, method_members): (Vec<FunctionDef>, Vec<FunctionDef>) = decl
        .methods
        .iter()
        .map(|m| function_def(m, Some(base_name.clone())))
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .partition(|m| m.is_generic_func);

    // Several constructors overload one another as the set `Point$1`,
    // `Point$2`, … (declaration order); a single one is named after the type.
    let mut constructors = vec![];
    let mut implicit: Option<&ast::FunctionDecl> = None;
    for (index, ctor) in decl.constructors.iter().enumerate() {
        check_implicit_constructor(decl, ctor)?;
        if let Some(attr) = implicit_attribute(&ctor.attributes) {
            if let Some(first) = implicit {
                return Err(Diagnostic::error(format!(
                    "only one constructor of '{}' may be '{}'",
                    decl.name, IMPLICIT_ATTRIBUTE
                ))
                .at(loc(attr.span))
                .with_note("previous implicit constructor is here", Some(loc(first.name_span))));
            }
            implicit = Some(ctor);
        }
        let mut f = member_def(ctor, Some(base_name.clone()))?;
        f.name = if decl.constructors.len() == 1 {
            ty.to_string()
        } else {
            format!("{}{}{}", ty, pepper_parser::namespace::OVERLOAD_SEPARATOR, index + 1)
        };
        f.ty = ty.clone();
        constructors.push(f);
    }
    if constructors.is_empty() {
        constructors.push(FunctionDef {
            trait_default: None,
            name: ty.to_string(),
            ty: ty.clone(),
            generic_params: vec![],
            parameters: vec![],
            body: Some(Block {
                name: String::new(),
                items: vec![],
                attributes: vec![],
            }),
            parent: Some(base_name.clone()),
            is_static: false,
            is_indexer: false,
            is_generic_func: false,
            attributes: vec![],
            loc: loc(decl.name_span),
        });
    }
    let destructor = match &decl.destructor {
        Some(body) => FunctionDef {
            trait_default: None,
            name: "__dtor".to_string(),
            ty: TypeName::void(),
            generic_params: vec![],
            parameters: vec![],
            body: Some(block(body)?),
            parent: Some(base_name.clone()),
            is_static: false,
            is_indexer: false,
            is_generic_func: false,
            attributes: body.attributes.clone(),
            loc: loc(decl.name_span),
        },
        None => FunctionDef {
            trait_default: None,
            name: "__dtor".to_string(),
            ty: TypeName::void(),
            generic_params: vec![],
            parameters: vec![],
            body: Some(Block {
                name: String::new(),
                items: vec![],
                attributes: vec![],
            }),
            parent: Some(base_name.clone()),
            is_static: false,
            is_indexer: false,
            is_generic_func: false,
            attributes: vec![],
            loc: loc(decl.name_span),
        },
    };

    Ok(StructDef {
        name: base_name.clone(),
        ty,
        generic_params,
        field_members,
        method_members,
        generic_methods,
        constructors,
        destructor,
        acquire: empty_method(&base_name, "__acquire"),
        release: empty_method(&base_name, "__release"),
        traits: vec![],
        attributes: decl.attributes.clone(),
        loc: loc(decl.name_span),
    })
}

/// Build an [`EnumDef`] from an `enum` declaration: its cases and their
/// values. Cases number from 0 in order; `= N` sets a case's value and the
/// cases after it continue from `N + 1`.
fn enum_def(decl: &ast::StructDecl) -> Result<EnumDef, Diagnostic> {
    check_deprecation(&decl.attributes)?;
    reject_implicit(&decl.attributes)?;
    let body = decl.enumeration.as_ref().expect("an enum declaration");
    if let Some(p) = decl.generic_params.first() {
        return Err(Diagnostic::error(format!(
            "enum '{}' cannot be generic: its cases carry no values",
            decl.name
        ))
        .at(loc(p.name_span)));
    }
    if let Some(m) = decl.methods.first() {
        return Err(Diagnostic::error(format!("methods on enums are not supported yet ('{}')", decl.name))
            .at(loc(m.name_span)));
    }
    let representation = match &body.representation {
        Some(t) => {
            let ty = type_name_from(t);
            if !ty.is_integral() || ty.name == "bool" {
                return Err(Diagnostic::error(format!(
                    "'{}' is not an integer type; an enum is stored as one of 'byte', 'short', 'int', 'long' or their unsigned forms",
                    t
                ))
                .at(loc(t.span)));
            }
            ty
        }
        None => TypeName::new("int"),
    };
    let (min, max) = integer_range(&representation.name);
    let mut cases: Vec<EnumCaseDef> = vec![];
    let mut next: i128 = 0;
    for case in &body.cases {
        check_deprecation(&case.attributes)?;
        reject_implicit(&case.attributes)?;
        if case.payload.is_some() {
            return Err(Diagnostic::error(format!(
                "cases that carry values are not supported yet ('{}')",
                case.name
            ))
            .at(loc(case.name_span)));
        }
        if let Some(previous) = cases.iter().find(|c| c.name == case.name) {
            return Err(Diagnostic::error(format!("redefinition of case '{}'", case.name))
                .at(loc(case.name_span))
                .with_note("previous definition is here", Some(previous.loc)));
        }
        let value = match &case.value {
            Some(e) => constant_integer(e).ok_or_else(|| {
                Diagnostic::error(format!("the value of case '{}' must be an integer constant", case.name))
                    .at(loc(e.span()))
            })?,
            None => next,
        };
        if value < min || value > max {
            let at = case.value.as_ref().map_or(case.name_span, |e| e.span());
            return Err(Diagnostic::error(format!(
                "value {} of case '{}' does not fit in '{}'",
                value, case.name, representation.name
            ))
            .at(loc(at)));
        }
        if let Some(previous) = cases.iter().find(|c| c.value as i128 == value) {
            return Err(Diagnostic::error(format!(
                "case '{}' has the same value as '{}' ({})",
                case.name, previous.name, value
            ))
            .at(loc(case.name_span))
            .with_note(format!("'{}' declared here", previous.name), Some(previous.loc)));
        }
        cases.push(EnumCaseDef {
            name: case.name.clone(),
            value: value as i64,
            attributes: case.attributes.clone(),
            loc: loc(case.name_span),
        });
        next = value + 1;
    }
    Ok(EnumDef {
        name: decl.name.clone(),
        representation,
        cases,
        attributes: decl.attributes.clone(),
        loc: loc(decl.name_span),
    })
}

/// The smallest and largest value of an integer type.
fn integer_range(name: &str) -> (i128, i128) {
    match name {
        "i8" | "char" => (i8::MIN as i128, i8::MAX as i128),
        "u8" | "byte" => (0, u8::MAX as i128),
        "i16" | "short" => (i16::MIN as i128, i16::MAX as i128),
        "u16" | "ushort" => (0, u16::MAX as i128),
        "u32" | "uint" => (0, u32::MAX as i128),
        "i64" | "long" => (i64::MIN as i128, i64::MAX as i128),
        "u64" | "ulong" => (0, u64::MAX as i128),
        _ => (i32::MIN as i128, i32::MAX as i128),
    }
}

/// The value of an integer constant: a literal, a character literal, or
/// either negated.
fn constant_integer(e: &ast::Expression) -> Option<i128> {
    match e {
        ast::Expression::Literal { value: ast::Literal::Integer(v), .. } => Some(*v as i128),
        ast::Expression::Literal { value: ast::Literal::Char(v), .. } => Some(*v as i128),
        ast::Expression::Unary { op, prefix: true, operand, .. } if op == "-" => constant_integer(operand).map(|v| -v),
        ast::Expression::Unary { op, prefix: true, operand, .. } if op == "+" => constant_integer(operand),
        _ => None,
    }
}

fn empty_method(parent: &str, name: &str) -> FunctionDef {
    FunctionDef {
        trait_default: None,
        name: name.to_string(),
        ty: TypeName::void(),
        generic_params: vec![],
        parameters: vec![],
        body: Some(Block {
            name: String::new(),
            items: vec![],
            attributes: vec![],
        }),
        parent: Some(parent.to_string()),
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
        attributes: vec![],
        loc: Loc::NONE,
    }
}

/// Parse-level module → model module (no synthesized members yet; call
/// [`struct_body::apply_synthesized`] afterwards). Locations carry the
/// default [`FileId`]; see [`build_file`].
pub fn build(module: &ast::Module) -> Result<Module, Diagnostic> {
    build_file(module, FileId::default())
}

/// [`build`], with every location pointing into `file`.
pub fn build_file(module: &ast::Module, file: FileId) -> Result<Module, Diagnostic> {
    let previous = FILE.with(|f| f.replace(file));
    let previous_error = LABEL_ERROR.with(|e| e.take());
    let built = build_module(module);
    let label_error = LABEL_ERROR.with(|e| e.replace(previous_error));
    FILE.with(|f| f.set(previous));
    match label_error {
        Some(error) => Err(error),
        None => built,
    }
}

fn build_module(module: &ast::Module) -> Result<Module, Diagnostic> {
    let mut out = Module::default();
    out.imports = module.imports.clone();
    for decl in &module.declarations {
        match decl {
            ast::Declaration::Variable(v) => {
                // Module-scope variable: an addressable global, not a
                // function. The initializer (if any) is codegen'd into the
                // global's constant initializer or an init function.
                out.globals.push(variable_def(v, Kind::Variable)?);
            }
            ast::Declaration::Function(f) => {
                if f.external {
                    check_deprecation(&f.attributes)?;
                    reject_implicit(&f.attributes)?;
                    out.externs.push(ExternDef {
                        name: f.name.clone(),
                        ty: type_name_from(&f.return_type),
                        parameters: f
                            .parameters
                            .iter()
                            .map(|p| variable_def(p, Kind::Param))
                            .collect::<Result<Vec<_>, _>>()?,
                        is_variadic: f.is_variadic,
                        attributes: f.attributes.clone(),
                        loc: loc(f.name_span),
                    });
                } else {
                    out.functions.push(function_def(f, None)?);
                }
            }
            ast::Declaration::Struct(s) if s.enumeration.is_some() => out.enums.push(enum_def(s)?),
            ast::Declaration::Struct(s) => out.structs.push(struct_def(s)?),
            ast::Declaration::Trait(t) => out.traits.push(trait_def(t)?),
            ast::Declaration::Extend(e) => out.extensions.push(extension_def(e)?),
            ast::Declaration::TypeAlias(t) => {
                check_deprecation(&t.attributes)?;
                reject_implicit(&t.attributes)?;
                out.type_aliases.push(TypeAliasDef {
                    name: t.name.clone(),
                    generic_params: t.generic_params.iter().map(generic_param_from).collect(),
                    target: type_name_from(&t.target),
                    attributes: t.attributes.clone(),
                    loc: loc(t.name_span),
                })
            }
        }
    }
    Ok(out)
}
