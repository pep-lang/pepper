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
/// `if (this === __null) { return; }`
pub(crate) fn null_guard() -> Statement {
    if_block(
        Expression::Binary {
            op: BinaryOp::Identical,
            lhs: Box::new(Expression::ThisRef),
            rhs: Box::new(Expression::PointerLiteral),
            loc: Loc::NONE,
        },
        vec![Statement::Return(ReturnStatement { expr: None, loc: Loc::NONE })],
    )
}

/// One step of a head count of `this`; its value is the new count.
pub(crate) fn count_step(field: CountField, increment: bool, atomic: bool) -> Expression {
    Expression::CountStep { field, increment, atomic }
}

/// Name of the local that holds the count a `count_local` step produced.
const COUNT_LOCAL: &str = "__count";

/// `u32 __count = <count step>;`
fn count_local(field: CountField, increment: bool, atomic: bool) -> Statement {
    Statement::Declaration(Declaration::Variable(var_def(
        COUNT_LOCAL,
        TypeName::new("u32"),
        Some(count_step(field, increment, atomic)),
        false,
    )))
}

fn count_ref() -> Expression {
    Expression::SymbolRef { id: COUNT_LOCAL.to_string(), ty: TypeName::new("u32"), loc: Loc::NONE }
}

/// `<value> == 0`
pub(crate) fn is_zero(value: Expression) -> Expression {
    Expression::Binary {
        op: BinaryOp::Equal,
        lhs: Box::new(value),
        rhs: Box::new(Expression::IntLiteral(0)),
        loc: Loc::NONE,
    }
}

/// Zero value for a field type: null reference for struct/pointer types,
/// 0.0 for floats, 0 for everything else (port of `zero_value` in
/// `StructGen.cpp:35`).
pub(crate) fn zero_for(ty: &TypeName) -> Expression {
    if let Some(default) = crate::enums::default_expression(ty) {
        return default;
    }
    // A tuple or a value struct is a value: its zero holds a zero of each
    // element.
    if ty.is_tuple() || ty.is_simd() || crate::value_structs::is_value(&ty.to_string()) {
        Expression::Default(ty.clone())
    } else if ty.is_pointer() || ty.is_struct() {
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
    // A value struct has no object: no counts, and codegen steps its
    // reference fields' counts itself, as for a tuple.
    if st.is_value() {
        st.acquire.body = None;
        st.release.body = None;
        return;
    }
    // Head field for the refcount. Its default is 0, but `finish` starts it
    // at 1 in every constructor: the constructor's `this` owns the first
    // reference. Guarded: specialized instances clone the base's fields (which already
    // carry the head) and re-run apply_synthesized.
    if !st.field_members.iter().any(|f| f.name == "__refcount") {
        st.field_members.insert(
            0,
            var_def("__refcount", TypeName::new("u32"), Some(Expression::IntLiteral(0)), false),
        );
    }
    // Second head field: weak references (`__weak<T>`, a
    // `std::weak_ptr`), plus one held on behalf of all strong references
    // together, as in a C++ control block. It starts at 1, so dropping a
    // weak reference never frees an object that strong references (the
    // constructor's `this` among them) still hold; the last strong release destroys the
    // object and gives that one up, and whichever count reaches 0 last frees
    // the memory.
    if !st.field_members.iter().any(|f| f.name == "__weakcount") {
        st.field_members.insert(
            1,
            var_def("__weakcount", TypeName::new("u32"), Some(Expression::IntLiteral(1)), false),
        );
    }

    // A `[Shared]` struct (or a function type) steps its counts atomically,
    // so references to it can be copied and dropped on several threads at
    // once; every other struct uses plain increments.
    let atomic = st.atomic_counts();

    // __acquire body: null-check, ++__refcount. Codegen acquires on a
    // struct-reference store whenever the new occupant differs from the old
    // one (including nulls from zero-initialized slots), so the guard
    // mirrors __release's.
    if let Some(body) = &mut st.acquire.body {
        body.items = vec![null_guard(), Statement::Expression(count_step(CountField::Strong, true, atomic))];
    }

    // __release body: null-check, decrement, dtor at zero. The decrement's
    // result is tested rather than re-reading a field another thread may be
    // changing.
    if let Some(body) = &mut st.release.body {
        body.items = vec![
            // NOTE: release gets called blindly on the lhs of any assignment.
            // The lhs can be a null-initialized ref.
            null_guard(),
            count_local(CountField::Strong, false, atomic),
            if_block(
                is_zero(count_ref()),
                vec![
                    // The strong references' weak reference is still held
                    // while the destructor runs, so a weak reference
                    // released inside it (a field pointing back at the
                    // object) cannot free the memory under it.
                    Statement::Expression(Expression::MethodCall {
                        this: Box::new(Expression::ThisRef),
                        method: "__dtor".to_string(),
                        args: vec![],
                        loc: Loc::NONE,
                    }),
                    // Destroyed: give up the strong references' weak
                    // reference. The memory goes once no weak reference
                    // remains; otherwise the last weak release frees it.
                    if_block(
                        is_zero(count_step(CountField::Weak, false, atomic)),
                        vec![call("_pep_free", vec![Expression::ThisRef])],
                    ),
                ],
            ),
        ];
    }
    // A reference enum's cases that carry nothing are immortal objects any
    // thread may reach (`Expression::StaticCase`): leave their counts alone.
    if st.enum_cases.as_ref().is_some_and(|cases| cases.iter().any(|c| c.payload.is_empty())) {
        crate::passes::function_types::skip_static_objects(st);
    }
}

/// Ctor finish, for each constructor: allocation prologue + field inits + user ctor body +
/// `return this`; synthesized methods appended
/// (port of `Struct.cpp:159-192`).
pub fn finish(st: &mut StructDef) -> Result<(), String> {
    let struct_name = st.name.clone();
    // Each constructor (several overload one another) gets the prologue.
    let mut constructors = std::mem::take(&mut st.constructors);
    for ctor in &mut constructors {
        // `this.<field>` constructor parameters become real parameters that
        // assign the field. Collect first so we don't borrow `st` twice.
        let init_params: Vec<(usize, String, TypeName)> = ctor
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
                            "constructor parameter 'this.{}' has no matching field in '{}'",
                            field, struct_name
                        )
                    })?;
                Ok((i, field, ty))
            })
            .collect::<Result<Vec<_>, String>>()?;
        for (i, field, ty) in &init_params {
            ctor.parameters[*i].name = format!("__init_{}", field);
            ctor.parameters[*i].ty = ty.clone();
        }

        // Copy off whatever the user put in the ctor, if anything.
        let user_ctor = ctor
            .body
            .as_ref()
            .map(|b| b.items.clone())
            .unwrap_or_default();

        // Create the allocation for `this`; the `__alloc_size` literal value is
        // filled in at codegen time. The `__` prefix keeps it from shadowing a
        // constructor parameter the user named `size`.
        let mut items: Vec<Statement> = if st.is_value() {
            // A value is built in place: `this` is the storage the
            // constructor returns, starting as the zero value.
            vec![Statement::Declaration(Declaration::Variable(var_def(
                "this",
                st.ty.clone(),
                Some(Expression::Default(st.ty.clone())),
                false,
            )))]
        } else {
            vec![
            Statement::Declaration(Declaration::Variable(var_def(
                "__alloc_size",
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
                        id: "__alloc_size".to_string(),
                        ty: TypeName::auto(),
                        loc: Loc::NONE,
                    }],
                    loc: Loc::NONE,
                }),
                false,
            ))),
            ]
        };

        // Field initializations. A field with an explicit default is assigned it;
        // every other field is zero-initialized (null reference / 0), matching
        // `StructGen.cpp:31-37`. `_pep_malloc` already zeroes the payload, so the
        // stores are redundant today — kept for C++ reference parity and to make
        // the ctor's initialization contract explicit in the model (a future
        // non-zeroing allocator would not silently change semantics).
        for field in &st.field_members {
            let value = match &field.default {
                // Why 1 and not 0: `this` owns the object's first
                // reference for the whole constructor, like the local
                // holding `make_shared`'s result. Starting at 0, a call
                // like `f(this)` would acquire it into `f`'s parameter
                // (0 → 1) and release it at `f`'s exit (1 → 0), destroying
                // the object mid-construction (#617). With `this` owning a
                // reference, that copy only ever goes 1 → 2 → 1. Codegen
                // tracks the constructor's `this` like any other local, so
                // at the end `return this` acquires the caller's reference
                // (1 → 2) and `this`'s scope exit drops its own (2 → 1):
                // the result leaves owning exactly one reference.
                _ if field.name == "__refcount" => Expression::IntLiteral(1),
                Some(d) => d.clone(),
                // A field typed by a bare type parameter (`T _value;`) has no
                // known zero until specialization: `__default<T>` becomes `0`
                // for `Optional<int>` and null for `Optional<Point>`. A null
                // literal here would store a pointer into an `int` slot.
                None if st.ty.sub_types.iter().any(|p| p.name == field.ty.name) && field.ty.sub_types.is_empty() => {
                    Expression::Default(field.ty.clone())
                }
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
        // acquires at the return site (1 → 2) and `this`'s scope exit
        // releases the constructor's own reference (2 → 1), so the ctor
        // result is an owned rvalue carrying one ref — exactly as
        // `std::make_shared` hands back a shared_ptr. A variable init
        // (`var x = T()`) moves that ref into the slot; a pass-by-value
        // param entry acquires on top of it.

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

        ctor.body = Some(Block {
            name: ctor.name.clone(),
            items,
            attributes: vec![],
        });
    }
    st.constructors = constructors;

    // The destructor does not free the object: `__release` does, once no
    // weak reference remains (see apply_synthesized).

    // A value struct has no object to count or destroy.
    if st.is_value() {
        return Ok(());
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
    for (_, step) in STEPS {
        step(module)?;
    }
    Ok(())
}

/// The steps of [`apply`], in order, by name (see `checked::run_steps`).
pub const STEPS: [(&str, fn(&mut Module) -> Result<(), Diagnostic>); 5] = [
    ("struct_body::derive_equatable(module)", derive_equatable),
    ("struct_body::lift_closures(module)", lift_closures),
    ("struct_body::strip_bodies(module)", strip_bodies),
    ("struct_body::resolve_type_aliases(module)", resolve_type_aliases),
    ("struct_body::synthesize(module)", synthesize),
];

/// `[Equatable]` structs get their `==` and `__hash` first, so every later
/// step treats them as declared.
fn derive_equatable(module: &mut Module) -> Result<(), Diagnostic> {
    crate::errors::take(); // each run starts fresh
    crate::equatable::derive(module)
}

/// Closure literals become structs first, so they get bodies below.
fn lift_closures(module: &mut Module) -> Result<(), Diagnostic> {
    // Checked declarations' bodies stay out of the passes.
    crate::checked::stash_bodies(module);
    // Enum names are integer types from here on (closure lifting asks).
    crate::enums::install(&module.enums);
    crate::passes::closures::lift_closures(module);
    crate::errors::take().map_or(Ok(()), Err)
}

/// Names synthesized from a file are numbered by now, so dropping the
/// cached units' bodies cannot renumber anything the others see.
fn strip_bodies(module: &mut Module) -> Result<(), Diagnostic> {
    crate::passes::strip_bodies::strip_bodies(module);
    Ok(())
}

fn resolve_type_aliases(module: &mut Module) -> Result<(), Diagnostic> {
    crate::passes::resolve_type_aliases::resolve_type_aliases(module);
    crate::errors::take().map_or(Ok(()), Err)
}

/// Each struct's synthesized members and constructor bodies.
fn synthesize(module: &mut Module) -> Result<(), Diagnostic> {
    crate::value_structs::install(module);
    for st in module.structs.iter_mut().filter(|st| !module.checked.has_struct(&st.name)) {
        apply_synthesized(st);
        let loc = st.loc;
        finish(st).map_err(|e| Diagnostic::error(e).at(loc))?;
    }
    Ok(())
}
