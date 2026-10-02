//! Build options (#369): `-D NAME[=VALUE]` on the command line,
//! `[BuildOption("NAME")]`, `BuildOption(NAME)` and its comparisons with
//! literals in `[Target(...)]`, the warning for a comparison with an option
//! that is not defined, and `reflect.build_option` in `static` blocks.

use crate::support::{compile_jit_with_runtime, run_linked_with, sema};

/// `f`, compiling with the build options `options` (as `-D` takes them).
fn with_options<R>(options: &[&str], f: impl FnOnce() -> R) -> R {
    let mut target = pepper_sema::Target::host();
    target.build_options =
        options.iter().map(|o| pepper_sema::passes::platform::parse_build_option(o).expect("a valid option")).collect();
    pepper_sema::with_target(target, f)
}

/// What `test` in `source` returns, compiled with `options`.
fn run(options: &[&str], source: &str) -> i32 {
    with_options(options, || compile_jit_with_runtime(source))
}

/// 1 when `condition`, a `Target(...)` predicate, holds with `options`, else 0.
fn holds(options: &[&str], condition: &str) -> i32 {
    run(
        options,
        &format!("test(): int {{\n    var r = 0;\n    [Target({condition})] {{\n        r = 1;\n    }}\n    return r;\n}}\n"),
    )
}

const FAST_OR_PORTABLE: &str = "[BuildOption(\"FAST\")]\nspeed(): int {\n    return 2;\n}\n\n\
                                [Target(!BuildOption(FAST))]\nspeed(): int {\n    return 1;\n}\n\n\
                                test(): int {\n    return speed();\n}\n";

#[test]
fn build_option_attribute_selects_a_declaration() {
    assert_eq!(run(&[], FAST_OR_PORTABLE), 1);
    assert_eq!(run(&["FAST"], FAST_OR_PORTABLE), 2);
    assert_eq!(run(&["FAST=0"], FAST_OR_PORTABLE), 2, "defined is defined, whatever the value");
    assert_eq!(run(&["OTHER"], FAST_OR_PORTABLE), 1);
}

#[test]
fn build_option_combines_with_platform_predicates() {
    assert_eq!(holds(&["X"], "BuildOption(X) && (OS(Windows) || !OS(Windows))"), 1);
    assert_eq!(holds(&[], "BuildOption(X) || Arch(x64) || Arch(aarch64)"), 1);
    assert_eq!(holds(&[], "BuildOption(X) && (OS(Windows) || !OS(Windows))"), 0);
    // `BuildOption` on a block, alone.
    assert_eq!(
        run(&["X"], "test(): int {\n    var r = 0;\n    [BuildOption(\"X\")] {\n        r = 1;\n    }\n    return r;\n}\n"),
        1
    );
}

#[test]
fn integer_comparisons() {
    assert_eq!(holds(&["LOG_LEVEL=2"], "BuildOption(LOG_LEVEL) >= 2"), 1);
    assert_eq!(holds(&["LOG_LEVEL=1"], "BuildOption(LOG_LEVEL) >= 2"), 0);
    assert_eq!(holds(&["MASK=0x10"], "BuildOption(MASK) == 16"), 1);
    assert_eq!(holds(&["N=-3"], "BuildOption(N) < -2"), 1);
    assert_eq!(holds(&["N= 7 "], "BuildOption(N) != 7"), 0);
    // The literal first: `2 < BuildOption(L)` is `BuildOption(L) > 2`.
    assert_eq!(holds(&["L=3"], "2 < BuildOption(L)"), 1);
    assert_eq!(holds(&["L=2"], "2 < BuildOption(L)"), 0);
    // A bare `-D N` is `N=1`, as in C.
    assert_eq!(holds(&["N"], "BuildOption(N) == 1"), 1);
}

#[test]
fn string_bool_and_float_comparisons() {
    assert_eq!(holds(&["BACKEND=zlib"], "BuildOption(BACKEND) == \"zlib\""), 1);
    assert_eq!(holds(&["BACKEND=zstd"], "BuildOption(BACKEND) == \"zlib\""), 0);
    assert_eq!(holds(&["BACKEND=zlib"], "BuildOption(BACKEND) < \"zstd\""), 1);
    assert_eq!(holds(&["TRACE"], "BuildOption(TRACE) == true"), 1);
    assert_eq!(holds(&["TRACE=off"], "BuildOption(TRACE) == true"), 0);
    assert_eq!(holds(&["TRACE=Yes"], "BuildOption(TRACE) != false"), 1);
    assert_eq!(holds(&["SCALE=1.5"], "BuildOption(SCALE) > 1.25"), 1);
    assert_eq!(holds(&["SCALE=1.5"], "BuildOption(SCALE) <= 1.0"), 0);
}

#[test]
fn comparison_with_an_undefined_option_is_false_and_warns() {
    assert_eq!(holds(&[], "BuildOption(LEVEL) >= 0"), 0);
    assert_eq!(holds(&[], "BuildOption(LEVEL) != 0"), 0);
    assert_eq!(holds(&[], "!(BuildOption(LEVEL) >= 0)"), 1);
    let source = "test(): int {\n    var r = 0;\n    [Target(BuildOption(LEVEL) >= 2)] {\n        r = 1;\n    }\n    \
                  [Target(BuildOption(LEVEL))] {\n        r = 2;\n    }\n    return r;\n}\n";
    let warnings = with_options(&[], || sema(source).expect("compiles").render_warnings());
    assert_eq!(
        warnings,
        "test.pep:3:13: warning: build option 'LEVEL' is not defined; the comparison is false\n\
         \x20   3 |     [Target(BuildOption(LEVEL) >= 2)] {\n\
         \x20     |             ^~~~~~~~~~~~~~~~~~\n\
         note: define it with '-D LEVEL=<value>'"
    );
    // Defined, or only tested for, it does not warn.
    let warnings = with_options(&["LEVEL=3"], || sema(source).expect("compiles").render_warnings());
    assert_eq!(warnings, "");
}

#[test]
fn static_blocks_read_build_options() {
    let source = "test(): int {\n    var r = 0;\n    static (r) {\n        \
                  if (reflect.has_build_option(\"FAST\")) {\n            r = 10;\n        }\n        \
                  if (reflect.build_option(\"LEVEL\", \"0\") == \"3\") {\n            r = r + 3;\n        }\n    }\n    \
                  return r;\n}\n";
    assert_eq!(run(&[], source), 0);
    assert_eq!(run(&["FAST"], source), 10);
    assert_eq!(run(&["FAST", "LEVEL=3"], source), 13);
    let error = with_options(&[], || {
        sema("test(): int {\n    static {\n        reflect.print(reflect.build_option(\"NOPE\"));\n    }\n    return 0;\n}\n")
            .expect_err("an undefined option without a default")
    });
    assert!(error.contains("test.pep:3:31: error: build option 'NOPE' is not defined"), "{error}");
}

#[test]
fn reflection_reads_a_build_option_attribute() {
    let source = "[BuildOption(\"FAST\")]\nfast(): int {\n    return 1;\n}\n\n\
                  test(): int {\n    var n = 0;\n    static (n) {\n        \
                  for (var marked in reflect.functions_with<BuildOption>()) {\n            \
                  reflect.assert(marked.attribute<BuildOption>().name == \"FAST\", \"the option's name\");\n            \
                  n = n + 1;\n        }\n    }\n    return n;\n}\n";
    assert_eq!(run(&["FAST"], source), 1);
}

#[test]
fn command_line_options_select_code_and_key_the_cache() {
    // Two builds of one file with different `-D` values: the second must
    // not reuse the first's cached objects.
    let source = "[Target(BuildOption(GREETING) == \"hi\")]\ncode(): int {\n    return 3;\n}\n\n\
                  [Target(!(BuildOption(GREETING) == \"hi\"))]\ncode(): int {\n    return 4;\n}\n\n\
                  main(): int {\n    return code();\n}\n";
    let hi = run_linked_with("build_option_cli", source, &["-D", "GREETING=hi"], |_| {});
    let other = run_linked_with("build_option_cli", source, &["-DGREETING=yo"], |_| {});
    assert_eq!((hi.status.code(), other.status.code()), (Some(3), Some(4)));
}
