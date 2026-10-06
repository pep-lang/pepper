## Calls of members a specialization did not get from a constrained
## extension: `constraints::check_withheld` in Pepper.

import [Diagnostic, Location] from compiler.diagnostic;
import [error_at, location_of] from "common";
import [constraint_spelled] from "constraints";
import [Loc] from "loc";
import [Expression, FunctionDef, Module, TypeName, Withheld] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Reports a call of a member a specialization did not get from a
## constrained extension (`b.label()` on a `Box<Circle>`, where `label`
## needs `T: Named`), with the constraint it misses. Runs once
## specializations and their calls are typed.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_withheld(module: Module, state: PassState) {
    if (module.withheld.count == 0) {
        return;
    }
    var finder = _WithheldCalls(module, state);
    for (var f in module.functions) {
        if (!f.is_generic_func) {
            finder.visit(f, Optional<TypeName>.Empty);
        }
    }
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            continue;
        }
        var current = Optional<TypeName>.Value(st.ty);
        for (var m in st.method_members) {
            finder.visit(m, current);
        }
        for (var c in st.constructors) {
            finder.visit(c, current);
        }
        finder.visit(st.destructor, current);
    }
    finder.current = Optional<TypeName>.Empty;
    for (var g in module.globals) {
        if (g.default.is_value()) {
            rewrite_expression(g.default.value(), finder);
        }
    }
    if (finder.found.is_value()) {
        state.report(finder.found.value());
    }
}

## Finds the first call of a withheld member.
struct _WithheldCalls {
    var module: Module;
    var state: PassState;
    var names: HashSet<String> = HashSet<String>();
    var free: HashSet<String> = HashSet<String>();
    var table: StructTable? = Optional<StructTable>.Empty;
    var current: TypeName? = Optional<TypeName>.Empty;
    var found: Diagnostic? = Optional<Diagnostic>.Empty;

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
        for (var w in module.withheld) {
            names.insert(w.member);
        }
        for (var f in module.functions) {
            free.insert(set_name(f.name));
        }
    }

    visit(function: FunctionDef, current: TypeName?) {
        this.current = current;
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        if (found.is_value()) {
            return e;
        }
        match (e) {
            MethodCall(node) => {
                if (!names.contains(set_name(node.method))) {
                    return e;
                }
                if (!table.is_value()) {
                    table = Optional<StructTable>.Value(StructTable(module, memo = state.trait_types_memo()));
                }
                var receiver = static_type_of(node.this_value, table.value(), current, state);
                if (receiver.is_value()) {
                    check(receiver.value(), node.method, node.args.count, node.loc);
                }
            }
            FunctionCall(node) => {
                var set = set_name(node.function);
                if (current.is_value() and names.contains(set) and !free.contains(set)) {
                    check(current.value(), node.function, node.args.count, node.loc);
                }
            }
            else => {}
        }
        return e;
    }

    check(receiver: TypeName, method: String, count: ulong, loc: Loc) {
        var owner = receiver.to_string();
        while (owner.ends_with("*")) {
            owner = owner.substr_bytes(0, owner.size - 1);
        }
        var member = set_name(method);
        for (var st in module.structs) {
            if (st.name != owner) {
                continue;
            }
            for (var m in st.method_members) {
                if (_offers(m, member, method, count)) {
                    return;
                }
            }
            for (var m in st.generic_methods) {
                if (_offers(m, member, method, count)) {
                    return;
                }
            }
            break;
        }
        # Of several withheld overloads, the one this call's arguments fit.
        var chosen = Optional<Withheld>.Empty;
        for (var w in module.withheld) {
            if (w.owner == owner and w.member == member) {
                if (w.params == count) {
                    chosen = Optional<Withheld>.Value(w);
                    break;
                }
                if (!chosen.is_value()) {
                    chosen = Optional<Withheld>.Value(w);
                }
            }
        }
        if (chosen.is_value()) {
            var w = chosen.value();
            found = Optional<Diagnostic>.Value(
                error_at(
                    $"no member named '{member}' in '{owner}'",
                    loc
                ).with_note(
                    $"'{member}' requires '{constraint_spelled(w.arg)}' to conform to '{constraint_spelled(w.bound)}'",
                    Optional<Location>.Value(location_of(w.at))
                )
            );
        }
    }
}

extend _WithheldCalls with Rewriter;

## Whether `m` is member `member` and takes `count` arguments (or is the
## very overload called).
_offers(m: FunctionDef, member: String, method: String, count: ulong): bool {
    if (set_name(m.name) != member) {
        return false;
    }
    ulong required = 0;
    for (var p in m.parameters) {
        if (!p.default.is_value()) {
            required += 1;
        }
    }
    return (count >= required and count <= m.parameters.count) or m.name == method;
}
