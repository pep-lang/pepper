## Conversions between plain and thread-safe function types:
## `shared_functions`.
##
## Wherever a function value flows into a typed slot (a variable's
## initializer, an assignment, an argument, a return), a named function or
## a closure creation whose captures are all thread-safe is retyped to a
## `shared` slot's type; a `shared` value in a plain slot of the same
## signature is wrapped in a plain closure that forwards to it; and a value
## with no state in a C function pointer slot becomes a function's address.

import [Location] from compiler.diagnostic;
import text;
import [is_numeric_type] from "arithmetic";
import [checked_decls, unit_decls] from "checked";
import [CALL_METHOD, closure_struct, field_def, is_closure_struct, THIS_FIELD] from "closures";
import "common";
import [RECEIVER_FIELD] from "function_references";
import [Loc] from "loc";
import [
    BinaryOp,
    Block,
    CastExpression,
    CastKind,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    FunctionPointerExpression,
    GenericParam,
    InvokeExpression,
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
import [ThreadSafeStructs, unsafe_part_in] from "shared_types";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [apply_synthesized, finish] from "synthesize";
import [FUNCTION, is_pointer_name, parse_type_string, SHARED_FUNCTION, VOID] from "type_name";
import [Rewriter, rewrite_children] from "walk";

## The field of an adapter holding the `shared` value it forwards to.
const _INNER_FIELD = "__inner";

## Applies the conversions between plain and `shared` function types, and
## reports a C function pointer type whose signature C cannot pass. Runs
## once every type is final, before `check_function_types`.
##
## @param module the model, changed in place
## @param state the passes' state, which takes the error
export shared_functions(module: Module, state: PassState) {
    _check_c_signatures(module, state);
    var converter = _SharedFunctions(module, state);
    # A checked declaration's conversions were applied with its unit.
    var own = unit_decls(module);
    for (var function in own.functions) {
        converter.owned_by(function.name);
        converter.function(function, Optional<TypeName>.Empty);
    }
    for (var st in own.structs) {
        if ((st.ty.is_generic() and st.name == st.ty.name) or st.ty.is_function_type() or st.ty.is_weak()) {
            continue;
        }
        var current = Optional<TypeName>.Value(st.ty);
        for (var constructor in st.constructors) {
            converter.owned_by($"{st.name}.{constructor.name}");
            converter.function(constructor, current);
        }
        for (var method in st.method_members) {
            converter.owned_by($"{st.name}.{method.name}");
            converter.function(method, current);
        }
    }
    converter.current = Optional<TypeName>.Empty;
    for (var g in module.globals) {
        if (module.checked.globals.contains(g.name)) {
            continue;
        }
        converter.owned_by(g.name);
        if (g.default.is_value()) {
            var value = converter.expression(g.default.value());
            g.default = Optional<Expression>.Value(converter.convert(value, g.ty, "stored as"));
        }
    }
    for (var st in converter.added) {
        module.structs.append(st);
    }
    for (var f in converter.added_functions) {
        module.functions.append(f);
    }
}

## This function type with the same signature, thread-safe or plain; any
## other type unchanged.
_with_sharing(ty: TypeName, shared: bool): TypeName {
    if (!ty.is_function_type()) {
        return ty;
    }
    return TypeName(
        name = shared ? SHARED_FUNCTION : FUNCTION, sub_types = ty.sub_types, flags = ty.flags, labels = ty.labels
    );
}

## The plain function type with a C function pointer type's signature.
_extern_as_function(ty: TypeName): TypeName? {
    if (!ty.is_extern_function_type()) {
        return Optional<TypeName>.Empty;
    }
    return Optional<TypeName>.Value(TypeName.with_args(FUNCTION, ty.sub_types));
}

## Same parameter and return types, whether each side is `shared` or not.
_same_signature(a: TypeName, b: TypeName): bool {
    return _canonical(_with_sharing(a, false)).to_string() == _canonical(_with_sharing(b, false)).to_string();
}

## A type some passes carry as a flat name (`__function<void>`), parsed.
_parsed(ty: TypeName): TypeName {
    if (ty.sub_types.count == 0 and ty.name.contains("<") and ty.name.ends_with(">")) {
        return parse_type_string(ty.name);
    }
    return ty;
}

## How a capture reads in a message, and what holds it.
_capture_text(name: String): (String, String) {
    if (name == RECEIVER_FIELD) {
        return ("method value", "its receiver");
    }
    if (name == THIS_FIELD) {
        return ("closure", "'this'");
    }
    return ("closure", $"'{name}'");
}

## Where a declared type was written, if it was.
_declared_at(type_loc: Loc): Location? {
    if (type_loc.is_none()) {
        return Optional<Location>.Empty;
    }
    return Optional<Location>.Value(location_of(type_loc));
}

struct _SharedFunctions {
    var table: StructTable;
    var safe: ThreadSafeStructs;
    var state: PassState;
    ## Free function → parameter types.
    var functions: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    ## Concrete struct constructor → parameter types.
    var constructors: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    ## Concrete struct → method → parameter types.
    var methods: HashMap<String, HashMap<String, Array<TypeName>>> = HashMap<String, HashMap<String, Array<TypeName>>>();
    ## Closure struct (by name and by type) → its capture fields.
    var captures: HashMap<String, Array<VariableDef>> = HashMap<String, Array<VariableDef>>();
    ## Closure struct (by name and by type) → its `__call` method.
    var calls: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    var added: Array<StructDef> = Array<StructDef>();
    ## Free functions made from closures converted to C function pointers.
    var added_functions: Array<FunctionDef> = Array<FunctionDef>();
    ## The declaration being walked, and how many adapters it made.
    var owner: String = "";
    var made: ulong = 0;
    var current: TypeName? = Optional<TypeName>.Empty;
    ## The externs' parameter types, which a function of the same name's
    ## give way to.
    var externs: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    var module: Module;
    var _checked: bool;
    # The checked structs taken in (`_checked_struct`), by type.
    var _taken: HashSet<String> = HashSet<String>();

    construct(module: Module, state: PassState) {
        this.state = state;
        this.module = module;
        _checked = module.checked.structs.count > 0 or module.checked.functions.count > 0;
        table = StructTable(module, memo = state.trait_types_memo());
        safe = ThreadSafeStructs(module, state);
        # The unit's own declarations; a checked one is taken in when a
        # lookup names it (`checked_decls`).
        var own = unit_decls(module);
        for (var f in own.functions) {
            if (!f.is_generic_func) {
                functions[f.name] = _parameter_types(f.parameters);
            }
        }
        for (var e in module.externs) {
            externs[e.name] = _parameter_types(e.parameters);
        }
        for (var st in own.structs) {
            _add_struct(st);
        }
    }

    # Takes in struct `st`: a closure's call and captures, a concrete
    # struct's constructors and methods.
    _add_struct(st: StructDef) {
        if (is_closure_struct(st.name)) {
            for (var m in st.method_members) {
                if (m.name == CALL_METHOD) {
                    var call = m.copy();
                    calls[st.ty.to_string()] = call;
                    calls[st.name] = call;
                    break;
                }
            }
            var fields = Array<VariableDef>();
            for (var f in st.field_members) {
                if (!f.name.starts_with("__") or f.name == THIS_FIELD or f.name == RECEIVER_FIELD) {
                    fields.append(f);
                }
            }
            captures[st.ty.to_string()] = fields;
            captures[st.name] = fields;
        }
        if (st.ty.is_generic() and st.name == st.ty.name) {
            return;
        }
        for (var c in st.constructors) {
            constructors[c.name] = _parameter_types(c.parameters);
        }
        var by_name = HashMap<String, Array<TypeName>>();
        for (var m in st.method_members) {
            by_name[m.name] = _parameter_types(m.parameters);
        }
        methods[st.name] = by_name;
    }

    # Takes in the checked struct of type `key`, once, unless the unit's own
    # entry for it stands.
    _checked_struct(key: String) {
        if (!_checked or methods.contains(key) or captures.contains(key) or !_taken.insert(key)) {
            return;
        }
        var st = checked_decls(module, state).structs.try_get(key);
        if (st.is_value()) {
            _add_struct(st.value());
        }
    }

    # The captures of closure struct `closure`.
    _captures(closure: String): Array<VariableDef>? {
        _checked_struct(closure);
        return captures.try_get(closure);
    }

    # The parameter types of the free function, extern or constructor a
    # call names.
    _params(name: String): Array<TypeName>? {
        var found = externs.try_get(name);
        if (found.is_value()) {
            return found;
        }
        found = functions.try_get(name);
        if (found.is_value()) {
            return found;
        }
        if (_checked) {
            var f = checked_decls(module, state).functions.try_get(name);
            if (f.is_value()) {
                return Optional<Array<TypeName>>.Value(_parameter_types(f.value().parameters));
            }
        }
        found = constructors.try_get(name);
        if (found.is_value() or !_checked) {
            return found;
        }
        var c = checked_decls(module, state).constructors.try_get(name);
        return c.is_value() ?
            Optional<Array<TypeName>>.Value(_parameter_types(c.value().parameters)) :
            Optional<Array<TypeName>>.Empty;
    }

    owned_by(owner: String) {
        this.owner = owner;
        made = 0;
    }

    ## `value` flows into a slot of type `expected`: returns what replaces
    ## it.
    convert(value: Expression, expected_type: TypeName, site: String): Expression {
        var expected = _parsed(expected_type);
        if (value is WithSubject(subject)) {
            subject.body = convert(subject.body, expected, site);
            return value;
        }
        if (expected.is_extern_function_type()) {
            if (value is Ternary(node)) {
                node.true_expr = convert(node.true_expr, expected, site);
                node.false_expr = convert(node.false_expr, expected, site);
                return value;
            }
            return to_extern(value, expected, site);
        }
        if (!expected.is_function_type()) {
            return value;
        }
        # Each arm converts on its own.
        if (value is Ternary(node)) {
            node.true_expr = convert(node.true_expr, expected, site);
            node.false_expr = convert(node.false_expr, expected, site);
            return value;
        }
        if (expected.is_shared_function_type()) {
            to_shared(value, expected, site);
            return value;
        }
        var actual = static_type_of(value, table, current, state);
        if (!actual.is_value()) {
            return value;
        }
        var parsed = _parsed(actual.value());
        if (parsed.is_shared_function_type() and _same_signature(parsed, expected)) {
            return adapter(value, parsed, expected, _expression_loc(value));
        }
        return value;
    }

    ## Retypes a value that is thread-safe by construction to the `shared`
    ## function type `expected`, checking a closure's captures.
    to_shared(value: Expression, expected: TypeName, site: String) {
        match (value) {
            FunctionRef(node) => {
                var ty = _parsed(node.ty);
                if (_same_signature(ty, expected)) {
                    node.ty = _with_sharing(ty, true);
                }
            }
            MakeClosure(node) => {
                var ty = _parsed(node.ty);
                if (_same_signature(ty, expected)) {
                    if (!ty.is_shared_function_type()) {
                        check_captures(node.closure, expected, node.loc, site);
                    }
                    node.ty = _with_sharing(ty, true);
                }
            }
            else => {}
        }
    }

    ## Replaces a value with no state by the address of a function, typed
    ## as the C function pointer type `expected`. Any other value is left
    ## for `check_function_types` to report.
    to_extern(value: Expression, expected: TypeName, site: String): Expression {
        var signature = _extern_as_function(expected);
        if (!signature.is_value()) {
            return value;
        }
        var loc = _expression_loc(value);
        String function = "";
        match (value) {
            FunctionRef(node) => {
                if (!_same_signature(_parsed(node.ty), signature.value())) {
                    return value;
                }
                function = node.function;
            }
            MakeClosure(node) => {
                if (!_same_signature(_parsed(node.ty), signature.value())) {
                    return value;
                }
                var fields = _captures(node.closure);
                if (fields.is_value() and fields.value().count > 0) {
                    var capture = fields.value()[0];
                    var at = capture.loc.is_none() ? node.loc : capture.loc;
                    var (what, captured) = _capture_text(capture.name);
                    state.report(
                        error_at(
                            $"{what} {site} C function pointer type '{expected.display()}' captures {captured}; a C function pointer cannot hold captured values",
                            at
                        ).with_note(
                            "pass what the callback needs through the C function's context argument instead",
                            _declared_at(capture.type_loc)
                        )
                    );
                    return value;
                }
                _checked_struct(node.closure);
                var call = calls.try_get(node.closure);
                if (!call.is_value()) {
                    return value;
                }
                # A free function: a `.` in the name would read as a method.
                var name = $"{_spelled(node.closure)}_c_function";
                bool exists = false;
                for (var f in added_functions) {
                    if (f.name == name) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    var copied = call.value().copy();
                    copied.name = name;
                    copied.parent = Optional<String>.Empty;
                    copied.is_static = false;
                    added_functions.append(copied);
                }
                function = name;
            }
            else => {
                return value;
            }
        }
        return Expression.Cast(
            CastExpression(
                Expression.FunctionPointer(FunctionPointerExpression(Optional<TypeName>.Empty, function, loc)),
                expected,
                loc,
                CastKind.Synthesized
            )
        );
    }

    ## Every value closure `closure` captures must be thread-safe.
    check_captures(closure: String, expected: TypeName, closure_loc: Loc, site: String) {
        var fields = _captures(closure);
        if (!fields.is_value()) {
            return;
        }
        for (var capture in fields.value()) {
            if (!unsafe_part_in(capture.ty, safe).is_value()) {
                continue;
            }
            var at = capture.loc.is_none() ? closure_loc : capture.loc;
            var (what, captured) = _capture_text(capture.name);
            state.report(
                error_at(
                    $"{what} {site} '{expected.display()}' captures {captured} of type '{capture.ty.display()}', which is not thread-safe",
                    at
                ).with_note(
                    "capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct",
                    _declared_at(capture.type_loc)
                )
            );
            return;
        }
    }

    ## A new plain closure of type `to` that holds `inner` (of the `shared`
    ## type `from`) and forwards every call to it.
    adapter(inner: Expression, from: TypeName, to: TypeName, loc: Loc): Expression {
        var (base, ty) = _owned_closure_name(state, owner, made, loc);
        made += 1;
        var parameters = Array<VariableDef>();
        var forwarded = Array<Expression>();
        ulong i = 0;
        for (var param_ty in to.function_params()) {
            var name = $"__arg{i}";
            var param = field_def(name, param_ty, Optional<Expression>.Empty, loc);
            param.kind = Kind.Param;
            parameters.append(param);
            forwarded.append(Expression.SymbolRef(SymbolRefExpression(name, param_ty, loc)));
            i += 1;
        }
        var returned = to.function_return();
        var ret = returned.is_value() ? returned.value() : TypeName.void();
        var callee = Expression.MemberRef(MemberRefExpression(Expression.ThisRef, _INNER_FIELD, loc));
        var call = Expression.Invoke(InvokeExpression(callee, forwarded));
        var items = Array<Statement>();
        if (ret.to_string() == VOID) {
            items.append(Statement.Expression(call));
        } else {
            items.append(Statement.Return(ReturnStatement(Optional<Expression>.Value(call), loc)));
        }
        var held = [field_def(_INNER_FIELD, from, Optional<Expression>.Empty, loc)];
        var st = closure_struct(base, ty, Array<GenericParam>(), held, parameters, ret, Block(items = items), loc);
        apply_synthesized(st);
        var failed = finish(state, st);
        if (failed.is_value()) {
            state.report(error_at(failed.value(), loc));
            return inner;
        }
        # `release_field_refs` has run: release the held value here.
        for (var m in st.method_members) {
            if (m.name == "__dtor" and m.body.is_value()) {
                var field = Expression.MemberRef(MemberRefExpression(Expression.ThisRef, _INNER_FIELD, Loc.none()));
                m.body.value().items.append(
                    Statement.Expression(
                        Expression.MethodCall(MethodCallExpression(field, "__release", Array<Expression>(), Loc.none()))
                    )
                );
                break;
            }
        }
        added.append(st);
        return Expression.MakeClosure(
            MakeClosureExpression(
                Expression.FunctionCall(FunctionCallExpression(ty.to_string(), [inner], loc)), ty.to_string(), to, loc
            )
        );
    }

    arguments(params: TypeName[], args: Expression[]) {
        ulong i = 0;
        while (i < params.count and i < args.count) {
            args[i] = convert(args[i], params[i], "passed as");
            i += 1;
        }
    }

    ## Children first, so a nested call's arguments are converted before
    ## the enclosing node reads their types.
    rewrite(e: Expression): Expression {
        return expression(e);
    }

    expression(e: Expression): Expression {
        var expr = rewrite_children(e, this);
        match (expr) {
            FunctionCall(node) => {
                var params = _params(node.function);
                if (params.is_value()) {
                    arguments(params.value(), node.args);
                }
            }
            MethodCall(node) => {
                var receiver = static_type_of(node.this_value, table, current, state);
                if (receiver.is_value()) {
                    _checked_struct(receiver.value().to_string());
                    var by_name = methods.try_get(receiver.value().to_string());
                    if (by_name.is_value()) {
                        var params = by_name.value().try_get(node.method);
                        if (params.is_value()) {
                            arguments(params.value(), node.args);
                        }
                    }
                }
            }
            Invoke(node) => {
                var callee = static_type_of(node.callee, table, current, state);
                if (callee.is_value()) {
                    var fn_ty = _parsed(callee.value());
                    if (fn_ty.is_function_type()) {
                        arguments(fn_ty.function_params(), node.args);
                    }
                }
            }
            Binary(node) => {
                if (node.op == BinaryOp.Assign) {
                    var lhs_type = static_type_of(node.lhs, table, current, state);
                    if (lhs_type.is_value()) {
                        node.rhs = convert(node.rhs, lhs_type.value(), "stored as");
                    }
                }
            }
            else => {}
        }
        return expr;
    }

    block(body: Block, returns: TypeName) {
        ulong i = 0;
        while (i < body.items.count) {
            match (body.items[i]) {
                Expression(e) => {
                    body.items[i] = Statement.Expression(expression(e));
                }
                Block(inner) => {
                    block(inner, returns);
                }
                Declaration(declaration) => {
                    if (declaration is Variable(var_def)) {
                        if (var_def.default.is_value()) {
                            var value = expression(var_def.default.value());
                            var_def.default = Optional<Expression>.Value(convert(value, var_def.ty, "stored as"));
                        }
                    }
                }
                Branch(branch) => {
                    branch.condition = expression(branch.condition);
                    block(branch.if_block, returns);
                    if (branch.else_block.is_value()) {
                        block(branch.else_block.value(), returns);
                    }
                }
                While(loop) => {
                    loop.condition = expression(loop.condition);
                    block(loop.block, returns);
                }
                Return(ret) => {
                    if (ret.expr.is_value()) {
                        var value = expression(ret.expr.value());
                        ret.expr = Optional<Expression>.Value(convert(value, returns, "returned as"));
                    }
                }
                else => {}
            }
            i += 1;
        }
    }

    function(f: FunctionDef, current: TypeName?) {
        if (f.is_generic_func) {
            return;
        }
        this.current = current;
        if (f.body.is_value()) {
            block(f.body.value(), f.ty);
        }
    }
}

extend _SharedFunctions with Rewriter;

_parameter_types(parameters: VariableDef[]): TypeName[] {
    var out = Array<TypeName>();
    for (var p in parameters) {
        out.append(p.ty);
    }
    return out;
}

## `name` with every character but an ASCII letter or digit as `_`.
_spelled(name: String): String {
    var out = Array<String>();
    var start: ulong = 0;
    ulong i = 0;
    while (i < name.size) {
        var b = name.byte_at(i);
        if (b.is_alphanumeric() and b < 128) {
            i += 1;
            continue;
        }
        out.append(name.substr_bytes(start, i - start));
        out.append("_");
        var (point, length) = text.Utf8.code_point_at(name, i);
        i += length;
        start = i;
    }
    out.append(name.substr_bytes(start, name.size - start));
    return "".join(out);
}

## Whether C can pass or return a value of type `ty` directly: a number,
## `bool`, a pointer, or another C function pointer.
_is_c_type(ty: TypeName, state: PassState): bool {
    var name = _canonical(ty).to_string();
    return is_numeric_type(state, name) or is_pointer_name(name) or _parsed(ty).is_extern_function_type();
}

## The first part of a C function pointer type nested anywhere in `ty`
## that C cannot pass, with the C function pointer type it is part of.
_non_c_part(declared: TypeName, state: PassState): (TypeName, TypeName)? {
    var ty = _parsed(declared);
    for (var sub in ty.sub_types) {
        var found = _non_c_part(sub, state);
        if (found.is_value()) {
            return found;
        }
    }
    if (!ty.is_extern_function_type()) {
        return Optional<(TypeName, TypeName)>.Empty;
    }
    var ret = ty.function_return();
    if (ret.is_value() and ret.value().to_string() != VOID and !_is_c_type(ret.value(), state)) {
        return Optional<(TypeName, TypeName)>.Value((ret.value(), ty));
    }
    for (var p in ty.function_params()) {
        if (!_is_c_type(p, state)) {
            return Optional<(TypeName, TypeName)>.Value((p, ty));
        }
    }
    return Optional<(TypeName, TypeName)>.Empty;
}

## Every local variable declared in `body`, nested blocks included.
_locals(body: Block, out: VariableDef[]) {
    for (var statement in body.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(var_def)) {
                    out.append(var_def);
                }
            }
            Block(inner) => {
                _locals(inner, out);
            }
            Branch(branch) => {
                _locals(branch.if_block, out);
                if (branch.else_block.is_value()) {
                    _locals(branch.else_block.value(), out);
                }
            }
            While(loop) => {
                _locals(loop.block, out);
            }
            else => {}
        }
    }
}

_function_variables(f: FunctionDef, out: VariableDef[]) {
    for (var p in f.parameters) {
        out.append(p);
    }
    if (f.body.is_value()) {
        _locals(f.body.value(), out);
    }
}

## Reports the first C function pointer type, wherever a variable, field
## or parameter declares one, whose signature has a type C cannot pass.
_check_c_signatures(module: Module, state: PassState) {
    var variables = Array<VariableDef>();
    # A checked declaration's were checked with its unit.
    var own = unit_decls(module);
    for (var f in own.functions) {
        if (!f.is_generic_func) {
            _function_variables(f, variables);
        }
    }
    for (var st in own.structs) {
        if (st.generic_params.count > 0) {
            continue;
        }
        for (var field in st.field_members) {
            variables.append(field);
        }
        for (var m in st.method_members) {
            _function_variables(m, variables);
        }
        for (var c in st.constructors) {
            _function_variables(c, variables);
        }
    }
    for (var e in module.externs) {
        for (var p in e.parameters) {
            variables.append(p);
        }
    }
    for (var g in module.globals) {
        variables.append(g);
    }
    for (var v in variables) {
        var found = _non_c_part(v.ty, state);
        if (found.is_value()) {
            var (part, whole) = found.value();
            state.report(
                error_at(
                    $"C function pointer type '{whole.display()}' cannot use '{part.display()}'; C passes only numbers, 'bool' and pointers",
                    v.type_loc.is_none() ? v.loc : v.type_loc
                )
            );
            return;
        }
    }
}
