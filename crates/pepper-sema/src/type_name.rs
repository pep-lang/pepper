//! Sema type name: port of `source/Sema/Model/TypeName.{h,cpp}`.

use std::collections::HashSet;
use std::fmt::{Display, Formatter};
use std::sync::LazyLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TypeFlags {
    Scalar,
    Function,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct TypeName {
    pub name: String,
    pub sub_types: Vec<TypeName>,
    pub flags: TypeFlags,
}

pub const AUTO: &str = "__auto";

/// Type of an integer literal, as in C: `i32` when the value fits, else
/// `i64` (codegen emits the same widths).
pub fn int_literal_type(value: i64) -> &'static str {
    if i32::try_from(value).is_ok() { "i32" } else { "i64" }
}
pub const VOID: &str = "void";
pub const BOOL: &str = "bool";
pub const VOID_PTR: &str = "void*";
/// Internal name of function types: `(P1, P2) => R` is `__function<R, P1, P2>`.
pub const FUNCTION: &str = "__function";
/// Internal name of thread-safe function types: `shared (P1, P2) => R` is
/// `__shared_function<R, P1, P2>`.
pub const SHARED_FUNCTION: &str = "__shared_function";
/// Internal name of C function pointer types: `extern (P1, P2) => R` is
/// `__extern_function<R, P1, P2>`. Not reference-counted; lowers to a bare
/// pointer, like `void*`.
pub const EXTERN_FUNCTION: &str = "__extern_function";
/// `__weak<T>`: a weak reference to a struct `T` (`std::weak_ptr<T>`).
pub const WEAK: &str = "__weak";

/// Integral-type alias set from `TypeName.cpp:23-45`.
pub static INTEGRAL_TYPES: LazyLock<HashSet<&'static str>> = LazyLock::new(|| {
    HashSet::from([
        "void",
        "__auto",
        "bool",
        "void*",
        "i8",
        "char",
        "u8",
        "byte",
        "i16",
        "short",
        "u16",
        "ushort",
        "i32",
        "int",
        "u32",
        "uint",
        "i64",
        "long",
        "u64",
        "ulong",
        "f64",
        "double",
        "f32",
        "float",
    ])
});

/// Whether a generic function's parameter list, as spelled, makes it a
/// concrete override (`hash<String>`) of the generic base of the same name
/// (`hash<T>`) rather than another generic base: every parameter must name a
/// primitive or `String`.
pub fn is_concrete_override<'a>(mut params: impl Iterator<Item = &'a str>) -> bool {
    params.all(|p| INTEGRAL_TYPES.contains(p) || p == "String")
}

/// A primitive (`int`, `bool`, `void*`, ...) or an enum, which is stored as
/// an integer (`crate::enums`).
pub fn is_integral_name(name: &str) -> bool {
    INTEGRAL_TYPES.contains(name) || crate::enums::is_enum(name)
}

/// Whether a function with these generic parameters, as spelled, is a
/// concrete override (`hash<int>`): it has some, and all are concrete. Module
/// linking and the visibility check both decide overrides by this.
pub fn is_override<'a>(params: impl IntoIterator<Item = &'a str>) -> bool {
    let mut params = params.into_iter().peekable();
    params.peek().is_some() && is_concrete_override(params)
}

impl TypeName {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            sub_types: vec![],
            flags: TypeFlags::Scalar,
        }
    }

    pub fn with_args(name: &str, args: Vec<TypeName>) -> Self {
        Self {
            name: name.to_string(),
            sub_types: args,
            flags: TypeFlags::Scalar,
        }
    }

    pub fn auto() -> Self {
        Self::new(AUTO)
    }

    pub fn void() -> Self {
        Self::new(VOID)
    }

    pub fn bool_() -> Self {
        Self::new(BOOL)
    }

    pub fn void_ptr() -> Self {
        Self::new(VOID_PTR)
    }

    pub fn make_function(name: &str, args: Vec<TypeName>) -> Self {
        Self {
            name: name.to_string(),
            sub_types: args,
            flags: TypeFlags::Function,
        }
    }

    pub fn empty() -> Self {
        Self::new("")
    }

    pub fn is_empty(&self) -> bool {
        self.name.is_empty() && self.sub_types.is_empty()
    }

    pub fn is_scalar(&self) -> bool {
        self.flags == TypeFlags::Scalar
    }

    pub fn is_function(&self) -> bool {
        self.flags == TypeFlags::Function
    }

    /// A function type, plain (`(P...) => R`, spelled `__function<R, P...>`)
    /// or thread-safe (`shared (P...) => R`, `__shared_function<R, P...>`).
    pub fn is_function_type(&self) -> bool {
        (self.name == FUNCTION || self.name == SHARED_FUNCTION) && !self.sub_types.is_empty()
    }

    /// A C function pointer type `extern (P...) => R`. Not a function type
    /// in the `is_function_type` sense: it has no object and no counts.
    pub fn is_extern_function_type(&self) -> bool {
        self.name == EXTERN_FUNCTION && !self.sub_types.is_empty()
    }

    /// A type whose values can be called: a function type or a C function
    /// pointer type.
    pub fn is_callable(&self) -> bool {
        self.is_function_type() || self.is_extern_function_type()
    }

    /// The plain function type `(P...) => R` with the signature of this C
    /// function pointer type.
    pub fn extern_as_function(&self) -> Option<TypeName> {
        self.is_extern_function_type().then(|| Self::with_args(FUNCTION, self.sub_types.clone()))
    }

    /// A thread-safe function type `shared (P...) => R`.
    pub fn is_shared_function_type(&self) -> bool {
        self.name == SHARED_FUNCTION && !self.sub_types.is_empty()
    }

    /// This function type with the same signature, thread-safe or plain;
    /// any other type unchanged.
    pub fn with_sharing(&self, shared: bool) -> TypeName {
        let mut ty = self.clone();
        if ty.is_function_type() {
            ty.name = (if shared { SHARED_FUNCTION } else { FUNCTION }).to_string();
        }
        ty
    }

    /// A weak reference type `__weak<T>`.
    pub fn is_weak(&self) -> bool {
        self.name == WEAK && self.sub_types.len() == 1
    }

    /// The `T` of `__weak<T>`.
    pub fn weak_target(&self) -> Option<&TypeName> {
        if self.is_weak() { self.sub_types.first() } else { None }
    }

    /// Function type `(params) => ret`.
    pub fn function_type(ret: TypeName, params: Vec<TypeName>) -> Self {
        let mut args = vec![ret];
        args.extend(params);
        Self::with_args(FUNCTION, args)
    }

    /// Return type of a function type.
    pub fn function_return(&self) -> Option<&TypeName> {
        if self.is_function_type() || self.is_extern_function_type() { self.sub_types.first() } else { None }
    }

    /// Parameter types of a function type.
    pub fn function_params(&self) -> &[TypeName] {
        if self.is_function_type() || self.is_extern_function_type() { &self.sub_types[1..] } else { &[] }
    }

    /// The type as the programmer writes it: `(int) => bool` for function
    /// types (recursively), `Name<args>` otherwise. For error messages.
    pub fn display(&self) -> String {
        if self.is_function_type() || self.is_extern_function_type() {
            let params: Vec<String> = self.function_params().iter().map(|p| p.display()).collect();
            let shared = if self.is_shared_function_type() {
                "shared "
            } else if self.is_extern_function_type() {
                "extern "
            } else {
                ""
            };
            return format!("{}({}) => {}", shared, params.join(", "), self.sub_types[0].display());
        }
        if self.is_generic() {
            let subs: Vec<String> = self.sub_types.iter().map(|t| t.display()).collect();
            return format!("{}<{}>", self.name, subs.join(", "));
        }
        self.name.clone()
    }

    pub fn is_generic(&self) -> bool {
        !self.sub_types.is_empty()
    }

    /// Whether the type names `name`, itself or nested (`Array<T>` and
    /// `T*` mention `T`).
    pub fn mentions(&self, name: &str) -> bool {
        self.name == name
            || self.name.trim_end_matches('*') == name
            || self.sub_types.iter().any(|t| t.mentions(name))
    }

    /// The type, or any type nested in it, is still `auto` (not inferred).
    pub fn contains_auto(&self) -> bool {
        self.name == AUTO || self.sub_types.iter().any(|t| t.contains_auto())
    }

    pub fn is_pointer(&self) -> bool {
        self.is_scalar() && self.name.ends_with('*')
    }

    pub fn is_integral(&self) -> bool {
        self.is_scalar() && is_integral_name(&self.name)
    }

    pub fn is_struct(&self) -> bool {
        self.is_scalar() && !self.is_integral()
    }

    /// `name<sub, sub>` for generics; `name` otherwise (matches `TypeName::to_string`).
    pub fn to_string(&self) -> String {
        let mut out = String::with_capacity(self.name.len());
        self.write_to(&mut out);
        out
    }

    fn write_to(&self, out: &mut String) {
        out.push_str(&self.name);
        if self.is_generic() {
            out.push('<');
            for (i, sub) in self.sub_types.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                sub.write_to(out);
            }
            out.push('>');
        }
    }

    /// Whether this is exactly `auto` (a type not inferred yet); same as
    /// `to_string() == AUTO`, without building the string.
    pub fn is_auto(&self) -> bool {
        self.name == AUTO && !self.is_generic()
    }

    /// Recursive generic parameter substitution (port of `Specializer::replace`).
    /// Pointer types carry the suffix in the name (`T*`), so a param used as a
    /// pointer is matched on the exact pointee and re-emitted with the stars.
    pub fn replace(&mut self, param_name: &str, type_arg: &TypeName) {
        if self.name == param_name {
            // Done: the argument may itself name a parameter spelled the
            // same (`Twin<T>` with `T` = `Box<T>`), which is not this one.
            *self = type_arg.clone();
            return;
        } else if let Some(pointee) = self.name.strip_suffix('*') {
            if pointee == param_name {
                let stars = &self.name[pointee.len()..];
                self.name = format!("{}{}", type_arg, stars);
            }
        }
        for arg in &mut self.sub_types {
            arg.replace(param_name, type_arg);
        }
    }
}

impl Display for TypeName {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.to_string())
    }
}

/// Numeric width/signedness/floatness from `TypeName.cpp:57-76`.
struct NumericTypeName {
    width: u32,
    is_signed: bool,
    is_float: bool,
}

fn numeric_type(name: &str) -> Option<NumericTypeName> {
    let (width, is_signed, is_float) = match name {
        "i1" | "bool" => (1, true, false),
        "i8" | "char" => (8, true, false),
        "u8" | "byte" => (8, false, false),
        "i16" | "short" => (16, true, false),
        "u16" | "ushort" => (16, false, false),
        "i32" | "int" => (32, true, false),
        "u32" | "uint" => (32, false, false),
        "i64" | "long" => (64, true, false),
        "u64" | "ulong" => (64, false, false),
        "f32" | "float" => (32, true, true),
        "f64" | "double" => (64, true, true),
        _ => return None,
    };
    Some(NumericTypeName {
        width,
        is_signed,
        is_float,
    })
}

/// Widest numeric type of two operands (port of `TypeName::widest`).
pub fn widest(lhs: &TypeName, rhs: &TypeName) -> TypeName {
    let lhs_type = numeric_type(&lhs.name).expect("non-numeric type in widest()");
    let rhs_type = numeric_type(&rhs.name).expect("non-numeric type in widest()");
    let width = lhs_type.width.max(rhs_type.width);
    if lhs_type.is_float || rhs_type.is_float {
        return if width > 32 {
            TypeName::new("f64")
        } else {
            TypeName::new("f32")
        };
    }
    if !lhs_type.is_signed && !rhs_type.is_signed {
        return if width > 32 {
            TypeName::new("u64")
        } else if width > 8 {
            TypeName::new("u32")
        } else {
            TypeName::new("u8")
        };
    }
    if width > 32 {
        TypeName::new("i64")
    } else if width > 8 {
        TypeName::new("i32")
    } else {
        TypeName::new("i8")
    }
}

/// Apply a full generic substitution map (used by function specialization).
pub fn replace_map(ty: &mut TypeName, type_map: &[(String, TypeName)]) {
    for (param, arg) in type_map {
        ty.replace(param, arg);
    }
}
