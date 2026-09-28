pub mod builder;
pub mod model;
pub mod passes;
pub(crate) mod static_type;
pub mod struct_body;
pub mod symbols;
pub mod type_name;
pub mod visibility;
pub mod model_tests;

pub use builder::build;
pub use model::Module;
pub use passes::transform_pass;
pub use passes::platform::apply_platform_filters;
pub use type_name::TypeName;
pub use visibility::{check_visibility, SourceFile, VisibilityError, VisibilityErrorKind};
