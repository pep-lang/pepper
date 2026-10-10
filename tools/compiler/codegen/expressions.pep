## Generating expressions: `codegen_expr` and its dispatch over every
## `Expression` case, the identity hash folding behind `__address<T>`, and
## raw buffer indexing, as `crates/pepper-codegen/src/lib.rs` makes them.

import llvm;
import compiler.sema;
import [
    AtomicFetchOp, BinaryOp, CountField, Expression, Loc, MemberRefExpression, MethodCallExpression, TypeName
] from compiler.sema;
import [Address, check_store_type] from "address";
import "address";
import "calls";
import "checks";
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

## The call that reports its caller's location (`passes::CALLER_LOCATION`).
const _CALLER_LOCATION = "__caller_location";

## The synthesized hash method of an `[Equatable]` struct
## (`equatable::HASH_METHOD`).
const _HASH_METHOD = "__hash";

# `LLVMAtomicOrdering` values.
const _MONOTONIC: int = 2;
const _ACQUIRE: int = 4;
const _RELEASE: int = 5;
const _ACQUIRE_RELEASE: int = 6;

# `LLVMAtomicRMWBinOp` values.
const _RMW_XCHG: int = 0;
const _RMW_ADD: int = 1;
const _RMW_SUB: int = 2;
const _RMW_AND: int = 3;
const _RMW_OR: int = 5;
const _RMW_XOR: int = 6;

## The receiver of an `Index` or `ArrayIndex` expression, if `expr` is one.
_index_lhs(expr: Expression): Expression? {
    match (expr) {
        Index(node) => {
            return Optional<Expression>.Value(node.lhs);
        }
        ArrayIndex(node) => {
            return Optional<Expression>.Value(node.lhs);
        }
        else => {
            return Optional<Expression>.Empty;
        }
    }
}

## Whether `value` has LLVM type kind `kind`.
_is_kind(value: llvm.Value, kind: llvm.TypeKind): bool {
    return value.value_type().kind() == kind;
}

extend Generator {
    ## The value of `expr`, its location remembered for errors and for
    ## `__caller_location()`.
    codegen_expr(expr: Expression): Result<llvm.Value> {
        var keep = keep_lazy;
        keep_lazy = false;
        if (expr is FunctionCall(call)) {
            if (call.function == _CALLER_LOCATION) {
                var at = in_default_argument ? call_loc : call.loc;
                # In a function whose `[Unsafe("bounds")]` the build does not
                # share, the location tells the callee's index check to pass
                # (see `UNCHECKED_BOUNDS_MARK`).
                if (in_default_argument and !runtime_checks.bounds) {
                    return Result<llvm.Value>.ok(unchecked_location_text(at));
                }
                return Result<llvm.Value>.ok(location_text(at));
            }
        }
        var loc = sema.expression_loc(expr);
        # The call a `__caller_location()` default argument reports.
        bool is_call = expr is FunctionCall(_) or expr is MethodCall(_);
        var outer_call = Optional<Loc>.Empty;
        if (is_call) {
            outer_call = Optional<Loc>.Value(call_loc);
            call_loc = loc;
        }
        var outer_default = in_default_argument;
        in_default_argument = false;
        # A read of a `[__Lazy]` place that writes or shares it gets the
        # place an object first (`materialize`).
        var lazy = keep ? Optional<String>.Empty : lazy_place(expr);
        var result = lazy.is_value() ? materialize(expr, lazy.value()) : codegen_expr_unlocated(expr);
        in_default_argument = outer_default;
        if (outer_call.is_value()) {
            call_loc = outer_call.value();
        }
        locate(result, loc);
        return result;
    }

    ## The value of `expr`: one case per kind of expression.
    codegen_expr_unlocated(expr: Expression): Result<llvm.Value> {
        match (expr) {
            BoolLiteral(value) => {
                return Result<llvm.Value>.ok(context.int1_type().const_uint(value ? 1 : 0));
            }
            IntLiteral(value) => {
                # C 6.4.4.1: an integer literal is `int` when it fits in the
                # signed-int range, else `long`. Emitting i32 for int-range
                # literals keeps mixed-type ops on the int path (`ulong * 1`
                # must promote to u64, not force both sides to i64); values
                # outside emit i64 so `long b = 2^40` does not wrap to zero.
                if (value >= -2147483648 and value <= 2147483647) {
                    return Result<llvm.Value>.ok(context.int32_type().const_int(value));
                }
                return Result<llvm.Value>.ok(context.int64_type().const_int(value));
            }
            FloatLiteral(value) => {
                return Result<llvm.Value>.ok(context.double_type().const_real(value));
            }
            StringLiteral(node) => {
                var cached = global_strings.try_get(node.value);
                if (cached.is_value()) {
                    return Result<llvm.Value>.ok(cached.value());
                }
                var ptr = builder.global_string(node.value, "str");
                global_strings[node.value] = ptr;
                return Result<llvm.Value>.ok(ptr);
            }
            PointerLiteral => {
                return Result<llvm.Value>.ok(context.pointer_type().zero());
            }
            SymbolRef(node) => {
                return codegen_symbol_ref_expr(node.id);
            }
            ThisRef => {
                return codegen_this_ref_expr();
            }
            MemberRef(node) => {
                return codegen_member_ref_expr(node);
            }
            Binary(node) => {
                return codegen_binary(node.op, node.lhs, node.rhs, node.loc);
            }
            Unary(node) => {
                return codegen_unary(node.op, node.operand, node.loc);
            }
            Cast(node) => {
                return codegen_cast(node.expr, node.ty, node.kind);
            }
            Ternary(node) => {
                return codegen_ternary(node.condition, node.true_expr, node.false_expr);
            }
            Index(node) => {
                return codegen_index_expr(node.lhs, node.rhs);
            }
            ArrayIndex(node) => {
                return codegen_index_expr(node.lhs, node.rhs);
            }
            SizeOf(ty) => {
                return codegen_size_of_expr(ty);
            }
            IsPod(ty) => {
                var pod = is_pod_name(ty.to_string());
                return Result<llvm.Value>.ok(context.int1_type().const_uint(pod ? 1 : 0));
            }
            Allocate(ty) => {
                return codegen_allocate_expr(ty);
            }
            Default(ty) => {
                return codegen_default_expr(ty);
            }
            Weak(op, ty, arg) => {
                return codegen_weak(op, ty, arg);
            }
            CountStep(node) => {
                var this_value = codegen_expr(Expression.ThisRef)?;
                if (!_is_kind(this_value, llvm.TypeKind.Pointer)) {
                    return fail<llvm.Value>($"head count on a non-reference {this_value.to_string()}");
                }
                var stepped = count_step(this_value, node.field, node.increment, node.atomic, false)?;
                return Result<llvm.Value>.ok(stepped);
            }
            FunctionPointer(node) => {
                var name = node.owner.is_value() ? $"{node.owner.value().to_string()}.{node.function}" : node.function;
                var target = ir.function(name);
                if (!target.is_value()) {
                    return fail<llvm.Value>($"use of undeclared identifier '{node.function}'");
                }
                var adapted = c_abi_adapter(name, target.value())?;
                return Result<llvm.Value>.ok(adapted);
            }
            RefCount(ty, arg) => {
                return codegen_ref_count_expr(ty, arg);
            }
            Address(ty, arg) => {
                return codegen_address_expr(ty, arg);
            }
            AtomicLoad(ty, arg) => {
                return codegen_atomic_load_expr(ty, arg);
            }
            ConstructAt(slot, value) => {
                # __construct_at(p[i], v): `p[i] = v` into a slot known to
                # be empty, so the store acquires `v` and skips the old
                # occupant's load, comparison and release.
                if (!(slot is Index(_)) and !(slot is ArrayIndex(_))) {
                    return fail<llvm.Value>("'__construct_at' stores into a raw buffer element, such as 'p[i]'");
                }
                codegen_assignment(BinaryOp.Assign, slot, value, Loc.none(), true)?;
                return Result<llvm.Value>.ok(context.int32_type().zero());
            }
            AtomicStore(ty, arg_ptr, arg_val) => {
                return codegen_atomic_store_expr(ty, arg_ptr, arg_val);
            }
            AtomicCmpXchg(ty, arg_ptr, arg_expected, arg_desired) => {
                return codegen_atomic_cmp_xchg_expr(ty, arg_ptr, arg_expected, arg_desired);
            }
            Simd(node) => {
                return codegen_simd(node.op, node.ty, node.args);
            }
            AtomicFetch(op, ty, arg_ptr, arg_val) => {
                return codegen_atomic_fetch_expr(op, ty, arg_ptr, arg_val);
            }
            FunctionCall(node) => {
                return codegen_call(node.function, node.args);
            }
            FunctionRef(node) => {
                var object = function_object(node.function, node.ty.to_string())?;
                return Result<llvm.Value>.ok(object);
            }
            Invoke(node) => {
                return codegen_invoke(node.callee, node.args);
            }
            ClosureLiteral(_) => {
                return fail<llvm.Value>("internal error: closure literal was not lifted");
            }
            MakeClosure(node) => {
                # The closure struct's constructor call; its result is used as
                # the function value (the two share their head layout).
                return codegen_expr(node.value);
            }
            MethodAddress(method) => {
                return method_address(method);
            }
            CallPointer(node) => {
                return codegen_call_pointer(node.pointer, node.args);
            }
            ToTrait(node) => {
                return codegen_to_trait(node.value, node.from, node.to);
            }
            FromTrait(node) => {
                return codegen_from_trait(node.value, node.from, node.to, node.candidates, node.test);
            }
            WithEntered(_) => {
                # lower_with_blocks replaces every one before codegen.
                return fail<llvm.Value>("internal error: unlowered 'with' condition");
            }
            Move(node) => {
                return codegen_move(node.value);
            }
            Destructure(_) => {
                # tuples::lower_destructures replaces every one before codegen.
                return fail<llvm.Value>("internal error: unlowered destructuring");
            }
            MatchArm(_) => {
                return fail<llvm.Value>("internal error: unlowered 'match' arm");
            }
            CaseValue(_) => {
                return fail<llvm.Value>("internal error: unlowered 'match' binding");
            }
            StaticCase(node) => {
                return static_case(node.ty, node.tag);
            }
            StaticString(node) => {
                return static_string(node.value);
            }
            WithSubject(subject) => {
                return with_subject(subject);
            }
            Subject(node) => {
                var subject = subjects.try_get(node.id);
                if (!subject.is_value()) {
                    return fail<llvm.Value>("internal error: 'match' value read outside its 'match'");
                }
                return Result<llvm.Value>.ok(subject.value());
            }
            NoMatch => {
                return fail<llvm.Value>("internal error: unlowered 'match' expression");
            }
            StaticValue(_) => {
                return fail<llvm.Value>("internal error: unexpanded 'static' block");
            }
            StaticMember(_) => {
                return fail<llvm.Value>("internal error: unexpanded 'static' block");
            }
            NamedArgument(_) => {
                return fail<llvm.Value>("internal error: unbound named argument");
            }
            DefaultArgument(_) => {
                return fail<llvm.Value>("internal error: default argument outside a call");
            }
            ForIterator(source) => {
                # Only a var default in well-formed models (codegen_var_def).
                var iterator = for_loop_iterator(source)?;
                return codegen_expr(iterator);
            }
            MethodCall(node) => {
                return codegen_method_call_expr(node);
            }
        }
    }

    ## A read of the local or global `id`.
    codegen_symbol_ref_expr(id: String): Result<llvm.Value> {
        var local = frame.find_local(id);
        Address addr;
        if (local.is_value()) {
            addr = local.value();
        } else {
            var global = global_address(id)?;
            if (!global.is_value()) {
                return fail<llvm.Value>($"use of undeclared identifier '{id}'");
            }
            addr = global.value();
        }
        var loaded = addr.load(builder);
        if (!loaded.is_value()) {
            return fail<llvm.Value>($"load failed {id}");
        }
        return Result<llvm.Value>.ok(loaded.value());
    }

    ## `this`: a copy of the value a value struct's `this` refers to, else
    ## the reference itself.
    codegen_this_ref_expr(): Result<llvm.Value> {
        var storage = value_this()?;
        if (storage.is_value()) {
            # A copy of the value `this` refers to.
            var ty = types.get(storage.value().ty);
            if (!ty.is_value()) {
                return fail<llvm.Value>($"unknown type name '{storage.value().ty}'");
            }
            return Result<llvm.Value>.ok(builder.load(ty.value(), storage.value().ptr, "this"));
        }
        var addr = frame.find_local("this");
        if (!addr.is_value()) {
            return fail<llvm.Value>("no this");
        }
        var loaded = addr.value().load(builder);
        if (!loaded.is_value()) {
            return fail<llvm.Value>("load this failed");
        }
        return Result<llvm.Value>.ok(loaded.value());
    }

    ## `lhs.name`: a tuple element, a field of a value that is no place, or
    ## a field read through the object's reference.
    codegen_member_ref_expr(node: MemberRefExpression): Result<llvm.Value> {
        var lhs = node.lhs;
        var name = node.name;
        var lhs_struct = struct_name_of(lhs);
        if (lhs_struct.is_value() and tuples.contains(lhs_struct.value())) {
            # A tuple element: extract it from the tuple value. An
            # owned-rvalue tuple (`f().0`) is a temporary released at the
            # end of the full expression, like a struct receiver.
            var index = uint.parse(name);
            if (!index.is_value()) {
                return fail<llvm.Value>($"no member named '{name}' in a tuple");
            }
            var lhs_temp = owned_temp_type(lhs);
            var tuple = codegen_expr(lhs)?;
            var element = builder.extract_value(tuple, index.value(), name);
            if (lhs_temp.is_value()) {
                deferred_temps.append(Temporary(tuple, lhs_temp.value()));
            }
            return Result<llvm.Value>.ok(element);
        }
        if (lhs_struct.is_value() and values.contains(lhs_struct.value()) and !is_value_place(lhs)) {
            # A field of a value that is no place (`f().end`): extract it,
            # as a tuple element is.
            var struct_name = lhs_struct.value();
            var desc = structs.try_get(struct_name);
            long position = -1;
            if (desc.is_value()) {
                var fields = desc.value().fields;
                for (var i in 0..fields.count) {
                    var (field_name, _) = fields[i];
                    if (field_name == name) {
                        position = i as long;
                        break;
                    }
                }
            }
            if (position < 0) {
                return fail<llvm.Value>($"no member named '{name}' in '{struct_name}'");
            }
            var lhs_temp = owned_temp_type(lhs);
            var value = codegen_expr(lhs)?;
            var field = builder.extract_value(value, position as uint, name);
            if (lhs_temp.is_value()) {
                deferred_temps.append(Temporary(value, lhs_temp.value()));
            }
            return Result<llvm.Value>.ok(field);
        }
        # Load lhs (this pointer), then StructGEP (Struct.cpp:60-70). The
        # struct name comes from the lhs's static type, not the LLVM value
        # (opaque pointers lose the type).
        var struct_name = lhs_struct.value_or("");
        # An owned-rvalue receiver (`f().x`) is a temporary: its creation ref
        # is released at the end of the full expression, which may still
        # read the field (`f().s == "x"`).
        var lhs_temp = owned_temp_type(lhs);
        # Reading a field neither writes nor shares the object, so an empty
        # `[__Lazy]` one stays null and reads as zeroed (`this` is never null
        # outside a `[__Reads]` method).
        var lazy = is_lazy(struct_name);
        keep_lazy = lazy;
        var this_ptr = codegen_expr(lhs)?;
        llvm.Value base_ptr;
        if (_is_kind(this_ptr, llvm.TypeKind.Struct)) {
            var place = codegen_lvalue(lhs)?;
            base_ptr = place.ptr;
        } else if (lazy and (this_may_be_null or !(lhs is ThisRef))) {
            base_ptr = lazy_base(struct_name, this_ptr)?;
        } else {
            base_ptr = this_ptr;
        }
        var found = structs.try_get(struct_name);
        if (!found.is_value()) {
            return fail<llvm.Value>($"not a struct: {struct_name}");
        }
        var desc = found.value();
        long idx = -1;
        for (var i in 0..desc.fields.count) {
            var (field_name, _) = desc.fields[i];
            if (field_name == name) {
                idx = i as long;
                break;
            }
        }
        if (idx < 0) {
            return fail<llvm.Value>($"no member named '{name}' in '{struct_name}'");
        }
        var (_, field_sema) = desc.fields[idx as ulong];
        var field_ty = types.get(field_sema);
        if (!field_ty.is_value()) {
            return fail<llvm.Value>($"unknown field type {field_sema}");
        }
        var gep = builder.field_pointer(desc.llvm_type, base_ptr, idx as uint, name);
        # Struct-typed fields store a reference (the heap object's pointer),
        # exactly like struct locals and params: load the stored pointer, not
        # the slot address.
        llvm.Value value;
        if (is_object(field_ty.value())) {
            value = builder.load(context.pointer_type(), gep, name);
        } else {
            value = builder.load(field_ty.value(), gep, name);
        }
        if (lhs_temp.is_value()) {
            deferred_temps.append(Temporary(this_ptr, lhs_temp.value()));
        }
        return Result<llvm.Value>.ok(value);
    }

    ## `lhs[rhs]` on a raw (POD) buffer: GEP and load.
    codegen_index_expr(lhs: Expression, rhs: Expression): Result<llvm.Value> {
        var index = codegen_expr(rhs)?;
        # An owned-rvalue receiver (`f()[i]`) is a temporary: its creation
        # ref is released at the end of the full expression.
        var lhs_temp = owned_temp_type(lhs);
        var slot_ptr = subscripted_pointer(lhs)?;
        # A nested index (`outer._data[0][i]`) GEPs the inner struct's own
        # `_data` buffer (the slot holds its reference); a plain index GEPs
        # the raw buffer directly. The element and value types come from the
        # indexed buffer's field type in both cases.
        var nested = nested_index_buffer(lhs, slot_ptr)?;
        llvm.Value ptr;
        String elem_name;
        if (nested.is_value()) {
            var (buffer, buffer_name) = nested.value();
            ptr = buffer;
            elem_name = buffer_name;
        } else {
            ptr = slot_ptr;
            elem_name = index_receiver_pointee(lhs).value_or("i32");
        }
        var element_ty = slot_stride(buffer_element_type(elem_name));
        # Struct elements are stored as references, so `slot_stride` already
        # mapped them to the pointer value type.
        var value_ty = element_ty;
        var gep = builder.element_pointer(element_ty, ptr, [index], false, "idx");
        var value = builder.load(value_ty, gep, "loadidx");
        if (lhs_temp.is_value()) {
            deferred_temps.append(Temporary(slot_ptr, lhs_temp.value()));
        }
        return Result<llvm.Value>.ok(value);
    }

    ## `sizeof(T)`: a struct's slot is pointer-sized; any other type's ABI
    ## size.
    codegen_size_of_expr(ty: TypeName): Result<llvm.Value> {
        var name = ty.to_string();
        if (structs.contains(name) and !values.contains(name)) {
            # Struct elements are stored as pointers, so a struct's slot (and
            # its `sizeof`) is exactly pointer-sized, independent of the
            # struct's own ABI size (matches `slot_stride`): the target's
            # pointer size, not the compiler's.
            var size = machine.size_of(context.pointer_type());
            return Result<llvm.Value>.ok(context.int64_type().const_uint(size));
        }
        var found = types.get(name);
        if (found.is_value()) {
            # Scalar/pointer ABI size, as the target data measures it.
            var size = machine.size_of(found.value());
            return Result<llvm.Value>.ok(context.int64_type().const_uint(size));
        }
        return fail<llvm.Value>($"unknown type name '{name}' in 'sizeof'");
    }

    ## `__allocate<T>()`: a zeroed object of the struct's ABI size, both head
    ## counts 1: the reference it hands out, and the weak reference all
    ## strong ones hold together (see `struct_body`).
    codegen_allocate_expr(ty: TypeName): Result<llvm.Value> {
        var name = ty.to_string();
        var desc = structs.try_get(name);
        if (!desc.is_value()) {
            return fail<llvm.Value>($"cannot allocate unknown struct '{name}'");
        }
        var size = context.int64_type().const_uint(desc.value().size);
        var object = call_function("_pep_malloc", [size])?;
        var one = context.int32_type().const_uint(1);
        for (var field in [CountField.Strong, CountField.Weak]) {
            var count = head_count_ptr(object, field)?;
            builder.store(one, count);
        }
        return Result<llvm.Value>.ok(object);
    }

    ## `__default<T>`: the type's zero value: 0 for numerics, a null pointer
    ## for pointers and struct types (including `String`), an enum's default
    ## case.
    codegen_default_expr(ty: TypeName): Result<llvm.Value> {
        var name = ty.to_string();
        var found = types.get(name);
        if (!found.is_value()) {
            return Result<llvm.Value>.ok(context.int32_type().zero());
        }
        var lowered = found.value();
        match (lowered.kind()) {
            Integer => {
                # An enum's default is a case (`EnumDef::default_value`).
                if (sema.is_enum(state, name)) {
                    return Result<llvm.Value>.ok(lowered.const_int(state.enum_default(name).value_or(0)));
                }
                return Result<llvm.Value>.ok(lowered.zero());
            }
            Half, Float, Double, BFloat, X86Fp80, Fp128, PpcFp128, Pointer, Array, Vector => {
                return Result<llvm.Value>.ok(lowered.zero());
            }
            Struct => {
                if (is_object(lowered)) {
                    return Result<llvm.Value>.ok(context.pointer_type().zero());
                }
                return Result<llvm.Value>.ok(lowered.zero());
            }
            else => {
                return Result<llvm.Value>.ok(context.int32_type().zero());
            }
        }
    }

    ## `__refcount<T>(t)`: 0 for POD T; the u32 head field of a struct
    ## object (index 0, inserted by sema's apply_synthesized). A trait value
    ## reads its object's head, which every struct lays out first.
    codegen_ref_count_expr(ty: TypeName, arg: Expression): Result<llvm.Value> {
        var ty_name = ty.to_string();
        var lowered = types.get(ty_name);
        bool counted = false;
        if (lowered.is_value()) {
            var kind = lowered.value().kind();
            if (kind == llvm.TypeKind.Struct and is_object(lowered.value())) {
                counted = true;
            } else if (kind == llvm.TypeKind.Array and is_trait_name(ty_name)) {
                counted = true;
            }
        }
        if (!counted) {
            return Result<llvm.Value>.ok(context.int32_type().const_uint(0));
        }
        # An owned-rvalue argument is a temporary: its creation ref is
        # released once the head field is read.
        var arg_temp = owned_temp_type(arg);
        var val = codegen_expr(arg)?;
        var object = object_pointer(val);
        if (object.is_err()) {
            return fail<llvm.Value>("__refcount expects a pointer");
        }
        var ptr = object.value();
        var i64 = context.int64_type();
        var zero = context.int32_type().const_uint(0);
        var ptr_int = builder.pointer_to_int(ptr, i64, "rcptr");
        var is_null = builder.compare(llvm.IntPredicate.Equal, ptr_int, i64.const_uint(0), "refcount_null");
        # The head-field load must not run on a null pointer: branch first
        # and phi the result (a select over an already-executed load would
        # dereference null).
        if (!frame.function.is_value()) {
            return fail<llvm.Value>("no function");
        }
        var fn_value = frame.function.value();
        var entry = builder.insert_block();
        var then_block = context.append_block(fn_value, "refcount_nonnull");
        var merge_block = context.append_block(fn_value, "refcount_merge");
        builder.conditional_branch(is_null, merge_block, then_block);
        builder.position_at_end(then_block);
        # Atomic: another thread may be changing the count.
        var loaded = load_strong_count(ptr)?;
        if (arg_temp.is_value()) {
            release_temp(arg_temp.value(), val)?;
        }
        # The release may have added blocks (an inlined count step).
        var then_end = builder.insert_block();
        builder.branch(merge_block);
        builder.position_at_end(merge_block);
        var phi = builder.phi(context.int32_type(), "__refcount");
        phi.add_incoming([loaded, zero], [then_end, entry]);
        return Result<llvm.Value>.ok(phi);
    }

    ## `__address<T>(v)`: identity hash: the object's pointer address for
    ## struct T (null gives the seed), the value's own bits for POD T, folded
    ## into the seed by `hash_fold`.
    codegen_address_expr(ty: TypeName, arg: Expression): Result<llvm.Value> {
        var i64 = context.int64_type();
        var seed = i64.const_uint(0xcbf29ce484222325);
        var ty_name = ty.to_string();
        var lowered = types.get(ty_name);
        bool is_reference = (lowered.is_value() and is_object(lowered.value())) or is_trait_name(ty_name);
        var derived = $"{ty_name}.{_HASH_METHOD}";
        if (functions.contains(derived)) {
            # An `[Equatable]` struct hashes its fields; null hashes to the
            # seed, as for any reference.
            var arg_temp = owned_temp_type(arg);
            var val = codegen_expr(arg)?;
            var pointer = object_pointer(val)?;
            var h = unless_null([pointer], seed, () => call_function(derived, [val]))?;
            if (arg_temp.is_value()) {
                release_temp(arg_temp.value(), val)?;
            }
            return Result<llvm.Value>.ok(h);
        }
        if (tuples.contains(ty_name) or values.contains(ty_name)) {
            var arg_temp = owned_temp_type(arg);
            var val = codegen_expr(arg)?;
            var h = tuple_hash(ty_name, val)?;
            if (arg_temp.is_value()) {
                release_temp(arg_temp.value(), val)?;
            }
            return Result<llvm.Value>.ok(h);
        }
        if (!lowered.is_value()) {
            return fail<llvm.Value>($"__address: unknown type {ty_name}");
        }
        if (!is_reference) {
            # POD: fold the value's own bytes.
            var val = codegen_expr(arg)?;
            var v64 = hash_value_to_i64(val)?;
            return hash_fold(seed, v64);
        }
        # An owned-rvalue argument is a temporary: its creation ref is
        # released once the address is read.
        var arg_temp = owned_temp_type(arg);
        var val = codegen_expr(arg)?;
        # A trait value hashes by its object, like the struct.
        var object = object_pointer(val);
        if (object.is_err()) {
            return fail<llvm.Value>("__address expects a pointer");
        }
        var ptr = object.value();
        var ptr_int = builder.pointer_to_int(ptr, i64, "addrptr");
        var is_null = builder.compare(llvm.IntPredicate.Equal, ptr_int, i64.zero(), "addrnul");
        # Null-guard: branch and phi the result (mirrors `__refcount`).
        if (!frame.function.is_value()) {
            return fail<llvm.Value>("no function");
        }
        var fn_value = frame.function.value();
        var entry = builder.insert_block();
        var then_block = context.append_block(fn_value, "addr_nonnull");
        var merge_block = context.append_block(fn_value, "addr_merge");
        builder.conditional_branch(is_null, merge_block, then_block);
        builder.position_at_end(then_block);
        # Fold the address bits through `hash_fold`: every `_pep_malloc`
        # result is pointer-aligned, so a raw `h & mask` would land all
        # struct keys in bucket 0.
        var folded = hash_fold(seed, ptr_int)?;
        if (arg_temp.is_value()) {
            release_temp(arg_temp.value(), val)?;
        }
        # The release may have added blocks (an inlined count step).
        var then_end = builder.insert_block();
        builder.branch(merge_block);
        builder.position_at_end(merge_block);
        var phi = builder.phi(i64, "__address");
        phi.add_incoming([folded, seed], [then_end, entry]);
        return Result<llvm.Value>.ok(phi);
    }

    ## `__atomic_load<T>(p)`: acquire-ordered load of the slot's T-sized
    ## value. Struct T stores a reference pointer; the loaded pointer is an
    ## owned ref (shared_ptr copy), so acquire it once. POD, float and
    ## pointer T: no ref work.
    codegen_atomic_load_expr(ty: TypeName, arg: Expression): Result<llvm.Value> {
        var ty_name = ty.to_string();
        reject_atomic_trait(ty_name)?;
        # Struct T occupies the slot as a reference pointer; track that
        # before remapping `stored` to the pointer type.
        var lowered = types.get(ty_name);
        bool is_struct = lowered.is_value() and lowered.value().kind() == llvm.TypeKind.Struct;
        if (!lowered.is_value()) {
            return fail<llvm.Value>($"__atomic_load: unknown type {ty_name}");
        }
        var stored = is_struct ? context.pointer_type() : lowered.value();
        var ptr = codegen_expr(arg)?;
        if (!_is_kind(ptr, llvm.TypeKind.Pointer)) {
            return fail<llvm.Value>($"__atomic_load expects a pointer, got {ptr.to_string()}");
        }
        var loaded = builder.load(stored, ptr, "atomic_load");
        loaded.set_ordering(_ACQUIRE);
        if (is_struct) {
            acquire_ref(ty_name, loaded)?;
        }
        return Result<llvm.Value>.ok(loaded);
    }

    ## An operand of an `__atomic_*<T>` intrinsic (the stored, expected,
    ## desired or added value) converted to a numeric `T`, as an argument to
    ## a `T` parameter is: a literal is an `int` or `double` until then, so
    ## `__atomic_store<ulong>(p, 0)` would store only 4 bytes (#639).
    atomic_operand(expr: Expression, value: llvm.Value, ty_name: String): llvm.Value {
        var kind = value.value_type().kind();
        bool numeric_value = kind == llvm.TypeKind.Integer
            or kind == llvm.TypeKind.Float
            or kind == llvm.TypeKind.Double;
        if (!numeric_value or !sema.is_numeric_type(state, ty_name)) {
            return value;
        }
        return coerce(value, numeric_source_name(expr, value), ty_name);
    }

    ## `__atomic_store<T>(p, v)`: release-ordered store, like shared_ptr's
    ## `operator=`: acquire(v), release(old). Struct T swaps the slot
    ## atomically (a plain load of old would race a concurrent store and
    ## leak or double-free it) with an atomic xchg on the pointer's i64 bits;
    ## POD, float and pointer T have no ref work, so a plain release store
    ## suffices.
    codegen_atomic_store_expr(ty: TypeName, arg_ptr: Expression, arg_val: Expression): Result<llvm.Value> {
        var ty_name = ty.to_string();
        reject_atomic_trait(ty_name)?;
        # Struct T swaps the slot's reference pointer atomically.
        var lowered = types.get(ty_name);
        if (!lowered.is_value()) {
            return fail<llvm.Value>($"__atomic_store: unknown type {ty_name}");
        }
        bool is_struct = lowered.value().kind() == llvm.TypeKind.Struct;
        var ptr = codegen_expr(arg_ptr)?;
        if (!_is_kind(ptr, llvm.TypeKind.Pointer)) {
            return fail<llvm.Value>($"__atomic_store expects a pointer, got {ptr.to_string()}");
        }
        # Owned-rvalue argument: its creation ref is released once the slot
        # has taken over ownership (the store acquires it below).
        var val_temp = owned_temp_type(arg_val);
        var val = atomic_operand(arg_val, codegen_expr(arg_val)?, ty_name);
        if (is_struct) {
            acquire_ref(ty_name, val)?;
            var i64 = context.int64_type();
            # Opaque pointers: no bitcast; go through integer bits.
            var new_bits = builder.pointer_to_int(val, i64, "atomic_new");
            var old_bits = builder.atomic_rmw(_RMW_XCHG, ptr, new_bits, _RELEASE);
            var old = builder.int_to_pointer(old_bits, context.pointer_type(), "atomic_old");
            release_temp(ty_name, old)?;
        } else {
            var store = builder.store(val, ptr);
            store.set_ordering(_RELEASE);
        }
        if (val_temp.is_value()) {
            release_temp(val_temp.value(), val)?;
        }
        # Void: the value is unused by every consuming context.
        return Result<llvm.Value>.ok(context.int32_type().zero());
    }

    ## `__atomic_cmpxchg<T>(p, expected, desired)`: acquire/release
    ## compare-and-exchange; returns success as i1. On success the slot now
    ## owns `desired` (acquire it) and drops `old` (release it); on failure
    ## nothing is released: both args remain owned by their callers.
    codegen_atomic_cmp_xchg_expr(
        ty: TypeName, arg_ptr: Expression, arg_expected: Expression, arg_desired: Expression
    ): Result<llvm.Value> {
        var ty_name = ty.to_string();
        reject_atomic_trait(ty_name)?;
        # Struct T compares the slot's reference pointer; track that before
        # remapping `stored` to the pointer type.
        var lowered = types.get(ty_name);
        bool is_struct = lowered.is_value() and lowered.value().kind() == llvm.TypeKind.Struct;
        if (!lowered.is_value()) {
            return fail<llvm.Value>($"__atomic_cmpxchg: unknown type {ty_name}");
        }
        var stored = is_struct ? context.pointer_type() : lowered.value();
        var ptr = codegen_expr(arg_ptr)?;
        if (!_is_kind(ptr, llvm.TypeKind.Pointer)) {
            return fail<llvm.Value>($"__atomic_cmpxchg expects a pointer, got {ptr.to_string()}");
        }
        var expected = atomic_operand(arg_expected, codegen_expr(arg_expected)?, ty_name);
        var desired = atomic_operand(arg_desired, codegen_expr(arg_desired)?, ty_name);
        # cmpxchg only accepts integers and pointers: bitcast floats.
        var stored_kind = stored.kind();
        if (stored_kind == llvm.TypeKind.Float or stored_kind == llvm.TypeKind.Double) {
            var int_ty = stored_kind == llvm.TypeKind.Float ? context.int32_type() : context.int64_type();
            expected = builder.bit_cast(expected, int_ty, "cas_e");
            desired = builder.bit_cast(desired, int_ty, "cas_d");
        } else if (stored_kind == llvm.TypeKind.Half or stored_kind == llvm.TypeKind.BFloat) {
            return fail<llvm.Value>("__atomic_cmpxchg: unsupported float width 16");
        } else if (stored_kind == llvm.TypeKind.X86Fp80) {
            return fail<llvm.Value>("__atomic_cmpxchg: unsupported float width 80");
        } else if (stored_kind == llvm.TypeKind.Fp128 or stored_kind == llvm.TypeKind.PpcFp128) {
            return fail<llvm.Value>("__atomic_cmpxchg: unsupported float width 128");
        }
        var res = builder.compare_exchange(ptr, expected, desired, _ACQUIRE_RELEASE, _MONOTONIC);
        var success = builder.extract_value(res, 1, "cas_ok");
        if (is_struct) {
            # Success only: the slot now owns `desired` and drops `old`;
            # failure leaves every ref where it was.
            var old = builder.extract_value(res, 0, "cas_old");
            if (!frame.function.is_value()) {
                return fail<llvm.Value>("no function");
            }
            var fn_value = frame.function.value();
            var then_block = context.append_block(fn_value, "cas_ok");
            var merge_block = context.append_block(fn_value, "cas_merge");
            builder.conditional_branch(success, then_block, merge_block);
            builder.position_at_end(then_block);
            acquire_ref(ty_name, desired)?;
            release_temp(ty_name, old)?;
            builder.branch(merge_block);
            builder.position_at_end(merge_block);
        }
        return Result<llvm.Value>.ok(success);
    }

    ## `__atomic_fetch_{add,sub,and,or,xor}<T>(p, v)`: acquire/release
    ## atomic read-modify-write on the T-sized value at pointer p; returns
    ## the previous slot occupant. Integer T only, so no ref work.
    codegen_atomic_fetch_expr(
        op: AtomicFetchOp, ty: TypeName, arg_ptr: Expression, arg_val: Expression
    ): Result<llvm.Value> {
        var ty_name = ty.to_string();
        var lowered = types.get(ty_name);
        if (!lowered.is_value() or lowered.value().kind() != llvm.TypeKind.Integer) {
            # Non-integer T: the fetch operations are undefined (as in C++'s
            # std::atomic<T>::fetch_add for a non-arithmetic T). Emit an
            # abort, unreachable at runtime; the constant return keeps the
            # IR valid. It has T's own LLVM type (a null `ptr` for a pointer
            # or struct T), since the caller stores it into a T-typed slot.
            llvm.Value dummy = context.int64_type().zero();
            if (lowered.is_value()) {
                match (lowered.value().kind()) {
                    Struct, Pointer => {
                        dummy = context.pointer_type().zero();
                    }
                    Half, Float, Double, BFloat, X86Fp80, Fp128, PpcFp128, Array => {
                        dummy = lowered.value().zero();
                    }
                    else => {}
                }
            }
            call_function("abort", Array<llvm.Value>())?;
            return Result<llvm.Value>.ok(dummy);
        }
        var ptr = codegen_expr(arg_ptr)?;
        if (!_is_kind(ptr, llvm.TypeKind.Pointer)) {
            return fail<llvm.Value>($"__atomic_fetch expects a pointer, got {ptr.to_string()}");
        }
        # Owned-rvalue argument: released once the RMW has consumed it.
        var val_temp = owned_temp_type(arg_val);
        var val = atomic_operand(arg_val, codegen_expr(arg_val)?, ty_name);
        if (!_is_kind(val, llvm.TypeKind.Integer)) {
            return fail<llvm.Value>($"__atomic_fetch expects an integer, got {val.to_string()}");
        }
        int rmw_op;
        match (op) {
            Add => {
                rmw_op = _RMW_ADD;
            }
            Sub => {
                rmw_op = _RMW_SUB;
            }
            And => {
                rmw_op = _RMW_AND;
            }
            Or => {
                rmw_op = _RMW_OR;
            }
            Xor => {
                rmw_op = _RMW_XOR;
            }
        }
        var old = builder.atomic_rmw(rmw_op, ptr, val, _ACQUIRE_RELEASE);
        if (val_temp.is_value()) {
            release_temp(val_temp.value(), val)?;
        }
        return Result<llvm.Value>.ok(old);
    }

    ## The arguments of a call to `mangled` after its receiver: each written
    ## one, then each default the call omits, appended to `arg_vals` and
    ## `arg_names`. Owned-rvalue arguments are temporaries (shared_ptr):
    ## their creation ref is released after the call, at the end of the full
    ## expression, so they go to `owned_arg_temps`. Lvalue reads are not:
    ## the callee's param entry owns them.
    codegen_method_call_args(
        mangled: String,
        args: Expression[],
        arg_vals: llvm.Value[],
        arg_names: String[],
        owned_arg_temps: Array<(llvm.Value, String)>
    ): Result<void> {
        for (var index in 0..args.count) {
            var arg = args[index];
            if (arg is DefaultArgument(_)) {
                var (v, name) = default_argument(mangled, index, owned_arg_temps)?;
                arg_names.append(name);
                arg_vals.append(v);
                continue;
            }
            keep_lazy = reads_param(mangled, index) or is_final_read(arg);
            var v = codegen_expr(arg)?;
            pass_argument(mangled, index, arg, v, owned_arg_temps)?;
            arg_names.append(numeric_source_name(arg, v));
            arg_vals.append(v);
        }
        # A default argument is evaluated at the call, so an owned default
        # (`String name = ""`) is a temporary like any other.
        var missing = missing_args(mangled, args.count)?;
        for (var offset in 0..missing.count) {
            var extra = missing[offset];
            var v = codegen_default(extra)?;
            default_temp(mangled, args.count + offset, extra, v, owned_arg_temps)?;
            arg_names.append(numeric_source_name(extra, v));
            arg_vals.append(v);
        }
        return Result<void>.ok();
    }

    ## `this.method(args)`: a refcount step on a buffer slot, an indexer or
    ## method on a raw buffer element, or a call of `<StructOf(this)>.method`.
    codegen_method_call_expr(node: MethodCallExpression): Result<llvm.Value> {
        var this_expr = node.this_value;
        var method = node.method;
        var args = node.args;
        # `x.__acquire()` / `x.__release()` step the count of the value `x`
        # holds, and do nothing for plain data, which has none (as C++'s
        # `std::destroy_at` does nothing for a trivially destructible type).
        # On a buffer slot (`_data[i].__release()`) the step leaves the slot
        # as it is: a container releasing its elements just before it frees
        # the buffer has no reason to write them.
        if ((method == "__acquire" or method == "__release") and args.count == 0) {
            var ty = value_sema_type(this_expr);
            if (ty.is_value()) {
                var none = context.int32_type().zero();
                if (is_pod_name(ty.value())) {
                    return Result<llvm.Value>.ok(none);
                }
                if (this_expr is Index(_) or this_expr is ArrayIndex(_)) {
                    # Counting skips null, so an empty `[__Lazy]` slot stays
                    # empty.
                    keep_lazy = true;
                    var value = codegen_expr(this_expr)?;
                    if (method == "__acquire") {
                        acquire_ref(ty.value(), value)?;
                    } else {
                        release_ref(ty.value(), value)?;
                    }
                    return Result<llvm.Value>.ok(none);
                }
            }
        }
        # Receiver is a buffer slot (`_data[i]`): GEP the element out of the
        # raw buffer. Indexer methods are the exception: they address the
        # pointee's own data (`s[0]` on `String s`), so they dispatch to the
        # pointee when it declares them. A value struct element is the
        # exception the other way: its methods take the slot's address as
        # `this`, which the general path below computes (`value_address`).
        var index_lhs = _index_lhs(this_expr);
        bool value_element = false;
        if (!method.starts_with("__index_") and index_lhs.is_value()) {
            var pointee_name = index_receiver_pointee(index_lhs.value());
            value_element = pointee_name.is_value() and values.contains(pointee_name.value());
        }
        if (!value_element and index_lhs.is_value()) {
            return codegen_element_method_call(this_expr, index_lhs.value(), method, args);
        }
        # Mangle: `<StructOf(this)>.<method>`. The struct name comes from the
        # receiver's static type; non-struct receivers fall back to the
        # method name as-is.
        var struct_name = struct_name_of(this_expr).value_or("");
        if (method.starts_with("__index_")) {
            # POD Array index set/get: direct GEP + load/store, but only when
            # the receiver's struct declares the indexer and the receiver is
            # not itself a pointer. A pointer receiver (raw buffer field like
            # `_data` on `Array<Array<int>>`) must GEP the slot; dispatching
            # would call the pointee's indexer on the element's own data.
            var receiver_ty = value_sema_type(this_expr);
            bool receiver_is_ptr = receiver_ty.is_value() and sema.is_pointer_name(receiver_ty.value());
            bool has_indexer = false;
            if (!receiver_is_ptr) {
                var desc = structs.try_get(struct_name);
                has_indexer = desc.is_value() and desc.value().methods.contains(method);
            }
            if (!has_indexer) {
                return codegen_index_method(this_expr, method, args);
            }
        }
        # The receiver is the instance pointer: loading the lhs gives exactly
        # what the `this` parameter expects. When the receiver itself is an
        # owned rvalue (`f().g()`), it is a temporary whose creation ref we
        # release after the call. A static call on a type literal
        # (`Result<int>.ok(5)`) lowers its receiver to a ctor-style call that
        # must NOT run: no instance exists.
        var mangled = $"{struct_name}.{method}";
        var found = structs.try_get(struct_name);
        bool is_static = found.is_value() and found.value().static_methods.contains(method);
        var this_temp = is_static ? Optional<String>.Empty : owned_temp_type(this_expr);
        var arg_vals = Array<llvm.Value>();
        var arg_names = Array<String>();
        var this_val_opt = Optional<llvm.Value>.Empty;
        # A temporary holding a value struct receiver.
        var this_slot = Optional<llvm.Value>.Empty;
        # A value struct's refcount thunks take the value itself.
        bool thunk = method == "__acquire" or method == "__release";
        if (!is_static and !thunk and values.contains(struct_name)) {
            # A value struct's `this` is its storage's address.
            var (address, temporary) = value_address(this_expr)?;
            this_slot = temporary;
            arg_vals.append(address);
            arg_names.append("");
        } else if (!is_static) {
            # A `[__Reads]` method (or a count step) runs on an empty
            # `[__Lazy]` object as null; any other method gets an object,
            # made in the receiver's place if it has one (`materialize`),
            # else for this call alone.
            var lazy = is_lazy(struct_name);
            var reads = thunk or reads_methods.contains(mangled);
            keep_lazy = lazy and reads;
            var this_val = codegen_expr(this_expr)?;
            if (lazy and !reads and this_temp.is_value()) {
                this_val = filled(this_val, struct_name)?;
            }
            this_val_opt = Optional<llvm.Value>.Value(this_val);
            arg_vals.append(this_val);
            arg_names.append("");
        }
        var owned_arg_temps = Array<(llvm.Value, String)>();
        codegen_method_call_args(mangled, args, arg_vals, arg_names, owned_arg_temps)?;
        var result = call_function_typed(mangled, arg_vals, arg_names)?;
        if (this_temp.is_value() and this_val_opt.is_value()) {
            release_temp(this_temp.value(), this_val_opt.value())?;
        }
        # An owned value receiver is released as the method left it.
        if (this_temp.is_value() and this_slot.is_value()) {
            var ty = this_temp.value();
            var llvm_ty = types.get(ty);
            if (!llvm_ty.is_value()) {
                return fail<llvm.Value>($"unknown type name '{ty}'");
            }
            var value = builder.load(llvm_ty.value(), this_slot.value(), "receiver");
            deferred_temps.append(Temporary(value, ty));
        }
        for (var entry in owned_arg_temps) {
            var (temp, ty) = entry;
            release_temp(ty, temp)?;
        }
        return Result<llvm.Value>.ok(result);
    }

    ## A method call on a raw buffer element `lhs[i]` (`this_expr`): an
    ## indexer or a method the element's type does not declare indexes the
    ## buffer; any other calls the pointee's method on the loaded element.
    codegen_element_method_call(
        this_expr: Expression, lhs: Expression, method: String, args: Expression[]
    ): Result<llvm.Value> {
        var pointee = index_element_type(lhs);
        var pointee_trait = Optional<String>.Empty;
        var receiver = index_receiver_pointee(lhs);
        if (receiver.is_value() and is_trait_name(receiver.value())) {
            pointee_trait = receiver;
        }
        String pointee_struct = "";
        if (pointee_trait.is_value()) {
            pointee_struct = pointee_trait.value();
        } else if (pointee.kind() == llvm.TypeKind.Struct) {
            pointee_struct = pointee.struct_name();
        }
        var pointee_desc = structs.try_get(pointee_struct);
        bool pointee_declares = (pointee_desc.is_value() and pointee_desc.value().methods.contains(method))
            or (pointee_trait.is_value() and functions.contains($"{pointee_struct}.{method}"));
        if (method.starts_with("__index_") or !pointee_declares) {
            return codegen_index_method(this_expr, method, args);
        }
        var mangled = $"{pointee_struct}.{method}";
        # Load the slot value with the correct element type: the Index arm
        # GEPs + loads using the receiver's pointee.
        keep_lazy = reads_methods.contains(mangled);
        var elem_val = codegen_expr(this_expr)?;
        bool is_static = pointee_desc.is_value() and pointee_desc.value().static_methods.contains(method);
        var arg_vals = Array<llvm.Value>();
        var arg_names = Array<String>();
        if (!is_static) {
            arg_vals.append(elem_val);
            arg_names.append("");
        }
        var owned_arg_temps = Array<(llvm.Value, String)>();
        codegen_method_call_args(mangled, args, arg_vals, arg_names, owned_arg_temps)?;
        var result = call_function_typed(mangled, arg_vals, arg_names)?;
        for (var entry in owned_arg_temps) {
            var (temp, ty) = entry;
            release_temp(ty, temp)?;
        }
        return Result<llvm.Value>.ok(result);
    }

    ## Folds one i64 into the running hash `h`: the 128-bit product of
    ## `h ^ v` and an odd constant, its high half xored into its low half
    ## (wyhash's "mum"). One multiply, and every bit of the input reaches the
    ## low bits a power-of-two table masks with, so aligned addresses and
    ## keys that differ only in high bits still spread.
    hash_fold(h: llvm.Value, v: llvm.Value): Result<llvm.Value> {
        var i64 = context.int64_type();
        var i128 = context.int_type(128);
        var mixed = builder.bit_xor(h, v, "hfx");
        var wide = builder.zero_extend(mixed, i128, "hfw");
        var product = builder.mul(wide, i128.const_uint(0x9e3779b97f4a7c15), "hfm");
        var low = builder.truncate(product, i64, "hflo");
        var shifted = builder.logical_shift_right(product, i128.const_uint(64), "hfsh");
        var high = builder.truncate(shifted, i64, "hfhi");
        return Result<llvm.Value>.ok(builder.bit_xor(low, high, "hfold"));
    }

    ## A loaded field's value as i64: ints zext/trunc, floats bitcast,
    ## pointers ptrtoint (identity).
    hash_value_to_i64(val: llvm.Value): Result<llvm.Value> {
        var i64 = context.int64_type();
        var ty = val.value_type();
        match (ty.kind()) {
            Integer => {
                var width = ty.int_width();
                if (width == 64) {
                    return Result<llvm.Value>.ok(val);
                }
                if (width > 64) {
                    return Result<llvm.Value>.ok(builder.truncate(val, i64, "hft"));
                }
                return Result<llvm.Value>.ok(builder.zero_extend(val, i64, "hfz"));
            }
            Double => {
                return Result<llvm.Value>.ok(builder.bit_cast(val, i64, "hfbits"));
            }
            Float => {
                var ext = builder.float_extend(val, context.double_type(), "hfext");
                return Result<llvm.Value>.ok(builder.bit_cast(ext, i64, "hfbits"));
            }
            Pointer => {
                return Result<llvm.Value>.ok(builder.pointer_to_int(val, i64, "hfptri"));
            }
            else => {
                return fail<llvm.Value>($"__address: cannot fold {val.to_string()}");
            }
        }
    }

    ## POD Array index get/set: `arr[i]` loads via GEP, `arr[i] = v` stores
    ## via GEP.
    codegen_index_method(this_expr: Expression, method: String, args: Expression[]): Result<llvm.Value> {
        var element_ty = slot_stride(index_element_type(this_expr));
        var value_ty = index_value_type(this_expr);
        var base = codegen_expr(this_expr)?;
        if (_is_kind(base, llvm.TypeKind.Struct)) {
            return fail<llvm.Value>("index method on struct value");
        }
        if (!_is_kind(base, llvm.TypeKind.Pointer)) {
            return fail<llvm.Value>("index method on non-pointer");
        }
        var ptr = base;
        if (args.count == 0) {
            return fail<llvm.Value>("index needs an index");
        }
        var index = codegen_expr(args[0])?;
        var gep = builder.element_pointer(element_ty, ptr, [index], false, "idxm");
        if (method == "__index_get") {
            return Result<llvm.Value>.ok(builder.load(value_ty, gep, "loadidx"));
        }
        # __index_set: the value is args[1]. An owned-rvalue value is a
        # temporary: the slot store acquires its own ref for the new
        # occupant, so the temp's creation ref is released after the store.
        if (args.count < 2) {
            return fail<llvm.Value>("index set needs a value");
        }
        var value_expr = args[1];
        var value_temp = owned_temp_type(value_expr);
        var value = codegen_expr(value_expr)?;
        if (value_ty.kind() == llvm.TypeKind.Integer and _is_kind(value, llvm.TypeKind.Integer)) {
            if (value.value_type().int_width() > value_ty.int_width()) {
                value = builder.truncate(value, value_ty, "narrow");
            }
        }
        index_refcount_ops(index_receiver_pointee(this_expr).value_or("i32"), value_ty, gep, value, value_expr)?;
        if (value_temp.is_value()) {
            release_temp(value_temp.value(), value)?;
        }
        check_store_type(value_ty, value, "element", index_receiver_pointee(this_expr).value_or(""))?;
        builder.store(value, gep);
        return Result<llvm.Value>.ok(value);
    }
}
