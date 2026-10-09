## Assignments whose target is still a call: `resolve_operators::
## check_assignment_targets` in Pepper.

import [Diagnostic, Location] from compiler.diagnostic;
import "closures";
import [error_at] from "common";
import [method_of] from "enums";
import [Loc] from "loc";
import [Block, Expression, FunctionDef, Module, TypeName] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [Rewriter, rewrite_block] from "walk";

## Reports the first assignment whose target is a call once the last
## operator resolution has run: `get() = v`, or `x[i] = v` where `x`'s
## type has a `[]` getter but no setter (the index became an
## `__index_get` call). Code generation has no place to store into.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_assignment_targets(module: Module, state: PassState) {
    var checker = _AssignmentTargets(StructTable(module, memo = state.trait_types_memo()), state);
    for (var st in module.structs) {
        if (st.ty.is_generic() and st.name == st.ty.name) {
            continue;
        }
        checker.current = Optional<TypeName>.Value(st.ty);
        for (var c in st.constructors) {
            checker.visit(c);
        }
        for (var m in st.method_members) {
            checker.visit(m);
        }
    }
    checker.current = Optional<TypeName>.Empty;
    for (var f in module.functions) {
        checker.visit(f);
    }
}

struct _AssignmentTargets {
    var table: StructTable;
    var state: PassState;
    var current: TypeName? = Optional<TypeName>.Empty;

    construct(table: StructTable, state: PassState) {
        this.table = table;
        this.state = state;
    }

    visit(function: FunctionDef) {
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        if (e is Binary(node)) {
            if (_is_assignment(node.op)) {
                var error = unassignable(node.lhs);
                if (error.is_value()) {
                    state.report(error.value());
                }
            }
        }
        return e;
    }

    ## The error for assigning to `target`, when it is a call.
    unassignable(target: Expression): Diagnostic? {
        var receiver = Optional<TypeName>.Empty;
        var name = "";
        var loc = Loc.none();
        match (target) {
            MethodCall(node) => {
                receiver = static_type_of(node.this_value, table, current, state);
                name = node.method;
                loc = node.loc;
            }
            FunctionCall(node) => {
                name = node.function;
                loc = node.loc;
                var enum_method = method_of(state, node.function);
                if (enum_method.is_value()) {
                    var (_, method) = enum_method.value();
                    name = method;
                    if (node.args.count > 0) {
                        receiver = static_type_of(node.args[0], table, current, state);
                    }
                }
            }
            else => {
                return Optional<Diagnostic>.Empty;
            }
        }
        if (set_name(name) == "__index_get") {
            var shown = receiver.is_value() ?
                $": '{receiver.value().to_string()}' declares a '[]' getter but no setter" :
                "";
            return Optional<Diagnostic>.Value(
                error_at(
                    $"cannot assign through '[]'{shown}", loc
                ).with_note("declare '[](index, value)' to allow assignment", Optional<Location>.Empty)
            );
        }
        return Optional<Diagnostic>.Value(error_at("expression is not assignable", loc));
    }
}

extend _AssignmentTargets with Rewriter;
