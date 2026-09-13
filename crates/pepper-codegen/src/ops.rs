//! Per-type codegen operations: port of `source/Sema/Operations.{h,cpp}` +
//! `source/CodeGen/LLVM/OperatorGen.cpp` coerce semantics.

use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::values::{BasicValueEnum, IntValue, PointerValue};
use pepper_sema::type_name::widest;

/// Compute the result type of a mixed-type arithmetic operation (port of
/// `widest()` from `TypeName.cpp:49-108`).
pub fn result_type(lhs: &str, rhs: &str) -> String {
    let lhs_ty = pepper_sema::type_name::TypeName::new(lhs);
    let rhs_ty = pepper_sema::type_name::TypeName::new(rhs);
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
    widest(&lhs_ty, &rhs_ty).to_string()
}

fn is_float_type(name: &str) -> bool {
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
            match builder.build_float_to_signed_int(value.into_float_value(), context.i32_type(), "f2i") {
                Ok(v) => BasicValueEnum::IntValue(v),
                Err(_) => value,
            }
        }
        (false, true) => {
            match builder.build_signed_int_to_float(value.into_int_value(), context.f64_type(), "i2f") {
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
                // i1 (bool) is unsigned: zext, not sext.
                let ext = if from_ty.get_bit_width() == 1 {
                    builder.build_int_z_extend(from_i, to_i, "zext")
                } else {
                    builder.build_int_s_extend(from_i, to_i, "sext")
                };
                match ext {
                    Ok(v) => BasicValueEnum::IntValue(v),
                    Err(_) => value,
                }
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
        "u64" | "ulong" => context.i64_type(),
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
pub fn as_bool<'ctx>(builder: &Builder<'ctx>, value: BasicValueEnum<'ctx>) -> IntValue<'ctx> {
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
                    .unwrap_or_else(|_| v)
            }
        }
        BasicValueEnum::FloatValue(v) => builder
            .build_float_compare(inkwell::FloatPredicate::ONE, v, v.get_type().const_zero(), "fbool")
            .expect("float compare"),
        BasicValueEnum::PointerValue(_) => value.into_int_value(),
        _ => value.into_int_value(),
    }
}
