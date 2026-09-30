//! Port of `source/Sema/ResolveResolvables.h`: resolve struct/function refs
//! and unresolved method calls against the symbol table. The module is
//! snapshotted into `ResolvedModuleView` before mutation to satisfy the
//! borrow checker (symbol tables are immutable during this pass).

use crate::model::*;
use crate::type_name::TypeName;

/// Immutable snapshot of what resolution needs from the module.
struct ResolvedModuleView {
    functions: Vec<(String, String)>, // name → type string
    externs: Vec<String>,
    structs: Vec<(String, String)>, // name → type string
    methods: Vec<(String, Vec<String>)>, // struct name → method names
}

fn view_of(module: &Module) -> ResolvedModuleView {
    ResolvedModuleView {
        functions: module
            .functions
            .iter()
            .map(|f| (f.name.clone(), f.ty.to_string()))
            // A call in a generic base naming an overload set resolves in
            // each specialization (see `overloads`).
            .chain(module.overload_sets.keys().map(|set| (set.clone(), String::new())))
            // A resolved call to an overloaded constructor (`Point$2`).
            .chain(
                module
                    .structs
                    .iter()
                    .filter(|st| st.constructors.len() > 1)
                    .flat_map(|st| st.constructors.iter().map(|c| (c.name.clone(), c.ty.to_string()))),
            )
            .collect(),
        externs: module.externs.iter().map(|e| e.name.clone()).collect(),
        structs: module
            .structs
            .iter()
            .flat_map(|st| vec![(st.name.clone(), st.ty.to_string())])
            .collect(),
        methods: module
            .structs
            .iter()
            .map(|st| {
                (
                    st.ty.to_string(),
                    st.method_members.iter().map(|m| m.name.clone()).collect(),
                )
            })
            .collect(),
    }
}

pub fn resolve_resolvables(module: &mut Module, report_missing: bool) {
    let view = view_of(module);

    // Struct spec resolution: extension targets.
    for ext in &mut module.extensions {
        if ext.resolved.is_none() {
            let target = ext.target.to_string();
            // `extend Box<int>` names one specialization: it applies only
            // once that instance exists, never to the generic base (which
            // every specialization clones). `extend Box` / `extend Box<T>`
            // (the struct's own parameters) extend the base.
            let base = module.structs.iter().find(|st| st.name == ext.target.name);
            let extends_base = ext.target.sub_types.is_empty()
                || base.is_some_and(|st| {
                    st.generic_params.len() == ext.target.sub_types.len()
                        && st.generic_params.iter().zip(&ext.target.sub_types).all(|(p, a)| a.sub_types.is_empty() && a.name == p.name)
                });
            let found = view
                .structs
                .iter()
                .find(|(name, _)| *name == target)
                .or_else(|| {
                    view.structs
                        .iter()
                        .find(|(name, _)| extends_base && *name == ext.target.name)
                });
            if let Some((name, _)) = found {
                ext.resolved = Some(name.clone());
            } else if base.is_some() && !extends_base {
                // The specialization is never used: nothing to extend.
            } else if report_missing {
                crate::errors::report(
                    Diagnostic::error(format!("cannot extend unknown struct '{}'", ext.target)).at(ext.loc),
                );
            }
        }
    }

    // Functions: resolve call targets in bodies.
    for function in &mut module.functions {
        if let Some(body) = &mut function.body {
            resolve_block(body, &view, report_missing);
        }
    }

    // Global initializers: same call-target resolution as function bodies.
    for var in &mut module.globals {
        if let Some(default) = &mut var.default {
            resolve_expression(default, &view, report_missing);
        }
    }

    for st_idx in 0..module.structs.len() {
        // Skip generic structs; no point in resolving generics, the results
        // won't get used anyway.
        if module.structs[st_idx].ty.is_generic() {
            continue;
        }
        let st = &mut module.structs[st_idx];
        for body in st.constructors.iter_mut().filter_map(|c| c.body.as_mut()) {
            resolve_block(body, &view, report_missing);
        }
        for method in &mut st.method_members {
            if let Some(body) = &mut method.body {
                resolve_block(body, &view, report_missing);
            }
        }
    }
}

fn resolve_block(block: &mut Block, view: &ResolvedModuleView, report_missing: bool) {
    for stmt in &mut block.items {
        resolve_statement(stmt, view, report_missing);
    }
}

fn resolve_statement(stmt: &mut Statement, view: &ResolvedModuleView, report_missing: bool) {
    match stmt {
        Statement::Expression(expr) => resolve_expression(expr, view, report_missing),
        Statement::Block(inner) => resolve_block(inner, view, report_missing),
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            resolve_expression(&mut branch.condition, view, report_missing);
            resolve_block(&mut branch.if_block, view, report_missing);
            if let Some(else_block) = &mut branch.else_block {
                resolve_block(else_block, view, report_missing);
            }
        }
        Statement::While(wh) => {
            resolve_expression(&mut wh.condition, view, report_missing);
            resolve_block(&mut wh.block, view, report_missing);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                resolve_expression(expr, view, report_missing);
            }
        }
        Statement::LoopBreak(_) => {}
    }
}

fn resolve_expression(expr: &mut Expression, view: &ResolvedModuleView, report_missing: bool) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        if let Expression::FunctionCall { function, loc, .. } = e {
            let known_function = view.functions.iter().any(|(name, _)| name == function);
            let known_extern = view.externs.iter().any(|name| name == function);
            let known_struct = view
                .structs
                .iter()
                .any(|(name, _)| name == function)
                || view
                    .structs
                    .iter()
                    .any(|(name, _)| {
                        name == function.split('<').next().unwrap_or(function)
                    });
            if !known_function && !known_extern && !known_struct {
                // Builtins (`_pep_*`, `trace_*`, `print`) and unresolved
                // generic calls are deferred to later passes/codegen.
                let builtin = function.starts_with("_pep_")
                    || function.starts_with("trace_")
                    || function == "print"
                    || function == "String"
                    || function.contains('<');
                if !builtin && report_missing {
                    crate::errors::report(
                        Diagnostic::error(format!("call to undeclared function '{}'", function)).at(*loc),
                    );
                }
            }
        }
    });
}

/// Resolve a method call target against the struct of `this` (kept for parity
/// with `resolve_method`).
pub fn resolve_method(this_type: &TypeName, method: &str, module: &Module) -> Option<String> {
    let view = view_of(module);
    let methods = view
        .methods
        .iter()
        .find(|(ty, _)| ty == &this_type.to_string())
        .or_else(|| view.methods.iter().find(|(ty, _)| ty == &this_type.name))?;
    methods
        .1
        .iter()
        .find(|m| *m == method)
        .map(|m| m.clone())
}
