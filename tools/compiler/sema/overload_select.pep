## Overload resolution: `pepper_sema::passes::overloads::Overloads` in
## Pepper. Picks the member of an overload set (free functions, methods,
## constructors) a call's arguments select. Each argument ranks against its
## parameter (0 exact, 1 promotion, 2 conversion, 3 an `[Implicit]`
## constructor; among integer widenings the narrower target ranks better),
## and the winner is no worse than every other viable member in every
## argument and better in at least one; a non-generic member beats a
## generic one, and the more specialized of two generic ones wins.

import [demangle_name] from compiler.link;
import [int_literal_type, is_numeric_type] from "arithmetic";
import [has_bare_attribute, IMPLICIT_ATTRIBUTE, STRING_CONSTANT] from "builder";
import [
    for_each_selected_site, ModuleTables, rewrite_module, SiteFilter, SiteSelection, SiteVisitor
] from "closure_sites";
import [Conformance, has_constraints] from "constraints";
import [Loc] from "loc";
import [Expression, ExtensionScopes, FunctionDef, FunctionRefExpression, Module, StructDef, TypeName] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [instance, trait_def, trait_types_of] from "traits";
import [GenericSignature, record_conformances, specialization] from "type_arguments";
import [AUTO, parse_type_string, replace_map] from "type_name";
import [Rewriter] from "walk";

## One member of an overload set, as resolution needs it.
export struct Member {
    ## Its name (`scale$2`).
    var name: String;
    ## Where it is declared.
    var loc: Loc;
    ## Its parameter types.
    var params: TypeName[];
    ## How many parameters (from the front) have no default.
    var required: ulong;
    ## Its return type.
    var ret: TypeName;
    ## Present for a generic member.
    var generic: GenericSignature?;
    ## Its parameter types with generic parameters named by position.
    var key: String;

    construct(function: FunctionDef, state: PassState) {
        name = function.name;
        loc = function.loc;
        params = Array<TypeName>();
        required = 0;
        for (var p in function.parameters) {
            params.append(p.ty);
            if (!p.default.is_value()) {
                required += 1;
            }
        }
        ret = function.ty;
        generic = function.is_generic_func ?
            Optional<GenericSignature>.Value(GenericSignature(function, state)) :
            Optional<GenericSignature>.Empty;
        key = _parameter_key(function);
    }

    ## The member's type as a value: `(params) => return`.
    signature(): TypeName {
        var args = Array<TypeName>();
        args.append(ret.to_string() == AUTO ? TypeName.void() : ret);
        args.append_all(params);
        return TypeName.with_args("__function", args);
    }
}

## What an argument tells resolution beyond its type.
export enum ArgKind {
    Plain,
    IntLiteral(value: long),
    ## A string literal, made a `String` construction of its raw global.
    StringLiteral,
    ## `__null`.
    Null,
    ## A closure literal with parameter types still unknown: its arity.
    UntypedClosure(arity: ulong),
    ## A parameter skipped by naming a later one: it takes its default.
    Default,
    ## Another overload set named as a value: its members' function types.
    Overloaded(types: TypeName[]),
}

## One argument of a call being resolved.
export struct ArgInfo {
    ## Its type, when known.
    var ty: TypeName?;
    ## What else is known about it.
    var kind: ArgKind;

    construct(ty: TypeName?, kind: ArgKind) {
        this.ty = ty;
        this.kind = kind;
    }

    ## Whether nothing is known about the argument yet.
    unknown(): bool {
        return !ty.is_value() and kind is Plain;
    }
}

## Returns whether `e` is a string literal after `convert_string_literals`.
##
## @param e the expression
## @returns true for a converted literal
export is_string_literal(e: Expression): bool {
    if (e is FunctionCall(call)) {
        if (call.function == "String" and call.args.count > 0) {
            if (call.args[0] is StringLiteral(literal)) {
                return literal.is_raw and literal.loc.same(call.loc);
            }
        }
    }
    return false;
}

## A resolved call.
export struct Choice {
    ## The name the call now spells: the member, or its specialization.
    var callee: String;
    ## Its return type.
    var ret: TypeName;
    ## Arguments that are string literals passed to a `__ptr<char>`
    ## parameter: they pass their raw global.
    var raw_literals: Array<ulong>;

    construct(callee: String, ret: TypeName, raw_literals: Array<ulong> = Array<ulong>()) {
        this.callee = callee;
        this.ret = ret;
        this.raw_literals = raw_literals;
    }
}

## Why a call could not be resolved.
export struct Failure {
    ## The error.
    var message: String;
    ## Its notes and where they point.
    var notes: Array<(String, Loc)>;

    construct(message: String, notes: Array<(String, Loc)>) {
        this.message = message;
        this.notes = notes;
    }
}

## How resolving a call came out.
export enum Outcome {
    Chosen(choice: Choice),
    ## Some argument's type is not known yet.
    Pending,
    Failed(failure: Failure),
}

## An argument's rank against a parameter: its class, then for an integer
## widening the target's width in bits.
struct _Rank {
    var class: int;
    var width: int;

    construct(class: int, width: int) {
        this.class = class;
        this.width = width;
    }

    ## Lexicographic order: negative, zero or positive.
    compare(other: _Rank): int {
        if (class != other.class) {
            return class < other.class ? -1 : 1;
        }
        if (width != other.width) {
            return width < other.width ? -1 : 1;
        }
        return 0;
    }
}

## A viable member with its argument ranks.
struct _Viable {
    var member: ulong;
    var ranks: Array<_Rank>;
    var generic: bool;
    var params: TypeName[];
    var callee: String;
    var ret: TypeName;

    construct(member: ulong, ranks: Array<_Rank>, generic: bool, params: TypeName[], callee: String, ret: TypeName) {
        this.member = member;
        this.ranks = ranks;
        this.generic = generic;
        this.params = params;
        this.callee = callee;
        this.ret = ret;
    }
}

_ordinal_text(n: ulong): String {
    var suffix = "th";
    var last = n % 10;
    var tens = n % 100;
    if (last == 1 and tens != 11) {
        suffix = "st";
    } else if (last == 2 and tens != 12) {
        suffix = "nd";
    } else if (last == 3 and tens != 13) {
        suffix = "rd";
    }
    return $"{n}{suffix}";
}

## The range of integer type `ty` (canonical spelling), as its bit count
## and signedness.
_integer_kind(ty: String): (int, bool)? {
    match (ty) {
        "i8" => {
            return Optional<(int, bool)>.Value((8, true));
        }
        "i16" => {
            return Optional<(int, bool)>.Value((16, true));
        }
        "i32" => {
            return Optional<(int, bool)>.Value((32, true));
        }
        "i64" => {
            return Optional<(int, bool)>.Value((64, true));
        }
        "u8" => {
            return Optional<(int, bool)>.Value((8, false));
        }
        "u16" => {
            return Optional<(int, bool)>.Value((16, false));
        }
        "u32" => {
            return Optional<(int, bool)>.Value((32, false));
        }
        "u64" => {
            return Optional<(int, bool)>.Value((64, false));
        }
        else => {
            return Optional<(int, bool)>.Empty;
        }
    }
}

## Whether integer literal `value` lies in the range of integer type `ty`.
_literal_fits(value: long, ty: String): bool {
    var kind = _integer_kind(ty);
    if (!kind.is_value()) {
        return false;
    }
    var (bits, signed) = kind.value();
    if (signed) {
        if (bits == 64) {
            return true;
        }
        long limit = (1 as long) << (bits - 1);
        return value >= -limit and value <= limit - 1;
    }
    if (value < 0) {
        return false;
    }
    if (bits == 64) {
        return true;
    }
    return value <= ((1 as long) << bits) - 1;
}

## The width in bits of integer type `ty`'s range.
_integer_bits(ty: String): int? {
    var kind = _integer_kind(ty);
    if (!kind.is_value()) {
        return Optional<int>.Empty;
    }
    var (bits, _) = kind.value();
    return Optional<int>.Value(bits);
}

## Whether every value of numeric type `from` is a value of `to`.
_promotes(from: String, to: String): bool {
    if (from == "f32" and to == "f64") {
        return true;
    }
    var a = _integer_kind(from);
    var b = _integer_kind(to);
    if (!a.is_value() or !b.is_value()) {
        return false;
    }
    var (from_bits, from_signed) = a.value();
    var (to_bits, to_signed) = b.value();
    if (from_signed == to_signed) {
        return from_bits <= to_bits;
    }
    # Unsigned into signed needs a wider target; signed never fits unsigned.
    return !from_signed and to_signed and from_bits < to_bits;
}

## The overload sets of a module and the conversions ranking needs.
export struct Overloads {
    var sets: HashMap<String, Array<Member>> = HashMap<String, Array<Member>>();
    ## The sets that are a struct's constructors (`Point`, `Box<int>`).
    var constructors: HashSet<String> = HashSet<String>();
    ## Method overload sets: struct type, then set name, to members.
    var methods: HashMap<String, HashMap<String, Array<Member>>> = HashMap<String, HashMap<String, Array<Member>>>();
    ## Every set name in `methods`.
    var method_set_names: HashSet<String> = HashSet<String>();
    ## Struct type to the parameter type of its `[Implicit]` constructor.
    var implicit: HashMap<String, TypeName> = HashMap<String, TypeName>();
    ## Struct name to the traits it declares.
    var conforms: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();
    var traits: HashSet<String> = HashSet<String>();
    ## Each extension method, by location: whether its extension is
    ## exported, and whether it is `private`.
    var extension_methods: HashMap<Loc, (bool, bool)> = HashMap<Loc, (bool, bool)>();
    var scopes: ExtensionScopes = ExtensionScopes();
    ## Private members of sets that also have exported members.
    var hidden: HashSet<Loc> = HashSet<Loc>();
    ## The `private` members of every set.
    var file_private: HashSet<Loc> = HashSet<Loc>();
    ## No argument type is still to come: arity alone may pick the only
    ## non-generic member.
    var settle_by_arity: bool = false;
    ## What deciding generic constraints needs, when any is written.
    var conformance: Conformance? = Optional<Conformance>.Empty;
    var state: PassState;

    ## Returns the overload sets of `module`, as `Overloads::build` does.
    ##
    ## @param module the model
    ## @param state the passes' state
    ## @param trait_types the module's trait types, when already found
    construct(module: Module, state: PassState, trait_types: TypeName[]? = Optional<TypeName[]>.Empty) {
        this.state = state;
        record_conformances(module, state);
        if (has_overloads(module)) {
            _build(module, trait_types);
        }
    }

    _build(module: Module, known_trait_types: TypeName[]?) {
        if (has_constraints(module)) {
            conformance = Optional<Conformance>.Value(Conformance(module, state));
        }
        for (var st in module.structs) {
            var methods_of = Array<FunctionDef>();
            methods_of.append_all(st.method_members);
            methods_of.append_all(st.generic_methods);
            for (var method in methods_of) {
                var set = set_name(method.name);
                if (set != method.name) {
                    _add_method(_canonical(st.ty).to_string(), set, Member(method, state));
                }
            }
        }
        # A value of trait type calls the trait's members: every instance
        # the module uses, and each trait's base.
        var trait_types = trait_types_of(module, known_trait_types, state.trait_types_memo());
        for (var t in module.traits) {
            trait_types.append(TypeName.named(t.name));
        }
        for (var ty in trait_types) {
            var def = trait_def(module.traits, ty);
            if (!def.is_value()) {
                continue;
            }
            var key = _canonical(ty).to_string();
            if (methods.contains(key)) {
                continue;
            }
            for (var method in instance(def.value(), ty).methods) {
                var set = set_name(method.name);
                if (set != method.name) {
                    _add_method(key, set, Member(method, state));
                }
            }
        }
        var functions = HashMap<String, FunctionDef>();
        for (var f in module.functions) {
            functions[f.name] = f;
        }
        for (var (set, names) in module.overload_sets) {
            var members = Array<Member>();
            for (var m in names) {
                var f = functions.try_get(m);
                if (f.is_value()) {
                    members.append(Member(f.value(), state));
                }
            }
            sets[set] = members;
        }
        # A set that mixes visibilities shows other files only its exported
        # members.
        for (var (_, members) in sets.iterate()) {
            bool any_public = false;
            for (var m in members) {
                if (!module.private_functions.contains(m.loc)) {
                    any_public = true;
                }
            }
            if (any_public) {
                for (var m in members) {
                    if (module.private_functions.contains(m.loc)) {
                        hidden.insert(m.loc);
                    }
                }
            }
        }
        for (var st in module.structs) {
            if (st.ty.is_generic() and st.name == st.ty.name) {
                continue;
            }
            if (st.constructors.count > 1) {
                var set = st.ty.to_string();
                var members = Array<Member>();
                for (var c in st.constructors) {
                    members.append(Member(c, state));
                }
                sets[set] = members;
                constructors.insert(set);
            }
            for (var c in st.constructors) {
                if (has_bare_attribute(c.attributes, IMPLICIT_ATTRIBUTE)) {
                    if (c.parameters.count > 0) {
                        implicit[_canonical(st.ty).to_string()] = c.parameters[0].ty;
                    }
                    break;
                }
            }
        }
        for (var st in module.structs) {
            _conform(st.ty.to_string(), st.traits);
        }
        for (var ext in module.extensions) {
            _conform(ext.target.to_string(), ext.traits);
            for (var m in ext.methods) {
                extension_methods[m.loc] = (ext.is_exported, ext.is_private);
            }
        }
        for (var t in module.traits) {
            traits.insert(t.name);
        }
        scopes = module.extension_scopes;
        file_private = module.file_private_functions;
        settle_by_arity = state.settle_overloads_by_arity;
    }

    ## Why `type_args` do not meet `signature`'s constraints, as a note
    ## (`'T' does not conform to 'Hashable'`); empty when they do.
    _unmet(signature: GenericSignature, type_args: TypeName[]): String? {
        if (!conformance.is_value()) {
            return Optional<String>.Empty;
        }
        return conformance.value().unmet(signature.params, type_args);
    }

    _add_method(key: String, set: String, member: Member) {
        if (!methods.contains(key)) {
            methods[key] = HashMap<String, Array<Member>>();
        }
        var sets_of = methods[key];
        if (!sets_of.contains(set)) {
            sets_of[set] = Array<Member>();
            method_set_names.insert(set);
        }
        sets_of[set].append(member);
    }

    _conform(key: String, more: TypeName[]) {
        if (!conforms.contains(key)) {
            conforms[key] = Array<TypeName>();
        }
        conforms[key].append_all(more);
    }

    ## Returns whether `name` names an overload set.
    is_set(name: String): bool {
        return sets.contains(name);
    }

    ## Returns whether there is nothing to resolve.
    is_empty(): bool {
        return sets.count == 0 and methods.count == 0;
    }

    ## Returns the set a call to `function` names and the type arguments
    ## it spells: `f<int>` is set `f` with `[int]`, but `Box<int>` is the
    ## constructor set of `Box<int>`.
    call_set(function: String): (String, TypeName[]?) {
        if (constructors.contains(function)) {
            return (function, Optional<TypeName[]>.Empty);
        }
        return split_type_arguments(function);
    }

    ## Returns the set a call to `function` names, without parsing its type
    ## arguments.
    call_set_name(function: String): String {
        if (constructors.contains(function) or set_name(function) != function) {
            return function;
        }
        var at = function.find("<");
        return at < 0 ? function : function.substr_bytes(0, at as ulong);
    }

    ## The members of `set` code at `at` can see.
    _set(set: String, at: Loc): Array<Member>? {
        var all = sets.try_get(set);
        if (!all.is_value()) {
            return Optional<Array<Member>>.Empty;
        }
        var members = all.value();
        if (at.is_none()) {
            return Optional<Array<Member>>.Value(members);
        }
        var own = HashSet<String>();
        for (var m in members) {
            if (m.loc.file == at.file) {
                own.insert(m.key);
            }
        }
        var visible = Array<Member>();
        for (var m in members) {
            if (m.loc.file == at.file) {
                visible.append(m);
            } else if ((!hidden.contains(m.loc) or _same_module(m.loc.file, at.file))
                and !file_private.contains(m.loc)
                and !own.contains(m.key)) {
                visible.append(m);
            }
        }
        return Optional<Array<Member>>.Value(visible);
    }

    _same_module(a: uint, b: uint): bool {
        if (a == b) {
            return true;
        }
        if (a >= scopes.module.count or b >= scopes.module.count) {
            return false;
        }
        var ma = scopes.module[a];
        var mb = scopes.module[b];
        return ma.is_value() and mb.is_value() and ma.value() == mb.value();
    }

    _sees(from: uint, file: uint, exported: bool, is_private: bool): bool {
        if (from >= scopes.visible.count) {
            return true;
        }
        if (is_private) {
            return from == file;
        }
        return _same_module(from, file)
            or (exported and (scopes.prelude.contains(file) or scopes.visible[from].contains(file)));
    }

    ## Returns the function types of the non-generic members of `set`
    ## visible at `at`.
    member_types(set: String, at: Loc): TypeName[] {
        var out = Array<TypeName>();
        var members = _set(set, at);
        if (members.is_value()) {
            for (var m in members.value()) {
                if (!m.generic.is_value()) {
                    out.append(m.signature());
                }
            }
        }
        return out;
    }

    ## Returns the member of `set` visible at `at` whose function type is
    ## exactly `expected`, with that type.
    member_for(set: String, expected: TypeName, at: Loc): (String, TypeName)? {
        var members = _set(set, at);
        if (!members.is_value()) {
            return Optional<(String, TypeName)>.Empty;
        }
        var want = _canonical(expected);
        var found = Array<Member>();
        for (var m in members.value()) {
            if (!m.generic.is_value() and _canonical(m.signature()) == want) {
                found.append(m);
            }
        }
        if (found.count != 1) {
            return Optional<(String, TypeName)>.Empty;
        }
        return Optional<(String, TypeName)>.Value((found[0].name, found[0].signature()));
    }

    ## Returns `candidate function` notes, one per member of `set` visible
    ## at `at`.
    candidate_notes(set: String, at: Loc): Array<(String, Loc)> {
        var what = constructors.contains(set) ? "candidate constructor" : "candidate function";
        var out = Array<(String, Loc)>();
        var members = _set(set, at);
        if (members.is_value()) {
            for (var m in members.value()) {
                out.append((what, m.loc));
            }
        }
        return out;
    }

    ## How well `arg` converts to a parameter of type `param`.
    _rank(arg: ArgInfo, param: TypeName, implicit_allowed: bool): _Rank? {
        var class = _rank_class(arg, param, implicit_allowed);
        if (!class.is_value()) {
            return Optional<_Rank>.Empty;
        }
        # Among integer widenings, the narrowest target is closest.
        int width = 0;
        if (class.value() == 1 and arg.kind is Plain and arg.ty.is_value()) {
            var a = _integer_bits(_canonical(arg.ty.value()).to_string());
            var p = _integer_bits(_canonical(param).to_string());
            if (a.is_value() and p.is_value()) {
                width = p.value();
            }
        }
        return Optional<_Rank>.Value(_Rank(class.value(), width));
    }

    ## The class of `arg`'s conversion to `param`: 0 exact, 1 promotion, 2
    ## conversion, 3 `[Implicit]` constructor.
    _rank_class(arg: ArgInfo, param: TypeName, implicit_allowed: bool): int? {
        var p = _canonical(param);
        var p_name = p.to_string();
        match (arg.kind) {
            Overloaded(types) => {
                if (p.is_function_type()) {
                    for (var t in types) {
                        if (_canonical(t) == p) {
                            return Optional<int>.Value(0);
                        }
                    }
                }
                return Optional<int>.Empty;
            }
            UntypedClosure(arity) => {
                return p.is_function_type() and p.function_params().count == arity ?
                    Optional<int>.Value(0) :
                    Optional<int>.Empty;
            }
            Null => {
                # `__null` is exact for a raw pointer.
                if (p_name.ends_with("*")) {
                    return Optional<int>.Value(0);
                }
                return Optional<int>.Value(is_numeric_type(state, p_name) ? 2 : 1);
            }
            StringLiteral => {
                if (p_name == "i8*" or p_name == STRING_CONSTANT) {
                    return Optional<int>.Value(0);
                }
            }
            else => {}
        }
        if (!arg.ty.is_value()) {
            return Optional<int>.Empty;
        }
        var a = _canonical(arg.ty.value());
        var a_name = a.to_string();
        if (a == p) {
            # A string literal is typed `String` by promotion.
            return Optional<int>.Value(arg.kind is StringLiteral ? 1 : 0);
        }
        if (arg.kind is IntLiteral(value)) {
            if (_literal_fits(value, p_name)) {
                return Optional<int>.Value(1);
            }
        }
        if (is_numeric_type(state, a_name) and is_numeric_type(state, p_name)) {
            return Optional<int>.Value(_promotes(a_name, p_name) ? 1 : 2);
        }
        if (traits.contains(p.name)) {
            var declared = conforms.try_get(a_name);
            if (declared.is_value()) {
                for (var t in declared.value()) {
                    if (_canonical(t) == p) {
                        return Optional<int>.Value(1);
                    }
                }
            }
            return Optional<int>.Empty;
        }
        # A plain function value passes where a `shared` one of the same
        # signature is expected, and the reverse.
        if (a.is_function_type() and p.is_function_type()) {
            return _same_types(a.sub_types, p.sub_types) ? Optional<int>.Value(1) : Optional<int>.Empty;
        }
        # Pointers convert among themselves and to and from numbers, and any
        # struct reference passes as `void*`.
        bool a_scalar = a_name.ends_with("*") or is_numeric_type(state, a_name);
        bool p_scalar = p_name.ends_with("*") or is_numeric_type(state, p_name);
        if ((a_scalar and p_scalar) or p_name == "void*") {
            return Optional<int>.Value(2);
        }
        # A `StringConstant` converts to a `String` and to a C string.
        if (a_name == STRING_CONSTANT) {
            if (p_name == "i8*") {
                return Optional<int>.Value(2);
            }
            if (p_name == "String" and implicit_allowed) {
                return Optional<int>.Value(3);
            }
            return Optional<int>.Empty;
        }
        if (implicit_allowed) {
            var from = implicit.try_get(p_name);
            if (from.is_value()) {
                var inner = _rank_class(arg, from.value(), false);
                if (inner.is_value() and inner.value() <= 1) {
                    return Optional<int>.Value(3);
                }
            }
        }
        return Optional<int>.Empty;
    }

    ## Resolves a call from `at` to `set` with `args`; `explicit` holds
    ## type arguments the call spells (`f<int>(x)`).
    ##
    ## @returns the outcome
    select(set: String, explicit: TypeName[]?, args: ArgInfo[], at: Loc): Outcome {
        var members = _set(set, at);
        if (!members.is_value()) {
            return Outcome.Pending;
        }
        var outcome = _select_in(members.value(), demangle_name(set), explicit, args);
        if (outcome is Failed(failure)) {
            if (constructors.contains(set)) {
                return Outcome.Failed(_constructor_failure(failure, set));
            }
        }
        return outcome;
    }

    ## Resolves a call from `at` of method set `set` of `receiver`'s
    ## struct.
    ##
    ## @returns the outcome
    select_method(receiver: TypeName, set: String, args: ArgInfo[], at: Loc): Outcome {
        # `set` may spell type arguments (`f<int>`), which only the set's
        # generic members take.
        var (name, explicit) = _method_set_and_type_arguments(set);
        var members = _method_set(receiver, name, at);
        if (!members.is_value()) {
            return Outcome.Pending;
        }
        return _select_in(members.value(), name, explicit, args);
    }

    ## The members of method set `set` of `receiver`'s struct code at `at`
    ## can see.
    _method_set(receiver: TypeName, set: String, at: Loc): Array<Member>? {
        var sets_of = methods.try_get(_canonical(receiver).to_string());
        if (!sets_of.is_value()) {
            return Optional<Array<Member>>.Empty;
        }
        var members = sets_of.value().try_get(set);
        if (!members.is_value()) {
            return Optional<Array<Member>>.Empty;
        }
        var visible = Array<Member>();
        for (var m in members.value()) {
            var ext = extension_methods.try_get(m.loc);
            if (ext.is_value()) {
                var (exported, is_private) = ext.value();
                if (!_sees(at.file, m.loc.file, exported, is_private)) {
                    continue;
                }
            }
            visible.append(m);
        }
        return Optional<Array<Member>>.Value(visible);
    }

    ## Returns whether some struct has a method overload set named `set`.
    is_any_method_set(set: String): bool {
        return method_set_names.contains(_method_set_name(set));
    }

    ## Returns whether `set` names a method overload set of `receiver`'s
    ## struct.
    is_method_set(receiver: TypeName, set: String): bool {
        var name = _method_set_name(set);
        if (!method_set_names.contains(name)) {
            return false;
        }
        var sets_of = methods.try_get(_canonical(receiver).to_string());
        return sets_of.is_value() and sets_of.value().contains(name);
    }

    ## Returns the member of method set `set` of `receiver`'s struct,
    ## visible at `at`, whose function type is exactly `expected`.
    method_member_for(receiver: TypeName, set: String, expected: TypeName, at: Loc): String? {
        var members = _method_set(receiver, set, at);
        if (!members.is_value()) {
            return Optional<String>.Empty;
        }
        var want = _canonical(expected);
        var found = Array<String>();
        for (var m in members.value()) {
            if (_canonical(m.signature()) == want) {
                found.append(m.name);
            }
        }
        return found.count == 1 ? Optional<String>.Value(found[0]) : Optional<String>.Empty;
    }

    ## Returns `candidate function` notes, one per member of method set
    ## `set` visible at `at`.
    method_candidate_notes(receiver: TypeName, set: String, at: Loc): Array<(String, Loc)> {
        var out = Array<(String, Loc)>();
        var members = _method_set(receiver, set, at);
        if (members.is_value()) {
            for (var m in members.value()) {
                out.append(("candidate function", m.loc));
            }
        }
        return out;
    }

    _select_in(members: Array<Member>, name: String, explicit: TypeName[]?, args: ArgInfo[]): Outcome {
        var outcome = _select_ranked(members, name, explicit, args);
        if (!settle_by_arity or explicit.is_value()) {
            return outcome;
        }
        # No type is still to come: a call still waiting, or settling on a
        # generic member only now, takes its only non-generic member of
        # that arity.
        bool settle = false;
        match (outcome) {
            Pending => {
                settle = true;
            }
            Chosen(choice) => {
                settle = true;
                for (var m in members) {
                    if (m.name == choice.callee and !m.generic.is_value()) {
                        settle = false;
                    }
                }
            }
            else => {}
        }
        if (!settle) {
            return outcome;
        }
        var fitting = Array<Member>();
        for (var m in members) {
            if (!m.generic.is_value() and args.count >= m.required and args.count <= m.params.count) {
                fitting.append(m);
            }
        }
        if (fitting.count == 1) {
            return Outcome.Chosen(Choice(fitting[0].name, fitting[0].ret));
        }
        return outcome;
    }

    _select_ranked(members: Array<Member>, name: String, explicit: TypeName[]?, args: ArgInfo[]): Outcome {
        var count = args.count;
        bool pending = false;
        for (var a in args) {
            if (a.unknown()) {
                pending = true;
            }
        }
        if (pending) {
            # Arity alone may decide, when one member fits and it is not
            # generic.
            var fitting = Array<Member>();
            for (var m in members) {
                if (count >= m.required
                    and count <= m.params.count
                    and (!explicit.is_value() or m.generic.is_value())) {
                    fitting.append(m);
                }
            }
            if (fitting.count == 1 and !fitting[0].generic.is_value()) {
                return Outcome.Chosen(Choice(fitting[0].name, fitting[0].ret));
            }
            return Outcome.Pending;
        }
        var notes = Array<(String, Loc)>();
        var viable = Array<_Viable>();
        ulong index = 0;
        while (index < members.count) {
            var member = members[index];
            index += 1;
            if (count < member.required or count > member.params.count) {
                var low = member.required;
                var high = member.params.count;
                var requires = "";
                if (low == high) {
                    requires = $"requires {high} {_plural(high)}";
                } else if (count < low) {
                    requires = $"requires at least {low} {_plural(low)}";
                } else {
                    requires = $"requires at most {high} {_plural(high)}";
                }
                notes.append(
                    (
                        $"candidate function not viable: {requires}, but {count} {count == 1 ? "was" : "were"} provided",
                        member.loc
                    )
                );
                continue;
            }
            var params = member.params;
            var callee = member.name;
            var ret = member.ret;
            if (!member.generic.is_value()) {
                # Written type arguments pick among the generic members.
                if (explicit.is_value()) {
                    continue;
                }
            } else {
                var signature = member.generic.value();
                var type_args = Array<TypeName>();
                if (explicit.is_value()) {
                    var written = explicit.value();
                    if (written.count > signature.params.count) {
                        continue;
                    }
                    bool filled = true;
                    ulong i = 0;
                    while (i < signature.params.count) {
                        if (i < written.count) {
                            type_args.append(written[i]);
                        } else if (signature.params[i].default.is_value()) {
                            type_args.append(signature.params[i].default.value());
                        } else {
                            filled = false;
                        }
                        i += 1;
                    }
                    if (!filled) {
                        continue;
                    }
                } else {
                    var types = Array<TypeName?>();
                    for (var a in args) {
                        if (a.kind is Overloaded(_)) {
                            types.append(Optional<TypeName>.Empty);
                        } else {
                            types.append(a.ty);
                        }
                    }
                    var inferred = signature.infer(types);
                    if (!inferred.is_value()) {
                        var bound = signature.bind(types);
                        var missing = "";
                        for (var p in signature.params) {
                            if (!bound.contains(p.name) and !p.default.is_value()) {
                                missing = p.name;
                                break;
                            }
                        }
                        notes.append(
                            ($"candidate function not viable: cannot infer type argument '{missing}'", member.loc)
                        );
                        continue;
                    }
                    type_args = inferred.value();
                }
                var unmet = _unmet(signature, type_args);
                if (unmet.is_value()) {
                    notes.append(($"candidate function not viable: {unmet.value()}", member.loc));
                    continue;
                }
                var map = Array<(String, TypeName)>();
                ulong k = 0;
                while (k < signature.params.count and k < type_args.count) {
                    map.append((signature.params[k].name, type_args[k]));
                    k += 1;
                }
                var substituted = Array<TypeName>();
                for (var p in member.params) {
                    var ty = p.copy();
                    replace_map(ty, map);
                    substituted.append(ty);
                }
                params = substituted;
                ret = member.ret.copy();
                replace_map(ret, map);
                callee = specialization(member.name, type_args);
            }
            var ranks = Array<_Rank>();
            bool failed = false;
            ulong i = 0;
            while (i < args.count and i < params.count) {
                var arg = args[i];
                var param = params[i];
                if (arg.kind is Default) {
                    if (i < member.required) {
                        failed = true;
                    } else {
                        ranks.append(_Rank(0, 0));
                        i += 1;
                        continue;
                    }
                } else {
                    var rank = _rank(arg, param, true);
                    if (rank.is_value()) {
                        ranks.append(rank.value());
                        i += 1;
                        continue;
                    }
                    failed = true;
                }
                if (failed) {
                    var from = "";
                    match (arg.kind) {
                        Overloaded(_) => {
                            from = "overloaded function";
                        }
                        UntypedClosure(n) => {
                            from = $"a closure of {n} parameter{n == 1 ? "" : "s"}";
                        }
                        Null => {
                            from = "__null";
                        }
                        Default => {
                            from = "a default argument";
                        }
                        else => {
                            from = arg.ty.is_value() ? $"'{arg.ty.value().display()}'" : "";
                        }
                    }
                    notes.append(
                        (
                            $"candidate function not viable: no known conversion from {from} to '{param.display()}' for {_ordinal_text(i + 1)} argument",
                            member.loc
                        )
                    );
                    break;
                }
            }
            if (failed) {
                continue;
            }
            viable.append(_Viable(index - 1, ranks, member.generic.is_value(), params, callee, ret));
        }
        if (viable.count == 0) {
            return Outcome.Failed(Failure($"no matching function for call to '{name}'", notes));
        }
        ulong w = 0;
        while (w < viable.count) {
            bool beats_all = true;
            ulong j = 0;
            while (j < viable.count) {
                if (j != w and !_better(members, viable[w], viable[j])) {
                    beats_all = false;
                    break;
                }
                j += 1;
            }
            if (beats_all) {
                var chosen = viable[w];
                var raw = Array<ulong>();
                ulong a = 0;
                while (a < args.count and a < chosen.params.count) {
                    if (args[a].kind is StringLiteral and _canonical(chosen.params[a]).to_string() == "i8*") {
                        raw.append(a);
                    }
                    a += 1;
                }
                return Outcome.Chosen(Choice(chosen.callee, chosen.ret, raw));
            }
            w += 1;
        }
        # The members no other viable member beats tie.
        var tied = Array<(String, Loc)>();
        ulong t = 0;
        while (t < viable.count) {
            bool beaten = false;
            ulong j = 0;
            while (j < viable.count) {
                if (j != t and _better(members, viable[j], viable[t])) {
                    beaten = true;
                }
                j += 1;
            }
            if (!beaten) {
                tied.append(("candidate function", members[viable[t].member].loc));
            }
            t += 1;
        }
        return Outcome.Failed(Failure($"call to '{name}' is ambiguous", tied));
    }
}

_plural(n: ulong): String {
    return n == 1 ? "argument" : "arguments";
}

_same_types(a: TypeName[], b: TypeName[]): bool {
    if (a.count != b.count) {
        return false;
    }
    ulong i = 0;
    while (i < a.count) {
        if (!(a[i] == b[i])) {
            return false;
        }
        i += 1;
    }
    return true;
}

## Whether viable `a` beats viable `b`.
_better(members: Array<Member>, a: _Viable, b: _Viable): bool {
    bool no_worse = true;
    bool strictly = false;
    ulong i = 0;
    while (i < a.ranks.count and i < b.ranks.count) {
        var c = a.ranks[i].compare(b.ranks[i]);
        if (c > 0) {
            no_worse = false;
        }
        if (c < 0) {
            strictly = true;
        }
        i += 1;
    }
    bool more_specialized = a.generic
        and b.generic
        and _at_least_as_specialized(members[a.member], members[b.member])
        and !_at_least_as_specialized(members[b.member], members[a.member]);
    return no_worse and (strictly or (!a.generic and b.generic) or more_specialized);
}

## Whether generic member `a` is at least as specialized as generic member
## `b`, as C++ orders function templates.
_at_least_as_specialized(a: Member, b: Member): bool {
    if (!a.generic.is_value() or !b.generic.is_value()) {
        return false;
    }
    var a_signature = a.generic.value();
    var b_signature = b.generic.value();
    var count = a.params.count < b.params.count ? a.params.count : b.params.count;
    var opaque = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < a_signature.params.count) {
        opaque.append((a_signature.params[i].name, TypeName.named($"$opaque{i}")));
        i += 1;
    }
    var a_params = Array<TypeName>();
    var arguments = Array<TypeName?>();
    i = 0;
    while (i < count) {
        var ty = a.params[i].copy();
        replace_map(ty, opaque);
        a_params.append(ty);
        arguments.append(Optional<TypeName>.Value(ty));
        i += 1;
    }
    var type_args = b_signature.infer(arguments);
    if (!type_args.is_value()) {
        return false;
    }
    var map = Array<(String, TypeName)>();
    i = 0;
    while (i < b_signature.params.count and i < type_args.value().count) {
        map.append((b_signature.params[i].name, type_args.value()[i]));
        i += 1;
    }
    i = 0;
    while (i < count) {
        var ty = b.params[i].copy();
        replace_map(ty, map);
        if (ty.to_string() != a_params[i].to_string()) {
            return false;
        }
        i += 1;
    }
    return true;
}

## A failed constructor call worded as clang words it.
_constructor_failure(failure: Failure, set: String): Failure {
    var ty = demangle_name(set);
    var message = failure.message.starts_with("no matching function") ?
        $"no matching constructor for initialization of '{ty}'" :
        $"call to constructor of '{ty}' is ambiguous";
    var notes = Array<(String, Loc)>();
    for (var (note, at) in failure.notes) {
        var text = note;
        var found = text.find("candidate function");
        if (found >= 0) {
            text = text.substr_bytes(0, found as ulong)
                + "candidate constructor"
                + text.substr_bytes(found as ulong + 18, text.size - found as ulong - 18);
        }
        notes.append((text, at));
    }
    return Failure(message, notes);
}

## Returns whether the module has anything to resolve: an overloaded free
## function, method or constructor.
##
## @param module the model
## @returns true when it does
export has_overloads(module: Module): bool {
    if (module.overload_sets.count > 0 or module.method_overload_sets.count > 0) {
        return true;
    }
    for (var st in module.structs) {
        if (st.constructors.count > 1) {
            return true;
        }
    }
    return false;
}

## Returns `name<args>` split into `name` and the written type arguments.
## A resolved member (`Box<int>$2`) is returned whole.
##
## @param function the callee as spelled
## @returns the name, and the type arguments if written
# The method set a call names, without the type arguments it may spell
# (`f<int>` is `f`). An operator method (`<`, `<<`) is its own name.
_method_set_name(method: String): String {
    var (name, _) = _method_set_and_type_arguments(method);
    return name;
}

# `split_type_arguments` for a method call's name, which may be an operator.
_method_set_and_type_arguments(method: String): (String, TypeName[]?) {
    if (method.is_empty) {
        return (method, Optional<TypeName[]>.Empty);
    }
    var first = method.byte_at(0);
    var word = (first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z') or first == '_';
    if (!word) {
        return (method, Optional<TypeName[]>.Empty);
    }
    return split_type_arguments(method);
}

export split_type_arguments(function: String): (String, TypeName[]?) {
    if (set_name(function) != function) {
        return (function, Optional<TypeName[]>.Empty);
    }
    var at = function.find("<");
    if (at < 0) {
        return (function, Optional<TypeName[]>.Empty);
    }
    return (function.substr_bytes(0, at as ulong), Optional<TypeName[]>.Value(parse_type_string(function).sub_types));
}

## Returns what resolution needs to know about `arg`, whose type is `ty` if
## known.
##
## @param arg the argument
## @param overloads the module's overload sets
## @param ty its type, if known
## @returns the argument's info
export arg_info(arg: Expression, overloads: Overloads, ty: TypeName?): ArgInfo {
    var kind = ArgKind.Plain;
    match (arg) {
        IntLiteral(value) => {
            return ArgInfo(
                Optional<TypeName>.Value(TypeName.named(int_literal_type(value))), ArgKind.IntLiteral(value)
            );
        }
        PointerLiteral => {
            return ArgInfo(Optional<TypeName>.Empty, ArgKind.Null);
        }
        DefaultArgument(_) => {
            return ArgInfo(Optional<TypeName>.Empty, ArgKind.Default);
        }
        MakeClosure(node) => {
            if (node.ty.contains_auto()) {
                return ArgInfo(Optional<TypeName>.Empty, ArgKind.UntypedClosure(node.ty.function_params().count));
            }
        }
        SymbolRef(node) => {
            if (node.ty.contains_auto() and overloads.is_set(node.id)) {
                return ArgInfo(Optional<TypeName>.Empty, ArgKind.Overloaded(overloads.member_types(node.id, node.loc)));
            }
        }
        else => {}
    }
    if (is_string_literal(arg)) {
        return ArgInfo(Optional<TypeName>.Value(TypeName.named("String")), ArgKind.StringLiteral);
    }
    if (ty.is_value()
        and (ty.value().name.size > 0 or ty.value().sub_types.count > 0)
        and !ty.value().contains_auto()) {
        return ArgInfo(ty, kind);
    }
    return ArgInfo(Optional<TypeName>.Empty, kind);
}

## Rewrites a call resolved to `choice`: its callee, and each string
## literal passed to a raw pointer parameter as that literal's global.
##
## @param args the call's arguments, changed in place
## @param choice the resolution
## @returns the callee to spell
export apply_choice(args: Expression[], choice: Choice): String {
    for (var i in choice.raw_literals) {
        if (args[i] is FunctionCall(inner)) {
            args[i] = inner.args[0];
        }
    }
    return choice.callee;
}

## Returns how `Module.call_targets` names method `member` of `receiver`'s
## struct: `Point.move$2`.
##
## @param receiver the receiver's type
## @param member the member
## @returns the target
export method_target(receiver: TypeName, member: String): String {
    return $"{receiver.to_string()}.{member}";
}

## The key of a name at a place, for the maps `bind_function_values` fills.
_named_at(name: String, loc: Loc): String {
    return $"{name}\n{loc.file}:{loc.span.start}:{loc.span.end}";
}

## Whether some expression could be an overloaded name used as a value.
struct _CandidateFinder {
    var overloads: Overloads;

    construct(overloads: Overloads) {
        this.overloads = overloads;
    }

    wants(e: Expression): bool {
        match (e) {
            SymbolRef(node) => {
                return node.ty.contains_auto() and overloads.is_set(node.id);
            }
            MemberRef(node) => {
                return overloads.is_any_method_set(node.name);
            }
            else => {}
        }
        return false;
    }
}

extend _CandidateFinder with SiteFilter;

## Finds the member each overloaded name used as a value stands for.
struct _ValueBinder {
    var overloads: Overloads;
    var table: StructTable;
    var state: PassState;
    var bound: HashMap<String, (String, TypeName)> = HashMap<String, (String, TypeName)>();
    var methods: HashMap<String, (TypeName, String)> = HashMap<String, (TypeName, String)>();

    construct(overloads: Overloads, table: StructTable, state: PassState) {
        this.overloads = overloads;
        this.table = table;
        this.state = state;
    }

    visit(owner: String?, e: Expression, expected: TypeName?, current: TypeName?) {
        if (!expected.is_value() or !expected.value().is_function_type() or expected.value().contains_auto()) {
            return;
        }
        match (e) {
            SymbolRef(node) => {
                if (node.ty.contains_auto() and overloads.is_set(node.id)) {
                    var member = overloads.member_for(node.id, expected.value(), node.loc);
                    if (member.is_value()) {
                        bound[_named_at(node.id, node.loc)] = member.value();
                    }
                }
            }
            MemberRef(node) => {
                var receiver = static_type_of(node.lhs, table, current, state);
                if (!receiver.is_value()) {
                    return;
                }
                var member = overloads.method_member_for(receiver.value(), node.name, expected.value(), node.loc);
                if (member.is_value()) {
                    methods[_named_at(node.name, node.loc)] = (receiver.value(), member.value());
                }
            }
            else => {}
        }
    }
}

extend _ValueBinder with SiteVisitor;

## Rewrites the names `_ValueBinder` bound.
struct _ValueRewriter {
    var binder: _ValueBinder;
    var targets: Array<(Loc, String)> = Array<(Loc, String)>();

    construct(binder: _ValueBinder) {
        this.binder = binder;
    }

    rewrite(e: Expression): Expression {
        if (e is MemberRef(node)) {
            var found = binder.methods.try_get(_named_at(node.name, node.loc));
            if (found.is_value()) {
                var (receiver, member) = found.value();
                targets.append((node.loc, method_target(receiver, member)));
                node.name = member;
            }
        }
        if (e is SymbolRef(node)) {
            var found = binder.bound.try_get(_named_at(node.id, node.loc));
            if (found.is_value()) {
                var (member, ty) = found.value();
                targets.append((node.loc, member));
                return Expression.FunctionRef(FunctionRefExpression(member, ty, node.loc));
            }
        }
        return e;
    }
}

extend _ValueRewriter with Rewriter;

## What `bind_function_values` looks for: the overloaded names, and the
## expressions that may use one as a value.
export struct FunctionValueSearch {
    var overloads: Overloads;
    var filter: SiteFilter;

    construct(overloads: Overloads) {
        this.overloads = overloads;
        this.filter = _CandidateFinder(overloads);
    }
}

## What `bind_function_values` looks for in `module`, if it has overloads.
##
## @param module the model
## @param state the passes' state
## @param tables the module's tables, built from it as it is now
## @returns the search, or none when nothing is overloaded
export function_value_search(module: Module, state: PassState, tables: ModuleTables): FunctionValueSearch? {
    if (!has_overloads(module)) {
        return Optional<FunctionValueSearch>.Empty;
    }
    return Optional<FunctionValueSearch>.Value(FunctionValueSearch(Overloads(module, state, tables.trait_types)));
}

## Binds each overloaded name used as a value to the member whose function
## type is the type of the slot it flows into (`var f: (int) => int =
## scale;`), as `overloads::bind_function_values` does.
##
## @param module the model, changed in place
## @param state the passes' state
## @param tables the module's tables, built from it as it is now
## @param search what to look for, found in the module as it is now
## @param sites the code holding a candidate (`search.filter`); most runs
##     find nothing to bind, so only that code is walked
## @returns whether it bound any
export bind_function_values(
    module: Module, state: PassState, tables: ModuleTables, search: FunctionValueSearch, sites: SiteSelection
): bool {
    if (!sites.any()) {
        return false;
    }
    var overloads = search.overloads;
    var binder = _ValueBinder(overloads, tables.statics(), state);
    for_each_selected_site(tables, sites, binder);
    if (binder.bound.count == 0 and binder.methods.count == 0) {
        return false;
    }
    var rewriter = _ValueRewriter(binder);
    rewrite_module(module, rewriter);
    module.call_targets.append_all(rewriter.targets);
    return true;
}
