## Overloaded free functions and methods, named:
## `pepper_sema::passes::overloads::name_overloads` in Pepper. Each file's
## same-name free functions are checked against one another, and the
## members of each set of two or more are renamed `name$1`, `name$2`, … in
## declaration order and recorded in `Module.overload_sets`; methods the
## same way in `Module.method_overload_sets`. Concrete overrides
## (`hash<Point>`) take their specialization's name first, so they never
## join a set.

import [Diagnostic, Location] from compiler.diagnostic;
import [demangle_name, is_concrete_override, is_override, NAMESPACE_SEPARATOR, OVERLOAD_SEPARATOR] from compiler.link;
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [ExternDef, FunctionDef, GenericParam, Module, StructDef, TypeName] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [parse_type_string, replace_map] from "type_name";

## Whether `function` is a concrete override (`hash<Point>`), which
## customizes a generic rather than overloading it.
_is_override(function: FunctionDef): bool {
    if (function.name.contains("<")) {
        return true;
    }
    var names = Array<String>();
    bool unbounded = true;
    for (var p in function.generic_params) {
        if (p.is_argument) {
            return true;
        }
        if (p.bounds.count > 0) {
            unbounded = false;
        }
        names.append(p.name);
    }
    return unbounded and is_override(names);
}

## What makes two members the same overload: their parameter types, with
## generic parameters named by position (`f<T>(T)` and `f<U>(U)` clash).
_parameter_key(function: FunctionDef): String {
    var positional = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < function.generic_params.count) {
        positional.append((function.generic_params[i].name, TypeName.named($"${i}")));
        i += 1;
    }
    var key = $"{function.generic_params.count}";
    for (var p in function.parameters) {
        var ty = p.ty.copy();
        replace_map(ty, positional);
        key = key + "\n" + _canonical(ty).to_string();
    }
    return key;
}

_return_key(function: FunctionDef): String {
    return _canonical(function.ty).to_string();
}

## The error for `later`, which takes the parameters `earlier` does.
_clash(name: String, later: FunctionDef, earlier: FunctionDef): Diagnostic {
    if (_return_key(earlier) == _return_key(later)) {
        return error_at(
            $"redefinition of '{name}'", later.loc
        ).with_note("previous definition is here", Optional<Location>.Value(location_of(earlier.loc)));
    }
    return error_at(
        "functions that differ only in their return type cannot be overloaded", later.loc
    ).with_note("previous declaration is here", Optional<Location>.Value(location_of(earlier.loc)));
}

## The first member of `members` (indices into `functions`) that takes the
## parameters of an earlier one, with that earlier one.
_first_clash(functions: FunctionDef[], members: ulong[]): (ulong, ulong)? {
    var keys = Array<String>();
    for (var i in members) {
        keys.append(_parameter_key(functions[i]));
    }
    ulong j = 0;
    while (j < members.count) {
        ulong k = 0;
        while (k < j) {
            if (keys[k] == keys[j]) {
                return Optional<(ulong, ulong)>.Value((members[j], members[k]));
            }
            k += 1;
        }
        j += 1;
    }
    return Optional<(ulong, ulong)>.Empty;
}

## A group of functions or externs: its file, its name and its members.
struct _Group {
    var file: uint;
    var name: String;
    var members: Array<ulong> = Array<ulong>();

    construct(file: uint, name: String) {
        this.file = file;
        this.name = name;
    }
}

## Groups keyed by file and name, in that order (as a `BTreeMap` of
## `(u32, String)` orders them).
struct _Groups {
    var groups: Array<_Group> = Array<_Group>();
    var index: HashMap<String, ulong> = HashMap<String, ulong>();

    add(file: uint, name: String, member: ulong) {
        var key = $"{file}\n{name}";
        if (!index.contains(key)) {
            index[key] = groups.count;
            groups.append(_Group(file, name));
        }
        groups[index[key]].members.append(member);
    }

    sorted(): _Group[] {
        var out = groups.copy();
        out.sort((a: _Group, b: _Group) => {
            if (a.file != b.file) {
                return a.file < b.file ? -1 : 1;
            }
            return _compare_bytes(a.name, b.name) as int;
        });
        return out;
    }
}

## Checks each file's same-name free functions and renames the members of
## every overload set, as `overloads::name_overloads` does.
##
## @param module the model, changed in place
## @param state the passes' state
export name_overloads(module: Module, state: PassState) {
    concrete_overrides(module);
    var shared = _replace_prelude_members(module);
    var grouping = _Groups();
    ulong i = 0;
    while (i < module.functions.count) {
        var function = module.functions[i];
        if (!_is_override(function)) {
            var file = shared.contains(function.name) ? shared[function.name] : function.loc.file;
            grouping.add(file, function.name, i);
        }
        i += 1;
    }
    var groups = grouping.sorted();
    for (var group in groups) {
        # An extern names one C symbol, so it cannot share its name with
        # another function of the file; redeclaring the same prototype is
        # allowed.
        var externs = Array<ExternDef>();
        for (var e in module.externs) {
            if (e.loc.file == group.file and e.name == group.name) {
                externs.append(e);
            }
        }
        if (group.members.count > 0 and externs.count > 0) {
            var function = module.functions[group.members[0]];
            var later = function.loc;
            var earlier = externs[0].loc;
            if (function.loc.span.start <= externs[0].loc.span.start) {
                later = externs[0].loc;
                earlier = function.loc;
            }
            var name = demangle_name(group.name);
            state.report(
                error_at(
                    $"extern '{name}' cannot be overloaded; rename it and overload Pepper functions named '{name}' that call it",
                    later
                ).with_note("previous declaration is here", Optional<Location>.Value(location_of(earlier)))
            );
            return;
        }
        if (group.members.count < 2) {
            continue;
        }
        var clash = _first_clash(module.functions, group.members);
        if (clash.is_value()) {
            var (later, earlier) = clash.value();
            state.report(_clash(demangle_name(group.name), module.functions[later], module.functions[earlier]));
            return;
        }
    }
    var extern_groups = _Groups();
    i = 0;
    while (i < module.externs.count) {
        extern_groups.add(module.externs[i].loc.file, module.externs[i].name, i);
        i += 1;
    }
    for (var group in extern_groups.sorted()) {
        var first = module.externs[group.members[0]];
        var prototype = _prototype(first);
        ulong k = 1;
        while (k < group.members.count) {
            var other = module.externs[group.members[k]];
            if (_prototype(other) != prototype) {
                state.report(
                    error_at(
                        $"extern '{first.name}' cannot be overloaded; rename it and overload Pepper functions named '{first.name}' that call it",
                        other.loc
                    ).with_note("previous declaration is here", Optional<Location>.Value(location_of(first.loc)))
                );
                return;
            }
            k += 1;
        }
    }
    if (!_check_constructors(module, state) or !_name_method_overloads(module, state)) {
        return;
    }
    for (var group in groups) {
        if (group.members.count < 2) {
            continue;
        }
        var names = Array<String>();
        for (var index in group.members) {
            var member = signature_member(group.name, module.functions[index], names);
            module.functions[index].name = member;
            names.append(member);
        }
        module.overload_sets[group.name] = names;
    }
    if (!_name_unions(module, state)) {
        return;
    }
    _attach_overrides(module, state);
}

_prototype(e: ExternDef): String {
    var out = Array<String>();
    for (var p in e.parameters) {
        out.append(_canonical(p.ty).to_string());
    }
    out.append(_canonical(e.ty).to_string());
    out.append(e.is_variadic ? "variadic" : "fixed");
    return "\n".join(out);
}

## Records each set that spans files with the members of every set or
## function it joins, after checking that no two members of one module
## take the same parameters. Returns false after reporting an error.
_name_unions(module: Module, state: PassState): bool {
    var unions = Array<(String, Array<Array<String>>)>();
    for (var (union, groups) in module.overload_unions) {
        unions.append((union, groups));
    }
    for (var (union, groups) in unions) {
        var names = Array<String>();
        for (var parts in groups) {
            var members = Array<ulong>();
            for (var part in parts) {
                var expanded = Array<String>();
                if (module.overload_sets.contains(part)) {
                    expanded = module.overload_sets[part].copy();
                } else {
                    expanded.append(part);
                }
                for (var member in expanded) {
                    ulong i = 0;
                    while (i < module.functions.count) {
                        if (module.functions[i].name == member) {
                            members.append(i);
                            break;
                        }
                        i += 1;
                    }
                }
            }
            var clash = _first_clash(module.functions, members);
            if (clash.is_value()) {
                var (later, earlier) = clash.value();
                var function = module.functions[later];
                state.report(_clash(demangle_name(function.name), function, module.functions[earlier]));
                return false;
            }
            for (var m in members) {
                names.append(module.functions[m].name);
            }
        }
        module.overload_sets[union] = names;
    }
    return true;
}

## Only prelude files may export the same name, and the first definition
## wins: a forced import's `assert(bool, __ptr<char>)` replaces the
## runtime's member with those parameters and joins the rest of its set.
## Removes each replaced member and returns the names so shared, each with
## the first file declaring it.
_replace_prelude_members(module: Module): HashMap<String, uint> {
    # By name, then by file (in file order): the members.
    var files = HashMap<String, Map<uint, Array<ulong>>>();
    ulong i = 0;
    while (i < module.functions.count) {
        var function = module.functions[i];
        if (!_is_override(function) and !function.name.contains(NAMESPACE_SEPARATOR)) {
            if (!files.contains(function.name)) {
                files[function.name] = Map<uint, Array<ulong>>();
            }
            var by_file = files[function.name];
            if (!by_file.contains(function.loc.file)) {
                by_file[function.loc.file] = Array<ulong>();
            }
            by_file[function.loc.file].append(i);
        }
        i += 1;
    }
    var shared = HashMap<String, uint>();
    var replaced = HashSet<ulong>();
    for (var (name, by_file) in files.iterate()) {
        if (by_file.count < 2) {
            continue;
        }
        var seen = HashSet<String>();
        bool first = true;
        for (var (file, members) in by_file) {
            if (first) {
                shared[name] = file;
                first = false;
            }
            var keys = Array<String>();
            for (var m in members) {
                keys.append(_parameter_key(module.functions[m]));
            }
            ulong k = 0;
            while (k < members.count) {
                if (seen.contains(keys[k])) {
                    replaced.insert(members[k]);
                }
                k += 1;
            }
            for (var key in keys) {
                seen.insert(key);
            }
        }
    }
    if (replaced.count > 0) {
        var kept = Array<FunctionDef>();
        i = 0;
        while (i < module.functions.count) {
            if (!replaced.contains(i)) {
                kept.append(module.functions[i]);
            }
            i += 1;
        }
        module.functions = kept;
    }
    return shared;
}

## Checks that no two constructors of a struct take the same parameters.
## Returns false after reporting an error.
_check_constructors(module: Module, state: PassState): bool {
    for (var st in module.structs) {
        if (st.constructors.count < 2) {
            continue;
        }
        var keys = Array<String>();
        for (var c in st.constructors) {
            keys.append(_parameter_key(c));
        }
        ulong j = 0;
        while (j < keys.count) {
            ulong k = 0;
            while (k < j) {
                if (keys[k] == keys[j]) {
                    state.report(
                        error_at(
                            $"constructor of '{demangle_name(st.name)}' cannot be redeclared",
                            st.constructors[j].loc
                        ).with_note(
                            "previous declaration is here",
                            Optional<Location>.Value(location_of(st.constructors[k].loc))
                        )
                    );
                    return false;
                }
                k += 1;
            }
            j += 1;
        }
    }
    return true;
}

## Checks each struct's and trait's same-name methods and renames the
## members of every method overload set (`get$1`, `get$2`), recording them
## in `Module.method_overload_sets`. Returns false after reporting an
## error.
_name_method_overloads(module: Module, state: PassState): bool {
    for (var st in module.structs) {
        var sets = group_struct_methods(st, state);
        if (!sets.is_value()) {
            return false;
        }
        if (sets.value().count > 0) {
            module.method_overload_sets[st.name] = sets.value();
        }
    }
    # A trait's overloads: each member is its own vtable slot.
    for (var t in module.traits) {
        var sets = group_methods(t.methods, t.name, state);
        if (!sets.is_value()) {
            return false;
        }
        if (sets.value().count > 0) {
            module.method_overload_sets[t.name] = sets.value();
        }
    }
    return true;
}

## Groups a struct's methods into overload sets as `group_methods` does,
## its generic methods included: `f(bool)` and `f<T>(T?)` are members of
## one set, which resolution chooses among as it does for free functions.
## As `overloads::group_struct_methods` does.
##
## @param st the struct, whose methods are renamed in place
## @param state the passes' state
## @returns the sets, or none after reporting an error
export group_struct_methods(st: StructDef, state: PassState): Map<String, Array<String>>? {
    var all = Array<FunctionDef>();
    all.append_all(st.method_members);
    all.append_all(st.generic_methods);
    return group_methods(all, st.name, state);
}

## Groups the methods of struct or trait `owner` into overload sets by set
## name, checks each set, and names the members of every set of two or
## more: a member already named (`get$1`) keeps its name and a new one
## takes the next ordinal, as `overloads::group_methods` does.
##
## @param methods the methods, renamed in place
## @param owner the struct or trait
## @param state the passes' state
## @returns the sets, or none after reporting an error
export group_methods(methods: FunctionDef[], owner: String, state: PassState): Map<String, Array<String>>? {
    var groups = Map<String, Array<ulong>>();
    ulong i = 0;
    while (i < methods.count) {
        var name = set_name(methods[i].name);
        if (!groups.contains(name)) {
            groups[name] = Array<ulong>();
        }
        groups[name].append(i);
        i += 1;
    }
    var sets = Map<String, Array<String>>();
    for (var (name, members) in groups) {
        if (members.count < 2) {
            continue;
        }
        var first = methods[members[0]];
        # Inside a method a bare `open(p)` could mean either kind.
        for (var other in members) {
            if (methods[other].is_static != first.is_static) {
                var static_one = first.is_static ? first : methods[other];
                var instance = first.is_static ? methods[other] : first;
                var later = static_one.loc.span.start > instance.loc.span.start ? static_one : instance;
                var earlier = static_one.loc.span.start > instance.loc.span.start ? instance : static_one;
                state.report(
                    error_at(
                        $"static method '{name}' cannot share its name with an instance method of '{demangle_name(owner)}'",
                        later.loc
                    ).with_note("previous declaration is here", Optional<Location>.Value(location_of(earlier.loc)))
                );
                return Optional<Map<String, Array<String>>>.Empty;
            }
        }
        var clash = _first_clash(methods, members);
        if (clash.is_value()) {
            var (later, earlier) = clash.value();
            state.report(_clash(name, methods[later], methods[earlier]));
            return Optional<Map<String, Array<String>>>.Empty;
        }
        var named = Array<String>();
        for (var m in members) {
            if (methods[m].name != name) {
                named.append(methods[m].name);
            }
        }
        var names = Array<String>();
        for (var m in members) {
            if (methods[m].name == name) {
                methods[m].name = signature_member(name, methods[m], named);
                named.append(methods[m].name);
            }
            names.append(methods[m].name);
        }
        sets[name] = names;
    }
    return Optional<Map<String, Array<String>>>.Value(sets);
}

## The name of `function` as a member of overload set `set`: the set's
## name, `$`, and a number made from its signature (its generic parameters,
## parameter types and whether it is static). A member's name depends only
## on its own declaration, not on the other members or the order files are
## checked in, so units checked apart (an extension in one file adding an
## overload to a struct declared in another) name the same members alike.
## Two signatures with the same number, which `taken` shows, take the next
## free one.
##
## @param set the set's name
## @param function the member
## @param taken the names the set's other members have
## @returns the member's name
export signature_member(set: String, function: FunctionDef, taken: String[]): String {
    var signature = StringBuilder();
    signature.append($"{function.generic_params.count}");
    for (var p in function.parameters) {
        signature.append(",");
        signature.append(p.ty.to_string());
    }
    if (function.is_static) {
        signature.append(",static");
    }
    # FNV-1a, 32 bits: a short number of digits, which `set_name` reads.
    ulong hash = 2166136261;
    for (var b in signature.to_string().bytes()) {
        hash = ((hash ^ (b as ulong)) * 16777619) & 0xffffffff;
    }
    var member = $"{set}{OVERLOAD_SEPARATOR}{hash}";
    while (taken.contains(member)) {
        hash = (hash + 1) & 0xffffffff;
        member = $"{set}{OVERLOAD_SEPARATOR}{hash}";
    }
    return member;
}

## A concrete override of an overloaded generic (`hash<Point>` with two
## generic `hash` members) overrides the member whose parameters, with the
## override's type arguments substituted, are the override's.
_attach_overrides(module: Module, state: PassState) {
    if (module.overload_sets.count == 0) {
        return;
    }
    ulong i = 0;
    while (i < module.functions.count) {
        var function = module.functions[i];
        var at = function.name.find("<");
        if (at < 0) {
            i += 1;
            continue;
        }
        var base = function.name.substr_bytes(0, at as ulong);
        if (!module.overload_sets.contains(base)) {
            i += 1;
            continue;
        }
        var args = parse_type_string(function.name).sub_types;
        var params = Array<String>();
        for (var p in function.parameters) {
            params.append(_canonical(p.ty).to_string());
        }
        var matching = Array<String>();
        for (var member in module.overload_sets[base]) {
            if (_overrides(module, member, args, params)) {
                matching.append(member);
            }
        }
        if (matching.count != 1) {
            state.report(
                error_at(
                    $"override '{demangle_name(function.name)}' matches {matching.count == 0 ? "none" : "several"} of the overloads of '{demangle_name(base)}'; it must match exactly one",
                    function.loc
                )
            );
            return;
        }
        function.name = TypeName.with_args(matching[0], args).to_string();
        i += 1;
    }
}

## Whether the member named `member`, specialized with `args`, takes
## parameters `params` (canonical).
_overrides(module: Module, member: String, args: TypeName[], params: String[]): bool {
    for (var m in module.functions) {
        if (m.name != member) {
            continue;
        }
        if (m.generic_params.count != args.count or m.parameters.count != params.count) {
            return false;
        }
        var map = Array<(String, TypeName)>();
        ulong k = 0;
        while (k < args.count) {
            map.append((m.generic_params[k].name, args[k]));
            k += 1;
        }
        k = 0;
        while (k < params.count) {
            var ty = m.parameters[k].ty.copy();
            replace_map(ty, map);
            if (_canonical(ty).to_string() != params[k]) {
                return false;
            }
            k += 1;
        }
        return true;
    }
    return false;
}

## Concrete specializations written as definitions override generic bases:
## each free function whose generic parameters are all concrete types
## (`hash<String>`) becomes its specialization (`name<args>`), as
## `gather_generics::concrete_overrides` does.
##
## @param module the model, changed in place
export concrete_overrides(module: Module) {
    var struct_names = HashSet<String>();
    for (var st in module.structs) {
        struct_names.insert(st.ty.name);
    }
    var rewrites = Array<(ulong, String)>();
    ulong index = 0;
    while (index < module.functions.count) {
        var function = module.functions[index];
        index += 1;
        # A constrained name (`describe<T: Shape>`) is always a parameter.
        if (function.generic_params.count == 0) {
            continue;
        }
        bool bounded = false;
        bool argument = false;
        var params = Array<String>();
        for (var p in function.generic_params) {
            if (p.bounds.count > 0) {
                bounded = true;
            }
            if (p.is_argument) {
                argument = true;
            }
            params.append(p.name);
        }
        if (bounded) {
            continue;
        }
        bool all_concrete = is_concrete_override(params) or argument;
        if (!all_concrete and !module.linked) {
            bool all_types = true;
            for (var p in params) {
                if (!_names_type(p, struct_names)) {
                    all_types = false;
                }
            }
            all_concrete = all_types and _has_base(module, function, struct_names);
        }
        if (all_concrete) {
            rewrites.append((index - 1, $"{function.name}<{", ".join(params)}>"));
        }
    }
    if (rewrites.is_empty) {
        return;
    }
    # A new list, so what was found from the old one (`layer_decls`) is
    # found again.
    var functions = module.functions.clone();
    for (var (i, name) in rewrites) {
        var concrete = functions[i].copy();
        concrete.name = name;
        concrete.generic_params = Array<GenericParam>();
        concrete.is_generic_func = false;
        functions[i] = concrete;
    }
    module.functions = functions;
}

_names_type(name: String, struct_names: HashSet<String>): bool {
    return is_concrete_override([name]) or struct_names.contains(name);
}

## Whether a generic base of `function`'s name and arity exists: one with
## a parameter that names no type.
_has_base(module: Module, function: FunctionDef, struct_names: HashSet<String>): bool {
    for (var other in module.functions) {
        if (other.name != function.name or other.generic_params.count != function.generic_params.count) {
            continue;
        }
        for (var p in other.generic_params) {
            if (p.bounds.count > 0 or !_names_type(p.name, struct_names)) {
                return true;
            }
        }
    }
    return false;
}
