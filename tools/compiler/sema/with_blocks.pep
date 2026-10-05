## Finishes lowering `with` blocks once types are known:
## `passes::lower_with_blocks` in Pepper. The builder leaves
##
##     var x = __with_scope_N.enter();
##     if (<WithEntered(x)>) { body } else { other }
##
## and this pass picks by `enter()`'s type: for a struct or pointer,
## `if (!(x === null))`, so a null result skips the body; for `void`, the
## hidden value becomes an expression statement and the body runs
## unconditionally; for any other type, the body runs unconditionally. It
## also reports binding a `void` result, `else` on a result that can never
## be null, and assigning to the binding.

import [Location] from compiler.diagnostic;
import [location_of] from "common";
import [Loc] from "loc";
import [
    BinaryExpression,
    BinaryOp,
    Block,
    Expression,
    Module,
    Statement,
    SymbolRefExpression,
    TypeName,
    UnaryExpression,
    UnaryOp
] from "model";
import [PassState] from "state";
import [trait_def] from "traits";
import [VOID] from "type_name";
import [Rewriter, rewrite_statement] from "walk";

## Lowers every `with` block in the bodies codegen sees, and reports the
## first error.
##
## @param module the model
## @param state the passes' state, which takes the error
export lower_with_blocks(module: Module, state: PassState) {
    var types = _WithTypes(module);
    for (var st in module.structs) {
        # Generic bases never reach codegen; their `enter()` types are
        # still template parameters.
        if (_is_generic_base(st)) {
            continue;
        }
        for (var m in st.method_members) {
            _lower_function_body(m.body, types, state);
        }
        for (var c in st.constructors) {
            _lower_function_body(c.body, types, state);
        }
        _lower_function_body(st.destructor.body, types, state);
    }
    for (var f in module.functions) {
        if (!f.is_generic_func) {
            _lower_function_body(f.body, types, state);
        }
    }
}

struct _WithTypes {
    var module: Module;
    ## Every concrete struct name (function types included): nullable.
    var structs: HashSet<String> = HashSet<String>();
    ## Struct name → what its `enter()` returns.
    var enter_types: HashMap<String, TypeName> = HashMap<String, TypeName>();

    construct(module: Module) {
        this.module = module;
        for (var st in module.structs) {
            structs.insert(st.name);
            if (!enter_types.contains(st.name)) {
                for (var m in st.method_members) {
                    if (m.name == "enter") {
                        enter_types[st.name] = m.ty;
                        break;
                    }
                }
            }
        }
    }

    nullable(ty: TypeName): bool {
        return ty.is_pointer() or structs.contains(ty.to_string()) or trait_def(module.traits, ty).is_value();
    }
}

_lower_function_body(body: Block?, types: _WithTypes, state: PassState) {
    if (body.is_value()) {
        _lower_with_block(body.value(), types, state);
    }
}

_lower_with_block(block: Block, types: _WithTypes, state: PassState) {
    for (var statement in block.items) {
        match (statement) {
            Block(inner) => {
                _lower_with_block(inner, types, state);
            }
            Branch(branch) => {
                _lower_with_block(branch.if_block, types, state);
                if (branch.else_block.is_value()) {
                    _lower_with_block(branch.else_block.value(), types, state);
                }
            }
            While(loop) => {
                _lower_with_block(loop.block, types, state);
            }
            else => {}
        }
    }
    # A lowered `with` is a block of [scope, value, Branch(WithEntered)].
    if (block.items.count != 3) {
        return;
    }
    var found_scope = _variable_at(block, 0);
    var found_value = _variable_at(block, 1);
    var found_branch = _branch_at(block, 2);
    if (!found_scope.is_value() or !found_value.is_value() or !found_branch.is_value()) {
        return;
    }
    var scope = found_scope.value();
    var value = found_value.value();
    var branch = found_branch.value();
    if (!_is_with_entered(branch.condition)) {
        return;
    }
    var scope_type = scope.ty.to_string();
    if (types.structs.contains(scope_type) and !types.enter_types.contains(scope_type)) {
        state.report(
            _error_at_known(
                $"'{scope_type}' cannot be used in a 'with' block: it has no 'enter()' method", scope.loc
            ).with_note("a 'with' scope implements Scoped<T>: 'T enter()' and 'exit()'", Optional<Location>.Empty)
        );
        return;
    }
    var hidden = value.hidden;
    # Inference leaves a local initialized from a `void` call untyped: ask
    # the scope's struct what `enter()` returns. A method declared without
    # a return type returns nothing.
    var ty = value.ty;
    if (ty.is_auto()) {
        var returns = types.enter_types.try_get(scope_type);
        if (returns.is_value()) {
            ty = returns.value().is_auto() ? TypeName.void() : returns.value();
        }
    }
    var at = value.loc;
    var name = value.name;
    if (ty.is_auto()) {
        state.report(_error_at_known("cannot determine the type 'enter()' returns in this 'with' block", at));
        return;
    }
    var is_void = ty.to_string() == VOID;
    if (is_void and !hidden) {
        state.report(
            _error_at_known(
                $"cannot bind '{name}': 'enter()' returns 'void'", at
            ).with_note("remove the binding: 'with (scope) { ... }'", Optional<Location>.Empty)
        );
        return;
    }
    if (!hidden) {
        var assignment = _assignment_to(branch.if_block, name);
        if (assignment.is_value()) {
            state.report(
                _error_at_known(
                    $"cannot assign to '{name}': it is bound by a 'with' block", assignment.value()
                ).with_note($"'{name}' is bound here", Optional<Location>.Value(location_of(at)))
            );
            return;
        }
    }
    if (types.nullable(ty)) {
        var identical = BinaryExpression(
            Expression.SymbolRef(SymbolRefExpression(name, ty, at)), Expression.PointerLiteral, BinaryOp.Identical, at
        );
        branch.condition = Expression.Unary(UnaryExpression(Expression.Binary(identical), UnaryOp.LogicalNot, at));
        return;
    }
    if (branch.else_block.is_value()) {
        state.report(
            _error_at_known(
                $"'else' requires 'enter()' to return a struct reference, but it returns '{ty.to_string()}'", at
            )
        );
        return;
    }
    # Never skipped: the body runs as a plain block.
    block.items[2] = Statement.Block(branch.if_block);
    if (is_void and value.default.is_value()) {
        block.items[1] = Statement.Expression(value.default.value());
    }
}

## Where `block` assigns to the local `name`, if it does (a declaration of
## the same name in it shadows the binding from there on).
_assignment_to(block: Block, name: String): Loc? {
    var finder = _AssignmentFinder(name);
    ulong i = 0;
    while (i < block.items.count) {
        var declared = _variable_at(block, i);
        if (declared.is_value() and declared.value().name == name) {
            break;
        }
        rewrite_statement(block.items[i], finder);
        if (finder.found.is_value()) {
            return finder.found;
        }
        i += 1;
    }
    return finder.found;
}

struct _AssignmentFinder {
    var name: String;
    var found: Loc? = Optional<Loc>.Empty;

    construct(name: String) {
        this.name = name;
    }

    rewrite(e: Expression): Expression {
        if (!found.is_value()) {
            if (e is Binary(node)) {
                if (_is_assignment(node.op)) {
                    if (node.lhs is SymbolRef(target)) {
                        if (target.id == name) {
                            found = Optional<Loc>.Value(target.loc);
                        }
                    }
                }
            }
        }
        return e;
    }
}

extend _AssignmentFinder with Rewriter;

_is_with_entered(e: Expression): bool {
    match (e) {
        WithEntered(value) => {
            return true;
        }
        else => {
            return false;
        }
    }
}
