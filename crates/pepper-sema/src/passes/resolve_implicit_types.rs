//! Port of `source/Sema/ResolveImplicitTypes.h`: resolve `auto` variable types
//! and unresolved symbol-ref types via scoped lookup.

use crate::model::*;
use crate::passes::type_arguments::GenericSignature;
use crate::type_name::TypeName;
use std::collections::{HashMap, HashSet};

/// Program-wide lookup tables: built once per run of the pass and shared,
/// by reference, by every function's scopes. Where a name is declared twice,
/// the first declaration wins, as in the scans these maps replace.
struct Tables {
    /// What calls with named arguments bind to.
    callees: crate::passes::named_arguments::Callees,
    /// Struct field tables: struct type string → fields.
    structs: Vec<(String, Vec<VariableDef>)>,
    /// Struct type string → its positions in `structs`, in order.
    struct_index: HashMap<String, Vec<usize>>,
    /// Struct type strings, and their base names (before any `<`).
    struct_names: HashSet<String>,
    struct_bases: HashSet<String>,
    /// Struct method tables: struct type string → (method name, return type).
    methods: Vec<(String, Vec<(String, TypeName)>)>,
    /// Struct type string → its positions in `methods`, in order.
    method_index: HashMap<String, Vec<usize>>,
    /// Free-function and extern name → return type.
    functions: HashMap<String, TypeName>,
    /// Free functions usable as values: name → function type.
    function_types: HashMap<String, TypeName>,
    /// Generic methods: struct type string → (method name → declaration).
    generic_methods: HashMap<String, Vec<(String, GenericSignature)>>,
    /// Every name in `generic_methods`.
    generic_method_names: HashSet<String>,
    /// Generic free functions: name → declaration.
    generic_functions: HashMap<String, GenericSignature>,
    /// Global variables: name → type (visible from every scope).
    globals: HashMap<String, TypeName>,
    /// Struct declared name → its type.
    struct_types: HashMap<String, TypeName>,
    /// Every property, for `passes::properties`.
    properties: crate::passes::properties::Properties,
}

/// Insert `(key, value)` pairs, keeping the first value of a repeated key.
fn first_wins<V>(pairs: impl IntoIterator<Item = (String, V)>) -> HashMap<String, V> {
    let mut map = HashMap::new();
    for (key, value) in pairs {
        map.entry(key).or_insert(value);
    }
    map
}

/// Positions of each key in `entries`, in order.
fn index_of<V>(entries: &[(String, V)]) -> HashMap<String, Vec<usize>> {
    let mut index: HashMap<String, Vec<usize>> = HashMap::new();
    for (i, (key, _)) in entries.iter().enumerate() {
        index.entry(key.clone()).or_default().push(i);
    }
    index
}

impl Tables {
    fn of(module: &Module) -> Self {
        let structs: Vec<(String, Vec<VariableDef>)> =
            module.structs.iter().map(|st| (st.ty.to_string(), st.field_members.clone())).collect();
        let mut methods: Vec<(String, Vec<(String, TypeName)>)> = module
            .structs
            .iter()
            .map(|st| (st.ty.to_string(), st.method_members.iter().map(|m| (m.name.clone(), m.ty.clone())).collect()))
            .collect();
        // Trait types used as values (`Source<int>`): what `var x = s.take()`
        // returns, with the trait's type arguments substituted.
        for ty in crate::traits::used_trait_types(module) {
            if let Some(def) = crate::traits::trait_def(&module.traits, &ty) {
                let instance = crate::traits::instance(def, &ty);
                methods.push((ty.to_string(), instance.methods.iter().map(|m| (m.name.clone(), m.ty.clone())).collect()));
            }
        }
        let generic_methods: HashMap<String, Vec<(String, GenericSignature)>> = module
            .structs
            .iter()
            .filter(|st| !st.generic_methods.is_empty())
            .map(|st| {
                let methods = st.generic_methods.iter().map(|m| (m.name.clone(), GenericSignature::of(m))).collect();
                (st.ty.to_string(), methods)
            })
            .collect();
        let functions = first_wins(
            module
                .functions
                .iter()
                .map(|f| (f.name.clone(), f.ty.clone()))
                .chain(module.externs.iter().map(|e| (e.name.clone(), e.ty.clone()))),
        );
        let generic_functions = first_wins(
            module.functions.iter().filter(|f| f.is_generic_func).map(|f| (f.name.clone(), GenericSignature::of(f))),
        );
        Tables {
            callees: crate::passes::named_arguments::Callees::of(module),
            struct_index: index_of(&structs),
            struct_names: structs.iter().map(|(ty, _)| ty.clone()).collect(),
            struct_bases: structs.iter().map(|(ty, _)| ty.split('<').next().unwrap_or(ty).to_string()).collect(),
            structs,
            method_index: index_of(&methods),
            methods,
            functions,
            function_types: first_wins(crate::passes::function_types::referenceable_functions(module)),
            generic_method_names: generic_methods.values().flatten().map(|(name, _)| name.clone()).collect(),
            generic_methods,
            generic_functions,
            globals: first_wins(module.globals.iter().map(|v| (v.name.clone(), v.ty.clone()))),
            struct_types: first_wins(module.structs.iter().map(|s| (s.name.clone(), s.ty.clone()))),
            properties: crate::passes::properties::Properties::of(module),
        }
    }
}

/// The struct whose methods are being resolved: its fields with resolved
/// types, and its methods. It stands in for the struct's entries in
/// `Tables`.
struct Own {
    name: String,
    fields: Vec<VariableDef>,
    methods: Vec<(String, TypeName)>,
}

struct Scopes<'t> {
    tables: &'t Tables,
    own: Option<Own>,
    /// (name, params) per scope; index 0 = globals.
    names: Vec<String>,
    params: Vec<Vec<VariableDef>>,
    /// Local symbols per scope: name → type. Scope 0 holds only what the
    /// global initializers declare after `tables.globals`.
    symbols: Vec<Vec<(String, TypeName)>>,
    /// While walking a function with no declared return type: the types of
    /// its `return <value>` statements.
    returns: Option<Vec<TypeName>>,
    /// Overloaded free functions, for resolving calls to them.
    overloads: std::rc::Rc<crate::passes::overloads::Overloads>,
    /// The generic parameters of the code being walked: a call whose
    /// arguments mention one is resolved in each specialization instead.
    unbound: Vec<String>,
    /// Calls resolved to an overload set's member: the callee's location and
    /// the member.
    resolved: std::rc::Rc<std::cell::RefCell<Vec<(Loc, String)>>>,
    /// Walking a generic base (a generic struct's methods, a generic
    /// function): its types still name its type parameters, so calls are
    /// not inferred here; each specialization infers its own.
    generic_base: bool,
    /// Walking a constructor's body.
    in_constructor: bool,
    /// The function or method being walked, and where it is declared.
    function: String,
    function_loc: Loc,
}

impl<'t> Scopes<'t> {
    fn new(tables: &'t Tables) -> Self {
        Scopes {
            tables,
            own: None,
            names: vec!["Globals".to_string()],
            params: vec![vec![]],
            symbols: vec![vec![]],
            returns: None,
            overloads: Default::default(),
            unbound: vec![],
            resolved: Default::default(),
            generic_base: false,
            in_constructor: false,
            function: String::new(),
            function_loc: Loc::NONE,
        }
    }

    fn push(&mut self, name: &str) {
        self.names.push(name.to_string());
        self.params.push(vec![]);
        self.symbols.push(vec![]);
    }

    fn pop(&mut self) {
        self.names.pop();
        self.params.pop();
        self.symbols.pop();
    }

    fn find_symbol(&self, name: &str) -> Option<TypeName> {
        self.symbol(name).cloned()
    }

    fn symbol(&self, name: &str) -> Option<&TypeName> {
        for scope in self.symbols[1..].iter().rev() {
            if let Some((_, ty)) = scope.iter().find(|(sym, _)| sym == name) {
                return Some(ty);
            }
        }
        if let Some(ty) = self.tables.globals.get(name) {
            return Some(ty);
        }
        self.symbols[0].iter().find(|(sym, _)| sym == name).map(|(_, ty)| ty)
    }

    fn find_param(&self, name: &str) -> Option<TypeName> {
        self.param(name).cloned()
    }

    fn param(&self, name: &str) -> Option<&TypeName> {
        self.params.iter().rev().flatten().find(|param| param.name == name).map(|param| &param.ty)
    }

    /// The field tables of struct type `key`, in order.
    fn field_tables<'a>(&'a self, key: &str) -> impl Iterator<Item = &'a [VariableDef]> + 'a {
        let own = self.own.as_ref().filter(|own| own.name == key);
        let shared = if own.is_some() { None } else { self.tables.struct_index.get(key) };
        own.map(|own| own.fields.as_slice())
            .into_iter()
            .chain(shared.into_iter().flatten().map(|&i| self.tables.structs[i].1.as_slice()))
    }

    /// The method tables of struct type `key`, in order.
    fn method_tables<'a>(&'a self, key: &str) -> impl Iterator<Item = &'a [(String, TypeName)]> + 'a {
        let own = self.own.as_ref().filter(|own| own.name == key);
        let shared = if own.is_some() { None } else { self.tables.method_index.get(key) };
        own.map(|own| own.methods.as_slice())
            .into_iter()
            .chain(shared.into_iter().flatten().map(|&i| self.tables.methods[i].1.as_slice()))
    }

    /// Declared type of field `name` on struct type `ty`.
    fn field_type(&self, ty: &TypeName, name: &str) -> Option<TypeName> {
        let key = ty.to_string();
        self.field_tables(&key).next().and_then(|fields| fields.iter().find(|f| f.name == name)).map(|f| f.ty.clone())
    }

    /// Declared return type of method `name` on struct type `ty`.
    fn method_return(&self, ty: &TypeName, name: &str) -> Option<TypeName> {
        let key = ty.to_string();
        self.method_tables(&key)
            .next()
            .and_then(|methods| methods.iter().find(|(m, _)| m == name))
            .map(|(_, ret)| ret.clone())
    }

    /// Whether struct type `ty` declares a method `name`.
    fn has_method(&self, ty: &TypeName, name: &str) -> bool {
        let key = ty.to_string();
        // An overloaded method is declared under its members' names.
        self.method_tables(&key).any(|methods| {
            // `set_name(m) == name` without splitting every member name.
            methods.iter().any(|(m, _)| m.strip_prefix(name).is_some_and(|rest| rest.is_empty() || crate::passes::overloads::set_name(m) == name))
        })
    }

    /// Function type of the free function `name`, when a bare `name` in
    /// value position refers to it: no local, parameter, or field (of the
    /// enclosing struct) shadows it.
    fn function_value(&self, name: &str, current_struct: Option<&TypeName>) -> Option<TypeName> {
        if self.param(name).is_some() || self.symbol(name).is_some() {
            return None;
        }
        if let Some(st) = current_struct {
            if self.field_type(st, name).is_some() || self.has_method(st, name) {
                return None;
            }
        }
        self.tables.function_types.get(name).cloned()
    }

    /// When a call `name(args)` calls through a function value rather than a
    /// function, the callee expression and its function type: a local,
    /// parameter or global of function type, or (in a method) a field of
    /// function type that no method of the same name shadows.
    fn value_callee(&self, name: &str, current_struct: Option<&TypeName>) -> Option<(Expression, TypeName)> {
        if let Some(ty) = self.param(name).or_else(|| self.symbol(name)) {
            return ty.is_callable().then(|| (Expression::SymbolRef { id: name.to_string(), ty: ty.clone(), loc: Loc::NONE }, ty.clone()));
        }
        let st = current_struct?;
        let ty = self.field_type(st, name).filter(|t| t.is_callable())?;
        if self.has_method(st, name) {
            return None;
        }
        let callee = Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: name.to_string(), loc: Loc::NONE };
        Some((callee, ty))
    }
}

/// Best-effort type of an expression (port of `typeOfExpr`).
fn type_of_expr(expr: &Expression, scopes: &Scopes, current_struct: Option<&TypeName>) -> TypeName {
    match expr {
        Expression::Destructure { value, .. } | Expression::Move { value, .. } => type_of_expr(value, scopes, current_struct),
        Expression::StaticCase { ty, .. } => ty.clone(),
        Expression::Subject { ty, .. } => ty.clone(),
        Expression::WithSubject(with) => type_of_expr(&with.body, scopes, current_struct),
        Expression::CaseValue(value) => {
            let subject = type_of_expr(&value.subject, scopes, current_struct);
            let field = |name: &str| scopes.field_type(&subject, name);
            crate::enums::case_value_type(value, &subject, field).ok().flatten().unwrap_or_else(TypeName::auto)
        }
        // A tuple literal before its type is spelled out: the tuple of its
        // elements' types, once they are all known.
        Expression::FunctionCall { function, args, .. } if crate::passes::tuples::constructor_labels(function).is_some() => {
            crate::passes::tuples::labeled_literal_type(function, args.iter().map(|a| type_of_expr(a, scopes, current_struct)))
                .unwrap_or_else(TypeName::auto)
        }
        Expression::MemberRef { lhs, name, .. } => {
            let lhs_type = type_of_expr(lhs, scopes, current_struct);
            if lhs_type.is_empty() || lhs_type.is_auto() {
                return TypeName::auto();
            }
            if let Some(element) = lhs_type.tuple_element(name) {
                return element.clone();
            }
            for fields in scopes.field_tables(&lhs_type.to_string()) {
                if let Some(field) = fields.iter().find(|f| &f.name == name) {
                    return field.ty.clone();
                }
            }
            // A property read before `passes::properties` rewrites it: the
            // type its getter returns.
            if scopes.tables.properties.find(&lhs_type, name).is_some() {
                if let Some(ty) = scopes.method_return(&lhs_type, &getter_name(name)) {
                    return ty;
                }
            }
            TypeName::auto()
        }
        Expression::SymbolRef { id, .. } => {
            // `this` inside a method resolves to the parent struct type.
            if id == "this" {
                if let Some(st) = current_struct {
                    return st.clone();
                }
            }
            // Parameters shadow globals (C++ scoping): a function's own
            // `s` is not the module-global `var s`.
            if let Some(ty) = scopes.find_param(id) {
                return ty;
            }
            if let Some(ty) = scopes.find_symbol(id) {
                return ty;
            }
            // A bare property in its struct's methods.
            if let Some(st) = current_struct
                && scopes.tables.properties.find(st, id).is_some()
                && let Some(ty) = scopes.method_return(st, &getter_name(id))
            {
                return ty;
            }
            // The symbol may be the name of a struct.
            if scopes.tables.struct_names.contains(id.as_str()) {
                return TypeName::new(id);
            }
            // A free function used as a value.
            if let Some(ty) = scopes.function_value(id, current_struct) {
                return ty;
            }
            TypeName::auto()
        }
        Expression::FunctionRef { ty, .. } => ty.clone(),
        Expression::MakeClosure { ty, .. } if !ty.contains_auto() => ty.clone(),
        Expression::Invoke { callee, .. } => type_of_expr(callee, scopes, current_struct)
            .function_return()
            .cloned()
            .unwrap_or_else(TypeName::auto),
        Expression::ThisRef => {
            if let Some(st) = current_struct {
                st.clone()
            } else {
                TypeName::auto()
            }
        }
        Expression::MethodCall { this, method, args, loc } => {
            let this_type = type_of_expr(this, scopes, current_struct);
            if this_type.is_empty() || this_type.is_auto() {
                return TypeName::auto();
            }
            // A method of an enum or another value type is the function
            // `E::m` (see `enums`, `value_types`).
            let key = crate::value_types::key(&this_type.to_string()).unwrap_or_else(|| this_type.to_string());
            if crate::enums::method_is_static(&key, method) == Some(false) {
                let mut all = vec![(**this).clone()];
                all.extend(args.iter().cloned());
                let call = Expression::FunctionCall {
                    function: crate::enums::method_name(&key, method),
                    args: all,
                    loc: *loc,
                };
                return type_of_expr(&call, scopes, current_struct);
            }
            if scopes.overloads.is_method_set(&this_type, method) {
                return select_method_overload(&this_type, method, args, *loc, scopes, current_struct)
                    .map(|c| c.ret)
                    .unwrap_or_else(TypeName::auto);
            }
            // Return type of the method, if the struct is known.
            for methods in scopes.method_tables(&this_type.to_string()) {
                if let Some((_, ret)) = methods.iter().find(|(m, _)| m == method) {
                    return ret.clone();
                }
            }
            // `obj.callback(x)` calls through a field of function type.
            if let Some(ret) = scopes.field_type(&this_type, method).as_ref().and_then(|t| t.function_return()) {
                return ret.clone();
            }
            TypeName::auto()
        }
        // `source.iterate()` if the source is Iterable, else the source
        // itself (an Iterator). Unknown until the source's struct is known.
        Expression::ForIterator(source) => {
            let source_type = type_of_expr(source, scopes, current_struct);
            if source_type.is_empty() || source_type.is_auto() {
                return TypeName::auto();
            }
            let Some(methods) = scopes.method_tables(&source_type.to_string()).next() else {
                return TypeName::auto();
            };
            match methods.iter().find(|(m, _)| m == "iterate") {
                Some((_, iterator)) => iterator.clone(),
                None => source_type,
            }
        }
        // `!x` is a `bool`; `-x`, `~x`, `++x` keep their operand's type
        // until `resolve_operators` turns an overloaded one into a call.
        Expression::Unary { op: UnaryOp::LogicalNot, .. } => TypeName::bool_(),
        Expression::Unary { operand, .. } => type_of_expr(operand, scopes, current_struct),
        Expression::Binary { op, lhs, rhs, loc } => {
            // Assignment resolves to the lhs type; comparisons to bool.
            if op.is_assignment() {
                type_of_expr(lhs, scopes, current_struct)
            } else if matches!(
                op,
                BinaryOp::Equal
                    | BinaryOp::NotEqual
                    | BinaryOp::Less
                    | BinaryOp::LessEqual
                    | BinaryOp::Greater
                    | BinaryOp::GreaterEqual
                    | BinaryOp::LogicalAnd
                    | BinaryOp::LogicalOr
                    | BinaryOp::Identical
                    | BinaryOp::NotIdentical
            ) {
                TypeName::bool_()
            } else {
                // Numeric operands promote (`1 + 0.5` is f64, `u8 + 10` is
                // i32); otherwise the lhs type (pointer arithmetic stays a
                // pointer). Auto when the lhs is unknown.
                let lhs_ty = type_of_expr(lhs, scopes, current_struct);
                if lhs_ty.is_empty() || lhs_ty.is_auto() {
                    TypeName::auto()
                } else if scopes.overloads.is_method_set(&lhs_ty, &op.op_name()) {
                    // An overloaded operator (`-(Instant)` and `-(Duration)`)
                    // has the type of the member `rhs` selects, once it does.
                    select_method_overload(&lhs_ty, &op.op_name(), std::slice::from_ref(&**rhs), *loc, scopes, current_struct)
                        .map(|c| c.ret)
                        .unwrap_or_else(TypeName::auto)
                } else if let Some(ret) = scopes.method_return(&lhs_ty, &op.op_name()) {
                    // An operator overload (`a + b` → `a.+(b)`) has its
                    // method's return type.
                    ret
                } else {
                    let rhs_ty = type_of_expr(rhs, scopes, current_struct);
                    match crate::arithmetic::binary_result(*op, &lhs_ty.to_string(), &rhs_ty.to_string()) {
                        Some(promoted) => TypeName::new(&promoted),
                        None => lhs_ty,
                    }
                }
            }
        }
        Expression::IntLiteral(v) => TypeName::new(crate::type_name::int_literal_type(*v)),
        Expression::FloatLiteral(_) => TypeName::new("f64"),
        Expression::BoolLiteral(_) => TypeName::bool_(),
        Expression::StringLiteral { .. } => TypeName::new("String"),
        Expression::PointerLiteral => TypeName::void_ptr(),
        // Constructor-style call `Name<...>(...)` resolves to Name<...>.
        Expression::FunctionCall { function, .. } if function.starts_with("__tuple<") => {
            crate::passes::gather_generics::parse_type_string(function)
        }
        Expression::FunctionCall { function, args, loc } => {
            // A call through a local, parameter or field of function type.
            if let Some((_, ty)) = scopes.value_callee(function, current_struct) {
                return ty.function_return().cloned().unwrap_or_else(TypeName::auto);
            }
            // Inside a method, a bare call naming one of the struct's own
            // methods is that method (convert_member_refs later rewrites it
            // to `this.m(..)`): class scope comes before file scope, so a
            // method `read` wins over an extern `read`.
            if let Some(st) = current_struct {
                let own = st.to_string();
                if let Some(methods) = scopes.method_tables(&own).next() {
                    if let Some((_, ret)) = methods.iter().find(|(m, _)| m == function) {
                        return ret.clone();
                    }
                }
            }
            // A call to an overloaded function has the type of the member
            // its arguments select, once they do.
            if let Some(ret) = overload_return(function, args, *loc, scopes, current_struct) {
                return ret;
            }
            // A generic function called without type arguments has no type
            // until they are inferred (`infer_type_arguments`).
            if !function.contains('<') && scopes.tables.generic_functions.contains_key(function.as_str()) {
                return TypeName::auto();
            }
            // Specialized call `name<args>`: the instance (not the base)
            // carries the substituted return type.
            if let Some(ty) = scopes.tables.functions.get(function.as_str()) {
                return ty.clone();
            }
            let name = function.split('<').next().unwrap_or(function).trim();
            if name.is_empty() {
                return TypeName::auto();
            }
            // Intrinsics carry no declared function; type them by name so a
            // `var x = __address<T>(v)` is not mis-inferred as i32.
            match name {
                "__address" => return TypeName::new("u64"),
                "__refcount" => return TypeName::new("u32"),
                // `__atomic_load<T>` yields T; the store is void and the
                // cmpxchg reports success as bool.
                "__atomic_load" => {
                    let parsed = crate::passes::gather_generics::parse_type_string(function);
                    if let Some(inner) = parsed.sub_types.into_iter().next() {
                        return inner;
                    }
                    return TypeName::auto();
                }
                // `__default<T>()` (until `convert_intrinsics` makes it a
                // `Default` node) is a `T`.
                "__default" => {
                    let parsed = crate::passes::gather_generics::parse_type_string(function);
                    return parsed.sub_types.into_iter().next().unwrap_or_else(TypeName::auto);
                }
                "__is_pod" => return TypeName::bool_(),
                "__atomic_store" => return TypeName::new("void"),
                "__atomic_cmpxchg" => return TypeName::new("bool"),
                _ => {}
            }
            // A generic call spelled with its arguments (`twice<int>(f)`)
            // before it is specialized: the base's return type with the
            // arguments substituted.
            if let Some(signature) = scopes.tables.generic_functions.get(name) {
                let params: Vec<String> = signature.params.iter().map(|p| p.name.clone()).collect();
                if let Some(ty) = scopes.tables.functions.get(name) {
                    let args = crate::passes::gather_generics::parse_type_string(function).sub_types;
                    if !args.is_empty() {
                        let map: Vec<(String, TypeName)> = params.iter().cloned().zip(args).collect();
                        let mut ty = ty.clone();
                        crate::type_name::replace_map(&mut ty, &map);
                        return ty;
                    }
                }
            }
            // Plain free-function call: its declared return type.
            if let Some(ty) = scopes.tables.functions.get(name) {
                return ty.clone();
            }
            // Constructor-style call `Name<...>(...)` resolves to Name<...>.
            if scopes.tables.struct_bases.contains(name) {
                return crate::passes::gather_generics::parse_type_string(function);
            }
            TypeName::auto()
        }
        // Intrinsics carry no declared function; type them directly so a
        // `var x = __address<T>(v)` is not mis-inferred as i32.
        Expression::Address(..) => TypeName::new("u64"),
        Expression::RefCount(..) | Expression::CountStep { .. } => TypeName::new("u32"),
        Expression::FunctionPointer { .. } => TypeName::new("void*"),
        Expression::Weak(op, ty, _) => op.result(ty),
        Expression::AtomicLoad(ty, _) | Expression::Allocate(ty) | Expression::Default(ty) => ty.clone(),
        Expression::IsPod(_) => TypeName::bool_(),
        Expression::SizeOf(_) => TypeName::new("u64"),
        Expression::AtomicStore(..) => TypeName::new("void"),
        Expression::AtomicCmpXchg(..) => TypeName::new("bool"),
        Expression::AtomicFetch(_, ty, _, _) => ty.clone(),
        // `p[i]` through a raw pointer reads the pointee (codegen GEPs
        // through it), so `var v = p[i]` on a `__ptr<ulong>` is a `ulong`.
        // Struct receivers become `__index_get` calls in resolve_operators
        // and are typed as method calls on the next run.
        Expression::Index { lhs, .. } | Expression::ArrayIndex { lhs, .. } => {
            if let Expression::ArrayIndex { ty, .. } = expr {
                if !ty.is_empty() && !ty.is_auto() {
                    return ty.clone();
                }
            }
            let lhs_type = type_of_expr(lhs, scopes, current_struct);
            if let Some(element) = pointee(&lhs_type) {
                return element;
            }
            // A struct receiver whose `[]` operator `resolve_operators` has
            // not lowered yet (its type was not known then): the indexer's
            // return type.
            for methods in scopes.method_tables(&lhs_type.to_string()) {
                if let Some((_, ret)) = methods.iter().find(|(m, _)| m == "__index_get") {
                    return ret.clone();
                }
            }
            TypeName::auto()
        }
        // `x as T` resolves to the cast target.
        Expression::Cast { ty, .. } => ty.clone(),
        // Both ternary arms have the same type (enforced by sema): report it
        // so `var x = c ? A() : B()` infers the arm's type.
        // A `match` expression's chain: the first arm's type (its last `?:`
        // may fall through to `NoMatch`, which has none).
        Expression::Ternary { true_expr, false_expr, .. } => {
            let ty = type_of_expr(true_expr, scopes, current_struct);
            if ty.is_auto() && matches!(true_expr.as_ref(), Expression::NoMatch) {
                type_of_expr(false_expr, scopes, current_struct)
            } else {
                ty
            }
        }
        _ => TypeName::auto(),
    }
}

/// The element type of a raw pointer, in either spelling: `__ptr<T>` (before
/// `convert_intrinsics`) or `T*` (after). `None` for anything else.
fn pointee(ty: &TypeName) -> Option<TypeName> {
    let element = if ty.name == "__ptr" && ty.sub_types.len() == 1 {
        ty.sub_types[0].clone()
    } else if ty.sub_types.is_empty() {
        crate::passes::gather_generics::parse_type_string(ty.name.strip_suffix('*')?)
    } else {
        return None;
    };
    // A `void` pointer indexes bytes and codegen picks the width; there is
    // no `void` local to infer.
    (element.to_string() != "void").then_some(element)
}

pub fn resolve_implicit_types(module: &mut Module) {
    crate::passes::type_arguments::record_conformances(module);
    // Inferring a return type can type the callers' locals, so repeat while
    // return types change (bounded: each run only replaces `auto`).
    // Closure types (see `closures::sync_closures`) and inferred types feed
    // each other, so they share the loop.
    for _ in 0..8 {
        let synced = crate::passes::closures::sync_closures(module);
        let bound = crate::passes::overloads::bind_function_values(module);
        if !resolve_once(module) && !synced && !bound {
            break;
        }
    }
    crate::passes::closures::sync_closures(module);
    crate::passes::named_arguments::take_warnings(module);
}

/// Whether `function`'s return type is inferred from its returns: it
/// declares none and is not an unspecialized generic. A specialization
/// (`g<int>`) keeps its base's `generic_params`, so `is_generic_func` is
/// what tells the two apart.
fn infers_return(function: &FunctionDef) -> bool {
    function.ty.is_auto() && !function.is_generic_func
}

/// Give `function` the type its returns agree on: `void` when it returns no
/// value, the first resolved return type otherwise. Returns whether the type
/// changed.
fn finish_return_inference(function: &mut FunctionDef, scopes: &mut Scopes) -> bool {
    let Some(returns) = scopes.returns.take() else {
        return false;
    };
    let inferred = if returns.is_empty() {
        // `main` is the process entry point: falling off its end exits 0.
        TypeName::new(if crate::passes::entry_point::is_entry_point(function) { "int" } else { "void" })
    } else {
        match returns.into_iter().find(|t| !t.is_empty() && !t.is_auto()) {
            Some(ty) => ty,
            None => return false,
        }
    };
    function.ty = inferred;
    true
}

/// One run of the pass; returns whether a function's return type was
/// inferred.
fn resolve_once(module: &mut Module) -> bool {
    let mut inferred = false;
    let tables = Tables::of(module);
    let overloads = std::rc::Rc::new(crate::passes::overloads::Overloads::build(module));
    let resolved: std::rc::Rc<std::cell::RefCell<Vec<(Loc, String)>>> = Default::default();

    // Structs first (methods see field types).
    for st in &mut module.structs {
        let current_struct = st.ty.clone();
        let mut scopes = Scopes::new(&tables);
        scopes.overloads = overloads.clone();
        scopes.resolved = resolved.clone();
        scopes.unbound = st.generic_params.iter().map(|p| p.name.clone()).collect();
        // A generic base (`Box` of `Box<T>`), not a specialization.
        scopes.generic_base = st.ty.is_generic() && st.name == st.ty.name;

        // Resolve field types with defaults.
        for field in &mut st.field_members {
            if field.ty.is_auto() {
                if let Some(default) = &field.default {
                    let ty = type_of_expr(default, &scopes, Some(&current_struct));
                    if !ty.is_empty() && !ty.is_auto() {
                        field.ty = ty;
                    }
                }
            }
            // A default calling an overloaded constructor or function
            // (`HashSet<String> names = HashSet<String>();`) picks its member.
            if let Some(default) = &mut field.default {
                crate::passes::walk_expression(default, &mut |e| resolve_overload(e, &scopes, Some(&current_struct)));
            }
        }

        // Method bodies see this struct's resolved field types and its
        // methods in place of its table entries. Other structs stay in the
        // tables: a method body may call another struct's methods or
        // constructor (`var p = other.parent()`, `var a = Array<int>()`),
        // and those must type too.
        scopes.own = Some(Own {
            name: current_struct.to_string(),
            fields: st.field_members.clone(),
            methods: st.method_members.iter().map(|m| (m.name.clone(), m.ty.clone())).collect(),
        });

        // Constructor body.
        for c in &mut st.constructors {
            resolve_parameter_defaults(&mut c.parameters, &mut scopes, &Some(current_struct.clone()));
            if let Some(body) = &mut c.body {
                scopes.push(&c.name);
                scopes.params.push(c.parameters.clone());
                scopes.in_constructor = true;
                scopes.function = c.name.clone();
                scopes.function_loc = c.loc;
                resolve_block(body, &mut scopes, &Some(current_struct.clone()));
                scopes.in_constructor = false;
                scopes.pop();
            }
        }

        // Methods.
        for method in &mut st.method_members {
            let method_struct = match &method.parent {
                // A specialization's methods keep the base's name as their
                // parent (`Box` in `Box<int>`): they belong to this struct.
                Some(name) if *name == current_struct.name => current_struct.clone(),
                Some(name) => tables.struct_types.get(name).cloned().unwrap_or_else(|| current_struct.clone()),
                None => current_struct.clone(),
            };
            resolve_parameter_defaults(&mut method.parameters, &mut scopes, &Some(method_struct.clone()));
            scopes.returns = infers_return(method).then(Vec::new);
            if let Some(body) = &mut method.body {
                scopes.function = method.name.clone();
                scopes.function_loc = method.loc;
                scopes.push(&method.name);
                scopes.params.push(method.parameters.clone());
                resolve_block(body, &mut scopes, &Some(method_struct.clone()));
                scopes.pop();
            } else {
                scopes.returns = None;
            }
            inferred |= finish_return_inference(method, &mut scopes);
        }
    }

    // Free functions.
    for function in &mut module.functions {
        let returns = infers_return(function).then(Vec::new);
        if let Some(body) = &mut function.body {
            let mut scopes = Scopes::new(&tables);
            scopes.overloads = overloads.clone();
            scopes.resolved = resolved.clone();
            scopes.unbound = function.generic_params.iter().map(|p| p.name.clone()).collect();
            scopes.generic_base = function.is_generic_func;
            resolve_parameter_defaults(&mut function.parameters, &mut scopes, &None);
            scopes.returns = returns;
            scopes.function = function.name.clone();
            scopes.function_loc = function.loc;
            scopes.push(&function.name);
            scopes.params.push(function.parameters.clone());
            resolve_block(body, &mut scopes, &None);
            scopes.pop();
            inferred |= finish_return_inference(function, &mut scopes);
        }
    }

    // Global variables: one shared scope so later globals see earlier ones.
    let mut scopes = Scopes::new(&tables);
    scopes.overloads = overloads.clone();
    scopes.resolved = resolved.clone();
    for var in &mut module.globals {
        if var.ty.is_auto() {
            if let Some(default) = &var.default {
                let ty = type_of_expr(default, &scopes, None);
                if !ty.is_empty() && !ty.is_auto() {
                    var.ty = ty;
                }
            }
        }
        if let Some(default) = &mut var.default {
            resolve_expression(default, &mut scopes, &None, None);
        }
        scopes.symbols[0].push((var.name.clone(), var.ty.clone()));
    }
    let resolved = std::mem::take(&mut *resolved.borrow_mut());
    inferred |= !resolved.is_empty();
    module.call_targets.extend(resolved);
    inferred
}

/// Default arguments are resolved in the declaring scope (no locals), so a
/// default such as `this.op = square` names the free function.
fn resolve_parameter_defaults(parameters: &mut [VariableDef], scopes: &mut Scopes, current_struct: &Option<TypeName>) {
    for param in parameters {
        if let Some(default) = &mut param.default {
            resolve_expression(default, scopes, current_struct, None);
        }
    }
}

fn resolve_block(block: &mut Block, scopes: &mut Scopes, current_struct: &Option<TypeName>) {
    for stmt in &mut block.items {
        resolve_statement(stmt, scopes, current_struct);
    }
}

fn resolve_statement(stmt: &mut Statement, scopes: &mut Scopes, current_struct: &Option<TypeName>) {
    match stmt {
        Statement::Expression(expr) => resolve_expression(expr, scopes, current_struct, None),
        Statement::Block(inner) => {
            scopes.push("block");
            resolve_block(inner, scopes, current_struct);
            scopes.pop();
        }
        Statement::Declaration(Declaration::Variable(var)) => {
            // Record the local symbol; resolve `auto` from the default value.
            if var.ty.is_auto() {
                if let Some(default) = &var.default {
                    let ty = type_of_expr(default, scopes, current_struct.as_ref());
                    if !ty.is_empty() && !ty.is_auto() {
                        var.ty = ty;
                    }
                }
            }
            // Resolve symbol types inside the default so operator resolution
            // can see them (`var ret = str += x` keeps `str` typed).
            if let Some(default) = &mut var.default {
                resolve_expression(default, scopes, current_struct, None);
            }
            scopes
                .symbols
                .last_mut()
                .expect("scope stack")
                .push((var.name.clone(), var.ty.clone()));
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            resolve_expression(&mut branch.condition, scopes, current_struct, None);
            scopes.push("if");
            resolve_block(&mut branch.if_block, scopes, current_struct);
            scopes.pop();
            if let Some(else_block) = &mut branch.else_block {
                scopes.push("else");
                resolve_block(else_block, scopes, current_struct);
                scopes.pop();
            }
        }
        Statement::While(wh) => {
            resolve_expression(&mut wh.condition, scopes, current_struct, None);
            scopes.push("while");
            resolve_block(&mut wh.block, scopes, current_struct);
            scopes.pop();
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                resolve_expression(expr, scopes, current_struct, None);
                let ty = type_of_expr(expr, scopes, current_struct.as_ref());
                if let Some(returns) = &mut scopes.returns {
                    returns.push(ty);
                }
            }
        }
        Statement::LoopBreak(_) => {}
    }
}

/// A call to a generic free function without type arguments,
/// `larger(3, 9)`, becomes a call to the specialization its arguments
/// select, `larger<i32>(3, 9)` (see `type_arguments`).
fn infer_type_arguments(e: &mut Expression, scopes: &Scopes, current: Option<&TypeName>) {
    if scopes.generic_base {
        return;
    }
    if let Expression::MethodCall { this, method, args, .. } = e {
        // `x.map(f)` calling a generic method: `x.map<U>(f)`.
        // Typing the receiver is costly: first rule out a method no struct
        // declares generic.
        // `x.count_all<int>(it)` writing only the leading type arguments:
        // the rest from the arguments, as for a free function.
        // An operator method (`<`) is never generic.
        if !method.starts_with(|c: char| c.is_alphabetic() || c == '_') {
            return;
        }
        let written = crate::passes::gather_generics::parse_type_string(method);
        if !scopes.tables.generic_method_names.contains(written.name.as_str()) {
            return;
        }
        let owner = type_of_expr(this, scopes, current);
        if owner.contains_auto() || scopes.has_method(&owner, method) {
            return;
        }
        let key = owner.to_string();
        let Some(methods) = scopes.tables.generic_methods.get(key.trim_end_matches('*')) else { return };
        let Some((_, signature)) = methods.iter().find(|(n, _)| *n == written.name) else { return };
        let types = argument_types(args, scopes, current);
        let type_args = if method.contains('<') { signature.complete(&written.sub_types, &types) } else { signature.infer(&types) };
        if let Some(type_args) = type_args {
            *method = crate::passes::type_arguments::specialization(&written.name, type_args);
        }
        return;
    }
    let Expression::FunctionCall { function, args, .. } = e else { return };
    if function.contains('<') {
        if function.starts_with(|c: char| c.is_alphabetic() || c == '_') {
            complete_type_arguments(function, args, scopes, current);
        }
        return;
    }
    let Some(signature) = scopes.tables.generic_functions.get(function.as_str()) else { return };
    if scopes.value_callee(function, current).is_some() {
        return;
    }
    // Inside a method, a bare call may be one of the struct's methods,
    // which `convert_member_refs` has not turned into a method call yet.
    if current.is_some_and(|st| scopes.has_method(st, function) || scopes.field_type(st, function).is_some()) {
        return;
    }
    let types = argument_types(args, scopes, current);
    if let Some(type_args) = signature.infer(&types) {
        *function = crate::passes::type_arguments::specialization(function, type_args);
    }
}

/// A call that writes only the leading type arguments, `count_all<int>(it)`
/// for `count_all<T, I>`, takes the rest from its arguments (or their
/// defaults): `count_all<int, ArrayIterator<int>>(it)`.
fn complete_type_arguments(function: &mut String, args: &[Expression], scopes: &Scopes, current: Option<&TypeName>) {
    let written = crate::passes::gather_generics::parse_type_string(function);
    let Some(signature) = scopes.tables.generic_functions.get(written.name.as_str()) else { return };
    if written.sub_types.len() >= signature.params.len() || scopes.value_callee(&written.name, current).is_some() {
        return;
    }
    let types = argument_types(args, scopes, current);
    if let Some(type_args) = signature.complete(&written.sub_types, &types) {
        *function = crate::passes::type_arguments::specialization(&written.name, type_args);
    }
}

/// The overload set a call `function(args)` names, unless a local, parameter
/// or member of the enclosing struct by that name shadows it: its base name
/// and written type arguments.
fn overload_call<'f>(function: &'f str, scopes: &Scopes, current: Option<&TypeName>) -> Option<(&'f str, Option<Vec<TypeName>>)> {
    if scopes.overloads.is_empty() || !scopes.overloads.is_set(scopes.overloads.call_set_name(function)) {
        return None;
    }
    let (base, explicit) = scopes.overloads.call_set(function);
    if !scopes.overloads.is_set(base) || scopes.value_callee(base, current).is_some() {
        return None;
    }
    if current.is_some_and(|st| scopes.has_method(st, base) || scopes.field_type(st, base).is_some()) {
        return None;
    }
    Some((base, explicit))
}

/// Resolve `function(args)` against its overload set, when it names one and
/// its arguments decide.
fn select_overload(
    function: &str,
    args: &[Expression],
    at: Loc,
    scopes: &Scopes,
    current: Option<&TypeName>,
) -> Option<crate::passes::overloads::Choice> {
    let (base, explicit) = overload_call(function, scopes, current)?;
    let infos: Vec<crate::passes::overloads::ArgInfo> = args
        .iter()
        .map(|arg| crate::passes::overloads::arg_info(arg, &scopes.overloads, Some(type_of_expr(arg, scopes, current))))
        .collect();
    // In a generic body, the specializations decide.
    let mentions_unbound = |t: &TypeName| scopes.unbound.iter().any(|p| t.mentions(p));
    if infos.iter().any(|i| i.ty.as_ref().is_some_and(mentions_unbound)) {
        return None;
    }
    match scopes.overloads.select(base, explicit.as_deref(), &infos, at) {
        crate::passes::overloads::Outcome::Chosen(choice) => Some(choice),
        _ => None,
    }
}

/// The return type of a call to an overloaded function, when its arguments
/// select a member.
fn overload_return(function: &str, args: &[Expression], at: Loc, scopes: &Scopes, current: Option<&TypeName>) -> Option<TypeName> {
    overload_call(function, scopes, current)?;
    Some(select_overload(function, args, at, scopes, current).map(|c| c.ret).unwrap_or_else(TypeName::auto))
}

/// Rewrite a call to an overloaded function to the member its arguments
/// select (see `overloads`).
fn resolve_overload(e: &mut Expression, scopes: &Scopes, current: Option<&TypeName>) {
    let Expression::FunctionCall { function, args, loc } = e else { return };
    let Some(choice) = select_overload(function, args, *loc, scopes, current) else { return };
    crate::passes::overloads::apply_choice(function, args, &choice);
    scopes.resolved.borrow_mut().push((*loc, choice.callee));
}

/// Resolve `receiver.method(args)` against the method overload set of the
/// receiver's struct, when it names one and its arguments decide.
fn select_method_overload(
    receiver: &TypeName,
    method: &str,
    args: &[Expression],
    at: Loc,
    scopes: &Scopes,
    current: Option<&TypeName>,
) -> Option<crate::passes::overloads::Choice> {
    let infos: Vec<crate::passes::overloads::ArgInfo> = args
        .iter()
        .map(|arg| crate::passes::overloads::arg_info(arg, &scopes.overloads, Some(type_of_expr(arg, scopes, current))))
        .collect();
    let mentions_unbound = |t: &TypeName| scopes.unbound.iter().any(|p| t.mentions(p));
    if mentions_unbound(receiver) || infos.iter().any(|i| i.ty.as_ref().is_some_and(mentions_unbound)) {
        return None;
    }
    match scopes.overloads.select_method(receiver, method, &infos, at) {
        crate::passes::overloads::Outcome::Chosen(choice) => Some(choice),
        _ => None,
    }
}

/// Rewrite a call of an overloaded method to the member its arguments
/// select.
fn resolve_method_overload(e: &mut Expression, scopes: &Scopes, current: Option<&TypeName>) {
    let Expression::MethodCall { this, method, args, loc } = e else { return };
    if scopes.overloads.is_empty() {
        return;
    }
    // Typing the receiver is costly: first rule out a name no struct
    // overloads.
    if !scopes.overloads.is_any_method_set(method) {
        return;
    }
    let receiver = type_of_expr(this, scopes, current);
    if receiver.is_empty() || receiver.contains_auto() || !scopes.overloads.is_method_set(&receiver, method) {
        return;
    }
    let Some(choice) = select_method_overload(&receiver, method, args, *loc, scopes, current) else { return };
    crate::passes::overloads::apply_choice(method, args, &choice);
    scopes.resolved.borrow_mut().push((*loc, crate::passes::overloads::method_target(&receiver, &choice.callee)));
}

/// What each argument's type says about a generic call's type arguments.
fn argument_types(args: &[Expression], scopes: &Scopes, current: Option<&TypeName>) -> Vec<Option<TypeName>> {
    args.iter()
        .map(|arg| match arg {
            // A closure's type binds what it already knows.
            Expression::MakeClosure { ty, .. } => Some(ty.clone()),
            _ => {
                let ty = type_of_expr(arg, scopes, current);
                (!ty.is_empty() && !ty.contains_auto()).then_some(ty)
            }
        })
        .collect()
}

fn resolve_expression(
    expr: &mut Expression,
    scopes: &mut Scopes,
    current_struct: &Option<TypeName>,
    _var: Option<&mut VariableDef>,
) {
    fill_subjects(expr, scopes, current_struct.as_ref());
    resolve_each(expr, scopes, current_struct);
    fill_subjects(expr, scopes, current_struct.as_ref());
}

/// Type each `Subject` of a `match` expression or `is` test as the value
/// its `WithSubject` examines, once that is known.
fn fill_subjects(expr: &mut Expression, scopes: &Scopes, current: Option<&TypeName>) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        let Expression::WithSubject(with) = e else { return };
        let ty = type_of_expr(&with.subject, scopes, current);
        if ty.is_auto() || ty.is_empty() {
            return;
        }
        let id = with.id;
        crate::passes::walk_expression(&mut with.body, &mut |inner: &mut Expression| {
            if let Expression::Subject { id: found, ty: slot, .. } = inner
                && *found == id
            {
                *slot = ty.clone();
            }
        });
    });
}

/// Bind a method call's named arguments once its receiver's type is known,
/// and report naming the arguments of a call through a function value.
fn bind_named_arguments(e: &mut Expression, scopes: &Scopes, current: Option<&TypeName>) {
    use crate::passes::named_arguments::{bind_method_call, has_named, report_function_value};
    match e {
        Expression::MethodCall { this, method, args, .. } if has_named(args) => {
            let receiver = type_of_expr(this, scopes, current);
            if receiver.is_empty() || receiver.contains_auto() {
                return;
            }
            if !scopes.has_method(&receiver, method)
                && let Some(ty) = scopes.field_type(&receiver, method).filter(|t| t.is_callable())
            {
                report_function_value(&ty, args);
                return;
            }
            bind_method_call(e, &receiver, &scopes.tables.callees);
        }
        Expression::FunctionCall { function, args, .. } if has_named(args) => {
            if let Some((_, ty)) = scopes.value_callee(function, current) {
                report_function_value(&ty, args);
            }
        }
        Expression::Invoke { callee, args } if has_named(args) => {
            let ty = type_of_expr(callee, scopes, current);
            if !ty.is_empty() && !ty.contains_auto() {
                report_function_value(&ty, args);
            }
        }
        _ => {}
    }
}

fn resolve_each(expr: &mut Expression, scopes: &mut Scopes, current_struct: &Option<TypeName>) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        let current = current_struct.as_ref();
        {
            let scopes: &Scopes = scopes;
            let site = crate::passes::properties::Site { current, in_constructor: scopes.in_constructor, function: &scopes.function, function_loc: scopes.function_loc };
            crate::passes::properties::lower(
                e,
                &scopes.tables.properties,
                &site,
                &|x| type_of_expr(x, scopes, current),
                &|name| scopes.param(name).is_some() || scopes.symbol(name).is_some(),
            );
        }
        bind_named_arguments(e, scopes, current);
        resolve_overload(e, scopes, current);
        resolve_method_overload(e, scopes, current);
        infer_type_arguments(e, scopes, current);
        // `(a, b)`: spell out its tuple type once the elements' are known.
        if let Expression::FunctionCall { function, args, .. } = e {
            if crate::passes::tuples::constructor_labels(function).is_some() {
                if let Some(ty) = crate::passes::tuples::literal_type(args.iter().map(|a| type_of_expr(a, scopes, current))) {
                    *function = ty.to_string();
                }
            }
        }
        // Calls through function values: `f(x)` on a local, parameter,
        // global or field of function type, and `obj.callback(x)`.
        if let Expression::FunctionCall { function, args, .. } = e {
            if let Some((callee, _)) = scopes.value_callee(function, current) {
                *e = Expression::Invoke { callee: Box::new(callee), args: std::mem::take(args) };
                return;
            }
        }
        // A value a `match` pattern binds: report patterns that do not fit
        // the enum matched.
        if let Expression::CaseValue(value) = e {
            let subject = type_of_expr(&value.subject, scopes, current);
            let field = |name: &str| scopes.field_type(&subject, name);
            if let Err(d) = crate::enums::case_value_type(value, &subject, field) {
                crate::errors::report(d);
            }
            return;
        }
        // `c.name()` on an enum value calls the function `Color::name(c)`,
        // and `x.doubled()` on an `int` with that method `i32::doubled(x)`.
        // `x.__acquire()` / `x.__release()` stay method calls for every
        // type: codegen steps the count, or does nothing for plain data.
        let refcount_step = matches!(e, Expression::MethodCall { method, args, .. }
            if (method == "__acquire" || method == "__release") && args.is_empty());
        if let Expression::MethodCall { this, method, args, loc } = e
            && !refcount_step
        {
            let this_type = type_of_expr(this, scopes, current);
            let key = crate::value_types::key(&this_type.to_string());
            let value_method = key.as_deref().is_some_and(|k| crate::enums::method_is_static(k, method).is_some());
            if crate::enums::is_enum(&this_type.to_string()) || value_method {
                let key = key.unwrap_or_else(|| this_type.to_string());
                let this = std::mem::replace(this.as_mut(), Expression::ThisRef);
                match crate::enums::call_on_value(&key, method, this.clone(), std::mem::take(args), *loc) {
                    Some(call) => *e = call,
                    None => {
                        if let Expression::MethodCall { this: slot, .. } = e {
                            **slot = this;
                        }
                    }
                }
                return;
            }
        }
        if let Expression::MethodCall { this, method, args, loc } = e {
            let this_type = type_of_expr(this, scopes, current);
            if !scopes.has_method(&this_type, method)
                && scopes.field_type(&this_type, method).is_some_and(|t| t.is_callable())
            {
                let callee = Expression::MemberRef { lhs: std::mem::replace(this, Box::new(Expression::ThisRef)), name: method.clone(), loc: *loc };
                *e = Expression::Invoke { callee: Box::new(callee), args: std::mem::take(args) };
                return;
            }
        }
        // A bare free-function name in value position is a function value.
        if let Expression::SymbolRef { id, ty, loc } = e {
            if ty.is_auto() && id != "this" {
                if let Some(fn_ty) = scopes.function_value(id, current) {
                    *e = Expression::FunctionRef { function: id.clone(), ty: fn_ty, loc: *loc };
                    return;
                }
            }
        }
        if let Expression::SymbolRef { id, ty, loc } = e {
            if ty.is_auto() && id != "this" {
                let resolved = if let Some(st) = current_struct {
                    type_of_expr(&Expression::SymbolRef {
                        id: id.clone(),
                        ty: TypeName::auto(),
                        loc: *loc,
                    }, scopes, Some(st))
                } else {
                    type_of_expr(
                        &Expression::SymbolRef {
                            id: id.clone(),
                            ty: TypeName::auto(),
                            loc: *loc,
                        },
                        scopes,
                        None,
                    )
                };
                if !resolved.is_empty() && !resolved.is_auto() {
                    *ty = resolved;
                }
            }
        }
    });
}
