//! Compiling a program as one LLVM module per compilation unit (see the
//! build cache design, INTERNALS.md §4.3), so each unit becomes its own
//! object and an unchanged unit's object can come from the cache.
//!
//! Sema still runs over the whole program; the code generator then runs
//! once per unit with a [`UnitFilter`]. Every declaration is declared in
//! every unit, and:
//!
//! - a symbol with an owner ([`crate::CodeGenerator::owners`]: a declaration
//!   of some file) is defined only in its file's unit;
//! - every other body (instantiations such as `Array<int>.append`, the
//!   `_pep_copy` and `_pep_fix_weak` methods that `copy` synthesizes on
//!   demand, and code without a source location) is defined in each unit
//!   that calls it, and becomes `linkonce_odr`, in a comdat where the
//!   object format has them, so the linker keeps one copy, the way C++
//!   emits templates;
//! - each file's global initializer is defined in its unit, and only the
//!   program module (`unit: None`) defines `__pep_global_init` and
//!   `llvm.global_ctors`, which call them in initialization order.
//!
//! [`finish`] then fixes linkage, removes unused private helpers with
//! `globaldce`, and spells every symbol Pepper defined with
//! [`symbol_name`], so names with `@`, `<` or spaces survive every linker.
//! Private names (`helper@io/file`) become external with hidden visibility,
//! since an instantiation in another object may call them.

use inkwell::module::{Linkage, Module};
use inkwell::values::{AsValueRef, GlobalValue};
use inkwell::GlobalVisibility;
use std::collections::{HashMap, HashSet};

/// Which unit a [`crate::CodeGenerator`] emits.
#[derive(Debug, Clone)]
pub struct UnitFilter {
    /// Each file's unit, indexed like the module's sources.
    pub unit_of_file: Vec<usize>,
    /// The unit to emit, or `None` for the program module.
    pub unit: Option<usize>,
    /// Per file, whether the unit's code may depend on it (see
    /// `Program::unit_inputs`); empty for every file.
    pub inputs: Vec<bool>,
}

impl UnitFilter {
    /// Whether a declaration at `loc` is one of the unit's inputs.
    pub fn is_input(&self, loc: pepper_sema::model::Loc) -> bool {
        loc.is_none() || self.inputs.is_empty() || self.inputs.get(loc.file.0 as usize).copied().unwrap_or(false)
    }
}

/// Finish a unit's module: owned symbols are external (hidden unless
/// `main`), shared definitions `linkonce_odr`, unused private helpers are
/// removed, and every symbol a Pepper declaration defines anywhere in the
/// program (`owners`, or a definition in this module) gets its linker
/// spelling. The C entry points in `exported` stay external and get their
/// C symbols (see [`crate::exports`]).
pub fn finish(module: &Module<'_>, owners: &HashMap<String, u32>, exported: &HashSet<String>) -> Result<(), String> {
    let machine = crate::target::target_machine()?;
    let comdats = !machine.get_triple().as_str().to_string_lossy().contains("apple");
    let mut defined: HashSet<String> = owners.keys().cloned().collect();
    let mut values: Vec<GlobalValue<'_>> = module.get_functions().map(|f| f.as_global_value()).collect();
    values.extend(module.get_globals());
    for &value in &values {
        let symbol = name_of(value);
        if symbol.starts_with("llvm.") || exported.contains(&symbol) {
            continue;
        }
        let definition = !value.is_declaration();
        if definition {
            defined.insert(symbol.clone());
        }
        if owners.contains_key(&symbol) {
            value.set_linkage(Linkage::External);
            value.set_visibility(visibility(&symbol));
        } else if definition {
            set_shared_linkage(module, value, &symbol, comdats);
        }
    }
    module
        .run_passes("globaldce", &machine, inkwell::passes::PassBuilderOptions::create())
        .map_err(|e| format!("cannot finish unit: {}", e.to_string()))?;
    order_strings(module);
    for f in module.get_functions() {
        respell(module, f.as_global_value(), &defined);
    }
    for g in module.get_globals() {
        respell(module, g, &defined);
    }
    for f in module.get_functions() {
        let name = name_of(f.as_global_value());
        if let Some(symbol) = name.strip_prefix(crate::exports::EXPORT_PREFIX).filter(|_| exported.contains(&name)) {
            if module.get_function(symbol).is_some() {
                return Err(format!("cannot export '{}': the program already has a C symbol of that name", symbol));
            }
            f.as_global_value().set_name(symbol);
        }
    }
    module.verify().map_err(|e| format!("unit does not verify: {}", e.to_string()))
}

/// Put the unit's string constants in the order of their first use, walking
/// the functions in module order, and number them in that order. Code is
/// generated in an order that depends on the program around the unit (an
/// instantiation's body is generated when a caller first needs it), and a
/// constant is created with the code that uses it, so the creation order,
/// and with it the unit's bitcode and cache key, would otherwise depend on
/// the program too. Constants made for code this unit does not keep were
/// removed by `globaldce`, so they shift nothing either.
fn order_strings(module: &Module<'_>) {
    use inkwell::llvm_sys::core::*;
    use inkwell::llvm_sys::prelude::LLVMValueRef;
    let strings: Vec<GlobalValue<'_>> = module
        .get_globals()
        .filter(|g| matches!(g.get_linkage(), Linkage::Private | Linkage::Internal) && name_of(*g).starts_with("str"))
        .collect();
    let mut position: HashMap<LLVMValueRef, usize> =
        strings.iter().enumerate().map(|(i, g)| (g.as_value_ref(), i)).collect();
    let mut order: Vec<usize> = Vec::with_capacity(strings.len());
    for function in module.get_functions() {
        for block in function.get_basic_block_iter() {
            let mut instruction = block.get_first_instruction();
            while let Some(i) = instruction {
                for index in 0..i.get_num_operands() {
                    let operand = unsafe { LLVMGetOperand(i.as_value_ref(), index) };
                    if let Some(at) = position.remove(&operand) {
                        order.push(at);
                    }
                }
                instruction = i.get_next_instruction();
            }
        }
    }
    // Strings only other constants use keep their relative order, last.
    let mut rest: Vec<usize> = position.into_values().collect();
    rest.sort_unstable();
    order.extend(rest);
    // Re-create each constant at the end of the global list in that order,
    // so the module lists them in it too, not only names them by it.
    for (number, &at) in order.iter().enumerate() {
        let old = strings[at].as_value_ref();
        unsafe {
            let name = std::ffi::CString::new(format!("__str.{}", number)).unwrap();
            let new = LLVMAddGlobal(module.as_mut_ptr(), LLVMGlobalGetValueType(old), name.as_ptr());
            LLVMSetInitializer(new, LLVMGetInitializer(old));
            LLVMSetGlobalConstant(new, LLVMIsGlobalConstant(old));
            LLVMSetLinkage(new, LLVMGetLinkage(old));
            LLVMSetUnnamedAddress(new, LLVMGetUnnamedAddress(old));
            LLVMSetAlignment(new, LLVMGetAlignment(old));
            LLVMReplaceAllUsesWith(old, new);
            LLVMDeleteGlobal(old);
        }
    }
}

/// Linkage of a shared definition: `linkonce_odr`, except private helpers
/// that nothing outside the object can name.
fn set_shared_linkage<'ctx>(module: &Module<'ctx>, value: GlobalValue<'ctx>, symbol: &str, comdats: bool) {
    if matches!(value.get_linkage(), Linkage::Private | Linkage::Internal) && !is_shared_helper(symbol) {
        return;
    }
    value.set_linkage(Linkage::LinkOnceODR);
    if comdats {
        value.set_comdat(module.get_or_insert_comdat(symbol));
    }
    value.set_visibility(visibility(symbol));
}

/// Helpers that are private to one object today but must be one object in
/// the program: a function value's identity is its function object.
fn is_shared_helper(symbol: &str) -> bool {
    symbol.starts_with("__function_object.") || symbol.starts_with("__function_thunk.")
}

/// Hidden for a file's private name, and for every Pepper definition that
/// only this program links against, so none reaches a dynamic symbol table.
fn visibility(symbol: &str) -> GlobalVisibility {
    if symbol == "main" { GlobalVisibility::Default } else { GlobalVisibility::Hidden }
}

fn name_of(value: GlobalValue<'_>) -> String {
    value.get_name().to_string_lossy().into_owned()
}

/// Give a symbol Pepper defined its linker spelling (see [`symbol_name`]),
/// renaming its comdat with it.
fn respell<'ctx>(module: &Module<'ctx>, value: GlobalValue<'ctx>, defined: &HashSet<String>) {
    let name = name_of(value);
    if !defined.contains(&name) {
        return;
    }
    let spelled = symbol_name(&name);
    if spelled == name {
        return;
    }
    value.set_name(&spelled);
    if value.get_comdat().is_some() {
        value.set_comdat(module.get_or_insert_comdat(&spelled));
    }
}

/// The linker spelling of a Pepper symbol. `main`, and a member name of
/// letters, digits, `_` and `.` (`Point.length`), is its own spelling; any
/// other name is `_P` followed by the name with `_` doubled and every other
/// byte written as `_` and two hex digits (`Array<int>.count` is
/// `_PArray_3cint_3e.count`), so every spelling names one symbol and no
/// linker reads a `@` as a symbol version. A free function or global is
/// escaped even when plain (`exit` is `_Pexit`): a C library defines names
/// like `exit` and `read` too, and a statically linked C runtime (Windows)
/// would see two definitions. A dotted name cannot be a C symbol. A plain
/// name that starts with `_P` is escaped too, so it cannot collide with an
/// escaped one.
pub fn symbol_name(name: &str) -> String {
    let plain = name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'.');
    if name == "main" || (plain && name.contains('.') && !name.starts_with("_P")) {
        return name.to_string();
    }
    let mut out = String::from("_P");
    for b in name.bytes() {
        match b {
            b'_' => out.push_str("__"),
            b if b.is_ascii_alphanumeric() || b == b'.' => out.push(b as char),
            b => out.push_str(&format!("_{:02x}", b)),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::symbol_name;

    #[test]
    fn symbol_names() {
        assert_eq!(symbol_name("main"), "main");
        assert_eq!(symbol_name("Point.length"), "Point.length");
        assert_eq!(symbol_name("Array<int>.count"), "_PArray_3cint_3e.count");
        assert_eq!(symbol_name("helper@io/file"), "_Phelper_40io_2ffile");
        assert_eq!(symbol_name("a_b@x"), "_Pa__b_40x");
        assert_eq!(symbol_name("_Pfoo"), "_P__Pfoo");
        assert_eq!(symbol_name("exit"), "_Pexit");
        assert_eq!(symbol_name("_pep_malloc"), "_P__pep__malloc");
        assert_ne!(symbol_name("a_40"), symbol_name("a@"));
    }
}
