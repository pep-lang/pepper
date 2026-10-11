## SIMD vectors (#517): the built-in type `__simd<T, N>`, LLVM's `<N x T>`,
## and the `__simd_<op><V>(args)` intrinsics (`Expression.Simd`) that the
## runtime's `simd.Vector<T, N>` and `simd.Mask<N>` are written with.
##
## Each operation is one or a few LLVM instructions or vector intrinsics,
## picked by the lane type: signed or unsigned integer, or float. Nothing
## here checks a value: the runtime panics before an operation LLVM leaves
## undefined (a zero divisor, a shift count of at least the lane width, a
## lane index out of range), and the operations that would otherwise be
## undefined are chosen so they are not (`llvm.fptosi.sat`, lane indices of
## `shuffle` masked to the lane count).

import llvm;
import compiler.sema;
import [Expression, PassState, SimdOp, TypeName] from compiler.sema;
import "address";
import "calls";
import "checks";
import "expressions";
import "functions";
import [Generator] from "generator";
import "generator";
import "globals";
import "lazy";
import "operators";
import "ops";
import "refs";
import "traits";
import [simd_shape] from "types";
import "types";

## Every SIMD operation, with the name after `__simd_` that calls it.
_simd_operations(): Array<(SimdOp, String)> {
    return [
        (SimdOp.Splat, "splat"),
        (SimdOp.Add, "add"),
        (SimdOp.Subtract, "subtract"),
        (SimdOp.Multiply, "multiply"),
        (SimdOp.Divide, "divide"),
        (SimdOp.Remainder, "remainder"),
        (SimdOp.And, "and"),
        (SimdOp.Or, "or"),
        (SimdOp.Xor, "xor"),
        (SimdOp.ShiftLeft, "shift_left"),
        (SimdOp.ShiftRight, "shift_right"),
        (SimdOp.Negate, "negate"),
        (SimdOp.Not, "not"),
        (SimdOp.Equal, "equal"),
        (SimdOp.NotEqual, "not_equal"),
        (SimdOp.Less, "less"),
        (SimdOp.LessEqual, "less_equal"),
        (SimdOp.Greater, "greater"),
        (SimdOp.GreaterEqual, "greater_equal"),
        (SimdOp.Select, "select"),
        (SimdOp.Minimum, "minimum"),
        (SimdOp.Maximum, "maximum"),
        (SimdOp.Abs, "abs"),
        (SimdOp.RotateLeft, "rotate_left"),
        (SimdOp.RotateRight, "rotate_right"),
        (SimdOp.SquareRoot, "square_root"),
        (SimdOp.Floor, "floor"),
        (SimdOp.Ceiling, "ceiling"),
        (SimdOp.Sum, "sum"),
        (SimdOp.ReduceMinimum, "reduce_minimum"),
        (SimdOp.ReduceMaximum, "reduce_maximum"),
        (SimdOp.Any, "any"),
        (SimdOp.All, "all"),
        (SimdOp.ToBits, "to_bits"),
        (SimdOp.Extract, "extract"),
        (SimdOp.Insert, "insert"),
        (SimdOp.Shuffle, "shuffle"),
        (SimdOp.Reverse, "reverse"),
        (SimdOp.InterleaveLow, "interleave_low"),
        (SimdOp.InterleaveHigh, "interleave_high"),
        (SimdOp.Load, "load"),
        (SimdOp.LoadAligned, "load_aligned"),
        (SimdOp.Store, "store"),
        (SimdOp.StoreAligned, "store_aligned"),
        (SimdOp.Convert, "convert"),
        (SimdOp.Reinterpret, "reinterpret"),
        (SimdOp.Lanes, "lanes"),
        (SimdOp.LaneBits, "lane_bits"),
        (SimdOp.IsSigned, "is_signed")
    ];
}

## The name after `__simd_` that calls `op`.
export simd_op_name(op: SimdOp): String {
    for (var entry in _simd_operations()) {
        var (candidate, name) = entry;
        if (candidate == op) {
            return name;
        }
    }
    return "";
}

## How many arguments `op` takes.
export simd_op_arity(op: SimdOp): ulong {
    match (op) {
        Lanes, LaneBits, IsSigned => {
            return 0;
        }
        Splat, Negate, Not, Abs, SquareRoot, Floor, Ceiling, Sum, ReduceMinimum, ReduceMaximum, Any, All, ToBits, Reverse, Load, LoadAligned, Convert, Reinterpret => {
            return 1;
        }
        Insert, Select => {
            return 3;
        }
        else => {
            return 2;
        }
    }
}

## The type of the node, given the vector type `ty` `op` works on.
export simd_op_result(op: SimdOp, ty: TypeName): TypeName {
    match (op) {
        Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual => {
            var mask = ty.copy();
            if (mask.sub_types.count > 0) {
                mask.sub_types[0] = TypeName.boolean();
            }
            return mask;
        }
        Extract, Sum, ReduceMinimum, ReduceMaximum => {
            if (ty.sub_types.count > 0) {
                return ty.sub_types[0].copy();
            }
            return TypeName.named("int");
        }
        Any, All, IsSigned => {
            return TypeName.boolean();
        }
        ToBits => {
            return TypeName.named("ulong");
        }
        Store, StoreAligned => {
            return TypeName.named("void");
        }
        Lanes, LaneBits => {
            return TypeName.named("int");
        }
        else => {
            return ty.copy();
        }
    }
}

## How lanes of a type compute.
enum _Lane {
    Signed,
    Unsigned,
    Float,
}

## The lane kind of lane type `name`.
_lane_of(state: PassState, name: String): _Lane {
    if (sema.is_float_type(name)) {
        return _Lane.Float;
    }
    if (sema.is_unsigned_int_type(state, name) or name == "bool") {
        return _Lane.Unsigned;
    }
    return _Lane.Signed;
}

## A vector type's lane kind, lane count and LLVM type.
struct _Shape {
    var lane: _Lane;
    var count: uint;
    var ty: llvm.Type;

    construct(lane: _Lane, count: uint, ty: llvm.Type) {
        this.lane = lane;
        this.count = count;
        this.ty = ty;
    }
}

## The bit width of an integer type, or of a vector's integer lanes.
_scalar_bits(ty: llvm.Type): uint {
    if (ty.kind() == llvm.TypeKind.Vector) {
        return _scalar_bits(ty.element_type());
    }
    match (ty.kind()) {
        Integer => {
            return ty.int_width();
        }
        Float => {
            return 32;
        }
        Double => {
            return 64;
        }
        else => {
            return 0;
        }
    }
}

extend Generator {
    ## The shape of vector type `ty` (not `simd_shape`: the free
    ## `simd_shape` of types.pep parses the name).
    simd_vector_shape(ty: TypeName): Result<_Shape> {
        var name = ty.to_string();
        var parsed = simd_shape(name);
        if (!parsed.is_value()) {
            return fail<_Shape>($"'{name}' is not a vector type");
        }
        var (lane, count) = parsed.value();
        var vector = types.get(name);
        if (!vector.is_value() or vector.value().kind() != llvm.TypeKind.Vector) {
            return fail<_Shape>($"unknown type name '{name}'");
        }
        return Result<_Shape>.ok(_Shape(_lane_of(state, lane), count, vector.value()));
    }

    ## A vector argument.
    simd_vector(arg: Expression): Result<llvm.Value> {
        var value = codegen_expr(arg)?;
        if (value.value_type().kind() != llvm.TypeKind.Vector) {
            return fail<llvm.Value>($"expected a vector, have '{value.value_type().to_string()}'");
        }
        return Result<llvm.Value>.ok(value);
    }

    ## A scalar argument as an integer of type `ty` (an index or count).
    simd_integer(arg: Expression, ty: llvm.Type): Result<llvm.Value> {
        var value = codegen_expr(arg)?;
        if (value.value_type().kind() != llvm.TypeKind.Integer) {
            return fail<llvm.Value>($"expected an integer, have '{value.value_type().to_string()}'");
        }
        if (value.value_type().same(ty)) {
            return Result<llvm.Value>.ok(value);
        }
        # Signed, as `LLVMBuildIntCast` casts.
        return Result<llvm.Value>.ok(simd_int_cast(value, ty, true, "simd.cast"));
    }

    ## `CreateIntCast`: `value` unchanged when it already has type `ty`, else
    ## truncated or extended (by sign when `signed`).
    simd_int_cast(value: llvm.Value, ty: llvm.Type, signed: bool, name: String): llvm.Value {
        if (value.value_type().same(ty)) {
            return value;
        }
        var from = _scalar_bits(value.value_type());
        var to = _scalar_bits(ty);
        if (from > to) {
            return builder.truncate(value, ty, name);
        }
        if (from == to) {
            return builder.bit_cast(value, ty, name);
        }
        if (signed) {
            return builder.sign_extend(value, ty, name);
        }
        return builder.zero_extend(value, ty, name);
    }

    ## `CreateFPCast`: `value` unchanged when it already has type `ty`, else
    ## narrowed or widened.
    simd_float_cast(value: llvm.Value, ty: llvm.Type, name: String): llvm.Value {
        if (value.value_type().same(ty)) {
            return value;
        }
        var from = _scalar_bits(value.value_type());
        var to = _scalar_bits(ty);
        if (from > to) {
            return builder.float_truncate(value, ty, name);
        }
        if (from == to) {
            return builder.bit_cast(value, ty, name);
        }
        return builder.float_extend(value, ty, name);
    }

    ## `value` in every lane of `ty`.
    simd_splat(value: llvm.Value, ty: llvm.Type): llvm.Value {
        var i32 = context.int32_type();
        var one = ty.undef();
        var first = builder.insert_element(one, value, i32.zero(), "simd.one");
        var zeros = i32.vector_type(ty.vector_size()).zero();
        return builder.shuffle_vector(first, one, zeros, "simd.splat");
    }

    ## A call of the overloaded LLVM intrinsic `name` on `overloads`.
    simd_intrinsic(name: String, overloads: llvm.Type[], args: llvm.Value[]): Result<llvm.Value> {
        var found = ir.intrinsic(name, overloads);
        if (!found.is_value()) {
            return fail<llvm.Value>($"unknown LLVM intrinsic '{name}'");
        }
        var function = found.value();
        var call = builder.call(function.global_type(), function, args, "simd.call");
        if (call.value_type().kind() == llvm.TypeKind.Void) {
            return fail<llvm.Value>($"'{name}' returns no value");
        }
        return Result<llvm.Value>.ok(call);
    }

    ## A constant `<count x i32>` lane-index vector.
    simd_indices(indices: uint[]): llvm.Value {
        var i32 = context.int32_type();
        var lanes = Array<llvm.Value>();
        for (var i in indices) {
            lanes.append(i32.const_uint(i as ulong));
        }
        return llvm.const_vector(lanes);
    }

    ## `Expression.Simd`: operation `op` on vector type `ty` (see `SimdOp`).
    codegen_simd(op: SimdOp, ty: TypeName, args: Array<Expression>): Result<llvm.Value> {
        var i32 = context.int32_type();
        var i64 = context.int64_type();
        match (op) {
            Lanes, LaneBits => {
                var shape = simd_vector_shape(ty)?;
                var value = op == SimdOp.Lanes ? shape.count : simd_lane_size(shape.ty) * 8;
                return Result<llvm.Value>.ok(i32.const_uint(value as ulong));
            }
            IsSigned => {
                var shape = simd_vector_shape(ty)?;
                ulong signed = shape.lane == _Lane.Signed ? 1 : 0;
                return Result<llvm.Value>.ok(context.int1_type().const_uint(signed));
            }
            Splat => {
                var shape = simd_vector_shape(ty)?;
                var value = codegen_expr(args[0])?;
                return Result<llvm.Value>.ok(simd_splat(value, shape.ty));
            }
            Load, LoadAligned => {
                var shape = simd_vector_shape(ty)?;
                var pointer = codegen_expr(args[0])?;
                var load = builder.load(shape.ty, pointer, "simd.load");
                var align = op == SimdOp.LoadAligned ? simd_size(shape.ty) : simd_lane_size(shape.ty);
                load.set_alignment(align);
                return Result<llvm.Value>.ok(load);
            }
            Store, StoreAligned => {
                var shape = simd_vector_shape(ty)?;
                var pointer = codegen_expr(args[0])?;
                var value = simd_vector(args[1])?;
                var store = builder.store(value, pointer);
                var align = op == SimdOp.StoreAligned ? simd_size(shape.ty) : simd_lane_size(shape.ty);
                store.set_alignment(align);
                return Result<llvm.Value>.ok(i32.zero());
            }
            Extract => {
                var index = simd_integer(args[1], i64)?;
                var vector = simd_vector(args[0])?;
                return Result<llvm.Value>.ok(builder.extract_element(vector, index, "simd.lane"));
            }
            Insert => {
                var vector = simd_vector(args[0])?;
                var index = simd_integer(args[1], i64)?;
                var value = codegen_expr(args[2])?;
                return Result<llvm.Value>.ok(builder.insert_element(vector, value, index, "simd.set"));
            }
            Negate, Not, Abs, SquareRoot, Floor, Ceiling => {
                return simd_unary(op, ty, args);
            }
            Add, Subtract, Multiply, Divide, Remainder, And, Or, Xor, Minimum, Maximum => {
                return simd_binary(op, ty, args);
            }
            ShiftLeft, ShiftRight, RotateLeft, RotateRight => {
                var shape = simd_vector_shape(ty)?;
                if (shape.lane == _Lane.Float) {
                    return fail<llvm.Value>($"'{simd_op_name(op)}' needs integer lanes, not '{ty.to_string()}'");
                }
                var v = simd_vector(args[0])?;
                var lane = shape.ty.element_type();
                var count = simd_integer(args[1], lane)?;
                var counts = simd_splat(count, shape.ty);
                var overload = [shape.ty];
                match (op) {
                    ShiftLeft => {
                        return Result<llvm.Value>.ok(builder.shift_left(v, counts, "simd.shl"));
                    }
                    ShiftRight => {
                        if (shape.lane == _Lane.Signed) {
                            return Result<llvm.Value>.ok(builder.arithmetic_shift_right(v, counts, "simd.shr"));
                        }
                        return Result<llvm.Value>.ok(builder.logical_shift_right(v, counts, "simd.shr"));
                    }
                    RotateLeft => {
                        return simd_intrinsic("llvm.fshl", overload, [v, v, counts]);
                    }
                    else => {
                        return simd_intrinsic("llvm.fshr", overload, [v, v, counts]);
                    }
                }
            }
            Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual => {
                return simd_compare(op, ty, args);
            }
            Select => {
                var mask = simd_vector(args[0])?;
                var if_true = simd_vector(args[1])?;
                var if_false = simd_vector(args[2])?;
                return Result<llvm.Value>.ok(builder.select(mask, if_true, if_false, "simd.select"));
            }
            Sum, ReduceMinimum, ReduceMaximum => {
                return simd_reduce(op, ty, args);
            }
            Any, All => {
                var shape = simd_vector_shape(ty)?;
                var v = simd_vector(args[0])?;
                var name = op == SimdOp.Any ? "llvm.vector.reduce.or" : "llvm.vector.reduce.and";
                return simd_intrinsic(name, [shape.ty], [v]);
            }
            ToBits => {
                var shape = simd_vector_shape(ty)?;
                var v = simd_vector(args[0])?;
                if (shape.count == 0) {
                    return fail<llvm.Value>("a vector has at least one lane");
                }
                var bits = context.int_type(shape.count);
                var packed = builder.bit_cast(v, bits, "simd.bits");
                if (shape.count < 64) {
                    return Result<llvm.Value>.ok(builder.zero_extend(packed, i64, "simd.bits64"));
                }
                return Result<llvm.Value>.ok(packed);
            }
            Reverse, InterleaveLow, InterleaveHigh, Shuffle => {
                return simd_permute(op, ty, args);
            }
            else => {
                # `Convert` and `Reinterpret`.
                return simd_convert(op, ty, args);
            }
        }
    }

    ## `Negate`, `Not`, `Abs`, `SquareRoot`, `Floor` and `Ceiling`.
    simd_unary(op: SimdOp, ty: TypeName, args: Array<Expression>): Result<llvm.Value> {
        var shape = simd_vector_shape(ty)?;
        var v = simd_vector(args[0])?;
        var float = shape.lane == _Lane.Float;
        var overload = [shape.ty];
        if (op == SimdOp.Negate and !float) {
            return Result<llvm.Value>.ok(builder.negate(v, "simd.neg"));
        }
        if (op == SimdOp.Negate and float) {
            return Result<llvm.Value>.ok(builder.float_negate(v, "simd.neg"));
        }
        if (op == SimdOp.Not and !float) {
            return Result<llvm.Value>.ok(builder.bit_not(v, "simd.not"));
        }
        if (op == SimdOp.Abs and !float) {
            var wrap = context.int1_type().zero();
            return simd_intrinsic("llvm.abs", overload, [v, wrap]);
        }
        if (op == SimdOp.Abs and float) {
            return simd_intrinsic("llvm.fabs", overload, [v]);
        }
        if (op == SimdOp.SquareRoot and float) {
            return simd_intrinsic("llvm.sqrt", overload, [v]);
        }
        if (op == SimdOp.Floor and float) {
            return simd_intrinsic("llvm.floor", overload, [v]);
        }
        if (op == SimdOp.Ceiling and float) {
            return simd_intrinsic("llvm.ceil", overload, [v]);
        }
        var needed = float ? "integer" : "float";
        return fail<llvm.Value>($"'{simd_op_name(op)}' needs {needed} lanes, not '{ty.to_string()}'");
    }

    ## The lane-wise binary operations: arithmetic, bitwise, minimum and
    ## maximum.
    simd_binary(op: SimdOp, ty: TypeName, args: Array<Expression>): Result<llvm.Value> {
        var shape = simd_vector_shape(ty)?;
        var l = simd_vector(args[0])?;
        var r = simd_vector(args[1])?;
        var lane = shape.lane;
        var float = lane == _Lane.Float;
        var signed = lane == _Lane.Signed;
        match (op) {
            Add => {
                return Result<llvm.Value>.ok(
                    float ? builder.float_add(l, r, "simd.add") : builder.add(l, r, "simd.add")
                );
            }
            Subtract => {
                return Result<llvm.Value>.ok(
                    float ? builder.float_sub(l, r, "simd.sub") : builder.sub(l, r, "simd.sub")
                );
            }
            Multiply => {
                return Result<llvm.Value>.ok(
                    float ? builder.float_mul(l, r, "simd.mul") : builder.mul(l, r, "simd.mul")
                );
            }
            Divide => {
                if (float) {
                    return Result<llvm.Value>.ok(builder.float_divide(l, r, "simd.div"));
                }
                if (signed) {
                    return Result<llvm.Value>.ok(builder.signed_divide(l, r, "simd.div"));
                }
                return Result<llvm.Value>.ok(builder.unsigned_divide(l, r, "simd.div"));
            }
            Remainder => {
                if (float) {
                    return Result<llvm.Value>.ok(builder.float_remainder(l, r, "simd.rem"));
                }
                if (signed) {
                    return Result<llvm.Value>.ok(builder.signed_remainder(l, r, "simd.rem"));
                }
                return Result<llvm.Value>.ok(builder.unsigned_remainder(l, r, "simd.rem"));
            }
            And, Or, Xor => {
                if (float) {
                    return fail<llvm.Value>($"'{simd_op_name(op)}' needs integer lanes, not '{ty.to_string()}'");
                }
                if (op == SimdOp.And) {
                    return Result<llvm.Value>.ok(builder.bit_and(l, r, "simd.and"));
                }
                if (op == SimdOp.Or) {
                    return Result<llvm.Value>.ok(builder.bit_or(l, r, "simd.or"));
                }
                return Result<llvm.Value>.ok(builder.bit_xor(l, r, "simd.xor"));
            }
            else => {
                String name;
                if (op == SimdOp.Minimum) {
                    name = float ? "llvm.minnum" : (signed ? "llvm.smin" : "llvm.umin");
                } else {
                    name = float ? "llvm.maxnum" : (signed ? "llvm.smax" : "llvm.umax");
                }
                return simd_intrinsic(name, [shape.ty], [l, r]);
            }
        }
    }

    ## The lane-wise comparisons: a mask of `i1` lanes.
    simd_compare(op: SimdOp, ty: TypeName, args: Array<Expression>): Result<llvm.Value> {
        var shape = simd_vector_shape(ty)?;
        var l = simd_vector(args[0])?;
        var r = simd_vector(args[1])?;
        if (shape.lane == _Lane.Float) {
            # Ordered, as scalar comparisons are, except `!=`, which is true
            # for NaN.
            llvm.RealPredicate predicate;
            match (op) {
                Equal => {
                    predicate = llvm.RealPredicate.OrderedEqual;
                }
                NotEqual => {
                    predicate = llvm.RealPredicate.UnorderedNotEqual;
                }
                Less => {
                    predicate = llvm.RealPredicate.OrderedLess;
                }
                LessEqual => {
                    predicate = llvm.RealPredicate.OrderedLessOrEqual;
                }
                Greater => {
                    predicate = llvm.RealPredicate.OrderedGreater;
                }
                else => {
                    predicate = llvm.RealPredicate.OrderedGreaterOrEqual;
                }
            }
            return Result<llvm.Value>.ok(builder.float_compare(predicate, l, r, "simd.cmp"));
        }
        var signed = shape.lane == _Lane.Signed;
        llvm.IntPredicate predicate;
        match (op) {
            Equal => {
                predicate = llvm.IntPredicate.Equal;
            }
            NotEqual => {
                predicate = llvm.IntPredicate.NotEqual;
            }
            Less => {
                predicate = signed ? llvm.IntPredicate.SignedLess : llvm.IntPredicate.UnsignedLess;
            }
            LessEqual => {
                predicate = signed ? llvm.IntPredicate.SignedLessOrEqual : llvm.IntPredicate.UnsignedLessOrEqual;
            }
            Greater => {
                predicate = signed ? llvm.IntPredicate.SignedGreater : llvm.IntPredicate.UnsignedGreater;
            }
            else => {
                predicate = signed ? llvm.IntPredicate.SignedGreaterOrEqual : llvm.IntPredicate.UnsignedGreaterOrEqual;
            }
        }
        return Result<llvm.Value>.ok(builder.compare(predicate, l, r, "simd.cmp"));
    }

    ## `Sum`, `ReduceMinimum` and `ReduceMaximum`: one lane from all.
    simd_reduce(op: SimdOp, ty: TypeName, args: Array<Expression>): Result<llvm.Value> {
        var shape = simd_vector_shape(ty)?;
        var v = simd_vector(args[0])?;
        var overload = [shape.ty];
        var lane = shape.lane;
        if (op == SimdOp.Sum) {
            if (lane == _Lane.Float) {
                # In lane order from -0.0 (the identity of `+`), so the result
                # does not depend on the target.
                var start = shape.ty.element_type().const_real(-0.0);
                return simd_intrinsic("llvm.vector.reduce.fadd", overload, [start, v]);
            }
            return simd_intrinsic("llvm.vector.reduce.add", overload, [v]);
        }
        if (op == SimdOp.ReduceMinimum) {
            if (lane == _Lane.Float) {
                return simd_intrinsic("llvm.vector.reduce.fmin", overload, [v]);
            }
            if (lane == _Lane.Signed) {
                return simd_intrinsic("llvm.vector.reduce.smin", overload, [v]);
            }
            return simd_intrinsic("llvm.vector.reduce.umin", overload, [v]);
        }
        if (lane == _Lane.Float) {
            return simd_intrinsic("llvm.vector.reduce.fmax", overload, [v]);
        }
        if (lane == _Lane.Signed) {
            return simd_intrinsic("llvm.vector.reduce.smax", overload, [v]);
        }
        return simd_intrinsic("llvm.vector.reduce.umax", overload, [v]);
    }

    ## `Reverse`, `InterleaveLow`, `InterleaveHigh` and `Shuffle`: lanes
    ## rearranged.
    simd_permute(op: SimdOp, ty: TypeName, args: Array<Expression>): Result<llvm.Value> {
        var shape = simd_vector_shape(ty)?;
        var n = shape.count;
        var a = simd_vector(args[0])?;
        if (op == SimdOp.Reverse) {
            var reversed = Array<uint>();
            for (var k in 0..n) {
                reversed.append(n - 1 - k);
            }
            var mask = simd_indices(reversed);
            return Result<llvm.Value>.ok(builder.shuffle_vector(a, a, mask, "simd.reverse"));
        }
        if (op == SimdOp.InterleaveLow or op == SimdOp.InterleaveHigh) {
            var other = simd_vector(args[1])?;
            uint base = op == SimdOp.InterleaveLow ? 0 : n / 2;
            var picks = Array<uint>();
            for (var i in 0..n) {
                picks.append(base + i / 2 + (i % 2) * n);
            }
            var mask = simd_indices(picks);
            return Result<llvm.Value>.ok(builder.shuffle_vector(a, other, mask, "simd.interleave"));
        }
        # Lane `i` is `a[indices[i] % n]`: always in range. With constant
        # indices LLVM folds the extracts and inserts into one
        # `shufflevector`.
        var indices = simd_vector(args[1])?;
        var i64 = context.int64_type();
        var wrap = i64.const_uint(n as ulong - 1);
        var result = shape.ty.undef();
        for (var i in 0..n) {
            var at = i64.const_uint(i as ulong);
            var index = builder.extract_element(indices, at, "simd.index");
            index = simd_int_cast(index, i64, false, "simd.index64");
            index = builder.bit_and(index, wrap, "simd.wrap");
            var lane = builder.extract_element(a, index, "simd.pick");
            result = builder.insert_element(result, lane, at, "simd.place");
        }
        return Result<llvm.Value>.ok(result);
    }

    ## `Convert` (lane by lane, by value) and `Reinterpret` (the same bits).
    simd_convert(op: SimdOp, ty: TypeName, args: Array<Expression>): Result<llvm.Value> {
        var target = simd_vector_shape(ty)?;
        var sema_type = value_sema_type(args[0]);
        var source_ty = sema_type.is_value() ? sema_type.value() : "";
        var source_shape = simd_shape(source_ty);
        var v = simd_vector(args[0])?;
        if (op == SimdOp.Reinterpret) {
            if (simd_size(v.value_type()) != simd_size(target.ty)) {
                return fail<llvm.Value>($"cannot reinterpret '{source_ty}' as '{ty.to_string()}': their sizes differ");
            }
            return Result<llvm.Value>.ok(builder.bit_cast(v, target.ty, "simd.reinterpret"));
        }
        if (v.value_type().vector_size() != target.count) {
            return fail<llvm.Value>($"cannot convert '{source_ty}' to '{ty.to_string()}': their lane counts differ");
        }
        var from = _Lane.Signed;
        if (source_shape.is_value()) {
            var (lane, _) = source_shape.value();
            from = _lane_of(state, lane);
        }
        var to = target.lane;
        if (from == _Lane.Float and to == _Lane.Float) {
            return Result<llvm.Value>.ok(simd_float_cast(v, target.ty, "simd.convert"));
        }
        if (from == _Lane.Float) {
            # Saturating: out-of-range lanes clamp and NaN is 0, where
            # `fptosi` would give poison.
            var name = to == _Lane.Signed ? "llvm.fptosi.sat" : "llvm.fptoui.sat";
            return simd_intrinsic(name, [target.ty, v.value_type()], [v]);
        }
        if (to == _Lane.Float) {
            if (from == _Lane.Signed) {
                return Result<llvm.Value>.ok(builder.signed_to_float(v, target.ty, "simd.convert"));
            }
            return Result<llvm.Value>.ok(builder.unsigned_to_float(v, target.ty, "simd.convert"));
        }
        return Result<llvm.Value>.ok(simd_int_cast(v, target.ty, from == _Lane.Signed, "simd.convert"));
    }

    ## Marks the methods of every struct holding a vector (`simd.Vector`,
    ## `simd.Mask`) `alwaysinline`, and at `-O0` inlines them: each wraps one
    ## or a few instructions, and a call per lane operation would make an
    ## unoptimized vector loop (the runtime's ASCII scan) slower than the
    ## scalar one it replaces. The optimizing pipelines inline them anyway.
    inline_vector_methods(): Result<void> {
        var prefixes = Array<String>();
        for (var entry in values) {
            var (name, fields) = entry;
            for (var field in fields) {
                if (simd_shape(field).is_value()) {
                    prefixes.append(name);
                    break;
                }
            }
        }
        if (prefixes.count == 0) {
            return Result<void>.ok();
        }
        var always = context.attribute("alwaysinline");
        var marked = false;
        for (var function in ir.functions()) {
            if (function.block_count() == 0) {
                continue;
            }
            var name = function.name();
            # Methods are `Name.method`, constructors `Name$1`.
            var member = false;
            for (var prefix in prefixes) {
                if (name.starts_with(prefix)) {
                    var rest = name.substr_bytes(prefix.size, name.size - prefix.size);
                    if (rest.starts_with(".") or rest.starts_with("$")) {
                        member = true;
                        break;
                    }
                }
            }
            if (member) {
                function.add_function_attribute(always);
                marked = true;
            }
        }
        if (marked and opt_level == 0) {
            var inlined = ir.run_passes("always-inline", machine);
            if (inlined.is_err()) {
                return fail<void>($"cannot inline vector methods: {inlined.error().message}");
            }
        }
        return Result<void>.ok();
    }

    ## The size of a vector type in bytes, as stored.
    simd_size(ty: llvm.Type): uint {
        return machine.store_size_of(ty) as uint;
    }

    ## The size of one lane in bytes: the alignment of an unaligned access.
    simd_lane_size(ty: llvm.Type): uint {
        var lane = ty.element_type();
        match (lane.kind()) {
            Integer => {
                return (lane.int_width() + 7) / 8;
            }
            Float => {
                return 4;
            }
            else => {
                return 8;
            }
        }
    }
}
