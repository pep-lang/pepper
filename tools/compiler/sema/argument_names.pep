## Named arguments left unbound, and the parameter names of literal
## arguments: `check_unbound` and `record_argument_names`.

import [error_at] from "common";
import [Loc] from "loc";
import [Expression, FunctionDef, Module, StructDef, TypeName] from "model";
import [Callee] from "named_arguments";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [Rewriter, rewrite_block] from "walk";

## Reports a call whose arguments are still named once binding is done:
## one whose callee takes no names (a function value, say).
##
## @param module the model
## @param state the passes' state, which takes the error
export check_unbound(module: Module, state: PassState) {
    var finder = _UnboundNames(state);
    for (var f in module.functions) {
        if (!f.is_generic_func) {
            finder.visit(f);
        }
    }
    for (var st in module.structs) {
        if (st.generic_params.count == 0 or st.name.contains("<")) {
            for (var c in st.constructors) {
                finder.visit(c);
            }
            for (var m in st.method_members) {
                finder.visit(m);
            }
        }
    }
}

struct _UnboundNames {
    var state: PassState;

    construct(state: PassState) {
        this.state = state;
    }

    visit(function: FunctionDef) {
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionCall(node) => {
                report(node.args);
            }
            MethodCall(node) => {
                report(node.args);
            }
            Invoke(node) => {
                report(node.args);
            }
            else => {}
        }
        return e;
    }

    report(args: Expression[]) {
        if (_has_named(args)) {
            state.report(error_at("cannot name the arguments of this call", _first_named(args)));
        }
    }
}

extend _UnboundNames with Rewriter;

## Records the parameter each literal argument passed by position fills
## (`Module.argument_names`), for the language server's inlay hints. Calls
## to a function of one parameter are left out: its name adds nothing.
##
## @param module the model, changed in place
## @param state the passes' state
export record_argument_names(module: Module, state: PassState) {
    var literals = HashMap<Loc, Array<(ulong, Loc)>>();
    for (var (call, index, at) in module.literal_args) {
        if (!literals.contains(call)) {
            literals[call] = Array<(ulong, Loc)>();
        }
        literals[call].append((index, at));
    }
    if (literals.count == 0) {
        return;
    }
    var recorder = _ArgumentNames(module, state, literals);
    for (var f in module.functions) {
        if (!f.is_generic_func) {
            recorder.visit(f, Optional<TypeName>.Empty);
        }
    }
    for (var st in module.structs) {
        if (st.generic_params.count != 0 and !st.name.contains("<")) {
            continue;
        }
        var current = Optional<TypeName>.Value(st.ty);
        for (var c in st.constructors) {
            recorder.visit(c, current);
        }
        for (var m in st.method_members) {
            recorder.visit(m, current);
        }
    }
    var found = recorder.found;
    found.sort((a: (Loc, String), b: (Loc, String)) => {
        var (x, _) = a;
        var (y, _) = b;
        if (x.file != y.file) {
            return x.file < y.file ? -1 : 1;
        }
        return x.span.start < y.span.start ? -1 : (x.span.start > y.span.start ? 1 : 0);
    });
    # Drop consecutive repeats.
    var kept = Array<(Loc, String)>();
    for (var (at, name) in found) {
        if (kept.count > 0) {
            var (last_at, last_name) = kept[kept.count - 1];
            if (last_at == at and last_name == name) {
                continue;
            }
        }
        kept.append((at, name));
    }
    module.argument_names = kept;
}

struct _ArgumentNames {
    var module: Module;
    var state: PassState;
    var literals: HashMap<Loc, Array<(ulong, Loc)>>;
    var table: StructTable;
    var current: TypeName? = Optional<TypeName>.Empty;
    var found: Array<(Loc, String)> = Array<(Loc, String)>();

    construct(module: Module, state: PassState, literals: HashMap<Loc, Array<(ulong, Loc)>>) {
        this.module = module;
        this.state = state;
        this.literals = literals;
        table = StructTable(module, memo = state.trait_types_memo());
    }

    visit(function: FunctionDef, current: TypeName?) {
        this.current = current;
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionCall(node) => {
                if (literals.contains(node.loc)) {
                    var names = function_parameters(node.function);
                    if (names.is_value()) {
                        record(names.value(), node.loc);
                    }
                }
            }
            MethodCall(node) => {
                if (literals.contains(node.loc)) {
                    var receiver = static_type_of(node.this_value, table, current, state);
                    if (receiver.is_value()) {
                        var spelled = receiver.value().to_string();
                        for (var st in module.structs) {
                            if (st.ty.to_string() != spelled) {
                                continue;
                            }
                            for (var m in st.method_members) {
                                if (m.name == node.method) {
                                    record(_parameter_names(m), node.loc);
                                    break;
                                }
                            }
                            break;
                        }
                    }
                }
            }
            else => {}
        }
        return e;
    }

    ## The parameter names of the function, constructor or extern `name`.
    function_parameters(name: String): String[]? {
        for (var f in module.functions) {
            if (f.name == name) {
                return Optional<String[]>.Value(_parameter_names(f));
            }
        }
        var constructor = _constructor_of(module, name);
        if (constructor.is_value()) {
            return Optional<String[]>.Value(_parameter_names(constructor.value()));
        }
        for (var x in module.externs) {
            if (x.name == name) {
                var names = Array<String>();
                for (var p in x.parameters) {
                    names.append(p.name);
                }
                return Optional<String[]>.Value(names);
            }
        }
        return Optional<String[]>.Empty;
    }

    record(names: String[], call: Loc) {
        if (names.count < 2) {
            return;
        }
        for (var (index, at) in literals[call]) {
            if (index < names.count) {
                found.append((at, names[index]));
            }
        }
    }
}

extend _ArgumentNames with Rewriter;

_parameter_names(function: FunctionDef): String[] {
    ulong skip = function.parameters.count > 0 and function.parameters[0].name == "this" ? 1 : 0;
    var names = Array<String>();
    for (var p in Callee.of(function, function.name, skip, Array<String>()).params) {
        names.append(p.name);
    }
    return names;
}

## The constructor a call of `function` names: the one of that name of the
## struct its set name spells, else the struct's only constructor.
_constructor_of(module: Module, function: String): FunctionDef? {
    var ty = set_name(function);
    for (var st in module.structs) {
        if (st.name != ty and st.ty.to_string() != ty) {
            continue;
        }
        for (var c in st.constructors) {
            if (c.name == function) {
                return Optional<FunctionDef>.Value(c);
            }
        }
        if (st.constructors.count == 1) {
            return Optional<FunctionDef>.Value(st.constructors[0]);
        }
        return Optional<FunctionDef>.Empty;
    }
    return Optional<FunctionDef>.Empty;
}
