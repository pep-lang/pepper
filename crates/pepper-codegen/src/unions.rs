//! A value enum's union layout (#392): a `[Value] enum` is its tag followed
//! by one storage that every case's values share, so it is as large as its
//! largest case plus the tag, not as all its cases together:
//!
//! ```text
//! [Value] enum Shape { Empty, Circle(radius: double), Label(text: String, size: int) }
//! %value.Shape = type { i32, [2 x i64] }      ; __tag, then the storage
//! Circle's values: { double }                 ; laid over the storage
//! Label's values:  { ptr, i32 }               ; laid over the same storage
//! ```
//!
//! Sema keeps a field per case value (`Circle.radius`, `Label.text`), so
//! everything that names a field is unchanged; only where a field lives
//! differs. Its address is the storage's, then the field's within its
//! case's struct ([`CodeGenerator::field_address`]). Only the case the tag
//! names holds live values: the others' fields read the same bytes as
//! something else. So whatever goes through every field (acquiring and
//! releasing the references a copy holds, `==`, `hash`) switches on the tag
//! and visits the fields of that case alone
//! ([`CodeGenerator::switch_on_case`]), and the constructor stores only the
//! named case's values (`struct_body::finish`).
//!
//! The storage is an array of the integer as wide as the strictest
//! alignment among the case values (of a vector, when that is wider than
//! 8 bytes), so the enum is aligned as its strictest value; the tag is
//! held apart from it, as the first field, so reading it never depends on
//! the case.

use crate::CodeGenerator;
use inkwell::types::{BasicType, BasicTypeEnum, StructType};
use inkwell::values::{BasicValueEnum, IntValue, PointerValue, StructValue};
use pepper_sema::model::StructDef;

/// Where the fields of a value enum live (see the module comment).
pub(crate) struct UnionLayout<'ctx> {
    /// For each field, in declaration order (the tag first): `None` for the
    /// tag, the struct's own field 0; else the struct of the field's case,
    /// laid over the storage, and the field's index in it.
    pub fields: Vec<Option<(StructType<'ctx>, u32)>>,
    /// The cases that carry values: each one's tag and its fields' indices
    /// among `fields`.
    pub cases: Vec<(i64, Vec<usize>)>,
}

impl<'ctx> CodeGenerator<'ctx> {
    /// Plan value enum `st`'s layout from the slot type of each of its
    /// fields. Its LLVM body is set by [`Self::finish_unions`], once the
    /// values it holds inline have bodies to measure.
    pub(crate) fn plan_union(&mut self, st: &StructDef, slots: &[BasicTypeEnum<'ctx>]) {
        let cases = st.enum_cases.as_deref().unwrap_or_default();
        let mut fields: Vec<Option<(StructType<'ctx>, u32)>> = vec![None; slots.len()];
        let mut payloads = vec![];
        for case in cases.iter().filter(|c| !c.payload.is_empty()) {
            let indices: Vec<usize> = case
                .payload
                .iter()
                .filter_map(|(value, _)| {
                    let name = pepper_sema::model::payload_field(&case.name, value);
                    st.field_members.iter().position(|f| f.name == name)
                })
                .collect();
            let types: Vec<BasicTypeEnum<'ctx>> = indices.iter().map(|&i| slots[i]).collect();
            let case_type = self.context.struct_type(&types, false);
            for (position, &index) in indices.iter().enumerate() {
                fields[index] = Some((case_type, position as u32));
            }
            payloads.push((case.value, indices));
        }
        self.unions.insert(st.name.clone(), UnionLayout { fields, cases: payloads });
        if !self.pending_unions.contains(&st.name) {
            self.pending_unions.push(st.name.clone());
        }
    }

    /// Set the body of every planned value enum: its tag, then a storage
    /// that fits each case's values. A case can hold another value enum or
    /// a value struct holding one, inline; such an enum is measured once
    /// the one it holds has a body. Value enums cannot hold themselves, so
    /// each pass sets at least one body until none is left.
    pub(crate) fn finish_unions(&mut self) -> Result<(), String> {
        let machine = crate::target::target_machine()?;
        let target = machine.get_target_data();
        let mut pending = std::mem::take(&mut self.pending_unions);
        while !pending.is_empty() {
            let before = pending.len();
            pending.retain(|name| {
                let Some(llvm_type) = self.types.struct_type(name) else { return false };
                // Every spelling of one enum (`Result<int>`, `Result<int,
                // Error>`) shares its type, set once.
                if !llvm_type.is_opaque() {
                    return false;
                }
                let layout = &self.unions[name];
                let mut case_types: Vec<StructType<'ctx>> = layout.fields.iter().flatten().map(|(case, _)| *case).collect();
                case_types.dedup();
                if !case_types.iter().all(|case| case.is_sized()) {
                    return true;
                }
                let tag = self.context.i32_type().as_basic_type_enum();
                let size = case_types.iter().map(|case| target.get_abi_size(case)).max().unwrap_or(0);
                // The case value aligned the strictest; an empty storage
                // when no case carries anything.
                let strictest = case_types
                    .iter()
                    .flat_map(|case| case.get_field_types())
                    .max_by_key(|ty| (target.get_abi_alignment(ty), std::cmp::Reverse(target.get_abi_size(ty))));
                let unit: BasicTypeEnum<'ctx> = match strictest {
                    Some(ty) if target.get_abi_alignment(&ty) > 8 => ty,
                    Some(ty) => match target.get_abi_alignment(&ty) {
                        8 => self.context.i64_type().into(),
                        4 => self.context.i32_type().into(),
                        2 => self.context.i16_type().into(),
                        _ => self.context.i8_type().into(),
                    },
                    None => self.context.i8_type().into(),
                };
                let unit_size = target.get_abi_size(&unit).max(1);
                let storage = unit.array_type(size.div_ceil(unit_size) as u32);
                llvm_type.set_body(&[tag, storage.into()], false);
                false
            });
            if pending.len() == before {
                return Err(format!("cannot lay out value enum '{}': it holds itself", pending[0]));
            }
        }
        Ok(())
    }

    /// The address of field `index` of the struct `name` whose storage is at
    /// `base`, and the LLVM type of its slot. A value enum's case value is
    /// inside the storage its cases share.
    pub(crate) fn field_address(
        &self,
        name: &str,
        llvm_type: StructType<'ctx>,
        base: PointerValue<'ctx>,
        index: usize,
        label: &str,
    ) -> Result<(PointerValue<'ctx>, BasicTypeEnum<'ctx>), String> {
        let Some((case, position)) = self.unions.get(name).and_then(|layout| layout.fields.get(index).copied().flatten()) else {
            let slot = llvm_type.get_field_type_at_index(index as u32).ok_or_else(|| format!("no field {} in '{}'", index, name))?;
            let address = self.builder.build_struct_gep(llvm_type, base, index as u32, label).map_err(|e| e.to_string())?;
            return Ok((address, slot));
        };
        let storage = self.builder.build_struct_gep(llvm_type, base, 1, "storage").map_err(|e| e.to_string())?;
        let address = self.builder.build_struct_gep(case, storage, position, label).map_err(|e| e.to_string())?;
        let slot = case.get_field_type_at_index(position).ok_or("bad case field")?;
        Ok((address, slot))
    }

    /// The offset in bytes of field `index` of the struct `name` (see
    /// [`Self::field_address`]).
    pub(crate) fn field_offset(&self, name: &str, llvm_type: StructType<'ctx>, index: usize) -> Option<u64> {
        let machine = crate::target::target_machine().ok()?;
        let target = machine.get_target_data();
        let Some((case, position)) = self.unions.get(name).and_then(|layout| layout.fields.get(index).copied().flatten()) else {
            return target.offset_of_element(&llvm_type, index as u32);
        };
        Some(target.offset_of_element(&llvm_type, 1)? + target.offset_of_element(&case, position)?)
    }

    /// Field `index` of `value`, a value of the struct `name` held in a
    /// register. A value enum's case value is read through a stack copy:
    /// the storage's integers are no case's values until read as them.
    pub(crate) fn extract_field(&mut self, name: &str, value: StructValue<'ctx>, index: usize, label: &str) -> Result<BasicValueEnum<'ctx>, String> {
        if !self.unions.contains_key(name) || index == 0 {
            return self.builder.build_extract_value(value, index as u32, label).map_err(|e| e.to_string());
        }
        let llvm_type = value.get_type();
        let copy = self.entry_alloca(llvm_type.into(), "enum_value")?;
        self.builder.build_store(copy, value).map_err(|e| e.to_string())?;
        let (address, slot) = self.field_address(name, llvm_type, copy, index, label)?;
        self.builder.build_load(slot, address, label).map_err(|e| e.to_string())
    }

    /// Branch on the tag of `value`, a value of value enum `name`: in a
    /// block for each case that carries values, `each` runs with that
    /// case's field indices and gives the case's result. A case that carries
    /// nothing gives `none`. The result is the case's, merged after the
    /// branch.
    pub(crate) fn switch_on_case(
        &mut self,
        name: &str,
        value: StructValue<'ctx>,
        none: IntValue<'ctx>,
        mut each: impl FnMut(&mut Self, &[usize]) -> Result<IntValue<'ctx>, String>,
    ) -> Result<IntValue<'ctx>, String> {
        let cases = self.unions.get(name).map(|layout| layout.cases.clone()).unwrap_or_default();
        let function = self.builder.get_insert_block().and_then(|b| b.get_parent()).ok_or("no function")?;
        let tag = self.builder.build_extract_value(value, 0, "tag").map_err(|e| e.to_string())?.into_int_value();
        let start = self.builder.get_insert_block().ok_or("no block")?;
        let merge = self.context.append_basic_block(function, "case_done");
        let mut incoming: Vec<(IntValue<'ctx>, inkwell::basic_block::BasicBlock<'ctx>)> = vec![(none, start)];
        let mut targets = vec![];
        for (case_tag, indices) in cases {
            let block = self.context.append_basic_block(function, "case");
            targets.push((tag.get_type().const_int(case_tag as u64, true), block));
            self.builder.position_at_end(block);
            let result = each(self, &indices)?;
            let end = self.builder.get_insert_block().ok_or("no block")?;
            self.builder.build_unconditional_branch(merge).map_err(|e| e.to_string())?;
            incoming.push((result, end));
        }
        self.builder.position_at_end(start);
        self.builder.build_switch(tag, merge, &targets).map_err(|e| e.to_string())?;
        self.builder.position_at_end(merge);
        let phi = self.builder.build_phi(none.get_type(), "case_result").map_err(|e| e.to_string())?;
        for (result, block) in &incoming {
            phi.add_incoming(&[(result, *block)]);
        }
        Ok(phi.as_basic_value().into_int_value())
    }

    /// The sema type of field `index` of value struct `name`.
    pub(crate) fn field_type_name(&self, name: &str, index: usize) -> String {
        self.values.get(name).and_then(|fields| fields.get(index)).cloned().unwrap_or_default()
    }
}
