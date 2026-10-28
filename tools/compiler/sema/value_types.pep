## Extensions of value types (numbers, `char`, `bool` and enums whose
## cases carry no values). A value
## type's methods are free functions `X::m`, as an enum's own are; an
## instance method takes the value as a first parameter `this`.
## `lower_extensions` turns each such extension's methods, and the trait
## defaults its conformances need, into those functions, and leaves the
## extension with no methods.

import [Diagnostic, Location] from compiler.diagnostic;
import [demangle_name] from compiler.link;
import [enum_method_name, enum_this_parameter] from "builder";
import [unit_decls] from "checked";
import [TRAIT_SELF] from "closures";
import "common";
import [
    Block,
    Declaration,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    Module,
    Statement,
    StaticItem,
    TraitDef,
    TypeName
] from "model";
import [set_name] from "names";
import "replace_types";
import [method_key, PassState] from "state";
import [parse_type_string, replace_map] from "type_name";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## The trait member through which only trait values are copied, which a
## value type never is.
export const COPY_TRAIT_METHOD = "_pep_copy_trait";

## Returns the name a value type's methods are filed under: the enum's
## name, or a number type's canonical spelling (`i32` for `int`); none for
## any other type.
##
## @param state the passes' state, which knows the enums
## @param name the type's name
## @returns the key
export value_type_key(state: PassState, name: String): String? {
    if (state.enum_representations.contains(name)) {
        return Optional<String>.Value(name);
    }
    match (name) {
        "int" => {
            return Optional<String>.Value("i32");
        }
        "uint" => {
            return Optional<String>.Value("u32");
        }
        "long" => {
            return Optional<String>.Value("i64");
        }
        "ulong" => {
            return Optional<String>.Value("u64");
        }
        "short" => {
            return Optional<String>.Value("i16");
        }
        "ushort" => {
            return Optional<String>.Value("u16");
        }
        "char" => {
            return Optional<String>.Value("i8");
        }
        "byte" => {
            return Optional<String>.Value("u8");
        }
        "float" => {
            return Optional<String>.Value("f32");
        }
        "double" => {
            return Optional<String>.Value("f64");
        }
        "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f32", "f64", "bool" => {
            return Optional<String>.Value(name);
        }
        else => {
            return Optional<String>.Empty;
        }
    }
}

## Returns whether `ty` is a value type an extension may target.
##
## @param state the passes' state
## @param ty the type
## @returns true for a number type, `char`, `bool` or a value enum
export is_value_type(state: PassState, ty: TypeName): bool {
    return ty.sub_types.count == 0 and value_type_key(state, ty.name).is_value();
}

## Turns every extension of a value type into functions. Errors go to `state`.
##
## @param module the model, changed in place
## @param state the passes' state
export lower_extensions(module: Module, state: PassState) {
    var added = Array<FunctionDef>();
    for (var ext in module.extensions) {
        # Lowered by an earlier run (a checked runtime): its methods are
        # functions already, and checking its traits again would find none.
        if (ext.resolved.is_value() or !is_value_type(state, ext.target)) {
            continue;
        }
        var key = value_type_key(state, ext.target.name).value();
        var shown = demangle_name(ext.target.name);
        bool is_enum = state.enum_representations.contains(ext.target.name);
        # An enum declares its own methods; an extension of one only
        # declares conformances.
        if (is_enum and ext.traits.count == 0) {
            state.report(
                error_at($"cannot extend enum '{shown}' without a trait: declare its methods inside the enum", ext.loc)
            );
            return;
        }
        if (!is_enum) {
            for (var m in ext.methods) {
                var error = _number_operator_error(state, m, shown);
                if (error.is_value()) {
                    state.report(error.value());
                    return;
                }
            }
        }
        var functions = Array<FunctionDef>();
        for (var m in ext.methods) {
            functions.append(_as_function(m, key));
        }
        for (var trait_name in ext.traits) {
            var found = Optional<TraitDef>.Empty;
            for (var t in module.traits) {
                if (t.name == trait_name.name) {
                    found = Optional<TraitDef>.Value(t);
                    break;
                }
            }
            if (!found.is_value()) {
                continue;
            }
            var def = found.value();
            var map = Array<(String, TypeName)>();
            ulong p = 0;
            while (p < def.generic_params.count and p < trait_name.sub_types.count) {
                map.append((def.generic_params[p].name, trait_name.sub_types[p].copy()));
                p += 1;
            }
            map.append(("this", TypeName.named(key)));
            map.append((TRAIT_SELF, TypeName.named(key)));
            for (var required in def.methods) {
                if (required.name == COPY_TRAIT_METHOD) {
                    continue;
                }
                var set = set_name(required.name);
                var wanted = Array<TypeName>();
                for (var parameter in required.parameters) {
                    var ty = parameter.ty.copy();
                    replace_map(ty, map);
                    wanted.append(_canonical(ty));
                }
                bool has = false;
                for (var m in ext.methods) {
                    if (set_name(m.name) != set
                        or m.is_static != required.is_static
                        or m.parameters.count != wanted.count) {
                        continue;
                    }
                    bool all = true;
                    ulong i = 0;
                    while (i < wanted.count) {
                        if (!(_canonical(m.parameters[i].ty) == wanted[i])) {
                            all = false;
                            break;
                        }
                        i += 1;
                    }
                    if (all) {
                        has = true;
                        break;
                    }
                }
                if (!has) {
                    var name = enum_method_name(key, set);
                    for (var f in functions) {
                        if (f.name == name and f.trait_default.is_value()) {
                            has = true;
                            break;
                        }
                    }
                }
                if (has) {
                    continue;
                }
                if (!required.body.is_value()) {
                    state.report(
                        error_at(
                            $"'{shown}' does not implement '{set}', required by trait '{trait_name.display()}'", ext.loc
                        ).with_note($"'{set}' declared here", Optional<Location>.Value(location_of(required.loc)))
                    );
                    return;
                }
                # The trait's default, for this type.
                var copy = required.copy();
                replace_map(copy.ty, map);
                for (var param in copy.generic_params) {
                    for (var bound in param.bounds) {
                        replace_map(bound.ty, map);
                    }
                }
                for (var parameter in copy.parameters) {
                    replace_map(parameter.ty, map);
                }
                if (copy.body.is_value()) {
                    substitute_block(copy.body.value(), map);
                }
                copy.name = set;
                copy.owner = ext.loc;
                var function = _as_function(copy, key);
                var names = Array<String>();
                for (var m in def.methods) {
                    names.append(set_name(m.name));
                }
                function.trait_default = Optional<Array<String>>.Value(names);
                functions.append(function);
            }
        }
        added.append_all(functions);
        ext.methods = Array<FunctionDef>();
        # Nothing for `resolve_resolvables` or `apply_extensions` to find:
        # the methods are functions now.
        ext.resolved = Optional<String>.Value(key);
    }
    module.functions.append_all(added);
}

## Why operator `m` cannot be declared in an extension of number type
## `shown`, or none when it can (or is not an operator).
_number_operator_error(state: PassState, m: FunctionDef, shown: String): Diagnostic? {
    var name = set_name(m.name);
    if (name.is_empty) {
        return Optional<Diagnostic>.Empty;
    }
    ulong i = 0;
    while (i < name.size) {
        if (!_is_ascii_punctuation(name.byte_at(i))) {
            return Optional<Diagnostic>.Empty;
        }
        i += 1;
    }
    if (m.is_static or m.parameters.count != 1) {
        return Optional<Diagnostic>.Value(
            error_at(
                $"operator '{name}' in an extension of '{shown}' must take one operand: the '{shown}' is the left operand",
                m.loc
            )
        );
    }
    var operand = m.parameters[0];
    if (operand.ty.is_pointer()
        or is_value_type(state, operand.ty)
        or state.enum_representations.contains(operand.ty.to_string())) {
        var at = operand.type_loc.is_none() ? m.loc : operand.type_loc;
        return Optional<Diagnostic>.Value(
            error_at(
                $"operator '{name}' of '{shown}' cannot take an operand of type '{operand.ty.display()}': the built-in operator applies",
                at
            )
        );
    }
    return Optional<Diagnostic>.Empty;
}

_is_ascii_punctuation(b: u8): bool {
    return (b >= 33 and b <= 47) or (b >= 58 and b <= 64) or (b >= 91 and b <= 96) or (b >= 123 and b <= 126);
}

## Method `m` of value type `key` as its function `key::m` (the name
## `enum_method_name` gives it).
_as_function(m: FunctionDef, key: String): FunctionDef {
    var f = m.copy();
    f.name = enum_method_name(key, m.name);
    f.parent = Optional<String>.Empty;
    if (!m.is_static) {
        f.parameters.insert(0, enum_this_parameter(key));
    }
    return f;
}

## Turns a static call on a value type written by its name (`int.zero()`)
## into its function, `i32::zero()`; an enum's are turned by `resolve_enum_cases`.
##
## @param module the model, changed in place
## @param state the passes' state
export resolve_static_calls(module: Module, state: PassState) {
    bool any = false;
    for (var f in module.functions) {
        var at = f.name.find("::");
        if (at >= 0 and !state.enum_representations.contains(f.name.substr_bytes(0, at as ulong))) {
            any = true;
            break;
        }
    }
    if (!any) {
        return;
    }
    for_each_expression(module, _StaticCalls(state));
}

struct _StaticCalls {
    var state: PassState;

    construct(state: PassState) {
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        if (e is MethodCall(call)) {
            if (call.this_value is SymbolRef(symbol)) {
                if (state.enum_representations.contains(symbol.id)) {
                    return e;
                }
                var key = value_type_key(state, symbol.id);
                if (!key.is_value()) {
                    return e;
                }
                var is_static = method_is_static(state, key.value(), call.method);
                if (is_static.is_value() and is_static.value()) {
                    return Expression.FunctionCall(
                        FunctionCallExpression(enum_method_name(key.value(), call.method), call.args, call.loc)
                    );
                }
            }
        }
        return e;
    }
}

extend _StaticCalls with Rewriter;

## Applies `rewriter` to every expression in the compilation unit's own code
## (a checked declaration's were rewritten with its unit): field defaults,
## the parameter defaults and bodies of methods, constructors, destructors
## and functions, extension methods, and globals.
##
## @param module the model, changed in place
## @param rewriter what to do at each expression
export for_each_expression(module: Module, rewriter: Rewriter) {
    var own = unit_decls(module);
    for (var st in own.structs) {
        for (var field in st.field_members) {
            if (field.default.is_value()) {
                field.default = Optional<Expression>.Value(rewrite_expression(field.default.value(), rewriter));
            }
        }
        var methods = Array<FunctionDef>();
        methods.append_all(st.method_members);
        methods.append_all(st.constructors);
        methods.append(st.destructor);
        for (var method in methods) {
            _walk_function(method, rewriter, true);
        }
    }
    for (var function in own.functions) {
        _walk_function(function, rewriter, true);
    }
    for (var e in module.checked.extensions..module.extensions.count) {
        for (var method in module.extensions[e].methods) {
            _walk_function(method, rewriter, false);
        }
    }
    for (var global in module.globals) {
        if (global.default.is_value() and !module.checked.globals.contains(global.name)) {
            global.default = Optional<Expression>.Value(rewrite_expression(global.default.value(), rewriter));
        }
    }
}

_walk_function(function: FunctionDef, rewriter: Rewriter, defaults: bool) {
    if (defaults) {
        for (var parameter in function.parameters) {
            if (parameter.default.is_value()) {
                parameter.default = Optional<Expression>.Value(rewrite_expression(parameter.default.value(), rewriter));
            }
        }
    }
    if (function.body.is_value()) {
        rewrite_block(function.body.value(), rewriter);
    }
}

## Returns whether value type `owner` has method `method`, and if so
## whether it is static.
##
## @param state the passes' state
## @param owner the value type's key
## @param method the method, with any type arguments
## @returns whether it is static, or none when there is no such method
export method_is_static(state: PassState, owner: String, method: String): bool? {
    var name = method;
    var at = method.find("<");
    if (at > 0 and method.ends_with(">")) {
        name = method.substr_bytes(0, at as ulong);
    }
    if (name.contains("<") or name.contains(">")) {
        name = name.replace("<", "{").replace(">", "}");
    }
    return state.enum_methods.try_get(method_key(owner, name));
}

## Replaces the types of `type_map` in `block`, as a specialization does.
##
## @param block the block, changed in place
## @param type_map the parameters and their types
export substitute_block(block: Block, type_map: Array<(String, TypeName)>) {
    for (var statement in block.items) {
        _substitute_statement(statement, type_map);
    }
}

_substitute_statement(statement: Statement, type_map: Array<(String, TypeName)>) {
    match (statement) {
        Expression(e) => {
            _substitute_expression(e, type_map);
        }
        Block(inner) => {
            substitute_block(inner, type_map);
        }
        Declaration(declaration) => {
            if (declaration is Variable(variable)) {
                replace_map(variable.ty, type_map);
                if (variable.default.is_value()) {
                    _substitute_expression(variable.default.value(), type_map);
                }
            }
        }
        Branch(branch) => {
            _substitute_expression(branch.condition, type_map);
            substitute_block(branch.if_block, type_map);
            if (branch.else_block.is_value()) {
                substitute_block(branch.else_block.value(), type_map);
            }
        }
        While(loop) => {
            _substitute_expression(loop.condition, type_map);
            substitute_block(loop.block, type_map);
        }
        Return(ret) => {
            if (ret.expr.is_value()) {
                _substitute_expression(ret.expr.value(), type_map);
            }
        }
        Static(block) => {
            _substitute(block, type_map);
            _substitute_static_items(block.items, type_map);
        }
        else => {}
    }
}

_substitute_static_items(items: StaticItem[], type_map: Array<(String, TypeName)>) {
    for (var item in items) {
        match (item) {
            For(node) => {
                _substitute_static_items(node.body, type_map);
            }
            While(node) => {
                _substitute_static_items(node.body, type_map);
            }
            Block(body) => {
                _substitute_static_items(body, type_map);
            }
            If(node) => {
                _substitute_static_items(node.then_items, type_map);
                _substitute_static_items(node.else_items, type_map);
            }
            EmitIf(node) => {
                _substitute_expression(node.condition, type_map);
                _substitute_static_items(node.then_items, type_map);
                _substitute_static_items(node.else_items, type_map);
            }
            Emit(statement, _) => {
                _substitute_statement(statement, type_map);
            }
            else => {}
        }
    }
}

_substitute_expression(e: Expression, type_map: Array<(String, TypeName)>) {
    rewrite_expression(e, _Substituter(type_map));
}

## Substitutes the type arguments of `type_map` at each expression.
struct _Substituter {
    var type_map: Array<(String, TypeName)>;

    construct(type_map: Array<(String, TypeName)>) {
        this.type_map = type_map;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            SizeOf(ty) => {
                replace_map(ty, type_map);
            }
            ArrayIndex(node) => {
                replace_map(node.ty, type_map);
            }
            IsPod(ty) => {
                replace_map(ty, type_map);
            }
            Default(ty) => {
                replace_map(ty, type_map);
            }
            StaticCase(node) => {
                replace_map(node.ty, type_map);
            }
            Subject(node) => {
                replace_map(node.ty, type_map);
            }
            Allocate(ty) => {
                replace_map(ty, type_map);
            }
            Cast(node) => {
                replace_map(node.ty, type_map);
            }
            RefCount(ty, _) => {
                replace_map(ty, type_map);
            }
            Weak(_, ty, _) => {
                replace_map(ty, type_map);
            }
            Address(ty, _) => {
                replace_map(ty, type_map);
            }
            AtomicLoad(ty, _) => {
                replace_map(ty, type_map);
            }
            AtomicStore(ty, _, _) => {
                replace_map(ty, type_map);
            }
            AtomicCmpXchg(ty, _, _, _) => {
                replace_map(ty, type_map);
            }
            AtomicFetch(_, ty, _, _) => {
                replace_map(ty, type_map);
            }
            Simd(node) => {
                replace_map(node.ty, type_map);
            }
            FunctionPointer(node) => {
                if (node.owner.is_value()) {
                    replace_map(node.owner.value(), type_map);
                }
            }
            MakeClosure(node) => {
                replace_map(node.ty, type_map);
                var parsed = parse_type_string(node.closure);
                replace_map(parsed, type_map);
                node.closure = parsed.to_string();
            }
            FunctionCall(node) => {
                var set = set_name(node.function);
                bool plain = !set.contains("<");
                for (var (param, _) in type_map) {
                    if (set == param) {
                        plain = false;
                    }
                }
                if (!plain) {
                    var ordinal = node.function.substr_bytes(set.size, node.function.size - set.size);
                    var parsed = parse_type_string(set);
                    replace_map(parsed, type_map);
                    node.function = parsed.to_string() + ordinal;
                }
            }
            MethodCall(node) => {
                if (node.method.contains("<")) {
                    var parsed = parse_type_string(node.method);
                    replace_map(parsed, type_map);
                    node.method = parsed.to_string();
                }
            }
            # A generic method's value, `this.pick<U>`.
            MemberRef(node) => {
                if (node.name.contains("<")) {
                    var parsed = parse_type_string(node.name);
                    replace_map(parsed, type_map);
                    node.name = parsed.to_string();
                }
            }
            SymbolRef(node) => {
                replace_map(node.ty, type_map);
            }
            else => {}
        }
        return e;
    }
}

extend _Substituter with Rewriter;
