//! Static type inference for operator overloading and print conversion:
//! a per-module table of struct fields/methods plus `of`, which best-effort
//! computes the static type of an expression.

use std::collections::{HashMap, HashSet};

use crate::model::{BinaryOp, Expression, Module, StructDef};
use crate::type_name::TypeName;

#[derive(Debug, Clone)]
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

impl StructInfo {
    fn of(st: &StructDef) -> StructInfo {
        StructInfo {
            fields: st.field_members.iter().map(|f| (f.name.clone(), f.ty.clone())).collect(),
            // An overloaded method also answers to its set's name (`+`).
            methods: st
                .method_members
                .iter()
                .flat_map(|m| [m.name.clone(), crate::passes::overloads::set_name(&m.name).to_string()])
                .collect(),
            returns: st.method_members.iter().map(|m| (m.name.clone(), m.ty.clone())).collect(),
            unary_operators: crate::passes::unary_operators::declared(&st.method_members),
        }
    }

    /// What a value of trait type can call.
    fn of_trait(t: &crate::model::TraitType) -> StructInfo {
        StructInfo {
            fields: vec![],
            methods: t
                .methods
                .iter()
                .flat_map(|m| [m.name.clone(), crate::passes::overloads::set_name(&m.name).to_string()])
                .collect(),
            returns: t.methods.iter().map(|m| (m.name.clone(), m.ty.clone())).collect(),
            unary_operators: crate::passes::unary_operators::declared(&t.methods),
        }
    }
}

/// The structs (and trait types) and functions of a module, for static
/// types. Over a checked runtime it holds only what the program adds, and
/// reads the rest from the runtime's table (`base`), built once
/// (`checked::CheckedFacts`).
#[derive(Debug, Default)]
pub(crate) struct StructTable {
    structs: HashMap<String, StructInfo>,
    /// Free-function and extern name -> return type.
    functions: HashMap<String, TypeName>,
    base: Option<std::sync::Arc<StructTable>>,
}

impl StructTable {
    pub(crate) fn build(module: &Module) -> Self {
        let facts = crate::checked::CheckedFacts::of(module);
        let mut table = StructTable { base: facts.map(|f| f.table.clone()), ..StructTable::default() };
        table.add_structs(module.structs.iter().filter(|st| !facts.is_some_and(|f| f.covers_struct(st))));
        // Traits used as types: what a value of the type can call. The
        // specialized instances first (`Iterator<int>`), then each base for
        // lookups of an instance nothing declares.
        for ty in crate::traits::used_trait_types(module) {
            if let Some(def) = crate::traits::trait_def(&module.traits, &ty)
                && table.get(&ty.to_string()).is_none()
            {
                table.structs.insert(ty.to_string(), StructInfo::of_trait(&crate::traits::instance(def, &ty)));
            }
        }
        for def in &module.traits {
            if table.get(&def.name).is_none() {
                let ty = TypeName::new(&def.name);
                table.structs.insert(def.name.clone(), StructInfo::of_trait(&crate::traits::instance(def, &ty)));
            }
        }
        table.add_functions(module.functions.iter().filter(|f| !facts.is_some_and(|_| module.checked.has_function(&f.name))));
        for e in &module.externs {
            table.functions.insert(e.name.clone(), e.ty.clone());
        }
        table
    }

    /// The table of `module`'s checked structs and functions alone, without
    /// trait types or externs (see `checked::CheckedFacts`).
    pub(crate) fn of_checked(module: &Module) -> Self {
        let mut table = StructTable::default();
        table.add_structs(module.structs.iter().filter(|st| module.checked.has_struct(&st.name)));
        table.add_functions(module.functions.iter().filter(|f| module.checked.has_function(&f.name)));
        table
    }

    fn add_structs<'m>(&mut self, structs: impl Iterator<Item = &'m StructDef>) {
        for st in structs {
            let name = st.ty.to_string();
            let info = StructInfo::of(st);
            // Also key the generic base (`Array<T>` -> `Array`) so pre-
            // specialization lookups resolve; never clobber a concrete entry.
            if name != st.ty.name && self.get(&st.ty.name).is_none() {
                self.structs.insert(st.ty.name.clone(), info.clone());
            }
            self.structs.insert(name, info);
        }
    }

    fn add_functions<'m>(&mut self, functions: impl Iterator<Item = &'m crate::model::FunctionDef>) {
        for f in functions {
            self.functions.insert(f.name.clone(), f.ty.clone());
        }
    }

    /// The return type of free function or extern `name`.
    pub(crate) fn function(&self, name: &str) -> Option<&TypeName> {
        self.functions.get(name).or_else(|| self.base.as_ref()?.function(name))
    }

    pub(crate) fn get(&self, name: &str) -> Option<&StructInfo> {
        self.structs.get(name).or_else(|| self.base.as_ref()?.get(name))
    }

    /// Base struct name of a type string (`String<...>` -> `String`).
    pub(crate) fn base_name(ty: &TypeName) -> String {
        ty.to_string().split('<').next().unwrap_or("").to_string()
    }

    /// Struct info for a type: the exact specialization first (`Array<int>`),
    /// then the generic base (`Array`) for pre-specialization lookups.
    pub(crate) fn lookup(&self, ty: &TypeName) -> Option<&StructInfo> {
        self.get(&ty.to_string()).or_else(|| self.get(&Self::base_name(ty)))
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
        Expression::StringLiteral { .. } | Expression::StaticString { .. } => Some(TypeName::new("String")),
        Expression::PointerLiteral => Some(TypeName::void_ptr()),
        Expression::BoolLiteral(_) => Some(TypeName::bool_()),
        Expression::IntLiteral(v) => Some(TypeName::new(crate::type_name::int_literal_type(*v))),
        Expression::FloatLiteral(_) => Some(TypeName::new("f64")),
        Expression::Destructure { value, .. } | Expression::Move { value, .. } => of(value, table, current),
        Expression::StaticCase { ty, .. } => Some(ty.clone()),
        Expression::Subject { ty, .. } if !ty.is_auto() => Some(ty.clone()),
        Expression::WithSubject(with) => of(&with.body, table, current),
        // An `is` test, or one arm's test of a `match`.
        Expression::MatchArm(_) => Some(TypeName::bool_()),
        // A value a `match` pattern binds: its payload field's type.
        Expression::CaseValue(value) => {
            let subject = of(&value.subject, table, current)?;
            let field = |name: &str| table.lookup(&subject)?.fields.iter().find(|(f, _)| f == name).map(|(_, ty)| ty.clone());
            crate::enums::case_value_type(value, &subject, field).ok().flatten()
        }
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
            // indexing stays raw (codegen GEPs through the pointer), even
            // when the pointee is a struct with its own indexer: `p[i]` on
            // an `Array<String>*` is an `Array<String>`, not a `String`.
            if let Some(pointee) = lhs_type.to_string().strip_suffix('*') {
                return Some(crate::passes::gather_generics::parse_type_string(pointee));
            }
            if let Some(info) = table.lookup(&lhs_type) {
                if let Some(ret) = info.returns.get("__index_get") {
                    return Some(ret.clone());
                }
            }
            None
        }
        // A raw index `resolve_operators` lowered before its element type was
        // known (`ty` still auto) is the pointee of its receiver.
        Expression::ArrayIndex { ty, lhs, .. } if ty.is_auto() => {
            of(lhs, table, current)?.to_string().strip_suffix('*').map(crate::passes::gather_generics::parse_type_string)
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
            if let Some(ty) = table.function(function) {
                return Some(ty.clone());
            }
            // Constructor-style call `Name<...>(...)` resolves to Name<...>;
            // one of several overloaded constructors (`Name$2`) too.
            let name = match function.rsplit_once('$') {
                Some((base, index)) if !index.is_empty() && index.bytes().all(|b| b.is_ascii_digit()) => base,
                _ => function.as_str(),
            };
            let ty = crate::passes::gather_generics::parse_type_string(name);
            table.lookup(&ty).map(|_| ty)
        }
        Expression::Binary { op, lhs, rhs, .. } => {
            if op.is_assignment() {
                of(lhs, table, current)
            } else if op.is_comparison() || op.is_overflow_test() || matches!(op, BinaryOp::LogicalAnd | BinaryOp::LogicalOr) {
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
        // Numeric arms have their common type; others the true arm's.
        Expression::Ternary { true_expr, false_expr, .. } => {
            let true_ty = of(true_expr, table, current)?;
            match of(false_expr, table, current) {
                Some(false_ty) if crate::arithmetic::is_numeric_type(&true_ty.to_string())
                    && crate::arithmetic::is_numeric_type(&false_ty.to_string()) =>
                {
                    Some(TypeName::new(&crate::arithmetic::conditional_result(&true_ty.to_string(), &false_ty.to_string())))
                }
                _ => Some(true_ty),
            }
        }
        Expression::Unary { op: crate::model::UnaryOp::LogicalNot, .. } => Some(TypeName::bool_()),
        Expression::Unary { op: crate::model::UnaryOp::Neg | crate::model::UnaryOp::BitNot, operand, .. } => {
            of(operand, table, current)
        }
        // `x as T` has the cast target's type.
        Expression::Cast { ty, .. } => Some(ty.clone()),
        Expression::Default(ty) => Some(ty.clone()),
        Expression::IsPod(_) => Some(TypeName::bool_()),
        Expression::SizeOf(_) => Some(TypeName::new("u64")),
        Expression::FunctionRef { ty, .. } => Some(ty.clone()),
        Expression::MakeClosure { ty, .. } if !ty.contains_auto() => Some(ty.clone()),
        Expression::ToTrait { to, .. } => Some(to.clone()),
        Expression::FromTrait { test: true, .. } => Some(TypeName::bool_()),
        Expression::FromTrait { to, .. } => Some(to.clone()),
        Expression::Invoke { callee, .. } => of(callee, table, current)?.function_return().cloned(),
        _ => None,
    }
}
