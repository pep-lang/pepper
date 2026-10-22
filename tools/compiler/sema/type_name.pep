## The sema type name's helpers. `TypeName` itself is generated in `model.pep`; this file adds what
## the builder and the passes ask of one.

import [TypeFlags, TypeName] from "model";
import [set_name] from "names";

## The type sema infers: `auto`.
export const AUTO = "__auto";
## The type of nothing.
export const VOID = "void";
## The type of a condition.
export const BOOL = "bool";
## The raw pointer type: `__ptr<T>`, which C's `T*` is parsed as.
export const POINTER = "__ptr";
## The untyped pointer, `__ptr<void>`, as `to_string` spells it.
export const VOID_PTR = "__ptr<void>";
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

## Returns whether `name` is a primitive type (`int`, `bool`, `__ptr<void>`,
## ...).
##
## @param name the type's name
## @returns true for a primitive
export is_integral_name(name: String): bool {
    match (name) {
        "void", "__auto", "bool", "__ptr<void>", "i8", "char", "u8", "byte", "i16", "short", "u16", "ushort", "i32", "int", "u32", "uint", "i64", "long", "u64", "ulong", "f64", "double", "f32", "float" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## Returns the sized name of a number type (`i32` for `int`), and any
## other name unchanged: `common_number_name` the other way, so the two
## change together.
##
## @param name the type's name
## @returns the sized name
export sized_number_name(name: String): String {
    match (name) {
        "char" => {
            return "i8";
        }
        "byte" => {
            return "u8";
        }
        "short" => {
            return "i16";
        }
        "ushort" => {
            return "u16";
        }
        "int" => {
            return "i32";
        }
        "uint" => {
            return "u32";
        }
        "long" => {
            return "i64";
        }
        "ulong" => {
            return "u64";
        }
        "float" => {
            return "f32";
        }
        "double" => {
            return "f64";
        }
        else => {
            return name;
        }
    }
}

## Returns the name programs commonly write for a number type sema spells
## by width (`int` for `i32`), and any other name unchanged.
##
## @param name the type's name
## @returns the common name
export common_number_name(name: String): String {
    match (name) {
        "i8" => {
            return "char";
        }
        "u8" => {
            return "byte";
        }
        "i16" => {
            return "short";
        }
        "u16" => {
            return "ushort";
        }
        "i32" => {
            return "int";
        }
        "u32" => {
            return "uint";
        }
        "i64" => {
            return "long";
        }
        "u64" => {
            return "ulong";
        }
        "f32" => {
            return "float";
        }
        "f64" => {
            return "double";
        }
        else => {
            return name;
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

    ## Returns `bool`.
    ##
    ## @returns the type
    static boolean(): TypeName {
        return TypeName(name = BOOL);
    }

    ## Returns `__ptr<pointee>`.
    ##
    ## @param pointee the type pointed at
    ## @returns the type
    static pointer_to(pointee: TypeName): TypeName {
        return TypeName(name = POINTER, sub_types = [pointee]);
    }

    ## Returns `__ptr<void>`.
    ##
    ## @returns the type
    static void_pointer(): TypeName {
        return TypeName.pointer_to(TypeName.void());
    }

    ## Returns whether this is a plain (scalar) type rather than a pointer
    ## to one.
    ##
    ## @returns true for a scalar
    is_scalar(): bool {
        return flags == TypeFlags.Scalar;
    }

    ## Returns whether this is the empty type: no name, no arguments.
    ##
    ## @returns true for a type never spelled
    is_empty(): bool {
        return name.size == 0 and sub_types.count == 0;
    }

    ## Returns whether a value of this type can be called: a function type
    ## or a C function pointer type.
    ##
    ## @returns true for a callable type
    is_callable(): bool {
        return is_function_type() or is_extern_function_type();
    }

    ## Returns whether this type, or a type nested in it (a pointer's
    ## pointee included), is `name`.
    ##
    ## @param name the type name
    ## @returns true when it appears
    mentions(name: String): bool {
        if (this.name == name) {
            return true;
        }
        for (var t in sub_types) {
            if (t.mentions(name)) {
                return true;
            }
        }
        return false;
    }

    ## Returns the position of tuple element `name`: its digits (`0`), or
    ## its label (`line`).
    ##
    ## @param name the element
    ## @returns the position, or none when the tuple has no such element
    tuple_index(name: String): ulong? {
        if (!is_tuple()) {
            return Optional<ulong>.Empty;
        }
        ulong index = 0;
        var parsed = ulong.parse(name);
        if (parsed.is_value()) {
            index = parsed.value();
        } else {
            bool found = false;
            while (index < labels.count) {
                if (labels[index] == name) {
                    found = true;
                    break;
                }
                index += 1;
            }
            if (!found) {
                return Optional<ulong>.Empty;
            }
        }
        return index < sub_types.count ? Optional<ulong>.Value(index) : Optional<ulong>.Empty;
    }

    ## Returns the type of element `name` (`0`, `1`, ... or a label) of a
    ## tuple type.
    ##
    ## @param name the element
    ## @returns its type, or none
    tuple_element(name: String): TypeName? {
        var index = tuple_index(name);
        return index.is_value() ? Optional<TypeName>.Value(sub_types[index.value()]) : Optional<TypeName>.Empty;
    }

    ## Returns whether a tuple among this type's type arguments, at any
    ## depth, has labels: whether a member read through a value of this
    ## type can take labels back (`labeled_through`).
    ##
    ## @returns true for `Array<(name: String, count: int)>`
    labels_arguments(): bool {
        for (var t in sub_types) {
            if (t._has_labeled_tuple()) {
                return true;
            }
        }
        return false;
    }

    ## Returns this type, a member's type in a specialization (a field's,
    ## or what a method returns), read through a value of type `receiver`,
    ## with the labels `receiver`'s type arguments are written with. Labels
    ## are not part of a type's identity, so one specialization serves every
    ## labeling of its arguments, and its members' types carry none: the
    ## labeled type is `declared`, the member's type in the generic
    ## declaration, with `receiver`'s type arguments in place of its
    ## parameters `params`.
    ##
    ## @param receiver the type the member is read through
    ## @param declared the member's type as the generic declaration writes it
    ## @param params the generic declaration's type parameters
    ## @returns the labeled type, or this type when `declared` with the
    ##     arguments in place is not this type (another declaration's
    ##     member, or a parameter left to its default)
    labeled_through(receiver: TypeName, declared: TypeName, params: String[]): TypeName {
        if (params.count != receiver.sub_types.count) {
            return this;
        }
        var type_map = Array<(String, TypeName)>();
        for (var i in 0..params.count) {
            type_map.append((params[i], receiver.sub_types[i]));
        }
        var out = declared.copy();
        replace_map(out, type_map);
        return out == this ? out : this;
    }

    ## Returns `written` when it is this type: the type a call that names a
    ## type is written with (`Array<(name: String, count: int)>()`), labels
    ## included, which the call's spelling drops.
    ##
    ## @param written the type as written, if the call names one with labels
    ## @returns `written`, or this type
    as_written(written: TypeName?): TypeName {
        return written.is_value() and written.value() == this ? written.value() : this;
    }

    # Whether a tuple in this type, this type included, has labels.
    _has_labeled_tuple(): bool {
        if (is_tuple() and labels.count > 0) {
            return true;
        }
        return labels_arguments();
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

    ## Returns the return type of a function type.
    ##
    ## @returns the return type, or none for any other type
    function_return(): TypeName? {
        if ((is_function_type() or is_extern_function_type()) and sub_types.count > 0) {
            return Optional<TypeName>.Value(sub_types[0]);
        }
        return Optional<TypeName>.Empty;
    }

    ## Returns the parameter types of a function type.
    ##
    ## @returns the parameter types; none for any other type
    function_params(): TypeName[] {
        var out = Array<TypeName>();
        if (is_function_type() or is_extern_function_type()) {
            ulong i = 1;
            while (i < sub_types.count) {
                out.append(sub_types[i]);
                i += 1;
            }
        }
        return out;
    }

    ## Returns whether this is a weak reference type.
    ##
    ## @returns true for `__weak<T>`
    is_weak(): bool {
        return name == WEAK and sub_types.count == 1;
    }

    ## Returns whether `auto` appears anywhere in this type.
    ##
    ## @returns true for `auto`, `Array<auto>`, ...
    contains_auto(): bool {
        if (name == AUTO) {
            return true;
        }
        for (var t in sub_types) {
            if (t.contains_auto()) {
                return true;
            }
        }
        return false;
    }

    ## Returns whether this is a raw pointer type.
    ##
    ## @returns true for `__ptr<int>`, `__ptr<void>`, ...
    is_pointer(): bool {
        return name == POINTER and sub_types.count == 1;
    }

    ## Returns the type a raw pointer points at.
    ##
    ## @returns `T` for `__ptr<T>`; none for any other type
    pointee(): TypeName? {
        return is_pointer() ? Optional<TypeName>.Value(sub_types[0]) : Optional<TypeName>.Empty;
    }

    ## Returns the type under every pointer layer: `int` for
    ## `__ptr<__ptr<int>>`, and the type itself when it is no pointer.
    ##
    ## @returns the type
    without_pointers(): TypeName {
        var out = this;
        while (out.is_pointer()) {
            out = out.sub_types[0];
        }
        return out;
    }

    ## Returns whether this is the untyped pointer.
    ##
    ## @returns true for `__ptr<void>`
    is_void_pointer(): bool {
        return is_pointer() and sub_types[0].name == VOID and sub_types[0].sub_types.count == 0;
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
    ## @returns true for `int`, `bool`, `__ptr<void>`, ...
    is_integral(): bool {
        return flags == TypeFlags.Scalar and (is_integral_name(name) or is_void_pointer());
    }

    ## Returns the type as the programmer writes it, for error messages:
    ## `(int) => bool` for function types, `(a: int, b: int)` for tuples,
    ## `Name<args>` otherwise, and each number type by its common name
    ## (`int` for the `i32` an integer literal is typed).
    ##
    ## @returns the text
    display(): String {
        return _display(true);
    }

    ## Returns the type as `display` does, but with each number type spelled
    ## as sema stores it (`u16` stays `u16`): for `reflect.name`, which
    ## gives a type's name as written.
    ##
    ## @returns the text
    display_stored(): String {
        return _display(false);
    }

    _display(common: bool): String {
        if (is_function_type() or is_extern_function_type()) {
            var params = Array<String>();
            ulong i = 1;
            while (i < sub_types.count) {
                params.append(sub_types[i]._display(common));
                i += 1;
            }
            var shared = "";
            if (is_shared_function_type()) {
                shared = "shared ";
            } else if (is_extern_function_type()) {
                shared = "extern ";
            }
            return $"{shared}({", ".join(params)}) => {sub_types[0]._display(common)}";
        }
        if (is_tuple()) {
            var elements = Array<String>();
            ulong i = 0;
            while (i < sub_types.count) {
                if (i < labels.count and !labels[i].is_empty) {
                    elements.append($"{labels[i]}: {sub_types[i]._display(common)}");
                } else {
                    elements.append(sub_types[i]._display(common));
                }
                i += 1;
            }
            return $"({", ".join(elements)})";
        }
        if (is_generic()) {
            var arguments = Array<String>();
            for (var t in sub_types) {
                arguments.append(t._display(common));
            }
            return $"{name}<{", ".join(arguments)}>";
        }
        return common ? common_number_name(name) : name;
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
    ## this type, a pointer to it (`__ptr<T>`) included.
    ##
    ## @param param_name the parameter's name
    ## @param type_arg the type it stands for
    replace(param_name: String, type_arg: TypeName) {
        if (name == param_name) {
            # Done: the argument may itself name a parameter spelled the
            # same (`Twin<T>` with `T` = `Box<T>`), which is not this one.
            assign(type_arg.copy());
            return;
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
## receiver `Result<int>`, `g<I>`), its arguments parsed; an operator's
## name is one name.
##
## @param text the string
## @returns the type
export parse_type_string(text: String): TypeName {
    var s = text;
    var set = set_name(text);
    if (set.ends_with(">")) {
        s = set;
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

## Returns whether `text`, a type as `TypeName.to_string` spells it, is a
## raw pointer: `__ptr<T>`.
##
## @param text the type's text
## @returns true for a pointer
export is_pointer_name(text: String): bool {
    if (!text.starts_with("__ptr<") or !text.ends_with(">")) {
        return false;
    }
    # The last `>` must close the first `<`, not end `__ptr<A>.f<B>`.
    ulong depth = 1;
    ulong i = 6;
    while (i + 1 < text.size) {
        var b = text.byte_at(i);
        if (b == '<') {
            depth += 1;
        } else if (b == '>') {
            depth -= 1;
            if (depth == 0) {
                return false;
            }
        }
        i += 1;
    }
    return true;
}

## Returns the type a raw pointer spelled `text` points at: `int` for
## `__ptr<int>`.
##
## @param text the type's text
## @returns the pointee's text; none when `text` is no pointer
export pointee_name(text: String): String? {
    if (!is_pointer_name(text)) {
        return Optional<String>.Empty;
    }
    return Optional<String>.Value(text.substr_bytes(6, text.size - 7));
}

## Returns `text`, a type's spelling, under every pointer layer: `int` for
## `__ptr<__ptr<int>>`.
##
## @param text the type's text
## @returns the innermost pointee's text, or `text` when it is no pointer
export without_pointer_names(text: String): String {
    var out = text;
    while (is_pointer_name(out)) {
        out = out.substr_bytes(6, out.size - 7);
    }
    return out;
}
