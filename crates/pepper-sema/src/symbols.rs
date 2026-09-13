//! Symbol table: port of `source/Sema/Transform.cpp:66-133`. Functions keyed
//! by name (later overwrites earlier), externs, structs by name + generic
//! `type.to_string()`, constructors under their (mangled) name, traits by name.

use crate::model::{ExternDef, FunctionDef, Module, StructDef, TraitDef};
use crate::type_name::TypeName;
use std::collections::HashMap;

#[derive(Debug, Default)]
pub struct SymbolTable {
    pub functions: HashMap<String, usize>,
    pub externs: HashMap<String, usize>,
    pub structs: HashMap<String, usize>,
    pub traits: HashMap<String, usize>,
}

impl SymbolTable {
    pub fn build(module: &Module) -> Self {
        let mut table = SymbolTable::default();
        for (idx, function) in module.functions.iter().enumerate() {
            table.functions.insert(function.name.clone(), idx);
        }
        for (idx, extern_function) in module.externs.iter().enumerate() {
            table.externs.insert(extern_function.name.clone(), idx);
        }
        for (idx, st) in module.structs.iter().enumerate() {
            table.structs.insert(st.name.clone(), idx);
            if st.ty.is_generic() {
                table.structs.insert(st.ty.to_string(), idx);
            }
        }
        for (idx, trait_def) in module.traits.iter().enumerate() {
            table.traits.insert(trait_def.name.clone(), idx);
        }
        table
    }

    pub fn function<'a>(&self, module: &'a Module, name: &str) -> Option<&'a FunctionDef> {
        self.functions.get(name).map(|&i| &module.functions[i])
    }

    pub fn extern_function<'a>(&self, module: &'a Module, name: &str) -> Option<&'a ExternDef> {
        self.externs.get(name).map(|&i| &module.externs[i])
    }

    pub fn struct_by_name<'a>(&self, module: &'a Module, name: &str) -> Option<&'a StructDef> {
        self.structs.get(name).map(|&i| &module.structs[i])
    }

    pub fn trait_by_name<'a>(&self, module: &'a Module, name: &str) -> Option<&'a TraitDef> {
        self.traits.get(name).map(|&i| &module.traits[i])
    }

    /// Type lookup: integral types resolve to themselves; known structs too
    /// (port of `SymbolTable::find(TypeName)`).
    pub fn find_type(&self, module: &Module, name: &TypeName) -> Option<TypeName> {
        if crate::type_name::INTEGRAL_TYPES.contains(name.to_string().as_str()) {
            return Some(name.clone());
        }
        if self.structs.contains_key(&name.to_string()) {
            return Some(name.clone());
        }
        let _ = module;
        None
    }
}
