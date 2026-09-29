//! LLVM type registry: port of `source/Sema/Types.{h,cpp}` +
//! `source/CodeGen/LLVM` struct-type handling.

use inkwell::context::Context;
use inkwell::types::{BasicMetadataTypeEnum, BasicType, BasicTypeEnum, StructType};
use pepper_sema::model::StructDef;
use pepper_sema::type_name::TypeName;
use std::collections::HashMap;

/// Registry of LLVM types keyed by Pepper type name.
pub struct Types<'ctx> {
    pub context: &'ctx Context,
    struct_types: HashMap<String, StructType<'ctx>>,
    /// Traits used as types: a value is `[2 x ptr]` (object, vtable),
    /// passed and stored by value. An array rather than a struct type keeps
    /// it apart from struct references, which lower to pointers.
    trait_types: HashMap<String, BasicTypeEnum<'ctx>>,
}

/// Integral-type aliases (same set as sema `TypeName::IntegralTypes`).
fn scalar_type<'ctx>(context: &'ctx Context, name: &str) -> Option<BasicTypeEnum<'ctx>> {
    Some(match name {
        "bool" => BasicTypeEnum::IntType(context.bool_type()),
        "i1" => BasicTypeEnum::IntType(context.bool_type()),
        "i8" | "char" => BasicTypeEnum::IntType(context.i8_type()),
        "u8" | "byte" => BasicTypeEnum::IntType(context.i8_type()),
        "i16" | "short" => BasicTypeEnum::IntType(context.i16_type()),
        "u16" | "ushort" => BasicTypeEnum::IntType(context.i16_type()),
        "i32" | "int" => BasicTypeEnum::IntType(context.i32_type()),
        "u32" | "uint" => BasicTypeEnum::IntType(context.i32_type()),
        "i64" | "long" => BasicTypeEnum::IntType(context.i64_type()),
        "u64" | "ulong" => BasicTypeEnum::IntType(context.i64_type()),
        "f32" | "float" => BasicTypeEnum::FloatType(context.f32_type()),
        "f64" | "double" => BasicTypeEnum::FloatType(context.f64_type()),
        "void" | "__auto" => BasicTypeEnum::IntType(context.i32_type()),
        _ => {
            // Pointer types: `T*`, `void*`.
            if name.ends_with('*') {
                return Some(BasicTypeEnum::PointerType(context.i8_type().ptr_type(inkwell::AddressSpace::default())));
            }
            return None;
        }
    })
}

impl<'ctx> Types<'ctx> {
    pub fn new(context: &'ctx Context) -> Self {
        Types {
            context,
            struct_types: HashMap::new(),
            trait_types: HashMap::new(),
        }
    }

    /// Resolve a Pepper type name to an LLVM type; structs must have been
    /// registered first.
    pub fn get(&self, name: &str) -> Option<BasicTypeEnum<'ctx>> {
        if let Some(ty) = self.trait_types.get(name) {
            return Some(*ty);
        }
        if let Some(st) = self.struct_types.get(name) {
            return Some(BasicTypeEnum::StructType(*st));
        }
        // Specialized struct name `Name<a, b>` maps to its declared base name.
        let base = name.split('<').next().unwrap_or(name);
        if let Some(st) = self.struct_types.get(base) {
            return Some(BasicTypeEnum::StructType(*st));
        }
        scalar_type(self.context, name)
    }

    /// Register a trait used as a type: `[2 x ptr]` (object, vtable).
    pub fn register_trait(&mut self, name: &str) {
        let ptr = self.context.ptr_type(inkwell::AddressSpace::default());
        self.trait_types
            .insert(name.to_string(), ptr.array_type(2).into());
    }

    /// Whether `name` is a registered trait type.
    pub fn is_trait(&self, name: &str) -> bool {
        self.trait_types.contains_key(name)
    }

    /// Metadata variant of [`Types::get`].
    pub fn get_meta(&self, name: &str) -> Option<BasicMetadataTypeEnum<'ctx>> {
        self.get(name).map(|t| t.into())
    }

    /// Register a struct type from its field types (port of
    /// `StructGen`'s `StructType::create(fieldTypes, name)`). Reuses the
    /// opaque type created by [`ensure_opaque`] so the LLVM name stays
    /// unique (`LLVMContext` disambiguates duplicate names with `.1`).
    pub fn register_struct(&mut self, st: &StructDef, field_types: &[BasicTypeEnum<'ctx>]) {
        let struct_ty = self.ensure_opaque(&st.name);
        struct_ty.set_body(field_types, false);
    }

    /// Opaque (body-less) struct type for a name, created once per name.
    pub fn ensure_opaque(&mut self, name: &str) -> StructType<'ctx> {
        if let Some(st) = self.struct_types.get(name) {
            return *st;
        }
        let struct_ty = self.context.opaque_struct_type(name);
        self.struct_types.insert(name.to_string(), struct_ty);
        struct_ty
    }

    /// The struct type for a (possibly specialized) name.
    pub fn struct_type(&self, name: &str) -> Option<StructType<'ctx>> {
        self.struct_types
            .get(name)
            .copied()
            .or_else(|| {
                let base = name.split('<').next().unwrap_or(name);
                self.struct_types.get(base).copied()
            })
    }
}

/// LLVM type of a sema TypeName (port of `Types::get(TypeName)`).
pub fn type_of<'ctx>(types: &Types<'ctx>, ty: &TypeName) -> Option<BasicTypeEnum<'ctx>> {
    types.get(&ty.to_string())
}
