## The compiler's module loading and linking: `load_program` reads and
## parses a program's files (the root, everything its imports reach, and
## the runtime), then links them into one namespace, as the Rust compiler's
## `pepper_sema::program` and `pepper_sema::modules` do.
export * from "program";
export [link, sort_errors, FileScope, Linked, ModuleError, ProgramFile] from "link";
export [
    declared_deprecation, deprecation_of, deprecation_warning, is_deprecation, Deprecation, DeprecationError
] from "deprecation";
export [is_build_option_name, Target, TEST_BUILD_OPTION] from "platform";
export [path_key, Runtime] from "files";
export [declares_override, unit_inputs, units, Unit, PRELUDE_UNIT] from "units";
export [
    demangle_name, is_concrete_override, is_override, mangle, NAMESPACE_SEPARATOR, OVERLOAD_SEPARATOR, symbol_name
] from "names";
export [
    all_hosts,
    find_manifest,
    host_named,
    is_identifier,
    line_column,
    load_manifest,
    package_directory,
    parse_manifest,
    read_lock,
    render_manifest_errors,
    Dependency,
    Host,
    LockedPackage,
    Manifest,
    ManifestError,
    Packages,
    Resolution,
    DEPS_DIR,
    LOCK_FILE
] from "project";
export [find_project, MANIFEST_FILE] from "files";
