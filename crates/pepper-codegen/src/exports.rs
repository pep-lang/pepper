//! The C entry points of `[Export]`ed functions (see
//! `pepper_sema::passes::exports`).
//!
//! Each export is a C-ABI function named by its C symbol that calls the
//! Pepper function, and each struct handle gets `<struct>_retain` and
//! `<struct>_release`, which step its count. Numbers, `bool`, pointers and
//! handles already have the C representation, so an entry point only
//! passes its arguments on; what it adds is the C symbol, default
//! visibility (and `dllexport` on Windows), and the widening C expects of
//! small integers.
//!
//! The program module defines them, never a file's unit: every program
//! links the program module, and a C program that links a static library
//! pulls it in through them, so its static constructor (which runs each
//! file's global initializer) runs too. Until then each is named
//! [`EXPORT_PREFIX`] and its C symbol, since a Pepper function of the same
//! name (`add`) keeps that name until [`crate::partition::finish`] spells it
//! for the linker (`_Padd`); `finish` then gives each entry point its C
//! symbol and leaves it external.

use crate::CodeGenerator;
use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::module::Linkage;
use inkwell::values::{BasicMetadataValueEnum, FunctionValue};
use inkwell::{DLLStorageClass, GlobalVisibility};
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::exports::small_integer_is_signed;
use pepper_sema::type_name::TypeName;

/// What a C entry point's name starts with until `partition::finish`
/// names it by its C symbol.
pub const EXPORT_PREFIX: &str = "__export.";

impl<'ctx> CodeGenerator<'ctx> {
    /// Define the entry point of every export and handle function, when
    /// this generator emits the program module (or the whole program).
    pub(crate) fn emit_exports(&mut self, module: &SemaModule) -> Result<(), String> {
        if self.unit.as_ref().is_some_and(|filter| filter.unit.is_some()) {
            return Ok(());
        }
        self.builder.unset_current_debug_location();
        for export in &module.exports.functions {
            let target = *self
                .functions
                .get(&export.function)
                .ok_or_else(|| format!("exported function '{}' has no code", export.symbol))?;
            let entry = self.export_function(&export.symbol, target.get_type())?;
            let parameters: Vec<&TypeName> = export.parameters.iter().map(|(_, ty)| ty).collect();
            self.widen_small_integers(entry, &parameters, &export.result);
            let block = self.context.append_basic_block(entry, "entry");
            self.builder.position_at_end(block);
            let arguments: Vec<BasicMetadataValueEnum<'ctx>> = entry.get_param_iter().map(Into::into).collect();
            let call = self.builder.build_call(target, &arguments, "").map_err(|e| e.to_string())?;
            match call.try_as_basic_value().basic() {
                Some(value) => self.builder.build_return(Some(&value)),
                None => self.builder.build_return(None),
            }
            .map_err(|e| e.to_string())?;
        }
        let pointer = self.context.ptr_type(inkwell::AddressSpace::default());
        let step = self.context.void_type().fn_type(&[pointer.into()], false);
        for handle in &module.exports.handles {
            for (symbol, retain) in [(&handle.retain, true), (&handle.release, false)] {
                let entry = self.export_function(symbol, step)?;
                let block = self.context.append_basic_block(entry, "entry");
                self.builder.position_at_end(block);
                let object = entry.get_nth_param(0).ok_or("a handle function has no parameter")?;
                if retain {
                    self.acquire_ref(&handle.structure, object)?;
                } else {
                    self.release_ref(&handle.structure, object)?;
                }
                self.builder.build_return(None).map_err(|e| e.to_string())?;
            }
        }
        Ok(())
    }

    /// Declare the C entry point `symbol`: external, visible outside the
    /// library, and exported from a Windows DLL.
    fn export_function(&mut self, symbol: &str, ty: inkwell::types::FunctionType<'ctx>) -> Result<FunctionValue<'ctx>, String> {
        if self.extern_names.contains(symbol) {
            return Err(format!("cannot export '{}': the program declares an extern of that name", symbol));
        }
        let name = format!("{}{}", EXPORT_PREFIX, symbol);
        let entry = self.module.add_function(&name, ty, Some(Linkage::External));
        let global = entry.as_global_value();
        global.set_visibility(GlobalVisibility::Default);
        if self.module.get_triple().as_str().to_string_lossy().contains("windows") {
            global.set_dll_storage_class(DLLStorageClass::Export);
        }
        self.exported.insert(name);
        Ok(entry)
    }

    /// Mark the parameters and result C widens (integers narrower than
    /// `int`, and `bool`) `signext` or `zeroext`, as clang does.
    fn widen_small_integers(&self, entry: FunctionValue<'ctx>, parameters: &[&TypeName], result: &TypeName) {
        let attribute = |signed: bool| {
            let name = if signed { "signext" } else { "zeroext" };
            self.context.create_enum_attribute(Attribute::get_named_enum_kind_id(name), 0)
        };
        for (index, ty) in parameters.iter().enumerate() {
            if let Some(signed) = small_integer_is_signed(ty) {
                entry.add_attribute(AttributeLoc::Param(index as u32), attribute(signed));
            }
        }
        if let Some(signed) = small_integer_is_signed(result) {
            entry.add_attribute(AttributeLoc::Return, attribute(signed));
        }
    }
}
