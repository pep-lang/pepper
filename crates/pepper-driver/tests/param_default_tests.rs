//! A `String` parameter's literal default (`new(String name = "")`) is a
//! String at every call site that omits the argument. Defaults were not
//! visited by convert_string_literals, so an omitted argument passed the raw
//! `char*` global where a String reference was expected, and the callee's
//! first refcount operation on it crashed.

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
fn string_literal_defaults() {
    let source = r#"
struct Named {
    String name;
    new(String n = "anon") { name = n; }
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
