## Resolvables: `pepper_sema::passes::resolve_resolvables` in Pepper. Each
## extension finds the struct it extends, and, on the last run, each call
## that names no function, extern or struct is reported.

import [error_at] from "common";
import [Block, Expression, FunctionDef, Module] from "model";
import [PassState] from "state";
import [Rewriter, rewrite_expression] from "walk";

## What resolution needs from the module, taken before it changes.
struct _Known {
    ## Functions, overload sets and overloaded constructors.
    var functions: HashSet<String> = HashSet<String>();
    var externs: HashSet<String> = HashSet<String>();
    var structs: HashSet<String> = HashSet<String>();

    construct(module: Module) {
        for (var f in module.functions) {
            functions.insert(f.name);
        }
        # A call in a generic base naming an overload set resolves in each
        # specialization.
        for (var (set, _) in module.overload_sets) {
            functions.insert(set);
        }
        for (var st in module.structs) {
            # A resolved call to an overloaded constructor (`Point$2`).
            if (st.constructors.count > 1) {
                for (var c in st.constructors) {
                    functions.insert(c.name);
                }
            }
            structs.insert(st.name);
        }
        for (var e in module.externs) {
            externs.insert(e.name);
        }
    }
}

## Resolves each extension's struct and, with `report_missing`, reports
## calls to undeclared functions, as
## `resolve_resolvables::resolve_resolvables` does.
##
## @param module the model, changed in place
## @param report_missing whether to report what does not resolve
## @param state the passes' state, which takes the first error
export resolve_resolvables(module: Module, report_missing: bool, state: PassState) {
    var known = _Known(module);
    for (var ext in module.extensions) {
        if (ext.resolved.is_value()) {
            continue;
        }
        var target = ext.target.to_string();
        # `extend Box<int>` names one specialization: it applies only once
        # that instance exists. `extend Box` / `extend Box<T>` (the struct's
        # own parameters) extend the base.
        bool has_base = false;
        bool extends_base = ext.target.sub_types.count == 0;
        for (var st in module.structs) {
            if (st.name != ext.target.name) {
                continue;
            }
            has_base = true;
            if (!extends_base and st.generic_params.count == ext.target.sub_types.count) {
                extends_base = true;
                ulong i = 0;
                while (i < st.generic_params.count) {
                    var a = ext.target.sub_types[i];
                    if (a.sub_types.count != 0 or a.name != st.generic_params[i].name) {
                        extends_base = false;
                        break;
                    }
                    i += 1;
                }
            }
            break;
        }
        if (known.structs.contains(target)) {
            ext.resolved = Optional<String>.Value(target);
        } else if (extends_base and known.structs.contains(ext.target.name)) {
            ext.resolved = Optional<String>.Value(ext.target.name);
        } else if (has_base and !extends_base) {
            # The specialization is never used: nothing to extend.
        } else if (report_missing) {
            state.report(error_at($"cannot extend unknown struct '{target}'", ext.loc));
        }
    }
    if (!report_missing) {
        # Only reporting reads the calls.
        return;
    }
    for (var function in module.functions) {
        # `T()` in a generic base is a constructor its specializations name,
        # and `f()` on a local whose type depends on `T` is a call through a
        # value its specializations type.
        var type_params = HashSet<String>();
        for (var p in function.generic_params) {
            type_params.insert(p.name);
        }
        if (function.is_generic_func) {
            for (var name in _declared_names(function)) {
                type_params.insert(name);
            }
        }
        _check_calls_in(function, known, type_params, state);
    }
    var none = HashSet<String>();
    for (var global in module.globals) {
        if (global.default.is_value()) {
            rewrite_expression(global.default.value(), _CallChecker(known, none, state));
        }
    }
    for (var st in module.structs) {
        if (st.ty.is_generic()) {
            continue;
        }
        for (var c in st.constructors) {
            _check_calls_in(c, known, none, state);
        }
        for (var m in st.method_members) {
            _check_calls_in(m, known, none, state);
        }
    }
}

_check_calls_in(function: FunctionDef, known: _Known, type_params: HashSet<String>, state: PassState) {
    if (function.body.is_value()) {
        _check_calls_in_block(function.body.value(), _CallChecker(known, type_params, state));
    }
}

## Declarations' initializers are not read: the Rust pass skips them.
_check_calls_in_block(block: Block, checker: _CallChecker) {
    for (var item in block.items) {
        match (item) {
            Expression(e) => {
                rewrite_expression(e, checker);
            }
            Block(inner) => {
                _check_calls_in_block(inner, checker);
            }
            Branch(branch) => {
                rewrite_expression(branch.condition, checker);
                _check_calls_in_block(branch.if_block, checker);
                if (branch.else_block.is_value()) {
                    _check_calls_in_block(branch.else_block.value(), checker);
                }
            }
            While(loop) => {
                rewrite_expression(loop.condition, checker);
                _check_calls_in_block(loop.block, checker);
            }
            Return(r) => {
                if (r.expr.is_value()) {
                    rewrite_expression(r.expr.value(), checker);
                }
            }
            else => {}
        }
    }
}

## Reports each call that names no function, extern or struct.
struct _CallChecker {
    var known: _Known;
    var type_params: HashSet<String>;
    var state: PassState;

    construct(known: _Known, type_params: HashSet<String>, state: PassState) {
        this.known = known;
        this.type_params = type_params;
        this.state = state;
    }

    rewrite(e: Expression): Expression {
        if (e is FunctionCall(call)) {
            var function = call.function;
            var open = function.find("<");
            var base = open < 0 ? function : function.substr_bytes(0, open as ulong);
            bool known_name = known.functions.contains(function)
                or known.externs.contains(function)
                or known.structs.contains(function)
                or known.structs.contains(base);
            # Builtins (`_pep_*`, `trace_*`) and unresolved generic calls are
            # left to later passes.
            bool builtin = function.starts_with("_pep_")
                or function.starts_with("trace_")
                or function == "String"
                or function == "__caller_location"
                or open >= 0
                or type_params.contains(function);
            if (!known_name and !builtin) {
                state.report(error_at($"call to undeclared function '{function}'", call.loc));
            }
        }
        return e;
    }
}

extend _CallChecker with Rewriter;
