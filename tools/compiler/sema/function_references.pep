## Methods, structs and generic functions used as values become closures:
## `function_references::reference_functions` in Pepper. `p.area` is a
## closure capturing `p` that calls `area` on it, `Shape.area` one taking
## the receiver as its first argument, and a struct's name (`Point`) or a
## specialization (`pick<int>`) one calling it.

import [Location] from compiler.diagnostic;
import [mangle] from compiler.link;
import text;
import [closure_struct, CLOSURE_PREFIX, field_def] from "closures";
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [
    BinaryOp,
    Block,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    GenericParam,
    Kind,
    MakeClosureExpression,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    ReturnStatement,
    Statement,
    StructDef,
    SymbolRefExpression,
    TypeName,
    VariableDef
] from "model";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [apply_synthesized, finish] from "synthesize";
import [instance, trait_def, used_trait_types] from "traits";
import [FUNCTION, parse_type_string, VOID] from "type_name";
import [Rewriter, rewrite_block, rewrite_children] from "walk";

## The field of a bound method's closure that holds its receiver.
export const RECEIVER_FIELD = "__receiver";

## What a referenced function takes and returns.
struct _Signature {
    var params: Array<(String, TypeName)> = Array<(String, TypeName)>();
    var ret: TypeName;
    var is_static: bool;
    var requires_arguments: bool = false;

    construct(function: FunctionDef) {
        for (var p in function.parameters) {
            var name = p.name.starts_with("this.") ? p.name.substr_bytes(5, p.name.size - 5) : p.name;
            params.append((name, p.ty));
            if (!p.default.is_value()) {
                requires_arguments = true;
            }
        }
        ret = function.ty;
        is_static = function.is_static;
    }
}

## What the program declares that a reference can name.
struct _Referenceable {
    var methods: HashMap<String, HashMap<String, _Signature>> = HashMap<String, HashMap<String, _Signature>>();
    var fields: HashMap<String, Array<String>> = HashMap<String, Array<String>>();
    var constructors: HashMap<String, _Signature> = HashMap<String, _Signature>();
    var plain_structs: HashMap<String, TypeName> = HashMap<String, TypeName>();
    var generic_functions: HashMap<String, _Signature> = HashMap<String, _Signature>();
    var variadic_externs: HashSet<String> = HashSet<String>();
    var statics: StructTable;

    construct(module: Module, state: PassState) {
        statics = StructTable(module, memo = state.trait_types_memo());
        for (var st in module.structs) {
            if (st.generic_params.count != 0) {
                continue;
            }
            var key = st.ty.to_string();
            if (!methods.contains(key)) {
                methods[key] = HashMap<String, _Signature>();
            }
            var own = methods[key];
            for (var m in st.method_members) {
                if (!m.name.starts_with("__") and !own.contains(m.name)) {
                    own[m.name] = _Signature(m);
                }
            }
            var names = Array<String>();
            for (var f in st.field_members) {
                names.append(f.name);
            }
            fields[key] = names;
            for (var c in st.constructors) {
                var ctor = _Signature(c);
                ctor.ret = st.ty;
                ulong i = 0;
                while (i < ctor.params.count) {
                    var (name, ty) = ctor.params[i];
                    if (ty.contains_auto() or ty.is_empty()) {
                        for (var f in st.field_members) {
                            if (f.name == name) {
                                ctor.params[i] = (name, f.ty);
                                break;
                            }
                        }
                    }
                    i += 1;
                }
                constructors[c.name] = ctor;
            }
            if (!st.name.starts_with("__") and !key.contains("<")) {
                plain_structs[st.name] = st.ty;
            }
        }
        for (var ty in used_trait_types(module, state.trait_types_memo())) {
            var def = trait_def(module.traits, ty);
            var key = ty.to_string();
            if (def.is_value() and !methods.contains(key)) {
                var own = HashMap<String, _Signature>();
                for (var m in instance(def.value(), ty).methods) {
                    own[m.name] = _Signature(m);
                }
                methods[key] = own;
            }
        }
        for (var f in module.functions) {
            if (!f.is_generic_func
                and f.name.contains("<")
                and (f.body.is_value() or module.stripped.contains(f.loc))) {
                generic_functions[f.name] = _Signature(f);
            }
        }
        for (var e in module.externs) {
            if (e.is_variadic) {
                variadic_externs.insert(e.name);
            }
        }
    }

    method(owner: TypeName, name: String): _Signature? {
        var own = methods.try_get(_without_stars(owner.to_string()));
        if (!own.is_value()) {
            return Optional<_Signature>.Empty;
        }
        return own.value().try_get(name);
    }

    has_field(owner: TypeName, name: String): bool {
        var names = fields.try_get(_without_stars(owner.to_string()));
        return names.is_value() and names.value().contains(name);
    }

    named_struct(e: Expression): TypeName? {
        match (e) {
            SymbolRef(node) => {
                return plain_structs.try_get(node.id);
            }
            FunctionCall(node) => {
                if (node.args.count == 0 and node.function.contains("<") and constructors.contains(node.function)) {
                    return Optional<TypeName>.Value(parse_type_string(node.function));
                }
            }
            else => {}
        }
        return Optional<TypeName>.Empty;
    }
}

_without_stars(text: String): String {
    var out = text;
    while (out.ends_with("*")) {
        out = out.substr_bytes(0, out.size - 1);
    }
    return out;
}

## What a reference names.
enum _Target {
    Bound(receiver: Expression, receiver_ty: TypeName, method: String),
    Unbound(owner: TypeName, method: String),
    Call(function: String),
}

## Turns each method, struct and specialization used as a value into a
## closure struct and its creation.
##
## @param module the model, changed in place
## @param state the passes' state, which takes the first error
export reference_functions(module: Module, state: PassState) {
    var replacer = _References(_Referenceable(module, state), state);
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            continue;
        }
        replacer.current = Optional<TypeName>.Value(st.ty);
        for (var field in st.field_members) {
            if (field.default.is_value()) {
                replacer.owned_by($"{st.name}.{field.name}");
                field.default = Optional<Expression>.Value(replacer.expression(field.default.value(), false));
            }
        }
        for (var method in st.method_members) {
            replacer.owned_by($"{st.name}.{method.name}");
            replacer.function(method);
        }
        for (var constructor in st.constructors) {
            replacer.owned_by($"{st.name}.{constructor.name}");
            replacer.function(constructor);
        }
        replacer.owned_by($"{st.name}.{st.destructor.name}");
        replacer.function(st.destructor);
    }
    replacer.current = Optional<TypeName>.Empty;
    for (var function in module.functions) {
        if (!function.is_generic_func) {
            replacer.owned_by(function.name);
            replacer.function(function);
        }
    }
    for (var g in module.globals) {
        if (g.default.is_value()) {
            replacer.owned_by(g.name);
            g.default = Optional<Expression>.Value(replacer.expression(g.default.value(), false));
        }
    }
    module.structs.append_all(replacer.added);
}

## Replaces the references in one function or initializer at a time.
struct _References {
    var declared: _Referenceable;
    var state: PassState;
    var added: Array<StructDef> = Array<StructDef>();
    var current: TypeName? = Optional<TypeName>.Empty;
    var retyped: HashMap<String, TypeName> = HashMap<String, TypeName>();
    var locals: Array<Array<String>> = Array<Array<String>>();
    var owner: String = "";
    var made: ulong = 0;

    construct(declared: _Referenceable, state: PassState) {
        this.declared = declared;
        this.state = state;
    }

    owned_by(owner: String) {
        this.owner = owner;
        made = 0;
    }

    function(function: FunctionDef) {
        for (var param in function.parameters) {
            if (param.default.is_value()) {
                param.default = Optional<Expression>.Value(expression(param.default.value(), false));
            }
        }
        if (!function.body.is_value()) {
            return;
        }
        var body = function.body.value();
        retyped = HashMap<String, TypeName>();
        var names = Array<String>();
        for (var p in function.parameters) {
            names.append(p.name);
        }
        locals = [names];
        block(body);
        locals = Array<Array<String>>();
        if (retyped.count > 0) {
            rewrite_block(body, _Retyper(retyped));
            retyped = HashMap<String, TypeName>();
        }
    }

    block(b: Block) {
        locals.append(Array<String>());
        block_items(b);
        locals.pop();
    }

    block_items(b: Block) {
        ulong i = 0;
        while (i < b.items.count) {
            match (b.items[i]) {
                Expression(e) => {
                    b.items[i] = Statement.Expression(expression(e, false));
                }
                Block(inner) => {
                    block(inner);
                }
                Declaration(declaration) => {
                    if (declaration is Variable(variable)) {
                        declare(variable);
                    }
                }
                Branch(branch) => {
                    branch.condition = expression(branch.condition, false);
                    block(branch.if_block);
                    if (branch.else_block.is_value()) {
                        block(branch.else_block.value());
                    }
                }
                While(loop) => {
                    loop.condition = expression(loop.condition, false);
                    block(loop.block);
                }
                Return(r) => {
                    if (r.expr.is_value()) {
                        r.expr = Optional<Expression>.Value(expression(r.expr.value(), false));
                    }
                }
                else => {}
            }
            i += 1;
        }
    }

    ## A local whose initializer is a reference takes the closure's type
    ## when the program wrote none.
    declare(variable: VariableDef) {
        if (variable.default.is_value()) {
            var was_reference = variable.default.value() is MakeClosure(_);
            var value = expression(variable.default.value(), false);
            variable.default = Optional<Expression>.Value(value);
            if (!was_reference) {
                _retype(variable, value);
            }
        }
        if (locals.count > 0) {
            locals[locals.count - 1].append(variable.name);
        }
    }

    _retype(variable: VariableDef, value: Expression) {
        if (value is MakeClosure(node)) {
            if (variable.type_loc == Loc.none() and !(variable.ty == node.ty)) {
                variable.ty = node.ty;
                retyped[variable.name] = node.ty;
            }
        }
    }

    is_local(name: String): bool {
        for (var scope in locals) {
            if (scope.contains(name)) {
                return true;
            }
        }
        return false;
    }

    named_struct(e: Expression): TypeName? {
        if (e is SymbolRef(node)) {
            if (is_local(node.id)) {
                return Optional<TypeName>.Empty;
            }
        }
        return declared.named_struct(e);
    }

    ## `e` with its references replaced; `receiver` when it is the receiver
    ## of a member access or call.
    expression(e: Expression, receiver: bool): Expression {
        match (e) {
            MemberRef(node) => {
                var owner = named_struct(node.lhs);
                if (owner.is_value()) {
                    if (declared.method(owner.value(), node.name).is_value()) {
                        return replace(e, _Target.Unbound(owner.value(), node.name), node.loc);
                    }
                    return e;
                }
                node.lhs = expression(node.lhs, true);
                var receiver_ty = static_type_of(node.lhs, declared.statics, current, state);
                if (!receiver_ty.is_value()
                    or receiver_ty.value().contains_auto()
                    or declared.has_field(receiver_ty.value(), node.name)) {
                    return e;
                }
                var signature = declared.method(receiver_ty.value(), node.name);
                if (!signature.is_value() or signature.value().is_static) {
                    return e;
                }
                return replace(e, _Target.Bound(node.lhs, receiver_ty.value(), node.name), node.loc);
            }
            MethodCall(node) => {
                node.this_value = expression(node.this_value, true);
                ulong i = 0;
                while (i < node.args.count) {
                    node.args[i] = expression(node.args[i], false);
                    i += 1;
                }
                return e;
            }
            SymbolRef(node) => {
                if (!receiver) {
                    if (declared.variadic_externs.contains(node.id) and !is_local(node.id)) {
                        state.report(
                            error_at(
                                $"variadic extern '{node.id}' cannot be a function value; wrap a call to it in a closure",
                                node.loc
                            )
                        );
                        return e;
                    }
                    var owner = named_struct(e);
                    if (owner.is_value()) {
                        return replace(e, _Target.Call(owner.value().to_string()), node.loc);
                    }
                    return e;
                }
            }
            FunctionCall(node) => {
                if (node.args.count == 0 and !receiver) {
                    var generic = declared.generic_functions.try_get(node.function);
                    var constructor = declared.constructors.try_get(node.function);
                    if ((generic.is_value() and generic.value().requires_arguments)
                        or (node.function.contains("<")
                            and constructor.is_value()
                            and constructor.value().requires_arguments)) {
                        return replace(e, _Target.Call(node.function), node.loc);
                    }
                    return e;
                }
            }
            else => {}
        }
        var out = rewrite_children(e, _ChildReferences(this));
        if (out is Binary(binary)) {
            if (binary.op == BinaryOp.Assign) {
                _check_this_cycle(binary.lhs, binary.rhs, state);
            }
        }
        return out;
    }

    ## The closure that stands for `target`, or `e` when there is none.
    replace(e: Expression, target: _Target, loc: Loc): Expression {
        var found = Optional<_Signature>.Empty;
        match (target) {
            Bound(_, receiver_ty, method) => {
                found = declared.method(receiver_ty, method);
            }
            Unbound(owner, method) => {
                found = declared.method(owner, method);
            }
            Call(function) => {
                found = declared.generic_functions.try_get(function);
                if (!found.is_value()) {
                    found = declared.constructors.try_get(function);
                }
            }
        }
        if (!found.is_value()) {
            return e;
        }
        var signature = found.value();
        var (base, ty) = _owned_closure_name(state, owner, made, loc);
        made += 1;
        var parameters = Array<VariableDef>();
        var forwarded = Array<Expression>();
        ulong i = 0;
        while (i < signature.params.count) {
            var (_, param_ty) = signature.params[i];
            var name = $"__arg{i}";
            parameters.append(_param(name, param_ty, loc));
            forwarded.append(Expression.SymbolRef(SymbolRefExpression(name, param_ty, loc)));
            i += 1;
        }
        var captures = Array<VariableDef>();
        var args = Array<Expression>();
        var call = Expression.FunctionCall(FunctionCallExpression("", Array<Expression>(), loc));
        match (target) {
            Bound(receiver, receiver_ty, method) => {
                captures.append(field_def(RECEIVER_FIELD, receiver_ty, Optional<Expression>.Empty, loc));
                args.append(receiver);
                var held = Expression.MemberRef(MemberRefExpression(Expression.ThisRef, RECEIVER_FIELD, loc));
                call = Expression.MethodCall(MethodCallExpression(held, method, forwarded, loc));
            }
            Unbound(owner_ty, method) => {
                if (signature.is_static) {
                    var named = Expression.SymbolRef(SymbolRefExpression(owner_ty.to_string(), TypeName.auto(), loc));
                    call = Expression.MethodCall(MethodCallExpression(named, method, forwarded, loc));
                } else {
                    parameters.insert(0, _param("self", owner_ty, loc));
                    var self_ref = Expression.SymbolRef(SymbolRefExpression("self", owner_ty, loc));
                    call = Expression.MethodCall(MethodCallExpression(self_ref, method, forwarded, loc));
                }
            }
            Call(function) => {
                call = Expression.FunctionCall(FunctionCallExpression(function, forwarded, loc));
            }
        }
        var statement = signature.ret.to_string() == VOID ?
            Statement.Expression(call) :
            Statement.Return(ReturnStatement(Optional<Expression>.Value(call), loc));
        var body = Block(items = [statement]);
        var types = Array<TypeName>();
        types.append(signature.ret);
        for (var p in parameters) {
            types.append(p.ty);
        }
        var function_type = TypeName.with_args(FUNCTION, types);
        var st = closure_struct(base, ty, Array<GenericParam>(), captures, parameters, signature.ret, body, loc);
        apply_synthesized(st);
        var error = finish(state, st);
        if (error.is_value()) {
            state.report(error_at(error.value(), loc));
            return e;
        }
        added.append(st);
        return Expression.MakeClosure(
            MakeClosureExpression(
                Expression.FunctionCall(FunctionCallExpression(ty.to_string(), args, loc)),
                ty.to_string(),
                function_type,
                loc
            )
        );
    }
}

## Replaces the references in each child of an expression.
struct _ChildReferences {
    var references: _References;

    construct(references: _References) {
        this.references = references;
    }

    rewrite(e: Expression): Expression {
        return references.expression(e, false);
    }
}

extend _ChildReferences with Rewriter;

## Gives the uses of retyped locals their new type.
struct _Retyper {
    var retyped: HashMap<String, TypeName>;

    construct(retyped: HashMap<String, TypeName>) {
        this.retyped = retyped;
    }

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            var ty = retyped.try_get(node.id);
            if (ty.is_value()) {
                node.ty = ty.value();
            }
        }
        return e;
    }
}

extend _Retyper with Rewriter;

_param(name: String, ty: TypeName, loc: Loc): VariableDef {
    var param = field_def(name, ty, Optional<Expression>.Empty, loc);
    param.kind = Kind.Param;
    return param;
}

## The name of reference number `index` made in `owner`: every character
## but a letter or digit is escaped, so two owners never give one name.
_owned_closure_name(state: PassState, owner: String, index: ulong, loc: Loc): (String, TypeName) {
    var escaped = Array<String>();
    var start: ulong = 0;
    ulong i = 0;
    while (i < owner.size) {
        var b = owner.byte_at(i);
        if (b.is_alphanumeric() and b < 128) {
            i += 1;
            continue;
        }
        escaped.append(owner.substr_bytes(start, i - start));
        var (point, length) = text.Utf8.code_point_at(owner, i);
        escaped.append($"_{point:x}_");
        i += length;
        start = i;
    }
    escaped.append(owner.substr_bytes(start, owner.size - start));
    var name = $"{CLOSURE_PREFIX}{"".join(escaped)}_{index}";
    var base = name;
    if (!loc.is_none() and (loc.file as ulong) < state.namespaces.count) {
        base = mangle(name, state.namespaces[loc.file as ulong]);
    }
    return (base, TypeName.named(base));
}

## Storing a method of `this` in a field of `this` makes a cycle.
_check_this_cycle(lhs: Expression, rhs: Expression, state: PassState) {
    if (lhs is MemberRef(member)) {
        if (member.lhs is ThisRef) {
            if (rhs is MakeClosure(closure)) {
                if (closure.value is FunctionCall(call)) {
                    if (call.args.count == 1 and call.args[0] is ThisRef) {
                        state.report(
                            error_at(
                                $"storing a method of 'this' in field '{member.name}' of 'this' creates a reference cycle that is never freed",
                                member.loc
                            ).with_note(
                                "the method value captures 'this' here; capture a 'Weak' reference to it in a closure instead",
                                Optional<Location>.Value(location_of(closure.loc))
                            )
                        );
                    }
                }
            }
        }
    }
}
