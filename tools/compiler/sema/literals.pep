## Literals: `pepper_sema::passes::resolve_literals` and
## `convert_string_literals` in Pepper. `-1` and `-2.5` become literals of
## their own, and each string literal a `String` built from a raw one.

import [Expression, FunctionCallExpression, FunctionDef, Module, StringLiteralExpression, UnaryOp] from "model";
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
                        return Expression.IntLiteral(-value);
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

## Returns `e` as `convert_string_literals` leaves it: a string literal
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

## Converts each string literal of every body, global initializer and
## `String` parameter default.
##
## @param module the model, changed in place
export convert_string_literals(module: Module) {
    var converter = _StringConverter();
    for (var function in module.functions) {
        _convert_function(function, converter);
    }
    for (var global in module.globals) {
        if (global.default.is_value()) {
            global.default = Optional<Expression>.Value(rewrite_expression(global.default.value(), converter));
        }
    }
    for (var st in module.structs) {
        for (var constructor in st.constructors) {
            _convert_function(constructor, converter);
        }
        for (var method in st.method_members) {
            _convert_function(method, converter);
        }
        for (var method in st.generic_methods) {
            _convert_function(method, converter);
        }
    }
    # Trait default bodies: `apply_extensions` copies each into the structs
    # that take it later.
    for (var t in module.traits) {
        for (var method in t.methods) {
            _convert_function(method, converter);
        }
    }
    for (var ext in module.extensions) {
        for (var method in ext.methods) {
            _convert_function(method, converter);
        }
    }
}

## A `String` parameter's literal default is evaluated at each call that
## omits the argument, so it is a `String` like any other literal; other
## parameter types keep theirs.
_convert_function(function: FunctionDef, converter: _StringConverter) {
    for (var p in function.parameters) {
        if (p.ty.to_string() == "String" and p.default.is_value()) {
            p.default = Optional<Expression>.Value(convert_string_literal(p.default.value()));
        }
    }
    if (function.body.is_value()) {
        rewrite_block(function.body.value(), converter);
    }
}

## Converts each string literal a walk meets.
struct _StringConverter {
    rewrite(e: Expression): Expression {
        return convert_string_literal(e);
    }
}

extend _StringConverter with Rewriter;
