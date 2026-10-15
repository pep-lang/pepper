## Assignments, binary and unary operators, casts, `&&`/`||` and `?:`: the
## operator half of the expression codegen, with `apply_op`.

import compiler.ast;
import llvm;
import compiler.sema;
import [BinaryOp, CastKind, Expression, Loc, TypeName, UnaryOp] from compiler.sema;
import [Address] from "address";
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import [Generator, Temporary] from "generator";
import "generator";
import "globals";
import "lazy";
import "ops";
import [binary_result_type] from "refs";
import "refs";
import "simd";
import "traits";
import "types";

## The plain operator a compound assignment applies (`+` for `+=`); none
## for any other operator.
_base_assign_op(op: BinaryOp): BinaryOp? {
    match (op) {
        AddAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Add);
        }
        SubAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Sub);
        }
        MulAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Mul);
        }
        DivAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Div);
        }
        ModAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.Mod);
        }
        LShiftAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.LShift);
        }
        RShiftAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.RShift);
        }
        BitAndAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.BitAnd);
        }
        BitOrAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.BitOr);
        }
        BitXorAssign => {
            return Optional<BinaryOp>.Value(BinaryOp.BitXor);
        }
        else => {
            return Optional<BinaryOp>.Empty;
        }
    }
}

## Whether `op` assigns: `=` or a compound assignment.
_is_assignment(op: BinaryOp): bool {
    match (op) {
        Assign, AddAssign, SubAssign, MulAssign, DivAssign, ModAssign, LShiftAssign, RShiftAssign, BitAndAssign, BitOrAssign, BitXorAssign => {
            return true;
        }
        else => {
            return false;
        }
    }
}

## `===` as `==` and `!==` as `!=`; any other operator as itself.
_identity_as_equality(op: BinaryOp): BinaryOp {
    if (op == BinaryOp.Identical) {
        return BinaryOp.Equal;
    }
    if (op == BinaryOp.NotIdentical) {
        return BinaryOp.NotEqual;
    }
    return op;
}

## The operator's variant name (`Add`).
_op_debug(op: BinaryOp): String {
    if (op.to_json() is String(text)) {
        return text;
    }
    return "";
}

## Whether `value` is an integer.
_is_int(value: llvm.Value): bool {
    return value.value_type().kind() == llvm.TypeKind.Integer;
}

## Whether `value` is a pointer.
_is_pointer(value: llvm.Value): bool {
    return value.value_type().kind() == llvm.TypeKind.Pointer;
}

extend Generator {
    ## The sema type of `expr`, or the best-effort name of its value.
    operand_sema_name(expr: Expression, value: llvm.Value): String {
        var name = value_sema_type(expr);
        return name.is_value() ? name.value() : value_type_name(value);
    }

    ## `value` truncated to an address's narrower integer slot type
    ## (`__ptr<char>` coerces to i32 while the slot is i8).
    narrow_to_slot(slot_ty: llvm.Type?, value: llvm.Value): llvm.Value {
        if (slot_ty.is_value() and slot_ty.value().kind() == llvm.TypeKind.Integer and _is_int(value)) {
            var target = slot_ty.value();
            if (value.value_type().int_width() > target.int_width()) {
                return builder.truncate(value, target, "narrow");
            }
        }
        return value;
    }

    ## `lhs = rhs` or a compound assignment: stores into the lhs address,
    ## stepping reference counts for a reference slot. `construct_slot` stores
    ## into a fresh element slot (no old occupant to release).
    codegen_assignment(
        op: BinaryOp, lhs: Expression, rhs: Expression, loc: Loc, construct_slot: bool
    ): Result<llvm.Value> {
        # An owned-rvalue rhs (e.g. `a[i] = f()`) is a temporary: the slot
        # store acquires its own ref for the new occupant, so the temp's
        # creation ref is released after the store.
        var rhs_temp = owned_temp_type(rhs);
        # A tuple or `[Value]` struct (value enums included) is copied field
        # by field, so an empty lazy object stored in one must exist:
        # otherwise each copy would make its own on first write. A place
        # read materializes as usual; a null temporary is filled here.
        var into_value = stores_into_value(lhs);
        keep_lazy = is_final_read(rhs) and !into_value;
        var rhs_val = codegen_expr(rhs)?;
        if (into_value and rhs_temp.is_value() and is_lazy(rhs_temp.value())) {
            rhs_val = filled(rhs_val, rhs_temp.value())?;
        }
        var lhs_addr = codegen_lvalue(lhs)?;
        var lhs_ty = lhs_addr.ty;
        # The sema names carry signedness (`u8` vs `i8`).
        var rhs_name = operand_sema_name(rhs, rhs_val);
        var coerced = coerce(rhs_val, rhs_name, lhs_ty);
        # The sema type name can be a pointer (`__ptr<char>` to i32 in
        # coerce) while the address's LLVM pointee is narrower (i8).
        var slot_ty = lhs_addr.llvm_ty;
        coerced = narrow_to_slot(slot_ty, coerced);
        # Compound assign: load lhs, apply the base op, store.
        var base = _base_assign_op(op);
        if (base.is_value()) {
            var base_op = base.value();
            var loaded = lhs_addr.load(builder);
            if (!loaded.is_value()) {
                return fail<llvm.Value>("compound lhs load");
            }
            var lhs_val = loaded.value();
            var lhs_name = operand_sema_name(lhs, lhs_val);
            # C: `x op= e` is `x = x op e`: the op runs on the usual
            # conversion of (lhs type, rhs type), so feed the unconverted rhs.
            var result_ty = binary_result_type(state, base_op, lhs_name, rhs_name);
            var lhs_c = coerce(lhs_val, lhs_name, result_ty);
            var rhs_c = coerce(rhs_val, rhs_name, result_ty);
            var checked = checked_operands(base_op, lhs_c, rhs_c, result_ty, loc)?;
            llvm.Value result;
            if (checked.is_value()) {
                result = checked.value();
            } else {
                result = apply_op(base_op, lhs_c, rhs_c, result_ty, Optional<llvm.Type>.Empty, Optional<String>.Empty)?;
            }
            # The result converts back to the lhs's type for the store.
            var lhs_sema = operand_sema_name(lhs, lhs_val);
            if (result_ty != lhs_sema) {
                result = coerce(result, result_ty, lhs_sema);
            }
            var fitted = narrow_to_slot(slot_ty, result);
            if (lhs is Index(_) or lhs is ArrayIndex(_)) {
                # Compound store into a struct-reference slot transfers
                # ownership like any other index store.
                index_refcount_ops(lhs_addr.ty, lhs_addr.llvm_ty.value(), lhs_addr.ptr, fitted, rhs)?;
            }
            if (lhs is MemberRef(_)) {
                # Compound store into a struct-typed field transfers
                # ownership like any other reference-slot store.
                field_refcount_ops(lhs, lhs_addr.ptr, fitted, rhs)?;
            }
            if (rhs_temp.is_value()) {
                release_temp(rhs_temp.value(), rhs_val)?;
            }
            lhs_addr.store(builder, fitted)?;
            return Result<llvm.Value>.ok(fitted);
        }
        if (lhs is Index(_) or lhs is ArrayIndex(_)) {
            # The element type is resolved from the buffer's pointee
            # (`_data`), not the index expression itself.
            if (construct_slot) {
                construct_refcount_ops(lhs_addr.ty, lhs_addr.llvm_ty.value(), coerced, rhs)?;
            } else {
                index_refcount_ops(lhs_addr.ty, lhs_addr.llvm_ty.value(), lhs_addr.ptr, coerced, rhs)?;
            }
        }
        if (lhs is MemberRef(_)) {
            # A struct-typed field is one reference slot: storing over it
            # releases the old occupant and acquires the new value.
            field_refcount_ops(lhs, lhs_addr.ptr, coerced, rhs)?;
        }
        if (lhs is SymbolRef(_)) {
            # A plain struct-reference local or global is one reference slot:
            # the same pointer is a no-op, otherwise acquire new then release
            # old.
            var ty_name = lhs_addr.ty;
            if (is_reference_name(ty_name)) {
                store_refcount_ops(ty_name, lhs_addr.ptr, lhs_addr.llvm_ty.value(), coerced, rhs)?;
            }
        }
        if (rhs_temp.is_value()) {
            release_temp(rhs_temp.value(), rhs_val)?;
        }
        lhs_addr.store(builder, coerced)?;
        return Result<llvm.Value>.ok(coerced);
    }

    ## `lhs op rhs`: an assignment, `&&`/`||`, a tuple or trait-value
    ## comparison, or a numeric or pointer operator.
    codegen_binary(op_in: BinaryOp, lhs: Expression, rhs: Expression, loc_in: Loc): Result<llvm.Value> {
        # A check's compile error points at the operator alone, not at the
        # right operand the binary's location also covers.
        var loc = loc_in;
        var width = sema.op_name(op_in).size;
        if (!loc_in.is_none() and width != 0) {
            var start = loc_in.span.start;
            var limit = loc_in.span.end > start + 1 ? loc_in.span.end : start + 1;
            var end = start + width < limit ? start + width : limit;
            loc = Loc.at(loc_in.file, ast.Span(start, end));
        }
        # Assignment: store into the lhs address.
        if (_is_assignment(op_in)) {
            return codegen_assignment(op_in, lhs, rhs, loc, false);
        }
        if (op_in == BinaryOp.LogicalAnd or op_in == BinaryOp.LogicalOr) {
            return codegen_logical(op_in, lhs, rhs);
        }
        # `===`/`!==` are identity comparisons: by here they compare the raw
        # values, exactly what `==`/`!=` do on the same raw values.
        var op = _identity_as_equality(op_in);
        var lhs_temp = owned_temp_type(lhs);
        var rhs_temp = owned_temp_type(rhs);
        # A test against null (`x === __null`) neither writes nor shares
        # `x`, so an empty `[__Lazy]` one stays null.
        bool null_test = lhs is PointerLiteral or rhs is PointerLiteral;
        keep_lazy = null_test;
        var lhs_val = codegen_expr(lhs)?;
        keep_lazy = null_test;
        var rhs_val = codegen_expr(rhs)?;
        # Tuples compare element-wise (`===` too: a tuple has no identity).
        if (lhs_val.value_type().kind() == llvm.TypeKind.Struct) {
            var tuple_ty = value_sema_type(lhs);
            if (tuple_ty.is_value() and is_aggregate(tuple_ty.value())) {
                var tuple = tuple_ty.value();
                # Only `==` and `!=`, and only with another value of the
                # type: any other operator is the user's error.
                if (!(op == BinaryOp.Equal or op == BinaryOp.NotEqual)
                    or !lhs_val.value_type().same(rhs_val.value_type())) {
                    var rhs_ty = value_sema_type(rhs);
                    var rhs_text = rhs_ty.is_value() ? rhs_ty.value() : "";
                    var lhs_display = sema.parse_type_string(tuple).display();
                    var rhs_display = sema.parse_type_string(rhs_text).display();
                    return fail<llvm.Value>(
                        $"invalid operands to binary expression ('{lhs_display}' and '{rhs_display}')"
                    );
                }
                var same = tuple_equal(tuple, lhs_val, rhs_val)?;
                var result = same;
                if (op != BinaryOp.Equal) {
                    result = builder.bit_not(same, "tuple_not_equal");
                }
                if (lhs_temp.is_value()) {
                    release_temp(lhs_temp.value(), lhs_val)?;
                }
                if (rhs_temp.is_value()) {
                    release_temp(rhs_temp.value(), rhs_val)?;
                }
                return Result<llvm.Value>.ok(result);
            }
        }
        # Trait values compare by identity, like the struct references they
        # hold: the same object is the same value, whatever the vtable.
        if (lhs_val.value_type().kind() == llvm.TypeKind.Array or rhs_val.value_type().kind() == llvm.TypeKind.Array) {
            llvm.IntPredicate predicate;
            if (op == BinaryOp.Equal or op == BinaryOp.Identical) {
                predicate = llvm.IntPredicate.Equal;
            } else if (op == BinaryOp.NotEqual) {
                predicate = llvm.IntPredicate.NotEqual;
            } else {
                var lhs_ty = value_sema_type(lhs);
                var rhs_ty = value_sema_type(rhs);
                var lhs_text = lhs_ty.is_value() ? lhs_ty.value() : "";
                var rhs_text = rhs_ty.is_value() ? rhs_ty.value() : "";
                return fail<llvm.Value>($"invalid operands to binary expression ('{lhs_text}' and '{rhs_text}')");
            }
            var i64 = context.int64_type();
            var l_object = object_pointer(lhs_val)?;
            var r_object = object_pointer(rhs_val)?;
            var l = builder.pointer_to_int(l_object, i64, "lhs_object");
            var r = builder.pointer_to_int(r_object, i64, "rhs_object");
            var result = builder.compare(predicate, l, r, "same_object");
            if (lhs_temp.is_value()) {
                release_temp(lhs_temp.value(), lhs_val)?;
            }
            if (rhs_temp.is_value()) {
                release_temp(rhs_temp.value(), rhs_val)?;
            }
            return Result<llvm.Value>.ok(result);
        }
        var lhs_name = operand_sema_name(lhs, lhs_val);
        var rhs_name = operand_sema_name(rhs, rhs_val);
        var result_ty = binary_result_type(state, op, lhs_name, rhs_name);
        # In `p + n` and `p - n`, the offset widens to 64 bits by its own
        # signedness: coercing it to the pointer's type cut it to 32 bits
        # (#524).
        bool pointer_arithmetic = (op == BinaryOp.Add or op == BinaryOp.Sub)
            and sema.is_pointer_name(lhs_name) != sema.is_pointer_name(rhs_name);
        var lhs_operand_ty = pointer_arithmetic and !sema.is_pointer_name(lhs_name) ? "long" : result_ty;
        var rhs_operand_ty = pointer_arithmetic and !sema.is_pointer_name(rhs_name) ? "long" : result_ty;
        var lhs_c = coerce(lhs_val, lhs_name, lhs_operand_ty);
        var rhs_c = coerce(rhs_val, rhs_name, rhs_operand_ty);
        # Pointer arithmetic needs the pointer's element type
        # (`__ptr<char>` strides i8): use the sema type of the lhs expression for that.
        var ptr_elem = Optional<llvm.Type>.Empty;
        var ptr_elem_name = Optional<String>.Empty;
        var lhs_sema = value_sema_type(lhs);
        if (lhs_sema.is_value()) {
            ptr_elem_name = sema.pointee_name(lhs_sema.value());
            if (ptr_elem_name.is_value() and ptr_elem_name.value() != "void") {
                ptr_elem = types.get(ptr_elem_name.value());
            }
        }
        llvm.Value result;
        if (op == BinaryOp.Pow and sema.is_float_type(result_ty)) {
            result = float_pow(lhs_c, rhs_val, rhs_name, result_ty)?;
        } else {
            var checked = checked_operands(op, lhs_c, rhs_c, result_ty, loc)?;
            if (checked.is_value()) {
                result = checked.value();
            } else {
                var applied = apply_op(op, lhs_c, rhs_c, result_ty, ptr_elem, ptr_elem_name);
                if (applied.is_err() and applied.error().message.starts_with("unsupported op")) {
                    var lhs_display = sema.constraint_spelled(sema.parse_type_string(lhs_name));
                    var rhs_display = sema.constraint_spelled(sema.parse_type_string(rhs_name));
                    applied = fail<llvm.Value>(
                        $"invalid operands to binary expression ('{lhs_display}' and '{rhs_display}')"
                    );
                }
                # At the operator, not the right operand.
                locate(applied, loc);
                result = applied?;
            }
        }
        # Owned-rvalue operands are temporaries: released once the op has
        # consumed them.
        if (lhs_temp.is_value()) {
            release_temp(lhs_temp.value(), lhs_val)?;
        }
        if (rhs_temp.is_value()) {
            release_temp(rhs_temp.value(), rhs_val)?;
        }
        return Result<llvm.Value>.ok(result);
    }

    ## `base ** exponent` with a floating-point result, through `llvm.powi`
    ## when the exponent is an integer of at most 32 bits and `llvm.pow`
    ## otherwise. `base` is already converted to `result_ty`; `exponent` is
    ## the unconverted right operand, typed `exponent_ty`.
    float_pow(base: llvm.Value, exponent: llvm.Value, exponent_ty: String, result_ty: String): Result<llvm.Value> {
        var float_ty = base.value_type();
        String name;
        llvm.Value power;
        var exponent_type = exponent.value_type();
        if (exponent_type.kind() == llvm.TypeKind.Integer and exponent_type.int_width() <= 32) {
            var i32_ty = context.int32_type();
            var width = exponent_type.int_width();
            bool unsigned = sema.is_unsigned_int_type(state, exponent_ty);
            var widened = exponent;
            if (width == 32) {
                widened = exponent;
            } else if (width == 1 or unsigned) {
                widened = builder.zero_extend(exponent, i32_ty, "powi_exp");
            } else {
                widened = builder.sign_extend(exponent, i32_ty, "powi_exp");
            }
            # A `uint` above `i32::MAX` would turn negative in `powi`.
            if (unsigned and width == 32) {
                name = "llvm.pow";
                power = coerce(exponent, exponent_ty, result_ty);
            } else {
                name = "llvm.powi";
                power = widened;
            }
        } else {
            name = "llvm.pow";
            power = coerce(exponent, exponent_ty, result_ty);
        }
        var overloaded = [float_ty];
        if (name == "llvm.powi") {
            overloaded.append(context.int32_type());
        }
        var declaration = ir.intrinsic(name, overloaded);
        if (!declaration.is_value()) {
            return fail<llvm.Value>($"no {name}");
        }
        var function = declaration.value();
        return Result<llvm.Value>.ok(builder.call(function.global_type(), function, [base, power], "pow"));
    }

    ## Resolves an lvalue expression to an address (an assignment target).
    codegen_lvalue(expr: Expression): Result<Address> {
        var result = codegen_lvalue_unlocated(expr);
        locate(result, sema.expression_loc(expr));
        return result;
    }

    codegen_lvalue_unlocated(expr: Expression): Result<Address> {
        match (expr) {
            SymbolRef(node) => {
                var local = frame.find_local(node.id);
                if (local.is_value()) {
                    return Result<Address>.ok(local.value());
                }
                var global = global_address(node.id)?;
                if (global.is_value()) {
                    return Result<Address>.ok(global.value());
                }
                return fail<Address>($"unknown lvalue {node.id}");
            }
            ThisRef => {
                var storage = value_this()?;
                if (storage.is_value()) {
                    return Result<Address>.ok(storage.value());
                }
                var this_local = frame.find_local("this");
                if (this_local.is_value()) {
                    return Result<Address>.ok(this_local.value());
                }
                return fail<Address>("no this");
            }
            MemberRef(node) => {
                var owner = struct_name_of(node.lhs);
                if (owner.is_value() and tuples.contains(owner.value())) {
                    return fail<Address>("tuple elements are immutable");
                }
                var struct_name = owner.is_value() ? owner.value() : "";
                # An owned-rvalue receiver (`f().x = v`) is a temporary: its
                # creation ref is released at the end of the full expression,
                # after the store through the field address.
                var lhs_temp = owned_temp_type(node.lhs);
                var this_ptr = codegen_expr(node.lhs)?;
                var base_ptr = this_ptr;
                if (this_ptr.value_type().kind() == llvm.TypeKind.Struct) {
                    var receiver = codegen_lvalue(node.lhs)?;
                    base_ptr = receiver.ptr;
                }
                var found = structs.try_get(struct_name);
                if (!found.is_value()) {
                    return fail<Address>($"not a struct: {struct_name}");
                }
                var desc = found.value();
                long idx = -1;
                for (var i in 0..desc.fields.count) {
                    var (field_name, _) = desc.fields[i];
                    if (field_name == node.name) {
                        idx = i as long;
                        break;
                    }
                }
                if (idx < 0) {
                    return fail<Address>($"no member named '{node.name}' in '{struct_name}'");
                }
                var index = idx as uint;
                var (_, ty_name) = desc.fields[idx as ulong];
                # The slot's type comes from the object's layout, not from the
                # field's Pepper type: a struct-typed field is a `ptr` slot (a
                # trait-typed one a `[2 x ptr]`).
                llvm.Type field_ty;
                if (!desc.llvm_type.is_opaque() and index < desc.llvm_type.field_count()) {
                    field_ty = desc.llvm_type.field(index);
                } else {
                    var resolved = types.get(ty_name);
                    if (!resolved.is_value()) {
                        return fail<Address>($"unknown field type {ty_name}");
                    }
                    field_ty = resolved.value();
                }
                var gep = field_address(desc, base_ptr, index, node.name);
                if (lhs_temp.is_value()) {
                    deferred_temps.append(Temporary(this_ptr, lhs_temp.value()));
                }
                return Result<Address>.ok(Address.typed(node.name, ty_name, field_ty, gep));
            }
            Index(node) => {
                return index_lvalue(node.lhs, node.rhs);
            }
            ArrayIndex(node) => {
                return index_lvalue(node.lhs, node.rhs);
            }
            else => {
                return fail<Address>("unsupported lvalue");
            }
        }
    }

    ## The address of `lhs[rhs]`, an element store: GEP into the buffer.
    index_lvalue(lhs: Expression, rhs: Expression): Result<Address> {
        var index = codegen_expr(rhs)?;
        # An owned-rvalue receiver (`f()[i] = v`) is a temporary: its
        # creation ref is released at the end of the full expression.
        var lhs_temp = owned_temp_type(lhs);
        var slot_ptr = subscripted_pointer(lhs)?;
        # A nested index (`outer._data[0][i] = v`) stores into the inner
        # struct's own `_data` buffer, not its reference slot.
        var nested = nested_index_buffer(lhs, slot_ptr)?;
        var ptr = slot_ptr;
        String elem_name;
        if (nested.is_value()) {
            var (buffer, name) = nested.value();
            ptr = buffer;
            elem_name = name;
        } else {
            var pointee = index_receiver_pointee(lhs);
            elem_name = pointee.is_value() ? pointee.value() : "i32";
        }
        # The element's value type, so stores truncate to it; struct
        # elements load and store as pointers.
        var element_ty = slot_stride(buffer_element_type(elem_name));
        var gep = builder.element_pointer(element_ty, ptr, [index], false, "idxl");
        if (lhs_temp.is_value()) {
            deferred_temps.append(Temporary(slot_ptr, lhs_temp.value()));
        }
        return Result<Address>.ok(Address.typed("idxl", elem_name, element_ty, gep));
    }

    ## `lhs op rhs` through `checked_int_binary` when both are integers;
    ## none when `op` has no check or the operands are not.
    checked_operands(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, ty: String, loc: Loc): Result<llvm.Value?> {
        var result = Result<llvm.Value?>.ok(Optional<llvm.Value>.Empty);
        if (_is_int(lhs) and _is_int(rhs)) {
            result = checked_int_binary(op, lhs, rhs, ty, loc);
        }
        if (result.is_err()) {
            locate_error(result.error().message, loc);
        }
        return result;
    }

    ## A unary operator: `-`, `+`, `!`, `~`, and the increments and
    ## decrements, which modify their operand in place.
    codegen_unary(op: UnaryOp, operand: Expression, loc: Loc): Result<llvm.Value> {
        match (op) {
            Neg => {
                var operand_temp = owned_temp_type(operand);
                var value = codegen_expr(operand)?;
                # C integer promotions apply to the unary operand first: `-x`
                # on a narrower-than-int x negates at int width.
                var sema_ty = value_sema_type(operand);
                if (_is_int(value) and value.value_type().int_width() < 32 and sema_ty.is_value()) {
                    value = coerce(value, sema_ty.value(), "i32");
                }
                # `-x` is `0 - x`, so negating the most negative value of a
                # signed type (or any nonzero unsigned value) overflows.
                var promoted = Optional<String>.Empty;
                if (sema_ty.is_value()) {
                    promoted = Optional<String>.Value(sema.result_type(state, sema_ty.value(), sema_ty.value()));
                }
                var ty = value.value_type();
                llvm.Value result;
                if (_is_int(value) and ty.int_width() >= 8) {
                    bool unsigned = promoted.is_value() and sema.is_unsigned_int_type(state, promoted.value());
                    result = checked_arithmetic(BinaryOp.Sub, ty.zero(), value, unsigned, loc, "negation")?;
                } else if (_is_int(value)) {
                    result = builder.negate(value, "neg");
                } else if (is_float_kind(ty)) {
                    result = builder.float_negate(value, "fneg");
                } else {
                    return fail<llvm.Value>("unsupported neg operand");
                }
                if (operand_temp.is_value()) {
                    release_temp(operand_temp.value(), value)?;
                }
                return Result<llvm.Value>.ok(result);
            }
            Pos => {
                return codegen_expr(operand);
            }
            LogicalNot => {
                var operand_temp = owned_temp_type(operand);
                var value = codegen_expr(operand)?;
                var b = as_bool(value);
                if (operand_temp.is_value()) {
                    release_temp(operand_temp.value(), value)?;
                }
                return Result<llvm.Value>.ok(builder.bit_not(b, "lnot"));
            }
            BitNot => {
                var operand_temp = owned_temp_type(operand);
                var value = codegen_expr(operand)?;
                # C integer promotions apply to the unary operand first.
                var sema_ty = value_sema_type(operand);
                if (_is_int(value) and value.value_type().int_width() < 32 and sema_ty.is_value()) {
                    value = coerce(value, sema_ty.value(), "i32");
                }
                if (!_is_int(value)) {
                    return fail<llvm.Value>("unsupported bitnot operand");
                }
                var result = builder.bit_not(value, "bnot");
                if (operand_temp.is_value()) {
                    release_temp(operand_temp.value(), value)?;
                }
                return Result<llvm.Value>.ok(result);
            }
            PreInc, PostInc, PreDec, PostDec => {
                # ++x / x++ / --x / x--: modify in place, return new or old.
                var addr = codegen_lvalue(operand)?;
                var loaded = addr.load(builder);
                if (!loaded.is_value()) {
                    return fail<llvm.Value>("inc load");
                }
                var old = loaded.value();
                bool inc = op == UnaryOp.PreInc or op == UnaryOp.PostInc;
                var ty = old.value_type();
                llvm.Value new_val;
                if (_is_int(old) and ty.int_width() >= 32) {
                    # `x++` is `x += 1`: a type narrower than `int` steps at
                    # `int` and the store keeps the low bits, so only `int`
                    # and wider can overflow.
                    bool unsigned = sema.is_unsigned_int_type(state, sema.stored_as(state, addr.ty));
                    var one = ty.const_uint(1);
                    var base = inc ? BinaryOp.Add : BinaryOp.Sub;
                    var name = inc ? "increment" : "decrement";
                    new_val = checked_arithmetic(base, old, one, unsigned, loc, name)?;
                } else if (_is_int(old)) {
                    var one = ty.const_uint(1);
                    new_val = inc ? builder.add(old, one, "inc") : builder.sub(old, one, "dec");
                } else if (is_float_kind(ty)) {
                    var one = ty.const_real(1.0);
                    new_val = inc ? builder.float_add(old, one, "finc") : builder.float_sub(old, one, "fdec");
                } else {
                    return fail<llvm.Value>("unsupported inc operand");
                }
                addr.store(builder, new_val)?;
                if (op == UnaryOp.PreInc or op == UnaryOp.PreDec) {
                    return Result<llvm.Value>.ok(new_val);
                }
                return Result<llvm.Value>.ok(old);
            }
        }
    }

    ## `expr as T`: a static cast (a compile error if the cast cannot
    ## succeed). Numeric and bool targets; a pointer may cast to an integer
    ## or to another pointer type, and `unsafe_cast` between a number and a
    ## float of the same width keeps the bits.
    codegen_cast(expr: Expression, ty: TypeName, kind: CastKind): Result<llvm.Value> {
        # Source signedness decides zext vs sext on widening; resolve it
        # before codegen_expr mutates the frame.
        var source_name = value_sema_type(expr);
        # Sema's `check_casts` reported the casts whose operand it could
        # type; the exact type decides the rest.
        if (source_name.is_value()) {
            var refused = sema.check_cast(sema.parse_type_string(source_name.value()), ty, kind, state);
            if (refused.is_value()) {
                return fail<llvm.Value>(refused.value());
            }
        }
        # An owned-rvalue source is a temporary: released once the cast has
        # consumed it.
        var src_temp = owned_temp_type(expr);
        var val = codegen_expr(expr)?;
        var name = ty.to_string();
        var found = types.get(name);
        if (!found.is_value()) {
            return fail<llvm.Value>($"unknown cast target type {name}");
        }
        var target = found.value();
        var from = val.value_type();
        bool from_int = from.kind() == llvm.TypeKind.Integer;
        bool from_float = is_float_kind(from);
        bool from_pointer = from.kind() == llvm.TypeKind.Pointer;
        bool to_int = target.kind() == llvm.TypeKind.Integer;
        bool to_float = is_float_kind(target);
        bool to_pointer = target.kind() == llvm.TypeKind.Pointer;
        # A no-op cast (identical LLVM types) is not a copy: the source
        # keeps its ref, so an owned-rvalue source stays a live temporary.
        bool identity = (((from_int and to_int) or (from_float and to_float)) and from.same(target))
            or (from_pointer and to_pointer);
        llvm.Value result;
        if (from_int and to_int) {
            if (from.same(target)) {
                result = val;
            } else if (from.int_width() < target.int_width()) {
                # 1-bit bool values and unsigned sources widen zero-extended;
                # signed types sign-extend. `__ptr<void>` indexes load one byte
                # (unsigned char in C).
                bool unsigned = source_name.is_value()
                    and (sema.is_unsigned_int_type(state, source_name.value())
                        or source_name.value() == "bool"
                        or source_name.value() == "void");
                if (from.int_width() == 1 or unsigned) {
                    result = builder.zero_extend(val, target, "cast");
                } else {
                    result = builder.sign_extend(val, target, "cast");
                }
            } else if (target.int_width() == 1) {
                # A 1-bit target is a bool: compare != 0 (`2 as bool` is
                # true); truncation would keep only the low bit.
                result = as_bool(val);
            } else {
                # Truncate: static_cast keeps the low bits.
                result = builder.truncate(val, target, "cast");
            }
        } else if (from_float and to_float) {
            if (from.same(target)) {
                result = val;
            } else if (_float_width(from) < _float_width(target)) {
                result = builder.float_extend(val, target, "cast");
            } else {
                result = builder.float_truncate(val, target, "cast");
            }
        } else if (from_int and to_float and kind == CastKind.Unsafe) {
            result = builder.bit_cast(val, target, "bits");
        } else if (from_float and to_int and kind == CastKind.Unsafe) {
            result = builder.bit_cast(val, target, "bits");
        } else if (from_int and to_float) {
            # Unsigned and 1-bit sources convert with uitofp, or
            # `u8 200 as float` reinterprets as -56.0.
            bool unsigned = from.int_width() == 1
                or (source_name.is_value()
                    and (sema.is_unsigned_int_type(state, source_name.value()) or source_name.value() == "bool"));
            if (unsigned) {
                result = builder.unsigned_to_float(val, target, "cast");
            } else {
                result = builder.signed_to_float(val, target, "cast");
            }
        } else if (from_float and to_int) {
            if (target.int_width() == 1) {
                # fptosi to i1 is poison outside -1..0; a bool target
                # compares != 0.
                result = as_bool(val);
            } else if (sema.is_unsigned_int_type(state, name)) {
                # fptosi is poison above the signed range of the target.
                result = builder.float_to_unsigned(val, target, "cast");
            } else {
                result = builder.float_to_signed(val, target, "cast");
            }
        } else if (from_pointer and to_pointer) {
            # LLVM pointers are opaque, so only the sema pointee changes.
            result = val;
        } else if (from_pointer and to_int) {
            # Address-as-integer for C ABI interop.
            result = builder.pointer_to_int(val, target, "ptrtoint");
        } else if (from_int and to_pointer) {
            result = builder.int_to_pointer(val, target, "inttoptr");
        } else {
            return fail<llvm.Value>($"cannot cast to {name}");
        }
        if (!identity and src_temp.is_value()) {
            release_temp(src_temp.value(), val)?;
        }
        return Result<llvm.Value>.ok(result);
    }

    ## `a && b` / `a || b`: `b` runs only when `a` does not decide the
    ## result. Both operands are tested for truth; the result is a bool.
    codegen_logical(op: BinaryOp, lhs: Expression, rhs: Expression): Result<llvm.Value> {
        if (!frame.function.is_value()) {
            return fail<llvm.Value>("no function");
        }
        var fn_value = frame.function.value();
        bool is_and = op == BinaryOp.LogicalAnd;
        var lhs_temp = owned_temp_type(lhs);
        var lhs_val = codegen_expr(lhs)?;
        var lhs_bool = as_bool(lhs_val);
        if (lhs_temp.is_value()) {
            release_temp(lhs_temp.value(), lhs_val)?;
        }
        var lhs_end = builder.insert_block();
        var rhs_block = context.append_block(fn_value, is_and ? "and.rhs" : "or.rhs");
        var merge_block = context.append_block(fn_value, is_and ? "and.end" : "or.end");
        if (is_and) {
            builder.conditional_branch(lhs_bool, rhs_block, merge_block);
        } else {
            builder.conditional_branch(lhs_bool, merge_block, rhs_block);
        }

        builder.position_at_end(rhs_block);
        # The rhs runs conditionally, so its temporaries are released in its
        # own block.
        var rhs_temp = owned_temp_type(rhs);
        var rhs_val = codegen_expr_in_arm(rhs)?;
        var rhs_bool = as_bool(rhs_val);
        if (rhs_temp.is_value()) {
            release_temp(rhs_temp.value(), rhs_val)?;
        }
        builder.branch(merge_block);
        var rhs_end = builder.insert_block();

        builder.position_at_end(merge_block);
        var bool_ty = context.int1_type();
        var phi = builder.phi(bool_ty, is_and ? "and" : "or");
        var decided = bool_ty.const_uint(is_and ? 0 : 1);
        phi.add_incoming([decided, rhs_bool], [lhs_end, rhs_end]);
        return Result<llvm.Value>.ok(phi);
    }

    ## Acquires a ternary arm that reads a reference, when the other arm is
    ## an owned rvalue (see `is_owned_rvalue`).
    copy_arm(arm: Expression, value: llvm.Value): Result<void> {
        if (is_owned_rvalue(arm) or arm is PointerLiteral) {
            return Result<void>.ok();
        }
        var ty = value_sema_type(arm);
        if (is_struct_ref_name(ty)) {
            acquire_copy(ty.is_value() ? ty.value() : "", value, arm)?;
        }
        return Result<void>.ok();
    }

    ## The numeric type a `?:` converts both arms to (`conditional_result`),
    ## or none when an arm is not a number or its type is unknown.
    conditional_type(true_expr: Expression, false_expr: Expression): String? {
        var true_name = value_sema_type(true_expr);
        if (!true_name.is_value()) {
            return Optional<String>.Empty;
        }
        var false_name = value_sema_type(false_expr);
        if (!false_name.is_value()) {
            return Optional<String>.Empty;
        }
        if (!sema.is_numeric_type(state, true_name.value()) or !sema.is_numeric_type(state, false_name.value())) {
            return Optional<String>.Empty;
        }
        return Optional<String>.Value(sema.conditional_result(state, true_name.value(), false_name.value()));
    }

    ## Converts a `?:` arm's numeric value to the conditional's type
    ## `common`, from the arm's own type (which carries its signedness).
    convert_arm(expr: Expression, value: llvm.Value, common: String?): llvm.Value {
        if (!common.is_value()) {
            return value;
        }
        var from = numeric_source_name(expr, value);
        return coerce(value, from, common.value());
    }

    ## `condition ? true_expr : false_expr`: each arm in its own block,
    ## merged by a phi.
    codegen_ternary(condition: Expression, true_expr: Expression, false_expr: Expression): Result<llvm.Value> {
        if (!frame.function.is_value()) {
            return fail<llvm.Value>("no function");
        }
        var fn_value = frame.function.value();
        var true_block = context.append_block(fn_value, "true");
        var false_block = context.append_block(fn_value, "false");
        var merge_block = context.append_block(fn_value, "ternarycont");

        var cond_temp = owned_temp_type(condition);
        var cond = codegen_expr(condition)?;
        if (cond_temp.is_value()) {
            release_temp(cond_temp.value(), cond)?;
        }
        var cond_bool = as_bool(cond);
        builder.conditional_branch(cond_bool, true_block, false_block);

        # One owned arm makes the result owned: copy the other arm's read.
        bool owned = is_owned_rvalue(true_expr) or is_owned_rvalue(false_expr);
        builder.position_at_end(true_block);
        # Numeric arms convert to the conditional's type inside their own
        # block, before the branch, so the phi sees one type.
        var common = conditional_type(true_expr, false_expr);
        var true_val = codegen_expr_in_arm(true_expr)?;
        if (owned) {
            copy_arm(true_expr, true_val)?;
        }
        true_val = convert_arm(true_expr, true_val, common);
        # The arm's creation ref survives into the phi: a ternary of owned
        # rvalues is itself an owned rvalue.
        builder.branch(merge_block);
        var true_end = builder.insert_block();

        builder.position_at_end(false_block);
        var false_val = codegen_expr_in_arm(false_expr)?;
        if (owned) {
            copy_arm(false_expr, false_val)?;
        }
        false_val = convert_arm(false_expr, false_val, common);
        builder.branch(merge_block);
        var false_end = builder.insert_block();

        builder.position_at_end(merge_block);
        # Arms of unknown type that still differ in width promote at the end
        # of their own blocks, by their LLVM types.
        if (!true_val.value_type().same(false_val.value_type())) {
            var promoted_ty = sema.result_type(state, value_type_name(true_val), value_type_name(false_val));
            var true_branch = true_end.terminator();
            if (!true_branch.is_null()) {
                builder.position_before(true_branch);
            }
            true_val = coerce(true_val, value_type_name(true_val), promoted_ty);
            var false_branch = false_end.terminator();
            if (!false_branch.is_null()) {
                builder.position_before(false_branch);
            }
            false_val = coerce(false_val, value_type_name(false_val), promoted_ty);
            builder.position_at_end(merge_block);
            keep_location();
        }
        var phi = builder.phi(true_val.value_type(), "ternary");
        phi.add_incoming([true_val, false_val], [true_end, false_end]);
        return Result<llvm.Value>.ok(phi);
    }

    ## Applies a binary operator to two coerced values: integers and floats
    ## by their own operators, pointer comparisons and arithmetic, and a
    ## mixed integer and pointer comparison.
    apply_op(
        op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, ty_name: String, ptr_elem: llvm.Type?, ptr_elem_name: String?
    ): Result<llvm.Value> {
        var lhs_ty = lhs.value_type();
        var rhs_ty = rhs.value_type();
        if (_is_int(lhs) and _is_int(rhs)) {
            # Mixed widths: widen both to the wider one before the op. Only
            # fires if the callers' coercion failed; 1-bit values (bools) are
            # unsigned 0/1 and zero-extend.
            var l = lhs;
            var r = rhs;
            if (lhs_ty.int_width() > rhs_ty.int_width()) {
                r = rhs_ty.int_width() == 1 ?
                    builder.zero_extend(rhs, lhs_ty, "argw") :
                    builder.sign_extend(rhs, lhs_ty, "argw");
            } else if (lhs_ty.int_width() < rhs_ty.int_width()) {
                l = lhs_ty.int_width() == 1 ?
                    builder.zero_extend(lhs, rhs_ty, "argw") :
                    builder.sign_extend(lhs, rhs_ty, "argw");
            }
            var value = int_binary(op, l, r, ty_name);
            if (!value.is_value()) {
                return fail<llvm.Value>($"unsupported op {_op_debug(op)}");
            }
            return Result<llvm.Value>.ok(value.value());
        }
        if (is_float_kind(lhs_ty) and is_float_kind(rhs_ty)) {
            var value = sema.is_comparison(op) ? float_compare(op, lhs, rhs) : float_binary(op, lhs, rhs);
            if (!value.is_value()) {
                return fail<llvm.Value>($"unsupported op {_op_debug(op)}");
            }
            return Result<llvm.Value>.ok(value.value());
        }
        if (_is_pointer(lhs) and _is_pointer(rhs)) {
            var value = pointer_binary(op, lhs, rhs);
            if (!value.is_value()) {
                return fail<llvm.Value>($"unsupported op {_op_debug(op)}");
            }
            return Result<llvm.Value>.ok(value.value());
        }
        # Pointer arithmetic: ptr + int / ptr - int (e.g. `Data + idx`).
        # Other ops (`ptr == int`) fall through to the mixed comparison.
        if (_is_pointer(lhs) and _is_int(rhs) and (op == BinaryOp.Add or op == BinaryOp.Sub)) {
            var idx = op == BinaryOp.Add ? rhs : builder.negate(rhs, "negidx");
            # Stride by the pointer's element type (`__ptr<char>` is i8,
            # `__ptr<int>` i32); opaque (`__ptr<void>`) pointers stride by
            # byte, as does a declared pointer result whose element type did
            # not resolve.
            llvm.Type element_ty;
            var elem_kind = ptr_elem.is_value() ? ptr_elem.value().kind() : llvm.TypeKind.Void;
            if (ptr_elem.is_value()
                and (elem_kind == llvm.TypeKind.Integer
                    or is_float_kind(ptr_elem.value())
                    or elem_kind == llvm.TypeKind.Pointer)) {
                element_ty = ptr_elem.value();
            } else if (ptr_elem_name.is_value() and ptr_elem_name.value() == "void") {
                element_ty = context.int8_type();
            } else if (ptr_elem_name.is_value() and sema.is_pointer_name(ptr_elem_name.value())) {
                # A pointer to pointers (`__ptr<__ptr<void>>`) strides by a
                # pointer.
                element_ty = context.pointer_type();
            } else if (sema.is_pointer_name(ty_name)) {
                element_ty = context.int8_type();
            } else {
                element_ty = context.int32_type();
            }
            return Result<llvm.Value>.ok(builder.element_pointer(element_ty, lhs, [idx], true, "ptrarith"));
        }
        # Mixed int/pointer comparison: ptrtoint the pointer side.
        if (sema.is_comparison(op)) {
            llvm.Value ptr_val;
            llvm.Value int_val;
            bool int_on_left;
            if (_is_int(lhs) and _is_pointer(rhs)) {
                ptr_val = rhs;
                int_val = lhs;
                int_on_left = true;
            } else if (_is_pointer(lhs) and _is_int(rhs)) {
                ptr_val = lhs;
                int_val = rhs;
                int_on_left = false;
            } else {
                return fail<llvm.Value>($"unsupported operand kinds for {_op_debug(op)}");
            }
            var i64 = context.int64_type();
            var as_int = builder.pointer_to_int(ptr_val, i64, "p2i");
            # `ty_name` names the integer operand (binary_result_type): widen
            # it to address width by its own signedness.
            var width = int_val.value_type().int_width();
            var widened = int_val;
            if (width >= 64) {
                widened = int_val;
            } else if (width == 1 or sema.is_unsigned_int_type(state, ty_name)) {
                widened = builder.zero_extend(int_val, i64, "argw");
            } else {
                widened = builder.sign_extend(int_val, i64, "argw");
            }
            var li = int_on_left ? widened : as_int;
            var ri = int_on_left ? as_int : widened;
            llvm.IntPredicate predicate;
            if (op == BinaryOp.Equal or op == BinaryOp.Identical) {
                predicate = llvm.IntPredicate.Equal;
            } else if (op == BinaryOp.NotEqual) {
                predicate = llvm.IntPredicate.NotEqual;
            } else {
                return fail<llvm.Value>($"unsupported op {_op_debug(op)}");
            }
            return Result<llvm.Value>.ok(builder.compare(predicate, li, ri, "mixedcmp"));
        }
        return fail<llvm.Value>($"unsupported operand kinds for {_op_debug(op)}");
    }
}
