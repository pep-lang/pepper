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
pub const VOID: &str = "void";
pub const BOOL: &str = "bool";
pub const VOID_PTR: &str = "void*";

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

    pub fn is_generic(&self) -> bool {
        !self.sub_types.is_empty()
    }

    pub fn is_pointer(&self) -> bool {
        self.is_scalar() && self.name.ends_with('*')
    }

    pub fn is_integral(&self) -> bool {
        self.is_scalar() && INTEGRAL_TYPES.contains(self.name.as_str())
    }

    pub fn is_struct(&self) -> bool {
        self.is_scalar() && !self.is_integral()
    }

    /// `name<sub, sub>` for generics; `name` otherwise (matches `TypeName::to_string`).
    pub fn to_string(&self) -> String {
        let generic_types = if self.is_generic() {
            let subs: Vec<String> = self.sub_types.iter().map(|t| t.to_string()).collect();
            format!("<{}>", subs.join(", "))
        } else {
            String::new()
        };
        format!("{}{}", self.name, generic_types)
    }

    /// Recursive generic parameter substitution (port of `Specializer::replace`).
    pub fn replace(&mut self, param_name: &str, type_arg: &TypeName) {
        if self.name == param_name {
            *self = type_arg.clone();
        }
        for arg in &mut self.sub_types {
            arg.replace(param_name, type_arg);
        }
    }
}

impl Display for TypeName {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_string())
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
