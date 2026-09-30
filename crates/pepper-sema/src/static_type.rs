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
    /// The unary operators declared: `-`, `~`, `!`, `!!` as instance methods
    /// without parameters (see `passes::unary_operators`).
    pub(crate) unary_operators: HashSet<String>,
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
                // An overloaded method also answers to its set's name (`+`).
                methods: st
                    .method_members
                    .iter()
                    .flat_map(|m| [m.name.clone(), crate::passes::overloads::set_name(&m.name).to_string()])
                    .collect(),
                returns: st
                    .method_members
                    .iter()
                    .map(|m| (m.name.clone(), m.ty.clone()))
                    .collect(),
                unary_operators: crate::passes::unary_operators::declared(&st.method_members),
            };
            structs.insert(name.clone(), info.clone());
            // Also key the generic base (`Array<T>` -> `Array`) so pre-
            // specialization lookups resolve; never clobber a concrete entry.
            if name != st.ty.name {
                structs.entry(st.ty.name.clone()).or_insert(info);
            }
        }
        // Traits used as types: what a value of the type can call. The
        // specialized instances first (`Iterator<int>`), then each base for
        // lookups of an instance nothing declares.
        let trait_info = |t: &crate::model::TraitType| StructInfo {
            fields: vec![],
            methods: t
                .methods
                .iter()
                .flat_map(|m| [m.name.clone(), crate::passes::overloads::set_name(&m.name).to_string()])
                .collect(),
            returns: t
                .methods
                .iter()
                .map(|m| (m.name.clone(), m.ty.clone()))
                .collect(),
            unary_operators: crate::passes::unary_operators::declared(&t.methods),
        };
        for ty in crate::traits::used_trait_types(module) {
            if let Some(def) = crate::traits::trait_def(&module.traits, &ty) {
                structs
                    .entry(ty.to_string())
                    .or_insert_with(|| trait_info(&crate::traits::instance(def, &ty)));
            }
        }
        for def in &module.traits {
            let ty = TypeName::new(&def.name);
            structs
                .entry(def.name.clone())
                .or_insert_with(|| trait_info(&crate::traits::instance(def, &ty)));
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
            if ty.is_empty() || ty.is_auto() {
                None
            } else {
                Some(ty.clone())
            }
        }
        Expression::ThisRef => current.cloned(),
        // A raw literal is the NUL-terminated `char*` global itself.
        Expression::StringLiteral { is_raw: true, .. } => Some(TypeName::new("char*")),
        Expression::StringLiteral { .. } => Some(TypeName::new("String")),
        Expression::PointerLiteral => Some(TypeName::void_ptr()),
        Expression::BoolLiteral(_) => Some(TypeName::bool_()),
        Expression::IntLiteral(v) => Some(TypeName::new(crate::type_name::int_literal_type(*v))),
        Expression::FloatLiteral(_) => Some(TypeName::new("f64")),
        Expression::Destructure { value, .. } => of(value, table, current),
        Expression::MemberRef { lhs, name, .. }
            if of(lhs, table, current).is_some_and(|t| t.tuple_element(name).is_some()) =>
        {
            of(lhs, table, current)?.tuple_element(name).cloned()
        }
        Expression::MemberRef { lhs, name, .. } => {
            // Specialized clones keep unsubstituted annotations on bare
            // symbols (`keys` typed `K*` in `HashMap<String, int>`), and a
            // table lookup of the enclosing type may fall back to the
            // generic base entry (also unsubstituted). So both the
            // annotation and the enclosing struct's field table are tried as
            // lhs types; for pointer types the stripped pointee is tried
            // first, so `keys._data` in a specialized body hits the exact
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
        Expression::Weak(op, ty, _) => Some(op.result(ty)),
        Expression::Allocate(ty) => Some(ty.clone()),
        Expression::CountStep { .. } => Some(TypeName::new("u32")),
        Expression::FunctionPointer { .. } => Some(TypeName::new("void*")),
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
        Expression::FunctionCall { function, args, .. } if crate::passes::tuples::constructor_labels(function).is_some() => {
            crate::passes::tuples::labeled_literal_type(function, args.iter().map(|a| of(a, table, current).unwrap_or_else(TypeName::auto)))
        }
        Expression::FunctionCall { function, .. } if function.starts_with("__tuple<") => {
            Some(crate::passes::gather_generics::parse_type_string(function))
        }
        Expression::FunctionCall { function, .. } => {
            // Plain free-function call: its declared return type.
            if let Some(ty) = table.functions.get(function) {
                return Some(ty.clone());
            }
            // Constructor-style call `Name<...>(...)` resolves to Name<...>.
            let ty = crate::passes::gather_generics::parse_type_string(function);
            table.lookup(&ty).map(|_| ty)
        }
        Expression::Binary { op, lhs, rhs, .. } => {
            if op.is_assignment() {
                of(lhs, table, current)
            } else if op.is_comparison() || matches!(op, BinaryOp::LogicalAnd | BinaryOp::LogicalOr) {
                Some(TypeName::bool_())
            } else {
                // An operator overload has its method's return type; numeric
                // operands promote; otherwise the lhs's type.
                let lhs_ty = of(lhs, table, current)?;
                if let Some(ret) = table.lookup(&lhs_ty).and_then(|info| info.returns.get(&op.op_name())) {
                    return Some(ret.clone());
                }
                let rhs_ty = of(rhs, table, current).map(|t| t.to_string()).unwrap_or_default();
                match crate::arithmetic::binary_result(*op, &lhs_ty.to_string(), &rhs_ty) {
                    Some(promoted) => Some(TypeName::new(&promoted)),
                    None => Some(lhs_ty),
                }
            }
        }
        Expression::Ternary { true_expr, .. } => of(true_expr, table, current),
        Expression::Unary { op: crate::model::UnaryOp::LogicalNot, .. } => Some(TypeName::bool_()),
        Expression::Unary { op: crate::model::UnaryOp::Neg | crate::model::UnaryOp::BitNot, operand, .. } => {
            of(operand, table, current)
        }
        // `x as T` has the cast target's type.
        Expression::Cast { ty, .. } => Some(ty.clone()),
        Expression::FunctionRef { ty, .. } => Some(ty.clone()),
        Expression::MakeClosure { ty, .. } if !ty.contains_auto() => Some(ty.clone()),
        Expression::ToTrait { to, .. } => Some(to.clone()),
        Expression::Invoke { callee, .. } => of(callee, table, current)?.function_return().cloned(),
        _ => None,
    }
}
