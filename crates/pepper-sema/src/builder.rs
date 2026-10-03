//! AST → model builder: port of `source/Sema/ModelBuilder.cpp` (`SemaParser`),
//! without the C++ Builder scope machinery — the model tree is built directly.

use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;
use pepper_parser::diagnostic::{Diagnostic, FileId};

mod static_items;
mod tries;
pub(crate) use static_items::{INTERPOLATE, REFLECT};
pub(crate) use tries::TRY_LOCAL;

thread_local! {
    /// The file being built, whose id every location built carries. Set by
    /// [`build_file`] for the duration of one build.
    static FILE: std::cell::Cell<FileId> = const { std::cell::Cell::new(FileId(0)) };
    /// The first bad tuple label [`type_name_from`] met. It returns a plain
    /// type, so [`build_file`] reports this once the build finishes.
    static LABEL_ERROR: std::cell::RefCell<Option<Diagnostic>> = const { std::cell::RefCell::new(None) };
    /// The declared return type of the function or closure whose body is
    /// being built, for [`check_literal_labels`] on its `return`s.
    static RETURN_TYPE: std::cell::RefCell<Option<ast::TypeName>> = const { std::cell::RefCell::new(None) };
    /// The generic types written with arguments so far, for
    /// `passes::constraints` (see [`TypeUse`]), and their contexts.
    static TYPE_USES: std::cell::RefCell<(Vec<TypeUse>, Vec<UseContext>)> = const { std::cell::RefCell::new((vec![], vec![])) };
    /// The context where types are being built: the generic parameters in
    /// scope, the extended type inside `extend`, and the enclosing
    /// attributes.
    static CONTEXT: std::cell::RefCell<UseContext> = std::cell::RefCell::new(UseContext::default());
    /// The index of `CONTEXT` in the recorded contexts, once a use recorded
    /// it; cleared whenever it changes.
    static CONTEXT_INDEX: std::cell::Cell<Option<usize>> = const { std::cell::Cell::new(None) };
    /// The literal arguments of the calls built so far (see
    /// `Module::literal_args`).
    static LITERAL_ARGS: std::cell::RefCell<Vec<(Loc, usize, Loc)>> = const { std::cell::RefCell::new(vec![]) };
    /// The properties built so far in this file (see [`property_members`]).
    static PROPERTIES: std::cell::RefCell<Vec<PropertyDef>> = const { std::cell::RefCell::new(vec![]) };
}

/// Records where each literal among `arguments` of the call at `call` is
/// written (`-1` included).
fn record_literal_args(call: Loc, arguments: &[ast::Expression]) {
    for (i, arg) in arguments.iter().enumerate() {
        let literal = match arg {
            ast::Expression::Literal { span, .. } => Some(*span),
            ast::Expression::Unary { operand, span, .. } if matches!(operand.as_ref(), ast::Expression::Literal { .. }) => Some(*span),
            _ => None,
        };
        if let Some(span) = literal {
            LITERAL_ARGS.with(|l| l.borrow_mut().push((call, i, loc(span))));
        }
    }
}

/// Builds with `change` applied to the context, restoring it afterwards.
fn in_context<T>(change: impl FnOnce(&mut UseContext), build: impl FnOnce() -> T) -> T {
    let saved = CONTEXT.with(|c| {
        let mut c = c.borrow_mut();
        let saved = c.clone();
        change(&mut c);
        saved
    });
    let index = CONTEXT_INDEX.with(|i| i.take());
    let built = build();
    CONTEXT.with(|c| *c.borrow_mut() = saved);
    CONTEXT_INDEX.with(|i| i.set(index));
    built
}

/// Builds code that carries `attributes`, so a use inside it is skipped
/// when a `[Target(...)]` among them removes it on this platform.
fn with_attributes<T>(attributes: &[ast::Attribute], build: impl FnOnce() -> T) -> T {
    if attributes.is_empty() {
        return build();
    }
    in_context(|c| c.conditions.extend(attributes.iter().cloned()), build)
}

/// Records a use of `ty` whose arguments are at `args`, in the current
/// context.
fn push_type_use(ty: TypeName, args: Vec<Loc>) {
    let context = CONTEXT_INDEX.with(|i| i.get()).unwrap_or_else(|| {
        let context = CONTEXT.with(|c| c.borrow().clone());
        let index = TYPE_USES.with(|u| {
            let mut u = u.borrow_mut();
            u.1.push(context);
            u.1.len() - 1
        });
        CONTEXT_INDEX.with(|i| i.set(Some(index)));
        index
    });
    TYPE_USES.with(|u| u.borrow_mut().0.push(TypeUse { ty, args, context }));
}

/// Builds a declaration with `params` in scope, and inside `extend
/// extension` when that is given, so the type uses it records know them.
fn in_generic_scope<T>(params: &[ast::GenericParam], extension: Option<&ast::TypeName>, build: impl FnOnce() -> T) -> T {
    // The declaration records its parameters' own uses, in scope.
    let recorded = TYPE_USES.with(|u| u.borrow().0.len());
    let params: Vec<GenericParam> = params.iter().filter(|p| !p.is_argument).map(generic_param_from).collect();
    let extension = extension.map(type_name_from);
    TYPE_USES.with(|u| u.borrow_mut().0.truncate(recorded));
    if params.is_empty() && extension.is_none() {
        return build();
    }
    in_context(
        |c| {
            c.scope.extend(params);
            if extension.is_some() {
                c.extension = extension;
            }
        },
        build,
    )
}

/// Records `t`, a generic type written with arguments, as `ty`.
fn record_type_use(t: &ast::TypeName, ty: &TypeName) {
    let named = !t.name.starts_with("__") && !t.name.ends_with("[]") && t.name != "Tuple";
    if !named || t.generic_types.is_empty() || t.generic_types.iter().any(|a| a.span.is_empty()) {
        return;
    }
    push_type_use(ty.clone(), t.generic_types.iter().map(|a| loc(a.span)).collect());
}

/// Builds a body with `returns` as the declared return type of its `return`s.
fn with_return_type<T>(returns: &ast::TypeName, build: impl FnOnce() -> T) -> T {
    let previous = RETURN_TYPE.with(|r| r.replace(Some(returns.clone())));
    let built = build();
    RETURN_TYPE.with(|r| *r.borrow_mut() = previous);
    built
}

/// Rejects a labeled tuple literal whose labels differ from those of the
/// labeled tuple type `expected` it initializes or returns, element by
/// element and into nested tuples: `var p: (line: int, column: int) =
/// (column: 7, line: 3);` would otherwise silently swap its meaning.
fn check_literal_labels(expected: &ast::TypeName, value: &ast::Expression) -> Result<(), Diagnostic> {
    let ast::Expression::Tuple { elements, labels, .. } = value else { return Ok(()) };
    if expected.name != ast::TUPLE_TYPE || expected.generic_types.len() != elements.len() {
        return Ok(());
    }
    if !expected.labels.is_empty() {
        for (i, (label, at)) in labels.iter().enumerate() {
            if *label != expected.labels[i] {
                return Err(Diagnostic::error(format!(
                    "label '{}' does not match '{}', the label of element {} of '{}'",
                    label,
                    expected.labels[i],
                    i,
                    type_name_from(expected).display()
                ))
                .at(loc(*at)));
            }
        }
    }
    for (element_type, element) in expected.generic_types.iter().zip(elements) {
        check_literal_labels(element_type, element)?;
    }
    Ok(())
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
        record_type_use(t, &ty);
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
        loc: loc(p.name_span),
        bounds: p.bounds.iter().map(|b| Bound { ty: type_name_from(b), loc: loc(b.span) }).collect(),
        default: p.default.as_ref().map(type_name_from),
        default_loc: p.default.as_ref().map_or(Loc::NONE, |d| loc(d.span)),
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

/// A call's arguments: positional ones first, then named ones
/// (`name = value`), which stay [`Expression::NamedArgument`]s until
/// `named_arguments` binds the call.
fn call_arguments(arguments: &[ast::Expression]) -> Result<Vec<Expression>, Diagnostic> {
    let mut named = None;
    arguments
        .iter()
        .map(|argument| match argument {
            ast::Expression::NamedArgument { name, name_span, value, .. } => {
                named.get_or_insert(*name_span);
                Ok(Expression::NamedArgument { name: name.clone(), value: Box::new(expression(value)?), loc: loc(*name_span) })
            }
            positional => match named {
                Some(first) => Err(Diagnostic::error("positional argument cannot follow a named argument")
                    .at(loc(positional.span()))
                    .with_note("first named argument here", Some(loc(first)))),
                None => expression(positional),
            },
        })
        .collect()
}

fn expression(expr: &ast::Expression) -> Result<Expression, Diagnostic> {
    // `field.name` in a statement a `static` block emits.
    if let Some(placeholder) = static_items::placeholder(expr)? {
        return Ok(placeholder);
    }
    match expr {
        ast::Expression::NamedArgument { name_span, .. } => {
            Err(Diagnostic::error("a named argument can only appear in a call").at(loc(*name_span)))
        }
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
                kind: CastKind::Synthesized,
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
        // A `?` that `tries::lift` left: not in a statement of a function body.
        ast::Expression::Unary { op, prefix: false, span, .. } if op == "?" => {
            Err(Diagnostic::error("'?' can be used only in a statement of a function body")
                .at(loc(ast::Span { start: span.end - 1, end: span.end })))
        }
        ast::Expression::Unary { op, prefix, operand, span } => Ok(Expression::Unary {
            op: unary_op(op, *prefix)
                .ok_or_else(|| Diagnostic::error(format!("unsupported unary operator '{}'", op)).at(loc(*span)))?,
            operand: Box::new(expression(operand)?),
            loc: loc(*span),
        }),
        ast::Expression::Cast { expr, ty, keyword_span, optional: true, span } => optional_cast(expr, ty, *keyword_span, *span),
        ast::Expression::Cast { expr, ty, keyword_span, .. } => Ok(Expression::Cast {
            expr: Box::new(expression(expr)?),
            ty: type_name_from(ty),
            loc: loc(*keyword_span),
            kind: CastKind::Static,
        }),
        // `a..b` is `_range(a, b, false)` and `a..>b` is `_range(a, b, true)`
        // (runtime/range.pep): a `Range<T>` value, its `T` inferred from the
        // bounds like any generic call.
        ast::Expression::Binary { lhs, op, rhs, span } if op == ".." || op == "..>" => Ok(Expression::FunctionCall {
            function: crate::passes::ranges::RANGE_FUNCTION.to_string(),
            args: vec![expression(lhs)?, expression(rhs)?, Expression::BoolLiteral(op == "..>")],
            // Located at the operator, which a binary expression's span starts at.
            loc: loc(ast::Span { start: span.start, end: span.start + op.len() }),
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
                record_literal_args(loc(*name_span), arguments);
                return Ok(Expression::MethodCall {
                    this: Box::new(expression(lhs)?),
                    method: name.clone(),
                    args: call_arguments(arguments)?,
                    loc: loc(*name_span),
                });
            }
            match function.as_ref() {
                ast::Expression::TypeLiteral(ty) if ty.name == UNSAFE_CAST => return unsafe_cast(ty, arguments),
                ast::Expression::SymbolRef { id, span } if id == UNSAFE_CAST => {
                    return Err(Diagnostic::error("'unsafe_cast' needs the type to cast to: 'unsafe_cast<T>(value)'").at(loc(*span)));
                }
                _ => {}
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
                        args: call_arguments(arguments)?,
                    });
                }
            };
            // The arithmetic intrinsics (`__wrapping_add(a, b)`, ...) are
            // operators without syntax.
            if let Some(op) = BinaryOp::intrinsic(&function)
                && let [lhs, rhs] = arguments.as_slice()
                && !matches!(lhs, ast::Expression::NamedArgument { .. })
                && !matches!(rhs, ast::Expression::NamedArgument { .. })
            {
                return Ok(Expression::Binary {
                    op,
                    lhs: Box::new(expression(lhs)?),
                    rhs: Box::new(expression(rhs)?),
                    loc: loc(target.span()),
                });
            }
            record_literal_args(loc(target.span()), arguments);
            Ok(Expression::FunctionCall {
                function,
                args: call_arguments(arguments)?,
                loc: loc(target.span()),
            })
        }
        // `(a, b)`: a call of the tuple constructor, whose type
        // `resolve_implicit_types` spells out once the elements' types are
        // known (`__tuple<int, String>(a, b)`).
        // A labeled literal `(line: 3, column: 7)` calls
        // `__tuple(line,column)`, so its type carries the labels.
        ast::Expression::Tuple { elements, labels, span } => {
            for (i, (label, at)) in labels.iter().enumerate() {
                if let Some((_, first)) = labels[..i].iter().find(|(l, _)| l == label) {
                    return Err(Diagnostic::error(format!("duplicate label '{}' in tuple", label))
                        .at(loc(*at))
                        .with_note("previous label here", Some(loc(*first))));
                }
            }
            Ok(Expression::FunctionCall {
                function: crate::passes::tuples::constructor_name(labels.iter().map(|(l, _)| l.as_str())),
                args: elements.iter().map(expression).collect::<Result<Vec<_>, _>>()?,
                loc: loc(*span),
            })
        }
        ast::Expression::ArrayLiteral { elements, span } => array_literal(elements, *span, None),
        ast::Expression::MapLiteral { entries, span } => map_literal(entries, *span, None),
        ast::Expression::Match(m) => match_expression(m),
        ast::Expression::Is { value, pattern, keyword_span, .. } => is_expression(value, pattern, *keyword_span),
        ast::Expression::Closure(c) => Ok(Expression::ClosureLiteral(Box::new(ClosureLiteral {
            parameters: c.parameters.iter().map(|p| variable_def(p, Kind::Param)).collect::<Result<Vec<_>, _>>()?,
            ty: type_name_from(&c.return_type),
            body: with_return_type(&c.return_type, || block(&c.body))?,
            expression_body: c.expression_body,
            loc: loc(c.span),
        }))),
    }
}
/// The intrinsic `unsafe_cast<T>(value)` (`crate::casts`).
const UNSAFE_CAST: &str = "unsafe_cast";

/// `unsafe_cast<T>(value)`: a reinterpret cast of `value` to `T`, located at
/// the `unsafe_cast` name.
fn unsafe_cast(ty: &ast::TypeName, arguments: &[ast::Expression]) -> Result<Expression, Diagnostic> {
    let at = loc(ast::Span { start: ty.span.start, end: ty.span.start + UNSAFE_CAST.len() });
    if ty.generic_types.len() != 1 {
        return Err(Diagnostic::error(format!(
            "'unsafe_cast' takes 1 type argument, have {}",
            ty.generic_types.len()
        ))
        .at(at));
    }
    let [value] = arguments else {
        let which = if arguments.is_empty() { "few" } else { "many" };
        return Err(Diagnostic::error(format!(
            "too {} arguments to 'unsafe_cast': expected 1, have {}",
            which,
            arguments.len()
        ))
        .at(at));
    };
    if let ast::Expression::NamedArgument { name_span, .. } = value {
        return Err(Diagnostic::error("'unsafe_cast' takes no named arguments").at(loc(*name_span)));
    }
    Ok(Expression::Cast {
        expr: Box::new(expression(value)?),
        ty: type_name_from(&ty.generic_types[0]),
        loc: at,
        kind: CastKind::Unsafe,
    })
}

/// `[a, b, c]` is `_array_literal(a)._literal_append(b)._literal_append(c)`
/// (runtime/array.pep; a long literal is a tree of such chains, see
/// `literals.rs`). The element type is `element` when the literal
/// initializes a variable declared as an `Array` or `HashSet`
/// (`long[] a = [1, 2]`), else the first element's type, inferred like any
/// generic call's; each later element converts to it. A literal flowing into
/// any other `Array` slot is retyped by `convert_to_traits`.
fn array_literal(elements: &[ast::Expression], span: ast::Span, element: Option<&TypeName>) -> Result<Expression, Diagnostic> {
    let Some((first, rest)) = elements.split_first() else {
        return match element {
            Some(ty) => Ok(Expression::FunctionCall { function: format!("Array<{}>", ty), args: vec![], loc: loc(span) }),
            None => Err(Diagnostic::error(
                "empty array literal has no element type; declare the variable's type or write 'Array<T>()'",
            )
            .at(loc(span))),
        };
    };
    let function = match element {
        Some(ty) => format!("_array_literal<{}>", ty),
        None => "_array_literal".to_string(),
    };
    let start = Expression::FunctionCall { function, args: vec![typed_expression(first, element)?], loc: loc(span) };
    let steps = rest.iter().map(|item| Ok(vec![typed_expression(item, element)?])).collect::<Result<Vec<_>, Diagnostic>>()?;
    Ok(crate::literals::build(start, steps, "_literal_append", TypeName::auto(), loc(span)))
}

/// `[k1: v1, k2: v2]` is `_map_literal(k1, v1)._literal_insert(k2, v2)`
/// (runtime/hash.pep), typed like an array literal: by the declared
/// `HashMap<K, V>` when there is one (`types`), else by the first entry.
fn map_literal(
    entries: &[(ast::Expression, ast::Expression)],
    span: ast::Span,
    types: Option<(&TypeName, &TypeName)>,
) -> Result<Expression, Diagnostic> {
    let Some(((first_key, first_value), rest)) = entries.split_first() else {
        return match types {
            Some((key, value)) => Ok(Expression::FunctionCall {
                function: format!("HashMap<{}, {}>", key, value),
                args: vec![],
                loc: loc(span),
            }),
            None => Err(Diagnostic::error(
                "empty map literal has no key or value type; declare the variable's type or write 'HashMap<K, V>()'",
            )
            .at(loc(span))),
        };
    };
    let function = match types {
        Some((key, value)) => format!("_map_literal<{}, {}>", key, value),
        None => "_map_literal".to_string(),
    };
    let (key_type, value_type) = (types.map(|t| t.0), types.map(|t| t.1));
    let entry = |key: &ast::Expression, value: &ast::Expression| -> Result<Vec<Expression>, Diagnostic> {
        Ok(vec![typed_expression(key, key_type)?, typed_expression(value, value_type)?])
    };
    let start = Expression::FunctionCall { function, args: entry(first_key, first_value)?, loc: loc(span) };
    let steps = rest.iter().map(|(key, value)| entry(key, value)).collect::<Result<Vec<_>, _>>()?;
    Ok(crate::literals::build(start, steps, "_literal_insert", TypeName::auto(), loc(span)))
}

/// `expr` initializing a slot of type `ty`: a collection literal takes its
/// types from it (`long[][] a = [[1], [2]]`).
fn typed_expression(expr: &ast::Expression, ty: Option<&TypeName>) -> Result<Expression, Diagnostic> {
    match (expr, ty) {
        (ast::Expression::ArrayLiteral { elements, span }, Some(ty)) if literal_element(ty).is_some() => {
            array_literal(elements, *span, literal_element(ty))
        }
        (ast::Expression::MapLiteral { entries, span }, Some(ty)) if map_types(ty).is_some() => {
            map_literal(entries, *span, map_types(ty))
        }
        _ => expression(expr),
    }
}

/// The element type an array literal takes in a slot of type `ty`: the `T`
/// of `Array<T>`, or the `K` of `HashSet<K>` (which converts from an array).
fn literal_element(ty: &TypeName) -> Option<&TypeName> {
    ((ty.name == "Array" || ty.name == "HashSet") && ty.sub_types.len() == 1).then(|| &ty.sub_types[0])
}

/// The key and value types of `HashMap<K, V>`.
fn map_types(ty: &TypeName) -> Option<(&TypeName, &TypeName)> {
    (ty.name == "HashMap" && ty.sub_types.len() == 2).then(|| (&ty.sub_types[0], &ty.sub_types[1]))
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
    with_attributes(&decl.attributes, || variable_in_context(decl, kind))
}

fn variable_in_context(decl: &ast::VariableDecl, kind: Kind) -> Result<VariableDef, Diagnostic> {
    check_deprecation(&decl.attributes)?;
    reject_implicit(&decl.attributes)?;
    let mut ty = type_name_from(&decl.type_name);
    // `const X = "text";` is a `StringConstant`: it never changes, so it
    // keeps the literal's constant bytes and allocates nothing.
    if decl.is_const
        && ty.is_auto()
        && matches!(decl.default_value, Some(ast::Expression::Literal { value: ast::Literal::String(_), .. }))
    {
        ty = TypeName::new(crate::passes::convert_to_traits::STRING_CONSTANT);
    }
    if let Some(value) = &decl.default_value {
        check_literal_labels(&decl.type_name, value)?;
    }
    // `long[] a = [1, 2]`: the declared type types a collection literal.
    let default = decl.default_value.as_ref().map(|value| typed_expression(value, Some(&ty))).transpose()?;
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
    with_attributes(&block.attributes, || block_in_context(block))
}

fn block_in_context(block: &ast::Block) -> Result<Block, Diagnostic> {
    let mut items = vec![];
    for stmt in &block.statements {
        // A statement using `?` lowers to several, its hidden locals first.
        if let Some(lowered) = tries::lift(stmt)? {
            items.extend(lowered);
            continue;
        }
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
        ast::Statement::Branch(branch) => match is_branch(branch)? {
            Some(lowered) => Ok(lowered),
            None => Ok(Statement::Branch(Branch {
                condition: {
                    check_branch_hints(&branch.if_block.attributes, "an 'if'")?;
                    expression(&branch.condition)?
                },
                if_block: block(&branch.if_block)?,
                else_block: branch.else_block.as_ref().map(block).transpose()?,
            })),
        },
        ast::Statement::While(wh) => match is_loop(wh)? {
            Some(lowered) => Ok(lowered),
            None => Ok(Statement::While(While {
                condition: expression(&wh.condition)?,
                block: block(&wh.block)?,
            })),
        },
        ast::Statement::For(f) => for_loop(f),
        ast::Statement::With(w) => with_block(w),
        ast::Statement::Match(m) => match_statement(m),
        ast::Statement::Static(s) => static_items::static_block(s),
        ast::Statement::Return(ret) => {
            if let (Some(value), Some(returns)) = (&ret.expr, RETURN_TYPE.with(|r| r.borrow().clone())) {
                check_literal_labels(&returns, value)?;
            }
            Ok(Statement::Return(ReturnStatement {
                expr: ret.expr.as_ref().map(expression).transpose()?,
                loc: loc(ret.expr.as_ref().map_or(ret.span, |e| e.span())),
            }))
        }
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
    let ast::Expression::Tuple { elements, labels, .. } = lhs else { unreachable!("checked by the caller") };
    if let Some((_, at)) = labels.first() {
        return Err(Diagnostic::error("a destructuring assignment cannot have labels: list the places alone").at(loc(*at)));
    }
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
        if let ast::Expression::Tuple { elements, labels, .. } = place {
            if let Some((_, at)) = labels.first() {
                return Err(Diagnostic::error("a destructuring assignment cannot have labels: list the places alone").at(loc(*at)));
            }
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
    set_counters([0; 5]);
}

/// The hidden-local counters, in the order `set_counters` takes them.
fn counters() -> [usize; 5] {
    [
        FOR_LOOPS.with(|c| c.get()),
        WITH_BLOCKS.with(|c| c.get()),
        TUPLES.with(|c| c.get()),
        MATCHES.with(|c| c.get()),
        tries::TRIES.with(|c| c.get()),
    ]
}

fn set_counters([for_loops, with_blocks, tuples, matches, tries]: [usize; 5]) {
    FOR_LOOPS.with(|c| c.set(for_loops));
    WITH_BLOCKS.with(|c| c.set(with_blocks));
    TUPLES.with(|c| c.set(tuples));
    MATCHES.with(|c| c.set(matches));
    tries::TRIES.with(|c| c.set(tries));
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
    for body in m.arms.iter().map(|a| &a.body).chain(m.else_arm.iter().map(|(_, b)| b)) {
        check_branch_hints(&body.attributes, "a 'match' arm")?;
    }
    let arms: Vec<(&[ast::Pattern], Option<&ast::Expression>, &ast::Block)> =
        m.arms.iter().map(|a| (a.patterns.as_slice(), a.guard.as_ref(), &a.body)).collect();
    let else_arm = m.else_arm.as_ref().map(|(span, b)| (loc(*span), block(b))).map(|(l, b)| b.map(|b| (l, b))).transpose()?;
    lower_match_statement(&m.value, m.keyword_span, &arms, else_arm, false)
}

/// The next program-wide `match` number (`__match_N`, [`MatchSite::id`]).
fn next_match() -> usize {
    MATCHES.with(|c| {
        let n = c.get();
        c.set(n + 1);
        n
    })
}

/// The statement form of a `match` (see [`match_statement`]); `partial` for
/// an `if` or `while` whose condition is an `is` test, whose one arm need not
/// handle every case.
fn lower_match_statement(
    value: &ast::Expression,
    keyword: ast::Span,
    arms: &[(&[ast::Pattern], Option<&ast::Expression>, &ast::Block)],
    else_arm: Option<(Loc, Block)>,
    partial: bool,
) -> Result<Statement, Diagnostic> {
    let n = next_match();
    let subject = format!("__match_{}", n);
    let at = loc(value.span());
    let hidden = VariableDef {
        name: subject.clone(),
        ty: TypeName::auto(),
        default: Some(expression(value)?),
        hidden: true,
        kind: Kind::Variable,
        attributes: vec![],
        loc: at,
        type_loc: Loc::NONE,
        is_const: false,
    };
    let site = MatchSite { id: n, keyword: loc(keyword), else_arm: else_arm.as_ref().map(|(l, _)| *l), partial, no_bindings: false };
    let subject_ref = Expression::SymbolRef { id: subject.clone(), ty: TypeName::auto(), loc: at };
    let mut chain: Option<Block> = else_arm.map(|(_, b)| b);
    let mut lowered: Vec<(Expression, Block)> = vec![];
    for (patterns, guard, body) in arms {
        let cases = patterns.iter().map(|p| case_pattern(p, &subject_ref)).collect::<Result<Vec<_>, _>>()?;
        let mut body = block(body)?;
        let (bindings, element_names) = match_bindings(patterns, &subject_ref)?;
        let test = arm_test(&subject_ref, cases, &site, element_names, *guard, &bindings)?;
        let locals = bindings.into_iter().map(|(name, value, at)| {
            Statement::Declaration(Declaration::Variable(VariableDef {
                name,
                ty: TypeName::auto(),
                default: Some(value),
                hidden: false,
                kind: Kind::Variable,
                attributes: vec![],
                loc: at,
                type_loc: Loc::NONE,
                is_const: true,
            }))
        });
        body.items.splice(0..0, locals);
        lowered.push((test, body));
    }
    if lowered.is_empty() {
        let test = arm_test(&subject_ref, vec![], &site, vec![], None, &[])?;
        lowered.push((test, Block { name: String::new(), items: vec![], attributes: vec![] }));
    }
    for (condition, body) in lowered.into_iter().rev() {
        let branch = Statement::Branch(Branch { condition, if_block: body, else_block: chain.take() });
        chain = Some(Block { name: String::new(), items: vec![branch], attributes: vec![] });
    }
    let mut items = vec![Statement::Declaration(Declaration::Variable(hidden))];
    items.extend(chain.map(|b| b.items).unwrap_or_default());
    Ok(Statement::Block(Block { name: String::new(), items, attributes: vec![] }))
}

/// The error for attributes above `what` (an `if` or a `match` arm) other
/// than one `[Likely]` or `[Unlikely]`, the branch hints codegen turns into
/// branch weights (`ast::branch_hint`).
fn check_branch_hints(attributes: &[ast::Attribute], what: &str) -> Result<(), Diagnostic> {
    let mut seen: Option<&ast::Attribute> = None;
    for attribute in attributes {
        let at = loc(attribute.span);
        match (attribute.name(), &attribute.body) {
            (Some("Likely" | "Unlikely"), ast::Expression::SymbolRef { .. }) => {}
            (Some(name @ ("Likely" | "Unlikely")), _) => {
                return Err(Diagnostic::error(format!("'{}' takes no arguments", name)).at(at));
            }
            (name, _) => {
                return Err(Diagnostic::error(format!(
                    "'{}' cannot mark {}; only '[Likely]' or '[Unlikely]' can",
                    name.unwrap_or("attribute"),
                    what
                ))
                .at(at));
            }
        }
        if let Some(first) = seen {
            return Err(Diagnostic::error(format!("only one of '[Likely]' or '[Unlikely]' can mark {}", what))
                .at(at)
                .with_note(format!("'{}' is here", first.name().unwrap_or_default()), Some(loc(first.span))));
        }
        seen = Some(attribute);
    }
    Ok(())
}

/// `if (x is P(a)) { ... } else { ... }`: the `match` statement `match (x) {
/// P(a) => { ... } else => { ... } }`, so `a` is a local of the block.
fn is_branch(branch: &ast::Branch) -> Result<Option<Statement>, Diagnostic> {
    let ast::Expression::Is { value, pattern, keyword_span, .. } = &branch.condition else {
        return Ok(None);
    };
    check_branch_hints(&branch.if_block.attributes, "an 'if'")?;
    let else_arm = branch.else_block.as_ref().map(block).transpose()?.map(|b| (Loc::NONE, b));
    let arms = [(std::slice::from_ref(pattern.as_ref()), None, &branch.if_block)];
    lower_match_statement(value, *keyword_span, &arms, else_arm, true).map(Some)
}

/// `while (x is P(a)) { body }`: `while (true) { match (x) { P(a) => { body }
/// else => { break; } } }`, so `a` is a local of the body and `x` is
/// examined again on every iteration.
fn is_loop(wh: &ast::While) -> Result<Option<Statement>, Diagnostic> {
    let ast::Expression::Is { value, pattern, keyword_span, .. } = &wh.condition else {
        return Ok(None);
    };
    let stop = Block { name: String::new(), items: vec![Statement::LoopBreak(LoopBreak { kind: LoopBreakKind::Break })], attributes: vec![] };
    let arms = [(std::slice::from_ref(pattern.as_ref()), None, &wh.block)];
    let body = lower_match_statement(value, *keyword_span, &arms, Some((Loc::NONE, stop)), true)?;
    Ok(Some(Statement::While(While {
        condition: Expression::BoolLiteral(true),
        block: Block { name: String::new(), items: vec![body], attributes: vec![] },
    })))
}

/// `match (e) { A, B => x, C => y, else => z }` becomes
///
/// ```text
/// WithSubject(N, e, MatchArm(Subject(N) is A, B) ? x : MatchArm(Subject(N) is C) ? y : z)
/// ```
///
/// with each name a pattern binds replaced in its arm's value by the
/// [`CaseValue`] it reads. Without an `else` the chain ends in `NoMatch`,
/// which `enums::lower_matches` drops once every case is handled.
fn match_expression(m: &ast::MatchExpression) -> Result<Expression, Diagnostic> {
    let n = next_match();
    let at = loc(m.value.span());
    let site = MatchSite {
        id: n,
        keyword: loc(m.keyword_span),
        else_arm: m.else_arm.as_ref().map(|(s, _)| loc(*s)),
        partial: false,
        no_bindings: false,
    };
    let subject = Expression::Subject { id: n, ty: TypeName::auto(), loc: at };
    let mut chain = match &m.else_arm {
        Some((_, value)) => expression(value)?,
        None => Expression::NoMatch,
    };
    let mut arms = vec![];
    for arm in &m.arms {
        let patterns = arm.patterns.iter().map(|p| case_pattern(p, &subject)).collect::<Result<Vec<_>, _>>()?;
        let mut value = expression(&arm.value)?;
        let (bindings, element_names) = match_bindings(&arm.patterns, &subject)?;
        bind_in_expression(&mut value, &bindings, ArmPart::Value)?;
        let test = arm_test(&subject, patterns, &site, element_names, arm.guard.as_ref(), &bindings)?;
        arms.push((test, value));
    }
    if arms.is_empty() {
        arms.push((arm_test(&subject, vec![], &site, vec![], None, &[])?, Expression::NoMatch));
    }
    for (test, value) in arms.into_iter().rev() {
        chain = Expression::Ternary { condition: Box::new(test), true_expr: Box::new(value), false_expr: Box::new(chain) };
    }
    Ok(Expression::WithSubject(Box::new(WithSubject { id: n, subject: expression(&m.value)?, body: chain, null_message: None, loc: at })))
}

/// The name `e as? T` binds the converted value to (see [`optional_cast`]).
pub(crate) const CAST_VALUE: &str = "__cast_value";

/// `e as? T`, a trait value's conversion that may fail: the `match`
/// expression `match (e) { T(value) => Optional<T>.Value(value), else =>
/// Optional<T>.Empty }`, so `enums::lower_matches` checks `T` and tests
/// the value's type as for any type pattern.
fn optional_cast(value: &ast::Expression, ty: &ast::TypeName, keyword: ast::Span, span: ast::Span) -> Result<Expression, Diagnostic> {
    const BOUND: &str = CAST_VALUE;
    let optional = ast::TypeName { name: "Optional".to_string(), generic_types: vec![ty.clone()], span: ty.span, labels: vec![] };
    let call = |method: &str, arguments: Vec<ast::Expression>| ast::Expression::FunctionCall {
        function: Box::new(ast::Expression::MemberAccess {
            lhs: Box::new(ast::Expression::TypeLiteral(optional.clone())),
            name: method.to_string(),
            name_span: keyword,
            span,
        }),
        arguments,
        span,
    };
    let pattern = ast::Pattern {
        literal: None,
        elements: None,
        qualifier: None,
        case: ty.to_string(),
        case_span: ty.span,
        bindings: Some(vec![ast::Pattern {
            literal: None,
            elements: None,
            qualifier: None,
            case: BOUND.to_string(),
            case_span: ty.span,
            bindings: None,
            range: None,
            constant: None,
            ty: None,
            span: ty.span,
        }]),
        range: None,
        constant: None,
        ty: Some(ty.clone()),
        span: ty.span,
    };
    let arm = ast::MatchValueArm {
        patterns: vec![pattern],
        guard: None,
        value: call("Value", vec![ast::Expression::SymbolRef { id: BOUND.to_string(), span: ty.span }]),
        span,
    };
    match_expression(&ast::MatchExpression {
        value: value.clone(),
        arms: vec![arm],
        else_arm: Some((
            keyword,
            ast::Expression::MemberAccess { lhs: Box::new(ast::Expression::TypeLiteral(optional.clone())), name: "Empty".to_string(), name_span: keyword, span },
        )),
        keyword_span: keyword,
        span,
    })
}

/// `e is P` anywhere but the whole condition of an `if` or `while`: a
/// single test over `e`, which may bind nothing.
fn is_expression(value: &ast::Expression, pattern: &ast::Pattern, keyword: ast::Span) -> Result<Expression, Diagnostic> {
    let mut element_names = vec![];
    for (name, span, _) in pattern_names(pattern, &Expression::NoMatch) {
        // A case of the value's enum, or else an error once its type is
        // known.
        element_names.push(ElementName { name, loc: loc(span), declared: false, missing: None });
    }
    let n = next_match();
    let at = loc(value.span());
    let site = MatchSite { id: n, keyword: loc(keyword), else_arm: None, partial: true, no_bindings: true };
    let subject = Expression::Subject { id: n, ty: TypeName::auto(), loc: at };
    let test = MatchArmTest {
        subject: subject.clone(),
        patterns: vec![case_pattern(pattern, &subject)?],
        site,
        element_names,
        guarded: false,
    };
    Ok(Expression::WithSubject(Box::new(WithSubject {
        id: n,
        subject: expression(value)?,
        body: Expression::MatchArm(Box::new(test)),
        null_message: None,
        loc: at,
    })))
}

/// The test of one arm: `MatchArm(subject is patterns)`, and with a guard
/// `MatchArm(...) && guard`, where each name the arm binds reads its value in
/// the guard as it does in a `match` expression's arm value.
fn arm_test(
    subject: &Expression,
    patterns: Vec<CasePattern>,
    site: &MatchSite,
    element_names: Vec<ElementName>,
    guard: Option<&ast::Expression>,
    bindings: &[(String, Expression, Loc)],
) -> Result<Expression, Diagnostic> {
    let test = Expression::MatchArm(Box::new(MatchArmTest {
        subject: subject.clone(),
        patterns,
        site: site.clone(),
        element_names,
        guarded: guard.is_some(),
    }));
    let Some(guard) = guard else {
        return Ok(test);
    };
    let at = loc(guard.span());
    let mut guard = expression(guard)?;
    bind_in_expression(&mut guard, bindings, ArmPart::Guard)?;
    Ok(Expression::Binary { op: BinaryOp::LogicalAnd, lhs: Box::new(test), rhs: Box::new(guard), loc: at })
}

/// A pattern of an arm over `subject`. A literal pattern carries the test
/// `subject == literal`, and its literal as written in `case`.
fn case_pattern(p: &ast::Pattern, subject: &Expression) -> Result<CasePattern, Diagnostic> {
    if let Some(elements) = &p.elements {
        let elements = elements
            .iter()
            .enumerate()
            .map(|(i, e)| case_pattern(e, &element_path(subject, i, loc(e.span))))
            .collect::<Result<Vec<_>, _>>()?;
        return Ok(CasePattern {
            qualifier: None,
            case: p.to_string(),
            loc: loc(p.span),
            bindings: None,
            literal: None,
            elements: Some(elements),
            range: false,
            constant: false,
            values: None,
            ty: None,
        });
    }
    let at = loc(p.case_span);
    let compare = |op: BinaryOp, value: Expression| Expression::Binary { op, lhs: Box::new(subject.clone()), rhs: Box::new(value), loc: at };
    let (literal, values) = match (&p.literal, &p.range, &p.constant) {
        (Some(start), Some(range), _) => {
            let low = compare(BinaryOp::GreaterEqual, expression(start)?);
            let op = if range.inclusive { BinaryOp::LessEqual } else { BinaryOp::Less };
            let high = compare(op, expression(&range.end)?);
            let test = Expression::Binary { op: BinaryOp::LogicalAnd, lhs: Box::new(low), rhs: Box::new(high), loc: at };
            let values = constant_integer(start)
                .zip(constant_integer(&range.end))
                .map(|(low, high)| (low, if range.inclusive { high } else { high - 1 }));
            (Some(test), values)
        }
        (Some(l), None, _) => (Some(compare(BinaryOp::Equal, expression(l)?)), constant_integer(l).map(|v| (v, v))),
        (None, _, Some(linked)) => {
            let value = Expression::SymbolRef { id: linked.clone(), ty: TypeName::auto(), loc: at };
            (Some(compare(BinaryOp::Equal, value)), None)
        }
        (None, _, None) => (None, None),
    };
    Ok(CasePattern {
        qualifier: if p.constant.is_some() { None } else { p.qualifier.as_ref().map(type_name_from) },
        case: if p.literal.is_some() || p.constant.is_some() { p.to_string() } else { p.case.clone() },
        loc: if p.range.is_some() { loc(p.span) } else { at },
        bindings: match &p.bindings {
            Some(subs) => Some(
                subs.iter()
                    .enumerate()
                    .map(|(i, sub)| case_pattern(sub, &case_path(subject, p, i)))
                    .collect::<Result<Vec<_>, _>>()?,
            ),
            None => None,
        },
        literal,
        elements: None,
        range: p.range.is_some(),
        constant: p.constant.is_some(),
        values,
        ty: if p.literal.is_some() || p.constant.is_some() { None } else { p.ty.as_ref().map(type_name_from) },
    })
}

/// Element `index` of the tuple `subject`: `subject.0`.
fn element_path(subject: &Expression, index: usize, at: Loc) -> Expression {
    Expression::MemberRef { lhs: Box::new(subject.clone()), name: index.to_string(), loc: at }
}

/// Value `index` of case pattern `p` over `subject`, the value the
/// pattern's sub-pattern at `index` matches: a [`CaseValue`] with one choice.
fn case_path(subject: &Expression, p: &ast::Pattern, index: usize) -> Expression {
    let subs = p.bindings.as_deref().unwrap_or_default();
    let at = subs.get(index).map_or(loc(p.case_span), |s| loc(s.span));
    Expression::CaseValue(Box::new(CaseValue {
        subject: subject.clone(),
        name: String::new(),
        choices: vec![CaseChoice {
            case: p.case.clone(),
            case_loc: loc(p.case_span),
            ty: p.ty.as_ref().map(type_name_from),
            index,
            bindings: subs.iter().map(|s| loc(s.span)).collect(),
            loc: at,
        }],
        loc: at,
    }))
}

/// What a name in a pattern binds.
enum Leaf<'p> {
    /// A bare name inside a tuple pattern or a nested case pattern: the
    /// element at `path` (`key` its positions), unless the element's enum has
    /// a case of that name.
    Element { path: Expression, key: Vec<String> },
    /// A value the case of `pattern` carries, at `index` among its bindings;
    /// `path` is the enum value. It binds unless the value's enum has a case
    /// of that name.
    Payload { path: Expression, key: Vec<String>, pattern: &'p ast::Pattern, index: usize },
}

/// Every name `p` may bind over `subject`, `_` left out, in order.
fn pattern_names<'p>(p: &'p ast::Pattern, subject: &Expression) -> Vec<(String, ast::Span, Leaf<'p>)> {
    fn walk<'p>(
        p: &'p ast::Pattern,
        path: Expression,
        key: Vec<String>,
        in_tuple: bool,
        out: &mut Vec<(String, ast::Span, Leaf<'p>)>,
    ) {
        if let Some(elements) = &p.elements {
            for (i, e) in elements.iter().enumerate() {
                let mut inner = key.clone();
                inner.push(i.to_string());
                walk(e, element_path(&path, i, loc(e.span)), inner, true, out);
            }
            return;
        }
        if in_tuple && p.is_bare_name() && p.case != "_" {
            out.push((p.case.clone(), p.case_span, Leaf::Element { path: path.clone(), key: key.clone() }));
        }
        for (index, sub) in p.bindings.iter().flatten().enumerate() {
            if sub.is_bare_name() {
                if sub.case != "_" {
                    out.push((sub.case.clone(), sub.case_span, Leaf::Payload { path: path.clone(), key: key.clone(), pattern: p, index }));
                }
                continue;
            }
            // A pattern the value must match: its own names bind inside it.
            let mut inner = key.clone();
            inner.push(format!("{}.{}", p.case, index));
            walk(sub, case_path(&path, p, index), inner, true, out);
        }
    }
    let mut out = vec![];
    walk(p, subject.clone(), vec![], false, &mut out);
    out
}

/// Where [`bind_in_expression`] replaces an arm's names.
#[derive(Clone, Copy)]
enum ArmPart {
    /// A `match` expression's arm value.
    Value,
    /// An arm's guard.
    Guard,
}

/// Replace each name an arm binds with the value it reads, in a `match`
/// expression's arm value or an arm's guard. A closure there may not use
/// one: it would outlive the value it reads.
fn bind_in_expression(value: &mut Expression, bindings: &[(String, Expression, Loc)], part: ArmPart) -> Result<(), Diagnostic> {
    if bindings.is_empty() {
        return Ok(());
    }
    let mut error = None;
    fn visit(e: &mut Expression, bindings: &[(String, Expression, Loc)], part: ArmPart, error: &mut Option<Diagnostic>) {
        if let Expression::SymbolRef { id, loc: at, .. } = e
            && let Some((_, v, _)) = bindings.iter().find(|(n, _, _)| n == id)
        {
            let _ = at;
            *e = v.clone();
            return;
        }
        if let Expression::ClosureLiteral(c) = e {
            let hidden: Vec<&str> = c.parameters.iter().map(|p| p.name.as_str()).collect();
            crate::passes::walk_block(&mut c.body, &mut |inner| {
                if let Expression::SymbolRef { id, loc: at, .. } = inner
                    && !hidden.contains(&id.as_str())
                    && error.is_none()
                    && let Some((name, _, bound)) = bindings.iter().find(|(n, _, _)| n == id)
                {
                    let message = match part {
                        ArmPart::Value => format!(
                            "a closure cannot use '{}', bound by an arm of a 'match' expression; use a 'match' statement",
                            name
                        ),
                        ArmPart::Guard => format!("a closure in a guard cannot use '{}', bound by the arm's patterns", name),
                    };
                    *error = Some(
                        Diagnostic::error(message)
                        .at(*at)
                        .with_note(format!("'{}' is bound here", name), Some(*bound)),
                    );
                }
            });
            return;
        }
        for child in crate::passes::children_mut(e) {
            visit(child, bindings, part, error);
        }
    }
    visit(value, bindings, part, &mut error);
    error.map_or(Ok(()), Err)
}

/// The names an arm's patterns bind, each with the value it reads and the
/// binding's location, and the arm's bare element names. A case's binding
/// reads the matched case's value at its position ([`CaseValue`]); a bare
/// name inside a tuple pattern reads its element (`__match_N.0`). Every
/// pattern of an arm must bind the same names, each at the same element.
///
/// A bare element name may turn out to be a case, which only the element's
/// type decides. One that every pattern has once, at the same element, is
/// bound here and dropped later if it is a case; any other must be a case.
fn match_bindings(
    patterns: &[ast::Pattern],
    subject: &Expression,
) -> Result<(Vec<(String, Expression, Loc)>, Vec<ElementName>), Diagnostic> {
    let mut per: Vec<Vec<(String, ast::Span, Leaf)>> = patterns.iter().map(|p| pattern_names(p, subject)).collect();
    let is_payload = |leaf: &Leaf| matches!(leaf, Leaf::Payload { .. });
    // A name twice in a case's values (`Pair(Line, Line)`) must be a case
    // there, like a bare name a tuple pattern repeats.
    for names in &mut per {
        let twice: Vec<String> = names
            .iter()
            .enumerate()
            .filter(|(i, (n, _, l))| is_payload(l) && names[..*i].iter().any(|(m, _, k)| m == n && is_payload(k)))
            .map(|(_, (n, _, _))| n.clone())
            .collect();
        for (name, _, leaf) in names.iter_mut() {
            if let Leaf::Payload { path, key, .. } = leaf
                && twice.contains(name)
            {
                *leaf = Leaf::Element { path: path.clone(), key: key.clone() };
            }
        }
    }
    let mut order: Vec<(String, ast::Span)> = vec![];
    for (name, span, _) in per.iter().flatten() {
        if !order.iter().any(|(n, _)| n == name) {
            order.push((name.clone(), *span));
        }
    }
    let mut out = vec![];
    let mut element_names = vec![];
    for (name, span) in order {
        let entries: Vec<Vec<&(String, ast::Span, Leaf)>> =
            per.iter().map(|names| names.iter().filter(|(n, _, _)| *n == name).collect()).collect();
        let key_of = |leaf: &Leaf| match leaf {
            Leaf::Element { key, .. } | Leaf::Payload { key, .. } => key.clone(),
        };
        let path_of = |leaf: &Leaf| match leaf {
            Leaf::Element { path, .. } | Leaf::Payload { path, .. } => path.clone(),
        };
        let any_payload = entries.iter().flatten().any(|(_, _, l)| is_payload(l));
        if !any_payload {
            let first = entries.first().and_then(|e| e.first()).map(|(_, _, l)| key_of(l));
            let consistent = entries.iter().all(|e| e.len() == 1 && Some(key_of(&e[0].2)) == first);
            for (_, at, _) in entries.iter().flatten() {
                element_names.push(ElementName { name: name.clone(), loc: loc(*at), declared: consistent, missing: None });
            }
            if consistent {
                out.push((name.clone(), path_of(&entries[0][0].2), loc(span)));
            }
            continue;
        }
        // A pattern without the name: then it binds nothing, and must be a
        // case wherever it appears (`Pair(Line, _), Line`).
        let lacking = patterns.iter().zip(&entries).find(|(_, found)| !found.iter().any(|(_, _, l)| is_payload(l)));
        if let Some((p, _)) = lacking {
            let shown = match &p.literal {
                Some(l) => l.to_string(),
                None if p.elements.is_some() => p.to_string(),
                None => p.case.clone(),
            };
            for (_, at, _) in entries.iter().flatten() {
                let missing = Some((shown.clone(), loc(p.case_span)));
                element_names.push(ElementName { name: name.clone(), loc: loc(*at), declared: false, missing });
            }
            continue;
        }
        let mut choices = vec![];
        let mut first: Option<(Vec<String>, Expression, ast::Span)> = None;
        for found in &entries {
            for (_, at, leaf) in found.iter().filter(|(_, _, l)| !is_payload(l)) {
                let _ = leaf;
                element_names.push(ElementName { name: name.clone(), loc: loc(*at), declared: false, missing: None });
            }
            let Some((_, at, Leaf::Payload { path, key, pattern, index })) = found.iter().copied().find(|(_, _, l)| is_payload(l)) else {
                continue;
            };
            match &first {
                None => first = Some((key.clone(), path.clone(), *at)),
                Some((first_key, _, first_at)) if first_key != key => {
                    return Err(Diagnostic::error(format!(
                        "'{}' is bound at a different element than in the arm's first pattern: bind it at the same element in each",
                        name
                    ))
                    .at(loc(*at))
                    .with_note(format!("'{}' is bound here", name), Some(loc(*first_at))));
                }
                Some(_) => {}
            }
            let all = pattern.bindings.as_deref().unwrap_or_default();
            choices.push(CaseChoice {
                case: pattern.case.clone(),
                case_loc: loc(pattern.case_span),
                ty: pattern.ty.as_ref().map(type_name_from),
                index: *index,
                bindings: all.iter().map(|s| loc(s.span)).collect(),
                loc: loc(*at),
            });
        }
        // A bare name in a case's values may turn out to be a case of the
        // value's enum (`Value(Empty)`), which only the value's type decides.
        for (_, at, _) in entries.iter().flatten().filter(|(_, _, l)| is_payload(l)) {
            element_names.push(ElementName { name: name.clone(), loc: loc(*at), declared: true, missing: None });
        }
        let path = first.map(|(_, path, _)| path).unwrap_or_else(|| subject.clone());
        let value = CaseValue { subject: path, name: name.clone(), choices, loc: loc(span) };
        out.push((name, Expression::CaseValue(Box::new(value)), loc(span)));
    }
    Ok((out, element_names))
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
    // Only a trait method (a requirement), an `extern`, or a `[__BuiltIn]`
    // declaration, which never reaches the builder, may end with `;`.
    if decl.body.is_none() && !decl.external {
        let name = if decl.is_indexer { "[]" } else { decl.name.as_str() };
        return Err(Diagnostic::error(format!("'{}' has no body; only a trait method or a '[__BuiltIn]' declaration may end with ';'", name))
            .at(loc(decl.name_span)));
    }
    trait_method_def(decl, parent)
}

/// A trait's method, whose body is optional: one without is a requirement.
fn trait_method_def(decl: &ast::FunctionDecl, parent: Option<String>) -> Result<FunctionDef, Diagnostic> {
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
    with_attributes(&decl.attributes, || in_generic_scope(&decl.generic_params, None, || member_in_scope(decl, parent)))
}

fn member_in_scope(decl: &ast::FunctionDecl, parent: Option<String>) -> Result<FunctionDef, Diagnostic> {
    check_deprecation(&decl.attributes)?;
    // A concrete override (`describe<Circle>`) passes its type arguments to
    // the generic it overrides, whose constraints they must meet.
    if parent.is_none() && decl.generic_params.iter().any(|p| p.is_argument) {
        let args = decl.generic_params.iter().map(|p| TypeName::new(&p.name)).collect();
        push_type_use(TypeName::with_args(&decl.name, args), decl.generic_params.iter().map(|p| loc(p.name_span)).collect());
    }
    // The signature before the body, so its type uses come first.
    let generic_params: Vec<GenericParam> = decl.generic_params.iter().map(generic_param_from).collect();
    let ty = type_name_from(&decl.return_type);
    let parameters: Vec<VariableDef> = decl
        .parameters
        .iter()
        .map(|p| variable_def(p, Kind::Param))
        .collect::<Result<Vec<_>, _>>()?;
    let body = with_return_type(&decl.return_type, || decl.body.as_ref().map(block).transpose())?;
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
        owner: Loc::NONE,
        name: decl.name.clone(),
        ty,
        generic_params,
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
        ast::Declaration::Static(s) => Err(Diagnostic::error("a module-scope 'static' block cannot be declared here").at(loc(s.keyword_span))),
    }
}
fn trait_def(t: &ast::TraitDecl) -> Result<TraitDef, Diagnostic> {
    check_deprecation(&t.attributes)?;
    reject_implicit(&t.attributes)?;
    Ok(TraitDef {
        name: t.name.clone(),
        generic_params: t.generic_params.iter().map(generic_param_from).collect(),
        methods: {
            let mut methods = t.methods.iter().map(|m| trait_method_def(m, None)).collect::<Result<Vec<_>, _>>()?;
            for property in &t.properties {
                methods.extend(property_members(property, PropertyOwner::Trait { name: &t.name })?.accessors);
            }
            methods
        },
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
        restated: e
            .target_bounds
            .iter()
            .enumerate()
            .flat_map(|(i, bounds)| bounds.iter().map(move |b| (i, Bound { ty: type_name_from(b), loc: loc(b.span) })))
            .collect(),
        methods: {
            let mut methods = e.methods.iter().map(|m| function_def(m, None)).collect::<Result<Vec<_>, _>>()?;
            let target = type_name_from(&e.target);
            for property in &e.properties {
                methods.extend(property_members(property, PropertyOwner::Extension { name: &target.name })?.accessors);
            }
            methods
        },
        attributes: e.attributes.clone(),
        loc: loc(e.target.span),
        is_exported: e.is_exported,
    })
}

/// Who declares a property, for [`property_members`].
enum PropertyOwner<'a> {
    /// A struct, with its `[Shared]` attribute if it has one.
    Struct { name: &'a str, shared: Option<&'a ast::Attribute> },
    Trait { name: &'a str },
    /// An extension of the struct `name`.
    Extension { name: &'a str },
    /// An enum whose cases carry no values: its accessors become the free
    /// functions `E::__get_p` (see [`enum_method`]).
    Enum { name: &'a str },
}

/// The members a property lowers to (see [`PropertyDef`]).
struct PropertyMembers {
    storage: Option<VariableDef>,
    accessors: Vec<FunctionDef>,
}

/// Lower `property` to its storage field and accessor methods, and record
/// its [`PropertyDef`] for `passes::properties`.
fn property_members(property: &ast::PropertyDecl, owner: PropertyOwner) -> Result<PropertyMembers, Diagnostic> {
    check_deprecation(&property.attributes)?;
    reject_implicit(&property.attributes)?;
    let name = &property.name;
    let Some(get) = &property.get else {
        let at = property.set.as_ref().map_or(property.name_span, |s| s.span);
        return Err(Diagnostic::error(format!("property '{}' has no 'get' accessor; a property must have one", name)).at(loc(at)));
    };
    let parent = match owner {
        PropertyOwner::Struct { name, .. } => Some(name.to_string()),
        _ => None,
    };
    let accessor = |method: String, parameters: Vec<ast::VariableDecl>, return_type: ast::TypeName, body: &Option<ast::Block>, span: ast::Span| {
        let decl = ast::FunctionDecl {
            is_exported: false,
            name: method,
            name_span: span,
            generic_params: vec![],
            return_type,
            parameters,
            external: false,
            body: body.clone(),
            is_static: false,
            is_indexer: false,
            is_variadic: false,
            span,
            attributes: property.attributes.clone(),
        };
        member_def(&decl, parent.clone())
    };
    let mut getter = accessor(getter_name(name), vec![], property.type_name.clone(), &get.function.body, property.name_span)?;
    let value = ast::VariableDecl {
        attributes: vec![],
        name: ast::PROPERTY_VALUE.to_string(),
        name_span: property.name_span,
        type_name: property.type_name.clone(),
        default_value: None,
        is_const: false,
        span: property.name_span,
        is_exported: false,
    };
    let void = ast::TypeName { name: "void".to_string(), generic_types: vec![], span: property.name_span, labels: vec![] };
    let mut setter = match &property.set {
        Some(set) => Some(accessor(setter_name(name), vec![value], void, &set.function.body, set.span)?),
        None => None,
    };
    let uses_field = |f: &FunctionDef| {
        let mut found = false;
        if let Some(body) = &f.body {
            crate::passes::visit_block(body, &mut |e| {
                found |= matches!(e, Expression::SymbolRef { id, .. } if id == ast::PROPERTY_FIELD);
            });
        }
        found
    };
    let has_storage = get.function.body.is_none()
        || property.set.as_ref().is_some_and(|s| s.function.body.is_none())
        || uses_field(&getter)
        || setter.as_ref().is_some_and(uses_field);
    let storage = if get.function.body.is_none() { name.clone() } else { storage_name(name) };
    let field_ref = |at: Loc| Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: storage.clone(), loc: at };
    match owner {
        PropertyOwner::Trait { .. } => {
            if let Some(body) = [&property.get, &property.set].into_iter().flatten().find_map(|a| a.function.body.as_ref().map(|_| a.span)) {
                return Err(Diagnostic::error(format!("an accessor of trait property '{}' cannot have a body", name)).at(loc(body)));
            }
            if let Some(value) = &property.default_value {
                return Err(Diagnostic::error(format!("trait property '{}' cannot have an initializer", name)).at(loc(value.span())));
            }
        }
        PropertyOwner::Extension { .. } if has_storage => {
            return Err(Diagnostic::error(format!(
                "an extension cannot add storage: property '{}' must be computed, with accessor bodies that do not use 'field'",
                name
            ))
            .at(loc(property.name_span)));
        }
        PropertyOwner::Enum { name: enum_name } => {
            if let Some(error) = enum_property_error(enum_name, property, has_storage) {
                return Err(error);
            }
        }
        PropertyOwner::Struct { shared: Some(shared), .. } => {
            if let Some(set) = &property.set {
                return Err(Diagnostic::error(format!(
                    "property '{}' of a '[{}]' struct cannot have a 'set' accessor: its storage is 'const'",
                    name, SHARED_ATTRIBUTE
                ))
                .at(loc(set.span))
                .with_note(format!("'[{}]' declared here", SHARED_ATTRIBUTE), Some(loc(shared.span))));
            }
        }
        _ => {}
    }
    if !has_storage {
        if let Some(value) = &property.default_value {
            return Err(Diagnostic::error(format!("property '{}' has no storage to initialize: it is computed", name))
                .at(loc(value.span())));
        }
    }
    let in_trait = matches!(owner, PropertyOwner::Trait { .. });
    // Default bodies read and write the storage; `field` in a written body
    // is the storage.
    if !in_trait {
        let at = loc(property.name_span);
        match &mut getter.body {
            Some(body) => replace_field(body, &storage),
            None => {
                getter.body = Some(Block {
                    name: String::new(),
                    items: vec![Statement::Return(ReturnStatement { expr: Some(field_ref(at)), loc: at })],
                    attributes: vec![],
                })
            }
        }
        if let Some(setter) = &mut setter {
            match &mut setter.body {
                Some(body) => replace_field(body, &storage),
                None => {
                    let assign = Expression::Binary {
                        op: BinaryOp::Assign,
                        lhs: Box::new(field_ref(at)),
                        rhs: Box::new(Expression::SymbolRef { id: ast::PROPERTY_VALUE.to_string(), ty: TypeName::auto(), loc: at }),
                        loc: at,
                    };
                    setter.body = Some(Block { name: String::new(), items: vec![Statement::Expression(assign)], attributes: vec![] })
                }
            }
        }
    }
    let shared = matches!(owner, PropertyOwner::Struct { shared: Some(_), .. });
    let storage_def = (has_storage && !in_trait)
        .then(|| -> Result<VariableDef, Diagnostic> {
            let field = ast::VariableDecl {
                attributes: property.attributes.clone(),
                name: storage.clone(),
                name_span: property.name_span,
                type_name: property.type_name.clone(),
                default_value: property.default_value.clone(),
                is_const: shared,
                span: property.span,
                is_exported: false,
            };
            variable_def(&field, Kind::Field)
        })
        .transpose()?;
    let owner_name = match owner {
        PropertyOwner::Struct { name, .. }
        | PropertyOwner::Trait { name }
        | PropertyOwner::Extension { name }
        | PropertyOwner::Enum { name } => name.to_string(),
    };
    PROPERTIES.with(|p| {
        p.borrow_mut().push(PropertyDef {
            name: name.clone(),
            owner: owner_name,
            in_trait,
            loc: loc(property.name_span),
            get: if get.function.body.is_some() { AccessorKind::Body } else { AccessorKind::Default },
            set: property.set.as_ref().map(|s| if s.function.body.is_some() { AccessorKind::Body } else { AccessorKind::Default }),
            set_loc: property.set.as_ref().map_or(Loc::NONE, |s| loc(s.span)),
            storage: (has_storage && !in_trait).then(|| storage.clone()),
            shared,
        })
    });
    Ok(PropertyMembers { storage: storage_def, accessors: [Some(getter), setter].into_iter().flatten().collect() })
}

/// Why `property` of enum `enum_name` is an error, if it is: an enum value
/// is immutable and has nowhere to keep anything, so its properties are
/// computed and read-only.
fn enum_property_error(enum_name: &str, property: &ast::PropertyDecl, has_storage: bool) -> Option<Diagnostic> {
    if let Some(set) = &property.set {
        return Some(
            Diagnostic::error(format!(
                "property '{}' of enum '{}' cannot have a 'set' accessor: enum values are immutable",
                property.name, enum_name
            ))
            .at(loc(set.span)),
        );
    }
    has_storage.then(|| {
        Diagnostic::error(format!(
            "property '{}' of enum '{}' must be computed: give 'get' a body that does not use 'field'",
            property.name, enum_name
        ))
        .at(loc(property.name_span))
    })
}

/// A property of an enum may not share a name with one of its cases.
fn check_enum_property_names(decl: &ast::StructDecl) -> Result<(), Diagnostic> {
    let body = decl.enumeration.as_ref().expect("an enum declaration");
    for property in &decl.properties {
        if let Some(case) = body.cases.iter().find(|c| c.name == property.name) {
            return Err(Diagnostic::error(format!("property '{}' has the same name as a case of '{}'", property.name, decl.name))
                .at(loc(property.name_span))
                .with_note("case declared here", Some(loc(case.name_span))));
        }
        if crate::enums::BUILT_IN_METHODS.contains(&property.name.as_str()) || property.name == "name" {
            return Err(Diagnostic::error(format!("'{}' is built into every enum and cannot be redeclared", property.name))
                .at(loc(property.name_span)));
        }
    }
    Ok(())
}

/// Inside an accessor body, `field` names the property's storage.
fn replace_field(body: &mut Block, storage: &str) {
    crate::passes::walk_block(body, &mut |e| {
        if let Expression::SymbolRef { id, loc, .. } = e
            && id == ast::PROPERTY_FIELD
        {
            *e = Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: storage.to_string(), loc: *loc };
        }
    });
}

/// A `[Value]` struct has no object: nothing destroys it, and it is
/// thread-safe exactly when its fields are, so `destruct` and `[Shared]`
/// do not apply to it.
fn check_value_attributes(decl: &ast::StructDecl) -> Result<(), Diagnostic> {
    if !has_attribute(&decl.attributes, VALUE_ATTRIBUTE) {
        return Ok(());
    }
    if let Some(span) = decl.destruct_span {
        return Err(Diagnostic::error(format!("value struct '{}' cannot have a destructor", decl.name)).at(loc(span)));
    }
    let shared = decl
        .attributes
        .iter()
        .find(|a| matches!(&a.body, ast::Expression::SymbolRef { id, .. } if id == SHARED_ATTRIBUTE));
    if let Some(shared) = shared {
        return Err(Diagnostic::error(format!(
            "'[Shared]' does not apply to value struct '{}': it is thread-safe when its fields are",
            decl.name
        ))
        .at(loc(shared.span)));
    }
    Ok(())
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
    check_value_attributes(decl)?;
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
    let (generic_methods, mut method_members): (Vec<FunctionDef>, Vec<FunctionDef>) = decl
        .methods
        .iter()
        .map(|m| function_def(m, Some(base_name.clone())))
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .partition(|m| m.is_generic_func);
    let mut field_members = field_members;
    let shared = decl
        .attributes
        .iter()
        .find(|a| matches!(&a.body, ast::Expression::SymbolRef { id, .. } if id == SHARED_ATTRIBUTE));
    for property in &decl.properties {
        let built = property_members(property, PropertyOwner::Struct { name: &base_name, shared })?;
        field_members.extend(built.storage);
        method_members.extend(built.accessors);
    }

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
            owner: Loc::NONE,
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
            owner: Loc::NONE,
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
            owner: Loc::NONE,
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
        enum_cases: None,
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
            payload: vec![],
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

/// Whether `decl` is an enum with a case that carries values: a reference
/// enum, built as a struct by [`reference_enum_def`].
fn is_reference_enum(decl: &ast::StructDecl) -> bool {
    decl.enumeration.as_ref().is_some_and(|e| e.cases.iter().any(|c| c.payload.is_some()))
}

/// Build a reference enum (an enum with a case that carries values) as the
/// struct its values are objects of:
///
/// - the field `__tag`, the case's position, then each case's values as the
///   fields `Case.value` (see [`payload_field`]), `const`;
/// - one constructor that sets every field, which only the cases call;
/// - each case as a static method: `Text(text: String): Doc` makes a `Doc`
///   whose other cases' fields hold their type's default;
/// - the declared methods, and the built-in `name()`.
///
/// Generic parameters, attributes and `extend` work as for any struct.
fn reference_enum_def(decl: &ast::StructDecl) -> Result<StructDef, Diagnostic> {
    let body = decl.enumeration.as_ref().expect("an enum declaration");
    if let Some(t) = &body.representation {
        return Err(Diagnostic::error(format!(
            "enum '{}' has cases that carry values, so it is not stored as an integer type",
            decl.name
        ))
        .at(loc(t.span)));
    }
    if let Some(m) = decl.methods.iter().find(|m| m.name == "name") {
        return Err(Diagnostic::error("'name' is built into every enum and cannot be redeclared").at(loc(m.name_span)));
    }
    let mut cases: Vec<EnumCaseDef> = vec![];
    let mut fields: Vec<ast::VariableDecl> = vec![];
    for (tag, case) in body.cases.iter().enumerate() {
        check_deprecation(&case.attributes)?;
        reject_implicit(&case.attributes)?;
        if let Some(value) = &case.value {
            return Err(Diagnostic::error(format!(
                "case '{}' of '{}' cannot have a value: its cases carry values",
                case.name, decl.name
            ))
            .at(loc(value.span())));
        }
        if let Some(previous) = cases.iter().find(|c| c.name == case.name) {
            return Err(Diagnostic::error(format!("redefinition of case '{}'", case.name))
                .at(loc(case.name_span))
                .with_note("previous definition is here", Some(previous.loc)));
        }
        if let Some(m) = decl.methods.iter().find(|m| m.name == case.name) {
            return Err(Diagnostic::error(format!("case '{}' has the same name as a method of '{}'", case.name, decl.name))
                .at(loc(case.name_span))
                .with_note("method declared here", Some(loc(m.name_span))));
        }
        let mut payload: Vec<(String, Loc)> = vec![];
        for value in case.payload.iter().flatten() {
            if let Some(default) = &value.default_value {
                return Err(Diagnostic::error(format!("the values of case '{}' cannot have defaults", case.name))
                    .at(loc(default.span())));
            }
            if let Some((_, previous)) = payload.iter().find(|(n, _)| *n == value.name) {
                return Err(Diagnostic::error(format!("redefinition of '{}' in case '{}'", value.name, case.name))
                    .at(loc(value.name_span))
                    .with_note("previous definition is here", Some(*previous)));
            }
            let mut field = value.clone();
            field.name = payload_field(&case.name, &value.name);
            field.is_const = true;
            fields.push(field);
            payload.push((value.name.clone(), loc(value.name_span)));
        }
        cases.push(EnumCaseDef {
            name: case.name.clone(),
            value: tag as i64,
            payload,
            attributes: case.attributes.clone(),
            loc: loc(case.name_span),
        });
    }
    check_enum_property_names(decl)?;
    let mut lowered = decl.clone();
    lowered.enumeration = None;
    lowered.fields = fields;
    lowered.constructors = vec![];
    lowered.destructor = None;
    let mut st = struct_def(&lowered)?;
    for property in &decl.properties {
        let stored = st.field_members.iter().any(|f| f.name == property.name || f.name == storage_name(&property.name));
        if let Some(error) = enum_property_error(&decl.name, property, stored) {
            return Err(error);
        }
    }
    let at = loc(decl.name_span);
    st.field_members.insert(
        0,
        VariableDef {
            name: TAG_FIELD.to_string(),
            ty: TypeName::new("int"),
            default: None,
            hidden: false,
            kind: Kind::Field,
            attributes: vec![],
            loc: at,
            type_loc: Loc::NONE,
            is_const: true,
        },
    );
    // `construct(this.__tag, this.Text.text, ...)`: each parameter sets its
    // field (`struct_body::finish`).
    st.constructors[0].parameters = st
        .field_members
        .iter()
        .map(|f| VariableDef {
            name: format!("this.{}", f.name),
            ty: f.ty.clone(),
            default: None,
            hidden: false,
            kind: Kind::Param,
            attributes: vec![],
            loc: Loc::NONE,
            type_loc: Loc::NONE,
            is_const: false,
        })
        .collect();
    let returns = |value: Expression| Statement::Return(ReturnStatement { expr: Some(value), loc: Loc::NONE });
    let method = |name: &str, ty: TypeName, parameters: Vec<VariableDef>, items: Vec<Statement>, is_static: bool, attributes: Vec<ast::Attribute>, at: Loc| FunctionDef {
        trait_default: None,
        owner: Loc::NONE,
        name: name.to_string(),
        ty,
        generic_params: vec![],
        parameters,
        body: Some(Block { name: String::new(), items, attributes: vec![] }),
        parent: Some(decl.name.clone()),
        is_static,
        is_indexer: false,
        is_generic_func: false,
        attributes,
        loc: at,
    };
    for (case, ast_case) in cases.iter().zip(&body.cases) {
        let parameters = ast_case
            .payload
            .iter()
            .flatten()
            .map(|p| variable_def(p, Kind::Param))
            .collect::<Result<Vec<_>, _>>()?;
        let mut args = vec![Expression::IntLiteral(case.value)];
        for f in st.field_members.iter().skip(1) {
            let own = case.payload.iter().find(|(name, _)| payload_field(&case.name, name) == f.name);
            args.push(match own {
                Some((name, _)) => Expression::SymbolRef { id: name.clone(), ty: f.ty.clone(), loc: Loc::NONE },
                None => Expression::Default(f.ty.clone()),
            });
        }
        // Unlocated: `enums::resolve_enum_cases` reports every located
        // construction of the enum, which only its cases may do. A case that
        // carries nothing is one shared, immortal object, except in a
        // `[Value]` enum, where every case is a value.
        let make = if case.payload.is_empty() && !has_attribute(&decl.attributes, VALUE_ATTRIBUTE) {
            Expression::StaticCase { ty: st.ty.clone(), tag: case.value }
        } else {
            Expression::FunctionCall { function: st.ty.to_string(), args, loc: Loc::NONE }
        };
        let f = method(&case.name, st.ty.clone(), parameters, vec![returns(make)], true, case.attributes.clone(), case.loc);
        st.method_members.push(f);
    }
    let text = |value: &str| Expression::StringLiteral { value: value.to_string(), is_raw: false, loc: Loc::NONE };
    let tag = || Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: TAG_FIELD.to_string(), loc: Loc::NONE };
    let mut items: Vec<Statement> = cases
        .iter()
        .map(|c| {
            Statement::Branch(Branch {
                condition: Expression::Binary {
                    op: BinaryOp::Equal,
                    lhs: Box::new(tag()),
                    rhs: Box::new(Expression::IntLiteral(c.value)),
                    loc: Loc::NONE,
                },
                if_block: Block { name: String::new(), items: vec![returns(text(&c.name))], attributes: vec![] },
                else_block: None,
            })
        })
        .collect();
    items.push(returns(text("")));
    st.method_members.push(method("name", TypeName::new("String"), vec![], items, false, vec![], at));
    st.enum_cases = Some(cases);
    Ok(st)
}

/// A method of an enum, as the free function `E::m` (see
/// `enums::method_name`): an instance method takes the value as its first
/// parameter, `this`, by value.
fn enum_method(decl: &ast::StructDecl, m: &ast::FunctionDecl) -> Result<FunctionDef, Diagnostic> {
    let at = loc(m.name_span);
    if crate::enums::BUILT_IN_METHODS.contains(&m.name.as_str()) {
        return Err(Diagnostic::error(format!("'{}' is built into every enum and cannot be redeclared", m.name)).at(at));
    }
    let operator = !m.name.starts_with(|c: char| c.is_ascii_alphanumeric() || c == '_') || m.is_indexer;
    if operator && m.is_static {
        return Err(Diagnostic::error(format!("an operator of enum '{}' cannot be static", decl.name)).at(at));
    }
    if m.name == "==" || m.name == "!=" {
        return Err(Diagnostic::error(format!(
            "enum '{}' cannot declare '{}': it compares its cases with '==' and '!=' already",
            decl.name, m.name
        ))
        .at(at));
    }
    // A value is passed by value and never changes, so nothing can assign
    // through one.
    let compound = m.name.ends_with('=') && !["<=", ">="].contains(&m.name.as_str());
    if compound || m.name == "__index_set" || m.name == "!!" {
        let shown = if m.name == "__index_set" { "[]".to_string() } else { m.name.clone() };
        let why = if m.name == "!!" {
            "an enum value is not a condition".to_string()
        } else {
            "its values never change".to_string()
        };
        return Err(Diagnostic::error(format!("enum '{}' cannot declare '{}': {}", decl.name, shown, why)).at(at));
    }
    let mut f = function_def(m, None)?;
    f.name = crate::enums::method_name(&decl.name, &m.name);
    if !m.is_static {
        f.parameters.insert(0, crate::enums::this_parameter(&decl.name));
    }
    Ok(f)
}

/// The smallest and largest value of an integer type.
pub(crate) fn integer_range(name: &str) -> (i128, i128) {
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
        owner: Loc::NONE,
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
///
/// Hidden locals are numbered from zero in each file: they are local to their
/// function, so they only need to be unique within it, and a file's code must
/// not depend on how many loops the files built before it had (the build
/// cache reuses a unit's object when its own sources match).
pub fn build_file(module: &ast::Module, file: FileId) -> Result<Module, Diagnostic> {
    reset_counters();
    let previous = FILE.with(|f| f.replace(file));
    let previous_error = LABEL_ERROR.with(|e| e.take());
    let previous_uses = TYPE_USES.with(|u| u.take());
    let previous_literals = LITERAL_ARGS.with(|l| l.take());
    let previous_properties = PROPERTIES.with(|p| p.take());
    let previous_context = CONTEXT.with(|c| c.take());
    let previous_index = CONTEXT_INDEX.with(|i| i.take());
    // Hidden locals are numbered per file, so a file's code (and its build
    // cache unit's bitcode) does not depend on the files built before it.
    let previous_counters = counters();
    set_counters([0; 5]);
    let built = build_module(module);
    let (uses, contexts) = TYPE_USES.with(|u| u.replace(previous_uses));
    let literals = LITERAL_ARGS.with(|l| l.replace(previous_literals));
    let properties = PROPERTIES.with(|p| p.replace(previous_properties));
    CONTEXT.with(|c| *c.borrow_mut() = previous_context);
    CONTEXT_INDEX.with(|i| i.set(previous_index));
    let built = built.map(|mut m| {
        m.type_uses = uses;
        m.use_contexts = contexts;
        m.literal_args = literals;
        m.properties = properties;
        m
    });
    set_counters(previous_counters);
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
    // A `[__BuiltIn]` declaration documents a compiler built-in; the
    // compiler never reads it (see `platform::keep`).
    for decl in module.declarations.iter().filter(|d| !ast::is_built_in(d.attributes())) {
        with_attributes(decl.attributes(), || declare(decl, &mut out))?;
    }
    Ok(out)
}

/// Builds top-level declaration `decl` into `out`.
fn declare(decl: &ast::Declaration, out: &mut Module) -> Result<(), Diagnostic> {
    {
        match decl {
            ast::Declaration::Variable(v) => {
                // Module-scope variable: an addressable global, not a
                // function. The initializer (if any) is codegen'd into the
                // global's constant initializer or an init function.
                out.globals.push(variable_def(v, Kind::Variable)?);
            }
            ast::Declaration::Static(s) => out.static_blocks.push(static_items::module_static_block(s)?),
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
                    if !f.is_exported {
                        out.private_functions.insert(loc(f.name_span));
                    }
                    out.functions.push(function_def(f, None)?);
                }
            }
            ast::Declaration::Struct(s) if is_reference_enum(s) => {
                out.structs.push(in_generic_scope(&s.generic_params, None, || reference_enum_def(s))?)
            }
            ast::Declaration::Struct(s) if s.enumeration.is_some() => {
                out.enums.push(enum_def(s)?);
                for m in &s.methods {
                    out.functions.push(enum_method(s, m)?);
                }
                check_enum_property_names(s)?;
                for property in &s.properties {
                    for mut f in property_members(property, PropertyOwner::Enum { name: &s.name })?.accessors {
                        f.name = crate::enums::method_name(&s.name, &f.name);
                        f.parameters.insert(0, crate::enums::this_parameter(&s.name));
                        out.functions.push(f);
                    }
                }
            }
            ast::Declaration::Struct(s) => out.structs.push(in_generic_scope(&s.generic_params, None, || struct_def(s))?),
            ast::Declaration::Trait(t) => out.traits.push(in_generic_scope(&t.generic_params, None, || trait_def(t))?),
            ast::Declaration::Extend(e) => {
                // A constrained extension's parameters carry the constraints
                // it adds (`extend Box<T: Named>`), beside the struct's own.
                let params: Vec<ast::GenericParam> = e
                    .target
                    .generic_types
                    .iter()
                    .zip(&e.target_bounds)
                    .filter(|(arg, bounds)| arg.generic_types.is_empty() && !bounds.is_empty())
                    .map(|(arg, bounds)| ast::GenericParam {
                        name: arg.name.clone(),
                        name_span: arg.span,
                        bounds: bounds.clone(),
                        default: None,
                        is_argument: false,
                    })
                    .collect();
                out.extensions.push(in_generic_scope(&params, Some(&e.target), || extension_def(e))?)
            }
            ast::Declaration::TypeAlias(t) => {
                check_deprecation(&t.attributes)?;
                reject_implicit(&t.attributes)?;
                let alias = in_generic_scope(&t.generic_params, None, || TypeAliasDef {
                    name: t.name.clone(),
                    generic_params: t.generic_params.iter().map(generic_param_from).collect(),
                    target: type_name_from(&t.target),
                    attributes: t.attributes.clone(),
                    loc: loc(t.name_span),
                });
                out.type_aliases.push(alias)
            }
        }
    }
    Ok(())
}
