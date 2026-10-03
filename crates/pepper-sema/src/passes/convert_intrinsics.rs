//! Port of `source/Sema/ConvertIntrinsics.h`: `__ptr<T>` → `T*` type rewrite;
//! `__is_pod`/`__default` calls become intrinsic expressions.

use crate::model::Diagnostic;
use crate::model::{Block, Declaration, Expression, FunctionDef, Module, SimdOp, Statement};
use crate::type_name::TypeName;
use std::collections::HashSet;

fn convert_type_string(ty: &mut TypeName) {
    // Inner-first, so `__ptr<__ptr<int>>` → `int**` and `Array<__ptr<char>>`
    // → `Array<char*>`.
    for sub in &mut ty.sub_types {
        convert_type_string(sub);
    }
    if ty.name == "__ptr" {
        if ty.sub_types.len() != 1 {
            crate::errors::report(Diagnostic::error(format!(
                "__ptr<T> takes exactly one type argument, {} given in '{}'",
                ty.sub_types.len(),
                ty
            )));
            return;
        }
        let pointee = ty.sub_types[0].to_string();
        *ty = TypeName::new(&format!("{}*", pointee));
    }
}

/// Convert the types an expression node carries: type positions such as
/// `x as __ptr<T>` and `sizeof<__ptr<T>>`, and the `T` of an intrinsic node,
/// which specialization may have substituted with a `__ptr<U>`
/// (`Atomic<__ptr<void>>`), or which a call lowered just now still spells
/// so (`__default<__ptr<void>>()`).
fn convert_node_types(e: &mut Expression) {
    if let Expression::Cast { ty, .. } | Expression::SizeOf(ty) = e {
        convert_type_string(ty);
    }
    match e {
            Expression::IsPod(ty)
            | Expression::Default(ty)
            | Expression::StaticCase { ty, .. }
            | Expression::Subject { ty, .. }
            | Expression::Allocate(ty)
            | Expression::RefCount(ty, _)
            | Expression::Address(ty, _)
            | Expression::Weak(_, ty, _)
            | Expression::AtomicLoad(ty, _)
            | Expression::AtomicStore(ty, _, _)
            | Expression::AtomicCmpXchg(ty, _, _, _)
            | Expression::AtomicFetch(_, ty, _, _)
            | Expression::Simd { ty, .. } => convert_type_string(ty),
            _ => {}
    }
}

fn convert_expression(expr: &mut Expression) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        convert_node_types(e);
        if let Expression::FunctionCall { function, args, loc } = e {
            let base = function.split('<').next().unwrap_or(function);
            if base == "__is_pod" || base == "__default" {
                // Store the inner type (not the full call name) so later
                // specialization passes can substitute generic params.
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&parsed.name),
                };
                *e = if base == "__is_pod" {
                    Expression::IsPod(ty)
                } else {
                    Expression::Default(ty)
                };
            } else if base == "__refcount" && args.len() == 1 {
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let base_name = parsed.name.clone();
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&base_name),
                };
                let arg = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                *e = Expression::RefCount(ty, Box::new(arg));
            } else if let Some(op) = [crate::model::WeakOp::From, crate::model::WeakOp::Upgrade, crate::model::WeakOp::Expired].into_iter().find(|op| op.name() == base)
                && args.len() == 1
            {
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let base_name = parsed.name.clone();
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&base_name),
                };
                let arg = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                *e = Expression::Weak(op, ty, Box::new(arg));
            } else if base == "__address" && args.len() == 1 {
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let base_name = parsed.name.clone();
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&base_name),
                };
                let arg = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                *e = Expression::Address(ty, Box::new(arg));
            } else if base == "__atomic_load" && args.len() == 1 {
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let base_name = parsed.name.clone();
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&base_name),
                };
                let arg = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                *e = Expression::AtomicLoad(ty, Box::new(arg));
            } else if base == "__atomic_store" && args.len() == 2 {
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let base_name = parsed.name.clone();
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&base_name),
                };
                let ptr = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                let val = std::mem::replace(&mut args[1], Expression::PointerLiteral);
                *e = Expression::AtomicStore(ty, Box::new(ptr), Box::new(val));
            } else if base == "__construct_at" && args.len() == 2 {
                let slot = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                let val = std::mem::replace(&mut args[1], Expression::PointerLiteral);
                *e = Expression::ConstructAt(Box::new(slot), Box::new(val));
            } else if base == "__atomic_cmpxchg" && args.len() == 3 {
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let base_name = parsed.name.clone();
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&base_name),
                };
                let ptr = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                let expected = std::mem::replace(&mut args[1], Expression::PointerLiteral);
                let desired = std::mem::replace(&mut args[2], Expression::PointerLiteral);
                *e = Expression::AtomicCmpXchg(ty, Box::new(ptr), Box::new(expected), Box::new(desired));
            } else if base.starts_with("__atomic_fetch_") && args.len() == 2 {
                let op = match base.strip_prefix("__atomic_fetch_").unwrap() {
                    "add" => crate::model::AtomicFetchOp::Add,
                    "sub" => crate::model::AtomicFetchOp::Sub,
                    "and" => crate::model::AtomicFetchOp::And,
                    "or" => crate::model::AtomicFetchOp::Or,
                    "xor" => crate::model::AtomicFetchOp::Xor,
                    _ => return,
                };
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let base_name = parsed.name.clone();
                let ty = match parsed.sub_types.into_iter().next() {
                    Some(inner) => inner,
                    None => TypeName::new(&base_name),
                };
                let ptr = std::mem::replace(&mut args[0], Expression::PointerLiteral);
                let val = std::mem::replace(&mut args[1], Expression::PointerLiteral);
                *e = Expression::AtomicFetch(op, ty, Box::new(ptr), Box::new(val));
            } else if let Some(op) = base.strip_prefix("__simd_").and_then(SimdOp::from_name) {
                if args.len() != op.arity() {
                    let which = if args.len() > op.arity() { "many" } else { "few" };
                    crate::errors::report(
                        Diagnostic::error(format!(
                            "too {} arguments to '{}': expected {}, have {}",
                            which,
                            base,
                            op.arity(),
                            args.len()
                        ))
                        .at(*loc),
                    );
                    return;
                }
                let parsed = crate::passes::gather_generics::parse_type_string(function);
                let ty = parsed.sub_types.into_iter().next().unwrap_or_else(|| TypeName::new("int"));
                *e = Expression::Simd { op, ty, args: std::mem::take(args), loc: *loc };
            }
            // The intrinsic node the call became.
            convert_node_types(e);
        }
    });
}

fn convert_block_decls(block: &mut Block) {
    for stmt in &mut block.items {
        match stmt {
            Statement::Declaration(Declaration::Variable(var)) => {
                convert_type_string(&mut var.ty);
                if let Some(default) = &mut var.default {
                    convert_expression(default);
                }
            }
            Statement::Declaration(_) => {}
            Statement::Block(inner) => convert_block_decls(inner),
            Statement::Branch(branch) => {
                convert_block_decls(&mut branch.if_block);
                if let Some(else_block) = &mut branch.else_block {
                    convert_block_decls(else_block);
                }
            }
            Statement::While(wh) => convert_block_decls(&mut wh.block),
            _ => {}
        }
    }
}

fn convert_function(function: &mut FunctionDef) {
    convert_type_string(&mut function.ty);
    for param in &mut function.parameters {
        convert_type_string(&mut param.ty);
    }
    if let Some(body) = &mut function.body {
        crate::passes::walk_block(body, &mut convert_expression);
        convert_block_decls(body);
    }
}

/// The function a `__function_pointer(f)` argument names: a free function,
/// or a static method of `owner` (the struct being converted, if any).
fn function_pointer_target(
    arg: &Expression,
    owner: Option<(&TypeName, &HashSet<String>)>,
    free_functions: &HashSet<String>,
) -> Result<(Option<TypeName>, String), Diagnostic> {
    let name = match arg {
        Expression::SymbolRef { id, .. } => id,
        Expression::FunctionRef { function, .. } => function,
        Expression::MemberRef { lhs, name, .. } if matches!(lhs.as_ref(), Expression::ThisRef) => name,
        other => {
            return Err(Diagnostic::error("'__function_pointer' expects the name of a function").at(other.loc()));
        }
    };
    if let Some((owner, statics)) = owner
        && statics.contains(name)
    {
        return Ok((Some(owner.clone()), name.clone()));
    }
    if free_functions.contains(name) {
        return Ok((None, name.clone()));
    }
    Err(Diagnostic::error(format!("use of undeclared identifier '{}'", name)).at(arg.loc()))
}

/// `__function_pointer(f)` calls in `function` → `FunctionPointer` nodes.
fn convert_function_pointers(
    function: &mut FunctionDef,
    owner: Option<(&TypeName, &HashSet<String>)>,
    free_functions: &HashSet<String>,
) {
    let Some(body) = &mut function.body else { return };
    crate::passes::walk_block(body, &mut |expr: &mut Expression| {
        crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
            let Expression::FunctionCall { function, args, loc } = e else { return };
            if function != "__function_pointer" {
                return;
            }
            if args.len() != 1 {
                let which = if args.len() > 1 { "many" } else { "few" };
                crate::errors::report(
                    Diagnostic::error(format!("too {} arguments to '__function_pointer': expected 1, have {}", which, args.len()))
                        .at(*loc),
                );
                return;
            }
            match function_pointer_target(&args[0], owner, free_functions) {
                Ok((owner, name)) => {
                    *e = Expression::FunctionPointer { owner, function: name, loc: *loc };
                }
                Err(diagnostic) => crate::errors::report(diagnostic),
            }
        });
    });
}

pub fn convert_intrinsics(module: &mut Module) {
    let free_functions: HashSet<String> = module.functions.iter().map(|f| f.name.clone()).collect();
    for function in &mut module.functions {
        convert_function_pointers(function, None, &free_functions);
    }
    for st in &mut module.structs {
        let statics: HashSet<String> =
            st.method_members.iter().filter(|m| m.is_static).map(|m| m.name.clone()).collect();
        let owner = st.ty.clone();
        for method in st.method_members.iter_mut().chain(st.constructors.iter_mut()).chain([&mut st.destructor]) {
            convert_function_pointers(method, Some((&owner, &statics)), &free_functions);
        }
    }
    for function in &mut module.functions {
        convert_function(function);
    }
    for var in &mut module.globals {
        convert_type_string(&mut var.ty);
        crate::passes::walk_global(var, &mut convert_expression);
    }
    // A trait's signatures, which its instances (`Shape s`) copy for the
    // calls through a value. The bodies of default methods are converted in
    // the structs they are copied into.
    for t in &mut module.traits {
        for method in &mut t.methods {
            convert_type_string(&mut method.ty);
            for param in &mut method.parameters {
                convert_type_string(&mut param.ty);
            }
        }
    }
    for st in &mut module.structs {
        for field in &mut st.field_members {
            convert_type_string(&mut field.ty);
        }
        for method in &mut st.method_members {
            convert_function(method);
        }
        // Constructor and destructor: signature, expressions, and body locals.
        for constructor in &mut st.constructors {
            convert_function(constructor);
        }
        convert_function(&mut st.destructor);
    }
    convert_trait_refs(module);
}

/// The type a reference to a trait-typed variable carries, converted like
/// the variable's declaration. A later specialization round can infer it
/// before this pass runs (`Iterator<T> source` in a trait's default method,
/// copied into `ArrayIterator<__ptr<char>>`), and calls through the value
/// would then name an `Iterator<__ptr<char>>` no declaration has. Only trait
/// types: elsewhere a reference's `__ptr<S>` spelling is what tells a raw
/// pointer from a reference to struct `S`.
fn convert_trait_refs(module: &mut Module) {
    let traits: HashSet<String> = module.traits.iter().map(|t| t.name.clone()).collect();
    if traits.is_empty() {
        return;
    }
    let mut convert = |e: &mut Expression| {
        if let Expression::SymbolRef { ty, .. } = e
            && traits.contains(&ty.name)
        {
            convert_type_string(ty);
        }
    };
    for function in &mut module.functions {
        if let Some(body) = &mut function.body {
            crate::passes::walk_block(body, &mut convert);
        }
    }
    for st in &mut module.structs {
        for method in st.method_members.iter_mut().chain(st.constructors.iter_mut()).chain([&mut st.destructor]) {
            if let Some(body) = &mut method.body {
                crate::passes::walk_block(body, &mut convert);
            }
        }
    }
}
