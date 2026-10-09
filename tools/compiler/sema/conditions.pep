## Struct values left in a boolean context: `unary_operators::
## check_conditions` in Pepper.

import [Location] from compiler.diagnostic;
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [BinaryOp, Block, Expression, FunctionDef, Module, TypeName, UnaryOp] from "model";
import [PassState] from "state";
import "static_blocks";
import [StructTable] from "static_type";
import "unary_operators";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Reports the first struct or trait value still in a boolean context (an
## `if` or `while` condition, a ternary's, an operand of `!`, `&&` or
## `||`) whose type declares no `!!`: a struct is never null-tested
## implicitly. Function types, weak references and closures are
## synthesized (`__…`) and keep their null test.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_conditions(module: Module, state: PassState) {
    var checker = _Conditions(module, state);
    for (var st in module.structs) {
        # Generic bases are checked in their specializations.
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
    for (var g in module.globals) {
        if (g.default.is_value()) {
            rewrite_expression(g.default.value(), checker);
        }
    }
}

struct _Conditions {
    var table: StructTable;
    var state: PassState;
    var declared_at: HashMap<String, Loc> = HashMap<String, Loc>();
    var current: TypeName? = Optional<TypeName>.Empty;

    construct(module: Module, state: PassState) {
        this.state = state;
        table = StructTable(module, memo = state.trait_types_memo());
        for (var st in module.structs) {
            if (st.ty.name.starts_with("__")) {
                continue;
            }
            declared_at[st.ty.to_string()] = st.loc;
            if (!declared_at.contains(st.ty.name)) {
                declared_at[st.ty.name] = st.loc;
            }
        }
        for (var t in module.traits) {
            if (!declared_at.contains(t.name)) {
                declared_at[t.name] = t.loc;
            }
        }
    }

    visit(function: FunctionDef) {
        if (function.body.is_value()) {
            var body = function.body.value();
            statement_conditions(body);
            rewrite_block(body, this);
        }
    }

    ## The condition of every `if` and `while`, nested blocks included. A
    ## `with` block's condition is its own.
    statement_conditions(block: Block) {
        for (var statement in block.items) {
            match (statement) {
                Block(inner) => {
                    statement_conditions(inner);
                }
                Branch(branch) => {
                    if (!(branch.condition is WithEntered(_))) {
                        check(branch.condition);
                    }
                    statement_conditions(branch.if_block);
                    if (branch.else_block.is_value()) {
                        statement_conditions(branch.else_block.value());
                    }
                }
                While(loop) => {
                    check(loop.condition);
                    statement_conditions(loop.block);
                }
                else => {}
            }
        }
    }

    rewrite(e: Expression): Expression {
        match (e) {
            Unary(node) => {
                if (node.op == UnaryOp.LogicalNot) {
                    check(node.operand);
                }
            }
            Ternary(node) => {
                check(node.condition);
            }
            Binary(node) => {
                if (node.op == BinaryOp.LogicalAnd or node.op == BinaryOp.LogicalOr) {
                    check(node.lhs);
                    check(node.rhs);
                }
            }
            else => {}
        }
        return e;
    }

    check(e: Expression) {
        var ty = _operand_type(e, table, current, state);
        if (!ty.is_value()) {
            return;
        }
        var spelled = ty.value().to_string();
        var at = spelled.find("<");
        var base = at < 0 ? spelled : spelled.substr_bytes(0, at as ulong);
        var declared = declared_at.try_get(spelled);
        if (!declared.is_value()) {
            declared = declared_at.try_get(base);
        }
        if (!declared.is_value()) {
            return;
        }
        var info = table.lookup(ty.value());
        if (info.is_value() and info.value().unary_operators.contains(_TRUTH_TEST)) {
            return;
        }
        state.report(
            error_at(
                $"'{ty.value().display()}' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'",
                _expression_loc(e)
            ).with_note($"'{base}' declared here", Optional<Location>.Value(location_of(declared.value())))
        );
    }
}

extend _Conditions with Rewriter;
