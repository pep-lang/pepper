## Which types are thread-safe: `ThreadSafeStructs` and `unsafe_part_in`. A
## `[Shared]` struct, a `shared` function type, and a value struct
## (`[Value]`) whose fields all are thread-safe are thread-safe structs;
## numbers, raw pointers and weak references to thread-safe types, and
## tuples of them, are thread-safe types.

import compiler.ast;
import [SHARED_ATTRIBUTE] from "builder";
import [Module, StructDef, TypeName] from "model";
import [PassState] from "state";
import [parse_type_string, SIMD] from "type_name";

## The names of the thread-safe structs.
export struct ThreadSafeStructs {
    var names: HashSet<String>;
    var state: PassState;

    ## Finds the thread-safe structs of `module`.
    ##
    ## @param module the model
    ## @param state the passes' state, which knows the enums
    construct(module: Module, state: PassState) {
        this.state = state;
        names = HashSet<String>();
        for (var st in module.structs) {
            if (ast.has_attribute(st.attributes, SHARED_ATTRIBUTE) or st.ty.is_shared_function_type()) {
                names.insert(st.name);
            }
        }
        # A value struct holding another counts once that one does.
        var values = Array<StructDef>();
        for (var st in module.structs) {
            if (st.is_value() and !(st.ty.is_generic() and st.name == st.ty.name)) {
                values.append(st);
            }
        }
        var growing = true;
        while (growing) {
            var found = Array<String>();
            for (var st in values) {
                if (names.contains(st.name)) {
                    continue;
                }
                bool all = true;
                for (var f in st.field_members) {
                    if (unsafe_part_in(f.ty, this).is_value()) {
                        all = false;
                        break;
                    }
                }
                if (all) {
                    found.append(st.name);
                }
            }
            growing = found.count > 0;
            for (var name in found) {
                names.insert(name);
            }
        }
    }
}

## The first type inside `ty` that is not thread-safe, if any.
##
## @param ty the type
## @param safe the thread-safe structs
## @returns the part, or none
export unsafe_part_in(ty: TypeName, safe: ThreadSafeStructs): TypeName? {
    var none = Optional<TypeName>.Empty;
    var name = ty.to_string();
    # A C function pointer is a code address, the same on every thread, and
    # a vector holds only numbers.
    if (safe.state.is_integral(name)
        or ty.name == SIMD
        or ty.is_shared_function_type()
        or ty.is_extern_function_type()) {
        return none;
    }
    if (ty.is_function_type()) {
        return Optional<TypeName>.Value(ty);
    }
    if (ty.is_pointer() or ty.is_weak()) {
        return unsafe_part_in(ty.sub_types[0], safe);
    }
    # A tuple is its elements, held by value.
    var parsed = parse_type_string(name);
    if (parsed.is_tuple()) {
        for (var e in parsed.sub_types) {
            var part = unsafe_part_in(e, safe);
            if (part.is_value()) {
                return part;
            }
        }
        return none;
    }
    if (safe.names.contains(name)) {
        return none;
    }
    # Some passes carry a type as a flat name (`__function<void>`).
    if (parsed.is_function_type() or parsed.is_extern_function_type()) {
        return unsafe_part_in(parsed, safe);
    }
    return Optional<TypeName>.Value(ty);
}
