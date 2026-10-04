pub mod arithmetic;
pub mod builder;
pub mod casts;
pub mod checked;
pub mod cold;
pub mod deprecation;
pub mod enums;
pub mod equatable;
pub mod pass_timer;
pub mod value_structs;
pub mod value_types;
pub mod interface;
pub mod literals;
pub mod member_lookup;
pub(crate) mod errors;
pub mod model;
pub mod modules;
pub mod passes;
pub mod program;
pub mod runtime_checks;
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
pub use passes::platform::{apply_platform_filters, current_target, with_simulated_host, with_target, BuildOptions, Target};
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
