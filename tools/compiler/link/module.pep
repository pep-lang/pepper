## The compiler's module loading and linking: `load_program` reads and
## parses a program's files (the root, everything its imports reach, and
## the runtime), then links them into one namespace.
export * from "program";
export [link, sort_errors, FileScope, Linked, ModuleError, ProgramFile] from "link";
export [
    declared_deprecation, deprecation_of, deprecation_warning, is_deprecation, Deprecation, DeprecationError
] from "deprecation";
export [
    contains_platform_predicate,
    DEFAULT_ANDROID_API,
    BUILD_OPTION_NAME_RULE,
    ENTRY_BUILD_OPTION,
    is_build_option_name,
    supported_triples,
    Target,
    TEST_ATTRIBUTE,
    TEST_BUILD_OPTION
] from "platform";
export [absolute, path_key, Runtime] from "files";
export [
    find_library_interface,
    interface_file_name,
    interface_hash,
    library_path_dirs,
    read_interface_bytes,
    InterfaceFile,
    LibraryInterface,
    INTERFACE_EXTENSION,
    INTERFACE_MAGIC
] from "interface_file";
export [
    ABI_VERSION,
    COMPILER_LEVEL,
    KIND_C,
    KIND_PEPPER,
    make_stamp,
    parse_stamp,
    read_stamps,
    RECORD_VERSION,
    REQUIRED_LEVEL_NAME,
    Stamp,
    STAMP_MAGIC,
    stamp_mismatch,
    stamp_warnings
] from "stamp";
export [declares_override, translation_units, TranslationUnit, unit_inputs] from "translation_units";
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
    parse_size,
    read_home_settings,
    read_lock,
    render_manifest_errors,
    Dependency,
    Feature,
    Host,
    LockedPackage,
    Manifest,
    ManifestError,
    Native,
    Packages,
    Resolution,
    DEPS_DIR,
    LOCK_FILE
] from "project";
export [find_project, MANIFEST_FILE] from "files";
