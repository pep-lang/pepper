## Generic calls and values whose type arguments nothing gave:
## `type_arguments::check_type_arguments` in Pepper.

import [Diagnostic, Location] from compiler.diagnostic;
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [Expression, FunctionDef, Module, StructDef, TypeName] from "model";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [parse_type_string] from "type_name";
import [Rewriter, rewrite_block] from "walk";

## Reports the first call of a generic function or method whose type
## arguments its arguments did not give, and the first generic function or
## method used as a value without them.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_type_arguments(module: Module, state: PassState) {
    var checker = _TypeArgumentChecks(module, state);
    if (checker.generics.count == 0 and !checker.has_methods) {
        return;
    }
    for (var st in module.structs) {
        if (st.generic_params.count != 0) {
            continue;
        }
        checker.current = Optional<TypeName>.Value(st.ty);
        for (var m in st.method_members) {
            checker.visit(m);
        }
        for (var c in st.constructors) {
            checker.visit(c);
        }
    }
    checker.current = Optional<TypeName>.Empty;
    for (var f in module.functions) {
        if (!f.is_generic_func) {
            checker.visit(f);
        }
    }
}

struct _TypeArgumentChecks {
    var module: Module;
    var state: PassState;
    var generics: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    var has_methods: bool = false;
    var method_names: HashSet<String> = HashSet<String>();
    var statics: StructTable? = Optional<StructTable>.Empty;
    var current: TypeName? = Optional<TypeName>.Empty;

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
        for (var f in module.functions) {
            if (f.is_generic_func) {
                generics[f.name] = f;
            }
        }
        for (var st in module.structs) {
            for (var m in st.generic_methods) {
                has_methods = true;
                method_names.insert(m.name);
            }
        }
    }

    visit(function: FunctionDef) {
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        match (e) {
            SymbolRef(node) => {
                if (node.ty.is_empty() or node.ty.is_auto()) {
                    var base = generics.try_get(node.id);
                    if (base.is_value()) {
                        state.report(
                            error_at(
                                $"cannot infer the type arguments of '{node.id}' used as a value; write them ({node.id}<{_all_params(base.value())}>) or give the value a function type",
                                node.loc
                            ).with_note("declared here", Optional<Location>.Value(location_of(base.value().loc)))
                        );
                    }
                }
            }
            FunctionCall(node) => {
                if (_named(node.function)) {
                    var base = generics.try_get(parse_type_string(node.function).name);
                    if (base.is_value()) {
                        check_call(node.function, node.args, node.loc, base.value());
                    }
                }
            }
            MethodCall(node) => {
                if (has_methods and _named(node.method)) {
                    var name = parse_type_string(node.method).name;
                    if (method_names.contains(name)) {
                        var st = owner_of(node.this_value);
                        if (st.is_value() and !_has_method(st.value(), node.method)) {
                            var base = _generic_method(st.value(), name);
                            if (base.is_value()) {
                                check_call(node.method, node.args, node.loc, base.value());
                            }
                        }
                    }
                }
            }
            MemberRef(node) => {
                if (has_methods and !node.name.contains("<") and method_names.contains(node.name)) {
                    var owner = owner_type(node.lhs);
                    if (owner.is_value()) {
                        var st = _struct_spelled(module, owner.value());
                        if (st.is_value()
                            and !_has_method(st.value(), node.name)
                            and !_has_field(st.value(), node.name)) {
                            var base = _generic_method(st.value(), node.name);
                            if (base.is_value()) {
                                state.report(
                                    error_at(
                                        $"cannot infer the type arguments of method '{node.name}' of '{owner.value().display()}' used as a value; write them ({node.name}<{_all_params(base.value())}>) or give the value a function type",
                                        node.loc
                                    ).with_note(
                                        "declared here", Optional<Location>.Value(location_of(base.value().loc))
                                    )
                                );
                            }
                        }
                    }
                }
            }
            else => {}
        }
        return e;
    }

    owner_type(e: Expression): TypeName? {
        if (!statics.is_value()) {
            statics = Optional<StructTable>.Value(StructTable(module, memo = state.trait_types_memo()));
        }
        return static_type_of(e, statics.value(), current, state);
    }

    owner_of(e: Expression): StructDef? {
        var owner = owner_type(e);
        if (!owner.is_value()) {
            return Optional<StructDef>.Empty;
        }
        return _struct_spelled(module, owner.value());
    }

    check_call(callee: String, args: Expression[], loc: Loc, base: FunctionDef) {
        # An argument naming nothing gives no type to infer from;
        # `resolve_resolvables` reports it as undeclared instead.
        for (var a in args) {
            if (a is SymbolRef(symbol)) {
                if (symbol.ty.is_empty() or symbol.ty.is_auto()) {
                    return;
                }
            }
        }
        var written = parse_type_string(callee);
        var all = _all_params(base);
        var message = "";
        if (written.sub_types.count == 0) {
            message = $"cannot infer the type arguments of '{written.name}' from its arguments; write them: {written.name}<{all}>(...)";
        } else {
            var unbound = Optional<String>.Empty;
            ulong i = written.sub_types.count;
            while (i < base.generic_params.count) {
                if (!base.generic_params[i].default.is_value()) {
                    unbound = Optional<String>.Value(base.generic_params[i].name);
                    break;
                }
                i += 1;
            }
            if (!unbound.is_value()) {
                return;
            }
            message = $"cannot infer the type argument '{unbound.value()}' of '{written.name}' from its arguments; write it: {written.name}<{all}>(...)";
        }
        state.report(
            error_at(message, loc).with_note("declared here", Optional<Location>.Value(location_of(base.loc)))
        );
    }
}

extend _TypeArgumentChecks with Rewriter;

## Whether `callee` starts as a name does: a letter or `_`.
_named(callee: String): bool {
    if (callee.size == 0) {
        return false;
    }
    var b = callee.byte_at(0);
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or b == '_' or b >= 128;
}

_all_params(base: FunctionDef): String {
    var names = Array<String>();
    for (var p in base.generic_params) {
        names.append(p.name);
    }
    return ", ".join(names);
}

## The struct `owner` (or a pointer to it) spells.
_struct_spelled(module: Module, owner: TypeName): StructDef? {
    var key = owner.to_string();
    while (key.ends_with("*")) {
        key = key.substr_bytes(0, key.size - 1);
    }
    for (var st in module.structs) {
        if (st.ty.to_string() == key) {
            return Optional<StructDef>.Value(st);
        }
    }
    return Optional<StructDef>.Empty;
}

_has_method(st: StructDef, name: String): bool {
    for (var m in st.method_members) {
        if (m.name == name) {
            return true;
        }
    }
    return false;
}

_generic_method(st: StructDef, name: String): FunctionDef? {
    for (var m in st.generic_methods) {
        if (m.name == name) {
            return Optional<FunctionDef>.Value(m);
        }
    }
    return Optional<FunctionDef>.Empty;
}
