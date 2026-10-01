//! Range bounds must be integers.
//!
//! The builder lowers `a..b` and `a..>b` to `_range(a, b, inclusive)`
//! (runtime/range.pep), whose `T` is inferred from the bounds. A `Range<T>`
//! steps by `+ 1` and compares with `<`, so any other `T` would fail inside
//! the runtime. `check_ranges` runs once each call is specialized
//! (`_range<String>`) and reports it at the range operator instead.

use pepper_parser::diagnostic::Diagnostic;

use crate::model::*;

/// The name the builder gives a range's call.
pub const RANGE_FUNCTION: &str = "_range";

pub fn check_ranges(module: &mut Module) {
    let mut check = |expr: &mut Expression| {
        let Expression::FunctionCall { function, loc, .. } = expr else { return };
        let Some(bound) = function.strip_prefix(RANGE_FUNCTION).and_then(|rest| rest.strip_prefix('<')).and_then(|rest| rest.strip_suffix('>')) else {
            return;
        };
        if !is_integer(bound) {
            crate::errors::report(
                Diagnostic::error(format!("range bounds must be integers, not '{}'", bound)).at(*loc),
            );
        }
    };
    for st in &mut module.structs {
        if st.ty.is_generic() && st.name == st.ty.name {
            continue;
        }
        for body in st.constructors.iter_mut().filter_map(|c| c.body.as_mut()) {
            crate::passes::walk_block(body, &mut check);
        }
        for body in st.method_members.iter_mut().filter_map(|m| m.body.as_mut()) {
            crate::passes::walk_block(body, &mut check);
        }
    }
    for function in module.functions.iter_mut().filter(|f| !f.is_generic_func) {
        if let Some(body) = &mut function.body {
            crate::passes::walk_block(body, &mut check);
        }
    }
}

/// Whether `ty` is an integer type a range can step through (not `bool`, a
/// float, or an enum).
fn is_integer(ty: &str) -> bool {
    matches!(
        ty,
        "i8" | "char" | "u8" | "byte" | "i16" | "short" | "u16" | "ushort" | "i32" | "int" | "u32" | "uint" | "i64" | "long" | "u64" | "ulong"
    )
}
