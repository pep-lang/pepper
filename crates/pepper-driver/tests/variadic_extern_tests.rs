//! Variadic externs: `extern int snprintf(char* buf, ulong n, char* fmt, ...);`
//! declares a C function whose trailing arguments are untyped. The LLVM
//! declaration is variadic (so the C ABI for `...` is used: on Apple arm64
//! those arguments go on the stack), and each extra argument gets C's default
//! argument promotions.

use clap::Parser;
use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

fn module_for(source: &str) -> SemaModule {
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
    module
}

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = module_for(source);
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

#[test]
fn variadic_extern_parses_and_prints() {
    let ast = pepper_parser::parser::parse_source("t.pep", "extern int printf(char* fmt, ...);").expect("parse");
    let text = format!("{}", ast);
    assert!(text.contains("printf(var fmt: char*, ...)"), "{text}");
    // `...` needs a named parameter before it and must come last.
    assert!(pepper_parser::parser::parse_source("t.pep", "extern int f(...);").is_err());
    assert!(pepper_parser::parser::parse_source("t.pep", "extern int f(int a, ..., int b);").is_err());
}

#[test]
fn variadic_declaration_is_variadic_in_llvm() {
    let mut module = module_for("extern int snprintf(char* buf, ulong n, char* fmt, ...);\ntest(): int { return 0; }");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.generate(&mut module).expect("codegen");
    let f = generator.module.get_function("snprintf").expect("snprintf declared");
    assert!(f.get_type().is_var_arg());
    assert_eq!(f.count_params(), 3);
}

/// Compile `source` to a native binary (named `name`), link it, run it and
/// return its exit code. A real link is needed rather than the JIT: on
/// Windows the UCRT defines `snprintf` inline in its headers, so the symbol
/// only exists in `legacy_stdio_definitions.lib`, which the JIT never loads.
fn build_and_run(name: &str, source: &str) -> i32 {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf();
    std::env::set_current_dir(&root).unwrap();
    let dir = std::env::temp_dir().join(format!("pepper_{name}_test"));
    std::fs::create_dir_all(&dir).unwrap();
    let src_path = dir.join(format!("{name}.pep"));
    let out_path = dir.join(if cfg!(windows) { format!("{name}.exe") } else { name.to_string() });
    std::fs::write(&src_path, source).unwrap();
    let options = pepper_driver::Options::parse_from(vec![
        "pepper".to_string(),
        src_path.to_string_lossy().into_owned(),
        "-o".to_string(),
        out_path.to_string_lossy().into_owned(),
    ]);
    assert_eq!(pepper_driver::run(options).expect("compile + link"), 0);
    std::process::Command::new(&out_path)
        .status()
        .expect("spawn binary")
        .code()
        .expect("exit code")
}

#[test]
fn variadic_call_passes_promoted_extras() {
    // snprintf formats into a buffer: the result proves each extra argument
    // arrived with the width `%d` / `%lld` / `%f` expects. (`%lld`, not
    // `%ld`: C `long` is 32-bit on Windows.)
    let source = r#"
[Target(OS(Windows))] [Link("legacy_stdio_definitions")] extern int snprintf(char* buf, ulong n, char* fmt, ...);
[Target(!OS(Windows))] extern int snprintf(char* buf, ulong n, char* fmt, ...);
main(): int {
    var buf: __ptr<char> = _pep_malloc(64);
    u8 small = 200;
    short neg = -3;
    float f = 1.5;
    long big = 5000000000;
    var n = snprintf(buf, 64, "%d|%d|%.1f|%lld", small, neg, f, big);
    # "200|-3|1.5|5000000000" is 21 bytes
    var ok = n == 21 && buf[0] == 50 && buf[4] == 45 && buf[5] == 51 && buf[9] == 53 && buf[20] == 48;
    _pep_free(buf);
    return ok ? 0 : 1;
}
"#;
    assert_eq!(build_and_run("variadic_snprintf", source), 0);
}
