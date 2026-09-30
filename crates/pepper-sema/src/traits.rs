//! Traits used as types (`Shape s`, `Array<Shape>`, `Iterator<int>`).
//!
//! A value of trait type is a struct reference whose concrete type is
//! erased: codegen represents it as `{ object, vtable }` and calls its
//! methods through the vtable of the struct's conformance to the trait. This
//! module answers the questions the passes ask about such types: is a type a
//! trait, what can be called through it, and does a struct conform to it.

use crate::model::{FunctionDef, Module, TraitDef, TraitType};
use crate::passes::specialize_structs::substitute;
use crate::type_name::TypeName;

/// The trait a type names, when it names one: a plain (non-pointer,
/// non-function) type whose name is a declared trait.
pub fn trait_def<'a>(traits: &'a [TraitDef], ty: &TypeName) -> Option<&'a TraitDef> {
    if !ty.is_scalar() || ty.is_pointer() {
        return None;
    }
    traits.iter().find(|t| t.name == ty.name)
}

/// Whether `ty` is a trait used as a type.
pub fn is_trait_type(traits: &[TraitDef], ty: &TypeName) -> bool {
    trait_def(traits, ty).is_some()
}

/// Whether a signature type names the implementing type (`this`), which a
/// value of trait type does not know.
fn mentions_this(ty: &TypeName) -> bool {
    ty.name == "this"
        || ty.name.trim_end_matches('*') == "this"
        || ty.sub_types.iter().any(mentions_this)
}

/// Whether a trait member can be called through a value of the trait type:
/// an instance method whose signature does not name `this` as a type, and
/// that has no type parameters of its own (a vtable holds one function per
/// member, not one per specialization).
pub fn is_dispatchable(method: &FunctionDef) -> bool {
    !method.is_static
        && !method.is_generic_func
        && !mentions_this(&method.ty)
        && !method.parameters.iter().any(|p| mentions_this(&p.ty))
}

/// `def` specialized at `ty`'s type arguments, keeping only the members a
/// value can call, in declaration order (their vtable order).
pub fn instance(def: &TraitDef, ty: &TypeName) -> TraitType {
    let type_map: Vec<(String, TypeName)> = def
        .generic_params
        .iter()
        .enumerate()
        .filter_map(|(idx, param)| {
            let arg = ty
                .sub_types
                .get(idx)
                .cloned()
                .or_else(|| param.default.clone())?;
            Some((param.name.clone(), arg))
        })
        .collect();
    let methods = def
        .methods
        .iter()
        .filter(|m| is_dispatchable(m))
        .map(|m| {
            let mut method = m.clone();
            method.body = None;
            substitute(&mut method.ty, &type_map);
            for param in &mut method.parameters {
                substitute(&mut param.ty, &type_map);
            }
            method
        })
        .collect();
    TraitType {
        ty: ty.clone(),
        methods,
    }
}

/// Every trait type the module uses as a value type: in fields, signatures,
/// locals, globals and conversions, including through pointers (`Shape*`,
/// the buffer of an `Array<Shape>`) and generic arguments. Generic bases are
/// skipped; their specializations carry the concrete types.
pub fn used_trait_types(module: &Module) -> Vec<TypeName> {
    let mut found: Vec<TypeName> = vec![];
    let traits = &module.traits;
    if traits.is_empty() {
        return found;
    }
    let names = TraitNames::of(traits);
    let mut add = |ty: &TypeName| {
        if names.mentioned_in(ty) {
            collect(traits, ty, &mut found);
        }
    };
    for st in &module.structs {
        if st.ty.is_generic() && st.name == st.ty.name {
            continue;
        }
        for field in &st.field_members {
            add(&field.ty);
        }
        for method in st
            .method_members
            .iter()
            .chain(st.constructors.iter()).chain([&st.destructor])
        {
            function_types(method, &mut add);
        }
    }
    for function in module.functions.iter().filter(|f| !f.is_generic_func) {
        function_types(function, &mut add);
    }
    for var in &module.globals {
        add(&var.ty);
    }
    found
}

/// The traits' names, for [`TraitNames::mentioned_in`].
struct TraitNames<'t> {
    /// Names that are one identifier (`Iterator`): matched as whole words.
    words: Vec<&'t str>,
    /// Any other name: matched anywhere.
    others: Vec<&'t str>,
    /// The length of the shortest name: no shorter spelling mentions one.
    shortest: usize,
}

fn is_word_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// The words of `text`, as bytes: its runs of [`is_word_char`] characters
/// (ASCII, so any other byte ends a word).
fn words(text: &str) -> impl Iterator<Item = &[u8]> {
    let bytes = text.as_bytes();
    let mut start = 0;
    (0..=bytes.len()).filter_map(move |i| {
        if i < bytes.len() && is_word_char(bytes[i] as char) {
            return None;
        }
        let word = &bytes[start..i];
        start = i + 1;
        (!word.is_empty()).then_some(word)
    })
}

impl<'t> TraitNames<'t> {
    fn of(traits: &'t [TraitDef]) -> Self {
        let (words, others) = traits.iter().map(|t| t.name.as_str()).partition(|name| name.chars().all(is_word_char));
        let shortest = traits.iter().map(|t| t.name.len()).min().unwrap_or(0);
        TraitNames { words, others, shortest }
    }

    /// Whether any name in `ty` spells a trait's name: a cheap filter before
    /// [`collect`] prints and re-parses the type (a pointer's stars and a
    /// generic argument can be spelled inside a name, `Array<Shape>*`). A
    /// trait is a whole word of the spelling, so `ArrayIterator` does not
    /// mention `Iterator`.
    fn mentioned_in(&self, ty: &TypeName) -> bool {
        let name = ty.name.as_str();
        if name.len() < self.shortest && ty.sub_types.is_empty() {
            return false;
        }
        words(name).any(|word| self.words.iter().any(|w| w.as_bytes() == word))
            || self.others.iter().any(|other| name.contains(other))
            || ty.sub_types.iter().any(|sub| self.mentioned_in(sub))
    }
}

fn collect(traits: &[TraitDef], ty: &TypeName, found: &mut Vec<TypeName>) {
    // Pointers carry their stars in the name (`Shape*`, `Array<int>*`).
    let text = ty.to_string();
    let pointee = crate::passes::gather_generics::parse_type_string(text.trim_end_matches('*'));
    let parsed = pointee.clone();
    if let Some(def) = trait_def(traits, &pointee) {
        // Only fully applied traits are types (`Iterator<T>` inside a
        // generic base is not).
        let applied = pointee.sub_types.len()
            >= def
                .generic_params
                .iter()
                .filter(|p| p.default.is_none())
                .count()
            && !pointee
                .sub_types
                .iter()
                .any(|a| def.generic_params.iter().any(|p| p.name == a.name));
        if applied && !found.iter().any(|f| f.to_string() == pointee.to_string()) {
            found.push(pointee.clone());
        }
    }
    for arg in &parsed.sub_types {
        collect(traits, arg, found);
    }
}

fn function_types(function: &FunctionDef, add: &mut impl FnMut(&TypeName)) {
    add(&function.ty);
    for param in &function.parameters {
        add(&param.ty);
    }
    if let Some(body) = &function.body {
        block_types(body, add);
    }
}

fn block_types(block: &crate::model::Block, add: &mut impl FnMut(&TypeName)) {
    use crate::model::{Declaration, Statement};
    for stmt in &block.items {
        match stmt {
            Statement::Block(inner) => block_types(inner, add),
            Statement::Declaration(Declaration::Variable(var)) => add(&var.ty),
            Statement::Branch(branch) => {
                block_types(&branch.if_block, add);
                if let Some(else_block) = &branch.else_block {
                    block_types(else_block, add);
                }
            }
            Statement::While(wh) => block_types(&wh.block, add),
            _ => {}
        }
    }
}
