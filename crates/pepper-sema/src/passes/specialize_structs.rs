//! Port of `source/Sema/SpecializeStructs.h` + `Specialization.h`: clone
//! fields/ctor/methods into specialized structs, substitute generic params.

use crate::model::*;
use crate::type_name::TypeName;

/// Substitute generic params → args recursively through a TypeName.
fn substitute(ty: &mut TypeName, type_map: &[(String, TypeName)]) {
    for (param, arg) in type_map {
        ty.replace(param, arg);
    }
}

fn specialize_struct(base: &StructDef, spec_type: &TypeName) -> StructDef {
    // map generic_params[idx] -> spec.type.sub_types[idx]
    let mut type_map: Vec<(String, TypeName)> = vec![];
    for (idx, param) in base.generic_params.iter().enumerate() {
        if let Some(arg) = spec_type.sub_types.get(idx) {
            type_map.push((param.name.clone(), arg.clone()));
        }
    }

    let mut specialized = StructDef {
        name: spec_type.to_string(),
        ty: spec_type.clone(),
        generic_params: vec![],
        field_members: vec![],
        method_members: vec![],
        constructor: base.constructor.clone(),
        destructor: base.destructor.clone(),
        acquire: base.acquire.clone(),
        release: base.release.clone(),
        traits: base.traits.clone(),
    };

    // Fields: clone then substitute types.
    for field in &base.field_members {
        let mut f = field.clone();
        substitute(&mut f.ty, &type_map);
        specialized.field_members.push(f);
    }

    // Methods: clone then substitute types.
    for method in &base.method_members {
        let mut m = method.clone();
        substitute(&mut m.ty, &type_map);
        for param in &mut m.parameters {
            substitute(&mut param.ty, &type_map);
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

    specialized
}

fn substitute_block(block: &mut Block, type_map: &[(String, TypeName)]) {
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
    }
}

fn substitute_expression(expr: &mut Expression, type_map: &[(String, TypeName)]) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        // SizeOf<T> in specialized bodies: substitute the generic arg.
        if let Expression::SizeOf(ty) = e {
            substitute(ty, type_map);
        }
        // Constructor calls inside method bodies (`array<T>(n)` →
        // `array<int>(n)`): parse the name, substitute, re-emit.
        if let Expression::FunctionCall { function, .. } = e {
            let mut parsed = crate::passes::gather_generics::parse_type_string(function);
            substitute(&mut parsed, type_map);
            *function = parsed.to_string();
        }
        // `this` symbol refs in specialized bodies carry the base type.
        if let Expression::SymbolRef { id, ty } = e {
            if id == "this" && !type_map.is_empty() {
                // type_map is per-struct; leave resolution to implicit types.
                let _ = ty;
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
