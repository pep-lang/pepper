## Traits used as types, tuples and boxed value structs: trait
## instantiation, the vtables and their thunks, tuple layout, equality and
## hashing, and the `ToTrait`/`FromTrait` conversions, as
## `crates/pepper-codegen/src/lib.rs` makes them.

import llvm;
import compiler.sema;
import [
    AUTO, CountField, Expression, FunctionDef, Loc, parse_type_string, set_name, TraitType, TypeName
] from compiler.sema;
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import [Generator, TraitDesc] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "simd";
import [is_object] from "types";
import "types";

## Whether `a` and `b` hold the same strings in the same order.
_same_strings(a: String[], b: String[]): bool {
    if (a.count != b.count) {
        return false;
    }
    for (var index in 0..a.count) {
        if (a[index] != b[index]) {
            return false;
        }
    }
    return true;
}

## Whether `value` is an LLVM floating-point number.
_is_float(value: llvm.Value): bool {
    var kind = value.value_type().kind();
    return kind == llvm.TypeKind.Float or kind == llvm.TypeKind.Double;
}

## Whether `value` is an LLVM array (a trait value).
_is_array(value: llvm.Value): bool {
    return value.value_type().kind() == llvm.TypeKind.Array;
}

extend Generator {
    ## The type identity a vtable ends with, after the trait's methods: an
    ## FNV-1a hash of the struct's name, as the pointer-sized integer a
    ## vtable slot holds (folded to 32 bits on a 32-bit target).
    type_id_value(struct_name: String): llvm.Value {
        var id = _fnv1a(struct_name);
        if (targets_32_bit()) {
            return context.int32_type().const_uint((id ^ (id >> 32)) & 0xffffffff);
        }
        return context.int64_type().const_uint(id);
    }

    ## Records trait type `t` and emits its count and dispatch thunks.
    instantiate_trait(t: TraitType): Result<void> {
        var name = t.ty.to_string();
        var desc = TraitDesc();
        for (var m in t.methods) {
            var params = Array<String>();
            for (var p in m.parameters) {
                params.append(p.ty.to_string());
            }
            desc.methods.append((m.name, params, m.ty.to_string()));
        }
        traits[name] = desc;
        emit_trait_refcount_thunk(name, "__release", VTABLE_RELEASE)?;
        emit_trait_refcount_thunk(name, "__acquire", VTABLE_ACQUIRE)?;
        for (var slot in 0..t.methods.count) {
            var method = t.methods[slot];
            # A thunk has no node of its own: an error is the trait method's,
            # located at its declaration unless a parameter's type claimed it.
            var result = emit_trait_dispatch_thunk(name, method, VTABLE_METHODS + slot as ulong);
            locate(result, method.loc);
            result?;
        }
        return Result<void>.ok();
    }

    ## Whether a sema type name is a trait used as a type.
    is_trait_name(name: String): bool {
        return traits.contains(name);
    }

    ## Whether a sema type name is a reference: a struct, a trait value, or
    ## a tuple (whose copy acquires its elements and whose drop releases
    ## them).
    is_reference_name(name: String): bool {
        return structs.contains(name) or is_trait_name(name) or tuples.contains(name);
    }

    ## The element types of a value aggregate: a tuple's elements, or a value
    ## struct's fields.
    aggregate_elements(name: String): String[]? {
        var found = tuples.try_get(name);
        if (found.is_value()) {
            return found;
        }
        return values.try_get(name);
    }

    ## Whether `name` is a tuple or a value struct.
    is_aggregate(name: String): bool {
        return aggregate_elements(name).is_value();
    }

    ## `__is_pod<T>`: whether a value of sema type `name` is plain data: not
    ## a reference, and not a tuple holding one at any depth.
    is_pod_name(name: String): bool {
        var pending = [name];
        while (pending.count > 0) {
            var next = pending.pop();
            var elements = aggregate_elements(next);
            if (elements.is_value()) {
                for (var element in elements.value()) {
                    pending.append(element);
                }
            } else if (is_reference_name(next)) {
                return false;
            }
        }
        return true;
    }

    ## The LLVM type a reference of sema type `name` is stored as: a pointer
    ## for a struct, `[2 x ptr]` for a trait value, the elements for a tuple.
    reference_value_type(name: String): llvm.Type {
        var found = types.get(name);
        if (found.is_value()) {
            var ty = found.value();
            if (ty.kind() == llvm.TypeKind.Array and types.is_trait(name)) {
                return ty;
            }
            if (ty.kind() == llvm.TypeKind.Struct and (tuples.contains(name) or values.contains(name))) {
                return ty;
            }
        }
        return context.pointer_type();
    }

    ## The object a reference points at: the pointer itself for a struct, the
    ## object half of a trait value.
    object_pointer(value: llvm.Value): Result<llvm.Value> {
        if (_is_pointer(value)) {
            return Result<llvm.Value>.ok(value);
        }
        if (_is_array(value)) {
            return Result<llvm.Value>.ok(builder.extract_value(value, 0, "object"));
        }
        return fail<llvm.Value>($"expected a reference, got {value.to_string()}");
    }

    # Tuples
    #
    # A tuple `(A, B)` (`__tuple<A, B>`) is a literal struct `{A', B'}` of its
    # elements' slot types, held by value. Its `__acquire` and `__release` are
    # thunks that step each reference element.

    ## Registers tuple type `ty` (and any tuple among its elements) with
    ## `Types`, in dependency order.
    register_tuple(ty: TypeName): Result<void> {
        var name = ty.to_string();
        if (tuples.contains(name)) {
            return Result<void>.ok();
        }
        var slots = Array<llvm.Type>();
        var elements = Array<String>();
        var parts = ty.is_tuple() ? ty.sub_types : Array<TypeName>();
        for (var part in parts) {
            var element = parse_type_string(part.to_string());
            if (element.is_tuple()) {
                register_tuple(element)?;
            }
            var element_name = element.to_string();
            var found = types.get(element_name);
            # A tuple in a generic base (`(K, V)`) names its type parameters;
            # only its specializations are emitted.
            if (!found.is_value()) {
                return Result<void>.ok();
            }
            var slot = is_object(found.value()) ? context.pointer_type() : found.value();
            slots.append(slot);
            elements.append(element_name);
        }
        types.register_tuple(name, slots);
        tuples[name] = elements;
        tuple_order.append(name);
        return Result<void>.ok();
    }

    ## `Tuple.__acquire(value)` / `Tuple.__release(value)`: steps each
    ## reference element of the tuple, first to last.
    emit_tuple_refcount_thunk(tuple: String, member: String): Result<void> {
        var thunk = declare_tuple_refcount_thunk(tuple, member)?;
        return define_tuple_refcount_thunk(tuple, thunk);
    }

    ## Declares `Tuple.__acquire` or `Tuple.__release` without its body.
    declare_tuple_refcount_thunk(tuple: String, member: String): Result<llvm.Value> {
        var ty = types.get(tuple);
        if (!ty.is_value()) {
            return fail<llvm.Value>($"unknown tuple type {tuple}");
        }
        var name = $"{tuple}.{member}";
        var thunk = ir.add_function(name, llvm.Type.function(context.void_type(), [ty.value()]));
        thunk.set_linkage(llvm.Linkage.Private);
        functions[name] = thunk;
        return Result<llvm.Value>.ok(thunk);
    }

    ## The body of a thunk `declare_tuple_refcount_thunk` declared.
    define_tuple_refcount_thunk(tuple: String, thunk: llvm.Value): Result<void> {
        var name = thunk.name();
        var member = name.ends_with(".__acquire") ? "__acquire" : "__release";
        var saved = builder.insert_block();
        var entry = context.append_block(thunk, "entry");
        builder.position_at_end(entry);
        var value = thunk.param(0);
        # A value struct's fields are its elements.
        var found = aggregate_elements(tuple);
        var elements = found.is_value() ? found.value() : Array<String>();
        for (var index in 0..elements.count) {
            var element = elements[index];
            if (!is_reference_name(element)) {
                continue;
            }
            var item = builder.extract_value(value, index as uint, "element");
            call_function($"{element}.{member}", [item])?;
        }
        builder.return_void();
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<void>.ok();
    }

    ## `(tuple local, element index)` when `expr` is `__tuple_N.k`, a
    ## destructuring binding's read of its hidden tuple.
    destructured_element(expr: Expression): (String, uint)? {
        if (expr is MemberRef(member)) {
            if (member.lhs is SymbolRef(symbol)) {
                if (!symbol.id.starts_with("__tuple_")) {
                    return Optional<(String, uint)>.Empty;
                }
                var index = uint.parse(member.name);
                if (!index.is_value()) {
                    return Optional<(String, uint)>.Empty;
                }
                return Optional<(String, uint)>.Value((symbol.id, index.value()));
            }
        }
        return Optional<(String, uint)>.Empty;
    }

    ## A tuple literal: the call of tuple type `tuple`'s constructor. Each
    ## element is copied in (an lvalue read acquires) or moved in (an owned
    ## rvalue keeps its reference); the result owns one reference to each.
    codegen_tuple(tuple: String, args: Expression[]): Result<llvm.Value> {
        var found = tuples.try_get(tuple);
        var elements = found.is_value() ? found.value() : Array<String>();
        var ty_found = types.get(tuple);
        if (!ty_found.is_value() or ty_found.value().kind() != llvm.TypeKind.Struct) {
            return fail<llvm.Value>($"unknown tuple type {tuple}");
        }
        var ty = ty_found.value();
        if (args.count != elements.count) {
            return fail<llvm.Value>($"tuple '{tuple}' has {elements.count} elements, but {args.count} were given");
        }
        var value = ty.undef();
        for (var index in 0..args.count) {
            var arg = args[index];
            var element = elements[index];
            var item = codegen_expr(arg)?;
            if (is_reference_name(element) and is_lvalue_read(arg)) {
                acquire_ref(element, item)?;
            } else if (is_lazy(element)) {
                # Copies of the tuple share its elements, so an empty lazy
                # temporary gets its object now (see `codegen_assignment`).
                item = filled(item, element)?;
            }
            if ((_is_int(item) or _is_float(item)) and sema.is_numeric_type(state, element)) {
                var source = numeric_source_name(arg, item);
                var coerced = coerce(item, source, element);
                # `coerce` works in C's promoted types; fit the slot exactly.
                var field = ty.field(index as uint);
                if (_is_int(coerced) and field.kind() == llvm.TypeKind.Integer and !coerced.value_type().same(field)) {
                    item = builder.int_cast(coerced, field, "element");
                } else {
                    item = coerced;
                }
            }
            value = builder.insert_value(value, item, index as uint, "tuple");
        }
        return Result<llvm.Value>.ok(value);
    }

    ## Whether tuple values `l` and `r` of type `tuple` are equal: every
    ## element compares equal, each as `==` compares it on its own.
    tuple_equal(tuple: String, l: llvm.Value, r: llvm.Value): Result<llvm.Value> {
        var found = aggregate_elements(tuple);
        var elements = found.is_value() ? found.value() : Array<String>();
        var all = context.int1_type().const_uint(1);
        for (var index in 0..elements.count) {
            var a = builder.extract_value(l, index as uint, "lhs_element");
            var b = builder.extract_value(r, index as uint, "rhs_element");
            var same = value_equal(elements[index], a, b)?;
            all = builder.bit_and(all, same, "tuple_equal");
        }
        return Result<llvm.Value>.ok(all);
    }

    ## The function `a == b` calls for two values of struct type `ty`: its
    ## `==` taking a `ty`; `ty.==` when it has none, which no function is
    ## named.
    equality_method(ty: String): String {
        var found = equality_methods.try_get(ty);
        return found.is_value() ? found.value() : $"{ty}.==";
    }

    ## `a == b` for two values of sema type `ty`, as an `i1`: a tuple
    ## element-wise, a struct through its `==` when it declares one (else by
    ## identity), a trait value by object, anything else by value.
    value_equal(ty: String, a: llvm.Value, b: llvm.Value): Result<llvm.Value> {
        var method = equality_method(ty);
        # A value struct without its own `==` compares field by field.
        if (tuples.contains(ty) or (values.contains(ty) and !functions.contains(method))) {
            return tuple_equal(ty, a, b);
        }
        if (functions.contains(method)) {
            # A null reference (an unset field, a value enum's payload of
            # another case) equals only null; `==` runs on two objects.
            if (_is_pointer(a) and _is_pointer(b)) {
                var same = builder.compare(llvm.IntPredicate.Equal, a, b, "same");
                return unless_null([a, b], same, (): Result<llvm.Value> => {
                    var called = call_function(method, [a, b])?;
                    return Result<llvm.Value>.ok(as_bool(called));
                });
            }
            var result = call_function(method, [a, b])?;
            return Result<llvm.Value>.ok(as_bool(result));
        }
        var x = a;
        var y = b;
        if (_is_array(a) and _is_array(b)) {
            x = object_pointer(a)?;
            y = object_pointer(b)?;
        }
        if (_is_int(x) and _is_int(y)) {
            return Result<llvm.Value>.ok(builder.compare(llvm.IntPredicate.Equal, x, y, "element_equal"));
        }
        if (_is_float(x) and _is_float(y)) {
            return Result<llvm.Value>.ok(builder.float_compare(llvm.RealPredicate.OrderedEqual, x, y, "element_equal"));
        }
        if (_is_pointer(x) and _is_pointer(y)) {
            var i64 = context.int64_type();
            var x_address = builder.pointer_to_int(x, i64, "lhs_address");
            var y_address = builder.pointer_to_int(y, i64, "rhs_address");
            return Result<llvm.Value>.ok(
                builder.compare(llvm.IntPredicate.Equal, x_address, y_address, "element_equal")
            );
        }
        return fail<llvm.Value>($"cannot compare values of type '{ty}'");
    }

    ## `compute`'s result, or `if_null` when any of `pointers` is null (then
    ## `compute` does not run).
    unless_null(pointers: llvm.Value[], if_null: llvm.Value, compute: () => Result<llvm.Value>): Result<llvm.Value> {
        if (!frame.function.is_value()) {
            return fail<llvm.Value>("no function");
        }
        var function = frame.function.value();
        var any_null = context.int1_type().zero();
        for (var pointer in pointers) {
            var is_null = builder.is_null(pointer, "is_null");
            any_null = builder.bit_or(any_null, is_null, "any_null");
        }
        var from = builder.insert_block();
        if (from.is_null()) {
            return fail<llvm.Value>("no block");
        }
        var call = context.append_block(function, "not_null");
        var done = context.append_block(function, "null_checked");
        builder.conditional_branch(any_null, done, call);
        builder.position_at_end(call);
        var computed = compute()?;
        var computed_in = builder.insert_block();
        if (computed_in.is_null()) {
            return fail<llvm.Value>("no block");
        }
        builder.branch(done);
        builder.position_at_end(done);
        var phi = builder.phi(if_null.value_type(), "result");
        phi.add_incoming([if_null, computed], [from, computed_in]);
        return Result<llvm.Value>.ok(phi);
    }

    ## `hash<T>` of a tuple value: each element's hash folded through
    ## `hash_fold` in order. An element hashes as `hash<E>` would: through the
    ## program's `hash<E>` when there is one, else by identity for references
    ## and by value otherwise.
    tuple_hash(tuple: String, value: llvm.Value): Result<llvm.Value> {
        var found = aggregate_elements(tuple);
        var elements = found.is_value() ? found.value() : Array<String>();
        var h = context.int64_type().const_uint(0xcbf29ce484222325);
        for (var index in 0..elements.count) {
            var element = elements[index];
            var item = builder.extract_value(value, index as uint, "element");
            var own_hash = hash_overrides.contains($"hash<{element}>");
            var derived = $"{element}.{sema.HASH_METHOD}";
            llvm.Value element_hash;
            if (tuples.contains(element) or (values.contains(element) and !own_hash)) {
                element_hash = tuple_hash(element, item)?;
            } else if (functions.contains(derived)) {
                # An `[Equatable]` struct hashes its fields; null as 0.
                var pointer = object_pointer(item)?;
                var zero = context.int64_type().zero();
                element_hash = unless_null([pointer], zero, () => call_function(derived, [item]))?;
            } else if (!own_hash and functions.contains(equality_method(element)) and _is_pointer(item)) {
                # An object compared by its `==` but hashed by identity (an
                # `Array`): equal elements would hash apart, so it adds
                # nothing to the hash.
                continue;
            } else if (own_hash) {
                # A null reference hashes as 0, without the call.
                var function = $"hash<{element}>";
                if (_is_pointer(item)) {
                    var zero = context.int64_type().zero();
                    element_hash = unless_null([item], zero, () => call_function(function, [item]))?;
                } else {
                    element_hash = call_function(function, [item])?;
                }
            } else {
                var hashed = item;
                if (_is_array(item)) {
                    hashed = object_pointer(item)?;
                }
                element_hash = hash_value_to_i64(hashed)?;
            }
            h = hash_fold(h, element_hash)?;
        }
        return Result<llvm.Value>.ok(h);
    }

    ## Loads vtable slot `slot` of trait value `value`.
    vtable_entry(value: llvm.Value, slot: ulong): Result<llvm.Value> {
        var ptr_type = context.pointer_type();
        var table = builder.extract_value(value, 1, "vtable");
        var entry = builder.element_pointer(ptr_type, table, [context.int64_type().const_uint(slot)], false, "slot");
        return Result<llvm.Value>.ok(builder.load(ptr_type, entry, "entry"));
    }

    ## `Trait.__acquire` / `Trait.__release`: nothing for a null value, else
    ## the concrete struct's own member through the vtable.
    emit_trait_refcount_thunk(trait_name: String, member: String, slot: ulong): Result<void> {
        var fat = types.get(trait_name);
        if (!fat.is_value()) {
            return fail<void>($"unknown trait type {trait_name}");
        }
        var ptr_type = context.pointer_type();
        var thunk = ir.add_function($"{trait_name}.{member}", llvm.Type.function(context.void_type(), [fat.value()]));
        thunk.set_linkage(llvm.Linkage.Private);
        functions[$"{trait_name}.{member}"] = thunk;
        var saved = builder.insert_block();
        var entry = context.append_block(thunk, "entry");
        var call_block = context.append_block(thunk, "call");
        var done = context.append_block(thunk, "done");
        builder.position_at_end(entry);
        var value = thunk.param(0);
        var object = object_pointer(value)?;
        var is_null = builder.is_null(object, "is_null");
        builder.conditional_branch(is_null, done, call_block);
        builder.position_at_end(call_block);
        var target = vtable_entry(value, slot)?;
        var target_type = llvm.Type.function(context.void_type(), [ptr_type]);
        builder.call(target_type, target, [object], "");
        builder.branch(done);
        builder.position_at_end(done);
        builder.return_void();
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<void>.ok();
    }

    ## `__weak<Shape>.__acquire` / `__release` (`increment` or not): nothing
    ## for a null value, else an atomic step of the object's weak count,
    ## freeing the memory when the last weak reference goes and no strong
    ## one is left.
    emit_weak_trait_thunk(name: String, increment: bool): Result<void> {
        var fat = types.get(name);
        if (!fat.is_value()) {
            return fail<void>($"unknown weak type {name}");
        }
        var member = increment ? "__acquire" : "__release";
        var thunk = ir.add_function($"{name}.{member}", llvm.Type.function(context.void_type(), [fat.value()]));
        thunk.set_linkage(llvm.Linkage.Private);
        functions[$"{name}.{member}"] = thunk;
        var saved = builder.insert_block();
        var entry = context.append_block(thunk, "entry");
        var step = context.append_block(thunk, "step");
        var done = context.append_block(thunk, "done");
        builder.position_at_end(entry);
        var value = thunk.param(0);
        var object = object_pointer(value)?;
        var is_null = builder.is_null(object, "is_null");
        builder.conditional_branch(is_null, done, step);
        builder.position_at_end(step);
        var after = count_step(object, CountField.Weak, increment, true, false)?;
        if (increment) {
            builder.branch(done);
        } else {
            var free_block = context.append_block(thunk, "free");
            var zero = builder.compare(llvm.IntPredicate.Equal, after, context.int32_type().zero(), "last");
            builder.conditional_branch(zero, free_block, done);
            builder.position_at_end(free_block);
            call_function("_pep_free", [object])?;
            builder.branch(done);
        }
        builder.position_at_end(done);
        builder.return_void();
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<void>.ok();
    }

    ## `Trait.method(value, args...)`: calls the vtable's implementation with
    ## the object as `this`. The arguments pass through untouched.
    emit_trait_dispatch_thunk(trait_name: String, method: FunctionDef, slot: ulong): Result<void> {
        var fat = types.get(trait_name);
        if (!fat.is_value()) {
            return fail<void>($"unknown trait type {trait_name}");
        }
        var ptr_type = context.pointer_type();
        var params = Array<llvm.Type>();
        for (var param in method.parameters) {
            var ty = abi_type(param.ty.to_string());
            locate(ty, param.type_loc);
            params.append(ty?);
        }
        # A trait method declared without a return type (`grow();`) returns
        # nothing, as its implementations do: WebAssembly traps on a call
        # whose type differs from the callee's.
        var returns_nothing = is_void(method.ty) or method.ty.to_string() == AUTO;
        var thunk_type = dispatch_type(fat.value(), params, returns_nothing, method)?;
        var target_type = dispatch_type(ptr_type, params, returns_nothing, method)?;
        var name = $"{trait_name}.{method.name}";
        var thunk = ir.add_function(name, thunk_type);
        thunk.set_linkage(llvm.Linkage.Private);
        functions[name] = thunk;
        var saved = builder.insert_block();
        var entry = context.append_block(thunk, "entry");
        builder.position_at_end(entry);
        var value = thunk.param(0);
        var object = object_pointer(value)?;
        # Calling through a null trait value panics, never jumps through null.
        if (runtime_checks.null and functions.contains("_pep_assert")) {
            var is_set = builder.is_not_null(object, "is_set");
            var message = $"called '{method.name}' on a null '{trait_name}'";
            # A thunk serves every call, so it has no one place to report.
            located_assert(is_set, message, Loc.none())?;
        }
        var target = vtable_entry(value, slot)?;
        var args = [object];
        for (var index in 1..thunk.param_count()) {
            args.append(thunk.param(index));
        }
        var returns = !_returns_void(thunk_type);
        var call = builder.call(target_type, target, args, returns ? "dispatch" : "");
        if (returns) {
            builder.return_value(call);
        } else {
            builder.return_void();
        }
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<void>.ok();
    }

    ## The type of a dispatch thunk (`this_type` the trait value) or of its
    ## target (`this_type` a pointer) for trait method `method`.
    dispatch_type(
        this_type: llvm.Type, params: llvm.Type[], returns_nothing: bool, method: FunctionDef
    ): Result<llvm.Type> {
        var all = [this_type];
        for (var p in params) {
            all.append(p);
        }
        if (returns_nothing) {
            return Result<llvm.Type>.ok(llvm.Type.function(context.void_type(), all));
        }
        var return_type = abi_type(method.ty.to_string())?;
        return Result<llvm.Type>.ok(llvm_fn_type(context, return_type, all, false));
    }

    ## The struct member implementing trait slot `name` with parameter types
    ## `params` for struct `from`: of an overloaded name, the one member of
    ## that name taking `params`.
    vtable_implementer(from: String, name: String, params: String[]): String {
        var st = structs.try_get(from);
        if (!st.is_value()) {
            return name;
        }
        var wanted = set_name(name);
        var found = Array<String>();
        for (var entry in st.value().method_params) {
            var (m, p) = entry;
            if (set_name(m) == wanted and _same_strings(p, params)) {
                found.append(m);
            }
        }
        return found.count == 1 ? found[0] : name;
    }

    ## The vtable of struct `from`'s conformance to trait `to`, emitted on
    ## first use: a private constant array of the struct's members, then its
    ## type id.
    vtable(from: String, to: String): Result<llvm.Value> {
        var global_name = $"__vtable.{from}.{to}";
        var existing = ir.global(global_name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var desc = traits.try_get(to);
        if (!desc.is_value()) {
            return fail<llvm.Value>($"unknown trait type '{to}'");
        }
        # The type id follows the members (see `type_id`).
        var members = Array<(String, Optional<String>)>();
        members.append(("__release", Optional<String>.Empty));
        members.append(("__acquire", Optional<String>.Empty));
        # A slot of an overloaded name takes the struct's member of that name
        # with the slot's parameter types.
        for (var method in desc.value().methods) {
            var (name, params, ret) = method;
            members.append((vtable_implementer(from, name, params), Optional<String>.Value(ret)));
        }
        # Declared before its entries: an entry's covariant adapter can
        # convert to this same trait, and must find this vtable rather than
        # make a second one.
        var ptr_type = context.pointer_type();
        var global = ir.add_global(ptr_type.array_type((members.count as ulong) + 1), global_name);
        global.set_linkage(llvm.Linkage.Private);
        global.set_global_constant(true);
        var entries = Array<llvm.Value>();
        var boxed = values.contains(from);
        for (var entry in members) {
            var (member, declared) = entry;
            var mangled = $"{from}.{member}";
            if (!functions.contains(mangled)) {
                return fail<llvm.Value>($"'{from}' does not implement '{member}', required by trait '{to}'");
            }
            # A value struct's trait value refers to its box_ty: each slot
            # forwards to the value inside it.
            llvm.Value function;
            if (boxed) {
                function = box_member(from, member)?;
            } else {
                function = functions[mangled];
            }
            # A struct result where the trait returns a trait value converts on
            # the way out.
            var returns = Optional<String>.Empty;
            var st = structs.try_get(from);
            if (st.is_value()) {
                returns = st.value().method_returns.try_get(member);
            }
            if (declared.is_value()
                and returns.is_value()
                and is_trait_name(declared.value())
                and structs.contains(returns.value())) {
                function = covariant_adapter(function, returns.value(), declared.value())?;
            }
            entries.append(function);
        }
        entries.append(type_id_value(from).const_int_to_pointer(ptr_type));
        var init = ptr_type.const_array(entries);
        global.set_initializer(init);
        return Result<llvm.Value>.ok(global);
    }

    ## `function` with its struct result (of type `returns`) converted to
    ## trait value `declared`, for a vtable slot whose trait declares the
    ## trait type. The result's one reference moves into the trait value.
    covariant_adapter(function: llvm.Value, returns: String, declared: String): Result<llvm.Value> {
        var name = $"__trait_adapter.{function.name()}.{declared}";
        var existing = ir.function(name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var fat_found = types.get(declared);
        if (!fat_found.is_value() or fat_found.value().kind() != llvm.TypeKind.Array) {
            return fail<llvm.Value>($"unknown trait type '{declared}'");
        }
        var fat = fat_found.value();
        var function_type = function.global_type();
        var params = function_type.param_types();
        var adapter = ir.add_function(name, llvm.Type.function(fat, params));
        adapter.set_linkage(llvm.Linkage.Private);
        var table = vtable(returns, declared)?;
        var saved = builder.insert_block();
        var entry = context.append_block(adapter, "entry");
        builder.position_at_end(entry);
        var args = Array<llvm.Value>();
        for (var index in 0..adapter.param_count()) {
            args.append(adapter.param(index));
        }
        if (_returns_void(function_type)) {
            builder.call(function_type, function, args, "");
            return fail<llvm.Value>($"'{function.name()}' returns nothing");
        }
        var object = builder.call(function_type, function, args, "result");
        # A value struct result moves into a box.
        if (values.contains(returns)) {
            object = box_value(returns, object)?;
        }
        var pair = builder.insert_value(fat.undef(), object, 0, "trait_object");
        pair = builder.insert_value(pair, table, 1, "trait_value");
        builder.return_value(pair);
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<llvm.Value>.ok(adapter);
    }

    ## A trait value is two pointers, which no single atomic instruction
    ## swaps: `Atomic<T>` holds struct references and numbers only.
    reject_atomic_trait(ty_name: String): Result<void> {
        if (is_trait_name(ty_name)) {
            return fail<void>($"atomic operations on trait type '{ty_name}' are not supported");
        }
        if (is_aggregate(ty_name)) {
            return fail<void>(
                $"atomic operations on tuple type '{parse_type_string(ty_name).display()}' are not supported"
            );
        }
        return Result<void>.ok();
    }

    ## The heap layout of a boxed value struct `value`: the two head counts
    ## every object starts with, then the value.
    box_type(value: String): Result<llvm.Type> {
        var ty = types.get(value);
        if (!ty.is_value()) {
            return fail<llvm.Type>($"unknown value struct '{value}'");
        }
        var count = context.int32_type();
        return Result<llvm.Type>.ok(context.struct_type([count, count, ty.value()]));
    }

    ## A new box_ty holding `value`, a value of value struct `name`, owning one
    ## reference. The value moves in: the caller has acquired what a copy
    ## needs.
    box_value(name: String, value: llvm.Value): Result<llvm.Value> {
        var box_ty = box_type(name)?;
        var size = context.int64_type().const_uint(machine.size_of(box_ty));
        var object = call_function("_pep_malloc", [size])?;
        var one = context.int32_type().const_uint(1);
        for (var field in [CountField.Strong, CountField.Weak]) {
            var count = head_count_ptr(object, field)?;
            builder.store(one, count);
        }
        var slot = builder.field_pointer(box_ty, object, 2, "boxed");
        builder.store(value, slot);
        return Result<llvm.Value>.ok(object);
    }

    ## The vtable entry for `member` of a boxed value struct `value`:
    ## `__acquire` and `__release` count the box_ty (the last release releases
    ## the value's references and frees it), and a method calls the value's
    ## own with `this` at the value inside the box.
    box_member(value: String, member: String): Result<llvm.Value> {
        var name = $"__box.{value}.{member}";
        var existing = ir.function(name);
        if (existing.is_value()) {
            return Result<llvm.Value>.ok(existing.value());
        }
        var box_ty = box_type(value)?;
        var ptr_type = context.pointer_type();
        var target = functions[$"{value}.{member}"];
        var counting = member == "__acquire" or member == "__release";
        var fn_type = counting ? llvm.Type.function(context.void_type(), [ptr_type]) : target.global_type();
        var thunk = ir.add_function(name, fn_type);
        thunk.set_linkage(llvm.Linkage.Private);
        var saved = builder.insert_block();
        var entry = context.append_block(thunk, "entry");
        builder.position_at_end(entry);
        var object = thunk.param(0);
        if (counting) {
            var step = context.append_block(thunk, "step");
            var done = context.append_block(thunk, "done");
            var is_null = builder.is_null(object, "is_null");
            builder.conditional_branch(is_null, done, step);
            builder.position_at_end(step);
            var count_ptr = head_count_ptr(object, CountField.Strong)?;
            var count_type = context.int32_type();
            var count = builder.load(count_type, count_ptr, "count");
            var one = count_type.const_uint(1);
            if (member == "__acquire") {
                var next = builder.add(count, one, "count");
                builder.store(next, count_ptr);
                builder.branch(done);
            } else {
                var next = builder.sub(count, one, "count");
                builder.store(next, count_ptr);
                var last = context.append_block(thunk, "last");
                var zero = builder.compare(llvm.IntPredicate.Equal, next, count_type.zero(), "zero");
                builder.conditional_branch(zero, last, done);
                builder.position_at_end(last);
                var slot = builder.field_pointer(box_ty, object, 2, "boxed");
                var held = builder.load(box_ty.field(2), slot, "value");
                call_function($"{value}.__release", [held])?;
                # The strong references' weak reference: a weak trait value
                # (`Weak<Shape>`) may still hold the box_ty, and frees it last.
                var weak = count_step(object, CountField.Weak, false, true, false)?;
                var free_block = context.append_block(thunk, "free");
                var unreferenced = builder.compare(llvm.IntPredicate.Equal, weak, count_type.zero(), "unreferenced");
                builder.conditional_branch(unreferenced, free_block, done);
                builder.position_at_end(free_block);
                call_function("_pep_free", [object])?;
                builder.branch(done);
            }
            builder.position_at_end(done);
            builder.return_void();
        } else {
            var slot = builder.field_pointer(box_ty, object, 2, "boxed");
            var args = [slot];
            for (var index in 1..thunk.param_count()) {
                args.append(thunk.param(index));
            }
            var target_type = target.global_type();
            if (_returns_void(target_type)) {
                builder.call(target_type, target, args, "");
                builder.return_void();
            } else {
                var result = builder.call(target_type, target, args, "result");
                builder.return_value(result);
            }
        }
        if (!saved.is_null()) {
            builder.position_at_end(saved);
        }
        return Result<llvm.Value>.ok(thunk);
    }

    ## `ToTrait`: pairs the object with its vtable. A null object (`__null`)
    ## makes a null trait value.
    codegen_to_trait(value: Expression, from: TypeName, to: TypeName): Result<llvm.Value> {
        var to_name = to.to_string();
        var fat_found = types.get(to_name);
        if (!fat_found.is_value() or fat_found.value().kind() != llvm.TypeKind.Array) {
            return fail<llvm.Value>($"unknown trait type '{to_name}'");
        }
        var fat = fat_found.value();
        if (from.is_pointer() or value is PointerLiteral) {
            return Result<llvm.Value>.ok(fat.zero());
        }
        var from_name = from.to_string();
        llvm.Value object;
        if (values.contains(from_name)) {
            # A value struct is copied into a new box_ty: a read acquires the
            # value's references, an owned rvalue moves them in.
            var read = is_lvalue_read(value);
            var held = codegen_expr(value)?;
            if (read) {
                acquire_ref(from_name, held)?;
            }
            object = box_value(from_name, held)?;
        } else {
            var reference = codegen_expr(value)?;
            object = object_pointer(reference)?;
        }
        var table = vtable(from_name, to_name)?;
        var pair = builder.insert_value(fat.undef(), object, 0, "trait_object");
        pair = builder.insert_value(pair, table, 1, "trait_value");
        return Result<llvm.Value>.ok(pair);
    }

    ## `FromTrait`: whether trait value `value` (of trait `from`) holds one of
    ## `candidates`, or, with `test` false, the value as a `to`: its object
    ## for a struct (a value struct's value, read from its box_ty), or for a
    ## trait the object with the vtable of its struct's conformance to `to`.
    codegen_from_trait(
        value: Expression, from: TypeName, to: TypeName, candidates: TypeName[], test: bool
    ): Result<llvm.Value> {
        var from_name = from.to_string();
        var to_name = to.to_string();
        var desc = traits.try_get(from_name);
        if (!desc.is_value()) {
            return fail<llvm.Value>($"unknown trait type '{from_name}'");
        }
        var methods = desc.value().methods.count;
        var pair = codegen_expr(value)?;
        var object = object_pointer(pair)?;
        var id_type = type_id_value("").value_type();
        var ptr_type = context.pointer_type();
        if (test) {
            var entry = builder.insert_block();
            if (entry.is_null()) {
                return fail<llvm.Value>("no function");
            }
            var function = entry.parent();
            var check = context.append_block(function, "type_check");
            var done = context.append_block(function, "type_checked");
            var is_null = builder.is_null(object, "is_null");
            builder.conditional_branch(is_null, done, check);
            builder.position_at_end(check);
            var id_pointer = vtable_entry(pair, VTABLE_METHODS + methods as ulong)?;
            var id = builder.pointer_to_int(id_pointer, id_type, "type_id");
            var matched = context.int1_type().zero();
            for (var candidate in candidates) {
                var expected = type_id_value(candidate.to_string());
                var same = builder.compare(llvm.IntPredicate.Equal, id, expected, "same_type");
                matched = builder.bit_or(matched, same, "matched");
            }
            var check_end = builder.insert_block();
            builder.branch(done);
            builder.position_at_end(done);
            var phi = builder.phi(context.int1_type(), "is_type");
            phi.add_incoming([context.int1_type().zero(), matched], [entry, check_end]);
            return Result<llvm.Value>.ok(phi);
        }
        if (is_trait_name(to_name)) {
            var fat_found = types.get(to_name);
            if (!fat_found.is_value() or fat_found.value().kind() != llvm.TypeKind.Array) {
                return fail<llvm.Value>($"unknown trait type '{to_name}'");
            }
            var fat = fat_found.value();
            var id_pointer = vtable_entry(pair, VTABLE_METHODS + methods as ulong)?;
            var id = builder.pointer_to_int(id_pointer, id_type, "type_id");
            var selected = ptr_type.zero();
            var index = candidates.count;
            while (index > 0) {
                index -= 1;
                var candidate = candidates[index].to_string();
                var expected = type_id_value(candidate);
                var same = builder.compare(llvm.IntPredicate.Equal, id, expected, "same_type");
                var table = vtable(candidate, to_name)?;
                selected = builder.select(same, table, selected, "vtable");
            }
            var converted = builder.insert_value(fat.undef(), object, 0, "trait_object");
            converted = builder.insert_value(converted, selected, 1, "trait_value");
            return Result<llvm.Value>.ok(converted);
        }
        if (values.contains(to_name)) {
            var box_ty = box_type(to_name)?;
            var slot = builder.field_pointer(box_ty, object, 2, "boxed");
            var field = box_ty.field(2);
            return Result<llvm.Value>.ok(builder.load(field, slot, "unboxed"));
        }
        return Result<llvm.Value>.ok(object);
    }
}
