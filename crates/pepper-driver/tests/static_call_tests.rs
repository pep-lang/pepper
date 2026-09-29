//! Static method calls on a bare struct name (`File.open(p)`), from a free
//! function and from another struct's method. Generic receivers
//! (`Result<int>.ok(1)`) and aliases already went through a ctor-style
//! receiver; a plain name reached codegen as an unknown symbol, and inside a
//! method it panicked in convert_member_refs as an unresolved field.

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
    transform_pass(&mut module).expect("sema");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

const MAKER: &str = r#"
struct Maker {
    int x;
    static Maker make(int x) {
        var m = Maker();
        m.x = x;
        return m;
    }
    static int twice(int v) { return v * 2; }
}
"#;

#[test]
fn static_call_on_struct_name_from_free_function() {
    let source = format!(
        "{MAKER}
test(): int {{
    var m = Maker.make(20);
    return m.x + Maker.twice(1) - 22;
}}"
    );
    assert_eq!(compile_jit_with_runtime(&source), 0);
}

#[test]
fn static_call_on_struct_name_from_another_structs_method() {
    let source = format!(
        "{MAKER}
struct User {{
    int y;
    int run() {{
        var m = Maker.make(y);
        return m.x + Maker.twice(3);
    }}
}}
test(): int {{
    var u = User();
    u.y = 4;
    return u.run() - 10;
}}"
    );
    assert_eq!(compile_jit_with_runtime(&source), 0);
}

#[test]
fn local_shadows_struct_name() {
    // A local named like a struct is the local, not the type.
    let source = format!(
        "{MAKER}
test(): int {{
    var Maker = 5;
    return Maker - 5;
}}"
    );
    assert_eq!(compile_jit_with_runtime(&source), 0);
}
