## Type aliases (`type Name<P1, P2 = Default> = Target;`), resolved.
## Each use of an
## alias name is expanded into its target, the alias's parameters replaced
## by the use's arguments (or their defaults), so no alias name remains in
## the model.

import [Diagnostic, Location] from compiler.diagnostic;
import [unit_decls] from "checked";
import [error_at, location_of] from "common";
import [Loc] from "loc";
import [
    Block,
    CasePattern,
    Declaration,
    Expression,
    FunctionCallExpression,
    FunctionDef,
    GenericParam,
    Module,
    Statement,
    StaticItem,
    TypeAliasDef,
    TypeName
] from "model";
import [PassState] from "state";
import [parse_type_string, replace_map] from "type_name";

## Hard cap on expansion depth: legitimate chains are short; anything
## deeper is a cycle the in-flight set should have caught.
const _MAX_EXPANSION_DEPTH: ulong = 1024;

## The value-symbol names visible in a scope: its own, then its enclosing
## scopes' (globals, then a struct's fields, then a function's locals).
struct _Values {
    var parent: _Values? = Optional<_Values>.Empty;
    var names: HashSet<String> = HashSet<String>();

    construct() {}

    # A scope nested in this one.
    scope(): _Values {
        var out = _Values();
        out.parent = Optional<_Values>.Value(this);
        return out;
    }

    contains(name: String): bool {
        if (names.contains(name)) {
            return true;
        }
        return parent.is_value() and parent.value().contains(name);
    }
}

struct _Resolver {
    var state: PassState;
    # Later definitions shadow earlier ones.
    var aliases: HashMap<String, TypeAliasDef> = HashMap<String, TypeAliasDef>();

    construct(state: PassState) {
        this.state = state;
    }

    # An error in a use of `def`. Type names carry no location, so it
    # points at the alias's declaration.
    alias_error(def: TypeAliasDef, message: String): Diagnostic {
        return Diagnostic.error(
            message
        ).with_note($"type alias '{def.name}' declared here", Optional<Location>.Value(location_of(def.loc)));
    }

    # Expands one type name (and its nested arguments) to a non-alias type.
    subst(ty: TypeName) {
        var inflight = HashSet<String>();
        expand_node(ty, inflight, 0);
    }

    # Expands `ty` in place. `inflight` holds the types being expanded on
    # this descent path: meeting one again means the aliases recurse.
    expand_node(ty: TypeName, inflight: HashSet<String>, depth: ulong) {
        if (depth > _MAX_EXPANSION_DEPTH) {
            state.report(Diagnostic.error($"type alias expansion too deep for '{ty.to_string()}'"));
            return;
        }
        # Nested arguments first; each is expanded independently.
        for (var arg in ty.sub_types) {
            expand_node(arg, inflight, depth + 1);
        }
        var found = aliases.try_get(ty.name);
        if (!found.is_value()) {
            return;
        }
        var def = found.value();
        if (ty.sub_types.count > def.generic_params.count) {
            state.report(
                alias_error(
                    def,
                    $"type alias '{def.name}' takes {def.generic_params.count} type argument(s), {ty.sub_types.count} given"
                )
            );
            return;
        }
        var map = Array<(String, TypeName)>();
        ulong i = 0;
        while (i < def.generic_params.count) {
            var param = def.generic_params[i];
            if (i < ty.sub_types.count) {
                map.append((param.name, ty.sub_types[i].copy()));
            } else if (param.default.is_value()) {
                map.append((param.name, param.default.value().copy()));
            } else {
                state.report(
                    alias_error(def, $"type alias '{def.name}' requires a type argument for parameter '{param.name}'")
                );
                return;
            }
            i += 1;
        }
        var current = ty.to_string();
        if (inflight.contains(current)) {
            state.report(alias_error(def, $"type alias '{def.name}' is recursive: '{current}'"));
            return;
        }
        inflight.insert(current);
        var next = def.target.copy();
        replace_map(next, map);
        ty.assign(next);
        expand_node(ty, inflight, depth + 1);
        inflight.remove(current);
    }

    # Expands the aliases in generic parameters' constraints and defaults.
    subst_params(params: GenericParam[]) {
        for (var param in params) {
            for (var bound in param.bounds) {
                subst(bound.ty);
            }
            if (param.default.is_value()) {
                subst(param.default.value());
            }
        }
    }

    subst_function(function: FunctionDef, enclosing: _Values) {
        var values = enclosing.scope();
        subst_params(function.generic_params);
        subst(function.ty);
        for (var parameter in function.parameters) {
            subst(parameter.ty);
            values.names.insert(parameter.name);
        }
        if (function.body.is_value()) {
            var body = function.body.value();
            _collect_value_names(body, values.names);
            for (var statement in body.items) {
                subst_statement(statement, values);
            }
        }
    }

    subst_statement(statement: Statement, values: _Values) {
        match (statement) {
            Expression(value) => {
                subst_expression(value, values);
            }
            Block(block) => {
                for (var item in block.items) {
                    subst_statement(item, values);
                }
            }
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    subst(variable.ty);
                    if (variable.default.is_value()) {
                        subst_expression(variable.default.value(), values);
                    }
                }
            }
            Branch(branch) => {
                subst_expression(branch.condition, values);
                for (var item in branch.if_block.items) {
                    subst_statement(item, values);
                }
                if (branch.else_block.is_value()) {
                    for (var item in branch.else_block.value().items) {
                        subst_statement(item, values);
                    }
                }
            }
            While(loop) => {
                subst_expression(loop.condition, values);
                for (var item in loop.block.items) {
                    subst_statement(item, values);
                }
            }
            Return(ret) => {
                if (ret.expr.is_value()) {
                    subst_expression(ret.expr.value(), values);
                }
            }
            Static(block) => {
                subst_static_items(block.items, values);
            }
            else => {}
        }
    }

    subst_static_items(items: StaticItem[], values: _Values) {
        for (var item in items) {
            match (item) {
                For(node) => {
                    subst_static_items(node.body, values);
                }
                While(node) => {
                    subst_static_items(node.body, values);
                }
                Block(body) => {
                    subst_static_items(body, values);
                }
                If(node) => {
                    subst_static_items(node.then_items, values);
                    subst_static_items(node.else_items, values);
                }
                EmitIf(node) => {
                    subst_expression(node.condition, values);
                    subst_static_items(node.then_items, values);
                    subst_static_items(node.else_items, values);
                }
                Emit(statement, _) => {
                    subst_statement(statement, values);
                }
                else => {}
            }
        }
    }

    subst_pattern_qualifiers(pattern: CasePattern) {
        if (pattern.qualifier.is_value()) {
            subst(pattern.qualifier.value());
        }
        if (pattern.ty.is_value()) {
            subst(pattern.ty.value());
        }
        _for_nested(pattern, (p) => subst_pattern_qualifiers(p));
    }

    subst_pattern_literals(pattern: CasePattern, values: _Values) {
        if (pattern.literal.is_value()) {
            subst_expression(pattern.literal.value(), values);
        }
        _for_nested(pattern, (p) => subst_pattern_literals(p, values));
    }

    # Every expression that carries a type name. `values` holds the value
    # symbols visible in the scope: a name bound to one is not an alias use
    # in a call.
    subst_expression(e: Expression, values: _Values) {
        match (e) {
            SymbolRef(node) => {
                subst(node.ty);
            }
            StaticMember(member) => {
                for (var arg in member.args) {
                    subst_expression(arg, values);
                }
            }
            MemberRef(node) => {
                subst_expression(node.lhs, values);
            }
            ForIterator(value) => {
                subst_expression(value, values);
            }
            WithEntered(value) => {
                subst_expression(value, values);
            }
            Destructure(node) => {
                subst_expression(node.value, values);
            }
            NamedArgument(node) => {
                subst_expression(node.value, values);
            }
            Move(node) => {
                subst_expression(node.value, values);
            }
            CaseValue(value) => {
                subst_expression(value.subject, values);
                for (var choice in value.choices) {
                    if (choice.ty.is_value()) {
                        subst(choice.ty.value());
                    }
                }
            }
            MatchArm(test) => {
                subst_expression(test.subject, values);
                for (var p in test.patterns) {
                    subst_pattern_qualifiers(p);
                    subst_pattern_literals(p, values);
                }
            }
            WithSubject(subject) => {
                subst_expression(subject.subject, values);
                subst_expression(subject.body, values);
            }
            Subject(node) => {
                subst(node.ty);
            }
            DefaultArgument(node) => {
                subst(node.ty);
            }
            MakeClosure(node) => {
                subst(node.ty);
                subst_expression(node.value, values);
            }
            CallPointer(node) => {
                subst_expression(node.pointer, values);
                for (var arg in node.args) {
                    subst_expression(arg, values);
                }
            }
            Binary(node) => {
                subst_expression(node.lhs, values);
                subst_expression(node.rhs, values);
            }
            Unary(node) => {
                subst_expression(node.operand, values);
            }
            ToTrait(node) => {
                subst_expression(node.value, values);
                subst(node.from);
                subst(node.to);
            }
            FromTrait(node) => {
                subst_expression(node.value, values);
                subst(node.from);
                subst(node.to);
            }
            Cast(node) => {
                subst_expression(node.expr, values);
                subst(node.ty);
            }
            Ternary(node) => {
                subst_expression(node.condition, values);
                subst_expression(node.true_expr, values);
                subst_expression(node.false_expr, values);
            }
            Index(node) => {
                subst_expression(node.lhs, values);
                subst_expression(node.rhs, values);
            }
            ArrayIndex(node) => {
                subst(node.ty);
                subst_expression(node.lhs, values);
                subst_expression(node.rhs, values);
            }
            SizeOf(ty) => {
                subst(ty);
            }
            IsPod(ty) => {
                subst(ty);
            }
            Default(ty) => {
                subst(ty);
            }
            Allocate(ty) => {
                subst(ty);
            }
            StaticCase(node) => {
                subst(node.ty);
            }
            FunctionPointer(node) => {
                if (node.owner.is_value()) {
                    subst(node.owner.value());
                }
            }
            RefCount(ty, operand) => {
                subst(ty);
                subst_expression(operand, values);
            }
            Address(ty, operand) => {
                subst(ty);
                subst_expression(operand, values);
            }
            Weak(_, ty, operand) => {
                subst(ty);
                subst_expression(operand, values);
            }
            AtomicLoad(ty, operand) => {
                subst(ty);
                subst_expression(operand, values);
            }
            AtomicStore(ty, lhs, rhs) => {
                subst(ty);
                subst_expression(lhs, values);
                subst_expression(rhs, values);
            }
            ConstructAt(lhs, rhs) => {
                subst_expression(lhs, values);
                subst_expression(rhs, values);
            }
            AtomicCmpXchg(ty, lhs, mid, rhs) => {
                subst(ty);
                subst_expression(lhs, values);
                subst_expression(mid, values);
                subst_expression(rhs, values);
            }
            AtomicFetch(_, ty, lhs, rhs) => {
                subst(ty);
                subst_expression(lhs, values);
                subst_expression(rhs, values);
            }
            Simd(node) => {
                subst(node.ty);
                for (var arg in node.args) {
                    subst_expression(arg, values);
                }
            }
            FunctionCall(node) => {
                # Type positions are encoded in the call string (static
                # calls like `Result<int>.ok(..)` and explicit generic
                # arguments `g<I>(..)`). Generic arguments are always type
                # positions; the base name is one only when no value symbol
                # owns its spelling.
                var parsed = parse_type_string(node.function);
                for (var sub in parsed.sub_types) {
                    subst(sub);
                }
                if (aliases.contains(parsed.name) and !values.contains(parsed.name)) {
                    subst(parsed);
                }
                node.function = parsed.to_string();
                for (var arg in node.args) {
                    subst_expression(arg, values);
                }
            }
            MethodCall(node) => {
                # A bare alias name as a static call's receiver
                # (`Pair.ok(..)`) becomes the constructor-style call
                # (`Result<int, Error>`), unless a value owns the name.
                match (node.this_value) {
                    SymbolRef(receiver) => {
                        if (aliases.contains(receiver.id) and !values.contains(receiver.id)) {
                            var expanded = TypeName.named(receiver.id);
                            subst(expanded);
                            node.this_value = Expression.FunctionCall(
                                FunctionCallExpression(expanded.to_string(), Array<Expression>(), receiver.loc)
                            );
                        }
                    }
                    else => {}
                }
                subst_expression(node.this_value, values);
                for (var arg in node.args) {
                    subst_expression(arg, values);
                }
            }
            FunctionRef(node) => {
                subst(node.ty);
            }
            Invoke(node) => {
                subst_expression(node.callee, values);
                for (var arg in node.args) {
                    subst_expression(arg, values);
                }
            }
            else => {}
        }
    }

    # Reports the first alias (in declaration order) whose target refers
    # back to it, at its name, with a note at each alias the cycle passes
    # through, and returns whether there is one.
    report_cycle(module: Module): bool {
        for (var def in module.type_aliases) {
            var path = [def.name];
            var done = HashSet<String>();
            if (!find_cycle(def.name, path, done)) {
                continue;
            }
            var error = error_at($"type alias '{def.name}' refers to itself", def.loc);
            ulong i = 1;
            while (i < path.count) {
                error = error.with_note(
                    $"through type alias '{path[i]}', declared here",
                    Optional<Location>.Value(location_of(aliases[path[i]].loc))
                );
                i += 1;
            }
            state.report(error);
            return true;
        }
        return false;
    }

    # Depth-first from `name`, with `path` the aliases on the way: whether
    # there is a cycle back to `path[0]`.
    find_cycle(name: String, path: String[], done: HashSet<String>): bool {
        var def = aliases.try_get(name);
        if (!def.is_value()) {
            return false;
        }
        var targets = Array<String>();
        _type_names(def.value().target, targets);
        for (var next in targets) {
            if (next == path[0]) {
                return true;
            }
            if (!aliases.contains(next) or path.contains(next) or done.contains(next)) {
                continue;
            }
            path.append(next);
            if (find_cycle(next, path, done)) {
                return true;
            }
            path.pop();
            done.insert(next);
        }
        return false;
    }
}

## Applies `f` to the patterns nested in `pattern`: its elements, then its
## bindings.
_for_nested(pattern: CasePattern, f: (CasePattern) => void) {
    if (pattern.elements.is_value()) {
        for (var element in pattern.elements.value()) {
            f(element);
        }
    }
    if (pattern.bindings.is_value()) {
        for (var binding in pattern.bindings.value()) {
            f(binding);
        }
    }
}

## The names in `ty`, its own first, then its arguments'.
_type_names(ty: TypeName, out: String[]) {
    out.append(ty.name);
    for (var arg in ty.sub_types) {
        _type_names(arg, out);
    }
}

## Collects the names of every variable declared anywhere in a block tree.
## It over-approximates scope (visible in the whole function): at worst an
## alias rewrite is skipped, never a value use rewritten.
_collect_value_names(block: Block, out: HashSet<String>) {
    for (var item in block.items) {
        match (item) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    out.insert(variable.name);
                }
            }
            Block(inner) => {
                _collect_value_names(inner, out);
            }
            Branch(branch) => {
                _collect_value_names(branch.if_block, out);
                if (branch.else_block.is_value()) {
                    _collect_value_names(branch.else_block.value(), out);
                }
            }
            While(loop) => {
                _collect_value_names(loop.block, out);
            }
            else => {}
        }
    }
}

## Expands every alias use in `module` and removes the aliases, as
## `resolve_type_aliases` does; errors go to `state`.
##
## @param module the model, changed in place
## @param state the passes' state
export resolve_type_aliases(module: Module, state: PassState) {
    if (module.type_aliases.count == 0) {
        return;
    }
    var resolver = _Resolver(state);
    for (var def in module.type_aliases) {
        resolver.aliases[def.name] = def;
    }
    if (resolver.report_cycle(module)) {
        return;
    }
    # A name bound to a value (global, function) is not an alias use in a
    # call, even if an alias shares the spelling.
    var global_values = _Values();
    for (var global in module.globals) {
        global_values.names.insert(global.name);
    }
    for (var function in module.functions) {
        global_values.names.insert(function.name);
    }
    for (var global in module.globals) {
        resolver.subst(global.ty);
        if (global.default.is_value()) {
            resolver.subst_expression(global.default.value(), global_values);
        }
    }
    # A checked declaration's aliases were expanded with its compilation unit.
    var own = unit_decls(module);
    for (var function in own.functions) {
        resolver.subst_function(function, global_values);
    }
    for (var st in own.structs) {
        resolver.subst_params(st.generic_params);
        # Method bodies see the struct's fields as value symbols; field
        # defaults see globals and the fields themselves.
        var struct_values = global_values.scope();
        for (var field in st.field_members) {
            struct_values.names.insert(field.name);
        }
        for (var field in st.field_members) {
            resolver.subst(field.ty);
            if (field.default.is_value()) {
                resolver.subst_expression(field.default.value(), struct_values);
            }
        }
        for (var method in st.method_members) {
            resolver.subst_function(method, struct_values);
        }
        for (var method in st.generic_methods) {
            resolver.subst_function(method, struct_values);
        }
        for (var constructor in st.constructors) {
            resolver.subst_function(constructor, struct_values);
        }
        resolver.subst_function(st.destructor, struct_values);
        resolver.subst_function(st.acquire, struct_values);
        resolver.subst_function(st.release, struct_values);
    }
    for (var tr in module.traits) {
        resolver.subst_params(tr.generic_params);
        for (var method in tr.methods) {
            resolver.subst_function(method, global_values);
        }
    }
    for (var ext in module.extensions) {
        resolver.subst(ext.target);
        for (var t in ext.traits) {
            resolver.subst(t);
        }
        for (var (_, bound) in ext.restated) {
            resolver.subst(bound.ty);
        }
        for (var method in ext.methods) {
            resolver.subst_function(method, global_values);
        }
    }
    for (var extern_function in module.externs) {
        resolver.subst(extern_function.ty);
        for (var param in extern_function.parameters) {
            resolver.subst(param.ty);
        }
    }
    for (var spec in module.struct_specs) {
        resolver.subst(spec);
    }
    for (var spec in module.func_specs) {
        resolver.subst(spec);
    }
    # A use keeps the name it was written with (an alias's constraints are
    # checked at it); its arguments are expanded.
    for (var type_use in module.type_uses) {
        for (var arg in type_use.ty.sub_types) {
            resolver.subst(arg);
        }
    }
    for (var context in module.use_contexts) {
        resolver.subst_params(context.scope);
        if (context.extension.is_value()) {
            resolver.subst(context.extension.value());
        }
    }
    var constrained = Array<TypeAliasDef>();
    for (var alias in module.type_aliases) {
        bool bounded = false;
        for (var p in alias.generic_params) {
            if (p.bounds.count > 0) {
                bounded = true;
            }
        }
        if (bounded) {
            constrained.append(alias.copy());
        }
    }
    for (var alias in constrained) {
        resolver.subst_params(alias.generic_params);
    }
    module.constrained_aliases = constrained;
    # Aliases are expanded away; the model no longer needs them.
    module.type_aliases.clear();
}
