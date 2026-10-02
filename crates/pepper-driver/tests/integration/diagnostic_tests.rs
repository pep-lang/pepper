//! Compiler errors through the driver: each points at the exact line and
//! column of the problem, clang-style, with the source line and a caret.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use crate::support::repo_root;

/// Compile `source` as `main.pep` (with the runtime) through codegen and
/// return the rendered error, with the temp directory stripped from paths.
fn error_of(test: &str, source: &str) -> String {
    error_of_files(test, source, &[])
}

/// [`error_of`], with `others` (name, source) written beside `main.pep`.
fn error_of_files(test: &str, source: &str, others: &[(&str, &str)]) -> String {
    error_of_files_with(test, source, others, &[])
}

/// [`error_of_files`], with extra command-line arguments. The directory of
/// `main.pep` is on the search path (`-I`), so `others` may hold modules
/// (`alt/module.pep`) that `--import` names.
fn error_of_files_with(test: &str, source: &str, others: &[(&str, &str)], args: &[&str]) -> String {
    // chdir so runtime discovery resolves like the CLI.
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_diagnostic_{}_{}", test, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    for (name, other) in others {
        let path = dir.join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, other).unwrap();
    }
    let main_path = dir.join("main.pep");
    std::fs::write(&main_path, source).unwrap();
    let mut argv = vec!["pepper", main_path.to_str().unwrap()];
    if !args.is_empty() {
        argv.extend(["-I", dir.to_str().unwrap()]);
        argv.extend_from_slice(args);
    }
    let options = pepper_driver::Options::parse_from(argv);
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
fn missing_semicolon() {
    // Right after the statement, with the `;` to insert, not at the next line.
    let source = "main(): int {\n    var total = 1\n    return total;\n}\n";
    let error = pepper_parser::parser::parse_source_diag(source).unwrap_err();
    assert_eq!(
        error.render_in("main.pep", source),
        "main.pep:2:18: error: expected ';'\n\
         \x20   2 |     var total = 1\n\
         \x20     |                  ^\n\
         \x20     |                  ;"
    );
}

#[test]
fn extend_without_body_or_semicolon() {
    // An extension that adopts a trait may end with `;` instead of a body.
    let source = "extend Point with Shape\nmain(): int {\n    return 0;\n}\n";
    let error = pepper_parser::parser::parse_source_diag(source).unwrap_err();
    assert_eq!(
        error.render_in("main.pep", source),
        "main.pep:1:24: error: expected '{' or ';'\n\
         \x20   1 | extend Point with Shape\n\
         \x20     |                        ^\n\
         \x20     |                        ;"
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
fn struct_compared_with_integer() {
    // An `Optional` never equals an integer: comparing would compare the
    // object, so `find(3) == -1` would always be false.
    let source = "find(x: int): ulong? {\n    return Optional<ulong>.some(1);\n}\nmain(): int {\n    if (find(3) == -1) { return 1; }\n    return 0;\n}\n";
    assert_eq!(
        error_of("struct_with_integer", source),
        "main.pep:5:17: error: cannot compare 'Optional<ulong>' with an integer\n\
         \x20   5 |     if (find(3) == -1) { return 1; }\n\
         \x20     |                 ^~"
    );
    let source = "struct P {\n    var x: int = 0;\n}\nmain(): int {\n    var p = P();\n    return 0 != p ? 1 : 0;\n}\n";
    assert_eq!(
        error_of("integer_with_struct", source),
        "main.pep:6:14: error: cannot compare 'P' with an integer\n\
         \x20   6 |     return 0 != p ? 1 : 0;\n\
         \x20     |              ^~"
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
fn export_star_collision() {
    let others = [
        ("a.pep", "export area(): int { return 1; }\n"),
        ("b.pep", "export size(): int { return 2; }\nexport size as area;\n"),
    ];
    assert_eq!(
        error_of_files("export_star_collision", "export * from \"a\";\nexport * from \"b\";\nmain(): int { return 0; }\n", &others),
        "main.pep:2:1: error: 'area' is exported twice by \"main.pep\"\n\
         \x20   2 | export * from \"b\";\n\
         \x20     | ^~~~~~~~~~~~~~~~~\n\
         main.pep:1:1: note: also exported here\n\
         \x20   1 | export * from \"a\";\n\
         \x20     | ^~~~~~~~~~~~~~~~~"
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
        "main.pep:3:30: error: cannot initialize variable 'f' of type '(String) => int' with a value of type '(int) => int'\n\
         \x20   3 |     var f: (String) => int = square;\n\
         \x20     |                              ^~~~~~"
    );
}

/// A call through a function value with the wrong number of arguments is
/// located at the callee's name (#378).
#[test]
fn function_value_argument_count() {
    assert_eq!(
        error_of(
            "function_value_argument_count",
            "square(x: int): int { return x * x; }\nmain(): int {\n    var f = square;\n    return f(1, 2);\n}\n"
        ),
        "main.pep:4:12: error: too many arguments to function of type '(int) => int': expected 1, have 2\n\
         \x20   4 |     return f(1, 2);\n\
         \x20     |            ^"
    );
    assert_eq!(
        error_of(
            "function_field_argument_count",
            "struct S {\n    var f: (int) => int;\n    construct() { this.f = (x: int): int => x; }\n    run(): int { return f(); }\n}\nmain(): int { return S().run(); }\n"
        ),
        "main.pep:4:25: error: too few arguments to function of type '(int) => int': expected 1, have 0\n\
         \x20   4 |     run(): int { return f(); }\n\
         \x20     |                         ^"
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
fn generic_method_value_without_type_arguments() {
    assert_eq!(
        error_of(
            "generic_method_value",
            "struct Box<T> {\n    T value;\n    construct(v: T) { value = v; }\n    map<U>(f: (T) => U): Box<U> { return Box<U>(f(value)); }\n}\nmain(): int {\n    var m = Box<int>(1).map;\n    return 0;\n}\n"
        ),
        "main.pep:7:25: error: cannot infer the type arguments of method 'map' of 'Box<int>' used as a value; write them (map<U>) or give the value a function type\n\
         \x20   7 |     var m = Box<int>(1).map;\n\
         \x20     |                         ^~~\n\
         main.pep:4:5: note: declared here\n\
         \x20   4 |     map<U>(f: (T) => U): Box<U> { return Box<U>(f(value)); }\n\
         \x20     |     ^~~"
    );
}

#[test]
fn generic_function_value_without_type_arguments() {
    assert_eq!(
        error_of(
            "generic_function_value",
            "larger<T>(a: T, b: T): T { return a > b ? a : b; }\nmain(): int {\n    var f = larger;\n    return 0;\n}\n"
        ),
        "main.pep:3:13: error: cannot infer the type arguments of 'larger' used as a value; write them (larger<T>) or give the value a function type\n\
         \x20   3 |     var f = larger;\n\
         \x20     |             ^~~~~~\n\
         main.pep:1:1: note: declared here\n\
         \x20   1 | larger<T>(a: T, b: T): T { return a > b ? a : b; }\n\
         \x20     | ^~~~~~"
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
fn variadic_extern_as_a_function_value() {
    assert_eq!(
        error_of(
            "variadic_extern_value",
            "extern int snprintf(char* buffer, ulong size, char* format, ...);\nmain(): int {\n    var f = snprintf;\n    return 0;\n}\n"
        ),
        "main.pep:3:13: error: variadic extern 'snprintf' cannot be a function value; wrap a call to it in a closure\n\
         \x20   3 |     var f = snprintf;\n\
         \x20     |             ^~~~~~~~"
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

#[test]
fn shared_struct_field_not_const() {
    assert_eq!(
        error_of("shared_not_const", "[Shared]\nstruct Counter {\n    int count;\n}\nmain(): int { return 0; }\n"),
        "main.pep:3:9: error: field 'count' of shared struct 'Counter' must be 'const'\n\
         \x20   3 |     int count;\n\
         \x20     |         ^~~~~\n\
         note: threads change a shared struct's state through a thread-safe member such as 'async.Atomic<T>' (after 'import async')"
    );
}

#[test]
fn shared_struct_field_not_thread_safe() {
    assert_eq!(
        error_of(
            "shared_not_thread_safe",
            "struct Plain { int x; }\n[Shared]\nstruct Config {\n    const inner: Plain;\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:4:18: error: field 'inner' of shared struct 'Config' has type 'Plain', which is not thread-safe\n\
         \x20   4 |     const inner: Plain;\n\
         \x20     |                  ^~~~~\n\
         main.pep:1:8: note: 'Plain' is not declared [Shared]\n\
         \x20   1 | struct Plain { int x; }\n\
         \x20     |        ^~~~~"
    );
}

#[test]
fn module_scope_variable_not_const() {
    // A private global is as reachable from every thread as an exported one.
    assert_eq!(
        error_of("global_not_const", "var hits = 0;\nmain(): int { return hits; }\n"),
        "main.pep:1:5: error: module-scope variable 'hits' must be 'const'\n\
         \x20   1 | var hits = 0;\n\
         \x20     |     ^~~~\n\
         note: every thread can reach a module-scope variable; change its state through a thread-safe type such as 'async.Atomic<T>' or 'async.ThreadLocal<T>' (after 'import async')"
    );
}

#[test]
fn c_style_module_scope_variable_not_const() {
    assert_eq!(
        error_of("c_style_global_not_const", "long total = 0;\nmain(): int { return 0; }\n"),
        "main.pep:1:6: error: module-scope variable 'total' must be 'const'\n\
         \x20   1 | long total = 0;\n\
         \x20     |      ^~~~~\n\
         note: every thread can reach a module-scope variable; change its state through a thread-safe type such as 'async.Atomic<T>' or 'async.ThreadLocal<T>' (after 'import async')"
    );
}

#[test]
fn exported_variable_not_const() {
    assert_eq!(
        error_of("exported_not_const", "export var hits = 0;\nmain(): int { return hits; }\n"),
        "main.pep:1:12: error: module-scope variable 'hits' must be 'const'\n\
         \x20   1 | export var hits = 0;\n\
         \x20     |            ^~~~\n\
         note: every thread can reach a module-scope variable; change its state through a thread-safe type such as 'async.Atomic<T>' or 'async.ThreadLocal<T>' (after 'import async')"
    );
}

#[test]
fn module_scope_variable_not_thread_safe() {
    assert_eq!(
        error_of(
            "global_not_thread_safe",
            "struct Plain { var x: int; }\nconst origin: Plain = Plain();\nmain(): int { return 0; }\n"
        ),
        "main.pep:2:15: error: module-scope variable 'origin' has type 'Plain', which is not thread-safe\n\
         \x20   2 | const origin: Plain = Plain();\n\
         \x20     |               ^~~~~\n\
         main.pep:1:8: note: 'Plain' is not declared [Shared]\n\
         \x20   1 | struct Plain { var x: int; }\n\
         \x20     |        ^~~~~"
    );
}

#[test]
fn exported_variable_not_thread_safe() {
    assert_eq!(
        error_of(
            "exported_not_thread_safe",
            "struct Plain { var x: int; }\nexport const origin: Plain = Plain();\nmain(): int { return 0; }\n"
        ),
        "main.pep:2:22: error: module-scope variable 'origin' has type 'Plain', which is not thread-safe\n\
         \x20   2 | export const origin: Plain = Plain();\n\
         \x20     |                      ^~~~~\n\
         main.pep:1:8: note: 'Plain' is not declared [Shared]\n\
         \x20   1 | struct Plain { var x: int; }\n\
         \x20     |        ^~~~~"
    );
}

#[test]
fn module_scope_variable_with_inferred_type_not_thread_safe() {
    // No written type: the error points at the name.
    let error = error_of("global_inferred", "const greeting = \"hi\";\nmain(): int { return 0; }\n");
    assert!(
        error.starts_with(
            "main.pep:1:7: error: module-scope variable 'greeting' has type 'String', which is not thread-safe\n\
             \x20   1 | const greeting = \"hi\";\n\
             \x20     |       ^~~~~~~~\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: 'String' is not declared [Shared]"), "{error}");
}

#[test]
fn module_scope_trait_value_not_thread_safe() {
    // A trait value may hold any struct, so it is never thread-safe.
    assert_eq!(
        error_of(
            "global_trait_value",
            "trait Shape { int area(); }\n[Shared]\nstruct Square { construct() {} }\nextend Square with Shape { int area() { return 1; } }\n\n\nconst unit: Shape = Square();\nmain(): int { return 0; }\n"
        ),
        "main.pep:7:13: error: module-scope variable 'unit' has type 'Shape', which is not thread-safe\n\
         \x20   7 | const unit: Shape = Square();\n\
         \x20     |             ^~~~~"
    );
}

#[test]
fn reexported_variable_not_const() {
    // The error is at the declaration, whichever name other files use.
    assert_eq!(
        error_of_files(
            "reexported_not_const",
            "import \"lib\";\nmain(): int { return total; }\n",
            &[("lib.pep", "var count = 0;\nexport count as total;\n")]
        ),
        "lib.pep:1:5: error: module-scope variable 'count' must be 'const'\n\
         \x20   1 | var count = 0;\n\
         \x20     |     ^~~~~\n\
         note: every thread can reach a module-scope variable; change its state through a thread-safe type such as 'async.Atomic<T>' or 'async.ThreadLocal<T>' (after 'import async')"
    );
}

#[test]
fn shared_generic_argument_not_thread_safe() {
    // `Atomic<T: Shared>`: the error points at the type argument, with the
    // constraint and why the type is not thread-safe.
    let error = error_of("shared_generic_argument", "import async;\nmain(): int {\n    var a = async.Atomic<String>();\n    return 0;\n}\n");
    assert!(
        error.starts_with(
            "main.pep:3:26: error: 'String' does not conform to 'Shared', required by 'T' in 'Atomic'\n\
             \x20   3 |     var a = async.Atomic<String>();\n\
             \x20     |                          ^~~~~~\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: constraint declared here"), "{error}");
    assert!(error.contains("note: 'String' is not declared [Shared]"), "{error}");
}

#[test]
fn shared_constraint_on_a_runtime_function() {
    // `spawn<T: Shared>`: the error points at the type argument, with the
    // constraint and why the type is not thread-safe.
    let error = error_of(
        "shared_constraint_on_spawn",
        "import async;\n\nmain(): int {\n    async.run(() => {\n        var t = async.spawn<String>(() => { return \"x\"; });\n    });\n    return 0;\n}\n",
    );
    assert!(
        error.starts_with(
            "main.pep:5:29: error: 'String' does not conform to 'Shared', required by 'T' in 'spawn'\n\
             \x20   5 |         var t = async.spawn<String>(() => { return \"x\"; });\n\
             \x20     |                             ^~~~~~\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: constraint declared here"), "{error}");
    assert!(error.contains("note: 'String' is not declared [Shared]"), "{error}");
}

#[test]
fn shared_generic_argument_through_generic_function() {
    // A shared struct named inside a generic function without a constraint:
    // the error points at the call that asked for the specialization, and a
    // note shows where the specialization names the struct.
    let source = "[Shared]\nstruct Cell<T> {\n    const value: T;\n}\n\nmake<T>(): Cell<T> { return Cell<T>(); }\n\nmain(): int {\n    var c = make<String>();\n    return 0;\n}\n";
    let error = error_of("shared_generic_through_function", source);
    assert!(
        error.starts_with(
            "main.pep:9:13: error: 'make<String>' requires thread-safe type arguments; 'String' is not thread-safe\n\
             \x20   9 |     var c = make<String>();\n\
             \x20     |             ^~~~~~~~~~~~\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: 'Cell<String>' is required here, in 'make<String>'"), "{error}");
    assert!(error.contains("note: 'String' is not declared [Shared]"), "{error}");
}

/// The first semantic error of `source` (as `main.pep`, with the runtime),
/// as a `Diagnostic`, for checking its fixes.
fn sema_error_of(source: &str) -> pepper_driver::parser_diagnostic::Diagnostic {
    std::env::set_current_dir(repo_root()).unwrap();
    let program = pepper_driver::compiler::load_with_runtime("main.pep", source).expect("load");
    let mut module = pepper_driver::compiler::merge(&program).expect("merge");
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    pepper_sema::struct_body::apply(&mut module).expect("struct bodies");
    pepper_sema::transform_pass(&mut module).expect_err("expected a semantic error")
}

const HANDLE_LOG: &str = "struct Handle {\n    int fd;\n    destruct {\n        fd = -1;\n    }\n}\n\nstruct Log {\n    Handle out;\n}\n\nmain(): int {\n    var log = Log();\n    var c = copy(log);\n    return 0;\n}\n";

#[test]
fn cannot_copy_a_struct_with_a_destructor() {
    // At the `copy` call, a note for the field on the way, the reason at the
    // struct, and the `Copyable` skeleton.
    assert_eq!(
        error_of("cannot_copy_destructor", HANDLE_LOG),
        "main.pep:14:13: error: cannot copy 'Log' because it contains 'Handle', which is not trivially copyable\n\
         \x20  14 |     var c = copy(log);\n\
         \x20     |             ^~~~\n\
         main.pep:9:5: note: 'Log' reaches it through field 'out'\n\
         \x20   9 |     Handle out;\n\
         \x20     |     ^~~~~~\n\
         main.pep:1:8: note: 'Handle' has a destructor, so copying its fields would release what it owns twice\n\
         \x20   1 | struct Handle {\n\
         \x20     |        ^~~~~~\n\
         note: implement 'Copyable<Handle>' to say how to copy it:\n\
         \x20   extend Handle with Copyable<Handle> {\n\
         \x20       Handle copy(Copies copies) {\n\
         \x20           # Build the copy; copy each struct field with copies.copy(field).\n\
         \x20           panic(\"copying 'Handle' is not implemented\");\n\
         \x20           return this;\n\
         \x20       }\n\
         \x20   }"
    );
}

#[test]
fn cannot_copy_offers_a_copyable_skeleton_fix() {
    // The fix inserts the skeleton after the struct's closing brace.
    let error = sema_error_of(HANDLE_LOG);
    let [fix] = error.fixes.as_slice() else { panic!("{:?}", error.fixes) };
    assert_eq!(fix.message, "Implement Copyable<Handle>");
    let [edit] = fix.edits.as_slice() else { panic!("{:?}", fix.edits) };
    assert_eq!(edit.loc.file, pepper_driver::parser_diagnostic::FileId(0));
    let end = HANDLE_LOG.find("}\n\nstruct Log").unwrap() + 1;
    assert_eq!((edit.loc.span.start, edit.loc.span.end), (end, end));
    assert!(edit.replacement.starts_with("\n\nextend Handle with Copyable<Handle> {\n    Handle copy(Copies copies) {\n"), "{}", edit.replacement);
}

#[test]
fn cannot_copy_a_struct_with_a_raw_pointer() {
    assert_eq!(
        error_of(
            "cannot_copy_raw_pointer",
            "struct Buffer {\n    __ptr<u8> data;\n}\n\nmain(): int {\n    var b = Buffer();\n    var c = copy(b);\n    return 0;\n}\n"
        )
        .split("\nnote: implement")
        .next()
        .unwrap(),
        "main.pep:7:13: error: cannot copy 'Buffer', which is not trivially copyable\n\
         \x20   7 |     var c = copy(b);\n\
         \x20     |             ^~~~\n\
         main.pep:2:5: note: 'Buffer' has raw pointer field 'data' of type '__ptr<u8>'\n\
         \x20   2 |     __ptr<u8> data;\n\
         \x20     |     ^~~~~~~~~"
    );
}

#[test]
fn cannot_copy_shows_each_field_on_the_way() {
    let error = error_of(
        "cannot_copy_two_hops",
        "struct Handle {\n    int fd;\n    destruct {\n        fd = -1;\n    }\n}\n\nstruct Sink {\n    Handle out;\n}\n\nstruct Log {\n    Sink sink;\n}\n\nmain(): int {\n    var c = copy(Log());\n    return 0;\n}\n",
    );
    assert!(error.starts_with("main.pep:17:13: error: cannot copy 'Log' because it contains 'Handle', which is not trivially copyable\n"), "{error}");
    let log_hop = error.find("main.pep:13:5: note: 'Log' reaches it through field 'sink'").expect(&error);
    let sink_hop = error.find("main.pep:9:5: note: 'Sink' reaches it through field 'out'").expect(&error);
    assert!(log_hop < sink_hop, "{error}");
}

#[test]
fn cannot_copy_a_runtime_type_that_forbids_it() {
    // Through an Array: at the copy, and the runtime's reason instead of a
    // skeleton.
    let error = error_of(
        "cannot_copy_file",
        "import io;\n\nstruct Log {\n    io.File out;\n}\n\nmain(): int {\n    var lines = Array<Log>();\n    var copied = copy(lines);\n    return 0;\n}\n",
    );
    assert!(
        error.starts_with(
            "main.pep:9:18: error: cannot copy 'Array<Log>' because it contains 'File', which cannot be copied\n\
             \x20   9 |     var copied = copy(lines);\n\
             \x20     |                  ^~~~\n\
             note: 'Array<Log>' copies its values of type 'Log'\n\
             main.pep:4:5: note: 'Log' reaches it through field 'out'\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: 'File' owns an operating-system handle and cannot be copied; send its path, and open the file again on the receiving thread"), "{error}");
    assert!(!error.contains("implement 'Copyable"), "{error}");
}

#[test]
fn cannot_copy_through_a_value_enum() {
    // Reported at the copy the program asks for, not at the enum's
    // synthesized copy (which has no location).
    let error = error_of(
        "cannot_copy_through_optional",
        "[NotCopyable(\"owns a resource\")]\nstruct Handle {\n    int id;\n}\n\nmain(): int {\n    var handles = Array<Optional<Handle>>();\n    var copied = copy(handles);\n    return 0;\n}\n",
    );
    assert!(error.starts_with("main.pep:8:18: error: cannot copy 'Array<Optional<Handle>>'"), "{error}");
}

#[test]
fn cannot_copy_a_plain_function_value() {
    assert_eq!(
        error_of(
            "cannot_copy_function",
            "struct Job {\n    () => void run;\n}\n\nmain(): int {\n    var c = copy(Job());\n    return 0;\n}\n"
        ),
        "main.pep:6:13: error: cannot copy 'Job' because it contains '() => void', which is a plain function value\n\
         \x20   6 |     var c = copy(Job());\n\
         \x20     |             ^~~~\n\
         main.pep:2:5: note: 'Job' reaches it through field 'run'\n\
         \x20   2 |     () => void run;\n\
         \x20     |     ^~~~~~~~~~\n\
         note: a plain function value may capture values that are not thread-safe; declare the type 'shared () => void' to pass it by reference"
    );
}

#[test]
fn string_clone_is_deprecated() {
    let source = "main(): int {\n    var a = \"abc\";\n    var b = a.clone();\n    return 0;\n}\n";
    let rendered = warnings_of(source);
    assert!(
        rendered.starts_with(
            "main.pep:3:15: warning: 'clone' is deprecated: use 'copy' instead [deprecated]\n\
             \x20   3 |     var b = a.clone();\n\
             \x20     |               ^~~~~\n\
             \x20     |               copy\n"
        ),
        "{rendered}"
    );
}

/// The start of every confinement test: a Mutex of a struct that is not
/// thread-safe.
const LOCKED_NAMES: &str = "import async;\n\nconst names = async.Mutex<Array<String>>(Array<String>());\n\n";

fn confinement_error(test: &str, body: &str) -> String {
    error_of(test, &format!("{LOCKED_NAMES}{body}"))
}

#[test]
fn a_value_cannot_move_into_a_locked_value() {
    assert_eq!(
        confinement_error(
            "confine_into",
            "main(): int {\n    var line = \"x\";\n    with (var list = names.lock()) {\n        list.append(line);\n    }\n    return 0;\n}\n"
        ),
        "main.pep:8:21: error: 'line' cannot move into the value locked by 'names'\n\
         \x20   8 |         list.append(line);\n\
         \x20     |                     ^~~~\n\
         main.pep:7:28: note: locked here\n\
         \x20   7 |     with (var list = names.lock()) {\n\
         \x20     |                            ^~~~\n\
         note: 'String' is not thread-safe, so the locked value cannot share it with the rest of the program; pass 'copy(line)'"
    );
}

#[test]
fn part_of_a_locked_value_cannot_outlive_the_lock() {
    assert_eq!(
        confinement_error(
            "confine_out",
            "main(): int {\n    var first = \"\";\n    with (var list = names.lock()) {\n        first = list[0];\n    }\n    return 0;\n}\n"
        ),
        "main.pep:8:17: error: 'list[0]' is part of the value locked by 'names' and cannot outlive the lock\n\
         \x20   8 |         first = list[0];\n\
         \x20     |                 ^~~~~~~\n\
         main.pep:7:28: note: locked here\n\
         \x20   7 |     with (var list = names.lock()) {\n\
         \x20     |                            ^~~~\n\
         note: 'String' is not thread-safe, so no part of the locked value may be kept outside the block; take 'copy(list[0])'"
    );
}

#[test]
fn part_of_a_locked_value_cannot_be_returned() {
    let error = confinement_error(
        "confine_return",
        "take(): String {\n    with (var list = names.lock()) {\n        return list[0];\n    }\n    return \"\";\n}\n\nmain(): int {\n    return 0;\n}\n",
    );
    assert!(
        error.starts_with(
            "main.pep:7:16: error: 'list[0]' is part of the value locked by 'names' and cannot be returned from the block\n\
             \x20   7 |         return list[0];\n\
             \x20     |                ^~~~~~~\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: return 'copy(list[0])' instead"), "{error}");
}

#[test]
fn a_closure_cannot_capture_a_locked_value() {
    let error = confinement_error(
        "confine_closure",
        "main(): int {\n    with (var list = names.lock()) {\n        var f = () => list.count;\n    }\n    return 0;\n}\n",
    );
    assert!(error.starts_with("main.pep:7:17: error: closure captures 'list', which is part of the value locked by 'names'\n"), "{error}");
}

#[test]
fn two_locked_values_stay_apart() {
    let error = confinement_error(
        "confine_two",
        "const other = async.Mutex<Array<String>>(Array<String>());\n\nmain(): int {\n    with (var a = names.lock()) {\n        with (var b = other.lock()) {\n            b.append(a[0]);\n        }\n    }\n    return 0;\n}\n",
    );
    assert!(
        error.starts_with("main.pep:10:22: error: 'a[0]' is part of the value locked by 'names' and cannot move into the value locked by 'other'\n"),
        "{error}"
    );
}

#[test]
fn new_values_and_copies_cross_a_lock() {
    // A literal, a fresh result, a thread-safe value, a copy, and a call
    // that does not keep its argument all compile.
    let dir = std::env::temp_dir().join("pepper_diagnostic_confine_fine");
    std::fs::create_dir_all(&dir).unwrap();
    let main = dir.join("main.pep");
    std::fs::write(
        &main,
        format!(
            "{LOCKED_NAMES}first(): String {{\n    with (var list = names.lock()) {{\n        return list[0].copy();\n    }}\n    return \"\";\n}}\n\n\
             main(): int {{\n    var line = \"x\";\n    with (var list = names.lock()) {{\n        list.append(\"worker\");\n        list.append(line + \"!\");\n        list.append(copy(line));\n        var n = list.count;\n        var found = list.contains(line);\n    }}\n    return 0;\n}}\n"
        ),
    )
    .unwrap();
    std::env::set_current_dir(repo_root()).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main.to_str().unwrap()]);
    pepper_driver::compiler::compile(&options, "main").unwrap_or_else(|e| panic!("{e}"));
}

#[test]
fn each_tuple_element_has_its_own_fresh_bit() {
    // `split` builds its first element and returns its argument as the
    // second: only the first is new.
    let source = |element: &str| {
        format!(
            "split(s: String): (String, String) {{
    return (s + \"!\", s);
}}

             main(): int {{
    var line = \"x\";
    with (var list = names.lock()) {{
        var (fresh, same) = split(line);
        list.append({element});
    }}
    return 0;
}}
"
        )
    };
    let error = confinement_error("tuple_same", &source("same"));
    assert!(error.starts_with("main.pep:13:21: error: 'same' cannot move into the value locked by 'names'
"), "{error}");
    let dir = std::env::temp_dir().join("pepper_diagnostic_tuple_fresh");
    std::fs::create_dir_all(&dir).unwrap();
    let main = dir.join("main.pep");
    std::fs::write(&main, format!("{LOCKED_NAMES}{}", source("fresh"))).unwrap();
    std::env::set_current_dir(repo_root()).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main.to_str().unwrap()]);
    pepper_driver::compiler::compile(&options, "main").unwrap_or_else(|e| panic!("{e}"));
}

#[test]
fn raw_memory_behind_a_shared_struct_is_not_fresh() {
    // A reference read through a `[Shared]` struct's raw field may be
    // referenced elsewhere; a channel's `receive` moves its value out of the buffer.
    let program = |taken: &str| {
        format!(
            "const jobs = async.Channel<String>();\n\n[Shared]\nstruct Box {{\n    const _slot: __ptr<void>;\n    construct() {{\n        _slot = _pep_malloc(8);\n    }}\n    String take() {{\n        __ptr<String> typed = _slot;\n        return typed[0];\n    }}\n}}\n\n\
             main(): int {{\n    var b = Box();\n    with (var list = names.lock()) {{\n        list.append({taken});\n    }}\n    return 0;\n}}\n"
        )
    };
    let error = confinement_error("raw_shared_read", &program("b.take()"));
    assert!(error.starts_with("main.pep:22:23: error: 'b.take()' cannot move into the value locked by 'names'\n"), "{error}");
    let dir = std::env::temp_dir().join("pepper_diagnostic_returns_owned_receive");
    std::fs::create_dir_all(&dir).unwrap();
    let main = dir.join("main.pep");
    std::fs::write(&main, format!("{LOCKED_NAMES}{}", program("jobs.receive().value()"))).unwrap();
    std::env::set_current_dir(repo_root()).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main.to_str().unwrap()]);
    pepper_driver::compiler::compile(&options, "main").unwrap_or_else(|e| panic!("{e}"));
}

#[test]
fn move_of_an_aliased_local_is_an_error() {
    assert_eq!(
        confinement_error(
            "move_alias",
            "main(): int {\n    var a = Array<String>();\n    var b = a;\n    names.replace(move(a));\n    return 0;\n}\n"
        ),
        "main.pep:8:24: error: 'a' cannot be moved: 'b' also references its value\n\
         \x20   8 |     names.replace(move(a));\n\
         \x20     |                        ^\n\
         note: only a variable that holds the one reference to a new value can hand it over; pass 'copy(...)' instead"
    );
}

#[test]
fn move_of_a_parameter_is_an_error() {
    assert_eq!(
        confinement_error(
            "move_parameter",
            "give(Array<String> s) {\n    names.replace(move(s));\n}\n\nmain(): int {\n    give(Array<String>());\n    return 0;\n}\n"
        ),
        "main.pep:6:24: error: 's' cannot be moved: its value shares objects with the rest of the program\n\
         \x20   6 |     names.replace(move(s));\n\
         \x20     |                        ^\n\
         note: only a variable that holds the one reference to a new value can hand it over; pass 'copy(...)' instead"
    );
}

#[test]
fn move_of_a_field_is_an_error() {
    assert_eq!(
        confinement_error(
            "move_field",
            "struct Holder {\n    var s: Array<String>;\n    construct() {\n        s = Array<String>();\n    }\n}\n\nmain(): int {\n    var h = Holder();\n    names.replace(move(h.s));\n    return 0;\n}\n"
        ),
        "main.pep:14:26: error: 'h.s' cannot be moved: only a local variable or parameter can hand over its value\n\
         \x20  14 |     names.replace(move(h.s));\n\
         \x20     |                          ^"
    );
}

#[test]
fn use_after_move_is_an_error() {
    assert_eq!(
        confinement_error(
            "move_use_after",
            "main(): int {\n    var a = Array<String>();\n    names.replace(move(a));\n    return a.count;\n}\n"
        ),
        "main.pep:8:12: error: 'a' is used after its value was moved\n\
         \x20   8 |     return a.count;\n\
         \x20     |            ^\n\
         main.pep:7:19: note: 'a' was moved here; assign it a new value before using it again\n\
         \x20   7 |     names.replace(move(a));\n\
         \x20     |                   ^~~~"
    );
}

#[test]
fn move_in_a_loop_is_a_use_after_move() {
    assert_eq!(
        confinement_error(
            "move_in_loop",
            "main(): int {\n    var a = Array<String>();\n    while (true) {\n        names.replace(move(a));\n    }\n    return 0;\n}\n"
        ),
        "main.pep:8:28: error: 'a' is used after its value was moved\n\
         \x20   8 |         names.replace(move(a));\n\
         \x20     |                            ^\n\
         main.pep:8:23: note: 'a' was moved here; assign it a new value before using it again\n\
         \x20   8 |         names.replace(move(a));\n\
         \x20     |                       ^~~~"
    );
}

#[test]
fn move_out_of_raw_memory_is_only_for_the_runtime() {
    assert_eq!(
        confinement_error(
            "move_raw",
            "main(): int {\n    __ptr<String> p = _pep_malloc(8);\n    var s = move(p[0]);\n    return 0;\n}\n"
        ),
        "main.pep:7:18: error: only the runtime may move a value out of raw memory\n\
         \x20   7 |     var s = move(p[0]);\n\
         \x20     |                  ^~~~\n\
         note: it promises that the slot held the only reference, which the compiler cannot check"
    );
}

#[test]
fn a_guard_is_only_a_with_scope() {
    assert_eq!(
        confinement_error("guard_variable", "main(): int {\n    var g = names.lock();\n    return 0;\n}\n"),
        "main.pep:6:19: error: 'MutexGuard<Array<String>>' can only be the scope of a 'with' block\n\
         \x20   6 |     var g = names.lock();\n\
         \x20     |                   ^~~~\n\
         note: a guard unlocks when its block ends; write 'with (var value = ...) { ... }'"
    );
    let field = confinement_error("guard_field", "struct Holder {\n    async.MutexGuard<Array<String>> guard;\n}\n\nmain(): int {\n    return 0;\n}\n");
    assert!(field.starts_with("main.pep:6:5: error: 'MutexGuard<Array<String>>' can only be the scope of a 'with' block\n"), "{field}");
}

#[test]
fn a_mutex_cannot_protect_a_number() {
    assert_eq!(
        error_of("mutex_int", "import async;\n\nmain(): int {\n    var m = async.Mutex<int>(0);\n    return 0;\n}\n"),
        "main.pep:4:13: error: 'Mutex<int>' cannot protect a number: its 'with' binding is a copy that the block cannot store back\n\
         \x20   4 |     var m = async.Mutex<int>(0);\n\
         \x20     |             ^~~~~~~~~~~~~~~~\n\
         note: use 'async.Atomic<int>' for a number that threads share"
    );
}

#[test]
fn move_source_is_only_for_the_runtime() {
    assert_eq!(
        error_of("move_source_user", "take([MoveSource] String s): String {\n    return s;\n}\n\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:1:6: error: '[MoveSource]' is only allowed in the runtime\n\
         \x20   1 | take([MoveSource] String s): String {\n\
         \x20     |      ^~~~~~~~~~~~\n\
         note: take the value with '[Move]', and have callers pass 'move(x)'"
    );
}

#[test]
fn sending_was_renamed_move() {
    assert_eq!(
        error_of("sending_renamed", "keep([Sending] String s) {\n}\n\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:1:6: error: unknown parameter attribute '[Sending]'\n\
         \x20   1 | keep([Sending] String s) {\n\
         \x20     |      ^~~~~~~~~\n\
         \x20     |      [Move]\n\
         note: a parameter takes '[Move]'"
    );
}

#[test]
fn a_moved_variable_may_move_into_a_locked_value() {
    // `move(x)` is a new value, so it may join the locked one even when `x`
    // was declared outside the block.
    compile_ok(
        "move_into_lock",
        "import async;\n\nconst names = async.Mutex<Array<String>>(Array<String>());\n\nmain(): int {\n    var line = \"x\";\n    with (var list = names.lock()) {\n        list.append(move(line));\n    }\n    return 0;\n}\n",
    );
}

const WAIT_WHILE_HEADER: &str = "import async;\n\nconst jobs = async.Mutex<Array<String>>(Array<String>());\nconst ready = jobs.condition();\n\n";

#[test]
fn a_locked_predicate_cannot_keep_the_value() {
    assert_eq!(
        error_of(
            "locked_keep",
            &format!(
                "{WAIT_WHILE_HEADER}main(): int {{\n    var saved = Array<String>();\n    with (var list = jobs.lock()) {{\n        ready.wait_while((queue: Array<String>): bool => {{\n            saved.append(queue[0]);\n            return queue.count == 0;\n        }});\n    }}\n    return 0;\n}}\n"
            )
        ),
        "main.pep:10:26: error: 'queue[0]' is part of the value locked by 'queue' and cannot outlive the lock\n\
         \x20  10 |             saved.append(queue[0]);\n\
         \x20     |                          ^~~~~~~~\n\
         main.pep:9:27: note: locked here\n\
         \x20   9 |         ready.wait_while((queue: Array<String>): bool => {\n\
         \x20     |                           ^~~~~\n\
         note: 'String' is not thread-safe, so no part of the locked value may be kept outside the block; take 'copy(queue[0])'"
    );
}

#[test]
fn a_locked_predicate_cannot_bring_a_value_in() {
    assert_eq!(
        error_of(
            "locked_bring",
            &format!(
                "{WAIT_WHILE_HEADER}main(): int {{\n    var extra = \"x\";\n    with (var list = jobs.lock()) {{\n        ready.wait_while((queue: Array<String>): bool => {{\n            queue.append(extra);\n            return false;\n        }});\n    }}\n    return 0;\n}}\n"
            )
        ),
        "main.pep:10:26: error: 'extra' cannot move into the value locked by 'queue'\n\
         \x20  10 |             queue.append(extra);\n\
         \x20     |                          ^~~~~\n\
         main.pep:9:27: note: locked here\n\
         \x20   9 |         ready.wait_while((queue: Array<String>): bool => {\n\
         \x20     |                           ^~~~~\n\
         note: 'String' is not thread-safe, so the locked value cannot share it with the rest of the program; pass 'copy(extra)'"
    );
}

#[test]
fn a_locked_parameter_takes_a_closure() {
    let error = error_of(
        "locked_named",
        &format!(
            "{WAIT_WHILE_HEADER}empty(queue: Array<String>): bool {{\n    return queue.count == 0;\n}}\n\nmain(): int {{\n    with (var list = jobs.lock()) {{\n        ready.wait_while(empty);\n    }}\n    return 0;\n}}\n"
        ),
    );
    assert!(
        error.starts_with(
            "main.pep:12:26: error: parameter 'predicate' takes a closure written at the call, because it is called with a locked value\n\
             \x20  12 |         ready.wait_while(empty);\n\
             \x20     |                          ^~~~~\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: 'predicate' is declared [Locked] here"), "{error}");
    assert!(error.ends_with("note: write the function here, as a closure, so the compiler can check that it keeps the value to itself"), "{error}");
}

#[test]
fn locked_is_only_for_the_runtime() {
    assert_eq!(
        error_of("locked_user", "check([Locked] predicate: (int) => bool): bool {\n    return predicate(1);\n}\n\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:1:7: error: '[Locked]' is only allowed in the runtime\n\
         \x20   1 | check([Locked] predicate: (int) => bool): bool {\n\
         \x20     |       ^~~~~~~~\n\
         note: a function that reads a locked value runs inside a 'with' block"
    );
}

#[test]
fn a_move_parameter_takes_a_new_value() {
    let error = error_of(
        "sending_named",
        "import async;\n\nmain(): int {\n    var list = Array<String>();\n    var m = async.Mutex<Array<String>>(list);\n    return 0;\n}\n",
    );
    assert!(
        error.starts_with(
            "main.pep:5:40: error: 'list' is not a new value, but parameter 'value' takes a value that nothing else references\n\
             \x20   5 |     var m = async.Mutex<Array<String>>(list);\n\
             \x20     |                                        ^~~~\n"
        ),
        "{error}"
    );
    assert!(error.contains("note: 'value' is declared [Move] here"), "{error}");
    assert!(error.ends_with("note: hand it over with 'move(list)', or pass a new value, such as 'copy(list)'"), "{error}");
    // A call that returns one of its inputs is not new; the note points at
    // the return that shares it.
    let blamed = error_of(
        "sending_blamed",
        "import async;\n\nsame(a: Array<String>): Array<String> {\n    return a;\n}\n\nmain(): int {\n    var list = Array<String>();\n    var m = async.Mutex<Array<String>>(same(list));\n    return 0;\n}\n",
    );
    assert!(blamed.contains("main.pep:4:12: note: 'same(list)' does not return a new value: this return shares its inputs"), "{blamed}");
}

#[test]
fn channel_send_takes_a_new_value() {
    let error = error_of(
        "send_named",
        "import async;\n\nconst lines = async.Channel<String>();\n\nmain(): int {\n    var line = \"hello\";\n    lines.send(line);\n    return 0;\n}\n",
    );
    assert!(
        error.starts_with(
            "main.pep:7:16: error: 'line' is not a new value, but parameter 'value' takes a value that nothing else references\n\
             \x20   7 |     lines.send(line);\n\
             \x20     |                ^~~~\n\
             \x20     |                move(line)\n"
        ),
        "{error}"
    );
    assert!(error.ends_with("note: hand it over with 'move(line)', or pass a new value, such as 'copy(line)'"), "{error}");
}

/// Compile `source` as `main.pep`, panicking with the error if it fails.
fn compile_ok(test: &str, source: &str) {
    let dir = std::env::temp_dir().join(format!("pepper_diagnostic_{}_{}", test, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let main = dir.join("main.pep");
    std::fs::write(&main, source).unwrap();
    std::env::set_current_dir(repo_root()).unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main.to_str().unwrap()]);
    pepper_driver::compiler::compile(&options, "main").unwrap_or_else(|e| panic!("{e}"));
}

#[test]
fn a_channel_carries_values_that_cannot_be_copied() {
    // `send` no longer copies, so the value type need not be copyable.
    compile_ok(
        "channel_of_files",
        "import io;\nimport async;\n\nstruct Log {\n    io.File out;\n}\n\nmain(): int {\n    var lines = async.Channel<Array<Log>>();\n    lines.send(Array<Log>());\n    return 0;\n}\n",
    );
}

#[test]
fn thread_local_get_needs_a_thread_safe_value() {
    assert_eq!(
        error_of(
            "thread_local_get",
            "import async;\n\nconst scratch = async.ThreadLocal<String>();\n\nmain(): int {\n    var s = scratch.get();\n    return 0;\n}\n"
        ),
        "main.pep:6:21: error: 'get' is not available on 'ThreadLocal<String>', because 'String' is not thread-safe\n\
         \x20   6 |     var s = scratch.get();\n\
         \x20     |                     ^~~\n\
         note: reach this thread's value with 'with (var value = scratch.enter())'"
    );
}

#[test]
fn task_local_get_needs_a_thread_safe_value() {
    assert_eq!(
        error_of(
            "task_local_get",
            "import async;\n\nconst scratch = async.TaskLocal<String>();\n\nmain(): int {\n    var s = scratch.get();\n    return 0;\n}\n"
        ),
        "main.pep:6:21: error: 'get' is not available on 'TaskLocal<String>', because 'String' is not thread-safe\n\
         \x20   6 |     var s = scratch.get();\n\
         \x20     |                     ^~~\n\
         note: reach this task's value with 'with (var value = scratch.enter())'"
    );
}

#[test]
fn function_pointer_undeclared() {
    assert_eq!(
        error_of("function_pointer_undeclared", "main(): int {\n    var p = __function_pointer(nope);\n    return 0;\n}\n"),
        "main.pep:2:32: error: use of undeclared identifier 'nope'\n\
         \x20   2 |     var p = __function_pointer(nope);\n\
         \x20     |                                ^~~~"
    );
}

#[test]
fn result_void_has_no_value() {
    // A `void` type argument erases the parameter and the field it types.
    assert_eq!(
        error_of("result_void_ok_argument", "main(): int {\n    var r = Result<void>.ok(1);\n    return 0;\n}\n"),
        "main.pep:2:26: error: too many arguments to 'Result<void, Error>.ok': expected 0, have 1\n\
         \x20   2 |     var r = Result<void>.ok(1);\n\
         \x20     |                          ^~"
    );
    assert_eq!(
        error_of("result_void_value_field", "main(): int {\n    var r = Result<void>.ok();\n    return r._value;\n}\n"),
        "main.pep:3:14: error: no member named '_value' in 'Result<void, Error>'\n\
         \x20   3 |     return r._value;\n\
         \x20     |              ^~~~~~"
    );
}

#[test]
fn void_call_used_as_a_value() {
    assert_eq!(
        error_of("void_result_value", "main(): int {\n    var r = Result<void>.ok();\n    var x = r.value();\n    return 0;\n}\n"),
        "main.pep:3:15: error: cannot use a value of type 'void' as variable 'x'\n\
         \x20   3 |     var x = r.value();\n\
         \x20     |               ^~~~~"
    );
    assert_eq!(
        error_of("void_argument", "f() { }\ng(n: int): int { return n; }\nmain(): int {\n    return g(f());\n}\n"),
        "main.pep:4:14: error: cannot use a value of type 'void' as argument 1 of 'g'\n\
         \x20   4 |     return g(f());\n\
         \x20     |              ^"
    );
    assert_eq!(
        error_of("void_condition", "f() { }\nmain(): int {\n    if (f()) { return 1; }\n    return 0;\n}\n"),
        "main.pep:3:9: error: cannot use a value of type 'void' as a condition\n\
         \x20   3 |     if (f()) { return 1; }\n\
         \x20     |         ^"
    );
}

#[test]
fn pointer_is_not_a_string() {
    assert_eq!(
        error_of("pointer_as_string_argument", "f(s: String): int { return 0; }\nmain(): int {\n    var p = \"x\".c_str();\n    return f(p);\n}\n"),
        "main.pep:4:14: error: cannot pass a value of type '__ptr<char>' as argument 1 of 'f', which has type 'String'; use 'String(...)' to copy a C string\n\
         \x20   4 |     return f(p);\n\
         \x20     |              ^"
    );
    assert_eq!(
        error_of("pointer_as_string_variable", "main(): int {\n    var p = \"x\".c_str();\n    var s: String = p;\n    return 0;\n}\n"),
        "main.pep:3:21: error: cannot initialize variable 's' of type 'String' with a value of type '__ptr<char>'; use 'String(...)' to copy a C string\n\
         \x20   3 |     var s: String = p;\n\
         \x20     |                     ^"
    );
    assert_eq!(
        error_of("string_as_pointer_argument", "f(p: __ptr<char>): int { return 0; }\nmain(): int {\n    var s = String();\n    return f(s);\n}\n"),
        "main.pep:4:14: error: cannot pass a value of type 'String' as argument 1 of 'f', which has type '__ptr<char>'\n\
         \x20   4 |     return f(s);\n\
         \x20     |              ^"
    );
}

#[test]
fn method_of_this_stored_in_a_field() {
    assert_eq!(
        error_of(
            "method_cycle",
            "struct Widget {\n    int size;\n    () => int measure;\n    area(): int { return size; }\n    setup() { measure = this.area; }\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:5:15: error: storing a method of 'this' in field 'measure' of 'this' creates a reference cycle that is never freed\n\
         \x20   5 |     setup() { measure = this.area; }\n\
         \x20     |               ^~~~~~~\n\
         main.pep:5:30: note: the method value captures 'this' here; capture a 'Weak' reference to it in a closure instead\n\
         \x20   5 |     setup() { measure = this.area; }\n\
         \x20     |                              ^~~~"
    );
}

// ── [Deprecated] ─────────────────────────────────────────────────────────────

/// Compile `source` as `main.pep` with the runtime and return the module,
/// whose warnings hold every deprecation warning of the compile.
fn compiled(source: &str) -> pepper_driver::compiler::Compiled {
    std::env::set_current_dir(repo_root()).unwrap();
    pepper_driver::compiler::compile_with_runtime("main.pep", source).expect("compile")
}

/// The rendered warnings of compiling `source` as `main.pep`.
fn warnings_of(source: &str) -> String {
    compiled(source).render_warnings()
}

#[test]
fn deprecated_function_warns_with_a_fix_and_still_compiles() {
    let source = "[Deprecated(\"use 'twice' instead\", \"twice\")]\n\
                  dup(x: int): int { return x * 2; }\n\
                  twice(x: int): int { return x * 2; }\n\
                  test(): int {\n    return dup(21);\n}\n";
    let mut module = compiled(source);
    assert_eq!(
        module.render_warnings(),
        "main.pep:5:12: warning: 'dup' is deprecated: use 'twice' instead [deprecated]\n\
         \x20   5 |     return dup(21);\n\
         \x20     |            ^~~\n\
         \x20     |            twice\n\
         main.pep:2:1: note: 'dup' declared here\n\
         \x20   2 | dup(x: int): int { return x * 2; }\n\
         \x20     | ^~~"
    );
    let [warning] = module.warnings.as_slice() else { panic!("{:?}", module.warnings) };
    assert_eq!(warning.fixes[0].message, "Replace 'dup' with 'twice'");
    let [edit] = warning.fixes[0].edits.as_slice() else { panic!("{:?}", warning.fixes) };
    assert_eq!(edit.replacement, "twice");
    assert_eq!(&source[edit.loc.span.start..edit.loc.span.end], "dup");
    assert_eq!(edit.loc.file, pepper_driver::parser_diagnostic::FileId(0));

    let ctx = inkwell::context::Context::create();
    assert_eq!(CodeGenerator::new(&ctx, "main").jit_execute(&mut module, "test").expect("jit"), 42);
}

#[test]
fn deprecated_method_warns_at_the_method_name() {
    let source = "struct Counter {\n\
                  \x20   int value;\n\
                  \x20   [Deprecated(\"use 'copy' instead\", \"copy\")]\n\
                  \x20   clone(): Counter { return this.copy(); }\n\
                  \x20   copy(): Counter { var c = Counter(); c.value = value; return c; }\n\
                  }\n\
                  test(): int {\n    var a = Counter();\n    var b = a.clone();\n    return b.value;\n}\n";
    assert_eq!(
        warnings_of(source),
        "main.pep:9:15: warning: 'clone' is deprecated: use 'copy' instead [deprecated]\n\
         \x20   9 |     var b = a.clone();\n\
         \x20     |               ^~~~~\n\
         \x20     |               copy\n\
         main.pep:4:5: note: 'clone' declared here\n\
         \x20   4 |     clone(): Counter { return this.copy(); }\n\
         \x20     |     ^~~~~"
    );
}

#[test]
fn deprecated_generic_method_warns_at_each_use() {
    let source = "struct Holder {\n\
                  \x20   int value;\n\
                  \x20   [Deprecated(\"use 'get' instead\")]\n\
                  \x20   pick<U>(U other): int { return value; }\n\
                  }\n\
                  test(): int {\n    var h = Holder();\n    return h.pick(1) + h.pick(2.0);\n}\n";
    assert_eq!(
        warnings_of(source),
        "main.pep:8:14: warning: 'pick' is deprecated: use 'get' instead [deprecated]\n\
         \x20   8 |     return h.pick(1) + h.pick(2.0);\n\
         \x20     |              ^~~~\n\
         main.pep:4:5: note: 'pick' declared here\n\
         \x20   4 |     pick<U>(U other): int { return value; }\n\
         \x20     |     ^~~~\n\
         main.pep:8:26: warning: 'pick' is deprecated: use 'get' instead [deprecated]\n\
         \x20   8 |     return h.pick(1) + h.pick(2.0);\n\
         \x20     |                          ^~~~\n\
         main.pep:4:5: note: 'pick' declared here\n\
         \x20   4 |     pick<U>(U other): int { return value; }\n\
         \x20     |     ^~~~"
    );
}

#[test]
fn deprecated_struct_warns_at_each_use_of_its_name() {
    let source = "[Deprecated(\"use 'Point' instead\")]\n\
                  struct OldPoint { int x; }\n\
                  test(): int {\n    var p: OldPoint = OldPoint();\n    return p.x;\n}\n";
    assert_eq!(
        warnings_of(source),
        "main.pep:4:12: warning: 'OldPoint' is deprecated: use 'Point' instead [deprecated]\n\
         \x20   4 |     var p: OldPoint = OldPoint();\n\
         \x20     |            ^~~~~~~~\n\
         main.pep:2:8: note: 'OldPoint' declared here\n\
         \x20   2 | struct OldPoint { int x; }\n\
         \x20     |        ^~~~~~~~\n\
         main.pep:4:23: warning: 'OldPoint' is deprecated: use 'Point' instead [deprecated]\n\
         \x20   4 |     var p: OldPoint = OldPoint();\n\
         \x20     |                       ^~~~~~~~\n\
         main.pep:2:8: note: 'OldPoint' declared here\n\
         \x20   2 | struct OldPoint { int x; }\n\
         \x20     |        ^~~~~~~~"
    );
}

#[test]
fn deprecated_field_warns_at_every_access() {
    // Through a value, and bare inside the struct's own method.
    let source = "struct Counter {\n\
                  \x20   [Deprecated(\"read 'value' instead\", \"value\")]\n\
                  \x20   int count;\n\
                  \x20   int value;\n\
                  \x20   total(): int { return count + value; }\n\
                  }\n\
                  test(): int {\n    var c = Counter();\n    c.count = 2;\n    return c.total();\n}\n";
    let rendered = warnings_of(source);
    let headers: Vec<&str> = rendered.lines().filter(|l| l.contains(": warning: ")).collect();
    assert_eq!(
        headers,
        [
            "main.pep:5:27: warning: 'count' is deprecated: read 'value' instead [deprecated]",
            "main.pep:9:7: warning: 'count' is deprecated: read 'value' instead [deprecated]",
        ]
    );
    assert!(rendered.contains("    9 |     c.count = 2;\n      |       ^~~~~\n      |       value\n"), "{rendered}");
    assert!(rendered.contains("main.pep:3:9: note: 'count' declared here"), "{rendered}");
}

#[test]
fn deprecated_variable_and_constructor() {
    // An empty message leaves just "is deprecated"; a deprecated
    // constructor is reported at the struct name that constructs.
    let source = "[Deprecated(\"\")]\n\
                  const limit = 3;\n\
                  struct Box {\n\
                  \x20   int value;\n\
                  \x20   [Deprecated(\"use 'make_box' instead\")]\n\
                  \x20   construct(int v) { value = v; }\n\
                  }\n\
                  test(): int {\n    var b = Box(limit);\n    return b.value;\n}\n";
    assert_eq!(
        warnings_of(source),
        "main.pep:9:13: warning: 'Box' is deprecated: use 'make_box' instead [deprecated]\n\
         \x20   9 |     var b = Box(limit);\n\
         \x20     |             ^~~\n\
         main.pep:6:5: note: 'Box' declared here\n\
         \x20   6 |     construct(int v) { value = v; }\n\
         \x20     |     ^~~~~~~~~\n\
         main.pep:9:17: warning: 'limit' is deprecated [deprecated]\n\
         \x20   9 |     var b = Box(limit);\n\
         \x20     |                 ^~~~~\n\
         main.pep:2:7: note: 'limit' declared here\n\
         \x20   2 | const limit = 3;\n\
         \x20     |       ^~~~~"
    );
}

#[test]
fn no_deprecation_warning_inside_deprecated_declarations() {
    // Nor in a closure written inside one, nor at the declarations
    // themselves, nor anywhere in the runtime.
    let source = "[Deprecated(\"old\")]\n\
                  const limit = 3;\n\
                  [Deprecated(\"old\")]\n\
                  helper(): int { return limit; }\n\
                  [Deprecated(\"old\")]\n\
                  struct Legacy {\n\
                  \x20   [Deprecated(\"old\")]\n\
                  \x20   int count;\n\
                  \x20   get(): int { return count + helper(); }\n\
                  }\n\
                  struct Current {\n\
                  \x20   [Deprecated(\"old\")]\n\
                  \x20   old(): int { var l = Legacy(); return l.get() + helper(); }\n\
                  }\n\
                  [Deprecated(\"old\")]\n\
                  legacy(): int { var c = Current(); var f = () => c.old(); return f() + helper(); }\n\
                  test(): int { return 0; }\n";
    assert_eq!(warnings_of(source), "");
}

#[test]
fn deprecated_function_used_through_imports() {
    // Through a qualifier, the warning points at the name after it, and the
    // fix renames only that; an import list names the declaration too.
    std::env::set_current_dir(repo_root()).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_diagnostic_deprecated_imports_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("lib.pep"),
        "[Deprecated(\"use 'fresh' instead\", \"fresh\")]\nexport stale(): int { return 1; }\nexport fresh(): int { return 1; }\n",
    )
    .unwrap();
    let main_path = dir.join("main.pep");
    std::fs::write(&main_path, "import \"lib\" as l;\nimport [stale] from \"lib\";\nmain(): int {\n    return l.stale() + stale();\n}\n")
        .unwrap();
    let options = pepper_driver::Options::parse_from(["pepper", main_path.to_str().unwrap()]);
    let module = pepper_driver::compiler::compile(&options, "main").expect("compile");
    let rendered = module.render_warnings().replace(&format!("{}{}", dir.display(), std::path::MAIN_SEPARATOR), "");
    let headers: Vec<&str> = rendered.lines().filter(|l| l.contains(": warning: ") || l.contains(": note: ")).collect();
    assert_eq!(
        headers,
        [
            "main.pep:2:9: warning: 'stale' is deprecated: use 'fresh' instead [deprecated]",
            "lib.pep:2:8: note: 'stale' declared here",
            "main.pep:4:14: warning: 'stale' is deprecated: use 'fresh' instead [deprecated]",
            "lib.pep:2:8: note: 'stale' declared here",
            "main.pep:4:24: warning: 'stale' is deprecated: use 'fresh' instead [deprecated]",
            "lib.pep:2:8: note: 'stale' declared here",
        ]
    );
    assert!(rendered.contains("    4 |     return l.stale() + stale();\n      |              ^~~~~\n      |              fresh\n"), "{rendered}");
}

#[test]
fn malformed_deprecated_attributes() {
    let message = "'Deprecated' expects a message string: [Deprecated(\"message\")]";
    let cases = [
        ("bare", "[Deprecated]\nf() {}\n", format!("main.pep:1:1: error: {message}")),
        ("no_arguments", "[Deprecated()]\nf() {}\n", format!("main.pep:1:1: error: {message}")),
        ("not_a_string", "[Deprecated(3)]\nf() {}\n", format!("main.pep:1:13: error: {message}")),
        (
            "replacement_not_a_string",
            "[Deprecated(\"old\", 3)]\nf() {}\n",
            "main.pep:1:20: error: 'Deprecated' expects the replacement as a string: [Deprecated(\"message\", \"replacement\")]".to_string(),
        ),
        ("replacement_not_a_name", "[Deprecated(\"old\", \"a b\")]\nf() {}\n", "main.pep:1:20: error: the replacement 'a b' is not a name".to_string()),
        (
            "too_many",
            "[Deprecated(\"old\", \"g\", \"h\")]\nf() {}\n",
            "main.pep:1:25: error: too many arguments to 'Deprecated': expected at most 2, have 3".to_string(),
        ),
        ("duplicate", "[Deprecated(\"a\")]\n[Deprecated(\"b\")]\nf() {}\n", "main.pep:2:1: error: duplicate 'Deprecated' attribute".to_string()),
        (
            "extension",
            "struct S { int x; }\n[Deprecated(\"old\")]\nextend S { m() {} }\n",
            "main.pep:2:1: error: 'Deprecated' cannot be applied to an extension; deprecate its methods instead".to_string(),
        ),
        (
            "destructor",
            "struct S {\n    int x;\n    [Deprecated(\"old\")]\n    destruct {}\n}\n",
            "main.pep:3:5: error: 'Deprecated' cannot be applied to a destructor".to_string(),
        ),
    ];
    for (name, prefix, expected) in cases {
        let source = format!("{prefix}main(): int {{ return 0; }}\n");
        let error = error_of(&format!("deprecated_{name}"), &source);
        assert_eq!(error.lines().next(), Some(expected.as_str()), "{name}: {error}");
    }
    // The whole rendering, for one: the caret covers the attribute.
    assert_eq!(
        error_of("deprecated_rendered", "[Deprecated]\nf() {}\nmain(): int { return 0; }\n"),
        format!("main.pep:1:1: error: {message}\n\
                 \x20   1 | [Deprecated]\n\
                 \x20     | ^~~~~~~~~~~~")
    );
}

#[test]
fn deprecated_extension_method_of_a_generic_struct() {
    // Each use once, however many specializations share its location.
    let source = "struct Box<T> { T value; }\n\
                  extend Box<T> {\n\
                  \x20   [Deprecated(\"use 'get' instead\", \"get\")]\n\
                  \x20   peek(): T { return value; }\n\
                  \x20   get(): T { return value; }\n\
                  }\n\
                  twice<T>(b: Box<T>): T { return b.peek(); }\n\
                  test(): int {\n    var a = Box<int>();\n    var s = Box<long>();\n    return a.peek() + twice(a) + (twice(s) as int);\n}\n";
    let rendered = warnings_of(source);
    let headers: Vec<&str> = rendered.lines().filter(|l| l.contains(": warning: ")).collect();
    assert_eq!(
        headers,
        [
            "main.pep:7:35: warning: 'peek' is deprecated: use 'get' instead [deprecated]",
            "main.pep:11:14: warning: 'peek' is deprecated: use 'get' instead [deprecated]",
        ]
    );
}

#[test]
fn void_pointer_is_not_a_struct() {
    // A struct may pass as `void*`, but no pointer is a struct reference.
    let variable = error_of("void_ptr_as_struct", "struct S { int x = 0; }\nmain(): int {\n    var p: __ptr<void> = __null;\n    S s = p;\n    return 0;\n}\n");
    assert!(variable.starts_with("main.pep:4:11: error: cannot initialize variable 's' of type 'S' with a value of type '__ptr<void>'\n"), "{variable}");
}

#[test]
fn type_arguments_not_inferred() {
    assert_eq!(
        error_of("type_arguments_not_inferred", "make<T>(): T { return __default<T>(); }\nmain(): int {\n    var x = make();\n    return 0;\n}\n"),
        "main.pep:3:13: error: cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)\n\
         \x20   3 |     var x = make();\n\
         \x20     |             ^~~~\n\
         main.pep:1:1: note: declared here\n\
         \x20   1 | make<T>(): T { return __default<T>(); }\n\
         \x20     | ^~~~"
    );
}

#[test]
fn written_type_arguments_too_few() {
    // #331: the arguments give no 'U', so the call is reported, not the
    // half-specialized function.
    assert_eq!(
        error_of("written_type_arguments_too_few", "make<T, U>(a: T): int { return 0; }\nmain(): int {\n    return make<int>(1);\n}\n"),
        "main.pep:3:12: error: cannot infer the type argument 'U' of 'make' from its arguments; write it: make<T, U>(...)\n\
         \x20   3 |     return make<int>(1);\n\
         \x20     |            ^~~~~~~~~\n\
         main.pep:1:1: note: declared here\n\
         \x20   1 | make<T, U>(a: T): int { return 0; }\n\
         \x20     | ^~~~"
    );
}

#[test]
fn method_type_arguments_not_inferred() {
    // A generic method's call is reported in sema, not as a missing member
    // in codegen: with no type arguments, and with too few.
    assert_eq!(
        error_of("method_type_arguments_not_inferred", "struct S {\n    make<T>(): int { return 0; }\n}\nmain(): int {\n    var s = S();\n    return s.make();\n}\n"),
        "main.pep:6:14: error: cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)\n\
         \x20   6 |     return s.make();\n\
         \x20     |              ^~~~\n\
         main.pep:2:5: note: declared here\n\
         \x20   2 |     make<T>(): int { return 0; }\n\
         \x20     |     ^~~~"
    );
    assert_eq!(
        error_of("method_type_arguments_too_few", "struct S {\n    make<T, U>(a: T): int { return 0; }\n}\nmain(): int {\n    var s = S();\n    return s.make<int>(1);\n}\n"),
        "main.pep:6:14: error: cannot infer the type argument 'U' of 'make' from its arguments; write it: make<T, U>(...)\n\
         \x20   6 |     return s.make<int>(1);\n\
         \x20     |              ^~~~\n\
         main.pep:2:5: note: declared here\n\
         \x20   2 |     make<T, U>(a: T): int { return 0; }\n\
         \x20     |     ^~~~"
    );
}

#[test]
fn shared_closure_captures_not_thread_safe() {
    // At the capture's first use in the closure, with a note at the
    // captured variable.
    assert_eq!(
        error_of(
            "shared_closure_capture",
            "import async;\n\nmain(): int {\n    var name = \"worker\";\n    var t = async.Thread.spawn(() => { print(name); });\n    t.join();\n    return 0;\n}\n"
        ),
        "main.pep:5:46: error: closure passed as 'shared () => void' captures 'name' of type 'String', which is not thread-safe\n\
         \x20   5 |     var t = async.Thread.spawn(() => { print(name); });\n\
         \x20     |                                              ^~~~\n\
         main.pep:4:9: note: capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct\n\
         \x20   4 |     var name = \"worker\";\n\
         \x20     |         ^~~~"
    );
    assert_eq!(
        error_of(
            "shared_closure_returned",
            "make(): shared () => int {\n    var s = \"x\";\n    return () => s.length as int;\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:3:18: error: closure returned as 'shared () => int' captures 's' of type 'String', which is not thread-safe\n\
         \x20   3 |     return () => s.length as int;\n\
         \x20     |                  ^\n\
         main.pep:2:9: note: capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct\n\
         \x20   2 |     var s = \"x\";\n\
         \x20     |         ^"
    );
}

#[test]
fn shared_closure_captures_this() {
    assert_eq!(
        error_of(
            "shared_closure_this",
            "struct S {\n    var n: int;\n    construct(this.n = 0) {}\n    run() {\n        var f: shared () => int = () => n;\n    }\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:5:41: error: closure stored as 'shared () => int' captures 'this' of type 'S', which is not thread-safe\n\
         \x20   5 |         var f: shared () => int = () => n;\n\
         \x20     |                                         ^\n\
         note: capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct"
    );
}

#[test]
fn shared_method_value_captures_receiver() {
    assert_eq!(
        error_of(
            "shared_method_value",
            "struct P {\n    var x: int;\n    construct(this.x = 0) {}\n    get(): int { return x; }\n}\ntake(f: shared () => int): int { return f(); }\nmain(): int {\n    var p = P(3);\n    return take(p.get);\n}\n"
        ),
        "main.pep:9:19: error: method value passed as 'shared () => int' captures its receiver of type 'P', which is not thread-safe\n\
         \x20   9 |     return take(p.get);\n\
         \x20     |                   ^~~\n\
         note: capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct"
    );
}

#[test]
fn plain_function_value_is_not_shared() {
    assert_eq!(
        error_of(
            "plain_to_shared_variable",
            "main(): int {\n    var g = () => {};\n    var f: shared () => void = g;\n    return 0;\n}\n"
        ),
        "main.pep:3:32: error: cannot initialize variable 'f' of type 'shared () => void' with a value of type '() => void'\n\
         \x20   3 |     var f: shared () => void = g;\n\
         \x20     |                                ^"
    );
    assert_eq!(
        error_of(
            "plain_to_shared_argument",
            "take(f: shared () => int): int { return f(); }\nmain(): int {\n    var h: () => int = () => 1;\n    return take(h);\n}\n"
        ),
        "main.pep:4:17: error: cannot pass a value of type '() => int' as argument 1 of 'take', which has type 'shared () => int'\n\
         \x20   4 |     return take(h);\n\
         \x20     |                 ^"
    );
}

#[test]
fn plain_function_type_in_shared_places() {
    assert_eq!(
        error_of(
            "plain_function_shared_field",
            "[Shared]\nstruct H {\n    const f: () => void;\n    construct(this.f = () => {}) {}\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:3:14: error: field 'f' of shared struct 'H' has type '() => void', which is not thread-safe\n\
         \x20   3 |     const f: () => void;\n\
         \x20     |              ^~~~~~~~~~\n\
         note: declare the function type 'shared () => void' to share it between threads"
    );
    assert_eq!(
        error_of("plain_function_global", "const f: () => int = () => 1;\nmain(): int { return 0; }\n"),
        "main.pep:1:10: error: module-scope variable 'f' has type '() => int', which is not thread-safe\n\
         \x20   1 | const f: () => int = () => 1;\n\
         \x20     |          ^~~~~~~~~\n\
         note: declare the function type 'shared () => int' to share it between threads"
    );
}

#[test]
fn implicit_on_a_constructor_that_takes_two_arguments() {
    assert_eq!(
        error_of(
            "implicit_two_arguments",
            "struct Span {\n    [Implicit]\n    construct(int start, int end) { }\n}\nmain(): int { return 0; }\n"
        ),
        "main.pep:2:5: error: 'Implicit' constructor of 'Span' must be callable with one argument\n\
         \x20   2 |     [Implicit]\n\
         \x20     |     ^~~~~~~~~~"
    );
    assert_eq!(
        error_of("implicit_on_function", "[Implicit]\nf(): int { return 1; }\nmain(): int { return 0; }\n"),
        "main.pep:1:1: error: 'Implicit' applies only to constructors\n\
         \x20   1 | [Implicit]\n\
         \x20     | ^~~~~~~~~~"
    );
}

#[test]
fn plain_constructor_suggested_for_a_mismatch() {
    assert_eq!(
        error_of(
            "plain_constructor_hint",
            "struct Label {\n    String text;\n    construct(String text) { this.text = text; }\n}\nshow(l: Label): int { return 0; }\nmain(): int { return show(\"x\"); }\n"
        ),
        "main.pep:6:27: error: cannot pass a value of type 'String' as argument 1 of 'show', which has type 'Label'\n\
         \x20   6 | main(): int { return show(\"x\"); }\n\
         \x20     |                           ^~~\n\
         main.pep:3:5: note: 'Label' has a constructor from 'String': call 'Label(...)', or mark the constructor [Implicit]\n\
         \x20   3 |     construct(String text) { this.text = text; }\n\
         \x20     |     ^~~~~~~~~"
    );
}

#[test]
fn private_name_is_shown_as_written() {
    // The root's private `Error` shares a name with the runtime's export, so
    // linking mangles it; the message spells it as written.
    let source = "struct Error { var x: int; }\nmain(): int {\n    var e = Error();\n    return e.y;\n}\n";
    assert_eq!(
        error_of("private_name_shown_as_written", source),
        "main.pep:4:14: error: no member named 'y' in 'Error'\n\
         \x20   4 |     return e.y;\n\
         \x20     |              ^"
    );
}

#[test]
fn extension_method_from_a_file_not_imported() {
    let files = [
        ("types.pep", "export struct S { var x: int; }\n"),
        ("ext.pep", "import \"types\";\nexport extend S { double(): int { return x * 2; } }\n"),
        ("other.pep", "import \"ext\";\nexport other(): int { return 0; }\n"),
    ];
    let main = "import \"types\";\nimport \"other\";\nmain(): int {\n    var s = S();\n    return s.double() + other();\n}\n";
    assert_eq!(
        error_of_files("extension_not_imported", main, &files),
        "main.pep:5:14: error: 'double' is declared in an extension in ext.pep, which this file does not import; add an import for it\n\
         \x20   5 |     return s.double() + other();\n\
         \x20     |              ^~~~~~\n\
         ext.pep:2:19: note: declared here\n\
         \x20   2 | export extend S { double(): int { return x * 2; } }\n\
         \x20     |                   ^~~~~~"
    );
}


#[test]
fn override_type_argument_names_a_type_alias() {
    let files = [("lib.pep", "export describe<T>(v: T): int { return 1; }\n")];
    let main = "import \"lib\";\nstruct Point { var x: int; }\ntype P = Point;\ndescribe<P>(p: P): int { return 2; }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of_files("override_alias_argument", main, &files),
        "main.pep:4:10: error: 'P' is not a struct; an override's type argument must name a struct\n\
         \x20   4 | describe<P>(p: P): int { return 2; }\n\
         \x20     |          ^"
    );
}

#[test]
fn duplicate_override_notes_the_other_declaration() {
    let files = [
        ("a.pep", "export struct Point { var x: int; }\nexport describe<T>(v: T): int { return 0; }\ndescribe<Point>(p: Point): int { return 1; }\n"),
        ("b.pep", "import \"a\";\ndescribe<Point>(p: Point): int { return 2; }\n"),
    ];
    let main = "import \"a\";\nimport \"b\";\nmain(): int { return 0; }\n";
    let err = error_of_files("duplicate_override_note", main, &files);
    assert!(err.starts_with("b.pep:2:1: error: override 'describe<Point>' is also declared in a.pep"), "{}", err);
    assert!(err.contains("a.pep:3:1: note: also declared here\n    3 | describe<Point>"), "{}", err);
}

#[test]
fn no_matching_overload_notes_each_candidate() {
    let main = "f(x: int): int { return 1; }\nf(x: int, y: int): int { return 2; }\nmain(): int {\n    var s = String();\n    return f(s);\n}\n";
    assert_eq!(
        error_of("no_matching_overload", main),
        "main.pep:5:12: error: no matching function for call to 'f'\n\
         \x20   5 |     return f(s);\n\
         \x20     |            ^\n\
         main.pep:1:1: note: candidate function not viable: no known conversion from 'String' to 'int' for 1st argument\n\
         \x20   1 | f(x: int): int { return 1; }\n\
         \x20     | ^\n\
         main.pep:2:1: note: candidate function not viable: requires 2 arguments, but 1 was provided\n\
         \x20   2 | f(x: int, y: int): int { return 2; }\n\
         \x20     | ^"
    );
}

#[test]
fn no_matching_constructor_notes_each_candidate() {
    let main = "struct P {\n    int x;\n    construct(v: int) { x = v; }\n    construct(a: int, b: int) { x = a + b; }\n}\nmain(): int {\n    return P(String()).x;\n}\n";
    assert_eq!(
        error_of("no_matching_constructor", main),
        "main.pep:7:12: error: no matching constructor for initialization of 'P'\n\
         \x20   7 |     return P(String()).x;\n\
         \x20     |            ^\n\
         main.pep:3:5: note: candidate constructor not viable: no known conversion from 'String' to 'int' for 1st argument\n\
         \x20   3 |     construct(v: int) { x = v; }\n\
         \x20     |     ^~~~~~~~~\n\
         main.pep:4:5: note: candidate constructor not viable: requires 2 arguments, but 1 was provided\n\
         \x20   4 |     construct(a: int, b: int) { x = a + b; }\n\
         \x20     |     ^~~~~~~~~"
    );
}

#[test]
fn c_function_pointer_from_a_capturing_closure() {
    assert_eq!(
        error_of(
            "c_function_pointer_capture",
            "extern void qsort(void* base, ulong count, ulong size, extern (void*, void*) => int compare);\nmain(): int {\n    var bias = 1;\n    qsort(_pep_malloc(4), 0, 4, (a, b) => bias);\n    return 0;\n}\n"
        ),
        "main.pep:4:43: error: closure passed as C function pointer type 'extern (void*, void*) => int' captures 'bias'; a C function pointer cannot hold captured values\n\
         \x20   4 |     qsort(_pep_malloc(4), 0, 4, (a, b) => bias);\n\
         \x20     |                                           ^~~~\n\
         main.pep:3:9: note: pass what the callback needs through the C function's context argument instead\n\
         \x20   3 |     var bias = 1;\n\
         \x20     |         ^~~~"
    );
}

#[test]
fn ambiguous_overload_call() {
    let main = "f(x: long): int { return 1; }\nf(x: short): int { return 2; }\nmain(): int { return f(1); }\n";
    assert_eq!(
        error_of("ambiguous_overload", main),
        "main.pep:3:22: error: call to 'f' is ambiguous\n\
         \x20   3 | main(): int { return f(1); }\n\
         \x20     |                      ^\n\
         main.pep:1:1: note: candidate function\n\
         \x20   1 | f(x: long): int { return 1; }\n\
         \x20     | ^\n\
         main.pep:2:1: note: candidate function\n\
         \x20   2 | f(x: short): int { return 2; }\n\
         \x20     | ^"
    );
}

#[test]
fn prelude_files_exporting_one_type() {
    // Two forced imports (prelude files) may export overloads of one
    // function, but not two types of one name: the merged program would keep
    // only one of them. The error is in the file loaded first.
    let others = [
        ("first/module.pep", "export struct Point { var x: int; }\nexport size(p: Point): int { return 1; }\n"),
        ("second/module.pep", "export f(): int { return 0; }\n\nexport struct Point { var y: int; }\n"),
    ];
    let error = error_of_files_with("prelude_type_twice", "main(): int { return 0; }\n", &others, &["--import", "first", "--import", "second"]);
    let first = format!("first{}module.pep", std::path::MAIN_SEPARATOR);
    let second = format!("second{}module.pep", std::path::MAIN_SEPARATOR);
    assert_eq!(
        error,
        format!(
            "{first}:1:15: error: redefinition of 'Point'\n\
             \x20   1 | export struct Point {{ var x: int; }}\n\
             \x20     |               ^~~~~\n\
             {second}:3:15: note: also exported here\n\
             \x20   3 | export struct Point {{ var y: int; }}\n\
             \x20     |               ^~~~~"
        )
    );

    // Against the runtime, which loads after forced imports, the error is
    // in the forced import: `Iterator.map`'s adapter is `MapIterator`.
    let others = [("alt/module.pep", "export struct MapIterator<K, V> { var key: K; var value: V; }\n")];
    let error = error_of_files_with("prelude_type_runtime", "main(): int { return 0; }\n", &others, &["--import", "alt"]);
    let alt = format!("alt{}module.pep:1:15: error: redefinition of 'MapIterator'\n", std::path::MAIN_SEPARATOR);
    assert!(error.starts_with(&alt), "{}", error);
    assert!(error.contains("iterator.pep:"), "{}", error);
    assert!(error.contains(": note: also exported here\n"), "{}", error);

    // One file declaring a type twice.
    let error = error_of("type_twice", "struct A { var x: int; }\nenum A { a, b }\nmain(): int { return 0; }\n");
    assert!(error.starts_with("main.pep:2:6: error: redefinition of 'A'\n"), "{}", error);
    assert!(error.contains("main.pep:1:8: note: previous definition is here\n"), "{}", error);
}

#[test]
fn overloads_that_cannot_coexist() {
    let redefinition = error_of("overload_redefinition", "f(x: int): int { return 1; }\nf(y: int): int { return 2; }\nmain(): int { return 0; }\n");
    assert!(redefinition.starts_with("main.pep:2:1: error: redefinition of 'f'\n"), "{}", redefinition);
    assert!(redefinition.contains("main.pep:1:1: note: previous definition is here\n"), "{}", redefinition);

    let return_only = error_of("overload_return_only", "f(x: int): int { return 1; }\nf(x: int): long { return 2; }\nmain(): int { return 0; }\n");
    assert!(
        return_only.starts_with("main.pep:2:1: error: functions that differ only in their return type cannot be overloaded\n"),
        "{}",
        return_only
    );

    let external = error_of("overload_extern", "extern int abs(int x);\nabs(x: double): double { return x; }\nmain(): int { return 0; }\n");
    assert_eq!(
        external,
        "main.pep:2:1: error: extern 'abs' cannot be overloaded; rename it and overload Pepper functions named 'abs' that call it\n\
         \x20   2 | abs(x: double): double { return x; }\n\
         \x20     | ^~~\n\
         main.pep:1:12: note: previous declaration is here\n\
         \x20   1 | extern int abs(int x);\n\
         \x20     |            ^~~"
    );
}

#[test]
fn overloaded_function_value_needs_a_type() {
    let main = "f(x: int): int { return 1; }\nf(x: long): int { return 2; }\nmain(): int {\n    var g = f;\n    return 0;\n}\n";
    let err = error_of("overload_value_untyped", main);
    assert!(err.starts_with("main.pep:4:13: error: cannot infer the type of 'g' from overloaded function 'f'\n    4 |     var g = f;\n      |             ^\n"), "{}", err);
    assert!(err.ends_with("main.pep:4:13: note: declare the type, for example 'var g: (int) => int = f;'\n    4 |     var g = f;\n      |             ^"), "{}", err);

    let main = "f(x: int): int { return 1; }\nf(x: long): int { return 2; }\nmain(): int {\n    var g: (bool) => int = f;\n    return 0;\n}\n";
    let err = error_of("overload_value_mismatch", main);
    assert!(
        err.starts_with("main.pep:4:28: error: address of overloaded function 'f' does not match required type '(bool) => int'\n"),
        "{}",
        err
    );
}

#[test]
fn another_file_sees_only_a_set_s_exported_members() {
    let files = [("util.pep", "export scale(x: int): int { return x * 2; }\nscale(x: double): double { return x * 3.0; }\n")];
    assert_eq!(
        error_of_files(
            "overload_mixed_visibility",
            "import \"util\";\nmain(): int {\n    var f: (double) => double = scale;\n    return 0;\n}\n",
            &files
        ),
        "main.pep:3:33: error: address of overloaded function 'scale' does not match required type '(double) => double'\n\
         \x20   3 |     var f: (double) => double = scale;\n\
         \x20     |                                 ^~~~~\n\
         util.pep:1:8: note: candidate function\n\
         \x20   1 | export scale(x: int): int { return x * 2; }\n\
         \x20     |        ^~~~~"
    );
}

#[test]
fn c_function_pointer_mismatches() {
    assert_eq!(
        error_of(
            "c_function_pointer_from_value",
            "main(): int {\n    var g: (int) => int = (x) => x;\n    var f: extern (int) => int = g;\n    return 0;\n}\n"
        ),
        "main.pep:3:34: error: cannot initialize variable 'f' of type 'extern (int) => int' with a value of type '(int) => int'; only a named function or a closure that captures nothing converts to a C function pointer\n\
         \x20   3 |     var f: extern (int) => int = g;\n\
         \x20     |                                  ^"
    );
    assert_eq!(
        error_of(
            "c_function_pointer_signature",
            "take(s: long): int { return 0; }\nmain(): int {\n    var f: extern (int) => int = take;\n    return 0;\n}\n"
        ),
        "main.pep:3:34: error: cannot initialize variable 'f' of type 'extern (int) => int' with a value of type '(long) => int'; the parameter and return types must match exactly\n\
         \x20   3 |     var f: extern (int) => int = take;\n\
         \x20     |                                  ^~~~"
    );
    assert_eq!(
        error_of(
            "c_function_pointer_to_function_value",
            "twice(x: int): int { return x * 2; }\nmain(): int {\n    var f: extern (int) => int = twice;\n    var g: (int) => int = f;\n    return g(1);\n}\n"
        ),
        "main.pep:4:27: error: cannot initialize variable 'g' of type '(int) => int' with a value of type 'extern (int) => int'; wrap it in a closure that calls it\n\
         \x20   4 |     var g: (int) => int = f;\n\
         \x20     |                           ^"
    );
}

#[test]
fn c_function_pointer_type_with_a_struct() {
    assert_eq!(
        error_of(
            "c_function_pointer_struct",
            "take(s: String): int { return 0; }\nmain(): int {\n    var f: extern (String) => int = take;\n    return 0;\n}\n"
        ),
        "main.pep:3:12: error: C function pointer type 'extern (String) => int' cannot use 'String'; C passes only numbers, 'bool' and pointers\n\
         \x20   3 |     var f: extern (String) => int = take;\n\
         \x20     |            ^~~~~~~~~~~~~~~~~~~~~~"
    );
}

const PAIR: &str = "pair(): (int, int) {\n    return (1, 2);\n}\n";

#[test]
fn destructure_wrong_count() {
    assert_eq!(
        error_of(
            "destructure_wrong_count",
            &format!("{PAIR}main(): int {{\n    var (a, b, c) = pair();\n    return 0;\n}}\n")
        ),
        "main.pep:5:21: error: cannot destructure '(int, int)' into 3 values: it has 2 elements\n\
         \x20   5 |     var (a, b, c) = pair();\n\
         \x20     |                     ^~~~~~"
    );
}

#[test]
fn destructure_non_tuple() {
    assert_eq!(
        error_of("destructure_non_tuple", "main(): int {\n    var s = \"x\";\n    var (a, b) = s;\n    return 0;\n}\n"),
        "main.pep:3:18: error: cannot destructure 'String': it is not a tuple\n\
         \x20   3 |     var (a, b) = s;\n\
         \x20     |                  ^"
    );
}

#[test]
fn tuple_element_is_immutable() {
    assert_eq!(
        error_of(
            "tuple_element_is_immutable",
            &format!("{PAIR}main(): int {{\n    var t = pair();\n    t.0 = 3;\n    return 0;\n}}\n")
        ),
        "main.pep:6:7: error: cannot assign to element 0 of tuple '(int, int)': tuple elements are immutable\n\
         \x20   6 |     t.0 = 3;\n\
         \x20     |       ^"
    );
}

#[test]
fn tuple_element_out_of_range() {
    assert_eq!(
        error_of(
            "tuple_element_out_of_range",
            &format!("{PAIR}main(): int {{\n    var t = pair();\n    return t.2;\n}}\n")
        ),
        "main.pep:6:14: error: no member named '2' in '(int, int)': its elements are '0' to '1'\n\
         \x20   6 |     return t.2;\n\
         \x20     |              ^"
    );
}

#[test]
fn tuple_element_type_mismatch() {
    assert_eq!(
        error_of("tuple_element_type_mismatch", "main(): int {\n    var t: (int, String) = (1, 2);\n    return 0;\n}\n"),
        "main.pep:2:28: error: cannot pass a value of type 'i32' as element 1 of '(int, String)', which has type 'String'\n\
         \x20   2 |     var t: (int, String) = (1, 2);\n\
         \x20     |                            ^~~~~~"
    );
}

#[test]
fn struct_without_truth_test_as_condition() {
    assert_eq!(
        error_of(
            "struct_condition",
            "struct Node {\n    int value;\n}\nmain(): int {\n    var node = Node();\n    if (node) {\n        return 1;\n    }\n    return 0;\n}\n"
        ),
        "main.pep:6:9: error: 'Node' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'\n\
         \x20   6 |     if (node) {\n\
         \x20     |         ^~~~\n\
         main.pep:1:8: note: 'Node' declared here\n\
         \x20   1 | struct Node {\n\
         \x20     |        ^~~~"
    );
    assert_eq!(
        error_of(
            "struct_operand_of_not",
            "struct Node {\n    int value;\n}\nmain(): int {\n    var node = Node();\n    return node.value > 0 && !node ? 1 : 0;\n}\n"
        ),
        "main.pep:6:31: error: 'Node' cannot be used as a condition: declare '!!(): bool' on it, or compare with '__null'\n\
         \x20   6 |     return node.value > 0 && !node ? 1 : 0;\n\
         \x20     |                               ^~~~\n\
         main.pep:1:8: note: 'Node' declared here\n\
         \x20   1 | struct Node {\n\
         \x20     |        ^~~~"
    );
}

#[test]
fn match_missing_cases() {
    assert_eq!(
        error_of(
            "match_missing_cases",
            "enum Color {\n    Red,\n    Green,\n    Blue,\n}\n\nmain(): int {\n    var c = Color.Red;\n    match (c) {\n        Red => { return 1; }\n    }\n    return 0;\n}\n"
        ),
        "main.pep:9:5: error: match on 'Color' does not handle 'Green' and 'Blue'\n\
         \x20   9 |     match (c) {\n\
         \x20     |     ^~~~~\n\
         note: handle each case, or add an 'else' arm\n\
         main.pep:3:5: note: 'Green' declared here\n\
         \x20   3 |     Green,\n\
         \x20     |     ^~~~~\n\
         main.pep:4:5: note: 'Blue' declared here\n\
         \x20   4 |     Blue,\n\
         \x20     |     ^~~~"
    );
}

#[test]
fn unary_operator_signatures() {
    assert_eq!(
        error_of("truth_test_return", "struct S {\n    !!(): int { return 1; }\n}\nmain(): int { return 0; }\n"),
        "main.pep:2:11: error: truth-test operator '!!' must return 'bool', not 'int'\n\
         \x20   2 |     !!(): int { return 1; }\n\
         \x20     |           ^~~"
    );
    assert_eq!(
        error_of("not_parameters", "struct S {\n    !(o: S): bool { return true; }\n}\nmain(): int { return 0; }\n"),
        "main.pep:2:5: error: unary operator '!' takes no parameters, have 1\n\
         \x20   2 |     !(o: S): bool { return true; }\n\
         \x20     |     ^"
    );
}

#[test]
fn enum_no_such_case() {
    assert_eq!(
        error_of("enum_no_such_case", "enum Color { Red, Green }\nmain(): int {\n    var c = Color.Pink;\n    return 0;\n}\n"),
        "main.pep:3:19: error: no case named 'Pink' in 'Color'\n\
         \x20   3 |     var c = Color.Pink;\n\
         \x20     |                   ^~~~\n\
         main.pep:1:6: note: 'Color' declared here\n\
         \x20   1 | enum Color { Red, Green }\n\
         \x20     |      ^~~~~"
    );
}

#[test]
fn match_case_handled_twice() {
    assert_eq!(
        error_of(
            "match_case_handled_twice",
            "enum Color { Red, Green }\nmain(): int {\n    match (Color.Red) {\n        Red => {}\n        Green, Red => {}\n    }\n    return 0;\n}\n"
        ),
        "main.pep:5:16: error: case 'Red' is already handled\n\
         \x20   5 |         Green, Red => {}\n\
         \x20     |                ^~~\n\
         main.pep:4:9: note: first handled here\n\
         \x20   4 |         Red => {}\n\
         \x20     |         ^~~"
    );
}

#[test]
fn enum_value_out_of_range() {
    assert_eq!(
        error_of("enum_value_out_of_range", "enum Kind: u8 {\n    Small,\n    Big = 256,\n}\nmain(): int { return 0; }\n"),
        "main.pep:3:11: error: value 256 of case 'Big' does not fit in 'u8'\n\
         \x20   3 |     Big = 256,\n\
         \x20     |           ^~~"
    );
}

#[test]
fn enum_duplicate_value() {
    assert_eq!(
        error_of("enum_duplicate_value", "enum Kind {\n    A = 1,\n    B = 1,\n}\nmain(): int { return 0; }\n"),
        "main.pep:3:5: error: case 'B' has the same value as 'A' (1)\n\
         \x20   3 |     B = 1,\n\
         \x20     |     ^\n\
         main.pep:2:5: note: 'A' declared here\n\
         \x20   2 |     A = 1,\n\
         \x20     |     ^"
    );
}

#[test]
fn enum_to_integer_needs_as() {
    assert_eq!(
        error_of("enum_to_integer_needs_as", "enum Color { Red }\nmain(): int {\n    int x = Color.Red;\n    return x;\n}\n"),
        "main.pep:3:19: error: cannot initialize variable 'x' of type 'int' with a value of type 'Color'\n\
         \x20   3 |     int x = Color.Red;\n\
         \x20     |                   ^~~"
    );
}

#[test]
fn match_on_a_non_enum() {
    assert_eq!(
        error_of("match_on_a_non_enum", "main(): int {\n    match (1.5) {\n    }\n    return 0;\n}\n"),
        "main.pep:2:12: error: cannot match on a value of 'f64': 'match' needs an enum, an integer, 'char', 'bool' or 'String'\n\
         \x20   2 |     match (1.5) {\n\
         \x20     |            ^~~"
    );
}

#[test]
fn enum_payload_errors_point_at_the_token() {
    let source = |body: &str| {
        format!(
            "enum Doc {{\n    Text(text: String),\n    Pair(a: int, b: int),\n    Line,\n}}\nmain(): int {{\n    var d = Doc.Line;\n    {}\n    return 0;\n}}\n",
            body
        )
    };
    assert_eq!(
        error_of("enum_case_takes_values", &source("var x = Doc.Text;")),
        "main.pep:8:17: error: case 'Text' of 'Doc' takes 1 value: 'Doc.Text(text)'\n\
         \x20   8 |     var x = Doc.Text;\n\
         \x20     |                 ^~~~\n\
         main.pep:2:5: note: 'Text' declared here\n\
         \x20   2 |     Text(text: String),\n\
         \x20     |     ^~~~"
    );
    assert_eq!(
        error_of("enum_too_many_bindings", &source("match (d) { Text(a, b) => {} else => {} }")),
        "main.pep:8:25: error: too many bindings for case 'Text': expected 1, have 2\n\
         \x20   8 |     match (d) { Text(a, b) => {} else => {} }\n\
         \x20     |                         ^\n\
         main.pep:2:5: note: 'Text' declared here\n\
         \x20   2 |     Text(text: String),\n\
         \x20     |     ^~~~"
    );
    assert_eq!(
        error_of("enum_binding_types_differ", &source("match (d) { Text(t), Pair(t, _) => {} else => {} }")),
        "main.pep:8:31: error: 't' has type 'int' here but 'String' in 'Text'\n\
         \x20   8 |     match (d) { Text(t), Pair(t, _) => {} else => {} }\n\
         \x20     |                               ^"
    );
    assert_eq!(
        error_of("enum_direct_construction", &source("var x = Doc(0);")),
        "main.pep:8:13: error: cannot construct enum 'Doc' directly: its values are made by its cases\n\
         \x20   8 |     var x = Doc(0);\n\
         \x20     |             ^~~\n\
         note: use a case, such as 'Doc.Text'"
    );
    assert_eq!(
        error_of("enum_payload_unknown_type", "enum Doc {\n    Text(text: Strin),\n}\nmain(): int { return 0; }\n"),
        "main.pep:2:16: error: unknown type name 'Strin'\n\
         \x20   2 |     Text(text: Strin),\n\
         \x20     |                ^~~~~"
    );
}

#[test]
fn unreachable_else_warns() {
    assert_eq!(
        warnings_of("enum Color { Red, Green }\ntest(): int {\n    match (Color.Red) {\n        Red, Green => {}\n        else => {}\n    }\n    return 0;\n}\n"),
        "main.pep:5:9: warning: 'else' is unreachable: every case of 'Color' is handled\n\
         \x20   5 |         else => {}\n\
         \x20     |         ^~~~"
    );
}

#[test]
fn overloaded_method_diagnostics() {
    let main = "struct S {\n    get(x: long): int { return 1; }\n    get(x: short): int { return 2; }\n}\nmain(): int { var s = S(); return s.get(1); }\n";
    assert_eq!(
        error_of("method_overload_ambiguous", main),
        "main.pep:5:37: error: call to 'get' is ambiguous\n\
         \x20   5 | main(): int { var s = S(); return s.get(1); }\n\
         \x20     |                                     ^~~\n\
         main.pep:2:5: note: candidate function\n\
         \x20   2 |     get(x: long): int { return 1; }\n\
         \x20     |     ^~~\n\
         main.pep:3:5: note: candidate function\n\
         \x20   3 |     get(x: short): int { return 2; }\n\
         \x20     |     ^~~"
    );

    let main = "struct S {\n    get(x: int): int { return 1; }\n    static get(x: String): int { return 2; }\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("method_overload_static", main),
        "main.pep:3:12: error: static method 'get' cannot share its name with an instance method of 'S'\n\
         \x20   3 |     static get(x: String): int { return 2; }\n\
         \x20     |            ^~~\n\
         main.pep:2:5: note: previous declaration is here\n\
         \x20   2 |     get(x: int): int { return 1; }\n\
         \x20     |     ^~~"
    );

    let redefinition = error_of("method_overload_redefinition", "struct S {\n    get(x: int): int { return 1; }\n    get(y: int): int { return 2; }\n}\nmain(): int { return 0; }\n");
    assert!(redefinition.starts_with("main.pep:3:5: error: redefinition of 'get'\n"), "{}", redefinition);

    let main = "struct S {\n    get(x: int): int { return 1; }\n    get(x: String): int { return 2; }\n}\nmain(): int {\n    var s = S();\n    var g = s.get;\n    return 0;\n}\n";
    let value = error_of("method_overload_value", main);
    assert!(value.starts_with("main.pep:7:15: error: cannot infer the type of 'g' from overloaded method 'S.get'\n"), "{}", value);
}

#[test]
fn extension_and_trait_overload_diagnostics() {
    // An extension member with the same parameters as a body method.
    let main = "struct S {\n    get(x: int): int { return 1; }\n}\nextend S {\n    get(y: int): int { return 2; }\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("extension_overload_redefinition", main),
        "main.pep:5:5: error: redefinition of 'get'\n\
         \x20   5 |     get(y: int): int { return 2; }\n\
         \x20     |     ^~~\n\
         main.pep:2:5: note: previous definition is here\n\
         \x20   2 |     get(x: int): int { return 1; }\n\
         \x20     |     ^~~"
    );

    // A conforming struct lacks one of a trait's overloads.
    let main = "trait Shape {\n    area(): int;\n    area(scale: int): int;\n}\nstruct Square {\n    area(): int { return 1; }\n}\nextend Square with Shape {}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("trait_overload_missing", main),
        "main.pep:8:8: error: 'Square' does not implement 'area(int)', required by trait 'Shape'\n\
         \x20   8 | extend Square with Shape {}\n\
         \x20     |        ^~~~~~\n\
         main.pep:3:5: note: 'area(int)' declared here\n\
         \x20   3 |     area(scale: int): int;\n\
         \x20     |     ^~~~"
    );

    // A private extension's overload is not a candidate in another file.
    let lib = "export struct Meter {\n    add(x: int): int { return x; }\n}\nextend Meter {\n    add(s: String): int { return 0; }\n}\n";
    let main = "import \"lib\";\nmain(): int {\n    var m = Meter();\n    return m.add(\"x\");\n}\n";
    assert_eq!(
        error_of_files("extension_overload_hidden", main, &[("lib.pep", lib)]),
        "main.pep:4:14: error: no matching function for call to 'add'\n\
         \x20   4 |     return m.add(\"x\");\n\
         \x20     |              ^~~\n\
         lib.pep:2:5: note: candidate function not viable: no known conversion from 'String' to 'int' for 1st argument\n\
         \x20   2 |     add(x: int): int { return x; }\n\
         \x20     |     ^~~"
    );
}

#[test]
fn enum_method_errors_point_at_the_method() {
    let source = |body: &str| {
        format!(
            "enum Light {{\n    Red,\n    wait(extra: int): int {{ return extra; }}\n    static first(): Light {{ return Light.Red; }}\n}}\nmain(): int {{\n    {}\n    return 0;\n}}\n",
            body
        )
    };
    assert_eq!(
        error_of("enum_method_not_static", &source("Light.wait(1);")),
        "main.pep:7:11: error: 'wait' is not static: call it on a value of 'Light', such as 'Light.Red.wait()'\n\
         \x20   7 |     Light.wait(1);\n\
         \x20     |           ^~~~"
    );
    assert_eq!(
        error_of("enum_method_too_many_arguments", &source("Light.Red.wait(1, 2);")),
        "main.pep:7:15: error: too many arguments to 'wait': expected 1, have 2\n\
         \x20   7 |     Light.Red.wait(1, 2);\n\
         \x20     |               ^~~~"
    );
    assert_eq!(
        error_of("enum_method_missing", &source("Light.Red.nope();")),
        "main.pep:7:15: error: no member named 'nope' in 'Light'\n\
         \x20   7 |     Light.Red.nope();\n\
         \x20     |               ^~~~"
    );
}

#[test]
fn tuple_labels_all_or_none() {
    assert_eq!(
        error_of("tuple_labels_all_or_none", "f(): (line: int, int) {\n    return (1, 2);\n}\n"),
        "main.pep:1:18: error: missing label for element 1 of a labeled tuple: label every element or none\n\
         \x20   1 | f(): (line: int, int) {\n\
         \x20     |                  ^~~\n\
         main.pep:1:13: note: element labeled 'line' here\n\
         \x20   1 | f(): (line: int, int) {\n\
         \x20     |             ^~~"
    );
}

#[test]
fn deprecated_enum_method_warns() {
    let source = "enum Light {\n    Red,\n    go(): bool { return true; }\n    [Deprecated(\"use 'go' instead\", \"go\")]\n    may_go(): bool { return true; }\n}\ntest(): int {\n    var l = Light.Red;\n    l.may_go();\n    return 0;\n}\n";
    assert_eq!(
        warnings_of(source),
        "main.pep:9:7: warning: 'may_go' is deprecated: use 'go' instead [deprecated]\n\
         \x20   9 |     l.may_go();\n\
         \x20     |       ^~~~~~\n\
         \x20     |       go\n\
         main.pep:5:5: note: 'may_go' declared here\n\
         \x20   5 |     may_go(): bool { return true; }\n\
         \x20     |     ^~~~~~"
    );
}

#[test]
fn tuple_label_duplicate() {
    assert_eq!(
        error_of("tuple_label_duplicate", "f(): (x: int, x: int) {\n    return (1, 2);\n}\n"),
        "main.pep:1:18: error: duplicate label 'x' in tuple type\n\
         \x20   1 | f(): (x: int, x: int) {\n\
         \x20     |                  ^~~\n\
         main.pep:1:10: note: previous label here\n\
         \x20   1 | f(): (x: int, x: int) {\n\
         \x20     |          ^~~"
    );
}

#[test]
fn tuple_literal_label_missing() {
    assert_eq!(
        error_of("tuple_literal_label_missing", "main(): int {\n    var p = (line: 3, 7);\n    return 0;\n}\n"),
        "main.pep:2:23: error: expected a label ('name: value'), as the first element has one\n\
         \x20   2 |     var p = (line: 3, 7);\n\
         \x20     |                       ^"
    );
}

#[test]
fn tuple_literal_label_unexpected() {
    assert_eq!(
        error_of("tuple_literal_label_unexpected", "main(): int {\n    var p = (3, column: 7);\n    return 0;\n}\n"),
        "main.pep:2:17: error: unexpected label 'column': the first element has none, so label every element or none\n\
         \x20   2 |     var p = (3, column: 7);\n\
         \x20     |                 ^~~~~~"
    );
}

#[test]
fn tuple_literal_single_labeled_element() {
    assert_eq!(
        error_of("tuple_literal_single_labeled_element", "main(): int {\n    var p = (line: 3);\n    return 0;\n}\n"),
        "main.pep:2:21: error: expected ','\n\
         \x20   2 |     var p = (line: 3);\n\
         \x20     |                     ^"
    );
}

#[test]
fn tuple_literal_label_duplicate() {
    assert_eq!(
        error_of("tuple_literal_label_duplicate", "main(): int {\n    var p = (x: 1, x: 2);\n    return 0;\n}\n"),
        "main.pep:2:20: error: duplicate label 'x' in tuple\n\
         \x20   2 |     var p = (x: 1, x: 2);\n\
         \x20     |                    ^\n\
         main.pep:2:14: note: previous label here\n\
         \x20   2 |     var p = (x: 1, x: 2);\n\
         \x20     |              ^"
    );
}

#[test]
fn destructuring_assignment_rejects_labels() {
    assert_eq!(
        error_of(
            "destructuring_assignment_rejects_labels",
            "main(): int {\n    var a = 1;\n    var b = 2;\n    (x: a, y: b) = (b, a);\n    return 0;\n}\n"
        ),
        "main.pep:4:6: error: a destructuring assignment cannot have labels: list the places alone\n\
         \x20   4 |     (x: a, y: b) = (b, a);\n\
         \x20     |      ^"
    );
}

#[test]
fn tuple_literal_label_mismatch() {
    assert_eq!(
        error_of(
            "tuple_literal_label_mismatch",
            "f(): (line: int, column: int) {\n    return (column: 7, line: 3);\n}\n"
        ),
        "main.pep:2:13: error: label 'column' does not match 'line', the label of element 0 of '(line: int, column: int)'\n\
         \x20   2 |     return (column: 7, line: 3);\n\
         \x20     |             ^~~~~~"
    );
}

#[test]
fn result_values_are_made_by_its_cases() {
    assert_eq!(
        error_of("result_constructed", "main(): int {\n    var r = Result<int>();\n    return 0;\n}\n"),
        "main.pep:2:13: error: cannot construct enum 'Result<int>' directly: its values are made by its cases\n\
         \x20   2 |     var r = Result<int>();\n\
         \x20     |             ^~~~~~~~~~~\n\
         note: use a case, such as 'Result<int>.Ok'"
    );
    assert_eq!(
        error_of("void_ok_binds", "main(): int {\n    match (Result<void>.Ok) { Ok(v) => {} Err(e) => {} }\n    return 0;\n}\n")
            .lines()
            .next()
            .unwrap(),
        "main.pep:2:34: error: too many bindings for case 'Ok': expected 0, have 1"
    );
}

#[test]
fn main_with_a_parameter_that_is_not_string_array() {
    assert_eq!(
        error_of("main_params_type", "main(args: int[]): int {\n    return 0;\n}\n"),
        "main.pep:1:12: error: 'main' must take no parameters or one 'String[]'\n\
         \x20   1 | main(args: int[]): int {\n\
         \x20     |            ^~~~~"
    );
}

#[test]
fn main_with_two_parameters() {
    assert_eq!(
        error_of("main_params_count", "main(args: String[], extra: int): int {\n    return 0;\n}\n"),
        "main.pep:1:22: error: 'main' must take no parameters or one 'String[]'\n\
         \x20   1 | main(args: String[], extra: int): int {\n\
         \x20     |                      ^~~~~"
    );
}

#[test]
fn main_declared_in_both_forms() {
    assert_eq!(
        error_of("main_both_forms", "main(): int {\n    return 0;\n}\nmain(args: String[]): int {\n    return 1;\n}\n"),
        "main.pep:4:1: error: redefinition of 'main'\n\
         \x20   4 | main(args: String[]): int {\n\
         \x20     | ^~~~\n\
         main.pep:1:1: note: previous definition is here\n\
         \x20   1 | main(): int {\n\
         \x20     | ^~~~"
    );
}

#[test]
fn match_expression_and_is_errors_point_at_the_token() {
    let shape = "enum Shape {\n    Circle(radius: int),\n    Empty,\n}\n";
    assert_eq!(
        error_of("is_binds_outside", &format!("{}main(): int {{\n    var ok = Shape.Empty is Circle(r);\n    return 0;\n}}\n", shape)),
        "main.pep:6:36: error: cannot bind 'r' here: 'is' binds names only as the whole condition of an 'if' or 'while'\n\
         \x20   6 |     var ok = Shape.Empty is Circle(r);\n\
         \x20     |                                    ^"
    );
    assert_eq!(
        error_of("is_binding_scope", &format!("{}main(): int {{\n    if (Shape.Empty is Circle(r)) {{ return r; }}\n    return r;\n}}\n", shape)),
        "main.pep:7:12: error: use of undeclared identifier 'r'\n\
         \x20   7 |     return r;\n\
         \x20     |            ^"
    );
    assert_eq!(
        error_of("match_needs_else", "main(): int {\n    return match (3) { 1 => 1 };\n}\n"),
        "main.pep:2:12: error: match on 'i32' needs an 'else' arm\n\
         \x20   2 |     return match (3) { 1 => 1 };\n\
         \x20     |            ^~~~~\n\
         note: literal patterns cannot handle every value"
    );
    assert_eq!(
        error_of("match_duplicate_literal", "main(): int {\n    return match (3) { 1 => 1, 1 => 2, else => 0 };\n}\n"),
        "main.pep:2:32: error: value '1' is already handled\n\
         \x20   2 |     return match (3) { 1 => 1, 1 => 2, else => 0 };\n\
         \x20     |                                ^\n\
         main.pep:2:24: note: first handled here\n\
         \x20   2 |     return match (3) { 1 => 1, 1 => 2, else => 0 };\n\
         \x20     |                        ^"
    );
}

#[test]
fn array_literal_element_mismatch() {
    assert_eq!(
        error_of("array_literal_element", "main(): int {\n    var a = [1, \"a\"];\n    return 0;\n}\n"),
        "main.pep:2:17: error: array literal element has type 'String', but the first element's type is 'i32'\n\
         \x20   2 |     var a = [1, \"a\"];\n\
         \x20     |                 ^~~"
    );
}

#[test]
fn map_literal_value_mismatch() {
    assert_eq!(
        error_of("map_literal_value", "main(): int {\n    var m = [\"a\": 1, \"b\": \"c\"];\n    return 0;\n}\n"),
        "main.pep:2:27: error: map literal value has type 'String', but the first value's type is 'i32'\n\
         \x20   2 |     var m = [\"a\": 1, \"b\": \"c\"];\n\
         \x20     |                           ^~~"
    );
}

#[test]
fn empty_array_literal_needs_a_type() {
    assert_eq!(
        error_of("empty_array_literal", "main(): int {\n    var a = [];\n    return 0;\n}\n"),
        "main.pep:2:13: error: empty array literal has no element type; declare the variable's type or write 'Array<T>()'\n\
         \x20   2 |     var a = [];\n\
         \x20     |             ^~"
    );
}

#[test]
fn empty_map_literal_needs_a_type() {
    assert_eq!(
        error_of("empty_map_literal", "main(): int {\n    var m = [:];\n    return 0;\n}\n"),
        "main.pep:2:13: error: empty map literal has no key or value type; declare the variable's type or write 'HashMap<K, V>()'\n\
         \x20   2 |     var m = [:];\n\
         \x20     |             ^~~"
    );
}

/// Two specializations of one generic struct are different types.
#[test]
fn different_specializations_do_not_convert() {
    assert_eq!(
        error_of("specialization_mismatch", "main(): int {\n    Array<long> a = Array<int>();\n    return 0;\n}\n"),
        "main.pep:2:21: error: cannot initialize variable 'a' of type 'Array<long>' with a value of type 'Array<int>'\n\
         \x20   2 |     Array<long> a = Array<int>();\n\
         \x20     |                     ^~~~~~~~~~"
    );
}

/// Type arguments compare wherever a value flows: an assignment, an
/// argument, a return, nested type arguments, and a field (#376).
#[test]
fn different_specializations_do_not_convert_anywhere() {
    let cases = [
        (
            "spec_assign",
            "main(): int {\n    var a = Array<int>();\n    a = Array<String>();\n    return 0;\n}\n",
            "main.pep:3:9: error: cannot assign a value of type 'Array<String>' to a variable of type 'Array<int>'\n\
             \x20   3 |     a = Array<String>();\n\
             \x20     |         ^~~~~~~~~~~~~",
        ),
        (
            "spec_argument",
            "take(a: Array<int>): int { return 0; }\nmain(): int {\n    var b = Array<String>();\n    return take(b);\n}\n",
            "main.pep:4:17: error: cannot pass a value of type 'Array<String>' as argument 1 of 'take', which has type 'Array<int>'\n\
             \x20   4 |     return take(b);\n\
             \x20     |                 ^",
        ),
        (
            "spec_return",
            "make(): Array<int> {\n    return Array<String>();\n}\nmain(): int { return make().count; }\n",
            "main.pep:2:12: error: cannot return a value of type 'Array<String>' from 'make', which returns 'Array<int>'\n\
             \x20   2 |     return Array<String>();\n\
             \x20     |            ^~~~~~~~~~~~~",
        ),
        (
            "spec_nested",
            "main(): int {\n    var b = Array<Array<String>>();\n    Array<Array<int>> a = b;\n    return 0;\n}\n",
            "main.pep:3:27: error: cannot initialize variable 'a' of type 'Array<Array<int>>' with a value of type 'Array<Array<String>>'\n\
             \x20   3 |     Array<Array<int>> a = b;\n\
             \x20     |                           ^",
        ),
        (
            "spec_field",
            "struct Box<T> {\n    var value: Array<T>;\n    construct() { this.value = Array<T>(); }\n}\nmain(): int {\n    var b = Box<int>();\n    b.value = Array<String>();\n    return 0;\n}\n",
            "main.pep:7:15: error: cannot assign a value of type 'Array<String>' to a variable of type 'Array<int>'\n\
             \x20   7 |     b.value = Array<String>();\n\
             \x20     |               ^~~~~~~~~~~~~",
        ),
        (
            "spec_alias",
            "type Ints = Array<int>;\nmain(): int {\n    Ints a = Array<String>();\n    return 0;\n}\n",
            "main.pep:3:14: error: cannot initialize variable 'a' of type 'Array<int>' with a value of type 'Array<String>'\n\
             \x20   3 |     Ints a = Array<String>();\n\
             \x20     |              ^~~~~~~~~~~~~",
        ),
    ];
    for (test, source, expected) in cases {
        assert_eq!(error_of(test, source), expected, "{test}");
    }
}

/// An omitted type argument is its default, so `Result<int>` is
/// `Result<int, Error>` but not `Result<int, String>` (#376).
#[test]
fn defaulted_type_arguments_compare_filled_in() {
    assert_eq!(
        error_of("spec_default", "main(): int {\n    var r: Result<int> = Result<int, String>.Ok(1);\n    return 0;\n}\n"),
        "main.pep:2:46: error: cannot initialize variable 'r' of type 'Result<int>' with a value of type 'Result<int, String>'\n\
         \x20   2 |     var r: Result<int> = Result<int, String>.Ok(1);\n\
         \x20     |                                              ^~"
    );
}

/// The arms of `c ? a : b` must have one type: the false arm converts to
/// the true arm's (#376).
#[test]
fn conditional_arms_of_different_types() {
    assert_eq!(
        error_of(
            "conditional_arms",
            "main(): int {\n    var flag = true;\n    var a = flag ? Array<int>() : Array<String>();\n    return 0;\n}\n"
        ),
        "main.pep:3:35: error: incompatible operand types ('Array<int>' and 'Array<String>')\n\
         \x20   3 |     var a = flag ? Array<int>() : Array<String>();\n\
         \x20     |                                   ^~~~~~~~~~~~~"
    );
    assert_eq!(
        error_of(
            "conditional_structs",
            "struct Foo {}\nstruct Bar {}\nmain(): int {\n    var c = true ? Foo() : Bar();\n    return 0;\n}\n"
        ),
        "main.pep:4:28: error: incompatible operand types ('Foo' and 'Bar')\n\
         \x20   4 |     var c = true ? Foo() : Bar();\n\
         \x20     |                            ^~~"
    );
}

#[test]
fn interpolation_without_to_string() {
    assert_eq!(
        error_of("interpolation_no_to_string", "struct Foo {}\n\nmain(): int {\n    var f = Foo();\n    print($\"f = {f}\");\n    return 0;\n}\n"),
        "main.pep:5:17: error: cannot interpolate a value of type 'Foo': it has no 'to_string()' method and no 'to_string' overload\n\
         \x20   5 |     print($\"f = {f}\");\n\
         \x20     |                 ^~~\n\
         main.pep:1:8: note: declare 'to_string(): String' in 'Foo', or implement 'ToString' with 'extend Foo with ToString'\n\
         \x20   1 | struct Foo {}\n\
         \x20     |        ^~~"
    );
}

#[test]
fn interpolation_undeclared_name() {
    assert_eq!(
        error_of("interpolation_undeclared", "main(): int {\n    print($\"{nope}\");\n    return 0;\n}\n"),
        "main.pep:2:14: error: use of undeclared identifier 'nope'\n\
         \x20   2 |     print($\"{nope}\");\n\
         \x20     |              ^~~~"
    );
}

#[test]
fn interpolation_unmatched_brace() {
    assert_eq!(
        error_of("interpolation_unmatched", "main(): int {\n    print($\"a } b\");\n    return 0;\n}\n"),
        "main.pep:2:15: error: unmatched '}' in interpolated string; write '}}' for a literal '}'\n\
         \x20   2 |     print($\"a } b\");\n\
         \x20     |               ^"
    );
}

#[test]
fn interpolation_unclosed_brace() {
    assert_eq!(
        error_of("interpolation_unclosed", "main(): int {\n    var x = 1;\n    print($\"a {x b\");\n    return 0;\n}\n"),
        "main.pep:3:18: error: expected '}'\n\
         \x20   3 |     print($\"a {x b\");\n\
         \x20     |                  ^\n\
         main.pep:3:15: note: to match this '{'\n\
         \x20   3 |     print($\"a {x b\");\n\
         \x20     |               ^"
    );
}

#[test]
fn interpolation_missing_expression() {
    assert_eq!(
        error_of("interpolation_missing_expression", "main(): int {\n    print($\"a {} b\");\n    return 0;\n}\n"),
        "main.pep:2:16: error: expected an expression after '{' in interpolated string; write '{{' for a literal '{'\n\
         \x20   2 |     print($\"a {} b\");\n\
         \x20     |                ^"
    );
}

#[test]
fn interpolation_expression_without_to_string() {
    // The whole `{...}` is marked, as for a name.
    assert_eq!(
        error_of("interpolation_expression_no_to_string", "struct Foo {}\n\nmake(): Foo {\n    return Foo();\n}\n\nmain(): int {\n    print($\"f = {make()}\");\n    return 0;\n}\n"),
        "main.pep:8:17: error: cannot interpolate a value of type 'Foo': it has no 'to_string()' method and no 'to_string' overload\n\
         \x20   8 |     print($\"f = {make()}\");\n\
         \x20     |                 ^~~~~~~~\n\
         main.pep:1:8: note: declare 'to_string(): String' in 'Foo', or implement 'ToString' with 'extend Foo with ToString'\n\
         \x20   1 | struct Foo {}\n\
         \x20     |        ^~~"
    );
}

#[test]
fn interpolation_expression_error() {
    // An error inside the braces is located inside them.
    assert_eq!(
        error_of("interpolation_expression_error", "main(): int {\n    var a = 1;\n    print($\"{a + nope}\");\n    return 0;\n}\n"),
        "main.pep:3:18: error: use of undeclared identifier 'nope'\n\
         \x20   3 |     print($\"{a + nope}\");\n\
         \x20     |                  ^~~~"
    );
}

#[test]
fn interpolation_assignment() {
    // An assignment is not an interpolated expression.
    assert_eq!(
        error_of("interpolation_assignment", "main(): int {\n    var a = 1;\n    print($\"{a = 2}\");\n    return 0;\n}\n"),
        "main.pep:3:16: error: an assignment cannot appear in an interpolated string\n\
         \x20   3 |     print($\"{a = 2}\");\n\
         \x20     |                ^"
    );
}

#[test]
fn interpolation_compound_assignment() {
    assert_eq!(
        error_of("interpolation_compound_assignment", "main(): int {\n    var a = 1;\n    print($\"{a += 1}\");\n    return 0;\n}\n"),
        "main.pep:3:16: error: an assignment cannot appear in an interpolated string\n\
         \x20   3 |     print($\"{a += 1}\");\n\
         \x20     |                ^~"
    );
}

#[test]
fn interpolation_nested_assignment() {
    // Not only at the top: inside a call's arguments and a ternary's branches too.
    assert_eq!(
        error_of("interpolation_nested_assignment", "f(x: int): int {\n    return x;\n}\n\nmain(): int {\n    var a = 1;\n    print($\"{true ? f(a <<= 3) : 2}\");\n    return 0;\n}\n"),
        "main.pep:7:25: error: an assignment cannot appear in an interpolated string\n\
         \x20   7 |     print($\"{true ? f(a <<= 3) : 2}\");\n\
         \x20     |                         ^~~"
    );
}

#[test]
fn interpolation_increment() {
    assert_eq!(
        error_of("interpolation_increment", "main(): int {\n    var a = 1;\n    var items = [1, 2];\n    print($\"{items[a++]}\");\n    return 0;\n}\n"),
        "main.pep:4:21: error: an increment cannot appear in an interpolated string\n\
         \x20   4 |     print($\"{items[a++]}\");\n\
         \x20     |                     ^~"
    );
}

#[test]
fn interpolation_decrement() {
    assert_eq!(
        error_of("interpolation_decrement", "main(): int {\n    var a = 1;\n    print($\"{--a}\");\n    return 0;\n}\n"),
        "main.pep:3:14: error: a decrement cannot appear in an interpolated string\n\
         \x20   3 |     print($\"{--a}\");\n\
         \x20     |              ^~"
    );
}

#[test]
fn interpolation_expression_across_lines() {
    // The expression in braces fits on one line.
    assert_eq!(
        error_of("interpolation_across_lines", "main(): int {\n    var a = 1;\n    print($\"{a +\n        a}\");\n    return 0;\n}\n"),
        "main.pep:3:17: error: expected '}'\n\
         \x20   3 |     print($\"{a +\n\
         \x20     |                 ^\n\
         main.pep:3:13: note: to match this '{'\n\
         \x20   3 |     print($\"{a +\n\
         \x20     |             ^"
    );
}

#[test]
fn interpolation_comment() {
    assert_eq!(
        error_of("interpolation_comment", "main(): int {\n    var a = 1;\n    print($\"{a # one}\");\n    return 0;\n}\n"),
        "main.pep:3:16: error: a comment cannot appear inside '{}' in an interpolated string\n\
         \x20   3 |     print($\"{a # one}\");\n\
         \x20     |                ^"
    );
}

#[test]
fn format_unexpected_character() {
    assert_eq!(
        error_of("format_unexpected_character", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print($\"{n:q}\");\n    return 0;\n}\n"),
        "main.pep:5:16: error: unexpected 'q' in format specification; expected '[[fill]align][+][0][width][.precision][type]'\n\
         \x20   5 |     print($\"{n:q}\");\n\
         \x20     |                ^"
    );
}

#[test]
fn format_empty_specification() {
    assert_eq!(
        error_of("format_empty_specification", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print($\"{n:}\");\n    return 0;\n}\n"),
        "main.pep:5:16: error: expected a format specification after ':'\n\
         \x20   5 |     print($\"{n:}\");\n\
         \x20     |                ^"
    );
}

#[test]
fn format_zero_and_alignment() {
    assert_eq!(
        error_of("format_zero_and_alignment", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print($\"{n:<05}\");\n    return 0;\n}\n"),
        "main.pep:5:17: error: '0' padding cannot be combined with an alignment\n\
         \x20   5 |     print($\"{n:<05}\");\n\
         \x20     |                 ^"
    );
}

#[test]
fn format_width_too_large() {
    assert_eq!(
        error_of("format_width_too_large", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print($\"{n:99999999999}\");\n    return 0;\n}\n"),
        "main.pep:5:16: error: format width is too large\n\
         \x20   5 |     print($\"{n:99999999999}\");\n\
         \x20     |                ^~~~~~~~~~~"
    );
}

#[test]
fn format_integer_type() {
    assert_eq!(
        error_of("format_integer_type", "struct Foo {}\n\nmain(): int {\n    var name = \"a\";\n    print($\"{name:x}\");\n    return 0;\n}\n"),
        "main.pep:5:19: error: cannot format a value of type 'String' as an integer\n\
         \x20   5 |     print($\"{name:x}\");\n\
         \x20     |                   ^"
    );
}

#[test]
fn format_padding_without_to_string() {
    assert_eq!(
        error_of("format_padding_without_to_string", "struct Foo {}\n\nmain(): int {\n    var f = Foo();\n    print($\"{f:>5}\");\n    return 0;\n}\n"),
        "main.pep:5:13: error: cannot interpolate a value of type 'Foo': it has no 'to_string()' method and no 'to_string' overload\n\
         \x20   5 |     print($\"{f:>5}\");\n\
         \x20     |             ^~~~~~\n\
         main.pep:1:8: note: declare 'to_string(): String' in 'Foo', or implement 'ToString' with 'extend Foo with ToString'\n\
         \x20   1 | struct Foo {}\n\
         \x20     |        ^~~"
    );
}

#[test]
fn string_format_not_a_literal() {
    assert_eq!(
        error_of("string_format_not_a_literal", "struct Foo {}\n\nmain(): int {\n    var name = \"a\";\n    print(String.format(name));\n    return 0;\n}\n"),
        "main.pep:5:25: error: the format of 'String.format' must be a string literal\n\
         \x20   5 |     print(String.format(name));\n\
         \x20     |                         ^~~~"
    );
}

#[test]
fn string_format_index_out_of_range() {
    assert_eq!(
        error_of("string_format_index_out_of_range", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print(String.format(\"{0} {2}\", n, n));\n    return 0;\n}\n"),
        "main.pep:5:31: error: argument index 2 is out of range for 2 arguments\n\
         \x20   5 |     print(String.format(\"{0} {2}\", n, n));\n\
         \x20     |                               ^"
    );
}

#[test]
fn string_format_unused_argument() {
    assert_eq!(
        error_of("string_format_unused_argument", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print(String.format(\"{0}\", n, n + 1));\n    return 0;\n}\n"),
        "main.pep:5:35: error: argument 1 of 'String.format' is not used by its format string\n\
         \x20   5 |     print(String.format(\"{0}\", n, n + 1));\n\
         \x20     |                                   ^~~~~"
    );
}

#[test]
fn string_format_missing_index() {
    assert_eq!(
        error_of("string_format_missing_index", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print(String.format(\"{x}\", n));\n    return 0;\n}\n"),
        "main.pep:5:27: error: expected an argument index after '{' in format string; write '{{' for a literal '{'\n\
         \x20   5 |     print(String.format(\"{x}\", n));\n\
         \x20     |                           ^"
    );
}

#[test]
fn string_format_unclosed_brace() {
    assert_eq!(
        error_of("string_format_unclosed_brace", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print(String.format(\"{0:x\", n));\n    return 0;\n}\n"),
        "main.pep:5:30: error: expected '}'\n\
         \x20   5 |     print(String.format(\"{0:x\", n));\n\
         \x20     |                              ^\n\
         main.pep:5:26: note: to match this '{'\n\
         \x20   5 |     print(String.format(\"{0:x\", n));\n\
         \x20     |                          ^"
    );
}

#[test]
fn string_format_unmatched_brace() {
    assert_eq!(
        error_of("string_format_unmatched_brace", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print(String.format(\"{0}}\", n));\n    return 0;\n}\n"),
        "main.pep:5:29: error: unmatched '}' in format string; write '}}' for a literal '}'\n\
         \x20   5 |     print(String.format(\"{0}}\", n));\n\
         \x20     |                             ^"
    );
}

#[test]
fn interpolation_unterminated() {
    assert_eq!(
        error_of("interpolation_unterminated", "main(): int {\n    print($\"a);\n    return 0;\n}\n"),
        "main.pep:2:12: error: missing terminating '\"' character\n\
         \x20   2 |     print($\"a);\n\
         \x20     |            ^"
    );
}

#[test]
fn undeclared_argument_of_generic_call() {
    // Not "cannot infer the type arguments": the argument names nothing.
    assert_eq!(
        error_of("undeclared_generic_argument", "wrap<T>(value: T): T {\n    return value;\n}\n\nmain(): int {\n    wrap(nope);\n    return 0;\n}\n"),
        "main.pep:6:10: error: use of undeclared identifier 'nope'\n\
         \x20   6 |     wrap(nope);\n\
         \x20     |          ^~~~"
    );
}

#[test]
fn tuple_match_missing_value() {
    assert_eq!(
        error_of("tuple_match_missing_value", "enum Shape { Circle, Square, Line }\nf(s: Shape, n: int): int {\n    match ((s, n)) {\n        (Circle, _) => { return 1; }\n        (Square, 0) => { return 2; }\n    }\n    return 0;\n}\n"),
        "main.pep:3:5: error: match on '(Shape, int)' does not handle '(Line, _)'\n\
         \x20   3 |     match ((s, n)) {\n\
         \x20     |     ^~~~~\n\
         note: handle it with another arm, or add an 'else' arm"
    );
}

#[test]
fn tuple_match_missing_bool() {
    assert_eq!(
        error_of("tuple_match_missing_bool", "enum Shape { Circle, Square, Line }\nf(a: bool, b: bool): int {\n    match ((a, b)) {\n        (true, _) => { return 1; }\n        (false, true) => { return 2; }\n    }\n    return 0;\n}\n"),
        "main.pep:3:5: error: match on '(bool, bool)' does not handle '(false, false)'\n\
         \x20   3 |     match ((a, b)) {\n\
         \x20     |     ^~~~~\n\
         note: handle it with another arm, or add an 'else' arm"
    );
}

#[test]
fn tuple_pattern_already_handled() {
    assert_eq!(
        error_of("tuple_pattern_already_handled", "enum Shape { Circle, Square, Line }\nf(s: Shape, n: int): int {\n    match ((s, n)) {\n        (_, k) => { return k; }\n        (Circle, _) => { return 1; }\n    }\n    return 0;\n}\n"),
        "main.pep:5:9: error: pattern '(Circle, _)' is already handled\n\
         \x20   5 |         (Circle, _) => { return 1; }\n\
         \x20     |         ^~~~~~~~~~~\n\
         note: the patterns before it match every value it does"
    );
}

#[test]
fn case_pattern_on_tuple() {
    assert_eq!(
        error_of("case_pattern_on_tuple", "enum Shape { Circle, Square, Line }\nf(a: int, b: int): int {\n    match ((a, b)) {\n        Circle => { return 1; }\n        else => { return 0; }\n    }\n}\n"),
        "main.pep:4:9: error: 'Circle' cannot match a value of '(int, int)': match a tuple with a tuple pattern, such as '(a, _)'\n\
         \x20   4 |         Circle => { return 1; }\n\
         \x20     |         ^~~~~~\n\
         main.pep:3:12: note: the value matched is here\n\
         \x20   3 |     match ((a, b)) {\n\
         \x20     |            ^~~~~~"
    );
}

#[test]
fn tuple_pattern_on_enum() {
    assert_eq!(
        error_of("tuple_pattern_on_enum", "enum Shape { Circle, Square, Line }\nf(s: Shape): int {\n    match (s) {\n        (Circle, _) => { return 1; }\n        else => { return 0; }\n    }\n}\n"),
        "main.pep:4:9: error: a tuple pattern cannot match a value of 'Shape'\n\
         \x20   4 |         (Circle, _) => { return 1; }\n\
         \x20     |         ^~~~~~~~~~~\n\
         main.pep:3:12: note: the value matched is here\n\
         \x20   3 |     match (s) {\n\
         \x20     |            ^"
    );
}

#[test]
fn tuple_pattern_case_on_int() {
    assert_eq!(
        error_of("tuple_pattern_case_on_int", "enum Shape { Circle, Square, Line }\nf(a: int, b: int): int {\n    match ((a, b)) {\n        (Shape.Circle, _) => { return 1; }\n        else => { return 0; }\n    }\n}\n"),
        "main.pep:4:16: error: 'Circle' cannot match a value of 'int': it is not an enum\n\
         \x20   4 |         (Shape.Circle, _) => { return 1; }\n\
         \x20     |                ^~~~~~"
    );
}

#[test]
fn tuple_pattern_binds_at_different_elements() {
    assert_eq!(
        error_of("tuple_pattern_binds_at_different_elements", "enum Shape { Circle, Square, Line }\nf(a: int, b: int): int {\n    match ((a, b)) {\n        (x, 1), (1, x) => { return x; }\n        else => { return 0; }\n    }\n}\n"),
        "main.pep:4:10: error: 'x' binds an element here, but not once at the same element in every pattern of the arm\n\
         \x20   4 |         (x, 1), (1, x) => { return x; }\n\
         \x20     |          ^\n\
         note: bind it once in each pattern, at the same element, or use '_'"
    );
}

#[test]
fn tuple_is_test_cannot_bind() {
    assert_eq!(
        error_of("tuple_is_test_cannot_bind", "enum Shape { Circle, Square, Line }\nf(a: int, s: Shape): int {\n    var hit = (a, s) is (n, Line);\n    return 0;\n}\n"),
        "main.pep:3:26: error: cannot bind 'n' here: 'is' binds names only as the whole condition of an 'if' or 'while'\n\
         \x20   3 |     var hit = (a, s) is (n, Line);\n\
         \x20     |                          ^"
    );
}

#[test]
fn tuple_pattern_needs_two_elements() {
    assert_eq!(
        error_of("tuple_pattern_needs_two_elements", "enum Shape { Circle, Square, Line }\nf(a: int, b: int): int {\n    match ((a, b)) {\n        (x) => { return x; }\n    }\n    return 0;\n}\n"),
        "main.pep:4:11: error: expected ','\n\
         \x20   4 |         (x) => { return x; }\n\
         \x20     |           ^"
    );
}

#[test]
fn tuple_match_unreachable_else_warns() {
    assert_eq!(
        warnings_of("test(): int {\n    int n = 1;\n    match ((n, true)) {\n        (_, _) => {}\n        else => {}\n    }\n    return 0;\n}\n"),
        "main.pep:5:9: warning: 'else' is unreachable: every value of '(int, bool)' is handled\n\
         \x20   5 |         else => {}\n\
         \x20     |         ^~~~"
    );
}

#[test]
fn closure_in_a_guard_cannot_use_a_binding() {
    assert_eq!(
        error_of("closure_in_a_guard", "enum Shape { Circle(r: int), Point }\ntest(): int {\n    return match (Shape.Point) {\n        Circle(r) if (() => r)() > 1 => 1,\n        else => 2,\n    };\n}\n"),
        "main.pep:4:29: error: a closure in a guard cannot use 'r', bound by the arm's patterns\n\
         \x20   4 |         Circle(r) if (() => r)() > 1 => 1,\n\
         \x20     |                             ^\n\
         main.pep:4:16: note: 'r' is bound here\n\
         \x20   4 |         Circle(r) if (() => r)() > 1 => 1,\n\
         \x20     |                ^"
    );
}

#[test]
fn guard_needs_a_condition() {
    assert_eq!(
        error_of("guard_needs_a_condition", "test(): int {\n    return match (1) {\n        1 if => 1,\n        else => 2,\n    };\n}\n"),
        "main.pep:3:14: error: expected expression or a condition\n\
         \x20   3 |         1 if => 1,\n\
         \x20     |              ^"
    );
}

#[test]
fn range_pattern_already_handled() {
    assert_eq!(
        error_of("range_already_handled", "test(): int {\n    return match (3) {\n        1..9 => 1,\n        2..>5 => 2,\n        else => 0,\n    };\n}\n"),
        "main.pep:4:9: error: pattern '2..>5' is already handled\n\
         \x20   4 |         2..>5 => 2,\n\
         \x20     |         ^~~~~\n\
         note: the patterns before it match every value it does"
    );
}

/// Source nested past `MAX_NESTING` fails at the token that crosses the
/// limit: an opening parenthesis, or the operator of a long chain.
#[test]
fn nested_too_deeply() {
    let n = pepper_parser::parser::MAX_NESTING + 10;
    for (source, token) in [
        (format!("main(): int {{\n    return {}0{};\n}}\n", "(".repeat(n), ")".repeat(n)), '('),
        (format!("main(): int {{\n    return 0{};\n}}\n", " + 1".repeat(n)), '+'),
    ] {
        // Parsing up to the limit needs the compiler's stack, not a test thread's.
        let parse = std::thread::Builder::new().stack_size(pepper_driver::STACK_SIZE);
        let error = parse
            .spawn(move || pepper_parser::parser::parse_source_diag(&source).unwrap_err().render_in("main.pep", &source))
            .unwrap()
            .join()
            .unwrap();
        let lines: Vec<&str> = error.lines().collect();
        assert!(lines[0].starts_with("main.pep:2:"), "{error}");
        assert!(
            lines[0].ends_with(
                "error: code is nested too deeply: the limit is 256 levels; split it into smaller expressions or functions"
            ),
            "{error}"
        );
        let caret = lines[2].find('^').unwrap();
        assert_eq!(lines[1].chars().nth(caret), Some(token), "{error}");
    }
}

#[test]
fn print_of_a_value_with_no_text() {
    assert_eq!(
        error_of("print_no_text", "struct Foo {}\n\nmain(): int {\n    var f = Foo();\n    print(f);\n    return 0;\n}\n"),
        "main.pep:5:11: error: cannot print a value of type 'Foo': it has no 'to_string()' method and no 'to_string' overload\n\
         \x20   5 |     print(f);\n\
         \x20     |           ^"
    );
}

#[test]
fn print_format_unused_argument() {
    assert_eq!(
        error_of("print_format_unused_argument", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print(\"{0}\", n, n + 1);\n    return 0;\n}\n"),
        "main.pep:5:21: error: argument 1 of 'print' is not used by its format string\n\
         \x20   5 |     print(\"{0}\", n, n + 1);\n\
         \x20     |                     ^~~~~"
    );
}

#[test]
fn format_precision_on_an_integer() {
    assert_eq!(
        error_of("format_precision_on_an_integer", "struct Foo {}\n\nmain(): int {\n    var n = 1;\n    print($\"{n:.2}\");\n    return 0;\n}\n"),
        "main.pep:5:16: error: cannot format a value of type 'i32' with a precision; only 'float' and 'double' take one\n\
         \x20   5 |     print($\"{n:.2}\");\n\
         \x20     |                ^"
    );
}

#[test]
fn format_precision_with_an_integer_type() {
    assert_eq!(
        error_of("format_precision_with_an_integer_type", "struct Foo {}\n\nmain(): int {\n    var d = 1.5;\n    print($\"{d:.2x}\");\n    return 0;\n}\n"),
        "main.pep:5:16: error: a precision cannot be combined with the integer type 'x'\n\
         \x20   5 |     print($\"{d:.2x}\");\n\
         \x20     |                ^"
    );
}

#[test]
fn format_precision_without_digits() {
    assert_eq!(
        error_of("format_precision_without_digits", "struct Foo {}\n\nmain(): int {\n    var d = 1.5;\n    print($\"{d:.}\");\n    return 0;\n}\n"),
        "main.pep:5:16: error: expected a precision after '.' in format specification\n\
         \x20   5 |     print($\"{d:.}\");\n\
         \x20     |                ^"
    );
}

/// Explicit type argument: reported at the argument, with the constraint and the missing extension.
#[test]
fn constraint_not_met_by_type_argument() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nstruct Gallery<T: Shape> {\n    var items = Array<T>();\n}\nmain(): int {\n    var g = Gallery<Circle>();\n    return 0;\n}\n";
    assert_eq!(
        error_of("constraint_not_met_by_type_argument", source),
        "main.pep:11:21: error: 'Circle' does not conform to trait 'Shape', required by 'T' in 'Gallery'\n\
         \x20  11 |     var g = Gallery<Circle>();\n\
         \x20     |                     ^~~~~~\n\
         main.pep:7:19: note: constraint declared here\n\
         \x20   7 | struct Gallery<T: Shape> {\n\
         \x20     |                   ^~~~~\n\
         main.pep:4:8: note: declare it with 'extend Circle with Shape'\n\
         \x20   4 | struct Circle {\n\
         \x20     |        ^~~~~~"
    );
}

/// Inferred type argument: reported at the call argument that fixed it.
#[test]
fn constraint_not_met_by_inferred_argument() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\ntotal<T: Shape>(items: Array<T>): int { return 0; }\nmain(): int {\n    var circles = Array<Circle>();\n    return total(circles);\n}\n";
    assert_eq!(
        error_of("constraint_not_met_by_inferred_argument", source),
        "main.pep:10:18: error: 'Circle' does not conform to trait 'Shape', required by 'T' in 'total'\n\
         \x20  10 |     return total(circles);\n\
         \x20     |                  ^~~~~~~\n\
         main.pep:7:10: note: constraint declared here\n\
         \x20   7 | total<T: Shape>(items: Array<T>): int { return 0; }\n\
         \x20     |          ^~~~~\n\
         main.pep:4:8: note: declare it with 'extend Circle with Shape'\n\
         \x20   4 | struct Circle {\n\
         \x20     |        ^~~~~~"
    );
}

/// A constraint must name a trait.
#[test]
fn constraint_names_a_struct() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nstruct Point {\n    var x: int;\n}\nf<T: Point>(x: T): int { return 0; }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_names_a_struct", source),
        "main.pep:10:6: error: 'Point' is not a trait; a constraint must name a trait\n\
         \x20  10 | f<T: Point>(x: T): int { return 0; }\n\
         \x20     |      ^~~~~\n\
         main.pep:7:8: note: 'Point' declared here\n\
         \x20   7 | struct Point {\n\
         \x20     |        ^~~~~"
    );
}

/// A default must meet its parameter's constraints.
#[test]
fn constraint_not_met_by_default() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nstruct Frame<TTag, T: Shape = Circle> {\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_not_met_by_default", source),
        "main.pep:7:31: error: 'Circle' does not conform to trait 'Shape', required by 'T' in 'Frame'\n\
         \x20   7 | struct Frame<TTag, T: Shape = Circle> {\n\
         \x20     |                               ^~~~~~\n\
         main.pep:7:23: note: constraint declared here\n\
         \x20   7 | struct Frame<TTag, T: Shape = Circle> {\n\
         \x20     |                       ^~~~~\n\
         main.pep:4:8: note: declare it with 'extend Circle with Shape'\n\
         \x20   4 | struct Circle {\n\
         \x20     |        ^~~~~~"
    );
}

/// An unconstrained parameter passed where a constraint applies, with a fix-it that adds it.
#[test]
fn constraint_not_met_by_parameter() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nstruct Gallery<T: Shape> {\n}\nwrap<T>(x: T): Gallery<T> { return Gallery<T>(); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_not_met_by_parameter", source),
        "main.pep:9:24: error: 'T' does not conform to trait 'Shape', required by 'T' in 'Gallery'\n\
         \x20   9 | wrap<T>(x: T): Gallery<T> { return Gallery<T>(); }\n\
         \x20     |                        ^\n\
         \x20     |       : Shape\n\
         main.pep:7:19: note: constraint declared here\n\
         \x20   7 | struct Gallery<T: Shape> {\n\
         \x20     |                   ^~~~~\n\
         main.pep:9:6: note: add a constraint to 'T': 'T: Shape'\n\
         \x20   9 | wrap<T>(x: T): Gallery<T> { return Gallery<T>(); }\n\
         \x20     |      ^"
    );
}

/// A concrete override passes its type arguments to the constrained generic.
#[test]
fn constraint_not_met_by_override() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Point {\n    var x: int;\n}\ndescribe<T: Shape>(x: T): int { return 1; }\ndescribe<Point>(x: Point): int { return 2; }\nmain(): int { return describe(Circle()); }\n";
    assert_eq!(
        error_of("constraint_not_met_by_override", source),
        "main.pep:12:10: error: 'Point' does not conform to trait 'Shape', required by 'T' in 'describe'\n\
         \x20  12 | describe<Point>(x: Point): int { return 2; }\n\
         \x20     |          ^~~~~\n\
         main.pep:11:13: note: constraint declared here\n\
         \x20  11 | describe<T: Shape>(x: T): int { return 1; }\n\
         \x20     |             ^~~~~\n\
         main.pep:8:8: note: declare it with 'extend Point with Shape'\n\
         \x20   8 | struct Point {\n\
         \x20     |        ^~~~~"
    );
}

/// An overload whose constraints the arguments do not meet is not viable.
#[test]
fn constraint_makes_overload_not_viable() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nf<T: Shape>(x: T): int { return 1; }\nf(x: int): int { return 2; }\nmain(): int { return f(Circle()); }\n";
    assert_eq!(
        error_of("constraint_makes_overload_not_viable", source),
        "main.pep:9:22: error: no matching function for call to 'f'\n\
         \x20   9 | main(): int { return f(Circle()); }\n\
         \x20     |                      ^\n\
         main.pep:7:1: note: candidate function not viable: 'Circle' does not conform to 'Shape'\n\
         \x20   7 | f<T: Shape>(x: T): int { return 1; }\n\
         \x20     | ^\n\
         main.pep:8:1: note: candidate function not viable: no known conversion from 'Circle' to 'int' for 1st argument\n\
         \x20   8 | f(x: int): int { return 2; }\n\
         \x20     | ^"
    );
}

/// A generic method's constraint, at the call argument.
#[test]
fn constraint_on_generic_method() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nstruct Canvas {\n    draw<T: Shape>(x: T): int { return 1; }\n}\nmain(): int {\n    var c = Canvas();\n    return c.draw(Circle());\n}\n";
    assert_eq!(
        error_of("constraint_on_generic_method", source),
        "main.pep:12:19: error: 'Circle' does not conform to trait 'Shape', required by 'T' in 'draw'\n\
         \x20  12 |     return c.draw(Circle());\n\
         \x20     |                   ^~~~~~\n\
         main.pep:8:13: note: constraint declared here\n\
         \x20   8 |     draw<T: Shape>(x: T): int { return 1; }\n\
         \x20     |             ^~~~~\n\
         main.pep:4:8: note: declare it with 'extend Circle with Shape'\n\
         \x20   4 | struct Circle {\n\
         \x20     |        ^~~~~~"
    );
}

/// A trait type meets its own constraint only when every member can be called through a value.
#[test]
fn constraint_trait_type_member_not_dispatchable() {
    let source = "trait Cloner {\n    duplicate(): this;\n}\nf<T: Cloner>(items: Array<T>): int { return 0; }\nmain(): int {\n    var items = Array<Cloner>();\n    return f(items);\n}\n";
    assert_eq!(
        error_of("constraint_trait_type_member_not_dispatchable", source),
        "main.pep:7:14: error: 'Cloner' does not conform to trait 'Cloner', required by 'T' in 'f'\n\
         \x20   7 |     return f(items);\n\
         \x20     |              ^~~~~\n\
         main.pep:4:6: note: constraint declared here\n\
         \x20   4 | f<T: Cloner>(items: Array<T>): int { return 0; }\n\
         \x20     |      ^~~~~~\n\
         main.pep:2:5: note: 'duplicate' cannot be called through a value of type 'Cloner'\n\
         \x20   2 |     duplicate(): this;\n\
         \x20     |     ^~~~~~~~~"
    );
}

/// A constraint naming nothing.
#[test]
fn constraint_names_an_unknown_type() {
    let source = "f<T: Drawable>(x: T): int { return 0; }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_names_an_unknown_type", source),
        "main.pep:1:6: error: unknown type name 'Drawable'\n\
         \x20   1 | f<T: Drawable>(x: T): int { return 0; }\n\
         \x20     |      ^~~~~~~~"
    );
}

/// Only the struct's own parameters restate its constraints.
#[test]
fn constraint_restated_on_a_specialization() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nstruct Box<T: Shape> {\n    var item: T;\n}\nextend Box<Circle: Shape> {\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_restated_on_a_specialization", source),
        "main.pep:10:20: error: only the parameters of 'Box' can restate its constraints\n\
         \x20  10 | extend Box<Circle: Shape> {\n\
         \x20     |                    ^~~~~"
    );
}

/// A primitive is no trait; with nothing to point at, there is no note.
#[test]
fn constraint_names_a_primitive() {
    let source = "one<T: bool>(x: T): int { return 0; }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_names_a_primitive", source),
        "main.pep:1:8: error: 'bool' is not a trait; a constraint must name a trait\n\
         \x20   1 | one<T: bool>(x: T): int { return 0; }\n\
         \x20     |        ^~~~"
    );
}

/// A constraint naming another parameter of its list points at it.
#[test]
fn constraint_names_a_sibling_parameter() {
    let source = "f<T, U: T>(u: U): int { return 0; }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_names_a_sibling_parameter", source),
        "main.pep:1:9: error: 'T' is not a trait; a constraint must name a trait\n\
         \x20   1 | f<T, U: T>(u: U): int { return 0; }\n\
         \x20     |         ^\n\
         main.pep:1:3: note: 'T' declared here\n\
         \x20   1 | f<T, U: T>(u: U): int { return 0; }\n\
         \x20     |   ^"
    );
}

/// A method's constraint naming its struct's parameter is not an unknown type.
#[test]
fn constraint_names_an_enclosing_parameter() {
    let source = "struct Box<T> {\n    var n: int;\n    m<U: T>(u: U): int { return 0; }\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constraint_names_an_enclosing_parameter", source),
        "main.pep:3:10: error: 'T' is not a trait; a constraint must name a trait\n\
         \x20   3 |     m<U: T>(u: U): int { return 0; }\n\
         \x20     |          ^\n\
         main.pep:1:12: note: 'T' declared here\n\
         \x20   1 | struct Box<T> {\n\
         \x20     |            ^"
    );
}

/// An inferred call is reported at its own argument, not at a use in code this platform drops.
#[test]
fn constraint_inferred_call_beside_platform_code() {
    let source = "trait Shape {\n    area(): int;\n}\nstruct Epoll {\n    var fd: int;\n    area(): int { return 1; }\n}\n[Target(OS(Windows) && OS(Linux))]\nextend Epoll with Shape {}\ntotal<T: Shape>(x: T): int { return x.area(); }\n[Target(OS(Windows) && OS(Linux))]\nnative(): int { return total<Epoll>(Epoll()); }\nmain(): int { return total(Epoll()); }\n";
    assert_eq!(
        error_of("constraint_inferred_call_beside_platform_code", source),
        "main.pep:13:28: error: 'Epoll' does not conform to trait 'Shape', required by 'T' in 'total'\n\
         \x20  13 | main(): int { return total(Epoll()); }\n\
         \x20     |                            ^~~~~\n\
         main.pep:10:10: note: constraint declared here\n\
         \x20  10 | total<T: Shape>(x: T): int { return x.area(); }\n\
         \x20     |          ^~~~~\n\
         main.pep:4:8: note: declare it with 'extend Epoll with Shape'\n\
         \x20   4 | struct Epoll {\n\
         \x20     |        ^~~~~"
    );
}

#[test]
fn closure_in_static_method_uses_an_instance_member() {
    assert_eq!(
        error_of(
            "closure_in_static_uses_this",
            "struct S {\n    var n: int = 1;\n    construct(this.n = 1) {}\n    m(): int { return n; }\n    static a(): int {\n        var f = (): int => m();\n        return f();\n    }\n}\n\nmain(): int {\n    return S.a();\n}\n"
        ),
        "main.pep:6:28: error: a closure in a static method cannot use 'this' or an instance member of 'S': a static method has none\n\
         \x20   6 |         var f = (): int => m();\n\
         \x20     |                            ^"
    );
}

#[test]
fn closure_in_static_method_uses_this() {
    // `this` carries no location of its own: the closure is underlined.
    assert_eq!(
        error_of(
            "closure_in_static_uses_this_itself",
            "struct S {\n    var n: int = 1;\n    construct(this.n = 1) {}\n    static a(): int {\n        var f = (): int => this.n;\n        return f();\n    }\n}\n\nmain(): int {\n    return S.a();\n}\n"
        ),
        "main.pep:5:17: error: a closure in a static method cannot use 'this' or an instance member of 'S': a static method has none\n\
         \x20   5 |         var f = (): int => this.n;\n\
         \x20     |                 ^~~~~~~~~~~~~~~~~"
    );
}

/// A constrained parameter offers only what its constraints declare.
#[test]
fn constrained_parameter_has_no_such_method() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.perimeter(); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_has_no_such_method", source),
        "main.pep:5:45: error: no member named 'perimeter' in 'T'\n\
         \x20   5 | total<T: Shape>(item: T): int { return item.perimeter(); }\n\
         \x20     |                                             ^~~~~~~~~\n\
         main.pep:5:10: note: 'T' is constrained by 'Shape', which has no member 'perimeter'\n\
         \x20   5 | total<T: Shape>(item: T): int { return item.perimeter(); }\n\
         \x20     |          ^~~~~"
    );
}

/// A field is not something a trait declares.
#[test]
fn constrained_parameter_has_no_fields() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.radius; }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_has_no_fields", source),
        "main.pep:5:45: error: no member named 'radius' in 'T'\n\
         \x20   5 | total<T: Shape>(item: T): int { return item.radius; }\n\
         \x20     |                                             ^~~~~~\n\
         main.pep:5:10: note: 'T' is constrained by 'Shape', which has no member 'radius'\n\
         \x20   5 | total<T: Shape>(item: T): int { return item.radius; }\n\
         \x20     |          ^~~~~"
    );
}

/// A constrained type parameter cannot be constructed.
#[test]
fn constrained_parameter_has_no_constructor() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nmake<T: Shape>(item: T): T { return T(); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_has_no_constructor", source),
        "main.pep:5:37: error: cannot construct 'T': a constrained type parameter has no constructor\n\
         \x20   5 | make<T: Shape>(item: T): T { return T(); }\n\
         \x20     |                                     ^\n\
         main.pep:5:9: note: 'T' is constrained by 'Shape', which has no constructor\n\
         \x20   5 | make<T: Shape>(item: T): T { return T(); }\n\
         \x20     |         ^~~~~"
    );
}

/// A member two constraints declare is ambiguous.
#[test]
fn constrained_parameter_member_of_two_constraints() {
    let source = "trait Named {\n    name(): String;\n}\ntrait Titled {\n    name(): String;\n}\nlabel<T: Named & Titled>(item: T): String { return item.name(); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_member_of_two_constraints", source),
        "main.pep:7:57: error: 'name' is declared by both 'Named' and 'Titled'; call it through one of them\n\
         \x20   7 | label<T: Named & Titled>(item: T): String { return item.name(); }\n\
         \x20     |                                                         ^~~~\n\
         main.pep:7:10: note: 'T' is constrained here\n\
         \x20   7 | label<T: Named & Titled>(item: T): String { return item.name(); }\n\
         \x20     |          ^~~~~"
    );
}

/// A constraint's method takes the arguments it declares.
#[test]
fn constrained_parameter_call_with_too_many_arguments() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.scale(1, 2); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_call_with_too_many_arguments", source),
        "main.pep:5:45: error: too many arguments to 'scale': expected 1, have 2\n\
         \x20   5 | total<T: Shape>(item: T): int { return item.scale(1, 2); }\n\
         \x20     |                                             ^~~~~\n\
         main.pep:3:5: note: 'scale' declared here\n\
         \x20   3 |     scale(by: int): int;\n\
         \x20     |     ^~~~~"
    );
}

/// A constraint's method takes the argument types it declares.
#[test]
fn constrained_parameter_call_with_wrong_argument() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\ntotal<T: Shape>(item: T): int { return item.scale(\"twice\"); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_call_with_wrong_argument", source),
        "main.pep:5:51: error: cannot pass a value of type 'String' as argument 1 of 'scale', which has type 'int'\n\
         \x20   5 | total<T: Shape>(item: T): int { return item.scale(\"twice\"); }\n\
         \x20     |                                                   ^~~~~~~\n\
         main.pep:3:5: note: 'scale' declared here\n\
         \x20   3 |     scale(by: int): int;\n\
         \x20     |     ^~~~~"
    );
}

/// A constrained value converts only to its constraints' trait types.
#[test]
fn constrained_parameter_converts_only_to_its_constraints() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nstruct Circle {\n}\nkeep<T: Shape>(item: T): int {\n    var shape: Shape = item;\n    var circle: Circle = item;\n    return 0;\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_converts_only_to_its_constraints", source),
        "main.pep:9:26: error: cannot initialize variable 'circle' of type 'Circle' with a value of type 'T'\n\
         \x20   9 |     var circle: Circle = item;\n\
         \x20     |                          ^~~~\n\
         main.pep:7:9: note: 'T' converts only to its constraint 'Shape'\n\
         \x20   7 | keep<T: Shape>(item: T): int {\n\
         \x20     |         ^~~~~"
    );
}

/// An operator the constraints do not declare.
#[test]
fn constrained_parameter_operator_not_declared() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nsmaller<T: Shape>(a: T, b: T): bool { return a < b; }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_operator_not_declared", source),
        "main.pep:5:48: error: invalid operands to binary expression ('T' and 'T')\n\
         \x20   5 | smaller<T: Shape>(a: T, b: T): bool { return a < b; }\n\
         \x20     |                                                ^\n\
         main.pep:5:12: note: 'T' is constrained by 'Shape', which has no operator '<'\n\
         \x20   5 | smaller<T: Shape>(a: T, b: T): bool { return a < b; }\n\
         \x20     |            ^~~~~"
    );
}

/// Inside a constrained generic struct, checked without any specialization.
#[test]
fn constrained_parameter_in_struct_method() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nstruct Gallery<T: Shape> {\n    var items = Array<T>();\n    first(): int { return items[0].depth(); }\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_in_struct_method", source),
        "main.pep:7:36: error: no member named 'depth' in 'T'\n\
         \x20   7 |     first(): int { return items[0].depth(); }\n\
         \x20     |                                    ^~~~~\n\
         main.pep:5:19: note: 'T' is constrained by 'Shape', which has no member 'depth'\n\
         \x20   5 | struct Gallery<T: Shape> {\n\
         \x20     |                   ^~~~~"
    );
}

/// A static member through the parameter must be one a constraint declares.
#[test]
fn constrained_parameter_static_member() {
    let source = "trait Shape {\n    area(): int;\n    scale(by: int): int;\n}\nmake<T: Shape>(): T { return T.unit(); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_static_member", source),
        "main.pep:5:32: error: no member named 'unit' in 'T'\n\
         \x20   5 | make<T: Shape>(): T { return T.unit(); }\n\
         \x20     |                                ^~~~\n\
         main.pep:5:9: note: 'T' is constrained by 'Shape', which has no static member 'unit'\n\
         \x20   5 | make<T: Shape>(): T { return T.unit(); }\n\
         \x20     |         ^~~~~"
    );
}

/// A compound assignment is its own operator: '+' does not provide '+='.
#[test]
fn constrained_parameter_compound_operator_not_declared() {
    let source = "trait Addable {\n    +(other: this): this;\n}\ngrow<T: Addable>(a: T, b: T): T {\n    var total = a;\n    total += b;\n    return total;\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_parameter_compound_operator_not_declared", source),
        "main.pep:6:11: error: invalid operands to binary expression ('T' and 'T')\n\
         \x20   6 |     total += b;\n\
         \x20     |           ^~\n\
         main.pep:4:9: note: 'T' is constrained by 'Addable', which has no operator '+='\n\
         \x20   4 | grow<T: Addable>(a: T, b: T): T {\n\
         \x20     |         ^~~~~~~"
    );
}

/// A conditional conformance names the condition a type argument misses.
#[test]
fn conditional_conformance_not_met_by_argument() {
    let source = "trait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Shape> with Shape {\n    area(): int { return item.area() * 2; }\n}\ntotal<T: Shape>(item: T): int { return item.area(); }\nmain(): int { return total(Box<String>(\"x\")); }\n";
    assert_eq!(
        error_of("conditional_conformance_not_met_by_argument", source),
        "main.pep:19:28: error: 'Box<String>' does not conform to trait 'Shape', required by 'T' in 'total'\n\
         \x20  19 | main(): int { return total(Box<String>(\"x\")); }\n\
         \x20     |                            ^~~~~~~~~~~\n\
         main.pep:18:10: note: constraint declared here\n\
         \x20  18 | total<T: Shape>(item: T): int { return item.area(); }\n\
         \x20     |          ^~~~~\n\
         main.pep:15:15: note: 'Box<String>' conforms to 'Shape' only when 'String' conforms to 'Shape'\n\
         \x20  15 | extend Box<T: Shape> with Shape {\n\
         \x20     |               ^~~~~"
    );
}

/// Converting to the trait names the condition too.
#[test]
fn conditional_conformance_not_met_by_conversion() {
    let source = "trait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Shape> with Shape {\n    area(): int { return item.area() * 2; }\n}\nmain(): int {\n    Shape shape = Box<String>(\"x\");\n    return 0;\n}\n";
    assert_eq!(
        error_of("conditional_conformance_not_met_by_conversion", source),
        "main.pep:19:19: error: 'Box<String>' does not conform to trait 'Shape'\n\
         \x20  19 |     Shape shape = Box<String>(\"x\");\n\
         \x20     |                   ^~~~~~~~~~~\n\
         main.pep:15:15: note: 'Box<String>' conforms to 'Shape' only when 'String' conforms to 'Shape'\n\
         \x20  15 | extend Box<T: Shape> with Shape {\n\
         \x20     |               ^~~~~"
    );
}

/// Inside a constrained extension, the parameter offers its constraints.
#[test]
fn constrained_extension_body_checked() {
    let source = "trait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Named> {\n    shout(): String { return item.yell(); }\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_extension_body_checked", source),
        "main.pep:16:35: error: no member named 'yell' in 'T'\n\
         \x20  16 |     shout(): String { return item.yell(); }\n\
         \x20     |                                   ^~~~\n\
         main.pep:15:15: note: 'T' is constrained by 'Named', which has no member 'yell'\n\
         \x20  15 | extend Box<T: Named> {\n\
         \x20     |               ^~~~~"
    );
}

/// A constrained extension's member exists only where its constraint is met.
#[test]
fn constrained_extension_member_withheld() {
    let source = "trait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Named> {\n    label(): String { return item.name(); }\n}\nmain(): int {\n    var box = Box<Circle>(Circle());\n    box.label();\n    return 0;\n}\n";
    assert_eq!(
        error_of("constrained_extension_member_withheld", source),
        "main.pep:20:9: error: no member named 'label' in 'Box<Circle>'\n\
         \x20  20 |     box.label();\n\
         \x20     |         ^~~~~\n\
         main.pep:15:15: note: 'label' requires 'Circle' to conform to 'Named'\n\
         \x20  15 | extend Box<T: Named> {\n\
         \x20     |               ^~~~~"
    );
}

/// A conformance for every Box cannot rest on a member only some Boxes have.
#[test]
fn conformance_member_only_in_constrained_extension() {
    let source = "trait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Named> {\n    name(): String { return item.name(); }\n}\nextend Box<T> with Named {}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("conformance_member_only_in_constrained_extension", source),
        "main.pep:18:8: error: 'Box' conforms to 'Named' for every 'T', but its 'name' exists only when 'T' conforms to 'Named'\n\
         \x20  18 | extend Box<T> with Named {}\n\
         \x20     |        ^~~~~~\n\
         main.pep:15:15: note: constraint declared here\n\
         \x20  15 | extend Box<T: Named> {\n\
         \x20     |               ^~~~~\n\
         note: make the conformance conditional: 'extend Box<T: Named> with Named'"
    );
}

/// An extension's constraint naming nothing.
#[test]
fn constrained_extension_names_an_unknown_type() {
    let source = "trait Shape {\n    area(): int;\n}\ntrait Named {\n    name(): String;\n}\nstruct Circle {\n    area(): int { return 3; }\n}\nextend Circle with Shape {}\nstruct Box<T> {\n    var item: T;\n    construct(item: T) { this.item = item; }\n}\nextend Box<T: Nope> {\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("constrained_extension_names_an_unknown_type", source),
        "main.pep:15:15: error: unknown type name 'Nope'\n\
         \x20  15 | extend Box<T: Nope> {\n\
         \x20     |               ^~~~"
    );
}

/// `T: Shared` takes only thread-safe types; the note says why a struct is not one.
#[test]
fn shared_constraint_not_met_by_struct() {
    let source = "struct Plain {\n    var n: int;\n}\nkeep<T: Shared>(value: T): int { return 1; }\nmain(): int { return keep(Plain()); }\n";
    assert_eq!(
        error_of("shared_constraint_not_met_by_struct", source),
        "main.pep:5:27: error: 'Plain' does not conform to 'Shared', required by 'T' in 'keep'\n\
         \x20   5 | main(): int { return keep(Plain()); }\n\
         \x20     |                           ^~~~~\n\
         main.pep:4:9: note: constraint declared here\n\
         \x20   4 | keep<T: Shared>(value: T): int { return 1; }\n\
         \x20     |         ^~~~~~\n\
         main.pep:1:8: note: 'Plain' is not declared [Shared]\n\
         \x20   1 | struct Plain {\n\
         \x20     |        ^~~~~"
    );
}

/// A plain function type is not thread-safe; the note says to declare it shared.
#[test]
fn shared_constraint_not_met_by_function_type() {
    let source = "keep<T: Shared>(value: T): int { return 1; }\nf() {}\nmain(): int {\n    var g: () => void = f;\n    return keep(g);\n}\n";
    assert_eq!(
        error_of("shared_constraint_not_met_by_function_type", source),
        "main.pep:5:17: error: '() => void' does not conform to 'Shared', required by 'T' in 'keep'\n\
         \x20   5 |     return keep(g);\n\
         \x20     |                 ^\n\
         main.pep:1:9: note: constraint declared here\n\
         \x20   1 | keep<T: Shared>(value: T): int { return 1; }\n\
         \x20     |         ^~~~~~\n\
         note: declare the function type 'shared () => void' to share it between threads"
    );
}

/// A tuple is thread-safe when its elements are.
#[test]
fn shared_constraint_not_met_by_tuple_element() {
    let source = "struct Plain {\n    var n: int;\n}\nkeep<T: Shared>(value: T): int { return 1; }\nmain(): int { return keep((1, Plain())); }\n";
    assert_eq!(
        error_of("shared_constraint_not_met_by_tuple_element", source),
        "main.pep:5:27: error: '(int, Plain)' does not conform to 'Shared', required by 'T' in 'keep'\n\
         \x20   5 | main(): int { return keep((1, Plain())); }\n\
         \x20     |                           ^~~~~~~~~~~~\n\
         main.pep:4:9: note: constraint declared here\n\
         \x20   4 | keep<T: Shared>(value: T): int { return 1; }\n\
         \x20     |         ^~~~~~\n\
         main.pep:1:8: note: 'Plain' is not declared [Shared]\n\
         \x20   1 | struct Plain {\n\
         \x20     |        ^~~~~"
    );
}

/// A type parameter passed on to `T: Shared` must be constrained `Shared` itself.
#[test]
fn shared_constraint_not_met_by_parameter() {
    let source = "keep<T: Shared>(value: T): int { return 1; }\npass<T>(value: T): int { return keep<T>(value); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("shared_constraint_not_met_by_parameter", source),
        "main.pep:2:38: error: 'T' does not conform to 'Shared', required by 'T' in 'keep'\n\
         \x20   2 | pass<T>(value: T): int { return keep<T>(value); }\n\
         \x20     |                                      ^\n\
         \x20     |       : Shared\n\
         main.pep:1:9: note: constraint declared here\n\
         \x20   1 | keep<T: Shared>(value: T): int { return 1; }\n\
         \x20     |         ^~~~~~\n\
         main.pep:2:6: note: add a constraint to 'T': 'T: Shared'\n\
         \x20   2 | pass<T>(value: T): int { return keep<T>(value); }\n\
         \x20     |      ^"
    );
}

/// A trait value may hold any struct, so it is not thread-safe.
#[test]
fn shared_constraint_not_met_by_trait_value() {
    let source = "trait Shape {\n    area(): int;\n}\nkeep<T: Shared>(value: T): int { return 1; }\npass(s: Shape): int { return keep(s); }\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("shared_constraint_not_met_by_trait_value", source),
        "main.pep:5:35: error: 'Shape' does not conform to 'Shared', required by 'T' in 'keep'\n\
         \x20   5 | pass(s: Shape): int { return keep(s); }\n\
         \x20     |                                   ^\n\
         main.pep:4:9: note: constraint declared here\n\
         \x20   4 | keep<T: Shared>(value: T): int { return 1; }\n\
         \x20     |         ^~~~~~\n\
         note: a value of trait type 'Shape' may refer to any struct, which need not be thread-safe"
    );
}

/// `Shared` in a constraint is always the built-in, so no trait takes the name.
#[test]
fn shared_constraint_name_taken_by_a_trait() {
    let source = "trait Shared {\n    f(): int;\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("shared_constraint_name_taken_by_a_trait", source),
        "main.pep:1:7: error: trait 'Shared' takes the name of the built-in constraint 'Shared'; rename it\n\
         \x20   1 | trait Shared {\n\
         \x20     |       ^~~~~~"
    );
}

/// A number that declares a trait still is no trait value.
#[test]
fn value_type_is_never_a_trait_value() {
    let source = "trait Doubled {\n    doubled(): int;\n}\nextend int with Doubled {\n    doubled(): int { return this * 2; }\n}\nmain(): int {\n    Doubled d = 3;\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_type_is_never_a_trait_value", source),
        "main.pep:8:5: error: 'int' cannot be converted to trait 'Doubled': only structs and enums whose cases carry values can be trait values\n\
         \x20   8 |     Doubled d = 3;\n\
         \x20     |     ^~~~~~~\n\
         main.pep:4:8: note: 'int' conforms to 'Doubled' here, which makes it meet the constraint, not a trait value\n\
         \x20   4 | extend int with Doubled {\n\
         \x20     |        ^~~"
    );
}

/// A value type's conformance needs every member the trait has no default for.
#[test]
fn value_type_misses_a_trait_member() {
    let source = "trait Doubled {\n    doubled(): int;\n}\nextend int with Doubled {\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("value_type_misses_a_trait_member", source),
        "main.pep:4:8: error: 'int' does not implement 'doubled', required by trait 'Doubled'\n\
         \x20   4 | extend int with Doubled {\n\
         \x20     |        ^~~\n\
         main.pep:2:5: note: 'doubled' declared here\n\
         \x20   2 |     doubled(): int;\n\
         \x20     |     ^~~~~~~"
    );
}

/// An enum declares its methods inside it; an extension of one names a trait.
#[test]
fn enum_extension_without_a_trait() {
    let source = "enum Light {\n    Red,\n    Green,\n}\nextend Light {\n    f(): int { return 1; }\n}\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("enum_extension_without_a_trait", source),
        "main.pep:5:8: error: cannot extend enum 'Light' without a trait: declare its methods inside the enum\n\
         \x20   5 | extend Light {\n\
         \x20     |        ^~~~~"
    );
}

/// A number meets a constraint only by declaring the trait; the error is at the literal.
#[test]
fn value_type_does_not_conform() {
    let source = "trait Doubled {\n    doubled(): int;\n}\ntwice<T: Doubled>(x: T): int { return 0; }\nmain(): int { return twice(3); }\n";
    assert_eq!(
        error_of("value_type_does_not_conform", source),
        "main.pep:5:28: error: 'int' does not conform to trait 'Doubled', required by 'T' in 'twice'\n\
         \x20   5 | main(): int { return twice(3); }\n\
         \x20     |                            ^\n\
         main.pep:4:10: note: constraint declared here\n\
         \x20   4 | twice<T: Doubled>(x: T): int { return 0; }\n\
         \x20     |          ^~~~~~~\n\
         note: declare it with 'extend int with Doubled'"
    );
}

/// A generic method's constraint, reported at a literal argument.
#[test]
fn value_type_literal_argument_of_a_method() {
    let source = "trait Doubled {\n    doubled(): int;\n}\nstruct Canvas {\n    draw<T: Doubled>(x: T): int { return 1; }\n}\nmain(): int {\n    var c = Canvas();\n    return c.draw(-7);\n}\n";
    assert_eq!(
        error_of("value_type_literal_argument_of_a_method", source),
        "main.pep:9:19: error: 'int' does not conform to trait 'Doubled', required by 'T' in 'draw'\n\
         \x20   9 |     return c.draw(-7);\n\
         \x20     |                   ^~\n\
         main.pep:5:13: note: constraint declared here\n\
         \x20   5 |     draw<T: Doubled>(x: T): int { return 1; }\n\
         \x20     |             ^~~~~~~\n\
         note: declare it with 'extend int with Doubled'"
    );
}

// Value structs (`[Value]`): what needs an object, and changes a copy would lose.

#[test]
fn value_struct_compared_for_identity() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var a = Span();\n    var b = Span();\n    return a === b ? 1 : 0;\n}\n";
    assert_eq!(
        error_of("value_struct_compared_for_identity", source),
        "main.pep:16:14: error: 'Span' is a value struct and has no identity; use '==' to compare values\n\
         \x20  16 |     return a === b ? 1 : 0;\n\
         \x20     |              ^~~~~"
    );
}

#[test]
fn value_struct_compared_with_null() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var a = Span();\n    return a == __null ? 1 : 0;\n}\n";
    assert_eq!(
        error_of("value_struct_compared_with_null", source),
        "main.pep:15:14: error: value struct 'Span' cannot be null\n\
         \x20  15 |     return a == __null ? 1 : 0;\n\
         \x20     |              ^~~~~~~~~"
    );
}

#[test]
fn value_struct_held_weakly() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var w: __weak<Span>;\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_held_weakly", source),
        "main.pep:14:12: error: '__weak' needs a reference type; 'Span' is a value struct\n\
         \x20  14 |     var w: __weak<Span>;\n\
         \x20     |            ^~~~~~~~~~~~"
    );
}

#[test]
fn value_struct_refcount() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var a = Span();\n    return __refcount(a);\n}\n";
    assert_eq!(
        error_of("value_struct_refcount", source),
        "main.pep:15:23: error: 'Span' is a value struct and has no object\n\
         \x20  15 |     return __refcount(a);\n\
         \x20     |                       ^"
    );
}

#[test]
fn value_struct_contains_itself() {
    let source = "[Value]\nstruct A {\n    var b: B;\n}\n\n[Value]\nstruct B {\n    var a: A;\n}\n\nmain(): int {\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_contains_itself", source),
        "main.pep:3:12: error: value struct 'A' contains itself through field 'b'\n\
         \x20   3 |     var b: B;\n\
         \x20     |            ^\n\
         main.pep:8:12: note: which holds field 'a' of type 'A'\n\
         \x20   8 |     var a: A;\n\
         \x20     |            ^"
    );
}

#[test]
fn value_struct_destructor() {
    let source = "[Value]\nstruct S {\n    var x: int;\n\n    destruct {}\n}\n\nmain(): int {\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_destructor", source),
        "main.pep:5:5: error: value struct 'S' cannot have a destructor\n\
         \x20   5 |     destruct {}\n\
         \x20     |     ^~~~~~~~"
    );
}

#[test]
fn value_struct_shared() {
    let source = "[Value]\n[Shared]\nstruct S {\n    const x: int;\n}\n\nmain(): int {\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_shared", source),
        "main.pep:2:1: error: '[Shared]' does not apply to value struct 'S': it is thread-safe when its fields are\n\
         \x20   2 | [Shared]\n\
         \x20     | ^~~~~~~~"
    );
}

#[test]
fn value_struct_passed_to_c() {
    let source = "[Value]\nstruct S {\n    var x: int;\n}\n\nextern int f(S s);\n\nmain(): int {\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_passed_to_c", source),
        "main.pep:6:14: error: value struct 'S' cannot be passed to C; pass a pointer\n\
         \x20   6 | extern int f(S s);\n\
         \x20     |              ^"
    );
}

#[test]
fn value_struct_temporary_field_assigned() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    var spans = Array<Span>();\n    spans.append(Span());\n    spans[0].end = 3;\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_temporary_field_assigned", source),
        "main.pep:16:14: error: cannot assign to field 'end' of a temporary 'Span'\n\
         \x20  16 |     spans[0].end = 3;\n\
         \x20     |              ^~~\n\
         main.pep:16:5: note: '[]' returns a copy; store it in a variable, change it, and assign it back\n\
         \x20  16 |     spans[0].end = 3;\n\
         \x20     |     ^~~~~~~~"
    );
}

#[test]
fn value_struct_const_field_assigned() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    const s = Span(1, 2);\n    s.end = 3;\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_const_field_assigned", source),
        "main.pep:15:7: error: cannot assign to field 'end' of const variable 's'\n\
         \x20  15 |     s.end = 3;\n\
         \x20     |       ^~~\n\
         main.pep:14:11: note: 's' declared const here\n\
         \x20  14 |     const s = Span(1, 2);\n\
         \x20     |           ^"
    );
}

#[test]
fn value_struct_mutating_method_on_temporary() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmake(): Span {\n    return Span(1, 2);\n}\n\nmain(): int {\n    make().grow(1);\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_mutating_method_on_temporary", source),
        "main.pep:18:12: error: cannot call mutating method 'grow' on a temporary 'Span'\n\
         \x20  18 |     make().grow(1);\n\
         \x20     |            ^~~~\n\
         main.pep:18:5: note: 'make' returns a copy; store it in a variable, change it, and assign it back\n\
         \x20  18 |     make().grow(1);\n\
         \x20     |     ^~~~\n\
         main.pep:9:9: note: 'grow' changes 'this' here\n\
         \x20   9 |         end = end + by;\n\
         \x20     |         ^~~"
    );
}

#[test]
fn value_struct_mutating_method_on_const() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    construct(this.start = 0, this.end = 0) {}\n\n    grow(by: int) {\n        end = end + by;\n    }\n}\n\nmain(): int {\n    const s = Span(1, 2);\n    s.grow(1);\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_mutating_method_on_const", source),
        "main.pep:15:7: error: cannot call mutating method 'grow' on const variable 's'\n\
         \x20  15 |     s.grow(1);\n\
         \x20     |       ^~~~\n\
         main.pep:14:11: note: 's' declared const here\n\
         \x20  14 |     const s = Span(1, 2);\n\
         \x20     |           ^\n\
         main.pep:9:9: note: 'grow' changes 'this' here\n\
         \x20   9 |         end = end + by;\n\
         \x20     |         ^~~"
    );
}

#[test]
fn value_struct_this_changed_in_closure() {
    let source = "[Value]\nstruct Span {\n    var start: int;\n    var end: int;\n\n    later(): () => void {\n        return () => { end = 5; };\n    }\n}\n\nmain(): int {\n    return 0;\n}\n";
    assert_eq!(
        error_of("value_struct_this_changed_in_closure", source),
        "main.pep:7:24: error: cannot change 'this' in a closure: the closure holds a copy of 'Span'\n\
         \x20   7 |         return () => { end = 5; };\n\
         \x20     |                        ^~~"
    );
}

#[test]
fn value_iterator_looped_over_as_const() {
    let source = "main(): int {\n    var values = Array<int>();\n    const it = values.iterate();\n    for (var x in it) {\n        return x;\n    }\n    return 0;\n}\n";
    let error = error_of("value_iterator_looped_over_as_const", source);
    assert!(
        error.starts_with(
            "main.pep:4:19: error: cannot call mutating method 'next' on const variable 'it'\n\
             \x20   4 |     for (var x in it) {\n\
             \x20     |                   ^~\n\
             main.pep:3:11: note: 'it' declared const here\n"
        ),
        "{}",
        error
    );
}

/// A generic whose instance asks for a larger instance of itself (#236).
#[test]
fn a_generic_that_asks_for_a_larger_instance_of_itself_stops_at_the_depth_limit() {
    let source = "struct Foo<T> {\n    var inner: Foo<Array<T>>;\n}\n\nmain(): int {\n    var f = Foo<int>();\n    return 0;\n}\n";
    let error = error_of("specialization_depth", source);
    let lines: Vec<&str> = error.lines().collect();
    assert_eq!(
        lines[0],
        "main.pep:2:16: error: 'Foo' is specialized 65 levels deep, past the limit of 64; a generic whose instance asks for a larger instance of itself never ends",
        "{error}"
    );
    assert_eq!(lines[1], "    2 |     var inner: Foo<Array<T>>;", "{error}");
    assert_eq!(lines[2], "      |                ^~~~~~~~~~~~~", "{error}");
    assert_eq!(lines[3], "main.pep:6:13: note: asked for by 'main' here", "{error}");
}

#[test]
fn range_of_a_non_integer() {
    assert_eq!(
        error_of("range_of_a_non_integer", "main(): int {\n    for (var c in \"a\"..\"z\") {\n    }\n    return 0;\n}\n"),
        "main.pep:2:22: error: range bounds must be integers, not 'String'\n\
         \x20   2 |     for (var c in \"a\"..\"z\") {\n\
         \x20     |                      ^~"
    );
}

// ── Hash keys whose == and hash<T> disagree ─────────────────────────────────

#[test]
fn hash_key_with_equality_but_no_hash_is_an_error_at_the_operator() {
    let source = "struct Point {\n    int x;\n    ==(other: Point): bool { return x == other.x; }\n}\n\
                  test(): int {\n    var seen = HashSet<Point>();\n    return seen.count;\n}\n";
    assert_eq!(
        error_of("hash_key_equality", source),
        "main.pep:3:5: error: 'Point' declares '==' but no 'hash<Point>', so as a HashMap or HashSet key, equal values will not find each other\n\
         \x20   3 |     ==(other: Point): bool { return x == other.x; }\n\
         \x20     |     ^~\n\
         note: declare 'hash<Point>(value: Point): u64' hashing the fields '==' compares"
    );
}

#[test]
fn hash_key_with_hash_but_no_equality_is_an_error_at_the_override() {
    let source = "struct Node {\n    int id;\n}\n\
                  hash<Node>(value: Node): u64 { return hash<int>(value.id); }\n\
                  test(): int {\n    var seen = HashMap<Node, int>();\n    return seen.count;\n}\n";
    assert_eq!(
        error_of("hash_key_hash", source),
        "main.pep:4:1: error: 'hash<Node>' is overridden but 'Node' declares no '==', so HashMap and HashSet keys still compare by identity\n\
         \x20   4 | hash<Node>(value: Node): u64 { return hash<int>(value.id); }\n\
         \x20     | ^~~~\n\
         main.pep:1:8: note: declare '==(other: Node): bool' comparing the fields the hash uses\n\
         \x20   1 | struct Node {\n\
         \x20     |        ^~~~"
    );
}

#[test]
fn hash_keys_with_both_halves_or_neither_compile_cleanly() {
    let source = "struct Point {\n    int x;\n    ==(other: Point): bool { return x == other.x; }\n}\n\
                  hash<Point>(value: Point): u64 { return hash<int>(value.x); }\n\
                  struct Node {\n    int id;\n}\n\
                  [Value]\nstruct Cell {\n    int row;\n}\n\
                  test(): int {\n    var a = HashSet<Point>();\n    var b = HashSet<Node>();\n    var c = HashSet<Cell>();\n    return a.count + b.count + c.count;\n}\n";
    assert_eq!(warnings_of(source), "");
}

// Properties (`docs/src/language/properties.md`).

#[test]
fn assigning_a_get_only_property_points_at_the_property() {
    assert_eq!(
        error_of("get_only_property", "struct A {\n    var balance: long { get; }\n}\nmain(): int {\n    var a = A();\n    a.balance = 3;\n    return 0;\n}\n"),
        "main.pep:6:7: error: cannot assign to 'balance': it has no 'set' accessor\n\
         \x20   6 |     a.balance = 3;\n\
         \x20     |       ^~~~~~~\n\
         main.pep:2:9: note: 'balance' declared here\n\
         \x20   2 |     var balance: long { get; }\n\
         \x20     |         ^~~~~~~"
    );
}

#[test]
fn a_set_only_property_points_at_its_set() {
    assert_eq!(
        error_of("set_only_property", "struct A {\n    var x: int { set; }\n}\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:2:18: error: property 'x' has no 'get' accessor; a property must have one\n\
         \x20   2 |     var x: int { set; }\n\
         \x20     |                  ^~~"
    );
}

#[test]
fn a_shared_struct_property_with_set_points_at_the_set() {
    assert_eq!(
        error_of("shared_property", "[Shared]\nstruct A {\n    var x: int { get; set; }\n}\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:3:23: error: property 'x' of a '[Shared]' struct cannot have a 'set' accessor: its storage is 'const'\n\
         \x20   3 |     var x: int { get; set; }\n\
         \x20     |                       ^~~\n\
         main.pep:1:1: note: '[Shared]' declared here\n\
         \x20   1 | [Shared]\n\
         \x20     | ^~~~~~~~"
    );
}

#[test]
fn an_extension_property_with_storage_points_at_its_name() {
    assert_eq!(
        error_of("ext_property", "struct A {\n    var x: int;\n}\nextend A {\n    var y: int { get; }\n}\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:5:9: error: an extension cannot add storage: property 'y' must be computed, with accessor bodies that do not use 'field'\n\
         \x20   5 |     var y: int { get; }\n\
         \x20     |         ^"
    );
}

#[test]
fn a_missing_trait_property_points_at_the_extension() {
    assert_eq!(
        error_of("trait_property", "trait T {\n    var label: String { get; }\n}\nstruct D {\n    var x: int;\n}\nextend D with T;\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:7:8: error: 'D' does not implement property 'label', required by trait 'T'\n\
         \x20   7 | extend D with T;\n\
         \x20     |        ^\n\
         main.pep:2:9: note: 'label' declared here\n\
         \x20   2 |     var label: String { get; }\n\
         \x20     |         ^~~~~"
    );
}

#[test]
fn a_property_initializer_before_its_accessors_points_at_it() {
    assert_eq!(
        error_of("init_property", "struct A {\n    var x: int = 3 { get; }\n}\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:2:18: error: the initializer of property 'x' goes after its accessors\n\
         \x20   2 |     var x: int = 3 { get; }\n\
         \x20     |                  ^"
    );
}

#[test]
fn calling_a_property_points_at_its_name() {
    let error = error_of("property_call", "main(): int {\n    var a = Array<int>();\n    return a.count() as int;\n}\n");
    assert!(
        error.starts_with(
            "main.pep:3:14: error: 'count' is a property, not a method; read it without '()'\n\
             \x20   3 |     return a.count() as int;\n\
             \x20     |              ^~~~~\n"
        ),
        "{}",
        error
    );
    assert!(error.replace('\\', "/").contains("runtime/array.pep:"), "{}", error);
}

#[test]
fn unknown_named_argument() {
    let source = "f(a: int, width: int = 3): int { return a + width; }\nmain(): int {\n    return f(1, widht = 2);\n}\n";
    assert_eq!(
        error_of("unknown_named_argument", source),
        "main.pep:3:17: error: no parameter named 'widht' in 'f'; did you mean 'width'?\n\
         \x20   3 |     return f(1, widht = 2);\n\
         \x20     |                 ^~~~~\n\
         main.pep:1:1: note: declared here\n\
         \x20   1 | f(a: int, width: int = 3): int { return a + width; }\n\
         \x20     | ^"
    );
}

#[test]
fn positional_after_named_argument() {
    let source = "f(a: int, b: int): int { return a + b; }\nmain(): int {\n    return f(a = 1, 2);\n}\n";
    assert_eq!(
        error_of("positional_after_named_argument", source),
        "main.pep:3:21: error: positional argument cannot follow a named argument\n\
         \x20   3 |     return f(a = 1, 2);\n\
         \x20     |                     ^\n\
         main.pep:3:14: note: first named argument here\n\
         \x20   3 |     return f(a = 1, 2);\n\
         \x20     |              ^"
    );
}

#[test]
fn link_name_was_removed() {
    let source = "[LinkName(\"llabs\")]\nextern long pep_abs(long v);\nmain(): int { return 0; }\n";
    assert_eq!(
        error_of("link_name_was_removed", source),
        "main.pep:1:1: error: 'LinkName' was removed; use '[Link(name = \"llabs\")]'\n\
         \x20   1 | [LinkName(\"llabs\")]\n\
         \x20     | ^~~~~~~~~~~~~~~~~~~\n\
         \x20     | [Link(name = \"llabs\")]"
    );
}

#[test]
fn trait_method_with_other_parameter_names_warns_with_a_rename() {
    let source = "trait Shape {\n    area(scale: int): int;\n}\n\
                  struct Square {\n    var side: int;\n    area(factor: int): int { return side * factor; }\n}\n\
                  extend Square with Shape;\n\
                  test(): int {\n    var s = Square();\n    s.side = 6;\n    return s.area(7);\n}\n";
    let mut module = compiled(source);
    assert_eq!(
        module.render_warnings(),
        "main.pep:6:10: warning: parameter 'factor' of 'area' is named 'scale' in trait 'Shape'\n\
         \x20   6 |     area(factor: int): int { return side * factor; }\n\
         \x20     |          ^~~~~~\n\
         main.pep:2:5: note: 'area' declared here\n\
         \x20   2 |     area(scale: int): int;\n\
         \x20     |     ^~~~"
    );
    let [warning] = module.warnings.as_slice() else { panic!("{:?}", module.warnings) };
    assert_eq!(warning.fixes[0].message, "rename 'factor' to 'scale'");
    // The parameter and its use in the body.
    let edits: Vec<(&str, &str)> =
        warning.fixes[0].edits.iter().map(|e| (&source[e.loc.span.start..e.loc.span.end], e.replacement.as_str())).collect();
    assert_eq!(edits, [("factor", "scale"), ("factor", "scale")]);

    let ctx = inkwell::context::Context::create();
    assert_eq!(CodeGenerator::new(&ctx, "main").jit_execute(&mut module, "test").expect("jit"), 42);
}

#[test]
fn reflect_fields_outside_the_declaring_file() {
    let others = [("shapes.pep", "export struct Account {\n    var owner: String;\n    var _balance: int;\n}\n")];
    assert_eq!(
        error_of_files(
            "reflect_fields",
            "import \"shapes\";\n\nmain(): int {\n    static {\n        for (var f in reflect.fields<Account>()) {\n        }\n    }\n    return 0;\n}\n",
            &others
        ),
        "main.pep:5:31: error: 'fields' of 'Account' is only available in the file that declares 'Account'; use 'properties'\n\
         \x20   5 |         for (var f in reflect.fields<Account>()) {\n\
         \x20     |                               ^~~~~~\n\
         shapes.pep:1:15: note: 'Account' declared here\n\
         \x20   1 | export struct Account {\n\
         \x20     |               ^~~~~~~\n\
         main.pep:3:1: note: in the static block of 'main'\n\
         \x20   3 | main(): int {\n\
         \x20     | ^~~~"
    );
}

#[test]
fn unknown_attribute_on_a_field() {
    assert_eq!(
        error_of("unknown_attribute", "struct P {\n    [Nmae(\"x\")]\n    var x: int;\n}\n\nmain(): int {\n    return 0;\n}\n"),
        "main.pep:2:6: error: unknown attribute 'Nmae'\n\
         \x20   2 |     [Nmae(\"x\")]\n\
         \x20     |      ^~~~"
    );
}

#[test]
fn static_block_runtime_value_not_captured() {
    assert_eq!(
        error_of(
            "static_capture",
            "struct P {\n    var x: int;\n}\n\nmain(): int {\n    var n = 0;\n    static {\n        for (var f in reflect.properties<P>()) {\n            n += 1;\n        }\n    }\n    return n;\n}\n"
        ),
        "main.pep:9:13: error: 'n' is a runtime value; add it to the static block's capture list\n\
         \x20   9 |             n += 1;\n\
         \x20     |             ^\n\
         main.pep:8:23: note: in pass 1 of 1 (member 'x')\n\
         \x20   8 |         for (var f in reflect.properties<P>()) {\n\
         \x20     |                       ^~~~~~~~~~~~~~~~~~~~~~~\n\
         main.pep:5:1: note: in the static block of 'main'\n\
         \x20   5 | main(): int {\n\
         \x20     | ^~~~"
    );
}

#[test]
fn cast_that_reinterprets_needs_unsafe_cast() {
    // `as` is a static cast: a pointer to an integer reinterprets, so the
    // error is at the `as` and names `unsafe_cast`.
    assert_eq!(
        error_of(
            "cast_pointer_to_integer",
            "main(): int {\n    var p = __null as __ptr<int>;\n    var a = p as ulong;\n    return 0;\n}\n"
        ),
        "main.pep:3:15: error: cannot cast '__ptr<int>' to 'ulong' with 'as'; use 'unsafe_cast<ulong>(...)' to reinterpret\n\
         \x20   3 |     var a = p as ulong;\n\
         \x20     |               ^~"
    );
    assert_eq!(
        error_of(
            "cast_pointer_to_pointer",
            "main(): int {\n    var p = __null as __ptr<int>;\n    var b = p as __ptr<u16>;\n    return 0;\n}\n"
        ),
        "main.pep:3:15: error: cannot cast '__ptr<int>' to '__ptr<ushort>' with 'as'; use 'unsafe_cast<__ptr<ushort>>(...)' to reinterpret\n\
         \x20   3 |     var b = p as __ptr<u16>;\n\
         \x20     |               ^~"
    );
}

#[test]
fn cast_of_a_struct_to_a_pointer() {
    assert_eq!(
        error_of(
            "cast_struct_to_pointer",
            "struct Dog {\n    construct() {}\n}\nmain(): int {\n    var d = Dog();\n    var p = d as __ptr<void>;\n    return 0;\n}\n"
        ),
        "main.pep:6:15: error: cannot cast 'Dog' to '__ptr<void>'\n\
         \x20   6 |     var p = d as __ptr<void>;\n\
         \x20     |               ^~"
    );
}

#[test]
fn unsafe_cast_never_reinterprets_a_reference() {
    assert_eq!(
        error_of(
            "unsafe_cast_struct",
            "struct Dog {\n    construct() {}\n}\nmain(): int {\n    var d = Dog();\n    var p = unsafe_cast<__ptr<void>>(d);\n    return 0;\n}\n"
        ),
        "main.pep:6:13: error: 'unsafe_cast' cannot convert 'Dog' to '__ptr<void>': it reinterprets only pointers and numbers\n\
         \x20   6 |     var p = unsafe_cast<__ptr<void>>(d);\n\
         \x20     |             ^~~~~~~~~~~"
    );
}

#[test]
fn unsafe_cast_of_numbers_of_different_widths() {
    assert_eq!(
        error_of("unsafe_cast_widths", "main(): int {\n    var n = 3;\n    var w = unsafe_cast<long>(n);\n    return 0;\n}\n"),
        "main.pep:3:13: error: 'unsafe_cast' cannot convert 'int' to 'long': the sizes differ; use 'as' to convert the value\n\
         \x20   3 |     var w = unsafe_cast<long>(n);\n\
         \x20     |             ^~~~~~~~~~~"
    );
}

#[test]
fn unsafe_cast_arguments() {
    let error = |test: &str, call: &str| error_of(test, &format!("main(): int {{\n    var x = {};\n    return 0;\n}}\n", call));
    assert_eq!(
        error("unsafe_cast_no_type", "unsafe_cast(3)"),
        "main.pep:2:13: error: 'unsafe_cast' needs the type to cast to: 'unsafe_cast<T>(value)'\n\
         \x20   2 |     var x = unsafe_cast(3);\n\
         \x20     |             ^~~~~~~~~~~"
    );
    assert_eq!(
        error("unsafe_cast_two_types", "unsafe_cast<int, int>(3)"),
        "main.pep:2:13: error: 'unsafe_cast' takes 1 type argument, have 2\n\
         \x20   2 |     var x = unsafe_cast<int, int>(3);\n\
         \x20     |             ^~~~~~~~~~~"
    );
    assert_eq!(
        error("unsafe_cast_two_values", "unsafe_cast<int>(3, 4)"),
        "main.pep:2:13: error: too many arguments to 'unsafe_cast': expected 1, have 2\n\
         \x20   2 |     var x = unsafe_cast<int>(3, 4);\n\
         \x20     |             ^~~~~~~~~~~"
    );
}

#[test]
fn enum_method_read_without_a_call() {
    let error = |test: &str, body: &str| error_of(test, &format!("enum L {{ A, B }}\nmain(): int {{\n    {}\n    return 0;\n}}\n", body));
    assert_eq!(
        error("enum_method_read", "print(L.A.name);"),
        "main.pep:3:15: error: 'name' is a method of 'L': call it as 'name()'\n\
         \x20   3 |     print(L.A.name);\n\
         \x20     |               ^~~~"
    );
    assert_eq!(
        error("enum_static_method_read", "var f = L.from_value;"),
        "main.pep:3:15: error: 'from_value' is a method of 'L': call it as 'L.from_value(...)'\n\
         \x20   3 |     var f = L.from_value;\n\
         \x20     |               ^~~~~~~~~~"
    );
}

#[test]
fn bound_method_passed_as_a_value() {
    // A reference enum's `name` is a struct method: `r.name` is a bound
    // method, which is not a `String`.
    assert_eq!(
        error_of("reference_enum_method_read", "enum R { A(x: int), B }\nmain(): int {\n    var r = R.A(1);\n    print(r.name);\n    return 0;\n}\n"),
        "main.pep:4:13: error: cannot pass a value of type '() => String' as argument 1 of 'print', which has type 'String'; call it with '()'\n\
         \x20   4 |     print(r.name);\n\
         \x20     |             ^~~~"
    );
    assert_eq!(
        error_of("bound_method_into_int", "struct S {\n    m(x: int): int { return x; }\n}\nmain(): int {\n    var s = S();\n    var n: int = s.m;\n    return 0;\n}\n"),
        "main.pep:6:20: error: cannot initialize variable 'n' of type 'int' with a value of type '(int) => int'\n\
         \x20   6 |     var n: int = s.m;\n\
         \x20     |                    ^"
    );
}

#[test]
fn constant_overflow_is_an_error_at_the_operator() {
    assert_eq!(
        error_of("constant_overflow", "main(): int {\n    var seconds = 100000 * 100000;\n    return 0;\n}\n"),
        "main.pep:2:26: error: integer overflow in 'int' multiplication\n\
         \x20   2 |     var seconds = 100000 * 100000;\n\
         \x20     |                          ^"
    );
}

#[test]
fn constant_division_by_zero_is_an_error_at_the_operator() {
    assert_eq!(
        error_of("constant_division_by_zero", "main(): int {\n    var x = 10;\n    x %= 0;\n    return x;\n}\n"),
        "main.pep:3:7: error: division by zero\n\
         \x20   3 |     x %= 0;\n\
         \x20     |       ^~"
    );
}

#[test]
fn propagation_needs_a_result_function() {
    // At the `?`, with a note at the function that does not return a Result.
    let source = "parse(): Result<int> {\n    return Result<int>.ok(1);\n}\nmain(): int {\n    return parse()?;\n}\n";
    assert_eq!(
        error_of("propagation_function", source),
        "main.pep:5:19: error: '?' requires the enclosing function to return a Result\n\
         \x20   5 |     return parse()?;\n\
         \x20     |                   ^\n\
         main.pep:4:1: note: 'main' returns 'int'\n\
         \x20   4 | main(): int {\n\
         \x20     | ^~~~"
    );
}

#[test]
fn propagation_after_a_call() {
    // The `?` would run before the call to its left, which the note shows.
    let source = "parse(): Result<int> {\n    return Result<int>.ok(1);\n}\nf(): Result<int> {\n    return Result<int>.ok(parse().value() + parse()?);\n}\nmain(): int {\n    return 0;\n}\n";
    assert_eq!(
        error_of("propagation_order", source),
        "main.pep:5:52: error: '?' cannot follow a call in the same statement\n\
         \x20   5 |     return Result<int>.ok(parse().value() + parse()?);\n\
         \x20     |                                                    ^\n\
         main.pep:5:35: note: the '?' would run before this call; call it in a statement of its own\n\
         \x20   5 |     return Result<int>.ok(parse().value() + parse()?);\n\
         \x20     |                                   ^~~~~"
    );
}

#[test]
fn power_of_a_pointer_names_the_operand_types() {
    assert_eq!(
        error_of("power_pointer", "main(): int {\n    var p: __ptr<int> = __null;\n    var q = p ** 2;\n    return 0;\n}\n"),
        "main.pep:3:15: error: invalid operands to binary expression ('__ptr<int>' and 'int')\n\
         \x20   3 |     var q = p ** 2;\n\
         \x20     |               ^~"
    );
}

#[test]
fn number_extension_operator_must_not_take_a_number() {
    assert_eq!(
        error_of("number_operator_number", "extend int {\n    +(other: int): int { return 0; }\n}\nmain(): int { return 0; }\n"),
        "main.pep:2:14: error: operator '+' of 'int' cannot take an operand of type 'int': the built-in operator applies\n\
         \x20   2 |     +(other: int): int { return 0; }\n\
         \x20     |              ^~~"
    );
}

#[test]
fn number_extension_operator_takes_one_operand() {
    assert_eq!(
        error_of("number_operator_unary", "extend double {\n    -(): double { return 0.0; }\n}\nmain(): int { return 0; }\n"),
        "main.pep:2:5: error: operator '-' in an extension of 'double' must take one operand: the 'double' is the left operand\n\
         \x20   2 |     -(): double { return 0.0; }\n\
         \x20     |     ^"
    );
}

#[test]
fn number_on_the_left_without_an_extension_operator() {
    assert_eq!(
        error_of("number_operator_missing", "struct V {\n    var x: int = 0;\n}\nmain(): int {\n    var w = 2 * V();\n    return 0;\n}\n"),
        "main.pep:5:15: error: invalid operands to binary expression ('int' and 'V')\n\
         \x20   5 |     var w = 2 * V();\n\
         \x20     |               ^"
    );
}

#[test]
fn extern_overloaded_by_another_extern() {
    assert_eq!(
        error_of("overload_two_externs", "extern int abs(int x);\n[Link(name = \"llabs\")]\nextern long abs(long x);\nmain(): int { return 0; }\n"),
        "main.pep:3:13: error: extern 'abs' cannot be overloaded; rename it and overload Pepper functions named 'abs' that call it\n\
         \x20   3 | extern long abs(long x);\n\
         \x20     |             ^~~\n\
         main.pep:1:12: note: previous declaration is here\n\
         \x20   1 | extern int abs(int x);\n\
         \x20     |            ^~~"
    );
}
