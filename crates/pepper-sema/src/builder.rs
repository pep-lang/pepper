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
        });
        return TypeName::with_args("Array", vec![element]);
    }
    if args.is_empty() {
        TypeName::new(&t.name)
    } else {
        TypeName::with_args(&t.name, args)
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
    Ok(VariableDef {
        name: decl.name.clone(),
        ty: type_name_from(&decl.type_name),
        default: decl.default_value.as_ref().map(expression).transpose()?,
        hidden: false,
        kind,
        attributes: decl.attributes.clone(),
        loc: loc(decl.name_span),
        type_loc: if decl.type_name.span.is_empty() { Loc::NONE } else { loc(decl.type_name.span) },
        is_const: decl.is_const,
    })
}

fn block(block: &ast::Block) -> Result<Block, Diagnostic> {
    Ok(Block {
        name: String::new(),
        items: block.statements.iter().map(statement).collect::<Result<Vec<_>, _>>()?,
        attributes: block.attributes.clone(),
    })
}

fn statement(stmt: &ast::Statement) -> Result<Statement, Diagnostic> {
    match stmt {
        ast::Statement::Expression(expr) => Ok(Statement::Expression(expression(expr)?)),
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

thread_local! {
    /// Numbers each lowered `for` loop's hidden iterator local.
    static FOR_LOOPS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    /// Numbers each lowered `with` block's hidden locals.
    static WITH_BLOCKS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// Restart hidden-local numbering (see `crate::reset_program_counters`).
pub(crate) fn reset_counters() {
    FOR_LOOPS.with(|c| c.set(0));
    WITH_BLOCKS.with(|c| c.set(0));
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
    let mut element = variable_def(&f.binding, Kind::Variable)?;
    element.default = Some(Expression::MethodCall { this: iterator_ref(), method: "current".to_string(), args: vec![], loc: at });
    let body = Block {
        name: String::new(),
        items: vec![Statement::Declaration(Declaration::Variable(element)), Statement::Block(block(&f.block)?)],
        attributes: vec![],
    };
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

    let constructor = match &decl.constructor {
        Some(ctor) => {
            check_implicit_constructor(decl, ctor)?;
            let mut f = member_def(ctor, Some(base_name.clone()))?;
            f.name = ty.to_string();
            f.ty = ty.clone();
            f
        }
        None => FunctionDef {
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
        },
    };
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
        constructor,
        destructor,
        acquire: empty_method(&base_name, "__acquire"),
        release: empty_method(&base_name, "__release"),
        traits: vec![],
        attributes: decl.attributes.clone(),
        loc: loc(decl.name_span),
    })
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
    let built = build_module(module);
    FILE.with(|f| f.set(previous));
    built
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
