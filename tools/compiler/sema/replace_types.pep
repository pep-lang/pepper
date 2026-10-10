## Replacing the types a specialization's type arguments name in code a
## `static` block emits, and in any statement or expression: apart from
## `static_blocks` so that the passes that substitute types need not import
## its evaluator.

import [Expression, Statement, StaticBlock, StaticItem, TypeName] from "model";
import [parse_type_string, replace_map] from "type_name";
import [Rewriter, rewrite_statement] from "walk";

## Replaces the types `type_map` names in `statement`, as
## `specialize_functions::replace_body_types` does for one statement.
##
## @param statement the statement, changed in place
## @param type_map the types to replace
export replace_statement_types(statement: Statement, type_map: Array<(String, TypeName)>) {
    match (statement) {
        Expression(value) => {
            replace_expression_types(value, type_map);
        }
        Block(inner) => {
            for (var item in inner.items) {
                replace_statement_types(item, type_map);
            }
        }
        Declaration(declaration) => {
            if (declaration is Variable(variable)) {
                replace_map(variable.ty, type_map);
                if (variable.default.is_value()) {
                    replace_expression_types(variable.default.value(), type_map);
                }
            }
        }
        Branch(branch) => {
            replace_expression_types(branch.condition, type_map);
            for (var item in branch.if_block.items) {
                replace_statement_types(item, type_map);
            }
            if (branch.else_block.is_value()) {
                for (var item in branch.else_block.value().items) {
                    replace_statement_types(item, type_map);
                }
            }
        }
        While(loop) => {
            replace_expression_types(loop.condition, type_map);
            for (var item in loop.block.items) {
                replace_statement_types(item, type_map);
            }
        }
        Return(ret) => {
            if (ret.expr.is_value()) {
                replace_expression_types(ret.expr.value(), type_map);
            }
        }
        Static(block) => {
            _substitute(block, type_map);
            _replace_static_items(block.items, type_map);
        }
        else => {}
    }
}

_replace_static_items(items: StaticItem[], type_map: Array<(String, TypeName)>) {
    for (var item in items) {
        match (item) {
            For(node) => {
                _replace_static_items(node.body, type_map);
            }
            While(node) => {
                _replace_static_items(node.body, type_map);
            }
            Block(body) => {
                _replace_static_items(body, type_map);
            }
            If(node) => {
                _replace_static_items(node.then_items, type_map);
                _replace_static_items(node.else_items, type_map);
            }
            EmitIf(node) => {
                replace_expression_types(node.condition, type_map);
                _replace_static_items(node.then_items, type_map);
                _replace_static_items(node.else_items, type_map);
            }
            Emit(statement, _) => {
                replace_statement_types(statement, type_map);
            }
            else => {}
        }
    }
}

## Records a specialization's type arguments in `block`, applying them to
## those recorded by an outer one.
_substitute(block: StaticBlock, type_map: Array<(String, TypeName)>) {
    for (var (_, ty) in block.type_map) {
        replace_map(ty, type_map);
    }
    for (var (param, ty) in type_map) {
        bool known = false;
        for (var (k, _) in block.type_map) {
            if (k == param) {
                known = true;
            }
        }
        if (!known) {
            block.type_map.append((param, ty.copy()));
        }
    }
}

## Replaces the types in `e` and what it holds.
struct _TypeReplacer {
    var type_map: Array<(String, TypeName)>;

    construct(type_map: Array<(String, TypeName)>) {
        this.type_map = type_map;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            SizeOf(ty) => {
                replace_map(ty, type_map);
            }
            ArrayIndex(node) => {
                replace_map(node.ty, type_map);
            }
            IsPod(ty) => {
                replace_map(ty, type_map);
            }
            Default(ty) => {
                replace_map(ty, type_map);
            }
            StaticCase(node) => {
                replace_map(node.ty, type_map);
            }
            Subject(node) => {
                replace_map(node.ty, type_map);
            }
            Allocate(ty) => {
                replace_map(ty, type_map);
            }
            Cast(node) => {
                replace_map(node.ty, type_map);
            }
            RefCount(ty, _) => {
                replace_map(ty, type_map);
            }
            Weak(_, ty, _) => {
                replace_map(ty, type_map);
            }
            Address(ty, _) => {
                replace_map(ty, type_map);
            }
            AtomicLoad(ty, _) => {
                replace_map(ty, type_map);
            }
            AtomicStore(ty, _, _) => {
                replace_map(ty, type_map);
            }
            AtomicCmpXchg(ty, _, _, _) => {
                replace_map(ty, type_map);
            }
            AtomicFetch(_, ty, _, _) => {
                replace_map(ty, type_map);
            }
            Simd(node) => {
                replace_map(node.ty, type_map);
            }
            MakeClosure(node) => {
                replace_map(node.ty, type_map);
                var parsed = parse_type_string(node.closure);
                replace_map(parsed, type_map);
                node.closure = parsed.to_string();
            }
            FunctionCall(node) => {
                if (node.function.contains("<")) {
                    var parsed = parse_type_string(node.function);
                    replace_map(parsed, type_map);
                    node.function = parsed.to_string();
                }
            }
            MethodCall(node) => {
                if (node.method.contains("<")) {
                    var parsed = parse_type_string(node.method);
                    replace_map(parsed, type_map);
                    node.method = parsed.to_string();
                }
            }
            SymbolRef(node) => {
                replace_map(node.ty, type_map);
            }
            else => {}
        }
        return e;
    }
}

extend _TypeReplacer with Rewriter;

## Replaces the types `type_map` names in `e` and what it holds.
##
## @param e the expression, changed in place
## @param type_map the types to replace
export replace_expression_types(e: Expression, type_map: Array<(String, TypeName)>) {
    rewrite_statement(Statement.Expression(e), _TypeReplacer(type_map));
}
