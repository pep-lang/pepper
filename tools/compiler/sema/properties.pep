## Property accesses: `pepper_sema::passes::properties` in Pepper. The
## builder lowers each property to plain members (its storage field, a
## getter and, with a `set`, a setter); this rewrites the accesses once the
## receiver's type is known:
##
## - a read `x.p` is the storage (`x.p` itself, for a default `get`) or the
##   call `x.__get_p()`;
## - an assignment `x.p = v` is a store to the storage (default `set`, or no
##   `set` inside the struct's own code) or the call `x.__set_p(v)`;
## - a compound assignment `x.p += v` (and `++`/`--`) reads, then writes,
##   evaluating `x` once;
## - a bare `p` in the struct's methods is `this.p`.
##
## It runs inside `resolve_implicit_types`, which types the receivers.

import [Location] from compiler.diagnostic;
import [getter_name, SHARED_ATTRIBUTE, setter_name] from "builder";
import [error_at, location_of] from "common";
import [method_of] from "enums";
import [Loc] from "loc";
import [
    AccessorKind,
    BinaryExpression,
    BinaryOp,
    Expression,
    MemberRefExpression,
    MethodCallExpression,
    Module,
    PropertyDef,
    SubjectExpression,
    SymbolRefExpression,
    TypeName,
    UnaryOp,
    WithSubject
] from "model";
import [PassState] from "state";

## The program's properties, by owner (struct or trait base name).
export struct Properties {
    var by_owner: HashMap<String, Array<PropertyDef>> = HashMap<String, Array<PropertyDef>>();
    ## Where every extension method is declared: an extension's methods are
    ## not their struct's own code, even once copied into it.
    var extension_methods: HashSet<Loc> = HashSet<Loc>();
    ## How many accesses `lower_property` has rewritten into something
    ## else: a caller compares it before and after to learn whether an
    ## access changed.
    var lowered: ulong = 0;

    ## Returns the properties of `module`.
    ##
    ## @param module the model
    construct(module: Module) {
        for (var property in module.properties) {
            if (!by_owner.contains(property.owner)) {
                by_owner[property.owner] = Array<PropertyDef>();
            }
            by_owner[property.owner].append(property);
        }
        for (var ext in module.extensions) {
            for (var m in ext.methods) {
                extension_methods.insert(m.loc);
            }
        }
    }

    ## Returns whether the program has no properties.
    is_empty(): bool {
        return by_owner.count == 0;
    }

    ## Returns property `name` of a value of type `ty`, if it has one.
    ##
    ## @param ty the value's type
    ## @param name the member
    ## @returns the property
    find(ty: TypeName, name: String): PropertyDef? {
        if (by_owner.count == 0 or ty.is_pointer()) {
            return Optional<PropertyDef>.Empty;
        }
        var owned = by_owner.try_get(ty.name);
        if (owned.is_value()) {
            for (var p in owned.value()) {
                if (p.name == name) {
                    return Optional<PropertyDef>.Value(p);
                }
            }
        }
        return Optional<PropertyDef>.Empty;
    }
}

## Where an access is written, and how to type expressions there.
export trait PropertySite {
    ## The struct whose code the access is in, if any.
    current(): TypeName?;

    ## Whether that code is a constructor.
    in_constructor(): bool;

    ## The name of the function or method the code is in.
    function(): String;

    ## Where that function is declared.
    function_loc(): Loc;

    ## Returns the type of `e` in the walk's scope.
    type_of(e: Expression): TypeName;

    ## Returns whether `name` is a parameter or local in the walk's scope.
    is_local(name: String): bool;
}

## Whether `this.name` here is `property`'s storage rather than the
## property: in its own accessors, when the storage keeps the property's
## name.
_is_own_storage(site: PropertySite, receiver: Expression, property: PropertyDef): bool {
    if (!(receiver is ThisRef)) {
        return false;
    }
    if (!property.storage.is_value() or property.storage.value() != property.name) {
        return false;
    }
    var function = site.function();
    return function == getter_name(property.name) or function == setter_name(property.name);
}

## Rewrites the property access `e`, if it is one, and returns what
## replaces it. As `properties::lower` does.
##
## @param e the expression
## @param properties the program's properties
## @param site where the access is written
## @param state the passes' state, for errors
## @returns the expression to keep
export lower_property(e: Expression, properties: Properties, site: PropertySite, state: PassState): Expression {
    if (properties.is_empty()) {
        return e;
    }
    match (e) {
        Binary(node) => {
            if (!_is_assignment(node.op)) {
                return e;
            }
            # Code the compiler synthesizes has no location and initializes
            # the storage itself; a constructor's `this.p` parameter, which
            # assigns the property, is the exception.
            bool init_parameter = false;
            if (node.rhs is SymbolRef(r)) {
                init_parameter = r.id.starts_with("__init_");
            }
            if (node.loc.is_none() and !init_parameter) {
                return e;
            }
            node.lhs = _bare_to_member(node.lhs, properties, site, state);
            if (!(node.lhs is MemberRef(_))) {
                return e;
            }
            var member = _member(node.lhs);
            var found = properties.find(site.type_of(member.lhs), member.name);
            if (!found.is_value() or _is_own_storage(site, member.lhs, found.value())) {
                return e;
            }
            var property = found.value();
            var at = member.loc;
            if (node.op != BinaryOp.Assign and _is_direct(property, site, properties)) {
                _rename(member, property, properties);
                return e;
            }
            if (node.op == BinaryOp.Assign) {
                if (!_stores_in_place(property, member.name)) {
                    properties.lowered += 1;
                }
                return _write(member.lhs, property, node.rhs, at, site, properties, state);
            }
            var base = _compound_base(node.op);
            if (!base.is_value()) {
                return e;
            }
            properties.lowered += 1;
            return _read_modify_write(
                member.lhs, property, base.value(), node.rhs, at, node.loc, site, properties, state
            );
        }
        Unary(node) => {
            bool increment = node.op == UnaryOp.PreInc or node.op == UnaryOp.PostInc;
            if (!increment and node.op != UnaryOp.PreDec and node.op != UnaryOp.PostDec) {
                return e;
            }
            node.operand = _bare_to_member(node.operand, properties, site, state);
            if (!(node.operand is MemberRef(_))) {
                return e;
            }
            var member = _member(node.operand);
            var found = properties.find(site.type_of(member.lhs), member.name);
            if (!found.is_value() or _is_own_storage(site, member.lhs, found.value())) {
                return e;
            }
            var property = found.value();
            var at = member.loc;
            var base = increment ? BinaryOp.Add : BinaryOp.Sub;
            if (_is_direct(property, site, properties)) {
                _rename(member, property, properties);
                return e;
            }
            properties.lowered += 1;
            return _read_modify_write(
                member.lhs, property, base, Expression.IntLiteral(1), at, node.loc, site, properties, state
            );
        }
        SymbolRef(_) => {
            var replaced = _bare_to_member(e, properties, site, state);
            if (replaced is MemberRef(_)) {
                return lower_property(replaced, properties, site, state);
            }
            return e;
        }
        MethodCall(node) => {
            # `x.count()` where `count` is a property: read it without `()`.
            if (node.args.count != 0) {
                return e;
            }
            var found = properties.find(site.type_of(node.this_value), node.method);
            if (!found.is_value()) {
                return e;
            }
            # A property of function type is called through.
            var read = Expression.MemberRef(MemberRefExpression(node.this_value, node.method, node.loc));
            if (site.type_of(read).is_callable()) {
                return e;
            }
            state.report(
                error_at(
                    $"'{node.method}' is a property, not a method; read it without '()'", node.loc
                ).with_note($"'{node.method}' declared here", Optional<Location>.Value(location_of(found.value().loc)))
            );
            return e;
        }
        MemberRef(node) => {
            var found = properties.find(site.type_of(node.lhs), node.name);
            if (!found.is_value() or _is_own_storage(site, node.lhs, found.value())) {
                return e;
            }
            if (!_reads_in_place(found.value(), node.name)) {
                properties.lowered += 1;
            }
            return _read(node.lhs, found.value(), node.loc);
        }
        else => {
            return e;
        }
    }
}

_member(e: Expression): MemberRefExpression {
    if (e is MemberRef(node)) {
        return node;
    }
    return MemberRefExpression(Expression.ThisRef, "", Loc.none());
}

## A bare `p` in the methods of a struct with a property `p` (and no local
## or parameter of that name) is `this.p`; a property with a default `get`
## is left alone, its storage being the field `p`.
_bare_to_member(e: Expression, properties: Properties, site: PropertySite, state: PassState): Expression {
    if (!(e is SymbolRef(_))) {
        return e;
    }
    var node = _symbol(e);
    # An instance method of an enum whose cases carry nothing is the free
    # function `E::m`, whose `this` is its first parameter.
    var current = site.current();
    if (!current.is_value()) {
        var owner = method_of(state, site.function());
        if (owner.is_value()) {
            var (enum_name, _) = owner.value();
            var ty = TypeName.named(enum_name);
            if (!properties.find(ty, node.id).is_value() or site.is_local(node.id) or !site.is_local("this")) {
                return e;
            }
            var self = Expression.SymbolRef(SymbolRefExpression("this", ty, Loc.none()));
            properties.lowered += 1;
            return Expression.MemberRef(MemberRefExpression(self, node.id, node.loc));
        }
        return e;
    }
    var found = properties.find(current.value(), node.id);
    if (!found.is_value()) {
        return e;
    }
    var property = found.value();
    bool body_set = property.set.is_value() and property.set.value() == AccessorKind.Body;
    if ((property.get == AccessorKind.Default and !body_set) or site.is_local(node.id)) {
        return e;
    }
    properties.lowered += 1;
    return Expression.MemberRef(MemberRefExpression(Expression.ThisRef, node.id, node.loc));
}

_symbol(e: Expression): SymbolRefExpression {
    if (e is SymbolRef(node)) {
        return node;
    }
    return SymbolRefExpression("", TypeName(), Loc.none());
}

## Whether code at `site` belongs to the struct that declares `property`:
## its constructors and the methods in its body, not an extension's.
_inside(property: PropertyDef, site: PropertySite, properties: Properties): bool {
    var current = site.current();
    return !property.in_trait
        and current.is_value()
        and current.value().name == property.owner
        and !properties.extension_methods.contains(site.function_loc());
}

## Whether both reading and writing `property` at `site` go straight to its
## storage.
_is_direct(property: PropertyDef, site: PropertySite, properties: Properties): bool {
    if (!property.storage.is_value() or property.get != AccessorKind.Default) {
        return false;
    }
    if (property.set.is_value()) {
        return property.set.value() == AccessorKind.Default;
    }
    return _inside(property, site, properties) and (!property.shared or site.in_constructor());
}

## Points `member` at `property`'s storage, counting a change of name.
_rename(member: MemberRefExpression, property: PropertyDef, properties: Properties) {
    if (property.storage.is_value() and member.name != property.storage.value()) {
        member.name = property.storage.value();
        properties.lowered += 1;
    }
}

## Whether `_read` of `property`, read as `name`, is that same member.
_reads_in_place(property: PropertyDef, name: String): bool {
    return property.storage.is_value()
        and property.get == AccessorKind.Default
        and !property.in_trait
        and property.storage.value() == name;
}

## Whether `_write` of `property`, written as `name`, is an assignment of
## that same member (or an error).
_stores_in_place(property: PropertyDef, name: String): bool {
    if (!property.storage.is_value() or property.storage.value() != name) {
        return false;
    }
    if (property.set.is_value()) {
        return property.set.value() == AccessorKind.Default and !property.in_trait;
    }
    return true;
}

## The value of `receiver.p`.
_read(receiver: Expression, property: PropertyDef, at: Loc): Expression {
    if (property.storage.is_value() and property.get == AccessorKind.Default and !property.in_trait) {
        return Expression.MemberRef(MemberRefExpression(receiver, property.storage.value(), at));
    }
    return Expression.MethodCall(MethodCallExpression(receiver, getter_name(property.name), Array<Expression>(), at));
}

_store(storage: String, receiver: Expression, value: Expression, at: Loc): Expression {
    var target = Expression.MemberRef(MemberRefExpression(receiver, storage, at));
    return Expression.Binary(BinaryExpression(target, value, BinaryOp.Assign, at));
}

## `receiver.p = value`.
_write(
    receiver: Expression,
    property: PropertyDef,
    value: Expression,
    at: Loc,
    site: PropertySite,
    properties: Properties,
    state: PassState
): Expression {
    if (property.set.is_value()) {
        if (property.set.value() == AccessorKind.Default and property.storage.is_value() and !property.in_trait) {
            return _store(property.storage.value(), receiver, value, at);
        }
        var args = Array<Expression>();
        args.append(value);
        return Expression.MethodCall(MethodCallExpression(receiver, setter_name(property.name), args, at));
    }
    var note = $"'{property.name}' declared here";
    if (property.storage.is_value() and _inside(property, site, properties)) {
        if (property.shared and !site.in_constructor()) {
            state.report(
                error_at(
                    $"cannot assign to '{property.name}' outside a constructor: the storage of a '[{SHARED_ATTRIBUTE}]' struct's property is 'const'",
                    at
                ).with_note(note, Optional<Location>.Value(location_of(property.loc)))
            );
        }
        return _store(property.storage.value(), receiver, value, at);
    }
    state.report(
        error_at(
            $"cannot assign to '{property.name}': it has no 'set' accessor", at
        ).with_note(note, Optional<Location>.Value(location_of(property.loc)))
    );
    return Expression.MemberRef(MemberRefExpression(receiver, property.name, at));
}

## The id of the `WithSubject` that evaluates a compound assignment's
## receiver once: made from its location, with the top bit set so it never
## meets a `match` site's.
_subject_id(at: Loc): ulong {
    return ((1 as ulong) << 62) | ((at.file as ulong) << 32) | at.span.start;
}

## `receiver.p op= operand`: read `p`, combine, write it back, evaluating
## `receiver` once.
_read_modify_write(
    receiver: Expression,
    property: PropertyDef,
    op: BinaryOp,
    operand: Expression,
    at: Loc,
    op_loc: Loc,
    site: PropertySite,
    properties: Properties,
    state: PassState
): Expression {
    bool simple = receiver is ThisRef;
    if (receiver is SymbolRef(_)) {
        simple = true;
    }
    if (simple) {
        return _update(receiver, property, op, operand, at, op_loc, site, properties, state);
    }
    var id = _subject_id(at);
    var subject = Expression.Subject(SubjectExpression(id, TypeName.auto(), at));
    var body = _update(subject, property, op, operand, at, op_loc, site, properties, state);
    return Expression.WithSubject(WithSubject(receiver, body, id, Optional<String>.Empty, at));
}

_update(
    receiver: Expression,
    property: PropertyDef,
    op: BinaryOp,
    operand: Expression,
    at: Loc,
    op_loc: Loc,
    site: PropertySite,
    properties: Properties,
    state: PassState
): Expression {
    var current = _read(receiver.copy(), property, at);
    var value = Expression.Binary(BinaryExpression(current, operand, op, op_loc));
    return _write(receiver, property, value, at, site, properties, state);
}

## The operator a compound assignment applies (`+` for `+=`).
_compound_base(op: BinaryOp): BinaryOp? {
    match (op) {
        AddAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Add);
        }
        SubAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Sub);
        }
        MulAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Mul);
        }
        DivAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Div);
        }
        ModAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Mod);
        }
        LShiftAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.LShift);
        }
        RShiftAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.RShift);
        }
        BitAndAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.BitAnd);
        }
        BitOrAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.BitOr);
        }
        BitXorAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.BitXor);
        }
        else => {
            return Optional<BinaryOp>.Empty;
        }
    }
}
