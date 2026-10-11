## Calls: free functions, externs and C function pointers, function values
## and their static objects, argument passing and default arguments, weak
## references, `move`, shared literals and enum cases.

import digest;
import llvm;
import compiler.sema;
import [CountField, Expression, TypeName, WeakOp, WithSubject] from compiler.sema;
import "address";
import "checks";
import "expressions";
import "functions";
import [Generator, Temporary] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import "traits";
import [is_object] from "types";
import "types";

## The count an immortal object starts at (sema's `STATIC_REFCOUNT`, 2^30).
const _STATIC_REFCOUNT: ulong = 1073741824;

## The C type an extern's parameter or result of Pepper type `ty` (whose
## LLVM type is `llvm_ty`) has in the C function itself, on a 32-bit target
## (WebAssembly): `long` and `ulong` are the C library's pointer-sized
## `ssize_t` and `size_t`, so they are 32 bits there; `i64` and `u64` stay
## 64 bits. Everything else is unchanged.
export c_abi_type(context: llvm.Context, ty: String, llvm_ty: llvm.Type): llvm.Type {
    if (ty == "long" or ty == "ulong") {
        return context.int32_type();
    }
    return llvm_ty;
}

## Whether `ty` (a function type) returns `void`.
_returns_void(fn_type: llvm.Type): bool {
    return fn_type.return_type().kind() == llvm.TypeKind.Void;
}

## The name a call to a function of type `fn_type` gets: none for a `void`
## call, which LLVM may not name.
_call_name(fn_type: llvm.Type, name: String): String {
    return _returns_void(fn_type) ? "" : name;
}

## A call's result: none for a `void` call.
_call_result(fn_type: llvm.Type, call: llvm.Value): llvm.Value? {
    if (_returns_void(fn_type)) {
        return Optional<llvm.Value>.Empty;
    }
    return Optional<llvm.Value>.Value(call);
}

## Whether `ty` is a float type of any width.
_is_float_type(ty: llvm.Type): bool {
    var kind = ty.kind();
    return kind == llvm.TypeKind.Float or kind == llvm.TypeKind.Double;
}

## The bit width of a float type.
_float_width(ty: llvm.Type): uint {
    return ty.kind() == llvm.TypeKind.Double ? 64 : 32;
}

## The weak intrinsic's source name.
_weak_name(op: WeakOp): String {
    match (op) {
        From => {
            return "__weak_from";
        }
        Upgrade => {
            return "__weak_upgrade";
        }
        Expired => {
            return "__weak_expired";
        }
    }
}

## "too many/few arguments" for a call of a function value of type `fn_ty`
## with `have` arguments.
_arity_error(fn_ty: TypeName, have: ulong): String {
    var expected = fn_ty.function_params().count;
    var which = have > expected ? "many" : "few";
    return $"too {which} arguments to function of type '{fn_ty.display()}': expected {expected}, have {have}";
}

extend Generator {
    ## Whether the target's pointers are 32 bits (WebAssembly's `wasm32`).
    targets_32_bit(): bool {
        return machine.triple().starts_with("wasm32");
    }

    ## A call of free function, extern or constructor `name` with `args`.
    codegen_call(name: String, args: Expression[]): Result<llvm.Value> {
        # Without the bounds check (`--no-runtime-checks=bounds`), an index
        # check is not made at all: its condition is not evaluated.
        # `_pep_assert` is the null check sema generates for a `match`.
        if ((name == "_pep_check_bounds" and !runtime_checks.bounds)
            or (name == "_pep_assert" and !runtime_checks.null)) {
            return Result<llvm.Value>.ok(context.int32_type().zero());
        }
        # release<T>(v): no-op for POD values (nothing to free), dispatches
        # to T.__release for struct references.
        if (name == "release" or name.starts_with("release<")) {
            var value = Optional<llvm.Value>.Empty;
            if (args.count > 0) {
                var v = codegen_expr(args[0])?;
                value = Optional<llvm.Value>.Value(v);
            }
            if (value.is_value() and name.starts_with("release<") and name.ends_with(">")) {
                var inner = name.substr_bytes(8, name.size - 9);
                var parsed = sema.parse_type_string(inner).to_string();
                var ty = types.get(parsed);
                bool is_struct = (ty.is_value() and ty.value().kind() == llvm.TypeKind.Struct) or is_trait_name(parsed);
                if (is_struct) {
                    release_ref(parsed, value.value())?;
                    return Result<llvm.Value>.ok(context.int32_type().zero());
                }
            }
            return Result<llvm.Value>.ok(value.is_value() ? value.value() : context.int32_type().zero());
        }
        # Intrinsics: __is_pod<T> is false for structs (true for POD);
        # __default<T> is the type's zero value.
        if (name == "__is_pod") {
            return Result<llvm.Value>.ok(context.int1_type().const_uint(0));
        }
        if (name == "__default" or name.starts_with("__default<")) {
            var parsed = sema.parse_type_string(name);
            var inner = parsed.sub_types.count > 0 ? parsed.sub_types[0] : TypeName.named(parsed.name);
            var ty = types.get(inner.to_string());
            if (ty.is_value()) {
                var t = ty.value();
                match (t.kind()) {
                    Integer, Float, Double, Pointer, Array, Vector => {
                        return Result<llvm.Value>.ok(t.zero());
                    }
                    Struct => {
                        if (is_object(t)) {
                            return Result<llvm.Value>.ok(context.pointer_type().zero());
                        }
                        return Result<llvm.Value>.ok(t.zero());
                    }
                    else => {
                        return Result<llvm.Value>.ok(context.int32_type().zero());
                    }
                }
            }
            return Result<llvm.Value>.ok(context.int32_type().zero());
        }
        if (tuples.contains(name)) {
            return codegen_tuple(name, args);
        }
        # An empty `[__Lazy]` object is null until it is written or shared
        # (see `materialize`).
        if (!making_lazy and is_lazy(name) and _all_defaults(args)) {
            return Result<llvm.Value>.ok(context.pointer_type().zero());
        }
        # Constructor call `Name<...>(ctor_args)`: specializations are
        # registered under their full name (`Array<int>`); fall back to the
        # base name for non-generic ctors.
        String target = name;
        if (!functions.contains(name)) {
            var open = name.find("<");
            target = (open < 0 ? name : name.substr_bytes(0, open as ulong)).trim();
        }
        # Owned-rvalue arguments are temporaries (shared_ptr): their creation
        # ref is released after the call, at the end of the full expression.
        # Lvalue reads are not: the callee's param entry owns them.
        var owned_arg_temps = Array<(llvm.Value, String)>();
        var arg_vals = Array<llvm.Value>();
        var arg_names = Array<String>();
        var is_extern = extern_names.contains(target);
        for (var arg in args) {
            if (arg is DefaultArgument(_)) {
                var (dv, dname) = default_argument(target, arg_names.count, owned_arg_temps)?;
                arg_names.append(dname);
                arg_vals.append(dv);
                continue;
            }
            # A string literal passed to a C function is its NUL-terminated
            # global (`puts("hi")`, `getenv("HOME")`), exactly as for
            # `assert`'s message; convert_string_literals made it a
            # `String(raw, size, len)` ctor call, whose String object C
            # would read as garbage.
            if (is_extern and _raw_string_argument(arg)) {
                var raw = codegen_expr(_first_argument(arg))?;
                arg_names.append("");
                arg_vals.append(raw);
                continue;
            }
            if (is_extern) {
                check_extern_struct_arg(target, arg_names.count, arg)?;
            }
            keep_lazy = reads_param(target, arg_names.count) or is_final_read(arg);
            var v = codegen_expr(arg)?;
            var index = arg_names.count;
            if (is_extern) {
                var checked = check_intrinsic_argument(target, index, v);
                locate(checked, sema.expression_loc(arg));
                if (checked.is_err()) {
                    return Result<llvm.Value>.err(checked.error());
                }
            }
            pass_argument(target, index, arg, v, owned_arg_temps)?;
            arg_names.append(numeric_source_name(arg, v));
            arg_vals.append(v);
        }
        # A default argument is evaluated at the call, so an owned default
        # (`String name = ""`) is a temporary like any other.
        var extras = missing_args(target, args.count)?;
        for (var offset in 0..extras.count) {
            var extra = extras[offset];
            var v = codegen_default(extra)?;
            default_temp(target, args.count + offset, extra, v, owned_arg_temps)?;
            arg_names.append(numeric_source_name(extra, v));
            arg_vals.append(v);
        }
        var result = call_function_typed(target, arg_vals, arg_names)?;
        for (var entry in owned_arg_temps) {
            var (temp, ty) = entry;
            release_temp(ty, temp)?;
        }
        return Result<llvm.Value>.ok(result);
    }

    ## LLVM type of a value of sema type `ty` as passed and returned: struct
    ## references are pointers.
    abi_type(ty: String): Result<llvm.Type> {
        var found = types.get(ty);
        if (!found.is_value()) {
            return fail<llvm.Type>($"unknown type name '{ty}'");
        }
        if (is_object(found.value())) {
            return Result<llvm.Type>.ok(context.pointer_type());
        }
        return Result<llvm.Type>.ok(found.value());
    }

    ## Call through a C function pointer (`extern (P...) => R`): a plain
    ## indirect call with the C calling convention, no function object. Its
    ## parameter and return types are C types, so nothing is counted.
    codegen_call_c_function(callee: Expression, fn_ty: TypeName, args: Expression[]): Result<llvm.Value> {
        var fn_params = fn_ty.function_params();
        if (args.count != fn_params.count) {
            return fail<llvm.Value>(_arity_error(fn_ty, args.count));
        }
        # On a 32-bit target `long` and `ulong` are the C function's
        # `ssize_t` and `size_t`, as for an extern (see `c_abi_type`).
        var narrow = targets_32_bit();
        var params = Array<llvm.Type>();
        for (var param in fn_params) {
            var ty = abi_type(param.to_string())?;
            params.append(narrow ? c_abi_type(context, param.to_string(), ty) : ty);
        }
        var ret_found = fn_ty.function_return();
        if (!ret_found.is_value()) {
            return fail<llvm.Value>($"not a function type: {fn_ty.display()}");
        }
        var ret = ret_found.value();
        var ret_name = ret.to_string();
        bool narrow_result = narrow and (ret_name == "long" or ret_name == "ulong");
        llvm.Type c_type;
        if (is_void(ret)) {
            c_type = llvm.Type.function(context.void_type(), params, false);
        } else {
            var ret_type = abi_type(ret_name)?;
            c_type = llvm_fn_type(context, narrow ? c_abi_type(context, ret_name, ret_type) : ret_type, params, false);
        }
        var target = codegen_expr(callee)?;
        # Calling a null C function pointer panics, never jumps through null.
        if (runtime_checks.null and functions.contains("_pep_assert")) {
            var is_set = builder.is_not_null(target, "fn_set");
            located_assert(is_set, "called a null C function pointer", sema.expression_loc(callee))?;
        }
        var arg_vals = Array<llvm.Value>();
        var arg_names = Array<String>();
        for (var arg in args) {
            var v = codegen_expr(arg)?;
            arg_names.append(numeric_source_name(arg, v));
            arg_vals.append(v);
        }
        var param_names = Array<String>();
        for (var p in fn_params) {
            param_names.append(p.to_string());
        }
        var coerced = coerce_args(c_type, arg_vals, arg_names, param_names);
        var call = builder.call(c_type, target, coerced, _call_name(c_type, "call"));
        var result = _call_result(c_type, call);
        if (narrow_result) {
            return widen_c_result(result, ret_name == "long");
        }
        return Result<llvm.Value>.ok(result.is_value() ? result.value() : context.int32_type().zero());
    }

    ## LLVM signature of a function value's invoke entry point: the function
    ## object first, then the declared parameters.
    invoke_fn_type(fn_ty: TypeName): Result<llvm.Type> {
        var params = Array<llvm.Type>();
        params.append(context.pointer_type());
        for (var param in fn_ty.function_params()) {
            var ty = abi_type(param.to_string())?;
            params.append(ty);
        }
        var ret = fn_ty.function_return();
        if (!ret.is_value()) {
            return fail<llvm.Type>($"not a function type: {fn_ty.display()}");
        }
        if (is_void(ret.value())) {
            return Result<llvm.Type>.ok(llvm.Type.function(context.void_type(), params, false));
        }
        var ret_type = abi_type(ret.value().to_string())?;
        return Result<llvm.Type>.ok(llvm_fn_type(context, ret_type, params, false));
    }

    ## Pass argument `index` (a parameter index, `this` not counted) of a
    ## call to `callee`: an owned temporary is released after the call,
    ## unless the parameter is `[Move]`, which takes it over; an lvalue
    ## passed to a `[Move]` parameter is acquired for it.
    pass_argument(
        callee: String, index: ulong, arg: Expression, value: llvm.Value, owned_arg_temps: Array<(llvm.Value, String)>
    ): Result<void> {
        if (copied_param(callee, index)) {
            return copy_argument(arg, value, owned_arg_temps);
        }
        bool sending = false;
        var sends = sending_params.try_get(callee);
        if (sends.is_value() and index < sends.value().count) {
            sending = sends.value()[index];
        }
        var temp = owned_temp_type(arg);
        if (temp.is_value()) {
            if (!sending) {
                owned_arg_temps.append((value, temp.value()));
            }
        } else if (sending) {
            var ty = value_sema_type(arg);
            if (ty.is_value() and is_reference_name(ty.value())) {
                acquire_ref(ty.value(), value)?;
            }
        }
        return Result<void>.ok();
    }

    ## Whether the caller makes the copy of parameter `index` of `callee`
    ## (`Module.caller_copies`).
    copied_param(callee: String, index: ulong): bool {
        var copies = caller_copies.try_get(callee);
        if (!copies.is_value() or index >= copies.value().count) {
            return false;
        }
        return copies.value()[index];
    }

    ## The caller's copy of `arg` (`value`) for a parameter whose copy the
    ## caller makes, dropped after the call (`owned_arg_temps`): none for a
    ## shared literal, whose count nothing steps, and none for an owned
    ## temporary, which is that copy. A parameter of this function's own
    ## that the caller copied, or a `String` method's `this`, may hold a
    ## shared literal, so its copy steps with a guard.
    copy_argument(arg: Expression, value: llvm.Value, owned_arg_temps: Array<(llvm.Value, String)>): Result<void> {
        if (arg is StaticString(_)) {
            return Result<void>.ok();
        }
        var temp = owned_temp_type(arg);
        if (temp.is_value()) {
            owned_arg_temps.append((value, temp.value()));
            return Result<void>.ok();
        }
        var found = value_sema_type(arg);
        if (!found.is_value() or !is_reference_name(found.value())) {
            return Result<void>.ok();
        }
        var ty = found.value();
        bool maybe_shared = false;
        match (arg) {
            SymbolRef(node) => {
                maybe_shared = copied_params.contains(node.id);
            }
            ThisRef => {
                maybe_shared = ty == "String";
            }
            else => {}
        }
        if (maybe_shared) {
            guarded_step(ty, value, true)?;
            guarded_temps.append(value);
        } else {
            acquire_copy(ty, value, arg)?;
        }
        owned_arg_temps.append((value, ty));
        return Result<void>.ok();
    }

    ## `move(value)`: load the reference the place holds and store null in
    ## its place, with no count step; the result carries the reference.
    codegen_move(value: Expression): Result<llvm.Value> {
        var found = value_sema_type(value);
        if (!found.is_value()) {
            return fail<llvm.Value>("cannot move a value of unknown type");
        }
        var ty = found.value();
        var address = codegen_lvalue(value)?;
        var stored = types.get(ty);
        if (!stored.is_value()) {
            return fail<llvm.Value>($"cannot move a value of type '{ty}'");
        }
        var slot_ty = stored.value();
        if (slot_ty.kind() == llvm.TypeKind.Struct and !is_aggregate(ty)) {
            slot_ty = context.pointer_type();
        }
        var moved = builder.load(slot_ty, address.ptr, "moved");
        builder.store(slot_ty.zero(), address.ptr);
        return Result<llvm.Value>.ok(moved);
    }

    ## Weak reference intrinsics. The argument is
    ## read like a method receiver; an owned-rvalue argument is a temporary
    ## released once the result exists (so `__weak_from<T>(T())` leaves a
    ## weak reference to an already destroyed object, as in C++).
    codegen_weak(op: WeakOp, ty: TypeName, arg: Expression): Result<llvm.Value> {
        # A trait value's weak reference is its object's, with its vtable
        # carried along: the counts sit in every object's head.
        var ty_name = ty.to_string();
        var layout = types.get(ty_name);
        var fat = Optional<llvm.Type>.Empty;
        if (layout.is_value() and layout.value().kind() == llvm.TypeKind.Struct and structs.contains(ty_name)) {
            fat = Optional<llvm.Type>.Empty;
        } else if (layout.is_value() and layout.value().kind() == llvm.TypeKind.Array and is_trait_name(ty_name)) {
            fat = Optional<llvm.Type>.Value(layout.value());
        } else {
            return fail<llvm.Value>($"{_weak_name(op)}<{ty_name}> needs a struct or trait type");
        }
        var arg_temp = owned_temp_type(arg);
        var val = codegen_expr(arg)?;
        llvm.Value ptr;
        var val_kind = val.value_type().kind();
        if (val_kind == llvm.TypeKind.Pointer) {
            ptr = val;
        } else if (val_kind == llvm.TypeKind.Array and fat.is_value()) {
            ptr = object_pointer(val)?;
        } else {
            return fail<llvm.Value>($"{_weak_name(op)} expects a reference, got {val.to_string()}");
        }
        llvm.Value result;
        match (op) {
            From => {
                # The weak reference is taken before a temporary's strong one
                # is released, so the object's memory stays.
                acquire_ref(sema.weak_result(op, ty).to_string(), val)?;
                result = val;
            }
            Expired => {
                # Expired iff null or no strong reference is left. The head
                # load must not run on null: branch, then phi.
                if (!frame.function.is_value()) {
                    return fail<llvm.Value>("no function");
                }
                var fn_value = frame.function.value();
                var entry = builder.insert_block();
                var then_block = context.append_block(fn_value, "weak_nonnull");
                var merge_block = context.append_block(fn_value, "weak_merge");
                var is_null = builder.is_null(ptr, "weak_null");
                builder.conditional_branch(is_null, merge_block, then_block);
                builder.position_at_end(then_block);
                var strong = load_strong_count(ptr)?;
                var dead = builder.compare(llvm.IntPredicate.Equal, strong, context.int32_type().zero(), "weak_dead");
                var dead_end = builder.insert_block();
                builder.branch(merge_block);
                builder.position_at_end(merge_block);
                var phi = builder.phi(context.int1_type(), "weak_expired");
                phi.add_incoming([dead, context.int1_type().all_ones()], [dead_end, entry]);
                result = phi;
            }
            Upgrade => {
                # `weak_ptr::lock`: take a strong reference only while one is
                # left, as one compare-and-swap loop, so a thread releasing
                # the last reference at the same moment can never be
                # resurrected. Null (or a destroyed object) gives null.
                if (!frame.function.is_value()) {
                    return fail<llvm.Value>("no function");
                }
                var fn_value = frame.function.value();
                var entry = builder.insert_block();
                var loop_block = context.append_block(fn_value, "upgrade_loop");
                var try_block = context.append_block(fn_value, "upgrade_try");
                var merge_block = context.append_block(fn_value, "upgrade_merge");
                var is_null = builder.is_null(ptr, "weak_null");
                builder.conditional_branch(is_null, merge_block, loop_block);
                builder.position_at_end(loop_block);
                var strong = load_strong_count(ptr)?;
                var dead = builder.compare(llvm.IntPredicate.Equal, strong, context.int32_type().zero(), "weak_dead");
                builder.conditional_branch(dead, merge_block, try_block);
                builder.position_at_end(try_block);
                var count = head_count_ptr(ptr, CountField.Strong)?;
                var bumped = builder.add(strong, context.int32_type().const_uint(1), "strong_up");
                var cas = builder.compare_exchange(count, strong, bumped, _ACQUIRE, _MONOTONIC);
                var won = builder.extract_value(cas, 1, "upgrade_ok");
                builder.conditional_branch(won, merge_block, loop_block);
                builder.position_at_end(merge_block);
                if (fat.is_value()) {
                    # The same vtable, or a null trait value.
                    var null_value = fat.value().zero();
                    var phi = builder.phi(fat.value(), "upgraded");
                    phi.add_incoming([null_value, null_value, val], [entry, loop_block, try_block]);
                    result = phi;
                } else {
                    var null_value = context.pointer_type().zero();
                    var phi = builder.phi(context.pointer_type(), "upgraded");
                    phi.add_incoming([null_value, null_value, ptr], [entry, loop_block, try_block]);
                    result = phi;
                }
            }
        }
        if (arg_temp.is_value()) {
            release_temp(arg_temp.value(), val)?;
        }
        return Result<llvm.Value>.ok(result);
    }

    ## The static function object for free function `name`, of function
    ## type `ty`: `{ refcount, invoke, destroy }` with an invoke thunk that
    ## forwards to `name`. Its refcount starts at `STATIC_REFCOUNT` (2^30),
    ## so the balanced acquire/release pairs of the slots holding it never
    ## reach zero: the object is immortal and never freed. Each function
    ## type gets its own object (`name` used as a `shared` and as a plain
    ## value has two).
    function_object(name: String, ty: String): Result<llvm.Value> {
        var fn_ty = sema.parse_type_string(ty);
        var global_name = fn_ty.is_shared_function_type() ?
            $"__function_object.shared.{name}" :
            $"__function_object.{name}";
        var existing = ir.global(global_name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var desc = structs.try_get(ty);
        if (!desc.is_value()) {
            return fail<llvm.Value>($"function type {ty} has no struct");
        }
        var struct_type = desc.value().llvm_type;
        var found = functions.try_get(name);
        if (!found.is_value()) {
            return fail<llvm.Value>($"unknown function {name}");
        }
        var target = found.value();
        var thunk_type = invoke_fn_type(fn_ty)?;
        var thunk_name = $"__function_thunk.{name}";
        var existing_thunk = ir.function(thunk_name);
        if (existing_thunk.is_value()) {
            return Result<llvm.Value>.ok(static_function_object(global_name, struct_type, existing_thunk.value()));
        }
        var thunk = ir.add_function(thunk_name, thunk_type);
        thunk.set_linkage(llvm.Linkage.Private);
        var saved = builder.insert_block();
        var entry = context.append_block(thunk, "entry");
        builder.position_at_end(entry);
        var forwarded = Array<llvm.Value>();
        for (var index in 1..thunk.param_count()) {
            forwarded.append(thunk.param(index));
        }
        var known = fn_param_types.try_get(name);
        var param_names = known.is_value() ? known.value() : Array<String>();
        var target_type = target.global_type();
        var coerced = coerce_args(target_type, forwarded, Array<String>(), param_names);
        var call = builder.call(target_type, target, coerced, _call_name(target_type, "forward"));
        var result = _call_result(target_type, call);
        var narrowed = extern_narrow_results.try_get(name);
        if (narrowed.is_value()) {
            var widened = widen_c_result(result, narrowed.value())?;
            result = Optional<llvm.Value>.Value(widened);
        }
        if (result.is_value() and !_returns_void(thunk_type)) {
            builder.return_value(result.value());
        } else {
            builder.return_void();
        }
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<llvm.Value>.ok(static_function_object(global_name, struct_type, thunk));
    }

    ## The object of a reference enum's case that carries no values
    ## (`Expression.StaticCase`): an immortal global whose counts start at
    ## `STATIC_REFCOUNT` and 1, whose tag is `tag`, and whose other fields
    ## are zero.
    static_case(ty: TypeName, tag: long): Result<llvm.Value> {
        var name = ty.to_string();
        var global_name = $"{name}.case{tag}";
        var existing = ir.global(global_name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var desc = structs.try_get(name);
        if (!desc.is_value()) {
            return fail<llvm.Value>($"unknown enum '{name}'");
        }
        var struct_type = desc.value().llvm_type;
        var names = Array<String>();
        for (var field in desc.value().fields) {
            var (field_name, _) = field;
            names.append(field_name);
        }
        var values = Array<llvm.Value>();
        for (var i in 0..struct_type.field_count()) {
            var field_type = struct_type.field(i);
            var field_name = i < names.count ? names[i] : "";
            if (field_name == "__refcount") {
                values.append(field_type.const_uint(_STATIC_REFCOUNT));
            } else if (field_name == "__weakcount") {
                values.append(field_type.const_uint(1));
            } else if (field_name == sema.TAG_FIELD) {
                values.append(field_type.const_int(tag));
            } else {
                values.append(field_type.zero());
            }
        }
        # External like a function definition: `partition.prepare` makes it
        # `linkonce_odr` in a comdat when units are split.
        var object = ir.add_global(struct_type, global_name);
        object.set_initializer(struct_type.const_struct(values));
        return Result<llvm.Value>.ok(object);
    }

    ## The immortal `String` of a shared literal (`Expression.StaticString`):
    ## one constant global holding the object, whose counts start at
    ## `STATIC_REFCOUNT` and 1, followed by its NUL-terminated bytes, which
    ## `_data` points to. Named by a hash of its text, so every part that
    ## uses the same literal names the same object, and an object kept in
    ## the build cache still means the same text when other units change
    ## (a numbered name would not).
    static_string(value: String): Result<llvm.Value> {
        var existing = static_strings.try_get(value);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var desc = structs.try_get("String");
        if (!desc.is_value()) {
            return fail<llvm.Value>("unknown type name 'String'");
        }
        var string_type = desc.value().llvm_type;
        var names = Array<String>();
        for (var field in desc.value().fields) {
            var (field_name, _) = field;
            names.append(field_name);
        }
        var bytes = context.const_string(value, true);
        var object_type = context.struct_type([string_type, bytes.value_type()]);
        var hash = digest.blake3(value);
        hash.truncate(16);
        var object = ir.add_global(object_type, $"str.object.{digest.to_hex(hash)}");
        var i32_type = context.int32_type();
        var data = object.const_gep(object_type, [i32_type.zero(), i32_type.const_uint(1), i32_type.zero()]);
        var values = Array<llvm.Value>();
        for (var i in 0..string_type.field_count()) {
            var field_type = string_type.field(i);
            var field_name = i < names.count ? names[i] : "";
            match (field_name) {
                "__refcount" => {
                    values.append(field_type.const_uint(_STATIC_REFCOUNT));
                }
                "__weakcount" => {
                    values.append(field_type.const_uint(1));
                }
                "_data" => {
                    values.append(data);
                }
                "_size" => {
                    values.append(field_type.const_uint(value.size));
                }
                "_length" => {
                    values.append(field_type.const_uint(value.length));
                }
                else => {
                    values.append(field_type.zero());
                }
            }
        }
        object.set_initializer(object_type.const_struct([string_type.const_struct(values), bytes]));
        object.set_global_constant(true);
        object.set_linkage(llvm.Linkage.Private);
        static_strings[value] = object;
        return Result<llvm.Value>.ok(object);
    }

    ## A `match` expression or `is` test: evaluate the subject once, check a
    ## reference enum is not null, then the body, which reads the subject
    ## through `Expression.Subject`. An owned subject is a temporary of the
    ## full expression: the body's value may be one of its fields.
    with_subject(subject_with: WithSubject): Result<llvm.Value> {
        var temp = owned_temp_type(subject_with.subject);
        var value = codegen_expr(subject_with.subject)?;
        # The body may read the subject several times (a long literal's
        # chains all append to it), so an empty `[__Lazy]` temporary gets its
        # object now; a place read already has one (`materialize`).
        if (temp.is_value() and is_lazy(temp.value())) {
            value = filled(value, temp.value())?;
        }
        if (subject_with.null_message.is_value() and runtime_checks.null and functions.contains("_pep_assert")) {
            var is_set = builder.is_not_null(value, "subject_set");
            located_assert(is_set, subject_with.null_message.value(), sema.expression_loc(subject_with.subject))?;
        }
        var outer = subjects.try_get(subject_with.id);
        subjects[subject_with.id] = value;
        var result = codegen_expr(subject_with.body);
        if (outer.is_value()) {
            subjects[subject_with.id] = outer.value();
        } else {
            subjects.remove(subject_with.id);
        }
        if (temp.is_value()) {
            deferred_temps.append(Temporary(value, temp.value()));
        }
        return result;
    }

    ## The immortal global `{ STATIC_REFCOUNT, 1, thunk, null }` named
    ## `global_name` (see `function_object`).
    static_function_object(global_name: String, struct_type: llvm.Type, thunk: llvm.Value): llvm.Value {
        var i32_type = context.int32_type();
        var init = struct_type.const_struct(
            [i32_type.const_uint(_STATIC_REFCOUNT), i32_type.const_uint(1), thunk, context.pointer_type().zero()]
        );
        var object = ir.add_global(struct_type, global_name);
        object.set_linkage(llvm.Linkage.Private);
        object.set_initializer(init);
        return object;
    }

    ## `MethodAddress(method)`: the entry point of `method` of the struct
    ## whose constructor is being emitted (a closure struct's `__invoke` and
    ## `__destroy` defaults).
    method_address(method: String): Result<llvm.Value> {
        if (!frame.function.is_value()) {
            return fail<llvm.Value>("method address outside a function");
        }
        var current = frame.function.value().name();
        var name = $"{current}.{method}";
        var function = functions.try_get(name);
        if (!function.is_value()) {
            return fail<llvm.Value>($"unknown method {name}");
        }
        return Result<llvm.Value>.ok(function.value());
    }

    ## `CallPointer`: call the `void` function at `pointer` with `args` (the
    ## function type destructor calling a closure's `__destroy`).
    codegen_call_pointer(pointer: Expression, args: Expression[]): Result<llvm.Value> {
        var target = codegen_expr(pointer)?;
        var values = Array<llvm.Value>();
        var arg_types = Array<llvm.Type>();
        for (var arg in args) {
            var v = codegen_expr(arg)?;
            arg_types.append(v.value_type());
            values.append(v);
        }
        var fn_type = llvm.Type.function(context.void_type(), arg_types, false);
        builder.call(fn_type, target, values, "");
        return Result<llvm.Value>.ok(context.int32_type().zero());
    }

    ## Call through a function value: load its invoke entry point and call it
    ## with the function object followed by the arguments. The callee is
    ## accessed like a method receiver (no refcount work); an owned-rvalue
    ## callee (`make_adder(1)(2)`) is a temporary released after the call.
    codegen_invoke(callee: Expression, args: Expression[]): Result<llvm.Value> {
        var callee_found = value_sema_type(callee);
        if (!callee_found.is_value()) {
            return fail<llvm.Value>("cannot call a value of unknown type");
        }
        var callee_ty_name = callee_found.value();
        var fn_ty = sema.parse_type_string(callee_ty_name);
        if (fn_ty.is_extern_function_type()) {
            return codegen_call_c_function(callee, fn_ty, args);
        }
        if (!fn_ty.is_function_type()) {
            return fail<llvm.Value>($"cannot call a value of type '{fn_ty.display()}'");
        }
        var fn_params = fn_ty.function_params();
        if (args.count != fn_params.count) {
            return fail<llvm.Value>(_arity_error(fn_ty, args.count));
        }
        var desc = structs.try_get(callee_ty_name);
        if (!desc.is_value()) {
            return fail<llvm.Value>($"function type {callee_ty_name} has no struct");
        }
        var struct_type = desc.value().llvm_type;
        var invoke_type = invoke_fn_type(fn_ty)?;

        var callee_temp = owned_temp_type(callee);
        var object = codegen_expr(callee)?;
        # Calling a null function value panics, never jumps through null.
        if (runtime_checks.null and functions.contains("_pep_assert")) {
            var is_set = builder.is_not_null(object, "fn_set");
            located_assert(is_set, "called a null function value", sema.expression_loc(callee))?;
        }
        var slot = builder.field_pointer(struct_type, object, FUNCTION_INVOKE_INDEX, "invoke_slot");
        var entry = builder.load(context.pointer_type(), slot, "invoke");

        var owned_arg_temps = Array<(llvm.Value, String)>();
        var arg_vals = Array<llvm.Value>();
        arg_vals.append(object);
        var arg_names = Array<String>();
        arg_names.append("");
        for (var arg in args) {
            var v = codegen_expr(arg)?;
            var temp = owned_temp_type(arg);
            if (temp.is_value()) {
                owned_arg_temps.append((v, temp.value()));
            }
            arg_names.append(numeric_source_name(arg, v));
            arg_vals.append(v);
        }
        var param_names = Array<String>();
        param_names.append("");
        for (var p in fn_params) {
            param_names.append(p.to_string());
        }
        var coerced = coerce_args(invoke_type, arg_vals, arg_names, param_names);
        var call = builder.call(invoke_type, entry, coerced, _call_name(invoke_type, "call"));
        for (var temp_entry in owned_arg_temps) {
            var (temp, ty) = temp_entry;
            release_temp(ty, temp)?;
        }
        if (callee_temp.is_value()) {
            release_temp(callee_temp.value(), object)?;
        }
        var result = _call_result(invoke_type, call);
        return Result<llvm.Value>.ok(result.is_value() ? result.value() : context.int32_type().zero());
    }

    ## The default of parameter `index` of `target`, which the call skipped
    ## by naming a later parameter: evaluated at the call, so an owned
    ## default is a temporary like any other. The value and its source name.
    default_argument(
        target: String, index: ulong, owned_arg_temps: Array<(llvm.Value, String)>
    ): Result<(llvm.Value, String)> {
        var defaults = param_defaults.try_get(target);
        var default = Optional<Expression>.Empty;
        if (defaults.is_value() and index < defaults.value().count) {
            default = defaults.value()[index];
        }
        if (!default.is_value()) {
            return fail<(llvm.Value, String)>($"internal error: parameter {index + 1} of '{target}' has no default");
        }
        var expr = default.value();
        var v = codegen_default(expr)?;
        default_temp(target, index, expr, v, owned_arg_temps)?;
        return Result<(llvm.Value, String)>.ok((v, numeric_source_name(expr, v)));
    }

    ## The temporary a default argument `default` (`value`) for parameter
    ## `index` of `target` leaves: an owned one, or the caller's copy when
    ## the caller makes it (`copy_argument`).
    default_temp(
        target: String,
        index: ulong,
        default: Expression,
        value: llvm.Value,
        owned_arg_temps: Array<(llvm.Value, String)>
    ): Result<void> {
        if (copied_param(target, index)) {
            return copy_argument(default, value, owned_arg_temps);
        }
        var temp = owned_temp_type(default);
        if (temp.is_value()) {
            owned_arg_temps.append((value, temp.value()));
        }
        return Result<void>.ok();
    }

    ## A default argument of the call being generated: a
    ## `__caller_location()` in it reports the call.
    codegen_default(default: Expression): Result<llvm.Value> {
        var outer = in_default_argument;
        in_default_argument = true;
        var result = codegen_expr(default);
        in_default_argument = outer;
        return result;
    }

    ## Default-argument expressions for the parameters a call did not supply.
    missing_args(target: String, provided: ulong): Result<Expression[]> {
        var found = param_defaults.try_get(target);
        if (!found.is_value()) {
            # Unknown names are not an error here: call_function declares
            # support-library externs (_pep_malloc, ...) on demand.
            return Result<Expression[]>.ok(Array<Expression>());
        }
        var defaults = found.value();
        # Parameters from the last one without a default on are optional.
        ulong required = 0;
        for (var i in 0..defaults.count) {
            if (!defaults[i].is_value()) {
                required = i + 1;
            }
        }
        # An enum method's value is its first argument (`c.m(x)` is
        # `E::m(c, x)`), which the caller did not write as one.
        var shown = target;
        ulong this_count = 0;
        var enum_method = sema.method_of(state, target);
        if (enum_method.is_value()) {
            var (enum_name, method) = enum_method.value();
            var is_static = sema.method_is_static(state, enum_name, method);
            if (is_static.is_value() and !is_static.value()) {
                this_count = 1;
            }
            shown = method;
        }
        if (provided > defaults.count) {
            var n = defaults.count - this_count;
            var expected = required == defaults.count ? $"{n}" : $"at most {n}";
            return fail<Expression[]>(
                $"too many arguments to '{shown}': expected {expected}, have {provided - this_count}"
            );
        }
        if (provided < required) {
            var n = required - this_count;
            var expected = required == defaults.count ? $"{n}" : $"at least {n}";
            return fail<Expression[]>(
                $"too few arguments to '{shown}': expected {expected}, have {provided - this_count}"
            );
        }
        var remaining = Array<Expression>();
        for (var i in provided..defaults.count) {
            remaining.append(defaults[i].value());
        }
        return Result<Expression[]>.ok(remaining);
    }

    ## Calls function `name` with `args`: its result, or an `i32` zero for a
    ## `void` call.
    call_function(name: String, args: llvm.Value[]): Result<llvm.Value> {
        return call_function_typed(name, args, Array<String>());
    }

    ## `call_function` with the sema type names of (a prefix of) the
    ## arguments, so integer arguments widen by their own signedness (a
    ## `u16` passed to a `long` parameter zero-extends). A `void` call gives
    ## an `i32` zero.
    call_function_typed(name: String, args: llvm.Value[], arg_names: String[]): Result<llvm.Value> {
        var result = call_function_result(name, args, arg_names)?;
        return Result<llvm.Value>.ok(result.is_value() ? result.value() : context.int32_type().zero());
    }

    ## The call `call_function_typed` makes: its result, or none for a
    ## `void` call.
    call_function_result(name: String, args: llvm.Value[], arg_names: String[]): Result<llvm.Value?> {
        var found = functions.try_get(name);
        if (!found.is_value()) {
            var dot = name.find(".");
            if (dot >= 0) {
                var owner = name.substr_bytes(0, dot as ulong);
                var member = name.substr_bytes(dot as ulong + 1, name.size - dot as ulong - 1);
                return fail<llvm.Value?>($"no member named '{member}' in '{owner}'");
            }
            return fail<llvm.Value?>($"call to undeclared function '{name}'");
        }
        var fn_value = found.value();
        var known = fn_param_types.try_get(name);
        var param_names = known.is_value() ? known.value() : Array<String>();
        var fn_type = fn_value.global_type();
        var coerced = coerce_args(fn_type, args, arg_names, param_names);
        if (extern_names.contains(name)) {
            var intrinsic = build_memory_intrinsic(fn_value, coerced)?;
            if (intrinsic.is_value()) {
                return Result<llvm.Value?>.ok(intrinsic);
            }
        }
        var call = builder.call(fn_type, fn_value, coerced, _call_name(fn_type, "call"));
        var result = _call_result(fn_type, call);
        var narrowed = extern_narrow_results.try_get(name);
        if (narrowed.is_value()) {
            var widened = widen_c_result(result, narrowed.value())?;
            return Result<llvm.Value?>.ok(Optional<llvm.Value>.Value(widened));
        }
        return Result<llvm.Value?>.ok(result);
    }

    ## The function C calls through a pointer to Pepper function `name`. On
    ## a 32-bit target C passes and returns `long`/`ulong` as its 32-bit
    ## `ssize_t`/`size_t` (see `c_abi_type`), so a Pepper function with such
    ## a parameter or result is called through an adapter with the C
    ## signature, which widens the arguments and narrows the result.
    ## Elsewhere, and for a function whose signature is already C's,
    ## `target` itself.
    c_abi_adapter(name: String, target: llvm.Value): Result<llvm.Value> {
        if (!targets_32_bit()) {
            return Result<llvm.Value>.ok(target);
        }
        var wide = context.int64_type();
        var known = fn_param_types.try_get(name);
        var parameter_types = known.is_value() ? known.value() : Array<String>();
        var fn_type = target.global_type();
        var llvm_parameters = fn_type.param_types();
        var narrows = Array<bool>();
        bool any_narrows = false;
        for (var index in 0..llvm_parameters.count) {
            var ty = llvm_parameters[index];
            bool is_c_long = index < parameter_types.count
                and (parameter_types[index] == "long" or parameter_types[index] == "ulong");
            bool narrows_parameter = is_c_long and ty.kind() == llvm.TypeKind.Integer and ty.int_width() == 64;
            narrows.append(narrows_parameter);
            any_narrows = any_narrows or narrows_parameter;
        }
        var returns = fn_returns.try_get(name);
        var result_type = returns.is_value() ? returns.value() : "";
        var return_type = fn_type.return_type();
        bool narrows_result = (result_type == "long" or result_type == "ulong")
            and return_type.kind() == llvm.TypeKind.Integer
            and return_type.int_width() == 64;
        if (!narrows_result and !any_narrows) {
            return Result<llvm.Value>.ok(target);
        }
        var adapter_name = $"__c_abi.{name}";
        var existing = ir.function(adapter_name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var narrow = context.int32_type();
        var parameters = Array<llvm.Type>();
        for (var index in 0..llvm_parameters.count) {
            parameters.append(narrows[index] ? narrow : llvm_parameters[index]);
        }
        llvm.Type adapter_type;
        if (return_type.kind() == llvm.TypeKind.Void) {
            adapter_type = llvm.Type.function(context.void_type(), parameters, false);
        } else if (narrows_result) {
            adapter_type = llvm.Type.function(narrow, parameters, false);
        } else {
            adapter_type = llvm.Type.function(return_type, parameters, false);
        }
        var adapter = ir.add_function(adapter_name, adapter_type);
        adapter.set_linkage(llvm.Linkage.Private);
        var saved = builder.insert_block();
        var entry = context.append_block(adapter, "entry");
        builder.position_at_end(entry);
        var arguments = Array<llvm.Value>();
        for (var index in 0..adapter.param_count()) {
            var argument = adapter.param(index);
            if (narrows[index]) {
                if (parameter_types[index] == "long") {
                    arguments.append(builder.sign_extend(argument, wide, "c_argument"));
                } else {
                    arguments.append(builder.zero_extend(argument, wide, "c_argument"));
                }
            } else {
                arguments.append(argument);
            }
        }
        var call = builder.call(fn_type, target, arguments, _call_name(fn_type, "forward"));
        var result = _call_result(fn_type, call);
        if (result.is_value() and narrows_result and result.value().value_type().kind() == llvm.TypeKind.Integer) {
            var narrowed = builder.truncate(result.value(), narrow, "c_result");
            builder.return_value(narrowed);
        } else if (result.is_value()) {
            builder.return_value(result.value());
        } else {
            builder.return_void();
        }
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<llvm.Value>.ok(adapter);
    }

    ## A 32-bit C `size_t` or `ssize_t` result (see `c_abi_type`) widened to
    ## Pepper's `ulong` or `long`: sign-extended when `signed`.
    widen_c_result(result: llvm.Value?, signed: bool): Result<llvm.Value> {
        if (!result.is_value() or result.value().value_type().kind() != llvm.TypeKind.Integer) {
            return Result<llvm.Value>.ok(result.is_value() ? result.value() : context.int32_type().zero());
        }
        var value = result.value();
        var wide = context.int64_type();
        if (signed) {
            return Result<llvm.Value>.ok(builder.sign_extend(value, wide, "c_result"));
        }
        return Result<llvm.Value>.ok(builder.zero_extend(value, wide, "c_result"));
    }

    ## Lowers a call to the C library's `memcpy`, `memmove` or `memset` to
    ## the LLVM intrinsic, so LLVM inlines a constant-size copy (#340). A
    ## call to the extern itself would not do: Pepper declares a `void`
    ## extern with an `i32` return, which does not match the C signature, so
    ## LLVM never recognizes it as the builtin. None for any other function,
    ## or when the arguments are not (pointer, pointer or integer, integer),
    ## and the caller emits a plain call.
    build_memory_intrinsic(fn_value: llvm.Value, args: llvm.Value[]): Result<llvm.Value?> {
        var symbol = fn_value.name();
        if (args.count != 3) {
            return Result<llvm.Value?>.ok(Optional<llvm.Value>.Empty);
        }
        var dest = args[0];
        var second = args[1];
        var size = args[2];
        if (dest.value_type().kind() != llvm.TypeKind.Pointer or size.value_type().kind() != llvm.TypeKind.Integer) {
            return Result<llvm.Value?>.ok(Optional<llvm.Value>.Empty);
        }
        var second_kind = second.value_type().kind();
        if (symbol == "memcpy" and second_kind == llvm.TypeKind.Pointer) {
            builder.memory_copy(dest, 1, second, 1, size);
        } else if (symbol == "memmove" and second_kind == llvm.TypeKind.Pointer) {
            builder.memory_move(dest, 1, second, 1, size);
        } else if (symbol == "memset" and second_kind == llvm.TypeKind.Integer) {
            # C converts the fill value to unsigned char (a truncation, or
            # the value itself when it is already a byte).
            var fill = second;
            if (second.value_type().int_width() != 8) {
                fill = builder.truncate(second, context.int8_type(), "fill");
            }
            builder.memory_set(dest, fill, size, 1);
        } else {
            return Result<llvm.Value?>.ok(Optional<llvm.Value>.Empty);
        }
        # C returns `dest`; an extern declared `void` reads as `i32` zero, as
        # a plain call's missing result does.
        var return_type = fn_value.global_type().return_type();
        match (return_type.kind()) {
            Pointer => {
                return Result<llvm.Value?>.ok(Optional<llvm.Value>.Value(dest));
            }
            Integer => {
                return Result<llvm.Value?>.ok(Optional<llvm.Value>.Value(return_type.zero()));
            }
            else => {
                return Result<llvm.Value?>.ok(Optional<llvm.Value>.Value(context.int32_type().zero()));
            }
        }
    }

    ## Coerce call arguments to the parameter types of `fn_type` (e.g. i32
    ## refcount to i64 for trace_int), widening integers by the signedness
    ## of their sema type names in `arg_names`, and converting a float to an
    ## integer parameter by the signedness of its sema type name in
    ## `param_names` (empty when unknown: signed).
    coerce_args(fn_type: llvm.Type, args: llvm.Value[], arg_names: String[], param_names: String[]): llvm.Value[] {
        var param_types = fn_type.param_types();
        var variadic = fn_type.is_variadic();
        var coerced = Array<llvm.Value>();
        for (var idx in 0..args.count) {
            var arg = args[idx];
            var arg_ty = arg.value_type();
            var arg_kind = arg_ty.kind();
            bool arg_int = arg_kind == llvm.TypeKind.Integer;
            bool arg_float = _is_float_type(arg_ty);
            bool named_unsigned = idx < arg_names.count and sema.is_unsigned_int_type(state, arg_names[idx]);
            # Only integer, float and pointer parameters are coerced to.
            var param_ty = Optional<llvm.Type>.Empty;
            if (idx < param_types.count) {
                var p = param_types[idx];
                if (p.kind() == llvm.TypeKind.Integer or _is_float_type(p) or p.kind() == llvm.TypeKind.Pointer) {
                    param_ty = Optional<llvm.Type>.Value(p);
                }
            }
            var value = arg;
            if (param_ty.is_value()) {
                var it = param_ty.value();
                if (it.kind() == llvm.TypeKind.Integer and arg_int) {
                    var to = it.int_width();
                    var from = arg_ty.int_width();
                    bool unsigned = from == 1 or named_unsigned;
                    if (to > from and unsigned) {
                        value = builder.zero_extend(arg, it, "argw");
                    } else if (to > from) {
                        value = builder.sign_extend(arg, it, "argw");
                    } else if (to < from) {
                        value = builder.truncate(arg, it, "argt");
                    }
                } else if (it.kind() == llvm.TypeKind.Integer and arg_float) {
                    # float -> integer parameter truncates toward zero, as
                    # assignment does (C 6.3.1.4); `bool` compares != 0.
                    bool unsigned = idx < param_names.count and sema.is_unsigned_int_type(state, param_names[idx]);
                    var width = it.int_width();
                    String target;
                    if (width == 1) {
                        target = "bool";
                    } else if (unsigned) {
                        target = $"u{width}";
                    } else {
                        target = $"i{width}";
                    }
                    value = coerce(arg, value_type_name(arg), target);
                } else if (_is_float_type(it) and arg_int) {
                    # int -> float parameter converts the value (C 6.3.1.4)
                    # instead of passing the integer bits.
                    bool unsigned = arg_ty.int_width() == 1 or named_unsigned;
                    if (unsigned) {
                        value = builder.unsigned_to_float(arg, it, "argf");
                    } else {
                        value = builder.signed_to_float(arg, it, "argf");
                    }
                } else if (_is_float_type(it) and arg_float and !arg_ty.same(it)) {
                    if (_float_width(arg_ty) < _float_width(it)) {
                        value = builder.float_extend(arg, it, "argf");
                    } else {
                        value = builder.float_truncate(arg, it, "argf");
                    }
                }
            } else if (variadic and arg_int and arg_ty.int_width() < 32) {
                # An argument in a variadic extern's `...` has no declared
                # type: C's default argument promotions apply (6.5.2.2p7), so
                # integers narrower than int widen to int by their own
                # signedness and float widens to double.
                var i32t = context.int32_type();
                bool unsigned = arg_ty.int_width() == 1 or named_unsigned;
                if (unsigned) {
                    value = builder.zero_extend(arg, i32t, "vararg");
                } else {
                    value = builder.sign_extend(arg, i32t, "vararg");
                }
            } else if (variadic and arg_float and _float_width(arg_ty) < 64) {
                value = builder.float_extend(arg, context.double_type(), "vararg");
            }
            coerced.append(value);
        }
        return coerced;
    }

    ## A Pepper struct is never a C pointer: passing one to an extern's
    ## pointer parameter would hand C the object, not its contents.
    check_extern_struct_arg(function: String, index: ulong, arg: Expression): Result<void> {
        var params = extern_params.try_get(function);
        if (!params.is_value() or index >= params.value().count) {
            return Result<void>.ok();
        }
        var param = params.value()[index];
        var found = value_sema_type(arg);
        if (!found.is_value()) {
            return Result<void>.ok();
        }
        var arg_ty = found.value();
        if (!structs.contains(arg_ty) or !sema.is_pointer_name(param)) {
            return Result<void>.ok();
        }
        var hint = arg_ty == "String" ? "; pass its 'c_str()'" : "";
        var result = fail<void>(
            $"cannot pass '{arg_ty}' to parameter {index + 1} of extern '{function}' of type '{param}'{hint}"
        );
        locate(result, sema.expression_loc(arg));
        return result;
    }
}

## Whether `arg` is `String(raw, ...)` made from a raw string literal.
_raw_string_argument(arg: Expression): bool {
    if (arg is FunctionCall(call)) {
        if (call.function == "String" and call.args.count > 0) {
            if (call.args[0] is StringLiteral(literal)) {
                return literal.is_raw;
            }
        }
    }
    return false;
}

## The first argument of a function call `arg`.
_first_argument(arg: Expression): Expression {
    if (arg is FunctionCall(call)) {
        return call.args[0];
    }
    return arg;
}

## Whether every one of `args` is a default the call leaves out: a
## zero-argument constructor call.
_all_defaults(args: Expression[]): bool {
    for (var arg in args) {
        if (!(arg is DefaultArgument(_))) {
            return false;
        }
    }
    return true;
}
