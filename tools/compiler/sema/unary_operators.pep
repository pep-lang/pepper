## Unary operators and truth tests on structs:
## `pepper_sema::passes::unary_operators` in Pepper. A struct may declare
## `-()`, `~()`, `!()` and the truth test `!!()` as instance methods without
## parameters; `-x`, `~x` and `!x` on such a struct become zero-argument
## method calls named after the operator, and a struct value in a boolean
## context (an `if`/`while` condition, a ternary condition, an operand of
## `and`/`or`, the operand of `!`) becomes `x.!!()`.

import [Loc] from "loc";
import [BinaryOp, Block, Expression, MethodCallExpression, TypeName, UnaryOp] from "model";
import [op_name] from "operators";
import "resolve_operators";
import [PassState] from "state";
import "static_blocks";
import [static_type_of, StructInfo, StructTable] from "static_type";
import [Rewriter, rewrite_block] from "walk";

## The truth-test operator.
const _TRUTH_TEST = "!!";

## Rewrites the unary operators and truth tests on structs in `body` into
## method calls, as `unary_operators::dispatch` does. The call names the
## operator (`-`), so an overload set holding both a unary and a binary `-`
## resolves to the member by its arity.
##
## @param body the body, changed in place
## @param table the structs
## @param current the struct whose method `body` is
## @param state the passes' state
export dispatch_unary(body: Block, table: StructTable, current: TypeName?, state: PassState) {
    var dispatch = _UnaryDispatch(table, current, state);
    dispatch.conditions(body);
    rewrite_block(body, dispatch);
}

struct _UnaryDispatch {
    var table: StructTable;
    var current: TypeName?;
    var state: PassState;

    construct(table: StructTable, current: TypeName?, state: PassState) {
        this.table = table;
        this.current = current;
        this.state = state;
    }

    ## Applies the truth test to the condition of every `if` and `while`,
    ## nested blocks included; a `with` block's condition is its own.
    conditions(block: Block) {
        for (var statement in block.items) {
            match (statement) {
                Block(inner) => {
                    conditions(inner);
                }
                Branch(branch) => {
                    if (!(branch.condition is WithEntered(_))) {
                        branch.condition = truth_test(branch.condition);
                    }
                    conditions(branch.if_block);
                    if (branch.else_block.is_value()) {
                        conditions(branch.else_block.value());
                    }
                }
                While(node) => {
                    node.condition = truth_test(node.condition);
                    conditions(node.block);
                }
                else => {}
            }
        }
    }

    ## `e.!!()` when `e`'s struct declares the truth test, else `e`.
    truth_test(e: Expression): Expression {
        if (_declares(e, _TRUTH_TEST)) {
            return _operator_method_call(e, _TRUTH_TEST, _expression_loc(e));
        }
        return e;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            Unary(node) => {
                var name = "";
                match (node.op) {
                    Neg => {
                        name = "-";
                    }
                    BitNot => {
                        name = "~";
                    }
                    LogicalNot => {
                        name = "!";
                    }
                    else => {}
                }
                if (name.is_empty) {
                    return e;
                }
                # An enum declaring the operator: `-a` is `E::-(a)`.
                var ty = static_type_of(node.operand, table, current, state);
                if (ty.is_value() and _declares_enum_operator(state, ty.value(), name)) {
                    return _enum_operator_call(ty.value(), name, [node.operand], node.loc);
                }
                if (name != "!") {
                    if (_declares(node.operand, name)) {
                        return _operator_method_call(node.operand, name, node.loc);
                    }
                    return e;
                }
                # `!!x` is the truth test itself.
                if (node.operand is Unary(inner)) {
                    if (inner.op == UnaryOp.LogicalNot and _declares(inner.operand, _TRUTH_TEST)) {
                        return _operator_method_call(inner.operand, _TRUTH_TEST, node.loc);
                    }
                }
                if (_declares(node.operand, "!")) {
                    return _operator_method_call(node.operand, "!", node.loc);
                }
                node.operand = truth_test(node.operand);
            }
            Ternary(node) => {
                node.condition = truth_test(node.condition);
            }
            Binary(node) => {
                if (node.op == BinaryOp.LogicalAnd or node.op == BinaryOp.LogicalOr) {
                    # A struct declaring `and` or `or` takes the whole
                    # operation.
                    var info = _struct_of(node.lhs);
                    if (!(info.is_value() and info.value().methods.contains(op_name(node.op)))) {
                        node.lhs = truth_test(node.lhs);
                        node.rhs = truth_test(node.rhs);
                    }
                }
            }
            else => {}
        }
        return e;
    }

    ## Whether `e` is a struct value whose struct declares the unary `op`.
    _declares(e: Expression, op: String): bool {
        var info = _struct_of(e);
        return info.is_value() and info.value().unary_operators.contains(op);
    }

    ## The struct (or trait) of `e`'s static type.
    _struct_of(e: Expression): StructInfo? {
        var ty = _operand_type(e, table, current, state);
        return ty.is_value() ? table.lookup(ty.value()) : Optional<StructInfo>.Empty;
    }
}

extend _UnaryDispatch with Rewriter;

## The static type of `e`; a bare field in a method (not yet `this.f`)
## types from the enclosing struct.
_operand_type(e: Expression, table: StructTable, current: TypeName?, state: PassState): TypeName? {
    var ty = static_type_of(e, table, current, state);
    if (ty.is_value() or !current.is_value()) {
        return ty;
    }
    if (e is SymbolRef(node)) {
        var info = table.lookup(current.value());
        if (info.is_value()) {
            return info.value().field(node.id);
        }
    }
    return Optional<TypeName>.Empty;
}

## `this.op()`, located at the operator use.
_operator_method_call(this_value: Expression, op: String, loc: Loc): Expression {
    return Expression.MethodCall(MethodCallExpression(this_value, op, Array<Expression>(), loc));
}
