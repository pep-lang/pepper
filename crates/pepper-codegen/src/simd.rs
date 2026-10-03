//! SIMD vectors (#517): the built-in type `__simd<T, N>`, LLVM's `<N x T>`,
//! and the `__simd_<op><V>(args)` intrinsics (`Expression::Simd`) that the
//! runtime's `simd.Vector<T, N>` and `simd.Mask<N>` are written with.
//!
//! Each operation is one or a few LLVM instructions or vector intrinsics,
//! picked by the lane type: signed or unsigned integer, or float. Nothing
//! here checks a value: the runtime panics before an operation LLVM leaves
//! undefined (a zero divisor, a shift count of at least the lane width, a
//! lane index out of range), and the operations that would otherwise be
//! undefined are chosen so they are not (`llvm.fptosi.sat`, lane indices of
//! `shuffle` masked to the lane count).

use crate::CodeGenerator;
use inkwell::intrinsics::Intrinsic;
use inkwell::types::{BasicType, BasicTypeEnum, VectorType};
use inkwell::values::{BasicMetadataValueEnum, BasicValue, BasicValueEnum, IntValue, VectorValue};
use inkwell::{FloatPredicate, IntPredicate};
use pepper_sema::arithmetic::{is_float_type, is_unsigned_int_type};
use pepper_sema::model::{Expression, SimdOp};
use pepper_sema::type_name::TypeName;

/// The name of the built-in vector type: `__simd<T, N>`.
pub use pepper_sema::type_name::SIMD as SIMD_TYPE;

/// The lane type and lane count of `__simd<T, N>`, when `name` spells one.
pub fn shape(name: &str) -> Option<(String, u32)> {
    if !name.starts_with("__simd<") {
        return None;
    }
    let ty = pepper_sema::passes::gather_generics::parse_type_string(name);
    let [lane, count] = ty.sub_types.as_slice() else { return None };
    Some((lane.to_string(), count.name.parse().ok()?))
}

/// The LLVM type of `__simd<T, N>`: `<N x T>`, with `bool` lanes as `i1`.
pub fn vector_type<'ctx>(lane: BasicTypeEnum<'ctx>, count: u32) -> Option<VectorType<'ctx>> {
    match lane {
        BasicTypeEnum::IntType(t) => Some(t.vec_type(count)),
        BasicTypeEnum::FloatType(t) => Some(t.vec_type(count)),
        _ => None,
    }
}

/// How lanes of a type compute.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Lane {
    Signed,
    Unsigned,
    Float,
}

impl Lane {
    fn of(name: &str) -> Lane {
        if is_float_type(name) {
            Lane::Float
        } else if is_unsigned_int_type(name) || name == "bool" {
            Lane::Unsigned
        } else {
            Lane::Signed
        }
    }
}

/// A vector type's lane type name, lane kind, lane count and LLVM type.
struct Shape<'ctx> {
    lane: Lane,
    count: u32,
    ty: VectorType<'ctx>,
}

impl<'ctx> CodeGenerator<'ctx> {
    fn simd_shape(&self, ty: &TypeName) -> Result<Shape<'ctx>, String> {
        let name = ty.to_string();
        let (lane, count) = shape(&name).ok_or_else(|| format!("'{}' is not a vector type", name))?;
        let Some(BasicTypeEnum::VectorType(vector)) = self.types.get(&name) else {
            return Err(format!("unknown type name '{}'", name));
        };
        Ok(Shape { lane: Lane::of(&lane), count, ty: vector })
    }

    fn simd_vector(&mut self, arg: &Expression) -> Result<VectorValue<'ctx>, String> {
        match self.codegen_expr(arg)? {
            BasicValueEnum::VectorValue(v) => Ok(v),
            other => Err(format!("expected a vector, have '{}'", other.get_type())),
        }
    }

    /// A scalar argument as an integer of `width` bits (an index or count).
    fn simd_integer(&mut self, arg: &Expression, ty: inkwell::types::IntType<'ctx>) -> Result<IntValue<'ctx>, String> {
        match self.codegen_expr(arg)? {
            BasicValueEnum::IntValue(v) if v.get_type() == ty => Ok(v),
            BasicValueEnum::IntValue(v) => self.builder.build_int_cast(v, ty, "simd.cast").map_err(|e| e.to_string()),
            other => Err(format!("expected an integer, have '{}'", other.get_type())),
        }
    }

    /// `value` in every lane of `ty`.
    fn simd_splat(&self, value: BasicValueEnum<'ctx>, ty: VectorType<'ctx>) -> Result<VectorValue<'ctx>, String> {
        let i32 = self.context.i32_type();
        let one = ty.get_undef();
        let first = self.builder.build_insert_element(one, value, i32.const_zero(), "simd.one").map_err(|e| e.to_string())?;
        let zeros = i32.vec_type(ty.get_size()).const_zero();
        self.builder.build_shuffle_vector(first, one, zeros, "simd.splat").map_err(|e| e.to_string())
    }

    /// A call of the overloaded LLVM intrinsic `name` on `overloads`.
    fn simd_intrinsic(
        &self,
        name: &str,
        overloads: &[BasicTypeEnum<'ctx>],
        args: &[BasicMetadataValueEnum<'ctx>],
    ) -> Result<BasicValueEnum<'ctx>, String> {
        let intrinsic = Intrinsic::find(name).ok_or_else(|| format!("unknown LLVM intrinsic '{}'", name))?;
        let function = intrinsic
            .get_declaration(&self.module, overloads)
            .ok_or_else(|| format!("no overload of LLVM intrinsic '{}' for these types", name))?;
        let call = self.builder.build_call(function, args, "simd.call").map_err(|e| e.to_string())?;
        call.try_as_basic_value().basic().ok_or_else(|| format!("'{}' returns no value", name))
    }

    /// A constant `<count x i32>` lane-index vector.
    fn simd_indices(&self, indices: impl IntoIterator<Item = u32>) -> VectorValue<'ctx> {
        let i32 = self.context.i32_type();
        let lanes: Vec<IntValue<'ctx>> = indices.into_iter().map(|i| i32.const_int(i as u64, false)).collect();
        VectorType::const_vector(&lanes)
    }

    /// `Expression::Simd`: operation `op` on vector type `ty` (see
    /// `SimdOp`).
    pub(crate) fn codegen_simd(&mut self, op: SimdOp, ty: &TypeName, args: &[Expression]) -> Result<BasicValueEnum<'ctx>, String> {
        use SimdOp::*;
        let e = |e: inkwell::builder::BuilderError| e.to_string();
        let i32 = self.context.i32_type();
        let i64 = self.context.i64_type();
        match op {
            Lanes | LaneBits => {
                let shape = self.simd_shape(ty)?;
                let value = if op == Lanes { shape.count } else { self.simd_lane_size(shape.ty) * 8 };
                Ok(i32.const_int(value as u64, false).into())
            }
            IsSigned => {
                let shape = self.simd_shape(ty)?;
                Ok(self.context.bool_type().const_int((shape.lane == Lane::Signed) as u64, false).into())
            }
            Splat => {
                let shape = self.simd_shape(ty)?;
                let value = self.codegen_expr(&args[0])?;
                Ok(self.simd_splat(value, shape.ty)?.into())
            }
            Load | LoadAligned => {
                let shape = self.simd_shape(ty)?;
                let pointer = self.codegen_expr(&args[0])?.into_pointer_value();
                let load = self.builder.build_load(shape.ty, pointer, "simd.load").map_err(e)?;
                let align = if op == LoadAligned { self.simd_size(shape.ty) } else { self.simd_lane_size(shape.ty) };
                if let Some(instruction) = load.as_instruction_value() {
                    instruction.set_alignment(align).map_err(|e| e.to_string())?;
                }
                Ok(load)
            }
            Store | StoreAligned => {
                let shape = self.simd_shape(ty)?;
                let pointer = self.codegen_expr(&args[0])?.into_pointer_value();
                let value = self.simd_vector(&args[1])?;
                let store = self.builder.build_store(pointer, value).map_err(e)?;
                let align = if op == StoreAligned { self.simd_size(shape.ty) } else { self.simd_lane_size(shape.ty) };
                store.set_alignment(align).map_err(|e| e.to_string())?;
                Ok(i32.const_zero().into())
            }
            Extract => {
                let index = self.simd_integer(&args[1], i64)?;
                let vector = self.simd_vector(&args[0])?;
                self.builder.build_extract_element(vector, index, "simd.lane").map_err(e)
            }
            Insert => {
                let vector = self.simd_vector(&args[0])?;
                let index = self.simd_integer(&args[1], i64)?;
                let value = self.codegen_expr(&args[2])?;
                Ok(self.builder.build_insert_element(vector, value, index, "simd.set").map_err(e)?.into())
            }
            Negate | Not | Abs | SquareRoot | Floor | Ceiling => {
                let shape = self.simd_shape(ty)?;
                let v = self.simd_vector(&args[0])?;
                let float = shape.lane == Lane::Float;
                let b = &self.builder;
                let overload = [shape.ty.as_basic_type_enum()];
                match (op, float) {
                    (Negate, false) => Ok(b.build_int_neg(v, "simd.neg").map_err(e)?.into()),
                    (Negate, true) => Ok(b.build_float_neg(v, "simd.neg").map_err(e)?.into()),
                    (Not, false) => Ok(b.build_not(v, "simd.not").map_err(e)?.into()),
                    (Abs, false) => {
                        let wrap = self.context.bool_type().const_zero();
                        self.simd_intrinsic("llvm.abs", &overload, &[v.into(), wrap.into()])
                    }
                    (Abs, true) => self.simd_intrinsic("llvm.fabs", &overload, &[v.into()]),
                    (SquareRoot, true) => self.simd_intrinsic("llvm.sqrt", &overload, &[v.into()]),
                    (Floor, true) => self.simd_intrinsic("llvm.floor", &overload, &[v.into()]),
                    (Ceiling, true) => self.simd_intrinsic("llvm.ceil", &overload, &[v.into()]),
                    _ => Err(format!("'{}' needs {} lanes, not '{}'", op.name(), if float { "integer" } else { "float" }, ty)),
                }
            }
            Add | Subtract | Multiply | Divide | Remainder | And | Or | Xor | Minimum | Maximum => {
                let shape = self.simd_shape(ty)?;
                let l = self.simd_vector(&args[0])?;
                let r = self.simd_vector(&args[1])?;
                let b = &self.builder;
                let overload = [shape.ty.as_basic_type_enum()];
                let value: VectorValue<'ctx> = match (op, shape.lane) {
                    (Add, Lane::Float) => b.build_float_add(l, r, "simd.add").map_err(e)?,
                    (Add, _) => b.build_int_add(l, r, "simd.add").map_err(e)?,
                    (Subtract, Lane::Float) => b.build_float_sub(l, r, "simd.sub").map_err(e)?,
                    (Subtract, _) => b.build_int_sub(l, r, "simd.sub").map_err(e)?,
                    (Multiply, Lane::Float) => b.build_float_mul(l, r, "simd.mul").map_err(e)?,
                    (Multiply, _) => b.build_int_mul(l, r, "simd.mul").map_err(e)?,
                    (Divide, Lane::Float) => b.build_float_div(l, r, "simd.div").map_err(e)?,
                    (Divide, Lane::Signed) => b.build_int_signed_div(l, r, "simd.div").map_err(e)?,
                    (Divide, Lane::Unsigned) => b.build_int_unsigned_div(l, r, "simd.div").map_err(e)?,
                    (Remainder, Lane::Float) => b.build_float_rem(l, r, "simd.rem").map_err(e)?,
                    (Remainder, Lane::Signed) => b.build_int_signed_rem(l, r, "simd.rem").map_err(e)?,
                    (Remainder, Lane::Unsigned) => b.build_int_unsigned_rem(l, r, "simd.rem").map_err(e)?,
                    (And, Lane::Float) | (Or, Lane::Float) | (Xor, Lane::Float) => {
                        return Err(format!("'{}' needs integer lanes, not '{}'", op.name(), ty));
                    }
                    (And, _) => b.build_and(l, r, "simd.and").map_err(e)?,
                    (Or, _) => b.build_or(l, r, "simd.or").map_err(e)?,
                    (Xor, _) => b.build_xor(l, r, "simd.xor").map_err(e)?,
                    (Minimum | Maximum, lane) => {
                        let name = match (op, lane) {
                            (Minimum, Lane::Float) => "llvm.minnum",
                            (Minimum, Lane::Signed) => "llvm.smin",
                            (Minimum, Lane::Unsigned) => "llvm.umin",
                            (_, Lane::Float) => "llvm.maxnum",
                            (_, Lane::Signed) => "llvm.smax",
                            _ => "llvm.umax",
                        };
                        return self.simd_intrinsic(name, &overload, &[l.into(), r.into()]);
                    }
                    _ => unreachable!(),
                };
                Ok(value.into())
            }
            ShiftLeft | ShiftRight | RotateLeft | RotateRight => {
                let shape = self.simd_shape(ty)?;
                if shape.lane == Lane::Float {
                    return Err(format!("'{}' needs integer lanes, not '{}'", op.name(), ty));
                }
                let v = self.simd_vector(&args[0])?;
                let lane = shape.ty.get_element_type().into_int_type();
                let count = self.simd_integer(&args[1], lane)?;
                let counts = self.simd_splat(count.into(), shape.ty)?;
                let b = &self.builder;
                let overload = [shape.ty.as_basic_type_enum()];
                match op {
                    ShiftLeft => Ok(b.build_left_shift(v, counts, "simd.shl").map_err(e)?.into()),
                    ShiftRight => {
                        Ok(b.build_right_shift(v, counts, shape.lane == Lane::Signed, "simd.shr").map_err(e)?.into())
                    }
                    RotateLeft => self.simd_intrinsic("llvm.fshl", &overload, &[v.into(), v.into(), counts.into()]),
                    _ => self.simd_intrinsic("llvm.fshr", &overload, &[v.into(), v.into(), counts.into()]),
                }
            }
            Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual => {
                let shape = self.simd_shape(ty)?;
                let l = self.simd_vector(&args[0])?;
                let r = self.simd_vector(&args[1])?;
                let b = &self.builder;
                let mask = if shape.lane == Lane::Float {
                    // Ordered, as scalar comparisons are, except `!=`, which
                    // is true for NaN.
                    let predicate = match op {
                        Equal => FloatPredicate::OEQ,
                        NotEqual => FloatPredicate::UNE,
                        Less => FloatPredicate::OLT,
                        LessEqual => FloatPredicate::OLE,
                        Greater => FloatPredicate::OGT,
                        _ => FloatPredicate::OGE,
                    };
                    b.build_float_compare(predicate, l, r, "simd.cmp").map_err(e)?
                } else {
                    let signed = shape.lane == Lane::Signed;
                    let predicate = match (op, signed) {
                        (Equal, _) => IntPredicate::EQ,
                        (NotEqual, _) => IntPredicate::NE,
                        (Less, true) => IntPredicate::SLT,
                        (Less, false) => IntPredicate::ULT,
                        (LessEqual, true) => IntPredicate::SLE,
                        (LessEqual, false) => IntPredicate::ULE,
                        (Greater, true) => IntPredicate::SGT,
                        (Greater, false) => IntPredicate::UGT,
                        (_, true) => IntPredicate::SGE,
                        (_, false) => IntPredicate::UGE,
                    };
                    b.build_int_compare(predicate, l, r, "simd.cmp").map_err(e)?
                };
                Ok(mask.into())
            }
            Select => {
                let mask = self.simd_vector(&args[0])?;
                let if_true = self.simd_vector(&args[1])?;
                let if_false = self.simd_vector(&args[2])?;
                self.builder.build_select(mask, if_true, if_false, "simd.select").map_err(e)
            }
            Sum | ReduceMinimum | ReduceMaximum => {
                let shape = self.simd_shape(ty)?;
                let v = self.simd_vector(&args[0])?;
                let overload = [shape.ty.as_basic_type_enum()];
                match (op, shape.lane) {
                    (Sum, Lane::Float) => {
                        // In lane order from -0.0 (the identity of `+`), so
                        // the result does not depend on the target.
                        let lane = shape.ty.get_element_type().into_float_type();
                        let start = lane.const_float(-0.0);
                        self.simd_intrinsic("llvm.vector.reduce.fadd", &overload, &[start.into(), v.into()])
                    }
                    (Sum, _) => self.simd_intrinsic("llvm.vector.reduce.add", &overload, &[v.into()]),
                    (ReduceMinimum, Lane::Float) => self.simd_intrinsic("llvm.vector.reduce.fmin", &overload, &[v.into()]),
                    (ReduceMinimum, Lane::Signed) => self.simd_intrinsic("llvm.vector.reduce.smin", &overload, &[v.into()]),
                    (ReduceMinimum, Lane::Unsigned) => {
                        self.simd_intrinsic("llvm.vector.reduce.umin", &overload, &[v.into()])
                    }
                    (_, Lane::Float) => self.simd_intrinsic("llvm.vector.reduce.fmax", &overload, &[v.into()]),
                    (_, Lane::Signed) => self.simd_intrinsic("llvm.vector.reduce.smax", &overload, &[v.into()]),
                    _ => self.simd_intrinsic("llvm.vector.reduce.umax", &overload, &[v.into()]),
                }
            }
            Any | All => {
                let shape = self.simd_shape(ty)?;
                let v = self.simd_vector(&args[0])?;
                let name = if op == Any { "llvm.vector.reduce.or" } else { "llvm.vector.reduce.and" };
                self.simd_intrinsic(name, &[shape.ty.as_basic_type_enum()], &[v.into()])
            }
            ToBits => {
                let shape = self.simd_shape(ty)?;
                let v = self.simd_vector(&args[0])?;
                let width = std::num::NonZeroU32::new(shape.count).ok_or("a vector has at least one lane")?;
                let bits = self.context.custom_width_int_type(width)?;
                let packed = self.builder.build_bit_cast(v, bits, "simd.bits").map_err(e)?.into_int_value();
                let wide = if shape.count < 64 {
                    self.builder.build_int_z_extend(packed, i64, "simd.bits64").map_err(e)?
                } else {
                    packed
                };
                Ok(wide.into())
            }
            Reverse | InterleaveLow | InterleaveHigh | Shuffle => {
                let shape = self.simd_shape(ty)?;
                let n = shape.count;
                let a = self.simd_vector(&args[0])?;
                match op {
                    Reverse => {
                        let mask = self.simd_indices((0..n).rev());
                        Ok(self.builder.build_shuffle_vector(a, a, mask, "simd.reverse").map_err(e)?.into())
                    }
                    InterleaveLow | InterleaveHigh => {
                        let other = self.simd_vector(&args[1])?;
                        let base = if op == InterleaveLow { 0 } else { n / 2 };
                        let mask = self.simd_indices((0..n).map(|i| base + i / 2 + (i % 2) * n));
                        Ok(self.builder.build_shuffle_vector(a, other, mask, "simd.interleave").map_err(e)?.into())
                    }
                    _ => {
                        // Lane `i` is `a[indices[i] % n]`: always in range.
                        // With constant indices LLVM folds the extracts and
                        // inserts into one `shufflevector`.
                        let indices = self.simd_vector(&args[1])?;
                        let wrap = i64.const_int(n as u64 - 1, false);
                        let mut result = shape.ty.get_undef();
                        for i in 0..n {
                            let at = i64.const_int(i as u64, false);
                            let b = &self.builder;
                            let index = b.build_extract_element(indices, at, "simd.index").map_err(e)?.into_int_value();
                            let index = b.build_int_cast_sign_flag(index, i64, false, "simd.index64").map_err(e)?;
                            let index = b.build_and(index, wrap, "simd.wrap").map_err(e)?;
                            let lane = b.build_extract_element(a, index, "simd.pick").map_err(e)?;
                            result = b.build_insert_element(result, lane, at, "simd.place").map_err(e)?;
                        }
                        Ok(result.into())
                    }
                }
            }
            Convert | Reinterpret => {
                let target = self.simd_shape(ty)?;
                let source_ty = self.value_sema_type(&args[0]).unwrap_or_default();
                let source_lane = shape(&source_ty).map(|(lane, _)| Lane::of(&lane));
                let v = self.simd_vector(&args[0])?;
                let b = &self.builder;
                if op == Reinterpret {
                    if self.simd_size(v.get_type()) != self.simd_size(target.ty) {
                        return Err(format!("cannot reinterpret '{}' as '{}': their sizes differ", source_ty, ty));
                    }
                    return b.build_bit_cast(v, target.ty, "simd.reinterpret").map_err(e);
                }
                if v.get_type().get_size() != target.count {
                    return Err(format!("cannot convert '{}' to '{}': their lane counts differ", source_ty, ty));
                }
                let from = source_lane.unwrap_or(Lane::Signed);
                let value: BasicValueEnum<'ctx> = match (from, target.lane) {
                    (Lane::Float, Lane::Float) => b.build_float_cast(v, target.ty, "simd.convert").map_err(e)?.into(),
                    (Lane::Float, to) => {
                        // Saturating: out-of-range lanes clamp and NaN is 0,
                        // where `fptosi` would give poison.
                        let name = if to == Lane::Signed { "llvm.fptosi.sat" } else { "llvm.fptoui.sat" };
                        let overloads = [target.ty.as_basic_type_enum(), v.get_type().as_basic_type_enum()];
                        return self.simd_intrinsic(name, &overloads, &[v.into()]);
                    }
                    (Lane::Signed, Lane::Float) => b.build_signed_int_to_float(v, target.ty, "simd.convert").map_err(e)?.into(),
                    (Lane::Unsigned, Lane::Float) => {
                        b.build_unsigned_int_to_float(v, target.ty, "simd.convert").map_err(e)?.into()
                    }
                    (from, _) => b.build_int_cast_sign_flag(v, target.ty, from == Lane::Signed, "simd.convert").map_err(e)?.into(),
                };
                Ok(value)
            }
        }
    }

    /// Marks the methods of every struct holding a vector (`simd.Vector`,
    /// `simd.Mask`) `alwaysinline`, and at `-O0` inlines them: each wraps
    /// one or a few instructions, and a call per lane operation would make
    /// an unoptimized vector loop (the runtime's ASCII scan) slower than
    /// the scalar one it replaces. The optimizing pipelines inline them
    /// anyway.
    pub(crate) fn inline_vector_methods(&self) -> Result<(), String> {
        let prefixes: Vec<String> = self
            .values
            .iter()
            .filter(|(_, fields)| fields.iter().any(|f| shape(f).is_some()))
            .map(|(name, _)| name.clone())
            .collect();
        if prefixes.is_empty() {
            return Ok(());
        }
        let kind = inkwell::attributes::Attribute::get_named_enum_kind_id("alwaysinline");
        let always = self.context.create_enum_attribute(kind, 0);
        let mut marked = false;
        for function in self.module.get_functions() {
            let name = function.get_name().to_string_lossy();
            // Methods are `Name.method`, constructors `Name$1`.
            let member = |p: &String| name.strip_prefix(p.as_str()).is_some_and(|rest| rest.starts_with(['.', '$']));
            if function.count_basic_blocks() > 0 && prefixes.iter().any(member) {
                function.add_attribute(inkwell::attributes::AttributeLoc::Function, always);
                marked = true;
            }
        }
        if marked && self.opt_level == crate::target::OptLevel::O0 {
            let machine = crate::target::target_machine()?;
            self.module
                .run_passes("always-inline", &machine, inkwell::passes::PassBuilderOptions::create())
                .map_err(|e| format!("cannot inline vector methods: {}", e))?;
        }
        Ok(())
    }

    /// The size of a vector type in bytes, as stored.
    pub(crate) fn simd_size(&self, ty: VectorType<'ctx>) -> u32 {
        let data = crate::target::target_machine().map(|m| m.get_target_data());
        match data {
            Ok(data) => data.get_store_size(&ty) as u32,
            Err(_) => ty.get_size() * self.simd_lane_size(ty),
        }
    }

    /// The size of one lane in bytes: the alignment of an unaligned access.
    fn simd_lane_size(&self, ty: VectorType<'ctx>) -> u32 {
        match ty.get_element_type() {
            BasicTypeEnum::IntType(t) => t.get_bit_width().div_ceil(8),
            BasicTypeEnum::FloatType(t) if t == self.context.f32_type() => 4,
            _ => 8,
        }
    }
}
