//! Runtime checks (#265): integer arithmetic that overflows, a division by
//! zero (or `MIN / -1`), and a shift by at least the type's width panic
//! with a located message instead of wrapping or being undefined:
//!
//! ```text
//! main.pep:3:14: integer overflow in 'int' addition
//! ```
//!
//! Each checked operation branches to its own cold block that calls
//! `_pep_panic` (noreturn, see [`crate::facts`]), so the fast path stays a
//! single `{s,u}{add,sub,mul}.with.overflow` and a predicted branch. An
//! operation whose operands are both constants is checked here instead: an
//! overflow is a compile error at the operator.
//!
//! [`RuntimeChecks`] says which kinds of check a build keeps
//! (`--no-runtime-checks`). Without the overflow check, arithmetic wraps
//! (never undefined); without the shift check, the count is masked to the
//! type's width.

use crate::CodeGenerator;
use inkwell::values::{BasicValueEnum, IntValue};
use pepper_sema::model::{BinaryOp, Loc};

/// Which runtime checks the generated code performs. Every check is on by
/// default; `--no-runtime-checks` turns kinds off from `-O1` up.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct RuntimeChecks {
    /// `+`, `-`, `*`, `**`, unary `-`, `++`, `--` and compound assignment
    /// overflowing their type.
    pub overflow: bool,
    /// Division or remainder by zero, and `MIN / -1` of a signed type.
    pub divide: bool,
    /// A shift count of at least the type's width.
    pub shift: bool,
    /// Array and string indexing out of range (`_pep_check_bounds`).
    pub bounds: bool,
    /// Calling through, or matching on, a null reference.
    pub null: bool,
}

impl Default for RuntimeChecks {
    fn default() -> Self {
        RuntimeChecks::ALL
    }
}

impl RuntimeChecks {
    /// Every check on.
    pub const ALL: RuntimeChecks = RuntimeChecks { overflow: true, divide: true, shift: true, bounds: true, null: true };

    /// The names `--no-runtime-checks` accepts, besides `all`.
    pub const NAMES: [&'static str; 5] = ["overflow", "divide", "shift", "bounds", "null"];

    /// Every check on except those named in `list`, a comma-separated list
    /// of [`Self::NAMES`] or `all` (`--no-runtime-checks=overflow,shift`).
    pub fn without(list: &str) -> Result<RuntimeChecks, String> {
        let mut checks = RuntimeChecks::ALL;
        for name in list.split(',').map(str::trim) {
            match name {
                "overflow" => checks.overflow = false,
                "divide" => checks.divide = false,
                "shift" => checks.shift = false,
                "bounds" => checks.bounds = false,
                "null" => checks.null = false,
                "all" => checks = RuntimeChecks::NONE,
                _ => {
                    return Err(format!(
                        "unknown runtime check '{}' in '--no-runtime-checks': expected {} or 'all'",
                        name,
                        Self::NAMES.map(|n| format!("'{}'", n)).join(", ")
                    ));
                }
            }
        }
        Ok(checks)
    }

    /// Every check off.
    pub const NONE: RuntimeChecks = RuntimeChecks { overflow: false, divide: false, shift: false, bounds: false, null: false };

    /// The names of the checks that are off, in [`Self::NAMES`] order: empty
    /// with every check on. Part of the build cache's key.
    pub fn removed(&self) -> Vec<&'static str> {
        let on = [self.overflow, self.divide, self.shift, self.bounds, self.null];
        Self::NAMES.iter().zip(on).filter(|&(_, on)| !on).map(|(name, _)| *name).collect()
    }
}

/// The Pepper name of the integer type `width` bits wide (`int`, `ulong`).
fn type_name(width: u32, unsigned: bool) -> &'static str {
    match (width, unsigned) {
        (8, false) => "char",
        (8, true) => "byte",
        (16, false) => "short",
        (16, true) => "ushort",
        (64, false) => "long",
        (64, true) => "ulong",
        (_, false) => "int",
        (_, true) => "uint",
    }
}

/// What a message calls the operation `op` (`addition`).
fn operation_name(op: BinaryOp) -> &'static str {
    match op {
        BinaryOp::Add | BinaryOp::AddOverflows => "addition",
        BinaryOp::Sub | BinaryOp::SubOverflows => "subtraction",
        BinaryOp::Mul | BinaryOp::MulOverflows => "multiplication",
        BinaryOp::Div => "division",
        BinaryOp::Mod => "remainder",
        BinaryOp::Pow => "exponentiation",
        _ => "operation",
    }
}

/// `value` as a signed or unsigned number of `width` bits, when it is a
/// constant.
fn constant(value: IntValue<'_>, unsigned: bool) -> Option<i128> {
    if !value.is_const() {
        return None;
    }
    if unsigned {
        value.get_zero_extended_constant().map(i128::from)
    } else {
        value.get_sign_extended_constant().map(i128::from)
    }
}

/// Whether `value` fits a `width`-bit integer of the given signedness.
fn fits(value: i128, width: u32, unsigned: bool) -> bool {
    if unsigned {
        value >= 0 && value < (1i128 << width)
    } else {
        value >= -(1i128 << (width - 1)) && value < (1i128 << (width - 1))
    }
}

impl<'ctx> CodeGenerator<'ctx> {
    /// `file:line:col: ` for `loc`, to start a check's message; empty when
    /// the location is unknown.
    fn check_prefix(&self, loc: Loc) -> String {
        let Some((name, lines)) = loc.known().and_then(|loc| self.check_files.get(loc.file.0 as usize)) else {
            return String::new();
        };
        let line = lines.partition_point(|&start| start <= loc.span.start);
        let column = loc.span.start - lines[line.max(1) - 1];
        format!("{}:{}:{}: ", name, line.max(1), column + 1)
    }

    /// Record each source's name and line starts, for [`Self::check_prefix`].
    pub(crate) fn index_check_files(&mut self, sources: &pepper_parser::diagnostic::SourceMap) {
        use pepper_parser::diagnostic::{FileId, Sources};
        self.check_files.clear();
        let mut file = 0;
        while let Some((name, text)) = sources.get(FileId(file)) {
            let mut lines = vec![0];
            lines.extend(text.bytes().enumerate().filter(|&(_, b)| b == b'\n').map(|(i, _)| i + 1));
            self.check_files.push((name.to_string(), lines));
            file += 1;
        }
    }

    /// Panic with `message` (located at `loc`) when `failed` is true; carry
    /// on after it otherwise. Without the runtime (`--no-runtime`) the
    /// failure traps.
    pub(crate) fn panic_if(&mut self, failed: IntValue<'ctx>, message: &str, loc: Loc) -> Result<(), String> {
        let function = self.builder.get_insert_block().and_then(|block| block.get_parent()).ok_or_else(|| "no function".to_string())?;
        let fail = self.context.append_basic_block(function, "check.fail");
        let ok = self.context.append_basic_block(function, "check.ok");
        self.builder.build_conditional_branch(failed, fail, ok).map_err(|e| e.to_string())?;
        self.builder.position_at_end(fail);
        let text = format!("{}{}", self.check_prefix(loc), message);
        match self.module.get_function("_pep_panic").or_else(|| self.functions.get("_pep_panic").copied()) {
            Some(panic) => {
                let text = self.check_message(&text)?;
                let call = self.builder.build_call(panic, &[text.into()], "").map_err(|e| e.to_string())?;
                // The call reads only its message (and the C library's own
                // state), and never returns: nothing after it can see the
                // program's memory, so a reference count stepped around a
                // check still folds away (#263). Encoded `MemoryEffects`:
                // argument memory read (1), inaccessible memory read and
                // written (3 << 2).
                let memory = inkwell::attributes::Attribute::get_named_enum_kind_id("memory");
                call.add_attribute(inkwell::attributes::AttributeLoc::Function, self.context.create_enum_attribute(memory, 1 | (3 << 2)));
            }
            None => {
                let trap = inkwell::intrinsics::Intrinsic::find("llvm.trap").ok_or("no llvm.trap")?;
                let trap = trap.get_declaration(&self.module, &[]).ok_or("no llvm.trap")?;
                self.builder.build_call(trap, &[], "").map_err(|e| e.to_string())?;
            }
        }
        self.builder.build_unreachable().map_err(|e| e.to_string())?;
        self.builder.position_at_end(ok);
        Ok(())
    }

    /// The constant C string `text`, one per distinct text, named by its
    /// hash: a unit's code must not depend on what was generated before it
    /// (the build cache checks that), so the name is no counter.
    fn check_message(&mut self, text: &str) -> Result<inkwell::values::PointerValue<'ctx>, String> {
        let hash = text.bytes().fold(0xcbf29ce484222325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3));
        let name = format!("__pep_check_message.{:016x}", hash);
        if let Some(global) = self.module.get_global(&name) {
            return Ok(global.as_pointer_value());
        }
        let bytes = self.context.const_string(text.as_bytes(), true);
        let global = self.module.add_global(bytes.get_type(), None, &name);
        global.set_initializer(&bytes);
        global.set_constant(true);
        global.set_linkage(inkwell::module::Linkage::Private);
        global.set_unnamed_addr(true);
        Ok(global.as_pointer_value())
    }

    /// `op`'s result and whether it overflowed, through LLVM's
    /// `llvm.{s,u}{add,sub,mul}.with.overflow`.
    fn with_overflow(&mut self, op: BinaryOp, lhs: IntValue<'ctx>, rhs: IntValue<'ctx>, unsigned: bool) -> Result<(IntValue<'ctx>, IntValue<'ctx>), String> {
        let base = match op {
            BinaryOp::Add | BinaryOp::AddOverflows | BinaryOp::WrappingAdd => "add",
            BinaryOp::Sub | BinaryOp::SubOverflows | BinaryOp::WrappingSub => "sub",
            _ => "mul",
        };
        let name = format!("llvm.{}{}.with.overflow", if unsigned { "u" } else { "s" }, base);
        let intrinsic = inkwell::intrinsics::Intrinsic::find(&name).ok_or_else(|| format!("no {}", name))?;
        let declaration = intrinsic.get_declaration(&self.module, &[lhs.get_type().into()]).ok_or_else(|| format!("no {}", name))?;
        let pair = self
            .builder
            .build_call(declaration, &[lhs.into(), rhs.into()], base)
            .map_err(|e| e.to_string())?
            .try_as_basic_value()
            .basic()
            .ok_or("no overflow result")?
            .into_struct_value();
        let value = self.builder.build_extract_value(pair, 0, base).map_err(|e| e.to_string())?.into_int_value();
        let overflowed = self.builder.build_extract_value(pair, 1, "overflowed").map_err(|e| e.to_string())?.into_int_value();
        Ok((value, overflowed))
    }

    /// `lhs op rhs` for `+`, `-` or `*`, panicking on overflow when the
    /// check is on. Two constant operands that overflow are a compile error.
    /// `operation` names it in the message when it is not `op`'s own name
    /// (`negation` for `0 - x`, `increment`).
    pub(crate) fn checked_arithmetic(&mut self, op: BinaryOp, lhs: IntValue<'ctx>, rhs: IntValue<'ctx>, unsigned: bool, loc: Loc, operation: Option<&str>) -> Result<IntValue<'ctx>, String> {
        let width = lhs.get_type().get_bit_width();
        let message = format!("integer overflow in '{}' {}", type_name(width, unsigned), operation.unwrap_or(operation_name(op)));
        if let (Some(l), Some(r)) = (constant(lhs, unsigned), constant(rhs, unsigned)) {
            let exact = match op {
                BinaryOp::Add => l + r,
                BinaryOp::Sub => l - r,
                _ => l.checked_mul(r).unwrap_or(i128::MAX),
            };
            if !fits(exact, width, unsigned) {
                return Err(message);
            }
        }
        let plain = |this: &mut Self| -> Result<IntValue<'ctx>, String> {
            match op {
                BinaryOp::Add => this.builder.build_int_add(lhs, rhs, "add"),
                BinaryOp::Sub => this.builder.build_int_sub(lhs, rhs, "sub"),
                _ => this.builder.build_int_mul(lhs, rhs, "mul"),
            }
            .map_err(|e| e.to_string())
        };
        if !self.runtime_checks.overflow || (lhs.is_const() && rhs.is_const()) {
            return plain(self);
        }
        let (value, overflowed) = self.with_overflow(op, lhs, rhs, unsigned)?;
        self.panic_if(overflowed, &message, loc)?;
        Ok(value)
    }

    /// `lhs / rhs` or `lhs % rhs`, panicking on a zero divisor and on
    /// `MIN / -1` when the check is on. A constant zero divisor is a compile
    /// error.
    fn checked_division(&mut self, op: BinaryOp, lhs: IntValue<'ctx>, rhs: IntValue<'ctx>, unsigned: bool, loc: Loc) -> Result<IntValue<'ctx>, String> {
        let width = lhs.get_type().get_bit_width();
        let divisor = constant(rhs, unsigned);
        if divisor == Some(0) {
            return Err("division by zero".to_string());
        }
        let can_overflow = !unsigned && divisor.is_none_or(|d| d == -1);
        if let (Some(l), Some(-1)) = (constant(lhs, unsigned), divisor)
            && !unsigned
            && !fits(-l, width, false)
        {
            return Err(format!("integer overflow in '{}' {}", type_name(width, unsigned), operation_name(op)));
        }
        if self.runtime_checks.divide {
            if divisor.is_none() {
                let zero = self
                    .builder
                    .build_int_compare(inkwell::IntPredicate::EQ, rhs, rhs.get_type().const_zero(), "divisor_zero")
                    .map_err(|e| e.to_string())?;
                self.panic_if(zero, "division by zero", loc)?;
            }
            if can_overflow && !(lhs.is_const() && constant(lhs, false).is_some_and(|l| fits(-l, width, false))) {
                let ty = lhs.get_type();
                let min = ty.const_int(1u64 << (width - 1), false);
                let is_min = self.builder.build_int_compare(inkwell::IntPredicate::EQ, lhs, min, "is_min").map_err(|e| e.to_string())?;
                let is_minus_one = self
                    .builder
                    .build_int_compare(inkwell::IntPredicate::EQ, rhs, ty.const_all_ones(), "is_minus_one")
                    .map_err(|e| e.to_string())?;
                let overflowed = self.builder.build_and(is_min, is_minus_one, "overflowed").map_err(|e| e.to_string())?;
                let message = format!("integer overflow in '{}' {}", type_name(width, unsigned), operation_name(op));
                self.panic_if(overflowed, &message, loc)?;
            }
        }
        let value = match (op, unsigned) {
            (BinaryOp::Div, true) => self.builder.build_int_unsigned_div(lhs, rhs, "udiv"),
            (BinaryOp::Div, false) => self.builder.build_int_signed_div(lhs, rhs, "sdiv"),
            (_, true) => self.builder.build_int_unsigned_rem(lhs, rhs, "urem"),
            (_, false) => self.builder.build_int_signed_rem(lhs, rhs, "srem"),
        };
        value.map_err(|e| e.to_string())
    }

    /// `lhs << rhs` or `lhs >> rhs`, panicking when the count is at least
    /// the type's width (or negative) and the check is on; without the
    /// check the count is masked to the width, so the result is never
    /// undefined.
    fn checked_shift(&mut self, op: BinaryOp, lhs: IntValue<'ctx>, rhs: IntValue<'ctx>, unsigned: bool, loc: Loc) -> Result<IntValue<'ctx>, String> {
        let ty = lhs.get_type();
        let width = ty.get_bit_width();
        let in_range = rhs.get_zero_extended_constant().is_some_and(|count| count < width as u64);
        let count = if in_range {
            rhs
        } else if self.runtime_checks.shift {
            let too_far = self
                .builder
                .build_int_compare(inkwell::IntPredicate::UGE, rhs, ty.const_int(width as u64, false), "shift_too_far")
                .map_err(|e| e.to_string())?;
            let message = format!("shift count out of range for '{}': must be from 0 to {}", type_name(width, unsigned), width - 1);
            self.panic_if(too_far, &message, loc)?;
            rhs
        } else {
            self.builder.build_and(rhs, ty.const_int(width as u64 - 1, false), "shift_count").map_err(|e| e.to_string())?
        };
        match op {
            BinaryOp::LShift => self.builder.build_left_shift(lhs, count, "shl"),
            _ => self.builder.build_right_shift(lhs, count, !unsigned, "shr"),
        }
        .map_err(|e| e.to_string())
    }

    /// `base ** exp` with every multiplication checked: a multiply whose
    /// result is used and overflows panics. Falls back to the unchecked
    /// form when the overflow check is off.
    fn checked_pow(&mut self, base: IntValue<'ctx>, exp: IntValue<'ctx>, unsigned: bool, loc: Loc) -> Result<IntValue<'ctx>, String> {
        let width = base.get_type().get_bit_width();
        let message = format!("integer overflow in '{}' {}", type_name(width, unsigned), operation_name(BinaryOp::Pow));
        if let (Some(b), Some(e)) = (constant(base, unsigned), constant(exp, unsigned))
            && e >= 0
        {
            let mut exact: Option<i128> = Some(1);
            for _ in 0..e.min(200) {
                exact = exact.and_then(|v| v.checked_mul(b)).filter(|&v| fits(v, width, unsigned));
                if exact.is_none() || b == 0 || b == 1 {
                    break;
                }
            }
            if exact.is_none() {
                return Err(message);
            }
        }
        if !self.runtime_checks.overflow || (base.is_const() && exp.is_const()) {
            return crate::ops::int_binary(self.context, &self.builder, BinaryOp::Pow, base, exp, if unsigned { "u64" } else { "i64" })
                .ok_or_else(|| "unsupported op Pow".to_string());
        }
        // A small constant exponent unrolls to checked multiplies.
        if let Some(e) = constant(exp, unsigned)
            && (0..=31).contains(&e)
        {
            let mut acc = base.get_type().const_int(1, false);
            for _ in 0..e {
                let (product, overflowed) = self.with_overflow(BinaryOp::Mul, acc, base, unsigned)?;
                self.panic_if(overflowed, &message, loc)?;
                acc = product;
            }
            return Ok(acc);
        }
        use inkwell::IntPredicate::*;
        let ty = base.get_type();
        let exp = if exp.get_type() == ty {
            exp
        } else if exp.get_type().get_bit_width() < ty.get_bit_width() {
            self.builder.build_int_s_extend(exp, ty, "powexp").map_err(|e| e.to_string())?
        } else {
            self.builder.build_int_truncate(exp, ty, "powexp").map_err(|e| e.to_string())?
        };
        let one = ty.const_int(1, false);
        let zero = ty.const_zero();
        let function = self.builder.get_insert_block().and_then(|block| block.get_parent()).ok_or_else(|| "no function".to_string())?;
        let entry = self.builder.get_insert_block().ok_or("no block")?;
        let header = self.context.append_basic_block(function, "pow.loop");
        let body = self.context.append_basic_block(function, "pow.body");
        let done = self.context.append_basic_block(function, "pow.done");
        self.builder.build_unconditional_branch(header).map_err(|e| e.to_string())?;

        self.builder.position_at_end(header);
        let acc = self.builder.build_phi(ty, "pow.acc").map_err(|e| e.to_string())?;
        let factor = self.builder.build_phi(ty, "pow.factor").map_err(|e| e.to_string())?;
        let remaining = self.builder.build_phi(ty, "pow.exp").map_err(|e| e.to_string())?;
        let acc_v = acc.as_basic_value().into_int_value();
        let factor_v = factor.as_basic_value().into_int_value();
        let remaining_v = remaining.as_basic_value().into_int_value();
        let more = self
            .builder
            .build_int_compare(if unsigned { NE } else { SGT }, remaining_v, zero, "pow.more")
            .map_err(|e| e.to_string())?;
        self.builder.build_conditional_branch(more, body, done).map_err(|e| e.to_string())?;

        self.builder.position_at_end(body);
        let low_bit = self.builder.build_and(remaining_v, one, "pow.bit").map_err(|e| e.to_string())?;
        let odd = self.builder.build_int_compare(NE, low_bit, zero, "pow.odd").map_err(|e| e.to_string())?;
        let (multiplied, multiply_overflowed) = self.with_overflow(BinaryOp::Mul, acc_v, factor_v, unsigned)?;
        let halved = self.builder.build_right_shift(remaining_v, one, false, "pow.half").map_err(|e| e.to_string())?;
        let (squared, square_overflowed) = self.with_overflow(BinaryOp::Mul, factor_v, factor_v, unsigned)?;
        // The product counts when this bit is set; the square only when a
        // later bit will use it.
        let used_product = self.builder.build_and(odd, multiply_overflowed, "pow.product_overflowed").map_err(|e| e.to_string())?;
        let more_bits = self.builder.build_int_compare(NE, halved, zero, "pow.more_bits").map_err(|e| e.to_string())?;
        let used_square = self.builder.build_and(more_bits, square_overflowed, "pow.square_overflowed").map_err(|e| e.to_string())?;
        let overflowed = self.builder.build_or(used_product, used_square, "pow.overflowed").map_err(|e| e.to_string())?;
        self.panic_if(overflowed, &message, loc)?;
        let next_acc = self.builder.build_select(odd, multiplied, acc_v, "pow.next").map_err(|e| e.to_string())?.into_int_value();
        let body_end = self.builder.get_insert_block().ok_or("no block")?;
        self.builder.build_unconditional_branch(header).map_err(|e| e.to_string())?;

        acc.add_incoming(&[(&one, entry), (&next_acc, body_end)]);
        factor.add_incoming(&[(&base, entry), (&squared, body_end)]);
        remaining.add_incoming(&[(&exp, entry), (&halved, body_end)]);

        self.builder.position_at_end(done);
        if unsigned {
            return Ok(acc_v);
        }
        let b = &self.builder;
        let e = |error: inkwell::builder::BuilderError| error.to_string();
        let negative = b.build_int_compare(SLT, exp, zero, "pow.neg").map_err(e)?;
        let exp_odd = b.build_and(exp, one, "pow.expbit").map_err(e)?;
        let exp_odd = b.build_int_compare(NE, exp_odd, zero, "pow.expodd").map_err(e)?;
        let minus_one = ty.const_all_ones();
        let base_is_one = b.build_int_compare(EQ, base, one, "pow.one").map_err(e)?;
        let base_is_minus_one = b.build_int_compare(EQ, base, minus_one, "pow.minusone").map_err(e)?;
        let sign = b.build_select(exp_odd, minus_one, one, "pow.sign").map_err(e)?.into_int_value();
        let fraction = b.build_select(base_is_minus_one, sign, zero, "pow.frac").map_err(e)?.into_int_value();
        let fraction = b.build_select(base_is_one, one, fraction, "pow.frac").map_err(e)?.into_int_value();
        Ok(b.build_select(negative, fraction, acc_v, "pow").map_err(e)?.into_int_value())
    }

    /// `lhs op rhs` on two integers of one width, with the runtime checks
    /// `op` has (see the module comment), or `None` for an operator that has
    /// none: the caller then applies it unchecked. `ty` is the operands'
    /// sema type, which carries their signedness.
    pub(crate) fn checked_int_binary(&mut self, op: BinaryOp, lhs: IntValue<'ctx>, rhs: IntValue<'ctx>, ty: &str, loc: Loc) -> Result<Option<BasicValueEnum<'ctx>>, String> {
        if lhs.get_type().get_bit_width() < 8 || lhs.get_type() != rhs.get_type() {
            return Ok(None);
        }
        let unsigned = crate::ops::is_unsigned_int_type(&pepper_sema::enums::stored_as(ty));
        let value = match op {
            BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul => self.checked_arithmetic(op, lhs, rhs, unsigned, loc, None)?,
            BinaryOp::Div | BinaryOp::Mod => self.checked_division(op, lhs, rhs, unsigned, loc)?,
            BinaryOp::LShift | BinaryOp::RShift => self.checked_shift(op, lhs, rhs, unsigned, loc)?,
            BinaryOp::Pow => self.checked_pow(lhs, rhs, unsigned, loc)?,
            BinaryOp::WrappingAdd => self.builder.build_int_add(lhs, rhs, "wrapping_add").map_err(|e| e.to_string())?,
            BinaryOp::WrappingSub => self.builder.build_int_sub(lhs, rhs, "wrapping_sub").map_err(|e| e.to_string())?,
            BinaryOp::WrappingMul => self.builder.build_int_mul(lhs, rhs, "wrapping_mul").map_err(|e| e.to_string())?,
            BinaryOp::AddOverflows | BinaryOp::SubOverflows | BinaryOp::MulOverflows => self.with_overflow(op, lhs, rhs, unsigned)?.1,
            _ => return Ok(None),
        };
        Ok(Some(value.into()))
    }
}
