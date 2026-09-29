//! Implicit types (`var x = ...`) inside struct methods: a method body may
//! call another struct's methods and constructors, and a bare call naming one
//! of the struct's own methods is that method even when a free function or
//! extern of the same name exists (class scope before file scope). Before the
//! fix a method body only saw its own struct's table, so such locals fell
//! back to `i32`, and a method `read` typed as the extern `read`.

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

fn compile_jit_with_runtime(source: &str) -> i32 {
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
    pepper_driver::compiler::check_with_runtime("test.pep", source).expect("visibility");
    module.merge(build(&ast).expect("build"));
    pepper_sema::apply_platform_filters(&mut module).expect("platform");
    struct_body::apply(&mut module).expect("sema");
    transform_pass(&mut module);
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn locals_from_other_structs_in_a_method() {
    let source = r#"
struct Node {
    String name;
    new(String n = "") { name = n; }
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
