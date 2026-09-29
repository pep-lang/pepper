//! The usual arithmetic conversions, shared by sema (the type a `var`
//! infers from `a + b`) and codegen (the type the operation runs at).

/// Compute the result type of a mixed-type arithmetic operation.
///
/// Integer operands promote to at least 32 bits (port of `largestIntType`
/// in `OperatorGen.cpp:59-64`: `(bits > 32) ? Int64 : Int32`) — an i8 + u8
/// sum like 300 must not wrap in 8-bit arithmetic. C-style promotion also
/// governs signedness: an operand keeps its unsignedness only when it is as
/// wide as the promoted result, so `u32`/`u64` operands yield a `"u32"`/
/// `"u64"` result while narrower unsigned operands (`u8`, `u16`) promote to
/// signed int. The returned name is load-bearing — it selects udiv/urem/ushr
/// and ULT-family ops in codegen's `int_binary` and zext-vs-sext in `codegen_cast`.
/// Floats promote to the wider float; non-numeric operands keep the lhs type
/// (pointer arithmetic is handled by `apply_op`).
pub fn result_type(lhs: &str, rhs: &str) -> String {
    if !is_numeric_type(lhs) || !is_numeric_type(rhs) {
        // Non-numeric operand: keep the lhs type.
        return lhs.to_string();
    }
    let width = |n: &str| -> u32 {
        match n {
            "bool" | "i1" => 1,
            "i8" | "char" | "u8" | "byte" => 8,
            "i16" | "short" | "u16" | "ushort" => 16,
            "f64" | "double" | "i64" | "long" | "u64" | "ulong" => 64,
            _ => 32,
        }
    };
    let w = width(lhs).max(width(rhs));
    if is_float_type(lhs) || is_float_type(rhs) {
        return if w > 32 { "f64".to_string() } else { "f32".to_string() };
    }
    // C-style integer promotion: an operand keeps its unsignedness only when
    // it is as wide as the promoted result — u8/u16 promote to signed int,
    // while u32/u64 stay unsigned. The name drives op selection (udiv/sdiv)
    // and cast signedness, so it must name the value actually produced.
    let promoted = if w > 32 { 64 } else { 32 };
    let keeps_unsigned = |n: &str| is_unsigned_int_type(n) && width(n) == promoted;
    let unsigned = keeps_unsigned(lhs) || keeps_unsigned(rhs);
    match (w > 32, unsigned) {
        (true, true) => "u64".to_string(),
        (true, false) => "i64".to_string(),
        (false, true) => "u32".to_string(),
        (false, false) => "i32".to_string(),
    }
}

/// Whether a type name is a numeric primitive (bool, integer or float,
/// including the C-style aliases).
pub fn is_numeric_type(n: &str) -> bool {
    matches!(
        n,
        "bool"
            | "i1"
            | "i8"
            | "char"
            | "u8"
            | "byte"
            | "i16"
            | "short"
            | "u16"
            | "ushort"
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
}

/// Whether a type name is one of the unsigned integer primitives (or an
/// alias). Selects zext/udiv/urem/lshr/ULT and fptoui/uitofp.
pub fn is_unsigned_int_type(name: &str) -> bool {
    matches!(name, "u8" | "byte" | "u16" | "ushort" | "u32" | "uint" | "u64" | "ulong")
}

pub fn is_float_type(name: &str) -> bool {
    matches!(name, "f32" | "float" | "f64" | "double")
}

/// Type of the arithmetic or bitwise `lhs op rhs` on numeric operands: the
/// promoted type (a shift keeps its promoted left operand's type). `None`
/// when an operand is not numeric, which keeps the lhs type (pointer
/// arithmetic, operator overloads).
pub fn binary_result(op: crate::model::BinaryOp, lhs: &str, rhs: &str) -> Option<String> {
    use crate::model::BinaryOp::*;
    if !is_numeric_type(lhs) || !is_numeric_type(rhs) {
        return None;
    }
    Some(match op {
        LShift | RShift => result_type(lhs, lhs),
        _ => result_type(lhs, rhs),
    })
}
