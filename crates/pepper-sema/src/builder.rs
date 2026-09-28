//! AST → model builder: port of `source/Sema/ModelBuilder.cpp` (`SemaParser`),
//! without the C++ Builder scope machinery — the model tree is built directly.

use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;

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
        "=" => BinaryOp::Assign,
        "+=" => BinaryOp::AddAssign,
        "-=" => BinaryOp::SubAssign,
        "*=" => BinaryOp::MulAssign,
        "/=" => BinaryOp::DivAssign,
        "%=" => BinaryOp::ModAssign,
        "<<=" => BinaryOp::LShiftAssign,
        ">>=" => BinaryOp::RShiftAssign,
        "&=" => BinaryOp::BitAndAssign,
        // C++ quirk: "^=" maps to BitOrAssign (ModelBuilder.cpp:244); real xor-assign is "^"
        "^=" => BinaryOp::BitOrAssign,
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

fn expression(expr: &ast::Expression) -> Result<Expression, String> {
    match expr {
        ast::Expression::Literal { value: lit, .. } => match lit {
            ast::Literal::String(value) => Ok(Expression::StringLiteral {
                value: value.clone(),
                is_raw: false,
            }),
            ast::Literal::Integer(v) => Ok(Expression::IntLiteral(*v)),
            ast::Literal::Float(v) => Ok(Expression::FloatLiteral(*v)),
            ast::Literal::Bool(v) => Ok(Expression::BoolLiteral(*v)),
            ast::Literal::Null => Ok(Expression::PointerLiteral),
        },
        ast::Expression::SymbolRef { id, .. } => {
            if id == "this" {
                Ok(Expression::ThisRef)
            } else {
                Ok(Expression::SymbolRef {
                    id: id.clone(),
                    ty: TypeName::auto(),
                })
            }
        }
        ast::Expression::TypeLiteral(ty) => Ok(Expression::FunctionCall {
            function: type_name_from(ty).to_string(),
            args: vec![],
        }),
        ast::Expression::SizeOf(ty) => Ok(Expression::SizeOf(type_name_from(ty))),
        ast::Expression::Unary { op, prefix, operand, .. } => Ok(Expression::Unary {
            op: unary_op(op, *prefix).expect("unknown unary operator"),
            operand: Box::new(expression(operand)?),
        }),
        ast::Expression::Cast { expr, ty, .. } => Ok(Expression::Cast {
            expr: Box::new(expression(expr)?),
            ty: type_name_from(ty),
        }),
        ast::Expression::Binary { lhs, op, rhs, .. } => Ok(Expression::Binary {
            op: binary_op(op).expect("unknown binary operator"),
            lhs: Box::new(expression(lhs)?),
            rhs: Box::new(expression(rhs)?),
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
        ast::Expression::Index { lhs, rhs, .. } => Ok(Expression::Index {
            lhs: Box::new(expression(lhs)?),
            rhs: Box::new(expression(rhs)?),
        }),
        ast::Expression::MemberAccess { lhs, name, .. } => {
            if name.starts_with("__") && name != "__release" && name != "__acquire" {
                return Err(format!("'{}' is a reserved (synthesized) member and cannot be accessed from source code", name));
            }
            Ok(Expression::MemberRef {
                lhs: Box::new(expression(lhs)?),
                name: name.clone(),
            })
        }
        ast::Expression::FunctionCall { function, arguments, .. } => {
            // Method call `t.getX()`: the target is a member access.
            if let ast::Expression::MemberAccess { lhs, name, .. } = function.as_ref() {
                // `__release`/`__acquire` are deliberately callable from
                // source: explicit refcount control is the language's escape
                // hatch for object lifetimes.
                if name.starts_with("__") && name != "__release" && name != "__acquire" {
                    return Err(format!("'{}' is a reserved (synthesized) method and cannot be called from source code", name));
                }
                return Ok(Expression::MethodCall {
                    this: Box::new(expression(lhs)?),
                    method: name.clone(),
                    args: arguments.iter().map(expression).collect::<Result<Vec<_>, _>>()?,
                });
            }
            // Constructor-style call `Name<args>(ctor_args)` keeps the generic
            // target name; the args become the call arguments.
            let function = match function.as_ref() {
                ast::Expression::TypeLiteral(ty) => type_name_from(ty).to_string(),
                ast::Expression::SymbolRef { id: name, .. } => name.clone(),
                ast::Expression::Literal { value: lit, .. } => lit.to_string(),
                other => {
                    // Fall back to the display form for exotic targets.
                    format!("{}", other)
                }
            };
            Ok(Expression::FunctionCall {
                function,
                args: arguments.iter().map(expression).collect::<Result<Vec<_>, _>>()?,
            })
        }
    }
}
fn variable_def(decl: &ast::VariableDecl, kind: Kind) -> Result<VariableDef, String> {
    Ok(VariableDef {
        name: decl.name.clone(),
        ty: type_name_from(&decl.type_name),
        default: decl.default_value.as_ref().map(expression).transpose()?,
        hidden: false,
        kind,
    })
}

fn block(block: &ast::Block) -> Result<Block, String> {
    Ok(Block {
        name: String::new(),
        items: block.statements.iter().map(statement).collect::<Result<Vec<_>, _>>()?,
        attributes: block.attributes.clone(),
    })
}

fn statement(stmt: &ast::Statement) -> Result<Statement, String> {
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
        ast::Statement::Return(ret) => Ok(Statement::Return(ReturnStatement {
            expr: Some(expression(&ret.expr)?),
        })),
        ast::Statement::LoopBreak(lb) => Ok(Statement::LoopBreak(LoopBreak {
            kind: match lb.kind {
                ast::LoopBreakKind::Break => LoopBreakKind::Break,
                ast::LoopBreakKind::Continue => LoopBreakKind::Continue,
            },
        })),
    }
}

fn function_def(decl: &ast::FunctionDecl, parent: Option<String>) -> Result<FunctionDef, String> {
    let parameters: Vec<VariableDef> = decl
        .parameters
        .iter()
        .map(|p| variable_def(p, Kind::Param))
        .collect::<Result<Vec<_>, _>>()?;
    let body = decl.body.as_ref().map(block).transpose()?;
    Ok(FunctionDef {
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
    })
}

fn declaration(decl: &ast::Declaration) -> Result<Declaration, String> {
    match decl {
        ast::Declaration::Variable(v) => {
            Ok(Declaration::Variable(variable_def(v, Kind::Variable)?))
        }
        ast::Declaration::Function(f) => Ok(Declaration::Function(function_def(f, None)?)),
        ast::Declaration::Struct(s) => Ok(Declaration::Struct(struct_def(s)?)),
        ast::Declaration::Trait(t) => Ok(Declaration::Trait(TraitDef {
            name: t.name.clone(),
            methods: t.methods.iter().map(|m| function_def(m, None)).collect::<Result<Vec<_>, _>>()?,
            attributes: t.attributes.clone(),
        })),
        ast::Declaration::Extend(e) => Ok(Declaration::Extension(ExtensionDef {
            target: type_name_from(&e.target),
            resolved: None,
            traits: e.traits.iter().map(type_name_from).collect(),
            methods: e.methods.iter().map(|m| function_def(m, None)).collect::<Result<Vec<_>, _>>()?,
            attributes: e.attributes.clone(),
        })),
    }
}
/// Build a `StructDef` from an AST struct declaration, including constructor
/// and destructor shells (filled in by `struct_body::finish`).
fn struct_def(decl: &ast::StructDecl) -> Result<StructDef, String> {
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
    let method_members: Vec<FunctionDef> = decl
        .methods
        .iter()
        .map(|m| function_def(m, Some(base_name.clone())))
        .collect::<Result<Vec<_>, _>>()?;

    let constructor = match &decl.constructor {
        Some(ctor) => {
            let mut f = function_def(ctor, Some(base_name.clone()))?;
            f.name = ty.to_string();
            f.ty = ty.clone();
            f
        }
        None => FunctionDef {
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
        },
    };
    let destructor = match &decl.destructor {
        Some(body) => FunctionDef {
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
        },
        None => FunctionDef {
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
        },
    };

    Ok(StructDef {
        name: base_name.clone(),
        ty,
        generic_params,
        field_members,
        method_members,
        constructor,
        destructor,
        acquire: empty_method(&base_name, "__acquire"),
        release: empty_method(&base_name, "__release"),
        traits: vec![],
        attributes: decl.attributes.clone(),
    })
}

fn empty_method(parent: &str, name: &str) -> FunctionDef {
    FunctionDef {
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
    }
}

/// Parse-level module → model module (no synthesized members yet; call
/// [`struct_body::apply_synthesized`] afterwards).
pub fn build(module: &ast::Module) -> Result<Module, String> {
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
                    out.externs.push(ExternDef {
                        name: f.name.clone(),
                        ty: type_name_from(&f.return_type),
                        parameters: f
                            .parameters
                            .iter()
                            .map(|p| variable_def(p, Kind::Param))
                            .collect::<Result<Vec<_>, _>>()?,
                        attributes: f.attributes.clone(),
                    });
                } else {
                    out.functions.push(function_def(f, None)?);
                }
            }
            ast::Declaration::Struct(s) => out.structs.push(struct_def(s)?),
            ast::Declaration::Trait(t) => out.traits.push(TraitDef {
                name: t.name.clone(),
                methods: t.methods.iter().map(|m| function_def(m, None)).collect::<Result<Vec<_>, _>>()?,
                attributes: t.attributes.clone(),
            }),
            ast::Declaration::Extend(e) => out.extensions.push(ExtensionDef {
                target: type_name_from(&e.target),
                resolved: None,
                traits: e.traits.iter().map(type_name_from).collect(),
                methods: e.methods.iter().map(|m| function_def(m, None)).collect::<Result<Vec<_>, _>>()?,
                attributes: e.attributes.clone(),
            }),
        }
    }
    Ok(out)
}
