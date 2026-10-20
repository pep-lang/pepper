## Implicit types.
## Each `auto` variable takes the type of its initializer, each unresolved
## name the type of what it names, each function declared without a return
## type the type its returns agree on, and calls to overload sets and
## generic functions the member or specialization their arguments select.
## Property accesses, calls through function values, calls on enum values
## and operators a number type's extension declares are rewritten on the
## way. Return types feed callers and closure types feed their creations,
## so the pass repeats while anything changes (at most eight times).

import [binary_result, conditional_result, int_literal_type, is_numeric_type] from "arithmetic";
import [enum_method_name, getter_name] from "builder";
import [has_body, is_checked_function, unit_decls] from "checked";
import [
    ModuleTables, rewrite_module, select_sites, select_sites_each, SiteFilter, SiteSelection, sync_closures
] from "closure_sites";
import "closures";
import [entry_function, MAIN_WITH_ARGUMENTS] from "entry_point";
import [call_on_value, case_value_type, FieldTypes, is_enum, method_read] from "enums";
import [Fingerprint] from "fingerprint";
import [
    bind_generic_function_values,
    bind_generic_method_values,
    generic_function_search,
    generic_method_search,
    GenericFunctionSearch,
    GenericMethodSearch
] from "generic_values";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Declaration,
    Expression,
    ExtensionDef,
    FunctionCallExpression,
    FunctionDef,
    FunctionRefExpression,
    InvokeExpression,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    Statement,
    StructDef,
    SymbolRefExpression,
    TypeName,
    UnaryExpression,
    UnaryOp,
    VariableDef
] from "model";
import [bind_method_call, Callees, has_named, report_function_value] from "named_arguments";
import [set_name] from "names";
import [is_comparison, op_name, simd_result, weak_result] from "operators";
import [
    apply_choice,
    arg_info,
    ArgInfo,
    bind_function_values,
    Choice,
    function_value_search,
    FunctionValueSearch,
    method_target,
    Overloads
] from "overload_select";
import [lower_property, Properties, PropertySite] from "properties";
import [ImplicitMemo, PassMemo, PassState] from "state";
import [instance, trait_def, trait_types_of, used_trait_types] from "traits";
import [labeled_tuple_literal_type, tuple_constructor_labels, tuple_literal_type] from "tuple_literals";
import [GenericSignature, record_conformances, specialization] from "type_arguments";
import [FUNCTION, parse_type_string, replace_map, VOID, without_pointer_names] from "type_name";
import [is_value_type, method_is_static, value_type_key] from "value_types";
import [Rewriter, rewrite_expression] from "walk";

## The keys of the number types and `bool`.
_number_keys(): String[] {
    return ["i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f32", "f64", "bool"];
}

## How many arguments the methods of one name take: the name (an overload
## set's members share their set's name), and the fewest and most.
## Generic methods count too: in `read<T>()`'s specialization a bare
## `read<T>(x)` calls its overload before that is specialized, not a free
## function `read`.
_method_arities(st: StructDef): Array<(String, ulong, ulong)> {
    var out = Array<(String, ulong, ulong)>();
    var members = Array<FunctionDef>();
    members.append_all(st.method_members);
    members.append_all(st.generic_methods);
    for (var m in members) {
        ulong fewest = 0;
        for (var p in m.parameters) {
            if (!p.default.is_value()) {
                fewest += 1;
            }
        }
        out.append((set_name(m.name), fewest, m.parameters.count));
    }
    return out;
}

_takes(arities: Array<(String, ulong, ulong)>, name: String, count: ulong): bool {
    var set = set_name(name);
    for (var (arity, fewest, most) in arities) {
        if (arity == set and count >= fewest and count <= most) {
            return true;
        }
    }
    return false;
}

# `st`'s methods (name, type) and arities: a checked struct's from `memo`
# while it is the same struct with as many fields and methods, since its
# methods' types were final when it was checked.
_struct_parts(
    module: Module, st: StructDef, memo: ImplicitMemo
): (Array<(String, TypeName)>, Array<(String, ulong, ulong)>) {
    var checked = module.checked.structs.contains(st.name);
    var fields = st.field_members.count;
    var count = st.method_members.count;
    if (checked) {
        var kept = memo.struct_parts.try_get(st.name);
        if (kept.is_value()) {
            var (was, kept_fields, kept_methods, methods, arities) = kept.value();
            if (was === st and kept_fields == fields and kept_methods == count) {
                return (methods, arities);
            }
        }
    }
    var own = Array<(String, TypeName)>();
    for (var m in st.method_members) {
        own.append((m.name, m.ty));
    }
    var arities = _method_arities(st);
    if (checked) {
        memo.struct_parts[st.name] = (st, fields, count, own, arities);
    }
    return (own, arities);
}

_function_type(ret: TypeName, params: TypeName[]): TypeName {
    var args = Array<TypeName>();
    args.append(ret);
    args.append_all(params);
    return TypeName.with_args(FUNCTION, args);
}

## Free functions that can be referenced by name as values.
##
## With `checked` set, only the checked functions (`true`), or only the
## others and the externs (`false`).
_referenceable_functions(
    module: Module, state: PassState, checked: bool? = Optional<bool>.Empty
): Array<(String, TypeName)> {
    var out = Array<(String, TypeName)>();
    # The unchecked functions are the unit's own: no checked one to skip.
    var functions = checked.is_value() and !checked.value() ? unit_decls(module).functions : module.functions;
    for (var f in functions) {
        # The cheapest test first: most of a compilation unit's functions are checked.
        if (checked.is_value() and is_checked_function(module, f) != checked.value()) {
            continue;
        }
        if (f.is_generic_func or f.name.contains("<") or !has_body(module, state, f)) {
            continue;
        }
        var params = Array<TypeName>();
        for (var p in f.parameters) {
            params.append(p.ty);
        }
        out.append((f.name, _function_type(f.ty.is_auto() ? TypeName.void() : f.ty, params)));
    }
    for (var e in module.externs) {
        if (e.is_variadic or (checked.is_value() and checked.value())) {
            continue;
        }
        var params = Array<TypeName>();
        for (var p in e.parameters) {
            params.append(p.ty);
        }
        out.append((e.name, _function_type(e.ty.is_auto() ? TypeName.void() : e.ty, params)));
    }
    return out;
}

_first_wins(map: HashMap<String, TypeName>, key: String, value: TypeName) {
    if (!map.contains(key)) {
        map[key] = value;
    }
}

_before_angle(text: String): String {
    var at = text.find("<");
    return at < 0 ? text : text.substr_bytes(0, at as ulong);
}

## The key under which a lookup of struct or trait type `key`'s fields
## is noted, and under which a change to them is announced: its spelling,
## under any pointer. Methods have their own keys (`_method_read`).
_type_read(key: String): String {
    return $"t:{without_pointer_names(key)}";
}

## The key under which a lookup of method `name` of struct or trait type
## `key` is noted, and under which a change to its return type is
## announced: the type under any pointer, and the name before any `$` or
## `@`, so an overload set and its members share it.
_method_read(key: String, name: String): String {
    var base = without_pointer_names(key);
    var bytes = name.bytes();
    ulong end = 0;
    while (end < bytes.count and bytes[end] != '$' as u8 and bytes[end] != '@' as u8) {
        end += 1;
    }
    return $"m:{base}.{name.substr_bytes(0, end)}";
}

## The key of every specialization of `key`'s base type: overload sets
## spell their receivers their own way, so a lookup of one notes this key
## too, and a change to any specialization announces it.
_base_read(key: String): String {
    return $"b:{_before_angle(without_pointer_names(key))}";
}

## The key under which a lookup of free function `name` (or the overload
## set or generic it belongs to) is noted, and under which a change to its
## type is announced: the name before any `$`, `<` or `@`.
_function_read(name: String): String {
    var bytes = name.bytes();
    ulong end = 0;
    while (end < bytes.count and bytes[end] != '$' as u8 and bytes[end] != '<' as u8 and bytes[end] != '@' as u8) {
        end += 1;
    }
    return $"f:{name.substr_bytes(0, end)}";
}

## Which callables a run of the pass walks again. A walk's result depends
## only on the callable's code and on what it looks up, and the pass only
## ever replaces `auto`: a callable whose code is as its last walk left it,
## whose last walk changed nothing, and none of whose lookups changed
## since, would come out of another walk unchanged, so it is skipped. The
## worklist lives on in `PassState.implicit` between runs of the pass:
## specialization rounds add code and change little of what was there.
struct _Worklist {
    ## What each callable looked up in its last walk, by its place
    ## (`s<struct>m<method>`, `f<function>`, ...); a callable whose last
    ## walk changed it is absent.
    var reads: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>();
    ## Each callable's fingerprint after its last walk, by its place: code
    ## another pass changed since is walked again.
    var prints: HashMap<String, ulong> = HashMap<String, ulong>();
    ## What changed since the last run: return types, fields and globals
    ## the pass typed, and declarations other passes added or changed.
    var changed: HashSet<String> = HashSet<String>();
    ## The next run changes into this.
    var changing: HashSet<String> = HashSet<String>();
    ## Every callable is walked: nothing is known of earlier walks.
    var all: bool = true;
    ## The callables whose last walk made a selection settling overloads
    ## by arity could change (`Overloads.settleable`), by place.
    var unsettled: HashSet<String> = HashSet<String>();
    ## This run settles overloads by arity: the unsettled callables are
    ## walked too.
    var settling: bool = false;
    # `Overloads.settleable` when the callable being walked was started.
    var _settle_mark: ulong = 0;
    ## Whether other passes may have changed code since the last run, so
    ## each callable's code is checked against its fingerprint.
    var checks_code: bool = true;
    ## How many changes this run made to the code it walked.
    var edits: ulong = 0;

    construct() {}

    ## Picks up where the last run of the pass left off.
    ##
    ## @param memo what it left
    construct(memo: ImplicitMemo) {
        if (memo.kept) {
            reads = memo.reads;
            prints = memo.prints;
            changed = memo.pending;
            unsettled = memo.unsettled;
            all = false;
        }
    }

    ## Whether the callable `f` at `place` must be walked.
    needs(place: String, f: FunctionDef): bool {
        if (all) {
            return true;
        }
        var read = reads.try_get(place);
        if (!read.is_value()) {
            return true;
        }
        if (settling and unsettled.contains(place)) {
            return true;
        }
        if (checks_code) {
            var print = prints.try_get(place);
            if (!print.is_value() or print.value() != _print(f)) {
                return true;
            }
        }
        # Through the smaller set: a round can announce thousands of keys.
        if (changed.count < read.value().count) {
            for (var key in changed) {
                if (read.value().contains(key)) {
                    return true;
                }
            }
            return false;
        }
        for (var key in read.value()) {
            if (changed.contains(key)) {
                return true;
            }
        }
        return false;
    }

    ## Starts walking the callable at `place`.
    start(tables: ImplicitTables, scopes: _TypeScopes) {
        tables.reads = HashSet<String>();
        scopes.edits = 0;
        _settle_mark = scopes.overloads.settleable;
    }

    ## Finishes walking the callable `f` at `place`.
    finish(place: String, f: FunctionDef, tables: ImplicitTables, scopes: _TypeScopes) {
        edits += scopes.edits;
        if (scopes.overloads.settleable != _settle_mark) {
            unsettled.insert(place);
        } else {
            unsettled.remove(place);
        }
        if (scopes.edits == 0) {
            reads[place] = tables.reads;
            prints[place] = _print(f);
        } else {
            reads.remove(place);
            prints.remove(place);
        }
    }

    ## Ends a run: what it changed is what the next run looks for.
    next_run() {
        changed = changing;
        changing = HashSet<String>();
        all = false;
        settling = false;
        edits = 0;
    }
}

## The fingerprint of callable `f`, its code included.
_print(f: FunctionDef): ulong {
    var into = Fingerprint();
    f.fingerprint(into);
    return into.value;
}

## The fingerprint of what callers of `f` see: everything but its code.
_signature(f: FunctionDef): ulong {
    var into = Fingerprint();
    into.add_text(f.name);
    f.ty.fingerprint(into);
    into.add(f.generic_params.count);
    for (var p in f.generic_params) {
        p.fingerprint(into);
    }
    into.add(f.parameters.count);
    for (var p in f.parameters) {
        p.fingerprint(into);
    }
    into.add_text(f.parent.is_value() ? f.parent.value() : "");
    into.add(f.is_static ? 1 : 0);
    into.add(f.is_indexer ? 1 : 0);
    into.add(f.is_generic_func ? 1 : 0);
    return into.value;
}

## What the walks look up, by declaration: each one's fingerprint and the
## read keys a change to it announces, and one fingerprint for what no key
## covers.
struct _Declarations {
    var prints: HashMap<String, ulong> = HashMap<String, ulong>();
    var announces: HashMap<String, Array<String>> = HashMap<String, Array<String>>();
    var context: ulong = 0;

    ## Takes the declarations of `module` the walks can look up.
    construct(module: Module, trait_types: TypeName[]) {
        # A checked unit's declarations do not change on top of it, so they
        # never announce anything: only its structs that got methods
        # specialized since (`_find<Point>`) count.
        var own = unit_decls(module);
        for (var st in own.structs) {
            if (module.checked.structs.contains(st.name) and !_has_body(st)) {
                continue;
            }
            var key = st.ty.to_string();
            var base = _base_read(key);
            var shape = Fingerprint();
            into_struct(st, shape);
            _add($"s:{key}", shape.value, [_type_read(key), base, _function_read(key)]);
            ulong i = 0;
            for (var c in st.constructors) {
                _add($"s:{key}c{i}", _signature(c), [_type_read(key), base, _function_read(key)]);
                i += 1;
            }
            for (var m in st.method_members) {
                _add($"s:{key}m:{m.name}", _signature(m), [_method_read(key, m.name), base]);
            }
            for (var m in st.generic_methods) {
                _add($"s:{key}g:{m.name}", _signature(m), [_method_read(key, m.name), base]);
            }
        }
        for (var ty in trait_types) {
            var key = ty.to_string();
            var shape = Fingerprint();
            ty.fingerprint(shape);
            _add($"t:{key}", shape.value, [_type_read(key), _base_read(key)]);
        }
        for (var f in own.functions) {
            _add($"f:{f.name}", _signature(f), [_function_read(f.name)]);
        }
        for (var e in module.externs) {
            var shape = Fingerprint();
            e.fingerprint(shape);
            _add($"e:{e.name}", shape.value, [_function_read(e.name)]);
        }
        for (var g in module.globals) {
            if (module.checked.globals.contains(g.name)) {
                continue;
            }
            var shape = Fingerprint();
            g.fingerprint(shape);
            _add($"g:{g.name}", shape.value, [$"g:{g.name}"]);
        }
        for (var (name, members) in module.overload_sets) {
            _add($"o:{name}", _names(members), [_function_read(name)]);
        }
        for (var (name, unions) in module.overload_unions) {
            var shape = Fingerprint();
            for (var members in unions) {
                shape.add(_names(members));
            }
            _add($"u:{name}", shape.value, [_function_read(name)]);
        }
        for (var (owner, sets) in module.method_overload_sets) {
            for (var (name, members) in sets) {
                _add($"m:{owner}.{name}", _names(members), [_method_read(owner, name), _base_read(owner)]);
            }
        }
        var rest = Fingerprint();
        rest.add(module.traits.count);
        for (var t in module.traits) {
            t.fingerprint(rest);
        }
        rest.add(module.extensions.count);
        for (var x in module.extensions) {
            into_extension(x, rest);
        }
        rest.add(module.enums.count);
        for (var x in module.enums) {
            x.fingerprint(rest);
        }
        rest.add(module.type_aliases.count);
        for (var x in module.type_aliases) {
            x.fingerprint(rest);
        }
        rest.add(module.properties.count);
        for (var x in module.properties) {
            x.fingerprint(rest);
        }
        rest.add(module.conversions.count);
        for (var x in module.conversions) {
            x.fingerprint(rest);
        }
        module.extension_scopes.fingerprint(rest);
        context = rest.value;
    }

    ## Adds what `st` itself declares, its methods aside, to `into`.
    into_struct(st: StructDef, into: Fingerprint) {
        into.add_text(st.name);
        st.ty.fingerprint(into);
        into.add(st.generic_params.count);
        for (var p in st.generic_params) {
            p.fingerprint(into);
        }
        into.add(st.field_members.count);
        for (var f in st.field_members) {
            f.fingerprint(into);
        }
        into.add(st.traits.count);
        for (var t in st.traits) {
            t.fingerprint(into);
        }
        into.add(st.constructors.count);
    }

    ## Adds what `x` declares to `into`: its methods' signatures, not their
    ## code, which the walks never look up.
    into_extension(x: ExtensionDef, into: Fingerprint) {
        x.target.fingerprint(into);
        into.add_text(x.resolved.is_value() ? x.resolved.value() : "");
        into.add(x.traits.count);
        for (var t in x.traits) {
            t.fingerprint(into);
        }
        into.add(x.restated.count);
        for (var (index, bound) in x.restated) {
            into.add(index);
            bound.fingerprint(into);
        }
        into.add(x.methods.count);
        for (var m in x.methods) {
            into.add(_signature(m));
        }
        into.add(x.attributes.count);
        x.loc.fingerprint(into);
        into.add(x.is_exported ? 1 : 0);
        into.add(x.is_private ? 1 : 0);
    }

    ## Records declaration `id`; a name declared twice folds into one.
    _add(id: String, print: ulong, announce: String[]) {
        var had = prints.try_get(id);
        if (!had.is_value()) {
            prints[id] = print;
            announces[id] = announce;
            return;
        }
        var both = Fingerprint();
        both.add(had.value());
        both.add(print);
        prints[id] = both.value;
    }

    ## Adds to `into` the read keys of what differs from `before`; returns
    ## whether what no key covers changed.
    changes(before: ImplicitMemo, into: HashSet<String>): bool {
        for (var (id, print) in prints) {
            var had = before.declarations.try_get(id);
            if (had.is_value() and had.value() == print) {
                continue;
            }
            for (var key in announces[id]) {
                into.insert(key);
            }
        }
        for (var (id, keys) in before.announces) {
            if (prints.contains(id)) {
                continue;
            }
            for (var key in keys) {
                into.insert(key);
            }
        }
        return context != before.context;
    }

    ## Leaves these in `memo` for the next run.
    keep(memo: ImplicitMemo) {
        memo.declarations = prints;
        memo.announces = announces;
        memo.context = context;
    }
}

## The fingerprint of a list of names.
_names(names: String[]): ulong {
    var into = Fingerprint();
    into.add(names.count);
    for (var name in names) {
        into.add_text(name);
    }
    return into.value;
}

## The tables of `module`'s checked declarations, built once per unit and
## kept in `state.checked_implicit`.
_checked_implicit(module: Module, state: PassState, callees: Callees): ImplicitTables {
    if (state.checked_implicit.is_value()) {
        var kept = state.checked_implicit.value() as? ImplicitTables;
        if (kept.is_value()) {
            return kept.value();
        }
    }
    var built = ImplicitTables.checked(module, state, callees);
    state.checked_implicit = Optional<PassMemo>.Value(built);
    return built;
}

## Program-wide lookup tables, built once per run of the pass. Where a name
## is declared twice, the first declaration wins.
export struct ImplicitTables {
    ## What calls with named arguments bind to.
    var callees: Callees;
    ## Struct field tables: struct type string, then fields.
    var structs: Array<(String, Array<VariableDef>)> = Array<(String, Array<VariableDef>)>();
    ## Struct type string to its positions in `structs`, in order.
    var struct_index: HashMap<String, Array<ulong>> = HashMap<String, Array<ulong>>();
    var struct_names: HashSet<String> = HashSet<String>();
    var struct_bases: HashSet<String> = HashSet<String>();
    ## Struct method tables: struct type string, then (method, return type).
    var methods: Array<(String, Array<(String, TypeName)>)> = Array<(String, Array<(String, TypeName)>)>();
    var method_index: HashMap<String, Array<ulong>> = HashMap<String, Array<ulong>>();
    ## Struct type string to how many arguments each of its methods takes.
    var arities: HashMap<String, Array<(String, ulong, ulong)>> = HashMap<String, Array<(String, ulong, ulong)>>();
    ## Free-function and extern name to return type.
    var functions: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Free functions usable as values: name to function type.
    var function_types: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Generic methods: struct type string to (method name, declaration).
    var generic_methods: HashMap<String, Array<(String, GenericSignature)>> = HashMap<String, Array<(String, GenericSignature)>>();
    var generic_method_names: HashSet<String> = HashSet<String>();
    ## Generic free functions: name to declaration.
    var generic_functions: HashMap<String, GenericSignature> = HashMap<String, GenericSignature>();
    ## Global variables: name to type.
    var globals: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Struct declared name to its type.
    var struct_types: HashMap<String, TypeName> = HashMap<String, TypeName>();
    var properties: Properties;
    ## What the callable being walked looked up that a run of the pass can
    ## change: `_type_read`, `_function_read` and `g:<global>` keys.
    var reads: HashSet<String> = HashSet<String>();

    ## The tables of the checked declarations, built once per unit
    ## (`PassState.checked_implicit`) and read under this run's own.
    var base: ImplicitTables? = Optional<ImplicitTables>.Empty;
    ## In a base: each struct entry's declaration (parallel to `structs`),
    ## and each struct's declaration with how many fields and methods it
    ## had, by name. An entry holds while its struct is the same, unchanged
    ## and not extended in this unit.
    var _struct_defs: Array<StructDef> = Array<StructDef>();
    var _covered: HashMap<String, (StructDef, ulong, ulong)> = HashMap<String, (StructDef, ulong, ulong)>();
    ## In a base: its structs by the name before their type arguments.
    var _by_base: HashMap<String, Array<StructDef>> = HashMap<String, Array<StructDef>>();
    var _state: PassState;

    construct(module: Module, state: PassState, trait_types: TypeName[]) {
        _state = state;
        callees = Callees(module, state, Optional<TypeName[]>.Value(trait_types));
        properties = Properties(module);
        bool checked = module.checked.structs.count > 0 or module.checked.functions.count > 0;
        if (checked) {
            base = Optional<ImplicitTables>.Value(_checked_implicit(module, state, callees));
        }
        # A checked struct the base does not cover is one the unit
        # extended or specialized a method for: one of the unit's own.
        var own = unit_decls(module);
        for (var st in own.structs) {
            if (checked and base.value().covers(st)) {
                continue;
            }
            _add_struct(module, st, state);
        }
        # Trait types used as values: what `var x = s.take()` returns.
        for (var ty in trait_types_of(module, Optional<TypeName[]>.Value(trait_types))) {
            var def = trait_def(module.traits, ty);
            if (def.is_value()) {
                var own = Array<(String, TypeName)>();
                for (var m in instance(def.value(), ty).methods) {
                    own.append((m.name, m.ty));
                }
                methods.append((ty.to_string(), own));
            }
        }
        _index();
        for (var f in own.functions) {
            _first_wins(functions, f.name, f.ty);
        }
        for (var e in module.externs) {
            _first_wins(functions, e.name, e.ty);
        }
        for (var f in own.functions) {
            if (f.is_generic_func and !generic_functions.contains(f.name)) {
                generic_functions[f.name] = GenericSignature(f, state);
            }
        }
        var which = checked ? Optional<bool>.Value(false) : Optional<bool>.Empty;
        for (var (name, ty) in _referenceable_functions(module, state, which)) {
            _first_wins(function_types, name, ty);
        }
        for (var g in module.globals) {
            _first_wins(globals, g.name, g.ty);
        }
    }

    ## The tables of `module`'s checked declarations alone: the structs no
    ## extension of this unit changed yet, and the checked functions.
    static checked(module: Module, state: PassState, callees: Callees): ImplicitTables {
        var out = ImplicitTables(callees, Properties(module), state);
        for (var st in module.structs) {
            if (!module.checked.structs.contains(st.name) or state.extended_checked.contains(st.name)) {
                continue;
            }
            out._add_struct(module, st, state);
            out._struct_defs.append(st);
            out._covered[st.name] = (st, st.field_members.count, st.method_members.count);
            var name = _before_angle(st.ty.to_string());
            if (!out._by_base.contains(name)) {
                out._by_base[name] = Array<StructDef>();
            }
            out._by_base[name].append(st);
        }
        out._index();
        for (var f in module.functions) {
            if (is_checked_function(module, f)) {
                _first_wins(out.functions, f.name, f.ty);
                if (f.is_generic_func and !out.generic_functions.contains(f.name)) {
                    out.generic_functions[f.name] = GenericSignature(f, state);
                }
            }
        }
        for (var (name, ty) in _referenceable_functions(module, state, Optional<bool>.Value(true))) {
            _first_wins(out.function_types, name, ty);
        }
        return out;
    }

    construct(callees: Callees, properties: Properties, state: PassState) {
        this.callees = callees;
        this.properties = properties;
        _state = state;
    }

    ## Whether this base's entries stand for `st`.
    covers(st: StructDef): bool {
        var found = _covered.try_get(st.name);
        if (!found.is_value()) {
            return false;
        }
        var (was, fields, count) = found.value();
        return was === st
            and fields == st.field_members.count
            and count == st.method_members.count
            and !_state.extended_checked.contains(st.name);
    }

    _add_struct(module: Module, st: StructDef, state: PassState) {
        var key = st.ty.to_string();
        # A checked unit's fields are final: no copy to keep apart from
        # what this run types.
        structs.append((key, module.checked.structs.contains(st.name) ? st.field_members : st.field_members.copy()));
        var (own, own_arities) = _struct_parts(module, st, state.implicit);
        methods.append((key, own));
        struct_names.insert(key);
        struct_bases.insert(_before_angle(key));
        if (!arities.contains(key)) {
            arities[key] = own_arities;
        }
        if (st.generic_methods.count != 0) {
            var generic = Array<(String, GenericSignature)>();
            for (var m in st.generic_methods) {
                generic.append((m.name, GenericSignature(m, state)));
                generic_method_names.insert(m.name);
            }
            generic_methods[key] = generic;
        }
        if (!struct_types.contains(st.name)) {
            struct_types[st.name] = st.ty;
        }
    }

    _index() {
        ulong i = 0;
        while (i < structs.count) {
            var (key, _) = structs[i];
            if (!struct_index.contains(key)) {
                struct_index[key] = Array<ulong>();
            }
            struct_index[key].append(i);
            i += 1;
        }
        i = 0;
        while (i < methods.count) {
            var (key, _) = methods[i];
            if (!method_index.contains(key)) {
                method_index[key] = Array<ulong>();
            }
            method_index[key].append(i);
            i += 1;
        }
    }

    ## The field tables of struct type `key`: the base's first, then this
    ## run's.
    field_lists(key: String): Array<Array<VariableDef>> {
        var out = Array<Array<VariableDef>>();
        if (base.is_value()) {
            var b = base.value();
            var found = b.struct_index.try_get(key);
            if (found.is_value()) {
                for (var i in found.value()) {
                    if (b.covers(b._struct_defs[i])) {
                        var (_, fields) = b.structs[i];
                        out.append(fields);
                    }
                }
            }
        }
        var found = struct_index.try_get(key);
        if (found.is_value()) {
            for (var i in found.value()) {
                var (_, fields) = structs[i];
                out.append(fields);
            }
        }
        return out;
    }

    ## The method tables of struct or trait type `key`: the base's first,
    ## then this run's.
    method_lists(key: String): Array<Array<(String, TypeName)>> {
        var out = Array<Array<(String, TypeName)>>();
        if (base.is_value()) {
            var b = base.value();
            var found = b.method_index.try_get(key);
            if (found.is_value()) {
                for (var i in found.value()) {
                    if (b.covers(b._struct_defs[i])) {
                        var (_, methods) = b.methods[i];
                        out.append(methods);
                    }
                }
            }
        }
        var found = method_index.try_get(key);
        if (found.is_value()) {
            for (var i in found.value()) {
                var (_, methods) = this.methods[i];
                out.append(methods);
            }
        }
        return out;
    }

    ## The base's struct entry under `key` that still stands, if any.
    _base_struct(key: String): bool {
        if (!base.is_value()) {
            return false;
        }
        var b = base.value();
        var found = b.struct_index.try_get(key);
        if (found.is_value()) {
            for (var i in found.value()) {
                if (b.covers(b._struct_defs[i])) {
                    return true;
                }
            }
        }
        return false;
    }

    is_struct_name(key: String): bool {
        return struct_names.contains(key) or _base_struct(key);
    }

    is_struct_base(name: String): bool {
        if (struct_bases.contains(name)) {
            return true;
        }
        if (!base.is_value()) {
            return false;
        }
        var found = base.value()._by_base.try_get(name);
        if (found.is_value()) {
            for (var st in found.value()) {
                if (base.value().covers(st)) {
                    return true;
                }
            }
        }
        return false;
    }

    arities_of(key: String): Array<(String, ulong, ulong)>? {
        if (_base_struct(key)) {
            return base.value().arities.try_get(key);
        }
        return arities.try_get(key);
    }

    generic_methods_of(key: String): Array<(String, GenericSignature)>? {
        if (_base_struct(key)) {
            var found = base.value().generic_methods.try_get(key);
            if (found.is_value()) {
                return found;
            }
        }
        return generic_methods.try_get(key);
    }

    is_generic_method_name(name: String): bool {
        return generic_method_names.contains(name)
            or (base.is_value() and base.value().generic_method_names.contains(name));
    }

    function_of(name: String): TypeName? {
        if (base.is_value()) {
            var found = base.value().functions.try_get(name);
            if (found.is_value()) {
                return found;
            }
        }
        return functions.try_get(name);
    }

    function_type_of(name: String): TypeName? {
        if (base.is_value()) {
            var found = base.value().function_types.try_get(name);
            if (found.is_value()) {
                return found;
            }
        }
        return function_types.try_get(name);
    }

    generic_function(name: String): GenericSignature? {
        if (base.is_value()) {
            var found = base.value().generic_functions.try_get(name);
            if (found.is_value()) {
                return found;
            }
        }
        return generic_functions.try_get(name);
    }

    struct_type_of(name: String): TypeName? {
        if (base.is_value()) {
            var b = base.value();
            var found = b.struct_types.try_get(name);
            var st = b._covered.try_get(name);
            if (found.is_value() and st.is_value() and b.covers(st.value().0)) {
                return found;
            }
        }
        return struct_types.try_get(name);
    }

    ## Records that the callable being walked looked up `key`.
    note(key: String) {
        reads.insert(key);
    }
}

extend ImplicitTables with PassMemo;

## The struct whose methods are being resolved: its fields with resolved
## types, and its methods. It stands in for the struct's table entries.
struct _OwnStruct {
    var name: String;
    var fields: Array<VariableDef>;
    var methods: Array<(String, TypeName)>;

    construct(name: String, fields: Array<VariableDef>, methods: Array<(String, TypeName)>) {
        this.name = name;
        this.fields = fields;
        this.methods = methods;
    }
}

## The scopes of the code being walked, and what typing it needs.
struct _TypeScopes {
    var tables: ImplicitTables;
    var state: PassState;
    var own: _OwnStruct? = Optional<_OwnStruct>.Empty;
    ## Parameters per scope; index 0 holds none.
    var params: Array<Array<VariableDef>> = Array<Array<VariableDef>>();
    ## Local symbols per scope; scope 0 holds what the global initializers
    ## declare after `tables.globals`.
    var symbols: Array<Array<(String, TypeName)>> = Array<Array<(String, TypeName)>>();
    ## While walking a function with no declared return type: the types of
    ## its `return <value>` statements.
    var returns: Array<TypeName>? = Optional<Array<TypeName>>.Empty;
    var overloads: Overloads;
    ## The generic parameters of the code being walked.
    var unbound: Array<String> = Array<String>();
    ## Calls resolved to an overload set's member, shared by every scope.
    var resolved: Array<(Loc, String)>;
    ## Walking a generic base: calls are not inferred here.
    var generic_base: bool = false;
    var in_constructor: bool = false;
    ## The function or method being walked, and where it is declared.
    var function: String = "";
    var function_loc: Loc = Loc.none();
    ## How many changes the walk made to the code it walked.
    var edits: ulong = 0;

    construct(tables: ImplicitTables, overloads: Overloads, resolved: Array<(Loc, String)>, state: PassState) {
        this.tables = tables;
        this.overloads = overloads;
        this.resolved = resolved;
        this.state = state;
        params.append(Array<VariableDef>());
        symbols.append(Array<(String, TypeName)>());
    }

    push() {
        params.append(Array<VariableDef>());
        symbols.append(Array<(String, TypeName)>());
    }

    pop() {
        params.pop();
        symbols.pop();
    }

    ## A local declared in the code being walked (not a global).
    local(name: String): TypeName? {
        ulong i = symbols.count;
        while (i > 1) {
            i -= 1;
            for (var (symbol, ty) in symbols[i]) {
                if (symbol == name) {
                    return Optional<TypeName>.Value(ty);
                }
            }
        }
        return Optional<TypeName>.Empty;
    }

    symbol(name: String): TypeName? {
        var found = local(name);
        if (found.is_value()) {
            return found;
        }
        tables.note($"g:{name}");
        found = tables.globals.try_get(name);
        if (found.is_value()) {
            return found;
        }
        for (var (symbol, ty) in symbols[0]) {
            if (symbol == name) {
                return Optional<TypeName>.Value(ty);
            }
        }
        return Optional<TypeName>.Empty;
    }

    param(name: String): TypeName? {
        ulong i = params.count;
        while (i > 0) {
            i -= 1;
            for (var p in params[i]) {
                if (p.name == name) {
                    return Optional<TypeName>.Value(p.ty);
                }
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## The field tables of struct type `key`, in order.
    field_tables(key: String): Array<Array<VariableDef>> {
        tables.note(_type_read(key));
        var out = Array<Array<VariableDef>>();
        if (own.is_value() and own.value().name == key) {
            out.append(own.value().fields);
            return out;
        }
        out.append_all(tables.field_lists(key));
        return out;
    }

    ## The method tables of struct type `key`, in order, for a lookup of
    ## method `name`.
    method_tables(key: String, name: String): Array<Array<(String, TypeName)>> {
        tables.note(_method_read(key, name));
        var out = Array<Array<(String, TypeName)>>();
        if (own.is_value() and own.value().name == key) {
            out.append(own.value().methods);
            return out;
        }
        out.append_all(tables.method_lists(key));
        return out;
    }

    ## Declared type of field `name` on struct type `ty`.
    field_type(ty: TypeName, name: String): TypeName? {
        var all = field_tables(ty.to_string());
        if (all.count == 0) {
            return Optional<TypeName>.Empty;
        }
        for (var f in all[0]) {
            if (f.name == name) {
                return Optional<TypeName>.Value(f.ty);
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## Declared return type of method `name` on struct type `ty`.
    method_return(ty: TypeName, name: String): TypeName? {
        var all = method_tables(ty.to_string(), name);
        if (all.count == 0) {
            return Optional<TypeName>.Empty;
        }
        for (var (m, ret) in all[0]) {
            if (m == name) {
                return Optional<TypeName>.Value(ret);
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## Whether struct type `ty` declares a method `name`; an overloaded
    ## method is declared under its members' names.
    has_method(ty: TypeName, name: String): bool {
        for (var methods in method_tables(ty.to_string(), name)) {
            for (var (m, _) in methods) {
                if (m.starts_with(name) and (m.size == name.size or set_name(m) == name)) {
                    return true;
                }
            }
        }
        return false;
    }

    ## Whether a bare call of `name` with `count` arguments in a method of
    ## `ty` calls one of its methods: class scope first, unless no method by
    ## that name takes `count` arguments and a free function `name` exists.
    calls_method(ty: TypeName, name: String, count: ulong): bool {
        if (!has_method(ty, name)) {
            return false;
        }
        tables.note(_function_read(name));
        bool free = tables.function_of(name).is_value()
            or tables.generic_function(name).is_value()
            or overloads.is_set(name);
        if (!free) {
            return true;
        }
        var arities = tables.arities_of(ty.to_string());
        return !arities.is_value() or _takes(arities.value(), name, count);
    }

    ## Function type of the free function `name`, when a bare `name` in
    ## value position refers to it.
    function_value(name: String, current: TypeName?): TypeName? {
        if (param(name).is_value() or symbol(name).is_value()) {
            return Optional<TypeName>.Empty;
        }
        if (current.is_value()) {
            if (field_type(current.value(), name).is_value() or has_method(current.value(), name)) {
                return Optional<TypeName>.Empty;
            }
        }
        tables.note(_function_read(name));
        return tables.function_type_of(name);
    }

    ## When a call `name(args)` calls through a function value, the callee
    ## expression and its function type.
    value_callee(name: String, current: TypeName?): (Expression, TypeName)? {
        var declared = param(name);
        if (!declared.is_value()) {
            declared = symbol(name);
        }
        if (declared.is_value()) {
            var ty = declared.value();
            if (!ty.is_callable()) {
                return Optional<(Expression, TypeName)>.Empty;
            }
            var callee = Expression.SymbolRef(SymbolRefExpression(name, ty.copy(), Loc.none()));
            return Optional<(Expression, TypeName)>.Value((callee, ty));
        }
        if (!current.is_value()) {
            return Optional<(Expression, TypeName)>.Empty;
        }
        var field = field_type(current.value(), name);
        if (!field.is_value() or !field.value().is_callable() or has_method(current.value(), name)) {
            return Optional<(Expression, TypeName)>.Empty;
        }
        var callee = Expression.MemberRef(MemberRefExpression(Expression.ThisRef, name, Loc.none()));
        return Optional<(Expression, TypeName)>.Value((callee, field.value()));
    }

    _mentions_unbound(ty: TypeName): bool {
        for (var p in unbound) {
            if (ty.mentions(p)) {
                return true;
            }
        }
        return false;
    }

    ## What resolution knows about each of `args`.
    _infos(args: Expression[], current: TypeName?): Array<ArgInfo> {
        var infos = Array<ArgInfo>();
        for (var arg in args) {
            if (arg is SymbolRef(node)) {
                tables.note(_function_read(node.id));
            }
            infos.append(arg_info(arg, overloads, Optional<TypeName>.Value(type_of(arg, current))));
        }
        return infos;
    }

    ## The overload set a call `function(args)` names, unless a local,
    ## parameter or member by that name shadows it.
    overload_call(function: String, current: TypeName?): (String, Optional<TypeName[]>)? {
        var none = Optional<(String, Optional<TypeName[]>)>.Empty;
        tables.note(_function_read(function));
        if (overloads.is_empty() or !overloads.is_set(overloads.call_set_name(function))) {
            return none;
        }
        var (base, explicit) = overloads.call_set(function);
        if (!overloads.is_set(base) or value_callee(base, current).is_value()) {
            return none;
        }
        if (current.is_value()
            and (has_method(current.value(), base) or field_type(current.value(), base).is_value())) {
            return none;
        }
        return Optional<(String, Optional<TypeName[]>)>.Value((base, explicit));
    }

    ## Resolves `function(args)` against its overload set, when it names one
    ## and its arguments decide.
    select_overload(function: String, args: Expression[], at: Loc, current: TypeName?): Choice? {
        var call = overload_call(function, current);
        if (!call.is_value()) {
            return Optional<Choice>.Empty;
        }
        var (base, explicit) = call.value();
        var infos = _infos(args, current);
        # In a generic body, the specializations decide.
        for (var info in infos) {
            if (info.ty.is_value() and _mentions_unbound(info.ty.value())) {
                return Optional<Choice>.Empty;
            }
        }
        var outcome = overloads.select(base, explicit, infos, at);
        if (outcome is Chosen(choice)) {
            return Optional<Choice>.Value(choice);
        }
        return Optional<Choice>.Empty;
    }

    ## Resolves `receiver.method(args)` against the method overload set of
    ## the receiver's struct, when its arguments decide.
    select_method_overload(
        receiver: TypeName, method: String, args: Expression[], at: Loc, current: TypeName?
    ): Choice? {
        var infos = _infos(args, current);
        if (_mentions_unbound(receiver)) {
            return Optional<Choice>.Empty;
        }
        for (var info in infos) {
            if (info.ty.is_value() and _mentions_unbound(info.ty.value())) {
                return Optional<Choice>.Empty;
            }
        }
        tables.note(_base_read(receiver.to_string()));
        var outcome = overloads.select_method(receiver, method, infos, at);
        if (outcome is Chosen(choice)) {
            return Optional<Choice>.Value(choice);
        }
        return Optional<Choice>.Empty;
    }

    ## What each argument's type says about a generic call's type
    ## arguments.
    argument_types(args: Expression[], current: TypeName?): Array<TypeName?> {
        var out = Array<TypeName?>();
        for (var arg in args) {
            if (arg is MakeClosure(node)) {
                out.append(Optional<TypeName>.Value(node.ty));
                continue;
            }
            var ty = type_of(arg, current);
            out.append(
                !ty.is_empty() and !ty.contains_auto() ? Optional<TypeName>.Value(ty) : Optional<TypeName>.Empty
            );
        }
        return out;
    }

    ## The function a binary operator with a number on the left calls, when
    ## the number type's extension declares that operator, and whether its
    ## result is negated (`!=` through `==`).
    number_operator(
        op: BinaryOp, lhs: Expression, lhs_type: TypeName?, rhs: Expression, current: TypeName?
    ): (String, bool)? {
        var none = Optional<(String, bool)>.Empty;
        var name = op_name(op);
        if (_is_assignment(op) or name.size == 0) {
            return none;
        }
        bool any = false;
        for (var key in _number_keys()) {
            if (_wanted(key, op, name)) {
                any = true;
                break;
            }
        }
        if (!any) {
            return none;
        }
        var left = lhs_type.is_value() ? lhs_type.value().to_string() : type_of(lhs, current).to_string();
        if (is_enum(state, left)) {
            return none;
        }
        var key = value_type_key(state, left);
        if (!key.is_value() or !_wanted(key.value(), op, name)) {
            return none;
        }
        var rhs_type = type_of(rhs, current);
        if (rhs_type.is_empty()
            or rhs_type.is_auto()
            or rhs_type.is_pointer()
            or is_value_type(state, rhs_type)
            or is_enum(state, rhs_type.to_string())) {
            return none;
        }
        if (_declares(key.value(), name)) {
            return Optional<(String, bool)>.Value((enum_method_name(key.value(), name), false));
        }
        return Optional<(String, bool)>.Value((enum_method_name(key.value(), "=="), true));
    }

    _declares(key: String, method: String): bool {
        var is_static = method_is_static(state, key, method);
        return is_static.is_value() and !is_static.value();
    }

    _wanted(key: String, op: BinaryOp, name: String): bool {
        return _declares(key, name) or (op == BinaryOp.NotEqual and _declares(key, "=="));
    }

    ## Best-effort type of an expression: `typeOfExpr`.
    type_of(e: Expression, current: TypeName?): TypeName {
        match (e) {
            Destructure(node) => {
                return type_of(node.value, current);
            }
            Move(node) => {
                return type_of(node.value, current);
            }
            StaticCase(node) => {
                return node.ty;
            }
            Subject(node) => {
                return node.ty;
            }
            WithSubject(scoped) => {
                return type_of(scoped.body, current);
            }
            MatchArm(_) => {
                return TypeName.boolean();
            }
            CaseValue(value) => {
                var subject = type_of(value.subject, current);
                var result = case_value_type(state, value, subject, _ScopeFields(this, subject));
                if (result is Ok(ty)) {
                    if (ty.is_value()) {
                        return ty.value();
                    }
                }
                return TypeName.auto();
            }
            MemberRef(node) => {
                var lhs_type = type_of(node.lhs, current);
                if (lhs_type.is_empty() or lhs_type.is_auto()) {
                    return TypeName.auto();
                }
                var element = lhs_type.tuple_element(node.name);
                if (element.is_value()) {
                    return element.value();
                }
                for (var fields in field_tables(lhs_type.to_string())) {
                    for (var f in fields) {
                        if (f.name == node.name) {
                            return f.ty;
                        }
                    }
                }
                # A property read before it is lowered: its getter's type.
                if (tables.properties.find(lhs_type, node.name).is_value()) {
                    var ret = method_return(lhs_type, getter_name(node.name));
                    if (ret.is_value()) {
                        return ret.value();
                    }
                }
                return TypeName.auto();
            }
            SymbolRef(node) => {
                return _symbol_type(node.id, current);
            }
            FunctionRef(node) => {
                return node.ty;
            }
            MakeClosure(node) => {
                return node.ty.contains_auto() ? TypeName.auto() : node.ty;
            }
            Invoke(node) => {
                var ret = type_of(node.callee, current).function_return();
                return ret.is_value() ? ret.value() : TypeName.auto();
            }
            ThisRef => {
                return current.is_value() ? current.value() : TypeName.auto();
            }
            MethodCall(node) => {
                return _method_call_type(node, current);
            }
            ForIterator(source) => {
                var source_type = type_of(source, current);
                if (source_type.is_empty() or source_type.is_auto()) {
                    return TypeName.auto();
                }
                var all = method_tables(source_type.to_string(), "iterate");
                if (all.count == 0) {
                    return TypeName.auto();
                }
                for (var (m, iterator) in all[0]) {
                    if (m == "iterate") {
                        return iterator;
                    }
                }
                return source_type;
            }
            Unary(node) => {
                if (node.op == UnaryOp.LogicalNot) {
                    return TypeName.boolean();
                }
                return type_of(node.operand, current);
            }
            Binary(node) => {
                return _binary_type(node, current);
            }
            IntLiteral(value) => {
                return TypeName.named(int_literal_type(value));
            }
            FloatLiteral(_) => {
                return TypeName.named("f64");
            }
            BoolLiteral(_) => {
                return TypeName.boolean();
            }
            StringLiteral(_) => {
                return TypeName.named("String");
            }
            PointerLiteral => {
                return TypeName.void_pointer();
            }
            FunctionCall(node) => {
                return _call_type(node, current);
            }
            Address(_, _) => {
                return TypeName.named("u64");
            }
            RefCount(_, _) => {
                return TypeName.named("u32");
            }
            CountStep(_) => {
                return TypeName.named("u32");
            }
            FunctionPointer(_) => {
                return TypeName.void_pointer();
            }
            Weak(op, ty, _) => {
                return weak_result(op, ty);
            }
            AtomicLoad(ty, _) => {
                return ty;
            }
            Allocate(ty) => {
                return ty;
            }
            Default(ty) => {
                return ty;
            }
            IsPod(_) => {
                return TypeName.boolean();
            }
            SizeOf(_) => {
                return TypeName.named("u64");
            }
            AtomicStore(_, _, _) => {
                return TypeName.named("void");
            }
            ConstructAt(_, _) => {
                return TypeName.named("void");
            }
            AtomicCmpXchg(_, _, _, _) => {
                return TypeName.named("bool");
            }
            AtomicFetch(_, ty, _, _) => {
                return ty;
            }
            Simd(node) => {
                return simd_result(node.op, node.ty);
            }
            Index(node) => {
                return _index_type(e, node.lhs, current);
            }
            ArrayIndex(node) => {
                if (!node.ty.is_empty() and !node.ty.is_auto()) {
                    return node.ty;
                }
                return _index_type(e, node.lhs, current);
            }
            Cast(node) => {
                return node.ty;
            }
            Ternary(node) => {
                var ty = type_of(node.true_expr, current);
                if (ty.is_auto() and node.true_expr is NoMatch) {
                    return type_of(node.false_expr, current);
                }
                var false_type = type_of(node.false_expr, current);
                var a = ty.to_string();
                var b = false_type.to_string();
                if (!false_type.is_auto() and is_numeric_type(state, a) and is_numeric_type(state, b)) {
                    return TypeName.named(conditional_result(state, a, b));
                }
                return ty;
            }
            else => {
                return TypeName.auto();
            }
        }
    }

    _symbol_type(id: String, current: TypeName?): TypeName {
        # `this` inside a method is the parent struct type.
        if (id == "this" and current.is_value()) {
            return current.value();
        }
        # Parameters shadow globals.
        var found = param(id);
        if (found.is_value()) {
            return found.value();
        }
        found = local(id);
        if (found.is_value()) {
            return found.value();
        }
        # A bare field in its struct's methods; fields shadow globals.
        if (current.is_value()) {
            found = field_type(current.value(), id);
            if (found.is_value()) {
                return found.value();
            }
        }
        found = symbol(id);
        if (found.is_value()) {
            return found.value();
        }
        # A bare property in its struct's methods.
        if (current.is_value()) {
            tables.note(_type_read(current.value().to_string()));
        }
        if (current.is_value() and tables.properties.find(current.value(), id).is_value()) {
            found = method_return(current.value(), getter_name(id));
            if (found.is_value()) {
                return found.value();
            }
        }
        # The name of a struct.
        if (tables.is_struct_name(id)) {
            return TypeName.named(id);
        }
        # A free function used as a value.
        found = function_value(id, current);
        if (found.is_value()) {
            return found.value();
        }
        return TypeName.auto();
    }

    _method_call_type(node: MethodCallExpression, current: TypeName?): TypeName {
        var this_type = type_of(node.this_value, current);
        if (this_type.is_empty() or this_type.is_auto()) {
            return TypeName.auto();
        }
        # A method of an enum or another value type is the function `E::m`.
        var text = this_type.to_string();
        var key = value_type_key(state, text);
        var owner = key.is_value() ? key.value() : text;
        if (_declares(owner, node.method)) {
            var all = Array<Expression>();
            all.append(node.this_value);
            all.append_all(node.args);
            var call = Expression.FunctionCall(
                FunctionCallExpression(enum_method_name(owner, node.method), all, node.loc)
            );
            return type_of(call, current);
        }
        if (overloads.is_method_set(this_type, node.method)) {
            var choice = select_method_overload(this_type, node.method, node.args, node.loc, current);
            return choice.is_value() ? choice.value().ret : TypeName.auto();
        }
        for (var methods in method_tables(text, node.method)) {
            for (var (m, ret) in methods) {
                if (m == node.method) {
                    return ret;
                }
            }
        }
        # `obj.callback(x)` calls through a field of function type.
        var field = field_type(this_type, node.method);
        if (field.is_value()) {
            var ret = field.value().function_return();
            if (ret.is_value()) {
                return ret.value();
            }
        }
        return TypeName.auto();
    }

    _binary_type(node: BinaryExpression, current: TypeName?): TypeName {
        if (_is_assignment(node.op)) {
            return type_of(node.lhs, current);
        }
        if (is_comparison(node.op) or node.op == BinaryOp.LogicalAnd or node.op == BinaryOp.LogicalOr) {
            return TypeName.boolean();
        }
        var lhs_type = type_of(node.lhs, current);
        if (lhs_type.is_empty() or lhs_type.is_auto()) {
            return TypeName.auto();
        }
        var number = number_operator(node.op, node.lhs, Optional<TypeName>.Value(lhs_type), node.rhs, current);
        if (number.is_value()) {
            var (function, _) = number.value();
            var args = Array<Expression>();
            args.append(node.lhs);
            args.append(node.rhs);
            return type_of(Expression.FunctionCall(FunctionCallExpression(function, args, node.loc)), current);
        }
        var name = op_name(node.op);
        if (overloads.is_method_set(lhs_type, name)) {
            var args = Array<Expression>();
            args.append(node.rhs);
            var choice = select_method_overload(lhs_type, name, args, node.loc, current);
            return choice.is_value() ? choice.value().ret : TypeName.auto();
        }
        var ret = method_return(lhs_type, name);
        if (ret.is_value()) {
            return ret.value();
        }
        var rhs_type = type_of(node.rhs, current);
        var promoted = binary_result(state, node.op, lhs_type.to_string(), rhs_type.to_string());
        return promoted.is_value() ? TypeName.named(promoted.value()) : lhs_type;
    }

    _call_type(node: FunctionCallExpression, current: TypeName?): TypeName {
        var function = node.function;
        tables.note(_function_read(function));
        if (tuple_constructor_labels(function).is_value()) {
            var types = Array<TypeName>();
            for (var a in node.args) {
                types.append(type_of(a, current));
            }
            var ty = labeled_tuple_literal_type(function, types);
            return ty.is_value() ? ty.value() : TypeName.auto();
        }
        if (function.starts_with("__tuple<")) {
            return parse_type_string(function);
        }
        # A call through a local, parameter or field of function type.
        var callee = value_callee(function, current);
        if (callee.is_value()) {
            var (_, ty) = callee.value();
            var ret = ty.function_return();
            return ret.is_value() ? ret.value() : TypeName.auto();
        }
        # Inside a method, a bare call naming one of the struct's own
        # methods is that method; a converted string literal still
        # constructs `String`.
        if (current.is_value() and !_is_converted_literal(node)) {
            var st = current.value();
            if (!has_method(st, function) or calls_method(st, function, node.args.count)) {
                var all = method_tables(st.to_string(), function);
                if (all.count > 0) {
                    for (var (m, ret) in all[0]) {
                        if (m == function) {
                            return ret;
                        }
                    }
                }
            }
        }
        # A call to an overloaded function has the type of the member its
        # arguments select, once they do.
        if (overload_call(function, current).is_value()) {
            var choice = select_overload(function, node.args, node.loc, current);
            return choice.is_value() ? choice.value().ret : TypeName.auto();
        }
        # A generic function called without type arguments has no type
        # until they are inferred.
        if (!function.contains("<") and tables.generic_function(function).is_value()) {
            return TypeName.auto();
        }
        var declared = tables.function_of(function);
        if (declared.is_value()) {
            return declared.value();
        }
        var name = _before_angle(function).trim();
        if (name.size == 0) {
            return TypeName.auto();
        }
        # Intrinsics carry no declared function; type them by name.
        match (name) {
            "__address" => {
                return TypeName.named("u64");
            }
            "__refcount" => {
                return TypeName.named("u32");
            }
            "__atomic_load", "__default", "__copy_object" => {
                var parsed = parse_type_string(function);
                return parsed.sub_types.count > 0 ? parsed.sub_types[0] : TypeName.auto();
            }
            "__is_pod" => {
                return TypeName.boolean();
            }
            "__caller_location" => {
                return TypeName.pointer_to(TypeName.named("char"));
            }
            "__atomic_store", "__construct_at" => {
                return TypeName.named("void");
            }
            "__atomic_cmpxchg" => {
                return TypeName.named("bool");
            }
            else => {}
        }
        # A generic call spelled with its arguments before it is
        # specialized: the base's return type with the arguments
        # substituted.
        var signature = tables.generic_function(name);
        if (signature.is_value()) {
            var base = tables.function_of(name);
            if (base.is_value()) {
                var args = parse_type_string(function).sub_types;
                if (args.count > 0) {
                    var map = Array<(String, TypeName)>();
                    ulong i = 0;
                    while (i < signature.value().params.count and i < args.count) {
                        map.append((signature.value().params[i].name, args[i]));
                        i += 1;
                    }
                    var ty = base.value().copy();
                    replace_map(ty, map);
                    return ty;
                }
            }
        }
        declared = tables.function_of(name);
        if (declared.is_value()) {
            return declared.value();
        }
        # A constructor-style call `Name<...>(...)`, or one of several
        # overloaded constructors (`Name$2`).
        var constructed = set_name(function);
        if (tables.is_struct_base(_before_angle(constructed).trim())) {
            return parse_type_string(constructed);
        }
        return TypeName.auto();
    }

    _index_type(e: Expression, lhs: Expression, current: TypeName?): TypeName {
        var lhs_type = type_of(lhs, current);
        var element = _pointee(lhs_type);
        if (element.is_value()) {
            return element.value();
        }
        # A struct receiver whose `[]` is not lowered yet: typed as the
        # `x.__index_get(i)` call it becomes.
        if (e is Index(node)) {
            if (!lhs_type.is_empty() and !lhs_type.is_auto()) {
                var args = Array<Expression>();
                args.append(node.rhs);
                var call = Expression.MethodCall(MethodCallExpression(node.lhs, "__index_get", args, node.loc));
                return type_of(call, current);
            }
        }
        return TypeName.auto();
    }
}

## The fields of a `match` subject's struct, in the walk's scope.
struct _ScopeFields {
    var scopes: _TypeScopes;
    var subject: TypeName;

    construct(scopes: _TypeScopes, subject: TypeName) {
        this.scopes = scopes;
        this.subject = subject;
    }

    field(name: String): TypeName? {
        return scopes.field_type(subject, name);
    }
}

extend _ScopeFields with FieldTypes;

## The element type of a raw pointer; none for any other type, and for a
## `void` pointer.
_pointee(ty: TypeName): TypeName? {
    var element = ty.pointee();
    return element.is_value() and element.value().to_string() != VOID ? element : Optional<TypeName>.Empty;
}

## Where a property access is written, for `lower_property`.
struct _PropertyAt {
    var scopes: _TypeScopes;
    var current_struct: TypeName?;

    construct(scopes: _TypeScopes, current_struct: TypeName?) {
        this.scopes = scopes;
        this.current_struct = current_struct;
    }

    current(): TypeName? {
        return current_struct;
    }

    in_constructor(): bool {
        return scopes.in_constructor;
    }

    function(): String {
        return scopes.function;
    }

    function_loc(): Loc {
        return scopes.function_loc;
    }

    type_of(e: Expression): TypeName {
        return scopes.type_of(e, current_struct);
    }

    is_local(name: String): bool {
        return scopes.param(name).is_value() or scopes.symbol(name).is_value();
    }
}

extend _PropertyAt with PropertySite;

## Types each `Subject` of a `match` expression or `is` test as the value
## its `WithSubject` examines, once that is known.
struct _SubjectFiller {
    var scopes: _TypeScopes;
    var current: TypeName?;

    construct(scopes: _TypeScopes, current: TypeName?) {
        this.scopes = scopes;
        this.current = current;
    }

    rewrite(e: Expression): Expression {
        if (e is WithSubject(scoped)) {
            var ty = scopes.type_of(scoped.subject, current);
            if (!ty.is_auto() and !ty.is_empty()) {
                scoped.body = rewrite_expression(scoped.body, _SubjectTyper(scoped.id, ty, scopes));
            }
        }
        return e;
    }
}

extend _SubjectFiller with Rewriter;

struct _SubjectTyper {
    var id: ulong;
    var ty: TypeName;
    var scopes: _TypeScopes;

    construct(id: ulong, ty: TypeName, scopes: _TypeScopes) {
        this.id = id;
        this.ty = ty;
        this.scopes = scopes;
    }

    rewrite(e: Expression): Expression {
        if (e is Subject(node)) {
            if (node.id == id) {
                if (node.ty.to_string() != ty.to_string()) {
                    scopes.edits += 1;
                }
                node.ty = ty.copy();
            }
        }
        return e;
    }
}

extend _SubjectTyper with Rewriter;

## What resolving implicit types does at each expression.
struct _ImplicitResolver {
    var scopes: _TypeScopes;
    var current: TypeName?;

    construct(scopes: _TypeScopes, current: TypeName?) {
        this.scopes = scopes;
        this.current = current;
    }

    rewrite(e: Expression): Expression {
        var state = scopes.state;
        var lowered = scopes.tables.properties.lowered;
        e = lower_property(e, scopes.tables.properties, _PropertyAt(scopes, current), state);
        if (scopes.tables.properties.lowered != lowered) {
            scopes.edits += 1;
        }
        e = _bind_named_arguments(e);
        _resolve_overload(e);
        _resolve_method_overload(e);
        _infer_type_arguments(e);
        # `(a, b)`: spell out its tuple type once the elements' are known.
        if (e is FunctionCall(node)) {
            if (tuple_constructor_labels(node.function).is_value()) {
                var types = Array<TypeName>();
                for (var a in node.args) {
                    types.append(scopes.type_of(a, current));
                }
                var ty = tuple_literal_type(types);
                if (ty.is_value() and node.function != ty.value().to_string()) {
                    node.function = ty.value().to_string();
                    scopes.edits += 1;
                }
            }
        }
        # Calls through function values: `f(x)` on a local, parameter,
        # global or field of function type.
        if (e is FunctionCall(node)) {
            var callee = scopes.value_callee(node.function, current);
            if (callee.is_value()) {
                var (target, _) = callee.value();
                # The callee stands for the name the call spells.
                if (target is SymbolRef(symbol)) {
                    symbol.loc = node.loc;
                }
                if (target is MemberRef(member)) {
                    member.loc = node.loc;
                }
                scopes.edits += 1;
                return Expression.Invoke(InvokeExpression(target, node.args));
            }
        }
        # A value a `match` pattern binds: report patterns that do not fit.
        if (e is CaseValue(value)) {
            var subject = scopes.type_of(value.subject, current);
            var result = case_value_type(state, value, subject, _ScopeFields(scopes, subject));
            if (result is Err(d)) {
                state.report(d);
            }
            return e;
        }
        # `2.0 * v`: an operator on a number with an extension operator for
        # the right operand calls it.
        if (e is Binary(node)) {
            var number = scopes.number_operator(node.op, node.lhs, Optional<TypeName>.Empty, node.rhs, current);
            if (number.is_value()) {
                var (function, negated) = number.value();
                var args = Array<Expression>();
                args.append(node.lhs);
                args.append(node.rhs);
                var call = Expression.FunctionCall(FunctionCallExpression(function, args, node.loc));
                scopes.edits += 1;
                return negated ? Expression.Unary(UnaryExpression(call, UnaryOp.LogicalNot, node.loc)) : call;
            }
        }
        # `c.name()` on an enum value calls `Color::name(c)`; `x.__acquire()`
        # and `x.__release()` stay method calls for every type.
        if (e is MethodCall(node)) {
            bool refcount_step = (node.method == "__acquire" or node.method == "__release") and node.args.count == 0;
            if (!refcount_step) {
                var this_type = scopes.type_of(node.this_value, current).to_string();
                var key = value_type_key(state, this_type);
                bool value_method = key.is_value() and method_is_static(state, key.value(), node.method).is_value();
                if (is_enum(state, this_type) or value_method) {
                    var owner = key.is_value() ? key.value() : this_type;
                    var call = call_on_value(state, owner, node.method, node.this_value, node.args, node.loc);
                    if (call.is_value()) {
                        scopes.edits += 1;
                    }
                    return call.is_value() ? call.value() : e;
                }
            }
        }
        # `c.name` without a call: a value type's methods have no value form.
        if (e is MemberRef(node)) {
            var lhs_type = scopes.type_of(node.lhs, current).to_string();
            var key = value_type_key(state, lhs_type);
            if (!key.is_value() and is_enum(state, lhs_type)) {
                key = Optional<String>.Value(lhs_type);
            }
            if (key.is_value()) {
                var error = method_read(state, key.value(), node.name, node.loc);
                if (error.is_value()) {
                    state.report(error.value());
                    return e;
                }
            }
        }
        if (e is MethodCall(node)) {
            var this_type = scopes.type_of(node.this_value, current);
            if (!scopes.has_method(this_type, node.method)) {
                var field = scopes.field_type(this_type, node.method);
                if (field.is_value() and field.value().is_callable()) {
                    var callee = Expression.MemberRef(MemberRefExpression(node.this_value, node.method, node.loc));
                    scopes.edits += 1;
                    return Expression.Invoke(InvokeExpression(callee, node.args));
                }
            }
        }
        # A bare free-function name in value position is a function value;
        # any other unresolved name takes its declaration's type.
        if (e is SymbolRef(node)) {
            if (node.ty.is_auto() and node.id != "this") {
                var function_type = scopes.function_value(node.id, current);
                if (function_type.is_value()) {
                    scopes.edits += 1;
                    return Expression.FunctionRef(
                        FunctionRefExpression(node.id, function_type.value().copy(), node.loc)
                    );
                }
                var resolved = scopes._symbol_type(node.id, current);
                if (!resolved.is_empty() and !resolved.is_auto()) {
                    node.ty = resolved.copy();
                    scopes.edits += 1;
                }
            }
        }
        return e;
    }

    ## Binds a method call's named arguments once its receiver's type is
    ## known, and reports naming the arguments of a call through a function
    ## value.
    _bind_named_arguments(e: Expression): Expression {
        var state = scopes.state;
        match (e) {
            MethodCall(node) => {
                if (!has_named(node.args)) {
                    return e;
                }
                var receiver = scopes.type_of(node.this_value, current);
                if (receiver.is_empty() or receiver.contains_auto()) {
                    return e;
                }
                if (!scopes.has_method(receiver, node.method)) {
                    var field = scopes.field_type(receiver, node.method);
                    if (field.is_value() and field.value().is_callable()) {
                        report_function_value(state, field.value(), node.args);
                        return e;
                    }
                }
                scopes.edits += 1;
                return bind_method_call(e, receiver, scopes.tables.callees, state);
            }
            FunctionCall(node) => {
                if (has_named(node.args)) {
                    var callee = scopes.value_callee(node.function, current);
                    if (callee.is_value()) {
                        var (_, ty) = callee.value();
                        report_function_value(state, ty, node.args);
                    }
                }
            }
            Invoke(node) => {
                if (has_named(node.args)) {
                    var ty = scopes.type_of(node.callee, current);
                    if (!ty.is_empty() and !ty.contains_auto()) {
                        report_function_value(state, ty, node.args);
                    }
                }
            }
            else => {}
        }
        return e;
    }

    ## Rewrites a call to an overloaded function to the member its
    ## arguments select.
    _resolve_overload(e: Expression) {
        if (e is FunctionCall(node)) {
            var choice = scopes.select_overload(node.function, node.args, node.loc, current);
            if (choice.is_value()) {
                node.function = apply_choice(node.args, choice.value());
                scopes.resolved.append((node.loc, choice.value().callee));
                scopes.edits += 1;
            }
        }
    }

    ## Rewrites a call of an overloaded method to the member its arguments
    ## select.
    _resolve_method_overload(e: Expression) {
        if (!(e is MethodCall(_)) or scopes.overloads.is_empty()) {
            return;
        }
        var node = _method_call_of(e);
        # Typing the receiver is costly: first rule out a name no struct
        # overloads.
        if (!scopes.overloads.is_any_method_set(node.method)) {
            return;
        }
        var receiver = scopes.type_of(node.this_value, current);
        if (receiver.is_empty() or receiver.contains_auto() or !scopes.overloads.is_method_set(receiver, node.method)) {
            return;
        }
        var choice = scopes.select_method_overload(receiver, node.method, node.args, node.loc, current);
        if (choice.is_value()) {
            node.method = apply_choice(node.args, choice.value());
            scopes.resolved.append((node.loc, method_target(receiver, choice.value().callee)));
            scopes.edits += 1;
        }
    }

    ## A call to a generic function or method without (all) its type
    ## arguments becomes a call to the specialization its arguments select.
    _infer_type_arguments(e: Expression) {
        if (scopes.generic_base) {
            return;
        }
        if (e is MethodCall(node)) {
            # An operator method (`<`) is never generic.
            if (!_starts_name(node.method)) {
                return;
            }
            var written = parse_type_string(node.method);
            if (!scopes.tables.is_generic_method_name(written.name)) {
                return;
            }
            var owner = scopes.type_of(node.this_value, current);
            if (owner.contains_auto() or scopes.has_method(owner, node.method)) {
                return;
            }
            var key = owner.without_pointers().to_string();
            scopes.tables.note(_type_read(key));
            var methods = scopes.tables.generic_methods_of(key);
            if (!methods.is_value()) {
                return;
            }
            for (var (name, signature) in methods.value()) {
                if (name != written.name) {
                    continue;
                }
                var types = scopes.argument_types(node.args, current);
                var type_args = node.method.contains("<") ?
                    signature.complete(written.sub_types, types) :
                    signature.infer(types);
                if (type_args.is_value()) {
                    var specialized = specialization(written.name, type_args.value());
                    if (node.method != specialized) {
                        node.method = specialized;
                        scopes.edits += 1;
                    }
                }
                return;
            }
            return;
        }
        if (!(e is FunctionCall(_))) {
            return;
        }
        var call = _function_call_of(e);
        if (call.function.contains("<")) {
            if (_starts_name(call.function)) {
                _complete_type_arguments(call);
            }
            return;
        }
        scopes.tables.note(_function_read(call.function));
        var signature = scopes.tables.generic_function(call.function);
        if (!signature.is_value() or scopes.value_callee(call.function, current).is_value()) {
            return;
        }
        # Inside a method, a bare call may be one of the struct's methods.
        if (current.is_value()) {
            var st = current.value();
            if (scopes.calls_method(st, call.function, call.args.count)
                or scopes.field_type(st, call.function).is_value()) {
                return;
            }
        }
        var type_args = signature.value().infer(scopes.argument_types(call.args, current));
        if (type_args.is_value()) {
            scopes.edits += 1;
            call.function = specialization(call.function, type_args.value());
        }
    }

    ## A call writing only the leading type arguments takes the rest from
    ## its arguments (or their defaults).
    _complete_type_arguments(call: FunctionCallExpression) {
        var written = parse_type_string(call.function);
        scopes.tables.note(_function_read(written.name));
        var signature = scopes.tables.generic_function(written.name);
        if (!signature.is_value()) {
            return;
        }
        if (written.sub_types.count >= signature.value().params.count
            or scopes.value_callee(written.name, current).is_value()) {
            return;
        }
        var type_args = signature.value().complete(written.sub_types, scopes.argument_types(call.args, current));
        if (type_args.is_value()) {
            var specialized = specialization(written.name, type_args.value());
            if (call.function != specialized) {
                call.function = specialized;
                scopes.edits += 1;
            }
        }
    }
}

extend _ImplicitResolver with Rewriter;

_starts_name(text: String): bool {
    if (text.size == 0) {
        return false;
    }
    var b = text.bytes()[0];
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 or b >= 128;
}

_method_call_of(e: Expression): MethodCallExpression {
    if (e is MethodCall(node)) {
        return node;
    }
    return MethodCallExpression(Expression.ThisRef);
}

_function_call_of(e: Expression): FunctionCallExpression {
    if (e is FunctionCall(node)) {
        return node;
    }
    return FunctionCallExpression();
}

## Resolves `e`: its subjects, then each expression in it.
_resolve_expression(e: Expression, scopes: _TypeScopes, current: TypeName?): Expression {
    e = rewrite_expression(e, _SubjectFiller(scopes, current));
    e = rewrite_expression(e, _ImplicitResolver(scopes, current));
    return rewrite_expression(e, _SubjectFiller(scopes, current));
}

_resolve_block(block: Block, scopes: _TypeScopes, current: TypeName?) {
    ulong i = 0;
    while (i < block.items.count) {
        _resolve_statement(block, i, scopes, current);
        i += 1;
    }
}

_resolve_statement(block: Block, index: ulong, scopes: _TypeScopes, current: TypeName?) {
    match (block.items[index]) {
        Expression(e) => {
            block.items[index] = Statement.Expression(_resolve_expression(e, scopes, current));
        }
        Block(inner) => {
            scopes.push();
            _resolve_block(inner, scopes, current);
            scopes.pop();
        }
        Declaration(declaration) => {
            if (declaration is Variable(variable)) {
                # Resolve `auto` from the default value.
                if (variable.ty.is_auto() and variable.default.is_value()) {
                    var ty = scopes.type_of(variable.default.value(), current);
                    if (!ty.is_empty() and !ty.is_auto()) {
                        variable.ty = ty.copy();
                        scopes.edits += 1;
                    }
                }
                if (variable.default.is_value()) {
                    variable.default = Optional<Expression>.Value(
                        _resolve_expression(variable.default.value(), scopes, current)
                    );
                }
                scopes.symbols[scopes.symbols.count - 1].append((variable.name, variable.ty));
            }
        }
        Branch(branch) => {
            branch.condition = _resolve_expression(branch.condition, scopes, current);
            scopes.push();
            _resolve_block(branch.if_block, scopes, current);
            scopes.pop();
            if (branch.else_block.is_value()) {
                scopes.push();
                _resolve_block(branch.else_block.value(), scopes, current);
                scopes.pop();
            }
        }
        While(loop) => {
            loop.condition = _resolve_expression(loop.condition, scopes, current);
            scopes.push();
            _resolve_block(loop.block, scopes, current);
            scopes.pop();
        }
        Return(r) => {
            if (r.expr.is_value()) {
                var value = _resolve_expression(r.expr.value(), scopes, current);
                r.expr = Optional<Expression>.Value(value);
                var ty = scopes.type_of(value, current);
                if (scopes.returns.is_value()) {
                    scopes.returns.value().append(ty);
                }
            }
        }
        else => {}
    }
}

## Default arguments are resolved in the declaring scope (no locals).
_resolve_parameter_defaults(parameters: VariableDef[], scopes: _TypeScopes, current: TypeName?) {
    for (var p in parameters) {
        if (p.default.is_value()) {
            p.default = Optional<Expression>.Value(_resolve_expression(p.default.value(), scopes, current));
        }
    }
}

## Whether `function`'s return type is inferred from its returns.
_infers_return(function: FunctionDef): bool {
    return function.ty.is_auto() and !function.is_generic_func;
}

## Gives `function` the type its returns agree on: `void` when it returns
## no value (`int` for the entry point), the first resolved return type
## otherwise. Returns whether the type changed.
_finish_return_inference(function: FunctionDef, scopes: _TypeScopes): bool {
    if (!scopes.returns.is_value()) {
        return false;
    }
    var returns = scopes.returns.value();
    scopes.returns = Optional<Array<TypeName>>.Empty;
    if (returns.count == 0) {
        bool entry = !function.parent.is_value()
            and (function.name == "main"
                or function.name == MAIN_WITH_ARGUMENTS
                or function.name == entry_function(scopes.state.target));
        function.ty = TypeName.named(entry ? "int" : "void");
        return true;
    }
    for (var ty in returns) {
        if (!ty.is_empty() and !ty.is_auto()) {
            function.ty = ty.copy();
            return true;
        }
    }
    return false;
}

_returns_for(function: FunctionDef): Array<TypeName>? {
    return _infers_return(function) ?
        Optional<Array<TypeName>>.Value(Array<TypeName>()) :
        Optional<Array<TypeName>>.Empty;
}

## Walks `function`'s body in a scope of its own.
_resolve_body(function: FunctionDef, scopes: _TypeScopes, current: TypeName?) {
    scopes.function = function.name;
    scopes.function_loc = function.loc;
    scopes.push();
    scopes.params[scopes.params.count - 1] = function.parameters.copy();
    _resolve_block(function.body.value(), scopes, current);
    scopes.pop();
}

## One run of the pass over the callables `work` needs, after `bindings`;
## returns whether a function's return type was inferred or a call
## resolved.
_resolve_once(module: Module, state: PassState, work: _Worklist, bindings: _Bindings): bool {
    bool inferred = false;
    var trait_types = bindings.trait_types;
    var tables = ImplicitTables(module, state, trait_types);
    var overloads = bindings.overloads.is_value() ?
        bindings.overloads.value() :
        Overloads(module, state, Optional<TypeName[]>.Value(trait_types));
    var resolved = Array<(Loc, String)>();
    # Structs first: methods see field types.
    ulong s = 0;
    while (s < module.structs.count) {
        var st = module.structs[s];
        s += 1;
        # A checked unit's structs were resolved when it was checked, their
        # field defaults and methods; only those specialized on top of it
        # (`_find<Point>`) have bodies. (Resolving their defaults again also
        # added their call targets again.)
        if (module.checked.structs.contains(st.name) and !_has_body(st)) {
            continue;
        }
        var place = $"s{st.ty.to_string()}";
        var struct_read = _type_read(st.ty.to_string());
        var struct_base = _base_read(st.ty.to_string());
        var current = Optional<TypeName>.Value(st.ty);
        var scopes = _TypeScopes(tables, overloads, resolved, state);
        for (var p in st.generic_params) {
            scopes.unbound.append(p.name);
        }
        # A generic base (`Box` of `Box<T>`), not a specialization.
        scopes.generic_base = st.ty.is_generic() and st.name == st.ty.name;
        for (var field in st.field_members) {
            if (field.ty.is_auto() and field.default.is_value()) {
                var ty = scopes.type_of(field.default.value(), current);
                if (!ty.is_empty() and !ty.is_auto()) {
                    field.ty = ty.copy();
                    work.changing.insert(struct_read);
                    work.changing.insert(struct_base);
                }
            }
            # A default calling an overloaded constructor or function picks
            # its member.
            if (field.default.is_value()) {
                field.default = Optional<Expression>.Value(
                    rewrite_expression(field.default.value(), _OverloadOnly(scopes, current))
                );
            }
        }
        work.edits += scopes.edits;
        # Method bodies see this struct's resolved fields and its methods
        # in place of its table entries.
        var own_methods = Array<(String, TypeName)>();
        for (var m in st.method_members) {
            own_methods.append((m.name, m.ty));
        }
        scopes.own = Optional<_OwnStruct>.Value(_OwnStruct(st.ty.to_string(), st.field_members.copy(), own_methods));
        ulong index = 0;
        for (var c in st.constructors) {
            var at = $"{place}c{index}";
            index += 1;
            if (!work.needs(at, c)) {
                continue;
            }
            work.start(tables, scopes);
            _resolve_parameter_defaults(c.parameters, scopes, current);
            if (c.body.is_value()) {
                scopes.in_constructor = true;
                _resolve_body(c, scopes, current);
                scopes.in_constructor = false;
            }
            work.finish(at, c, tables, scopes);
        }
        if (st.destructor.body.is_value() and work.needs($"{place}d", st.destructor)) {
            work.start(tables, scopes);
            _resolve_body(st.destructor, scopes, current);
            work.finish($"{place}d", st.destructor, tables, scopes);
        }
        index = 0;
        for (var method in st.method_members) {
            var at = $"{place}m{index}:{method.name}";
            index += 1;
            if (!work.needs(at, method)) {
                continue;
            }
            work.start(tables, scopes);
            # A specialization's methods keep the base's name as parent.
            var method_struct = st.ty;
            if (method.parent.is_value() and method.parent.value() != st.ty.name) {
                var found = tables.struct_type_of(method.parent.value());
                if (found.is_value()) {
                    method_struct = found.value();
                }
            }
            var here = Optional<TypeName>.Value(method_struct);
            _resolve_parameter_defaults(method.parameters, scopes, here);
            scopes.returns = _returns_for(method);
            if (method.body.is_value()) {
                _resolve_body(method, scopes, here);
            } else {
                scopes.returns = Optional<Array<TypeName>>.Empty;
            }
            if (_finish_return_inference(method, scopes)) {
                inferred = true;
                work.changing.insert(_method_read(st.ty.to_string(), method.name));
                work.changing.insert(struct_base);
            }
            work.finish(at, method, tables, scopes);
        }
    }
    # Free functions.
    ulong f = 0;
    while (f < module.functions.count) {
        var function = module.functions[f];
        f += 1;
        if (!function.body.is_value() or is_checked_function(module, function)) {
            continue;
        }
        var at = $"f{function.name}";
        if (!work.needs(at, function)) {
            continue;
        }
        var none = Optional<TypeName>.Empty;
        var scopes = _TypeScopes(tables, overloads, resolved, state);
        for (var p in function.generic_params) {
            scopes.unbound.append(p.name);
        }
        scopes.generic_base = function.is_generic_func;
        var returns = _returns_for(function);
        work.start(tables, scopes);
        _resolve_parameter_defaults(function.parameters, scopes, none);
        scopes.returns = returns;
        _resolve_body(function, scopes, none);
        if (_finish_return_inference(function, scopes)) {
            inferred = true;
            work.changing.insert(_function_read(function.name));
        }
        work.finish(at, function, tables, scopes);
    }
    # Global variables: one shared scope so later globals see earlier ones.
    var scopes = _TypeScopes(tables, overloads, resolved, state);
    var none = Optional<TypeName>.Empty;
    for (var global in module.globals) {
        if (global.ty.is_auto() and global.default.is_value()) {
            var ty = scopes.type_of(global.default.value(), none);
            if (!ty.is_empty() and !ty.is_auto()) {
                global.ty = ty.copy();
                work.changing.insert($"g:{global.name}");
            }
        }
        if (global.default.is_value()) {
            global.default = Optional<Expression>.Value(_resolve_expression(global.default.value(), scopes, none));
        }
        scopes.symbols[0].append((global.name, global.ty));
    }
    work.edits += scopes.edits;
    if (resolved.count > 0) {
        inferred = true;
    }
    module.call_targets.append_all(resolved);
    return inferred;
}

## Whether any constructor, method or the destructor of `st` has a body.
_has_body(st: StructDef): bool {
    if (st.destructor.body.is_value()) {
        return true;
    }
    for (var c in st.constructors) {
        if (c.body.is_value()) {
            return true;
        }
    }
    for (var m in st.method_members) {
        if (m.body.is_value()) {
            return true;
        }
    }
    return false;
}

## Resolves only the overloaded calls in a field's default.
struct _OverloadOnly {
    var resolver: _ImplicitResolver;

    construct(scopes: _TypeScopes, current: TypeName?) {
        resolver = _ImplicitResolver(scopes, current);
    }

    rewrite(e: Expression): Expression {
        resolver._resolve_overload(e);
        return e;
    }
}

extend _OverloadOnly with Rewriter;

## What the binding passes changed, and the module's trait types after.
struct _Bindings {
    var trait_types: TypeName[];
    var bound: bool = false;
    var specialized: bool = false;
    var methods: bool = false;
    ## The overloads a binding pass built, while the module is as they saw it.
    var overloads: Overloads? = Optional<Overloads>.Empty;

    construct(trait_types: TypeName[]) {
        this.trait_types = trait_types;
    }
}

## The code of `module` holding what `search` looks for, if anything does.
_function_sites(module: Module, search: GenericFunctionSearch?): SiteSelection? {
    if (!search.is_value()) {
        return Optional<SiteSelection>.Empty;
    }
    return Optional<SiteSelection>.Value(select_sites(module, search.value().filter, true));
}

## The code of `module` holding what `search` looks for, if anything does.
_method_sites(module: Module, search: GenericMethodSearch?): SiteSelection? {
    if (!search.is_value()) {
        return Optional<SiteSelection>.Empty;
    }
    return Optional<SiteSelection>.Value(select_sites(module, search.value().filter, false));
}

## Runs the three binding passes: overloaded names, generic functions and
## generic methods used as values. They share tables while none of them
## changes the module, and the tables share the trait types one walk over
## every function finds; one more walk finds the code each pass needs.
##
## @param module the model, changed in place
## @param state the passes' state
## @returns what changed
_bind_values(module: Module, state: PassState): _Bindings {
    var result = _Bindings(used_trait_types(module, state.trait_types_memo()));
    var tables = ModuleTables(module, state, Optional<TypeName[]>.Value(result.trait_types));
    var values = function_value_search(module, state, tables);
    var functions = generic_function_search(module, state);
    var methods = generic_method_search(module);
    var filters = Array<SiteFilter>();
    var applied = Array<bool>();
    if (values.is_value()) {
        filters.append(values.value().filter);
        applied.append(false);
    }
    if (functions.is_value()) {
        filters.append(functions.value().filter);
        applied.append(true);
    }
    if (methods.is_value()) {
        filters.append(methods.value().filter);
        applied.append(false);
    }
    var selections = select_sites_each(module, filters, applied);
    ulong at = 0;
    var function_sites = Optional<SiteSelection>.Empty;
    var method_sites = Optional<SiteSelection>.Empty;
    if (values.is_value()) {
        result.bound = bind_function_values(module, state, tables, values.value(), selections[at]);
        at += 1;
    }
    if (functions.is_value()) {
        function_sites = Optional<SiteSelection>.Value(selections[at]);
        at += 1;
    }
    if (methods.is_value()) {
        method_sites = Optional<SiteSelection>.Value(selections[at]);
    }
    if (result.bound) {
        result.trait_types = used_trait_types(module, state.trait_types_memo());
        tables.reset(Optional<TypeName[]>.Value(result.trait_types));
        functions = generic_function_search(module, state);
        function_sites = _function_sites(module, functions);
    }
    if (functions.is_value()) {
        result.specialized = bind_generic_function_values(
            module, state, tables, functions.value(), function_sites.value()
        );
    }
    if (result.specialized) {
        result.trait_types = used_trait_types(module, state.trait_types_memo());
        tables.reset(Optional<TypeName[]>.Value(result.trait_types));
    }
    if (result.bound or result.specialized) {
        methods = generic_method_search(module);
        method_sites = _method_sites(module, methods);
    }
    if (methods.is_value()) {
        result.methods = bind_generic_method_values(module, state, tables, methods.value(), method_sites.value());
    }
    if (result.methods) {
        result.trait_types = used_trait_types(module, state.trait_types_memo());
    }
    # Binding nothing leaves the module as the search found it.
    if (values.is_value() and !result.bound and !result.specialized and !result.methods) {
        result.overloads = values.value().built_overloads();
    }
    return result;
}

## Resolves `auto` variable types, unresolved names, inferred return types
## and overloaded and generic calls.
##
## @param module the model, changed in place
## @param state the passes' state
export resolve_implicit_types(module: Module, state: PassState) {
    record_conformances(module, state);
    # Inferring a return type can type the callers' locals, and closure
    # types and inferred types feed each other: repeat while anything
    # changes, at most eight times. Each run walks only what changed and
    # what looks it up, since the last run here too.
    var memo = state.implicit;
    var work = _Worklist(memo);
    # Settling overloads by arity selects calls whose lookups did not
    # change: the callables whose last walk left one it could settle are
    # walked.
    work.settling = state.settle_overloads_by_arity;
    ulong round = 0;
    # Whether the last run changed nothing since its closures were synced.
    bool quiet = false;
    while (round < 8) {
        bool synced = sync_closures(module, state);
        var bindings = _bind_values(module, state);
        bool bound = bindings.bound or bindings.specialized or bindings.methods;
        # Code and declarations other passes changed: any before the first
        # run, and what closures and bindings changed before the others.
        work.checks_code = round == 0 or synced or bound;
        if (work.checks_code) {
            var declarations = _Declarations(module, bindings.trait_types);
            if (declarations.changes(memo, work.changed)) {
                work.all = true;
            }
            declarations.keep(memo);
        }
        bool inferred = _resolve_once(module, state, work, bindings);
        if (!inferred and !synced and !bound) {
            quiet = work.edits == 0 and work.changing.count == 0;
            break;
        }
        work.next_run();
        round += 1;
    }
    if (!quiet) {
        sync_closures(module, state);
    }
    # The declarations stay as the last run that took them saw them: the
    # next run announces what this one changed since, along with what other
    # passes change, and a walk of a callable already up to date changes
    # nothing. Taking them again here cost a walk of every body.
    memo.reads = work.reads;
    memo.prints = work.prints;
    memo.pending = work.changing;
    memo.unsettled = work.unsettled;
    memo.kept = true;
}
