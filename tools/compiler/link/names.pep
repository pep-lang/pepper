## Names in the linked program: the namespaces that tell two files' private
## declarations apart, and the rule that decides when a generic function's
## parameters are types (a concrete override, `hash<int>`).

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

## Returns a type's name without the array brackets after it: `Point` for
## `Point[]`.
##
## @param name a type's name
## @returns the base name
export base_type_name(name: String): String {
    ulong size = name.size;
    while (size > 0) {
        var b = name.byte_at(size - 1);
        if (b != '[' and b != ']') {
            break;
        }
        size -= 1;
    }
    return name.substr_bytes(0, size);
}

## Returns whether `name` names a primitive type (`int`, `bool`,
## `__ptr<void>`).
##
## @param name a type's name
## @returns true for a primitive
export is_integral_type(name: String): bool {
    match (name) {
        "void", "__auto", "bool", "__ptr<void>", "i8", "char", "u8", "byte", "i16", "short", "u16", "ushort", "i32", "int", "u32", "uint", "i64", "long", "u64", "ulong", "f64", "double", "f32", "float" => {
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

## The linker spelling of a Pepper symbol. `main`, and a member name of
## letters, digits, `_` and `.` (`Point.length`), is its own spelling; any
## other name is `_P` followed by the name with `_` doubled and every other
## byte written as `_` and two hex digits (`Array<int>.count` is
## `_PArray_3cint_3e.count`), so every spelling names one symbol and no
## linker reads a `@` as a symbol version.
##
## @param name the symbol's Pepper name
## @returns its spelling
export symbol_name(name: String): String {
    var bytes = name.bytes();
    bool plain = true;
    for (var b in bytes) {
        if (!_is_plain(b)) {
            plain = false;
            break;
        }
    }
    if (name == "main" or (plain and name.contains(".") and !name.starts_with("_P"))) {
        return name;
    }
    var out = StringBuilder();
    out.append("_P");
    for (var i in 0..bytes.count) {
        var b = bytes[i];
        if (b == '_' as u8) {
            out.append("__");
        } else if (_is_plain(b)) {
            out.append(name.substr_bytes(i, 1));
        } else {
            out.append(b < 16 ? $"_0{b:x}" : $"_{b:x}");
        }
    }
    return out.to_string();
}

_is_plain(b: u8): bool {
    return (b >= '0' as u8 and b <= '9' as u8)
        or (b >= 'a' as u8 and b <= 'z' as u8)
        or (b >= 'A' as u8 and b <= 'Z' as u8)
        or b == '_' as u8
        or b == '.' as u8;
}
