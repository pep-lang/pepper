## Methods with type parameters of their own (`map<U>(f: (T) => U)`):
## `generic_methods::specialize_methods` in Pepper. A call `x.map<long>(f)`,
## or the method as a value (`x.map<long>`), adds `map<long>`, the method
## with `U` replaced, to `method_members` of `x`'s struct, where it is
## compiled like any method.

import [Diagnostic] from compiler.diagnostic;
import [check_method_call, Conformance, has_constraints] from "constraints";
import [Loc] from "loc";
import [Expression, FunctionDef, Module, TypeName] from "model";
import [replace_body_types] from "specialize_functions";
import [rewrite_static_calls] from "specialize_structs";
import [PassState] from "state";
import [replace_expression_types] from "static_blocks";
import [static_type_of, StructTable] from "static_type";
import [parse_type_string, replace_map] from "type_name";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Adds the method specializations that calls name, as
## `generic_methods::specialize_methods` does.
##
## @param module the model
## @param state the passes' state, which takes the first error
## @returns whether any was added
export specialize_methods(module: Module, state: PassState): bool {
    var finder = _GenericMethodCalls(module, state);
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            continue;
        }
        finder.current = Optional<TypeName>.Value(st.ty);
        var methods = st.method_members.copy();
        methods.append_all(st.constructors);
        methods.append(st.destructor);
        for (var m in methods) {
            if (m.body.is_value()) {
                rewrite_block(m.body.value(), finder);
            }
        }
    }
    finder.current = Optional<TypeName>.Empty;
    for (var f in module.functions) {
        if (!f.is_generic_func and f.body.is_value()) {
            rewrite_block(f.body.value(), finder);
        }
    }
    for (var g in module.globals) {
        if (g.default.is_value()) {
            rewrite_expression(g.default.value(), finder);
        }
    }
    # A generic method's constraints are checked before it is cloned.
    bool constrained = has_constraints(module);
    var conformance = Optional<Conformance>.Empty;
    bool added = false;
    for (var (owner, method, loc, args) in finder.wanted) {
        var key = owner.to_string();
        while (key.ends_with("*")) {
            key = key.substr_bytes(0, key.size - 1);
        }
        var index = Optional<ulong>.Empty;
        ulong i = 0;
        while (i < module.structs.count) {
            if (module.structs[i].ty.to_string() == key) {
                index = Optional<ulong>.Value(i);
                break;
            }
            i += 1;
        }
        if (!index.is_value()) {
            continue;
        }
        var st = module.structs[index.value()];
        bool exists = false;
        for (var m in st.method_members) {
            if (m.name == method) {
                exists = true;
                break;
            }
        }
        if (exists) {
            continue;
        }
        var spec = parse_type_string(method);
        var base = Optional<FunctionDef>.Empty;
        for (var m in st.generic_methods) {
            if (m.name == spec.name) {
                base = Optional<FunctionDef>.Value(m);
                break;
            }
        }
        if (!base.is_value()) {
            continue;
        }
        # `s.count_all<int>(it)` for `count_all<T, I>`: the rest come from
        # the arguments first.
        bool missing = false;
        ulong p = spec.sub_types.count;
        while (p < base.value().generic_params.count) {
            if (!base.value().generic_params[p].default.is_value()) {
                missing = true;
            }
            p += 1;
        }
        if (missing) {
            continue;
        }
        if (constrained) {
            if (!conformance.is_value()) {
                conformance = Optional<Conformance>.Value(Conformance(module, state));
            }
            var error = check_method_call(conformance.value(), module, base.value(), spec, loc, args);
            if (error.is_value()) {
                state.report(error.value());
                return false;
            }
        }
        st.method_members.append(_specialize_method(base.value(), spec, state));
        added = true;
    }
    return added;
}

## Finds the calls and values naming a generic method with type arguments.
struct _GenericMethodCalls {
    var module: Module;
    var state: PassState;
    var current: TypeName? = Optional<TypeName>.Empty;
    ## Built on the first call naming a generic method: most runs find none.
    var table: StructTable? = Optional<StructTable>.Empty;
    ## Each call's receiver type and method, where it is, and its arguments.
    var wanted: Array<(TypeName, String, Loc, Expression[])> = Array<(TypeName, String, Loc, Expression[])>();

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            MethodCall(node) => {
                _found(node.this_value, node.method, node.loc, node.args);
            }
            MemberRef(node) => {
                _found(node.lhs, node.name, node.loc, Array<Expression>());
            }
            else => {}
        }
        return e;
    }

    _found(receiver: Expression, method: String, loc: Loc, args: Expression[]) {
        # `<`, `<=` and `<<` are operators, not type arguments.
        if (!method.contains("<") or method.size == 0) {
            return;
        }
        var first = method.bytes()[0];
        if (!((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z') or first == '_' or first >= 128)) {
            return;
        }
        if (!table.is_value()) {
            table = Optional<StructTable>.Value(StructTable(module));
        }
        var owner = static_type_of(receiver, table.value(), current, state);
        if (owner.is_value() and !owner.value().contains_auto()) {
            wanted.append((owner.value(), method, loc, args));
        }
    }
}

extend _GenericMethodCalls with Rewriter;

## `base` with its type parameters replaced by `spec`'s arguments, named
## `spec` (`map<long>`).
_specialize_method(base: FunctionDef, spec: TypeName, state: PassState): FunctionDef {
    var type_map = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < base.generic_params.count) {
        var p = base.generic_params[i];
        if (i < spec.sub_types.count) {
            type_map.append((p.name, spec.sub_types[i]));
        } else if (p.default.is_value()) {
            type_map.append((p.name, p.default.value()));
        }
        i += 1;
    }
    var method = base.copy();
    method.name = spec.to_string();
    method.generic_params = Array<GenericParam>();
    method.is_generic_func = false;
    replace_map(method.ty, type_map);
    for (var p in method.parameters) {
        replace_map(p.ty, type_map);
        if (p.default.is_value()) {
            replace_expression_types(p.default.value(), type_map);
        }
    }
    if (method.body.is_value()) {
        replace_body_types(method.body.value(), type_map);
    }
    rewrite_static_calls(method, type_map, Array<String>(), state);
    return method;
}
