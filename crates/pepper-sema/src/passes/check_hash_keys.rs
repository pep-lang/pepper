//! Struct keys whose `==` and `hash<T>` disagree. `HashMap` and `HashSet`
//! find a key by `hash<K>` and then `==`, so keys that are `==` must hash
//! equally. A struct used as a key (any specialization of the runtime's
//! `_HashTable<K, V>`, which both containers hold) that declares an `==`
//! operator for itself but no `hash<K>` override keeps the identity (or,
//! for a value struct, field-by-field) hash, which equal keys rarely share:
//! lookups then miss entries that are there. A reference struct with a
//! `hash<K>` override but no `==` still compares keys by identity, so equal
//! keys never find each other. Both are errors, at the declaration to
//! complete; each struct is reported once. Runtime structs (`Array`, whose
//! `==` compares elements but whose hash is its identity) are not checked:
//! the program cannot change them.

use crate::model::*;
use pepper_parser::diagnostic::Diagnostic;
use std::collections::HashSet;

/// The runtime struct both hash containers keep their entries in.
const TABLE: &str = "_HashTable";

pub fn check_hash_keys(module: &mut Module) {
    let keys: HashSet<String> = module
        .structs
        .iter()
        .filter(|st| st.ty.name == TABLE)
        .filter_map(|st| st.ty.sub_types.first().map(|k| k.to_string()))
        .collect();
    let runtime = super::RuntimeDirectory::default();
    let mut errors = vec![];
    // An `[Equatable]` struct's hash is derived with its `==`; an override
    // would replace one half.
    for st in module.structs.iter().filter(|st| is_derived(st)) {
        let hash_name = format!("hash<{}>", st.name);
        if let Some(hash) = module.functions.iter().find(|f| f.name == hash_name && f.generic_params.is_empty()) {
            errors.push(
                Diagnostic::error(format!(
                    "'{}' is '[{}]', so its hash is derived and '{hash_name}' cannot be overridden",
                    st.name,
                    crate::equatable::EQUATABLE_ATTRIBUTE
                ))
                .at(hash.loc)
                .with_note(
                    format!(
                        "remove this override, or remove '[{}]' to declare both '==' and 'hash' by hand",
                        crate::equatable::EQUATABLE_ATTRIBUTE
                    ),
                    None,
                )
                .with_note(format!("'{}' declared here", st.name), Some(st.loc)),
            );
        }
    }
    let mut sorted: Vec<&String> = keys.iter().collect();
    sorted.sort();
    for key in sorted {
        let Some(st) = module.structs.iter().find(|st| &st.name == key) else {
            continue;
        };
        if runtime.contains(module, st.loc.file) {
            continue;
        }
        let equality = st
            .method_members
            .iter()
            .find(|m| m.name == "==" && m.parameters.len() == 1 && m.parameters[0].ty.to_string() == *key);
        let hash_name = format!("hash<{}>", key);
        // An override declares no type parameters; the generic `hash<T>`'s
        // own specialization for `key` has the same name but keeps them.
        let hash = module.functions.iter().find(|f| f.name == hash_name && f.generic_params.is_empty());
        let is_value = st.is_value();
        if is_derived(st) {
            continue;
        }
        match (equality, hash) {
            (Some(equality), None) => errors.push(
                Diagnostic::error(format!(
                    "'{key}' declares '==' but no '{hash_name}', so as a HashMap or HashSet key, equal values will not find each other"
                ))
                .at(equality.loc)
                .with_note(
                    format!(
                        "declare '{hash_name}(value: {key}): u64' hashing the fields '==' compares, or remove '==' and mark '{key}' '[{}]' to derive both",
                        crate::equatable::EQUATABLE_ATTRIBUTE
                    ),
                    None,
                ),
            ),
            (None, Some(hash)) if !is_value => errors.push(
                Diagnostic::error(format!(
                    "'{hash_name}' is overridden but '{key}' declares no '==', so HashMap and HashSet keys still compare by identity"
                ))
                .at(hash.loc)
                .with_note(
                    format!(
                        "declare '==(other: {key}): bool' comparing the fields the hash uses, or remove the override and mark '{key}' '[{}]' to derive both",
                        crate::equatable::EQUATABLE_ATTRIBUTE
                    ),
                    Some(st.loc),
                ),
            ),
            _ => {}
        }
    }
    for error in errors {
        crate::errors::report(error);
    }
}

/// Whether `st` is `[Equatable]`: its `==` and hash are derived together.
fn is_derived(st: &StructDef) -> bool {
    st.method_members.iter().any(|m| m.name == crate::equatable::HASH_METHOD)
}
