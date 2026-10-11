## Struct specializations: `specialize_structs`. Each requested `Box<int>`
## is cloned from its generic base, the frozen template once the constraints
## are checked, with the type arguments substituted into its fields, methods
## and bodies.

import compiler.diagnostic;
import [Diagnostic] from compiler.diagnostic;
import [OVERLOAD_SEPARATOR] from compiler.link;
import [enum_method_name, payload_field] from "builder";
import [is_checked_function] from "checked";
import [error_at, location_of] from "common";
import [Conformance, withhold] from "constraints";
import [defer_methods] from "lazy_methods";
import [Loc] from "loc";
import [
    BinaryOp,
    Block,
    CasePattern,
    Declaration,
    Expression,
    FunctionDef,
    Module,
    SpecRequest,
    Statement,
    StructDef,
    Templates,
    TypeName,
    Withheld
] from "model";
import [set_name] from "names";
import [PassState] from "state";
import [apply_synthesized] from "synthesize";
import [replace_map, VOID] from "type_name";
import [method_is_static, substitute_block, value_type_key] from "value_types";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## How long a chain of specializations asking for each other may get.
const _SPECIALIZATION_LIMIT: ulong = 64;

## Freezes `module`'s generic bases. The templates of checked bases (a
## reused runtime's) stay as they were frozen when it was checked.
##
## @param module the model
## @returns the templates
export freeze_templates(module: Module): Templates {
    var templates = module.templates.copy();
    templates.frozen = true;
    for (var st in module.structs) {
        if (st.ty.is_generic() and st.name == st.ty.name and !module.checked.structs.contains(st.name)) {
            templates.structs.append(st.copy());
        }
    }
    for (var f in module.functions) {
        if (f.is_generic_func and !is_checked_function(module, f)) {
            templates.functions.append(f.copy());
        }
    }
    return templates;
}

## Clones each requested struct specialization from its generic base.
##
## @param module the model
## @param state the passes' state, which takes the first error
export specialize_structs(module: Module, state: PassState) {
    var specs = module.struct_specs.copy();
    # Constrained extensions give their members only to specializations
    # whose arguments meet their constraints.
    var conformance = Optional<Conformance>.Empty;
    for (var e in module.extensions) {
        if (e.restated.count > 0) {
            conformance = Optional<Conformance>.Value(Conformance(module, state));
            break;
        }
    }
    # The structs there are, by name and by spelled type, and the first
    # generic base of each name: looked up once per spec.
    var existing = HashSet<String>();
    for (var st in module.structs) {
        existing.insert(st.name);
        existing.insert(st.ty.to_string());
    }
    var bases = HashMap<String, StructDef>();
    for (var st in module.templates.frozen ? module.templates.structs : module.structs) {
        if (st.ty.is_generic() and !bases.contains(st.name)) {
            bases[st.name] = st;
        }
    }
    for (var spec in specs) {
        if (existing.contains(spec.to_string())) {
            continue;
        }
        if (specialization_too_deep(module, spec, state)) {
            return;
        }
        var found = bases.try_get(spec.name);
        if (!found.is_value()) {
            continue;
        }
        var base = Optional<StructDef>.Value(found.value().copy());
        var specialized = _specialize_struct(base.value(), spec, state);
        if (conformance.is_value()) {
            var withheld = withhold(module, conformance.value(), base.value(), specialized);
            # A withheld member leaves its overload set.
            var sets = module.method_overload_sets.try_get(specialized.name);
            if (sets.is_value()) {
                var emptied = Array<String>();
                for (var (set, members) in sets.value()) {
                    var kept = Array<String>();
                    for (var m in members) {
                        bool gone = false;
                        for (var w in withheld) {
                            if (w.name == m) {
                                gone = true;
                                break;
                            }
                        }
                        if (!gone) {
                            kept.append(m);
                        }
                    }
                    members.clear();
                    members.append_all(kept);
                    if (members.count == 0) {
                        emptied.append(set);
                    }
                }
                for (var set in emptied) {
                    sets.value().remove(set);
                }
            }
            module.withheld.append_all(withheld);
        }
        # The synthesized members (counting, release) of the new instance.
        apply_synthesized(specialized);
        defer_methods(module, specialized, state);
        module.structs.append(specialized);
        existing.insert(specialized.name);
        existing.insert(specialized.ty.to_string());
    }
}

## Reports a specialization whose chain of requests is longer than the
## limit.
##
## @param module the model
## @param spec the specialization
## @param state the passes' state, which takes the error
## @returns true when it is too deep
export specialization_too_deep(module: Module, spec: TypeName, state: PassState): bool {
    var chain = Array<SpecRequest>();
    var name = spec.to_string();
    while (true) {
        var request = module.spec_requests.try_get(name);
        if (!request.is_value()) {
            break;
        }
        chain.append(request.value());
        if (chain.count > _SPECIALIZATION_LIMIT) {
            break;
        }
        name = request.value().by;
    }
    if (chain.count <= _SPECIALIZATION_LIMIT) {
        return false;
    }
    var error = error_at(
        $"'{spec.name}' is specialized {chain.count} levels deep, past the limit of {_SPECIALIZATION_LIMIT}; a generic whose instance asks for a larger instance of itself never ends",
        chain[0].loc
    );
    # The chain usually repeats one place (a field asking for its own type
    # with a larger argument): each place once, innermost first.
    var shown = Array<Loc>();
    shown.append(chain[0].loc);
    ulong i = 1;
    while (i < chain.count) {
        var request = chain[i];
        i += 1;
        bool seen = false;
        for (var at in shown) {
            if (at == request.loc) {
                seen = true;
                break;
            }
        }
        if (!seen) {
            shown.append(request.loc);
            error = error.with_note(
                $"asked for by '{request.by}' here", Optional<diagnostic.Location>.Value(location_of(request.loc))
            );
        }
    }
    state.report(error);
    return true;
}

_specialize_struct(base: StructDef, spec_type: TypeName, state: PassState): StructDef {
    var type_map = Array<(String, TypeName)>();
    ulong index = 0;
    while (index < base.generic_params.count) {
        var param = base.generic_params[index];
        # Missing arguments fall back to the parameter's default.
        if (index < spec_type.sub_types.count) {
            type_map.append((param.name, spec_type.sub_types[index]));
        } else if (param.default.is_value()) {
            type_map.append((param.name, param.default.value()));
        }
        index += 1;
    }
    var specialized = StructDef(
        name = spec_type.to_string(),
        ty = spec_type.copy(),
        traits = Array<TypeName>(),
        attributes = base.attributes,
        loc = base.loc,
        enum_cases = base.enum_cases
    );
    # Declared traits name the parameters too (`extend Box<T> with
    # Iterator<T>` gives `Box<int>` the trait `Iterator<int>`).
    for (var t in base.traits) {
        replace_map(t, type_map);
        specialized.traits.append(t);
    }
    for (var field in base.field_members) {
        replace_map(field.ty, type_map);
        specialized.field_members.append(field);
    }
    # A field's name is a value in every method, never the type parameter a
    # static call names.
    var fields = Array<String>();
    for (var f in base.field_members) {
        fields.append(f.name);
    }
    # A generic method keeps its own type parameters (`map<U>` of
    # `Box<int>`).
    for (var m in base.generic_methods) {
        for (var p in m.generic_params) {
            for (var bound in p.bounds) {
                replace_map(bound.ty, type_map);
            }
        }
        _substitute_function(m, type_map);
        rewrite_static_calls(m, type_map, fields, state);
        specialized.generic_methods.append(m);
    }
    for (var m in base.method_members) {
        _substitute_function(m, type_map);
        rewrite_static_calls(m, type_map, fields, state);
        specialized.method_members.append(m);
    }
    # A single constructor is named after the specialized type; an overload
    # set keeps its ordinal (`Box<T>$2` is `Box<int>$2`).
    var base_name = base.ty.to_string();
    for (var ctor in base.constructors) {
        var original = ctor.name;
        _substitute_function(ctor, type_map);
        rewrite_static_calls(ctor, type_map, fields, state);
        ctor.name = spec_type.to_string();
        if (original.starts_with(base_name)) {
            var suffix = original.substr_bytes(base_name.size, original.size - base_name.size);
            if (suffix.starts_with(OVERLOAD_SEPARATOR)) {
                ctor.name = spec_type.to_string() + suffix;
            }
        }
        specialized.constructors.append(ctor);
    }
    var destructor = base.destructor;
    if (destructor.body.is_value()) {
        substitute_block(destructor.body.value(), type_map);
    }
    rewrite_static_calls(destructor, type_map, fields, state);
    specialized.destructor = destructor;
    var acquire = base.acquire;
    if (acquire.body.is_value()) {
        substitute_block(acquire.body.value(), type_map);
    }
    specialized.acquire = acquire;
    var release = base.release;
    if (release.body.is_value()) {
        substitute_block(release.body.value(), type_map);
    }
    specialized.release = release;
    _erase_void(specialized);
    return specialized;
}

## Substitutes `type_map` into `f`'s return type, parameters and body.
_substitute_function(f: FunctionDef, type_map: Array<(String, TypeName)>) {
    replace_map(f.ty, type_map);
    for (var p in f.parameters) {
        replace_map(p.ty, type_map);
        if (p.default.is_value()) {
            _substitute_expression(p.default.value(), type_map);
        }
    }
    if (f.body.is_value()) {
        substitute_block(f.body.value(), type_map);
    }
}

## Rewrites each static call through a type parameter in `function`'s body
## (`T.unit()`) to name its type argument: `Square.unit()`, and
## `Box<int>.make()` as a type literal. A parameter, local or field
## (`fields`) of that name is a value, not the type, anywhere in the
## function.
##
## @param function the function, changed in place
## @param type_map the parameters and their types
## @param fields the enclosing struct's fields
## @param state the passes' state, for value types' static methods
export rewrite_static_calls(
    function: FunctionDef, type_map: Array<(String, TypeName)>, fields: String[], state: PassState
) {
    if (!function.body.is_value()) {
        return;
    }
    var values = HashSet<String>();
    for (var f in fields) {
        values.insert(f);
    }
    for (var p in function.parameters) {
        values.insert(p.name.starts_with("this.") ? p.name.substr_bytes(5, p.name.size - 5) : p.name);
    }
    _collect_local_names(function.body.value(), values);
    var map = Array<(String, TypeName)>();
    for (var (p, ty) in type_map) {
        if (!values.contains(p)) {
            map.append((p, ty));
        }
    }
    if (map.count == 0) {
        return;
    }
    rewrite_block(function.body.value(), _StaticCallRewriter(map, state));
}

_collect_local_names(block: Block, out: HashSet<String>) {
    for (var item in block.items) {
        match (item) {
            Declaration(declaration) => {
                if (declaration is Variable(variable)) {
                    out.insert(variable.name);
                }
            }
            Block(inner) => {
                _collect_local_names(inner, out);
            }
            Branch(branch) => {
                _collect_local_names(branch.if_block, out);
                if (branch.else_block.is_value()) {
                    _collect_local_names(branch.else_block.value(), out);
                }
            }
            While(loop) => {
                _collect_local_names(loop.block, out);
            }
            else => {}
        }
    }
}

struct _StaticCallRewriter {
    var map: Array<(String, TypeName)>;
    var state: PassState;

    construct(map: Array<(String, TypeName)>, state: PassState) {
        this.map = map;
        this.state = state;
    }

    _type_of(name: String): TypeName? {
        for (var (p, ty) in map) {
            if (p == name) {
                return Optional<TypeName>.Value(ty);
            }
        }
        return Optional<TypeName>.Empty;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionCall(node) => {
                # A constructor through a type parameter: `T()` is `Point()`.
                var ty = _type_of(node.function);
                if (ty.is_value()) {
                    node.function = ty.value().to_string();
                }
            }
            MethodCall(node) => {
                if (node.this_value is SymbolRef(symbol)) {
                    var ty = _type_of(symbol.id);
                    if (!ty.is_value()) {
                        return e;
                    }
                    # A value type's static method is its function `X::m`.
                    var key = value_type_key(state, ty.value().to_string());
                    if (key.is_value()) {
                        var is_static = method_is_static(state, key.value(), node.method);
                        if (is_static.is_value() and is_static.value()) {
                            return Expression.FunctionCall(
                                FunctionCallExpression(
                                    function = enum_method_name(key.value(), node.method),
                                    args = node.args,
                                    loc = node.loc
                                )
                            );
                        }
                    }
                    if (ty.value().sub_types.count == 0) {
                        symbol.id = ty.value().to_string();
                    } else {
                        node.this_value = Expression.FunctionCall(
                            FunctionCallExpression(function = ty.value().to_string(), loc = symbol.loc)
                        );
                    }
                }
            }
            else => {}
        }
        return e;
    }
}

_is_void(ty: TypeName): bool {
    return ty.name == VOID and ty.sub_types.count == 0;
}

## A `void` type argument (`Result<void>`) erases what it types: fields and parameters of type
## `void`, the statements that only move them, an enum case's value of that
## type with its field, and the arguments that pass one.
_erase_void(st: StructDef) {
    var fields = Array<String>();
    for (var f in st.field_members) {
        if (_is_void(f.ty)) {
            fields.append(f.name);
        }
    }
    bool params = false;
    for (var m in st.method_members) {
        params = params or _has_void_parameter(m);
    }
    for (var c in st.constructors) {
        params = params or _has_void_parameter(c);
    }
    if (fields.count == 0 and !params) {
        return;
    }
    var kept_fields = Array<VariableDef>();
    for (var f in st.field_members) {
        if (!_is_void(f.ty)) {
            kept_fields.append(f);
        }
    }
    st.field_members = kept_fields;
    # An enum case's value of type `void` goes with its field (`Ok(value:
    # TValue)` in `Result<void>` is `Ok`).
    var void_values = Array<(String, ulong[])>();
    if (st.enum_cases.is_value()) {
        for (var c in st.enum_cases.value()) {
            var erased = Array<ulong>();
            ulong i = 0;
            while (i < c.payload.count) {
                var (value_name, _) = c.payload[i];
                if (fields.contains(payload_field(c.name, value_name))) {
                    erased.append(i);
                }
                i += 1;
            }
            if (erased.count > 0) {
                var kept = Array<(String, Loc)>();
                ulong j = 0;
                while (j < c.payload.count) {
                    if (!erased.contains(j)) {
                        kept.append(c.payload[j]);
                    }
                    j += 1;
                }
                c.payload = kept;
                void_values.append((c.name, erased));
            }
        }
    }
    for (var m in st.method_members) {
        _erase_void_function(m, fields, void_values);
    }
    for (var c in st.constructors) {
        _erase_void_function(c, fields, void_values);
    }
}

_has_void_parameter(f: FunctionDef): bool {
    for (var p in f.parameters) {
        if (_is_void(p.ty)) {
            return true;
        }
    }
    return false;
}

_erase_void_function(f: FunctionDef, fields: String[], void_values: Array<(String, ulong[])>) {
    var params = Array<String>();
    var kept = Array<VariableDef>();
    for (var p in f.parameters) {
        if (_is_void(p.ty)) {
            params.append(p.name);
        } else {
            kept.append(p);
        }
    }
    f.parameters = kept;
    bool returns_void = _is_void(f.ty);
    if (f.body.is_value()) {
        _erase_void_values(f.body.value(), void_values, params);
        rewrite_block(f.body.value(), _VoidArgumentEraser(params, fields));
        _erase_void_block(f.body.value(), fields, params, returns_void);
    }
}

_erased_of(void_values: Array<(String, ulong[])>, case: String): ulong[]? {
    for (var (c, erased) in void_values) {
        if (c == case) {
            return Optional<ulong[]>.Value(erased);
        }
    }
    return Optional<ulong[]>.Empty;
}

## Erases the `void` values of enum cases from a body: a binding of one (a
## local holding a `CaseValue`) is removed and its name added to `erased`,
## and patterns and the other bindings no longer count it.
_erase_void_values(block: Block, void_values: Array<(String, ulong[])>, erased: String[]) {
    if (void_values.count == 0) {
        return;
    }
    var kept = Array<Statement>();
    for (var item in block.items) {
        bool keep = true;
        if (item is Declaration(declaration)) {
            if (declaration is Variable(variable)) {
                if (variable.default.is_value()) {
                    if (variable.default.value() is CaseValue(value)) {
                        for (var choice in value.choices) {
                            var gone = _erased_of(void_values, choice.case);
                            if (gone.is_value() and gone.value().contains(choice.index)) {
                                keep = false;
                            }
                        }
                    }
                }
                if (!keep) {
                    erased.append(variable.name);
                }
            }
        }
        if (keep) {
            kept.append(item);
        }
    }
    block.items = kept;
    for (var item in block.items) {
        match (item) {
            Block(inner) => {
                _erase_void_values(inner, void_values, erased);
            }
            Branch(branch) => {
                _erase_void_values(branch.if_block, void_values, erased);
                if (branch.else_block.is_value()) {
                    _erase_void_values(branch.else_block.value(), void_values, erased);
                }
            }
            While(loop) => {
                _erase_void_values(loop.block, void_values, erased);
            }
            else => {}
        }
    }
    rewrite_block(block, _VoidValueEraser(void_values));
}

struct _VoidValueEraser {
    var void_values: Array<(String, ulong[])>;

    construct(void_values: Array<(String, ulong[])>) {
        this.void_values = void_values;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            MatchArm(arm) => {
                for (var pattern in arm.patterns) {
                    var gone = _erased_of(void_values, pattern.case);
                    if (!gone.is_value() or !pattern.bindings.is_value()) {
                        continue;
                    }
                    var bindings = pattern.bindings.value();
                    var kept = Array<CasePattern>();
                    ulong i = 0;
                    while (i < bindings.count) {
                        if (!gone.value().contains(i)) {
                            kept.append(bindings[i]);
                        }
                        i += 1;
                    }
                    pattern.bindings = Optional<Array<CasePattern>>.Value(kept);
                }
            }
            CaseValue(value) => {
                for (var choice in value.choices) {
                    var gone = _erased_of(void_values, choice.case);
                    if (!gone.is_value()) {
                        continue;
                    }
                    ulong before = 0;
                    for (var i in gone.value()) {
                        if (i < choice.index) {
                            before += 1;
                        }
                    }
                    choice.index -= before;
                    var kept = Array<Loc>();
                    ulong i = 0;
                    while (i < choice.bindings.count) {
                        if (!gone.value().contains(i)) {
                            kept.append(choice.bindings[i]);
                        }
                        i += 1;
                    }
                    choice.bindings = kept;
                }
            }
            else => {}
        }
        return e;
    }
}

## Whether `e` is a removed parameter or binding, a removed field of
## `this`, or (when `defaults`) the default of `void`.
_is_erased(e: Expression, params: String[], fields: String[], defaults: bool): bool {
    match (e) {
        SymbolRef(node) => {
            return params.contains(node.id);
        }
        MemberRef(node) => {
            return node.lhs is ThisRef and fields.contains(node.name);
        }
        Default(ty) => {
            return defaults and _is_void(ty);
        }
        else => {
            return false;
        }
    }
}

## Drops the arguments that are erased values from every call in a body:
## the parameters they fill were erased too.
struct _VoidArgumentEraser {
    var params: String[];
    var fields: String[];

    construct(params: String[], fields: String[]) {
        this.params = params;
        this.fields = fields;
    }

    _kept(args: Expression[]): Expression[] {
        var out = Array<Expression>();
        for (var a in args) {
            if (!_is_erased(a, params, fields, true)) {
                out.append(a);
            }
        }
        return out;
    }

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionCall(node) => {
                node.args = _kept(node.args);
            }
            MethodCall(node) => {
                node.args = _kept(node.args);
            }
            else => {}
        }
        return e;
    }
}

_erase_void_block(block: Block, fields: String[], params: String[], returns_void: bool) {
    # A call stored into a removed field still runs: `this.Value = body()`
    # becomes `body();`.
    ulong i = 0;
    while (i < block.items.count) {
        if (block.items[i] is Expression(e)) {
            if (e is Binary(node)) {
                if (node.op == BinaryOp.Assign
                    and node.lhs is MemberRef(_)
                    and _is_erased(node.lhs, params, fields, false)) {
                    if (node.rhs is FunctionCall(_) or node.rhs is MethodCall(_) or node.rhs is Invoke(_)) {
                        block.items[i] = Statement.Expression(node.rhs);
                    }
                }
            }
        }
        i += 1;
    }
    var kept = Array<Statement>();
    for (var item in block.items) {
        bool keep = true;
        if (item is Expression(e)) {
            if (e is Binary(node)) {
                if (node.op == BinaryOp.Assign) {
                    bool field_store = node.lhs is MemberRef(_) and _is_erased(node.lhs, params, fields, false);
                    bool param_value = node.rhs is SymbolRef(_) and _is_erased(node.rhs, params, fields, false);
                    keep = !(field_store or param_value);
                }
            }
        }
        if (keep) {
            kept.append(item);
        }
    }
    block.items = kept;
    for (var item in block.items) {
        match (item) {
            Block(inner) => {
                _erase_void_block(inner, fields, params, returns_void);
            }
            Branch(branch) => {
                _erase_void_block(branch.if_block, fields, params, returns_void);
                if (branch.else_block.is_value()) {
                    _erase_void_block(branch.else_block.value(), fields, params, returns_void);
                }
            }
            While(loop) => {
                _erase_void_block(loop.block, fields, params, returns_void);
            }
            Return(ret) => {
                if (returns_void and ret.expr.is_value() and _is_erased(ret.expr.value(), params, fields, false)) {
                    ret.expr = Optional<Expression>.Empty;
                }
            }
            else => {}
        }
    }
}

extend _StaticCallRewriter with Rewriter;
extend _VoidValueEraser with Rewriter;
extend _VoidArgumentEraser with Rewriter;
