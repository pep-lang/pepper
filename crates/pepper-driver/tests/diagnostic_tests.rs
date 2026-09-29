//! Compiler errors through the driver: each points at the exact line and
//! column of the problem, clang-style, with the source line and a caret.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

/// Compile `source` as `main.pep` (with the runtime) through codegen and
/// return the rendered error, with the temp directory stripped from paths.
fn error_of(test: &str, source: &str) -> String {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_diagnostic_{}", test));
    std::fs::create_dir_all(&dir).unwrap();
    let main_path = dir.join("main.pep");
    std::fs::write(&main_path, source).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main_path.to_str().unwrap()]);
    let error = match pepper_driver::compiler::compile(&options, "main") {
        Err(e) => e,
        Ok(mut module) => {
            let ctx = inkwell::context::Context::create();
            let mut generator = CodeGenerator::new(&ctx, "main");
            match generator.generate(&mut module) {
                Err(d) => module.sources.render(&d),
                Ok(()) => panic!("expected {} to fail to compile", test),
            }
        }
    };
    error.replace(&format!("{}{}", dir.display(), std::path::MAIN_SEPARATOR), "")
}

#[test]
fn parse_error() {
    assert_eq!(
        error_of("parse", "main(): int {\n    var x = ;\n    return 0;\n}\n"),
        "main.pep:2:13: error: expected expression\n\
         \x20   2 |     var x = ;\n\
         \x20     |             ^"
    );
}

#[test]
fn undeclared_identifier() {
    assert_eq!(
        error_of("undeclared_identifier", "main(): int {\n    var a = 1;\n    return a + nope;\n}\n"),
        "main.pep:3:16: error: use of undeclared identifier 'nope'\n\
         \x20   3 |     return a + nope;\n\
         \x20     |                ^~~~"
    );
}

#[test]
fn undeclared_function() {
    assert_eq!(
        error_of("undeclared_function", "main(): int {\n    return frob(1);\n}\n"),
        "main.pep:2:12: error: call to undeclared function 'frob'\n\
         \x20   2 |     return frob(1);\n\
         \x20     |            ^~~~"
    );
}

#[test]
fn unknown_type() {
    assert_eq!(
        error_of("unknown_type", "main(): int {\n    var x: Frob = 1;\n    return 0;\n}\n"),
        "main.pep:2:12: error: unknown type name 'Frob'\n\
         \x20   2 |     var x: Frob = 1;\n\
         \x20     |            ^~~~"
    );
}

#[test]
fn unknown_member() {
    let source = "struct P { var x: int; }\nmain(): int {\n    var p = P();\n    return p.y;\n}\n";
    assert_eq!(
        error_of("unknown_member", source),
        "main.pep:4:14: error: no member named 'y' in 'P'\n\
         \x20   4 |     return p.y;\n\
         \x20     |              ^"
    );
}

#[test]
fn unknown_method() {
    let source = "struct P { var x: int; }\nmain(): int {\n    var p = P();\n    return p.go();\n}\n";
    assert_eq!(
        error_of("unknown_method", source),
        "main.pep:4:14: error: no member named 'go' in 'P'\n\
         \x20   4 |     return p.go();\n\
         \x20     |              ^~"
    );
}

#[test]
fn argument_count() {
    let source = "f(a: int, b: int = 2): int { return a + b; }\nmain(): int {\n    return f(1, 2, 3) + f();\n}\n";
    assert_eq!(
        error_of("too_many_args", source),
        "main.pep:3:12: error: too many arguments to 'f': expected at most 2, have 3\n\
         \x20   3 |     return f(1, 2, 3) + f();\n\
         \x20     |            ^"
    );
    let source = "f(a: int, b: int = 2): int { return a + b; }\nmain(): int {\n    return f();\n}\n";
    assert_eq!(
        error_of("too_few_args", source),
        "main.pep:3:12: error: too few arguments to 'f': expected at least 1, have 0\n\
         \x20   3 |     return f();\n\
         \x20     |            ^"
    );
}

#[test]
fn reserved_member() {
    let source = "struct P { var x: int; }\nmain(): int {\n    var p = P();\n    return p.__refcount;\n}\n";
    assert!(
        error_of("reserved_member", source).starts_with(
            "main.pep:4:14: error: '__refcount' is a reserved (synthesized) member and cannot be accessed from source code\n\
             \x20   4 |     return p.__refcount;\n\
             \x20     |              ^~~~~~~~~~"
        )
    );
}

#[test]
fn unresolved_import() {
    assert_eq!(
        error_of("unresolved_import", "import \"nope\";\nmain(): int { return 0; }\n"),
        "main.pep:1:8: error: cannot find \"nope.pep\" or the module folder \"nope\" next to this file\n\
         \x20   1 | import \"nope\";\n\
         \x20     |        ^~~~~~"
    );
}

#[test]
fn malformed_platform_attribute() {
    let e = error_of("platform", "f() {}\n[Target(Os)]\ng() {}\nmain(): int { return 0; }\n");
    assert!(e.starts_with("main.pep:2:1: error: bare symbol `Os` is not a predicate"), "{}", e);
    assert!(e.ends_with("    2 | [Target(Os)]\n      | ^~~~~~~~~~~~"), "{}", e);
}
