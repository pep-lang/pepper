## Names in the linked program: the namespaces that tell two files' private
## declarations apart, and the rule that decides when a generic function's
## parameters are types (a concrete override, `hash<int>`).

import compiler.ast;
import [Span, TypeName] from compiler.ast;

## Separates a name from the namespace of the file that declares it:
## `helper@io/file`.
export const NAMESPACE_SEPARATOR = "@";

## Separates an overload set's name from a member's number: `f$2`.
export const OVERLOAD_SEPARATOR = "$";

## Returns `name` in the namespace `namespace`: `helper@io/file`.
##
## @param name the declared name
## @param namespace the declaring file's namespace
## @returns the mangled name
export mangle(name: String, namespace: String): String {
    return name + NAMESPACE_SEPARATOR + namespace;
}

## Returns `name` without a namespace or an overload member's number:
## `helper` for `helper@io/file` and for `helper$2`.
##
## @param name a name, mangled or not
## @returns the name as declared
export demangle_name(name: String): String {
    ulong i = 0;
    while (i < name.size) {
        var b = name.byte_at(i);
        if (b == '@' or b == '$') {
            return name.substr_bytes(0, i);
        }
        i += 1;
    }
    return name;
}

## Returns whether `name` names a primitive type (`int`, `bool`, `void*`).
##
## @param name a type's name
## @returns true for a primitive
export is_integral_type(name: String): bool {
    match (name) {
        "void", "__auto", "bool", "void*", "i8", "char", "u8", "byte", "i16", "short", "u16", "ushort", "i32", "int", "u32", "uint", "i64", "long", "u64", "ulong", "f64", "double", "f32", "float" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Returns whether every one of a generic function's parameters, as spelled,
## names a primitive or `String`.
##
## @param params the parameters' names
## @returns true when all are concrete
export is_concrete_override(params: String[]): bool {
    for (var param in params) {
        if (!is_integral_type(param) and param != "String") {
            return false;
        }
    }
    return true;
}

## Returns whether a function with these generic parameters, as spelled, is
## a concrete override (`hash<int>`): it has some, and all are concrete.
##
## @param params the parameters' names
## @returns true for a concrete override
export is_override(params: String[]): bool {
    return params.count > 0 and is_concrete_override(params);
}

## Returns the type `text` spells (`Box<Pair<int, S>>`), every part at
## `span`. A pointer keeps its stars in its name, and an operator's name
## (`<=`) is a name.
##
## @param text the type's text
## @param span where every part is
## @returns the type
export parse_type_string(text: String, span: Span): TypeName {
    if (text.ends_with("*")) {
        return TypeName(text, span);
    }
    var found = text.find("<");
    if (found <= 0 or !text.ends_with(">") or text.size <= found as ulong + 1) {
        return TypeName(text, span);
    }
    ulong open = found as ulong;
    var out = TypeName(text.substr_bytes(0, open), span);
    var inner = text.substr_bytes(open + 1, text.size - open - 2);
    if (inner.trim().is_empty) {
        return out;
    }
    # Split on top-level commas only.
    long depth = 0;
    ulong start = 0;
    ulong i = 0;
    while (i < inner.size) {
        var b = inner.byte_at(i);
        if (b == '<') {
            depth += 1;
        } else if (b == '>') {
            depth -= 1;
        } else if (b == ',' and depth == 0) {
            out.generic_types.append(parse_type_string(inner.substr_bytes(start, i - start).trim(), span));
            start = i + 1;
        }
        i += 1;
    }
    var last = inner.substr_bytes(start, inner.size - start).trim();
    if (!last.is_empty) {
        out.generic_types.append(parse_type_string(last, span));
    }
    return out;
}
