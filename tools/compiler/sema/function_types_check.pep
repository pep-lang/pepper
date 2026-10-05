## Values whose type does not match the typed slot they flow into:
## `check_function_types` in Pepper. Function values, numbers, enums,
## structs, pointers, weak references and C function pointers each convert
## only as their kind allows, a `void` call is never a value, and enums and
## structs take part only in the comparisons they support.

import compiler.ast;
import [Location] from compiler.diagnostic;
import [is_numeric_type] from "arithmetic";
import [IMPLICIT_ATTRIBUTE] from "builder";
import [error_at, location_of] from "common";
import [is_enum] from "enums";
import [Loc] from "loc";
import [
    BinaryOp, Block, Expression, FunctionDef, GenericParam, Module, StructDef, TypeName, UnaryOp, VariableDef
] from "model";
import [set_name] from "names";
import [op_name] from "operators";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [trait_def] from "traits";
import [AUTO, parse_type_string, replace_map, VOID, VOID_PTR] from "type_name";
import [Rewriter, rewrite_expression] from "walk";

## Reports the first value whose type does not match its slot. Runs before
## `lower_with_blocks`, so the language server reports it too.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_function_types(module: Module, state: PassState) {
    var checker = _FunctionTypes(module, state);
    for (var f in module.functions) {
        checker.unbound = _base_params(module, f.name, false);
        checker.current = Optional<TypeName>.Empty;
        checker.function(f);
    }
    for (var st in module.structs) {
        # Generic bases are checked through their specializations; the
        # synthesized function-type structs hold no user code.
        if (_is_generic_base(st) or st.ty.is_function_type() or st.ty.is_weak()) {
            continue;
        }
        checker.unbound = _base_params(module, st.name, true);
        checker.current = Optional<TypeName>.Value(st.ty);
        for (var c in st.constructors) {
            checker.function(c);
        }
        for (var m in st.method_members) {
            checker.function(m);
        }
    }
    checker.unbound = Array<String>();
    checker.current = Optional<TypeName>.Empty;
    for (var g in module.globals) {
        if (g.default.is_value()) {
            checker.variable(g, g.default.value());
        }
    }
}

## The parameter names of the generic base the specialization `name` (a
## function, or a struct when `is_struct`) came from; none for a name that
## is not a specialization.
_base_params(module: Module, name: String, is_struct: bool): String[] {
    var out = Array<String>();
    var open = name.find("<");
    if (open < 0) {
        return out;
    }
    var base = name.substr_bytes(0, open as ulong);
    if (is_struct) {
        for (var b in module.structs) {
            if (b.ty.name == base) {
                for (var p in b.generic_params) {
                    out.append(p.name);
                }
            }
        }
    } else {
        for (var f in module.functions) {
            if (f.name == base) {
                for (var p in f.generic_params) {
                    out.append(p.name);
                }
            }
        }
    }
    return out;
}

## Each generic struct with a defaulted parameter, by base name:
## `value_structs::defaulted_params`.
export defaulted_params(module: Module): HashMap<String, Array<GenericParam>> {
    var out = HashMap<String, Array<GenericParam>>();
    for (var st in module.structs) {
        for (var p in st.generic_params) {
            if (p.default.is_value()) {
                out[st.ty.name] = st.generic_params;
                break;
            }
        }
    }
    return out;
}

## `ty` spelled one way: every omitted type argument filled in from the
## generic parameter's default, and `__ptr<T>` as `T*`:
## `value_structs::fill_defaults`. Type names nest only as deep as the
## program spells them.
export fill_defaults(ty: TypeName, params: HashMap<String, Array<GenericParam>>) {
    for (var arg in ty.sub_types) {
        fill_defaults(arg, params);
    }
    if (ty.name == "__ptr" and ty.sub_types.count == 1) {
        ty.name = $"{ty.sub_types[0].to_string()}*";
        ty.sub_types = Array<TypeName>();
        return;
    }
    var generic = params.try_get(ty.name);
    if (!generic.is_value()) {
        return;
    }
    var declared = generic.value();
    var map = Array<(String, TypeName)>();
    ulong i = 0;
    while (i < declared.count and i < ty.sub_types.count) {
        map.append((declared[i].name, ty.sub_types[i]));
        i += 1;
    }
    i = ty.sub_types.count;
    while (i < declared.count) {
        var p = declared[i];
        if (!p.default.is_value()) {
            return;
        }
        var arg = p.default.value().copy();
        replace_map(arg, map);
        fill_defaults(arg, params);
        map.append((p.name, arg));
        ty.sub_types.append(arg);
        i += 1;
    }
}

## A type as Pepper code spells it: `T*` is `__ptr<T>`.
_pepper_spelling(ty: TypeName): String {
    if (ty.name.ends_with("*") and ty.sub_types.count == 0) {
        return $"__ptr<{_pepper_spelling(TypeName.named(ty.name.substr_bytes(0, ty.name.size - 1)))}>";
    }
    return ty.display();
}

_is_void_ptr(ty: TypeName): bool {
    return _canonical(ty).to_string() == VOID_PTR;
}

## A `match` arm's test, when `condition` is one: `enums::arm_test`.
_is_arm_test(condition: Expression): bool {
    match (condition) {
        MatchArm(test) => {
            return true;
        }
        Binary(node) => {
            if (node.op == BinaryOp.LogicalAnd) {
                if (node.lhs is MatchArm(test)) {
                    return test.guarded;
                }
            }
        }
        else => {}
    }
    return false;
}

## Re-parses a type some passes carry as a flat name, when it starts with
## `prefix`.
_parsed_if(ty: TypeName, prefix: String): TypeName {
    var s = ty.to_string();
    if (s.starts_with(prefix) and s.ends_with(">")) {
        return parse_type_string(s);
    }
    return ty;
}

## What a type certainly is.
enum _TypeKind {
    ## An enum: an integer that converts to nothing else.
    Enum,
    Numeric,
    Struct,
    ## A raw pointer, which converts among pointers but is never a struct.
    Pointer,
}

## How a slot reads in a message.
enum _SlotKind {
    Argument,
    ArrayElement,
    MapEntry,
    Operands,
    Assignment,
    Return,
    Variable,
    Silent,
}

## Where a value flows: names the slot in a message, and locates the error
## when the value itself has no location.
struct _FlowSlot {
    var kind: _SlotKind;
    var what: String;
    ## The function returned from, the variable initialized, or the map
    ## entry's part.
    var name: String;
    var fallback: Loc;

    construct(kind: _SlotKind, what: String, name: String, fallback: Loc) {
        this.kind = kind;
        this.what = what;
        this.name = name;
        this.fallback = fallback;
    }

    ## The message for a value of type `actual` where `expected` is.
    mismatch(expected: String, actual: String): String {
        match (kind) {
            Argument => {
                return $"cannot pass a value of type '{actual}' as {what}, which has type '{expected}'";
            }
            ArrayElement => {
                return $"array literal element has type '{actual}', but the first element's type is '{expected}'";
            }
            MapEntry => {
                return $"map literal {name} has type '{actual}', but the first {name}'s type is '{expected}'";
            }
            Operands => {
                return $"incompatible operand types ('{expected}' and '{actual}')";
            }
            Assignment => {
                return $"cannot assign a value of type '{actual}' to a variable of type '{expected}'";
            }
            Return => {
                return $"cannot return a value of type '{actual}' from '{name}', which returns '{expected}'";
            }
            Variable => {
                return $"cannot initialize variable '{name}' of type '{expected}' with a value of type '{actual}'";
            }
            Silent => {
                return "";
            }
        }
    }
}

## Collects the calls, operators and ternaries of an expression, in order.
struct _FlowNodes {
    var nodes: Array<Expression> = Array<Expression>();

    construct() {}

    rewrite(e: Expression): Expression {
        match (e) {
            FunctionCall(node) => {
                nodes.append(e);
            }
            MethodCall(node) => {
                nodes.append(e);
            }
            Invoke(node) => {
                nodes.append(e);
            }
            Binary(node) => {
                nodes.append(e);
            }
            Unary(node) => {
                nodes.append(e);
            }
            Ternary(node) => {
                nodes.append(e);
            }
            else => {}
        }
        return e;
    }
}

extend _FlowNodes with Rewriter;

struct _FunctionTypes {
    var module: Module;
    var state: PassState;
    var table: StructTable;
    ## The generic parameter names of the base being checked through a
    ## specialization, whose spelling may remain in annotations.
    var unbound: Array<String> = Array<String>();
    var defaults: HashMap<String, Array<GenericParam>>;
    var current: TypeName? = Optional<TypeName>.Empty;
    var struct_names: HashSet<String> = HashSet<String>();
    var functions: HashMap<String, FunctionDef> = HashMap<String, FunctionDef>();
    var externs: HashMap<String, Array<TypeName>> = HashMap<String, Array<TypeName>>();

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
        table = StructTable(module);
        defaults = defaulted_params(module);
        for (var st in module.structs) {
            struct_names.insert(st.name);
        }
        # The first of a name, as a search in order finds it.
        for (var f in module.functions) {
            if (!f.is_generic_func and !functions.contains(f.name)) {
                functions[f.name] = f;
            }
        }
        for (var e in module.externs) {
            if (!externs.contains(e.name)) {
                externs[e.name] = _parameter_types(e.parameters);
            }
        }
    }

    report(message: String, value: Expression, slot: _FlowSlot) {
        report_with(message, Optional<(String, Loc)>.Empty, value, slot);
    }

    report_with(message: String, note: (String, Loc)?, value: Expression, slot: _FlowSlot) {
        var own = _expression_loc(value);
        var diagnostic = error_at(message, own.is_none() ? slot.fallback : own);
        if (note.is_value()) {
            var (text, at) = note.value();
            diagnostic = diagnostic.with_note(text, Optional<Location>.Value(location_of(at)));
        }
        state.report(diagnostic);
    }

    ## Whether `ty` or one of its type arguments names a generic parameter
    ## of the base being checked.
    mentions_unbound(ty: TypeName): bool {
        for (var p in unbound) {
            if (p == ty.name) {
                return true;
            }
        }
        for (var t in ty.sub_types) {
            if (mentions_unbound(t)) {
                return true;
            }
        }
        return false;
    }

    ## `ty` canonical, with every omitted type argument filled in.
    with_defaults(ty: TypeName): TypeName {
        var filled = _canonical(ty);
        fill_defaults(filled, defaults);
        return _canonical(filled);
    }

    is_trait(ty: TypeName): bool {
        return trait_def(module.traits, ty).is_value();
    }

    ## What a type certainly is, or none when unknown here (unresolved, a
    ## generic parameter, a function).
    kind_of(ty: TypeName): _TypeKind? {
        var name = ty.to_string();
        if (name == AUTO or name.size == 0 or ty.is_function_type()) {
            return Optional<_TypeKind>.Empty;
        }
        if (name.ends_with("*") or (ty.name == "__ptr" and ty.sub_types.count == 1)) {
            return Optional<_TypeKind>.Value(_TypeKind.Pointer);
        }
        for (var p in unbound) {
            if (p == ty.name) {
                return Optional<_TypeKind>.Empty;
            }
        }
        if (is_enum(state, name)) {
            return Optional<_TypeKind>.Value(_TypeKind.Enum);
        }
        if (is_numeric_type(state, _canonical(ty).to_string())) {
            return Optional<_TypeKind>.Value(_TypeKind.Numeric);
        }
        # A trait used as a type is a reference too.
        if (struct_names.contains(name) or is_trait(ty)) {
            return Optional<_TypeKind>.Value(_TypeKind.Struct);
        }
        return Optional<_TypeKind>.Empty;
    }

    ## A non-function `value` flowing into a non-function slot.
    value_flows_into(value: Expression, expected: TypeName, slot: _FlowSlot) {
        # A tuple is a value, never a null reference.
        if (_is_null(value) and expected.is_tuple()) {
            report(slot.mismatch(_pepper_spelling(expected), "__null"), value, slot);
            return;
        }
        # Raw buffer reads (`Data[i]`) carry no reliable static type.
        match (value) {
            PointerLiteral => {
                return;
            }
            Default(ty) => {
                return;
            }
            ArrayIndex(node) => {
                return;
            }
            Index(node) => {
                return;
            }
            else => {}
        }
        var expected_kind = kind_of(expected);
        if (!expected_kind.is_value()) {
            return;
        }
        # A raw literal is the `char*` global a `String` is built from.
        bool literal = false;
        bool string_literal = false;
        match (value) {
            StringLiteral(node) => {
                literal = node.is_raw;
                string_literal = true;
            }
            FunctionCall(node) => {
                literal = _is_converted_literal(node);
            }
            else => {}
        }
        TypeName? found = Optional<TypeName>.Empty;
        if (literal and (string_literal or expected_kind.value() is Pointer)) {
            found = Optional<TypeName>.Value(TypeName.named("char*"));
        } else {
            found = static_type_of(value, table, current, state);
        }
        if (!found.is_value()) {
            return;
        }
        var actual = found.value();
        # A function value (a bound method read without a call) is never a
        # number, enum or struct.
        var function = parse_type_string(actual.to_string());
        if (function.is_function_type() and !(expected_kind.value() is Pointer)) {
            var message = slot.mismatch(_pepper_spelling(expected), function.display());
            var returned = function.function_return();
            if (function.function_params().count == 0
                and returned.is_value()
                and _same_type(returned.value(), expected)) {
                message = $"{message}; call it with '()'";
            }
            report(message, value, slot);
            return;
        }
        var actual_kind = kind_of(actual);
        if (!actual_kind.is_value()) {
            return;
        }
        bool mismatch = true;
        match (expected_kind.value()) {
            Enum => {
                if (actual_kind.value() is Enum) {
                    mismatch = _canonical(expected).name != _canonical(actual).name;
                }
            }
            Numeric => {
                if (actual_kind.value() is Numeric or actual_kind.value() is Pointer) {
                    mismatch = false;
                }
            }
            Struct => {
                if (actual_kind.value() is Struct) {
                    if (expected.is_tuple() or actual.is_tuple()) {
                        mismatch = !_same_type(expected, actual);
                    } else {
                        var e = with_defaults(expected);
                        var a = with_defaults(actual);
                        mismatch = e.name != a.name
                            or (e.sub_types.count == a.sub_types.count
                                and !e.contains_auto()
                                and !a.contains_auto()
                                and !mentions_unbound(e)
                                and !mentions_unbound(a)
                                and e.to_string() != a.to_string());
                    }
                }
            }
            Pointer => {
                if (actual_kind.value() is Pointer or actual_kind.value() is Numeric) {
                    mismatch = false;
                } else if (actual_kind.value() is Struct) {
                    mismatch = !_is_void_ptr(expected);
                }
            }
        }
        if (!mismatch) {
            return;
        }
        var message = slot.mismatch(_pepper_spelling(expected), _pepper_spelling(actual));
        var c_string = actual_kind.value() is Pointer and expected.to_string() == "String";
        if (c_string) {
            message = $"{message}; use 'String(...)' to copy a C string";
        }
        # The C-string hint already names the constructor.
        var note = c_string ? Optional<(String, Loc)>.Empty : constructor_hint(expected, actual);
        report_with(message, note, value, slot);
    }

    ## A call that returns nothing used as a value: reports it and returns
    ## true.
    void_used(value: Expression, slot: _FlowSlot): bool {
        bool call = false;
        match (value) {
            FunctionCall(node) => {
                call = true;
            }
            MethodCall(node) => {
                call = true;
            }
            Invoke(node) => {
                call = true;
            }
            else => {}
        }
        if (!call) {
            return false;
        }
        var ty = static_type_of(value, table, current, state);
        if (!(ty.is_value() and ty.value().name == VOID and ty.value().sub_types.count == 0)) {
            return false;
        }
        report($"cannot use a value of type 'void' as {slot.what}", value, slot);
        return true;
    }

    ## When `expected`'s constructor takes one `actual` but is not
    ## `[Implicit]`, a note at the constructor saying how to convert.
    constructor_hint(expected: TypeName, actual: TypeName): (String, Loc)? {
        var none = Optional<(String, Loc)>.Empty;
        var spelled = expected.to_string();
        for (var st in module.structs) {
            if (st.name != spelled and st.ty.to_string() != spelled) {
                continue;
            }
            for (var c in st.constructors) {
                if (ast.has_attribute(c.attributes, IMPLICIT_ATTRIBUTE)) {
                    if (c.parameters.count > 0) {
                        return none;
                    }
                    break;
                }
            }
            for (var c in st.constructors) {
                if (c.parameters.count == 0 or !_same_type(c.parameters[0].ty, actual)) {
                    continue;
                }
                bool rest = true;
                ulong i = 1;
                while (i < c.parameters.count) {
                    if (!c.parameters[i].default.is_value()) {
                        rest = false;
                        break;
                    }
                    i += 1;
                }
                if (rest) {
                    return Optional<(String, Loc)>.Value(
                        (
                            $"'{expected.display()}' has a constructor from '{actual.display()}': call '{expected.display()}(...)', or mark the constructor [Implicit]",
                            c.loc
                        )
                    );
                }
            }
            return none;
        }
        return none;
    }

    ## `value` flows into a slot of type `expected`.
    flows_into(value: Expression, expected: TypeName, slot: _FlowSlot) {
        # Each arm of `c ? a : b` flows into the slot.
        if (value is Ternary(node)) {
            flows_into(node.true_expr, expected, slot);
            flows_into(node.false_expr, expected, slot);
            return;
        }
        if (void_used(value, slot)
            or weak_flows_into(value, expected, slot)
            or extern_flows_into(value, expected, slot)) {
            return;
        }
        if (!expected.is_function_type()) {
            value_flows_into(value, expected, slot);
            return;
        }
        if (_is_null(value)) {
            return;
        }
        var found = static_type_of(value, table, current, state);
        if (!found.is_value()) {
            return;
        }
        var actual = parse_type_string(found.value().to_string());
        if (!actual.is_function_type()) {
            # Only a value whose type is certainly not a function is an
            # error: unsubstituted generic parameters and unresolved types
            # are left to codegen.
            var integral = actual.is_integral() or (actual.is_scalar() and is_enum(state, actual.name));
            var known = integral or struct_names.contains(actual.to_string());
            if (!known or actual.is_auto() or actual.is_pointer()) {
                return;
            }
            report(slot.mismatch(expected.display(), actual.display()), value, slot);
        } else if (!_same_type(actual, expected)) {
            report(slot.mismatch(expected.display(), actual.display()), value, slot);
        }
    }

    ## A `__weak<T>` and a `T` hold different counts, so neither converts
    ## to the other implicitly. Returns true when either side is a weak
    ## reference, which this check then covers entirely.
    weak_flows_into(value: Expression, expected_type: TypeName, slot: _FlowSlot): bool {
        var expected = _parsed_if(expected_type, "__weak<");
        if (_is_null(value)) {
            return expected.is_weak();
        }
        var found = static_type_of(value, table, current, state);
        if (!found.is_value()) {
            return expected.is_weak();
        }
        var actual = _parsed_if(found.value(), "__weak<");
        if (!actual.is_weak() and !expected.is_weak()) {
            return false;
        }
        if (actual.is_auto() or expected.is_auto() or _same_type(actual, expected)) {
            return true;
        }
        String hint = "";
        if (expected.is_weak() and expected.sub_types.count > 0 and !actual.is_weak()) {
            hint = $"; use '__weak_from<{expected.sub_types[0].display()}>(...)' to make one";
        } else if (!expected.is_weak() and actual.is_weak() and actual.sub_types.count > 0) {
            hint = $"; use '__weak_upgrade<{actual.sub_types[0].display()}>(...)' to get a strong reference";
        }
        report($"{slot.mismatch(expected.display(), actual.display())}{hint}", value, slot);
        return true;
    }

    ## A C function pointer holds a bare address: only a value of the same
    ## C function pointer type fills one, and one converts to nothing but
    ## `void*`. Returns true when either side is a C function pointer.
    extern_flows_into(value: Expression, expected_type: TypeName, slot: _FlowSlot): bool {
        var expected = _parsed_if(expected_type, "__extern_function<");
        if (_is_null(value)) {
            return expected.is_extern_function_type();
        }
        var found = static_type_of(value, table, current, state);
        if (!found.is_value()) {
            return expected.is_extern_function_type();
        }
        var actual = _parsed_if(found.value(), "__extern_function<");
        if (!actual.is_extern_function_type() and !expected.is_extern_function_type()) {
            return false;
        }
        if (actual.to_string() == AUTO or _same_type(actual, expected)) {
            return true;
        }
        if (actual.is_extern_function_type() and _canonical(expected).to_string() == VOID_PTR) {
            return true;
        }
        String hint = "";
        if (expected.is_extern_function_type() and actual.is_function_type()) {
            bool named = false;
            match (value) {
                FunctionRef(node) => {
                    named = true;
                }
                MakeClosure(node) => {
                    named = true;
                }
                else => {}
            }
            hint = named ?
                "; the parameter and return types must match exactly" :
                "; only a named function or a closure that captures nothing converts to a C function pointer";
        } else if (actual.is_extern_function_type() and expected.is_function_type()) {
            hint = "; wrap it in a closure that calls it";
        }
        report($"{slot.mismatch(expected.display(), actual.display())}{hint}", value, slot);
        return true;
    }

    ## The label and parameter types of a call of `function`.
    parameters_of_call(function: String): (String, Array<TypeName>)? {
        var f = functions.try_get(function);
        if (f.is_value()) {
            return Optional<(String, Array<TypeName>)>.Value(
                ($"argument {{}} of '{function}'", _parameter_types(f.value().parameters))
            );
        }
        var e = externs.try_get(function);
        if (e.is_value()) {
            return Optional<(String, Array<TypeName>)>.Value(($"argument {{}} of '{function}'", e.value()));
        }
        var owner = _constructor_owner(module, function);
        if (!owner.is_value()) {
            return Optional<(String, Array<TypeName>)>.Empty;
        }
        var (st, ctor) = owner.value();
        # A tuple literal's arguments are its elements, numbered as `t.0`.
        var label = st.ty.is_tuple() ? $"element {{}} of '{st.ty.display()}'" : $"argument {{}} of '{st.name}'";
        return Optional<(String, Array<TypeName>)>.Value((label, _parameter_types(ctor.parameters)));
    }

    parameters_of_method(this_type: TypeName, method: String): Array<TypeName>? {
        var key = this_type.to_string();
        for (var st in module.structs) {
            if (st.name != key) {
                continue;
            }
            for (var m in st.method_members) {
                if (m.name == method) {
                    return Optional<Array<TypeName>>.Value(_parameter_types(m.parameters));
                }
            }
            return Optional<Array<TypeName>>.Empty;
        }
        return Optional<Array<TypeName>>.Empty;
    }

    ## Checks each argument whose parameter `checked` keeps (all when
    ## `extern_only` is false; C function pointer and function parameters
    ## otherwise).
    check_arguments(label: String, params: TypeName[], args: Expression[], call: Loc, extern_only: bool) {
        ulong idx = 0;
        while (idx < params.count and idx < args.count) {
            var param = params[idx];
            if (extern_only and !param.is_extern_function_type() and !param.is_function_type()) {
                idx += 1;
                continue;
            }
            var number = label.starts_with("element ") ? idx : idx + 1;
            var what = label.replace("{}", $"{number}");
            var kind = _SlotKind.Argument;
            String part = "";
            if (label == "argument {} of '_literal_append'") {
                kind = _SlotKind.ArrayElement;
            } else if (label == "argument {} of '_literal_insert'") {
                kind = _SlotKind.MapEntry;
                part = idx == 0 ? "key" : "value";
            }
            flows_into(args[idx], param, _FlowSlot(kind, what, part, call));
            idx += 1;
        }
    }

    expression(e: Expression) {
        var collector = _FlowNodes();
        rewrite_expression(e, collector);
        for (var node in collector.nodes) {
            check_node(node);
        }
    }

    check_node(e: Expression) {
        match (e) {
            FunctionCall(node) => {
                var found = parameters_of_call(node.function);
                if (found.is_value()) {
                    var (label, params) = found.value();
                    # An extern's other parameters are C types, which code
                    # generation checks with extern-specific hints.
                    check_arguments(label, params, node.args, node.loc, externs.contains(node.function));
                }
            }
            MethodCall(node) => {
                var this_type = static_type_of(node.this_value, table, current, state);
                if (this_type.is_value()) {
                    var params = parameters_of_method(this_type.value(), node.method);
                    if (params.is_value()) {
                        check_arguments(
                            $"argument {{}} of '{node.method}'", params.value(), node.args, node.loc, false
                        );
                    }
                }
            }
            Invoke(node) => {
                var found = static_type_of(node.callee, table, current, state);
                if (!found.is_value() or !found.value().is_function_type()) {
                    return;
                }
                var fn_ty = found.value();
                var params = fn_ty.function_params();
                var at = _expression_loc(node.callee);
                if (node.args.count != params.count) {
                    var many = node.args.count > params.count ? "many" : "few";
                    report(
                        $"too {many} arguments to function of type '{fn_ty.display()}': expected {params.count}, have {node.args.count}",
                        node.callee,
                        _FlowSlot(_SlotKind.Silent, "", "", at)
                    );
                } else {
                    check_arguments(
                        $"argument {{}} of a call through '{fn_ty.display()}'", params, node.args, at, false
                    );
                }
            }
            Binary(node) => {
                if (node.op == BinaryOp.Assign) {
                    # A raw buffer slot (`Data[i] = v`) has no reliable
                    # static type.
                    bool raw_slot = false;
                    match (node.lhs) {
                        Index(index) => {
                            raw_slot = true;
                        }
                        ArrayIndex(index) => {
                            raw_slot = true;
                        }
                        else => {}
                    }
                    var lhs_type = static_type_of(node.lhs, table, current, state);
                    if (lhs_type.is_value() and (!raw_slot or lhs_type.value().is_function_type())) {
                        flows_into(
                            node.rhs,
                            lhs_type.value(),
                            _FlowSlot(_SlotKind.Assignment, "the value of an assignment", "", node.loc)
                        );
                    }
                    return;
                }
                var slot = _FlowSlot(_SlotKind.Silent, "an operand", "", node.loc);
                void_used(node.lhs, slot);
                void_used(node.rhs, slot);
                enum_operands(node.op, node.lhs, node.rhs, node.loc);
                struct_with_integer(node.op, node.lhs, node.rhs, node.loc);
            }
            Unary(node) => {
                void_used(node.operand, _FlowSlot(_SlotKind.Silent, "an operand", "", node.loc));
                if (node.op != UnaryOp.LogicalNot) {
                    var ty = static_type_of(node.operand, table, current, state);
                    if (ty.is_value() and is_enum(state, ty.value().name)) {
                        state.report(
                            error_at(
                                $"invalid operand to unary expression ('{ty.value().display()}'): an enum only compares with '==' and '!='",
                                node.loc
                            )
                        );
                    }
                }
            }
            # `c ? a : b` has the true arm's type, so the false arm must
            # convert to it. A `match` expression's arms are checked by
            # `enums::check_arm_types`.
            Ternary(node) => {
                if (_is_arm_test(node.condition)) {
                    return;
                }
                var true_type = static_type_of(node.true_expr, table, current, state);
                if (!true_type.is_value()) {
                    return;
                }
                flows_into(
                    node.false_expr,
                    true_type.value(),
                    _FlowSlot(_SlotKind.Operands, "an operand of '?:'", "", _expression_loc(node.false_expr))
                );
            }
            else => {}
        }
    }

    ## An enum takes part only in `==` and `!=` with a value of the same
    ## enum (and in `===`/`!==`, which compare raw values).
    enum_operands(op: BinaryOp, lhs: Expression, rhs: Expression, loc: Loc) {
        if (op == BinaryOp.LogicalAnd or op == BinaryOp.LogicalOr) {
            return;
        }
        var l = static_type_of(lhs, table, current, state);
        var r = static_type_of(rhs, table, current, state);
        var lhs_enum = l.is_value() and is_enum(state, l.value().name);
        var rhs_enum = r.is_value() and is_enum(state, r.value().name);
        if ((!lhs_enum and !rhs_enum) or !l.is_value() or !r.is_value()) {
            return;
        }
        var comparison = op == BinaryOp.Equal
            or op == BinaryOp.NotEqual
            or op == BinaryOp.Identical
            or op == BinaryOp.NotIdentical;
        if (!comparison) {
            state.report(
                error_at(
                    $"invalid operands to binary expression ('{l.value().display()}' and '{r.value().display()}'): an enum only compares with '==' and '!='",
                    loc
                )
            );
        } else if (!_same_type(l.value(), r.value())) {
            state.report(
                error_at(
                    $"cannot compare a value of type '{l.value().display()}' with a value of type '{r.value().display()}'",
                    loc
                )
            );
        }
    }

    ## A struct value never equals an integer: `a.find(x) == -1` would
    ## compare the object's address. A struct that declares `==` or `!=`
    ## itself decides.
    struct_with_integer(op: BinaryOp, lhs: Expression, rhs: Expression, loc: Loc) {
        if (op != BinaryOp.Equal and op != BinaryOp.NotEqual) {
            return;
        }
        var l = static_type_of(lhs, table, current, state);
        var r = static_type_of(rhs, table, current, state);
        if (!l.is_value() or !r.is_value()) {
            return;
        }
        var name = op_name(op);
        TypeName? structure = Optional<TypeName>.Empty;
        if (is_struct_operand(l.value(), name) and is_integer(r.value())) {
            structure = l;
        } else if (is_struct_operand(r.value(), name) and is_integer(l.value())) {
            structure = r;
        } else {
            return;
        }
        # The binary node starts at its operator: point at just the operator.
        var end = loc.span.start + name.size;
        if (loc.span.end < end) {
            end = loc.span.end;
        }
        var at = Loc.at(loc.file, ast.Span(loc.span.start, end));
        state.report(error_at($"cannot compare '{structure.value().display()}' with an integer", at));
    }

    is_integer(t: TypeName): bool {
        return t.is_scalar() and t.name != "bool" and !is_enum(state, t.name) and is_numeric_type(state, t.name);
    }

    is_struct_operand(t: TypeName, op: String): bool {
        if (t.is_pointer() or is_enum(state, t.name)) {
            return false;
        }
        var info = table.structs.try_get(t.to_string());
        return info.is_value() and !info.value().methods.contains(op);
    }

    block(body: Block, function: FunctionDef) {
        # A `with` block is [scope, value = scope.enter(), Branch(WithEntered)]
        # until `lower_with_blocks`, which explains a `void` binding itself.
        String? with_value = Optional<String>.Empty;
        if (body.items.count == 3) {
            if (body.items[0] is Declaration(first)) {
                if (first is Variable(scope)) {
                    if (body.items[1] is Declaration(second)) {
                        if (second is Variable(bound)) {
                            if (body.items[2] is Branch(branch)) {
                                if (branch.condition is WithEntered(entered)) {
                                    with_value = Optional<String>.Value(bound.name);
                                }
                            }
                        }
                    }
                }
            }
        }
        for (var statement in body.items) {
            match (statement) {
                Expression(e) => {
                    expression(e);
                }
                Block(inner) => {
                    block(inner, function);
                }
                Declaration(declaration) => {
                    if (declaration is Variable(variable)) {
                        # A constructor's synthesized `this` is initialized
                        # from the raw allocation.
                        if (variable.name != "this" and variable.default.is_value()) {
                            expression(variable.default.value());
                            if (!(with_value.is_value() and with_value.value() == variable.name)) {
                                this.variable(variable, variable.default.value());
                            }
                        }
                    }
                }
                Branch(branch) => {
                    expression(branch.condition);
                    condition(branch.condition);
                    block(branch.if_block, function);
                    if (branch.else_block.is_value()) {
                        block(branch.else_block.value(), function);
                    }
                }
                While(loop) => {
                    expression(loop.condition);
                    condition(loop.condition);
                    block(loop.block, function);
                }
                Return(ret) => {
                    if (ret.expr.is_value()) {
                        expression(ret.expr.value());
                        flows_into(
                            ret.expr.value(),
                            function.ty,
                            _FlowSlot(
                                _SlotKind.Return, $"the return value of '{function.name}'", function.name, ret.loc
                            )
                        );
                    } else if (function.ty.to_string() != VOID and !ret.loc.is_none()) {
                        state.report(error_at($"non-void function '{function.name}' should return a value", ret.loc));
                    }
                }
                else => {}
            }
        }
    }

    ## A `void` call cannot be an `if` or `while` condition.
    condition(e: Expression) {
        void_used(e, _FlowSlot(_SlotKind.Silent, "a condition", "", _expression_loc(e)));
    }

    ## A variable's initializer flows into the variable.
    variable(v: VariableDef, default: Expression) {
        var fallback = v.type_loc.is_none() ? v.loc : v.type_loc;
        flows_into(default, v.ty, _FlowSlot(_SlotKind.Variable, $"variable '{v.name}'", v.name, fallback));
    }

    function(f: FunctionDef) {
        if (f.is_generic_func or !f.body.is_value()) {
            return;
        }
        block(f.body.value(), f);
    }
}

## The struct and constructor a call of `function` names:
## `Module::constructor_of`.
_constructor_owner(module: Module, function: String): (StructDef, FunctionDef)? {
    var ty = set_name(function);
    for (var st in module.structs) {
        if (st.name != ty and st.ty.to_string() != ty) {
            continue;
        }
        for (var c in st.constructors) {
            if (c.name == function) {
                return Optional<(StructDef, FunctionDef)>.Value((st, c));
            }
        }
        if (st.constructors.count == 1) {
            return Optional<(StructDef, FunctionDef)>.Value((st, st.constructors[0]));
        }
        return Optional<(StructDef, FunctionDef)>.Empty;
    }
    return Optional<(StructDef, FunctionDef)>.Empty;
}
