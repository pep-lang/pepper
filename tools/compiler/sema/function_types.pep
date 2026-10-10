## The structs of function, tuple and weak reference types:
## `pepper_sema::passes::function_types::synthesize_function_types` in
## Pepper, with `tuples::tuple_struct` and `weak_types::weak_struct`. Each
## distinct function type (`__function<R, P...>`) a module uses becomes a
## counted struct holding `__invoke` and `__destroy`; each tuple type a
## struct with a `const` field per element; each `__weak<T>` a view of
## `T`'s object head that steps the weak count.

import [has_bare_attribute, SHARED_ATTRIBUTE] from "builder";
import [DESTROY_FIELD, empty_function, field_def, INVOKE_FIELD] from "closures";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Branch,
    CallPointerExpression,
    CountField,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    Kind,
    MemberRefExpression,
    Module,
    Statement,
    StructDef,
    TypeFlags,
    TypeName,
    UnaryExpression,
    UnaryOp,
    VariableDef,
    WeakOp
] from "model";
import [PassState] from "state";
import [apply_synthesized, count_step, finish, is_zero, null_guard, skip_static_objects] from "synthesize";
import [parse_type_string, WEAK] from "type_name";
import [Rewriter, rewrite_expression] from "walk";

## Adds a struct for every function type, tuple type and weak reference
## type the module uses that has none yet, as
## `function_types::synthesize_function_types` does.
##
## @param module the model, changed in place
## @param state the passes' state
export synthesize_function_types(module: Module, state: PassState) {
    var found = _TypesFound();
    for (var st in module.structs) {
        for (var field in st.field_members) {
            found.add(field.ty);
        }
        for (var method in st.method_members) {
            _function_types(method, found);
        }
        for (var method in st.constructors) {
            _function_types(method, found);
        }
        _function_types(st.destructor, found);
    }
    for (var function in module.functions) {
        _function_types(function, found);
    }
    for (var ext in module.extensions) {
        for (var method in ext.methods) {
            _function_types(method, found);
        }
    }
    for (var global in module.globals) {
        found.add(global.ty);
        if (global.default.is_value()) {
            _expression_types(global.default.value(), found);
        }
    }
    for (var spec in module.struct_specs) {
        found.add(spec);
    }
    var names = HashSet<String>();
    for (var st in module.structs) {
        names.insert(st.name);
    }
    for (var ty in found.types) {
        var name = ty.to_string();
        if (names.contains(name)) {
            continue;
        }
        if (ty.is_tuple()) {
            _push(module, names, tuple_struct(ty, state));
            continue;
        }
        if (ty.is_weak()) {
            # Only a concrete struct target: `__weak<T>` inside a generic
            # base waits for its specializations.
            var target = ty.sub_types[0];
            var spelled = target.to_string();
            bool known = false;
            for (var st in module.structs) {
                if (st.name == spelled) {
                    known = true;
                    _push(module, names, weak_struct(ty, has_bare_attribute(st.attributes, SHARED_ATTRIBUTE), state));
                    break;
                }
            }
            if (!known and _is_trait_type(module, target)) {
                # A weak trait value is the object and its vtable; its
                # object may be `[Shared]`, so it counts atomically.
                _push(module, names, weak_struct(ty, true, state));
            }
            continue;
        }
        var st = _function_struct(ty);
        apply_synthesized(st);
        if (!ty.is_shared_function_type()) {
            skip_static_objects(st);
        }
        finish(state, st);
        _push(module, names, st);
    }
}

_push(module: Module, names: HashSet<String>, st: StructDef) {
    names.insert(st.name);
    module.structs.append(st);
}

_is_trait_type(module: Module, ty: TypeName): bool {
    if (ty.flags != TypeFlags.Scalar or ty.is_pointer()) {
        return false;
    }
    for (var t in module.traits) {
        if (t.name == ty.name) {
            return true;
        }
    }
    return false;
}

## The types gathered, each once, innermost first.
struct _TypesFound {
    var types: Array<TypeName> = Array<TypeName>();
    var seen: HashSet<String> = HashSet<String>();

    ## Records `ty` and every function, weak or tuple type nested in it
    ## (innermost first, so a `(int) => (int) => int` registers its return
    ## type before itself).
    add(ty: TypeName) {
        for (var sub in ty.sub_types) {
            add(sub);
        }
        if ((ty.is_function_type() or ty.is_weak() or ty.is_tuple()) and !ty.contains_auto()) {
            var spelled = ty.to_string();
            if (!seen.contains(spelled)) {
                seen.insert(spelled);
                types.append(ty.copy());
            }
        }
    }
}

_function_types(function: FunctionDef, found: _TypesFound) {
    found.add(function.ty);
    for (var p in function.parameters) {
        found.add(p.ty);
        if (p.default.is_value()) {
            _expression_types(p.default.value(), found);
        }
    }
    if (function.body.is_value()) {
        _block_types(function.body.value(), found);
    }
}

_block_types(block: Block, found: _TypesFound) {
    for (var statement in block.items) {
        match (statement) {
            Expression(e) => {
                _expression_types(e, found);
            }
            Block(inner) => {
                _block_types(inner, found);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    found.add(variable.ty);
                    if (variable.default.is_value()) {
                        _expression_types(variable.default.value(), found);
                    }
                }
            }
            Branch(branch) => {
                _expression_types(branch.condition, found);
                _block_types(branch.if_block, found);
                if (branch.else_block.is_value()) {
                    _block_types(branch.else_block.value(), found);
                }
            }
            While(loop) => {
                _expression_types(loop.condition, found);
                _block_types(loop.block, found);
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    _expression_types(ret.expr.value(), found);
                }
            }
            else => {}
        }
    }
}

_expression_types(e: Expression, found: _TypesFound) {
    rewrite_expression(e, _TypeVisitor(found));
}

## Records the types an expression and its sub-expressions spell.
struct _TypeVisitor {
    var found: _TypesFound;

    construct(found: _TypesFound) {
        this.found = found;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            SymbolRef(node) => {
                found.add(node.ty);
            }
            FunctionRef(node) => {
                found.add(node.ty);
            }
            Cast(node) => {
                found.add(node.ty);
            }
            ArrayIndex(node) => {
                found.add(node.ty);
            }
            Weak(op, ty, _) => {
                found.add(_weak_result(op, ty));
            }
            MakeClosure(node) => {
                found.add(node.ty);
            }
            FunctionCall(node) => {
                if (node.function.contains("<")) {
                    found.add(parse_type_string(node.function));
                }
            }
            else => {}
        }
        return e;
    }
}

extend _TypeVisitor with Rewriter;

## The type a weak reference operation on target `ty` gives.
_weak_result(op: WeakOp, ty: TypeName): TypeName {
    match (op) {
        From => {
            return TypeName.with_args(WEAK, [ty.copy()]);
        }
        Upgrade => {
            return ty.copy();
        }
        Expired => {
            return TypeName.named("bool");
        }
    }
}

_pointer_field(name: String): VariableDef {
    return field_def(name, TypeName.void_pointer(), Optional<Expression>.Empty, Loc.none());
}

## The struct for one function type, before `apply_synthesized` and
## `finish`.
_function_struct(ty: TypeName): StructDef {
    var name = ty.to_string();
    return StructDef(
        name = name,
        ty = ty.copy(),
        field_members = [_pointer_field(INVOKE_FIELD), _pointer_field(DESTROY_FIELD)],
        constructors = [empty_function(name, ty.copy(), name)],
        destructor = _destructor(name),
        acquire = empty_function("__acquire", TypeName.void(), name),
        release = empty_function("__release", TypeName.void(), name),
        loc = Loc.none()
    );
}

_destroy_ref(): Expression {
    return Expression.MemberRef(MemberRefExpression(Expression.ThisRef, DESTROY_FIELD, Loc.none()));
}

## A function type's destructor: a closure's `__destroy` releases its
## captured values (`if (this.__destroy !== null) __destroy(this);`).
_destructor(parent: String): FunctionDef {
    var destructor = empty_function("__dtor", TypeName.void(), parent);
    var condition = Expression.Unary(
        UnaryExpression(
            Expression.Binary(
                BinaryExpression(_destroy_ref(), Expression.PointerLiteral, BinaryOp.Identical, Loc.none())
            ),
            UnaryOp.LogicalNot,
            Loc.none()
        )
    );
    var call = Statement.Expression(
        Expression.CallPointer(CallPointerExpression(_destroy_ref(), [Expression.ThisRef]))
    );
    destructor.body = Optional<Block>.Value(Block(items = [Statement.Branch(Branch(condition, Block("if", [call])))]));
    return destructor;
}

## Returns the struct sema uses for tuple type `ty`: a `const` field per
## element, named by its position, and a constructor that takes them in
## order, as `tuples::tuple_struct` does.
##
## @param ty the tuple type
## @param state the passes' state
## @returns the struct
export tuple_struct(ty: TypeName, state: PassState): StructDef {
    var name = ty.to_string();
    var fields = Array<VariableDef>();
    var parameters = Array<VariableDef>();
    ulong i = 0;
    while (i < ty.sub_types.count) {
        var field = field_def($"{i}", ty.sub_types[i].copy(), Optional<Expression>.Empty, Loc.none());
        field.is_const = true;
        fields.append(field);
        var parameter = field.copy();
        parameter.name = $"this.{i}";
        parameter.kind = Kind.Param;
        parameters.append(parameter);
        i += 1;
    }
    var constructor = empty_function(name, ty.copy(), name);
    constructor.parameters = parameters;
    var st = StructDef(
        name = name,
        ty = ty.copy(),
        field_members = fields,
        constructors = [constructor],
        destructor = empty_function("__dtor", TypeName.void(), name),
        acquire = empty_function("__acquire", TypeName.void(), name),
        release = empty_function("__release", TypeName.void(), name),
        loc = Loc.none()
    );
    apply_synthesized(st);
    finish(state, st);
    # The constructor sets every element from its parameters, so it needs
    # no zero stores (and a tuple element is never null).
    if (st.constructors[0].body.is_value()) {
        var body = st.constructors[0].body.value();
        var kept = Array<Statement>();
        for (var item in body.items) {
            if (!_is_zero_store(item)) {
                kept.append(item);
            }
        }
        body.items = kept;
    }
    return st;
}

## `this.<digits> = <zero>`, a zero store a tuple's constructor drops.
_is_zero_store(item: Statement): bool {
    if (item is Expression(e)) {
        if (e is Binary(node)) {
            if (node.op != BinaryOp.Assign) {
                return false;
            }
            if (node.lhs is MemberRef(member)) {
                if (!(member.lhs is ThisRef) or !_is_digits(member.name)) {
                    return false;
                }
                match (node.rhs) {
                    PointerLiteral, Default(_), FloatLiteral(_) => {
                        return true;
                    }
                    IntLiteral(value) => {
                        return value == 0;
                    }
                    else => {
                        return false;
                    }
                }
            }
        }
    }
    return false;
}

_is_digits(text: String): bool {
    if (text.size == 0) {
        return false;
    }
    ulong i = 0;
    while (i < text.size) {
        var b = text.byte_at(i);
        if (b < 48 or b > 57) {
            return false;
        }
        i += 1;
    }
    return true;
}

## Returns the struct for `ty` (`__weak<T>`), as `weak_types::weak_struct`
## does: its `__acquire` steps the weak count up and its `__release` steps
## it down, freeing the memory at 0.
##
## @param ty the weak reference type
## @param atomic whether the counts step atomically (`T` is `[Shared]`)
## @param state the passes' state
## @returns the struct
export weak_struct(ty: TypeName, atomic: bool, state: PassState): StructDef {
    var name = ty.to_string();
    var st = StructDef(
        name = name,
        ty = ty.copy(),
        constructors = [empty_function(name, ty.copy(), name)],
        destructor = empty_function("__dtor", TypeName.void(), name),
        acquire = empty_function("__acquire", TypeName.void(), name),
        release = empty_function("__release", TypeName.void(), name),
        loc = Loc.none()
    );
    apply_synthesized(st);
    if (st.acquire.body.is_value()) {
        st.acquire.body.value().items = [null_guard(), Statement.Expression(count_step(CountField.Weak, true, atomic))];
    }
    if (st.release.body.is_value()) {
        # The strong references hold one weak reference between them until
        # the object is destroyed, so 0 means destroyed and unreferenced.
        var free = Statement.Expression(
            Expression.FunctionCall(FunctionCallExpression("_pep_free", [Expression.ThisRef], Loc.none()))
        );
        st.release.body.value().items = [
            null_guard(),
            Statement.Branch(Branch(is_zero(count_step(CountField.Weak, false, atomic)), Block("if", [free])))
        ];
    }
    finish(state, st);
    return st;
}
