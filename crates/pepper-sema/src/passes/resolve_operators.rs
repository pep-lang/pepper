//! Port of `source/Sema/ResolveOperators.h`: index operations become
//! `__index_get`/`__index_set` method calls or POD array indexing; binary
//! operator overloads become method calls. Conversion is gated on the lhs's
//! static type naming a struct that declares the method, so plain field
//! compares (`Size == 0`) and POD indexing stay untouched.

use crate::model::*;
use crate::static_type::{self, StructInfo, StructTable};
use crate::type_name::TypeName;

pub fn resolve_operators(module: &mut Module) {
    // Struct table for overload gating. Built before any mutation so the
    // per-struct walks and the free-function walk share one immutable view.
    let table = StructTable::build(module);

    for st_idx in 0..module.structs.len() {
        // Abstract generic bases (`array<T>`) have no concrete bodies to
        // resolve; specializations (`array<int>`) are concrete and must be.
        // Rewriting operator dispatch inside a base body would bake the
        // method into an unsubstituted receiver, and specialization clones
        // that MethodCall verbatim (SymbolRef `ty` annotations are not
        // substituted), so codegen would mangle against the parameter name.
        // Leave base bodies raw — the final pass resolves the specialized
        // clones, where the element type is concrete.
        if module.structs[st_idx].ty.is_generic() && module.structs[st_idx].name == module.structs[st_idx].ty.name {
            continue;
        }
        // The enclosing struct's type supplies `this`/bare-field types to the
        // walker (implicit-this fallback). Cloned so the mutable borrow of
        // the bodies below can coexist with it.
        let current = module.structs[st_idx].ty.clone();
        let st = &mut module.structs[st_idx];
        if let Some(body) = &mut st.constructor.body {
            resolve_body(body, &table, Some(&current));
        }
        for method in &mut st.method_members {
            if let Some(body) = &mut method.body {
                resolve_body(body, &table, Some(&current));
            }
        }
    }

    for function in &mut module.functions {
        if let Some(body) = &mut function.body {
            resolve_body(body, &table, None);
        }
    }
}

fn resolve_body(body: &mut Block, table: &StructTable, current: Option<&TypeName>) {
    // Single traversal: walk_block visits every expression node once.
    crate::passes::walk_block(body, &mut |expr: &mut Expression| match expr {
        Expression::Binary { op, lhs, rhs } if op.is_assignment() => {
            // `x[y] = z` → `x.__index_set(y, z)`, when the container is a
            // struct declaring the setter.
            if let Expression::Index { lhs: container, rhs: index } = &**lhs {
                if lhs_struct(container, table, current).is_some_and(|info| info.methods.contains("__index_set")) && !is_raw_buffer_field(container, table, current) {
                    let container = (**container).clone();
                    let index = (**index).clone();
                    let rhs_value = (**rhs).clone();
                    *expr = Expression::MethodCall {
                        this: Box::new(container),
                        method: "__index_set".to_string(),
                        args: vec![index, rhs_value],
                    };
                    return;
                }
            }
            // Compound assigns with an overload method (`str += x` →
            // `str.+=(x)`): only when the lhs's struct declares it.
            let op_name = op.op_name();
            if !op_name.is_empty() && lhs_struct(&**lhs, table, current).is_some_and(|info| info.methods.contains(&op_name)) {
                let lhs = (**lhs).clone();
                let rhs = (**rhs).clone();
                *expr = Expression::MethodCall {
                    this: Box::new(lhs),
                    method: op_name,
                    args: vec![rhs],
                };
            }
        }
        Expression::Index { lhs, rhs } => {
            let info = lhs_struct(lhs, table, current);
            if info.is_some_and(|i| i.methods.contains("__index_get")) && !is_raw_buffer_field(lhs, table, current) {
                // Replace the index op with a call to the index method.
                let lhs = (**lhs).clone();
                let rhs = (**rhs).clone();
                *expr = Expression::MethodCall {
                    this: Box::new(lhs),
                    method: "__index_get".to_string(),
                    args: vec![rhs],
                };
            } else if info.is_none() && static_type::of(lhs, table, current).is_some() {
                // POD receiver with a known type: array indexing (element
                // type resolved at codegen). Unknown receivers are left
                // alone — codegen handles `Index` like `ArrayIndex`.
                let lhs = (**lhs).clone();
                let rhs = (**rhs).clone();
                *expr = Expression::ArrayIndex {
                    ty: TypeName::auto(),
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                };
            }
        }
        Expression::Binary { op, lhs, rhs } => {
            // Resolve overloads on lhs: x + y → x.operator+(y). Only when
            // the lhs's struct declares the method — plain field compares
            // (`Size == 0`) and POD elements must stay binary ops.
            let op_name = op.op_name();
            if !op_name.is_empty() {
                // `Data[idx] == key` on a raw buffer field: dispatch on the
                // pointee (string content equality), which the receiver's
                // own static type does not describe. Struct receivers
                // (`array<string>`) already type as their element, so
                // lhs_struct covers them.
                let lhs_structured = index_pointee_declares(lhs, table, current, &op_name)
                    || lhs_struct(&**lhs, table, current).is_some_and(|info| info.methods.contains(&op_name));
                if lhs_structured {
                    let lhs = (**lhs).clone();
                    let rhs = (**rhs).clone();
                    *expr = Expression::MethodCall {
                        this: Box::new(lhs),
                        method: op_name,
                        args: vec![rhs],
                    };
                }
            }
        }
        _ => {}
    });
}

/// The struct declaring the lhs's type, via its static type. Bare symbols resolve
/// against the enclosing struct's field table (implicit-this fields), since
/// implicit-type resolution does not annotate them.
fn lhs_struct<'a>(lhs: &Expression, table: &'a StructTable, current: Option<&TypeName>) -> Option<&'a StructInfo> {
    let ty = static_type::of(lhs, table, current).or_else(|| {
        if let Expression::SymbolRef { id, .. } = lhs {
            current.and_then(|c| {
                table.lookup(c)
                    .and_then(|info| info.fields.iter().find(|(f, _)| f == id).map(|(_, ty)| ty.clone()))
            })
        } else { None }
    })?;
    table.lookup(&ty)
}

/// True when a binary op on an index (`recv[i] == x`) should dispatch on the
/// index receiver's element: `static_type::of` types such a receiver as its
/// declared buffer type (`string*`, `array<int>*`), so the pointee is what the
/// operator applies to. Non-buffer receivers (a nested index typed `array<int>`)
/// carry no trailing `*` and are handled by lhs_struct instead.
fn index_pointee_declares(lhs: &Expression, table: &StructTable, current: Option<&TypeName>, method: &str) -> bool {
    let (Expression::Index { lhs: receiver, .. } | Expression::ArrayIndex { lhs: receiver, .. }) = lhs
    else {
        return false;
    };
    let Some(buffer_ty) = static_type::of(receiver, table, current) else {
        return false;
    };
    let binding = buffer_ty.to_string();
    let Some(pointee) = binding.strip_suffix('*') else {
        return false;
    };
    table.lookup(&TypeName::new(pointee)).is_some_and(|info| info.methods.contains(method))
}

/// True when the index receiver is a declared raw-buffer field (`Data` typed
/// `T*`). Such indexes stay RAW — codegen GEPs through the pointer directly.
/// Rewriting them to `__index_get` bakes the pointee's indexer into the
/// receiver, and an operator on the result then mangles against the pointee's
/// *pointee* (`array<int>*` element `==` → `int.==`, which does not exist).
fn is_raw_buffer_field(expr: &Expression, table: &StructTable, current: Option<&TypeName>) -> bool {
    static_type::of(expr, table, current)
        .is_some_and(|ty| ty.to_string().ends_with('*'))
}

