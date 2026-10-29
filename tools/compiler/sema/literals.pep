## Literals: `resolve_literals`, and the conversion `resolve_injected` makes
## of each string literal. `-1` and `-2.5` become literals of their own, and
## each string literal a `String` built from a raw one; `check_string_bytes`
## then rejects such a `String` whose bytes are not UTF-8.

import [unit_decls] from "checked";
import "closures";
import "common";
import [Loc] from "loc";
import [
    CastExpression,
    CastKind,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    Module,
    StringLiteralExpression,
    TypeName,
    UnaryOp
] from "model";
import [PassState] from "state";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Folds each `-<literal>` in function bodies and global initializers into
## a negated literal.
## Parameter defaults are left as written.
##
## @param module the model, changed in place
export resolve_literals(module: Module) {
    var folder = _NegationFolder();
    for (var st in module.structs) {
        for (var method in st.method_members) {
            if (method.body.is_value()) {
                rewrite_block(method.body.value(), folder);
            }
        }
        for (var constructor in st.constructors) {
            if (constructor.body.is_value()) {
                rewrite_block(constructor.body.value(), folder);
            }
        }
        if (st.destructor.body.is_value()) {
            rewrite_block(st.destructor.body.value(), folder);
        }
    }
    for (var function in module.functions) {
        if (function.body.is_value()) {
            rewrite_block(function.body.value(), folder);
        }
    }
    for (var global in module.globals) {
        if (global.default.is_value()) {
            global.default = Optional<Expression>.Value(rewrite_expression(global.default.value(), folder));
        }
    }
}

## Replaces `-<literal>` with the negated literal.
struct _NegationFolder {
    rewrite(e: Expression): Expression {
        if (e is Unary(node)) {
            if (node.op == UnaryOp.Neg) {
                match (node.operand) {
                    IntLiteral(value) => {
                        return Expression.IntLiteral((0 as long).wrapping_sub(value));
                    }
                    FloatLiteral(value) => {
                        return Expression.FloatLiteral(-value);
                    }
                    else => {}
                }
            }
        }
        return e;
    }
}

extend _NegationFolder with Rewriter;

## Returns the expression a decimal literal above `long`'s range stands
## for: its bits, cast to `ulong`.
##
## @param value the literal's value
## @param loc where the literal is
## @returns the cast
export make_unsigned_literal(value: ulong, loc: Loc): Expression {
    var bits = Expression.IntLiteral(unsafe_cast<long>(value));
    return Expression.Cast(CastExpression(bits, TypeName.named("ulong"), loc, CastKind.Synthesized));
}

## Returns `e` as `make_unsigned_literal` made it, or none when it is
## something else.
##
## @param e the expression
## @returns the cast, or none
export unsigned_literal(e: Expression): CastExpression? {
    if (e is Cast(cast)) {
        # Only these synthesized casts to `ulong` are located, and their
        # bits, 2^63 and up, read as a negative `long`.
        if (cast.kind == CastKind.Synthesized and !cast.loc.is_none() and cast.ty.to_string() == "ulong") {
            if (cast.expr is IntLiteral(bits)) {
                if (bits < 0) {
                    return Optional<CastExpression>.Value(cast);
                }
            }
        }
    }
    return Optional<CastExpression>.Empty;
}

## Returns `e` as `resolve_injected` leaves it: a string literal
## that is not raw becomes `String(<raw literal>, size, length)`, located
## at the literal.
##
## @param e the expression
## @returns the expression, converted if it is a string literal
export convert_string_literal(e: Expression): Expression {
    if (e is StringLiteral(literal)) {
        # Raw literals are `__ptr<char>` globals; they stay as they are.
        if (literal.is_raw) {
            return e;
        }
        var raw = Expression.StringLiteral(StringLiteralExpression(literal.value, true, literal.loc));
        var args = [
            raw, Expression.IntLiteral(literal.value.size as long), Expression.IntLiteral(literal.value.length as long)
        ];
        return Expression.FunctionCall(FunctionCallExpression("String", args, literal.loc));
    }
    return e;
}

## Reports each string literal whose bytes are not UTF-8 (written with
## `\x80` to `\xFF`) that is still a `String` once `convert_to_traits` has
## given every literal its slot's type. A `String` always holds UTF-8, so
## such bytes are allowed only in a `StringConstant` or a C string.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_string_bytes(module: Module, state: PassState) {
    # A checked declaration was walked with its unit (its body is stashed).
    var own = unit_decls(module);
    var checker = _StringBytes(state);
    for (var f in own.functions) {
        # A generic function's literals are checked in its specializations.
        if (f.generic_params.count == 0) {
            checker.visit(f);
        }
    }
    for (var st in own.structs) {
        if (_is_generic_base(st)) {
            continue;
        }
        for (var c in st.constructors) {
            checker.visit(c);
        }
        for (var m in st.method_members) {
            checker.visit(m);
        }
        checker.visit(st.destructor);
    }
    for (var g in module.globals) {
        if (g.default.is_value() and !module.checked.globals.contains(g.name)) {
            rewrite_expression(g.default.value(), checker);
        }
    }
}

struct _StringBytes {
    var state: PassState;

    construct(state: PassState) {
        this.state = state;
    }

    visit(f: FunctionDef) {
        if (f.body.is_value()) {
            rewrite_block(f.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        if (e is FunctionCall(call)) {
            if (_is_converted_literal(call)) {
                if (call.args[0] is StringLiteral(literal)) {
                    # A String's `length` is 0 when its bytes are not UTF-8.
                    if (literal.value.size > 0 and literal.value.length == 0) {
                        state.report(
                            error_at(
                                "string literal is not valid UTF-8, so it cannot be a 'String'; store it in a 'StringConstant'",
                                literal.loc
                            )
                        );
                    }
                }
            }
        }
        return e;
    }
}

extend _StringBytes with Rewriter;
