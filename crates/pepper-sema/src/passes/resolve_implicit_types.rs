//! Port of `source/Sema/ResolveImplicitTypes.h`: resolve `auto` variable types
//! and unresolved symbol-ref types via scoped lookup.

use crate::model::*;
use crate::type_name::TypeName;

struct Scopes {
    /// (name, params) per scope; index 0 = globals.
    names: Vec<String>,
    params: Vec<Vec<VariableDef>>,
    /// Local symbols per scope: name → type.
    symbols: Vec<Vec<(String, TypeName)>>,
    /// Index of the innermost function scope, if any.
    function_depth: Option<usize>,
    /// Struct field tables: struct type string → fields.
    structs: Vec<(String, Vec<VariableDef>)>,
    /// Struct method tables: struct type string → (method name, return type).
    methods: Vec<(String, Vec<(String, TypeName)>)>,
    /// Free-function and extern name → return type.
    functions: Vec<(String, TypeName)>,
}

impl Scopes {
    fn new() -> Self {
        Scopes {
            names: vec!["Globals".to_string()],
            params: vec![vec![]],
            symbols: vec![vec![]],
            function_depth: None,
            structs: vec![],
            methods: vec![],
            functions: vec![],
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
        for scope in self.symbols.iter().rev() {
            for (sym, ty) in scope {
                if sym == name {
                    return Some(ty.clone());
                }
            }
        }
        None
    }

    fn find_param(&self, name: &str) -> Option<TypeName> {
        for scope in self.params.iter().rev() {
            for param in scope {
                if param.name == name {
                    return Some(param.ty.clone());
                }
            }
        }
        None
    }

    fn in_method(&self) -> bool {
        self.function_depth.is_some()
    }
}

/// Best-effort type of an expression (port of `typeOfExpr`).
fn type_of_expr(expr: &Expression, scopes: &Scopes, current_struct: Option<&TypeName>) -> TypeName {
    match expr {
        Expression::MemberRef { lhs, name } => {
            let lhs_type = type_of_expr(lhs, scopes, current_struct);
            if lhs_type.is_empty() || lhs_type.to_string() == crate::type_name::AUTO {
                return TypeName::auto();
            }
            for (ty, fields) in &scopes.structs {
                if *ty == lhs_type.to_string() {
                    for field in fields {
                        if &field.name == name {
                            return field.ty.clone();
                        }
                    }
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
            // The symbol may be the name of a struct.
            for (ty, _) in &scopes.structs {
                if ty == id {
                    return TypeName::new(id);
                }
            }
            TypeName::auto()
        }
        Expression::ThisRef => {
            if let Some(st) = current_struct {
                st.clone()
            } else {
                TypeName::auto()
            }
        }
        Expression::MethodCall { this, method, .. } => {
            let this_type = type_of_expr(this, scopes, current_struct);
            if this_type.is_empty() || this_type.to_string() == crate::type_name::AUTO {
                return TypeName::auto();
            }
            // Return type of the method, if the struct is known.
            for (ty, methods) in &scopes.methods {
                if *ty == this_type.to_string() {
                    if let Some((_, ret)) = methods.iter().find(|(m, _)| m == method) {
                        return ret.clone();
                    }
                }
            }
            TypeName::auto()
        }
        Expression::Binary { op, lhs, .. } => {
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
            ) {
                TypeName::bool_()
            } else {
                // Arithmetic keeps the lhs type (pointer arithmetic stays a
                // pointer); fall back to auto when the lhs is unknown.
                let lhs_ty = type_of_expr(lhs, scopes, current_struct);
                if lhs_ty.is_empty() || lhs_ty.to_string() == crate::type_name::AUTO {
                    TypeName::auto()
                } else {
                    lhs_ty
                }
            }
        }
        Expression::IntLiteral(_) => TypeName::new("i32"),
        Expression::FloatLiteral(_) => TypeName::new("f64"),
        Expression::BoolLiteral(_) => TypeName::bool_(),
        Expression::StringLiteral { .. } => TypeName::new("String"),
        Expression::PointerLiteral => TypeName::void_ptr(),
        // Constructor-style call `Name<...>(...)` resolves to Name<...>.
        Expression::FunctionCall { function, .. } => {
            // Specialized call `name<args>`: the instance (not the base)
            // carries the substituted return type.
            if let Some((_, ty)) = scopes.functions.iter().find(|(n, _)| n == function) {
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
                "__atomic_store" => return TypeName::new("void"),
                "__atomic_cmpxchg" => return TypeName::new("bool"),
                _ => {}
            }
            // Plain free-function call: its declared return type.
            if let Some((_, ty)) = scopes.functions.iter().find(|(n, _)| n == name) {
                return ty.clone();
            }
            // Constructor-style call `Name<...>(...)` resolves to Name<...>.
            for (ty, _) in &scopes.structs {
                let base = ty.split('<').next().unwrap_or(ty);
                if base == name {
                    return crate::passes::gather_generics::parse_type_string(function);
                }
            }
            TypeName::auto()
        }
        // Intrinsics carry no declared function; type them directly so a
        // `var x = __address<T>(v)` is not mis-inferred as i32.
        Expression::Address(..) => TypeName::new("u64"),
        Expression::RefCount(..) => TypeName::new("u32"),
        Expression::AtomicLoad(ty, _) => ty.clone(),
        Expression::AtomicStore(..) => TypeName::new("void"),
        Expression::AtomicCmpXchg(..) => TypeName::new("bool"),
        Expression::AtomicFetch(_, ty, _, _) => ty.clone(),
        // `x as T` resolves to the cast target.
        Expression::Cast { ty, .. } => ty.clone(),
        // Both ternary arms have the same type (enforced by sema): report it
        // so `var x = c ? A() : B()` infers the arm's type.
        Expression::Ternary { true_expr, .. } => type_of_expr(true_expr, scopes, current_struct),
        _ => TypeName::auto(),
    }
}

/// Walk a struct's ctor + methods with scopes; `f` runs per expression.
fn walk_struct(st: &StructDef, scopes: &mut Scopes, current_struct: &TypeName, f: &mut impl FnMut(&mut Expression, &Scopes, &TypeName, Option<&mut VariableDef>)) {
    let _ = scopes;
    let _ = f;
    let _ = st;
}

pub fn resolve_implicit_types(module: &mut Module) {
    // Struct field table.
    let struct_fields: Vec<(String, Vec<VariableDef>)> = module
        .structs
        .iter()
        .map(|st| {
            (
                st.ty.to_string(),
                st.field_members.clone(),
            )
        })
        .collect();
    // Struct method table: return type per method name.
    let struct_methods: Vec<(String, Vec<(String, TypeName)>)> = module
        .structs
        .iter()
        .map(|st| {
            (
                st.ty.to_string(),
                st.method_members
                    .iter()
                    .map(|m| (m.name.clone(), m.ty.clone()))
                    .collect(),
            )
        })
        .collect();
    // Free-function and extern return types.
    let mut function_returns: Vec<(String, TypeName)> = module
        .functions
        .iter()
        .map(|f| (f.name.clone(), f.ty.clone()))
        .collect();
    for e in &module.externs {
        function_returns.push((e.name.clone(), e.ty.clone()));
    }

    // Global variables are visible from every scope (C++ global scope).
    let global_symbols: Vec<(String, TypeName)> = module
        .globals
        .iter()
        .map(|v| (v.name.clone(), v.ty.clone()))
        .collect();

    // Structs first (methods see field types).
    let struct_pairs: Vec<(String, TypeName)> = module
        .structs
        .iter()
        .map(|s| (s.name.clone(), s.ty.clone()))
        .collect();
    for st in &mut module.structs {
        let current_struct = st.ty.clone();
        let mut scopes = Scopes::new();
        scopes.structs = struct_fields.clone();
        scopes.methods = struct_methods.clone();
        scopes.functions = function_returns.clone();
        scopes.symbols[0].extend(global_symbols.iter().cloned());

        // Resolve field types with defaults.
        for field in &mut st.field_members {
            if field.ty.to_string() == crate::type_name::AUTO {
                if let Some(default) = &field.default {
                    let ty = type_of_expr(default, &scopes, Some(&current_struct));
                    if !ty.is_empty() && ty.to_string() != crate::type_name::AUTO {
                        field.ty = ty;
                    }
                }
            }
        }

        // Rebuild field table with resolved types for method bodies.
        scopes.structs = vec![(current_struct.to_string(), st.field_members.clone())];
        scopes.methods = vec![(
            current_struct.to_string(),
            st.method_members
                .iter()
                .map(|m| (m.name.clone(), m.ty.clone()))
                .collect(),
        )];

        // Constructor body.
        if let Some(body) = &mut st.constructor.body {
            scopes.push(&st.constructor.name);
            scopes.params.push(st.constructor.parameters.clone());
            scopes.function_depth = Some(scopes.names.len() - 1);
            resolve_block(body, &mut scopes, &Some(current_struct.clone()));
            scopes.pop();
            scopes.function_depth = None;
        }

        // Methods.
        for method in &mut st.method_members {
            let parent = method.parent.clone();
            let method_struct = match &parent {
                Some(name) => {
                    // Find the struct by declared name (snapshot avoids the
                    // double borrow of module.structs).
                    let pairs: Vec<(String, TypeName)> = struct_pairs.clone();
                    pairs
                        .into_iter()
                        .find(|(sname, _)| sname == name)
                        .map(|(_, ty)| ty)
                        .unwrap_or_else(|| current_struct.clone())
                }
                None => current_struct.clone(),
            };
            if let Some(body) = &mut method.body {
                scopes.push(&method.name);
                scopes.params.push(method.parameters.clone());
                scopes.function_depth = Some(scopes.names.len() - 1);
                resolve_block(body, &mut scopes, &Some(method_struct.clone()));
                scopes.pop();
                scopes.function_depth = None;
            }
        }
    }

    // Free functions.
    for function in &mut module.functions {
        if let Some(body) = &mut function.body {
            let mut scopes = Scopes::new();
            scopes.structs = struct_fields.clone();
            scopes.methods = struct_methods.clone();
            scopes.functions = function_returns.clone();
            scopes.symbols[0].extend(global_symbols.iter().cloned());
            scopes.push(&function.name);
            scopes.params.push(function.parameters.clone());
            scopes.function_depth = Some(scopes.names.len() - 1);
            resolve_block(body, &mut scopes, &None);
            scopes.pop();
        }
    }

    // Global variables: one shared scope so later globals see earlier ones.
    let mut scopes = Scopes::new();
    scopes.structs = struct_fields.clone();
    scopes.methods = struct_methods.clone();
    scopes.functions = function_returns.clone();
    scopes.symbols[0].extend(global_symbols.iter().cloned());
    for var in &mut module.globals {
        if var.ty.to_string() == crate::type_name::AUTO {
            if let Some(default) = &var.default {
                let ty = type_of_expr(default, &scopes, None);
                if !ty.is_empty() && ty.to_string() != crate::type_name::AUTO {
                    var.ty = ty;
                }
            }
        }
        if let Some(default) = &mut var.default {
            resolve_expression(default, &mut scopes, &None, None);
        }
        scopes.symbols[0].push((var.name.clone(), var.ty.clone()));
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
            if var.ty.to_string() == crate::type_name::AUTO {
                if let Some(default) = &var.default {
                    let ty = type_of_expr(default, scopes, current_struct.as_ref());
                    if !ty.is_empty() && ty.to_string() != crate::type_name::AUTO {
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
            }
        }
        Statement::LoopBreak(_) => {}
    }
}

fn resolve_expression(
    expr: &mut Expression,
    scopes: &mut Scopes,
    current_struct: &Option<TypeName>,
    _var: Option<&mut VariableDef>,
) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        if let Expression::SymbolRef { id, ty } = e {
            if ty.to_string() == crate::type_name::AUTO && id != "this" {
                let resolved = if let Some(st) = current_struct {
                    type_of_expr(&Expression::SymbolRef {
                        id: id.clone(),
                        ty: TypeName::auto(),
                    }, scopes, Some(st))
                } else {
                    type_of_expr(
                        &Expression::SymbolRef {
                            id: id.clone(),
                            ty: TypeName::auto(),
                        },
                        scopes,
                        None,
                    )
                };
                if !resolved.is_empty() && resolved.to_string() != crate::type_name::AUTO {
                    *ty = resolved;
                }
            }
        }
    });
}
