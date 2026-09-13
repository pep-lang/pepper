//! Port of `source/Sema/ConvertIntrinsics.h`: `__ptr<T>` → `T*` type rewrite;
//! `__is_pod`/`__default` calls become intrinsic expressions.

use crate::model::{Expression, FunctionDef, Module};
use crate::type_name::TypeName;

fn convert_type_string(ty: &mut TypeName) {
    if ty.name == "__ptr" {
        if ty.sub_types.len() != 1 {
            panic!("__ptr<T> takes only a single generic type argument");
        }
        let pointee = ty.sub_types[0].to_string();
        *ty = TypeName::new(&format!("{}*", pointee));
    }
}

fn convert_expression(expr: &mut Expression) {
    crate::passes::walk_expression(expr, &mut |e: &mut Expression| {
        if let Expression::FunctionCall { function, .. } = e {
            if function == "__is_pod" {
                *e = Expression::IsPod(TypeName::new(function));
            } else if function == "__default" {
                *e = Expression::Default(TypeName::new(function));
            }
        }
    });
}

fn convert_function(function: &mut FunctionDef) {
    convert_type_string(&mut function.ty);
    for param in &mut function.parameters {
        convert_type_string(&mut param.ty);
    }
    if let Some(body) = &mut function.body {
        crate::passes::walk_block(body, &mut convert_expression);
    }
}

pub fn convert_intrinsics(module: &mut Module) {
    for function in &mut module.functions {
        convert_function(function);
    }
    for st in &mut module.structs {
        for field in &mut st.field_members {
            convert_type_string(&mut field.ty);
        }
        for method in &mut st.method_members {
            convert_function(method);
        }
        if let Some(body) = &mut st.constructor.body {
            crate::passes::walk_block(body, &mut convert_expression);
        }
    }
}
