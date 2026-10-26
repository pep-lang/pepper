## How the program uses its value structs (`[Value]`):
## `check_value_structs`. A value struct has no object, so identity,
## `__null`, `__weak`, `__refcount` and C need a reference type; a value
## struct that contains itself would be infinitely large; and a change that
## would land in a copy and be lost (a field of a temporary, a mutating
## method called on one, `this` in a closure) or that a `const` forbids is
## an error.

import [Diagnostic, Location] from compiler.diagnostic;
import [stashed_member, unit_decls] from "checked";
import [THIS_FIELD] from "closures";
import "common";
import [Loc] from "loc";
import [
    BinaryOp, Block, Expression, FunctionDef, Module, Statement, StructDef, TypeName, UnaryOp, VariableDef
] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [Rewriter, rewrite_expression] from "walk";

## Reports the first misuse of a value struct, once every type is final.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_value_structs(module: Module, state: PassState) {
    state.value_structs.clear();
    for (var st in module.structs) {
        if (st.is_value()) {
            state.value_structs.insert(st.ty.name);
        }
    }
    if (state.value_structs.count == 0) {
        return;
    }
    _check_recursion(module, state);
    _check_value_types(module, state);
    var table = StructTable(module, memo = state.trait_types_memo());
    var mutating = _mutating_methods(module, table, state);
    state.value_facts = _facts_of(mutating);
    var globals = Array<_ValueBinding>();
    for (var g in module.globals) {
        globals.append(_ValueBinding(g.name, g.is_const ? Optional<Loc>.Value(g.loc) : Optional<Loc>.Empty));
    }
    for (var st in module.structs) {
        if (_is_generic_base(st)) {
            continue;
        }
        var functions = Array<FunctionDef>();
        for (var c in st.constructors) {
            if (c.body.is_value()) {
                functions.append(c);
            }
        }
        for (var m in st.method_members) {
            if (m.body.is_value()) {
                functions.append(m);
            }
        }
        var fields = HashSet<String>();
        for (var f in st.field_members) {
            fields.insert(f.name);
        }
        for (var function in functions) {
            var uses = _Uses(table, state, Optional<TypeName>.Value(st.ty), fields, globals, function);
            uses.block(function.body.value());
            for (var found in uses.found) {
                _report_found(found, mutating, state);
            }
        }
    }
    for (var function in module.functions) {
        if (!function.body.is_value()) {
            continue;
        }
        var uses = _Uses(table, state, Optional<TypeName>.Empty, HashSet<String>(), globals, function);
        uses.block(function.body.value());
        for (var found in uses.found) {
            _report_found(found, mutating, state);
        }
    }
}

## A value struct stored in itself would be infinitely large. Follows
## fields of value struct type with an explicit stack, since a chain can be
## as long as the program makes it.
_check_recursion(module: Module, state: PassState) {
    var by_name = HashMap<String, StructDef>();
    var values = Array<StructDef>();
    for (var st in module.structs) {
        if (st.is_value() and !_is_generic_base(st)) {
            by_name[st.ty.to_string()] = st;
            values.append(st);
        }
    }
    # In declaration order, so the first one reported is stable.
    for (var st in values) {
        var name = st.ty.to_string();
        # Each entry: the struct reached, and the chain of fields that led
        # to it.
        var stack = Array<(StructDef, Array<VariableDef>)>();
        stack.append((st, Array<VariableDef>()));
        var seen = HashSet<String>();
        while (stack.count > 0) {
            var (at, chain) = stack.pop();
            for (var field in at.field_members) {
                var field_type = field.ty.to_string();
                var next = by_name.try_get(field_type);
                if (!next.is_value()) {
                    continue;
                }
                var path = Array<VariableDef>();
                for (var link in chain) {
                    path.append(link);
                }
                path.append(field);
                if (field_type == name) {
                    _report_recursion(st, path, state);
                    return;
                }
                if (!seen.contains(field_type)) {
                    seen.insert(field_type);
                    stack.append((next.value(), path));
                }
            }
        }
    }
}

_report_recursion(st: StructDef, path: VariableDef[], state: PassState) {
    var first = path[0];
    var diagnostic = error_at(
        $"value struct '{st.ty.display()}' contains itself through field '{first.name}'", _written_at(first)
    );
    ulong i = 1;
    while (i < path.count) {
        var field = path[i];
        diagnostic = diagnostic.with_note(
            $"which holds field '{field.name}' of type '{field.ty.display()}'",
            Optional<Location>.Value(location_of(_written_at(field)))
        );
        i += 1;
    }
    state.report(diagnostic);
}

## Where `variable`'s type is written, else its name.
_written_at(variable: VariableDef): Loc {
    return variable.type_loc.is_none() ? variable.loc : variable.type_loc;
}

## `__weak<V>` anywhere a type is written, and a value struct in an
## `extern` signature. Synthesized declarations (a specialization's hidden
## parameters) have no location; the source that asked for them is
## reported instead.
_check_value_types(module: Module, state: PassState) {
    var declared = Array<VariableDef>();
    # A checked declaration's types were checked with its unit.
    var own = unit_decls(module);
    for (var st in own.structs) {
        if (_is_generic_base(st)) {
            continue;
        }
        for (var f in st.field_members) {
            declared.append(f);
        }
        for (var c in st.constructors) {
            for (var p in c.parameters) {
                declared.append(p);
            }
        }
        for (var m in st.method_members) {
            for (var p in m.parameters) {
                declared.append(p);
            }
        }
    }
    for (var f in own.functions) {
        for (var p in f.parameters) {
            declared.append(p);
        }
    }
    for (var g in module.globals) {
        if (!module.checked.globals.contains(g.name)) {
            declared.append(g);
        }
    }
    for (var variable in declared) {
        var value = _weak_of_value(variable.ty, state);
        if (value.is_value() and !_written_at(variable).is_none()) {
            state.report(error_at(_weak_error(value.value()), _written_at(variable)));
        }
    }
    for (var ext in module.externs) {
        for (var param in ext.parameters) {
            if (state.is_value_struct(param.ty.to_string())) {
                state.report(error_at(_extern_error(param.ty), _written_at(param)));
            }
        }
        if (state.is_value_struct(ext.ty.to_string())) {
            state.report(error_at(_extern_error(ext.ty), ext.loc));
        }
    }
}

_extern_error(ty: TypeName): String {
    return $"value struct '{ty.display()}' cannot be passed to C; pass a pointer";
}

_weak_error(value: TypeName): String {
    return $"'__weak' needs a reference type; '{value.display()}' is a value struct";
}

_null_error(ty: TypeName): String {
    return $"value struct '{ty.display()}' cannot be null";
}

## The value struct `ty` holds weakly (`Span` in `Array<__weak<Span>>`).
_weak_of_value(ty: TypeName, state: PassState): TypeName? {
    var stack = [ty];
    while (stack.count > 0) {
        var at = stack.pop();
        if (at.name == "__weak" and at.sub_types.count > 0 and state.is_value_struct(at.sub_types[0].to_string())) {
            return Optional<TypeName>.Value(at.sub_types[0]);
        }
        for (var sub in at.sub_types) {
            stack.append(sub);
        }
    }
    return Optional<TypeName>.Empty;
}

## A visible binding: its name, and where it was declared `const` if it
## was.
struct _ValueBinding {
    var name: String;
    var declared: Loc?;

    construct(name: String, declared: Loc?) {
        this.name = name;
        this.declared = declared;
    }
}

## The storage an expression of value struct type lives in, which a change
## through it changes.
enum _Root {
    ## The method's receiver.
    This,
    ## A local, parameter or module-scope variable, with where it was
    ## declared `const` if it was.
    Variable(name: String, declared: Loc?),
    ## A copy: the result of the call named, at the location, which nothing
    ## keeps.
    Temporary(source: String, made: Loc),
    ## Memory behind a reference or a pointer, which keeps the change.
    Place,
    ## A closure's copy of the receiver of the method that made it.
    ClosureThis,
}

## What a walk over a function finds: a change to a value (an assignment
## to one of its fields, or a call of one of its mutating methods), or a
## use that needs an object.
struct _ValueUse {
    var error: Diagnostic?;
    var root: _Root;
    ## The value struct changed.
    var ty: TypeName;
    ## The field assigned, or the method called.
    var member: String;
    var method: bool;
    var at: Loc;

    construct(error: Diagnostic?, root: _Root, ty: TypeName, member: String, method: bool, at: Loc) {
        this.error = error;
        this.root = root;
        this.ty = ty;
        this.member = member;
        this.method = method;
        this.at = at;
    }

    static failed(error: Diagnostic): _ValueUse {
        return _ValueUse(Optional<Diagnostic>.Value(error), _Root.Place, TypeName(), "", false, Loc.none());
    }

    static change(root: _Root, ty: TypeName, member: String, method: bool, at: Loc): _ValueUse {
        return _ValueUse(Optional<Diagnostic>.Empty, root, ty, member, method, at);
    }
}

## The methods of value structs that change `this`, with where each first
## does.
struct _Mutating {
    ## `struct\nmethod` → where.
    var at: HashMap<String, Loc> = HashMap<String, Loc>();
    ## (struct, method, where), in the order found.
    var found: Array<(String, String, Loc)> = Array<(String, String, Loc)>();
    ## The name of each found method's struct, in the same order.
    var owners: String[] = Array<String>();
    ## `struct\noverload set` → where its first found member changes `this`:
    ## a scan of `found` per call cost a nested literal its depth (#210).
    var first_of_set: HashMap<String, Loc> = HashMap<String, Loc>();

    construct() {}

    insert(ty: String, method: String, loc: Loc, owner: String) {
        at[$"{ty}\n{method}"] = loc;
        found.append((ty, method, loc));
        owners.append(owner);
        var set = $"{ty}\n{set_name(method)}";
        if (!first_of_set.contains(set)) {
            first_of_set[set] = loc;
        }
    }

    contains(ty: String, method: String): bool {
        return at.contains($"{ty}\n{method}");
    }

    ## Where method `method` of value struct `ty` first changes `this`, if
    ## it does. A call still named by its overload set (`grow`) is mutating
    ## when any member of the set is.
    first(ty: TypeName, method: String): Loc? {
        var spelled = ty.to_string();
        var direct = at.try_get($"{spelled}\n{method}");
        if (direct.is_value()) {
            return direct;
        }
        return first_of_set.try_get($"{spelled}\n{method}");
    }
}

_report_found(found: _ValueUse, mutating: _Mutating, state: PassState) {
    if (found.error.is_value()) {
        state.report(found.error.value());
        return;
    }
    var first_change = Optional<Loc>.Empty;
    if (found.method) {
        first_change = mutating.first(found.ty, found.member);
        if (!first_change.is_value()) {
            return;
        }
    }
    var what = found.method ? $"call mutating method '{set_name(found.member)}'" : $"assign to field '{found.member}'";
    var preposition = found.method ? "on" : "of";
    Diagnostic? made = Optional<Diagnostic>.Empty;
    match (found.root) {
        Temporary(source, at) => {
            made = Optional<Diagnostic>.Value(
                error_at(
                    $"cannot {what} {preposition} a temporary '{found.ty.display()}'",
                    found.at
                ).with_note(
                    $"'{source}' returns a copy; store it in a variable, change it, and assign it back",
                    Optional<Location>.Value(location_of(at))
                )
            );
        }
        ClosureThis => {
            made = Optional<Diagnostic>.Value(
                error_at(
                    $"cannot change 'this' in a closure: the closure holds a copy of '{found.ty.display()}'", found.at
                )
            );
        }
        Variable(name, declared) => {
            if (!declared.is_value()) {
                return;
            }
            made = Optional<Diagnostic>.Value(
                error_at(
                    $"cannot {what} {preposition} const variable '{name}'", found.at
                ).with_note($"'{name}' declared const here", Optional<Location>.Value(location_of(declared.value())))
            );
        }
        else => {
            return;
        }
    }
    var diagnostic = made.value();
    if (first_change.is_value()) {
        diagnostic = diagnostic.with_note(
            $"'{set_name(found.member)}' changes 'this' here",
            Optional<Location>.Value(location_of(first_change.value()))
        );
    }
    state.report(diagnostic);
}

## The methods of value structs that change `this`: one that assigns to a
## field of `this` (or of a value field of it), or calls a mutating method
## on `this` or a value field. A fixpoint, since one method can make
## another mutating.
##
## A checked struct's come from its unit's record (`VALUE_FACTS`), unless this
## compilation unit extended it: its stashed bodies are walked no more. Which
## methods are mutating comes out the same; only the order they are found in can
## differ, which picks the change a note shows for a call still named by an
## overload set of two mutating methods.
_mutating_methods(module: Module, table: StructTable, state: PassState): _Mutating {
    var mutating = _Mutating();
    var globals = Array<_ValueBinding>();
    var seeded = _seed_mutating(module, state, mutating);
    while (true) {
        var before = mutating.found.count;
        for (var st in module.structs) {
            if (!st.is_value() or _is_generic_base(st) or seeded.contains(st.name)) {
                continue;
            }
            var fields = HashSet<String>();
            for (var f in st.field_members) {
                fields.insert(f.name);
            }
            var spelled = st.ty.to_string();
            for (var method in st.method_members) {
                if (method.is_static or mutating.contains(spelled, method.name)) {
                    continue;
                }
                # A checked struct's bodies are stashed while the passes
                # run; its methods change `this` all the same.
                var body = method.body.is_value() ? method.body : stashed_member(state, st.name, "method", method.name);
                if (!body.is_value()) {
                    continue;
                }
                var uses = _Uses(table, state, Optional<TypeName>.Value(st.ty), fields, globals, method);
                uses.block(body.value());
                for (var found in uses.found) {
                    if (found.error.is_value() or !(found.root is This)) {
                        continue;
                    }
                    if (!found.method or mutating.first(found.ty, found.member).is_value()) {
                        mutating.insert(spelled, method.name, found.at, st.name);
                        break;
                    }
                }
            }
        }
        if (mutating.found.count == before) {
            return mutating;
        }
    }
    return mutating;
}

## A walk over one function's body that tracks the bindings in scope and
## records what it finds about value structs.
struct _Uses {
    var table: StructTable;
    var state: PassState;
    var current: TypeName?;
    ## The enclosing struct's fields: a bare name that is not a local is one.
    var fields: HashSet<String>;
    ## Innermost last; index 0 holds the module-scope variables.
    var scopes: Array<Array<_ValueBinding>> = Array<Array<_ValueBinding>>();
    var found: Array<_ValueUse> = Array<_ValueUse>();

    construct(
        table: StructTable,
        state: PassState,
        current: TypeName?,
        fields: HashSet<String>,
        globals: _ValueBinding[],
        function: FunctionDef
    ) {
        this.table = table;
        this.state = state;
        this.current = current;
        this.fields = fields;
        scopes.append(globals);
        var parameters = Array<_ValueBinding>();
        for (var p in function.parameters) {
            parameters.append(_ValueBinding(p.name, Optional<Loc>.Empty));
        }
        scopes.append(parameters);
    }

    ## An explicit stack of statements still to visit, so nesting depth is
    ## not bounded by the stack; none closes a scope.
    block(body: Block) {
        scopes.append(Array<_ValueBinding>());
        var stack = Array<Statement?>();
        _open(stack, body);
        while (stack.count > 0) {
            var item = stack.pop();
            if (!item.is_value()) {
                scopes.pop();
                continue;
            }
            match (item.value()) {
                Expression(e) => {
                    expression(e);
                }
                Block(inner) => {
                    scopes.append(Array<_ValueBinding>());
                    stack.append(Optional<Statement>.Empty);
                    _open(stack, inner);
                }
                Declaration(declaration) => {
                    if (declaration is Variable(variable)) {
                        declare(variable);
                    }
                }
                Branch(branch) => {
                    expression(branch.condition);
                    if (branch.else_block.is_value()) {
                        scopes.append(Array<_ValueBinding>());
                        stack.append(Optional<Statement>.Empty);
                        _open(stack, branch.else_block.value());
                    }
                    scopes.append(Array<_ValueBinding>());
                    stack.append(Optional<Statement>.Empty);
                    _open(stack, branch.if_block);
                }
                While(loop) => {
                    expression(loop.condition);
                    scopes.append(Array<_ValueBinding>());
                    stack.append(Optional<Statement>.Empty);
                    _open(stack, loop.block);
                }
                Return(ret) => {
                    if (ret.expr.is_value()) {
                        expression(ret.expr.value());
                    }
                }
                else => {}
            }
        }
        scopes.pop();
    }

    declare(variable: VariableDef) {
        if (variable.default.is_value()) {
            var default = variable.default.value();
            expression(default);
            if (_is_null(default) and state.is_value_struct(variable.ty.to_string())) {
                found.append(_ValueUse.failed(error_at(_null_error(variable.ty), variable.loc)));
            }
        }
        var value = _weak_of_value(variable.ty, state);
        if (value.is_value() and !_written_at(variable).is_none()) {
            found.append(_ValueUse.failed(error_at(_weak_error(value.value()), _written_at(variable))));
        }
        scopes[scopes.count - 1].append(
            _ValueBinding(variable.name, variable.is_const ? Optional<Loc>.Value(variable.loc) : Optional<Loc>.Empty)
        );
    }

    binding(name: String): _ValueBinding? {
        ulong i = scopes.count;
        while (i > 1) {
            i -= 1;
            var scope = scopes[i];
            ulong j = scope.count;
            while (j > 0) {
                j -= 1;
                if (scope[j].name == name) {
                    return Optional<_ValueBinding>.Value(scope[j]);
                }
            }
        }
        return Optional<_ValueBinding>.Empty;
    }

    type_of(e: Expression): TypeName? {
        var ty = static_type_of(e, table, current, state);
        if (ty.is_value()) {
            return ty;
        }
        if (!current.is_value()) {
            return Optional<TypeName>.Empty;
        }
        if (e is SymbolRef(node)) {
            var info = table.lookup(current.value());
            if (!info.is_value()) {
                return Optional<TypeName>.Empty;
            }
            for (var (f, field_type) in info.value().fields) {
                if (f == node.id) {
                    return Optional<TypeName>.Value(field_type);
                }
            }
        }
        return Optional<TypeName>.Empty;
    }

    ## The value struct type of `e`, if it has one.
    value_type(e: Expression): TypeName? {
        var ty = type_of(e);
        if (ty.is_value() and state.is_value_struct(ty.value().to_string())) {
            return ty;
        }
        return Optional<TypeName>.Empty;
    }

    ## The storage that `e`, a value, lives in.
    root(value: Expression): _Root {
        var e = value;
        while (true) {
            match (e) {
                ThisRef => {
                    return _Root.This;
                }
                SymbolRef(node) => {
                    var bound = binding(node.id);
                    if (bound.is_value()) {
                        return _Root.Variable(node.id, bound.value().declared);
                    }
                    if (node.id == THIS_FIELD and fields.contains(node.id)) {
                        return _Root.ClosureThis;
                    }
                    if (fields.contains(node.id)) {
                        return _Root.This;
                    }
                    for (var g in scopes[0]) {
                        if (g.name == node.id) {
                            return _Root.Variable(node.id, g.declared);
                        }
                    }
                    return _Root.Place;
                }
                MemberRef(node) => {
                    if (node.name == THIS_FIELD and node.lhs is ThisRef) {
                        return _Root.ClosureThis;
                    }
                    # A field of a value lives in that value; a field of an
                    # object lives in the object.
                    if (!value_type(node.lhs).is_value()) {
                        return _Root.Place;
                    }
                    e = node.lhs;
                }
                MethodCall(node) => {
                    return _Root.Temporary(_call_name(node.method), node.loc);
                }
                FunctionCall(node) => {
                    return _Root.Temporary(_call_name(node.function), node.loc);
                }
                else => {
                    return _Root.Place;
                }
            }
        }
        return _Root.Place;
    }

    expression(e: Expression) {
        rewrite_expression(e, this);
    }

    rewrite(e: Expression): Expression {
        match (e) {
            Binary(node) => {
                var nulled = _is_null(node.lhs) or _is_null(node.rhs);
                var value = value_type(node.lhs);
                if (!value.is_value()) {
                    value = value_type(node.rhs);
                }
                var identity = node.op == BinaryOp.Identical or node.op == BinaryOp.NotIdentical;
                var compares = node.op == BinaryOp.Assign
                    or node.op == BinaryOp.Equal
                    or node.op == BinaryOp.NotEqual
                    or identity;
                if (value.is_value() and nulled and compares) {
                    found.append(_ValueUse.failed(error_at(_null_error(value.value()), node.loc)));
                } else if (value.is_value() and identity) {
                    var instead = node.op == BinaryOp.Identical ? "==" : "!=";
                    found.append(
                        _ValueUse.failed(
                            error_at(
                                $"'{value.value().display()}' is a value struct and has no identity; use '{instead}' to compare values",
                                node.loc
                            )
                        )
                    );
                }
                if (_is_assignment(node.op)) {
                    assigned(node.lhs);
                }
            }
            Unary(node) => {
                if (node.op == UnaryOp.PreInc
                    or node.op == UnaryOp.PostInc
                    or node.op == UnaryOp.PreDec
                    or node.op == UnaryOp.PostDec) {
                    assigned(node.operand);
                }
            }
            # `__address` of a value hashes its fields, as for a tuple: the
            # generic `hash<T>` is built on it.
            RefCount(_, arg) => {
                var value = value_type(arg);
                if (value.is_value()) {
                    found.append(
                        _ValueUse.failed(
                            error_at(
                                $"'{value.value().display()}' is a value struct and has no object", _expression_loc(arg)
                            )
                        )
                    );
                }
            }
            # `for` over a value iterator (no `iterate()`) drives it with
            # `next()` in place, which a `const` forbids.
            ForIterator(source) => {
                var ty = value_type(source);
                if (ty.is_value()) {
                    var info = table.lookup(ty.value());
                    if (!(info.is_value() and info.value().methods.contains("iterate"))) {
                        var root = root(source);
                        if (root is Variable(name, declared)) {
                            if (declared.is_value()) {
                                found.append(_ValueUse.change(root, ty.value(), "next", true, _expression_loc(source)));
                            }
                        }
                    }
                }
            }
            Weak(_, ty, arg) => {
                if (state.is_value_struct(ty.to_string())) {
                    found.append(_ValueUse.failed(error_at(_weak_error(ty), _expression_loc(arg))));
                }
            }
            MethodCall(node) => {
                var ty = value_type(node.this_value);
                if (ty.is_value()) {
                    found.append(_ValueUse.change(root(node.this_value), ty.value(), node.method, true, node.loc));
                }
            }
            else => {}
        }
        return e;
    }

    ## `target` is assigned: a field of a value changes that value.
    assigned(target: Expression) {
        match (target) {
            MemberRef(node) => {
                var ty = value_type(node.lhs);
                if (ty.is_value()) {
                    found.append(_ValueUse.change(root(node.lhs), ty.value(), node.name, false, node.loc));
                }
            }
            # A bare field in a method is `this.field`.
            SymbolRef(node) => {
                if (!binding(node.id).is_value() and fields.contains(node.id)) {
                    if (current.is_value() and state.is_value_struct(current.value().to_string())) {
                        found.append(_ValueUse.change(_Root.This, current.value(), node.id, false, node.loc));
                    }
                }
            }
            else => {}
        }
    }
}

extend _Uses with Rewriter;

## Pushes `body`'s statements so the first is popped first.
_open(stack: Array<Statement?>, body: Block) {
    ulong i = body.items.count;
    while (i > 0) {
        i -= 1;
        stack.append(Optional<Statement>.Value(body.items[i]));
    }
}

_is_null(e: Expression): bool {
    match (e) {
        PointerLiteral => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## A called function or method as the source spells it: `[]` for an
## indexer, an overload by its set's name.
_call_name(name: String): String {
    var set = set_name(name);
    if (set.starts_with("__index")) {
        return "[]";
    }
    var open = set.find("<");
    return open < 0 ? set : set.substr_bytes(0, open as ulong);
}

## The key prefix of a value struct's mutating method in a checked unit's
## summaries (`Checked.summaries`): `mut`, then the struct's name, its
## type's spelling and the method, a line each; the text is where it falls
## in the order found.
export const VALUE_FACTS = "mut\n";

# The mutating methods as recorded with the unit: (key, where, order).
_facts_of(mutating: _Mutating): Array<(String, Loc, String)> {
    var out = Array<(String, Loc, String)>();
    for (var i in 0..mutating.found.count) {
        var (ty, method, loc) = mutating.found[i];
        out.append(($"{VALUE_FACTS}{mutating.owners[i]}\n{ty}\n{method}", loc, $"{i}"));
    }
    return out;
}

# Puts the checked structs' recorded mutating methods in `mutating`, in the
# order found, and returns the structs they are of: all the checked value
# structs but those an extension of this compilation unit changed.
_seed_mutating(module: Module, state: PassState, mutating: _Mutating): HashSet<String> {
    var seeded = HashSet<String>();
    var facts = Array<(ulong, String, String, String, Loc)>();
    for (var (key, (loc, text)) in module.checked.summaries) {
        if (!key.starts_with(VALUE_FACTS)) {
            continue;
        }
        var parts = key.split("\n");
        var order = ulong.parse(text);
        if (parts.count != 4 or !order.is_value() or state.extended_checked.contains(parts[1])) {
            continue;
        }
        facts.append((order.value(), parts[1], parts[2], parts[3], loc));
    }
    facts.sort((a, b) => {
        var (x, _, _, _, _) = a;
        var (y, _, _, _, _) = b;
        return x < y ? -1 : (x > y ? 1 : 0);
    });
    for (var (_, owner, ty, method, loc) in facts) {
        mutating.insert(ty, method, loc, owner);
    }
    for (var st in module.structs) {
        if (st.is_value() and module.checked.structs.contains(st.name) and !state.extended_checked.contains(st.name)) {
            seeded.insert(st.name);
        }
    }
    return seeded;
}
