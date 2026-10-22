## Constrained generic code.
## Inside `total_area<T: Shape>`, a value of type `T` offers exactly what
## `Shape` offers, checked in the generic itself: the instance methods and
## operators its constraints' traits declare, their static members through
## the parameter (`T.make()`), flowing into a slot of one of those trait
## types, and being stored, passed, returned and compared. Anything else on
## it is an error at the member or operator. An unconstrained parameter is
## checked in each specialization instead.

import compiler.ast;
import [Diagnostic, Location] from compiler.diagnostic;
import [copy_without_body] from "checked";
import [expression_children] from "closure_sites";
import "closures";
import "common";
import [is_shared_bound] from "constraints";
import [Loc] from "loc";
import [
    BinaryOp, Block, Expression, FunctionDef, GenericParam, Module, Statement, TraitDef, TypeName, UnaryOp
] from "model";
import [set_name] from "names";
import [op_name] from "operators";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [StructInfo] from "struct_info";
import [parse_type_string, replace_map] from "type_name";

## A constrained parameter in scope: its constraints and their members.
struct _Constrained {
    ## Each constraint's trait type and where it is written.
    var bounds: Array<(TypeName, Loc)> = Array<(TypeName, Loc)>();
    ## Each member the constraints declare: which constraint (by index),
    ## and its signature with the trait's parameters and `this` replaced.
    var members: Array<(ulong, FunctionDef)> = Array<(ulong, FunctionDef)>();

    construct(param: GenericParam, traits: TraitDef[]) {
        ulong index = 0;
        while (index < param.bounds.count) {
            var bound = param.bounds[index];
            bounds.append((bound.ty, bound.loc));
            index += 1;
            # The built-in `Shared` offers no members.
            if (is_shared_bound(bound.ty)) {
                continue;
            }
            var def = Optional<TraitDef>.Empty;
            for (var t in traits) {
                if (t.name == bound.ty.name) {
                    def = Optional<TraitDef>.Value(t);
                    break;
                }
            }
            if (!def.is_value()) {
                continue;
            }
            var map = Array<(String, TypeName)>();
            ulong i = 0;
            while (i < def.value().generic_params.count) {
                var p = def.value().generic_params[i];
                if (i < bound.ty.sub_types.count) {
                    map.append((p.name, bound.ty.sub_types[i]));
                } else if (p.default.is_value()) {
                    map.append((p.name, p.default.value()));
                }
                i += 1;
            }
            map.append(("this", TypeName.named(param.name)));
            for (var method in def.value().methods) {
                # A generic member's own parameters (`put<U>`) shadow the
                # trait's.
                var own = Array<(String, TypeName)>();
                for (var (n, t) in map) {
                    bool shadowed = false;
                    for (var gp in method.generic_params) {
                        if (gp.name == n) {
                            shadowed = true;
                            break;
                        }
                    }
                    if (!shadowed) {
                        own.append((n, t));
                    }
                }
                var m = copy_without_body(method);
                m.ty = _substitute_all(m.ty, own);
                for (var p in m.parameters) {
                    p.ty = _substitute_all(p.ty, own);
                }
                members.append((index - 1, m));
            }
        }
    }

    ## The members named `name` (an overload set's members too; a generic
    ## method by its name without type arguments).
    named(name: String): Array<(ulong, FunctionDef)> {
        var base = _without_type_arguments(name);
        var out = Array<(ulong, FunctionDef)>();
        for (var (b, m) in members) {
            if (set_name(m.name) == base) {
                out.append((b, m));
            }
        }
        return out;
    }

    ## The note for a member `what` no constraint declares.
    missing(param: String, what: String): (String, Optional<Loc>) {
        var names = Array<String>();
        for (var (b, _) in bounds) {
            names.append($"'{b.display()}'");
        }
        var message = names.count == 1 ?
            $"'{param}' is constrained by {names[0]}, which has no {what}" :
            $"'{param}' is constrained by {" & ".join(names)}, none of which has {what}";
        if (bounds.count == 0) {
            return (message, Optional<Loc>.Empty);
        }
        var (_, at) = bounds[0];
        return (message, Optional<Loc>.Value(at));
    }
}

## `ty` with every name in `map` replaced by its type at once, so a
## replacement is never replaced again.
_substitute_all(ty: TypeName, map: Array<(String, TypeName)>): TypeName {
    for (var (name, replacement) in map) {
        if (ty.sub_types.count == 0 and name == ty.name) {
            return replacement.copy();
        }
    }
    var out = ty.copy();
    ulong i = 0;
    while (i < out.sub_types.count) {
        out.sub_types[i] = _substitute_all(out.sub_types[i], map);
        i += 1;
    }
    return out;
}

## `member`'s signature at a call spelled `method` (`put<int>`): its
## parameter types and result, with its own type parameters replaced by
## the written type arguments, or unknown where they are not written.
_member_signature(member: FunctionDef, method: String): (Array<TypeName?>, TypeName?) {
    var written = parse_type_string(method).sub_types;
    var map = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < member.generic_params.count and i < written.count) {
        map.append((member.generic_params[i].name, written[i]));
        i += 1;
    }
    var params = Array<TypeName?>();
    for (var p in member.parameters) {
        params.append(_resolve_signature_type(member, p.ty, map));
    }
    return (params, _resolve_signature_type(member, member.ty, map));
}

_resolve_signature_type(member: FunctionDef, ty: TypeName, map: Array<(String, TypeName)>): TypeName? {
    var out = _substitute_all(ty, map);
    if (out.is_auto()) {
        return Optional<TypeName>.Empty;
    }
    for (var p in member.generic_params) {
        if (out.mentions(p.name)) {
            return Optional<TypeName>.Empty;
        }
    }
    return Optional<TypeName>.Value(out);
}

## A method's name without the type arguments a generic method call spells
## (`map` for `map<long>`); an operator (`<`, `<=`) is its own name.
_without_type_arguments(name: String): String {
    var at = name.find("<");
    return at > 0 ? name.substr_bytes(0, at as ulong) : name;
}

_has_bounds(params: GenericParam[]): bool {
    for (var p in params) {
        if (p.bounds.count > 0) {
            return true;
        }
    }
    return false;
}

## Checks every generic base with a constrained parameter. Runs before anything is specialized.
##
## @param module the model
## @param state the passes' state, which takes the first error
export check_bounds(module: Module, state: PassState) {
    bool any = false;
    for (var f in module.functions) {
        any = any or _has_bounds(f.generic_params);
    }
    for (var e in module.extensions) {
        any = any or e.restated.count > 0;
    }
    for (var st in module.structs) {
        any = any or _has_bounds(st.generic_params);
        for (var m in st.generic_methods) {
            any = any or _has_bounds(m.generic_params);
        }
    }
    for (var t in module.traits) {
        any = any or _has_bounds(t.generic_params);
        for (var m in t.methods) {
            any = any or _has_bounds(m.generic_params);
        }
    }
    if (!any) {
        return;
    }
    var checker = _BoundsChecker(module, state);
    var none = Array<GenericParam>();
    var no_struct = Optional<TypeName>.Empty;
    for (var f in module.functions) {
        if (f.is_generic_func and _has_bounds(f.generic_params)) {
            checker.function(f, none, no_struct, HashMap<String, TypeName>());
        }
    }
    for (var st in module.structs) {
        if (st.name.contains("<")) {
            continue;
        }
        var current = Optional<TypeName>.Value(st.ty);
        # Inside a constrained extension (`extend Box<T: Named>`), a
        # parameter offers the struct's constraints and the extension's.
        var extended = Array<(HashSet<Loc>, GenericParam[])>();
        for (var (ext, added) in _constrained_extensions(module, st.name)) {
            var params = Array<GenericParam>();
            for (var p in st.generic_params) {
                params.append(p.copy());
            }
            for (var (i, bound) in added) {
                if (i < params.count) {
                    params[i].bounds.append(bound.copy());
                }
            }
            var locs = HashSet<Loc>();
            for (var m in ext.methods) {
                locs.insert(m.loc);
            }
            extended.append((locs, params));
        }
        var methods = Array<FunctionDef>();
        methods.append_all(st.method_members);
        methods.append_all(st.constructors);
        methods.append(st.destructor);
        for (var method in methods) {
            if (method.trait_default.is_value()) {
                continue;
            }
            var own = _params_of(method, st.generic_params, extended);
            if (_has_bounds(own)) {
                checker.function(method, own, current, HashMap<String, TypeName>());
            }
        }
        for (var method in st.generic_methods) {
            if (method.trait_default.is_value()) {
                continue;
            }
            var own = _params_of(method, st.generic_params, extended);
            if (_has_bounds(own) or _has_bounds(method.generic_params)) {
                checker.function(method, own, current, HashMap<String, TypeName>());
            }
        }
    }
    for (var t in module.traits) {
        for (var method in t.methods) {
            if (!method.body.is_value()) {
                continue;
            }
            if (_has_bounds(t.generic_params) or _has_bounds(method.generic_params)) {
                var own = HashMap<String, TypeName>();
                for (var m in t.methods) {
                    own[set_name(m.name)] = m.ty;
                }
                checker.function(method, t.generic_params, no_struct, own);
            }
        }
    }
}

_params_of(
    method: FunctionDef, params: GenericParam[], extended: Array<(HashSet<Loc>, GenericParam[])>
): GenericParam[] {
    for (var (locs, own) in extended) {
        if (locs.contains(method.loc)) {
            return own;
        }
    }
    return params;
}

## The state of one function's walk.
struct _BoundsWalk {
    var params: HashMap<String, _Constrained> = HashMap<String, _Constrained>();
    ## Locals and parameters, innermost scope last.
    var scopes: Array<HashMap<String, TypeName>> = Array<HashMap<String, TypeName>>();
    var current: TypeName?;
    ## The return types of the methods a bare call names.
    var own: HashMap<String, TypeName>;
    var returns: TypeName;
    var function: String;

    construct(current: TypeName?, own: HashMap<String, TypeName>, returns: TypeName, function: String) {
        this.current = current;
        this.own = own;
        this.returns = returns;
        this.function = function;
    }
}

struct _BoundsChecker {
    var traits: TraitDef[];
    var literal_args: Array<(Loc, ulong, Loc)>;
    var table: StructTable;
    ## Each generic struct's parameter names, to read its members' types
    ## at a specialization.
    var struct_params: HashMap<String, String[]> = HashMap<String, String[]>();
    var state: PassState;

    construct(module: Module, state: PassState) {
        this.state = state;
        traits = module.traits;
        literal_args = module.literal_args;
        table = StructTable(module, memo = state.trait_types_memo());
        for (var st in module.structs) {
            if (st.generic_params.count != 0 and !st.name.contains("<")) {
                var names = Array<String>();
                for (var p in st.generic_params) {
                    names.append(p.name);
                }
                struct_params[st.name] = names;
            }
        }
    }

    _report(error: Diagnostic, note: (String, Optional<Loc>)) {
        var (text, at) = note;
        state.report(
            error.with_note(
                text, at.is_value() ? Optional<Location>.Value(location_of(at.value())) : Optional<Location>.Empty
            )
        );
    }

    ## Checks `function`, where a bare call of `own` (a trait's default
    ## method calling a sibling) returns its type.
    function(function: FunctionDef, outer: GenericParam[], current: TypeName?, own: HashMap<String, TypeName>) {
        if (!function.body.is_value()) {
            return;
        }
        var walk = _BoundsWalk(current, own, function.ty, set_name(function.name));
        var all = outer.copy();
        all.append_all(function.generic_params);
        for (var p in all) {
            if (p.bounds.count > 0 and !p.is_argument) {
                walk.params[p.name] = _Constrained(p, traits);
            }
        }
        if (walk.params.count == 0) {
            return;
        }
        var locals = HashMap<String, TypeName>();
        for (var p in function.parameters) {
            var name = p.name.starts_with("this.") ? p.name.substr_bytes(5, p.name.size - 5) : p.name;
            locals[name] = p.ty;
        }
        walk.scopes.append(locals);
        for (var p in function.parameters) {
            if (p.default.is_value()) {
                expression(p.default.value(), walk);
            }
        }
        block(function.body.value(), walk);
    }

    block(b: Block, walk: _BoundsWalk) {
        walk.scopes.append(HashMap<String, TypeName>());
        for (var item in b.items) {
            statement(item, walk);
        }
        walk.scopes.pop();
    }

    statement(item: Statement, walk: _BoundsWalk) {
        match (item) {
            Expression(e) => {
                expression(e, walk);
            }
            Block(inner) => {
                block(inner, walk);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    var ty = _initialized(variable, walk);
                    walk.scopes.last()[variable.name] = ty;
                }
            }
            Branch(branch) => {
                expression(branch.condition, walk);
                block(branch.if_block, walk);
                if (branch.else_block.is_value()) {
                    block(branch.else_block.value(), walk);
                }
            }
            While(loop) => {
                expression(loop.condition, walk);
                block(loop.block, walk);
            }
            Return(r) => {
                if (!r.expr.is_value()) {
                    return;
                }
                var value = r.expr.value();
                expression(value, walk);
                if (walk.returns.is_auto()) {
                    return;
                }
                var ty = type_of(value, walk);
                if (!ty.is_value()) {
                    return;
                }
                var bad = flows(ty.value(), walk.returns, walk);
                if (bad.is_value()) {
                    var own_loc = _expression_loc(value);
                    var at = own_loc.is_none() ? r.loc : own_loc;
                    _report(
                        error_at(
                            $"cannot return a value of type '{ty.value().display()}' from '{walk.function}', which returns '{walk.returns.display()}'",
                            at
                        ),
                        bad.value()
                    );
                }
            }
            else => {}
        }
    }

    ## The constrained parameter `ty` names, if it names one.
    constrained(ty: TypeName, walk: _BoundsWalk): _Constrained? {
        if (ty.sub_types.count != 0) {
            return Optional<_Constrained>.Empty;
        }
        return walk.params.try_get(ty.name);
    }

    local(name: String, walk: _BoundsWalk): TypeName? {
        ulong i = walk.scopes.count;
        while (i > 0) {
            i -= 1;
            var found = walk.scopes[i].try_get(name);
            if (found.is_value()) {
                return found;
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## Whether a value of type `value` may flow into a slot of type `slot`:
    ## none when it may; otherwise the note for a constrained `value`.
    flows(value: TypeName, slot: TypeName, walk: _BoundsWalk): (String, Optional<Loc>)? {
        var none = Optional<(String, Optional<Loc>)>.Empty;
        var c = constrained(value, walk);
        if (!c.is_value()) {
            return none;
        }
        if (slot.contains_auto() or _canonical(slot) == _canonical(value)) {
            return none;
        }
        for (var (b, _) in c.value().bounds) {
            if (_canonical(b) == _canonical(slot)) {
                return none;
            }
        }
        # Another generic parameter, a pointer or a function type: left to
        # the specializations.
        if ((slot.sub_types.count == 0 and walk.params.contains(slot.name) and slot.name != value.name)
            or slot.is_pointer()
            or slot.name.starts_with("__")) {
            return none;
        }
        var names = Array<String>();
        for (var (b, _) in c.value().bounds) {
            names.append($"'{b.display()}'");
        }
        var plural = names.count == 1 ? "" : "s";
        var at = Optional<Loc>.Empty;
        if (c.value().bounds.count > 0) {
            var (_, first) = c.value().bounds[0];
            at = Optional<Loc>.Value(first);
        }
        return Optional<(String, Optional<Loc>)>.Value(
            ($"'{value.name}' converts only to its constraint{plural} {" & ".join(names)}", at)
        );
    }

    ## The type of `e` where the walk can tell.
    type_of(e: Expression, walk: _BoundsWalk): TypeName? {
        var none = Optional<TypeName>.Empty;
        match (e) {
            SymbolRef(node) => {
                var found = local(node.id, walk);
                if (!found.is_value()) {
                    found = field(node.id, walk);
                }
                if (!found.is_value() and !node.ty.is_empty() and !node.ty.is_auto()) {
                    found = Optional<TypeName>.Value(node.ty);
                }
                if (found.is_value() and found.value().is_auto()) {
                    return none;
                }
                return found;
            }
            MethodCall(node) => {
                var receiver_param = static_receiver(node.this_value, walk);
                if (receiver_param.is_value()) {
                    return _first_return(receiver_param.value(), node.method);
                }
                var receiver = type_of(node.this_value, walk);
                if (!receiver.is_value()) {
                    return none;
                }
                var c = constrained(receiver.value(), walk);
                if (c.is_value()) {
                    return _first_return(c.value(), node.method);
                }
                return member_return(receiver.value(), node.method);
            }
            ForIterator(source_expression) => {
                var source = type_of(source_expression, walk);
                if (!source.is_value()) {
                    return none;
                }
                # A constrained parameter iterates as its constraints say:
                # through `iterate()`, or as an iterator.
                var c = constrained(source.value(), walk);
                if (c.is_value()) {
                    for (var (_, m) in c.value().named("iterate")) {
                        if (!m.is_static and m.parameters.count == 0) {
                            var (_, ret) = _member_signature(m, "iterate");
                            return ret;
                        }
                    }
                    if (c.value().named("next").count > 0 and c.value().named("current").count > 0) {
                        return source;
                    }
                    return none;
                }
                var iterator = member_return(source.value(), "iterate");
                return iterator.is_value() ? iterator : source;
            }
            Index(node) => {
                var owner = type_of(node.lhs, walk);
                if (!owner.is_value()) {
                    return none;
                }
                return member_return(owner.value(), "__index_get");
            }
            MemberRef(node) => {
                var owner = type_of(node.lhs, walk);
                if (!owner.is_value()) {
                    return none;
                }
                var element = owner.value().tuple_element(node.name);
                if (element.is_value()) {
                    return element;
                }
                var info = table.lookup(owner.value());
                if (!info.is_value()) {
                    return none;
                }
                var ty = info.value().field(node.name);
                if (!ty.is_value()) {
                    return none;
                }
                return Optional<TypeName>.Value(specialize(owner.value(), ty.value()));
            }
            Ternary(node) => {
                return type_of(node.true_expr, walk);
            }
            Binary(node) => {
                if (_is_assignment(node.op)) {
                    return type_of(node.lhs, walk);
                }
            }
            FunctionCall(node) => {
                # A bare call of a sibling method.
                var set = set_name(node.function);
                var own = walk.own.try_get(set);
                if (own.is_value()) {
                    return own.value().is_auto() ? none : own;
                }
                if (walk.current.is_value()) {
                    var ret = member_return(walk.current.value(), node.function);
                    if (ret.is_value()) {
                        return ret;
                    }
                }
            }
            else => {}
        }
        return static_type_of(e, table, walk.current, state);
    }

    _first_return(c: _Constrained, method: String): TypeName? {
        var named = c.named(method);
        if (named.count == 0) {
            return Optional<TypeName>.Empty;
        }
        var (_, m) = named[0];
        var (_, ret) = _member_signature(m, method);
        return ret;
    }

    ## The type of field `name` of the struct whose method is walked.
    field(name: String, walk: _BoundsWalk): TypeName? {
        if (!walk.current.is_value()) {
            return Optional<TypeName>.Empty;
        }
        var info = table.lookup(walk.current.value());
        if (!info.is_value()) {
            return Optional<TypeName>.Empty;
        }
        return info.value().field(name);
    }

    ## The type method `method` of a value of type `receiver` returns.
    member_return(receiver: TypeName, method: String): TypeName? {
        var info = table.lookup(receiver);
        if (!info.is_value()) {
            return Optional<TypeName>.Empty;
        }
        var ret = info.value().returns.try_get(method);
        if (!ret.is_value()) {
            return ret;
        }
        var ty = specialize(receiver, ret.value());
        return ty.is_auto() ? Optional<TypeName>.Empty : Optional<TypeName>.Value(ty);
    }

    ## `ty`, a member type of generic struct `owner`'s base, at `owner`'s
    ## type arguments.
    specialize(owner: TypeName, ty: TypeName): TypeName {
        var params = struct_params.try_get(owner.name);
        if (!params.is_value()) {
            return ty;
        }
        var map = Array<(String, TypeName)>();
        ulong i = 0;
        while (i < params.value().count and i < owner.sub_types.count) {
            map.append((params.value()[i], owner.sub_types[i]));
            i += 1;
        }
        var out = ty.copy();
        replace_map(out, map);
        return out;
    }

    ## The constrained parameter a static call names: `T` in `T.make()`,
    ## when no local or field is called `T`.
    static_receiver(this_value: Expression, walk: _BoundsWalk): _Constrained? {
        if (this_value is SymbolRef(node)) {
            if (local(node.id, walk).is_value() or field(node.id, walk).is_value()) {
                return Optional<_Constrained>.Empty;
            }
            return walk.params.try_get(node.id);
        }
        return Optional<_Constrained>.Empty;
    }

    expression(e: Expression, walk: _BoundsWalk) {
        match (e) {
            MethodCall(node) => {
                var receiver_param = static_receiver(node.this_value, walk);
                if (receiver_param.is_value()) {
                    var id = "";
                    if (node.this_value is SymbolRef(symbol)) {
                        id = symbol.id;
                    }
                    call(id, receiver_param.value(), node.method, node.args, node.loc, true, walk);
                } else {
                    var receiver = type_of(node.this_value, walk);
                    if (receiver.is_value()) {
                        var c = constrained(receiver.value(), walk);
                        if (c.is_value()) {
                            call(receiver.value().name, c.value(), node.method, node.args, node.loc, false, walk);
                        }
                    }
                }
            }
            MemberRef(node) => {
                # A method used as a value (`x.value`) is a member too.
                var owner = type_of(node.lhs, walk);
                if (owner.is_value()) {
                    var c = constrained(owner.value(), walk);
                    if (c.is_value()) {
                        bool instance = false;
                        for (var (_, m) in c.value().named(node.name)) {
                            if (!m.is_static) {
                                instance = true;
                            }
                        }
                        if (!instance) {
                            var param = owner.value().name;
                            _report(
                                error_at($"no member named '{node.name}' in '{param}'", node.loc),
                                c.value().missing(param, $"member '{node.name}'")
                            );
                        }
                    }
                }
            }
            FunctionCall(node) => {
                var c = walk.params.try_get(node.function);
                if (c.is_value() and !local(node.function, walk).is_value()) {
                    _report(
                        error_at(
                            $"cannot construct '{node.function}': a constrained type parameter has no constructor",
                            node.loc
                        ),
                        c.value().missing(node.function, "constructor")
                    );
                }
            }
            Binary(node) => {
                _binary(node.op, node.lhs, node.rhs, node.loc, walk);
            }
            Unary(node) => {
                _unary(node, walk);
            }
            Index(node) => {
                _index(node, walk);
            }
            else => {}
        }
        for (var child in expression_children(e)) {
            expression(child, walk);
        }
    }

    # Checks the initial value of `variable` and gives the variable's type:
    # the value's for `var`.
    _initialized(variable: VariableDef, walk: _BoundsWalk): TypeName {
        var ty = variable.ty;
        if (!variable.default.is_value()) {
            return ty;
        }
        var value_expression = variable.default.value();
        expression(value_expression, walk);
        var value = type_of(value_expression, walk);
        if (ty.is_auto()) {
            return value.is_value() ? value.value() : TypeName.auto();
        }
        if (!value.is_value()) {
            return ty;
        }
        var own_loc = _expression_loc(value_expression);
        var at = own_loc.is_none() ? variable.loc : own_loc;
        var bad = flows(value.value(), ty, walk);
        if (bad.is_value()) {
            _report(
                error_at(
                    $"cannot initialize variable '{variable.name}' of type '{ty.display()}' with a value of type '{value.value().display()}'",
                    at
                ),
                bad.value()
            );
        }
        return ty;
    }

    # `-x` or `~x` on a constrained type parameter needs the operator in
    # its constraints.
    _unary(node: UnaryExpression, walk: _BoundsWalk) {
        if (node.op != UnaryOp.Neg and node.op != UnaryOp.BitNot) {
            return;
        }
        var t = type_of(node.operand, walk);
        if (!t.is_value()) {
            return;
        }
        var c = constrained(t.value(), walk);
        if (!c.is_value()) {
            return;
        }
        var name = node.op == UnaryOp.Neg ? "-" : "~";
        for (var (_, m) in c.value().named(name)) {
            if (m.parameters.count == 0 and !m.is_static) {
                return;
            }
        }
        var param = t.value().name;
        var operator = Loc.at(node.loc.file, ast.Span(node.loc.span.start, node.loc.span.start + 1));
        _report(
            error_at($"invalid argument type '{param}' to unary expression", operator),
            c.value().missing(param, $"operator '{name}'")
        );
    }

    # `x[i]` on a constrained type parameter needs an indexer in its
    # constraints.
    _index(node: IndexExpression, walk: _BoundsWalk) {
        var t = type_of(node.lhs, walk);
        if (!t.is_value()) {
            return;
        }
        var c = constrained(t.value(), walk);
        if (!c.is_value()) {
            return;
        }
        for (var (_, m) in c.value().members) {
            if (m.is_indexer) {
                return;
            }
        }
        var param = t.value().name;
        _report(error_at($"type '{param}' cannot be indexed", node.loc), c.value().missing(param, "indexer"));
    }

    _binary(op: BinaryOp, lhs: Expression, rhs: Expression, loc: Loc, walk: _BoundsWalk) {
        var lhs_type = type_of(lhs, walk);
        var rhs_type = type_of(rhs, walk);
        if (op == BinaryOp.Assign) {
            if (rhs_type.is_value() and lhs_type.is_value()) {
                var bad = flows(rhs_type.value(), lhs_type.value(), walk);
                if (bad.is_value()) {
                    var own_loc = _expression_loc(rhs);
                    _report(
                        error_at(
                            $"cannot assign a value of type '{rhs_type.value().display()}' to a variable of type '{lhs_type.value().display()}'",
                            own_loc.is_none() ? loc : own_loc
                        ),
                        bad.value()
                    );
                }
            }
            return;
        }
        if (op == BinaryOp.Equal
            or op == BinaryOp.NotEqual
            or op == BinaryOp.Identical
            or op == BinaryOp.NotIdentical
            or op == BinaryOp.LogicalAnd
            or op == BinaryOp.LogicalOr) {
            return;
        }
        var left = lhs_type.is_value() ? constrained(lhs_type.value(), walk) : Optional<_Constrained>.Empty;
        var right = rhs_type.is_value() ? constrained(rhs_type.value(), walk) : Optional<_Constrained>.Empty;
        if (!left.is_value() and !right.is_value()) {
            return;
        }
        var c = left.is_value() ? left.value() : right.value();
        var param = left.is_value() ? lhs_type.value().name : rhs_type.value().name;
        # A compound assignment (`+=`) is its own operator: `+` does not
        # provide it.
        var name = op_name(op);
        bool declared = left.is_value() and c.named(name).count > 0;
        if (declared) {
            return;
        }
        var shown_left = lhs_type.is_value() ? lhs_type.value().display() : "?";
        var shown_right = rhs_type.is_value() ? rhs_type.value().display() : "?";
        # The node's location runs on over the right operand.
        var operator = Loc.at(loc.file, ast.Span(loc.span.start, loc.span.start + name.size));
        _report(
            error_at($"invalid operands to binary expression ('{shown_left}' and '{shown_right}')", operator),
            c.missing(param, $"operator '{name}'")
        );
    }

    ## A call of `method` on a value of constrained type `param`, or
    ## through it as a static call.
    call(
        param: String, c: _Constrained, method: String, args: Expression[], loc: Loc, is_static: bool, walk: _BoundsWalk
    ) {
        var base = _without_type_arguments(method);
        var named = Array<(ulong, FunctionDef)>();
        for (var (b, m) in c.named(method)) {
            if (m.is_static == is_static) {
                named.append((b, m));
            }
        }
        if (named.count == 0) {
            var what = is_static ? $"static member '{base}'" : $"member '{base}'";
            _report(error_at($"no member named '{base}' in '{param}'", loc), c.missing(param, what));
            return;
        }
        # The same member from two constraints: which one is meant?
        var owners = Array<ulong>();
        for (var (b, _) in named) {
            if (owners.count == 0 or owners.last() != b) {
                owners.append(b);
            }
        }
        if (owners.count > 1) {
            var (first, first_loc) = c.bounds[owners[0]];
            var (second, _) = c.bounds[owners[1]];
            _report(
                error_at(
                    $"'{base}' is declared by both '{first.display()}' and '{second.display()}'; call it through one of them",
                    loc
                ),
                ($"'{param}' is constrained here", Optional<Loc>.Value(first_loc))
            );
            return;
        }
        var fits = Array<FunctionDef>();
        for (var (_, m) in named) {
            ulong required = 0;
            for (var p in m.parameters) {
                if (!p.default.is_value()) {
                    required += 1;
                }
            }
            if (args.count >= required and args.count <= m.parameters.count) {
                fits.append(m);
            }
        }
        if (fits.count != 1) {
            if (fits.count == 0 and named.count == 1) {
                var (_, only) = named[0];
                var expected = only.parameters.count;
                var many = args.count > expected ? "many" : "few";
                _report(
                    error_at($"too {many} arguments to '{base}': expected {expected}, have {args.count}", loc),
                    ($"'{base}' declared here", Optional<Loc>.Value(only.loc))
                );
            }
            # Several overloads fit, or none: the specializations decide.
            return;
        }
        var member = fits[0];
        var (parameters, _) = _member_signature(member, method);
        ulong i = 0;
        while (i < args.count and i < parameters.count) {
            var arg = args[i];
            var expected = parameters[i];
            i += 1;
            # A parameter typed by the member's own unwritten type parameter
            # takes what inference gives it.
            if (!expected.is_value()) {
                continue;
            }
            var actual = type_of(arg, walk);
            if (!actual.is_value()) {
                continue;
            }
            if (!_incompatible(actual.value(), expected.value(), walk)) {
                continue;
            }
            var at = _expression_loc(arg);
            if (at.is_none()) {
                at = loc;
                for (var (call_loc, j, written) in literal_args) {
                    if (call_loc == loc and j == i - 1) {
                        at = written;
                        break;
                    }
                }
            }
            _report(
                error_at(
                    $"cannot pass a value of type '{actual.value().display()}' as argument {i} of '{base}', which has type '{expected.value().display()}'",
                    at
                ),
                ($"'{base}' declared here", Optional<Loc>.Value(member.loc))
            );
            return;
        }
    }

    ## Whether a value of type `actual` clearly cannot be passed as
    ## `expected`: both are known, and a struct is passed for a number, or
    ## they are different generic parameters, or `actual` is a constrained
    ## parameter the slot is not one of its constraints.
    _incompatible(actual: TypeName, expected: TypeName, walk: _BoundsWalk): bool {
        if (actual.contains_auto() or expected.contains_auto() or _canonical(actual) == _canonical(expected)) {
            return false;
        }
        bool actual_param = actual.sub_types.count == 0 and walk.params.contains(actual.name);
        bool expected_param = expected.sub_types.count == 0 and walk.params.contains(expected.name);
        if (actual_param or expected_param) {
            if (!actual_param) {
                return true;
            }
            for (var (t, _) in walk.params[actual.name].bounds) {
                if (_canonical(t) == _canonical(expected)) {
                    return false;
                }
            }
            return true;
        }
        return _is_number(expected) and !_is_number(actual) and !actual.is_pointer() and !expected.is_pointer();
    }

    _is_number(t: TypeName): bool {
        return (t.is_scalar() and state.is_integral(t.name))
            or t.name == "f32"
            or t.name == "f64"
            or t.name == "float"
            or t.name == "double"
            or t.name == "bool";
    }
}
