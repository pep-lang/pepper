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
fn undeclared_identifier_before_whitespace() {
    // The caret covers the name, not the space after it.
    assert_eq!(
        error_of("undeclared_before_space", "main(): int {\n    return nope + 1;\n}\n"),
        "main.pep:2:12: error: use of undeclared identifier 'nope'\n\
         \x20   2 |     return nope + 1;\n\
         \x20     |            ^~~~"
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

#[test]
fn deprecated_new_warns_with_a_fix_and_still_compiles() {
    let source = "struct S {\n    int x;\n    new(this.x = 7) {}\n}\ntest(): int {\n    var s = S();\n    return s.x;\n}\n";
    let program = pepper_driver::compiler::load_with_runtime("main.pep", source).expect("load");
    assert_eq!(
        program.render_warnings(),
        "main.pep:3:5: warning: `new` is deprecated; constructors are spelled `construct`, matching `destruct` [deprecated]\n\
         \x20   3 |     new(this.x = 7) {}\n\
         \x20     |     ^~~\n\
         \x20     |     construct"
    );
    // The fix points into main.pep, not whichever file the parser saw first.
    let warnings = program.warnings();
    assert_eq!(warnings.len(), 1, "the runtime itself uses no deprecated syntax");
    assert_eq!(warnings[0].fixes[0].edits[0].loc.file, pepper_driver::parser_diagnostic::FileId(0));

    let mut module = pepper_driver::compiler::compile_with_runtime("main.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    assert_eq!(CodeGenerator::new(&ctx, "main").jit_execute(&mut module, "test").expect("jit"), 7);
}

#[test]
fn function_type_mismatch() {
    assert_eq!(
        error_of(
            "function_type_mismatch",
            "square(x: int): int { return x * x; }\nmain(): int {\n    var f: (String) => int = square;\n    return 0;\n}\n"
        ),
        "main.pep:3:12: error: variable 'f' expects a function of type '(String) => int', but was given a function of type '(int) => int'\n\
         \x20   3 |     var f: (String) => int = square;\n\
         \x20     |            ^~~~~~~~~~~~~~~~"
    );
}

#[test]
fn with_binding_assigned() {
    let source = "struct S {\n    construct() {}\n    S enter() { return this; }\n    exit() {}\n}\nmain(): int {\n    with (var s = S()) {\n        s = S();\n    }\n    return 0;\n}\n";
    assert_eq!(
        error_of("with_binding_assigned", source),
        "main.pep:8:9: error: cannot assign to 's': it is bound by a 'with' block\n\
         \x20   8 |         s = S();\n\
         \x20     |         ^\n\
         main.pep:7:15: note: 's' is bound here\n\
         \x20   7 |     with (var s = S()) {\n\
         \x20     |               ^"
    );
}

#[test]
fn recursive_type_alias() {
    assert_eq!(
        error_of("recursive_type_alias", "type A = B;\ntype B = Array<A>;\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:1:6: error: type alias 'A' refers to itself\n\
         \x20   1 | type A = B;\n\
         \x20     |      ^\n\
         main.pep:2:6: note: through type alias 'B', declared here\n\
         \x20   2 | type B = Array<A>;\n\
         \x20     |      ^"
    );
}

#[test]
fn with_malformed_header() {
    assert_eq!(
        error_of("with_malformed_header", "main(): int {\n    with (var x) {\n    }\n    return 0;\n}\n"),
        "main.pep:2:16: error: expected '='\n\
         \x20   2 |     with (var x) {\n\
         \x20     |                ^"
    );
}

#[test]
fn subscript_of_an_element_that_is_not_indexable() {
    // Used to panic in codegen (reading and storing alike).
    let source = "main(): int {\n    var a = Array<int>();\n    a.append(1);\n    a[0][0] = 3;\n    return a[0][0];\n}\n";
    assert_eq!(
        error_of("subscript_not_indexable", source),
        "main.pep:4:5: error: subscripted value of type 'int' is not a pointer or an indexable struct\n\
         \x20   4 |     a[0][0] = 3;\n\
         \x20     |     ^~~~~~~"
    );
    let source = "main(): int {\n    var a = Array<int>();\n    a.append(1);\n    return a[0][0];\n}\n";
    assert_eq!(
        error_of("subscript_not_indexable_read", source),
        "main.pep:4:12: error: subscripted value of type 'int' is not a pointer or an indexable struct\n\
         \x20   4 |     return a[0][0];\n\
         \x20     |            ^~~~~~~"
    );
}

#[test]
fn with_void_binding() {
    let source = "struct Lock {\n    construct() {}\n    enter() {}\n    exit() {}\n}\nmain(): int {\n    with (var l = Lock()) {\n    }\n    return 0;\n}\n";
    assert_eq!(
        error_of("with_void_binding", source),
        "main.pep:7:15: error: cannot bind 'l': 'enter()' returns 'void'\n\
         \x20   7 |     with (var l = Lock()) {\n\
         \x20     |               ^\n\
         note: remove the binding: 'with (scope) { ... }'"
    );
}

#[test]
fn unknown_parameter_type() {
    assert_eq!(
        error_of("unknown_parameter_type", "f(x: Nope): int {\n    return 0;\n}\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:1:6: error: unknown type name 'Nope'\n\
         \x20   1 | f(x: Nope): int {\n\
         \x20     |      ^~~~"
    );
}

#[test]
fn with_else_on_int() {
    let source = "struct Counter {\n    construct() {}\n    int enter() { return 1; }\n    exit() {}\n}\nmain(): int {\n    with (var n = Counter()) {\n    } else {\n    }\n    return 0;\n}\n";
    assert_eq!(
        error_of("with_else_on_int", source),
        "main.pep:7:15: error: 'else' requires 'enter()' to return a struct reference, but it returns 'int'\n\
         \x20   7 |     with (var n = Counter()) {\n\
         \x20     |               ^"
    );
}

#[test]
fn bare_return_in_a_non_void_function() {
    assert_eq!(
        error_of("bare_return_non_void", "f(x: int): int {\n    if (x > 0) {\n        return;\n    }\n    return 1;\n}\nmain(): int {\n    return f(1);\n}\n"),
        "main.pep:3:9: error: non-void function 'f' should return a value\n\
         \x20   3 |         return;\n\
         \x20     |         ^~~~~~"
    );
}

#[test]
fn unknown_escape_sequence() {
    assert_eq!(
        error_of("unknown_escape_sequence", "main(): int {\n    print(\"a\\qb\");\n    return 0;\n}\n"),
        "main.pep:2:13: error: unknown escape sequence '\\q'\n\
         \x20   2 |     print(\"a\\qb\");\n\
         \x20     |             ^~"
    );
}

#[test]
fn with_no_enter() {
    let source = "struct Plain {\n    construct() {}\n}\nmain(): int {\n    with (var p = Plain()) {\n    }\n    return 0;\n}\n";
    assert_eq!(
        error_of("with_no_enter", source),
        "main.pep:5:19: error: 'Plain' cannot be used in a 'with' block: it has no 'enter()' method\n\
         \x20   5 |     with (var p = Plain()) {\n\
         \x20     |                   ^~~~~~~\n\
         note: a 'with' scope implements Scoped<T>: 'T enter()' and 'exit()'"
    );
}

#[test]
fn struct_does_not_conform_to_trait() {
    let source = "trait Shape {\n    int area();\n}\nstruct Circle {\n    construct() {}\n}\nmain(): int {\n    Shape s = Circle();\n    return 0;\n}\n";
    assert_eq!(
        error_of("struct_does_not_conform_to_trait", source),
        "main.pep:8:15: error: 'Circle' does not conform to trait 'Shape'\n\
         \x20   8 |     Shape s = Circle();\n\
         \x20     |               ^~~~~~\n\
         main.pep:4:8: note: declare it with 'extend Circle with Shape'\n\
         \x20   4 | struct Circle {\n\
         \x20     |        ^~~~~~"
    );
}

#[test]
fn static_trait_member_through_a_value() {
    let source = "trait Shape {\n    int area();\n    static this unit();\n}\nstruct Square {\n    construct() {}\n}\nextend Square with Shape {\n    int area() { return 1; }\n    static Square unit() { return Square(); }\n}\nmain(): int {\n    Shape s = Square();\n    var u = s.unit();\n    return 0;\n}\n";
    assert_eq!(
        error_of("static_trait_member_through_a_value", source),
        "main.pep:14:15: error: 'unit' is static and cannot be called on a value of trait type 'Shape'\n\
         \x20  14 |     var u = s.unit();\n\
         \x20     |               ^~~~\n\
         main.pep:3:17: note: 'unit' declared here\n\
         \x20   3 |     static this unit();\n\
         \x20     |                 ^~~~"
    );
}

#[test]
fn trait_method_signature_mismatch() {
    let source = "trait Shape {\n    int area();\n}\nstruct Square {\n    construct() {}\n}\nextend Square with Shape {\n    long area() { return 1; }\n}\nmain(): int {\n    return 0;\n}\n";
    assert_eq!(
        error_of("trait_method_signature_mismatch", source),
        "main.pep:8:10: error: 'area' in 'Square' has type '() => long', but trait 'Shape' declares '() => int'\n\
         \x20   8 |     long area() { return 1; }\n\
         \x20     |          ^~~~\n\
         main.pep:2:9: note: 'area' declared here\n\
         \x20   2 |     int area();\n\
         \x20     |         ^~~~"
    );
}

#[test]
fn weak_reference_to_trait_type() {
    let source = "trait Shape {\n    int area();\n}\nstruct Square {\n    construct() {}\n}\nextend Square with Shape {\n    int area() { return 1; }\n}\nmain(): int {\n    var w: Weak<Shape> = __null;\n    return 0;\n}\n";
    assert_eq!(
        error_of("weak_reference_to_trait_type", source),
        "main.pep:11:12: error: weak reference to trait type 'Shape' is not supported\n\
         \x20  11 |     var w: Weak<Shape> = __null;\n\
         \x20     |            ^~~~~~~~~~~"
    );
}

#[test]
fn assigning_a_captured_local() {
    assert_eq!(
        error_of(
            "closure_assign",
            "main(): int {\n    var count = 0;\n    var f = () => count;\n    count = 5;\n    return f();\n}\n"
        ),
        "main.pep:4:5: error: cannot assign to 'count' because a closure captures it\n\
         \x20   4 |     count = 5;\n\
         \x20     |     ^~~~~\n\
         main.pep:3:19: note: captured here; a closure keeps a copy, so the variable must not change\n\
         \x20   3 |     var f = () => count;\n\
         \x20     |                   ^~~~~"
    );
}

#[test]
fn closure_parameter_type_not_inferred() {
    assert_eq!(
        error_of("closure_infer", "main(): int {\n    var f = (x) => x;\n    return 0;\n}\n"),
        "main.pep:2:14: error: cannot infer the type of parameter 'x'; write it: (x: Type) => ...\n\
         \x20   2 |     var f = (x) => x;\n\
         \x20     |              ^"
    );
}

#[test]
fn closure_capturing_this_stored_in_a_field() {
    assert_eq!(
        error_of(
            "closure_cycle",
            "struct Widget {\n    int size;\n    () => int measure;\n    setup() { measure = () => size; }\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:4:15: error: storing a closure that captures 'this' in field 'measure' of 'this' creates a reference cycle that is never freed\n\
         \x20   4 |     setup() { measure = () => size; }\n\
         \x20     |               ^~~~~~~\n\
         main.pep:4:25: note: the closure captures 'this' here; capture a 'Weak' reference to it instead\n\
         \x20   4 |     setup() { measure = () => size; }\n\
         \x20     |                         ^~~~~~~~~~"
    );
}
