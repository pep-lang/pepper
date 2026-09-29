//! Port of `source/Sema/SpecializeStructs.h` + `Specialization.h`: clone
//! fields/ctor/methods into specialized structs, substitute generic params.

use crate::model::*;
use crate::type_name::TypeName;

/// Substitute generic params → args recursively through a TypeName.
pub(crate) fn substitute(ty: &mut TypeName, type_map: &[(String, TypeName)]) {
    for (param, arg) in type_map {
        ty.replace(param, arg);
    }
}

fn specialize_struct(base: &StructDef, spec_type: &TypeName) -> StructDef {
    // map generic_params[idx] -> spec.type.sub_types[idx]
    let mut type_map: Vec<(String, TypeName)> = vec![];
    for (idx, param) in base.generic_params.iter().enumerate() {
        // Missing arguments fall back to the parameter's default.
        let arg = spec_type.sub_types.get(idx).cloned().or_else(|| param.default.clone());
        if let Some(arg) = arg {
            type_map.push((param.name.clone(), arg));
        }
    }

    let mut specialized = StructDef {
        name: spec_type.to_string(),
        ty: spec_type.clone(),
        generic_params: vec![],
        field_members: vec![],
        method_members: vec![],
        generic_methods: vec![],
        constructor: base.constructor.clone(),
        destructor: base.destructor.clone(),
        acquire: base.acquire.clone(),
        release: base.release.clone(),
        traits: base.traits.clone(),
        attributes: base.attributes.clone(),
        loc: base.loc,
    };

    // Declared traits name the parameters too (`extend Box<T> with
    // Iterator<T>` gives `Box<int>` the trait `Iterator<int>`).
    for trait_name in &mut specialized.traits {
        substitute(trait_name, &type_map);
    }

    // Fields: clone then substitute types.
    for field in &base.field_members {
        let mut f = field.clone();
        substitute(&mut f.ty, &type_map);
        specialized.field_members.push(f);
    }

    // Methods: clone then substitute types. A generic method keeps its own
    // type parameters (`map<U>` of `Box<int>`).
    for method in &base.generic_methods {
        let mut m = method.clone();
        substitute(&mut m.ty, &type_map);
        for param in &mut m.parameters {
            substitute(&mut param.ty, &type_map);
            if let Some(default) = &mut param.default {
                substitute_expression(default, &type_map);
            }
        }
        if let Some(body) = &mut m.body {
            substitute_block(body, &type_map);
        }
        specialized.generic_methods.push(m);
    }
    for method in &base.method_members {
        let mut m = method.clone();
        substitute(&mut m.ty, &type_map);
        for param in &mut m.parameters {
            substitute(&mut param.ty, &type_map);
            if let Some(default) = &mut param.default {
                substitute_expression(default, &type_map);
            }
        }
        if let Some(body) = &mut m.body {
            substitute_block(body, &type_map);
        }
        specialized.method_members.push(m);
    }

    // Constructor: substitute the body's variable types.
    let mut ctor = base.constructor.clone();
    substitute(&mut ctor.ty, &type_map);
    for param in &mut ctor.parameters {
        substitute(&mut param.ty, &type_map);
        if let Some(default) = &mut param.default {
            substitute_expression(default, &type_map);
        }
    }
    if let Some(body) = &mut ctor.body {
        substitute_block(body, &type_map);
    }
    ctor.name = spec_type.to_string();
    specialized.constructor = ctor;

    // Dtor/acquire/release.
    let mut dtor = base.destructor.clone();
    if let Some(body) = &mut dtor.body {
        substitute_block(body, &type_map);
    }
    specialized.destructor = dtor;
    let mut acquire = base.acquire.clone();
    if let Some(body) = &mut acquire.body {
        substitute_block(body, &type_map);
    }
    specialized.acquire = acquire;
    let mut release = base.release.clone();
    if let Some(body) = &mut release.body {
        substitute_block(body, &type_map);
    }
    specialized.release = release;

    erase_void(&mut specialized);
    specialized
}

/// A `void` type argument (`Result<void>`) erases what it types, as Rust's
/// `()` carries nothing: fields and parameters of type `void` are removed,
/// along with the statements that only move them. Removed are an
/// assignment to a removed field of `this` (the constructor's zero
/// initialization, `this.Value = v`), an assignment whose value is a
/// removed parameter (`r.Value = v`), and the value of a `return` that
/// returns either one (`return this.Value;` in a method whose return type
/// became `void`). Any other use is left in place, so it is reported as
/// the missing member or symbol it now is.
fn erase_void(st: &mut StructDef) {
    let is_void = |ty: &TypeName| ty.name == crate::type_name::VOID && ty.sub_types.is_empty();
    let fields: Vec<String> = st
        .field_members
        .iter()
        .filter(|f| is_void(&f.ty))
        .map(|f| f.name.clone())
        .collect();
    let has_void_param = |f: &FunctionDef| f.parameters.iter().any(|p| is_void(&p.ty));
    if fields.is_empty()
        && !st.method_members.iter().any(has_void_param)
        && !has_void_param(&st.constructor)
    {
        return;
    }
    st.field_members.retain(|f| !is_void(&f.ty));
    let erase_function = |f: &mut FunctionDef| {
        let params: Vec<String> = f
            .parameters
            .iter()
            .filter(|p| is_void(&p.ty))
            .map(|p| p.name.clone())
            .collect();
        f.parameters.retain(|p| !is_void(&p.ty));
        let returns_void = is_void(&f.ty);
        if let Some(body) = &mut f.body {
            erase_void_block(body, &fields, &params, returns_void);
        }
    };
    for method in &mut st.method_members {
        erase_function(method);
    }
    erase_function(&mut st.constructor);
}

fn erase_void_block(block: &mut Block, fields: &[String], params: &[String], returns_void: bool) {
    let erased = |e: &Expression| match e {
        Expression::SymbolRef { id, .. } => params.contains(id),
        Expression::MemberRef { lhs, name, .. } => {
            matches!(**lhs, Expression::ThisRef) && fields.contains(name)
        }
        _ => false,
    };
    block.items.retain(|stmt| match stmt {
        Statement::Expression(Expression::Binary { op: BinaryOp::Assign, lhs, rhs, .. }) => {
            let field_store = matches!(&**lhs, Expression::MemberRef { .. }) && erased(lhs);
            let param_value = matches!(&**rhs, Expression::SymbolRef { .. }) && erased(rhs);
            !(field_store || param_value)
        }
        _ => true,
    });
    for stmt in &mut block.items {
        match stmt {
            Statement::Block(inner) => erase_void_block(inner, fields, params, returns_void),
            Statement::Branch(branch) => {
                erase_void_block(&mut branch.if_block, fields, params, returns_void);
                if let Some(else_block) = &mut branch.else_block {
                    erase_void_block(else_block, fields, params, returns_void);
                }
            }
            Statement::While(wh) => erase_void_block(&mut wh.block, fields, params, returns_void),
            Statement::Return(ret) if returns_void => {
                if ret.expr.as_ref().is_some_and(|e| erased(e)) {
                    ret.expr = None;
                }
            }
            _ => {}
        }
    }
}

pub(crate) fn substitute_block(block: &mut Block, type_map: &[(String, TypeName)]) {
    for stmt in &mut block.items {
        substitute_statement(stmt, type_map);
    }
}

fn substitute_statement(stmt: &mut Statement, type_map: &[(String, TypeName)]) {
    match stmt {
        Statement::Expression(expr) => substitute_expression(expr, type_map),
        Statement::Block(inner) => substitute_block(inner, type_map),
        Statement::Declaration(Declaration::Variable(var)) => {
            substitute(&mut var.ty, type_map);
            if let Some(default) = &mut var.default {
                substitute_expression(default, type_map);
            }
        }
        Statement::Declaration(_) => {}
        Statement::Branch(branch) => {
            substitute_expression(&mut branch.condition, type_map);
            substitute_block(&mut branch.if_block, type_map);
            if let Some(else_block) = &mut branch.else_block {
                substitute_block(else_block, type_map);
            }
        }
        Statement::While(wh) => {
            substitute_expression(&mut wh.condition, type_map);
            substitute_block(&mut wh.block, type_map);
        }
        Statement::Return(ret) => {
            if let Some(expr) = &mut ret.expr {
                substitute_expression(expr, type_map);
            }
        }
        Statement::LoopBreak(_) => {}
    }
}

fn substitute_expression(expr: &mut Expression, type_map: &[(String, TypeName)]) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        // SizeOf<T> in specialized bodies: substitute the generic arg.
        if let Expression::SizeOf(ty) = e {
            substitute(ty, type_map);
        }
        // Intrinsic nodes carry a TypeName that may still reference a
        // generic param (e.g. `Address(T)` from `__address<T>(v)`):
        // substitute those too.
        match e {
            Expression::ArrayIndex { ty, .. }
            | Expression::IsPod(ty)
            | Expression::Default(ty)
            | Expression::Cast { ty, .. } => substitute(ty, type_map),
            Expression::RefCount(ty, _) | Expression::Weak(_, ty, _) => substitute(ty, type_map),
            Expression::Address(ty, _) => substitute(ty, type_map),
            Expression::AtomicLoad(ty, _)
            | Expression::AtomicStore(ty, _, _)
            | Expression::AtomicCmpXchg(ty, _, _, _) => substitute(ty, type_map),
            Expression::AtomicFetch(_, ty, _, _) => substitute(ty, type_map),
            Expression::FunctionPointer { owner: Some(ty), .. } => substitute(ty, type_map),
            Expression::MakeClosure { closure, ty, .. } => {
                substitute(ty, type_map);
                let mut parsed = crate::passes::gather_generics::parse_type_string(closure);
                substitute(&mut parsed, type_map);
                *closure = parsed.to_string();
            }
            _ => {}
        }
        // Constructor calls inside method bodies (`Array<T>(n)` →
        // `Array<int>(n)`): parse the name, substitute, re-emit.
        if let Expression::FunctionCall { function, .. } = e {
            let mut parsed = crate::passes::gather_generics::parse_type_string(function);
            substitute(&mut parsed, type_map);
            *function = parsed.to_string();
        }
        // A constructor's `__init_<field>` parameter is typed like its field
        // (`T`, `(T) => T`) when `finish` synthesizes it, and a symbol of a
        // compound type naming the parameters (`Seq<T>`, `(T) => U`) must
        // not keep them. A bare `T` symbol is left for type resolution.
        if let Expression::SymbolRef { id, ty, .. } = e {
            if id.starts_with("__init_") || !ty.sub_types.is_empty() {
                substitute(ty, type_map);
            }
        }
    });
}

pub fn specialize_structs(module: &mut Module) {
    let specs: Vec<TypeName> = module.struct_specs.clone();
    for spec in specs {
        // Dedupe: skip if a struct with this name/type already exists.
        if module
            .structs
            .iter()
            .any(|st| st.name == spec.to_string() || st.ty == spec)
        {
            continue;
        }
        let Some(base) = module
            .structs
            .iter()
            .find(|st| st.name == spec.name && st.ty.is_generic())
            .cloned()
        else {
            // Non-generic struct referenced with args, or unknown: skip.
            continue;
        };
        let mut specialized = specialize_struct(&base, &spec);
        // Apply synthesized members to the new instance (refcount + methods).
        crate::struct_body::apply_synthesized(&mut specialized);
        module.structs.push(specialized);
    }
}
