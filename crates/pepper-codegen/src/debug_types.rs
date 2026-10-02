//! Debug types for `-g` (see [`crate::debug`]): Pepper's numeric types as
//! base types under their Pepper names, raw pointers, a plain enum as an
//! enumeration, a tuple as a structure with members `0`, `1`, and so on, a
//! trait value as its object and vtable pointers, a struct reference
//! (which covers a generic's instantiation such as `Array<int>`, an enum
//! with payloads and a function type's object) as a pointer to a structure
//! type with every field, the `__refcount`/`__weakcount` head included, so
//! ownership bugs can be diagnosed in the debugger, and a value struct
//! (`[Value]`, such as `Optional<T>` and `Result<T>`) as the structure
//! itself, which has no head.
//!
//! Types refer to each other through fields and elements, in cycles too
//! (`struct Node { Node next; }`). A struct's type is built after its
//! fields' structs, from a work stack; a reference back to a struct or
//! tuple still being built is a declaration, which the debugger resolves
//! to the definition by name.

use crate::CodeGenerator;
use inkwell::debug_info::{DIFlags, DIFlagsConstants, DIType};
use inkwell::types::BasicTypeEnum;
use inkwell::AddressSpace;
use std::collections::HashSet;

// DWARF base type encodings (`DW_ATE_*`).
const BOOLEAN: u32 = 0x02;
const FLOAT: u32 = 0x04;
const SIGNED: u32 = 0x05;
const SIGNED_CHAR: u32 = 0x06;
const UNSIGNED: u32 = 0x07;
const UNSIGNED_CHAR: u32 = 0x08;

const POINTER_BITS: u64 = usize::BITS as u64;

/// The width and encoding of a Pepper numeric type.
fn scalar(name: &str) -> Option<(u64, u32)> {
    Some(match name {
        "bool" | "i1" => (8, BOOLEAN),
        "i8" | "char" => (8, SIGNED_CHAR),
        "u8" | "byte" => (8, UNSIGNED_CHAR),
        "i16" | "short" => (16, SIGNED),
        "u16" | "ushort" => (16, UNSIGNED),
        "i32" | "int" => (32, SIGNED),
        "u32" | "uint" => (32, UNSIGNED),
        "i64" | "long" => (64, SIGNED),
        "u64" | "ulong" => (64, UNSIGNED),
        "f32" | "float" => (32, FLOAT),
        "f64" | "double" => (64, FLOAT),
        _ => return None,
    })
}

/// The name a program writes for a numeric type sema spells by width
/// (an integer literal's `i32` is an `int`).
fn written(name: &str) -> &str {
    match name {
        "i1" => "bool",
        "i16" => "short",
        "u16" => "ushort",
        "i32" => "int",
        "u32" => "uint",
        "i64" => "long",
        "u64" => "ulong",
        "f32" => "float",
        "f64" => "double",
        other => other,
    }
}

impl<'ctx> CodeGenerator<'ctx> {
    /// The debug type of a value of sema type `name`, or `None` when debug
    /// info is off or does not describe it yet.
    pub(crate) fn debug_type(&mut self, name: &str) -> Option<DIType<'ctx>> {
        let debug = self.debug.as_ref()?;
        if let Some(&ty) = debug.types.get(name) {
            return Some(ty);
        }
        // `T**` is `T` behind two pointers: built from the inside out.
        let base = name.trim_end_matches('*');
        let pointers = name.len() - base.len();
        let base_type = if self.is_debug_struct(base) {
            self.debug_struct_reference(base)?
        } else if self.tuples.contains_key(base) {
            self.debug_tuple(base)?
        } else if self.is_trait_name(base) {
            self.debug_trait_value(base)
        } else {
            self.debug_value_type(base, pointers > 0)?
        };
        Some(self.debug_pointers(base, pointers, base_type))
    }

    /// Whether `name` is a struct the debug info describes as one: not a
    /// trait, a tuple or a function type's object.
    fn is_debug_struct(&self, name: &str) -> bool {
        self.structs.contains_key(name) && !self.is_trait_name(name) && !self.tuples.contains_key(name)
    }

    /// `ty` (the type of `base`) behind `pointers` raw pointers.
    fn debug_pointers(&mut self, base: &str, pointers: usize, mut ty: DIType<'ctx>) -> DIType<'ctx> {
        let mut spelled = base.to_string();
        for _ in 0..pointers {
            spelled.push('*');
            ty = self.debug_pointer(&spelled, ty);
        }
        ty
    }

    /// The type of `base` when it is not a struct: a number, a plain enum,
    /// or `void` behind a pointer (`pointee`).
    fn debug_value_type(&mut self, base: &str, pointee: bool) -> Option<DIType<'ctx>> {
        Some(if base == "void" && pointee {
            self.debug_base_type("void", 8, UNSIGNED_CHAR)
        } else if let Some((bits, encoding)) = scalar(base) {
            self.debug_base_type(written(base), bits, encoding)
        } else if self.debug.as_ref()?.enums.contains_key(base) {
            self.debug_enum(base)?
        } else if let Some(BasicTypeEnum::IntType(int)) = self.types.get(base) {
            self.debug_base_type(base, int.get_bit_width() as u64, SIGNED)
        } else {
            return None;
        })
    }

    fn debug_base_type(&mut self, name: &str, bits: u64, encoding: u32) -> DIType<'ctx> {
        let debug = self.debug.as_mut().expect("debug info");
        if let Some(&ty) = debug.types.get(name) {
            return ty;
        }
        let ty = debug.builder().create_basic_type(name, bits, encoding, DIFlags::ZERO).expect("base type").as_type();
        debug.types.insert(name.to_string(), ty);
        ty
    }

    fn debug_pointer(&mut self, name: &str, pointee: DIType<'ctx>) -> DIType<'ctx> {
        let debug = self.debug.as_mut().expect("debug info");
        if let Some(&ty) = debug.types.get(name) {
            return ty;
        }
        let ty = debug.builder().create_pointer_type(name, pointee, POINTER_BITS, 0, AddressSpace::default()).as_type();
        debug.types.insert(name.to_string(), ty);
        ty
    }

    /// A reference to the struct `name`: a pointer to its structure type.
    /// Structs reach each other through fields to any depth (and in
    /// cycles), so their types are built from a work stack, after the
    /// structs their fields name; a field naming a struct still being
    /// built points at a declaration of it, which the debugger resolves to
    /// the definition by name.
    fn debug_struct_reference(&mut self, name: &str) -> Option<DIType<'ctx>> {
        if self.debug.as_ref()?.building.contains(name) {
            return Some(self.debug_declaration(name));
        }
        let mut building: HashSet<String> = HashSet::new();
        let mut stack = vec![(name.to_string(), false)];
        while let Some((current, fields_done)) = stack.pop() {
            if self.debug.as_ref()?.types.contains_key(&current) {
                continue;
            }
            if !fields_done {
                building.insert(current.clone());
                self.debug.as_mut()?.building.insert(current.clone());
                stack.push((current.clone(), true));
                for (_, field) in &self.structs[&current].fields {
                    let base = field.trim_end_matches('*');
                    if self.is_debug_struct(base) && !building.contains(base) && !self.debug.as_ref()?.types.contains_key(base) {
                        stack.push((base.to_string(), false));
                    }
                }
                continue;
            }
            let ty = self.debug_structure(&current);
            building.remove(&current);
            self.debug.as_mut()?.building.remove(&current);
            if self.values.contains_key(&current) {
                // A value struct is held inline: the structure itself.
                self.debug.as_mut()?.types.insert(current, ty);
                continue;
            }
            // Named as the user writes the type: a reference is the struct.
            let display = pepper_parser::namespace::demangle_name(&current).to_string();
            let debug = self.debug.as_mut()?;
            let reference = debug.builder().create_pointer_type(&display, ty, POINTER_BITS, 0, AddressSpace::default()).as_type();
            debug.types.insert(current, reference);
        }
        self.debug.as_ref()?.types.get(name).copied()
    }

    /// The structure type of the struct `name`, whose fields' structs are
    /// built already or being built.
    fn debug_structure(&mut self, name: &str) -> DIType<'ctx> {
        let desc = &self.structs[name];
        let (llvm_type, loc, size) = (desc.llvm_type, desc.loc, desc.size);
        let fields: Vec<(String, String, pepper_sema::model::Loc)> = desc
            .fields
            .iter()
            .zip(desc.field_locs.iter())
            .map(|((field, ty), loc)| (field.clone(), ty.clone(), *loc))
            .collect();
        let display = pepper_parser::namespace::demangle_name(name).to_string();
        let target = crate::target::host_machine().expect("host target machine").get_target_data();
        let mut members = vec![];
        for (index, (field, ty, field_loc)) in fields.iter().enumerate() {
            // A field's struct is built already, or is being built: never
            // build one from here, which would recurse as deep as the
            // structs nest.
            let base = ty.trim_end_matches('*');
            let member_type = if self.is_debug_struct(base) {
                let known = self.debug.as_ref().expect("debug info").types.get(base).copied();
                let reference = known.unwrap_or_else(|| self.debug_declaration(base));
                Some(self.debug_pointers(base, ty.len() - base.len(), reference))
            } else {
                self.debug_type(ty)
            };
            let Some(member_type) = member_type else { continue };
            let offset = target.offset_of_element(&llvm_type, index as u32).unwrap_or(0) * 8;
            let debug = self.debug.as_mut().expect("debug info");
            let file = debug.file_of(*field_loc);
            let line = debug.line_column(*field_loc).map_or(0, |(line, _)| line);
            let scope = debug.unit_scope();
            let bits = member_type.get_size_in_bits();
            // An enum's payload field `Case.value` is `Case__value`: a
            // debugger's expressions and natvis cannot name a member with a
            // dot in it.
            let field = field.replace('.', "__");
            let member = debug.builder().create_member_type(scope, &field, file, line, bits, 0, offset, DIFlags::ZERO, member_type);
            members.push(member.as_type());
        }
        let debug = self.debug.as_mut().expect("debug info");
        let file = debug.file_of(loc);
        let line = debug.line_column(loc).map_or(0, |(line, _)| line);
        let scope = debug.unit_scope();
        debug
            .builder()
            .create_struct_type(scope, &display, file, line, size * 8, 0, DIFlags::ZERO, None, &members, 0, None, name)
            .as_type()
    }

    /// A struct or tuple whose type is still being built: a declaration of
    /// it, behind a pointer for a struct reference. A value (a tuple or a
    /// value struct) is held inline, so its declaration carries its size.
    fn debug_declaration(&mut self, name: &str) -> DIType<'ctx> {
        let display = pepper_parser::namespace::demangle_name(name).to_string();
        let size = if self.values.contains_key(name) {
            Some(self.structs[name].size * 8)
        } else if self.tuples.contains_key(name) {
            let target = crate::target::host_machine().expect("host target machine").get_target_data();
            self.types.get(name).map(|ty| target.get_abi_size(&ty) * 8)
        } else {
            None
        };
        let debug = self.debug.as_mut().expect("debug info");
        let scope = debug.unit_scope();
        let file = debug.file_of(pepper_sema::model::Loc::NONE);
        let declared = debug
            .builder()
            .create_struct_type(scope, &display, file, 0, size.unwrap_or(0), 0, DIFlags::FWD_DECL, None, &[], 0, None, name)
            .as_type();
        if size.is_some() {
            return declared;
        }
        debug.builder().create_pointer_type(&display, declared, POINTER_BITS, 0, AddressSpace::default()).as_type()
    }

    /// A plain enum: an enumeration of its cases over its representation.
    fn debug_enum(&mut self, name: &str) -> Option<DIType<'ctx>> {
        let (loc, representation, cases) = self.debug.as_ref()?.enums.get(name)?.clone();
        let (bits, encoding) = scalar(&representation)?;
        let underlying = self.debug_base_type(&representation, bits, encoding);
        let display = pepper_parser::namespace::demangle_name(name).to_string();
        let debug = self.debug.as_mut()?;
        let unsigned = encoding == UNSIGNED || encoding == UNSIGNED_CHAR;
        let enumerators: Vec<_> = cases.iter().map(|(case, value)| debug.builder().create_enumerator(case, *value, unsigned)).collect();
        let file = debug.file_of(loc);
        let line = debug.line_column(loc).map_or(0, |(line, _)| line);
        let scope = debug.unit_scope();
        let ty = debug.builder().create_enumeration_type(scope, &display, file, line, bits, 0, &enumerators, underlying).as_type();
        debug.types.insert(name.to_string(), ty);
        Some(ty)
    }

    /// A tuple: a structure with a member per element, named `0`, `1`, and
    /// so on. An element that leads back to the tuple, through a struct, is
    /// a declaration (see the module comment).
    fn debug_tuple(&mut self, name: &str) -> Option<DIType<'ctx>> {
        if self.debug.as_ref()?.building.contains(name) {
            return Some(self.debug_declaration(name));
        }
        let elements = self.tuples.get(name)?.clone();
        let llvm_type = self.types.get(name)?.into_struct_type();
        self.debug.as_mut()?.building.insert(name.to_string());
        let target = crate::target::host_machine().expect("host target machine").get_target_data();
        let mut members = vec![];
        for (index, element) in elements.iter().enumerate() {
            let Some(element_type) = self.debug_type(element) else { continue };
            let offset = target.offset_of_element(&llvm_type, index as u32).unwrap_or(0) * 8;
            let debug = self.debug.as_mut()?;
            let (scope, file) = (debug.unit_scope(), debug.file_of(pepper_sema::model::Loc::NONE));
            let bits = element_type.get_size_in_bits();
            let member = debug.builder().create_member_type(scope, &index.to_string(), file, 0, bits, 0, offset, DIFlags::ZERO, element_type);
            members.push(member.as_type());
        }
        let size = target.get_abi_size(&llvm_type) * 8;
        let display = pepper_sema::passes::gather_generics::parse_type_string(name).display();
        let display = pepper_parser::namespace::demangle(&display).into_owned();
        let debug = self.debug.as_mut()?;
        debug.building.remove(name);
        let (scope, file) = (debug.unit_scope(), debug.file_of(pepper_sema::model::Loc::NONE));
        let ty = debug.builder().create_struct_type(scope, &display, file, 0, size, 0, DIFlags::ZERO, None, &members, 0, None, name).as_type();
        debug.types.insert(name.to_string(), ty);
        Some(ty)
    }

    /// A trait value (`Shape`): the object it refers to and its vtable.
    fn debug_trait_value(&mut self, name: &str) -> DIType<'ctx> {
        let byte = self.debug_base_type("void", 8, UNSIGNED_CHAR);
        let pointer = self.debug_pointers("void", 1, byte);
        let display = pepper_parser::namespace::demangle_name(name).to_string();
        let debug = self.debug.as_mut().expect("debug info");
        let (scope, file) = (debug.unit_scope(), debug.file_of(pepper_sema::model::Loc::NONE));
        let members: Vec<DIType<'ctx>> = ["object", "vtable"]
            .iter()
            .enumerate()
            .map(|(i, member)| {
                let offset = i as u64 * POINTER_BITS;
                debug.builder().create_member_type(scope, member, file, 0, POINTER_BITS, 0, offset, DIFlags::ZERO, pointer).as_type()
            })
            .collect();
        let ty = debug
            .builder()
            .create_struct_type(scope, &display, file, 0, 2 * POINTER_BITS, 0, DIFlags::ZERO, None, &members, 0, None, name)
            .as_type();
        debug.types.insert(name.to_string(), ty);
        ty
    }
}
