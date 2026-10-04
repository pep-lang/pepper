## The compiler's module loading and linking: `load_program` reads and
## parses a program's files (the root, everything its imports reach, and
## the runtime), then links them into one namespace, as the Rust compiler's
## `pepper_sema::program` and `pepper_sema::modules` do.
export * from "program";
export [link, sort_errors, FileScope, Linked, ModuleError, ProgramFile] from "link";
export [deprecation_of, is_deprecation, Deprecation, DeprecationError] from "deprecation";
export [Target, TEST_BUILD_OPTION] from "platform";
