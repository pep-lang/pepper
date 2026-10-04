## The sema type name's helpers: `crates/pepper-sema/src/type_name.rs` in
## Pepper. `TypeName` itself is generated in `model.pep`; this file adds what
## the builder and the passes ask of one.

import [TypeFlags, TypeName] from "model";
import [set_name] from "names";

## The type sema infers: `auto`.
export const AUTO = "__auto";
## The type of nothing.
export const VOID = "void";
## The type of a condition.
export const BOOL = "bool";
## The untyped pointer.
export const VOID_PTR = "void*";
## Function types: `(P1, P2) => R` is `__function<R, P1, P2>`.
export const FUNCTION = "__function";
## Thread-safe function types: `shared (P1, P2) => R` is
## `__shared_function<R, P1, P2>`.
export const SHARED_FUNCTION = "__shared_function";
## C function pointer types: `extern (P1, P2) => R` is
## `__extern_function<R, P1, P2>`.
export const EXTERN_FUNCTION = "__extern_function";
## `__weak<T>`: a weak reference to a struct `T`.
export const WEAK = "__weak";
## Tuple types: `(A, B)` is `__tuple<A, B>`.
export const TUPLE = "__tuple";
## The built-in vector type `__simd<T, N>`.
export const SIMD = "__simd";

## Returns whether `name` is a primitive type (`int`, `bool`, `void*`, ...).
##
## @param name the type's name
## @returns true for a primitive
export is_integral_name(name: String): bool {
    match (name) {
        "void", "__auto", "bool", "void*", "i8", "char", "u8", "byte", "i16", "short", "u16", "ushort", "i32", "int", "u32", "uint", "i64", "long", "u64", "ulong", "f64", "double", "f32", "float" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

export extend TypeName {
    ## Returns the type named `name`, with no arguments.
    ##
    ## @param name the name
    ## @returns the type
    static named(name: String): TypeName {
        return TypeName(name = name);
    }

    ## Returns the type `name<args>`.
    ##
    ## @param name the name
    ## @param args the type arguments
    ## @returns the type
    static with_args(name: String, args: TypeName[]): TypeName {
        return TypeName(name = name, sub_types = args);
    }

    ## Returns `auto`, a type not inferred yet.
    ##
    ## @returns the type
    static auto(): TypeName {
        return TypeName(name = AUTO);
    }

    ## Returns `void`.
    ##
    ## @returns the type
    static void(): TypeName {
        return TypeName(name = VOID);
    }

    ## Returns whether this is a function type, plain or thread-safe.
    ##
    ## @returns true for `(P...) => R` and `shared (P...) => R`
    is_function_type(): bool {
        return (name == FUNCTION or name == SHARED_FUNCTION) and sub_types.count > 0;
    }

    ## Returns whether this is a C function pointer type.
    ##
    ## @returns true for `extern (P...) => R`
    is_extern_function_type(): bool {
        return name == EXTERN_FUNCTION and sub_types.count > 0;
    }

    ## Returns whether this is a thread-safe function type.
    ##
    ## @returns true for `shared (P...) => R`
    is_shared_function_type(): bool {
        return name == SHARED_FUNCTION and sub_types.count > 0;
    }

    ## Returns whether this is a tuple type.
    ##
    ## @returns true for `(A, B, ...)`
    is_tuple(): bool {
        return name == TUPLE and sub_types.count >= 2;
    }

    ## Returns whether this type has type arguments.
    ##
    ## @returns true for `Name<args>`
    is_generic(): bool {
        return sub_types.count > 0;
    }

    ## Returns whether this is exactly `auto`.
    ##
    ## @returns true for a type not inferred yet
    is_auto(): bool {
        return name == AUTO and sub_types.count == 0;
    }

    ## Returns whether this is a primitive type. An enum, which sema also
    ## stores as an integer, is not known here.
    ##
    ## @returns true for `int`, `bool`, `void*`, ...
    is_integral(): bool {
        return flags == TypeFlags.Scalar and is_integral_name(name);
    }

    ## Returns the type as the programmer writes it, for error messages:
    ## `(int) => bool` for function types, `(a: int, b: int)` for tuples,
    ## `Name<args>` otherwise.
    ##
    ## @returns the text
    display(): String {
        if (is_function_type() or is_extern_function_type()) {
            var params = Array<String>();
            ulong i = 1;
            while (i < sub_types.count) {
                params.append(sub_types[i].display());
                i += 1;
            }
            var shared = "";
            if (is_shared_function_type()) {
                shared = "shared ";
            } else if (is_extern_function_type()) {
                shared = "extern ";
            }
            return $"{shared}({", ".join(params)}) => {sub_types[0].display()}";
        }
        if (is_tuple()) {
            var elements = Array<String>();
            ulong i = 0;
            while (i < sub_types.count) {
                if (i < labels.count and !labels[i].is_empty) {
                    elements.append($"{labels[i]}: {sub_types[i].display()}");
                } else {
                    elements.append(sub_types[i].display());
                }
                i += 1;
            }
            return $"({", ".join(elements)})";
        }
        if (is_generic()) {
            var arguments = Array<String>();
            for (var t in sub_types) {
                arguments.append(t.display());
            }
            return $"{name}<{", ".join(arguments)}>";
        }
        return name;
    }

    ## Returns the type's spelling in sema: `name<sub, sub>`, or `name`.
    ##
    ## @returns the text
    to_string(): String {
        if (sub_types.count == 0) {
            return name;
        }
        var arguments = Array<String>();
        for (var t in sub_types) {
            arguments.append(t.to_string());
        }
        return $"{name}<{", ".join(arguments)}>";
    }

    ## Returns whether `other` is the same type. Labels are not part of a
    ## type's identity.
    ##
    ## @param other the other type
    ## @returns true when equal
    ==(other: TypeName): bool {
        if (name != other.name or flags != other.flags or sub_types.count != other.sub_types.count) {
            return false;
        }
        ulong i = 0;
        while (i < sub_types.count) {
            if (!(sub_types[i] == other.sub_types[i])) {
                return false;
            }
            i += 1;
        }
        return true;
    }

    ## Makes this type `other`: its name, arguments, flags and labels.
    ##
    ## @param other the type to become
    assign(other: TypeName) {
        name = other.name;
        sub_types = other.sub_types;
        flags = other.flags;
        labels = other.labels;
    }

    ## Replaces generic parameter `param_name` with `type_arg` throughout
    ## this type, a pointer to it (`T*`) included.
    ##
    ## @param param_name the parameter's name
    ## @param type_arg the type it stands for
    replace(param_name: String, type_arg: TypeName) {
        if (name == param_name) {
            # Done: the argument may itself name a parameter spelled the
            # same (`Twin<T>` with `T` = `Box<T>`), which is not this one.
            assign(type_arg.copy());
            return;
        } else if (name.ends_with("*") and name.substr_bytes(0, name.size - 1) == param_name) {
            name = $"{type_arg.to_string()}*";
        }
        for (var arg in sub_types) {
            arg.replace(param_name, type_arg);
        }
    }
}

## Replaces each generic parameter of `type_map` in `ty` with its type, in
## order.
##
## @param ty the type, changed in place
## @param type_map the parameters and their types
export replace_map(ty: TypeName, type_map: Array<(String, TypeName)>) {
    for (var (param, arg) in type_map) {
        ty.replace(param, arg);
    }
}

## Returns the type a call's function string spells (`Result<int>.ok`'s
## receiver `Result<int>`, `g<I>`), its arguments parsed; a pointer type or
## an operator's name is one name.
##
## @param text the string
## @returns the type
export parse_type_string(text: String): TypeName {
    var s = text;
    var set = set_name(text);
    if (set.ends_with(">")) {
        s = set;
    }
    if (s.ends_with("*")) {
        return TypeName.named(s);
    }
    var open = s.find("<");
    if (open <= 0 or !s.ends_with(">") or s.size <= open as ulong + 1) {
        return TypeName.named(s);
    }
    var name = s.substr_bytes(0, open as ulong);
    var inner = s.substr_bytes(open as ulong + 1, s.size - open as ulong - 2);
    var args = Array<TypeName>();
    if (!inner.trim().is_empty) {
        # Split on top-level commas only.
        var parts = Array<String>();
        ulong depth = 0;
        ulong start = 0;
        ulong i = 0;
        while (i < inner.size) {
            var b = inner.byte_at(i);
            if (b == '<') {
                depth += 1;
            } else if (b == '>') {
                depth -= 1;
            } else if (b == ',' and depth == 0) {
                parts.append(inner.substr_bytes(start, i - start).trim());
                start = i + 1;
            }
            i += 1;
        }
        var last = inner.substr_bytes(start, inner.size - start).trim();
        if (!last.is_empty) {
            parts.append(last);
        }
        for (var part in parts) {
            args.append(parse_type_string(part));
        }
    }
    return TypeName.with_args(name, args);
}
