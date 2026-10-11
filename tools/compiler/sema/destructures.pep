## Tuple destructures and element references: `lower_destructures`.

import "closures";
import [error_at] from "common";
import [Expression, FunctionDef, Module, TypeName] from "model";
import [PassState] from "state";
import [StructTable, static_type_of] from "static_type";
import "type_name";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Replaces each `Destructure` with the tuple it reads, reporting one that
## isn't a tuple or has a different number of elements; renames each
## labelled element reference (`t.line`) to its position; and reports an
## assignment to a tuple element. A tuple's own constructor is what sets
## its elements, so tuple structs are skipped.
##
## @param module the model, changed in place
## @param state the passes' state, which takes the error
export lower_destructures(module: Module, state: PassState) {
    var lowering = _Destructures(module, state);
    for (var st in module.structs) {
        if (st.ty.is_tuple()) {
            continue;
        }
        lowering.current = Optional<TypeName>.Value(st.ty);
        for (var m in st.method_members) {
            lowering.visit(m);
        }
        for (var c in st.constructors) {
            lowering.visit(c);
        }
        lowering.visit(st.destructor);
    }
    lowering.current = Optional<TypeName>.Empty;
    for (var f in module.functions) {
        lowering.visit(f);
    }
    for (var g in module.globals) {
        if (g.default.is_value()) {
            g.default = Optional<Expression>.Value(rewrite_expression(g.default.value(), lowering));
        }
    }
}

struct _Destructures {
    var table: StructTable;
    var state: PassState;
    var current: TypeName? = Optional<TypeName>.Empty;

    construct(module: Module, state: PassState) {
        this.state = state;
        table = StructTable(module, memo = state.trait_types_memo());
    }

    visit(function: FunctionDef) {
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        match (e) {
            Destructure(node) => {
                var ty = static_type_of(node.value, table, current, state);
                if (ty.is_value()) {
                    var t = ty.value();
                    if (!t.is_tuple()) {
                        state.report(error_at($"cannot destructure '{t.display()}': it is not a tuple", node.loc));
                    } else if (t.sub_types.count != node.count) {
                        var noun = node.count == 1 ? "value" : "values";
                        state.report(
                            error_at(
                                $"cannot destructure '{t.display()}' into {node.count} {noun}: it has {t.sub_types.count} elements",
                                node.loc
                            )
                        );
                    }
                }
                return node.value;
            }
            MemberRef(node) => {
                var ty = static_type_of(node.lhs, table, current, state);
                if (ty.is_value() and ty.value().is_tuple()) {
                    var t = ty.value();
                    # A label (`t.line`) names its position from here on.
                    var index = t.tuple_index(node.name);
                    if (index.is_value()) {
                        node.name = $"{index.value()}";
                    } else {
                        state.report(
                            error_at(
                                $"no member named '{node.name}' in '{t.display()}': its elements are '0' to '{t.sub_types.count - 1}'",
                                node.loc
                            )
                        );
                    }
                }
            }
            Binary(node) => {
                if (_is_assignment(node.op)) {
                    if (node.lhs is MemberRef(target)) {
                        var ty = static_type_of(target.lhs, table, current, state);
                        if (ty.is_value() and ty.value().tuple_element(target.name).is_value()) {
                            state.report(
                                error_at(
                                    $"cannot assign to element {target.name} of tuple '{ty.value().display()}': tuple elements are immutable",
                                    target.loc
                                )
                            );
                        }
                    }
                }
            }
            else => {}
        }
        return e;
    }
}

extend _Destructures with Rewriter;
