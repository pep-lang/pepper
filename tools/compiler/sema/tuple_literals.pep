## Tuple literals before their type is known: `pepper_sema::passes::tuples`'
## `literal_type`, `constructor_labels` and `labeled_literal_type` in
## Pepper. A literal `(a, b)` is built as a call of `__tuple` (or
## `__tuple(line,column)` when labeled), which `resolve_implicit_types`
## renames to the literal's type once its elements' types are known.

import [TypeName] from "model";
import [TUPLE] from "type_name";

## Returns the type of a tuple literal whose elements have `types`, or none
## while one is unknown.
##
## @param types the elements' types
## @returns the tuple type
export tuple_literal_type(types: TypeName[]): TypeName? {
    if (types.count < 2) {
        return Optional<TypeName>.Empty;
    }
    for (var t in types) {
        if (t.is_empty() or t.contains_auto() or t.name == "void") {
            return Optional<TypeName>.Empty;
        }
    }
    return Optional<TypeName>.Value(TypeName.with_args(TUPLE, types));
}

## Returns the labels of an unspelled tuple constructor (`__tuple`, or
## `__tuple(line,column)`), or none when `function` is not one.
##
## @param function the callee
## @returns the labels
export tuple_constructor_labels(function: String): String[]? {
    if (!function.starts_with(TUPLE)) {
        return Optional<String[]>.Empty;
    }
    var rest = function.substr_bytes(TUPLE.size, function.size - TUPLE.size);
    if (rest.size == 0) {
        return Optional<String[]>.Value(Array<String>());
    }
    if (!rest.starts_with("(") or !rest.ends_with(")")) {
        return Optional<String[]>.Empty;
    }
    var inner = rest.substr_bytes(1, rest.size - 2);
    return Optional<String[]>.Value(inner.split(","));
}

## Returns the type of a tuple literal calling `function` with arguments of
## `types`, labeled like the literal.
##
## @param function the callee
## @param types the elements' types
## @returns the tuple type
export labeled_tuple_literal_type(function: String, types: TypeName[]): TypeName? {
    var labels = tuple_constructor_labels(function);
    if (!labels.is_value()) {
        return Optional<TypeName>.Empty;
    }
    var ty = tuple_literal_type(types);
    if (!ty.is_value()) {
        return ty;
    }
    if (labels.value().count == ty.value().sub_types.count) {
        ty.value().labels = labels.value();
    }
    return ty;
}
