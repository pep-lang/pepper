## Bare names in struct methods: `convert_member_refs`. An unresolved symbol
## naming a field becomes `this.<field>`; a plain call naming a method
## becomes a method call (on `this`, or on the struct for a static method,
## as `S.f()` would be written); parameters and locals are exempt.

import "closures";
import [error_at] from "common";
import [Loc] from "loc";
import [
    Block,
    Declaration,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    Kind,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    Statement,
    SymbolRefExpression,
    TypeName
] from "model";
import [set_name, without_type_arguments] from "names";
import "resolve_implicit_types";
import [PassState] from "state";
import "type_name";
import [Rewriter, rewrite_expression] from "walk";

## Marks a static method's name in a method list; no identifier contains it.
const _STATIC_MARK = "static ";

## In a method list, marks a generic base struct (`Array` of `Array<T>`).
const _GENERIC_BASE = "generic base";

## The members a bare name in a method may bind to on `this`, and what
## decides between a method and a free function of one name.
struct _Methods {
    var names: HashSet<String>;
    var arities: Array<(String, ulong, ulong)>;
    ## The free functions and externs a bare call may name instead.
    var free: HashSet<String>;

    construct(names: HashSet<String>, arities: Array<(String, ulong, ulong)>, free: HashSet<String>) {
        this.names = names;
        this.arities = arities;
        this.free = free;
    }

    contains(name: String): bool {
        return names.contains(name);
    }

    ## Whether a bare call of `name` with `count` arguments is a method
    ## call: one of the methods takes `count` arguments, or no free function
    ## `name` exists to call instead.
    calls_method(name: String, count: ulong): bool {
        return contains(name) and (!free.contains(name) or _takes(arities, name, count));
    }
}

## Rewrites the bare names of one method body, given the names in scope.
struct _MemberRefs {
    var state: PassState;
    var struct_name: String;
    var fields: HashSet<String>;
    var methods: _Methods;
    var locals: Array<String>;
    var globals: HashSet<String>;

    construct(
        state: PassState,
        struct_name: String,
        fields: HashSet<String>,
        methods: _Methods,
        locals: Array<String>,
        globals: HashSet<String>
    ) {
        this.state = state;
        this.struct_name = struct_name;
        this.fields = fields;
        this.methods = methods;
        this.locals = locals;
        this.globals = globals;
    }

    block(block: Block) {
        ulong i = 0;
        while (i < block.items.count) {
            block.items[i] = statement(block.items[i]);
            i += 1;
        }
    }

    ## A nested block's locals go out of scope at its end.
    scoped(block: Block) {
        var base = locals.count;
        this.block(block);
        locals.truncate(base);
    }

    statement(statement: Statement): Statement {
        match (statement) {
            Expression(value) => {
                return Statement.Expression(rewrite_expression(value, this));
            }
            Block(value) => {
                scoped(value);
            }
            Declaration(value) => {
                if (value is Variable(variable)) {
                    locals.append(variable.name);
                    if (variable.default.is_value()) {
                        variable.default = Optional<Expression>.Value(
                            rewrite_expression(variable.default.value(), this)
                        );
                    }
                }
            }
            Branch(value) => {
                value.condition = rewrite_expression(value.condition, this);
                scoped(value.if_block);
                if (value.else_block.is_value()) {
                    scoped(value.else_block.value());
                }
            }
            While(value) => {
                value.condition = rewrite_expression(value.condition, this);
                scoped(value.block);
            }
            Return(value) => {
                if (value.expr.is_value()) {
                    value.expr = Optional<Expression>.Value(rewrite_expression(value.expr.value(), this));
                }
            }
            else => {}
        }
        return statement;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            SymbolRef(node) => {
                return _symbol(e, node);
            }
            FunctionCall(node) => {
                return _call(e, node);
            }
            else => {}
        }
        return e;
    }

    _symbol(e: Expression, node: SymbolRefExpression): Expression {
        var id = node.id;
        if (id == "this" or locals.contains(id)) {
            return e;
        }
        # Fields shadow file-scope globals (member-lookup order).
        if (fields.contains(id)) {
            return Expression.MemberRef(MemberRefExpression(Expression.ThisRef, id, node.loc));
        }
        if (methods.contains(id)) {
            return _method_value(e, id, id, node.loc);
        }
        # File-scope globals and struct names (the receiver of a static
        # call) are visible from methods too.
        if (globals.contains(id)) {
            return e;
        }
        if (node.ty.is_empty() or node.ty.is_auto()) {
            state.report(error_at($"use of undeclared identifier '{id}' in a method of '{struct_name}'", node.loc));
        }
        return e;
    }

    ## A bare method name as the method's value, as `this.m` (or `S.m` for
    ## a static method) would write it; `e` when a generic base's static
    ## method, which has no name to write it on.
    _method_value(e: Expression, method: String, name: String, at: Loc): Expression {
        var receiver = Expression.ThisRef;
        if (methods.contains(_STATIC_MARK + method)) {
            if (methods.contains(_GENERIC_BASE)) {
                return e;
            }
            # A specialization is named as `Box<int>.m` writes it: a
            # constructor-style receiver.
            if (struct_name.contains("<")) {
                receiver = Expression.FunctionCall(FunctionCallExpression(struct_name, Array<Expression>(), at));
            } else {
                receiver = Expression.SymbolRef(SymbolRefExpression(struct_name, TypeName.auto(), at));
            }
        }
        return Expression.MemberRef(MemberRefExpression(receiver, name, at));
    }

    _call(e: Expression, node: FunctionCallExpression): Expression {
        # A call with explicit type arguments (`make<String>(n)`) names its
        # method by the name before them. A converted string literal
        # constructs `String` even beside a method named `String`.
        var name = without_type_arguments(node.function);
        # `make<int>` with no parentheses is the generic method's value.
        if (node.bare and node.args.count == 0 and methods.contains(name)) {
            return _method_value(e, name, node.function, node.loc);
        }
        if (!methods.calls_method(name, node.args.count) or _is_converted_literal(node)) {
            return e;
        }
        var receiver = Expression.ThisRef;
        if (methods.contains(_STATIC_MARK + name)) {
            # A generic base has no name to call on; its specializations,
            # copied from it, convert the call.
            if (methods.contains(_GENERIC_BASE)) {
                return e;
            }
            receiver = Expression.SymbolRef(SymbolRefExpression(struct_name, TypeName.auto(), Loc.none()));
        }
        return Expression.MethodCall(MethodCallExpression(receiver, node.function, node.args, node.loc));
    }
}

extend _MemberRefs with Rewriter;

## Rewrites the bare names in every struct's constructors and methods, reporting a bare name
## that names nothing.
##
## @param module the model, changed in place
## @param state the passes' state, which takes the first error
export convert_member_refs(module: Module, state: PassState) {
    # Names a bare symbol in a method may resolve to outside the struct:
    # module globals, and struct names.
    var globals = HashSet<String>();
    for (var g in module.globals) {
        globals.insert(g.name);
    }
    for (var st in module.structs) {
        globals.insert(st.name);
    }
    var free = HashSet<String>();
    for (var f in module.functions) {
        free.insert(f.name);
    }
    for (var e in module.externs) {
        free.insert(e.name);
    }
    for (var st in module.structs) {
        if (!_has_body(st.constructors) and !_has_body(st.method_members)) {
            continue;
        }
        var fields = HashSet<String>();
        for (var f in st.field_members) {
            if (f.kind == Kind.Field) {
                fields.insert(f.name);
            }
        }
        # An overloaded method is also called by its set's name; a static
        # method's names are listed again behind `_STATIC_MARK`. Generic
        # methods count too: a bare `make<T>(n)` calls one before any
        # specialization of it exists.
        var names = HashSet<String>();
        var members = Array<FunctionDef>();
        members.append_all(st.method_members);
        members.append_all(st.generic_methods);
        for (var m in members) {
            names.insert(m.name);
            names.insert(set_name(m.name));
            if (m.is_static) {
                names.insert(_STATIC_MARK + m.name);
                names.insert(_STATIC_MARK + set_name(m.name));
            }
        }
        if (st.generic_params.count > 0) {
            names.insert(_GENERIC_BASE);
        }
        var methods = _Methods(names, _method_arities(st), free);
        # A bare property whose storage is not a field of its name is
        # `this.p` too, which the next `resolve_implicit_types` rewrites.
        for (var property in module.properties) {
            if (property.owner == st.ty.name and !property.in_trait) {
                fields.insert(property.name);
            }
        }
        # A generic base's own type parameters name types, not members.
        var type_params = Array<String>();
        for (var p in st.generic_params) {
            if (!fields.contains(p.name)) {
                type_params.append(p.name);
            }
        }
        for (var c in st.constructors) {
            _convert(c, st.name, fields, methods, type_params, globals, state);
        }
        for (var m in st.method_members) {
            if (!m.body.is_value()) {
                continue;
            }
            # A trait's default method sees only the trait: its methods, on
            # `this`, and no fields.
            if (m.trait_default.is_value()) {
                var trait_names = HashSet<String>();
                for (var name in m.trait_default.value()) {
                    trait_names.insert(name);
                }
                var trait_methods = _Methods(trait_names, Array<(String, ulong, ulong)>(), HashSet<String>());
                _convert(m, st.name, HashSet<String>(), trait_methods, type_params, globals, state);
            } else {
                _convert(m, st.name, fields, methods, type_params, globals, state);
            }
        }
    }
}

_has_body(functions: FunctionDef[]): bool {
    for (var f in functions) {
        if (f.body.is_value()) {
            return true;
        }
    }
    return false;
}

## Rewrites one body, its parameters and the struct's type parameters
## exempt.
_convert(
    function: FunctionDef,
    struct_name: String,
    fields: HashSet<String>,
    methods: _Methods,
    type_params: String[],
    globals: HashSet<String>,
    state: PassState
) {
    if (!function.body.is_value()) {
        return;
    }
    var locals = Array<String>();
    for (var p in function.parameters) {
        locals.append(p.name);
    }
    locals.append_all(type_params);
    _MemberRefs(state, struct_name, fields, methods, locals, globals).block(function.body.value());
}
