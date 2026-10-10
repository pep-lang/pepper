## Closure literals: lifting, from `pepper_sema::passes::closures`. Each
## literal becomes a synthesized struct (`__closure_N@<namespace>`) whose
## `__call` runs its body and whose fields hold what it captures, and the
## literal becomes the `MakeClosure` that constructs it. A captured local
## may never be assigned.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [is_deprecation, mangle] from compiler.link;
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [
    BinaryOp,
    Block,
    ClosureLiteral,
    Declaration,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    GenericParam,
    Kind,
    MakeClosureExpression,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    Statement,
    StaticItem,
    StructDef,
    SymbolRefExpression,
    TypeName,
    UnaryOp,
    VariableDef
] from "model";
import [set_name, without_type_arguments] from "names";
import [PassState] from "state";
import [FUNCTION] from "type_name";
import [Rewriter, rewrite_children] from "walk";

## The method holding a closure's body.
export const CALL_METHOD = "__call";
## The field holding the captured `this` of the enclosing method.
export const THIS_FIELD = "__this";
## Name prefix of the synthesized closure structs.
export const CLOSURE_PREFIX = "__closure_";
## The type parameter a closure in a trait's default method has for the
## struct the method is copied into.
export const TRAIT_SELF = "__This";
## The function-type head field that points at `__call`.
export const INVOKE_FIELD = "__invoke";
## The function-type head field that points at the destructor.
export const DESTROY_FIELD = "__destroy";

## Returns whether `name` (a struct name or type string) is a synthesized
## closure.
##
## @param name the name
## @returns true for a closure struct
export is_closure_struct(name: String): bool {
    return name.starts_with(CLOSURE_PREFIX);
}

## What the code around a literal provides: its generic parameters and, in
## a method, the struct `this` refers to and that struct's member names.
struct _ClosureContext {
    var generics: GenericParam[] = Array<GenericParam>();
    var this_ty: TypeName? = Optional<TypeName>.Empty;
    var fields: HashSet<String> = HashSet<String>();
    var methods: HashSet<String> = HashSet<String>();
    # The static methods among `methods`, extensions' included.
    var statics: HashSet<String> = HashSet<String>();
    # The function being lifted from is static: it has no `this`.
    var in_static: bool = false;

    construct() {}

    with_function(function: FunctionDef): _ClosureContext {
        var out = _ClosureContext();
        out.generics.append_all(generics);
        out.this_ty = this_ty;
        out.fields = fields;
        out.methods = methods;
        out.statics = statics;
        out.in_static = function.is_static;
        # An override's type arguments (`describe<Point>`) are types, not
        # parameters the lifted closure would take.
        for (var p in function.generic_params) {
            if (!p.is_argument) {
                out.generics.append(p);
            }
        }
        return out;
    }

    outside_function(): _ClosureContext {
        var out = _ClosureContext();
        out.generics = generics;
        out.fields = fields;
        out.methods = methods;
        out.statics = statics;
        return out;
    }
}

## The names of `st`'s static methods, its extensions' included.
_static_methods(st: StructDef, module: Module): HashSet<String> {
    var out = HashSet<String>();
    for (var m in st.method_members) {
        if (m.is_static) {
            out.insert(m.name);
        }
    }
    for (var m in st.generic_methods) {
        if (m.is_static) {
            out.insert(m.name);
        }
    }
    for (var e in module.extensions) {
        if (e.target.name == st.ty.name) {
            for (var m in e.methods) {
                if (m.is_static) {
                    out.insert(m.name);
                }
            }
        }
    }
    return out;
}

## A local in scope.
struct _CapturedLocal {
    var name: String;
    var ty: TypeName;
    # How many closure literals enclose the declaration (0: the function).
    var level: ulong;
    var loc: Loc;

    construct(name: String, ty: TypeName, level: ulong, loc: Loc) {
        this.name = name;
        this.ty = ty;
        this.level = level;
        this.loc = loc;
    }
}

## A closure literal being lifted.
struct _ClosureFrame {
    var level: ulong;
    # Captured locals, each with where this closure first uses it.
    var captures: Array<(ulong, Loc)> = Array<(ulong, Loc)>();
    var uses_this: bool = false;
    # Where this closure first uses `this` or a member, when known.
    var this_use: Loc = Loc.none();
    # Where the closure literal is.
    var literal: Loc;

    construct(level: ulong, literal: Loc) {
        this.level = level;
        this.literal = literal;
    }
}

struct _ClosureLifter {
    var state: PassState;
    var ctx: _ClosureContext;
    var vars: _CapturedLocal[] = Array<_CapturedLocal>();
    var scopes: Array<Array<ulong>> = [Array<ulong>()];
    var level: ulong = 0;
    var frames: _ClosureFrame[] = Array<_ClosureFrame>();
    # Assignments to locals: the variable, and where its name is.
    var assignments: Array<(ulong, Loc)> = Array<(ulong, Loc)>();
    # Captured locals and where a closure first uses each.
    var captured: HashMap<ulong, Loc> = HashMap<ulong, Loc>();
    var lifted: StructDef[] = Array<StructDef>();
    # The closure levels at which enclosing `static` blocks begin: a closure
    # deeper than one is lifted out of that block's expansion.
    var static_levels: Array<ulong> = Array<ulong>();

    construct(state: PassState, ctx: _ClosureContext) {
        this.state = state;
        this.ctx = ctx;
    }

    declare(name: String, ty: TypeName, loc: Loc) {
        vars.append(_CapturedLocal(name, ty, level, loc));
        scopes.last().append(vars.count - 1);
    }

    resolve(name: String): ulong? {
        ulong s = scopes.count;
        while (s > 0) {
            s -= 1;
            var scope = scopes[s];
            ulong i = scope.count;
            while (i > 0) {
                i -= 1;
                if (vars[scope[i]].name == name) {
                    return Optional<ulong>.Value(scope[i]);
                }
            }
        }
        return Optional<ulong>.Empty;
    }

    # A use of local `id`: every closure between it and its declaration
    # captures it.
    use_var(id: ulong, loc: Loc) {
        var declared = vars[id].level;
        bool any = false;
        for (var frame in frames) {
            if (frame.level > declared) {
                any = true;
                bool known = false;
                for (var (c, _) in frame.captures) {
                    if (c == id) {
                        known = true;
                        break;
                    }
                }
                if (!known) {
                    frame.captures.append((id, loc));
                }
            }
        }
        if (any and !captured.contains(id)) {
            captured[id] = loc;
        }
    }

    # A use of `this` inside a closure: every enclosing closure captures it.
    use_this(loc: Loc) {
        if (ctx.in_static) {
            var ty = ctx.this_ty.is_value() ? ctx.this_ty.value().display() : "";
            # `this` itself carries no location: point at the closure.
            var at = loc;
            if (at.same(Loc.none()) and frames.count > 0) {
                at = frames.last().literal;
            }
            state.report(
                error_at(
                    $"a closure in a static method cannot use 'this' or an instance member of '{ty}': a static method has none",
                    at
                )
            );
            return;
        }
        for (var frame in frames) {
            frame.uses_this = true;
            if (frame.this_use.is_none()) {
                frame.this_use = loc;
            }
        }
    }

    # The enclosing struct as the receiver of a static method: `C<T>.m()`
    # names a generic one as a constructor-style receiver.
    static_receiver(loc: Loc): Expression {
        var ty = ctx.this_ty.is_value() ? ctx.this_ty.value() : TypeName.auto();
        if (ty.sub_types.count == 0) {
            return Expression.SymbolRef(SymbolRefExpression(ty.to_string(), TypeName.auto(), loc));
        }
        return Expression.FunctionCall(FunctionCallExpression(ty.to_string(), Array<Expression>(), loc));
    }

    walk_block(block: Block) {
        scopes.append(Array<ulong>());
        ulong i = 0;
        while (i < block.items.count) {
            block.items[i] = walk_statement(block.items[i]);
            i += 1;
        }
        scopes.pop();
    }

    walk_statement(statement: Statement): Statement {
        match (statement) {
            Expression(value) => {
                return Statement.Expression(walk_expression(value));
            }
            Block(block) => {
                walk_block(block);
            }
            Declaration(declaration) => {
                match (declaration) {
                    Variable(variable) => {
                        if (variable.default.is_value()) {
                            variable.default = Optional<Expression>.Value(walk_expression(variable.default.value()));
                        }
                        declare(variable.name, variable.ty, variable.loc);
                    }
                    else => {}
                }
            }
            Branch(branch) => {
                branch.condition = walk_expression(branch.condition);
                walk_block(branch.if_block);
                if (branch.else_block.is_value()) {
                    walk_block(branch.else_block.value());
                }
            }
            While(loop) => {
                loop.condition = walk_expression(loop.condition);
                walk_block(loop.block);
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    ret.expr = Optional<Expression>.Value(walk_expression(ret.expr.value()));
                }
            }
            Static(block) => {
                static_levels.append(level);
                walk_static_items(block.items);
                static_levels.pop();
            }
            else => {}
        }
        return statement;
    }

    # The statements a `static` block emits: a closure literal in one is
    # lifted like any other, before the block is expanded.
    walk_static_items(items: Array<StaticItem>) {
        ulong i = 0;
        while (i < items.count) {
            match (items[i]) {
                For(node) => {
                    _walk_scoped(node.body);
                }
                While(node) => {
                    _walk_scoped(node.body);
                }
                Block(value) => {
                    _walk_scoped(value);
                }
                If(node) => {
                    _walk_scoped(node.then_items);
                    _walk_scoped(node.else_items);
                }
                EmitIf(node) => {
                    node.condition = walk_expression(node.condition);
                    _walk_scoped(node.then_items);
                    _walk_scoped(node.else_items);
                }
                Emit(statement, span) => {
                    items[i] = StaticItem.Emit(walk_statement(statement), span);
                }
                else => {}
            }
            i += 1;
        }
    }

    _walk_scoped(items: Array<StaticItem>) {
        scopes.append(Array<ulong>());
        walk_static_items(items);
        scopes.pop();
    }

    # A compile-time value used inside a closure that a `static` block
    # emits: the lifted closure's body is outside the block, where the value
    # no longer exists.
    static_value_in_closure(loc: Loc): bool {
        if (static_levels.count == 0 or level <= static_levels.last()) {
            return false;
        }
        state.report(
            error_at(
                "a closure cannot use a compile-time value of its static block; assign the value to a local outside the closure and use the local",
                loc
            )
        );
        return true;
    }

    # The local an assignment target names, and where.
    assigned_local(target: Expression): (ulong, Loc)? {
        match (target) {
            SymbolRef(node) => {
                var v = resolve(node.id);
                if (v.is_value()) {
                    return Optional<(ulong, Loc)>.Value((v.value(), node.loc));
                }
            }
            else => {}
        }
        return Optional<(ulong, Loc)>.Empty;
    }

    # Walks `e` and what it holds, and returns what replaces it.
    rewrite(e: Expression): Expression {
        return walk_expression(e);
    }

    walk_expression(e: Expression): Expression {
        bool inside = level > 0;
        var expr = e;
        match (e) {
            ClosureLiteral(literal) => {
                return lift(literal);
            }
            StaticValue(value) => {
                if (static_value_in_closure(value.loc)) {
                    return expr;
                }
            }
            StaticMember(value) => {
                if (static_value_in_closure(value.loc)) {
                    return expr;
                }
            }
            SymbolRef(node) => {
                var v = resolve(node.id);
                if (v.is_value()) {
                    use_var(v.value(), node.loc);
                } else if (inside and ctx.this_ty.is_value() and ctx.fields.contains(node.id)) {
                    # A bare field of the enclosing struct: `__this.field`.
                    use_this(node.loc);
                    return Expression.MemberRef(MemberRefExpression(_this_ref(node.loc), node.id, node.loc));
                } else if (inside and ctx.this_ty.is_value() and ctx.methods.contains(node.id)) {
                    # A bare method of the enclosing struct as a value: `S.m`
                    # for a static one, else `__this.m`.
                    Expression receiver = Expression.ThisRef;
                    if (ctx.statics.contains(node.id)) {
                        receiver = static_receiver(node.loc);
                    } else {
                        use_this(node.loc);
                        receiver = _this_ref(node.loc);
                    }
                    return Expression.MemberRef(MemberRefExpression(receiver, node.id, node.loc));
                }
                return e;
            }
            ThisRef => {
                if (inside) {
                    use_this(Loc.none());
                    return _this_ref(Loc.none());
                }
                return e;
            }
            FunctionCall(node) => {
                var loc = node.loc;
                # A call with explicit type arguments (`make<int>(n)`)
                # names its method by the name before them.
                var name = without_type_arguments(node.function);
                if (_is_converted_literal(node)) {
                    # A converted string literal constructs `String`,
                    # whatever the enclosing struct names `String`.
                } else if (resolve(node.function).is_value()) {
                    # A call through a local of function type.
                    use_var(resolve(node.function).value(), loc);
                } else if (inside
                    and ctx.this_ty.is_value()
                    and ctx.statics.contains(name)
                    and !ctx.fields.contains(name)) {
                    # A bare static method of the enclosing struct:
                    # `S.m(...)`, which needs no `this`.
                    expr = Expression.MethodCall(
                        MethodCallExpression(static_receiver(loc), node.function, node.args, loc)
                    );
                } else if (inside
                    and ctx.this_ty.is_value()
                    and (ctx.methods.contains(name) or ctx.fields.contains(node.function))) {
                    # A bare method of the enclosing struct (or a call
                    # through one of its fields): `__this.m(...)`.
                    use_this(loc);
                    expr = Expression.MethodCall(MethodCallExpression(_this_ref(loc), node.function, node.args, loc));
                }
            }
            Binary(node) => {
                if (_is_assignment(node.op)) {
                    var assigned = assigned_local(node.lhs);
                    if (assigned.is_value()) {
                        assignments.append(assigned.value());
                    }
                }
            }
            Unary(node) => {
                if (_is_step(node.op)) {
                    var assigned = assigned_local(node.operand);
                    if (assigned.is_value()) {
                        assignments.append(assigned.value());
                    }
                }
            }
            else => {}
        }
        var out = rewrite_children(expr, this);
        match (out) {
            Binary(node) => {
                match (node.op) {
                    Assign => {
                        check_this_cycle(node.lhs, node.rhs);
                    }
                    else => {}
                }
            }
            else => {}
        }
        return out;
    }

    # `this.field = <closure capturing this>` in a method: the object would
    # hold the closure and the closure the object, a cycle reference
    # counting never frees.
    check_this_cycle(lhs: Expression, rhs: Expression) {
        if (level > 0 or !ctx.this_ty.is_value()) {
            return;
        }
        var field = "";
        var loc = Loc.none();
        bool found = false;
        match (lhs) {
            MemberRef(node) => {
                if (node.lhs is ThisRef) {
                    field = node.name;
                    loc = node.loc;
                    found = true;
                }
            }
            SymbolRef(node) => {
                if (!resolve(node.id).is_value() and ctx.fields.contains(node.id)) {
                    field = node.id;
                    loc = node.loc;
                    found = true;
                }
            }
            else => {}
        }
        if (!found) {
            return;
        }
        match (rhs) {
            MakeClosure(node) => {
                match (node.value) {
                    FunctionCall(call) => {
                        for (var arg in call.args) {
                            if (arg is ThisRef) {
                                state.report(
                                    error_at(
                                        $"storing a closure that captures 'this' in field '{field}' of 'this' creates a reference cycle that is never freed",
                                        loc
                                    ).with_note(
                                        "the closure captures 'this' here; capture a 'Weak' reference to it instead",
                                        Optional<Location>.Value(location_of(node.loc))
                                    )
                                );
                                return;
                            }
                        }
                    }
                    else => {}
                }
            }
            else => {}
        }
    }

    # Returns the creation expression replacing the closure literal,
    # and records the struct it becomes.
    lift(literal: ClosureLiteral): Expression {
        level += 1;
        frames.append(_ClosureFrame(level, literal.loc));
        scopes.append(Array<ulong>());
        for (var param in literal.parameters) {
            declare(param.name, param.ty, param.loc);
        }
        walk_block(literal.body);
        scopes.pop();
        var frame = frames.pop();
        level -= 1;

        var loc = literal.loc;
        var (base, ty) = closure_name(state, ctx.generics, loc);
        # Captured values, then `this`. Each capture field is located at the
        # closure's first use of the value, and its `type_loc` is where the
        # captured local is declared.
        var captures = Array<VariableDef>();
        var args = Array<Expression>();
        for (var (id, first_use) in frame.captures) {
            var v = vars[id];
            var used = first_use.is_none() ? loc : first_use;
            var captured_field = field_def(v.name, v.ty.copy(), Optional<Expression>.Empty, used);
            captured_field.type_loc = v.loc;
            captures.append(captured_field);
            args.append(Expression.SymbolRef(SymbolRefExpression(v.name, TypeName.auto(), loc)));
        }
        if (frame.uses_this and ctx.this_ty.is_value()) {
            var used = frame.this_use.is_none() ? loc : frame.this_use;
            captures.append(field_def(THIS_FIELD, ctx.this_ty.value().copy(), Optional<Expression>.Empty, used));
            args.append(level == 0 ? Expression.ThisRef : _this_ref(loc));
        }
        var signature_args = [literal.ty.copy()];
        for (var p in literal.parameters) {
            signature_args.append(p.ty.copy());
        }
        var signature = TypeName.with_args(FUNCTION, signature_args);
        lifted.append(
            closure_struct(base, ty, ctx.generics, captures, literal.parameters, literal.ty, literal.body, loc)
        );
        return Expression.MakeClosure(
            MakeClosureExpression(
                Expression.FunctionCall(FunctionCallExpression(ty.to_string(), args, loc)),
                ty.to_string(),
                signature,
                loc
            )
        );
    }

    # A captured local that is assigned anywhere is an error.
    check_assignments() {
        for (var (id, loc) in assignments) {
            var first = captured.try_get(id);
            if (first.is_value()) {
                state.report(
                    error_at(
                        $"cannot assign to '{vars[id].name}' because a closure captures it",
                        loc
                    ).with_note(
                        "captured here; a closure keeps a copy, so the variable must not change",
                        Optional<Location>.Value(location_of(first.value()))
                    )
                );
                return;
            }
        }
    }
}

extend _ClosureLifter with Rewriter;

_this_ref(loc: Loc): Expression {
    return Expression.SymbolRef(SymbolRefExpression(THIS_FIELD, TypeName.auto(), loc));
}

## Whether a call constructs `String` from a raw literal at its own
## location: a string literal `convert_string_literals` converted.
_is_converted_literal(call: FunctionCallExpression): bool {
    if (call.function != "String" or call.args.count == 0) {
        return false;
    }
    match (call.args[0]) {
        StringLiteral(literal) => {
            return literal.is_raw and literal.loc.same(call.loc);
        }
        else => {}
    }
    return false;
}

_is_assignment(op: BinaryOp): bool {
    match (op) {
        Assign, AddAssign, SubAssign, MulAssign, DivAssign, ModAssign, LShiftAssign, RShiftAssign, BitAndAssign, BitOrAssign, BitXorAssign => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_step(op: UnaryOp): bool {
    match (op) {
        PreInc, PostInc, PreDec, PostDec => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Returns a fresh closure struct name for a literal at `loc`, and its type
## over `generics`. A closure in a file is `__closure_N@<namespace>`,
## numbered in that file alone, so its name does not depend on the rest of
## the program.
##
## @param state the passes' state, which numbers the closures
## @param generics the generic parameters of the enclosing code
## @param loc where the literal is
## @returns the struct's name and type
export closure_name(state: PassState, generics: GenericParam[], loc: Loc): (String, TypeName) {
    bool in_file = !loc.is_none() and (loc.file as ulong) < state.namespaces.count;
    long key = in_file ? loc.file as long : -1;
    var next = state.closure_counts.try_get(key);
    ulong n = next.is_value() ? next.value() : 0;
    state.closure_counts[key] = n + 1;
    var base = $"{CLOSURE_PREFIX}{n}";
    if (in_file) {
        base = mangle(base, state.namespaces[loc.file as ulong]);
    }
    if (generics.count == 0) {
        return (base, TypeName.named(base));
    }
    var args = Array<TypeName>();
    for (var g in generics) {
        args.append(TypeName.named(g.name));
    }
    return (base, TypeName.with_args(base, args));
}

## Returns a function with an empty body, as the struct's synthesized
## members start.
##
## @param name the function's name
## @param ty its return type
## @param parent the struct it belongs to
## @returns the function
export empty_function(name: String, ty: TypeName, parent: String): FunctionDef {
    return FunctionDef(
        name = name,
        ty = ty,
        body = Optional<Block>.Value(Block()),
        parent = Optional<String>.Value(parent),
        loc = Loc.none(),
        owner = Loc.none()
    );
}

## Returns a field of a synthesized struct.
##
## @param name the field's name
## @param ty its type
## @param default its default value, if any
## @param loc where it points
## @returns the field
export field_def(name: String, ty: TypeName, default: Expression?, loc: Loc): VariableDef {
    return VariableDef(name = name, ty = ty, default = default, kind = Kind.Field, loc = loc, type_loc = Loc.none());
}

## Returns the struct a closure becomes: the function-type head, one field
## per captured value (initialized by the constructor in order), and
## `__call` running `body`.
##
## @param base the struct's name
## @param ty its type
## @param generics its generic parameters
## @param captures the captured values' fields
## @param parameters `__call`'s parameters
## @param ret `__call`'s return type
## @param body `__call`'s body
## @param loc where the closure is
## @returns the struct
export closure_struct(
    base: String,
    ty: TypeName,
    generics: GenericParam[],
    captures: VariableDef[],
    parameters: VariableDef[],
    ret: TypeName,
    body: Block,
    loc: Loc
): StructDef {
    var fields = [
        field_def(
            INVOKE_FIELD,
            TypeName.void_pointer(),
            Optional<Expression>.Value(Expression.MethodAddress(CALL_METHOD)),
            loc
        ),
        field_def(
            DESTROY_FIELD, TypeName.void_pointer(), Optional<Expression>.Value(Expression.MethodAddress("__dtor")), loc
        )
    ];
    fields.append_all(captures);
    var ctor_params = Array<VariableDef>();
    ulong i = 2;
    while (i < fields.count) {
        var param = fields[i].copy();
        param.name = $"this.{fields[i].name}";
        param.kind = Kind.Param;
        param.default = Optional<Expression>.Empty;
        ctor_params.append(param);
        i += 1;
    }
    var constructor = empty_function(ty.to_string(), ty.copy(), base);
    constructor.parameters = ctor_params;
    constructor.loc = loc;
    var call = FunctionDef(
        name = CALL_METHOD,
        ty = ret,
        parameters = parameters,
        body = Optional<Block>.Value(body),
        parent = Optional<String>.Value(base),
        loc = loc,
        owner = Loc.none()
    );
    var generic_copies = Array<GenericParam>();
    for (var g in generics) {
        generic_copies.append(g.copy());
    }
    return StructDef(
        name = base,
        ty = ty.copy(),
        generic_params = generic_copies,
        field_members = fields,
        method_members = [call],
        constructors = [constructor],
        destructor = empty_function("__dtor", TypeName.void(), base),
        acquire = empty_function("__acquire", TypeName.void(), base),
        release = empty_function("__release", TypeName.void(), base),
        loc = loc
    );
}

## Lifts the literals in `function`, whose parameters are locals.
_lift_function(state: PassState, function: FunctionDef, ctx: _ClosureContext, lifted: StructDef[]) {
    var lifter = _ClosureLifter(state, ctx.with_function(function));
    for (var param in function.parameters) {
        if (param.default.is_value()) {
            param.default = Optional<Expression>.Value(lifter.walk_expression(param.default.value()));
        }
    }
    for (var param in function.parameters) {
        if (!param.name.starts_with("this.")) {
            lifter.declare(param.name, param.ty, param.loc);
        }
    }
    if (function.body.is_value()) {
        lifter.walk_block(function.body.value());
    }
    lifter.check_assignments();
    lifted.append_all(lifter.lifted);
}

## Lifts a literal outside any function (a global or field default).
_lift_default(state: PassState, variable: VariableDef, ctx: _ClosureContext, lifted: StructDef[]) {
    var lifter = _ClosureLifter(state, ctx.outside_function());
    variable.default = Optional<Expression>.Value(lifter.walk_expression(variable.default.value()));
    lifted.append_all(lifter.lifted);
}

## Turns every closure literal in `module` into a synthesized struct and a
## `MakeClosure`, as `lift_closures` does; errors go to `state`.
##
## @param module the model, changed in place
## @param state the passes' state
export lift_closures(module: Module, state: PassState) {
    state.namespaces = module.namespaces;
    var lifted = Array<StructDef>();
    # Every name a type can have: an `extend Box<T>` parameter is one that
    # names none of them.
    var types = HashSet<String>();
    for (var s in module.structs) {
        types.insert(s.ty.name);
    }
    for (var a in module.type_aliases) {
        types.insert(a.name);
    }
    for (var t in module.traits) {
        types.insert(t.name);
    }
    var struct_contexts = Array<_ClosureContext>();
    for (var st in module.structs) {
        var ctx = _ClosureContext();
        ctx.generics = st.generic_params;
        ctx.this_ty = Optional<TypeName>.Value(st.ty);
        for (var f in st.field_members) {
            ctx.fields.insert(f.name);
        }
        for (var m in st.method_members) {
            ctx.methods.insert(m.name);
        }
        for (var m in st.generic_methods) {
            ctx.methods.insert(m.name);
        }
        _add_extension_methods(module, st.ty.name, ctx.methods);
        ctx.statics = _static_methods(st, module);
        struct_contexts.append(ctx);
    }
    var extension_contexts = Array<_ClosureContext>();
    for (var ext in module.extensions) {
        var ctx = _ClosureContext();
        for (var t in ext.target.sub_types) {
            if (t.sub_types.count == 0 and !types.contains(t.name) and !state.is_integral(t.name)) {
                ctx.generics.append(GenericParam(name = t.name, loc = Loc.none(), default_loc = Loc.none()));
            }
        }
        ctx.this_ty = Optional<TypeName>.Value(ext.target);
        for (var s in module.structs) {
            if (s.ty.name == ext.target.name) {
                for (var m in s.method_members) {
                    ctx.methods.insert(m.name);
                }
                for (var m in s.generic_methods) {
                    ctx.methods.insert(m.name);
                }
                for (var f in s.field_members) {
                    ctx.fields.insert(f.name);
                }
                ctx.statics = _static_methods(s, module);
                break;
            }
        }
        _add_extension_methods(module, ext.target.name, ctx.methods);
        extension_contexts.append(ctx);
    }
    var plain = _ClosureContext();
    for (var function in module.functions) {
        var before = lifted.count;
        _lift_function(state, function, plain, lifted);
        _inherit_deprecation([function.attributes], lifted, before);
    }
    ulong s = 0;
    while (s < module.structs.count) {
        var st = module.structs[s];
        var ctx = struct_contexts[s];
        var before = lifted.count;
        for (var f in st.field_members) {
            if (f.default.is_value()) {
                _lift_default(state, f, ctx, lifted);
            }
        }
        for (var constructor in st.constructors) {
            var from = lifted.count;
            _lift_function(state, constructor, ctx, lifted);
            _inherit_deprecation([st.attributes, constructor.attributes], lifted, from);
        }
        _lift_function(state, st.destructor, ctx, lifted);
        _inherit_deprecation([st.attributes], lifted, before);
        var methods = Array<FunctionDef>();
        methods.append_all(st.method_members);
        methods.append_all(st.generic_methods);
        for (var method in methods) {
            var from = lifted.count;
            _lift_function(state, method, ctx, lifted);
            _inherit_deprecation([st.attributes, method.attributes], lifted, from);
        }
        s += 1;
    }
    ulong e = 0;
    while (e < module.extensions.count) {
        for (var method in module.extensions[e].methods) {
            var from = lifted.count;
            _lift_function(state, method, extension_contexts[e], lifted);
            _inherit_deprecation([method.attributes], lifted, from);
        }
        e += 1;
    }
    for (var tr in module.traits) {
        # `this` has no single struct type in a trait's default method: its
        # closures are generic over the conforming type, `TRAIT_SELF`. They
        # see the trait's methods, and no fields.
        var ctx = _ClosureContext();
        ctx.generics.append_all(tr.generic_params);
        ctx.generics.append(GenericParam(name = TRAIT_SELF, loc = Loc.none(), default_loc = Loc.none()));
        ctx.this_ty = Optional<TypeName>.Value(TypeName.named(TRAIT_SELF));
        for (var m in tr.methods) {
            ctx.methods.insert(set_name(m.name));
            if (m.is_static) {
                ctx.statics.insert(set_name(m.name));
            }
        }
        for (var method in tr.methods) {
            var from = lifted.count;
            _lift_function(state, method, ctx, lifted);
            _inherit_deprecation([tr.attributes, method.attributes], lifted, from);
        }
    }
    for (var global in module.globals) {
        if (global.default.is_value()) {
            _lift_default(state, global, plain, lifted);
        }
    }
    module.structs.append_all(lifted);
}

_add_extension_methods(module: Module, name: String, methods: HashSet<String>) {
    for (var e in module.extensions) {
        if (e.target.name == name) {
            for (var m in e.methods) {
                methods.insert(m.name);
            }
        }
    }
}

## A closure lifted out of a declaration marked `[Deprecated]` (any of
## `attributes`) is still inside it: its `__call` carries the attribute, so
## the deprecation check does not report the uses in its body.
_inherit_deprecation(attributes: Array<Array<ast.Attribute>>, lifted: StructDef[], from: ulong) {
    var found = Optional<ast.Attribute>.Empty;
    for (var list in attributes) {
        for (var a in list) {
            if (is_deprecation(a)) {
                found = Optional<ast.Attribute>.Value(a);
                break;
            }
        }
        if (found.is_value()) {
            break;
        }
    }
    if (!found.is_value()) {
        return;
    }
    ulong i = from;
    while (i < lifted.count) {
        for (var method in lifted[i].method_members) {
            method.attributes.append(found.value());
        }
        i += 1;
    }
}

## Reports the first closure whose parameter, return or captured type is
## still `auto` once every type is final: the type must be written.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_closures(module: Module, state: PassState) {
    for (var st in module.structs) {
        if (!is_closure_struct(st.name) or st.generic_params.count > 0) {
            continue;
        }
        for (var call in st.method_members) {
            if (call.name != CALL_METHOD) {
                continue;
            }
            for (var param in call.parameters) {
                if (param.ty.contains_auto()) {
                    state.report(
                        error_at(
                            $"cannot infer the type of parameter '{param.name}'; write it: ({param.name}: Type) => ...",
                            param.loc
                        )
                    );
                    return;
                }
            }
            if (call.ty.contains_auto()) {
                state.report(
                    error_at(
                        "cannot infer the return type of this closure; write it after the parameters: (...): Type => ...",
                        call.loc
                    )
                );
                return;
            }
            for (var field in st.field_members) {
                if (field.ty.contains_auto()) {
                    state.report(
                        error_at($"cannot infer the type of '{field.name}', which this closure captures", field.loc)
                    );
                    return;
                }
            }
            break;
        }
    }
}
