## Generic constraints, as far
## as overload resolution needs it. A constraint names a trait, and every
## type argument of the parameter must conform to it nominally: a struct
## through an `extend S with Trait` (for a generic struct, `extend Box<T>
## with Trait` covers every `Box<X>`), a trait type when every member of the
## trait can be called through a value, a number, `bool` or enum through
## `extend int with Trait`. Pointers, tuples and function types conform to
## none; the built-in `Shared` accepts the thread-safe types.

import compiler.ast;
import [demangle, Diagnostic, Fix, Location] from compiler.diagnostic;
import [demangle_name] from compiler.link;
import [is_sealed] from "apply_extensions";
import "common";
import [Loc] from "loc";
import [
    Block,
    Bound,
    Expression,
    ExtensionDef,
    FunctionDef,
    GenericParam,
    Module,
    StructDef,
    TraitDef,
    TypeName,
    TypeUse,
    UseContext,
    Withheld
] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [is_dispatchable] from "traits";
import [parse_type_string, replace_map, SHARED_FUNCTION] from "type_name";
import [is_value_type, value_type_key] from "value_types";
import [Rewriter, rewrite_expression] from "walk";

## The built-in constraint `T: Shared`.
export const SHARED = "Shared";

## Returns whether constraint `ty` is the built-in `Shared`.
##
## @param ty the constraint
## @returns true for `Shared`
export is_shared_bound(ty: TypeName): bool {
    return ty.name == SHARED and ty.sub_types.count == 0;
}

## Returns whether any generic parameter in the module is constrained.
##
## @param module the model
## @returns true when a constraint is written anywhere
export has_constraints(module: Module): bool {
    for (var f in module.functions) {
        if (_constrained(f.generic_params)) {
            return true;
        }
    }
    for (var st in module.structs) {
        if (_constrained(st.generic_params)) {
            return true;
        }
        for (var m in st.generic_methods) {
            if (_constrained(m.generic_params)) {
                return true;
            }
        }
    }
    for (var t in module.traits) {
        if (_constrained(t.generic_params)) {
            return true;
        }
        for (var m in t.methods) {
            if (_constrained(m.generic_params)) {
                return true;
            }
        }
    }
    for (var e in module.extensions) {
        if (e.restated.count != 0) {
            return true;
        }
        for (var m in e.methods) {
            if (_constrained(m.generic_params)) {
                return true;
            }
        }
    }
    return module.constrained_aliases.count != 0;
}

_constrained(params: GenericParam[]): bool {
    for (var p in params) {
        if (p.bounds.count != 0) {
            return true;
        }
    }
    return false;
}

## One extension, as conformance needs it.
struct _Extension {
    var target: TypeName;
    var traits: TypeName[];
    ## The constraints it adds: the parameter's position, the trait and
    ## where it is written.
    var conditions: Array<(ulong, TypeName, Loc)>;

    construct(target: TypeName, traits: TypeName[], conditions: Array<(ulong, TypeName, Loc)>) {
        this.target = target;
        this.traits = traits;
        this.conditions = conditions;
    }
}

## A generic parameter in scope at a use: its constraints, and the end of
## its name or of its last constraint, for the fix that adds one.
struct _InScope {
    var bounds: Array<TypeName> = Array<TypeName>();
    var end: Loc;

    construct(p: GenericParam) {
        end = p.bounds.count > 0 ? p.bounds.last().loc : p.loc;
        for (var b in p.bounds) {
            bounds.append(b.ty);
        }
    }
}

## A constraint an argument does not meet.
export struct Unmet {
    ## The position of the parameter.
    var index: ulong;
    var param: String;
    var arg: TypeName;
    var required: TypeName;
    ## Where the constraint is written.
    var bound: Loc;

    construct(index: ulong, param: String, arg: TypeName, required: TypeName, bound: Loc) {
        this.index = index;
        this.param = param;
        this.arg = arg;
        this.required = required;
        this.bound = bound;
    }
}

## The runtime's ordering trait, which a tuple of `Comparable` elements
## conforms to (#367).
export const COMPARABLE = "Comparable";

## What deciding conformance needs from the module: `Conformance`.
export struct Conformance {
    ## Each trait's members a value of the trait type cannot call: the name
    ## and where it is declared.
    var _undispatchable: HashMap<String, Array<(String, Loc)>> = HashMap<String, Array<(String, Loc)>>();
    ## Structs by declared name (generic bases and plain structs): their
    ## parameters' names and where they are declared.
    var _structs: HashMap<String, (String[], Loc)> = HashMap<String, (String[], Loc)>();
    var _enums: HashMap<String, Loc> = HashMap<String, Loc>();
    var _extensions: Array<_Extension> = Array<_Extension>();
    ## The structs whose references are thread-safe, by name.
    var _shared: HashSet<String> = HashSet<String>();
    var _state: PassState;

    ## Collects what deciding conformance needs from `module`.
    ##
    ## @param module the model
    ## @param state the passes' state
    construct(module: Module, state: PassState) {
        _state = state;
        for (var t in module.traits) {
            var undispatchable = Array<(String, Loc)>();
            for (var m in t.methods) {
                if (!is_dispatchable(m)) {
                    undispatchable.append((set_name(m.name), m.loc));
                }
            }
            _undispatchable[t.name] = undispatchable;
        }
        for (var st in module.structs) {
            if (!st.name.contains("<")) {
                var params = Array<String>();
                for (var p in st.generic_params) {
                    params.append(p.name);
                }
                _structs[st.name] = (params, st.loc);
            }
            if (ast.has_attribute(st.attributes, SHARED) or st.ty.is_shared_function_type()) {
                _shared.insert(st.name);
            }
        }
        for (var e in module.enums) {
            _enums[e.name] = e.loc;
        }
        for (var e in module.extensions) {
            _extensions.append(_Extension(e.target, e.traits, _added_constraints(module, e.target, e.restated)));
        }
    }

    _is_trait(ty: TypeName): bool {
        return ty.is_scalar() and !ty.is_pointer() and _undispatchable.contains(ty.name);
    }

    ## The first part of `ty` that is not thread-safe, if any. A type
    ## parameter is thread-safe when it is constrained `Shared` itself.
    _unshared_part(ty: TypeName, scope: HashMap<String, _InScope>): TypeName? {
        var none = Optional<TypeName>.Empty;
        if (ty.sub_types.count == 0) {
            var param = scope.try_get(ty.name);
            if (param.is_value()) {
                for (var b in param.value().bounds) {
                    if (is_shared_bound(b)) {
                        return none;
                    }
                }
                return Optional<TypeName>.Value(ty);
            }
        }
        var name = ty.to_string();
        if (name == "void"
            or _state.is_integral(name)
            or ty.is_shared_function_type()
            or ty.is_extern_function_type()) {
            return none;
        }
        if (ty.is_function_type()) {
            return Optional<TypeName>.Value(ty);
        }
        if (ty.is_pointer() or ty.is_weak()) {
            return _unshared_part(ty.sub_types[0], scope);
        }
        if (ty.is_tuple()) {
            for (var e in ty.sub_types) {
                var part = _unshared_part(e, scope);
                if (part.is_value()) {
                    return part;
                }
            }
            return none;
        }
        # A `[Shared]` generic struct's own constraints say which arguments
        # it takes (`Atomic<T: Shared>`).
        if (_shared.contains(ty.name) or _shared.contains(name)) {
            return none;
        }
        return Optional<TypeName>.Value(ty);
    }

    ## Whether `arg` conforms to the trait type `required`.
    _conforms(arg: TypeName, required: TypeName, scope: HashMap<String, _InScope>): bool {
        if (is_shared_bound(required)) {
            return !_unshared_part(arg, scope).is_value();
        }
        var want = _canonical(required);
        if (arg.sub_types.count == 0) {
            var param = scope.try_get(arg.name);
            if (param.is_value()) {
                for (var b in param.value().bounds) {
                    if (_canonical(b) == want) {
                        return true;
                    }
                }
                return false;
            }
        }
        if (_is_trait(arg)) {
            return _canonical(arg) == want and _undispatchable[arg.name].count == 0;
        }
        if (arg.is_pointer()) {
            return false;
        }
        # A tuple of `Comparable` elements is `Comparable` (#367); a tuple
        # conforms to no other trait.
        if (arg.is_tuple()) {
            return want == _canonical(TypeName.named(COMPARABLE)) and _comparable_elements(arg, scope);
        }
        # A number, `bool` or enum conforms through `extend int with Tr`.
        if (arg.sub_types.count == 0) {
            var key = value_type_key(_state, arg.name);
            if (key.is_value()) {
                for (var e in _extensions) {
                    if (e.target.sub_types.count != 0) {
                        continue;
                    }
                    var target = value_type_key(_state, e.target.name);
                    if (!target.is_value() or target.value() != key.value()) {
                        continue;
                    }
                    for (var t in e.traits) {
                        if (_canonical(t) == want) {
                            return true;
                        }
                    }
                }
                return false;
            }
        }
        for (var (map, conditions) in _declaring(arg, required)) {
            bool met = true;
            for (var (i, bound, _) in conditions) {
                var copy = bound.copy();
                replace_map(copy, map);
                if (i >= arg.sub_types.count or !_conforms(arg.sub_types[i], copy, scope)) {
                    met = false;
                    break;
                }
            }
            if (met) {
                return true;
            }
        }
        return false;
    }

    ## Whether every element of the tuple type `ty` is `Comparable`, so the
    ## tuple is too (`synthesize_function_types` declares it).
    ##
    ## @param ty the tuple type
    ## @returns whether it is
    tuple_is_comparable(ty: TypeName): bool {
        return _undispatchable.contains(COMPARABLE) and _comparable_elements(ty, HashMap<String, _InScope>());
    }

    _comparable_elements(ty: TypeName, scope: HashMap<String, _InScope>): bool {
        for (var e in ty.sub_types) {
            if (!_conforms(e, TypeName.named(COMPARABLE), scope)) {
                return false;
            }
        }
        return true;
    }

    ## The extensions that declare `required` for `arg`, a struct: each
    ## with its parameters' arguments and the conditions it adds.
    _declaring(arg: TypeName, required: TypeName): Array<(Array<(String, TypeName)>, Array<(ulong, TypeName, Loc)>)> {
        var out = Array<(Array<(String, TypeName)>, Array<(ulong, TypeName, Loc)>)>();
        var found = _structs.try_get(arg.name);
        if (!found.is_value() or arg.is_pointer()) {
            return out;
        }
        var (params, _) = found.value();
        var want = _canonical(required);
        for (var e in _extensions) {
            if (e.target.name != arg.name) {
                continue;
            }
            # `extend Box<T>` (the struct's own parameters) covers every
            # `Box<X>`; `extend Box<int>` only itself.
            bool generic = e.target.sub_types.count == 0;
            if (!generic and e.target.sub_types.count == params.count) {
                generic = true;
                ulong i = 0;
                while (i < params.count) {
                    var t = e.target.sub_types[i];
                    if (t.sub_types.count != 0 or t.name != params[i]) {
                        generic = false;
                        break;
                    }
                    i += 1;
                }
            }
            var map = Array<(String, TypeName)>();
            if (generic) {
                ulong i = 0;
                while (i < params.count and i < arg.sub_types.count) {
                    map.append((params[i], arg.sub_types[i]));
                    i += 1;
                }
            } else if (_canonical(e.target) != _canonical(arg)) {
                continue;
            }
            for (var t in e.traits) {
                var copy = t.copy();
                replace_map(copy, map);
                if (_canonical(copy) == want) {
                    out.append((map, e.conditions));
                    break;
                }
            }
        }
        return out;
    }

    ## The note that says why `arg` does not conform to `required` although
    ## an extension declares it: the condition it does not meet.
    condition_note(arg: TypeName, required: TypeName): (String, Loc)? {
        var none = HashMap<String, _InScope>();
        # Another extension declaring it may be met.
        if (_conforms(arg, required, none)) {
            return Optional<(String, Loc)>.Empty;
        }
        for (var (map, conditions) in _declaring(arg, required)) {
            for (var (i, bound, loc) in conditions) {
                var copy = bound.copy();
                replace_map(copy, map);
                if (i >= arg.sub_types.count) {
                    continue;
                }
                var a = arg.sub_types[i];
                if (!_conforms(a, copy, none)) {
                    return Optional<(String, Loc)>.Value(
                        (
                            $"'{arg.display()}' conforms to '{required.display()}' only when '{a.display()}' conforms to '{copy.display()}'",
                            loc
                        )
                    );
                }
            }
        }
        return Optional<(String, Loc)>.Empty;
    }

    ## The error for `bound`, a constraint that names no trait.
    _not_a_trait(bound: Bound, params: GenericParam[]): Diagnostic {
        var name = bound.ty.display();
        var param = Optional<GenericParam>.Empty;
        if (bound.ty.sub_types.count == 0) {
            for (var p in params) {
                if (p.name == bound.ty.name) {
                    param = Optional<GenericParam>.Value(p);
                    break;
                }
            }
        }
        var declared = Optional<Loc>.Empty;
        var st = _structs.try_get(bound.ty.name);
        if (st.is_value()) {
            var (_, loc) = st.value();
            declared = Optional<Loc>.Value(loc);
        } else if (_enums.contains(bound.ty.name)) {
            declared = Optional<Loc>.Value(_enums[bound.ty.name]);
        } else if (param.is_value()) {
            declared = Optional<Loc>.Value(param.value().loc);
        }
        if (declared.is_value() and declared.value().is_none()) {
            declared = Optional<Loc>.Empty;
        }
        bool known = declared.is_value()
            or param.is_value()
            or _state.is_integral(bound.ty.name)
            or bound.ty.is_pointer()
            or bound.ty.name.starts_with("__");
        if (!known) {
            return error_at($"unknown type name '{name}'", bound.loc);
        }
        var error = error_at($"'{name}' is not a trait; a constraint must name a trait", bound.loc);
        if (declared.is_value()) {
            return error.with_note($"'{name}' declared here", Optional<Location>.Value(location_of(declared.value())));
        }
        return error;
    }

    ## Returns whether `arg` meets constraint `required` (concrete types).
    ##
    ## @param arg the type argument
    ## @param required the constraint
    ## @returns true when it conforms
    meets(arg: TypeName, required: TypeName): bool {
        return _conforms(arg, required, HashMap<String, _InScope>());
    }

    ## The first constraint of `params` that `args` (defaults filling the
    ## rest) do not meet. A constraint may name the parameters of its own
    ## list, which take the arguments.
    _unmet_in(params: GenericParam[], args: TypeName[], scope: HashMap<String, _InScope>): Unmet? {
        var map = Array<(String, TypeName)>();
        ulong i = 0;
        while (i < params.count) {
            var p = params[i];
            if (i < args.count) {
                map.append((p.name, args[i]));
            } else if (p.default.is_value()) {
                map.append((p.name, p.default.value()));
            } else {
                return Optional<Unmet>.Empty;
            }
            i += 1;
        }
        i = 0;
        while (i < params.count) {
            var (_, arg) = map[i];
            if (!arg.is_auto() and !arg.contains_auto()) {
                for (var bound in params[i].bounds) {
                    var required = bound.ty.copy();
                    replace_map(required, map);
                    if (!_conforms(arg, required, scope)) {
                        return Optional<Unmet>.Value(Unmet(i, params[i].name, arg, required, bound.loc));
                    }
                }
            }
            i += 1;
        }
        return Optional<Unmet>.Empty;
    }

    ## The first constraint of `params` that `args` do not meet, as
    ## "'T' does not conform to 'Trait'": overload resolution's note.
    ##
    ## @param params the generic parameters
    ## @param args the type arguments
    ## @returns the reason, or none when every constraint is met
    unmet(params: GenericParam[], args: TypeName[]): String? {
        var found = _unmet_in(params, args, HashMap<String, _InScope>());
        if (!found.is_value()) {
            return Optional<String>.Empty;
        }
        var u = found.value();
        return Optional<String>.Value($"'{u.arg.display()}' does not conform to '{u.required.display()}'");
    }

    ## The error for `unmet`, a constraint of `generic`, at `at`.
    _error(unmet: Unmet, generic: String, at: Loc, module: Module, scope: HashMap<String, _InScope>): Diagnostic {
        var arg = unmet.arg.display();
        var required = unmet.required.display();
        bool shared = is_shared_bound(unmet.required);
        var kind = shared ? "" : "trait ";
        var error = error_at(
            $"'{arg}' does not conform to {kind}'{required}', required by '{unmet.param}' in '{generic}'", at
        ).with_note("constraint declared here", Optional<Location>.Value(location_of(unmet.bound)));
        if (unmet.arg.sub_types.count == 0) {
            var param = scope.try_get(unmet.arg.name);
            if (param.is_value()) {
                bool bare = param.value().bounds.count == 0;
                var separator = bare ? ": " : " & ";
                var what = bare ? "a constraint" : "the constraint";
                var end = param.value().end;
                var declared = end.is_none() ? Optional<Location>.Empty : Optional<Location>.Value(location_of(end));
                error = error.with_note($"add {what} to '{arg}': '{arg}{separator}{required}'", declared);
                if (!end.is_none() and !at.is_none() and at.file == end.file) {
                    var insert = Loc();
                    insert.file = end.file;
                    insert.span = ast.Span(end.span.end, end.span.end);
                    var written = demangle(required);
                    error = error.with_fix(
                        Fix($"Constrain '{arg}' to '{written}'", location_of(insert), $"{separator}{written}")
                    );
                }
                return error;
            }
        }
        if (shared) {
            # Why it is not thread-safe, as for a `[Shared]` struct's field.
            var part = _unshared_part(unmet.arg, scope);
            if (!part.is_value()) {
                return error;
            }
            if (_is_trait(part.value())) {
                return error.with_note(
                    $"a value of trait type '{part.value().display()}' may refer to any struct, which need not be thread-safe",
                    Optional<Location>.Empty
                );
            }
            return _not_shared_note(error, part.value(), module);
        }
        if (_is_trait(unmet.arg)) {
            var undispatchable = _undispatchable[unmet.arg.name];
            if (_canonical(unmet.arg) == _canonical(unmet.required) and undispatchable.count > 0) {
                var (name, loc) = undispatchable[0];
                return error.with_note(
                    $"'{name}' cannot be called through a value of type '{arg}'",
                    Optional<Location>.Value(location_of(loc))
                );
            }
            return error;
        }
        var note = condition_note(unmet.arg, unmet.required);
        if (note.is_value()) {
            var (text, loc) = note.value();
            return error.with_note(text, Optional<Location>.Value(location_of(loc)));
        }
        # A sealed trait takes no conformance a program declares.
        if (is_sealed(module, unmet.required)) {
            return error;
        }
        # A number, `bool` or enum conforms by an extension too.
        if (is_value_type(_state, unmet.arg)) {
            var declared = _enums.try_get(unmet.arg.name);
            return error.with_note(
                $"declare it with 'extend {arg} with {required}'",
                declared.is_value() ? Optional<Location>.Value(location_of(declared.value())) : Optional<Location>.Empty
            );
        }
        var st = _structs.try_get(unmet.arg.name);
        if (st.is_value() and !unmet.arg.is_pointer()) {
            var (_, st_loc) = st.value();
            var written = demangle(arg);
            var required_written = demangle(required);
            error = error.with_note(
                $"declare it with 'extend {arg} with {required}'", Optional<Location>.Value(location_of(st_loc))
            );
            # The editor applies a fix to the file it shows.
            if (!at.is_none() and at.file == st_loc.file) {
                var end = _struct_end(_state, st_loc);
                if (end.is_value()) {
                    var insert = Loc();
                    insert.file = st_loc.file;
                    insert.span = ast.Span(end.value(), end.value());
                    error = error.with_fix(
                        Fix(
                            $"Declare 'extend {written} with {required_written}'",
                            location_of(insert),
                            $"\n\nextend {written} with {required_written} {{\n}}"
                        )
                    );
                }
            }
        }
        return error;
    }
}

## `diagnostic` with a note saying why `ty` is not thread-safe.
_not_shared_note(diagnostic: Diagnostic, ty: TypeName, module: Module): Diagnostic {
    if (ty.is_function_type()) {
        var shared = ty.copy();
        shared.name = SHARED_FUNCTION;
        return diagnostic.with_note(
            $"declare the function type '{shared.display()}' to share it between threads", Optional<Location>.Empty
        );
    }
    var name = ty.to_string();
    for (var st in module.structs) {
        if (st.name == name) {
            if (st.loc.is_none()) {
                return diagnostic;
            }
            return diagnostic.with_note(
                $"'{ty.display()}' is not declared [Shared]", Optional<Location>.Value(location_of(st.loc))
            );
        }
    }
    return diagnostic;
}

## Where the struct declared at `loc` ends, just past its `}`. Needs the program's source text.
_struct_end(state: PassState, loc: Loc): ulong? {
    var none = Optional<ulong>.Empty;
    if ((loc.file as ulong) >= state.sources.count) {
        return none;
    }
    var text = state.sources[loc.file as ulong].text;
    var bytes = text.bytes();
    ulong i = loc.span.start;
    while (i < bytes.count and bytes[i] != '{') {
        i += 1;
    }
    if (i >= bytes.count) {
        return none;
    }
    ulong depth = 0;
    while (i < bytes.count) {
        var b = bytes[i];
        if (b == '#') {
            while (i < bytes.count and bytes[i] != '\n') {
                i += 1;
            }
        } else if (b == '"') {
            i += 1;
            while (i < bytes.count and bytes[i] != '"') {
                if (bytes[i] == '\\') {
                    i += 1;
                }
                i += 1;
            }
        } else if (b == '{') {
            depth += 1;
        } else if (b == '}') {
            depth -= 1;
            if (depth == 0) {
                return Optional<ulong>.Value(i + 1);
            }
        }
        i += 1;
    }
    return none;
}

## Every constrained extension of struct `name`: the extension and the
## constraints it adds.
_constrained_extensions(module: Module, name: String): Array<(ExtensionDef, Array<(ulong, Bound)>)> {
    var out = Array<(ExtensionDef, Array<(ulong, Bound)>)>();
    for (var e in module.extensions) {
        if (e.target.name != name) {
            continue;
        }
        var added = _added_bounds(module, e.target, e.restated);
        if (added.count > 0) {
            out.append((e, added));
        }
    }
    return out;
}

## The constraints an extension adds to its struct's parameters, beyond
## the struct's own.
_added_bounds(module: Module, target: TypeName, restated: Array<(ulong, Bound)>): Array<(ulong, Bound)> {
    var out = Array<(ulong, Bound)>();
    if (restated.count == 0) {
        return out;
    }
    for (var st in module.structs) {
        if (st.name != target.name or st.generic_params.count == 0) {
            continue;
        }
        for (var (i, bound) in restated) {
            if (i >= st.generic_params.count) {
                continue;
            }
            bool already = false;
            for (var b in st.generic_params[i].bounds) {
                if (_canonical(b.ty) == _canonical(bound.ty)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                out.append((i, bound));
            }
        }
        return out;
    }
    return out;
}

_added_constraints(module: Module, target: TypeName, restated: Array<(ulong, Bound)>): Array<(ulong, TypeName, Loc)> {
    var out = Array<(ulong, TypeName, Loc)>();
    for (var (i, bound) in _added_bounds(module, target, restated)) {
        out.append((i, bound.ty, bound.loc));
    }
    return out;
}

## The generics a use can name that constrain a parameter, by name: their
## parameters. The first declaration of a name is the one a use means.
_constrained_generics(module: Module): HashMap<String, GenericParam[]> {
    var first = HashMap<String, GenericParam[]>();
    var order = Array<String>();
    var add = (name: String, params: GenericParam[]) => {
        if (!first.contains(name)) {
            first[name] = params;
            order.append(name);
        }
    };
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            add(st.name, st.generic_params);
        }
    }
    for (var t in module.traits) {
        add(t.name, t.generic_params);
    }
    for (var f in module.functions) {
        if (f.is_generic_func) {
            add(f.name, f.generic_params);
        }
    }
    for (var a in module.constrained_aliases) {
        add(a.name, a.generic_params);
    }
    var out = HashMap<String, GenericParam[]>();
    for (var name in order) {
        if (_constrained(first[name])) {
            out[name] = first[name];
        }
    }
    return out;
}

## The scope of a use: its parameters, and inside `extend Box<T>` the
## parameters of `Box`, which carry its constraints.
_scope_of(module: Module, context: UseContext): HashMap<String, _InScope> {
    var scope = HashMap<String, _InScope>();
    if (context.extension.is_value()) {
        var target = context.extension.value();
        for (var st in module.structs) {
            if (st.name == target.name and st.generic_params.count != 0) {
                for (var p in st.generic_params) {
                    scope[p.name] = _InScope(p);
                }
                break;
            }
        }
    }
    for (var p in context.scope) {
        var own = _InScope(p);
        var outer = scope.try_get(p.name);
        if (outer.is_value() and context.extension.is_value()) {
            # An extension's parameter keeps its struct's constraints.
            outer.value().bounds.append_all(own.bounds);
        } else {
            scope[p.name] = own;
        }
    }
    return scope;
}

## A declared list of generic parameters: the name of what declares it,
## the list, and the parameters of what encloses it.
struct _Declared {
    var name: String;
    var params: GenericParam[];
    var outer: GenericParam[];

    construct(name: String, params: GenericParam[], outer: GenericParam[]) {
        this.name = name;
        this.params = params;
        this.outer = outer;
    }
}

## Every declared list of generic parameters, in declaration order.
_declarations(module: Module): Array<_Declared> {
    var out = Array<_Declared>();
    var none = Array<GenericParam>();
    for (var st in module.structs) {
        if (st.name.contains("<")) {
            continue;
        }
        out.append(_Declared(st.name, st.generic_params, none));
        for (var m in st.generic_methods) {
            out.append(_Declared(set_name(m.name), m.generic_params, st.generic_params));
        }
    }
    for (var t in module.traits) {
        out.append(_Declared(t.name, t.generic_params, none));
        for (var m in t.methods) {
            out.append(_Declared(set_name(m.name), m.generic_params, t.generic_params));
        }
    }
    for (var e in module.extensions) {
        var outer = none;
        for (var st in module.structs) {
            if (st.name == e.target.name and st.generic_params.count != 0) {
                outer = st.generic_params;
                break;
            }
        }
        for (var m in e.methods) {
            out.append(_Declared(set_name(m.name), m.generic_params, outer));
        }
    }
    for (var f in module.functions) {
        if (f.is_generic_func) {
            out.append(_Declared(set_name(f.name), f.generic_params, none));
        }
    }
    for (var a in module.constrained_aliases) {
        out.append(_Declared(a.name, a.generic_params, none));
    }
    return out;
}

## Checks the constraints themselves, the uses written in the source, and
## the concrete overrides, then the specializations gathered so far.
##
## @param module the model
## @param state the passes' state, which takes the first error
export check_constraints(module: Module, state: PassState) {
    # `Shared` in a constraint is always the built-in, so a trait cannot
    # take the name.
    for (var t in module.traits) {
        if (demangle_name(t.name) == SHARED) {
            state.report(
                error_at($"trait '{SHARED}' takes the name of the built-in constraint 'Shared'; rename it", t.loc)
            );
            return;
        }
    }
    if (!has_constraints(module)) {
        return;
    }
    var conformance = Conformance(module, state);
    # Specializations copy their base's parameters: check each once.
    var seen = HashSet<Loc>();
    for (var declared in _declarations(module)) {
        for (var p in declared.params) {
            for (var bound in p.bounds) {
                if (seen.contains(bound.loc)) {
                    continue;
                }
                seen.insert(bound.loc);
                if (conformance._is_trait(bound.ty) or is_shared_bound(bound.ty)) {
                    continue;
                }
                var params = declared.params.copy();
                params.append_all(declared.outer);
                state.report(conformance._not_a_trait(bound, params));
                return;
            }
        }
    }
    # A constraint on an extension's parameter: the struct's own, restated,
    # or one it adds (a constrained extension).
    for (var ext in module.extensions) {
        for (var (i, bound) in ext.restated) {
            var base = Optional<StructDef>.Empty;
            for (var st in module.structs) {
                if (st.name == ext.target.name and st.generic_params.count != 0) {
                    base = Optional<StructDef>.Value(st);
                    break;
                }
            }
            bool own = base.is_value() and i < base.value().generic_params.count and i < ext.target.sub_types.count;
            if (own) {
                var a = ext.target.sub_types[i];
                own = a.sub_types.count == 0 and a.name == base.value().generic_params[i].name;
            }
            if (own) {
                if (conformance._is_trait(bound.ty) or is_shared_bound(bound.ty)) {
                    continue;
                }
                state.report(conformance._not_a_trait(bound, base.value().generic_params));
            } else {
                state.report(
                    error_at($"only the parameters of '{ext.target.name}' can restate its constraints", bound.loc)
                );
            }
            return;
        }
    }
    if (!_check_conditional_members(module, state)) {
        return;
    }
    # Each default meets its parameter's constraints.
    seen = HashSet<Loc>();
    for (var declared in _declarations(module)) {
        var scope = HashMap<String, _InScope>();
        for (var p in declared.params) {
            scope[p.name] = _InScope(p);
        }
        ulong i = 0;
        while (i < declared.params.count) {
            var p = declared.params[i];
            i += 1;
            if (!p.default.is_value() or p.bounds.count == 0) {
                continue;
            }
            var first = p.bounds[0];
            if (seen.contains(first.loc)) {
                continue;
            }
            seen.insert(first.loc);
            # The default stands for this parameter; earlier ones stay
            # themselves.
            var args = Array<TypeName>();
            var head = Array<GenericParam>();
            ulong k = 0;
            while (k < i - 1) {
                args.append(TypeName.named(declared.params[k].name));
                head.append(declared.params[k]);
                k += 1;
            }
            args.append(p.default.value());
            head.append(p);
            var unmet = conformance._unmet_in(head, args, scope);
            if (unmet.is_value() and unmet.value().index == i - 1) {
                var at = p.default_loc.is_none() ? first.loc : p.default_loc;
                state.report(conformance._error(unmet.value(), declared.name, at, module, scope));
                return;
            }
        }
    }
    # Each generic type written with arguments.
    var generics = _constrained_generics(module);
    seen = HashSet<Loc>();
    for (var type_use in module.type_uses) {
        var params = generics.try_get(type_use.ty.name);
        if (!params.is_value()) {
            continue;
        }
        if (type_use.args.count > 0) {
            if (seen.contains(type_use.args[0])) {
                continue;
            }
            seen.insert(type_use.args[0]);
        }
        var context = _compiled(module, type_use, state);
        if (!context.is_value()) {
            continue;
        }
        var scope = _scope_of(module, context.value());
        var unmet = conformance._unmet_in(params.value(), type_use.ty.sub_types, scope);
        if (unmet.is_value()) {
            var at = unmet.value().index < type_use.args.count ? type_use.args[unmet.value().index] : Loc.none();
            state.report(conformance._error(unmet.value(), type_use.ty.name, at, module, scope));
            return;
        }
    }
    check_specializations(module, state);
}

## A conformance needs its members wherever it holds: one a constrained
## extension provides (`extend Box<T: Named> { name() }`) does not serve
## `extend Box<T> with Named`, which holds for every `Box<X>`. Returns false
## after reporting.
_check_conditional_members(module: Module, state: PassState): bool {
    for (var ext in module.extensions) {
        if (ext.traits.count == 0) {
            continue;
        }
        var base = Optional<StructDef>.Empty;
        for (var s in module.structs) {
            if (s.name == ext.target.name and s.generic_params.count != 0) {
                base = Optional<StructDef>.Value(s);
                break;
            }
        }
        if (!base.is_value()) {
            continue;
        }
        var st = base.value();
        var own = Array<(ulong, TypeName)>();
        for (var (i, b) in _added_bounds(module, ext.target, ext.restated)) {
            own.append((i, _canonical(b.ty)));
        }
        var others = _constrained_extensions(module, st.name);
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
            for (var required in def.value().methods) {
                var set = set_name(required.name);
                var implementers = Array<FunctionDef>();
                for (var m in st.method_members) {
                    if (!m.trait_default.is_value() and set_name(m.name) == set) {
                        implementers.append(m);
                    }
                }
                for (var m in st.generic_methods) {
                    if (!m.trait_default.is_value() and set_name(m.name) == set) {
                        implementers.append(m);
                    }
                }
                # The constraint each implementer needs beyond this
                # conformance's own, if any.
                var needed = Array<(ulong, Bound)?>();
                for (var m in implementers) {
                    needed.append(_needs(m, others, own));
                }
                if (needed.count == 0 or !needed[0].is_value()) {
                    continue;
                }
                bool all = true;
                for (var n in needed) {
                    if (!n.is_value()) {
                        all = false;
                    }
                }
                if (!all) {
                    continue;
                }
                var (i, bound) = needed[0].value();
                var param = i < st.generic_params.count ? st.generic_params[i].name : "";
                var trait_shown = trait_name.display();
                var bound_shown = bound.ty.display();
                state.report(
                    error_at(
                        $"'{st.name}' conforms to '{trait_shown}' for every '{param}', but its '{set}' exists only when '{param}' conforms to '{bound_shown}'",
                        ext.loc
                    ).with_note(
                        "constraint declared here",
                        Optional<Location>.Value(location_of(bound.loc))
                    ).with_note(
                        $"make the conformance conditional: 'extend {st.name}<{param}: {bound_shown}> with {trait_shown}'",
                        Optional<Location>.Empty
                    )
                );
                return false;
            }
        }
    }
    return true;
}

_needs(
    m: FunctionDef, others: Array<(ExtensionDef, Array<(ulong, Bound)>)>, own: Array<(ulong, TypeName)>
): (ulong, Bound)? {
    for (var (other, added) in others) {
        bool provides = false;
        for (var x in other.methods) {
            if (x.loc == m.loc) {
                provides = true;
                break;
            }
        }
        if (!provides) {
            continue;
        }
        for (var (i, b) in added) {
            bool covered = false;
            for (var (j, t) in own) {
                if (j == i and t == _canonical(b.ty)) {
                    covered = true;
                    break;
                }
            }
            if (!covered) {
                return Optional<(ulong, Bound)>.Value((i, b));
            }
        }
    }
    return Optional<(ulong, Bound)>.Empty;
}

## Checks the struct and function specializations gathered so far, before
## they are cloned: one that
## fails comes from an inferred call, so it is reported at the call's
## argument that fixed the failing type argument.
##
## @param module the model
## @param state the passes' state, which takes the first error
export check_specializations(module: Module, state: PassState) {
    if (!has_constraints(module)) {
        return;
    }
    var generics = _constrained_generics(module);
    # The specializations checked before (in an earlier round, or with a
    # checked unit) met their constraints then, and still do: conformances
    # are only ever added.
    var specs = Array<TypeName>();
    var (struct_from, func_from) = state.checked_specs;
    for (var i in struct_from..module.struct_specs.count) {
        var s = module.struct_specs[i];
        if (generics.contains(s.name)) {
            specs.append(s);
        }
    }
    for (var i in func_from..module.func_specs.count) {
        var s = module.func_specs[i];
        if (generics.contains(s.name)) {
            specs.append(s);
        }
    }
    state.checked_specs = (module.struct_specs.count, module.func_specs.count);
    if (specs.count == 0) {
        return;
    }
    var conformance = Conformance(module, state);
    var none = HashMap<String, _InScope>();
    for (var spec in specs) {
        var unmet = conformance._unmet_in(generics[spec.name], spec.sub_types, none);
        if (unmet.is_value()) {
            var at = _spec_site(module, spec, unmet.value(), state);
            state.report(conformance._error(unmet.value(), spec.name, at, module, none));
            return;
        }
    }
}

## The context of `type_use`, when this platform compiles the code it is
## in.
_compiled(module: Module, type_use: TypeUse, state: PassState): UseContext? {
    if (type_use.context >= module.use_contexts.count) {
        return Optional<UseContext>.Empty;
    }
    var context = module.use_contexts[type_use.context];
    var kept = state.target.keep(context.conditions);
    if (kept.is_ok() and !kept.value()) {
        return Optional<UseContext>.Empty;
    }
    return Optional<UseContext>.Value(context);
}

## Where the specialization `spec` is asked for: a use that spells it, or
## the argument of a call to it whose parameter's type mentions the failing
## type parameter, else the call.
_spec_site(module: Module, spec: TypeName, unmet: Unmet, state: PassState): Loc {
    for (var type_use in module.type_uses) {
        if (_canonical(type_use.ty) == _canonical(spec) and _compiled(module, type_use, state).is_value()) {
            if (unmet.index < type_use.args.count) {
                return type_use.args[unmet.index];
            }
            break;
        }
    }
    var base = Optional<FunctionDef>.Empty;
    for (var f in module.functions) {
        if (f.is_generic_func and f.name == spec.name) {
            base = Optional<FunctionDef>.Value(f);
            break;
        }
    }
    var finder = _SpecCallFinder(module, spec.to_string(), base, unmet.param);
    _for_each_expression(module, finder);
    if (finder.found.is_value()) {
        return finder.found.value();
    }
    if (base.is_value()) {
        return base.value().loc;
    }
    for (var st in module.structs) {
        if (st.name == spec.name) {
            return st.loc;
        }
    }
    return Loc.none();
}

## The argument of a call to `base` that fixes `param`: the first whose
## parameter's declared type mentions it.
##
## @param module the model
## @param base the generic function called, if known
## @param param the type parameter
## @param args the call's arguments
## @param call where the call is
## @returns where to report
export argument_site(module: Module, base: FunctionDef?, param: String, args: Expression[], call: Loc): Loc {
    if (!base.is_value()) {
        return call;
    }
    ulong i = 0;
    while (i < base.value().parameters.count and i < args.count) {
        if (_mentions_name(base.value().parameters[i].ty, param)) {
            var own = _expression_loc(args[i]);
            if (!own.is_none()) {
                return own;
            }
            for (var (c, j, at) in module.literal_args) {
                if (c == call and j == i) {
                    return at;
                }
            }
            return call;
        }
        i += 1;
    }
    return call;
}

_mentions_name(ty: TypeName, name: String): bool {
    if (ty.name == name) {
        return true;
    }
    for (var t in ty.sub_types) {
        if (_mentions_name(t, name)) {
            return true;
        }
    }
    return false;
}

## Finds the first call to a specialization.
struct _SpecCallFinder {
    var module: Module;
    var name: String;
    var base: FunctionDef?;
    var param: String;
    var found: Loc? = Optional<Loc>.Empty;

    construct(module: Module, name: String, base: FunctionDef?, param: String) {
        this.module = module;
        this.name = name;
        this.base = base;
        this.param = param;
    }

    rewrite(e: Expression): Expression {
        if (found.is_value()) {
            return e;
        }
        if (e is FunctionCall(call)) {
            if (call.function == name) {
                found = Optional<Loc>.Value(argument_site(module, base, param, call.args, call.loc));
            }
        }
        return e;
    }
}

extend _SpecCallFinder with Rewriter;

## Applies `visitor` to every expression of the module's code, in
## declaration order: functions, struct methods and constructors, extension
## methods, then globals. `static` blocks are not entered.
_for_each_expression(module: Module, visitor: Rewriter) {
    for (var f in module.functions) {
        _visit_function_body(f, visitor);
    }
    for (var st in module.structs) {
        for (var m in st.method_members) {
            _visit_function_body(m, visitor);
        }
        for (var c in st.constructors) {
            _visit_function_body(c, visitor);
        }
    }
    for (var ext in module.extensions) {
        for (var m in ext.methods) {
            _visit_function_body(m, visitor);
        }
    }
    for (var g in module.globals) {
        if (g.default.is_value()) {
            rewrite_expression(g.default.value(), visitor);
        }
    }
}

_visit_function_body(f: FunctionDef, visitor: Rewriter) {
    if (f.body.is_value()) {
        _visit_body_block(f.body.value(), visitor);
    }
}

_visit_body_block(block: Block, visitor: Rewriter) {
    for (var item in block.items) {
        match (item) {
            Expression(e) => {
                rewrite_expression(e, visitor);
            }
            Block(inner) => {
                _visit_body_block(inner, visitor);
            }
            Declaration(declaration) => {
                if (declaration is Variable(v)) {
                    if (v.default.is_value()) {
                        rewrite_expression(v.default.value(), visitor);
                    }
                }
            }
            Branch(branch) => {
                rewrite_expression(branch.condition, visitor);
                _visit_body_block(branch.if_block, visitor);
                if (branch.else_block.is_value()) {
                    _visit_body_block(branch.else_block.value(), visitor);
                }
            }
            While(loop) => {
                rewrite_expression(loop.condition, visitor);
                _visit_body_block(loop.block, visitor);
            }
            Return(r) => {
                if (r.expr.is_value()) {
                    rewrite_expression(r.expr.value(), visitor);
                }
            }
            else => {}
        }
    }
}

## Removes from `specialized`, a specialization of `base`, the members and
## conformances of each constrained extension whose added constraints its
## type arguments do not meet.
##
## @param module the model
## @param conformance the program's conformances
## @param base the generic base
## @param specialized the specialization, changed in place
## @returns what it removed
export withhold(module: Module, conformance: Conformance, base: StructDef, specialized: StructDef): Withheld[] {
    var withheld = Array<Withheld>();
    var args = specialized.ty.sub_types;
    var map = Array<(String, TypeName)>();
    ulong p = 0;
    while (p < base.generic_params.count and p < args.count) {
        map.append((base.generic_params[p].name, args[p]));
        p += 1;
    }
    for (var ext in module.extensions) {
        if (ext.target.name != base.name) {
            continue;
        }
        var unmet = Optional<(TypeName, TypeName, Loc)>.Empty;
        for (var (i, bound) in _added_bounds(module, ext.target, ext.restated)) {
            var required = bound.ty.copy();
            replace_map(required, map);
            if (i >= args.count) {
                continue;
            }
            if (!conformance.meets(args[i], required)) {
                unmet = Optional<(TypeName, TypeName, Loc)>.Value((args[i], required, bound.loc));
                break;
            }
        }
        if (!unmet.is_value()) {
            continue;
        }
        var (arg, required, at) = unmet.value();
        var traits = Array<TypeName>();
        for (var t in ext.traits) {
            var copy = t.copy();
            replace_map(copy, map);
            traits.append(_canonical(copy));
        }
        # A conformance another extension declares and the arguments meet
        # stays, with the trait defaults it copied in.
        var kept = Array<TypeName>();
        for (var t in traits) {
            if (conformance.meets(specialized.ty, t)) {
                kept.append(t);
            }
        }
        var own = HashSet<Loc>();
        for (var m in ext.methods) {
            own.insert(m.loc);
        }
        var from_extension = (m: FunctionDef) => own.contains(m.loc)
            or (m.trait_default.is_value() and m.owner == ext.loc and kept.count == 0);
        var members = specialized.method_members.copy();
        members.append_all(specialized.generic_methods);
        for (var m in members) {
            if (from_extension(m)) {
                withheld.append(
                    Withheld(
                        owner = specialized.name,
                        member = set_name(m.name),
                        name = m.name,
                        params = m.parameters.count,
                        arg = arg.copy(),
                        bound = required.copy(),
                        at = at
                    )
                );
            }
        }
        var methods = Array<FunctionDef>();
        for (var m in specialized.method_members) {
            if (!from_extension(m)) {
                methods.append(m);
            }
        }
        specialized.method_members = methods;
        var generic_methods = Array<FunctionDef>();
        for (var m in specialized.generic_methods) {
            if (!from_extension(m)) {
                generic_methods.append(m);
            }
        }
        specialized.generic_methods = generic_methods;
        var kept_traits = Array<TypeName>();
        for (var t in specialized.traits) {
            var c = _canonical(t);
            if (!traits.contains(c) or kept.contains(c)) {
                kept_traits.append(t);
            }
        }
        specialized.traits = kept_traits;
    }
    return withheld;
}

## The error for a call of generic method `base` at `spec` whose type
## arguments do not meet its constraints: at the argument that fixes the
## unmet parameter, else the call.
##
## @param conformance the program's conformances
## @param module the model
## @param base the generic method
## @param spec the specialization the call names
## @param call where the call is
## @param args the call's arguments
## @returns the error, if a constraint is unmet
export check_method_call(
    conformance: Conformance, module: Module, base: FunctionDef, spec: TypeName, call: Loc, args: Expression[]
): Diagnostic? {
    var unmet = conformance._unmet_in(base.generic_params, spec.sub_types, HashMap<String, _InScope>());
    if (!unmet.is_value()) {
        return Optional<Diagnostic>.Empty;
    }
    var at = argument_site(module, Optional<FunctionDef>.Value(base), unmet.value().param, args, call);
    return Optional<Diagnostic>.Value(
        conformance._error(unmet.value(), set_name(base.name), at, module, HashMap<String, _InScope>())
    );
}
