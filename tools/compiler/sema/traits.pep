## Traits used as types (`Shape s`, `Array<Shape>`): `pepper_sema::traits`
## in Pepper, as far as the passes ported so far ask about them. A module
## with no checked runtime is assumed.

import [Block, FunctionDef, Module, TraitDef, TraitType, TypeFlags, TypeName] from "model";
import [parse_type_string] from "type_name";

## Returns the trait a type names: a plain (non-pointer, non-function) type
## whose name is a declared trait.
##
## @param traits the module's traits
## @param ty the type
## @returns the trait, if `ty` names one
export trait_def(traits: TraitDef[], ty: TypeName): TraitDef? {
    if (ty.flags != TypeFlags.Scalar or ty.is_pointer()) {
        return Optional<TraitDef>.Empty;
    }
    for (var t in traits) {
        if (t.name == ty.name) {
            return Optional<TraitDef>.Value(t);
        }
    }
    return Optional<TraitDef>.Empty;
}

## Whether a signature type names the implementing type (`this`).
_mentions_this(ty: TypeName): bool {
    if (ty.name == "this") {
        return true;
    }
    var bare = ty.name;
    while (bare.ends_with("*")) {
        bare = bare.substr_bytes(0, bare.size - 1);
    }
    if (bare == "this") {
        return true;
    }
    for (var sub in ty.sub_types) {
        if (_mentions_this(sub)) {
            return true;
        }
    }
    return false;
}

## Returns whether a trait member can be called through a value of the
## trait type: an instance method whose signature does not name `this`
## and that has no type parameters of its own.
##
## @param method the member
## @returns true when a vtable can hold it
export is_dispatchable(method: FunctionDef): bool {
    if (method.is_static or method.is_generic_func or _mentions_this(method.ty)) {
        return false;
    }
    for (var p in method.parameters) {
        if (_mentions_this(p.ty)) {
            return false;
        }
    }
    return true;
}

## Returns `def` specialized at `ty`'s type arguments, keeping only the
## members a value can call, in declaration order.
##
## @param def the trait
## @param ty the trait type
## @returns the instance
export instance(def: TraitDef, ty: TypeName): TraitType {
    var type_map = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < def.generic_params.count) {
        var param = def.generic_params[i];
        if (i < ty.sub_types.count) {
            type_map.append((param.name, ty.sub_types[i].copy()));
        } else if (param.default.is_value()) {
            type_map.append((param.name, param.default.value().copy()));
        }
        i += 1;
    }
    var methods = Array<FunctionDef>();
    for (var m in def.methods) {
        if (!is_dispatchable(m)) {
            continue;
        }
        var method = m.copy();
        method.body = Optional<Block>.Empty;
        _substitute_type(method.ty, type_map);
        for (var p in method.parameters) {
            _substitute_type(p.ty, type_map);
        }
        methods.append(method);
    }
    return TraitType(ty.copy(), methods);
}

## Substitutes each parameter in turn, as `specialize_structs::substitute`
## does.
_substitute_type(ty: TypeName, type_map: Array<(String, TypeName)>) {
    for (var (param, arg) in type_map) {
        ty.replace(param, arg);
    }
}

## Returns every trait type the module uses as a value type: in fields,
## signatures, locals and globals, through pointers and generic arguments
## too. Generic bases are skipped.
##
## @param module the model
## @returns the trait types, each once, in the order found
export used_trait_types(module: Module): TypeName[] {
    var found = _TraitTypes(module.traits);
    if (module.traits.count == 0) {
        return found.types;
    }
    for (var st in module.structs) {
        if (st.ty.is_generic() and st.name == st.ty.name) {
            continue;
        }
        for (var field in st.field_members) {
            found.add(field.ty);
        }
        for (var method in st.method_members) {
            found.add_function(method);
        }
        for (var constructor in st.constructors) {
            found.add_function(constructor);
        }
        found.add_function(st.destructor);
    }
    for (var function in module.functions) {
        if (!function.is_generic_func) {
            found.add_function(function);
        }
    }
    for (var global in module.globals) {
        found.add(global.ty);
    }
    return found.types;
}

## The trait types found so far.
struct _TraitTypes {
    var traits: TraitDef[];
    var types: Array<TypeName> = Array<TypeName>();
    var seen: HashSet<String> = HashSet<String>();
    ## The types already looked through, as written: one adds nothing more.
    var visited: HashSet<String> = HashSet<String>();

    ## The traits' names.
    var names: HashSet<String> = HashSet<String>();

    construct(traits: TraitDef[]) {
        this.traits = traits;
        for (var t in traits) {
            names.insert(t.name);
        }
    }

    ## Whether `ty` could name a trait: most types are spelled without one.
    _mentions_trait(ty: TypeName): bool {
        var name = ty.name;
        while (name.ends_with("*")) {
            name = name.substr_bytes(0, name.size - 1);
        }
        # A type carried as a flat name is looked through as written.
        if (names.contains(name) or name.contains("<")) {
            return true;
        }
        for (var sub in ty.sub_types) {
            if (_mentions_trait(sub)) {
                return true;
            }
        }
        return false;
    }

    add_function(function: FunctionDef) {
        add(function.ty);
        for (var p in function.parameters) {
            add(p.ty);
        }
        if (function.body.is_value()) {
            add_block(function.body.value());
        }
    }

    add_block(block: Block) {
        for (var statement in block.items) {
            match (statement) {
                Block(inner) => {
                    add_block(inner);
                }
                Declaration(declaration) => {
                    if (declaration is Variable(variable)) {
                        add(variable.ty);
                    }
                }
                Branch(branch) => {
                    add_block(branch.if_block);
                    if (branch.else_block.is_value()) {
                        add_block(branch.else_block.value());
                    }
                }
                While(loop) => {
                    add_block(loop.block);
                }
                else => {}
            }
        }
    }

    ## Records each fully applied trait type in `ty`.
    add(ty: TypeName) {
        if (!_mentions_trait(ty)) {
            return;
        }
        # Pointers carry their stars in the name (`Shape*`).
        var text = ty.to_string();
        if (visited.contains(text)) {
            return;
        }
        visited.insert(text);
        while (text.ends_with("*")) {
            text = text.substr_bytes(0, text.size - 1);
        }
        var pointee = parse_type_string(text);
        var def = trait_def(traits, pointee);
        if (def.is_value()) {
            # Only fully applied traits are types (`Iterator<T>` inside a
            # generic base is not).
            ulong required = 0;
            for (var p in def.value().generic_params) {
                if (!p.default.is_value()) {
                    required += 1;
                }
            }
            bool applied = pointee.sub_types.count >= required;
            for (var a in pointee.sub_types) {
                for (var p in def.value().generic_params) {
                    if (p.name == a.name) {
                        applied = false;
                    }
                }
            }
            var spelled = pointee.to_string();
            if (applied and !seen.contains(spelled)) {
                seen.insert(spelled);
                types.append(pointee);
            }
        }
        for (var arg in pointee.sub_types) {
            add(arg);
        }
    }
}
