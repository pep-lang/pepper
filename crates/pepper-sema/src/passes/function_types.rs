//! Function types (`(P...) => R`, spelled `__function<R, P...>`) are
//! reference-counted heap objects, so each distinct function type becomes a
//! synthesized struct with the usual `__refcount` head:
//!
//! ```text
//! struct __function<R, P...> {
//!     u32 __refcount;
//!     u32 __weakcount;
//!     void* __invoke;    # R invoke(__function<R, P...> self, P... args)
//!     void* __destroy;   # reserved for closures: releases captured values
//! }
//! ```
//!
//! Every function type shares this layout, so a value of one spelling
//! (`(int) => int`) and another (`(i32) => i32`) are interchangeable in
//! codegen. Refcounting, field releases and scope exits then treat function
//! values exactly like any other struct reference (shared_ptr semantics).

use crate::model::*;
use crate::type_name::TypeName;
use std::collections::HashSet;

/// Field holding the invoke entry point (codegen reads it by index).
pub const INVOKE_FIELD: &str = "__invoke";
/// Field reserved for a closure's capture-release routine.
pub const DESTROY_FIELD: &str = "__destroy";

/// The function type of a free function: `(params) => return`.
pub fn signature(function: &FunctionDef) -> TypeName {
    // A function declared without a return type returns nothing.
    let ret = if function.ty.to_string() == crate::type_name::AUTO { TypeName::void() } else { function.ty.clone() };
    TypeName::function_type(ret, function.parameters.iter().map(|p| p.ty.clone()).collect())
}

/// Free functions that can be referenced by name as values: concrete,
/// non-generic definitions (generic references come with explicit
/// specialization later).
pub fn referenceable_functions(module: &Module) -> Vec<(String, TypeName)> {
    module
        .functions
        .iter()
        .filter(|f| !f.is_generic_func && !f.name.contains('<') && f.body.is_some())
        .map(|f| (f.name.clone(), signature(f)))
        .collect()
}

/// Add a struct for every function type and weak reference type
/// (`__weak<T>`, see `weak_types`) used anywhere in the module that does not
/// have one yet. Idempotent; run whenever new types may have
/// appeared (after parsing and after each specialization round).
pub fn synthesize_function_types(module: &mut Module) {
    let mut found: Vec<TypeName> = vec![];
    let mut seen: HashSet<String> = HashSet::new();
    {
        let mut add = |ty: &TypeName| collect(ty, &mut found, &mut seen);
        for st in &module.structs {
            for field in &st.field_members {
                add(&field.ty);
            }
            for method in st.method_members.iter().chain([&st.constructor, &st.destructor]) {
                function_types(method, &mut add);
            }
        }
        for function in &module.functions {
            function_types(function, &mut add);
        }
        for ext in &module.extensions {
            for method in &ext.methods {
                function_types(method, &mut add);
            }
        }
        for var in &module.globals {
            add(&var.ty);
            if let Some(default) = &var.default {
                expression_types(default, &mut add);
            }
        }
        for spec in &module.struct_specs {
            add(spec);
        }
    }
    for ty in found {
        let name = ty.to_string();
        if module.structs.iter().any(|st| st.name == name) {
            continue;
        }
        if let Some(target) = ty.weak_target() {
            // Only a concrete struct target: `__weak<T>` inside a generic
            // base waits for its specializations.
            if let Some(shared) = module.structs.iter().find(|st| st.name == target.to_string()).map(|st| st.is_shared()) {
                module.structs.push(crate::passes::weak_types::weak_struct(&ty, shared));
            }
            continue;
        }
        let mut st = function_struct(&ty);
        crate::struct_body::apply_synthesized(&mut st);
        crate::struct_body::finish(&mut st).expect("function type struct");
        module.structs.push(st);
    }
}

/// Record `ty` and every function type nested in it (innermost first, so a
/// `(int) => (int) => int` registers its return type before itself).
fn collect(ty: &TypeName, found: &mut Vec<TypeName>, seen: &mut HashSet<String>) {
    for sub in &ty.sub_types {
        collect(sub, found, seen);
    }
    if let Some(pointee) = ty.name.strip_suffix('*') {
        collect(&TypeName::new(pointee), found, seen);
    }
    if (ty.is_function_type() || ty.is_weak()) && !ty.contains_auto() && seen.insert(ty.to_string()) {
        found.push(ty.clone());
    }
}

fn function_types(function: &FunctionDef, add: &mut impl FnMut(&TypeName)) {
    add(&function.ty);
    for param in &function.parameters {
        add(&param.ty);
        if let Some(default) = &param.default {
            expression_types(default, add);
        }
    }
    if let Some(body) = &function.body {
        block_types(body, add);
    }
}

fn block_types(block: &Block, add: &mut impl FnMut(&TypeName)) {
    for stmt in &block.items {
        match stmt {
            Statement::Expression(expr) => expression_types(expr, add),
            Statement::Block(inner) => block_types(inner, add),
            Statement::Declaration(Declaration::Variable(var)) => {
                add(&var.ty);
                if let Some(default) = &var.default {
                    expression_types(default, add);
                }
            }
            Statement::Declaration(_) => {}
            Statement::Branch(branch) => {
                expression_types(&branch.condition, add);
                block_types(&branch.if_block, add);
                if let Some(else_block) = &branch.else_block {
                    block_types(else_block, add);
                }
            }
            Statement::While(wh) => {
                expression_types(&wh.condition, add);
                block_types(&wh.block, add);
            }
            Statement::Return(ret) => {
                if let Some(expr) = &ret.expr {
                    expression_types(expr, add);
                }
            }
            Statement::LoopBreak(_) => {}
        }
    }
}

fn expression_types(expr: &Expression, add: &mut impl FnMut(&TypeName)) {
    // `walk_expression` needs `&mut`; the walk only reads.
    let mut expr = expr.clone();
    crate::passes::walk_expression(&mut expr, &mut |e: &mut Expression| match e {
        Expression::SymbolRef { ty, .. }
        | Expression::FunctionRef { ty, .. }
        | Expression::Cast { ty, .. }
        | Expression::ArrayIndex { ty, .. } => add(ty),
        Expression::Weak(op, ty, _) => add(&op.result(ty)),
        Expression::MakeClosure { ty, .. } => add(ty),
        Expression::FunctionCall { function, .. } if function.contains('<') => {
            add(&crate::passes::gather_generics::parse_type_string(function));
        }
        _ => {}
    });
}

pub(crate) fn empty_function(name: &str, ty: TypeName, parent: &str) -> FunctionDef {
    FunctionDef {
        name: name.to_string(),
        ty,
        generic_params: vec![],
        parameters: vec![],
        body: Some(Block { name: String::new(), items: vec![], attributes: vec![] }),
        parent: Some(parent.to_string()),
        is_static: false,
        is_indexer: false,
        is_generic_func: false,
        attributes: vec![],
        loc: Loc::NONE,
    }
}

fn pointer_field(name: &str) -> VariableDef {
    VariableDef {
        name: name.to_string(),
        ty: TypeName::void_ptr(),
        default: None,
        hidden: false,
        kind: Kind::Field,
        attributes: vec![],
        loc: Loc::NONE,
        type_loc: Loc::NONE,
        is_const: false,
    }
}

/// The destructor of a function type: a closure's `__destroy` releases its
/// captured values (`if (this.__destroy !== null) __destroy(this);`). A
/// named function's static object has none.
fn destructor(parent: &str) -> FunctionDef {
    let mut dtor = empty_function("__dtor", TypeName::void(), parent);
    let destroy = || {
        Box::new(Expression::MemberRef { lhs: Box::new(Expression::ThisRef), name: DESTROY_FIELD.to_string(), loc: Loc::NONE })
    };
    dtor.body = Some(Block {
        name: String::new(),
        items: vec![Statement::Branch(Branch {
            condition: Expression::Unary {
                op: UnaryOp::LogicalNot,
                operand: Box::new(Expression::Binary {
                    op: BinaryOp::Identical,
                    lhs: destroy(),
                    rhs: Box::new(Expression::PointerLiteral),
                    loc: Loc::NONE,
                }),
                loc: Loc::NONE,
            },
            if_block: Block {
                name: "if".to_string(),
                items: vec![Statement::Expression(Expression::CallPointer { pointer: destroy(), args: vec![Expression::ThisRef] })],
                attributes: vec![],
            },
            else_block: None,
        })],
        attributes: vec![],
    });
    dtor
}

/// The struct for one function type, before `apply_synthesized`/`finish`.
fn function_struct(ty: &TypeName) -> StructDef {
    let name = ty.to_string();
    StructDef {
        name: name.clone(),
        ty: ty.clone(),
        generic_params: vec![],
        field_members: vec![pointer_field(INVOKE_FIELD), pointer_field(DESTROY_FIELD)],
        method_members: vec![],
        constructor: empty_function(&name, ty.clone(), &name),
        destructor: destructor(&name),
        acquire: empty_function("__acquire", TypeName::void(), &name),
        release: empty_function("__release", TypeName::void(), &name),
        traits: vec![],
        attributes: vec![],
        loc: Loc::NONE,
    }
}
