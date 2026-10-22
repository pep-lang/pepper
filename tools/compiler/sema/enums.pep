## Enum cases written in code: `resolve_enum_cases`. Every `Color.Red`
## becomes `Red`'s value typed `Color`, a reference enum's case that carries
## nothing becomes a call of its static method, an enum's static methods are
## called as functions, and each enum gets its built-in methods `name` and
## `from_value`. Lowering `match` comes later.

import [Diagnostic, Location] from compiler.diagnostic;
import [demangle_name] from compiler.link;
import [CAST_VALUE, enum_method_name, enum_this_parameter, payload_field] from "builder";
import [is_checked_function, unit_decls] from "checked";
import "common";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Branch,
    CaseChoice,
    CaseValue,
    CastExpression,
    CastKind,
    Declaration,
    EnumCaseDef,
    EnumDef,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    GenericParam,
    MethodCallExpression,
    Module,
    ReturnStatement,
    Statement,
    StringLiteralExpression,
    StructDef,
    SymbolRefExpression,
    TypeName,
    VariableDef
] from "model";
import [method_key, PassState, ReferenceEnum] from "state";
import [is_integral_name, parse_type_string, replace_map, VOID] from "type_name";
import [lower_extensions, method_is_static, resolve_static_calls, value_type_key] from "value_types";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Resolves the enum cases and methods written in code. Errors go to `state`.
##
## @param module the model, changed in place
## @param state the passes' state
export resolve_enum_cases(module: Module, state: PassState) {
    state.install_enums(module.enums);
    install_reference_enums(state, module.structs);
    install_traits(module, state);
    # Extensions of numbers, `bool` and enums become functions `X::m`.
    lower_extensions(module, state);
    bool has_reference_enum = false;
    for (var st in module.structs) {
        if (st.enum_cases.is_value()) {
            has_reference_enum = true;
        }
    }
    if (module.enums.count == 0 and !has_reference_enum) {
        install_methods(module, state);
        _method_bodies(module, state);
        resolve_static_calls(module, state);
        return;
    }
    _add_built_in_methods(module);
    install_methods(module, state);
    _method_bodies(module, state);
    resolve_static_calls(module, state);
    var enums = HashMap<String, EnumDef>();
    for (var e in module.enums) {
        if (!enums.contains(e.name)) {
            enums[e.name] = e;
        }
    }
    var resolver = _CaseResolver(state, enums);
    _for_each_body(module, resolver);
    # A checked runtime's defaults were resolved when it was checked, and
    # the cases they hold are located casts now, which the walk would
    # report as written by the user.
    for (var st in module.structs) {
        if (module.checked.structs.contains(st.name)) {
            continue;
        }
        for (var field in st.field_members) {
            if (field.default.is_value()) {
                field.default = Optional<Expression>.Value(rewrite_expression(field.default.value(), resolver));
            }
        }
        var methods = Array<FunctionDef>();
        methods.append_all(st.method_members);
        methods.append_all(st.generic_methods);
        methods.append_all(st.constructors);
        for (var method in methods) {
            _resolve_defaults(method, resolver);
        }
    }
    for (var function in module.functions) {
        if (!is_checked_function(module, function)) {
            _resolve_defaults(function, resolver);
        }
    }
    for (var global in module.globals) {
        if (module.checked.globals.contains(global.name)) {
            continue;
        }
        if (!global.default.is_value()) {
            global.default = default_expression(state, global.ty);
        }
        if (global.default.is_value()) {
            global.default = Optional<Expression>.Value(rewrite_expression(global.default.value(), resolver));
        }
    }
}

_resolve_defaults(function: FunctionDef, resolver: Rewriter) {
    for (var p in function.parameters) {
        if (p.default.is_value()) {
            p.default = Optional<Expression>.Value(rewrite_expression(p.default.value(), resolver));
        }
    }
}

## Every function body and method body of the compilation unit's own code (a
## checked declaration's cases were resolved with its unit): structs'
## methods, constructors, destructors and count methods, then extensions' and
## traits' methods, then free functions; each first gets its enum locals'
## defaults.
_for_each_body(module: Module, resolver: _CaseResolver) {
    var own = unit_decls(module);
    for (var st in own.structs) {
        var methods = Array<FunctionDef>();
        methods.append_all(st.method_members);
        methods.append_all(st.generic_methods);
        methods.append_all(st.constructors);
        methods.append(st.destructor);
        methods.append(st.acquire);
        methods.append(st.release);
        for (var method in methods) {
            _in_body(method, resolver);
        }
    }
    for (var e in module.checked.extensions..module.extensions.count) {
        for (var method in module.extensions[e].methods) {
            _in_body(method, resolver);
        }
    }
    for (var t in module.traits) {
        for (var method in t.methods) {
            _in_body(method, resolver);
        }
    }
    for (var function in own.functions) {
        _in_body(function, resolver);
    }
}

_in_body(function: FunctionDef, resolver: _CaseResolver) {
    if (function.body.is_value()) {
        _give_defaults(resolver.state, function.body.value());
        rewrite_block(function.body.value(), resolver);
    }
}

## A local of an enum type declared without a value starts as the enum's
## default.
_give_defaults(state: PassState, block: Block) {
    for (var statement in block.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (!variable.default.is_value()) {
                        variable.default = default_expression(state, variable.ty);
                    }
                }
            }
            Block(inner) => {
                _give_defaults(state, inner);
            }
            Branch(branch) => {
                _give_defaults(state, branch.if_block);
                if (branch.else_block.is_value()) {
                    _give_defaults(state, branch.else_block.value());
                }
            }
            While(loop) => {
                _give_defaults(state, loop.block);
            }
            else => {}
        }
    }
}

## Returns the default value of enum type `ty` as an expression of its
## type, when `ty` is an enum.
##
## @param state the passes' state
## @param ty the type
## @returns the expression
export default_expression(state: PassState, ty: TypeName): Expression? {
    var value = state.enum_default(ty.to_string());
    if (!value.is_value()) {
        return Optional<Expression>.Empty;
    }
    return Optional<Expression>.Value(
        Expression.Cast(
            CastExpression(Expression.IntLiteral(value.value()), ty.copy(), Loc.none(), CastKind.Synthesized)
        )
    );
}

## A case's value as an expression of the enum's type: `Color.Red` is
## `0 as Color`.
_case_expression(e: EnumDef, c: EnumCaseDef, loc: Loc): Expression {
    return Expression.Cast(
        CastExpression(Expression.IntLiteral(c.value), TypeName.named(e.name), loc, CastKind.Synthesized)
    );
}

## Records the reference enums among `structs`.
##
## @param state the passes' state
## @param structs the program's structs
export install_reference_enums(state: PassState, structs: StructDef[]) {
    state.reference_enums.clear();
    for (var st in structs) {
        if (!st.enum_cases.is_value() or state.reference_enums.contains(st.ty.name)) {
            continue;
        }
        var cases = st.enum_cases.value();
        var payload_types = Array<TypeName[]>();
        for (var c in cases) {
            var types = Array<TypeName>();
            for (var (name, _) in c.payload) {
                var field = payload_field(c.name, name);
                var ty = TypeName.auto();
                for (var f in st.field_members) {
                    if (f.name == field) {
                        ty = f.ty.copy();
                        break;
                    }
                }
                types.append(ty);
            }
            payload_types.append(types);
        }
        var copied = Array<EnumCaseDef>();
        for (var c in cases) {
            copied.append(c.copy());
        }
        var params = Array<GenericParam>();
        for (var p in st.generic_params) {
            params.append(p.copy());
        }
        state.reference_enums[st.ty.name] = ReferenceEnum(copied, st.loc, params, payload_types);
    }
}

## Returns the cases of reference enum `ty` and where its name is, or none
## when `ty` is not a reference enum. A value whose type is a type parameter
## `ty` sets to `void` is erased.
##
## @param state the passes' state
## @param ty the type
## @returns the cases and the location
export reference_cases(state: PassState, ty: TypeName): (EnumCaseDef[], Loc)? {
    var found = state.reference_enums.try_get(ty.name);
    if (!found.is_value()) {
        return Optional<(EnumCaseDef[], Loc)>.Empty;
    }
    var r = found.value();
    var cases = Array<EnumCaseDef>();
    ulong i = 0;
    while (i < r.cases.count) {
        var c = r.cases[i].copy();
        var kept = Array<(String, Loc)>();
        ulong v = 0;
        while (v < c.payload.count) {
            bool erased = v < r.payload_types[i].count
                and _is_erased_parameter(r.payload_types[i][v], r.generic_params, ty);
            if (!erased) {
                kept.append(c.payload[v]);
            }
            v += 1;
        }
        c.payload = kept;
        cases.append(c);
        i += 1;
    }
    return Optional<(EnumCaseDef[], Loc)>.Value((cases, r.loc));
}

## Whether `declared` is a type parameter among `params` that `ty`'s
## arguments (or the parameter's default) set to `void`.
_is_erased_parameter(declared: TypeName, params: GenericParam[], ty: TypeName): bool {
    if (declared.sub_types.count > 0 or ty.sub_types.count == 0) {
        return false;
    }
    ulong index = 0;
    while (index < params.count) {
        if (params[index].name == declared.name) {
            var argument = Optional<TypeName>.Empty;
            if (index < ty.sub_types.count) {
                argument = Optional<TypeName>.Value(ty.sub_types[index]);
            } else {
                argument = params[index].default;
            }
            return argument.is_value() and argument.value().name == VOID and argument.value().sub_types.count == 0;
        }
        index += 1;
    }
    return false;
}

## A type as messages show it: demangled, a tuple as `(A, B)`.
_shown_type(ty: TypeName): String {
    if (ty.is_tuple()) {
        var elements = Array<String>();
        for (var t in ty.sub_types) {
            elements.append(_shown_type(t));
        }
        return $"({", ".join(elements)})";
    }
    return demangle_name(ty.to_string());
}

## Records every value type's methods (the functions named `X::m`).
##
## @param module the model
## @param state the passes' state
export install_methods(module: Module, state: PassState) {
    state.enum_methods.clear();
    for (var f in module.functions) {
        var of = method_of(state, f.name);
        if (!of.is_value()) {
            continue;
        }
        var (owner, method) = of.value();
        bool is_static = true;
        if (f.parameters.count > 0) {
            var first = f.parameters[0];
            is_static = !(first.name == "this" and first.ty.name == owner);
        }
        state.enum_methods[method_key(owner, method)] = is_static;
    }
}

## Returns the value type and method a function named by
## `enum_method_name` belongs to.
##
## @param state the passes' state
## @param function the function's name
## @returns the value type's key and the method
export method_of(state: PassState, function: String): (String, String)? {
    var at = function.find("::");
    if (at < 0) {
        return Optional<(String, String)>.Empty;
    }
    var owner = function.substr_bytes(0, at as ulong);
    var method = function.substr_bytes(at as ulong + 2, function.size - at as ulong - 2);
    var key = value_type_key(state, owner);
    if (!key.is_value() or key.value() != owner) {
        return Optional<(String, String)>.Empty;
    }
    return Optional<(String, String)>.Value((owner, method));
}

## Inside an enum's methods, `this` is the value parameter, and a bare call
## of another method of the enum calls it on `this`.
_method_bodies(module: Module, state: PassState) {
    for (var f in module.functions) {
        var of = method_of(state, f.name);
        if (!of.is_value() or !f.body.is_value()) {
            continue;
        }
        var (owner, _) = of.value();
        bool has_this = f.parameters.count > 0 and f.parameters[0].name == "this";
        var locals = HashSet<String>();
        for (var p in f.parameters) {
            locals.insert(p.name);
        }
        rewrite_block(f.body.value(), _MethodBody(state, owner, has_this, locals));
    }
}

struct _MethodBody {
    var state: PassState;
    var owner: String;
    var has_this: bool;
    var locals: HashSet<String>;

    construct(state: PassState, owner: String, has_this: bool, locals: HashSet<String>) {
        this.state = state;
        this.owner = owner;
        this.has_this = has_this;
        this.locals = locals;
    }

    this_value(): Expression {
        return Expression.SymbolRef(SymbolRefExpression("this", TypeName.named(owner), Loc.none()));
    }

    rewrite(e: Expression): Expression {
        match (e) {
            ThisRef => {
                return this_value();
            }
            FunctionCall(call) => {
                if (locals.contains(call.function)) {
                    return e;
                }
                var is_static = method_is_static(state, owner, call.function);
                if (!is_static.is_value()) {
                    return e;
                }
                if (is_static.value()) {
                    call.function = enum_method_name(owner, call.function);
                } else if (has_this) {
                    call.function = enum_method_name(owner, call.function);
                    call.args.insert(0, this_value());
                }
            }
            else => {}
        }
        return e;
    }
}

extend _MethodBody with Rewriter;

## Adds each enum's built-in methods, `name(): String` and
## `static from_value(value: R): Result<E>`, from the cases that survived
## platform selection.
_add_built_in_methods(module: Module) {
    var added = Array<FunctionDef>();
    for (var e in module.enums) {
        var ty = TypeName.named(e.name);
        var items = Array<Statement>();
        for (var c in e.cases) {
            var this_value = Expression.SymbolRef(SymbolRefExpression("this", ty.copy(), Loc.none()));
            items.append(
                _when(_equal(this_value, _case_expression(e, c, Loc.none())), _return_value(_string_value(c.name)))
            );
        }
        items.append(_return_value(_string_value("")));
        added.append(_built_in(e, "name", TypeName.named("String"), [enum_this_parameter(e.name)], items, false));

        var result = $"Result<{e.name}>";
        var items_from = Array<Statement>();
        for (var c in e.cases) {
            var literal = Expression.Cast(
                CastExpression(
                    Expression.IntLiteral(c.value), e.representation.copy(), Loc.none(), CastKind.Synthesized
                )
            );
            var value = Expression.SymbolRef(SymbolRefExpression("value", e.representation.copy(), Loc.none()));
            items_from.append(
                _when(_equal(value, literal), _return_value(_make(result, "ok", _case_expression(e, c, Loc.none()))))
            );
        }
        var message = $"no case of '{demangle_name(e.name)}' has this value";
        items_from.append(_return_value(_make(result, "err", _string_value(message))));
        var parameter = enum_this_parameter(e.name);
        parameter.name = "value";
        parameter.ty = e.representation.copy();
        added.append(_built_in(e, "from_value", TypeName.named(result), [parameter], items_from, true));
    }
    # A checked module's enums have theirs already.
    var known = HashSet<String>();
    for (var f in module.functions) {
        known.insert(f.name);
    }
    for (var f in added) {
        if (!known.contains(f.name)) {
            module.functions.append(f);
        }
    }
}

_built_in(
    e: EnumDef, name: String, ty: TypeName, parameters: Array<VariableDef>, items: Statement[], is_static: bool
): FunctionDef {
    return FunctionDef(
        name = enum_method_name(e.name, name),
        ty = ty,
        parameters = parameters,
        body = Optional<Block>.Value(Block(items = items)),
        is_static = is_static,
        loc = e.loc,
        owner = Loc.none()
    );
}

_return_value(value: Expression): Statement {
    return Statement.Return(ReturnStatement(Optional<Expression>.Value(value), Loc.none()));
}

_string_value(value: String): Expression {
    return Expression.StringLiteral(StringLiteralExpression(value, false, Loc.none()));
}

_when(condition: Expression, then: Statement): Statement {
    return Statement.Branch(Branch(condition, Block(items = [then])));
}

_equal(lhs: Expression, rhs: Expression): Expression {
    return Expression.Binary(BinaryExpression(lhs, rhs, BinaryOp.Equal, Loc.none()));
}

## `Result<E>.method(arg)`.
_make(result: String, method: String, arg: Expression): Expression {
    var receiver = Expression.FunctionCall(FunctionCallExpression(result, Array<Expression>(), Loc.none()));
    return Expression.MethodCall(MethodCallExpression(receiver, method, [arg], Loc.none()));
}

## The type an expression names when it is a type used as a value's
## receiver: `Doc` in `Doc.Line`, `Tree<int>` in `Tree<int>.Leaf`.
_named_type(e: Expression): TypeName? {
    match (e) {
        SymbolRef(symbol) => {
            return Optional<TypeName>.Value(TypeName.named(symbol.id));
        }
        FunctionCall(call) => {
            if (call.args.count == 0) {
                return Optional<TypeName>.Value(parse_type_string(call.function));
            }
        }
        else => {}
    }
    return Optional<TypeName>.Empty;
}

## What `resolve_enum_cases` does at each expression.
struct _CaseResolver {
    var state: PassState;
    var enums: HashMap<String, EnumDef>;
    # The types named as receivers (`Tree<int>` in `Tree<int>.Leaf`), which
    # the walk meets right after the member they are the receiver of.
    var receivers: HashSet<Loc> = HashSet<Loc>();

    construct(state: PassState, enums: HashMap<String, EnumDef>) {
        this.state = state;
        this.enums = enums;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            MethodCall(call) => {
                if (call.this_value is FunctionCall(receiver)) {
                    receivers.insert(receiver.loc);
                }
            }
            MemberRef(member) => {
                if (member.lhs is FunctionCall(receiver)) {
                    receivers.insert(receiver.loc);
                }
            }
            else => {}
        }
        if (e is FunctionCall(call)) {
            return _construction(e, call);
        }
        if (e is MemberRef(member)) {
            return _member(e, member);
        }
        if (e is MethodCall(call)) {
            if (call.this_value is SymbolRef(symbol)) {
                return _static_call(e, call, symbol.id);
            }
            return e;
        }
        if (e is Cast(cast)) {
            if (cast.kind is Static) {
                return _cast(e, cast);
            }
        }
        return e;
    }

    # `Doc(...)`: a reference enum's values are made by its cases only.
    _construction(e: Expression, call: FunctionCallExpression): Expression {
        if (call.loc.is_none() or receivers.contains(call.loc)) {
            return e;
        }
        var ty = parse_type_string(call.function);
        var found = reference_cases(state, ty);
        if (!found.is_value()) {
            return e;
        }
        var (cases, _) = found.value();
        var first = cases.count > 0 ? cases[0].name : "Case";
        state.report(
            error_at(
                $"cannot construct enum '{_shown_type(ty)}' directly: its values are made by its cases", call.loc
            ).with_note($"use a case, such as '{_shown_type(ty)}.{first}'", Optional<Location>.Empty)
        );
        return e;
    }

    _member(e: Expression, member: MemberRefExpression): Expression {
        var rewritten = _reference_case(e, member);
        if (rewritten.is_value()) {
            return rewritten.value();
        }
        if (member.lhs is SymbolRef(symbol)) {
            return _value_case(e, member, symbol.id);
        }
        return e;
    }

    # `Doc.Line`: a reference enum's case that carries no values is a
    # call of its static method, `Doc.Line()`. Empty when `member` names
    # no reference enum.
    _reference_case(e: Expression, member: MemberRefExpression): Expression? {
        var ty = _named_type(member.lhs);
        if (!ty.is_value()) {
            return Optional<Expression>.Empty;
        }
        var found = reference_cases(state, ty.value());
        if (!found.is_value()) {
            return Optional<Expression>.Empty;
        }
        var (cases, declared) = found.value();
        var shown = _shown_type(ty.value());
        var c = Optional<EnumCaseDef>.Empty;
        for (var candidate in cases) {
            if (candidate.name == member.name) {
                c = Optional<EnumCaseDef>.Value(candidate);
                break;
            }
        }
        if (!c.is_value()) {
            state.report(
                error_at(
                    $"no case named '{member.name}' in '{shown}'", member.loc
                ).with_note($"'{shown}' declared here", Optional<Location>.Value(location_of(declared)))
            );
            return Optional<Expression>.Value(e);
        }
        var case = c.value();
        if (case.payload.count == 0) {
            return Optional<Expression>.Value(
                Expression.MethodCall(
                    MethodCallExpression(member.lhs.copy(), member.name, Array<Expression>(), member.loc)
                )
            );
        }
        var names = Array<String>();
        for (var (n, _) in case.payload) {
            names.append(n);
        }
        var s = case.payload.count == 1 ? "" : "s";
        state.report(
            error_at(
                $"case '{case.name}' of '{shown}' takes {case.payload.count} value{s}: '{shown}.{case.name}({", ".join(names)})'",
                member.loc
            ).with_note($"'{case.name}' declared here", Optional<Location>.Value(location_of(case.loc)))
        );
        return Optional<Expression>.Value(e);
    }

    # `Color.Red`: a case of the enum `id` names.
    _value_case(e: Expression, member: MemberRefExpression, id: String): Expression {
        var found = enums.try_get(id);
        if (!found.is_value()) {
            return e;
        }
        var def = found.value();
        for (var c in def.cases) {
            if (c.name == member.name) {
                return _case_expression(def, c, member.loc);
            }
        }
        var read = method_read(state, def.name, member.name, member.loc);
        if (read.is_value()) {
            state.report(read.value());
            return e;
        }
        state.report(
            error_at(
                $"no case named '{member.name}' in '{def.name}'", member.loc
            ).with_note($"'{def.name}' declared here", Optional<Location>.Value(location_of(def.loc)))
        );
        return e;
    }

    # `Color.from_value(1)`: a static method called on the enum `id` names.
    _static_call(e: Expression, call: MethodCallExpression, id: String): Expression {
        var found = enums.try_get(id);
        if (!found.is_value()) {
            return e;
        }
        var def = found.value();
        var is_static = method_is_static(state, def.name, call.method);
        if (!is_static.is_value()) {
            state.report(
                error_at(
                    $"no member named '{call.method}' in '{def.name}'", call.loc
                ).with_note($"'{def.name}' declared here", Optional<Location>.Value(location_of(def.loc)))
            );
            return e;
        }
        if (is_static.value()) {
            return Expression.FunctionCall(
                FunctionCallExpression(enum_method_name(def.name, call.method), call.args, call.loc)
            );
        }
        var first = def.cases.count > 0 ? def.cases[0].name : "Case";
        state.report(
            error_at(
                $"'{call.method}' is not static: call it on a value of '{def.name}', such as '{def.name}.{first}.{call.method}()'",
                call.loc
            )
        );
        return e;
    }

    # `1 as Color`: an integer does not convert to an enum.
    _cast(e: Expression, cast: CastExpression): Expression {
        var found = enums.try_get(cast.ty.to_string());
        if (!found.is_value()) {
            return e;
        }
        var def = found.value();
        var first = def.cases.count > 0 ? def.cases[0].name : "Case";
        state.report(
            error_at(
                $"cannot convert a value to enum '{def.name}' with 'as'", cast.loc
            ).with_note($"name a case instead, such as '{def.name}.{first}'", Optional<Location>.Empty)
        );
        return e;
    }
}

extend _CaseResolver with Rewriter;

## Returns the error for a method of value type `owner` read without a
## call (`c.name`), or none when `method` is not one of its methods.
##
## @param state the passes' state
## @param owner the value type's key
## @param method the method
## @param loc where it is read
## @returns the error
export method_read(state: PassState, owner: String, method: String, loc: Loc): Diagnostic? {
    var is_static = method_is_static(state, owner, method);
    if (!is_static.is_value()) {
        return Optional<Diagnostic>.Empty;
    }
    var call = is_static.value() ? $"'{owner}.{method}(...)'" : $"'{method}()'";
    return Optional<Diagnostic>.Value(error_at($"'{method}' is a method of '{owner}': call it as {call}", loc));
}

## Records the program's traits and which struct declares which, for a
## `match` on a trait value.
##
## @param module the model
## @param state the passes' state
export install_traits(module: Module, state: PassState) {
    state.trait_names.clear();
    for (var t in module.traits) {
        state.trait_names.insert(t.name);
    }
    state.trait_structs.clear();
    for (var st in module.structs) {
        if ((st.ty.is_generic() and st.name == st.ty.name) or st.ty.is_tuple()) {
            continue;
        }
        var traits = Array<String>();
        for (var t in st.traits) {
            traits.append(_canonical(t).to_string());
        }
        var ty = TypeName.named(st.name);
        state.trait_structs.append((ty, _canonical(ty).to_string(), traits));
    }
}

## Returns whether `ty` is a trait used as a type.
##
## @param state the passes' state
## @param ty the type
## @returns true for a trait
export is_trait(state: PassState, ty: TypeName): bool {
    return ty.is_scalar() and !ty.is_pointer() and state.trait_names.contains(ty.name);
}

## Returns whether `name` names an enum.
##
## @param state the passes' state
## @param name the type's spelling
## @returns true for an enum
export is_enum(state: PassState, name: String): bool {
    return state.enum_representations.contains(name);
}

## Whether `ty` is a type a `match` takes literal patterns of.
_is_literal_type(ty: TypeName): bool {
    if (!ty.is_scalar()) {
        return false;
    }
    if (ty.name == "String") {
        return true;
    }
    match (ty.name) {
        "void", "__auto", "f32", "float", "f64", "double" => {
            return false;
        }
        else => {
            return is_integral_name(ty.name);
        }
    }
}

## The case named `name` among `cases`, or the `no case named` error.
_find_case(cases: EnumCaseDef[], name: String, ty: TypeName, declared: Loc, at: Loc): Result<EnumCaseDef, Diagnostic> {
    for (var c in cases) {
        if (c.name == name) {
            return Result<EnumCaseDef, Diagnostic>.Ok(c);
        }
    }
    return Result<EnumCaseDef, Diagnostic>.Err(
        error_at(
            $"no case named '{name}' in '{_shown_type(ty)}'", at
        ).with_note($"'{_shown_type(ty)}' declared here", Optional<Location>.Value(location_of(declared)))
    );
}

## Checks a pattern's binding count against its case.
_check_binding_count(c: EnumCaseDef, count: ulong, extra: Loc?, pattern: Loc): Diagnostic? {
    var expected = c.payload.count;
    var note = $"'{c.name}' declared here";
    if (count > expected) {
        var at = extra.is_value() ? extra.value() : pattern;
        return Optional<Diagnostic>.Value(
            error_at(
                $"too many bindings for case '{c.name}': expected {expected}, have {count}", at
            ).with_note(note, Optional<Location>.Value(location_of(c.loc)))
        );
    }
    if (count < expected) {
        return Optional<Diagnostic>.Value(
            error_at(
                $"too few bindings for case '{c.name}': expected {expected}, have {count}", pattern
            ).with_note(note, Optional<Location>.Value(location_of(c.loc)))
        );
    }
    return Optional<Diagnostic>.Empty;
}

## What `case_value_type` needs to know about the subject's struct.
export trait FieldTypes {
    ## Returns the type of field `name` of the subject's struct, or none.
    ##
    ## @param name the field
    ## @returns its type
    field(name: String): TypeName?;
}

## Returns the type of a value a pattern binds, once the `match`'s subject
## has type `subject`: none while that type is unknown, the error when the
## patterns do not fit the enum.
##
## @param state the passes' state
## @param value the bound value
## @param subject the subject's type
## @param fields the subject struct's fields
## @returns the type, or the error
export case_value_type(
    state: PassState, value: CaseValue, subject: TypeName, fields: FieldTypes
): Result<TypeName?, Diagnostic> {
    if (subject.is_auto() or subject.is_empty()) {
        return Result<TypeName?, Diagnostic>.Ok(Optional<TypeName>.Empty);
    }
    if (value.name == CAST_VALUE and !is_trait(state, subject)) {
        return Result<TypeName?, Diagnostic>.Err(
            error_at(
                $"'as?' converts a value of trait type, not one of '{_shown_type(subject)}': use 'as' to convert it",
                value.choices[0].case_loc
            )
        );
    }
    if (is_trait(state, subject)) {
        # A type pattern binds the value itself, as that type.
        var found = Optional<(TypeName, CaseChoice)>.Empty;
        for (var choice in value.choices) {
            if (!choice.ty.is_value()) {
                return Result<TypeName?, Diagnostic>.Err(
                    error_at(
                        $"a value of trait type '{_shown_type(subject)}' is matched by type: name a struct or trait, as in 'Circle(c)'",
                        choice.case_loc
                    )
                );
            }
            var ty = choice.ty.value();
            if (choice.bindings.count != 1) {
                return Result<TypeName?, Diagnostic>.Err(
                    error_at(
                        $"type pattern '{_shown_type(ty)}' binds one name, the value as a '{_shown_type(ty)}', not {choice.bindings.count}",
                        choice.case_loc
                    )
                );
            }
            if (found.is_value()) {
                var (first, first_choice) = found.value();
                if (!(first == ty)) {
                    var shown_first = first_choice.ty.is_value() ? first_choice.ty.value() : first;
                    return Result<TypeName?, Diagnostic>.Err(
                        error_at(
                            $"'{value.name}' has type '{_shown_type(ty)}' here but '{_shown_type(first)}' in '{_shown_type(shown_first)}'",
                            choice.loc
                        )
                    );
                }
            } else {
                found = Optional<(TypeName, CaseChoice)>.Value((ty, choice));
            }
        }
        if (!found.is_value()) {
            return Result<TypeName?, Diagnostic>.Ok(Optional<TypeName>.Empty);
        }
        var (ty, _) = found.value();
        return Result<TypeName?, Diagnostic>.Ok(Optional<TypeName>.Value(ty));
    }
    var reference = reference_cases(state, subject);
    if (!reference.is_value()) {
        var first = value.choices[0];
        if (is_enum(state, subject.to_string())) {
            return Result<TypeName?, Diagnostic>.Err(
                error_at($"case '{first.case}' of '{_shown_type(subject)}' carries no values to bind", first.loc)
            );
        }
        if (_is_literal_type(subject)) {
            return Result<TypeName?, Diagnostic>.Err(
                error_at(
                    $"'{first.case}' is not a literal or a constant: a 'match' on '{_shown_type(subject)}' takes literals, ranges and module-scope constants",
                    first.case_loc
                )
            );
        }
        return Result<TypeName?, Diagnostic>.Err(
            error_at(
                $"cannot match on a value of '{_shown_type(subject)}': 'match' needs an enum, an integer, 'char', 'bool' or 'String'",
                _expression_loc(value.subject)
            )
        );
    }
    var (cases, declared) = reference.value();
    var found = Optional<(TypeName, CaseChoice)>.Empty;
    for (var choice in value.choices) {
        var lookup = _find_case(cases, choice.case, subject, declared, choice.case_loc);
        if (lookup is Err(e)) {
            return Result<TypeName?, Diagnostic>.Err(e);
        }
        var c = lookup.value();
        var extra = choice.bindings.count > c.payload.count ?
            Optional<Loc>.Value(choice.bindings[c.payload.count]) :
            Optional<Loc>.Empty;
        var count_error = _check_binding_count(c, choice.bindings.count, extra, choice.case_loc);
        if (count_error.is_value()) {
            return Result<TypeName?, Diagnostic>.Err(count_error.value());
        }
        var (payload_name, _) = c.payload[choice.index];
        var field = fields.field(payload_field(c.name, payload_name));
        if (!field.is_value()) {
            return Result<TypeName?, Diagnostic>.Ok(Optional<TypeName>.Empty);
        }
        var ty = field.value();
        if (found.is_value()) {
            var (first, first_choice) = found.value();
            if (!(first == ty)) {
                return Result<TypeName?, Diagnostic>.Err(
                    error_at(
                        $"'{value.name}' has type '{_shown_type(ty)}' here but '{_shown_type(first)}' in '{first_choice.case}'",
                        choice.loc
                    )
                );
            }
        } else {
            found = Optional<(TypeName, CaseChoice)>.Value((ty, choice));
        }
    }
    if (!found.is_value()) {
        return Result<TypeName?, Diagnostic>.Ok(Optional<TypeName>.Empty);
    }
    var (ty, _) = found.value();
    return Result<TypeName?, Diagnostic>.Ok(Optional<TypeName>.Value(ty));
}

## Returns the call of method `method` on a value of value type `owner` as
## a call of its function: `c.name()` is `Color::name(c)`. Reports a
## method the type lacks, or a static one called on a value, and returns
## none then.
##
## @param state the passes' state
## @param owner the value type's key
## @param method the method
## @param value the value called on
## @param args the call's arguments
## @param loc where the call is
## @returns the call
export call_on_value(
    state: PassState, owner: String, method: String, value: Expression, args: Expression[], loc: Loc
): Expression? {
    var is_static = method_is_static(state, owner, method);
    if (!is_static.is_value()) {
        state.report(error_at($"no member named '{method}' in '{owner}'", loc));
        return Optional<Expression>.Empty;
    }
    if (is_static.value()) {
        state.report(error_at($"'{method}' is a static method of '{owner}': call it as '{owner}.{method}(...)'", loc));
        return Optional<Expression>.Empty;
    }
    var all = Array<Expression>();
    all.append(value);
    all.append_all(args);
    return Optional<Expression>.Value(
        Expression.FunctionCall(FunctionCallExpression(enum_method_name(owner, method), all, loc))
    );
}
