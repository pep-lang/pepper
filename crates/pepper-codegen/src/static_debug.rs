//! The debugger's view of an expanded `static` block (`-g`, see
//! INTERNALS.md §4.4). `passes::static_blocks` starts each pass of an
//! unrolled compile-time loop, and the branch a compile-time `if` kept,
//! with a [`StaticPass`]. Here it becomes:
//!
//! - one `nop` at the loop's or the `if`'s header, under `-O0`, so stepping
//!   stops on the header once per pass, as in a runtime loop. Without it
//!   every pass's code carries the same line, and a debugger, which steps
//!   until the line changes, runs all the passes in one step. (An empty
//!   inline asm would leave no instruction to stop at.)
//! - each compile-time variable in scope (the loop's `field`, a `var`),
//!   stored in its own slot when the function starts (so it holds its
//!   value from the header on) and declared in the pass's lexical block, so
//!   `p field.name` prints the pass's member. A member, case, function or
//!   attribute is a structure of what `reflect` reads from it; a string is
//!   a `char*` to a constant.

use crate::CodeGenerator;
use inkwell::debug_info::{DIFlags, DIFlagsConstants, DIType};
use inkwell::types::BasicType;
use inkwell::values::BasicValueEnum;
use pepper_sema::model::{Loc, StaticConstant, StaticPass};

impl<'ctx> CodeGenerator<'ctx> {
    /// Compile a [`StaticPass`]: nothing without debug info.
    pub(crate) fn codegen_static_pass(&mut self, pass: &StaticPass) -> Result<(), String> {
        if self.debug.is_none() {
            return Ok(());
        }
        if pass.stop && self.opt_level == crate::target::OptLevel::O0 && !crate::target::triple_name().starts_with("wasm") {
            let asm_type = self.context.void_type().fn_type(&[], false);
            let nop = self.context.create_inline_asm(asm_type, "nop".to_string(), String::new(), true, false, None, false);
            self.builder.build_indirect_call(asm_type, nop, &[], "").map_err(|e| e.to_string())?;
        }
        for (name, value) in &pass.values {
            let Some((constant, ty)) = self.static_constant(value) else { continue };
            let slot = self.entry_constant(constant, name)?;
            let block = self.builder.get_insert_block().expect("insert block");
            if let Some(debug) = self.debug.as_mut() {
                debug.declare(self.context, slot, name, ty, pass.loc, None, block);
            }
        }
        Ok(())
    }

    /// A slot in the function's entry block holding `constant`, stored
    /// there too: the debugger may show the variable as soon as it enters
    /// the pass's scope, on the header, before any code of the pass runs.
    fn entry_constant(&self, constant: BasicValueEnum<'ctx>, name: &str) -> Result<inkwell::values::PointerValue<'ctx>, String> {
        let function = self.builder.get_insert_block().and_then(|block| block.get_parent()).ok_or("no function")?;
        let entry = function.get_first_basic_block().ok_or("no entry block")?;
        let builder = self.context.create_builder();
        match entry.get_first_instruction() {
            Some(first) => builder.position_before(&first),
            None => builder.position_at_end(entry),
        }
        let slot = builder.build_alloca(constant.get_type(), name).map_err(|e| e.to_string())?;
        builder.build_store(slot, constant).map_err(|e| e.to_string())?;
        Ok(slot)
    }

    /// `value` as an LLVM constant and its debug type.
    fn static_constant(&mut self, value: &StaticConstant) -> Option<(BasicValueEnum<'ctx>, DIType<'ctx>)> {
        Some(match value {
            StaticConstant::Int(n) => (self.context.i64_type().const_int(*n as u64, true).into(), self.debug_type("long")?),
            StaticConstant::Float(x) => (self.context.f64_type().const_float(*x).into(), self.debug_type("double")?),
            StaticConstant::Bool(b) => (self.context.i8_type().const_int(*b as u64, false).into(), self.debug_type("bool")?),
            StaticConstant::String(text) => {
                let global = self.builder.build_global_string_ptr(text, "static.string").ok()?;
                (global.as_pointer_value().into(), self.debug_type("char*")?)
            }
            StaticConstant::Record { name, fields } => {
                let mut values = vec![];
                let mut types = vec![];
                let mut names = vec![];
                for (field, value) in fields {
                    let (value, ty) = self.static_constant(value)?;
                    values.push(value);
                    types.push(ty);
                    names.push(field.as_str());
                }
                let constant = self.context.const_struct(&values, false);
                let ty = self.static_record_type(name, &names, &types, constant.get_type().as_basic_type_enum())?;
                (constant.into(), ty)
            }
        })
    }

    /// The structure type named `name` with members `names` of types
    /// `types`, laid out as `llvm_type`: one per record name, which always
    /// has the same members.
    fn static_record_type(
        &mut self,
        name: &str,
        names: &[&str],
        types: &[DIType<'ctx>],
        llvm_type: inkwell::types::BasicTypeEnum<'ctx>,
    ) -> Option<DIType<'ctx>> {
        let key = format!("static {}", name);
        if let Some(&ty) = self.debug.as_ref()?.types.get(&key) {
            return Some(ty);
        }
        let inkwell::types::BasicTypeEnum::StructType(struct_type) = llvm_type else { return None };
        let target = crate::target::target_machine().ok()?.get_target_data();
        let size = target.get_abi_size(&struct_type) * 8;
        let debug = self.debug.as_mut()?;
        let file = debug.file_of(Loc::NONE);
        let scope = debug.unit_scope();
        let mut members = vec![];
        for (index, (field, ty)) in names.iter().zip(types).enumerate() {
            let offset = target.offset_of_element(&struct_type, index as u32).unwrap_or(0) * 8;
            let bits = ty.get_size_in_bits();
            members.push(debug.builder().create_member_type(scope, field, file, 0, bits, 0, offset, DIFlags::ZERO, *ty).as_type());
        }
        let ty = debug.builder().create_struct_type(scope, name, file, 0, size, 0, DIFlags::ZERO, None, &members, 0, None, &key).as_type();
        debug.types.insert(key, ty);
        Some(ty)
    }
}
