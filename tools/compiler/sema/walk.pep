## Walks over the sema model's expressions, as `pepper_sema::passes`'
## `rewrite_block`, `rewrite_expression` and `children_mut` do: a `Rewriter` sees
## every expression of a block, before its sub-expressions, and may replace
## it.

import [Block, CasePattern, Declaration, Expression, Statement, StaticItem] from "model";

## What a walk does at each expression.
export trait Rewriter {
    ## Returns what replaces `e`: `e` itself to keep it. The walk goes on
    ## into the sub-expressions of what this returns.
    ##
    ## @param e the expression
    ## @returns the expression to keep
    rewrite(e: Expression): Expression;
}

## Applies `rewriter` to every expression in `block`, in order: each
## statement's, closure bodies' and the statements a `static` block emits.
##
## @param block the block, changed in place
## @param rewriter what to do at each expression
export rewrite_block(block: Block, rewriter: Rewriter) {
    ulong i = 0;
    while (i < block.items.count) {
        block.items[i] = rewrite_statement(block.items[i], rewriter);
        i += 1;
    }
}

## Applies `rewriter` to every expression in `statement`, in order.
##
## @param statement the statement
## @param rewriter what to do at each expression
## @returns the statement, with its expressions replaced
export rewrite_statement(statement: Statement, rewriter: Rewriter): Statement {
    match (statement) {
        Expression(value) => {
            return Statement.Expression(rewrite_expression(value, rewriter));
        }
        Block(value) => {
            rewrite_block(value, rewriter);
        }
        Declaration(value) => {
            if (value is Variable(variable)) {
                if (variable.default.is_value()) {
                    variable.default = Optional<Expression>.Value(
                        rewrite_expression(variable.default.value(), rewriter)
                    );
                }
            }
        }
        Branch(value) => {
            value.condition = rewrite_expression(value.condition, rewriter);
            rewrite_block(value.if_block, rewriter);
            if (value.else_block.is_value()) {
                rewrite_block(value.else_block.value(), rewriter);
            }
        }
        While(value) => {
            value.condition = rewrite_expression(value.condition, rewriter);
            rewrite_block(value.block, rewriter);
        }
        Return(value) => {
            if (value.expr.is_value()) {
                value.expr = Optional<Expression>.Value(rewrite_expression(value.expr.value(), rewriter));
            }
        }
        Static(value) => {
            _rewrite_static_items(value.items, rewriter);
        }
        else => {}
    }
    return statement;
}

_rewrite_static_items(items: StaticItem[], rewriter: Rewriter) {
    ulong i = 0;
    while (i < items.count) {
        match (items[i]) {
            For(node) => {
                _rewrite_static_items(node.body, rewriter);
            }
            While(node) => {
                _rewrite_static_items(node.body, rewriter);
            }
            Block(body) => {
                _rewrite_static_items(body, rewriter);
            }
            If(node) => {
                _rewrite_static_items(node.then_items, rewriter);
                _rewrite_static_items(node.else_items, rewriter);
            }
            EmitIf(node) => {
                node.condition = rewrite_expression(node.condition, rewriter);
                _rewrite_static_items(node.then_items, rewriter);
                _rewrite_static_items(node.else_items, rewriter);
            }
            Emit(statement, span) => {
                items[i] = StaticItem.Emit(rewrite_statement(statement, rewriter), span);
            }
            else => {}
        }
        i += 1;
    }
}

## Applies `rewriter` to `e`, then to every expression inside what it
## returns, a closure's body included.
##
## @param e the expression
## @param rewriter what to do at each expression
## @returns the expression, replaced or with its sub-expressions replaced
export rewrite_expression(e: Expression, rewriter: Rewriter): Expression {
    var out = rewriter.rewrite(e);
    if (out is ClosureLiteral(closure)) {
        rewrite_block(closure.body, rewriter);
        return out;
    }
    return rewrite_children(out, _Walk(rewriter));
}

## Walks each child with its rewriter, for `rewrite_expression`.
struct _Walk {
    var rewriter: Rewriter;

    construct(rewriter: Rewriter) {
        this.rewriter = rewriter;
    }

    rewrite(e: Expression): Expression {
        return rewrite_expression(e, rewriter);
    }
}

extend _Walk with Rewriter;

## Replaces each direct sub-expression of `e` with what `rewriter` returns
## for it, in order. A closure literal's body is a block, not a
## sub-expression; a `match` arm's are its subject and its patterns'
## literals.
##
## @param e the expression
## @param rewriter what replaces each child
## @returns `e`, or a new expression when `e` holds its children by value
export rewrite_children(e: Expression, rewriter: Rewriter): Expression {
    match (e) {
        StaticMember(node) => {
            _map_all(node.args, rewriter);
        }
        MemberRef(node) => {
            node.lhs = rewriter.rewrite(node.lhs);
        }
        Binary(node) => {
            node.lhs = rewriter.rewrite(node.lhs);
            node.rhs = rewriter.rewrite(node.rhs);
        }
        Index(node) => {
            node.lhs = rewriter.rewrite(node.lhs);
            node.rhs = rewriter.rewrite(node.rhs);
        }
        ArrayIndex(node) => {
            node.lhs = rewriter.rewrite(node.lhs);
            node.rhs = rewriter.rewrite(node.rhs);
        }
        Unary(node) => {
            node.operand = rewriter.rewrite(node.operand);
        }
        Cast(node) => {
            node.expr = rewriter.rewrite(node.expr);
        }
        Ternary(node) => {
            node.condition = rewriter.rewrite(node.condition);
            node.true_expr = rewriter.rewrite(node.true_expr);
            node.false_expr = rewriter.rewrite(node.false_expr);
        }
        RefCount(ty, value) => {
            return Expression.RefCount(ty, rewriter.rewrite(value));
        }
        Address(ty, value) => {
            return Expression.Address(ty, rewriter.rewrite(value));
        }
        Weak(op, ty, value) => {
            return Expression.Weak(op, ty, rewriter.rewrite(value));
        }
        AtomicLoad(ty, value) => {
            return Expression.AtomicLoad(ty, rewriter.rewrite(value));
        }
        ForIterator(value) => {
            return Expression.ForIterator(rewriter.rewrite(value));
        }
        WithEntered(value) => {
            return Expression.WithEntered(rewriter.rewrite(value));
        }
        MatchArm(test) => {
            test.subject = rewriter.rewrite(test.subject);
            for (var pattern in test.patterns) {
                _map_literals(pattern, rewriter);
            }
        }
        CaseValue(value) => {
            value.subject = rewriter.rewrite(value.subject);
        }
        WithSubject(subject) => {
            subject.subject = rewriter.rewrite(subject.subject);
            subject.body = rewriter.rewrite(subject.body);
        }
        AtomicStore(ty, pointer, value) => {
            var p = rewriter.rewrite(pointer);
            return Expression.AtomicStore(ty, p, rewriter.rewrite(value));
        }
        AtomicFetch(op, ty, pointer, value) => {
            var p = rewriter.rewrite(pointer);
            return Expression.AtomicFetch(op, ty, p, rewriter.rewrite(value));
        }
        ConstructAt(pointer, value) => {
            var p = rewriter.rewrite(pointer);
            return Expression.ConstructAt(p, rewriter.rewrite(value));
        }
        AtomicCmpXchg(ty, pointer, expected, desired) => {
            var p = rewriter.rewrite(pointer);
            var x = rewriter.rewrite(expected);
            return Expression.AtomicCmpXchg(ty, p, x, rewriter.rewrite(desired));
        }
        FunctionCall(node) => {
            _map_all(node.args, rewriter);
        }
        Simd(node) => {
            _map_all(node.args, rewriter);
        }
        MethodCall(node) => {
            node.this_value = rewriter.rewrite(node.this_value);
            _map_all(node.args, rewriter);
        }
        Invoke(node) => {
            node.callee = rewriter.rewrite(node.callee);
            _map_all(node.args, rewriter);
        }
        CallPointer(node) => {
            node.pointer = rewriter.rewrite(node.pointer);
            _map_all(node.args, rewriter);
        }
        MakeClosure(node) => {
            node.value = rewriter.rewrite(node.value);
        }
        ToTrait(node) => {
            node.value = rewriter.rewrite(node.value);
        }
        FromTrait(node) => {
            node.value = rewriter.rewrite(node.value);
        }
        Destructure(node) => {
            node.value = rewriter.rewrite(node.value);
        }
        Move(node) => {
            node.value = rewriter.rewrite(node.value);
        }
        NamedArgument(node) => {
            node.value = rewriter.rewrite(node.value);
        }
        else => {}
    }
    return e;
}

_map_all(items: Expression[], rewriter: Rewriter) {
    ulong i = 0;
    while (i < items.count) {
        items[i] = rewriter.rewrite(items[i]);
        i += 1;
    }
}

## Replaces the literal tests of `pattern` and the patterns nested in it.
_map_literals(pattern: CasePattern, rewriter: Rewriter) {
    if (pattern.literal.is_value()) {
        pattern.literal = Optional<Expression>.Value(rewriter.rewrite(pattern.literal.value()));
    }
    if (pattern.elements.is_value()) {
        for (var element in pattern.elements.value()) {
            _map_literals(element, rewriter);
        }
    }
    if (pattern.bindings.is_value()) {
        for (var binding in pattern.bindings.value()) {
            _map_literals(binding, rewriter);
        }
    }
}
