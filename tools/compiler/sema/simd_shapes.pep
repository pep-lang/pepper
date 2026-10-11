## The lane count of a SIMD vector: `check_simd_shapes`. A generic struct
## whose field is the built-in `__simd<T, N>` takes its lane count as an
## integer type argument; each specialization's count must be a power of two
## from 1 to 64, so a mask's lanes fit a `ulong`.

import "common";
import [Loc] from "loc";
import [Module, TypeName] from "model";
import [PassState] from "state";
import [SIMD] from "type_name";

## The largest lane count: a mask's bits fill a `ulong`.
const _MAX_LANES: ulong = 64;

## Reports the first specialization whose lane count is not a power of two
## from 1 to 64, at the argument where the program writes it.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_simd_shapes(module: Module, state: PassState) {
    # Each generic struct holding a `__simd` field, with the index of the
    # parameter that is its lane count.
    var counted = HashMap<String, ulong>();
    for (var st in module.structs) {
        if (!(st.ty.is_generic() and st.name == st.ty.name)) {
            continue;
        }
        for (var field in st.field_members) {
            if (field.ty.name != SIMD or field.ty.sub_types.count < 2) {
                continue;
            }
            var count = field.ty.sub_types[1];
            ulong index = 0;
            while (index < st.generic_params.count) {
                if (st.generic_params[index].name == count.name) {
                    counted[st.name] = index;
                    break;
                }
                index += 1;
            }
        }
    }
    if (counted.count == 0) {
        return;
    }
    for (var spec in module.struct_specs) {
        var index = counted.try_get(spec.name);
        if (!index.is_value() or index.value() >= spec.sub_types.count) {
            continue;
        }
        var count = spec.sub_types[index.value()];
        if (_is_lane_count(count.name)) {
            continue;
        }
        state.report(
            error_at(
                $"lane count of '{spec.to_string()}' must be a power of two from 1 to {_MAX_LANES}, not '{count.to_string()}'",
                _lane_site(module, spec, index.value())
            )
        );
        return;
    }
}

_is_lane_count(text: String): bool {
    var n = ulong.parse(text);
    if (!n.is_value()) {
        return false;
    }
    var value = n.value();
    return value != 0 and (value & (value - 1)) == 0 and value <= _MAX_LANES;
}

## Where the program writes `spec`'s argument `index`, else nowhere.
_lane_site(module: Module, spec: TypeName, index: ulong): Loc {
    var wanted = _canonical(spec);
    for (var u in module.type_uses) {
        if (_canonical(u.ty) == wanted) {
            if (index < u.args.count) {
                return u.args[index];
            }
            return Loc.none();
        }
    }
    return Loc.none();
}
