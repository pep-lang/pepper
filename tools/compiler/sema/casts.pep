## What a cast may convert, and the `check_casts` pass.
##
## `x as T` is a `static_cast`: a value conversion between numbers, `bool`
## and enums, a pointer to `__ptr<void>` and back, and the identity.
## `unsafe_cast<T>(x)` is a `reinterpret_cast`: a pointer to another pointer
## or an integer and back, and a number to another number of the same width
## with its bits unchanged. Neither ever applies to a refcounted reference.

import [unit_decls] from "checked";
import [bit_width, is_float_type] from "arithmetic";
import "common";
import "function_types_check";
import [Loc] from "loc";
import [CastKind, Expression, FunctionDef, Module, TypeName] from "model";
import [PassState] from "state";
import [static_type_of, StructTable] from "static_type";
import [trait_def] from "traits";
import [POINTER] from "type_name";
import "value_structs";
import [Rewriter, rewrite_block, rewrite_expression] from "walk";

## Reports the first cast that converts what its kind may not. Runs once
## every type is final and `convert_to_traits` has turned each `s as Trait`
## into a `ToTrait`. A cast whose operand has no static type here is left
## to code generation.
##
## @param module the model
## @param state the passes' state, which takes the error
export check_casts(module: Module, state: PassState) {
    # A checked declaration was walked with its unit (its body is stashed).
    var own = unit_decls(module);
    var checker = _Casts(module, state);
    var bases = _Bases(module);
    for (var f in own.functions) {
        if (f.generic_params.count == 0) {
            checker.unbound = bases.params(f.name, false);
            checker.current = Optional<TypeName>.Empty;
            checker.visit(f);
        }
    }
    for (var st in own.structs) {
        # Generic bases are checked through their specializations.
        if (_is_generic_base(st) or st.ty.is_function_type() or st.ty.is_weak()) {
            continue;
        }
        checker.unbound = bases.params(st.name, true);
        checker.current = Optional<TypeName>.Value(st.ty);
        for (var c in st.constructors) {
            checker.visit(c);
        }
        for (var m in st.method_members) {
            checker.visit(m);
        }
    }
    checker.unbound = Array<String>();
    checker.current = Optional<TypeName>.Empty;
    for (var g in module.globals) {
        if (module.checked.globals.contains(g.name)) {
            continue;
        }
        if (g.default.is_value()) {
            rewrite_expression(g.default.value(), checker);
        }
    }
}

struct _Casts {
    var module: Module;
    var state: PassState;
    var table: StructTable;
    var current: TypeName? = Optional<TypeName>.Empty;
    var unbound: Array<String> = Array<String>();

    construct(module: Module, state: PassState) {
        this.module = module;
        this.state = state;
        table = StructTable(module, memo = state.trait_types_memo());
    }

    visit(f: FunctionDef) {
        if (f.body.is_value()) {
            rewrite_block(f.body.value(), this);
        }
    }

    rewrite(e: Expression): Expression {
        if (e is Cast(node)) {
            check(node.expr, node.ty, node.kind, node.loc);
        }
        return e;
    }

    check(operand: Expression, ty: TypeName, kind: CastKind, loc: Loc) {
        if (kind == CastKind.Synthesized) {
            return;
        }
        TypeName from = TypeName.void_pointer();
        if (!_is_null(operand)) {
            var found = static_type_of(operand, table, current, state);
            if (!found.is_value() or found.value().contains_auto()) {
                return;
            }
            for (var p in unbound) {
                if (found.value().mentions(p) or ty.mentions(p)) {
                    return;
                }
            }
            from = found.value();
        }
        var message = check_cast(from, ty, kind, state);
        if (!message.is_value()) {
            return;
        }
        # A trait value may hold something else: its conversion can fail.
        var text = message.value();
        if (kind == CastKind.Static and trait_def(module.traits, from).is_value()) {
            text = $"{text}; use 'as?' to convert a trait value, which gives '{constraint_spelled(ty)}?'";
        }
        state.report(error_at(text, loc));
    }
}

extend _Casts with Rewriter;

## The kind of value a cast converts from or to.
enum _CastCategory {
    ## An integer, `bool`, or a byte read through a `void` pointer.
    Integer(width: uint),
    Float(width: uint),
    ## An enum, stored as an integer of this width.
    Enum(width: uint),
    ## `__ptr<void>`.
    VoidPointer,
    ## `__ptr<T>` for any other `T`, or a C function pointer.
    Pointer,
    ## Anything else: a struct, trait, function type, tuple or weak
    ## reference.
    Other,
}

_category(ty: TypeName, state: PassState): _CastCategory {
    var name = ty.to_string();
    if (ty.is_extern_function_type()) {
        return _CastCategory.Pointer;
    }
    if (ty.is_void_pointer()) {
        return _CastCategory.VoidPointer;
    }
    if (ty.name == POINTER) {
        return _CastCategory.Pointer;
    }
    # Indexing a `void` pointer reads one byte.
    if (name == "void") {
        return _CastCategory.Integer(8);
    }
    var representation = state.enum_representations.try_get(name);
    if (representation.is_value()) {
        var (stored, _) = representation.value();
        var width = bit_width(stored);
        return _CastCategory.Enum(width.is_value() ? width.value() : 32);
    }
    var width = bit_width(name);
    if (!width.is_value()) {
        return _CastCategory.Other;
    }
    if (is_float_type(name)) {
        return _CastCategory.Float(width.value());
    }
    return _CastCategory.Integer(width.value());
}

_is_number(c: _CastCategory): bool {
    match (c) {
        Integer(w) => {
            return true;
        }
        Float(w) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_any_pointer(c: _CastCategory): bool {
    match (c) {
        Pointer => {
            return true;
        }
        VoidPointer => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## The width of a number category, 0 for any other.
_number_width(c: _CastCategory): uint {
    match (c) {
        Integer(w) => {
            return w;
        }
        Float(w) => {
            return w;
        }
        else => {
            return 0;
        }
    }
}

_is_enum_category(c: _CastCategory): bool {
    match (c) {
        Enum(w) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_integer_category(c: _CastCategory): bool {
    match (c) {
        Integer(w) => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_void_pointer_category(c: _CastCategory): bool {
    match (c) {
        VoidPointer => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_other_category(c: _CastCategory): bool {
    match (c) {
        Other => {
            return true;
        }
        else => {
            return false;
        }
    }
}

_is_static(from: _CastCategory, to: _CastCategory): bool {
    if ((_is_number(from) or _is_enum_category(from)) and _is_number(to)) {
        return true;
    }
    # `n as E` is reported by `enums` with the case to name instead.
    if (_is_number(from) and _is_enum_category(to)) {
        return true;
    }
    if (_is_any_pointer(from) and _is_void_pointer_category(to)) {
        return true;
    }
    return _is_void_pointer_category(from) and _is_any_pointer(to) and !_is_void_pointer_category(to);
}

_is_reinterpret(from: _CastCategory, to: _CastCategory): bool {
    if (_is_any_pointer(from) and _is_any_pointer(to)) {
        return true;
    }
    if (_is_any_pointer(from) and _is_integer_category(to)) {
        return _number_width(to) > 1;
    }
    if (_is_integer_category(from) and _is_any_pointer(to)) {
        return _number_width(from) > 1;
    }
    if (_is_number(from) and _is_number(to)) {
        var a = _number_width(from);
        return a == _number_width(to) and a > 1;
    }
    return false;
}

## Returns why a cast of `kind` may not convert `from` to `to`, or none
## when it may. A synthesized cast is always allowed.
##
## @param from the operand's type
## @param to the type cast to
## @param kind the cast's kind
## @param state the passes' state, which knows the enums
## @returns the error message, or none
export check_cast(from: TypeName, to: TypeName, kind: CastKind, state: PassState): String? {
    var ok = Optional<String>.Empty;
    if (kind == CastKind.Synthesized or _canonical(from).to_string() == _canonical(to).to_string()) {
        return ok;
    }
    var source = _category(from, state);
    var target = _category(to, state);
    var from_text = constraint_spelled(from);
    var to_text = constraint_spelled(to);
    if (kind == CastKind.Static) {
        if (_is_static(source, target)) {
            return ok;
        }
        if (_is_reinterpret(source, target)) {
            return Optional<String>.Value(
                $"cannot cast '{from_text}' to '{to_text}' with 'as'; use 'unsafe_cast<{to_text}>(...)' to reinterpret"
            );
        }
        return Optional<String>.Value($"cannot cast '{from_text}' to '{to_text}'");
    }
    if (_is_reinterpret(source, target)) {
        return ok;
    }
    if (_is_other_category(source) or _is_other_category(target)) {
        return Optional<String>.Value(
            $"'unsafe_cast' cannot convert '{from_text}' to '{to_text}': it reinterprets only pointers and numbers"
        );
    }
    if (_is_static(source, target)) {
        return Optional<String>.Value(
            $"'unsafe_cast' cannot convert '{from_text}' to '{to_text}': the sizes differ; use 'as' to convert the value"
        );
    }
    return Optional<String>.Value($"'unsafe_cast' cannot convert '{from_text}' to '{to_text}'");
}
