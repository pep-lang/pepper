## Conversions where a value flows into a typed slot (a variable's
## initializer, an assignment, an argument, a return): `convert_to_traits`.
##
## A value reaching a struct slot whose constructor is `[Implicit]` from its
## type (or a type it promotes to) becomes that constructor's call; a
## struct value reaching a trait slot is wrapped in `ToTrait`, which the
## struct must conform to by `extend S with Tr`; string literals and
## `StringConstant`s become C strings, `StringConstant`s and `String`s as
## their slots need; tuple and collection literals take their slot's type.
## A decimal literal above `long`'s range fits only a `ulong` slot (or a
## float's): any other integer slot is an error.
## Calls through a trait value are checked against the trait's
## dispatchable members, and every trait type the program uses is recorded
## for code generation.

import compiler.ast;
import [Location] from compiler.diagnostic;
import [is_sealed] from "apply_extensions";
import [bit_width, is_float_type] from "arithmetic";
import [IMPLICIT_ATTRIBUTE, STRING_CONSTANT] from "builder";
import [checked_decls, unit_decls] from "checked";
import "closure_sites";
import "closures";
import "common";
import [Conformance] from "constraints";
import [unsigned_literal] from "literals";
import [Loc] from "loc";
import [
    BinaryOp,
    Block,
    CastKind,
    Conversion,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    MethodCallExpression,
    Module,
    Statement,
    StructDef,
    ToTraitExpression,
    TraitDef,
    TraitType,
    TypeName
] from "model";
import "overload_select";
import "shared_functions";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [instance, trait_def, used_trait_types] from "traits";
import [parse_type_string, pointee_name] from "type_name";
import "value_structs";
import [is_value_type, value_type_key] from "value_types";
import [Rewriter, rewrite_children] from "walk";

## Converts values to the types of the slots they flow into (see above).
##
## @param module the model, changed in place
## @param state the passes' state, which takes the error
export convert_to_traits(module: Module, state: PassState) {
    # A checked declaration's values were converted with its unit: only the
    # unit's own code is walked, and a checked declaration is looked up by
    # name when the walk names it (`checked_decls`).
    var own = unit_decls(module);
    var implicit = _Implicits(module, state);
    for (var st in own.structs) {
        implicit.add(st);
    }
    # shortcut: a program with no traits (only one built without the
    # runtime) skips this pass, so its decimal literals past `long`'s range
    # go unchecked; walk it for them if such programs ever matter.
    if (module.traits.count == 0 and !implicit.any(module)) {
        return;
    }
    var converter = _TraitConversions(module, state, implicit);
    converter.check_covariant_returns(own.structs);
    converter.current = Optional<TypeName>.Empty;
    for (var f in own.functions) {
        converter.function(f);
    }
    for (var st in own.structs) {
        if (_is_generic_base(st) or st.ty.is_function_type()) {
            continue;
        }
        converter.current = Optional<TypeName>.Value(st.ty);
        for (var c in st.constructors) {
            converter.function(c);
        }
        for (var m in st.method_members) {
            converter.function(m);
        }
    }
    converter.current = Optional<TypeName>.Empty;
    for (var g in module.globals) {
        if (module.checked.globals.contains(g.name)) {
            continue;
        }
        var fallback = g.type_loc.is_none() ? g.loc : g.type_loc;
        if (g.default.is_value()) {
            var value = converter.expression(g.default.value());
            g.default = Optional<Expression>.Value(converter.convert(value, g.ty, fallback));
        }
    }
    # Every trait type in use, for codegen: the declared ones and those the
    # conversions above introduced.
    for (var ty in used_trait_types(module, state.trait_types_memo())) {
        converter.trait_type(ty);
    }
    var trait_types = Array<TraitType>();
    for (var (_, t) in converter.trait_types) {
        trait_types.append(t);
    }
    trait_types.sort((a: TraitType, b: TraitType) => _compare_bytes(a.ty.to_string(), b.ty.to_string()) as int);
    module.trait_types = trait_types;
    module.conversions = converter.conversions;
}

## The structs whose constructor is `[Implicit]`, by name and by type: the
## unit's own, and a checked one found when a lookup names it.
struct _Implicits {
    var module: Module;
    var state: PassState;
    var own: HashMap<String, _Implicit> = HashMap<String, _Implicit>();
    var _checked: HashMap<String, _Implicit?> = HashMap<String, _Implicit?>();

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
    }

    ## Takes in `st`, one of the unit's own structs.
    add(st: StructDef) {
        var entry = _implicit_of(st);
        if (entry.is_value()) {
            own[st.name] = entry.value();
            own[st.ty.to_string()] = entry.value();
        }
    }

    ## Whether any struct has an `[Implicit]` constructor.
    any(module: Module): bool {
        if (own.count > 0) {
            return true;
        }
        for (var st in module.structs) {
            if (module.checked.structs.contains(st.name) and _implicit_of(st).is_value()) {
                return true;
            }
        }
        return false;
    }

    ## The struct of type `name` whose constructor is `[Implicit]`, if any.
    find(name: String): _Implicit? {
        var found = own.try_get(name);
        if (found.is_value() or (module.checked.structs.count == 0 and module.checked.functions.count == 0)) {
            return found;
        }
        var known = _checked.try_get(name);
        if (known.is_value()) {
            return known.value();
        }
        var st = checked_decls(module, state).structs.try_get(name);
        var entry = st.is_value() ? _implicit_of(st.value()) : Optional<_Implicit>.Empty;
        _checked[name] = entry;
        return entry;
    }
}

# The `[Implicit]` constructor of `st`, not a generic base, if it has one.
_implicit_of(st: StructDef): _Implicit? {
    if (_is_generic_base(st)) {
        return Optional<_Implicit>.Empty;
    }
    for (var c in st.constructors) {
        if (ast.has_attribute(c.attributes, IMPLICIT_ATTRIBUTE)) {
            if (c.parameters.count > 0) {
                return Optional<_Implicit>.Value(_Implicit(c.parameters[0].ty, c.name, c.loc));
            }
            break;
        }
    }
    return Optional<_Implicit>.Empty;
}

## A struct whose constructor is `[Implicit]`.
struct _Implicit {
    ## The constructor's parameter type.
    var from: TypeName;
    ## The constructor call's name (`Path`, `Box<int>`, `Path$2`).
    var callee: String;
    ## The constructor, for the language server.
    var constructor: Loc;

    construct(from: TypeName, callee: String, constructor: Loc) {
        this.from = from;
        this.callee = callee;
        this.constructor = constructor;
    }
}

## What the conversions need of a concrete struct.
struct _StructFacts {
    var methods: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    var traits: Array<TypeName>;
    var loc: Loc;

    construct(st: StructDef) {
        for (var m in st.method_members) {
            methods[m.name] = _types_of(m);
        }
        traits = st.traits;
        loc = st.loc;
    }
}

_types_of(f: FunctionDef): TypeName[] {
    var out = Array<TypeName>();
    for (var p in f.parameters) {
        out.append(p.ty);
    }
    return out;
}

## Two types the same once canonical.
_same_type(a: TypeName, b: TypeName): bool {
    return _canonical(a).to_string() == _canonical(b).to_string();
}

struct _TraitConversions {
    var state: PassState;
    var module: Module;
    var implicit: _Implicits;
    var conversions: Array<Conversion> = Array<Conversion>();
    var table: StructTable;
    var trait_defs: Array<TraitDef>;
    ## Each conformance of a value type (`extend int with Tr`): the type's
    ## key, the trait (canonical), and the extension.
    var value_conformances: Array<(String, String, Loc)> = Array<(String, String, Loc)>();
    ## Present when an extension adds constraints: says which condition of
    ## a conditional conformance a struct does not meet.
    var conformance: Conformance?;
    var trait_types: HashMap<String, TraitType> = HashMap<String, TraitType>();
    ## The unit's own free functions and constructors → parameter types; a
    ## checked one's are found as a lookup names it (`_params`).
    var functions: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    var constructors: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    ## C functions' parameter types, by name: only a `StringConstant`
    ## argument converts there (to its bytes).
    var externs: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    ## The unit's own structs, and the checked ones looked up so far (`_facts`).
    var structs: HashMap<String, _StructFacts?> = HashMap<String, _StructFacts?>();
    var current: TypeName? = Optional<TypeName>.Empty;
    var _checked: bool;

    construct(module: Module, state: PassState, implicit: _Implicits) {
        this.state = state;
        this.module = module;
        this.implicit = implicit;
        _checked = module.checked.structs.count > 0 or module.checked.functions.count > 0;
        table = StructTable(module, memo = state.trait_types_memo());
        trait_defs = module.traits;
        bool restated = false;
        for (var e in module.extensions) {
            if (e.restated.count > 0) {
                restated = true;
            }
            if (!is_value_type(state, e.target)) {
                continue;
            }
            var key = value_type_key(state, e.target.name);
            var spelled = key.is_value() ? key.value() : "";
            for (var t in e.traits) {
                value_conformances.append((spelled, _canonical(t).to_string(), e.loc));
            }
        }
        conformance = restated ? Optional<Conformance>.Value(Conformance(module, state)) : Optional<Conformance>.Empty;
        for (var e in module.externs) {
            externs[e.name] = _parameter_types(e.parameters);
        }
        var own = unit_decls(module);
        for (var f in own.functions) {
            if (!f.is_generic_func) {
                functions[f.name] = _types_of(f);
            }
        }
        for (var st in own.structs) {
            if (_is_generic_base(st)) {
                continue;
            }
            for (var c in st.constructors) {
                constructors[c.name] = _types_of(c);
            }
            structs[st.name] = Optional<_StructFacts>.Value(_StructFacts(st));
        }
    }

    ## The parameter types of the free function or constructor `name`: a
    ## constructor's first, the unit's own before a checked one's.
    _params(name: String): Array<TypeName>? {
        var found = constructors.try_get(name);
        if (found.is_value()) {
            return found;
        }
        if (_checked) {
            var c = checked_decls(module, state).constructors.try_get(name);
            if (c.is_value()) {
                return Optional<Array<TypeName>>.Value(_types_of(c.value()));
            }
        }
        found = functions.try_get(name);
        if (found.is_value() or !_checked) {
            return found;
        }
        var f = checked_decls(module, state).functions.try_get(name);
        return f.is_value() ? Optional<Array<TypeName>>.Value(_types_of(f.value())) : Optional<Array<TypeName>>.Empty;
    }

    ## What the conversions need of the struct of type `name`, if it is one
    ## and not a generic base.
    _facts(name: String): _StructFacts? {
        var found = structs.try_get(name);
        if (found.is_value()) {
            return found.value();
        }
        if (!_checked) {
            return Optional<_StructFacts>.Empty;
        }
        var st = checked_decls(module, state).structs.try_get(name);
        var facts = st.is_value() and !_is_generic_base(st.value()) ?
            Optional<_StructFacts>.Value(_StructFacts(st.value())) :
            Optional<_StructFacts>.Empty;
        structs[name] = facts;
        return facts;
    }

    is_trait(ty: TypeName): bool {
        return trait_def(trait_defs, ty).is_value();
    }

    trait_type(ty: TypeName): TraitType? {
        var def = trait_def(trait_defs, ty);
        if (!def.is_value()) {
            return Optional<TraitType>.Empty;
        }
        var key = ty.to_string();
        var known = trait_types.try_get(key);
        if (known.is_value()) {
            return known;
        }
        var made = instance(def.value(), ty);
        trait_types[key] = made;
        return Optional<TraitType>.Value(made);
    }

    ## `value` flows into a slot of type `expected`: returns what replaces
    ## it.
    convert(value: Expression, expected: TypeName, fallback: Loc): Expression {
        var unsigned = unsigned_literal(value);
        if (unsigned.is_value() and _narrower_than_ulong(expected)) {
            state.report(
                error_at($"integer literal is too large for type '{expected.display()}'", unsigned.value().loc)
            );
            return value;
        }
        if (_is_c_string_type(expected)) {
            return convert_constant(_unwrap_string_literal(value), "c_str");
        }
        var name = expected.to_string();
        if (name == STRING_CONSTANT) {
            _constant_string_literal(value);
            return value;
        }
        if (name == "String") {
            return convert_constant(value, "to_string");
        }
        if (expected.is_tuple()) {
            convert_tuple(value, expected, fallback);
            return value;
        }
        var element = _array_element(expected);
        if (element.is_value() and _is_array_literal(value)) {
            return convert_array_literal(value, expected, element.value(), fallback);
        }
        var map = _map_slot_types(expected);
        if (map.is_value() and _is_map_literal(value)) {
            var (key, map_value) = map.value();
            return convert_map_literal(value, expected, key, map_value, fallback);
        }
        # A `match` expression's value is its body's.
        if (value is WithSubject(subject)) {
            subject.body = convert(subject.body, expected, fallback);
            return value;
        }
        # A null weak trait value is its zero pair.
        if (_is_null(value)
            and expected.is_weak()
            and expected.sub_types.count > 0
            and is_trait(expected.sub_types[0])) {
            return Expression.Default(expected);
        }
        var to_trait = is_trait(expected);
        if (value is ToTrait(existing)) {
            return value;
        }
        if (!to_trait and !implicit.find(expected.to_string()).is_value()) {
            return value;
        }
        # Each arm converts on its own: they may be different structs.
        if (value is Ternary(node)) {
            node.true_expr = convert(node.true_expr, expected, fallback);
            node.false_expr = convert(node.false_expr, expected, fallback);
            return value;
        }
        var own = _expression_loc(value);
        var loc = own.is_none() ? fallback : own;
        if (!to_trait) {
            return convert_implicit(value, expected, loc);
        }
        TypeName from = TypeName.void_pointer();
        if (!_is_null(value)) {
            var found = static_type_of(value, table, current, state);
            if (!found.is_value()) {
                return value;
            }
            var actual = found.value();
            if (is_trait(actual)) {
                # A trait value of the same type needs nothing; converting
                # one trait to another needs supertraits, which do not exist.
                if (!_same_type(actual, expected)) {
                    state.report(
                        error_at(
                            $"cannot convert a value of trait type '{actual.display()}' to trait type '{expected.display()}'",
                            loc
                        )
                    );
                }
                return value;
            }
            var facts = _facts(actual.to_string());
            if (!facts.is_value()) {
                # A number, `bool` or enum may conform to the trait, for
                # constraints, but is never a trait value.
                if (is_value_type(state, actual)) {
                    report_value_type(actual, expected, loc);
                }
                # Anything else: the type checks report the mismatch.
                return value;
            }
            if (!_conforms_to(facts.value(), expected)) {
                var error = error_at($"'{actual.display()}' does not conform to trait '{expected.display()}'", loc);
                # A conditional conformance names the condition missed.
                var condition = conformance.is_value() ?
                    conformance.value().condition_note(actual, expected) :
                    Optional<(String, Loc)>.Empty;
                if (condition.is_value()) {
                    var (note, at) = condition.value();
                    error = error.with_note(note, Optional<Location>.Value(location_of(at)));
                } else if (!is_sealed(module, expected)) {
                    error = error.with_note(
                        $"declare it with 'extend {actual.display()} with {expected.display()}'",
                        Optional<Location>.Value(location_of(facts.value().loc))
                    );
                }
                state.report(error);
                return value;
            }
            from = actual;
        }
        trait_type(expected);
        return Expression.ToTrait(ToTraitExpression(value, from, expected, loc));
    }

    report_value_type(actual: TypeName, expected: TypeName, loc: Loc) {
        var key = value_type_key(state, actual.name);
        var wanted = _canonical(expected).to_string();
        Loc? declared = Optional<Loc>.Empty;
        if (key.is_value()) {
            for (var (k, t, at) in value_conformances) {
                if (k == key.value() and t == wanted) {
                    declared = Optional<Loc>.Value(at);
                    break;
                }
            }
        }
        var shown = actual.display();
        var error = error_at(
            $"'{shown}' cannot be converted to trait '{expected.display()}': only structs and enums whose cases carry values can be trait values",
            loc
        );
        if (declared.is_value()) {
            error = error.with_note(
                $"'{shown}' conforms to '{expected.display()}' here, which makes it meet the constraint, not a trait value",
                Optional<Location>.Value(location_of(declared.value()))
            );
        }
        state.report(error);
    }

    ## `value` flows into a slot of tuple type `expected`. A tuple literal
    ## of as many elements takes the slot's type, and each element then
    ## flows into its element's slot. Any other value is left to the type
    ## checks.
    convert_tuple(value: Expression, expected: TypeName, fallback: Loc) {
        match (value) {
            Ternary(node) => {
                convert_tuple(node.true_expr, expected, fallback);
                convert_tuple(node.false_expr, expected, fallback);
            }
            FunctionCall(node) => {
                if (node.function.starts_with("__tuple<") and node.args.count == expected.sub_types.count) {
                    node.function = expected.to_string();
                    var loc = node.loc.is_none() ? fallback : node.loc;
                    arguments(expected.sub_types, node.args, loc);
                }
            }
            else => {}
        }
    }

    ## An array literal flowing into a slot of type `expected`, an
    ## `Array<element>`: built from `Array<element>()` rather than from its
    ## first element, so its elements convert to `element`.
    convert_array_literal(value: Expression, expected: TypeName, element: TypeName, fallback: Loc): Expression {
        var (start, rest, at) = _literal_parts(value);
        var loc = at.is_none() ? fallback : at;
        var steps = Array<Array<Expression>>();
        if (start is FunctionCall(first)) {
            steps.append(first.args);
        }
        for (var step in rest) {
            steps.append(step);
        }
        for (var step in steps) {
            ulong i = 0;
            while (i < step.count) {
                step[i] = convert(step[i], element, loc);
                i += 1;
            }
        }
        var call = Expression.FunctionCall(FunctionCallExpression(expected.to_string(), Array<Expression>(), loc));
        return _build_literal(call, steps, "_literal_append", expected, loc);
    }

    ## A map literal flowing into a slot of type `expected`, a
    ## `HashMap<key, value>`: built from `HashMap<key, value>()`.
    convert_map_literal(
        value: Expression, expected: TypeName, key: TypeName, map_value: TypeName, fallback: Loc
    ): Expression {
        var (start, rest, at) = _literal_parts(value);
        var loc = at.is_none() ? fallback : at;
        var entries = Array<Array<Expression>>();
        if (start is FunctionCall(first)) {
            entries.append(first.args);
        }
        for (var entry in rest) {
            entries.append(entry);
        }
        for (var entry in entries) {
            entry[0] = convert(entry[0], key, loc);
            entry[1] = convert(entry[1], map_value, loc);
        }
        var call = Expression.FunctionCall(FunctionCallExpression(expected.to_string(), Array<Expression>(), loc));
        return _build_literal(call, entries, "_literal_insert", expected, loc);
    }

    ## A `StringConstant` flowing into a `String` slot is a copy of its text
    ## (`method` is `to_string`); into a C string slot, its own constant
    ## bytes (`c_str`). Each arm of a ternary converts on its own.
    convert_constant(value: Expression, method: String): Expression {
        if (value is Ternary(node)) {
            node.true_expr = convert_constant(node.true_expr, method);
            node.false_expr = convert_constant(node.false_expr, method);
            return value;
        }
        var ty = static_type_of(value, table, current, state);
        if (!ty.is_value() or ty.value().to_string() != STRING_CONSTANT) {
            return value;
        }
        return Expression.MethodCall(MethodCallExpression(value, method, Array<Expression>(), _expression_loc(value)));
    }

    ## `value` flows into a slot of struct type `expected`, which has an
    ## `[Implicit]` constructor: calls it when the value is not already an
    ## `expected` and fits the constructor's parameter.
    convert_implicit(value: Expression, expected: TypeName, loc: Loc): Expression {
        # `__null` is a null reference of any struct type.
        if (_is_null(value)) {
            return value;
        }
        var found = implicit.find(expected.to_string());
        if (!found.is_value()) {
            return value;
        }
        var entry = found.value();
        var actual = static_type_of(value, table, current, state);
        if (!actual.is_value()) {
            return value;
        }
        # Already the struct. Type arguments are not compared: one
        # specialization may be spelled two ways.
        if (_canonical(actual.value()).name == _canonical(expected).name) {
            return value;
        }
        if (!fits(value, actual.value(), entry.from)) {
            return value;
        }
        # A specialized body converts once per specialization; the source
        # location is one place.
        var at = _expression_loc(value);
        if (!at.is_none()) {
            bool known = false;
            for (var c in conversions) {
                if (c.at.same(at)
                    and c.from.to_string() == actual.value().to_string()
                    and c.to.to_string() == expected.to_string()
                    and c.constructor.same(entry.constructor)) {
                    known = true;
                    break;
                }
            }
            if (!known) {
                conversions.append(Conversion(at, actual.value(), expected, entry.constructor));
            }
        }
        # A struct reaching a trait parameter still needs its `ToTrait`.
        var argument = convert(value, entry.from, loc);
        return Expression.FunctionCall(FunctionCallExpression(entry.callee, [argument], loc));
    }

    ## Whether `value`, of type `actual`, reaches `to` exactly or by
    ## promotion: the conversions an implicit constructor's argument may
    ## take.
    fits(value: Expression, actual: TypeName, to: TypeName): bool {
        # An array literal becomes whatever `Array` it flows into.
        if (_is_array_literal(value) and _array_element(to).is_value()) {
            return true;
        }
        var from_name = _canonical(actual).to_string();
        var to_name = _canonical(to).to_string();
        if (from_name == to_name) {
            return true;
        }
        if (is_trait(to)) {
            var facts = _facts(actual.to_string());
            return facts.is_value() and _conforms_to(facts.value(), to);
        }
        if (value is IntLiteral(v)) {
            return _literal_fits(v, to_name);
        }
        return _promotes(from_name, to_name);
    }

    ## A trait method implemented with a struct return type where the trait
    ## returns a trait type: that struct must conform to the declared trait
    ## type.
    check_covariant_returns(structs: StructDef[]) {
        for (var st in structs) {
            if (_is_generic_base(st)) {
                continue;
            }
            for (var declared in st.traits) {
                var def = trait_def(trait_defs, declared);
                if (!def.is_value()) {
                    continue;
                }
                var made = instance(def.value(), declared);
                for (var required in made.methods) {
                    if (!is_trait(required.ty)) {
                        continue;
                    }
                    FunctionDef? have = Optional<FunctionDef>.Empty;
                    for (var m in st.method_members) {
                        if (m.name == required.name) {
                            have = Optional<FunctionDef>.Value(m);
                            break;
                        }
                    }
                    if (!have.is_value() or is_trait(have.value().ty)) {
                        continue;
                    }
                    var method = have.value();
                    var facts = _facts(method.ty.to_string());
                    if (!(facts.is_value() and _conforms_to(facts.value(), required.ty))) {
                        state.report(
                            error_at(
                                $"'{method.name}' in '{st.ty.display()}' returns '{method.ty.display()}', which does not conform to '{required.ty.display()}' as trait '{declared.display()}' requires",
                                method.loc
                            ).with_note(
                                $"'{required.name}' declared here", Optional<Location>.Value(location_of(required.loc))
                            )
                        );
                    }
                }
            }
        }
    }

    arguments(params: TypeName[], args: Expression[], call: Loc) {
        ulong i = 0;
        while (i < params.count and i < args.count) {
            args[i] = convert(args[i], params[i], call);
            i += 1;
        }
    }

    ## Parameter types of a call through a trait value, reporting a member
    ## the value cannot call.
    trait_method_params(receiver: TypeName, method: String, loc: Loc): TypeName[]? {
        # The synthesized refcount members dispatch like any other.
        if (method == "__acquire" or method == "__release") {
            return Optional<TypeName[]>.Value(Array<TypeName>());
        }
        var def = trait_def(trait_defs, receiver);
        if (!def.is_value()) {
            return Optional<TypeName[]>.Empty;
        }
        var made = trait_type(receiver);
        if (!made.is_value()) {
            return Optional<TypeName[]>.Empty;
        }
        for (var m in made.value().methods) {
            if (m.name == method) {
                return Optional<TypeName[]>.Value(_types_of(m));
            }
        }
        FunctionDef? declared = Optional<FunctionDef>.Empty;
        for (var m in def.value().methods) {
            if (m.name == method) {
                declared = Optional<FunctionDef>.Value(m);
                break;
            }
        }
        String message = $"no member named '{method}' in '{receiver.display()}'";
        if (declared.is_value()) {
            message = declared.value().is_static ?
                $"'{method}' is static and cannot be called on a value of trait type '{receiver.display()}'" :
                $"'{method}' uses 'this' as a type and cannot be called on a value of trait type '{receiver.display()}'";
        }
        var diagnostic = error_at(message, loc);
        if (declared.is_value()) {
            diagnostic = diagnostic.with_note(
                $"'{method}' declared here", Optional<Location>.Value(location_of(declared.value().loc))
            );
        }
        state.report(diagnostic);
        return Optional<TypeName[]>.Empty;
    }

    rewrite(e: Expression): Expression {
        return expression(e);
    }

    ## Children first, so a nested call's arguments are converted before the
    ## enclosing node reads their types.
    expression(e: Expression): Expression {
        var expr = _converts_children(e) ? rewrite_children(e, this) : e;
        match (expr) {
            # `s as Trait` is the conversion a trait-typed slot makes.
            Cast(node) => {
                if (node.kind == CastKind.Static and is_trait(node.ty)) {
                    node.expr = convert(node.expr, node.ty, Loc.none());
                    if (node.expr is ToTrait(converted)) {
                        return node.expr;
                    }
                }
            }
            FunctionCall(node) => {
                # `String(text)` of a `StringConstant` copies its text.
                if (node.function == "String" and node.args.count == 1) {
                    var ty = static_type_of(node.args[0], table, current, state);
                    if (ty.is_value() and ty.value().to_string() == STRING_CONSTANT) {
                        return Expression.MethodCall(
                            MethodCallExpression(node.args[0], "to_string", Array<Expression>(), node.loc)
                        );
                    }
                }
                var c_params = externs.try_get(node.function);
                if (c_params.is_value()) {
                    var params = c_params.value();
                    ulong i = 0;
                    while (i < node.args.count and i < params.count) {
                        if (_is_c_string_type(params[i])) {
                            node.args[i] = convert_constant(node.args[i], "c_str");
                        }
                        i += 1;
                    }
                    return expr;
                }
                # Constructors are listed with the functions, by name.
                var params = _params(node.function);
                if (params.is_value()) {
                    arguments(params.value(), node.args, node.loc);
                }
            }
            MethodCall(node) => {
                var receiver = static_type_of(node.this_value, table, current, state);
                if (!receiver.is_value()) {
                    return expr;
                }
                TypeName[]? params = Optional<TypeName[]>.Empty;
                if (is_trait(receiver.value())) {
                    params = trait_method_params(receiver.value(), node.method, node.loc);
                } else {
                    var facts = _facts(receiver.value().to_string());
                    if (facts.is_value()) {
                        params = facts.value().methods.try_get(node.method);
                    }
                }
                if (params.is_value()) {
                    arguments(params.value(), node.args, node.loc);
                }
            }
            Invoke(node) => {
                var callee = static_type_of(node.callee, table, current, state);
                if (callee.is_value() and callee.value().is_callable()) {
                    arguments(callee.value().function_params(), node.args, _expression_loc(node.callee));
                }
            }
            Binary(node) => {
                if (node.op == BinaryOp.Assign) {
                    var lhs_type = static_type_of(node.lhs, table, current, state);
                    if (lhs_type.is_value()) {
                        node.rhs = convert(node.rhs, lhs_type.value(), node.loc);
                    }
                }
            }
            else => {}
        }
        return expr;
    }

    block(body: Block, returns: TypeName) {
        ulong i = 0;
        while (i < body.items.count) {
            match (body.items[i]) {
                Expression(e) => {
                    body.items[i] = Statement.Expression(expression(e));
                }
                Block(inner) => {
                    block(inner, returns);
                }
                Declaration(declaration) => {
                    if (declaration is Variable(variable)) {
                        var fallback = variable.type_loc.is_none() ? variable.loc : variable.type_loc;
                        if (variable.default.is_value()) {
                            var value = expression(variable.default.value());
                            variable.default = Optional<Expression>.Value(convert(value, variable.ty, fallback));
                        }
                    }
                }
                Branch(branch) => {
                    branch.condition = expression(branch.condition);
                    block(branch.if_block, returns);
                    if (branch.else_block.is_value()) {
                        block(branch.else_block.value(), returns);
                    }
                }
                While(loop) => {
                    loop.condition = expression(loop.condition);
                    block(loop.block, returns);
                }
                Return(ret) => {
                    if (ret.expr.is_value()) {
                        var value = expression(ret.expr.value());
                        ret.expr = Optional<Expression>.Value(convert(value, returns, ret.loc));
                    }
                }
                else => {}
            }
            i += 1;
        }
    }

    function(f: FunctionDef) {
        if (f.is_generic_func) {
            return;
        }
        # A default flows into its parameter at each call that omits it.
        for (var p in f.parameters) {
            if (p.default.is_value()) {
                var fallback = p.type_loc.is_none() ? p.loc : p.type_loc;
                p.default = Optional<Expression>.Value(convert(expression(p.default.value()), p.ty, fallback));
            }
        }
        if (f.body.is_value()) {
            block(f.body.value(), f.ty);
        }
    }
}

extend _TraitConversions with Rewriter;

## Whether `facts`' struct declares conformance to trait `to`.
_conforms_to(facts: _StructFacts, to: TypeName): bool {
    var wanted = _canonical(to).to_string();
    for (var t in facts.traits) {
        if (_canonical(t).to_string() == wanted) {
            return true;
        }
    }
    return false;
}

## The expressions whose children the conversions walk into: not a
## closure's construction, a weak reference, a pointer call, a trait
## value's unwrapping, a move, a named argument, a case value, a static
## member or a destructure.
_converts_children(e: Expression): bool {
    match (e) {
        Weak(op, ty, value) => {
            return false;
        }
        CallPointer(node) => {
            return false;
        }
        MakeClosure(node) => {
            return false;
        }
        FromTrait(node) => {
            return false;
        }
        Move(node) => {
            return false;
        }
        NamedArgument(node) => {
            return false;
        }
        CaseValue(value) => {
            return false;
        }
        StaticMember(node) => {
            return false;
        }
        Destructure(node) => {
            return false;
        }
        else => {
            return true;
        }
    }
}

# An integer type that cannot hold every `ulong`.
_narrower_than_ulong(ty: TypeName): bool {
    var name = ty.to_string();
    return bit_width(name).is_value() and !is_float_type(name) and name != "u64" and name != "ulong";
}

## A pointer to characters, bytes, or `void`: a slot a string literal fills
## with its NUL-terminated bytes rather than a `String`.
_is_c_string_type(ty: TypeName): bool {
    var pointee = pointee_name(ty.to_string());
    if (!pointee.is_value()) {
        return false;
    }
    match (pointee.value()) {
        "char", "i8", "byte", "u8", "void" => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## A string literal flowing into a character pointer is its raw global:
## the `String(raw, size, length)` call `convert_string_literals` made is
## unwrapped. Each arm of a ternary unwraps on its own.
_unwrap_string_literal(value: Expression): Expression {
    match (value) {
        Ternary(node) => {
            node.true_expr = _unwrap_string_literal(node.true_expr);
            node.false_expr = _unwrap_string_literal(node.false_expr);
        }
        FunctionCall(node) => {
            if (_is_converted_literal(node)) {
                return node.args[0];
            }
        }
        else => {}
    }
    return value;
}

## A string literal flowing into a `StringConstant` slot is that value: the
## `String(raw, size, length)` call becomes `StringConstant(raw, size,
## length)`. Each arm of a ternary converts on its own.
_constant_string_literal(value: Expression) {
    match (value) {
        Ternary(node) => {
            _constant_string_literal(node.true_expr);
            _constant_string_literal(node.false_expr);
        }
        FunctionCall(node) => {
            if (_is_converted_literal(node)) {
                node.function = STRING_CONSTANT;
            }
        }
        else => {}
    }
}

## The element type of an `Array<T>` slot.
_array_element(ty: TypeName): TypeName? {
    var parsed = parse_type_string(ty.to_string());
    if (parsed.name == "Array" and parsed.sub_types.count == 1) {
        return Optional<TypeName>.Value(parsed.sub_types[0]);
    }
    return Optional<TypeName>.Empty;
}

## The key and value types of a `HashMap<K, V>` slot.
_map_slot_types(ty: TypeName): (TypeName, TypeName)? {
    return _map_types(parse_type_string(ty.to_string()));
}

## Whether `value` is an array literal as the builder lowers it.
_is_array_literal(value: Expression): bool {
    return _literal_is(value, "_array_literal", "_literal_append", 1);
}

## Whether `value` is a map literal as the builder lowers it.
_is_map_literal(value: Expression): bool {
    return _literal_is(value, "_map_literal", "_literal_insert", 2);
}

## Whether `value` is a collection literal made from a call of `start` (or
## of a specialization `start<...>`) with `arity` arguments and steps
## `step`.
_literal_is(value: Expression, start: String, step: String, arity: ulong): bool {
    Expression first = value;
    Expression? body = Optional<Expression>.Empty;
    if (value is WithSubject(subject)) {
        first = subject.subject;
        body = Optional<Expression>.Value(subject.body);
    } else {
        first = _chain_start(value, step);
    }
    bool started = false;
    if (first is FunctionCall(call)) {
        started = call.args.count == arity
            and (call.function == start
                or (call.function.starts_with(start)
                    and call.function.substr_bytes(start.size, call.function.size - start.size).starts_with("<")));
    }
    if (!started) {
        return false;
    }
    if (!body.is_value()) {
        return true;
    }
    if (body.value() is MethodCall(node)) {
        return node.method == _LITERAL_THEN or node.method == step;
    }
    return false;
}

## The receiver a chain of `step` calls starts from.
_chain_start(value: Expression, step: String): Expression {
    var at = value;
    while (true) {
        if (at is MethodCall(node)) {
            if (node.method != step) {
                return at;
            }
            at = node.this_value;
        } else {
            return at;
        }
    }
    return at;
}

## A chain's start and the arguments of each of its calls, in order.
_chain_steps(value: Expression): (Expression, Array<Array<Expression>>) {
    var steps = Array<Array<Expression>>();
    var at = value;
    while (true) {
        if (at is MethodCall(node)) {
            steps.append(node.args);
            at = node.this_value;
        } else {
            break;
        }
    }
    steps.reverse();
    return (at, steps);
}

## The start call of a literal `_literal_is` accepts, its steps' arguments
## in order, and its location.
_literal_parts(value: Expression): (Expression, Array<Array<Expression>>, Loc) {
    if (value is WithSubject(subject)) {
        var steps = Array<Array<Expression>>();
        # Leaves left to right; a stack keeps this flat.
        var pending = [subject.body];
        while (pending.count > 0) {
            var node = pending.pop();
            bool joined = false;
            if (node is MethodCall(call)) {
                if (call.method == _LITERAL_THEN) {
                    pending.append(call.args[call.args.count - 1]);
                    pending.append(call.this_value);
                    joined = true;
                }
            }
            if (!joined) {
                var (_, leaf) = _chain_steps(node);
                for (var step in leaf) {
                    steps.append(step);
                }
            }
        }
        return (subject.subject, steps, subject.loc);
    }
    var (start, steps) = _chain_steps(value);
    return (start, steps, _expression_loc(start));
}
