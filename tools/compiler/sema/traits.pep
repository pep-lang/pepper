## Traits used as types (`Shape s`, `Array<Shape>`): `pepper_sema::traits`
## in Pepper, as far as the passes ported so far ask about them. A module
## with no checked runtime is assumed.

import [drop_body] from "checked";
import [Block, FunctionDef, Module, StructDef, TraitDef, TraitType, TypeFlags, TypeName] from "model";
import [TraitTypeMemo] from "state";
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

## Returns whether a trait member can be called through a value of the
## trait type: an instance method whose signature does not name `this`
## and that has no type parameters of its own.
##
## @param method the member
## @returns true when a vtable can hold it
export is_dispatchable(method: FunctionDef): bool {
    if (method.is_static or method.is_generic_func or method.ty.mentions("this")) {
        return false;
    }
    for (var p in method.parameters) {
        if (p.ty.mentions("this")) {
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
        drop_body(method);
        _substitute_type(method.ty, type_map);
        for (var p in method.parameters) {
            _substitute_type(p.ty, type_map);
        }
        methods.append(method);
    }
    return TraitType(ty.copy(), methods);
}

## Substitutes each parameter in turn.
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
## @param memo what earlier calls found in the checked declarations, when
##     the caller keeps it (`PassState.trait_memo`)
## @returns the trait types, each once, in the order found
export used_trait_types(module: Module, memo: TraitTypeMemo? = Optional<TraitTypeMemo>.Empty): TypeName[] {
    var found = _TraitTypes(module.traits);
    if (module.traits.count == 0) {
        return found.types;
    }
    if (memo.is_value() and memo.value().stashed) {
        return _with_checked(module, memo.value(), found);
    }
    for (var st in module.structs) {
        if (st.ty.is_generic() and st.name == st.ty.name) {
            continue;
        }
        if (!memo.is_value() or !_is_settled(module, st)) {
            found.add_struct(st);
            continue;
        }
        var members = st.method_members.count + st.constructors.count;
        var known = memo.value().structs.try_get(st.name);
        if (known.is_value()) {
            var (counted, types) = known.value();
            if (counted == members) {
                found.replay(types);
                continue;
            }
        }
        found.noting = true;
        found.add_struct(st);
        memo.value().structs[st.name] = (members, found.noted);
        found.noting = false;
        found.noted = Array<TypeName>();
    }
    for (var function in module.functions) {
        if (function.is_generic_func) {
            continue;
        }
        if (!memo.is_value() or function.body.is_value() or !module.checked.functions.contains(function.name)) {
            found.add_function(function);
            continue;
        }
        var known = memo.value().functions.try_get(function.name);
        if (known.is_value()) {
            found.replay(known.value());
            continue;
        }
        found.noting = true;
        found.add_function(function);
        memo.value().functions[function.name] = found.noted;
        found.noting = false;
        found.noted = Array<TypeName>();
    }
    for (var global in module.globals) {
        found.add(global.ty);
    }
    return found.types;
}

# `used_trait_types` while the checked bodies are stashed: what the settled
# checked declarations hold is found once per compilation unit
# (`TraitTypeMemo`), and only the rest is looked through each time.
_with_checked(module: Module, memo: TraitTypeMemo, found: _TraitTypes): TypeName[] {
    # A checked struct gains methods (a generic method specialized for it)
    # with bodies: what it holds is then looked through again.
    ulong fields = 0;
    ulong methods = 0;
    for (var st in module.structs) {
        if (module.checked.structs.contains(st.name)) {
            fields += st.field_members.count;
            methods += st.method_members.count;
        }
    }
    var counts = (module.checked.structs.count as ulong, module.checked.functions.count as ulong, fields, methods);
    if (!memo.checked_types.is_value() or memo.checked_types_counts != counts) {
        var checked = _TraitTypes(module.traits);
        var unsettled = HashSet<String>();
        for (var st in module.structs) {
            if (!module.checked.structs.contains(st.name) or (st.ty.is_generic() and st.name == st.ty.name)) {
                continue;
            }
            if (_is_settled(module, st)) {
                checked.add_struct(st);
            } else {
                unsettled.insert(st.name);
            }
        }
        for (var function in module.functions) {
            if (!function.is_generic_func
                and !function.body.is_value()
                and module.checked.functions.contains(function.name)) {
                checked.add_function(function);
            }
        }
        memo.checked_types = Optional<(TypeName[], HashSet<String>, HashSet<String>, HashSet<String>)>.Value(
            (checked.types, checked.seen, checked.visited, unsettled)
        );
        memo.checked_types_counts = counts;
    }
    var (types, seen, visited, unsettled) = memo.checked_types.value();
    found.types.append_all(types);
    found.base_seen = seen;
    found.base_visited = visited;
    for (var st in module.structs) {
        if (st.ty.is_generic() and st.name == st.ty.name) {
            continue;
        }
        if (module.checked.structs.contains(st.name) and !unsettled.contains(st.name)) {
            continue;
        }
        found.add_struct(st);
    }
    for (var function in module.functions) {
        if (function.is_generic_func) {
            continue;
        }
        if (!function.body.is_value() and module.checked.functions.contains(function.name)) {
            continue;
        }
        found.add_function(function);
    }
    for (var global in module.globals) {
        found.add(global.ty);
    }
    return found.types;
}

# Whether `st` is checked and none of its members has a body: the passes
# stashed them, so it stays as it is.
_is_settled(module: Module, st: StructDef): bool {
    if (!module.checked.structs.contains(st.name) or st.destructor.body.is_value()) {
        return false;
    }
    for (var method in st.method_members) {
        if (method.body.is_value()) {
            return false;
        }
    }
    for (var constructor in st.constructors) {
        if (constructor.body.is_value()) {
            return false;
        }
    }
    return true;
}

## `used_trait_types(module, memo)`, or a copy of `known` when the caller already
## found them and the module's declared types have not changed since.
##
## @param module the model
## @param known the trait types found before, if any
## @returns the trait types
export trait_types_of(
    module: Module, known: TypeName[]?, memo: TraitTypeMemo? = Optional<TraitTypeMemo>.Empty
): TypeName[] {
    if (!known.is_value()) {
        return used_trait_types(module, memo);
    }
    var out = Array<TypeName>();
    for (var ty in known.value()) {
        out.append(ty.copy());
    }
    return out;
}

## The trait types found so far.
struct _TraitTypes {
    var traits: TraitDef[];
    var types: Array<TypeName> = Array<TypeName>();
    var seen: HashSet<String> = HashSet<String>();
    ## The types already looked through, as written: one adds nothing more.
    var visited: HashSet<String> = HashSet<String>();
    ## What the checked declarations found (`_with_checked`), read without
    ## a copy: `seen` and `visited` hold only what is found beyond them.
    var base_seen: HashSet<String> = HashSet<String>();
    var base_visited: HashSet<String> = HashSet<String>();

    ## The traits' names.
    var names: HashSet<String> = HashSet<String>();
    ## The types `add` looked through, in order: what a `TraitTypeMemo`
    ## keeps of a declaration.
    var noted: Array<TypeName> = Array<TypeName>();
    var noting: bool = false;

    construct(traits: TraitDef[]) {
        this.traits = traits;
        for (var t in traits) {
            names.insert(t.name);
        }
    }

    ## Whether `ty` could name a trait: most types are spelled without one.
    _mentions_trait(ty: TypeName): bool {
        var name = ty.name;
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

    ## Adds what struct `st`'s fields, methods, constructors and destructor
    ## use.
    add_struct(st: StructDef) {
        for (var field in st.field_members) {
            add(field.ty);
        }
        for (var method in st.method_members) {
            add_function(method);
        }
        for (var constructor in st.constructors) {
            add_function(constructor);
        }
        add_function(st.destructor);
    }

    ## Looks through types a `TraitTypeMemo` noted, as `add` did.
    replay(types: TypeName[]) {
        for (var ty in types) {
            _look_through(ty);
        }
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
        if (noting) {
            noted.append(ty);
        }
        _look_through(ty);
    }

    # `add` for a type that may name a trait.
    _look_through(ty: TypeName) {
        # A pointer (`__ptr<Shape>`) is looked through below, as a type
        # argument.
        var text = ty.to_string();
        if (base_visited.contains(text) or visited.contains(text)) {
            return;
        }
        visited.insert(text);
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
            if (applied and !base_seen.contains(spelled) and !seen.contains(spelled)) {
                seen.insert(spelled);
                types.append(pointee);
            }
        }
        for (var arg in pointee.sub_types) {
            if (_mentions_trait(arg)) {
                _look_through(arg);
            }
        }
    }
}
