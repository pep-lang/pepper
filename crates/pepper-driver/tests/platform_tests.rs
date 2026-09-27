//! Platform selection end-to-end: the `Target(...)` attribute gates top-level
//! declarations and attributed blocks against the host (the compile target).
//! Expected values are computed from `std::env::consts::{OS, ARCH}`, so the
//! same assertions hold on any supported host.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

fn compile_jit(source: &str) -> i32 {
    compile_jit_mapped(source, |_| None)
}

/// Run the full pipeline to a JIT engine, mapping host symbols for declared
/// (not defined) functions before static ctors run — MCJIT resolves a declare
/// lazily, and an unmapped one is not addressable.
fn compile_jit_mapped(source: &str, map_global: impl Fn(&str) -> Option<usize>) -> i32 {
    // Struct constructors allocate via `_pep_malloc`, so the runtime prelude
    // must be linked (the support library's on-demand extern declaration is
    // gone).
    let mut module = SemaModule::default();
    let (runtime_sources, _libs, _dirs) = pepper_driver::runtime::discover();
    assert!(!runtime_sources.is_empty(), "runtime prelude not discovered");
    for path in runtime_sources {
        let content = std::fs::read_to_string(&path).expect("read runtime source");
        let ast = pepper_parser::parser::parse_source(&path.to_string_lossy(), &content)
            .expect("parse runtime source");
        module.merge(build(&ast).expect("build"));
    }
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    module.merge(build(&ast).expect("build"));
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module);
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine_mapped(&mut module, map_global).expect("jit engine");
    CodeGenerator::jit_call_i32(&ee, "test").expect("entry")
}

fn is_windows() -> bool {
    std::env::consts::OS == "windows"
}

fn is_x64() -> bool {
    std::env::consts::ARCH == "x86_64"
}

#[test]
fn block_os_match_kept() {
    // The matching block runs; the non-matching one is dropped.
    let expected = if is_windows() { 1 } else { 2 };
    assert_eq!(
        compile_jit(
            "test(): int {\n\
             var r = 3;\n\
             [Target(OS(Windows))] { r = 1; }\n\
             [Target(!OS(Windows))] { r = 2; }\n\
             return r;\n\
             }"
        ),
        expected
    );
}

#[test]
fn block_or_combination() {
    // `[Target(OS(Windows) || OS(Mac))]` matches on Windows and Mac, not Linux.
    let expected = if is_windows() || std::env::consts::OS == "macos" { 1 } else { 3 };
    assert_eq!(
        compile_jit(
            "test(): int {\n\
             var r = 3;\n\
             [Target(OS(Windows) || OS(Mac))] { r = 1; }\n\
             return r;\n\
             }"
        ),
        expected
    );
}

#[test]
fn block_and_combination() {
    // `[Target(OS(Windows) && Arch(x64))]` matches only on a Windows x64 host.
    let expected = if is_windows() && is_x64() { 1 } else { 3 };
    assert_eq!(
        compile_jit(
            "test(): int {\n\
             var r = 3;\n\
             [Target(OS(Windows) && Arch(x64))] { r = 1; }\n\
             return r;\n\
             }"
        ),
        expected
    );
}

#[test]
fn block_negated_composite() {
    // Negation wraps the whole composite: matches only on Linux.
    let expected = if std::env::consts::OS == "linux" { 1 } else { 3 };
    assert_eq!(
        compile_jit(
            "test(): int {\n\
             var r = 3;\n\
             [Target(!(OS(Windows) || OS(Mac)))] { r = 1; }\n\
             return r;\n\
             }"
        ),
        expected
    );
}

#[test]
fn block_nested_in_if() {
    // Filtering recurses into branch bodies.
    let expected = if is_windows() { 1 } else { 4 };
    assert_eq!(
        compile_jit(
            "test(): int {\n\
             var r = 9;\n\
             if true {\n\
                 [Target(OS(Windows))] { r = 1; }\n\
                 [Target(!OS(Windows))] { r = 4; }\n\
             }\n\
             return r;\n\
             }"
        ),
        expected
    );
}

// ── Top-level functions ────────────────────────────────────────────────────

#[test]
fn function_platform_split() {
    // Exactly one of the two definitions survives.
    let expected = if is_windows() { 1 } else { 2 };
    assert_eq!(
        compile_jit(
            "[Target(OS(Windows))] win(): int {\n\
             return 1;\n\
             }\n\
             [Target(!OS(Windows))] win(): int {\n\
             return 2;\n\
             }\n\
             test(): int {\n\
             return win();\n\
             }"
        ),
        expected
    );
}

#[test]
fn function_target_wraps_arch() {
    // `Target` wraps an `Arch(...)` predicate for arch-specific code.
    let expected = if is_x64() { 1 } else { 2 };
    assert_eq!(
        compile_jit(
            "[Target(Arch(x64))] b(): int {\n\
             return 1;\n\
             }\n\
             [Target(!Arch(x64))] b(): int {\n\
             return 2;\n\
             }\n\
             test(): int {\n\
             return b();\n\
             }"
        ),
        expected
    );
}

#[test]
fn function_case_insensitive_values() {
    // Values match case-insensitively.
    let expected = if is_windows() { 1 } else { 2 };
    assert_eq!(
        compile_jit(
            "[Target(OS(windows))] c(): int {\n\
             return 1;\n\
             }\n\
             [Target(!OS(windows))] c(): int {\n\
             return 2;\n\
             }\n\
             test(): int {\n\
             return c();\n\
             }"
        ),
        expected
    );
}

#[test]
fn multiple_attributes_anded() {
    // Multiple attributes on one item are ANDed: the non-predicate ones are
    // neutral, so exactly the matching `Target` definition survives.
    let expected = if is_windows() { 1 } else { 2 };
    assert_eq!(
        compile_jit(
            "[Target(OS(Windows))] [Export] f(): int {\n\
             return 1;\n\
             }\n\
             [Target(!OS(Windows))] [Inline] f(): int {\n\
             return 2;\n\
             }\n\
             test(): int {\n\
             return f();\n\
             }"
        ),
        expected
    );
}

// ── Structs ────────────────────────────────────────────────────────────────

#[test]
fn struct_platform_split() {
    // Only the matching definition is visible.
    let expected = if is_windows() { 1 } else { 2 };
    assert_eq!(
        compile_jit(
            "[Target(OS(Windows))] struct P {\n\
             int x;\n\
             new(this.x = 1) {}\n\
             }\n\
             [Target(!OS(Windows))] struct P {\n\
             int x;\n\
             new(this.x = 2) {}\n\
             }\n\
             test(): int {\n\
             var p = P();\n\
             return p.x;\n\
             }"
        ),
        expected
    );
}

// ── Externs ────────────────────────────────────────────────────────────────

fn filtered_module(source: &str) -> SemaModule {
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast).expect("build");
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    module
}

#[test]
fn extern_non_matching_dropped() {
    // A non-matching extern is dropped from the filtered module (asserted on
    // the model: an unreferenced LLVM declare would not fail MCJIT, so a JIT
    // compile alone cannot observe the drop).
    let predicate = if is_windows() { "[Target(!OS(Windows))]" } else { "[Target(OS(Windows))]" };
    let module = filtered_module(&format!(
        "{predicate} extern int missing_symbol();\n\
         test(): int {{\n\
         return 0;\n\
         }}"
    ));
    assert!(module.externs.is_empty(), "non-matching extern was kept");
}

#[test]
fn extern_matching_kept() {
    // A matching extern survives filtering.
    let predicate = if is_windows() { "[Target(OS(Windows))]" } else { "[Target(!OS(Windows))]" };
    let module = filtered_module(&format!(
        "{predicate} extern int present_symbol();\n\
         test(): int {{\n\
         return 0;\n\
         }}"
    ));
    assert_eq!(module.externs.len(), 1, "matching extern was dropped");
}

#[test]
fn extern_composite_predicate() {
    // A composite `Target` argument selects on both OS and Arch.
    let expected = if is_windows() && is_x64() { 1 } else { 0 };
    let module = filtered_module(
        "[Target(OS(Windows) && Arch(x64))] extern int composite_symbol();\n\
         test(): int {\n\
         return 0;\n\
         }",
    );
    assert_eq!(module.externs.len(), expected, "composite predicate mismatch");
}

// ── JIT invocation of per-arch symbols ─────────────────────────────────────

/// Bespoke per-arch host symbols: the Pepper test calls whichever matches the
/// host via a `Target(Arch(...))` gate, and MCJIT resolves it through the
/// global mapping. The non-matching twin is dropped by the filter, so MCJIT
/// never has to resolve it.
#[unsafe(no_mangle)]
pub extern "C" fn pep_test_arch_x64() -> i32 {
    0x5836
}

#[unsafe(no_mangle)]
pub extern "C" fn pep_test_arch_aarch64() -> i32 {
    0x4141
}

#[test]
fn extern_arch_symbol_invoked_in_jit() {
    // End-to-end: the matching per-arch extern is declared, called through a
    // gated block, and resolved by MCJIT to the host symbol.
    let expected = if is_x64() { 0x5836 } else { 0x4141 };
    assert_eq!(
        compile_jit_mapped(
            "[Target(Arch(x64))] extern int pep_test_arch_x64();\n\
             [Target(Arch(aarch64))] extern int pep_test_arch_aarch64();\n\
             arch_tag(): int {\n\
             [Target(Arch(x64))] { return pep_test_arch_x64(); }\n\
             [Target(Arch(aarch64))] { return pep_test_arch_aarch64(); }\n\
             return 0;\n\
             }\n\
             test(): int {\n\
             return arch_tag();\n\
             }",
            |name| match name {
                "pep_test_arch_x64" => Some(pep_test_arch_x64 as *const () as usize),
                "pep_test_arch_aarch64" => Some(pep_test_arch_aarch64 as *const () as usize),
                _ => None,
            },
        ),
        expected
    );
}

// ── Error paths ────────────────────────────────────────────────────────────

fn supported_host() -> bool {
    matches!(std::env::consts::OS, "windows" | "macos" | "linux")
        && matches!(std::env::consts::ARCH, "x86_64" | "aarch64")
}

/// A `Target(...)` attribute that is false on the current host, for tests
/// that need code to be dropped.
fn dropped_predicate() -> &'static str {
    if std::env::consts::OS == "linux" {
        "[Target(OS(Windows))]"
    } else {
        "[Target(OS(Linux))]"
    }
}

fn platform_err(source: &str) -> String {
    let ast = pepper_parser::parser::parse_source("test.pep", source).expect("parse error");
    let mut module: SemaModule = build(&ast).expect("build");
    pepper_sema::apply_platform_filters(&mut module).expect_err("platform filter must fail")
}

#[test]
fn unknown_os_value_errors() {
    // A misspelled/unsupported value is a hard error, not a silent drop.
    if !supported_host() {
        return;
    }
    let err = platform_err("[Target(OS(Darwin))] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
    // The offending attribute is named in the diagnostic.
    assert!(err.contains("OS(Darwin)"), "expected attribute context in: {err}");
}

#[test]
fn unknown_arch_value_errors() {
    // `arm64` is not a known arch name (x64, aarch64) — hard error.
    if !supported_host() {
        return;
    }
    let err = platform_err("[Target(Arch(arm64))] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("unknown Arch value"), "unexpected error: {err}");
}

#[test]
fn target_two_arguments_errors() {
    // `Target` takes exactly one value (a single boolean expression).
    let err = platform_err("[Target(OS(Windows), Arch(x64))] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("Target takes exactly one value"), "unexpected error: {err}");
}

#[test]
fn bare_target_errors() {
    // A bare `Target` without a call is not an attribute.
    let err = platform_err("[Target] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("used without a value"), "unexpected error: {err}");
}

#[test]
fn nested_target_errors() {
    // `Target` cannot be nested inside its own argument.
    let err = platform_err("[Target(Target(OS(Windows)))] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("cannot be nested"), "unexpected error: {err}");
}

#[test]
fn unknown_predicate_inside_target_errors() {
    // Only `OS` and `Arch` are valid inside `Target(...)`.
    let err = platform_err("[Target(Foo(Windows))] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("unknown predicate"), "unexpected error: {err}");
}

#[test]
fn bare_symbol_inside_target_errors() {
    // A bare symbol is not a predicate; `OS(...)`/`Arch(...)` calls are.
    let err = platform_err("[Target(Windows)] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("not a predicate"), "unexpected error: {err}");
}

#[test]
fn validation_not_short_circuited() {
    // `[Target(OS(Linux))] [Target(OS())]`: on a non-Linux host the first
    // predicate is false, but the malformed second attribute must still be
    // reported.
    let err = platform_err("[Target(OS(Linux))] [Target(OS())] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("exactly one value"), "unexpected error: {err}");
}

#[test]
fn combined_body_not_short_circuited() {
    // `[Target({false} && OS(Windwos))]`: the left half is false on every
    // supported host, but the malformed right half must still be reported.
    if !supported_host() {
        return;
    }
    let false_half = match std::env::consts::OS {
        "linux" => "OS(Windows)",
        _ => "OS(Linux)",
    };
    let err = platform_err(&format!(
        "[Target({false_half} && OS(Windwos))] f(): int {{\nreturn 0;\n}}\ntest(): int {{\nreturn 0;\n}}"
    ));
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}

#[test]
fn non_symbol_argument_errors() {
    // A literal argument is not a platform symbol — hard error.
    let err = platform_err("[Target(OS(1))] f(): int {\nreturn 0;\n}\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("must be a symbol"), "unexpected error: {err}");
}

#[test]
fn method_platform_split() {
    // Platform attributes on struct methods are evaluated, not ignored.
    let expected = if is_windows() { 7 } else { 8 };
    assert_eq!(
        compile_jit(
            "struct S {\n\
             int x;\n\
             new(this.x = 0) {}\n\
             [Target(OS(Windows))] int get() { return 7; }\n\
             [Target(!OS(Windows))] int get() { return 8; }\n\
             }\n\
             test(): int {\n\
             var s = S();\n\
             return s.get();\n\
             }"
        ),
        expected
    );
}

#[test]
fn extension_method_platform_split() {
    // Platform attributes on extension methods are evaluated, not ignored.
    let expected = if is_windows() { 9 } else { 10 };
    assert_eq!(
        compile_jit(
            "struct S {\n\
             int x;\n\
             new(this.x = 0) {}\n\
             }\n\
             extend S {\n\
             [Target(OS(Windows))] int get() { return 9; }\n\
             [Target(!OS(Windows))] int get() { return 10; }\n\
             }\n\
             test(): int {\n\
             var s = S();\n\
             return s.get();\n\
             }"
        ),
        expected
    );
}

#[test]
fn trait_method_platform_split() {
    // Platform attributes on traits and their methods are evaluated, not
    // ignored: the split keeps exactly one method per host. The JIT value
    // comes from the extension's cloned methods; the filtered-model checks
    // below guard the trait-method retain itself, which has no downstream
    // consumer.
    let source = "trait T {\n\
                 [Target(OS(Windows))] int get();\n\
                 [Target(!OS(Windows))] int get();\n\
                 }\n\
                 struct S {\n\
                 new() {}\n\
                 }\n\
                 extend S with T {\n\
                 [Target(OS(Windows))] int get() { return 11; }\n\
                 [Target(!OS(Windows))] int get() { return 12; }\n\
                 }\n\
                 test(): int {\n\
                 var s = S();\n\
                 return s.get();\n\
                 }";
    let expected = if is_windows() { 11 } else { 12 };
    assert_eq!(compile_jit(source), expected);
    let module = filtered_module(source);
    assert_eq!(module.traits[0].methods.len(), 1);
    // A trait dropped on this host disappears from the model entirely.
    let dropped = filtered_module(&format!("{d} trait T {{\nint get();\n}}", d = dropped_predicate()));
    assert!(dropped.traits.is_empty());
    // Same for a dropped extension.
    let dropped_ext = filtered_module(&format!(
        "trait T {{\nint get();\n}}\nstruct S {{\nnew() {{}}\n}}\n{d} extend S with T {{\nint get() {{ return 1; }}\n}}",
        d = dropped_predicate()
    ));
    assert!(dropped_ext.extensions.is_empty());
}

#[test]
fn malformed_attribute_body_is_parse_error() {
    // A body that fails to parse inside `[...]` is a hard error at the
    // brackets, not a misreported dangling `[` later. Top-level boolean logic
    // is also rejected: `[]` holds exactly one attribute.
    for source in [
        "[]\ntest(): int {\nreturn 0;\n}",
        "[*]\ntest(): int {\nreturn 0;\n}",
        "[if x { }]\ntest(): int {\nreturn 0;\n}",
        // Top-level boolean logic is not an attribute.
        "[OS(Windows) || OS(Mac)]\ntest(): int {\nreturn 0;\n}",
        "[!OS(Windows)]\ntest(): int {\nreturn 0;\n}",
        "[Target(OS(Windows)) && Export]\ntest(): int {\nreturn 0;\n}",
        // `OS`/`Arch` are only valid inside `Target(...)`.
        "[OS(Windows)]\ntest(): int {\nreturn 0;\n}",
        "[Arch(x64)]\ntest(): int {\nreturn 0;\n}",
    ] {
        assert!(
            pepper_parser::parser::parse_source("test.pep", source).is_err(),
            "expected parse error for: {source}"
        );
    }
}

#[test]
fn block_attribute_validated_on_all_hosts() {
    // An attributed block inside a surviving function is validated even when
    // the first predicate already drops it on this host — the misspelled
    // value is reported, not silently dropped.
    if !supported_host() {
        return;
    }
    let err = platform_err("test(): int {\n\
                            [Target(OS(Linux))] [Target(OS(Windwos))] { return 1; }\n\
                            return 0;\n\
                            }");
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}

#[test]
fn nested_block_in_dropped_block_is_walked() {
    // A malformed predicate nested inside a dropped block must still be
    // reported on every host, not only where the enclosing block matches.
    if !supported_host() {
        return;
    }
    let err = platform_err(&format!("test(): int {{\n\
                            {d} {{ [Target(OS(Windwos))] {{ }} }}\n\
                            return 0;\n\
                            }}", d = dropped_predicate()));
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}

#[test]
fn consecutive_non_matching_blocks_all_dropped() {
    // Removing one block must not skip the next one: both predicates below
    // are false on the current host, so `r` must stay 3.
    let (p1, p2) = match std::env::consts::OS {
        "linux" => ("[Target(OS(Windows))]", "[Target(OS(Mac))]"),
        "macos" => ("[Target(OS(Windows))]", "[Target(OS(Linux))]"),
        _ => ("[Target(OS(Linux))]", "[Target(OS(Mac))]"),
    };
    assert_eq!(
        compile_jit(&format!(
            "test(): int {{\n\
             var r = 3;\n\
             {p1} {{ r = 1; }}\n\
             {p2} {{ r = 2; }}\n\
             return r;\n\
             }}"
        )),
        3
    );
}

#[test]
fn block_after_dropped_block_is_validated() {
    // A malformed predicate on the block following a dropped one must be
    // reported on every host. The first block's predicate is false on this
    // host, so it is the one that gets removed.
    if !supported_host() {
        return;
    }
    let dropped = dropped_predicate();
    let err = platform_err(&format!("test(): int {{\n\
                            {dropped} {{ }}\n\
                            [Target(OS(Windwos))] {{ }}\n\
                            return 0;\n\
                            }}"));
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}
#[test]
fn dropped_function_body_is_walked() {
    // The predicate drops the function on this host, but a malformed
    // predicate inside its body must still be reported.
    if !supported_host() {
        return;
    }
    let err = platform_err(&format!("{d} f(): int {{\n\
                           [Target(OS(Windwos))] {{ return 1; }}\n\
                           return 0;\n\
                           }}\ntest(): int {{\nreturn 0;\n}}", d = dropped_predicate()));
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}

#[test]
fn constructor_attribute_validated() {
    // Constructor attributes are evaluated too (constructors cannot be
    // dropped), so an unknown value is a hard error.
    if !supported_host() {
        return;
    }
    let err = platform_err("struct S {\n\
                           [Target(OS(Windwos))] new() {}\n\
                           }\ntest(): int {\nreturn 0;\n}");
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}

#[test]
fn dropped_struct_member_body_is_walked() {
    // The predicate drops the struct (and its method) on this host, but a
    // malformed predicate inside the member's body must still be reported.
    if !supported_host() {
        return;
    }
    let err = platform_err(&format!("{d} struct S {{\n\
                           {d} f(): int {{ [Target(OS(Windwos))] {{ return 1; }} return 0; }}\n\
                           new() {{}}\n\
                           }}\ntest(): int {{\nreturn 0;\n}}", d = dropped_predicate()));
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}

#[test]
fn dropped_struct_constructor_attribute_validated() {
    // A constructor's attributes are validated even when the whole struct is
    // dropped on this host.
    if !supported_host() {
        return;
    }
    let err = platform_err(&format!("{d} struct S {{\n\
                           [Target(OS(Windwos))] new() {{}}\n\
                           }}\ntest(): int {{\nreturn 0;\n}}", d = dropped_predicate()));
    assert!(err.contains("unknown OS value"), "unexpected error: {err}");
}
