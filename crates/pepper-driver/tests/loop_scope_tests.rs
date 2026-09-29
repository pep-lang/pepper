//! A while body's struct locals are released where each iteration leaves the
//! body: its fall-through end, a `continue`, or a `break`, each releasing only
//! the locals declared before it. They used to be released at the loop's
//! condition block, which a `continue` placed before a declaration reaches
//! without passing that declaration: invalid IR ("Instruction does not
//! dominate all uses").

use pepper_codegen::CodeGenerator;
use pepper_sema::builder::build;
use pepper_sema::model::Module as SemaModule;
use pepper_sema::passes::transform_pass;
use pepper_sema::struct_body;

/// `_pep_live_allocs()` is a process-wide counter: serialize the census.
static CENSUS_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// Compile + JIT; return (entry result, net live-allocation delta).
fn compile_jit_census(source: &str) -> (i32, i64) {
    let _census = CENSUS_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs = unsafe {
        ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs")
            .expect("_pep_live_allocs")
    };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    (result, after - before)
}

#[test]
fn continue_before_a_declaration() {
    let (result, leaked) = compile_jit_census(
        r#"
struct Item {
    int v;
    new(this.v = 0) {}
}
test(): int {
    var kept = Array<Item>();
    var i = 0;
    while (i < 10) {
        var early = Item(i);
        i = i + 1;
        if (i % 2 == 0) {
            continue;                    # `late` is not declared yet
        }
        var late = Item(i * 10);
        kept.append(late);
        if (i == 9) {
            break;                       # both locals are live here
        }
    }
    return kept.count() - 5;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0, "loop locals leaked or double-released");
}

#[test]
fn locals_released_every_iteration() {
    // Each iteration's String is released on every exit path; a shared one
    // survives the loop with its count intact.
    let (result, leaked) = compile_jit_census(
        r#"
test(): int {
    var shared = "s";
    var n = 0;
    while (n < 100) {
        var a = shared;
        var b = "x" + shared;
        n = n + 1;
        if (n > 50) {
            continue;
        }
        var c = b + a;
    }
    return shared.size() - 1;
}
"#,
    );
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}
