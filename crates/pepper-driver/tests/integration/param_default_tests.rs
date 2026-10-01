//! A `String` parameter's literal default (`construct(String name = "")`) is a
//! String at every call site that omits the argument. Defaults were not
//! visited by convert_string_literals, so an omitted argument passed the raw
//! `char*` global where a String reference was expected, and the callee's
//! first refcount operation on it crashed.

use crate::support::compile_jit_with_runtime;

#[test]
fn string_literal_defaults() {
    let source = r#"
struct Named {
    String name;
    construct(String n = "anon") { name = n; }
    String greet(String prefix = "hi ") { return prefix + name; }
}
label(String s = ""): int { return s.size(); }
test(): int {
    var a = Named();                     # ctor default
    if (!(a.name == "anon")) { return 1; }
    if (!(a.greet() == "hi anon")) { return 2; }   # method default
    if (label() != 0) { return 3; }                # empty default
    if (label("xyz") != 3) { return 4; }
    if (!(Named("b").greet("yo ") == "yo b")) { return 5; }
    return 0;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}
