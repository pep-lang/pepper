## String literals as immortal static objects: `passes::static_strings` in
## Pepper.
##
## A literal can share one immortal object wherever its use neither keeps
## nor changes the object: an argument whose parameter is free, or the
## receiver of a method whose `this` is. Such a literal becomes a
## `StaticString`. A free parameter's copy is made by the caller around the
## call (`Module.caller_copies`), so a shared literal passes with no count
## step. Only a direct call can make the caller's copy, so the parameters
## of constructors, of `__` methods, of functions used as values and of
## methods a trait's vtable calls are never free.
##
## A `String` slot (`this` of a `String` method, or a parameter) is free
## when every use of it in the body reads a field that holds no reference,
## passes it to a free parameter of a function or method the call resolves
## to, or is a statement of its own or a comparison with null. Freedom is
## the greatest fixed point over the call graph. The facts ride in each
## function's recorded link summary (`|s=`, one character per slot: `f`
## free, `k` kept, `-` not a `String`), so a function whose body the build
## cache skipped reads them back.

import [is_numeric_type] from "arithmetic";
import [expression_children] from "closure_sites";
import [takes_over] from "confinement";
import [Loc] from "loc";
import [
    BinaryOp,
    Block,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    Module,
    Statement,
    StaticStringExpression,
    StructDef,
    TypeName,
    UnaryOp,
    VariableDef
] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## What the recorded link summary carries after the confinement summary.
const _FACTS = "|s=";

## Shares the string literals that may be shared, and records which
## parameters' copies callers make (`module.caller_copies`) and the facts
## for the link summaries to record.
##
## @param module the model
## @param state the passes' state
export share_string_literals(module: Module, state: PassState) {
    var program = _Literals(module, state);
    program.seed();
    var keys = Array<String>();
    for (var (key, _) in program.kept) {
        keys.append(key);
    }
    keys.sort((a: String, b: String) => a < b ? -1 : (a > b ? 1 : 0));
    var changed = true;
    while (changed) {
        changed = false;
        for (var key in keys) {
            if (program.refine(key)) {
                changed = true;
            }
        }
    }
    # Facts and copies first: sharing replaces literals in the bodies.
    var facts = program.record_facts();
    var caller_copies = HashMap<String, Array<bool>>();
    for (var (key, callee) in program.callees) {
        if (!program.kept.contains(key)) {
            continue;
        }
        var first: ulong = callee.has_this ? 1 : 0;
        var copies = Array<bool>();
        bool any = false;
        ulong i = 0;
        while (i < callee.function.parameters.count) {
            var copy = program.argument_free(key, first + i);
            copies.append(copy);
            any = any or copy;
            i += 1;
        }
        if (any) {
            caller_copies[key] = copies;
        }
    }
    for (var (_, callee) in program.callees) {
        if (callee.function.body.is_value()) {
            _SharedLiterals(program, _LiteralScope.of(callee)).block(callee.function.body.value());
        }
    }
    for (var variable in module.globals) {
        if (variable.default.is_value()) {
            var shared = _SharedLiterals(program, _LiteralScope.global());
            variable.default = Optional<Expression>.Value(shared.root(variable.default.value()));
        }
    }
    module.caller_copies = caller_copies;
    var recorded = Array<(Loc, String)>();
    for (var (loc, summary) in module.summaries_to_record) {
        var found = _facts_at(facts, loc);
        recorded.append((loc, found.is_value() ? summary + _FACTS + found.value() : summary));
    }
    module.summaries_to_record = recorded;
}

_facts_at(facts: Array<(Loc, String)>, at: Loc): String? {
    for (var (loc, text) in facts) {
        if (loc.same(at)) {
            return Optional<String>.Value(text);
        }
    }
    return Optional<String>.Empty;
}

_is_string(ty: TypeName): bool {
    return ty.to_string() == "String";
}

_key(owner: String, method: String): String {
    return $"{owner}.{method}";
}

## A function with a body or recorded facts.
struct _LiteralCallee {
    var function: FunctionDef;
    ## The struct of a method or constructor.
    var owner: StructDef?;
    ## Slot 0 is `this`.
    var has_this: bool;

    construct(function: FunctionDef, owner: StructDef?, has_this: bool) {
        this.function = function;
        this.owner = owner;
        this.has_this = has_this;
    }

    slot_types(): TypeName[] {
        var out = Array<TypeName>();
        if (has_this) {
            out.append(owner.is_value() ? owner.value().ty : TypeName.auto());
        }
        for (var p in function.parameters) {
            out.append(p.ty);
        }
        return out;
    }
}

## A resolved method call: the key, the slot of `this` (-1 for a static
## method) and the slot of its first argument.
struct _LiteralMethod {
    var key: String;
    var this_slot: long;
    var first: ulong;

    construct(key: String, this_slot: long, first: ulong) {
        this.key = key;
        this.this_slot = this_slot;
        this.first = first;
    }
}

struct _Literals {
    var module: Module;
    var state: PassState;
    var table: StructTable;
    var callees: HashMap<String, _LiteralCallee> = HashMap<String, _LiteralCallee>();
    ## Concrete structs by name.
    var structs: HashMap<String, StructDef> = HashMap<String, StructDef>();
    ## Constructor call names (`Point`, `Point$2`) to their keys.
    var constructors: HashMap<String, String> = HashMap<String, String>();
    var externs: HashSet<String> = HashSet<String>();
    ## Per key, per operand slot: kept (`true`) or free. Only keys with a
    ## `String` slot.
    var kept: HashMap<String, Array<bool>> = HashMap<String, Array<bool>>();

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
        this.table = StructTable(module);
        for (var f in module.functions) {
            if (!f.is_generic_func) {
                callees[f.name] = _LiteralCallee(f, Optional<StructDef>.Empty, false);
            }
        }
        for (var st in module.structs) {
            if (st.name == st.ty.name and st.ty.is_generic()) {
                continue;
            }
            structs[st.name] = st;
            for (var m in st.method_members) {
                if (!m.is_generic_func) {
                    callees[_key(st.name, m.name)] = _LiteralCallee(m, Optional<StructDef>.Value(st), !m.is_static);
                }
            }
            for (var c in st.constructors) {
                var key = _key(c.name, "__ctor");
                constructors[c.name] = key;
                callees[key] = _LiteralCallee(c, Optional<StructDef>.Value(st), false);
            }
        }
        for (var e in module.externs) {
            externs.insert(e.name);
        }
    }

    ## Seeds every slot: a `String` slot of a function with a body starts
    ## free; one whose body the cache skipped takes its recorded fact.
    seed() {
        var indirect = _indirectly_called(module);
        for (var (key, callee) in callees) {
            var types = callee.slot_types();
            bool any = false;
            for (var t in types) {
                any = any or _is_string(t);
            }
            if (!any) {
                continue;
            }
            # Only a direct call can make the caller's copy. A property
            # getter (`__get_p`) is called like any method.
            var method = callee.function.name;
            var dot = method.rfind(".");
            if (dot >= 0) {
                method = method.substr_bytes(dot as ulong + 1, method.size - dot as ulong - 1);
            }
            var internal = method.starts_with("__") and !method.starts_with("__get_");
            var out = Array<bool>();
            if (key.ends_with(".__ctor") or internal or indirect.contains(key)) {
                for (var t in types) {
                    out.append(true);
                }
            } else if (callee.function.body.is_value()) {
                for (var t in types) {
                    out.append(!_is_string(t));
                }
            } else {
                var recorded = _recorded_facts(module, callee.function, types.count);
                if (recorded.is_value()) {
                    out = recorded.value();
                } else {
                    for (var t in types) {
                        out.append(true);
                    }
                }
            }
            kept[key] = out;
        }
    }

    ## Whether slot `slot` of `key` is free.
    is_free(key: String, slot: ulong): bool {
        var found = kept.try_get(key);
        return found.is_value() and slot < found.value().count and !found.value()[slot];
    }

    ## The callee of `function(args)`, whose first argument is slot 0.
    resolve_function(function: String): String? {
        if (externs.contains(function)) {
            return Optional<String>.Empty;
        }
        var constructor = constructors.try_get(function);
        if (constructor.is_value()) {
            return constructor;
        }
        return callees.contains(function) ? Optional<String>.Value(function) : Optional<String>.Empty;
    }

    ## The callee of `this.method(args)`.
    resolve_method(scope: _LiteralScope, this_value: Expression, method: String): _LiteralMethod? {
        var none = Optional<_LiteralMethod>.Empty;
        if (this_value is SymbolRef(node)) {
            if (!scope.local(node.id).is_value() and structs.contains(node.id)) {
                var key = _key(structs[node.id].name, method);
                var callee = callees.try_get(key);
                if (!callee.is_value() or callee.value().has_this) {
                    return none;
                }
                return Optional<_LiteralMethod>.Value(_LiteralMethod(key, -1, 0));
            }
        }
        var ty = scope.ty(this_value, table, state);
        if (!ty.is_value()) {
            return none;
        }
        var st = structs.try_get(ty.value().to_string());
        if (!st.is_value()) {
            return none;
        }
        var key = _key(st.value().name, method);
        var callee = callees.try_get(key);
        if (!callee.is_value()) {
            return none;
        }
        return Optional<_LiteralMethod>.Value(
            callee.value().has_this ? _LiteralMethod(key, 0, 1) : _LiteralMethod(key, -1, 0)
        );
    }

    ## Whether the parameter at `slot` of `key` takes over its argument.
    takes_over_at(key: String, slot: ulong): bool {
        var callee = callees.try_get(key);
        if (!callee.is_value()) {
            return true;
        }
        var offset: ulong = callee.value().has_this ? 1 : 0;
        var parameters = callee.value().function.parameters;
        if (slot < offset or slot - offset >= parameters.count) {
            return true;
        }
        return takes_over(parameters[slot - offset].attributes);
    }

    ## Whether an argument at `slot` of `key` may be a shared literal.
    argument_free(key: String, slot: ulong): bool {
        return is_free(key, slot) and !takes_over_at(key, slot);
    }

    ## Marks kept every `String` slot of `key` whose uses its body does not
    ## allow, under the current facts; whether anything changed.
    refine(key: String): bool {
        var found = kept.try_get(key);
        if (!found.is_value()) {
            return false;
        }
        var slots = found.value();
        var callee = callees[key];
        if (!callee.function.body.is_value()) {
            return false;
        }
        var names = Array<String>();
        if (callee.has_this) {
            names.append("this");
        }
        for (var p in callee.function.parameters) {
            names.append(p.name);
        }
        var changed = Array<ulong>();
        ulong slot = 0;
        while (slot < names.count) {
            if (!slots[slot]) {
                var uses = _SlotUses(this, _LiteralScope.of(callee), names[slot], callee.has_this and slot == 0);
                uses.block(callee.function.body.value());
                if (uses.kept) {
                    changed.append(slot);
                }
            }
            slot += 1;
        }
        for (var s in changed) {
            slots[s] = true;
        }
        return changed.count > 0;
    }

    ## The facts to record for each function with a body and a `String`
    ## slot, by location.
    record_facts(): Array<(Loc, String)> {
        var out = Array<(Loc, String)>();
        if (module.summaries_to_record.count == 0) {
            return out;
        }
        for (var (key, callee) in callees) {
            var found = kept.try_get(key);
            if (!found.is_value() or !callee.function.body.is_value()) {
                continue;
            }
            var types = callee.slot_types();
            var text = "";
            ulong i = 0;
            while (i < types.count and i < found.value().count) {
                text += !_is_string(types[i]) ? "-" : (found.value()[i] ? "k" : "f");
                i += 1;
            }
            out.append((callee.function.loc, text));
        }
        return out;
    }
}

## The keys of the functions and methods a call can reach without naming
## them: those used as function values, and the methods that implement a
## trait's, which a trait value's vtable calls.
_indirectly_called(module: Module): HashSet<String> {
    var note = _IndirectCalls();
    for (var f in module.functions) {
        if (f.body.is_value()) {
            rewrite_block(f.body.value(), note);
        }
    }
    for (var st in module.structs) {
        for (var f in st.method_members) {
            if (f.body.is_value()) {
                rewrite_block(f.body.value(), note);
            }
        }
        for (var f in st.constructors) {
            if (f.body.is_value()) {
                rewrite_block(f.body.value(), note);
            }
        }
    }
    for (var variable in module.globals) {
        if (variable.default.is_value()) {
            rewrite_expression(variable.default.value(), note);
        }
    }
    for (var st in module.structs) {
        var slots = HashSet<String>();
        for (var t in st.traits) {
            for (var def in module.traits) {
                if (def.name == t.name) {
                    for (var m in def.methods) {
                        slots.insert(set_name(m.name));
                    }
                    break;
                }
            }
        }
        for (var m in st.method_members) {
            if (slots.contains(set_name(m.name))) {
                note.found.insert(_key(st.name, m.name));
            }
        }
    }
    return note.found;
}

struct _IndirectCalls {
    var found: HashSet<String> = HashSet<String>();

    construct() {}

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionRef(node) => {
                found.insert(node.function);
            }
            FunctionPointer(node) => {
                found.insert(
                    node.owner.is_value() ? _key(node.owner.value().to_string(), node.function) : node.function
                );
            }
            else => {}
        }
        return e;
    }
}

extend _IndirectCalls with Rewriter;

## The facts `|s=` recorded for `function`, whose body the cache skipped.
_recorded_facts(module: Module, function: FunctionDef, slots: ulong): bool[]? {
    var none = Optional<bool[]>.Empty;
    var text = module.recorded_summaries.try_get(function.loc);
    if (!text.is_value()) {
        return none;
    }
    var at = text.value().find(_FACTS);
    if (at < 0) {
        return none;
    }
    var start = at as ulong + _FACTS.size;
    var kept = Array<bool>();
    var i = start;
    while (i < text.value().size) {
        kept.append(text.value().byte_at(i) != 'f');
        i += 1;
    }
    return kept.count == slots ? Optional<bool[]>.Value(kept) : none;
}

## The local types in scope, for resolving method calls.
struct _LiteralScope {
    var locals: Array<Array<(String, TypeName)>> = Array<Array<(String, TypeName)>>();
    var current: TypeName? = Optional<TypeName>.Empty;

    construct() {}

    static of(callee: _LiteralCallee): _LiteralScope {
        var out = _LiteralScope();
        var parameters = Array<(String, TypeName)>();
        for (var p in callee.function.parameters) {
            parameters.append((p.name, p.ty));
        }
        if (callee.owner.is_value()) {
            out.current = Optional<TypeName>.Value(callee.owner.value().ty);
            parameters.append(("this", callee.owner.value().ty));
        }
        out.locals.append(parameters);
        return out;
    }

    static global(): _LiteralScope {
        var out = _LiteralScope();
        out.locals.append(Array<(String, TypeName)>());
        return out;
    }

    local(name: String): TypeName? {
        var i = locals.count;
        while (i > 0) {
            i -= 1;
            var scope = locals[i];
            var j = scope.count;
            while (j > 0) {
                j -= 1;
                var (n, t) = scope[j];
                if (n == name) {
                    return Optional<TypeName>.Value(t);
                }
            }
        }
        return Optional<TypeName>.Empty;
    }

    ty(e: Expression, table: StructTable, state: PassState): TypeName? {
        match (e) {
            SymbolRef(node) => {
                var found = local(node.id);
                if (found.is_value()) {
                    return found;
                }
            }
            ThisRef => {
                return current;
            }
            else => {}
        }
        var out = static_type_of(e, table, current, state);
        return out.is_value() and !out.value().is_auto() ? out : Optional<TypeName>.Empty;
    }

    push() {
        locals.append(Array<(String, TypeName)>());
    }

    pop() {
        locals.pop();
    }

    declare(variable: VariableDef) {
        locals[locals.count - 1].append((variable.name, variable.ty));
    }
}

## One walk over a body for the uses of one operand slot.
struct _SlotUses {
    var program: _Literals;
    var scope: _LiteralScope;
    var name: String;
    var is_this: bool;
    var kept: bool = false;

    construct(program: _Literals, scope: _LiteralScope, name: String, is_this: bool) {
        this.program = program;
        this.scope = scope;
        this.name = name;
        this.is_this = is_this;
    }

    is_slot(e: Expression): bool {
        match (e) {
            ThisRef => {
                return is_this;
            }
            SymbolRef(node) => {
                return node.id == name;
            }
            else => {
                return false;
            }
        }
    }

    block(b: Block) {
        scope.push();
        for (var s in b.items) {
            if (kept) {
                break;
            }
            statement(s);
        }
        scope.pop();
    }

    statement(s: Statement) {
        match (s) {
            Expression(e) => {
                if (!is_slot(e)) {
                    expression(e, false);
                }
            }
            Block(inner) => {
                block(inner);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.name == name) {
                        kept = true;
                    }
                    if (variable.default.is_value()) {
                        expression(variable.default.value(), false);
                    }
                    scope.declare(variable);
                }
            }
            Branch(branch) => {
                expression(branch.condition, false);
                block(branch.if_block);
                if (branch.else_block.is_value()) {
                    block(branch.else_block.value());
                }
            }
            While(loop) => {
                expression(loop.condition, false);
                block(loop.block);
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    expression(ret.expr.value(), false);
                }
            }
            # Never reaches codegen.
            Static(_) => {
                kept = true;
            }
            else => {}
        }
    }

    ## An argument: the slot itself is allowed where its parameter is free.
    argument(arg: Expression, key: String?, slot: ulong) {
        if (is_slot(arg)) {
            if (!key.is_value() or !program.argument_free(key.value(), slot)) {
                kept = true;
            }
        } else {
            expression(arg, false);
        }
    }

    ## `e`, which is written to (or through) when `write`.
    expression(e: Expression, write: bool) {
        if (kept) {
            return;
        }
        if (is_slot(e)) {
            # A use no rule below allows.
            kept = true;
            return;
        }
        match (e) {
            MemberRef(node) => {
                if (is_slot(node.lhs)) {
                    bool plain = false;
                    var ty = scope.ty(node.lhs, program.table, program.state);
                    if (ty.is_value()) {
                        var st = program.structs.try_get(ty.value().to_string());
                        if (st.is_value()) {
                            for (var f in st.value().field_members) {
                                if (f.name == node.name) {
                                    plain = f.ty.is_pointer() or is_numeric_type(program.state, f.ty.to_string());
                                    break;
                                }
                            }
                        }
                    }
                    if (write or !plain) {
                        kept = true;
                    }
                } else {
                    expression(node.lhs, write);
                }
            }
            Index(node) => {
                expression(node.lhs, write);
                expression(node.rhs, false);
            }
            ArrayIndex(node) => {
                expression(node.lhs, write);
                expression(node.rhs, false);
            }
            Binary(node) => {
                if (_is_assignment(node.op)) {
                    expression(node.lhs, true);
                    expression(node.rhs, false);
                } else if (_is_comparison(node.op)
                    and ((is_slot(node.lhs) and node.rhs is PointerLiteral)
                        or (is_slot(node.rhs) and node.lhs is PointerLiteral))) {} else {
                    children(e);
                }
            }
            Unary(node) => {
                if (_is_step(node.op)) {
                    expression(node.operand, true);
                } else {
                    children(e);
                }
            }
            ConstructAt(slot, value) => {
                expression(slot, true);
                expression(value, false);
            }
            AtomicStore(_, a, b) => {
                expression(a, true);
                expression(b, false);
            }
            AtomicFetch(_, _, a, b) => {
                expression(a, true);
                expression(b, false);
            }
            Simd(node) => {
                for (var arg in node.args) {
                    expression(arg, false);
                }
            }
            AtomicCmpXchg(_, a, b, c) => {
                expression(a, true);
                expression(b, false);
                expression(c, false);
            }
            FunctionCall(node) => {
                var key = program.resolve_function(node.function);
                ulong i = 0;
                while (i < node.args.count) {
                    argument(node.args[i], key, i);
                    i += 1;
                }
            }
            MethodCall(node) => {
                var callee = program.resolve_method(scope, node.this_value, node.method);
                if (is_slot(node.this_value)) {
                    if (!callee.is_value()
                        or callee.value().this_slot < 0
                        or !program.is_free(callee.value().key, callee.value().this_slot as ulong)) {
                        kept = true;
                    }
                } else if (!callee.is_value() or callee.value().this_slot >= 0) {
                    # A static call's receiver names a type.
                    expression(node.this_value, false);
                }
                var key = callee.is_value() ? Optional<String>.Value(callee.value().key) : Optional<String>.Empty;
                var first: ulong = callee.is_value() ? callee.value().first : 0;
                ulong i = 0;
                while (i < node.args.count) {
                    argument(node.args[i], key, first + i);
                    i += 1;
                }
            }
            else => {
                children(e);
            }
        }
    }

    children(e: Expression) {
        for (var child in expression_children(e)) {
            expression(child, false);
        }
    }
}

_is_comparison(op: BinaryOp): bool {
    match (op) {
        Equal, NotEqual, Identical, NotIdentical => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## The literal `convert_string_literals` made a constructor call, as a
## `StaticString`.
_shared_literal(e: Expression): Expression? {
    if (e is FunctionCall(call)) {
        if (_is_converted_literal(call)) {
            if (call.args[0] is StringLiteral(literal)) {
                return Optional<Expression>.Value(
                    Expression.StaticString(StaticStringExpression(literal.value, call.loc))
                );
            }
        }
    }
    return Optional<Expression>.Empty;
}

## One walk over a body that shares the literals that may be shared: each
## literal argument to a free parameter, and each literal receiver of a
## method whose `this` is free.
struct _SharedLiterals {
    var program: _Literals;
    var scope: _LiteralScope;

    construct(program: _Literals, scope: _LiteralScope) {
        this.program = program;
        this.scope = scope;
    }

    block(b: Block) {
        scope.push();
        for (var s in b.items) {
            statement(s);
        }
        scope.pop();
    }

    statement(s: Statement) {
        match (s) {
            Expression(e) => {
                expression(e);
            }
            Block(inner) => {
                block(inner);
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    if (variable.default.is_value()) {
                        expression(variable.default.value());
                    }
                    scope.declare(variable);
                }
            }
            Branch(branch) => {
                expression(branch.condition);
                block(branch.if_block);
                if (branch.else_block.is_value()) {
                    block(branch.else_block.value());
                }
            }
            While(loop) => {
                expression(loop.condition);
                block(loop.block);
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    expression(ret.expr.value());
                }
            }
            else => {}
        }
    }

    ## `e` at the root of a global's initializer, which is no argument.
    root(e: Expression): Expression {
        expression(e);
        return e;
    }

    ## `arg`, or its shared literal.
    share(arg: Expression): Expression {
        var shared = _shared_literal(arg);
        return shared.is_value() ? shared.value() : arg;
    }

    expression(e: Expression) {
        match (e) {
            FunctionCall(node) => {
                var key = program.resolve_function(node.function);
                if (key.is_value()) {
                    ulong i = 0;
                    while (i < node.args.count) {
                        if (program.argument_free(key.value(), i)) {
                            node.args[i] = share(node.args[i]);
                        }
                        i += 1;
                    }
                }
            }
            MethodCall(node) => {
                var callee = program.resolve_method(scope, node.this_value, node.method);
                if (callee.is_value()) {
                    var c = callee.value();
                    if (c.this_slot >= 0 and program.is_free(c.key, c.this_slot as ulong)) {
                        node.this_value = share(node.this_value);
                    }
                    ulong i = 0;
                    while (i < node.args.count) {
                        if (program.argument_free(c.key, c.first + i)) {
                            node.args[i] = share(node.args[i]);
                        }
                        i += 1;
                    }
                }
            }
            else => {}
        }
        for (var child in expression_children(e)) {
            expression(child);
        }
    }
}
