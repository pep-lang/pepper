## Expression types and reference counting: what an expression's value is
## (`value_sema_type`), whether it reads or owns a reference, and the
## acquire, release and store steps of a reference slot; also the element
## types of indexed receivers, and the head counts every object starts with.

import llvm;
import compiler.sema;
import [BinaryOp, CountField, Expression, PassState, WeakOp] from compiler.sema;
import [Address, check_store_type] from "address";
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import [Generator, ScopeSlot, Temporary] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "simd";
import "traits";
import [is_object] from "types";
import "types";

## A present string.
_some(text: String): String? {
    return Optional<String>.Value(text);
}

## The part of `name` before its first `<` (`split('<').next()`): the whole
## name when it has none.
_base_name(name: String): String {
    var open = name.find("<");
    if (open < 0) {
        return name;
    }
    return name.substr_bytes(0, open as ulong);
}

## The byte offset of a head count in every object: the strong count at 0,
## the weak count at 4.
export count_field_offset(field: CountField): ulong {
    match (field) {
        Strong => {
            return 0;
        }
        Weak => {
            return 4;
        }
    }
}

## True when the expression codegens to a float value. `value_sema_type`
## cannot resolve every form (literals, nested unresolvable binaries), so
## callers deciding signedness from an unresolved operand must check this
## first.
export is_float_valued(expr: Expression): bool {
    match (expr) {
        FloatLiteral(_) => {
            return true;
        }
        Unary(node) => {
            return is_float_valued(node.operand);
        }
        Binary(node) => {
            return is_float_valued(node.lhs) or is_float_valued(node.rhs);
        }
        Cast(node) => {
            return sema.is_float_type(node.ty.to_string());
        }
        Ternary(node) => {
            return is_float_valued(node.true_expr) or is_float_valued(node.false_expr);
        }
        else => {
            return false;
        }
    }
}

## The type `codegen_binary` produces for a binary op, shared by
## `value_sema_type` and both codegen sites. Shifts are excluded from the
## usual arithmetic conversions (C semantics): the result takes the type of
## the promoted left operand.
export binary_result_type(state: PassState, op: BinaryOp, lhs_name: String, rhs_name: String): String {
    if (sema.is_overflow_test(op)) {
        # `__add_overflows(a, b)` tests at the operands' own width.
        return sema.stored_as(state, lhs_name);
    }
    if (op == BinaryOp.LShift or op == BinaryOp.RShift) {
        return sema.result_type(state, lhs_name, lhs_name);
    }
    if ((op == BinaryOp.Add or op == BinaryOp.Sub)
        and (sema.is_pointer_name(lhs_name) or sema.is_pointer_name(rhs_name))) {
        # Pointer arithmetic produces a pointer: name the pointer operand so
        # `coerce` does not ptrtoint the result into an integer.
        return sema.is_pointer_name(lhs_name) ? lhs_name : rhs_name;
    }
    if (sema.is_comparison(op) and sema.is_pointer_name(lhs_name) != sema.is_pointer_name(rhs_name)) {
        # Pointer against integer: name the integer operand, so `coerce`
        # leaves it at its own width and signedness.
        return sema.is_pointer_name(lhs_name) ? rhs_name : lhs_name;
    }
    return sema.result_type(state, lhs_name, rhs_name);
}

extend Generator {
    # Expression types

    ## Type name of an already-generated numeric value for conversion
    ## decisions: the declared sema type (which carries signedness) when it
    ## agrees with the value's kind, else the name implied by the LLVM value.
    numeric_source_name(expr: Expression, value: llvm.Value): String {
        var fallback = value_type_name(value);
        var name = value_sema_type(expr);
        if (name.is_value() and sema.is_numeric_type(state, name.value())) {
            var kind = value.value_type().kind();
            bool float_value = kind == llvm.TypeKind.Float or kind == llvm.TypeKind.Double;
            if (sema.is_float_type(name.value()) == float_value) {
                return name.value();
            }
        }
        return fallback;
    }

    ## The pointer an index expression subscripts: the buffer pointer, or
    ## the struct reference whose `_data` it indexes. Anything else is an
    ## error rather than a crash.
    subscripted_pointer(lhs: Expression): Result<llvm.Value> {
        var value = codegen_expr(lhs)?;
        if (value.value_type().kind() == llvm.TypeKind.Pointer) {
            return Result<llvm.Value>.ok(value);
        }
        return fail<llvm.Value>(not_subscriptable(lhs));
    }

    not_subscriptable(lhs: Expression): String {
        var ty = value_sema_type(lhs);
        if (ty.is_value()) {
            return $"subscripted value of type '{ty.value()}' is not a pointer or an indexable struct";
        }
        return "subscripted value is not a pointer or an indexable struct";
    }

    ## Sema type string of an expression's value, as declared; none when it
    ## cannot be resolved.
    value_sema_type(expr: Expression): String? {
        match (expr) {
            # Literals carry C's type directly: a bool literal is `bool`, an
            # int-range integer literal is `int` (else `long`), a float
            # literal is `double`.
            BoolLiteral(_) => {
                return _some("bool");
            }
            IntLiteral(v) => {
                if (-2147483648 <= v and v <= 2147483647) {
                    return _some("int");
                }
                return _some("long");
            }
            FloatLiteral(_) => {
                return _some("double");
            }
            # A bare struct name that no local or global shadows is a type
            # literal: the receiver of a static call `File.open(p)`.
            SymbolRef(node) => {
                var local = frame.find_local(node.id);
                if (local.is_value()) {
                    return _some(local.value().ty);
                }
                var global = global_addrs.try_get(node.id);
                if (global.is_value()) {
                    return _some(global.value().ty);
                }
                if (structs.contains(node.id)) {
                    return _some(node.id);
                }
                return Optional<String>.Empty;
            }
            ThisRef => {
                var local = frame.find_local("this");
                if (local.is_value()) {
                    return _some(local.value().ty);
                }
                return Optional<String>.Empty;
            }
            FunctionCall(node) => {
                # A tuple literal has its tuple's type.
                if (tuples.contains(node.function)) {
                    return _some(node.function);
                }
                # Free functions first (their declared return type), then
                # ctor-style calls `Name<...>(...)` resolve to Name<...>.
                var returned = fn_returns.try_get(node.function);
                if (returned.is_value()) {
                    return returned;
                }
                var base = _base_name(node.function);
                if (!base.is_empty and structs.contains(base)) {
                    return _some(sema.parse_type_string(node.function).to_string());
                }
                return Optional<String>.Empty;
            }
            MemberRef(node) => {
                var struct_name = struct_name_of(node.lhs);
                if (!struct_name.is_value()) {
                    return Optional<String>.Empty;
                }
                var elements = tuples.try_get(struct_name.value());
                if (elements.is_value()) {
                    var index = ulong.parse(node.name);
                    if (!index.is_value() or index.value() >= elements.value().count) {
                        return Optional<String>.Empty;
                    }
                    return _some(elements.value()[index.value()]);
                }
                var desc = structs.try_get(struct_name.value());
                if (!desc.is_value()) {
                    return Optional<String>.Empty;
                }
                for (var field in desc.value().fields) {
                    var (field_name, field_ty) = field;
                    if (field_name == node.name) {
                        return _some(field_ty);
                    }
                }
                return Optional<String>.Empty;
            }
            MethodCall(node) => {
                var struct_name = struct_name_of(node.this_value);
                if (!struct_name.is_value()) {
                    return Optional<String>.Empty;
                }
                var trait_desc = traits.try_get(struct_name.value());
                if (trait_desc.is_value()) {
                    for (var method in trait_desc.value().methods) {
                        var (name, _, ret) = method;
                        if (name == node.method) {
                            return _some(ret);
                        }
                    }
                    return Optional<String>.Empty;
                }
                var desc = structs.try_get(struct_name.value());
                if (!desc.is_value()) {
                    return Optional<String>.Empty;
                }
                return desc.value().method_returns.try_get(node.method);
            }
            StaticString(_) => {
                return _some("String");
            }
            ToTrait(node) => {
                return _some(node.to.to_string());
            }
            FromTrait(node) => {
                if (node.test) {
                    return _some("bool");
                }
                return _some(node.to.to_string());
            }
            Unary(node) => {
                match (node.op) {
                    # `!x` produces an i1.
                    LogicalNot => {
                        return _some("bool");
                    }
                    # `-x`/`~x` produce a signed two's-complement value at the
                    # operand's width: a narrower-than-int unsigned operand
                    # promotes to signed int.
                    Neg, BitNot => {
                        var operand = value_sema_type(node.operand);
                        if (!operand.is_value()) {
                            return operand;
                        }
                        return _some(sema.result_type(state, operand.value(), operand.value()));
                    }
                    else => {
                        return value_sema_type(node.operand);
                    }
                }
            }
            Binary(node) => {
                # The produced value is the promoted type from
                # `codegen_binary` (`binary_result_type`); a comparison
                # produces an i1.
                var op = node.op;
                if (sema.is_comparison(op)
                    or sema.is_overflow_test(op)
                    or op == BinaryOp.LogicalAnd
                    or op == BinaryOp.LogicalOr) {
                    return _some("bool");
                }
                var l = value_sema_type(node.lhs);
                var r = value_sema_type(node.rhs);
                if (l.is_value() and r.is_value()) {
                    return _some(binary_result_type(state, op, l.value(), r.value()));
                }
                # An unresolved rhs promotes to `int` as codegen_binary
                # coerces it; a float-valued rhs falls through to the
                # `value_type_name` fallback.
                if (l.is_value() and !r.is_value() and !is_float_valued(node.rhs)) {
                    return _some(binary_result_type(state, op, l.value(), "int"));
                }
                return Optional<String>.Empty;
            }
            # Indexed element: the receiver's pointee (`Array<Array<int>>` to
            # `Array<int>`).
            Index(node) => {
                return index_receiver_pointee(node.lhs);
            }
            ArrayIndex(node) => {
                return index_receiver_pointee(node.lhs);
            }
            # `x as T` has the cast target's type.
            Cast(node) => {
                return _some(node.ty.to_string());
            }
            FunctionRef(node) => {
                return _some(node.ty.to_string());
            }
            MakeClosure(node) => {
                return _some(node.ty.to_string());
            }
            Invoke(node) => {
                var callee = value_sema_type(node.callee);
                if (!callee.is_value()) {
                    return Optional<String>.Empty;
                }
                var callee_ty = sema.parse_type_string(callee.value());
                var ret = callee_ty.function_return();
                if (!ret.is_value()) {
                    return Optional<String>.Empty;
                }
                return _some(ret.value().to_string());
            }
            # Numeric arms have their common type; other arms share the true
            # arm's type.
            Ternary(node) => {
                var common = conditional_type(node.true_expr, node.false_expr);
                if (common.is_value()) {
                    return common;
                }
                return value_sema_type(node.true_expr);
            }
            Subject(node) => {
                return _some(node.ty.to_string());
            }
            WithSubject(subject) => {
                return value_sema_type(subject.body);
            }
            # Atomic intrinsics: the load yields T, the store is void, the
            # cmpxchg reports success as bool.
            Weak(op, ty, _) => {
                return _some(sema.weak_result(op, ty).to_string());
            }
            CountStep(_) => {
                return _some("u32");
            }
            FunctionPointer(_) => {
                return _some(sema.VOID_PTR);
            }
            AtomicLoad(ty, _) => {
                return _some(ty.to_string());
            }
            Allocate(ty) => {
                return _some(ty.to_string());
            }
            Move(node) => {
                return value_sema_type(node.value);
            }
            AtomicStore(_, _, _), ConstructAt(_, _) => {
                return _some("void");
            }
            AtomicCmpXchg(_, _, _, _) => {
                return _some("bool");
            }
            AtomicFetch(_, ty, _, _) => {
                return _some(ty.to_string());
            }
            Simd(node) => {
                return _some(sema.simd_result(node.op, node.ty).to_string());
            }
            else => {
                return Optional<String>.Empty;
            }
        }
    }

    ## Best-effort struct name of an expression's value, for field/method
    ## access. The declared name resolves exactly first; unregistered names
    ## fall back to their base for abstract receivers.
    struct_name_of(expr: Expression): String? {
        var found = value_sema_type(expr);
        if (!found.is_value()) {
            return found;
        }
        var ty = sema.without_pointer_names(found.value());
        if (structs.contains(ty) or is_trait_name(ty) or tuples.contains(ty)) {
            return _some(ty);
        }
        var base = _base_name(ty);
        if (base.is_empty) {
            return Optional<String>.Empty;
        }
        return _some(base);
    }

    # Reads and owned values

    ## True when an expression reads an existing struct reference (an lvalue
    ## read of a tracked slot) rather than producing one: copying it into
    ## another reference slot must `__acquire` the new occupant, as
    ## `shared_ptr::operator=` does. A lowered indexer is a read only when it
    ## takes the plain GEP and load path.
    is_lvalue_read(expr: Expression): bool {
        match (expr) {
            SymbolRef(_), ThisRef, Subject(_), MemberRef(_), Index(_), ArrayIndex(_), FunctionRef(_) => {
                return is_struct_ref_name(value_sema_type(expr));
            }
            # Converting keeps the reference it converts: a read stays a
            # read. Boxing a value struct makes a new object.
            ToTrait(node) => {
                if (values.contains(node.from.to_string())) {
                    return false;
                }
                return is_lvalue_read(node.value);
            }
            # The object of the `match`'s subject, a place: a read.
            FromTrait(node) => {
                if (node.test) {
                    return false;
                }
                return is_struct_ref_name(_some(node.to.to_string()));
            }
            # A ternary that owns nothing yields a read of one arm (or null).
            Ternary(node) => {
                return !is_owned_rvalue(expr) and (is_lvalue_read(node.true_expr) or is_lvalue_read(node.false_expr));
            }
            WithSubject(subject) => {
                return is_lvalue_read(subject.body);
            }
            MethodCall(node) => {
                if (node.method != "__index_get") {
                    return false;
                }
                var receiver = value_sema_type(node.this_value);
                if (receiver.is_value() and sema.is_pointer_name(receiver.value())) {
                    return false;
                }
                var struct_name = struct_name_of(node.this_value);
                var desc = structs.try_get(struct_name.is_value() ? struct_name.value() : "");
                bool has_indexer = desc.is_value() and desc.value().methods.contains(node.method);
                return !has_indexer and is_struct_ref_name(value_sema_type(expr));
            }
            else => {
                return false;
            }
        }
    }

    ## True when an expression's value is a freshly created owned reference
    ## (a shared_ptr rvalue): a call result whose declared type is a
    ## registered struct, a new object, a moved or atomically loaded
    ## reference. A discarded owned rvalue is released at the end of its
    ## full expression.
    is_owned_rvalue(expr: Expression): bool {
        match (expr) {
            MethodCall(_), FunctionCall(_), Invoke(_), MakeClosure(_) => {
                return is_struct_ref_name(value_sema_type(expr));
            }
            # A ternary with an owned rvalue arm is one owned rvalue.
            Ternary(node) => {
                return is_owned_rvalue(node.true_expr) or is_owned_rvalue(node.false_expr);
            }
            WithSubject(subject) => {
                return is_owned_rvalue(subject.body);
            }
            # A converted call result is still that call's one reference; a
            # boxed value struct is a new object.
            ToTrait(node) => {
                if (values.contains(node.from.to_string())) {
                    return true;
                }
                return is_owned_rvalue(node.value);
            }
            # `__weak_from` and `__weak_upgrade` hand out a new reference.
            Weak(op, ty, _) => {
                if (op == WeakOp.Expired) {
                    return false;
                }
                return is_struct_ref_name(_some(sema.weak_result(op, ty).to_string()));
            }
            # An atomic load yields a freshly acquired reference.
            AtomicLoad(ty, _) => {
                return is_struct_ref_name(_some(ty.to_string()));
            }
            # A new object owns its one reference.
            Allocate(ty) => {
                return is_struct_ref_name(_some(ty.to_string()));
            }
            # A moved reference is handed over: the place gave it up.
            Move(node) => {
                return is_struct_ref_name(value_sema_type(node.value));
            }
            # An atomic fetch returns the old slot occupant, acquired at the
            # return site.
            AtomicFetch(_, ty, _, _) => {
                return is_struct_ref_name(_some(ty.to_string()));
            }
            else => {
                return false;
            }
        }
    }

    ## True when a sema type name names a registered struct.
    is_struct_ref_name(ty: String?): bool {
        if (!ty.is_value()) {
            return false;
        }
        return is_reference_name(ty.value());
    }

    # Acquire and release

    ## Acquire a reference to `val`, of type `ty_name`: `T.__acquire(v)`,
    ## which ignores null, or the inlined step for a struct with the
    ## standard counts.
    acquire_ref(ty_name: String, val: llvm.Value): Result<void> {
        return acquire_ref_from(ty_name, val, false);
    }

    ## Acquire a reference to `val`, a copy of `source`: when `source` reads
    ## a slot that owns a reference, the object's count is at least 1 before
    ## the step, and the inlined step tells LLVM so.
    acquire_copy(ty_name: String, val: llvm.Value, source: Expression): Result<void> {
        var live = reads_owning_slot(source);
        return acquire_ref_from(ty_name, val, live);
    }

    acquire_ref_from(ty_name: String, val: llvm.Value, live: bool): Result<void> {
        var atomic = _inline_counts(ty_name);
        if (atomic.is_value()) {
            return inline_count_step(ty_name, val, true, atomic.value(), live, false);
        }
        call_function($"{ty_name}.__acquire", [val])?;
        return Result<void>.ok();
    }

    ## Whether `ty_name`'s counts step inline, and whether atomically.
    _inline_counts(ty_name: String): bool? {
        var desc = structs.try_get(ty_name);
        if (!desc.is_value()) {
            return Optional<bool>.Empty;
        }
        return desc.value().inline_counts;
    }

    ## Whether `expr` reads a reference out of a slot that owns one: a
    ## local, parameter, global, field or pointer element, or a ternary or
    ## `with` whose every reference result is one (or null). `this` is not
    ## such a slot.
    reads_owning_slot(expr: Expression): bool {
        match (expr) {
            SymbolRef(node) => {
                if (node.id == "this") {
                    return false;
                }
                return is_lvalue_read(expr);
            }
            MemberRef(_), Index(_), ArrayIndex(_) => {
                return is_lvalue_read(expr);
            }
            Ternary(node) => {
                if (is_owned_rvalue(expr)) {
                    return false;
                }
                bool true_arm = node.true_expr is PointerLiteral or reads_owning_slot(node.true_expr);
                if (!true_arm) {
                    return false;
                }
                return node.false_expr is PointerLiteral or reads_owning_slot(node.false_expr);
            }
            WithSubject(subject) => {
                return reads_owning_slot(subject.body);
            }
            else => {
                return false;
            }
        }
    }

    ## Acquire (`increment`) or release a copy of a parameter the caller
    ## copied, which may be a shared string literal: a step that leaves an
    ## immortal count alone.
    guarded_step(ty_name: String, val: llvm.Value, increment: bool): Result<void> {
        var atomic = _inline_counts(ty_name);
        if (atomic.is_value()) {
            return inline_count_step(ty_name, val, increment, atomic.value(), false, true);
        }
        return fail<void>($"internal error: a caller-copied parameter of type '{ty_name}' without inline counts");
    }

    ## Release a reference to `val`, of type `ty_name`: `T.__release(v)`, or
    ## inlined like `acquire_ref`, with only the last release a call, to
    ## `T.__last_release`.
    release_ref(ty_name: String, val: llvm.Value): Result<void> {
        var atomic = _inline_counts(ty_name);
        if (atomic.is_value()) {
            return inline_count_step(ty_name, val, false, atomic.value(), false, false);
        }
        call_function($"{ty_name}.__release", [val])?;
        return Result<void>.ok();
    }

    ## The inlined body of a standard `__acquire` (`increment`) or
    ## `__release`. `live`: another slot owns a reference to the object.
    ## `guarded`: the object may be a shared string literal, whose count (at
    ## or above `STATIC_REFCOUNT`) is left alone.
    inline_count_step(
        ty_name: String, val: llvm.Value, increment: bool, atomic: bool, live: bool, guarded: bool
    ): Result<void> {
        var object = val;
        # The insert point's function: a thunk is emitted while another
        # function is being compiled.
        var current = builder.insert_block();
        if (current.is_null()) {
            return fail<void>("a reference count step outside a function");
        }
        var function = current.parent();
        if (function.is_null()) {
            return fail<void>("a reference count step outside a function");
        }
        var step = context.append_block(function, increment ? "acquire" : "release");
        var done = context.append_block(function, "counted");
        # `LLVMBuildIsNull`: a compare with null.
        var is_null = builder.compare(llvm.IntPredicate.Equal, object, object.value_type().zero(), "is_null");
        if (guarded) {
            # An immortal static object's count is never written.
            var check = context.append_block(function, "check_static");
            builder.conditional_branch(is_null, done, check);
            builder.position_at_end(check);
            var i32_type = context.int32_type();
            var count = head_count_ptr(object, CountField.Strong)?;
            var load = builder.load(i32_type, count, "count");
            if (atomic) {
                load.set_ordering(_MONOTONIC);
            }
            var limit = i32_type.const_uint(sema.STATIC_REFCOUNT as ulong);
            var is_static = builder.compare(llvm.IntPredicate.UnsignedGreaterOrEqual, load, limit, "is_static");
            builder.conditional_branch(is_static, done, step);
        } else {
            builder.conditional_branch(is_null, done, step);
        }
        builder.position_at_end(step);
        var after = count_step(object, CountField.Strong, increment, atomic, live)?;
        if (increment) {
            builder.branch(done);
        } else {
            var last = context.append_block(function, "last_release");
            var zero = context.int32_type().zero();
            var is_last = builder.compare(llvm.IntPredicate.Equal, after, zero, "is_last");
            builder.conditional_branch(is_last, last, done);
            builder.position_at_end(last);
            # Through the runtime, which puts a destruction nested too deep
            # on a list instead of recursing.
            var last_release_fn = last_release(ty_name, atomic)?;
            call_function("_pep_release_last", [object, last_release_fn])?;
            builder.branch(done);
        }
        builder.position_at_end(done);
        return Result<void>.ok();
    }

    ## `T.__last_release(this)`: what a standard `__release` does when the
    ## strong count reaches 0, out of line (`cold`, never inlined), called
    ## through the runtime's `_pep_release_last`. It destroys the object, then gives up the strong references' weak
    ## reference and frees the memory when no weak reference remains.
    last_release(ty_name: String, atomic: bool): Result<llvm.Value> {
        var name = $"{ty_name}.__last_release";
        var existing = ir.function(name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var pointer = context.pointer_type();
        var function = ir.add_function(name, llvm.Type.function(context.void_type(), [pointer]));
        for (var attribute in ["cold", "noinline"]) {
            function.add_function_attribute(context.attribute(attribute));
        }
        var resume = builder.insert_block();
        var entry = context.append_block(function, "entry");
        builder.position_at_end(entry);
        var object = function.param(0);
        call_function($"{ty_name}.__dtor", [object])?;
        var weak = count_step(object, CountField.Weak, false, atomic, false)?;
        var free_block = context.append_block(function, "free");
        var done = context.append_block(function, "done");
        var zero = context.int32_type().zero();
        var unreferenced = builder.compare(llvm.IntPredicate.Equal, weak, zero, "unreferenced");
        builder.conditional_branch(unreferenced, free_block, done);
        builder.position_at_end(free_block);
        call_function("_pep_free", [object])?;
        builder.branch(done);
        builder.position_at_end(done);
        builder.return_void();
        if (!resume.is_null()) {
            builder.position_at_end(resume);
        }
        return Result<llvm.Value>.ok(function);
    }

    ## Sema type name when `expr` produces an owned rvalue temporary that a
    ## consuming context must release once it is done with the value. Lvalue
    ## reads carry no ref of their own, so they are never temporaries.
    owned_temp_type(expr: Expression): String? {
        if (is_owned_rvalue(expr) and !is_lvalue_read(expr)) {
            return value_sema_type(expr);
        }
        return Optional<String>.Empty;
    }

    # Value struct places

    ## In a value struct's method, where `this` refers: the storage whose
    ## address the `this` parameter holds. None elsewhere, and in a value
    ## struct's constructor, whose `this` is a local holding the value.
    value_this(): Result<Address?> {
        var found = frame.find_local("this");
        if (!found.is_value()) {
            return Result<Optional<Address>>.ok(Optional<Address>.Empty);
        }
        var local = found.value();
        bool pointer_slot = local.llvm_ty.is_value() and local.llvm_ty.value().kind() == llvm.TypeKind.Pointer;
        if (!values.contains(local.ty) or !pointer_slot) {
            return Result<Optional<Address>>.ok(Optional<Address>.Empty);
        }
        var ty = types.get(local.ty);
        if (!ty.is_value()) {
            return fail<Optional<Address>>($"unknown type name '{local.ty}'");
        }
        var ptr = local.load(builder);
        if (!ptr.is_value()) {
            return fail<Optional<Address>>("load this failed");
        }
        return Result<Optional<Address>>.ok(
            Optional<Address>.Value(Address.typed("this", local.ty, ty.value(), ptr.value()))
        );
    }

    ## Whether `expr` names storage a value struct method may change in
    ## place: a variable, `this`, or a field of one or of an object.
    is_value_place(expr: Expression): bool {
        match (expr) {
            SymbolRef(node) => {
                return frame.find_local(node.id).is_value() or global_addrs.contains(node.id);
            }
            ThisRef => {
                return true;
            }
            # A slot of a raw buffer (`_data[i]`) is storage; an indexer call
            # (`a[i]` on an Array) returns a copy instead.
            Index(node) => {
                var ty = value_sema_type(node.lhs);
                return ty.is_value() and sema.is_pointer_name(ty.value());
            }
            ArrayIndex(node) => {
                var ty = value_sema_type(node.lhs);
                return ty.is_value() and sema.is_pointer_name(ty.value());
            }
            MemberRef(node) => {
                var found = struct_name_of(node.lhs);
                var owner = found.is_value() ? found.value() : "";
                if (values.contains(owner)) {
                    return is_value_place(node.lhs);
                }
                # A field of an object is the object's storage.
                return !tuples.contains(owner);
            }
            else => {
                return false;
            }
        }
    }

    ## The address of the value struct `expr` refers to, for a method's
    ## `this`: the storage of a place, else a hidden temporary holding the
    ## value, whose address is also returned so the caller can release an
    ## owned one as the method left it.
    value_address(expr: Expression): Result<(llvm.Value, llvm.Value?)> {
        if (is_value_place(expr)) {
            var place = codegen_lvalue(expr)?;
            return Result<(llvm.Value, Optional<llvm.Value>)>.ok((place.ptr, Optional<llvm.Value>.Empty));
        }
        var value = codegen_expr(expr)?;
        var slot = entry_alloca(value.value_type(), "value");
        builder.store(value, slot);
        return Result<(llvm.Value, Optional<llvm.Value>)>.ok((slot, Optional<llvm.Value>.Value(slot)));
    }

    # Temporaries and scopes

    ## Release an owned rvalue temporary (`T.__release`), a no-op for empty
    ## type names; a guarded argument copy takes the guarded step.
    release_temp(ty: String, val: llvm.Value): Result<void> {
        for (var at in 0..guarded_temps.count) {
            if (guarded_temps[at].same(val)) {
                # Move the last entry into its place.
                var last = guarded_temps.count - 1;
                guarded_temps[at] = guarded_temps[last];
                guarded_temps.truncate(last);
                return guarded_step(ty, val, false);
            }
        }
        if (!ty.is_empty) {
            release_ref(ty, val)?;
        }
        return Result<void>.ok();
    }

    ## Track a struct-reference slot for scope-exit release. A slot lives in
    ## exactly one scope (the innermost at declaration), so shadowed names
    ## release independently when their own scopes exit.
    track_scope_local(name: String, ty_name: String, addr: llvm.Value) {
        # No live scope (dead code after an early return): nothing to
        # release.
        if (scopes.count == 0) {
            return;
        }
        scopes[scopes.count - 1].append(ScopeSlot(name, ty_name, addr));
    }

    ## Release every tracked slot in `scope` (reverse declaration order).
    release_scope(scope: Array<ScopeSlot>): Result<void> {
        var index = scope.count;
        while (index > 0) {
            index -= 1;
            var slot = scope[index];
            var val = builder.load(reference_value_type(slot.ty), slot.slot, "scope_release");
            release_ref(slot.ty, val)?;
        }
        return Result<void>.ok();
    }

    ## End of a full expression: release the temporaries whose release was
    ## deferred while it was evaluated, most recent first.
    flush_deferred_temps(): Result<void> {
        var temps = deferred_temps;
        deferred_temps = Array<Temporary>();
        var index = temps.count;
        while (index > 0) {
            index -= 1;
            var temp = temps[index];
            release_temp(temp.ty, temp.value)?;
        }
        return Result<void>.ok();
    }

    ## Evaluate `expr` in a conditionally executed region (a ternary arm):
    ## temporaries deferred inside it are released before the region ends,
    ## since the end of the enclosing full expression is in a block the
    ## region does not dominate.
    codegen_expr_in_arm(expr: Expression): Result<llvm.Value> {
        var outer = deferred_temps;
        deferred_temps = Array<Temporary>();
        var result = codegen_expr(expr);
        var flushed = flush_deferred_temps();
        deferred_temps = outer;
        var value = result?;
        flushed?;
        return Result<llvm.Value>.ok(value);
    }

    ## Release every tracked slot in every enclosing scope (innermost
    ## first, each in reverse declaration order): the early-return path.
    ## Scopes are not consumed: every exit point emits its own releases.
    release_all_scopes(): Result<void> {
        var all = scopes;
        scopes = Array<Array<ScopeSlot>>();
        var index = all.count;
        while (index > 0) {
            index -= 1;
            var released = release_scope(all[index]);
            if (released.is_err()) {
                scopes = all;
                return released;
            }
        }
        scopes = all;
        return Result<void>.ok();
    }

    # Indexed receivers

    ## LLVM element type behind a pointer/Array receiver (`__ptr<char>` to
    ## i8, `__ptr<int>` to i32); i32 when the receiver's type is unknown. The exact
    ## name resolves first; unregistered names fall back to their base.
    index_element_type(receiver: Expression): llvm.Type {
        # `outer._data[0][0]`: resolve the element type from the base
        # receiver's pointee.
        var r = receiver;
        while (true) {
            if (r is Index(node)) {
                r = node.lhs;
            } else if (r is ArrayIndex(node)) {
                r = node.lhs;
            } else {
                break;
            }
        }
        var base = Optional<String>.Empty;
        var base_type = value_sema_type(r);
        if (base_type.is_value()) {
            base = sema.pointee_name(base_type.value());
        }
        if (!base.is_value()) {
            base = value_sema_type(receiver);
        }
        if (!base.is_value()) {
            return context.int32_type();
        }
        var b = base.value();
        # `void` (opaque) is registered as i32 in the type map, but an opaque
        # pointer indexes at byte granularity: it falls through to
        # `pointee_llvm_type`.
        if (b != "void") {
            var pointee = types.get(b);
            if (pointee.is_value()) {
                return pointee.value();
            }
            var name = _base_name(b);
            if (!name.is_empty) {
                pointee = types.get(name);
                if (pointee.is_value()) {
                    return pointee.value();
                }
            }
        }
        return pointee_llvm_type(b);
    }

    ## LLVM element type for an indexed receiver's pointee name. `void`
    ## (opaque pointers) indexes at byte granularity; other unresolvable
    ## names fall back to i32.
    pointee_llvm_type(name: String): llvm.Type {
        if (name == "void") {
            return context.int8_type();
        }
        var ty = types.get(name);
        return ty.is_value() ? ty.value() : context.int32_type();
    }

    ## Value type of an indexed element: struct elements are stored as
    ## references, so they load and store as pointers while the GEP stride
    ## stays the element type.
    index_value_type(receiver: Expression): llvm.Type {
        var elem = index_element_type(receiver);
        if (is_object(elem)) {
            return context.pointer_type();
        }
        return elem;
    }

    ## Sema type string of an indexed receiver's pointee
    ## (`Array<Array<int>>` to `Array<int>`); none when the receiver's type
    ## is unknown.
    index_receiver_pointee(receiver: Expression): String? {
        var ty = value_sema_type(receiver);
        if (!ty.is_value()) {
            return ty;
        }
        var pointee = sema.pointee_name(ty.value());
        if (!pointee.is_value()) {
            return pointee;
        }
        if (types.get(pointee.value()).is_value()) {
            return pointee;
        }
        var base = _base_name(pointee.value());
        if (base.is_empty) {
            return Optional<String>.Empty;
        }
        return _some(base);
    }

    ## For a nested index on a struct-reference slot (`outer._data[0][i]`),
    ## `slot_ptr` addresses the loaded inner reference; the indexed buffer
    ## lives in its `_data` field. Returns that buffer pointer and the
    ## buffer's element name; none for plain receivers, which GEP the raw
    ## buffer directly.
    nested_index_buffer(lhs: Expression, slot_ptr: llvm.Value): Result<Optional<(llvm.Value, String)>> {
        bool nested = lhs is Index(_) or lhs is ArrayIndex(_);
        if (!nested) {
            return Result<Optional<(llvm.Value, String)>>.ok(Optional<(llvm.Value, String)>.Empty);
        }
        # A pointer element (`rows[0]` of a `__ptr<__ptr<int>>`) is itself
        # the buffer.
        var lhs_type = value_sema_type(lhs);
        if (lhs_type.is_value()) {
            var pointee = sema.pointee_name(lhs_type.value());
            if (pointee.is_value()) {
                return Result<Optional<(llvm.Value, String)>>.ok(
                    Optional<(llvm.Value, String)>.Value((slot_ptr, pointee.value()))
                );
            }
        }
        var elem = index_element_type(lhs);
        if (elem.kind() != llvm.TypeKind.Struct) {
            return fail<Optional<(llvm.Value, String)>>(not_subscriptable(lhs));
        }
        var desc = structs.try_get(elem.struct_name());
        if (!desc.is_value()) {
            return fail<Optional<(llvm.Value, String)>>("nested index on unregistered struct");
        }
        long data_idx = -1;
        var data_name = "";
        var fields = desc.value().fields;
        for (var i in 0..fields.count) {
            var (field_name, field_ty) = fields[i];
            if (field_name == "_data") {
                data_idx = i as long;
                # The `_data` field is a raw pointer buffer: its element is
                # the pointee. Non-pointer fields use their own type name.
                var pointee = sema.pointee_name(field_ty);
                data_name = pointee.is_value() ? pointee.value() : field_ty;
                break;
            }
        }
        if (data_idx < 0) {
            return fail<Optional<(llvm.Value, String)>>("nested index: no _data field");
        }
        # `slot_ptr` addresses the inner reference; its `_data` field is the
        # raw buffer pointer. GEP the field, then load it to get the buffer.
        var data_addr = builder.field_pointer(desc.value().llvm_type, slot_ptr, data_idx as uint, "dataf");
        var buffer = builder.load(context.pointer_type(), data_addr, "innerbuf");
        return Result<Optional<(llvm.Value, String)>>.ok(Optional<(llvm.Value, String)>.Value((buffer, data_name)));
    }

    ## LLVM type of a buffer field's element name for the GEP stride.
    buffer_element_type(name: String): llvm.Type {
        return pointee_llvm_type(name);
    }

    ## GEP stride for an indexed element. Struct elements are stored as
    ## pointers, so every struct slot is exactly pointer-sized.
    slot_stride(elem: llvm.Type): llvm.Type {
        if (is_object(elem)) {
            return context.pointer_type();
        }
        return elem;
    }

    # Stores into reference slots

    ## Store a struct-reference value into an Array element slot, applying
    ## the shared_ptr `operator=` rule (`store_refcount_ops`). Only buffers
    ## whose element type is a struct or trait need it.
    index_refcount_ops(
        elem_name: String, value_ty: llvm.Type, gep: llvm.Value, new_val: llvm.Value, source: Expression
    ): Result<void> {
        var elem = buffer_element_type(elem_name);
        if (elem.kind() != llvm.TypeKind.Struct and !is_trait_name(elem_name)) {
            return Result<void>.ok();
        }
        return store_refcount_ops(elem_name, gep, value_ty, new_val, source);
    }

    ## The reference counting of `__construct_at` into an element slot of
    ## `elem_name`: the slot is empty, so the new value is acquired and
    ## nothing is released. The caller stores the value.
    construct_refcount_ops(
        elem_name: String, value_ty: llvm.Type, new_val: llvm.Value, source: Expression
    ): Result<void> {
        var elem = buffer_element_type(elem_name);
        if (elem.kind() != llvm.TypeKind.Struct and !is_trait_name(elem_name)) {
            return Result<void>.ok();
        }
        check_store_type(value_ty, new_val, "reference slot", elem_name)?;
        if (is_aggregate(elem_name)) {
            call_function($"{elem_name}.__acquire", [new_val])?;
            return Result<void>.ok();
        }
        return acquire_copy(elem_name, new_val, source);
    }

    ## Store a struct-reference value into a struct-typed field, applying
    ## the shared_ptr `operator=` rule (`store_refcount_ops`). A field is one
    ## reference slot.
    field_refcount_ops(lhs: Expression, gep: llvm.Value, new_val: llvm.Value, source: Expression): Result<void> {
        var field_ty_name = "";
        if (lhs is MemberRef(node)) {
            # `codegen_lvalue` already resolved this MemberRef; a miss here
            # means the store target is not a struct field.
            var found = struct_name_of(node.lhs);
            var desc = structs.try_get(found.is_value() ? found.value() : "");
            if (!desc.is_value()) {
                return Result<void>.ok();
            }
            bool matched = false;
            for (var field in desc.value().fields) {
                var (field_name, ty_name) = field;
                if (field_name == node.name) {
                    field_ty_name = ty_name;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                return Result<void>.ok();
            }
        } else {
            # `this = ...` is not a valid store target.
            return Result<void>.ok();
        }
        var field_ty = types.get(field_ty_name);
        if (!field_ty.is_value()) {
            return Result<void>.ok();
        }
        var kind = field_ty.value().kind();
        llvm.Type value_ty;
        if (kind == llvm.TypeKind.Struct and is_aggregate(field_ty_name)) {
            value_ty = field_ty.value();
        } else if (kind == llvm.TypeKind.Struct) {
            value_ty = context.pointer_type();
        } else if (kind == llvm.TypeKind.Array and is_trait_name(field_ty_name)) {
            value_ty = field_ty.value();
        } else {
            return Result<void>.ok();
        }
        return store_refcount_ops(field_ty_name, gep, value_ty, new_val, source);
    }

    ## Store a struct-reference value into an existing reference slot, as
    ## `shared_ptr::operator=` does: the same pointer as the current
    ## occupant is a no-op; otherwise acquire the new occupant, store it,
    ## and only then release the old one. `value_ty` is the slot's LLVM type.
    store_refcount_ops(
        ty_name: String, gep: llvm.Value, value_ty: llvm.Type, new_val: llvm.Value, source: Expression
    ): Result<void> {
        var old = builder.load(value_ty, gep, "oldref");
        # A tuple or a value struct has no identity to compare: acquiring its
        # new elements before releasing the old ones makes self-assignment
        # safe.
        if (is_aggregate(ty_name)) {
            call_function($"{ty_name}.__acquire", [new_val])?;
            store_before_release(gep, value_ty, new_val, ty_name)?;
            call_function($"{ty_name}.__release", [old])?;
            return Result<void>.ok();
        }
        var i64 = context.int64_type();
        # A trait value is the same reference when it is the same object.
        var old_object = object_pointer(old)?;
        var new_object = object_pointer(new_val)?;
        var old_i = builder.pointer_to_int(old_object, i64, "oldi");
        var new_i = builder.pointer_to_int(new_object, i64, "newi");
        var same = builder.compare(llvm.IntPredicate.Equal, old_i, new_i, "same");
        if (!frame.function.is_value()) {
            return fail<void>("no function");
        }
        var fn_value = frame.function.value();
        var ops_block = context.append_block(fn_value, "rcops");
        var cont_block = context.append_block(fn_value, "cont");
        builder.conditional_branch(same, cont_block, ops_block);
        builder.position_at_end(ops_block);
        acquire_copy(ty_name, new_val, source)?;
        store_before_release(gep, value_ty, new_val, ty_name)?;
        release_ref(ty_name, old)?;
        builder.branch(cont_block);
        builder.position_at_end(cont_block);
        return Result<void>.ok();
    }

    ## Store `new_val` into the reference slot `gep` (of LLVM type
    ## `value_ty`, Pepper type `ty_name`) before its old occupant is
    ## released.
    store_before_release(gep: llvm.Value, value_ty: llvm.Type, new_val: llvm.Value, ty_name: String): Result<void> {
        check_store_type(value_ty, new_val, "reference slot", ty_name)?;
        builder.store(new_val, gep);
        return Result<void>.ok();
    }

    # Head counts

    ## Atomic (monotonic) read of the strong count of the object at
    ## `object`.
    load_strong_count(object: llvm.Value): Result<llvm.Value> {
        var count = head_count_ptr(object, CountField.Strong)?;
        var load = builder.load(context.int32_type(), count, "strong_count");
        load.set_alignment(4);
        load.set_ordering(_MONOTONIC);
        return Result<llvm.Value>.ok(load);
    }

    ## One step of a head count of `object`, returning the count after it.
    ## `live` says another slot owns a reference to the object, so the count
    ## is between 1 and `i32::MAX` before the step: the load carries that
    ## range (`!range`), so LLVM may fold the matching release's test for 0.
    ## Atomic counts are never folded.
    count_step(object: llvm.Value, field: CountField, increment: bool, atomic: bool, live: bool): Result<llvm.Value> {
        var count = head_count_ptr(object, field)?;
        var i32_type = context.int32_type();
        var one = i32_type.const_uint(1);
        llvm.Value old;
        if (atomic) {
            # Taking a reference needs no ordering (the caller already holds
            # one); dropping one is acquire-release, so the last release sees
            # every other thread's writes before it destroys the object.
            if (increment) {
                old = builder.atomic_rmw(_RMW_ADD, count, one, _MONOTONIC);
            } else {
                old = builder.atomic_rmw(_RMW_SUB, count, one, _ACQUIRE_RELEASE);
            }
        } else {
            old = builder.load(i32_type, count, "count");
            if (live) {
                var range = context.metadata_node(
                    [context.constant_metadata(one), context.constant_metadata(i32_type.const_uint(2147483648))]
                );
                old.set_metadata(context.metadata_kind("range"), context.metadata_value(range));
            }
        }
        llvm.Value after;
        if (increment) {
            after = builder.add(old, one, "count_after");
        } else {
            after = builder.sub(old, one, "count_after");
        }
        if (!atomic) {
            builder.store(after, count);
        }
        return Result<llvm.Value>.ok(after);
    }

    ## Address of head count `field` in the object at `object`.
    head_count_ptr(object: llvm.Value, field: CountField): Result<llvm.Value> {
        var offset = context.int64_type().const_uint(count_field_offset(field));
        return Result<llvm.Value>.ok(
            builder.element_pointer(context.int8_type(), object, [offset], false, HEAD_COUNT_NAME)
        );
    }
}
