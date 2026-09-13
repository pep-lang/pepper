//! AST → model builder: port of `source/Sema/ModelBuilder.cpp` (`SemaParser`),
//! without the C++ Builder scope machinery — the model tree is built directly.

use crate::model::*;
use crate::type_name::TypeName;
use pepper_parser::ast;

fn type_name_from(t: &ast::TypeName) -> TypeName {
    let args: Vec<TypeName> = t.generic_types.iter().map(type_name_from).collect();
    if args.is_empty() {
        TypeName::new(&t.name)
    } else {
        TypeName::with_args(&t.name, args)
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
        "|" => BinaryOp::BitOr,
        "||" => BinaryOp::LogicalOr,
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

fn expression(expr: &ast::Expression) -> Expression {
    match expr {
        ast::Expression::Literal(lit) => match lit {
            ast::Literal::String(value, is_raw) => Expression::StringLiteral {
                value: value.clone(),
                is_raw: *is_raw,
            },
            ast::Literal::Integer(v) => Expression::IntLiteral(*v),
            ast::Literal::Float(v) => Expression::FloatLiteral(*v),
            ast::Literal::Bool(v) => Expression::BoolLiteral(*v),
            ast::Literal::Null => Expression::PointerLiteral,
        },
        ast::Expression::SymbolRef(id) => {
            if id == "this" {
                Expression::ThisRef
            } else {
                Expression::SymbolRef {
                    id: id.clone(),
                    ty: TypeName::auto(),
                }
            }
        }
        ast::Expression::TypeLiteral(ty) => Expression::FunctionCall {
            function: ty.name.clone(),
            args: vec![],
        },
        ast::Expression::SizeOf(ty) => Expression::SizeOf(type_name_from(ty)),
        ast::Expression::Unary { op, prefix, operand } => Expression::Unary {
            op: unary_op(op, *prefix).expect("unknown unary operator"),
            operand: Box::new(expression(operand)),
        },
        ast::Expression::Binary { lhs, op, rhs } => Expression::Binary {
            op: binary_op(op).expect("unknown binary operator"),
            lhs: Box::new(expression(lhs)),
            rhs: Box::new(expression(rhs)),
        },
        ast::Expression::Ternary {
            condition,
            true_expr,
            false_expr,
        } => Expression::Ternary {
            condition: Box::new(expression(condition)),
            true_expr: Box::new(expression(true_expr)),
            false_expr: Box::new(expression(false_expr)),
        },
        ast::Expression::Index { lhs, rhs } => Expression::Index {
            lhs: Box::new(expression(lhs)),
            rhs: Box::new(expression(rhs)),
        },
        ast::Expression::MemberAccess { lhs, name } => Expression::MemberRef {
            lhs: Box::new(expression(lhs)),
            name: name.clone(),
        },
        ast::Expression::FunctionCall { function, arguments } => {
            // Constructor-style call `Name<args>(ctor_args)` keeps the generic
            // target name; the args become the call arguments.
            let function = match function.as_ref() {
                ast::Expression::TypeLiteral(ty) => type_name_from(ty).to_string(),
                ast::Expression::SymbolRef(name) => name.clone(),
                other => match other {
                    _ => panic!("unsupported call target"),
                },
            };
            Expression::FunctionCall {
                function,
                args: arguments.iter().map(expression).collect(),
            }
        }
    }
}

fn variable_def(decl: &ast::VariableDecl, kind: Kind) -> VariableDef {
    VariableDef {
        name: decl.name.clone(),
        ty: type_name_from(&decl.type_name),
        default: decl.default_value.as_ref().map(expression),
        hidden: false,
        kind,
    }
}

fn block(block: &ast::Block) -> Block {
    Block {
        name: String::new(),
        items: block.statements.iter().map(statement).collect(),
    }
}

fn statement(stmt: &ast::Statement) -> Statement {
    match stmt {
        ast::Statement::Expression(expr) => Statement::Expression(expression(expr)),
        ast::Statement::Block(inner) => Statement::Block(block(inner)),
        ast::Statement::Declaration(decl) => Statement::Declaration(declaration(decl)),
        ast::Statement::Branch(branch) => Statement::Branch(Branch {
            condition: expression(&branch.condition),
            if_block: block(&branch.if_block),
            else_block: branch.else_block.as_ref().map(block),
        }),
        ast::Statement::While(wh) => Statement::While(While {
            condition: expression(&wh.condition),
            block: block(&wh.block),
        }),
        ast::Statement::Return(ret) => Statement::Return(ReturnStatement {
            expr: Some(expression(&ret.expr)),
        }),
    }
}

fn function_def(decl: &ast::FunctionDecl, parent: Option<String>) -> FunctionDef {
    let parameters: Vec<VariableDef> = decl
        .parameters
        .iter()
        .map(|p| variable_def(p, Kind::Param))
        .collect();
    let body = decl.body.as_ref().map(block);
    FunctionDef {
        name: decl.name.clone(),
        ty: type_name_from(&decl.return_type),
        parameters,
        body,
        parent,
        is_static: decl.is_static,
        is_indexer: decl.is_indexer,
        is_generic_func: false,
    }
}

fn declaration(decl: &ast::Declaration) -> Declaration {
    match decl {
        ast::Declaration::Variable(v) => {
            Declaration::Variable(variable_def(v, Kind::Variable))
        }
        ast::Declaration::Function(f) => Declaration::Function(function_def(f, None)),
        ast::Declaration::Struct(s) => Declaration::Struct(struct_def(s)),
        ast::Declaration::Trait(t) => Declaration::Trait(TraitDef {
            name: t.name.clone(),
            methods: t.methods.iter().map(|m| function_def(m, None)).collect(),
        }),
        ast::Declaration::Extend(e) => Declaration::Extension(ExtensionDef {
            target: type_name_from(&e.target),
            resolved: None,
            traits: e.traits.iter().map(type_name_from).collect(),
            methods: e.methods.iter().map(|m| function_def(m, None)).collect(),
        }),
    }
}

/// Build a `StructDef` from an AST struct declaration, including constructor
/// and destructor shells (filled in by `struct_body::finish`).
fn struct_def(decl: &ast::StructDecl) -> StructDef {
    let generic_params: Vec<TypeName> = decl.generic_params.iter().map(type_name_from).collect();
    let base_name = decl.name.clone();
    let ty = if generic_params.is_empty() {
        TypeName::new(&base_name)
    } else {
        TypeName::with_args(&base_name, generic_params.clone())
    };
    let field_members: Vec<VariableDef> = decl
        .fields
        .iter()
        .map(|f| variable_def(f, Kind::Field))
        .collect();
    let method_members: Vec<FunctionDef> = decl
        .methods
        .iter()
        .map(|m| function_def(m, Some(base_name.clone())))
        .collect();

    let constructor = match &decl.constructor {
        Some(ctor) => {
            let mut f = function_def(ctor, Some(base_name.clone()));
            f.name = ty.to_string();
            f
        }
        None => FunctionDef {
            name: ty.to_string(),
            ty: ty.clone(),
            parameters: vec![],
            body: Some(Block {
                name: String::new(),
                items: vec![],
            }),
            parent: Some(base_name.clone()),
            is_static: false,
            is_indexer: false,
            is_generic_func: false,
        },
    };
    let destructor = match &decl.destructor {
        Some(body) => FunctionDef {
            name: "__dtor".to_string(),
            ty: TypeName::void(),
            parameters: vec![],
            body: Some(block(body)),
            parent: Some(base_name.clone()),
            is_static: false,
            is_indexer: false,
            is_generic_func: false,
        },
        None => FunctionDef {
            name: "__dtor".to_string(),
            ty: TypeName::void(),
            parameters: vec![],
            body: Some(Block {
                name: String::new(),
                items: vec![],
            }),
            parent: Some(base_name.clone()),
            is_static: false,
            is_indexer: false,
            is_generic_func: false,
        },
    };

    StructDef {
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
    }
}

fn empty_method(parent: &str, name: &str) -> FunctionDef {
    FunctionDef {
        name: name.to_string(),
        ty: TypeName::void(),
        parameters: vec![],
        body: Some(Block {
            name: String::new(),
            items: vec![],
        }),
        parent: Some(parent.to_string()),
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
    }
}

/// Parse-level module → model module (no synthesized members yet; call
/// [`struct_body::apply_synthesized`] afterwards).
pub fn build(module: &ast::Module) -> Module {
    let mut out = Module::default();
    out.imports = module.imports.clone();
    for decl in &module.declarations {
        match decl {
            ast::Declaration::Variable(v) => {
                out.functions.push(FunctionDef {
                    name: v.name.clone(),
                    ty: type_name_from(&v.type_name),
                    parameters: vec![],
                    body: v
                        .default_value
                        .as_ref()
                        .map(|expr| Block {
                            name: String::new(),
                            items: vec![Statement::Expression(expression(expr))],
                        }),
                    parent: None,
                    is_static: false,
                    is_indexer: false,
                    is_generic_func: false,
                });
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
                            .collect(),
                    });
                } else {
                    out.functions.push(function_def(f, None));
                }
            }
            ast::Declaration::Struct(s) => out.structs.push(struct_def(s)),
            ast::Declaration::Trait(t) => out.traits.push(TraitDef {
                name: t.name.clone(),
                methods: t.methods.iter().map(|m| function_def(m, None)).collect(),
            }),
            ast::Declaration::Extend(e) => out.extensions.push(ExtensionDef {
                target: type_name_from(&e.target),
                resolved: None,
                traits: e.traits.iter().map(type_name_from).collect(),
                methods: e.methods.iter().map(|m| function_def(m, None)).collect(),
            }),
        }
    }
    out
}
