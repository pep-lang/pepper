## Inferring a generic function's type arguments from a call's arguments:
## `pepper_sema::passes::type_arguments` in Pepper. `larger(3, 9)` is
## `larger<int>(3, 9)`: each parameter's declared type is matched against
## its argument's type, binding the generic parameters it mentions.

import [FunctionDef, GenericParam, Module, TypeName] from "model";
import [PassState] from "state";
import [replace_map] from "type_name";

## Records the trait conformances of `module`'s structs for inference to
## see through, as `type_arguments::record_conformances` does.
##
## @param module the model
## @param state the passes' state, which keeps them
export record_conformances(module: Module, state: PassState) {
    var table = HashMap<String, (String[], TypeName[])>();
    for (var st in module.structs) {
        if (st.traits.count == 0) {
            continue;
        }
        if (st.ty.is_generic() and st.name == st.ty.name) {
            var params = Array<String>();
            for (var p in st.generic_params) {
                params.append(p.name);
            }
            table[st.name] = (params, st.traits);
        } else {
            table[st.ty.to_string()] = (Array<String>(), st.traits);
        }
    }
    state.conformances = table;
}

## The traits `actual` declares, with its type arguments substituted.
_conformances_of(state: PassState, actual: TypeName): TypeName[] {
    var exact = state.conformances.try_get(actual.to_string());
    if (exact.is_value()) {
        var (_, traits) = exact.value();
        return traits;
    }
    var base = state.conformances.try_get(actual.name);
    if (!base.is_value()) {
        return Array<TypeName>();
    }
    var (params, traits) = base.value();
    if (params.count != actual.sub_types.count) {
        return Array<TypeName>();
    }
    var map = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < params.count) {
        map.append((params[i], actual.sub_types[i]));
        i += 1;
    }
    var out = Array<TypeName>();
    for (var t in traits) {
        var copy = t.copy();
        replace_map(copy, map);
        out.append(copy);
    }
    return out;
}

## Returns `name<args>`, the name call sites and specializations use.
##
## @param name the generic's name
## @param args the type arguments
## @returns the name
export specialization(name: String, args: TypeName[]): String {
    return TypeName.with_args(name, args).to_string();
}

## A generic function's declaration, as the inference needs it.
export struct GenericSignature {
    ## Its generic parameters.
    var params: GenericParam[];
    ## Its parameters' declared types.
    var parameter_types: TypeName[];
    ## How many of the parameters (from the front) have no default.
    var required: ulong;
    ## The passes' state, for the conformances.
    var state: PassState;

    ## Returns `function`'s signature.
    ##
    ## @param function the generic function
    ## @param state the passes' state
    ## @returns the signature
    construct(function: FunctionDef, state: PassState) {
        params = function.generic_params;
        parameter_types = Array<TypeName>();
        required = 0;
        for (var p in function.parameters) {
            parameter_types.append(p.ty);
            if (!p.default.is_value()) {
                required += 1;
            }
        }
        this.state = state;
    }

    _is_param(name: String): bool {
        for (var p in params) {
            if (p.name == name) {
                return true;
            }
        }
        return false;
    }

    ## Returns the bindings `arguments` (their types, where known) give,
    ## without defaults.
    ##
    ## @param arguments each argument's type, where known
    ## @returns the bindings by parameter name
    bind(arguments: Array<TypeName?>): HashMap<String, TypeName> {
        var bindings = HashMap<String, TypeName>();
        ulong i = 0;
        while (i < parameter_types.count and i < arguments.count) {
            if (arguments[i].is_value()) {
                _unify(parameter_types[i], arguments[i].value(), bindings);
            }
            i += 1;
        }
        _bind_through_bounds(bindings);
        return bindings;
    }

    ## Binds the parameters a bound names from the bound parameter's type
    ## argument, until nothing new binds.
    _bind_through_bounds(bindings: HashMap<String, TypeName>) {
        while (true) {
            var before = bindings.count;
            for (var param in params) {
                var actual = bindings.try_get(param.name);
                if (!actual.is_value()) {
                    continue;
                }
                for (var bound in param.bounds) {
                    _unify(bound.ty, actual.value(), bindings);
                }
            }
            if (bindings.count == before) {
                break;
            }
        }
    }

    ## Returns the type arguments for a call with `arguments`, when every
    ## generic parameter is bound by an argument or its default.
    ##
    ## @param arguments each argument's type, where known
    ## @returns the type arguments, or none
    infer(arguments: Array<TypeName?>): TypeName[]? {
        if (arguments.count < required or arguments.count > parameter_types.count) {
            return Optional<TypeName[]>.Empty;
        }
        return _with_defaults(bind(arguments));
    }

    _with_defaults(bindings: HashMap<String, TypeName>): TypeName[]? {
        var out = Array<TypeName>();
        for (var p in params) {
            var bound = bindings.try_get(p.name);
            if (bound.is_value()) {
                out.append(bound.value().copy());
            } else if (p.default.is_value()) {
                out.append(p.default.value().copy());
            } else {
                return Optional<TypeName[]>.Empty;
            }
        }
        return Optional<TypeName[]>.Value(out);
    }

    ## Returns the type arguments for a call that writes only the leading
    ## ones: the written ones, then each missing one from its default, else
    ## from the arguments.
    ##
    ## @param written the type arguments written
    ## @param arguments each argument's type, where known
    ## @returns the type arguments, or none when every one is written or
    ## one stays unbound
    complete(written: TypeName[], arguments: Array<TypeName?>): TypeName[]? {
        if (written.count >= params.count) {
            return Optional<TypeName[]>.Empty;
        }
        bool all_defaulted = true;
        ulong i = written.count;
        while (i < params.count) {
            if (!params[i].default.is_value()) {
                all_defaulted = false;
            }
            i += 1;
        }
        if (all_defaulted or arguments.count < required or arguments.count > parameter_types.count) {
            return Optional<TypeName[]>.Empty;
        }
        var bindings = HashMap<String, TypeName>();
        i = 0;
        while (i < written.count) {
            bindings[params[i].name] = written[i];
            i += 1;
        }
        i = written.count;
        while (i < params.count) {
            if (params[i].default.is_value()) {
                bindings[params[i].name] = params[i].default.value();
            }
            i += 1;
        }
        i = 0;
        while (i < parameter_types.count and i < arguments.count) {
            if (arguments[i].is_value()) {
                _unify(parameter_types[i], arguments[i].value(), bindings);
            }
            i += 1;
        }
        _bind_through_bounds(bindings);
        var out = Array<TypeName>();
        for (var p in params) {
            var bound = bindings.try_get(p.name);
            if (!bound.is_value()) {
                return Optional<TypeName[]>.Empty;
            }
            out.append(bound.value().copy());
        }
        return Optional<TypeName[]>.Value(out);
    }

    ## Returns the type arguments that make the function, whose declared
    ## return type is `ret`, a value of function type `expected`.
    ##
    ## @param ret the declared return type
    ## @param expected the function type
    ## @returns the type arguments, or none when the counts differ or a
    ## parameter stays unbound
    infer_from_function_type(ret: TypeName, expected: TypeName): TypeName[]? {
        var expected_params = expected.function_params();
        if (expected_params.count != parameter_types.count) {
            return Optional<TypeName[]>.Empty;
        }
        var bindings = HashMap<String, TypeName>();
        ulong i = 0;
        while (i < parameter_types.count) {
            _unify(parameter_types[i], expected_params[i], bindings);
            i += 1;
        }
        var expected_return = expected.function_return();
        if (expected_return.is_value()) {
            _unify(ret, expected_return.value(), bindings);
        }
        _bind_through_bounds(bindings);
        return _with_defaults(bindings);
    }

    ## Returns parameter `index`'s type with the known bindings substituted
    ## and every unbound generic parameter left `auto`.
    ##
    ## @param index the parameter
    ## @param bindings what is bound
    ## @returns the type, or none past the parameters
    expected(index: ulong, bindings: HashMap<String, TypeName>): TypeName? {
        if (index >= parameter_types.count) {
            return Optional<TypeName>.Empty;
        }
        var ty = parameter_types[index].copy();
        for (var param in params) {
            var bound = bindings.try_get(param.name);
            ty.replace(param.name, bound.is_value() ? bound.value() : TypeName.auto());
        }
        return Optional<TypeName>.Value(ty);
    }

    _unify(pattern: TypeName, actual: TypeName, bindings: HashMap<String, TypeName>) {
        if (actual.is_auto()) {
            return;
        }
        if (pattern.sub_types.count == 0 and _is_param(pattern.name)) {
            if (!actual.contains_auto() and !bindings.contains(pattern.name)) {
                bindings[pattern.name] = actual.copy();
            }
            return;
        }
        if (pattern.name == actual.name and pattern.sub_types.count == actual.sub_types.count) {
            ulong i = 0;
            while (i < pattern.sub_types.count) {
                _unify(pattern.sub_types[i], actual.sub_types[i], bindings);
                i += 1;
            }
            return;
        }
        # A trait parameter takes its arguments from the trait the
        # argument's struct declares.
        if (pattern.sub_types.count > 0) {
            for (var conformance in _conformances_of(state, actual)) {
                if (conformance.name == pattern.name and conformance.sub_types.count == pattern.sub_types.count) {
                    ulong i = 0;
                    while (i < pattern.sub_types.count) {
                        _unify(pattern.sub_types[i], conformance.sub_types[i], bindings);
                        i += 1;
                    }
                    return;
                }
            }
        }
    }
}
