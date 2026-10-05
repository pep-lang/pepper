## Overload calls and values that resolution could not settle:
## `overloads::check_overloads` in Pepper.

import [Diagnostic, Location] from compiler.diagnostic;
import [demangle_name] from compiler.link;
import [for_each_applied_site, SiteVisitor] from "closure_sites";
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [Block, Expression, Module, TypeName, VariableDef] from "model";
import [arg_info, ArgInfo, Failure, has_overloads, Outcome, Overloads] from "overload_select";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";

## Reports the first overload call no member fits or two fit equally, one
## whose argument types stayed unknown, and the first overload set used as
## a value that no expected type picks a member of.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_overloads(module: Module, state: PassState) {
    if (!has_overloads(module)) {
        return;
    }
    var checker = _OverloadChecks(module, state);
    for_each_applied_site(module, state, checker);
}

struct _OverloadChecks {
    var state: PassState;
    var overloads: Overloads;
    var table: StructTable;
    ## `var g = scale;`: no type to pick a member by.
    var untyped: HashMap<Loc, String> = HashMap<Loc, String>();
    var generic_bases: HashSet<String> = HashSet<String>();
    var reported: bool = false;

    construct(module: Module, state: PassState) {
        this.state = state;
        overloads = Overloads(module, state);
        table = StructTable(module);
        for (var g in module.globals) {
            _note_untyped(g, overloads, untyped);
        }
        for (var f in module.functions) {
            _untyped_in(f.body, overloads, untyped);
            if (f.is_generic_func) {
                generic_bases.insert(f.name);
            }
        }
        for (var st in module.structs) {
            for (var m in st.method_members) {
                _untyped_in(m.body, overloads, untyped);
            }
            for (var c in st.constructors) {
                _untyped_in(c.body, overloads, untyped);
            }
            if (st.generic_params.count > 0 and st.name == st.ty.name) {
                generic_bases.insert(st.name);
            }
        }
    }

    visit(owner: String?, e: Expression, expected: TypeName?, current: TypeName?) {
        if (reported or (owner.is_value() and generic_bases.contains(owner.value()))) {
            return;
        }
        match (e) {
            FunctionCall(node) => {
                var (base, explicit) = overloads.call_set(node.function);
                if (!overloads.is_set(base)) {
                    return;
                }
                var infos = infos_of(node.args, current);
                var failure = Optional<Failure>.Empty;
                match (overloads.select(base, explicit, infos, node.loc)) {
                    Failed(f) => {
                        failure = Optional<Failure>.Value(f);
                    }
                    else => {}
                }
                if (!failure.is_value()) {
                    failure = Optional<Failure>.Value(
                        Failure(
                            $"cannot choose an overload of '{demangle_name(base)}': the type of its {_ordinal_text(_first_unknown(infos) + 1)} argument is unknown",
                            overloads.candidate_notes(base, node.loc)
                        )
                    );
                }
                report(failure.value(), node.loc);
            }
            MethodCall(node) => {
                var receiver = static_type_of(node.this_value, table, current, state);
                if (!receiver.is_value() or !overloads.is_method_set(receiver.value(), node.method)) {
                    return;
                }
                var infos = infos_of(node.args, current);
                var failure = Optional<Failure>.Empty;
                match (overloads.select_method(receiver.value(), node.method, infos, node.loc)) {
                    Failed(f) => {
                        failure = Optional<Failure>.Value(f);
                    }
                    else => {}
                }
                if (!failure.is_value()) {
                    failure = Optional<Failure>.Value(
                        Failure(
                            $"cannot choose an overload of '{node.method}': the type of its {_ordinal_text(_first_unknown(infos) + 1)} argument is unknown",
                            overloads.method_candidate_notes(receiver.value(), node.method, node.loc)
                        )
                    );
                }
                report(failure.value(), node.loc);
            }
            MemberRef(node) => {
                var receiver = static_type_of(node.lhs, table, current, state);
                if (!receiver.is_value() or !overloads.is_method_set(receiver.value(), node.name)) {
                    return;
                }
                var spelled = $"{receiver.value().display()}.{node.name}";
                var message = $"reference to overloaded method '{spelled}' could not be resolved";
                var name = untyped.try_get(node.loc);
                if (name.is_value()) {
                    message = $"cannot infer the type of '{name.value()}' from overloaded method '{spelled}'";
                } else if (expected.is_value() and expected.value().is_function_type()) {
                    message = $"address of overloaded method '{spelled}' does not match required type '{expected.value().display()}'";
                }
                report(
                    Failure(message, overloads.method_candidate_notes(receiver.value(), node.name, node.loc)), node.loc
                );
            }
            SymbolRef(node) => {
                if (!node.ty.contains_auto() or !overloads.is_set(node.id)) {
                    return;
                }
                var shown = demangle_name(node.id);
                var message = $"reference to overloaded function '{shown}' could not be resolved";
                var name = untyped.try_get(node.loc);
                if (name.is_value()) {
                    message = $"cannot infer the type of '{name.value()}' from overloaded function '{shown}'";
                } else if (expected.is_value() and expected.value().is_function_type()) {
                    message = $"address of overloaded function '{shown}' does not match required type '{expected.value().display()}'";
                }
                var notes = overloads.candidate_notes(node.id, node.loc);
                if (name.is_value()) {
                    var types = overloads.member_types(node.id, node.loc);
                    var example = types.count > 0 ? types[0].display() : "(...) => ...";
                    notes.append(
                        ($"declare the type, for example 'var {name.value()}: {example} = {shown};'", node.loc)
                    );
                }
                report(Failure(message, notes), node.loc);
            }
            else => {}
        }
    }

    infos_of(args: Expression[], current: TypeName?): Array<ArgInfo> {
        var infos = Array<ArgInfo>();
        for (var arg in args) {
            infos.append(arg_info(arg, overloads, static_type_of(arg, table, current, state)));
        }
        return infos;
    }

    report(failure: Failure, at: Loc) {
        var diagnostic = error_at(failure.message, at);
        for (var (note, where) in failure.notes) {
            diagnostic = diagnostic.with_note(note, Optional<Location>.Value(location_of(where)));
        }
        state.report(diagnostic);
        reported = true;
    }
}

extend _OverloadChecks with SiteVisitor;

_first_unknown(infos: Array<ArgInfo>): ulong {
    ulong i = 0;
    while (i < infos.count) {
        if (infos[i].unknown()) {
            return i;
        }
        i += 1;
    }
    return 0;
}

## A local or global declared without a type and initialized with an
## overloaded name (or any member reference), by the name's location.
_note_untyped(variable: VariableDef, overloads: Overloads, found: HashMap<Loc, String>) {
    if (!variable.default.is_value() or !variable.ty.contains_auto()) {
        return;
    }
    match (variable.default.value()) {
        SymbolRef(node) => {
            if (overloads.is_set(node.id)) {
                found[node.loc] = variable.name;
            }
        }
        # A method set is checked where the value is reported.
        MemberRef(node) => {
            found[node.loc] = variable.name;
        }
        else => {}
    }
}

_untyped_in(body: Block?, overloads: Overloads, found: HashMap<Loc, String>) {
    if (body.is_value()) {
        _untyped_in_block(body.value(), overloads, found);
    }
}

_untyped_in_block(block: Block, overloads: Overloads, found: HashMap<Loc, String>) {
    for (var statement in block.items) {
        match (statement) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    _note_untyped(variable, overloads, found);
                }
            }
            Block(inner) => {
                _untyped_in_block(inner, overloads, found);
            }
            Branch(branch) => {
                _untyped_in_block(branch.if_block, overloads, found);
                if (branch.else_block.is_value()) {
                    _untyped_in_block(branch.else_block.value(), overloads, found);
                }
            }
            While(loop) => {
                _untyped_in_block(loop.block, overloads, found);
            }
            else => {}
        }
    }
}
