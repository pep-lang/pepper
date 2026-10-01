//! Per-type codegen operations: port of `source/Sema/Operations.{h,cpp}` +
//! `source/CodeGen/LLVM/OperatorGen.cpp` coerce semantics.

use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::values::{BasicValueEnum, IntValue, PointerValue};

pub use pepper_sema::arithmetic::{is_float_type, is_numeric_type, is_unsigned_int_type, result_type};

/// Coerce a value to the target integer/float type name (port of the coerce
/// helper in `OperatorGen.cpp`).
pub fn coerce<'ctx>(
    context: &'ctx Context,
    builder: &Builder<'ctx>,
    value: BasicValueEnum<'ctx>,
    from: &str,
    to: &str,
) -> BasicValueEnum<'ctx> {
    if from == to {
        return value;
    }
    // An enum converts as the integer type it is stored as (`Wide: long`
    // is an i64), never as the `int` an unknown name would default to.
    let (from, to) = (&*pepper_sema::enums::stored_as(from), &*pepper_sema::enums::stored_as(to));
    let from_f = is_float_type(from);
    let to_f = is_float_type(to);
    match (from_f, to_f) {
        (true, true) => {
            let to64 = matches!(to, "f64" | "double");
            let from64 = matches!(from, "f64" | "double");
            if to64 && !from64 {
                match builder.build_float_cast(value.into_float_value(), context.f64_type(), "fcast") {
                    Ok(v) => BasicValueEnum::FloatValue(v),
                    Err(_) => value,
                }
            } else if !to64 && from64 {
                match builder.build_float_cast(value.into_float_value(), context.f32_type(), "fcast") {
                    Ok(v) => BasicValueEnum::FloatValue(v),
                    Err(_) => value,
                }
            } else {
                value
            }
        }
        (true, false) => {
            // C 6.3.1.4: float→int truncates toward zero into the *target*
            // width; unsigned targets use fptoui (fptosi is poison above the
            // signed range), bool compares != 0.
            if to == "bool" || to == "i1" {
                BasicValueEnum::IntValue(as_bool(context, builder, value))
            } else {
                let target = int_type_of_name(context, to);
                let unsigned = is_unsigned_int_type(to);
                let v = if unsigned {
                    builder.build_float_to_unsigned_int(value.into_float_value(), target, "f2i")
                } else {
                    builder.build_float_to_signed_int(value.into_float_value(), target, "f2i")
                };
                match v {
                    Ok(v) => BasicValueEnum::IntValue(v),
                    Err(_) => value,
                }
            }
        }
        (false, true) => {
            // C 6.3.1.4: int→float converts into the *target* float width;
            // unsigned and 1-bit sources use uitofp (`u8 200 as float` must
            // be 200.0, not -56.0).
            let from_i = match value {
                BasicValueEnum::IntValue(v) => v,
                _ => return value,
            };
            let target = if matches!(to, "f64" | "double") {
                context.f64_type()
            } else {
                context.f32_type()
            };
            let unsigned = from_i.get_type().get_bit_width() == 1
                || is_unsigned_int_type(from) || from == "void";
            let v = if unsigned {
                builder.build_unsigned_int_to_float(from_i, target, "i2f")
            } else {
                builder.build_signed_int_to_float(from_i, target, "i2f")
            };
            match v {
                Ok(v) => BasicValueEnum::FloatValue(v),
                Err(_) => value,
            }
        }
        (false, false) => {
            let from_i = match value {
                BasicValueEnum::IntValue(v) => v,
                _ => return value,
            };
            let from_ty = from_i.get_type();
            let to_i = int_type_of_name(context, to);
            let to_ty = to_i;
            if from_ty.get_bit_width() == to_ty.get_bit_width() {
                value
            } else if from_ty.get_bit_width() < to_ty.get_bit_width() {
                // i1 (bool) and unsigned sources widen with zext, not sext —
                // `u8 b = 200` must stay 200, not become -56. A void* byte
                // load is an unsigned char in C, so "void" extends too.
                let unsigned = is_unsigned_int_type(from) || from == "void"
                    || from_ty.get_bit_width() == 1;
                let ext = if unsigned {
                    builder.build_int_z_extend(from_i, to_i, "zext")
                } else {
                    builder.build_int_s_extend(from_i, to_i, "sext")
                };
                match ext {
                    Ok(v) => BasicValueEnum::IntValue(v),
                    Err(_) => value,
                }
            } else if to_ty.get_bit_width() == 1 {
                // C 6.3.1.4: conversion to _Bool is a nonzero test, not a
                // low-bit truncation (`bool b; b += 2` must be true).
                BasicValueEnum::IntValue(as_bool(context, builder, value))
            } else {
                match builder.build_int_truncate(from_i, to_i, "trunc") {
                    Ok(v) => BasicValueEnum::IntValue(v),
                    Err(_) => value,
                }
            }
        }
    }
}

fn int_type_of_name<'ctx>(context: &'ctx Context, name: &str) -> inkwell::types::IntType<'ctx> {
    match name {
        "bool" | "i1" => context.bool_type(),
        "i8" | "char" | "u8" | "byte" => context.i8_type(),
        "i16" | "short" | "u16" | "ushort" => context.i16_type(),
        "u32" | "uint" => context.i32_type(),
        "i64" | "long" | "u64" | "ulong" => context.i64_type(),
        _ => context.i32_type(),
    }
}

/// Signed/unsigned-aware integer binary op (port of `Operations.h:66-89`).
pub fn int_binary<'ctx>(
    context: &'ctx Context,
    builder: &Builder<'ctx>,
    op: pepper_sema::model::BinaryOp,
    lhs: IntValue<'ctx>,
    rhs: IntValue<'ctx>,
    ty_name: &str,
) -> Option<IntValue<'ctx>> {
    use pepper_sema::model::BinaryOp::*;
    let unsigned = is_unsigned_int_type(ty_name);
    let v = match op {
        Add => builder.build_int_add(lhs, rhs, "add").ok()?,
        Sub => builder.build_int_sub(lhs, rhs, "sub").ok()?,
        Mul => builder.build_int_mul(lhs, rhs, "mul").ok()?,
        Div => {
            if unsigned {
                builder.build_int_unsigned_div(lhs, rhs, "udiv").ok()?
            } else {
                builder.build_int_signed_div(lhs, rhs, "sdiv").ok()?
            }
        }
        Mod => {
            if unsigned {
                builder.build_int_unsigned_rem(lhs, rhs, "urem").ok()?
            } else {
                builder.build_int_signed_rem(lhs, rhs, "srem").ok()?
            }
        }
        Pow => {
            // A small constant exponent unrolls to multiplies; anything else
            // runs exponentiation by squaring.
            match rhs.get_zero_extended_constant() {
                Some(exp) if exp <= 31 && (unsigned || rhs.get_sign_extended_constant().is_some_and(|e| e >= 0)) => {
                    let mut acc = lhs.get_type().const_int(1, !unsigned);
                    for _ in 0..exp {
                        acc = builder.build_int_mul(acc, lhs, "powmul").ok()?;
                    }
                    acc
                }
                _ => int_pow(context, builder, lhs, rhs, unsigned)?,
            }
        }
        LShift => builder.build_left_shift(lhs, rhs, "shl").ok()?,
        RShift => builder.build_right_shift(lhs, rhs, !unsigned, "shr").ok()?,
        BitAnd | LogicalAnd => builder.build_and(lhs, rhs, "and").ok()?,
        BitOr | LogicalOr => builder.build_or(lhs, rhs, "or").ok()?,
        BitXor => builder.build_xor(lhs, rhs, "xor").ok()?,
        Equal => builder
            .build_int_compare(inkwell::IntPredicate::EQ, lhs, rhs, "eq")
            .ok()?,
        NotEqual => builder
            .build_int_compare(inkwell::IntPredicate::NE, lhs, rhs, "ne")
            .ok()?,
        Less => builder
            .build_int_compare(
                if unsigned { inkwell::IntPredicate::ULT } else { inkwell::IntPredicate::SLT },
                lhs,
                rhs,
                "lt",
            )
            .ok()?,
        LessEqual => builder
            .build_int_compare(
                if unsigned { inkwell::IntPredicate::ULE } else { inkwell::IntPredicate::SLE },
                lhs,
                rhs,
                "le",
            )
            .ok()?,
        Greater => builder
            .build_int_compare(
                if unsigned { inkwell::IntPredicate::UGT } else { inkwell::IntPredicate::SGT },
                lhs,
                rhs,
                "gt",
            )
            .ok()?,
        GreaterEqual => builder
            .build_int_compare(
                if unsigned { inkwell::IntPredicate::UGE } else { inkwell::IntPredicate::SGE },
                lhs,
                rhs,
                "ge",
            )
            .ok()?,
        _ => return None,
    };
    Some(v)
}

/// `base ** exp` for integers, by squaring. A negative signed exponent gives
/// the truncated real result: `1` for base 1, `±1` for base -1, else `0`.
fn int_pow<'ctx>(
    context: &'ctx Context,
    builder: &Builder<'ctx>,
    base: IntValue<'ctx>,
    exp: IntValue<'ctx>,
    unsigned: bool,
) -> Option<IntValue<'ctx>> {
    use inkwell::IntPredicate::*;
    let ty = base.get_type();
    let exp = if exp.get_type() == ty {
        exp
    } else if exp.get_type().get_bit_width() < ty.get_bit_width() {
        builder.build_int_s_extend(exp, ty, "powexp").ok()?
    } else {
        builder.build_int_truncate(exp, ty, "powexp").ok()?
    };
    let one = ty.const_int(1, false);
    let zero = ty.const_zero();
    let entry = builder.get_insert_block()?;
    let function = entry.get_parent()?;
    let header = context.append_basic_block(function, "pow.loop");
    let body = context.append_basic_block(function, "pow.body");
    let done = context.append_basic_block(function, "pow.done");
    builder.build_unconditional_branch(header).ok()?;

    builder.position_at_end(header);
    let acc = builder.build_phi(ty, "pow.acc").ok()?;
    let factor = builder.build_phi(ty, "pow.factor").ok()?;
    let remaining = builder.build_phi(ty, "pow.exp").ok()?;
    let acc_v = acc.as_basic_value().into_int_value();
    let factor_v = factor.as_basic_value().into_int_value();
    let remaining_v = remaining.as_basic_value().into_int_value();
    let more = builder
        .build_int_compare(if unsigned { NE } else { SGT }, remaining_v, zero, "pow.more")
        .ok()?;
    builder.build_conditional_branch(more, body, done).ok()?;

    builder.position_at_end(body);
    let low_bit = builder.build_and(remaining_v, one, "pow.bit").ok()?;
    let odd = builder.build_int_compare(NE, low_bit, zero, "pow.odd").ok()?;
    let multiplied = builder.build_int_mul(acc_v, factor_v, "pow.mul").ok()?;
    let next_acc = builder.build_select(odd, multiplied, acc_v, "pow.next").ok()?.into_int_value();
    let squared = builder.build_int_mul(factor_v, factor_v, "pow.square").ok()?;
    let halved = builder.build_right_shift(remaining_v, one, false, "pow.half").ok()?;
    let body_end = builder.get_insert_block()?;
    builder.build_unconditional_branch(header).ok()?;

    acc.add_incoming(&[(&one, entry), (&next_acc, body_end)]);
    factor.add_incoming(&[(&base, entry), (&squared, body_end)]);
    remaining.add_incoming(&[(&exp, entry), (&halved, body_end)]);

    builder.position_at_end(done);
    if unsigned {
        return Some(acc_v);
    }
    let negative = builder.build_int_compare(SLT, exp, zero, "pow.neg").ok()?;
    let exp_odd = builder.build_and(exp, one, "pow.expbit").ok()?;
    let exp_odd = builder.build_int_compare(NE, exp_odd, zero, "pow.expodd").ok()?;
    let minus_one = ty.const_all_ones();
    let base_is_one = builder.build_int_compare(EQ, base, one, "pow.one").ok()?;
    let base_is_minus_one = builder.build_int_compare(EQ, base, minus_one, "pow.minusone").ok()?;
    let sign = builder.build_select(exp_odd, minus_one, one, "pow.sign").ok()?.into_int_value();
    let fraction = builder.build_select(base_is_minus_one, sign, zero, "pow.frac").ok()?.into_int_value();
    let fraction = builder.build_select(base_is_one, one, fraction, "pow.frac").ok()?.into_int_value();
    Some(builder.build_select(negative, fraction, acc_v, "pow").ok()?.into_int_value())
}

/// Float binary op.
pub fn float_binary<'ctx>(
    builder: &Builder<'ctx>,
    op: pepper_sema::model::BinaryOp,
    lhs: inkwell::values::FloatValue<'ctx>,
    rhs: inkwell::values::FloatValue<'ctx>,
) -> Option<inkwell::values::FloatValue<'ctx>> {
    use pepper_sema::model::BinaryOp::*;
    let v = match op {
        Add => builder.build_float_add(lhs, rhs, "fadd").ok()?,
        Sub => builder.build_float_sub(lhs, rhs, "fsub").ok()?,
        Mul => builder.build_float_mul(lhs, rhs, "fmul").ok()?,
        Div => builder.build_float_div(lhs, rhs, "fdiv").ok()?,
        Mod => builder.build_float_rem(lhs, rhs, "frem").ok()?,
        _ => return None,
    };
    Some(v)
}

/// Float comparison (returns i1), as IEEE 754 and C define it: every
/// comparison but `!=` is ordered (false when either side is NaN), and `!=`,
/// the negation of `==`, is unordered (true when either side is NaN).
pub fn float_compare<'ctx>(
    builder: &Builder<'ctx>,
    op: pepper_sema::model::BinaryOp,
    lhs: inkwell::values::FloatValue<'ctx>,
    rhs: inkwell::values::FloatValue<'ctx>,
) -> Option<IntValue<'ctx>> {
    use pepper_sema::model::BinaryOp::*;
    let pred = match op {
        Equal => inkwell::FloatPredicate::OEQ,
        NotEqual => inkwell::FloatPredicate::UNE,
        Less => inkwell::FloatPredicate::OLT,
        LessEqual => inkwell::FloatPredicate::OLE,
        Greater => inkwell::FloatPredicate::OGT,
        GreaterEqual => inkwell::FloatPredicate::OGE,
        _ => return None,
    };
    builder.build_float_compare(pred, lhs, rhs, "fcmp").ok()
}

/// Pointer comparison (port of the pointer ops in `Operations.h`).
pub fn pointer_binary<'ctx>(
    context: &'ctx Context,
    builder: &Builder<'ctx>,
    op: pepper_sema::model::BinaryOp,
    lhs: PointerValue<'ctx>,
    rhs: PointerValue<'ctx>,
) -> Option<IntValue<'ctx>> {
    use pepper_sema::model::BinaryOp::*;
    let pred = match op {
        Equal | Identical => inkwell::IntPredicate::EQ,
        NotEqual => inkwell::IntPredicate::NE,
        _ => return None,
    };
    // Pointer compare via ptrtoint.
    let i64t = context.i64_type();
    let lhs_int = builder.build_ptr_to_int(lhs, i64t, "p2i").ok()?;
    let rhs_int = builder.build_ptr_to_int(rhs, i64t, "p2i").ok()?;
    builder.build_int_compare(pred, lhs_int, rhs_int, "ptrcmp").ok()
}

/// Int value as bool (non-zero) (port of `asBool`).
pub fn as_bool<'ctx>(context: &'ctx Context, builder: &Builder<'ctx>, value: BasicValueEnum<'ctx>) -> IntValue<'ctx> {
    match value {
        BasicValueEnum::IntValue(v) => {
            if v.get_type().get_bit_width() == 1 {
                v
            } else {
                builder
                    .build_int_compare(
                        inkwell::IntPredicate::NE,
                        v,
                        v.get_type().const_zero(),
                        "asbool",
                    )
                    .unwrap_or(v)
            }
        }
        // A float is true unless it equals zero, so NaN is true, as in C.
        BasicValueEnum::FloatValue(v) => builder
            .build_float_compare(inkwell::FloatPredicate::UNE, v, v.get_type().const_zero(), "fbool")
            .expect("float compare"),
        BasicValueEnum::PointerValue(p) => {
            // Pointer truthiness: ptr != null via ptrtoint compare.
            let i64t = context.i64_type();
            let zero = i64t.const_zero();
            let lhs_int = builder.build_ptr_to_int(p, i64t, "p2i").unwrap_or(zero);
            builder
                .build_int_compare(inkwell::IntPredicate::NE, lhs_int, zero, "ptrbool")
                .unwrap_or(lhs_int)
        }
        _ => value.into_int_value(),
    }
}
