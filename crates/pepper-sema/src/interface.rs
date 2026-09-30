//! Build cache phase 2c: a file's **interface hash**, the part of the file
//! that code in other compilation units can depend on. A unit's cache key
//! names the files it imports by their interface hashes rather than their
//! text, so an edit that leaves a file's interface alone (a body, a comment,
//! a moved declaration) rebuilds only that file's unit: early cutoff.
//!
//! The interface is the file's declarations as the builder makes them,
//! without locations (their positions change with every edit above them,
//! and no unit's code depends on another's positions), and with the bodies
//! a cached unit's sema skips (`passes::strip_bodies`) replaced by what
//! stands in for them there: the function's recorded link summary. That
//! skipping those bodies changes no other unit's code is what verifying the
//! cache checks (`--verify-cache`), so the same bodies can change without
//! changing any other unit's code. A body without a recorded summary is
//! never skipped, so it is part of the interface.
//!
//! Also part of it: how many closures each skipped body creates, since a
//! file's closure structs are numbered in order (`__closure_3@io/file`), so
//! a closure added to one body renames those of the bodies after it,
//! generic ones included.

use crate::model::*;
use pepper_parser::ast;
use pepper_parser::diagnostic::{Diagnostic, FileId, Loc};
use std::collections::HashMap;
use std::fmt::Write;

/// The interface hash (hex) of `module`, the linked syntax tree of the
/// program file `file`, given the link summaries recorded for its functions
/// by location (see the module docs).
pub fn interface_hash(module: &ast::Module, file: FileId, summaries: &HashMap<Loc, &str>) -> Result<String, Diagnostic> {
    let mut built = crate::builder::build_file(module, file)?;
    // What stands in for each skipped body, in declaration order.
    let mut skipped: Vec<(usize, String)> = vec![];
    let mut skip = |function: &mut FunctionDef| {
        if !function.owner.is_none() || !function.generic_params.is_empty() || function.ty.is_auto() {
            return;
        }
        let Some(body) = function.body.take() else { return };
        let mut closures = 0;
        crate::passes::visit_block(&body, &mut |e| closures += matches!(e, Expression::ClosureLiteral(_)) as usize);
        let stands_in = match summaries.get(&function.loc) {
            Some(summary) => format!("summary {}", crate::passes::check_confinement::summary_without_position(summary)),
            None => ast::without_positions(|| format!("body {:?}", body)),
        };
        skipped.push((closures, stands_in));
    };
    for function in &mut built.functions {
        skip(function);
    }
    for st in built.structs.iter_mut().filter(|st| st.generic_params.is_empty()) {
        st.method_members.iter_mut().for_each(&mut skip);
    }
    for ext in built.extensions.iter_mut().filter(|e| e.target.sub_types.is_empty()) {
        ext.methods.iter_mut().for_each(&mut skip);
    }
    let mut hasher = blake3::Hasher::new();
    let mut out = HashWriter(&mut hasher);
    ast::without_positions(|| write!(out, "pepper interface 1\n{:?}\n{:?}", built, skipped)).expect("hashing cannot fail");
    Ok(hasher.finalize().to_hex().to_string())
}

/// Feeds formatted text to a hasher.
struct HashWriter<'h>(&'h mut blake3::Hasher);

impl Write for HashWriter<'_> {
    fn write_str(&mut self, s: &str) -> std::fmt::Result {
        self.0.update(s.as_bytes());
        Ok(())
    }
}
