## Per-type operations, as `crates/pepper-codegen/src/ops.rs` makes them:
## numeric conversions with C's rules, integer, float and pointer binary
## operators, and truth tests.

import llvm;
import compiler.sema;
import [BinaryOp] from compiler.sema;
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
import "refs";
import "simd";
import "traits";
import "types";

## Whether `ty` is `float` or `double`.
is_float_kind(ty: llvm.Type): bool {
    var kind = ty.kind();
    return kind == llvm.TypeKind.Float or kind == llvm.TypeKind.Double;
}

## Whether `name` names a 64-bit float.
_is_double(name: String): bool {
    return name == "f64" or name == "double";
}

extend Generator {
    ## The integer type a primitive's name is stored as; `int` for any
    ## other name.
    int_type_of_name(name: String): llvm.Type {
        match (name) {
            "bool", "i1" => {
                return context.int1_type();
            }
            "i8", "char", "u8", "byte" => {
                return context.int8_type();
            }
            "i16", "short", "u16", "ushort" => {
                return context.int16_type();
            }
            "i64", "long", "u64", "ulong" => {
                return context.int64_type();
            }
            else => {
                return context.int32_type();
            }
        }
    }

    ## `value` of sema type `from` converted to sema type `to`, with C's
    ## rules: an enum converts as the integer type it is stored as.
    coerce(value: llvm.Value, from_name: String, to_name: String): llvm.Value {
        if (from_name == to_name) {
            return value;
        }
        var from = sema.stored_as(state, from_name);
        var to = sema.stored_as(state, to_name);
        var from_float = sema.is_float_type(from);
        var to_float = sema.is_float_type(to);
        var kind = value.value_type().kind();
        if (from_float and to_float) {
            if (_is_double(to) and !_is_double(from)) {
                return builder.float_extend(value, context.double_type(), "fcast");
            }
            if (!_is_double(to) and _is_double(from)) {
                return builder.float_truncate(value, context.float_type(), "fcast");
            }
            return value;
        }
        if (from_float) {
            # Float to integer truncates toward zero into the target width;
            # unsigned targets use fptoui, bool compares with zero.
            if (to == "bool" or to == "i1") {
                return as_bool(value);
            }
            var target = int_type_of_name(to);
            if (sema.is_unsigned_int_type(state, to)) {
                return builder.float_to_unsigned(value, target, "f2i");
            }
            return builder.float_to_signed(value, target, "f2i");
        }
        if (to_float) {
            if (kind != llvm.TypeKind.Integer) {
                return value;
            }
            var target = _is_double(to) ? context.double_type() : context.float_type();
            bool unsigned = value.value_type().int_width() == 1
                or sema.is_unsigned_int_type(state, from)
                or from == "void";
            if (unsigned) {
                return builder.unsigned_to_float(value, target, "i2f");
            }
            return builder.signed_to_float(value, target, "i2f");
        }
        if (kind != llvm.TypeKind.Integer) {
            return value;
        }
        var from_width = value.value_type().int_width();
        var target = int_type_of_name(to);
        var to_width = target.int_width();
        if (from_width == to_width) {
            return value;
        }
        if (from_width < to_width) {
            # bool, unsigned and `void` (a C `unsigned char`) sources widen
            # with zeros.
            bool unsigned = sema.is_unsigned_int_type(state, from) or from == "void" or from_width == 1;
            if (unsigned) {
                return builder.zero_extend(value, target, "zext");
            }
            return builder.sign_extend(value, target, "sext");
        }
        if (to_width == 1) {
            # Conversion to bool is a nonzero test, not a truncation.
            return as_bool(value);
        }
        return builder.truncate(value, target, "trunc");
    }

    ## A signedness-aware integer binary operator, unchecked; none for an
    ## operator integers lack.
    int_binary(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value, ty_name: String): llvm.Value? {
        var unsigned = sema.is_unsigned_int_type(state, ty_name);
        llvm.Value v;
        match (op) {
            Add => {
                v = builder.add(lhs, rhs, "add");
            }
            Sub => {
                v = builder.sub(lhs, rhs, "sub");
            }
            Mul => {
                v = builder.mul(lhs, rhs, "mul");
            }
            Div => {
                v = unsigned ? builder.unsigned_divide(lhs, rhs, "udiv") : builder.signed_divide(lhs, rhs, "sdiv");
            }
            Mod => {
                v = unsigned ?
                    builder.unsigned_remainder(lhs, rhs, "urem") :
                    builder.signed_remainder(lhs, rhs, "srem");
            }
            Pow => {
                # A small constant exponent unrolls to multiplies; anything
                # else runs exponentiation by squaring.
                bool small = rhs.is_constant_int()
                    and rhs.zero_extended() <= 31
                    and (unsigned or rhs.sign_extended() >= 0);
                if (small) {
                    var acc = lhs.value_type().const_uint(1);
                    for (var _ in 0..rhs.zero_extended()) {
                        acc = builder.mul(acc, lhs, "powmul");
                    }
                    v = acc;
                } else {
                    v = int_pow(lhs, rhs, unsigned);
                }
            }
            LShift => {
                v = builder.shift_left(lhs, rhs, "shl");
            }
            RShift => {
                v = unsigned ?
                    builder.logical_shift_right(lhs, rhs, "shr") :
                    builder.arithmetic_shift_right(lhs, rhs, "shr");
            }
            BitAnd, LogicalAnd => {
                v = builder.bit_and(lhs, rhs, "and");
            }
            BitOr, LogicalOr => {
                v = builder.bit_or(lhs, rhs, "or");
            }
            BitXor => {
                v = builder.bit_xor(lhs, rhs, "xor");
            }
            Equal => {
                v = builder.compare(llvm.IntPredicate.Equal, lhs, rhs, "eq");
            }
            NotEqual => {
                v = builder.compare(llvm.IntPredicate.NotEqual, lhs, rhs, "ne");
            }
            Less => {
                v = builder.compare(
                    unsigned ? llvm.IntPredicate.UnsignedLess : llvm.IntPredicate.SignedLess, lhs, rhs, "lt"
                );
            }
            LessEqual => {
                v = builder.compare(
                    unsigned ? llvm.IntPredicate.UnsignedLessOrEqual : llvm.IntPredicate.SignedLessOrEqual,
                    lhs,
                    rhs,
                    "le"
                );
            }
            Greater => {
                v = builder.compare(
                    unsigned ? llvm.IntPredicate.UnsignedGreater : llvm.IntPredicate.SignedGreater, lhs, rhs, "gt"
                );
            }
            GreaterEqual => {
                v = builder.compare(
                    unsigned ? llvm.IntPredicate.UnsignedGreaterOrEqual : llvm.IntPredicate.SignedGreaterOrEqual,
                    lhs,
                    rhs,
                    "ge"
                );
            }
            else => {
                return Optional<llvm.Value>.Empty;
            }
        }
        return Optional<llvm.Value>.Value(v);
    }

    ## `base ** exp` for integers, by squaring. A negative signed exponent
    ## gives the truncated real result: `1` for base 1, `±1` for base -1,
    ## else `0`.
    int_pow(base: llvm.Value, exp: llvm.Value, unsigned: bool): llvm.Value {
        var ty = base.value_type();
        var power = exp;
        if (!exp.value_type().same(ty)) {
            if (exp.value_type().int_width() < ty.int_width()) {
                power = builder.sign_extend(exp, ty, "powexp");
            } else {
                power = builder.truncate(exp, ty, "powexp");
            }
        }
        var one = ty.const_uint(1);
        var zero = ty.zero();
        var entry = builder.insert_block();
        var function = entry.parent();
        var header = context.append_block(function, "pow.loop");
        var body = context.append_block(function, "pow.body");
        var done = context.append_block(function, "pow.done");
        builder.branch(header);

        builder.position_at_end(header);
        var acc = builder.phi(ty, "pow.acc");
        var factor = builder.phi(ty, "pow.factor");
        var remaining = builder.phi(ty, "pow.exp");
        var more = builder.compare(
            unsigned ? llvm.IntPredicate.NotEqual : llvm.IntPredicate.SignedGreater, remaining, zero, "pow.more"
        );
        builder.conditional_branch(more, body, done);

        builder.position_at_end(body);
        var low_bit = builder.bit_and(remaining, one, "pow.bit");
        var odd = builder.compare(llvm.IntPredicate.NotEqual, low_bit, zero, "pow.odd");
        var multiplied = builder.mul(acc, factor, "pow.mul");
        var next_acc = builder.select(odd, multiplied, acc, "pow.next");
        var squared = builder.mul(factor, factor, "pow.square");
        var halved = builder.logical_shift_right(remaining, one, "pow.half");
        var body_end = builder.insert_block();
        builder.branch(header);

        acc.add_incoming([one, next_acc], [entry, body_end]);
        factor.add_incoming([base, squared], [entry, body_end]);
        remaining.add_incoming([power, halved], [entry, body_end]);

        builder.position_at_end(done);
        if (unsigned) {
            return acc;
        }
        var negative = builder.compare(llvm.IntPredicate.SignedLess, power, zero, "pow.neg");
        var exp_bit = builder.bit_and(power, one, "pow.expbit");
        var exp_odd = builder.compare(llvm.IntPredicate.NotEqual, exp_bit, zero, "pow.expodd");
        var minus_one = ty.all_ones();
        var base_is_one = builder.compare(llvm.IntPredicate.Equal, base, one, "pow.one");
        var base_is_minus_one = builder.compare(llvm.IntPredicate.Equal, base, minus_one, "pow.minusone");
        var sign = builder.select(exp_odd, minus_one, one, "pow.sign");
        var fraction = builder.select(base_is_minus_one, sign, zero, "pow.frac");
        fraction = builder.select(base_is_one, one, fraction, "pow.frac");
        return builder.select(negative, fraction, acc, "pow");
    }

    ## A float arithmetic operator; none for any other.
    float_binary(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value): llvm.Value? {
        match (op) {
            Add => {
                return Optional<llvm.Value>.Value(builder.float_add(lhs, rhs, "fadd"));
            }
            Sub => {
                return Optional<llvm.Value>.Value(builder.float_sub(lhs, rhs, "fsub"));
            }
            Mul => {
                return Optional<llvm.Value>.Value(builder.float_mul(lhs, rhs, "fmul"));
            }
            Div => {
                return Optional<llvm.Value>.Value(builder.float_divide(lhs, rhs, "fdiv"));
            }
            Mod => {
                return Optional<llvm.Value>.Value(builder.float_remainder(lhs, rhs, "frem"));
            }
            else => {
                return Optional<llvm.Value>.Empty;
            }
        }
    }

    ## A float comparison, as IEEE 754 and C define it: every comparison but
    ## `!=` is ordered, and `!=` is unordered.
    float_compare(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value): llvm.Value? {
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
            GreaterEqual => {
                predicate = llvm.RealPredicate.OrderedGreaterOrEqual;
            }
            else => {
                return Optional<llvm.Value>.Empty;
            }
        }
        return Optional<llvm.Value>.Value(builder.float_compare(predicate, lhs, rhs, "fcmp"));
    }

    ## A pointer comparison, through `ptrtoint`; none for an operator
    ## pointers lack.
    pointer_binary(op: BinaryOp, lhs: llvm.Value, rhs: llvm.Value): llvm.Value? {
        llvm.IntPredicate predicate;
        match (op) {
            Equal, Identical => {
                predicate = llvm.IntPredicate.Equal;
            }
            NotEqual => {
                predicate = llvm.IntPredicate.NotEqual;
            }
            else => {
                return Optional<llvm.Value>.Empty;
            }
        }
        var i64 = context.int64_type();
        var lhs_int = builder.pointer_to_int(lhs, i64, "p2i");
        var rhs_int = builder.pointer_to_int(rhs, i64, "p2i");
        return Optional<llvm.Value>.Value(builder.compare(predicate, lhs_int, rhs_int, "ptrcmp"));
    }

    ## `value` as an `i1`: an integer or float is true unless zero (NaN is
    ## true), a pointer unless null.
    as_bool(value: llvm.Value): llvm.Value {
        var ty = value.value_type();
        var kind = ty.kind();
        if (kind == llvm.TypeKind.Integer) {
            if (ty.int_width() == 1) {
                return value;
            }
            return builder.compare(llvm.IntPredicate.NotEqual, value, ty.zero(), "asbool");
        }
        if (is_float_kind(ty)) {
            return builder.float_compare(llvm.RealPredicate.UnorderedNotEqual, value, ty.zero(), "fbool");
        }
        if (kind == llvm.TypeKind.Pointer) {
            var i64 = context.int64_type();
            var as_int = builder.pointer_to_int(value, i64, "p2i");
            return builder.compare(llvm.IntPredicate.NotEqual, as_int, i64.zero(), "ptrbool");
        }
        return value;
    }
}
