## Uses of deprecated members: `check_deprecated_members` in Pepper. A
## field or method (an extension's included) marked `[Deprecated(...)]`,
## reached as `x.name`, `x.name(...)`, a static `S.name(...)`, or a bare
## `name` inside a method. Which struct a member belongs to depends on the
## type of `x`, so this runs once every type is final; uses of top-level
## names are found when linking. Each warning goes to `state.notes`.
##
## A use is reported only where the source spells the member's name at the
## use's location, which leaves out the calls sema synthesizes (a `for`
## loop's `next()`, a `with` block's `enter()`, an operator overload). Uses
## inside a deprecated function, method, or struct are not reported, and
## each location is reported once, however many specializations share it.

import compiler.ast;
import [Diagnostic] from compiler.diagnostic;
import [declared_deprecation, Deprecation, deprecation_warning] from compiler.link;
import [location_of] from "common";
import [method_of] from "enums";
import [Loc] from "loc";
import [Expression, FunctionDef, Module, SymbolRefExpression, TypeName] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## The owner under which overloaded constructors are listed, by function
## name.
const _CONSTRUCTORS = "";

## Adds a warning to `state.notes` for each use of a deprecated member.
##
## @param module the model
## @param state the passes' state
export check_deprecated_members(module: Module, state: PassState) {
    var members = _Members();
    for (var st in module.structs) {
        for (var f in st.field_members) {
            members.add(st.name, f.name, f.attributes, f.loc);
        }
        for (var m in st.method_members) {
            members.add(st.name, m.name, m.attributes, m.loc);
        }
        for (var m in st.generic_methods) {
            members.add(st.name, m.name, m.attributes, m.loc);
        }
    }
    for (var t in module.traits) {
        for (var m in t.methods) {
            members.add(t.name, m.name, m.attributes, m.loc);
        }
    }
    # An enum's methods are the functions `E::m`, which calls reach by that
    # name once `c.m()` is resolved.
    for (var f in module.functions) {
        var of = method_of(state, f.name);
        if (of.is_value()) {
            var (_, method) = of.value();
            members.add(f.name, method, f.attributes, f.loc);
        }
    }
    # An overloaded constructor (`Point$2`) is deprecated on its own; its
    # calls are only known once overloads are resolved. A single
    # constructor is checked when linking, with the struct.
    for (var st in module.structs) {
        if (st.constructors.count > 1) {
            for (var c in st.constructors) {
                members.add(_CONSTRUCTORS, c.name, c.attributes, c.loc);
            }
        }
    }
    if (members.owners.count == 0) {
        return;
    }
    var checker = _DeprecatedUses(members, StructTable(module), state);
    for (var function in module.functions) {
        if (!declared_deprecation(function.attributes).is_value()) {
            checker.function(function, Optional<TypeName>.Empty);
        }
    }
    for (var st in module.structs) {
        if (declared_deprecation(st.attributes).is_value()) {
            continue;
        }
        var current = Optional<TypeName>.Value(st.ty);
        for (var constructor in st.constructors) {
            checker.function(constructor, current);
        }
        checker.function(st.destructor, current);
        for (var method in st.method_members) {
            if (!declared_deprecation(method.attributes).is_value()) {
                checker.function(method, current);
            }
        }
    }
    for (var variable in module.globals) {
        if (!declared_deprecation(variable.attributes).is_value() and variable.default.is_value()) {
            checker.current = Optional<TypeName>.Empty;
            rewrite_expression(variable.default.value(), checker);
        }
    }
    state.notes.append_all(checker.warnings);
}

## A deprecated member: its deprecation and where it is declared.
struct _Member {
    var deprecation: Deprecation;
    var at: Loc;

    construct(deprecation: Deprecation, at: Loc) {
        this.deprecation = deprecation;
        this.at = at;
    }
}

## Owner type (a struct or trait, by name or specialization) to member name
## to its deprecation.
struct _Members {
    var owners: HashMap<String, HashMap<String, _Member>> = HashMap<String, HashMap<String, _Member>>();

    construct() {}

    add(owner: String, name: String, attributes: ast.Attribute[], at: Loc) {
        var deprecation = declared_deprecation(attributes);
        if (!deprecation.is_value()) {
            return;
        }
        if (!owners.contains(owner)) {
            owners[owner] = HashMap<String, _Member>();
        }
        owners[owner][name] = _Member(deprecation.value(), at);
    }

    get(owner: String, name: String): _Member? {
        var found = owners.try_get(owner);
        return found.is_value() ? found.value().try_get(name) : Optional<_Member>.Empty;
    }
}

struct _DeprecatedUses {
    var members: _Members;
    var table: StructTable;
    var state: PassState;
    var current: TypeName? = Optional<TypeName>.Empty;
    ## Locations already reported, as "file:start".
    var seen: HashSet<String> = HashSet<String>();
    var warnings: Diagnostic[] = Array<Diagnostic>();

    construct(members: _Members, table: StructTable, state: PassState) {
        this.members = members;
        this.table = table;
        this.state = state;
    }

    function(function: FunctionDef, current: TypeName?) {
        this.current = current;
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        match (e) {
            MethodCall(node) => {
                member(node.this_value, node.method, node.loc);
            }
            MemberRef(node) => {
                member(node.lhs, node.name, node.loc);
            }
            FunctionCall(node) => {
                constructor(node.function, node.loc);
                var of = method_of(state, node.function);
                if (of.is_value()) {
                    var (_, method) = of.value();
                    var owner = Expression.SymbolRef(SymbolRefExpression(node.function, TypeName.auto(), Loc.none()));
                    member(owner, method, node.loc);
                }
            }
            else => {}
        }
        return e;
    }

    ## The source text at `at`, or empty.
    spelled(at: Loc): String {
        if ((at.file as ulong) >= state.sources.count) {
            return "";
        }
        var text = state.sources[at.file as ulong].text;
        if (at.span.end > text.size or at.span.start > at.span.end) {
            return "";
        }
        return text.substr_bytes(at.span.start, at.span.end - at.span.start);
    }

    ## Whether `at` is reported for the first time, noting it.
    first_at(at: Loc): bool {
        return seen.insert($"{at.file}:{at.span.start}");
    }

    ## A call to overloaded constructor `function` (`Point$2`) at `used`,
    ## where the source spells the type (`Point`, `Box<int>` or `Box`).
    constructor(function: String, used: Loc) {
        var found = members.get(_CONSTRUCTORS, function);
        if (!found.is_value() or used.is_none()) {
            return;
        }
        var ty = set_name(function);
        var open = ty.find("<");
        var base = open < 0 ? ty : ty.substr_bytes(0, open as ulong);
        var text = spelled(used);
        if ((text != ty and text != base) or !first_at(used)) {
            return;
        }
        var entry = found.value();
        warnings.append(deprecation_warning(base, entry.deprecation, location_of(used), text, location_of(entry.at)));
    }

    ## The use of member `name` of `owner` at `used`.
    member(owner: Expression, full_name: String, used: Loc) {
        # A generic method's specialization (`pick<int>`) is a use of
        # `pick`.
        var open = full_name.find("<");
        var name = open < 0 ? full_name : full_name.substr_bytes(0, open as ulong);
        if (used.is_none()) {
            return;
        }
        var found = lookup(owner, name);
        if (!found.is_value()) {
            return;
        }
        var entry = found.value();
        if (used.same(entry.at)) {
            return;
        }
        var text = spelled(used);
        if (text != name or !first_at(used)) {
            return;
        }
        warnings.append(deprecation_warning(name, entry.deprecation, location_of(used), text, location_of(entry.at)));
    }

    ## The deprecation of member `name` of the type of `owner`, if it has
    ## one.
    lookup(owner: Expression, name: String): _Member? {
        var ty = static_type_of(owner, table, current, state);
        if (!ty.is_value()) {
            # A static call names the struct itself: `S.make()`.
            if (owner is SymbolRef(node)) {
                ty = Optional<TypeName>.Value(TypeName.named(node.id));
            } else {
                return Optional<_Member>.Empty;
            }
        }
        var pointee = ty.value().to_string();
        while (pointee.ends_with("*")) {
            pointee = pointee.substr_bytes(0, pointee.size - 1);
        }
        var open = pointee.find("<");
        var base = open < 0 ? pointee : pointee.substr_bytes(0, open as ulong);
        var found = members.get(pointee, name);
        return found.is_value() ? found : members.get(base, name);
    }
}

extend _DeprecatedUses with Rewriter;
