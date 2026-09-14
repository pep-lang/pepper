//! Port of `source/Sema/GatherGenerics.h`: record generic uses as specs.

use crate::model::{Expression, Module, Spec};
use crate::passes::{walk_expression, walk_function};
use crate::symbols::SymbolTable;
use crate::type_name::TypeName;
use std::collections::HashSet;

pub fn gather_generics(module: &mut Module) {
    let symbols = SymbolTable::build(module);
    let mut functions: HashSet<String> = HashSet::new();
    let mut structs: HashSet<String> = HashSet::new();

    let mut gather = |expr: &mut Expression| {
        if let Expression::FunctionCall { function, .. } = expr {
            eprintln!("DBG gather call={:?}", function);
            // Do not record specializations for intrinsics.
            if function.starts_with("__") {
                return;
            }
            if let Some(open) = function.find('<') {
                if function.ends_with('>') {
                    functions.insert(function.clone());
                    let _ = open;
                }
            }
        }
    };

    // Walk struct bodies for generic calls and TypeLiteral-based generics.
    for st in &module.structs {
        for method in &mut {
            // borrow dance: gather uses closures over a set, walk takes &mut
            st.method_members.clone()
        } {
            let _ = method;
        }
    }

    for st in &mut module.structs {
        for method in &mut st.method_members {
            walk_function(method, &mut gather);
        }
        if let Some(body) = &mut st.constructor.body {
            crate::passes::walk_block(body, &mut gather);
        }
        if let Some(body) = &mut st.destructor.body {
            crate::passes::walk_block(body, &mut gather);
        }
        // Struct field/method types carrying generics.
        for field in &st.field_members {
            if field.ty.is_generic() && !field.ty.name.starts_with("__") {
                structs.insert(field.ty.to_string());
            }
        }
        for method in &st.method_members {
            if method.ty.is_generic() && !method.ty.name.starts_with("__") {
                structs.insert(method.ty.to_string());
            }
            for param in &method.parameters {
                if param.ty.is_generic() && !param.ty.name.starts_with("__") {
                    structs.insert(param.ty.to_string());
                }
            }
        }
    }

    for function in &mut module.functions {
        walk_function(function, &mut gather);
        if function.ty.is_generic() && !function.ty.name.starts_with("__") {
            structs.insert(function.ty.to_string());
        }
        for param in &function.parameters {
            if param.ty.is_generic() && !param.ty.name.starts_with("__") {
                structs.insert(param.ty.to_string());
            }
        }
    }

    for ext in &mut module.extensions {
        for method in &mut ext.methods {
            walk_function(method, &mut gather);
        }
    }

    eprintln!("DBG gather functions={:?}", functions);
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
    eprintln!("DBG gather structs={:?} -> specs={:?}", structs, struct_specs.iter().map(|s| s.to_string()).collect::<Vec<_>>());
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
    let _ = Spec::Struct(TypeName::auto());
}

/// Parse `Name<a, b>` back into a TypeName (specs are carried as TypeNames).
pub fn parse_type_string(s: &str) -> TypeName {
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
