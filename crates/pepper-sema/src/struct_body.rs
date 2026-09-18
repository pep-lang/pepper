//! Synthesized struct members: port of `source/Sema/Model/Struct.cpp:99-192`.
//! Adds the `__refcount` head field, the `__acquire`/`__release`/`__dtor`
//! bodies, and the ctor `finish()` prologue/epilogue.

use crate::model::*;
use crate::type_name::TypeName;

fn member_ref(name: &str) -> Expression {
    Expression::MemberRef {
        lhs: Box::new(Expression::ThisRef),
        name: name.to_string(),
    }
}

fn call(function: &str, args: Vec<Expression>) -> Statement {
    Statement::Expression(Expression::FunctionCall {
        function: function.to_string(),
        args,
    })
}

fn str_lit(value: String) -> Expression {
    Expression::StringLiteral {
        value,
        is_raw: true,
    }
}

fn var_def(name: &str, ty: TypeName, default: Option<Expression>, hidden: bool) -> VariableDef {
    VariableDef {
        name: name.to_string(),
        ty,
        default,
        hidden,
        kind: Kind::Variable,
    }
}

fn if_block(condition: Expression, items: Vec<Statement>) -> Statement {
    Statement::Branch(Branch {
        condition,
        if_block: Block {
            name: "if".to_string(),
            items,
        },
        else_block: None,
    })
}

/// Fill in the refcount field + synthesized method bodies (the `StructDef`
/// constructor part of `Struct.cpp:99-149`).
pub fn apply_synthesized(st: &mut StructDef) {
    // Head field for the refcount.
    st.field_members.insert(
        0,
        var_def("__refcount", TypeName::new("u32"), Some(Expression::IntLiteral(0)), false),
    );

    let struct_name = st.name.clone();

    // __acquire body: ++this.__refcount + trace calls.
    if let Some(body) = &mut st.acquire.body {
        body.items = vec![
            Statement::Expression(Expression::Binary {
                op: BinaryOp::Assign,
                lhs: Box::new(member_ref("__refcount")),
                rhs: Box::new(Expression::Binary {
                    op: BinaryOp::Add,
                    lhs: Box::new(member_ref("__refcount")),
                    rhs: Box::new(Expression::IntLiteral(1)),
                }),
            }),
            call(
                "trace_ptr",
                vec![
                    Expression::ThisRef,
                    str_lit(format!("acquire: {}", struct_name)),
                ],
            ),
            call(
                "trace_int",
                vec![
                    member_ref("__refcount"),
                    str_lit(format!("  refcount: {}", struct_name)),
                ],
            ),
        ];
    }

    // __release body: null-check, decrement, trace calls, dtor at zero.
    if let Some(body) = &mut st.release.body {
        body.items = vec![
            // NOTE: release gets called blindly on the lhs of any assignment.
            // The lhs can be a null-initialized ref.
            if_block(
                Expression::Binary {
                    op: BinaryOp::Identical,
                    lhs: Box::new(Expression::ThisRef),
                    rhs: Box::new(Expression::PointerLiteral),
                },
                vec![Statement::Return(ReturnStatement { expr: None })],
            ),
            Statement::Expression(Expression::Binary {
                op: BinaryOp::Assign,
                lhs: Box::new(member_ref("__refcount")),
                rhs: Box::new(Expression::Binary {
                    op: BinaryOp::Sub,
                    lhs: Box::new(member_ref("__refcount")),
                    rhs: Box::new(Expression::IntLiteral(1)),
                }),
            }),
            call(
                "trace_ptr",
                vec![
                    Expression::ThisRef,
                    str_lit(format!("release: {}", struct_name)),
                ],
            ),
            call(
                "trace_int",
                vec![
                    member_ref("__refcount"),
                    str_lit(format!("  refcount: {}", struct_name)),
                ],
            ),
            if_block(
                Expression::Binary {
                    op: BinaryOp::Equal,
                    lhs: Box::new(member_ref("__refcount")),
                    rhs: Box::new(Expression::IntLiteral(0)),
                },
                vec![
                    call(
                        "trace_ptr",
                        vec![Expression::ThisRef, str_lit(format!("dtor: {}", struct_name))],
                    ),
                    Statement::Expression(Expression::MethodCall {
                        this: Box::new(Expression::ThisRef),
                        method: "__dtor".to_string(),
                        args: vec![],
                    }),
                ],
            ),
        ];
    }
}

/// Ctor finish: allocation prologue + field inits + user ctor body +
/// `return this`; dtor gets `_pep_free`; synthesized methods appended
/// (port of `Struct.cpp:159-192`).
pub fn finish(st: &mut StructDef) -> Result<(), String> {
    let struct_name = st.name.clone();
    // `this.<field>` constructor parameters become real parameters that
    // assign the field. Collect first so we don't borrow `st` twice.
    let init_params: Vec<(usize, String, TypeName)> = st
        .constructor
        .parameters
        .iter()
        .enumerate()
        .filter(|(_, p)| p.name.starts_with("this."))
        .map(|(i, p)| {
            let field = p.name.strip_prefix("this.").unwrap().to_string();
            let ty = st
                .field_members
                .iter()
                .find(|f| f.name == field)
                .map(|f| f.ty.clone())
                .ok_or_else(|| {
                    format!(
                        "constructor parameter this.{} has no matching field on {}",
                        field, struct_name
                    )
                })?;
            Ok((i, field, ty))
        })
        .collect::<Result<Vec<_>, String>>()?;
    for (i, field, ty) in &init_params {
        st.constructor.parameters[*i].name = format!("__init_{}", field);
        st.constructor.parameters[*i].ty = ty.clone();
    }

    // Copy off whatever the user put in the ctor, if anything.
    let user_ctor = st
        .constructor
        .body
        .as_ref()
        .map(|b| b.items.clone())
        .unwrap_or_default();

    // Create the allocation for `this`; the `size` literal value is filled in
    // at codegen time.
    let mut items: Vec<Statement> = vec![
        Statement::Declaration(Declaration::Variable(var_def(
            "size",
            TypeName::new("u64"),
            None,
            true,
        ))),
        Statement::Declaration(Declaration::Variable(var_def(
            "this",
            st.ty.clone(),
            Some(Expression::FunctionCall {
                function: "_pep_malloc".to_string(),
                args: vec![Expression::SymbolRef {
                    id: "size".to_string(),
                    ty: TypeName::auto(),
                }],
            }),
            false,
        ))),
        call(
            "trace_ptr",
            vec![Expression::ThisRef, str_lit(format!("ctor: {}", struct_name))],
        ),
    ];

    // Field initializations.
    for field in &st.field_members {
        if let Some(default) = &field.default {
            items.push(Statement::Expression(Expression::Binary {
                op: BinaryOp::Assign,
                lhs: Box::new(member_ref(&field.name)),
                rhs: Box::new(default.clone()),
            }));
        }
    }
    // Assign the `this.<field>` parameters to their fields, in declaration
    // order. The `__init_` prefix keeps them out of the bare-symbol →
    // `this.<field>` rewrite, so they don't shadow the field.
    for (_, field, ty) in &init_params {
        items.push(Statement::Expression(Expression::Binary {
            op: BinaryOp::Assign,
            lhs: Box::new(member_ref(field)),
            rhs: Box::new(Expression::SymbolRef {
                id: format!("__init_{}", field),
                ty: ty.clone(),
            }),
        }));
    }

    // Restore the user's ctor instructions.
    items.extend(user_ctor);

    // The ctor returns `this`.
    items.push(Statement::Return(ReturnStatement {
        expr: Some(Expression::SymbolRef {
            id: "this".to_string(),
            ty: st.ty.clone(),
        }),
    }));

    st.constructor.body = Some(Block {
        name: st.constructor.name.clone(),
        items,
    });

    // Free at the end of the destructor.
    if let Some(body) = &mut st.destructor.body {
        body.items.push(call(
            "_pep_free",
            vec![Expression::ThisRef],
        ));
    }

    // Append synthesized methods in order: release, acquire, dtor.
    let release = st.release.clone();
    let acquire = st.acquire.clone();
    let destructor = st.destructor.clone();
    st.method_members.push(release);
    st.method_members.push(acquire);
    st.method_members.push(destructor);
    Ok(())
}

/// Apply both the constructor bodies and the synthesized members to every
/// struct in the module.
pub fn apply(module: &mut Module) -> Result<(), String> {
    for st in &mut module.structs {
        apply_synthesized(st);
        finish(st)?;
    }
    Ok(())
}
