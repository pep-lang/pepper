## Checks on local bindings: `pepper_sema::passes::check_bindings` in
## Pepper. A scope declares each name once, and a `const` binding is
## assigned only by its initializer (a struct's const fields also in its
## constructors).

import [Location] from compiler.diagnostic;
import "closures";
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [Block, Expression, FunctionDef, Module, Statement, UnaryOp, VariableDef] from "model";
import [PassState] from "state";
import [Rewriter, rewrite_expression] from "walk";

## A visible binding: its name, and where it is declared when it is const.
struct _LocalBinding {
    var name: String;
    var declared: Loc?;

    construct(name: String, declared: Loc?) {
        this.name = name;
        this.declared = declared;
    }
}

_local_binding(variable: VariableDef): _LocalBinding {
    return _LocalBinding(variable.name, variable.is_const ? Optional<Loc>.Value(variable.loc) : Optional<Loc>.Empty);
}

struct _Scopes {
    var state: PassState;
    # Innermost last; index 0 holds the module-scope variables.
    var scopes: Array<_LocalBinding[]> = Array<_LocalBinding[]>();
    # The enclosing struct's fields, when checking a method.
    var fields: _LocalBinding[];
    # Per block scope, the names it declared and where.
    var declared: Array<Array<(String, Loc)>> = Array<Array<(String, Loc)>>();

    construct(state: PassState, globals: _LocalBinding[], fields: _LocalBinding[]) {
        this.state = state;
        this.scopes.append(globals);
        this.fields = fields;
    }

    declare(variable: VariableDef) {
        # Synthesized locals (a loop's hidden iterator) carry no location.
        if (declared.count > 0 and !variable.loc.is_none()) {
            var names = declared.last();
            for (var (name, previous) in names) {
                if (name == variable.name) {
                    state.report(
                        error_at(
                            $"redefinition of '{variable.name}'", variable.loc
                        ).with_note("previous definition is here", Optional<Location>.Value(location_of(previous)))
                    );
                    break;
                }
            }
            names.append((variable.name, variable.loc));
        }
        scopes.last().append(_local_binding(variable));
    }

    # The const declaration `name` resolves to, if it is const. Locals and
    # parameters shadow fields, which shadow module-scope variables.
    const_symbol(name: String): Loc? {
        ulong s = scopes.count;
        while (s > 1) {
            s -= 1;
            var found = _find_last(scopes[s], name);
            if (found.is_value()) {
                return found.value().declared;
            }
        }
        for (var f in fields) {
            if (f.name == name) {
                return f.declared;
            }
        }
        var global = _find_last(scopes[0], name);
        return global.is_value() ? global.value().declared : Optional<Loc>.Empty;
    }

    const_field(name: String): Loc? {
        for (var f in fields) {
            if (f.name == name) {
                return f.declared;
            }
        }
        return Optional<Loc>.Empty;
    }
}

_find_last(bindings: _LocalBinding[], name: String): _LocalBinding? {
    ulong i = bindings.count;
    while (i > 0) {
        i -= 1;
        if (bindings[i].name == name) {
            return Optional<_LocalBinding>.Value(bindings[i]);
        }
    }
    return Optional<_LocalBinding>.Empty;
}

## Reports a name declared twice in one scope and an assignment to a
## `const` binding.
##
## @param module the model
## @param state the passes' state, which keeps the first error
export check_bindings(module: Module, state: PassState) {
    var globals = Array<_LocalBinding>();
    for (var v in module.globals) {
        globals.append(_local_binding(v));
    }
    for (var function in module.functions) {
        _check_function(state, function, globals, Array<_LocalBinding>());
    }
    for (var st in module.structs) {
        var fields = Array<_LocalBinding>();
        var unconstrained = Array<_LocalBinding>();
        for (var f in st.field_members) {
            fields.append(_local_binding(f));
            unconstrained.append(_LocalBinding(f.name, Optional<Loc>.Empty));
        }
        # The constructor initializes the fields, const ones included.
        for (var constructor in st.constructors) {
            _check_function(state, constructor, globals, unconstrained);
        }
        _check_function(state, st.destructor, globals, fields);
        for (var method in st.method_members) {
            _check_function(state, method, globals, fields);
        }
    }
}

_check_function(state: PassState, function: FunctionDef, globals: _LocalBinding[], fields: _LocalBinding[]) {
    if (!function.body.is_value()) {
        return;
    }
    var scopes = _Scopes(state, globals.copy(), fields);
    var parameters = Array<_LocalBinding>();
    for (var p in function.parameters) {
        parameters.append(_LocalBinding(p.name, Optional<Loc>.Empty));
    }
    scopes.scopes.append(parameters);
    _check_block(function.body.value(), scopes);
}

_check_block(block: Block, scopes: _Scopes) {
    scopes.scopes.append(Array<_LocalBinding>());
    scopes.declared.append(Array<(String, Loc)>());
    for (var statement in block.items) {
        _check_statement(statement, scopes);
    }
    scopes.declared.pop();
    scopes.scopes.pop();
}

_check_statement(statement: Statement, scopes: _Scopes) {
    match (statement) {
        Expression(e) => {
            _check_expression(e, scopes);
        }
        Block(inner) => {
            _check_block(inner, scopes);
        }
        Declaration(declaration) => {
            if (declaration is Variable(variable)) {
                if (variable.default.is_value()) {
                    _check_expression(variable.default.value(), scopes);
                }
                scopes.declare(variable);
            }
        }
        Branch(branch) => {
            _check_expression(branch.condition, scopes);
            _check_block(branch.if_block, scopes);
            if (branch.else_block.is_value()) {
                _check_block(branch.else_block.value(), scopes);
            }
        }
        While(loop) => {
            _check_expression(loop.condition, scopes);
            _check_block(loop.block, scopes);
        }
        Return(ret) => {
            if (ret.expr.is_value()) {
                _check_expression(ret.expr.value(), scopes);
            }
        }
        else => {}
    }
}

_check_expression(e: Expression, scopes: _Scopes) {
    rewrite_expression(e, _AssignmentCheck(scopes));
}

## Reports each assignment to a const binding the walk meets.
struct _AssignmentCheck {
    var scopes: _Scopes;

    construct(scopes: _Scopes) {
        this.scopes = scopes;
    }

    rewrite(e: Expression): Expression {
        var target = Optional<Expression>.Empty;
        match (e) {
            Binary(node) => {
                if (_is_assignment(node.op)) {
                    target = Optional<Expression>.Value(node.lhs);
                }
            }
            Unary(node) => {
                if (_is_step(node.op)) {
                    target = Optional<Expression>.Value(node.operand);
                }
            }
            else => {}
        }
        if (!target.is_value()) {
            return e;
        }
        var name = "";
        var at = Loc.none();
        var declared = Optional<Loc>.Empty;
        match (target.value()) {
            SymbolRef(symbol) => {
                name = symbol.id;
                at = symbol.loc;
                declared = scopes.const_symbol(symbol.id);
            }
            MemberRef(member) => {
                if (!(member.lhs is ThisRef)) {
                    return e;
                }
                name = member.name;
                at = member.loc;
                declared = scopes.const_field(member.name);
            }
            else => {
                return e;
            }
        }
        if (declared.is_value()) {
            scopes.state.report(
                error_at(
                    $"cannot assign to const variable '{name}'", at
                ).with_note($"'{name}' declared const here", Optional<Location>.Value(location_of(declared.value())))
            );
        }
        return e;
    }
}

extend _AssignmentCheck with Rewriter;
