//! Per-type codegen operations: port of `source/Sema/Operations.{h,cpp}` +
//! `source/CodeGen/LLVM/OperatorGen.cpp` coerce semantics.

use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::values::{BasicValueEnum, IntValue, PointerValue};

/// Compute the result type of a mixed-type arithmetic operation.
///
/// Integer operands promote to at least 32 bits (port of `largestIntType`
/// in `OperatorGen.cpp:59-64`: `(bits > 32) ? Int64 : Int32`) — an i8 + u8
/// sum like 300 must not wrap in 8-bit arithmetic. C-style promotion also
/// governs signedness: an operand keeps its unsignedness only when it is as
/// wide as the promoted result, so `u32`/`u64` operands yield a `"u32"`/
/// `"u64"` result while narrower unsigned operands (`u8`, `byte`) promote to
/// signed int. The returned name is load-bearing — it selects udiv/urem/ushr
/// and ULT-family ops in `int_binary` and zext-vs-sext in `codegen_cast`.
/// Floats promote to the wider float; non-numeric operands keep the lhs type
/// (pointer arithmetic is handled by `apply_op`).
pub fn result_type(lhs: &str, rhs: &str) -> String {
    let numeric = |n: &str| {
        matches!(
            n,
            "bool"
                | "i1"
                | "i8"
                | "char"
                | "u8"
                | "byte"
                | "i32"
                | "int"
                | "u32"
                | "uint"
                | "i64"
                | "long"
                | "u64"
                | "ulong"
                | "f32"
                | "float"
                | "f64"
                | "double"
        )
    };
    if !numeric(lhs) || !numeric(rhs) {
        // Non-numeric operand: keep the lhs type.
        return lhs.to_string();
    }
    let width = |n: &str| -> u32 {
        match n {
            "bool" | "i1" => 1,
            "i8" | "char" | "u8" | "byte" => 8,
            "f64" | "double" | "i64" | "long" | "u64" | "ulong" => 64,
            _ => 32,
        }
    };
    let w = width(lhs).max(width(rhs));
    if is_float_type(lhs) || is_float_type(rhs) {
        return if w > 32 { "f64".to_string() } else { "f32".to_string() };
    }
    // C-style integer promotion: an operand keeps its unsignedness only when
    // it is as wide as the promoted result — u8/byte promote to signed int,
    // while u32/u64 stay unsigned. The name drives op selection (udiv/sdiv)
    // and cast signedness, so it must name the value actually produced.
    let promoted = if w > 32 { 64 } else { 32 };
    let keeps_unsigned = |n: &str| {
        matches!(n, "u8" | "byte" | "u32" | "uint" | "u64" | "ulong") && width(n) == promoted
    };
    let unsigned = keeps_unsigned(lhs) || keeps_unsigned(rhs);
    match (w > 32, unsigned) {
        (true, true) => "u64".to_string(),
        (true, false) => "i64".to_string(),
        (false, true) => "u32".to_string(),
        (false, false) => "i32".to_string(),
    }
}

pub fn is_float_type(name: &str) -> bool {
    matches!(name, "f32" | "float" | "f64" | "double")
}

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
                let unsigned = matches!(to, "u8" | "byte" | "u32" | "uint" | "u64" | "ulong");
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
                || matches!(from, "u8" | "byte" | "void" | "u32" | "uint" | "u64" | "ulong");
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
                let unsigned = matches!(from, "u8" | "byte" | "void" | "u32" | "uint" | "u64" | "ulong")
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
        "u32" | "uint" => context.i32_type(),
        "i64" | "long" | "u64" | "ulong" => context.i64_type(),
        _ => context.i32_type(),
    }
}

/// Signed/unsigned-aware integer binary op (port of `Operations.h:66-89`).
pub fn int_binary<'ctx>(
    _context: &'ctx Context,
    builder: &Builder<'ctx>,
    op: pepper_sema::model::BinaryOp,
    lhs: IntValue<'ctx>,
    rhs: IntValue<'ctx>,
    ty_name: &str,
) -> Option<IntValue<'ctx>> {
    use pepper_sema::model::BinaryOp::*;
    let unsigned = matches!(ty_name, "u8" | "byte" | "u32" | "uint" | "u64" | "ulong");
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
            // Integer pow via unrolled multiply loop (rhs small in tests);
            // fall back to shift for rhs <= 31.
            let (width, _) = (lhs.get_type().get_bit_width(), ());
            let rhs_const = rhs.get_zero_extended_constant();
            match rhs_const {
                Some(exp) if exp <= 31 => {
                    let mut acc = lhs.get_type().const_int(1, !unsigned);
                    for _ in 0..exp {
                        acc = builder.build_int_mul(acc, lhs, "powmul").ok()?;
                    }
                    acc
                }
                _ => {
                    let _ = width;
                    return None;
                }
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

/// Float comparison (returns i1).
pub fn float_compare<'ctx>(
    builder: &Builder<'ctx>,
    op: pepper_sema::model::BinaryOp,
    lhs: inkwell::values::FloatValue<'ctx>,
    rhs: inkwell::values::FloatValue<'ctx>,
) -> Option<IntValue<'ctx>> {
    use pepper_sema::model::BinaryOp::*;
    let pred = match op {
        Equal => inkwell::FloatPredicate::OEQ,
        NotEqual => inkwell::FloatPredicate::ONE,
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
        BasicValueEnum::FloatValue(v) => builder
            .build_float_compare(inkwell::FloatPredicate::ONE, v, v.get_type().const_zero(), "fbool")
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
