//! Port of `source/Sema/GatherGenerics.h`: record generic uses as specs.

use crate::model::{Block, Declaration, Expression, Module, Statement};
use crate::passes::walk_function;
use crate::symbols::SymbolTable;
use crate::type_name::TypeName;
use std::collections::BTreeSet;

pub fn gather_generics(module: &mut Module) {
    concrete_overrides(module);
    let symbols = SymbolTable::build(module);
    let mut functions: BTreeSet<String> = BTreeSet::new();
    let mut structs: BTreeSet<String> = BTreeSet::new();

    // Walk struct bodies for generic calls and TypeLiteral-based generics.
    for st in &mut module.structs {
        let params = param_names(&st.generic_params);
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, .. } = expr {
                // Do not record specializations for intrinsics.
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    let ty = parse_type_string(function);
                    if !contains_param(&ty, &params) {
                        functions.insert(function.clone());
                    }
                }
            }
        };
        for method in &mut st.method_members {
            walk_function(method, &mut gather);
        }
        for body in st.constructors.iter_mut().filter_map(|c| c.body.as_mut()) {
            crate::passes::walk_block(body, &mut gather);
        }
        if let Some(body) = &mut st.destructor.body {
            crate::passes::walk_block(body, &mut gather);
        }
        // Struct field/method types carrying generics.
        for field in &st.field_members {
            if field.ty.is_generic()
                && !field.ty.name.starts_with("__")
                && !contains_param(&field.ty, &params)
            {
                structs.insert(field.ty.to_string());
            }
        }
        for method in &st.method_members {
            if method.ty.is_generic()
                && !method.ty.name.starts_with("__")
                && !contains_param(&method.ty, &params)
            {
                structs.insert(method.ty.to_string());
            }
            for param in &method.parameters {
                if param.ty.is_generic()
                    && !param.ty.name.starts_with("__")
                    && !contains_param(&param.ty, &params)
                {
                    structs.insert(param.ty.to_string());
                }
            }
        }
    }

    for function in &mut module.functions {
        let params = param_names(&function.generic_params);
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, .. } = expr {
                // Do not record specializations for intrinsics.
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    let ty = parse_type_string(function);
                    if !contains_param(&ty, &params) {
                        functions.insert(function.clone());
                    }
                }
            }
        };
        walk_function(function, &mut gather);
        // A generic function's own parameters (`Array<U>` in `f<U>`) are
        // not a use; its specializations' concrete types are.
        if function.ty.is_generic() && !function.ty.name.starts_with("__") && !contains_param(&function.ty, &params) {
            structs.insert(function.ty.to_string());
        }
        for param in &function.parameters {
            if param.ty.is_generic() && !param.ty.name.starts_with("__") && !contains_param(&param.ty, &params) {
                structs.insert(param.ty.to_string());
            }
        }
    }

    // Global initializers: `var x = Array<int>()` at file scope must register
    // the specialization too.
    for var in &mut module.globals {
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, .. } = expr {
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    functions.insert(function.clone());
                }
            }
        };
        crate::passes::walk_global(var, &mut gather);
        if var.ty.is_generic() && !var.ty.name.starts_with("__") {
            structs.insert(var.ty.to_string());
        }
    }

    for ext in &mut module.extensions {
        let mut gather = |expr: &mut Expression| {
            if let Expression::FunctionCall { function, .. } = expr {
                // Do not record specializations for intrinsics.
                if function.starts_with("__") && !crate::passes::closures::is_closure_struct(function) {
                    return;
                }
                if function.find('<').is_some() && function.ends_with('>') {
                    functions.insert(function.clone());
                }
            }
        };
        for method in &mut ext.methods {
            walk_function(method, &mut gather);
        }
    }

    // Local variable declarations (`Array<int> a;` with no ctor call) are the
    // only place generic types can appear that fields/params/calls miss.
    for st in &module.structs {
        let params = param_names(&st.generic_params);
        for method in &st.method_members {
            if let Some(body) = &method.body {
                gather_local_declarations(body, &mut structs, &params);
            }
        }
        for body in st.constructors.iter().filter_map(|c| c.body.as_ref()) {
            gather_local_declarations(body, &mut structs, &params);
        }
    }
    for function in &module.functions {
        let params = param_names(&function.generic_params);
        if let Some(body) = &function.body {
            gather_local_declarations(body, &mut structs, &params);
        }
    }

    // Emit struct specs.
    let mut struct_specs: Vec<TypeName> = module.struct_specs.clone();
    for name in &structs {
        let ty = parse_type_string(name);
        if struct_specs.iter().any(|s| s == &ty) {
            continue;
        }
        if let Some(st) = symbols.struct_by_name(module, &ty.name) {
            if st.ty == ty {
                continue;
            }
            struct_specs.push(ty);
        }
    }
    module.struct_specs = struct_specs;

    // Emit function specs (constructor calls become struct specs).
    let mut func_specs: Vec<TypeName> = module.func_specs.clone();
    for name in &functions {
        let ty = parse_type_string(name);
        if func_specs.iter().any(|s| s == &ty) {
            continue;
        }
        if let Some(st) = symbols.struct_by_name(module, &ty.name) {
            if st.ty == ty || module.struct_specs.iter().any(|s| s == &ty) {
                continue;
            }
            module.struct_specs.push(ty.clone());
            continue;
        }
        if let Some(function) = symbols.function(module, &ty.name) {
            if function.ty == ty {
                continue;
            }
        }
        func_specs.push(ty);
    }
    module.func_specs = func_specs;
}

/// Concrete specializations written as definitions override generic bases:
/// `hash<String>(String value)` is a distinct function from `hash<T>(T)`.
/// The parser cannot tell them apart (both parse as name + generic params),
/// so this pass rewrites any free-function definition whose generic
/// parameters are ALL concrete types into its specialization form, in place:
/// the name becomes `name<args>` (the same string call sites use) and the
/// definition stops being a generic base. The generic base (`hash<T>`) is a
/// separate remaining entry that serves other call sites (`hash<int>`);
/// `specialize_functions` skips cloning a spec whose name already exists, so
/// the user's concrete body wins over the synthesized one. Idempotent —
/// rewritten functions have empty `generic_params` and are skipped on later
/// rounds.
pub(crate) fn concrete_overrides(module: &mut Module) {
    // A struct can be an override's argument too (`describe<Point>` of
    // `describe<T>`), but a struct's name is also a legal generic parameter
    // name: it overrides only when a generic base of the same name and
    // arity exists, one with a parameter that names no type.
    let linked = module.linked;
    let is_struct = |name: &str| module.structs.iter().any(|st| st.ty.name == name);
    let names_type = |p: &str| crate::type_name::is_concrete_override(std::iter::once(p)) || is_struct(p);
    let has_base = |function: &crate::model::FunctionDef| {
        module.functions.iter().any(|other| {
            other.name == function.name
                && other.generic_params.len() == function.generic_params.len()
                && other.generic_params.iter().any(|p| !names_type(&p.name))
        })
    };
    let mut rewrites: Vec<(usize, String)> = vec![];
    for (idx, function) in module.functions.iter().enumerate() {
        if function.generic_params.is_empty() {
            continue;
        }
        let params = || function.generic_params.iter().map(|p| p.name.as_str());
        // Module linking decides by what each file can see, and marks what
        // it decided; only an unlinked module falls back to program-wide
        // names.
        let all_concrete = crate::type_name::is_concrete_override(params())
            || function.generic_params.iter().any(|p| p.is_argument)
            || (!linked && params().all(names_type) && has_base(function));
        if !all_concrete {
            continue;
        }
        let args = function.generic_params.iter().map(|p| p.name.clone()).collect::<Vec<_>>().join(", ");
        rewrites.push((idx, format!("{}<{}>", function.name, args)));
    }
    for (idx, new_name) in rewrites {
        let mut concrete = module.functions[idx].clone();
        concrete.name = new_name;
        concrete.generic_params.clear();
        concrete.is_generic_func = false;
        // The original definition stays in place as the generic base.
        module.functions[idx] = concrete;
    }
}

/// A type that references one of the enclosing generic parameters is unbound
/// in this context; recording it as a spec would produce a specialization
/// with no concrete argument (e.g. `Array<V>` from HashMap's own field
/// list). Concrete uses are re-discovered from specialized bodies in the
/// second gather round.
fn contains_param(ty: &TypeName, params: &[TypeName]) -> bool {
    if params.iter().any(|p| p.name == ty.name) {
        return true;
    }
    ty.sub_types.iter().any(|s| contains_param(s, params))
}

/// Generic parameter names as bare TypeNames (for `contains_param`).
fn param_names(params: &[crate::model::GenericParam]) -> Vec<TypeName> {
    params.iter().map(|p| TypeName::new(&p.name)).collect()
}

/// Parse `Name<a, b>` back into a TypeName (specs are carried as TypeNames).
/// A call to an overloaded constructor (`Box<int>$2`) parses as the type
/// it constructs.
pub fn parse_type_string(s: &str) -> TypeName {
    let s = match crate::passes::overloads::set_name(s) {
        set if set.ends_with('>') => set,
        _ => s,
    };
    // A pointer type keeps its stars in the name (`Atomic<long>*`), with no
    // type arguments of its own.
    if s.ends_with('*') {
        return TypeName::new(s);
    }
    let Some(open) = s.find('<') else {
        return TypeName::new(s);
    };
    let name = &s[..open];
    let inner = &s[open + 1..s.len() - 1];
    let args: Vec<TypeName> = if inner.trim().is_empty() {
        vec![]
    } else {
        // Split on top-level commas only.
        let mut parts = vec![];
        let mut depth = 0usize;
        let mut current = String::new();
        for c in inner.chars() {
            match c {
                '<' => {
                    depth += 1;
                    current.push(c);
                }
                '>' => {
                    depth -= 1;
                    current.push(c);
                }
                ',' if depth == 0 => {
                    parts.push(current.trim().to_string());
                    current = String::new();
                }
                _ => current.push(c),
            }
        }
        if !current.trim().is_empty() {
            parts.push(current.trim().to_string());
        }
        parts.iter().map(|p| parse_type_string(p)).collect()
    };
    TypeName::with_args(name, args)
}

/// Collect generic types from local variable declarations, recursing into
/// nested blocks (branch/while bodies). Same predicate as the field and
/// parameter collection above.
fn gather_local_declarations(
    block: &Block,
    structs: &mut BTreeSet<String>,
    params: &[TypeName],
) {
    for stmt in &block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) => {
                if var.ty.is_generic()
                    && !var.ty.name.starts_with("__")
                    && !contains_param(&var.ty, params)
                {
                    structs.insert(var.ty.to_string());
                }
            }
            Statement::Block(inner) => gather_local_declarations(inner, structs, params),
            Statement::Branch(branch) => {
                gather_local_declarations(&branch.if_block, structs, params);
                if let Some(else_block) = &branch.else_block {
                    gather_local_declarations(else_block, structs, params);
                }
            }
            Statement::While(wh) => gather_local_declarations(&wh.block, structs, params),
            _ => {}
        }
    }
}
