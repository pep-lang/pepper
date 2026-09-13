//! Port of `source/Sema/TagGenerics.h`: duplicate function names with generic
//! sub_types are specializations — rename to `type.to_string()`.

use crate::model::Module;
use std::collections::HashSet;

pub fn tag_generics(module: &mut Module) {
    let mut functions: HashSet<String> = HashSet::new();
    for function in &mut module.functions {
        if !functions.contains(&function.name) {
            functions.insert(function.name.clone());
            continue;
        }
        // If this isn't the first time this function name has been seen, then
        // this is a specialization.
        if !function.ty.sub_types.is_empty() {
            function.is_generic_func = false;
            function.name = function.ty.to_string();
        }
    }
}
