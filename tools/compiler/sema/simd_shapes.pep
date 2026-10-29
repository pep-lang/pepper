## The lane count of a SIMD vector: `check_simd_shapes`. A generic struct
## whose field is the built-in `__simd<T, N>` takes its lane count as an
## integer type argument, as does one whose field passes its parameter on as
## such a count; each specialization's count must be a power of two from 1
## to 64, so a mask's lanes fit a `ulong`. No other type argument may be a
## number.

import "common";
import "constraints";
import [Loc] from "loc";
import [Module, TypeName] from "model";
import [PassState] from "state";
import [SIMD] from "type_name";

## The largest lane count: a mask's bits fill a `ulong`.
const _MAX_LANES: ulong = 64;

## Reports the first number written as a type argument that is not a lane
## count, then the first specialization whose lane count is not a power of
## two from 1 to 64, each at the argument where the program writes it.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_simd_shapes(module: Module, state: PassState) {
    var counted = _lane_counts(module);
    var typed = _typed_function_parameters(module, counted);
    var generic_structs = HashSet<String>();
    for (var st in module.structs) {
        if (st.ty.is_generic() and st.name == st.ty.name) {
            generic_structs.insert(st.name);
        }
    }
    for (var type_use in module.type_uses) {
        ulong index = 0;
        while (index < type_use.ty.sub_types.count and index < type_use.args.count) {
            var argument = type_use.ty.sub_types[index];
            var name = type_use.ty.name;
            # A struct takes a number only as a lane count; a generic
            # function, unless its signature uses that parameter as a type.
            bool refused = false;
            if (generic_structs.contains(name)) {
                var counts = counted.try_get(name);
                refused = !(counts.is_value() and counts.value().contains(index));
            } else {
                var as_type = typed.try_get(name);
                refused = as_type.is_value() and as_type.value().contains(index);
            }
            if (refused and ulong.parse(argument.name).is_value() and _compiled(module, type_use, state).is_value()) {
                state.report(
                    error_at(
                        $"'{argument.name}' is not a type; a number is a type argument only as a SIMD type's lane count, as in 'simd.Vector<float, 4>'",
                        type_use.args[index]
                    )
                );
                return;
            }
            index += 1;
        }
    }
    for (var spec in module.struct_specs) {
        var counts = counted.try_get(spec.name);
        if (!counts.is_value()) {
            continue;
        }
        for (var index in counts.value()) {
            if (index >= spec.sub_types.count or _is_lane_count(spec.sub_types[index].name)) {
                continue;
            }
            state.report(
                error_at(
                    $"lane count of '{spec.to_string()}' must be a power of two from 1 to {_MAX_LANES}, not '{spec.sub_types[index].to_string()}'",
                    _lane_site(module, spec, index)
                )
            );
            return;
        }
    }
}

## The index of each lane-count parameter of each generic struct: one that a
## field's `__simd<T, N>` takes as `N`, or that a field passes on as another
## struct's lane count (a struct wrapping a `Vector`).
_lane_counts(module: Module): HashMap<String, HashSet<ulong>> {
    var counted = HashMap<String, HashSet<ulong>>();
    bool changed = true;
    while (changed) {
        changed = false;
        for (var st in module.structs) {
            if (!(st.ty.is_generic() and st.name == st.ty.name)) {
                continue;
            }
            for (var field in st.field_members) {
                for (var name in _counts_in(field.ty, counted)) {
                    ulong index = 0;
                    while (index < st.generic_params.count) {
                        if (st.generic_params[index].name == name) {
                            if (!counted.contains(st.name)) {
                                counted[st.name] = HashSet<ulong>();
                            }
                            changed = counted[st.name].insert(index) or changed;
                        }
                        index += 1;
                    }
                }
            }
        }
    }
    return counted;
}

## The indices of each generic function's parameters that its signature
## uses as types (`T` of `show<T>(value: T)`), not only as lane counts
## (`N` of `counting<T, N>(): Vector<T, N>`), by the function's name.
_typed_function_parameters(module: Module, counted: HashMap<String, HashSet<ulong>>): HashMap<String, HashSet<ulong>> {
    var out = HashMap<String, HashSet<ulong>>();
    for (var f in module.functions) {
        if (f.generic_params.count == 0) {
            continue;
        }
        var names = HashSet<String>();
        _type_names(f.ty, counted, names);
        for (var p in f.parameters) {
            _type_names(p.ty, counted, names);
        }
        if (!out.contains(f.name)) {
            out[f.name] = HashSet<ulong>();
        }
        ulong index = 0;
        while (index < f.generic_params.count) {
            if (names.contains(f.generic_params[index].name)) {
                out[f.name].insert(index);
            }
            index += 1;
        }
    }
    return out;
}

## Adds to `out` the names `ty` uses as types, leaving out its lane counts.
_type_names(ty: TypeName, counted: HashMap<String, HashSet<ulong>>, out: HashSet<String>) {
    out.insert(ty.name);
    var counts = counted.try_get(ty.name);
    ulong index = 0;
    while (index < ty.sub_types.count) {
        bool lane = (ty.name == SIMD and index == 1) or (counts.is_value() and counts.value().contains(index));
        if (!lane) {
            _type_names(ty.sub_types[index], counted, out);
        }
        index += 1;
    }
}

## The names `ty`, or a type inside it, passes as a lane count.
_counts_in(ty: TypeName, counted: HashMap<String, HashSet<ulong>>): Array<String> {
    var out = Array<String>();
    if (ty.name == SIMD and ty.sub_types.count >= 2) {
        out.append(ty.sub_types[1].name);
    }
    var counts = counted.try_get(ty.name);
    if (counts.is_value()) {
        for (var index in counts.value()) {
            if (index < ty.sub_types.count) {
                out.append(ty.sub_types[index].name);
            }
        }
    }
    for (var inner in ty.sub_types) {
        out.append_all(_counts_in(inner, counted));
    }
    return out;
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
