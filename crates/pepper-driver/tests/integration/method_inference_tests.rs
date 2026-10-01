//! Implicit types (`var x = ...`) inside struct methods: a method body may
//! call another struct's methods and constructors, and a bare call naming one
//! of the struct's own methods is that method even when a free function or
//! extern of the same name exists (class scope before file scope). Before the
//! fix a method body only saw its own struct's table, so such locals fell
//! back to `i32`, and a method `read` typed as the extern `read`.

use pepper_codegen::CodeGenerator;

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn locals_from_other_structs_in_a_method() {
    let source = r#"
struct Node {
    String name;
    construct(String n = "") { name = n; }
    Node child(String n) { return Node(n); }
}
struct Walker {
    int run(Node root) {
        var c = root.child("abc");       # another struct's method
        var fresh = Node("de");          # another struct's constructor
        var list = Array<Node>();        # a generic constructor
        list.append(c);
        list.append(fresh);
        return list[0].name.size() * 10 + list[1].name.size();
    }
}
test(): int {
    var w = Walker();
    return w.run(Node("r")) - 32;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

#[test]
fn own_method_shadows_free_function() {
    let source = r#"
pick(): long { return 7; }
struct Box {
    String s;
    String pick() { return s; }
    int size_of_pick() {
        var v = pick();                  # Box.pick, a String, not ::pick
        return v.size();
    }
}
test(): int {
    var b = Box();
    b.s = "four";
    return b.size_of_pick() - 4;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}

/// An operator on a bare call to one of the struct's own methods resolves
/// like one on `this.m()`: the implicit receiver was an untyped `this`
/// symbol, so `label() + label()` stayed a raw `+` and codegen failed with
/// "unsupported op Add" (#243).
#[test]
fn operator_on_an_implicit_this_call() {
    let source = r#"
struct Box {
    int value;
    construct(int value) { this.value = value; }
    String label() { return "x"; }
    String twice() { return label() + label(); }
    bool same() { return label() == label(); }
    Box doubled() { return Box(value * 2); }
    int sum() { return doubled().value + doubled().value; }
}
test(): int {
    var b = Box(3);
    if (b.twice() != "xx") { return 1; }
    if (!b.same()) { return 2; }
    return b.sum() - 12;
}
"#;
    assert_eq!(compile_jit_with_runtime(source), 0);
}
