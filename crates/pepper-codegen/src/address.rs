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
    pub fn store(&self, builder: &Builder<'ctx>, value: BasicValueEnum<'ctx>) -> Option<()> {
        builder.build_store(self.ptr, value).ok().map(|_| ())
    }
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
