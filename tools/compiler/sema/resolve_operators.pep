## Operators on structs: `pepper_sema::passes::resolve_operators` in Pepper.
## Index operations become `__index_get`/`__index_set` method calls or raw
## array indexing; binary operator overloads become method calls. Each is
## gated on the left side's static type naming a struct that declares the
## method, so plain compares (`size == 0`) and raw indexing stay as they are.

import [enum_method_name] from "builder";
import [is_enum] from "enums";
import [Loc] from "loc";
import [
    ArrayIndexExpression,
    BinaryExpression,
    BinaryOp,
    Block,
    Declaration,
    Expression,
    FunctionCallExpression,
    IndexExpression,
    Kind,
    MethodCallExpression,
    Module,
    Statement,
    SymbolRefExpression,
    TypeName,
    UnaryExpression,
    UnaryOp,
    VariableDef
] from "model";
import [op_name] from "operators";
import [apply_choice, arg_info, ArgInfo, method_target, Outcome, Overloads] from "overload_select";
import [PassState] from "state";
import [static_type_of, StructInfo, StructTable] from "static_type";
import [dispatch_unary] from "unary_operators";
import [method_is_static] from "value_types";
import [Rewriter, rewrite_block] from "walk";

## The prefix of a compound index assignment's temporaries.
const _INDEX_TEMPORARY = "_idx_tmp_";

## Rewrites the operators on structs in every concrete body and global
## initializer, as `resolve_operators::resolve_operators` does, recording
## the overloaded members it picks in `module.call_targets`.
##
## @param module the model, changed in place
## @param state the passes' state
export resolve_operators(module: Module, state: PassState) {
    var table = StructTable(module);
    var overloads = Overloads(module, state);
    var resolver = _OperatorResolver(table, overloads, state);
    for (var st in module.structs) {
        # A generic base's bodies stay raw: its specializations, where the
        # element type is concrete, are resolved instead.
        if (st.ty.is_generic() and st.name == st.ty.name) {
            continue;
        }
        resolver.current = Optional<TypeName>.Value(st.ty);
        for (var c in st.constructors) {
            if (c.body.is_value()) {
                resolver.body(c.body.value());
            }
        }
        for (var m in st.method_members) {
            if (m.body.is_value()) {
                resolver.body(m.body.value());
            }
        }
    }
    resolver.current = Optional<TypeName>.Empty;
    for (var f in module.functions) {
        if (f.body.is_value()) {
            resolver.body(f.body.value());
        }
    }
    # Global initializers; only the first statement of one survives.
    for (var g in module.globals) {
        if (!g.default.is_value()) {
            continue;
        }
        var items = Array<Statement>();
        items.append(Statement.Expression(g.default.value()));
        var block = Block(items = items);
        resolver.body(block);
        g.default = Optional<Expression>.Empty;
        if (block.items.count > 0) {
            if (block.items[0] is Expression(value)) {
                g.default = Optional<Expression>.Value(value);
            }
        }
    }
    module.call_targets.append_all(resolver.targets);
}

## The walks over one body; `current` is the struct whose method it is.
struct _OperatorResolver {
    var table: StructTable;
    var overloads: Overloads;
    var state: PassState;
    var current: TypeName? = Optional<TypeName>.Empty;
    var targets: Array<(Loc, String)> = Array<(Loc, String)>();
    ## The number of the next compound index assignment's temporary.
    var temporaries: ulong = 0;

    construct(table: StructTable, overloads: Overloads, state: PassState) {
        this.table = table;
        this.overloads = overloads;
        this.state = state;
    }

    body(body: Block) {
        # Temporaries are numbered within their function, after any an
        # earlier run declared there.
        temporaries = _next_index_temporary(body);
        _expand_compound_index_assigns(body);
        dispatch_unary(body, table, current, state);
        rewrite_block(body, _OperatorDispatch(this));
        # A walk visits an index before its receiver, so `a[x][y]` lowers
        # only `a[x]`; once that call has a type (its overload picked), the
        # outer index can lower too. Repeat while an index lowers.
        while (true) {
            # An overloaded operator names its set (`+`); pick the member.
            # Nested calls type from the inside out, so repeat while that
            # settles more.
            if (!overloads.is_empty()) {
                for (var round in 0..4) {
                    var picker = _OverloadPicker(this);
                    rewrite_block(body, picker);
                    if (!picker.changed) {
                        break;
                    }
                }
            }
            var lowering = _IndexLowering(this);
            rewrite_block(body, lowering);
            if (!lowering.lowered) {
                break;
            }
        }
    }

    type_of(e: Expression): TypeName? {
        return static_type_of(e, table, current, state);
    }

    ## The struct declaring `e`'s type; a bare field in a method (not yet
    ## `this.f`) types from the enclosing struct.
    lhs_struct(e: Expression): StructInfo? {
        var ty = _operand_type(e, table, current, state);
        return ty.is_value() ? table.lookup(ty.value()) : Optional<StructInfo>.Empty;
    }

    declares(e: Expression, method: String): bool {
        var info = lhs_struct(e);
        return info.is_value() and info.value().methods.contains(method);
    }

    ## Whether `e`'s type is a raw buffer (`T*`): indexing it stays raw.
    is_raw_buffer_field(e: Expression): bool {
        var ty = type_of(e);
        return ty.is_value() and ty.value().to_string().ends_with("*");
    }

    ## Whether `e` is an element of a raw buffer (`_data[i]`): an index into
    ## it stays an index.
    is_buffer_element(e: Expression): bool {
        match (e) {
            Index(node) => {
                return is_raw_buffer_field(node.lhs);
            }
            ArrayIndex(node) => {
                return is_raw_buffer_field(node.lhs);
            }
            else => {
                return false;
            }
        }
    }

    ## Whether the receiver of the index `e` (`recv[i] == x`) is a buffer
    ## (`String*`) whose pointee declares `method`.
    index_pointee_declares(e: Expression, method: String): bool {
        var receiver: Expression;
        match (e) {
            Index(node) => {
                receiver = node.lhs;
            }
            ArrayIndex(node) => {
                receiver = node.lhs;
            }
            else => {
                return false;
            }
        }
        var ty = type_of(receiver);
        if (!ty.is_value()) {
            return false;
        }
        var text = ty.value().to_string();
        if (!text.ends_with("*")) {
            return false;
        }
        var info = table.lookup(TypeName.named(text.substr_bytes(0, text.size - 1)));
        return info.is_value() and info.value().methods.contains(method);
    }

    ## Whether an index into `container` goes through its `__index_set`.
    sets_index(container: Expression): bool {
        return declares(container, "__index_set") and !is_raw_buffer_field(container) and !is_buffer_element(container);
    }

    ## The index `node` lowered to its receiver's `__index_get` call, or to
    ## raw `ArrayIndex` on a pointer; empty when it stays (a receiver whose
    ## type is not known yet is left for a later try).
    lower_index(node: IndexExpression): Expression? {
        var none = Optional<Expression>.Empty;
        # An enum's indexer: `light[i]` is `Light::__index_get(light, i)`.
        var ty = type_of(node.lhs);
        if (ty.is_value() and _declares_enum_operator(state, ty.value(), "__index_get")) {
            return Optional<Expression>.Value(
                _enum_operator_call(ty.value(), "__index_get", [node.lhs, node.rhs], node.loc)
            );
        }
        if (is_buffer_element(node.lhs)) {
            return none;
        }
        var info = lhs_struct(node.lhs);
        if (info.is_value()) {
            if (info.value().methods.contains("__index_get") and !is_raw_buffer_field(node.lhs)) {
                return Optional<Expression>.Value(
                    Expression.MethodCall(MethodCallExpression(node.lhs, "__index_get", [node.rhs], node.loc))
                );
            }
            return none;
        }
        if (ty.is_value() and ty.value().is_pointer()) {
            # A raw pointer receiver: array indexing. Any other receiver is
            # left for a later run.
            return Optional<Expression>.Value(
                Expression.ArrayIndex(ArrayIndexExpression(node.lhs, node.rhs, TypeName.auto(), node.loc))
            );
        }
        return none;
    }

    ## Expands each `x[y] op= z` to `var tmp = x.__index_get(y);` and
    ## `x.__index_set(y, tmp op z)`, nested blocks included.
    _expand_compound_index_assigns(body: Block) {
        ulong i = 0;
        while (i < body.items.count) {
            match (body.items[i]) {
                Expression(e) => {
                    var expanded = _compound_index_assign(e);
                    if (expanded.is_value()) {
                        var (declaration, set) = expanded.value();
                        body.items[i] = Statement.Declaration(Declaration.Variable(declaration));
                        body.items.insert(i + 1, Statement.Expression(set));
                        i += 2;
                        continue;
                    }
                }
                Block(inner) => {
                    _expand_compound_index_assigns(inner);
                }
                Branch(branch) => {
                    _expand_compound_index_assigns(branch.if_block);
                    if (branch.else_block.is_value()) {
                        _expand_compound_index_assigns(branch.else_block.value());
                    }
                }
                While(node) => {
                    _expand_compound_index_assigns(node.block);
                }
                else => {}
            }
            i += 1;
        }
    }

    _compound_index_assign(e: Expression): (VariableDef, Expression)? {
        var none = Optional<(VariableDef, Expression)>.Empty;
        if (e is Binary(node)) {
            if (node.lhs is Index(index)) {
                return _compound_index_set(node, index);
            }
        }
        return none;
    }

    _compound_index_set(node: BinaryExpression, index: IndexExpression): (VariableDef, Expression)? {
        var none = Optional<(VariableDef, Expression)>.Empty;
        var base = _compound_base(node.op);
        if (!base.is_value() or !sets_index(index.lhs)) {
            return none;
        }
        var loc = node.loc;
        var get_call = Expression.MethodCall(
            MethodCallExpression(index.lhs.copy(), "__index_get", [index.rhs.copy()], loc)
        );
        var name = $"{_INDEX_TEMPORARY}{temporaries}";
        temporaries += 1;
        var element = type_of(get_call);
        var temporary = VariableDef(
            name,
            element.is_value() ? element.value() : TypeName.auto(),
            Optional<Expression>.Value(get_call),
            kind = Kind.Variable,
            loc = loc,
            type_loc = Loc.none()
        );
        var value = Expression.Binary(
            BinaryExpression(
                Expression.SymbolRef(SymbolRefExpression(name, TypeName.auto(), loc)),
                node.rhs.copy(),
                base.value(),
                loc
            )
        );
        var set = Expression.MethodCall(
            MethodCallExpression(index.lhs.copy(), "__index_set", [index.rhs.copy(), value], loc)
        );
        return Optional<(VariableDef, Expression)>.Value((temporary, set));
    }
}

## Index assignments, compound assignment and binary operator overloads.
struct _OperatorDispatch {
    var resolver: _OperatorResolver;

    construct(resolver: _OperatorResolver) {
        this.resolver = resolver;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            Binary(node) => {
                if (_is_assignment(node.op)) {
                    return _assignment(e, node);
                }
                return _binary(e, node);
            }
            Index(node) => {
                var lowered = resolver.lower_index(node);
                if (lowered.is_value()) {
                    return lowered.value();
                }
            }
            else => {}
        }
        return e;
    }

    _assignment(e: Expression, node: BinaryExpression): Expression {
        # `x[y] = z` is `x.__index_set(y, z)` when the container is a
        # struct declaring the setter.
        if (node.op == BinaryOp.Assign) {
            if (node.lhs is Index(index)) {
                if (resolver.sets_index(index.lhs)) {
                    return Expression.MethodCall(
                        MethodCallExpression(index.lhs, "__index_set", [index.rhs, node.rhs], node.loc)
                    );
                }
            }
        }
        # A compound assignment with an overload (`s += x` is `s.+=(x)`).
        var name = op_name(node.op);
        if (!name.is_empty and resolver.declares(node.lhs, name)) {
            return Expression.MethodCall(MethodCallExpression(node.lhs, name, [node.rhs], node.loc));
        }
        return e;
    }

    _binary(e: Expression, node: BinaryExpression): Expression {
        var name = op_name(node.op);
        if (name.is_empty) {
            return e;
        }
        # An enum declaring the operator: `a < b` is `E::<(a, b)`.
        var ty = resolver.type_of(node.lhs);
        if (ty.is_value() and _declares_enum_operator(resolver.state, ty.value(), name)) {
            return _enum_operator_call(ty.value(), name, [node.lhs, node.rhs], node.loc);
        }
        if (resolver.index_pointee_declares(node.lhs, name) or resolver.declares(node.lhs, name)) {
            return Expression.MethodCall(MethodCallExpression(node.lhs, name, [node.rhs], node.loc));
        }
        if (node.op == BinaryOp.NotEqual
            and (resolver.index_pointee_declares(node.lhs, "==") or resolver.declares(node.lhs, "=="))) {
            # Without its own `!=`, `a != b` is `!(a == b)`.
            var equal = Expression.MethodCall(MethodCallExpression(node.lhs, "==", [node.rhs], node.loc));
            return Expression.Unary(UnaryExpression(equal, UnaryOp.LogicalNot, node.loc));
        }
        return e;
    }
}

extend _OperatorDispatch with Rewriter;

## Picks the member of each overloaded method call's set its arguments
## select.
struct _OverloadPicker {
    var resolver: _OperatorResolver;
    var changed: bool = false;

    construct(resolver: _OperatorResolver) {
        this.resolver = resolver;
    }

    rewrite(e: Expression): Expression {
        if (e is MethodCall(node)) {
            _pick(node);
        }
        return e;
    }

    _pick(node: MethodCallExpression) {
        var receiver = resolver.type_of(node.this_value);
        if (!receiver.is_value() or !resolver.overloads.is_method_set(receiver.value(), node.method)) {
            return;
        }
        var infos = Array<ArgInfo>();
        for (var arg in node.args) {
            infos.append(arg_info(arg, resolver.overloads, resolver.type_of(arg)));
        }
        var outcome = resolver.overloads.select_method(receiver.value(), node.method, infos, node.loc);
        if (outcome is Chosen(choice)) {
            var before = node.method;
            node.method = apply_choice(node.args, choice);
            resolver.targets.append((node.loc, method_target(receiver.value(), choice.callee)));
            if (node.method != before) {
                changed = true;
            }
        }
    }
}

extend _OverloadPicker with Rewriter;

## Lowers the indexes whose receivers are typed by now.
struct _IndexLowering {
    var resolver: _OperatorResolver;
    var lowered: bool = false;

    construct(resolver: _OperatorResolver) {
        this.resolver = resolver;
    }

    rewrite(e: Expression): Expression {
        if (e is Index(node)) {
            var out = resolver.lower_index(node);
            if (out.is_value()) {
                lowered = true;
                return out.value();
            }
        }
        return e;
    }
}

extend _IndexLowering with Rewriter;

## Whether `ty` is an enum whose own instance method `operator` an operator
## on its value calls: `enums::declares_operator`.
_declares_enum_operator(state: PassState, ty: TypeName, operator: String): bool {
    if (ty.sub_types.count > 0 or ty.is_pointer() or !is_enum(state, ty.name)) {
        return false;
    }
    var is_static = method_is_static(state, ty.name, operator);
    return is_static.is_value() and !is_static.value();
}

## The call of operator method `operator` of enum `ty` on `operands`, the
## value first.
_enum_operator_call(ty: TypeName, operator: String, operands: Expression[], loc: Loc): Expression {
    return Expression.FunctionCall(FunctionCallExpression(enum_method_name(ty.name, operator), operands, loc));
}

## One more than the highest `_idx_tmp_N` `block` declares, or 0.
_next_index_temporary(block: Block): ulong {
    ulong next = 0;
    for (var statement in block.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (!variable.name.starts_with(_INDEX_TEMPORARY)) {
                        continue;
                    }
                    var number = ulong.parse(
                        variable.name.substr_bytes(_INDEX_TEMPORARY.size, variable.name.size - _INDEX_TEMPORARY.size)
                    );
                    if (number.is_value() and number.value() + 1 > next) {
                        next = number.value() + 1;
                    }
                }
            }
            Block(inner) => {
                next = _max_ulong(next, _next_index_temporary(inner));
            }
            Branch(branch) => {
                next = _max_ulong(next, _next_index_temporary(branch.if_block));
                if (branch.else_block.is_value()) {
                    next = _max_ulong(next, _next_index_temporary(branch.else_block.value()));
                }
            }
            While(node) => {
                next = _max_ulong(next, _next_index_temporary(node.block));
            }
            else => {}
        }
    }
    return next;
}

_max_ulong(a: ulong, b: ulong): ulong {
    return a > b ? a : b;
}
