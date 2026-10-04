## Synthesized struct members: `pepper_sema::struct_body`'s
## `apply_synthesized` and `finish` in Pepper. A counted struct gets its
## head fields (`__refcount`, `__weakcount`) and the bodies of `__acquire`
## and `__release`; every constructor gets the allocation prologue, the
## field initializations and `return this`.

import [Diagnostic] from compiler.diagnostic;
import [has_bare_attribute, SHARED_ATTRIBUTE] from "builder";
import [error_at] from "common";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Branch,
    CastExpression,
    CastKind,
    CountField,
    CountStepExpression,
    Declaration,
    Expression,
    FunctionCallExpression,
    Kind,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    ReturnStatement,
    Statement,
    StructDef,
    SymbolRefExpression,
    TypeFlags,
    TypeName,
    VariableDef
] from "model";
import [PassState] from "state";
import [SIMD] from "type_name";

## The reference count an immortal object (a reference enum's case that
## carries nothing) starts at: steps leave it alone from here up.
export const STATIC_REFCOUNT: long = 1073741824;

## Name of the local that holds the count a `_count_local` step produced.
const _COUNT_LOCAL = "__count";

_member_ref(name: String): Expression {
    return Expression.MemberRef(MemberRefExpression(Expression.ThisRef, name, Loc.none()));
}

_call(function: String, args: Expression[]): Statement {
    return Statement.Expression(Expression.FunctionCall(FunctionCallExpression(function, args, Loc.none())));
}

_var_def(name: String, ty: TypeName, default: Expression?, hidden: bool): VariableDef {
    return VariableDef(
        name = name,
        ty = ty,
        default = default,
        hidden = hidden,
        kind = Kind.Variable,
        loc = Loc.none(),
        type_loc = Loc.none()
    );
}

_if_block(condition: Expression, items: Statement[]): Statement {
    return Statement.Branch(Branch(condition, Block("if", items)));
}

_binary(op: BinaryOp, lhs: Expression, rhs: Expression): Expression {
    return Expression.Binary(BinaryExpression(lhs, rhs, op, Loc.none()));
}

_return_nothing(): Statement {
    return Statement.Return(ReturnStatement(Optional<Expression>.Empty, Loc.none()));
}

## `if (this === __null) { return; }`
export null_guard(): Statement {
    return _if_block(_binary(BinaryOp.Identical, Expression.ThisRef, Expression.PointerLiteral), [_return_nothing()]);
}

## Returns one step of a head count of `this`; its value is the new count.
##
## @param field the count
## @param increment whether it goes up
## @param atomic whether the step is atomic
## @returns the step
export count_step(field: CountField, increment: bool, atomic: bool): Expression {
    return Expression.CountStep(CountStepExpression(field, increment, atomic));
}

## `u32 __count = <count step>;`
_count_local(field: CountField, increment: bool, atomic: bool): Statement {
    return Statement.Declaration(
        Declaration.Variable(
            _var_def(
                _COUNT_LOCAL,
                TypeName.named("u32"),
                Optional<Expression>.Value(count_step(field, increment, atomic)),
                false
            )
        )
    );
}

_count_ref(): Expression {
    return Expression.SymbolRef(SymbolRefExpression(_COUNT_LOCAL, TypeName.named("u32"), Loc.none()));
}

## `<value> == 0`
export is_zero(value: Expression): Expression {
    return _binary(BinaryOp.Equal, value, Expression.IntLiteral(0));
}

## Returns the zero value of a field of type `ty`: an enum's default, the
## default of a value, null for a reference or pointer, 0.0 for a float and
## 0 for anything else.
##
## @param state the passes' state, which knows the enums and values
## @param ty the type
## @returns the value
export zero_for(state: PassState, ty: TypeName): Expression {
    var spelled = ty.to_string();
    var default = state.enum_default(spelled);
    if (default.is_value()) {
        return Expression.Cast(
            CastExpression(Expression.IntLiteral(default.value()), ty.copy(), Loc.none(), CastKind.Synthesized)
        );
    }
    # A tuple or a value struct is a value: its zero holds a zero of each
    # element.
    bool scalar = ty.flags == TypeFlags.Scalar;
    if (ty.is_tuple() or ty.name == SIMD or state.is_value_struct(spelled)) {
        return Expression.Default(ty.copy());
    }
    bool pointer = scalar and ty.name.ends_with("*");
    bool is_struct = scalar and !state.is_integral(ty.name) and ty.name != SIMD;
    if (pointer or is_struct) {
        return Expression.PointerLiteral;
    }
    match (ty.name) {
        "f32", "float", "f64", "double" => {
            return Expression.FloatLiteral(0.0);
        }
        else => {
            return Expression.IntLiteral(0);
        }
    }
}

## A counted struct's synthesized members: the head fields and the bodies
## of `__acquire` and `__release`. A value struct has none.
##
## @param st the struct, changed in place
export apply_synthesized(st: StructDef) {
    if (st.is_value()) {
        st.acquire.body = Optional<Block>.Empty;
        st.release.body = Optional<Block>.Empty;
        return;
    }
    if (!_has_field(st, "__refcount")) {
        st.field_members.insert(
            0,
            _var_def("__refcount", TypeName.named("u32"), Optional<Expression>.Value(Expression.IntLiteral(0)), false)
        );
    }
    if (!_has_field(st, "__weakcount")) {
        st.field_members.insert(
            1,
            _var_def("__weakcount", TypeName.named("u32"), Optional<Expression>.Value(Expression.IntLiteral(1)), false)
        );
    }
    # A `[Shared]` struct (or a shared function type) steps its counts
    # atomically.
    bool atomic = has_bare_attribute(st.attributes, SHARED_ATTRIBUTE) or st.ty.is_shared_function_type();
    if (st.acquire.body.is_value()) {
        st.acquire.body.value().items = [
            null_guard(), Statement.Expression(count_step(CountField.Strong, true, atomic))
        ];
    }
    if (st.release.body.is_value()) {
        st.release.body.value().items = [
            null_guard(),
            _count_local(CountField.Strong, false, atomic),
            _if_block(
                is_zero(_count_ref()),
                [
                    Statement.Expression(
                        Expression.MethodCall(
                            MethodCallExpression(Expression.ThisRef, "__dtor", Array<Expression>(), Loc.none())
                        )
                    ),
                    _if_block(
                        is_zero(count_step(CountField.Weak, false, atomic)), [_call("_pep_free", [Expression.ThisRef])]
                    )
                ]
            )
        ];
    }
    # A reference enum's cases that carry nothing are immortal objects any
    # thread may reach: their counts are left alone.
    if (st.enum_cases.is_value()) {
        bool bare = false;
        for (var c in st.enum_cases.value()) {
            if (c.payload.count == 0) {
                bare = true;
            }
        }
        if (bare) {
            skip_static_objects(st);
        }
    }
}

## Makes `__acquire` and `__release` return at once for an immortal
## object: one whose `__refcount` is `STATIC_REFCOUNT` or more.
##
## @param st the struct, changed in place
export skip_static_objects(st: StructDef) {
    for (var method in [st.acquire, st.release]) {
        if (!method.body.is_value()) {
            continue;
        }
        var guard = _if_block(
            _binary(BinaryOp.GreaterEqual, _member_ref("__refcount"), Expression.IntLiteral(STATIC_REFCOUNT)),
            [_return_nothing()]
        );
        var items = method.body.value().items;
        items.insert(items.count < 1 ? items.count : 1, guard);
    }
}

_has_field(st: StructDef, name: String): bool {
    for (var f in st.field_members) {
        if (f.name == name) {
            return true;
        }
    }
    return false;
}

## Completes each constructor of `st` (the allocation prologue, the field
## initializations, the user's body and `return this`) and, for a counted
## struct, appends `__release`, `__acquire` and `__dtor` to its methods.
##
## @param state the passes' state
## @param st the struct, changed in place
## @returns the error, if a `this.<field>` parameter names no field
export finish(state: PassState, st: StructDef): String? {
    for (var ctor in st.constructors) {
        # `this.<field>` parameters become real parameters that assign the
        # field.
        var init_params = Array<(ulong, String, TypeName)>();
        ulong i = 0;
        while (i < ctor.parameters.count) {
            var p = ctor.parameters[i];
            if (p.name.starts_with("this.")) {
                var field = p.name.substr_bytes(5, p.name.size - 5);
                var ty = Optional<TypeName>.Empty;
                for (var f in st.field_members) {
                    if (f.name == field) {
                        ty = Optional<TypeName>.Value(f.ty);
                        break;
                    }
                }
                if (!ty.is_value()) {
                    return Optional<String>.Value(
                        $"constructor parameter 'this.{field}' has no matching field in '{st.name}'"
                    );
                }
                init_params.append((i, field, ty.value()));
            }
            i += 1;
        }
        for (var (index, field, ty) in init_params) {
            ctor.parameters[index].name = $"__init_{field}";
            ctor.parameters[index].ty = ty.copy();
        }
        var user_ctor = Array<Statement>();
        if (ctor.body.is_value()) {
            for (var s in ctor.body.value().items) {
                user_ctor.append(s.copy());
            }
        }
        var items = Array<Statement>();
        if (st.is_value()) {
            # A value is built in place: `this` is the storage the
            # constructor returns, starting as the zero value.
            items.append(
                Statement.Declaration(
                    Declaration.Variable(
                        _var_def(
                            "this", st.ty.copy(), Optional<Expression>.Value(Expression.Default(st.ty.copy())), false
                        )
                    )
                )
            );
        } else {
            items.append(
                Statement.Declaration(
                    Declaration.Variable(
                        _var_def("__alloc_size", TypeName.named("u64"), Optional<Expression>.Empty, true)
                    )
                )
            );
            var size = Expression.SymbolRef(SymbolRefExpression("__alloc_size", TypeName.auto(), Loc.none()));
            items.append(
                Statement.Declaration(
                    Declaration.Variable(
                        _var_def(
                            "this",
                            st.ty.copy(),
                            Optional<Expression>.Value(
                                Expression.FunctionCall(FunctionCallExpression("_pep_malloc", [size], Loc.none()))
                            ),
                            false
                        )
                    )
                )
            );
        }
        # Field initializations: a field's default, else its zero.
        for (var field in st.field_members) {
            Expression value = Expression.PointerLiteral;
            if (field.name == "__refcount") {
                # `this` owns the object's first reference for the whole
                # constructor; its scope exit releases it after `return
                # this` acquires the caller's.
                value = Expression.IntLiteral(1);
            } else if (field.default.is_value()) {
                value = field.default.value().copy();
            } else if (field.ty.sub_types.count == 0 and _names_parameter(st.ty, field.ty.name)) {
                # A field typed by a bare type parameter has no known zero
                # until specialization.
                value = Expression.Default(field.ty.copy());
            } else {
                value = zero_for(state, field.ty);
            }
            items.append(Statement.Expression(_binary(BinaryOp.Assign, _member_ref(field.name), value)));
        }
        # The `this.<field>` parameters, assigned to their fields.
        for (var (_, field, ty) in init_params) {
            var parameter = Expression.SymbolRef(SymbolRefExpression($"__init_{field}", ty.copy(), Loc.none()));
            items.append(Statement.Expression(_binary(BinaryOp.Assign, _member_ref(field), parameter)));
        }
        items.append_all(user_ctor);
        var this_ref = Expression.SymbolRef(SymbolRefExpression("this", st.ty.copy(), Loc.none()));
        items.append(Statement.Return(ReturnStatement(Optional<Expression>.Value(this_ref), Loc.none())));
        ctor.body = Optional<Block>.Value(Block(ctor.name, items));
    }
    # A value struct has no object to count or destroy.
    if (st.is_value()) {
        return Optional<String>.Empty;
    }
    st.method_members.append(st.release.copy());
    st.method_members.append(st.acquire.copy());
    st.method_members.append(st.destructor.copy());
    return Optional<String>.Empty;
}

_names_parameter(ty: TypeName, name: String): bool {
    for (var p in ty.sub_types) {
        if (p.name == name) {
            return true;
        }
    }
    return false;
}

## Each struct's synthesized members and constructor bodies, as
## `struct_body::synthesize` does; a checked struct's are already there.
##
## @param module the model, changed in place
## @param state the passes' state
## @returns the first error
export synthesize(module: Module, state: PassState): Diagnostic? {
    state.value_structs.clear();
    for (var st in module.structs) {
        if (st.is_value()) {
            state.value_structs.insert(st.ty.name);
        }
    }
    for (var st in module.structs) {
        if (module.checked.structs.contains(st.name)) {
            continue;
        }
        apply_synthesized(st);
        var error = finish(state, st);
        if (error.is_value()) {
            return Optional<Diagnostic>.Value(error_at(error.value(), st.loc));
        }
    }
    return Optional<Diagnostic>.Empty;
}
