## The LLVM type of each Pepper type name: `crates/pepper-codegen/src/types.rs`
## in Pepper.

import llvm;
import [parse_type_string, PassState, stored_as] from compiler.sema;
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";

## What a value struct's LLVM name starts with (`value.Span`): it is named
## for readable IR, but held by value like a tuple, not as an object.
const _VALUE_PREFIX = "value.";

## Whether an LLVM type lowered from a Pepper type is a struct object, which
## values reference through a pointer: a named struct. A tuple is a literal
## struct, and a value struct's name starts with `value.`.
export is_object(ty: llvm.Type): bool {
    if (ty.kind() != llvm.TypeKind.Struct) {
        return false;
    }
    var name = ty.struct_name();
    return !name.is_empty and !name.starts_with(_VALUE_PREFIX);
}

## The registry of LLVM types by Pepper type name.
export struct Types {
    var context: llvm.Context;
    var state: PassState;
    var struct_types: HashMap<String, llvm.Type> = HashMap<String, llvm.Type>();
    ## Traits used as types: `[2 x ptr]` (object, vtable).
    var trait_types: HashMap<String, llvm.Type> = HashMap<String, llvm.Type>();
    ## Tuple types: a literal struct of the elements' slot types.
    var tuple_types: HashMap<String, llvm.Type> = HashMap<String, llvm.Type>();
    ## Each value struct's name with every omitted type argument filled in,
    ## for the names that differ (`value_structs::canonical`).
    var canonical: HashMap<String, String> = HashMap<String, String>();

    construct(context: llvm.Context, state: PassState) {
        this.context = context;
        this.state = state;
    }

    ## The LLVM type of `name`; structs must be registered first.
    get(name: String): llvm.Type? {
        var found = trait_types.try_get(name);
        if (found.is_value()) {
            return found;
        }
        found = tuple_types.try_get(name);
        if (found.is_value()) {
            return found;
        }
        found = struct_types.try_get(name);
        if (found.is_value()) {
            return found;
        }
        # A specialization `Name<a, b>` maps to its declared base name.
        var open = name.find("<");
        if (open >= 0) {
            found = struct_types.try_get(name.substr_bytes(0, open as ulong));
            if (found.is_value()) {
                return found;
            }
        }
        return scalar_type(name);
    }

    ## The LLVM type of a number, pointer or vector type name.
    scalar_type(name: String): llvm.Type? {
        var stored = stored_as(state, name);
        match (stored) {
            "bool", "i1" => {
                return Optional<llvm.Type>.Value(context.int1_type());
            }
            "i8", "char", "u8", "byte" => {
                return Optional<llvm.Type>.Value(context.int8_type());
            }
            "i16", "short", "u16", "ushort" => {
                return Optional<llvm.Type>.Value(context.int16_type());
            }
            "i32", "int", "u32", "uint", "void", "__auto" => {
                return Optional<llvm.Type>.Value(context.int32_type());
            }
            "i64", "long", "u64", "ulong" => {
                return Optional<llvm.Type>.Value(context.int64_type());
            }
            "f32", "float" => {
                return Optional<llvm.Type>.Value(context.float_type());
            }
            "f64", "double" => {
                return Optional<llvm.Type>.Value(context.double_type());
            }
            else => {}
        }
        # Pointer types: `T*`, `void*`, and C function pointers.
        if (stored.ends_with("*") or stored.starts_with("__extern_function<")) {
            return Optional<llvm.Type>.Value(context.pointer_type());
        }
        # `__simd<T, N>`: `<N x T>`.
        var shape = simd_shape(stored);
        if (shape.is_value()) {
            var (lane, count) = shape.value();
            var lane_type = scalar_type(lane);
            if (!lane_type.is_value()) {
                return Optional<llvm.Type>.Empty;
            }
            var kind = lane_type.value().kind();
            if (kind != llvm.TypeKind.Integer and kind != llvm.TypeKind.Float and kind != llvm.TypeKind.Double) {
                return Optional<llvm.Type>.Empty;
            }
            return Optional<llvm.Type>.Value(lane_type.value().vector_type(count));
        }
        return Optional<llvm.Type>.Empty;
    }

    ## Registers a trait used as a type: `[2 x ptr]` (object, vtable).
    register_trait(name: String) {
        trait_types[name] = context.pointer_type().array_type(2);
    }

    is_trait(name: String): bool {
        return trait_types.contains(name);
    }

    ## Registers a tuple type: a literal struct of its elements' slot types.
    register_tuple(name: String, elements: llvm.Type[]) {
        tuple_types[name] = context.struct_type(elements);
    }

    is_tuple(name: String): bool {
        return tuple_types.contains(name);
    }

    ## Sets a struct's body from its field types, on the opaque type
    ## `ensure_opaque` made, so the LLVM name stays unique.
    register_struct(name: String, fields: llvm.Type[]) {
        ensure_opaque(name).set_body(fields);
    }

    ## The body-less struct type for `name`, made once per name.
    ensure_opaque(name: String): llvm.Type {
        var found = struct_types.try_get(name);
        if (found.is_value()) {
            return found.value();
        }
        var made = context.named_struct_type(name);
        struct_types[name] = made;
        return made;
    }

    ## `ensure_opaque` for a value struct, whose LLVM name marks it as no
    ## object. Every spelling of one type shares its canonical name's type.
    ensure_value_opaque(name: String): llvm.Type {
        var found = struct_types.try_get(name);
        if (found.is_value()) {
            return found.value();
        }
        var spelled = canonical.try_get(name);
        var canonical_name = spelled.is_value() ? spelled.value() : name;
        var existing = struct_types.try_get(canonical_name);
        llvm.Type made;
        if (existing.is_value()) {
            made = existing.value();
        } else {
            made = context.named_struct_type($"{_VALUE_PREFIX}{canonical_name}");
            struct_types[canonical_name] = made;
        }
        struct_types[name] = made;
        return made;
    }

    ## The struct type for a (possibly specialized) name.
    struct_type(name: String): llvm.Type? {
        var found = struct_types.try_get(name);
        if (found.is_value()) {
            return found;
        }
        var open = name.find("<");
        if (open >= 0) {
            return struct_types.try_get(name.substr_bytes(0, open as ulong));
        }
        return Optional<llvm.Type>.Empty;
    }
}

## The lane type and lane count of `__simd<T, N>`, when `name` spells one.
export simd_shape(name: String): (String, uint)? {
    if (!name.starts_with("__simd<")) {
        return Optional<(String, uint)>.Empty;
    }
    var ty = parse_type_string(name);
    if (ty.sub_types.count != 2) {
        return Optional<(String, uint)>.Empty;
    }
    var count = uint.parse(ty.sub_types[1].name);
    if (!count.is_value()) {
        return Optional<(String, uint)>.Empty;
    }
    return Optional<(String, uint)>.Value((ty.sub_types[0].to_string(), count.value()));
}
