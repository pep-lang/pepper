//! What a cast may convert (docs/src/language/types-and-variables.md,
//! "Casting with `as`" and "Reinterpreting with `unsafe_cast`").
//!
//! `x as T` is a `static_cast`: a value conversion between numbers, `bool`
//! and enums (an enum to its integer; the other way is a case, reported by
//! `enums`), a struct to a trait it conforms to (`convert_to_traits` turns
//! that into a `ToTrait`), a pointer to `__ptr<void>` and back, and the
//! identity. `unsafe_cast<T>(x)` is a `reinterpret_cast`: a pointer to
//! another pointer or an integer and back, and a number to another number of
//! the same width with its bits unchanged. Neither ever applies to a
//! refcounted reference, so the shared_ptr model cannot be bypassed.
//!
//! `check` decides both on the types as sema spells them after
//! `convert_intrinsics` (`int*` for `__ptr<int>`); `check_casts` reports
//! from it in sema, and codegen asks it again with the exact types of the
//! casts sema could not type.

use crate::model::CastKind;
use crate::type_name::TypeName;

/// The kind of value a cast converts from or to.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Category {
    /// An integer, `bool`, or a byte read through a `void` pointer.
    Integer(u32),
    Float(u32),
    /// An enum, stored as an integer of this width.
    Enum(u32),
    /// `__ptr<void>`.
    VoidPointer,
    /// `__ptr<T>` for any other `T`, or a C function pointer.
    Pointer,
    /// Anything else: a struct, trait, function type, tuple or weak
    /// reference.
    Other,
}

fn category(ty: &TypeName) -> Category {
    let name = ty.to_string();
    if ty.is_extern_function_type() {
        return Category::Pointer;
    }
    if name == "void*" || (ty.name == "__ptr" && ty.sub_types.first().is_some_and(|t| t.to_string() == "void")) {
        return Category::VoidPointer;
    }
    if (ty.is_scalar() && name.ends_with('*')) || ty.name == "__ptr" {
        return Category::Pointer;
    }
    // Indexing a `void` pointer reads one byte.
    if name == "void" {
        return Category::Integer(8);
    }
    if let Some(representation) = crate::enums::representation(&name) {
        return Category::Enum(crate::arithmetic::bit_width(&representation).unwrap_or(32));
    }
    match crate::arithmetic::bit_width(&name) {
        Some(width) if crate::arithmetic::is_float_type(&name) => Category::Float(width),
        Some(width) => Category::Integer(width),
        None => Category::Other,
    }
}

/// The type as written in source: `__ptr<int>` for sema's `int*`.
pub fn spelled(ty: &TypeName) -> String {
    let name = ty.to_string();
    match name.strip_suffix('*') {
        Some(pointee) if ty.is_scalar() => format!("__ptr<{}>", spelled(&TypeName::new(pointee))),
        _ => crate::passes::constraints::spelled(ty),
    }
}

fn is_static(from: Category, to: Category) -> bool {
    use Category::*;
    match (from, to) {
        (Integer(_) | Float(_) | Enum(_), Integer(_) | Float(_)) => true,
        // `n as E` is reported by `enums` with the case to name instead.
        (Integer(_) | Float(_), Enum(_)) => true,
        (Pointer | VoidPointer, VoidPointer) | (VoidPointer, Pointer) => true,
        _ => false,
    }
}

fn is_reinterpret(from: Category, to: Category) -> bool {
    use Category::*;
    match (from, to) {
        (Pointer | VoidPointer, Pointer | VoidPointer) => true,
        (Pointer | VoidPointer, Integer(width)) | (Integer(width), Pointer | VoidPointer) => width > 1,
        (Integer(a) | Float(a), Integer(b) | Float(b)) => a == b && a > 1,
        _ => false,
    }
}

/// Whether a cast of `kind` may convert `from` to `to`; the error message
/// when not. A synthesized cast is always allowed.
pub fn check(from: &TypeName, to: &TypeName, kind: CastKind) -> Result<(), String> {
    if kind == CastKind::Synthesized || crate::passes::check_function_types::canonical(from) == crate::passes::check_function_types::canonical(to) {
        return Ok(());
    }
    let (source, target) = (category(from), category(to));
    let (from_text, to_text) = (spelled(from), spelled(to));
    match kind {
        CastKind::Static if is_static(source, target) => Ok(()),
        CastKind::Static if is_reinterpret(source, target) => Err(format!(
            "cannot cast '{}' to '{}' with 'as'; use 'unsafe_cast<{}>(...)' to reinterpret",
            from_text, to_text, to_text
        )),
        CastKind::Static => Err(format!("cannot cast '{}' to '{}'", from_text, to_text)),
        CastKind::Unsafe if is_reinterpret(source, target) => Ok(()),
        CastKind::Unsafe if source == Category::Other || target == Category::Other => Err(format!(
            "'unsafe_cast' cannot convert '{}' to '{}': it reinterprets only pointers and numbers",
            from_text, to_text
        )),
        CastKind::Unsafe if is_static(source, target) => Err(format!(
            "'unsafe_cast' cannot convert '{}' to '{}': the sizes differ; use 'as' to convert the value",
            from_text, to_text
        )),
        CastKind::Unsafe => Err(format!("'unsafe_cast' cannot convert '{}' to '{}'", from_text, to_text)),
        CastKind::Synthesized => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn allowed(from: &str, to: &str, kind: CastKind) -> bool {
        check(&TypeName::new(from), &TypeName::new(to), kind).is_ok()
    }

    #[test]
    fn as_is_a_static_cast() {
        assert!(allowed("int", "double", CastKind::Static));
        assert!(allowed("bool", "u8", CastKind::Static));
        assert!(allowed("int*", "void*", CastKind::Static));
        assert!(allowed("void*", "u8*", CastKind::Static));
        assert!(allowed("u8*", "u8*", CastKind::Static));
        assert!(!allowed("char*", "u8*", CastKind::Static));
        assert!(!allowed("void*", "ulong", CastKind::Static));
        assert!(!allowed("String", "void*", CastKind::Static));
    }

    #[test]
    fn unsafe_cast_reinterprets() {
        assert!(allowed("char*", "u8*", CastKind::Unsafe));
        assert!(allowed("void*", "ulong", CastKind::Unsafe));
        assert!(allowed("ulong", "int*", CastKind::Unsafe));
        assert!(allowed("float", "uint", CastKind::Unsafe));
        assert!(allowed("u64", "double", CastKind::Unsafe));
        assert!(!allowed("float", "ulong", CastKind::Unsafe));
        assert!(!allowed("int", "long", CastKind::Unsafe));
        assert!(!allowed("String", "void*", CastKind::Unsafe));
        assert!(!allowed("void*", "String", CastKind::Unsafe));
        assert!(!allowed("void*", "bool", CastKind::Unsafe));
    }

    #[test]
    fn messages_name_the_types_as_written() {
        let error = check(&TypeName::new("char*"), &TypeName::new("u8*"), CastKind::Static).unwrap_err();
        assert_eq!(error, "cannot cast '__ptr<char>' to '__ptr<byte>' with 'as'; use 'unsafe_cast<__ptr<byte>>(...)' to reinterpret");
    }
}
