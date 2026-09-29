//! Static type inference for operator overloading and print conversion:
//! a per-module table of struct fields/methods plus `of`, which best-effort
//! computes the static type of an expression.

use std::collections::{HashMap, HashSet};

use crate::model::{BinaryOp, Expression, Module};
use crate::type_name::TypeName;

#[derive(Clone)]
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
    /// Free-function and extern name -> return type.
    pub(crate) functions: HashMap<String, TypeName>,
}

impl StructTable {
    pub(crate) fn build(module: &Module) -> Self {
        let mut structs = HashMap::new();
        for st in &module.structs {
            let name = st.ty.to_string();
            let info = StructInfo {
                fields: st
                    .field_members
                    .iter()
                    .map(|f| (f.name.clone(), f.ty.clone()))
                    .collect(),
                methods: st.method_members.iter().map(|m| m.name.clone()).collect(),
                returns: st
                    .method_members
                    .iter()
                    .map(|m| (m.name.clone(), m.ty.clone()))
                    .collect(),
            };
            structs.insert(name.clone(), info.clone());
            // Also key the generic base (`Array<T>` -> `Array`) so pre-
            // specialization lookups resolve; never clobber a concrete entry.
            if name != st.ty.name {
                structs.entry(st.ty.name.clone()).or_insert(info);
            }
        }
        let mut functions = HashMap::new();
        for f in &module.functions {
            functions.insert(f.name.clone(), f.ty.clone());
        }
        for e in &module.externs {
            functions.insert(e.name.clone(), e.ty.clone());
        }
        Self { structs, functions }
    }

    pub(crate) fn get(&self, name: &str) -> Option<&StructInfo> {
        self.structs.get(name)
    }

    /// Base struct name of a type string (`String<...>` -> `String`).
    pub(crate) fn base_name(ty: &TypeName) -> String {
        ty.to_string().split('<').next().unwrap_or("").to_string()
    }

    /// Struct info for a type: the exact specialization first (`Array<int>`),
    /// then the generic base (`Array`) for pre-specialization lookups.
    pub(crate) fn lookup(&self, ty: &TypeName) -> Option<&StructInfo> {
        self.structs
            .get(&ty.to_string())
            .or_else(|| self.structs.get(&Self::base_name(ty)))
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
        Expression::StringLiteral { .. } => Some(TypeName::new("String")),
        Expression::PointerLiteral => Some(TypeName::void_ptr()),
        Expression::BoolLiteral(_) => Some(TypeName::bool_()),
        Expression::IntLiteral(_) => Some(TypeName::new("i32")),
        Expression::FloatLiteral(_) => Some(TypeName::new("f64")),
        Expression::MemberRef { lhs, name, .. } => {
            // Specialized clones keep unsubstituted annotations on bare
            // symbols (`keys` typed `K*` in `HashMap<String, int>`), and a
            // table lookup of the enclosing type may fall back to the
            // generic base entry (also unsubstituted). So both the
            // annotation and the enclosing struct's field table are tried as
            // lhs types; for pointer types the stripped pointee is tried
            // first, so `keys.Data` in a specialized body hits the exact
            // `Array<String>` entry before the base-name fallback reaches
            // the unsubstituted generic `Array`. The first candidate that
            // names the field wins.
            let mut candidates = Vec::new();
            if let Some(ty) = of(lhs, table, current) {
                candidates.push(ty);
            }
            if let Expression::SymbolRef { id, .. } = lhs.as_ref() {
                if let Some(ty) = current.and_then(|c| {
                    table.lookup(c)
                        .and_then(|info| info.fields.iter().find(|(f, _)| f == id).map(|(_, ty)| ty.clone()))
                }) {
                    candidates.push(ty);
                }
            }
            for lhs_type in candidates {
                // A starred type (`Array<String>*`) must try its exact
                // specialized pointee first: `lookup` on the pointer falls
                // straight through to the unsubstituted generic base, which
                // would shadow the concrete entry.
                let mut keys = Vec::new();
                if let Some(pointee) = lhs_type.to_string().strip_suffix('*') {
                    keys.push(TypeName::new(pointee));
                }
                keys.push(lhs_type.clone());
                for key in keys {
                    if let Some(info) = table.lookup(&key) {
                        if let Some((_, ty)) = info.fields.iter().find(|(f, _)| f == name) {
                            return Some(ty.clone());
                        }
                    }
                }
            }
            None
        }
        Expression::MethodCall { this, method, .. } => {
            let this_type = of(this, table, current)?;
            table.lookup(&this_type)?.returns.get(method).cloned()
        }
        // `source.iterate()` if the source is Iterable, else the source.
        Expression::ForIterator(source) => {
            let source_type = of(source, table, current)?;
            match table.lookup(&source_type)?.returns.get("iterate") {
                Some(iterator) => Some(iterator.clone()),
                None => Some(source_type),
            }
        }
        Expression::Index { lhs, .. } => {
            let lhs_type = of(lhs, table, current)?;
            // Pointer receiver (`T*`): the element is the pointee, and the
            // indexing stays RAW (codegen GEPs through the pointer). Even
            // when the pointee is a struct with its own indexer — dispatching
            // on it would route `Data[i] = v` inside an Array of arrays to
            // the element's `__index_set` instead of writing the slot. A
            // generic pointee such as `Array<int>*` is the exception: its
            // specialized entry (`Array<int>`) carries a concrete
            // `__index_get` return, so use it — the base-template lookup
            // would otherwise yield the unsubstituted template param.
            if let Some(pointee) = lhs_type.to_string().strip_suffix('*') {
                let pointee_ty = TypeName::new(pointee);
                if let Some(info) = table.get(pointee) {
                    if let Some(ret) = info.returns.get("__index_get") {
                        return Some(ret.clone());
                    }
                } else if let Some(info) = table.lookup(&pointee_ty) {
                    if let Some(ret) = info.returns.get("__index_get") {
                        return Some(ret.clone());
                    }
                }
                return Some(pointee_ty);
            }
            if let Some(info) = table.lookup(&lhs_type) {
                if let Some(ret) = info.returns.get("__index_get") {
                    return Some(ret.clone());
                }
            }
            None
        }
        Expression::ArrayIndex { ty, .. } => Some(ty.clone()),
        Expression::FunctionCall { function, .. } => {
            // Plain free-function call: its declared return type.
            if let Some(ty) = table.functions.get(function) {
                return Some(ty.clone());
            }
            // Constructor-style call `Name<...>(...)` resolves to Name<...>.
            let ty = crate::passes::gather_generics::parse_type_string(function);
            table.lookup(&ty).map(|_| ty)
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
        // `x as T` has the cast target's type.
        Expression::Cast { ty, .. } => Some(ty.clone()),
        Expression::FunctionRef { ty, .. } => Some(ty.clone()),
        Expression::Invoke { callee, .. } => of(callee, table, current)?.function_return().cloned(),
        _ => None,
    }
}
