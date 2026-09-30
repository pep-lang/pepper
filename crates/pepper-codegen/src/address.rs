//! Address: port of `source/CodeGen/LLVM/Address.h`.

use inkwell::builder::Builder;
use inkwell::basic_block::BasicBlock;
use inkwell::types::BasicTypeEnum;
use inkwell::values::{BasicValueEnum, FunctionValue, PointerValue};
use std::rc::Rc;

/// A named address (alloca or field GEP) with its Pepper type name and
/// LLVM pointee type (opaque pointers require the type for loads).
#[derive(Clone)]
pub struct Address<'ctx> {
    pub name: String,
    pub ty: Rc<str>,
    pub llvm_ty: Option<BasicTypeEnum<'ctx>>,
    pub ptr: PointerValue<'ctx>,
}

impl<'ctx> Address<'ctx> {
    pub fn new(name: &str, ty: &str, ptr: PointerValue<'ctx>) -> Self {
        Address {
            name: name.to_string(),
            ty: Rc::from(ty),
            llvm_ty: None,
            ptr,
        }
    }

    pub fn with_llvm_ty(
        name: &str,
        ty: &str,
        llvm_ty: BasicTypeEnum<'ctx>,
        ptr: PointerValue<'ctx>,
    ) -> Self {
        Address {
            name: name.to_string(),
            ty: Rc::from(ty),
            llvm_ty: Some(llvm_ty),
            ptr,
        }
    }

    /// Load the current value (port of `Address::value`).
    pub fn load(&self, builder: &Builder<'ctx>) -> Option<BasicValueEnum<'ctx>> {
        match self.llvm_ty {
            Some(ty) => builder.build_load(ty, self.ptr, &self.name).ok(),
            None => None,
        }
    }

    /// Store a value into this address (port of `Address::assign`).
    ///
    /// Fails when the value's LLVM type differs from the slot's: a wider
    /// value writes past the slot (an 8-byte `ptr` into a 4-byte `i32`
    /// field overran the object), so the mismatch is a compiler bug to
    /// report, never a store to emit.
    pub fn store(&self, builder: &Builder<'ctx>, value: BasicValueEnum<'ctx>) -> Result<(), String> {
        if let Some(slot_ty) = self.llvm_ty {
            check_store_type(slot_ty, value, &self.name, &self.ty)?;
        }
        builder.build_store(self.ptr, value).map_err(|e| e.to_string())?;
        Ok(())
    }
}

/// Checks that `value` has exactly the LLVM type `slot_ty` of the slot it
/// is about to be stored into, which is named `name` and has Pepper type
/// `pepper_ty`. Every typed store in codegen goes through this: LLVM
/// accepts a store of any type through an opaque pointer, so a mismatch
/// would otherwise silently corrupt the neighboring memory.
pub fn check_store_type<'ctx>(
    slot_ty: BasicTypeEnum<'ctx>,
    value: BasicValueEnum<'ctx>,
    name: &str,
    pepper_ty: &str,
) -> Result<(), String> {
    let value_ty = value.get_type();
    if value_ty == slot_ty {
        return Ok(());
    }
    Err(format!(
        "internal error: storing a value of LLVM type '{}' into '{}' ('{}', LLVM type '{}')",
        value_ty.print_to_string().to_string(),
        name,
        pepper_ty,
        slot_ty.print_to_string().to_string(),
    ))
}

/// Function context for a codegen'd function: entry/return blocks, retval
/// alloca, and the local-address stack (port of `FunctionGen`'s frame).
pub struct Frame<'ctx> {
    pub function: Option<FunctionValue<'ctx>>,
    pub entry: Option<inkwell::basic_block::BasicBlock<'ctx>>,
    pub return_block: Option<inkwell::basic_block::BasicBlock<'ctx>>,
    pub retval: Option<PointerValue<'ctx>>,
    pub retval_type: Option<String>,
    pub locals: Vec<(String, Address<'ctx>)>,
    /// Innermost enclosing while's `(continue, break)` blocks; `None` outside a loop.
    pub loop_break: Option<(BasicBlock<'ctx>, BasicBlock<'ctx>)>,
    /// Index of the innermost enclosing while's body scope on `scopes`;
    /// `None` outside a loop. Used by break/continue to release exactly the
    /// scopes exited by the jump (all scopes at or below that index for
    /// break; above it for continue).
    pub loop_base_depth: Option<usize>,
    /// True once the current region (function body, `{ }`, if-arm, while
    /// body) has emitted a `return`/`break`/`continue`: every subsequent
    /// statement in it is dead and must be skipped.
    pub exited: bool,
}

impl<'ctx> Frame<'ctx> {
    pub fn empty() -> Self {
        Frame {
            function: None,
            entry: None,
            return_block: None,
            retval: None,
            retval_type: None,
            locals: vec![],
            loop_break: None,
            loop_base_depth: None,
            exited: false,
        }
    }

    pub fn find_local(&self, name: &str) -> Option<&Address<'ctx>> {
        self.locals
            .iter()
            .rev()
            .find(|(n, _)| n == name)
            .map(|(_, a)| a)
    }

    pub fn push_local(&mut self, name: &str, addr: Address<'ctx>) {
        self.locals.push((name.to_string(), addr));
    }
}
