## Interpolated values. The
## parser lowers `$"n = {n}"` to `"n = " + _pep_interpolate(n)`, which the
## runtime converts with `to_string(value)`: a number or `bool` overload, a
## concrete override `to_string<T>`, or the generic one, which calls
## `value.to_string()`. A type with none of these is reported at the
## `{name}`, as are values `print<T>` cannot print and format
## specifications a value's type does not take.

import [demangle, Location] from compiler.diagnostic;
import [demangle_name] from compiler.link;
import "common";
import [Loc] from "loc";
import [Expression, FunctionDef, Module] from "model";
import [set_name] from "names";
import "resolve_implicit_types";
import [PassState] from "state";
import [parse_type_string] from "type_name";
import [rewrite_block, Rewriter] from "walk";

const _TO_STRING = "to_string";
const _PRINT = "print";
const _INTERPOLATE_FUNCTION = "_pep_interpolate";
const _FORMAT_FUNCTION = "_pep_format";
const _FORMAT_INTEGER_FUNCTION = "_pep_format_integer";
const _FORMAT_FLOAT_FUNCTION = "_pep_format_float";
## The most elements a tuple the runtime's `to_string` overloads convert.
const _MAX_TUPLE: ulong = 8;

## The types the runtime's non-generic `to_string` overloads take.
_to_string_overload(ty: String): bool {
    match (ty) {
        "bool", "i8", "char", "u8", "byte", "i16", "short", "u16", "ushort", "i32", "int", "u32", "uint", "i64", "long", "u64", "ulong", "float", "f32", "double", "f64" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_float_name(ty: String): bool {
    return ty == "float" or ty == "f32" or ty == "double" or ty == "f64";
}

## The name of a specialization `f<A, B>` and its type arguments' text.
_split_generic(name: String): (String, String)? {
    var open = name.find("<");
    if (open < 0 or !name.ends_with(">")) {
        return Optional<(String, String)>.Empty;
    }
    var at = open as ulong;
    return Optional<(String, String)>.Value((name.substr_bytes(0, at), name.substr_bytes(at + 1, name.size - at - 2)));
}

## Whether `function` declares a `to_string()` an instance can call.
_is_to_string_method(function: FunctionDef): bool {
    return set_name(function.name) == _TO_STRING and !function.is_static and function.parameters.count == 0;
}

_base_of(ty: String): String {
    var open = ty.find("<");
    return open < 0 ? ty : ty.substr_bytes(0, open as ulong);
}

## Checks each value an interpolated string, a format specification or
## `print` converts.
##
## @param module the model
## @param state the passes' state, which takes the first error
export check_interpolations(module: Module, state: PassState) {
    var checker = _InterpolationChecker(module, state);
    # Generic bases are checked through their specializations.
    for (var function in module.functions) {
        if (!function.is_generic_func and function.body.is_value()) {
            rewrite_block(function.body.value(), checker);
        }
    }
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            continue;
        }
        for (var m in st.method_members) {
            if (m.body.is_value()) {
                rewrite_block(m.body.value(), checker);
            }
        }
        for (var c in st.constructors) {
            if (c.body.is_value()) {
                rewrite_block(c.body.value(), checker);
            }
        }
    }
}

struct _InterpolationChecker {
    ## Every type argument with a concrete override `to_string<X>`.
    var overrides: HashSet<String> = HashSet<String>();
    ## The types with a `to_string()` method.
    var with_method: HashSet<String> = HashSet<String>();
    var traits: HashSet<String> = HashSet<String>();
    var struct_locs: HashMap<String, Loc> = HashMap<String, Loc>();
    var state: PassState;

    construct(module: Module, state: PassState) {
        this.state = state;
        # The generic's own specializations (`to_string<Foo>` made for a
        # call) keep the generic's location, so they are not overrides.
        var generic_locs = HashSet<Loc>();
        for (var f in module.functions) {
            if (f.is_generic_func and demangle_name(_base_of(f.name)) == _TO_STRING) {
                generic_locs.insert(f.loc);
            }
        }
        for (var f in module.functions) {
            if (f.is_generic_func or generic_locs.contains(f.loc)) {
                continue;
            }
            var split = _split_generic(f.name);
            if (split.is_value()) {
                var (base, args) = split.value();
                if (demangle_name(base) == _TO_STRING) {
                    overrides.insert(args);
                }
            }
        }
        for (var s in module.structs) {
            for (var m in s.method_members) {
                if (_is_to_string_method(m)) {
                    with_method.insert(s.name);
                    break;
                }
            }
            struct_locs[s.name] = s.loc;
        }
        for (var t in module.traits) {
            for (var m in t.methods) {
                if (_is_to_string_method(m)) {
                    with_method.insert(_base_of(t.name));
                    break;
                }
            }
            traits.insert(_base_of(t.name));
        }
        var suffix = $"::{_TO_STRING}";
        for (var f in module.functions) {
            if (f.name.ends_with(suffix)) {
                with_method.insert(f.name.substr_bytes(0, f.name.size - suffix.size));
            }
        }
    }

    _convertible(ty: String): bool {
        if (overrides.contains(ty) or with_method.contains(ty)) {
            return true;
        }
        if (ty.starts_with("__tuple<")) {
            var tuple = parse_type_string(ty);
            if (tuple.sub_types.count > _MAX_TUPLE) {
                return false;
            }
            for (var element in tuple.sub_types) {
                if (!_convertible(element.to_string())) {
                    return false;
                }
            }
            return true;
        }
        var base = _base_of(ty);
        if (traits.contains(base)) {
            return with_method.contains(base);
        }
        # The runtime's overloads: every number type and `bool`.
        return _to_string_overload(ty);
    }

    rewrite(e: Expression): Expression {
        if (!(e is FunctionCall(_))) {
            return e;
        }
        var call = _function_call_of(e);
        var split = _split_generic(call.function);
        if (!split.is_value()) {
            return e;
        }
        var (base, ty) = split.value();
        var shown = demangle(ty);
        # The runtime's `print<T>(value)` prints `to_string(value)`.
        if (demangle_name(set_name(base)) == _PRINT) {
            if (!_convertible(ty)) {
                var at = call.loc;
                if (call.args.count > 0 and !_expression_loc(call.args[0]).is_none()) {
                    at = _expression_loc(call.args[0]);
                }
                state.report(
                    error_at(
                        $"cannot print a value of type '{shown}': it has no 'to_string()' method and no 'to_string' overload",
                        at
                    )
                );
            }
            return e;
        }
        if (base == _FORMAT_FLOAT_FUNCTION) {
            if (!_is_float_name(ty)) {
                state.report(
                    error_at(
                        $"cannot format a value of type '{shown}' with a precision; only 'float' and 'double' take one",
                        call.loc
                    )
                );
            }
            return e;
        }
        if (base == _FORMAT_INTEGER_FUNCTION) {
            if (ty == "bool" or _is_float_name(ty) or !_to_string_overload(ty)) {
                state.report(error_at($"cannot format a value of type '{shown}' as an integer", call.loc));
            }
            return e;
        }
        if ((base != _INTERPOLATE_FUNCTION and base != _FORMAT_FUNCTION) or _convertible(ty)) {
            return e;
        }
        var error = error_at(
            $"cannot interpolate a value of type '{shown}': it has no 'to_string()' method and no 'to_string' overload",
            call.loc
        );
        var declared = struct_locs.try_get(ty);
        if (declared.is_value()) {
            error = error.with_note(
                $"declare 'to_string(): String' in '{shown}', or implement 'ToString' with 'extend {shown} with ToString'",
                Optional<Location>.Value(location_of(declared.value()))
            );
        }
        state.report(error);
        return e;
    }
}

extend _InterpolationChecker with Rewriter;
