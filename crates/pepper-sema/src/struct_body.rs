//! Synthesized struct members: port of `source/Sema/Model/Struct.cpp:99-192`.
//! Adds the `__refcount` head field, the `__acquire`/`__release`/`__dtor`
//! bodies, and the ctor `finish()` prologue/epilogue.

use crate::model::*;
use crate::type_name::TypeName;

fn member_ref(name: &str) -> Expression {
    Expression::MemberRef {
        lhs: Box::new(Expression::ThisRef),
        name: name.to_string(),
        loc: Loc::NONE,
    }
}

fn call(function: &str, args: Vec<Expression>) -> Statement {
    Statement::Expression(Expression::FunctionCall {
        function: function.to_string(),
        args,
        loc: Loc::NONE,
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
        attributes: vec![],
        loc: Loc::NONE,
        type_loc: Loc::NONE,
        is_const: false,
    }
}

fn if_block(condition: Expression, items: Vec<Statement>) -> Statement {
    Statement::Branch(Branch {
        condition,
        if_block: Block {
            name: "if".to_string(),
            items,
            attributes: vec![],
        },
        else_block: None,
    })
}
/// Zero value for a field type: null reference for struct/pointer types,
/// 0.0 for floats, 0 for everything else (port of `zero_value` in
/// `StructGen.cpp:35`).
fn zero_for(ty: &TypeName) -> Expression {
    if ty.is_pointer() || ty.is_struct() {
        Expression::PointerLiteral
    } else if matches!(ty.name.as_str(), "f32" | "float" | "f64" | "double") {
        Expression::FloatLiteral(0.0)
    } else {
        Expression::IntLiteral(0)
    }
}

/// Fill in the refcount field + synthesized method bodies (the `StructDef`
/// constructor part of `Struct.cpp:99-149`).
pub fn apply_synthesized(st: &mut StructDef) {
    // Head field for the refcount. Default 0 (port of `Struct.cpp:108-109`,
    // `IntegerLiteral(0)`): a freshly constructed object carries NO refs —
    // its first reference is taken by the receiver's init/param-entry
    // acquire (the caller side), exactly as C++'s `RefTypeOps::init` does.
    // Guarded: specialized instances clone the base's fields (which already
    // carry the head) and re-run apply_synthesized.
    if !st.field_members.iter().any(|f| f.name == "__refcount") {
        st.field_members.insert(
            0,
            var_def("__refcount", TypeName::new("u32"), Some(Expression::IntLiteral(0)), false),
        );
    }

    let struct_name = st.name.clone();

    // __acquire body: null-check, ++this.__refcount + trace calls. Codegen
    // acquires on a struct-reference store whenever the new occupant differs
    // from the old one (including nulls from zero-initialized slots), so the
    // guard mirrors __release's.
    if let Some(body) = &mut st.acquire.body {
        body.items = vec![
            if_block(
                Expression::Binary {
                    op: BinaryOp::Identical,
                    lhs: Box::new(Expression::ThisRef),
                    rhs: Box::new(Expression::PointerLiteral),
                    loc: Loc::NONE,
                },
                vec![Statement::Return(ReturnStatement { expr: None, loc: Loc::NONE })],
            ),
            Statement::Expression(Expression::Binary {
                op: BinaryOp::Assign,
                lhs: Box::new(member_ref("__refcount")),
                rhs: Box::new(Expression::Binary {
                    op: BinaryOp::Add,
                    lhs: Box::new(member_ref("__refcount")),
                    rhs: Box::new(Expression::IntLiteral(1)),
                    loc: Loc::NONE,
                }),
                loc: Loc::NONE,
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
                    loc: Loc::NONE,
                },
                vec![Statement::Return(ReturnStatement { expr: None, loc: Loc::NONE })],
            ),
            Statement::Expression(Expression::Binary {
                op: BinaryOp::Assign,
                lhs: Box::new(member_ref("__refcount")),
                rhs: Box::new(Expression::Binary {
                    op: BinaryOp::Sub,
                    lhs: Box::new(member_ref("__refcount")),
                    rhs: Box::new(Expression::IntLiteral(1)),
                    loc: Loc::NONE,
                }),
                loc: Loc::NONE,
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
                    loc: Loc::NONE,
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
                        loc: Loc::NONE,
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
                    loc: Loc::NONE,
                }],
                loc: Loc::NONE,
            }),
            false,
        ))),
        call(
            "trace_ptr",
            vec![Expression::ThisRef, str_lit(format!("ctor: {}", struct_name))],
        ),
    ];

    // Field initializations. A field with an explicit default is assigned it;
    // every other field is zero-initialized (null reference / 0), matching
    // `StructGen.cpp:31-37`. `_pep_malloc` already zeroes the payload, so the
    // stores are redundant today — kept for C++ reference parity and to make
    // the ctor's initialization contract explicit in the model (a future
    // non-zeroing allocator would not silently change semantics).
    for field in &st.field_members {
        let value = match &field.default {
            Some(d) => d.clone(),
            None => zero_for(&field.ty),
        };
        items.push(Statement::Expression(Expression::Binary {
            op: BinaryOp::Assign,
            lhs: Box::new(member_ref(&field.name)),
            rhs: Box::new(value),
            loc: Loc::NONE,
        }));
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
                loc: Loc::NONE,
            }),
            loc: Loc::NONE,
        }));
    }

    // The object leaves the ctor with `__refcount == 1`: `return this`
    // acquires at the return site, so the ctor result is an owned rvalue
    // carrying its creation ref — exactly as `std::make_shared` hands back a
    // shared_ptr. A variable init (`var x = T()`) moves that ref into the
    // slot; a pass-by-value param entry acquires on top of it. The ctor's
    // `this` local is excluded from scope tracking (codegen), so nothing
    // here releases the object.

    // Restore the user's ctor instructions.
    items.extend(user_ctor);

    // The ctor returns `this`.
    items.push(Statement::Return(ReturnStatement {
        expr: Some(Expression::SymbolRef {
            id: "this".to_string(),
            ty: st.ty.clone(),
            loc: Loc::NONE,
        }),
        loc: Loc::NONE,
    }));

    st.constructor.body = Some(Block {
        name: st.constructor.name.clone(),
        items,
        attributes: vec![],
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
/// struct in the module. Type aliases expand first so synthesis sees only
/// real types (a field of alias type must lower like a field of its target).
pub fn apply(module: &mut Module) -> Result<(), Diagnostic> {
    crate::errors::take(); // each run starts fresh
    crate::passes::resolve_type_aliases::resolve_type_aliases(module);
    if let Some(error) = crate::errors::take() {
        return Err(error);
    }
    for st in &mut module.structs {
        apply_synthesized(st);
        let loc = st.loc;
        finish(st).map_err(|e| Diagnostic::error(e).at(loc))?;
    }
    Ok(())
}
