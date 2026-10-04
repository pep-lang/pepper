## Extensions: `pepper_sema::passes::apply_extensions` in Pepper. Each
## extension's methods are cloned onto the structs it extends, and each trait
## it declares is recorded: the struct must have every member the trait
## declares, a trait member with a body is the struct's default when it has
## none of its own, and a plain field meets a trait's property.

import [Diagnostic, Edit, Fix, Location] from compiler.diagnostic;
import [TRAIT_SELF] from "closures";
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Expression,
    ExtensionDef,
    FunctionDef,
    Kind,
    MemberRefExpression,
    Module,
    ReturnStatement,
    Statement,
    StructDef,
    SymbolRefExpression,
    TraitDef,
    TypeName
] from "model";
import [Callee] from "named_arguments";
import [set_name] from "names";
import [group_methods] from "overloads";
import [PassState] from "state";
import [trait_def] from "traits";
import [replace_map, SIMD] from "type_name";
import [substitute_block] from "value_types";
import [Rewriter, rewrite_block] from "walk";

## The trait the deprecated `copy(copies: Copies)` still implements.
const _COPYABLE_TRAIT = "Copyable";
## The synthesized trait member that copies the struct behind a trait value.
const _COPY_TRAIT_METHOD = "_pep_copy_trait";

## Applies each resolved extension to the structs it extends, once each, as
## `apply_extensions::apply_extensions` does: an instance specialized after
## an extension first ran gets it too.
##
## @param module the model, changed in place
## @param state the passes' state: what was applied, and the first error
export apply_extensions(module: Module, state: PassState) {
    ulong index = 0;
    while (index < module.extensions.count) {
        var ext = module.extensions[index];
        if (ext.resolved.is_value()) {
            var target = ext.resolved.value();
            for (var st in module.structs) {
                if (st.name != target and st.ty.to_string() != target) {
                    continue;
                }
                var key = $"{index}\n{st.name}";
                if (state.applied_extensions.contains(key)) {
                    continue;
                }
                state.applied_extensions.insert(key);
                _apply_to_struct(st, ext, module.traits, state);
                # An extension's methods join the struct's overload sets.
                var sets = group_methods(st.method_members, st.name, state);
                if (!sets.is_value()) {
                    return;
                }
                if (sets.value().count > 0) {
                    module.method_overload_sets[st.name] = sets.value();
                }
            }
        }
        index += 1;
    }
}

_extension_method(method: FunctionDef, parent: String): FunctionDef {
    var m = method.copy();
    m.parent = Optional<String>.Value(parent);
    return m;
}

_apply_to_struct(st: StructDef, ext: ExtensionDef, traits: TraitDef[], state: PassState) {
    for (var method in ext.methods) {
        var m = _extension_method(method, st.name);
        if (m.is_generic_func) {
            st.generic_methods.append(m);
        } else {
            st.method_members.append(m);
        }
    }
    for (var trait_name in ext.traits) {
        st.traits.append(trait_name.copy());
        for (var def in traits) {
            if (def.name == trait_name.name) {
                _conform(st, ext, trait_name, def, traits, state);
                break;
            }
        }
    }
}

## `extend S with Trait`: S must have every method the trait declares.
_conform(st: StructDef, ext: ExtensionDef, trait_name: TypeName, def: TraitDef, traits: TraitDef[], state: PassState) {
    # The trait's parameters take the `with` clause's arguments; `this` in a
    # trait signature is the extended struct.
    var type_map = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < def.generic_params.count and i < trait_name.sub_types.count) {
        type_map.append((def.generic_params[i].name, trait_name.sub_types[i]));
        i += 1;
    }
    type_map.append(("this", st.ty));
    type_map.append((TRAIT_SELF, st.ty));
    for (var required in def.methods) {
        # `copies` gives every struct that declares a trait this member.
        if (required.name == _COPY_TRAIT_METHOD) {
            continue;
        }
        if (required.is_generic_func and _has_generic_method(st, required.name)) {
            continue;
        }
        # The struct's methods of the member's name, overloads included; the
        # one with the declared parameter types implements it.
        var set = set_name(required.name);
        var candidates = Array<FunctionDef>();
        for (var m in st.method_members) {
            if (set_name(m.name) == set) {
                candidates.append(m);
            }
        }
        # The deprecated `copy(copies: Copies)` still implements
        # `Copyable<T>` for one release.
        if (def.name == _COPYABLE_TRAIT and _has_deprecated_copy(candidates)) {
            continue;
        }
        var have = Optional<FunctionDef>.Empty;
        for (var c in candidates) {
            if (_same_parameters(c, required, type_map)) {
                have = Optional<FunctionDef>.Value(c);
                break;
            }
        }
        if (have.is_value()) {
            _check_signature(st, have.value(), required, trait_name, type_map, traits, state);
            continue;
        }
        if (candidates.count == 1 and !required.body.is_value() and set == required.name) {
            # Report how the one method of that name differs, unless the
            # trait overloads the name and that method is another member's.
            _check_signature(st, candidates[0], required, trait_name, type_map, traits, state);
            continue;
        }
        # A trait's property is met by a plain field of its name too.
        var accessor = _field_accessor(st, required);
        if (accessor.is_value()) {
            st.method_members.append(accessor.value());
            continue;
        }
        if (required.body.is_value()) {
            var method = _extension_method(required, st.name);
            # A copied default joins the struct's overload set of its name.
            method.name = set;
            var members = Array<String>();
            for (var m in def.methods) {
                members.append(set_name(m.name));
            }
            method.trait_default = Optional<Array<String>>.Value(members);
            method.owner = ext.loc;
            replace_map(method.ty, type_map);
            # `put_all<I: Iterator<T>>` of `Sink<int>`: `I: Iterator<int>`.
            for (var p in method.generic_params) {
                for (var bound in p.bounds) {
                    replace_map(bound.ty, type_map);
                }
            }
            for (var param in method.parameters) {
                replace_map(param.ty, type_map);
            }
            if (method.body.is_value()) {
                substitute_block(method.body.value(), type_map);
            }
            # A generic default method (`map<U>`) is specialized per call.
            if (method.is_generic_func) {
                st.generic_methods.append(method);
            } else {
                st.method_members.append(method);
            }
            continue;
        }
        # An overloaded member is named with its parameter types.
        var property = Optional<String>.Empty;
        if (required.name.starts_with("__get_") or required.name.starts_with("__set_")) {
            property = Optional<String>.Value(required.name.substr_bytes(6, required.name.size - 6));
        }
        var wanted = set;
        if (property.is_value()) {
            wanted = property.value();
        } else if (set != required.name) {
            var params = Array<String>();
            for (var p in required.parameters) {
                var ty = p.ty.copy();
                replace_map(ty, type_map);
                params.append(ty.display());
            }
            wanted = $"{set}({", ".join(params)})";
        }
        var kind = property.is_value() ? "property " : "";
        state.report(
            error_at(
                $"'{st.ty.display()}' does not implement {kind}'{wanted}', required by trait '{trait_name.display()}'",
                ext.loc
            ).with_note($"'{wanted}' declared here", Optional<Location>.Value(location_of(required.loc)))
        );
    }
}

_has_generic_method(st: StructDef, name: String): bool {
    for (var m in st.generic_methods) {
        if (m.name == name) {
            return true;
        }
    }
    return false;
}

_has_deprecated_copy(candidates: FunctionDef[]): bool {
    for (var m in candidates) {
        if (m.name == "copy" and m.parameters.count == 1 and m.parameters[0].ty.name == "_Copies") {
            return true;
        }
    }
    return false;
}

## For a trait property's accessor `required` (`__get_p` or `__set_p`), the
## accessor of a plain field `p` of `st` that meets it.
_field_accessor(st: StructDef, required: FunctionDef): FunctionDef? {
    bool getter = required.name.starts_with("__get_");
    if (!getter and !required.name.starts_with("__set_")) {
        return Optional<FunctionDef>.Empty;
    }
    var name = required.name.substr_bytes(6, required.name.size - 6);
    for (var field in st.field_members) {
        if (field.name != name or field.kind != Kind.Field or field.hidden) {
            continue;
        }
        var at = required.loc;
        var field_ref = Expression.MemberRef(MemberRefExpression(Expression.ThisRef, name, at));
        var statement = Statement.Expression(
            Expression.Binary(
                BinaryExpression(
                    field_ref,
                    Expression.SymbolRef(SymbolRefExpression("value", field.ty.copy(), at)),
                    BinaryOp.Assign,
                    at
                )
            )
        );
        if (getter) {
            statement = Statement.Return(ReturnStatement(Optional<Expression>.Value(field_ref), at));
        }
        var accessor = _extension_method(required, st.name);
        accessor.ty = getter ? field.ty.copy() : TypeName.void();
        if (accessor.parameters.count > 0) {
            accessor.parameters[0].ty = field.ty.copy();
        }
        var items = Array<Statement>();
        items.append(statement);
        accessor.body = Optional<Block>.Value(Block("", items));
        return Optional<FunctionDef>.Value(accessor);
    }
    return Optional<FunctionDef>.Empty;
}

## Whether `have` takes the parameter types trait member `required`
## declares (with the trait's type arguments substituted).
_same_parameters(have: FunctionDef, required: FunctionDef, type_map: Array<(String, TypeName)>): bool {
    if (have.is_static != required.is_static or have.parameters.count != required.parameters.count) {
        return false;
    }
    ulong i = 0;
    while (i < have.parameters.count) {
        var declared = required.parameters[i].ty.copy();
        replace_map(declared, type_map);
        if (_canonical(have.parameters[i].ty) != _canonical(declared)) {
            return false;
        }
        i += 1;
    }
    return true;
}

## The declared type with the trait's arguments substituted; a method
## declared without a return type returns nothing.
_declared_type(ty: TypeName, type_map: Array<(String, TypeName)>): TypeName {
    var out = ty.copy();
    replace_map(out, type_map);
    return out.is_auto() ? TypeName.void() : out;
}

_actual_type(ty: TypeName): TypeName {
    return ty.is_auto() ? TypeName.void() : ty;
}

## A struct, not a number, `bool`, enum or SIMD vector: `TypeName::is_struct`.
_is_struct_type(ty: TypeName, state: PassState): bool {
    return ty.is_scalar() and !state.is_integral(ty.name) and ty.name != SIMD;
}

## A trait method's implementation must have the declared signature, except
## that where the trait returns a trait type, the implementation may return
## a struct (`convert_to_traits` checks it conforms).
_check_signature(
    st: StructDef,
    have: FunctionDef,
    required: FunctionDef,
    trait_name: TypeName,
    type_map: Array<(String, TypeName)>,
    traits: TraitDef[],
    state: PassState
) {
    var expected_params = Array<TypeName>();
    for (var p in required.parameters) {
        expected_params.append(_declared_type(p.ty, type_map));
    }
    var found_params = Array<TypeName>();
    for (var p in have.parameters) {
        found_params.append(_actual_type(p.ty));
    }
    var have_ret = _actual_type(have.ty);
    var declared_ret = _declared_type(required.ty, type_map);
    bool covariant = trait_def(traits, declared_ret).is_value()
        and !trait_def(traits, have_ret).is_value()
        and _is_struct_type(have_ret, state)
        and !have_ret.is_pointer();
    bool same = have.is_static == required.is_static
        and have.parameters.count == required.parameters.count
        and (covariant or _canonical(have_ret) == _canonical(declared_ret));
    ulong i = 0;
    while (same and i < have.parameters.count) {
        same = _canonical(found_params[i]) == _canonical(expected_params[i]);
        i += 1;
    }
    if (same) {
        return;
    }
    var expected = _function_type(declared_ret, expected_params).display();
    var found = _function_type(have_ret, found_params).display();
    state.report(
        error_at(
            $"'{have.name}' in '{st.ty.display()}' has type '{found}', but trait '{trait_name.display()}' declares '{expected}'",
            have.loc
        ).with_note($"'{required.name}' declared here", Optional<Location>.Value(location_of(required.loc)))
    );
}

## Warns where a method that implements a trait's member names a parameter
## differently from the trait, with a fix that renames it and its uses, as
## `apply_extensions::check_parameter_names` does: a call names the
## arguments of whichever it reaches.
##
## @param module the model
## @param state the passes' state, which takes the warnings
export check_parameter_names(module: Module, state: PassState) {
    var seen = HashSet<Loc>();
    for (var ext in module.extensions) {
        if (!ext.resolved.is_value()) {
            continue;
        }
        var target = ext.resolved.value();
        var st = Optional<StructDef>.Empty;
        for (var s in module.structs) {
            if (s.name == target) {
                st = Optional<StructDef>.Value(s);
                break;
            }
        }
        var methods = ext.methods.copy();
        if (st.is_value()) {
            methods.append_all(st.value().method_members);
        }
        for (var trait_name in ext.traits) {
            var def = Optional<TraitDef>.Empty;
            for (var t in module.traits) {
                if (t.name == trait_name.name) {
                    def = Optional<TraitDef>.Value(t);
                    break;
                }
            }
            if (!def.is_value()) {
                continue;
            }
            var type_map = Array<(String, TypeName)>();
            ulong i = 0;
            while (i < def.value().generic_params.count and i < trait_name.sub_types.count) {
                type_map.append((def.value().generic_params[i].name, trait_name.sub_types[i]));
                i += 1;
            }
            if (st.is_value()) {
                type_map.append(("this", st.value().ty));
            }
            for (var required in def.value().methods) {
                var set = set_name(required.name);
                var candidates = Array<FunctionDef>();
                for (var m in methods) {
                    if (set_name(m.name) == set and m.parameters.count == required.parameters.count) {
                        candidates.append(m);
                    }
                }
                var have = Optional<FunctionDef>.Empty;
                if (candidates.count == 1) {
                    have = Optional<FunctionDef>.Value(candidates[0]);
                } else {
                    for (var c in candidates) {
                        if (_same_parameters(c, required, type_map)) {
                            have = Optional<FunctionDef>.Value(c);
                            break;
                        }
                    }
                }
                if (!have.is_value()) {
                    continue;
                }
                var implementation = have.value();
                # A default the trait gave the struct is the trait's own.
                if (implementation.loc == required.loc or seen.contains(implementation.loc)) {
                    continue;
                }
                seen.insert(implementation.loc);
                _check_names(implementation, required, set, trait_name, state);
            }
        }
    }
}

_parameter_names_of(function: FunctionDef): String[] {
    var out = Array<String>();
    for (var p in Callee.of(function, "", 0, Array<String>()).params) {
        out.append(p.name);
    }
    return out;
}

_check_names(have: FunctionDef, required: FunctionDef, set: String, trait_name: TypeName, state: PassState) {
    var names = _parameter_names_of(have);
    var wanted_names = _parameter_names_of(required);
    ulong i = 0;
    while (i < names.count and i < wanted_names.count and i < have.parameters.count) {
        var name = names[i];
        var wanted = wanted_names[i];
        var param = have.parameters[i];
        i += 1;
        if (name == "this" or name == wanted or param.loc.is_none()) {
            continue;
        }
        var locs = Array<Loc>();
        locs.append(param.loc);
        if (have.body.is_value()) {
            var finder = _UseFinder(name, param.loc.file);
            rewrite_block(have.body.value(), finder);
            locs.append_all(finder.found);
        }
        locs.sort((a, b) => a.span.start < b.span.start ? -1 : (a.span.start > b.span.start ? 1 : 0));
        var fix = Fix($"rename '{name}' to '{wanted}'", location_of(locs[0]), wanted);
        ulong k = 1;
        while (k < locs.count) {
            if (locs[k].span.start != locs[k - 1].span.start) {
                fix.edits.append(Edit(location_of(locs[k]), wanted));
            }
            k += 1;
        }
        state.notes.append(
            Diagnostic
                .warning($"parameter '{name}' of '{set}' is named '{wanted}' in trait '{trait_name.display()}'")
                .at(location_of(param.loc))
                .with_note($"'{set}' declared here", Optional<Location>.Value(location_of(required.loc)))
                .with_fix(fix)
        );
    }
}

## Where a body uses a parameter: each symbol of its name in its file.
struct _UseFinder {
    var name: String;
    var file: uint;
    var found: Array<Loc> = Array<Loc>();

    construct(name: String, file: uint) {
        this.name = name;
        this.file = file;
    }

    rewrite(e: Expression): Expression {
        if (e is SymbolRef(node)) {
            if (node.id == name and node.loc.file == file) {
                found.append(node.loc);
            }
        }
        return e;
    }
}

extend _UseFinder with Rewriter;
