//! The lane count of a SIMD vector (#517). A generic struct whose field is
//! the built-in `__simd<T, N>` (the runtime's `simd.Vector<T, N>` and
//! `simd.Mask<N>`) takes its lane count as an integer type argument; each
//! specialization's count must be a power of two from 1 to 64, so a mask's
//! lanes fit the `ulong` of `to_bits()`. The error is located at the
//! argument where the program writes the type. The lane type is checked by
//! the `T: Lane` constraint (`passes::constraints`).

use crate::model::{Diagnostic, Loc, Module};
use crate::passes::check_function_types::canonical;
use crate::type_name::TypeName;
use std::collections::HashMap;

/// The largest lane count: a mask's bits fill a `ulong`.
pub const MAX_LANES: u64 = 64;

/// Whether `text` is a lane count a vector can have.
pub fn is_lane_count(text: &str) -> bool {
    text.parse::<u64>().is_ok_and(|n| n.is_power_of_two() && n <= MAX_LANES)
}

pub fn check_simd_shapes(module: &Module) {
    // Each generic struct holding a `__simd` field, with the index of the
    // parameter that is its lane count.
    let mut counted: HashMap<&str, usize> = HashMap::new();
    for st in module.structs.iter().filter(|st| st.ty.is_generic() && st.name == st.ty.name) {
        for field in &st.field_members {
            let Some(count) = field.ty.sub_types.get(1).filter(|_| field.ty.is_simd()) else { continue };
            if let Some(index) = st.generic_params.iter().position(|p| p.name == count.name) {
                counted.insert(st.name.as_str(), index);
            }
        }
    }
    if counted.is_empty() {
        return;
    }
    for spec in &module.struct_specs {
        let Some(&index) = counted.get(spec.name.as_str()) else { continue };
        let Some(count) = spec.sub_types.get(index) else { continue };
        if is_lane_count(&count.name) {
            continue;
        }
        crate::errors::report(
            Diagnostic::error(format!(
                "lane count of '{}' must be a power of two from 1 to {}, not '{}'",
                spec, MAX_LANES, count
            ))
            .at(argument_site(module, spec, index)),
        );
        return;
    }
}

/// Where the program writes `spec`'s argument `index`, else where it writes
/// `spec`, else nowhere.
fn argument_site(module: &Module, spec: &TypeName, index: usize) -> Loc {
    let spec = canonical(spec);
    module
        .type_uses
        .iter()
        .find(|u| canonical(&u.ty) == spec)
        .and_then(|u| u.args.get(index).copied())
        .unwrap_or(Loc::NONE)
}
