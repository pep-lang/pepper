//! Static type inference for operator overloading and print conversion:
//! a per-module table of struct fields/methods plus `of`, which best-effort
//! computes the static type of an expression.

use std::collections::{HashMap, HashSet};

use crate::model::{BinaryOp, Expression, Module};
use crate::type_name::TypeName;

pub(crate) struct StructInfo {
    /// (field name, field type)
    pub(crate) fields: Vec<(String, TypeName)>,
    /// Method names declared on the struct.
    pub(crate) methods: HashSet<String>,
    /// Method name -> return type.
    pub(crate) returns: HashMap<String, TypeName>,
}

pub(crate) struct StructTable {
    pub(crate) structs: HashMap<String, StructInfo>,
}

impl StructTable {
    pub(crate) fn build(module: &Module) -> Self {
        let mut structs = HashMap::new();
        for st in &module.structs {
            let name = st.ty.to_string();
            let fields = st
                .field_members
                .iter()
                .map(|f| (f.name.clone(), f.ty.clone()))
                .collect();
            let methods = st.method_members.iter().map(|m| m.name.clone()).collect();
            let returns = st
                .method_members
                .iter()
                .map(|m| (m.name.clone(), m.ty.clone()))
                .collect();
            structs.insert(name, StructInfo { fields, methods, returns });
        }
        Self { structs }
    }

    pub(crate) fn get(&self, name: &str) -> Option<&StructInfo> {
        self.structs.get(name)
    }

    /// Base struct name of a type string (`string<...>` -> `string`).
    pub(crate) fn base_name(ty: &TypeName) -> String {
        ty.to_string().split('<').next().unwrap_or("").to_string()
    }
}

/// Best-effort static type of an expression. Returns `None` when the type
/// cannot be determined (e.g. a bare symbol whose declaration is not visible).
pub(crate) fn of(expr: &Expression, table: &StructTable, current: Option<&TypeName>) -> Option<TypeName> {
    match expr {
        Expression::SymbolRef { ty, .. } => {
            if ty.is_empty() || ty.to_string() == crate::type_name::AUTO {
                None
            } else {
                Some(ty.clone())
            }
        }
        Expression::ThisRef => current.cloned(),
        Expression::StringLiteral { .. } => Some(TypeName::new("string")),
        Expression::PointerLiteral => Some(TypeName::void_ptr()),
        Expression::BoolLiteral(_) => Some(TypeName::bool_()),
        Expression::IntLiteral(_) => Some(TypeName::new("i32")),
        Expression::FloatLiteral(_) => Some(TypeName::new("f64")),
        Expression::MemberRef { lhs, name } => {
            let lhs_type = of(lhs, table, current)?;
            let info = table.get(&StructTable::base_name(&lhs_type))?;
            info.fields.iter().find(|(f, _)| f == name).map(|(_, ty)| ty.clone())
        }
        Expression::MethodCall { this, method, .. } => {
            let this_type = of(this, table, current)?;
            table.get(&StructTable::base_name(&this_type))?.returns.get(method).cloned()
        }
        Expression::Index { lhs, .. } => {
            let lhs_type = of(lhs, table, current)?;
            table
                .get(&StructTable::base_name(&lhs_type))?
                .returns
                .get("__index_get")
                .cloned()
        }
        Expression::ArrayIndex { ty, .. } => Some(ty.clone()),
        Expression::FunctionCall { function, .. } => {
            let base = StructTable::base_name(&TypeName::new(function.as_str()));
            if table.get(&base).is_some() {
                Some(TypeName::new(base.as_str()))
            } else {
                None
            }
        }
        Expression::Binary { op, lhs, .. } => {
            if op.is_assignment() {
                of(lhs, table, current)
            } else if op.is_comparison() || matches!(op, BinaryOp::LogicalAnd | BinaryOp::LogicalOr) {
                Some(TypeName::bool_())
            } else {
                // Arithmetic/bitwise ops keep the lhs's type.
                of(lhs, table, current)
            }
        }
        Expression::Ternary { true_expr, .. } => of(true_expr, table, current),
        _ => None,
    }
}
