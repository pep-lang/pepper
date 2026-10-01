pub mod arithmetic;
pub mod builder;
pub mod deprecation;
pub mod enums;
pub mod interface;
pub mod member_lookup;
pub(crate) mod errors;
pub mod model;
pub mod modules;
pub mod passes;
pub mod program;
pub(crate) mod scope_walk;
pub(crate) mod static_type;
pub mod struct_body;
pub mod symbols;
pub mod traits;
pub mod type_name;
pub mod visibility;
#[cfg(test)]
mod model_tests;

pub use builder::build;
pub use model::Module;
pub use passes::transform_pass;
pub use passes::platform::{apply_platform_filters, with_simulated_host};
pub use type_name::TypeName;
pub use visibility::{check_visibility, SourceFile, VisibilityError, VisibilityErrorKind};
pub use modules::{FileScope, ModuleError, ProgramFile};
pub use pepper_parser::namespace;

/// Restart the thread-local counters that number synthesized names (hidden
/// `for`/`with` locals, closure structs, index temporaries), so a program
/// compiles to the same names, and the same symbols, however many programs
/// the thread compiled before. `program::load_program` calls it.
pub fn reset_program_counters() {
    builder::reset_counters();
    passes::closures::reset_counter();
    passes::resolve_operators::reset_counter();
}
