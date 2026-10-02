//! LLVM intrinsics reached through `extern` declarations (#344).
//!
//! An extern whose C symbol starts with `llvm.` (`[Link(name =
//! "llvm.ctpop")]`) is not a C function: it is declared as that LLVM
//! intrinsic, with the extern's prototype as its signature, and a call to it
//! is the intrinsic's instruction. The runtime's bit and floating-point
//! methods (`count_ones`, `rotate_left`, `square_root`, ...) and the `hint`
//! module are written with these.
//!
//! The symbol may be the intrinsic's base name (`llvm.ctpop`): when the
//! intrinsic is overloaded, the overload is picked from the prototype (the
//! return type, the first parameter's type, or both, in LLVM's mangling,
//! `llvm.ctpop.i32`). A spelled-out name (`llvm.ctpop.i32`) is used as is.
//! Each candidate is checked by declaring it in a scratch module and running
//! LLVM's verifier, which compares a declaration with the intrinsic's
//! signature, so a prototype that matches no overload is a located error at
//! the extern, never an invalid module. An argument the intrinsic requires
//! to be a constant (`immarg`, such as `llvm.ctlz`'s `is_zero_poison`) is
//! checked at each call, at the argument.

use crate::CodeGenerator;
use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::types::{AsTypeRef, BasicTypeEnum, FunctionType};
use inkwell::values::{AsValueRef, BasicValueEnum, FunctionValue};

/// Whether a C symbol names an LLVM intrinsic rather than a C function.
pub(crate) fn is_intrinsic_symbol(symbol: &str) -> bool {
    symbol.starts_with("llvm.")
}

impl<'ctx> CodeGenerator<'ctx> {
    /// Declare the LLVM intrinsic `symbol` with the extern's prototype
    /// `fn_type` (see the module comment). `name` is the extern's Pepper
    /// name, for the error.
    pub(crate) fn declare_intrinsic(&self, name: &str, symbol: &str, fn_type: FunctionType<'ctx>) -> Result<FunctionValue<'ctx>, String> {
        let id = unsafe { inkwell::llvm_sys::core::LLVMLookupIntrinsicID(symbol.as_ptr() as *const _, symbol.len()) };
        if id == 0 {
            return Err(format!("unknown LLVM intrinsic '{}'", symbol));
        }
        let mut candidates = vec![symbol.to_string()];
        if unsafe { inkwell::llvm_sys::core::LLVMIntrinsicIsOverloaded(id) } != 0 {
            let ret = fn_type.get_return_type();
            let first = fn_type.get_param_types().first().and_then(|p| BasicTypeEnum::try_from(*p).ok());
            let overloads: Vec<Vec<BasicTypeEnum<'ctx>>> = [vec![ret], vec![first], vec![ret, first]]
                .into_iter()
                .filter_map(|types| types.into_iter().collect::<Option<Vec<_>>>())
                .filter(|types| !types.is_empty())
                .collect();
            for types in overloads {
                candidates.push(self.overloaded_intrinsic_name(id, &types));
            }
        }
        let mut problem = String::new();
        for candidate in &candidates {
            if let Some(f) = self.module.get_function(candidate) {
                if f.get_type() == fn_type {
                    return Ok(f);
                }
                continue;
            }
            match self.check_intrinsic(candidate, fn_type) {
                Ok(()) => return Ok(self.module.add_function(candidate, fn_type, None)),
                // Every overload but one has a mangled name that does not fit
                // the prototype; say what is wrong with the others.
                Err(message) if !message.contains("mangled") => problem = message,
                Err(_) => {}
            }
        }
        Err(format!(
            "'{}' does not match the signature of LLVM intrinsic '{}'{}",
            name,
            symbol,
            if problem.is_empty() { String::new() } else { format!(": {}", problem) }
        ))
    }

    /// LLVM's mangled name of intrinsic `id` overloaded on `types`
    /// (`llvm.ctpop` on `i32` is `llvm.ctpop.i32`).
    fn overloaded_intrinsic_name(&self, id: u32, types: &[BasicTypeEnum<'ctx>]) -> String {
        let mut refs: Vec<_> = types.iter().map(|t| t.as_type_ref()).collect();
        let mut length = 0usize;
        unsafe {
            let text = inkwell::llvm_sys::core::LLVMIntrinsicCopyOverloadedName2(
                self.module.as_mut_ptr(),
                id,
                refs.as_mut_ptr(),
                refs.len(),
                &mut length,
            );
            let bytes = std::slice::from_raw_parts(text as *const u8, length);
            let name = String::from_utf8_lossy(bytes).into_owned();
            inkwell::llvm_sys::core::LLVMDisposeMessage(text as *mut _);
            name
        }
    }

    /// Whether declaring `symbol` with `fn_type` is a valid intrinsic
    /// declaration: the verifier's first complaint, if not.
    fn check_intrinsic(&self, symbol: &str, fn_type: FunctionType<'ctx>) -> Result<(), String> {
        let scratch = self.context.create_module("intrinsic_check");
        let f = scratch.add_function(symbol, fn_type, None);
        if unsafe { inkwell::llvm_sys::core::LLVMGetIntrinsicID(f.as_value_ref()) } == 0 {
            return Err(format!("'{}' is not an LLVM intrinsic", symbol));
        }
        // The verifier checks an intrinsic's signature at its calls, not at
        // its declaration: call it once, with zeros (constants, as `immarg`
        // parameters require).
        let caller = scratch.add_function("caller", self.context.void_type().fn_type(&[], false), None);
        let builder = self.context.create_builder();
        builder.position_at_end(self.context.append_basic_block(caller, "entry"));
        let mut args: Vec<inkwell::values::BasicMetadataValueEnum<'ctx>> = vec![];
        for param in fn_type.get_param_types() {
            let Ok(ty) = BasicTypeEnum::try_from(param) else {
                return Err(format!("'{}' takes a parameter Pepper cannot pass", symbol));
            };
            args.push(ty.const_zero().into());
        }
        let built = builder.build_call(f, &args, "").and_then(|_| builder.build_return(None));
        built.map_err(|e| e.to_string())?;
        scratch
            .verify()
            .map_err(|e| e.to_string().lines().next().unwrap_or_default().trim().trim_end_matches('!').to_lowercase())
    }

    /// The error for argument `index` of a call of extern `name` when the
    /// extern is an intrinsic that requires that argument to be a constant
    /// (`immarg`) and `value` is not one.
    pub(crate) fn check_intrinsic_argument(&self, name: &str, index: usize, value: BasicValueEnum<'ctx>) -> Result<(), String> {
        let Some(function) = self.functions.get(name) else { return Ok(()) };
        if unsafe { inkwell::llvm_sys::core::LLVMGetIntrinsicID(function.as_value_ref()) } == 0 {
            return Ok(());
        }
        let immarg = Attribute::get_named_enum_kind_id("immarg");
        if function.get_enum_attribute(AttributeLoc::Param(index as u32), immarg).is_none() {
            return Ok(());
        }
        let constant = match value {
            BasicValueEnum::IntValue(v) => v.is_const(),
            BasicValueEnum::FloatValue(v) => v.is_const(),
            _ => true,
        };
        if constant {
            return Ok(());
        }
        Err(format!("argument {} to '{}' must be a constant", index + 1, name))
    }
}
