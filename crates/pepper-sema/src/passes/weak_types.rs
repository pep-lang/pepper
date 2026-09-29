//! Weak references: `__weak<T>` ≡ `std::weak_ptr<T>`.
//!
//! A `__weak<T>` value is a pointer to a `T` object, like a `T` value, but it
//! owns a weak count instead of a strong one. Each distinct `__weak<T>`
//! becomes a synthesized struct that is a *view of `T`'s object head*:
//!
//! ```text
//! struct __weak<T> {
//!     u32 __refcount;    # the same two head fields every struct starts with
//!     u32 __weakcount;
//! }
//! ```
//!
//! so codegen's shared_ptr rules (copy, assign, parameter, scope exit) apply
//! to weak slots unchanged, through its `__acquire`/`__release`:
//!
//! - `__acquire`: `++__weakcount`.
//! - `__release`: `--__weakcount`, freeing the memory at 0. The strong
//!   references hold one weak reference between them until the object is
//!   destroyed (see `struct_body`), so 0 means destroyed and unreferenced.
//!
//! Nothing constructs a `__weak<T>`: values come from `__weak_from<T>(t)`
//! and are read back through `__weak_upgrade<T>(w)` (codegen intrinsics).

use crate::model::*;
use crate::passes::function_types::empty_function;
use crate::type_name::TypeName;

fn head(field: &str) -> Expression {
    Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: field.to_string(), loc: Loc::NONE }
}

fn step(field: &str, op: BinaryOp) -> Statement {
    Statement::Expression(Expression::Binary {
        op: BinaryOp::Assign,
        lhs: Box::new(head(field)),
        rhs: Box::new(Expression::Binary {
            op,
            lhs: Box::new(head(field)),
            rhs: Box::new(Expression::IntLiteral(1)),
            loc: Loc::NONE,
        }),
        loc: Loc::NONE,
    })
}

fn is_zero(field: &str) -> Expression {
    Expression::Binary {
        op: BinaryOp::Equal,
        lhs: Box::new(head(field)),
        rhs: Box::new(Expression::IntLiteral(0)),
        loc: Loc::NONE,
    }
}

fn when(condition: Expression, items: Vec<Statement>) -> Statement {
    Statement::Branch(Branch {
        condition,
        if_block: Block { name: "if".to_string(), items, attributes: vec![] },
        else_block: None,
    })
}

/// `if (this === __null) { return; }`
fn null_guard() -> Statement {
    when(
        Expression::Binary {
            op: BinaryOp::Identical,
            lhs: Box::new(Expression::ThisRef),
            rhs: Box::new(Expression::PointerLiteral),
            loc: Loc::NONE,
        },
        vec![Statement::Return(ReturnStatement { expr: None, loc: Loc::NONE })],
    )
}

/// The synthesized struct for `ty` (`__weak<T>`).
pub fn weak_struct(ty: &TypeName) -> StructDef {
    let name = ty.to_string();
    let mut st = StructDef {
        name: name.clone(),
        ty: ty.clone(),
        generic_params: vec![],
        field_members: vec![],
        method_members: vec![],
        constructor: empty_function(&name, ty.clone(), &name),
        destructor: empty_function("__dtor", TypeName::void(), &name),
        acquire: empty_function("__acquire", TypeName::void(), &name),
        release: empty_function("__release", TypeName::void(), &name),
        traits: vec![],
        attributes: vec![],
        loc: Loc::NONE,
    };
    crate::struct_body::apply_synthesized(&mut st);
    if let Some(body) = &mut st.acquire.body {
        body.items = vec![null_guard(), step("__weakcount", BinaryOp::Add)];
    }
    if let Some(body) = &mut st.release.body {
        body.items = vec![
            null_guard(),
            step("__weakcount", BinaryOp::Sub),
            // The strong references hold one weak reference between them
            // until the object is destroyed, so 0 means destroyed and
            // unreferenced.
            when(
                is_zero("__weakcount"),
                vec![Statement::Expression(Expression::FunctionCall {
                    function: "_pep_free".to_string(),
                    args: vec![Expression::ThisRef],
                    loc: Loc::NONE,
                })],
            ),
        ];
    }
    crate::struct_body::finish(&mut st).expect("weak reference struct");
    st
}
