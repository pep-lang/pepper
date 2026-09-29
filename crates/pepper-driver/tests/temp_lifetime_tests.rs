//! The receiver of a member access or index on a call result (`f().x`,
//! `f()[i]`) is a temporary destroyed at the end of the full expression, as
//! C++ destroys a temporary `shared_ptr`. It used to be released right after
//! the field load, so `f().s == "x"` compared a String the temporary had
//! just freed (a use-after-free that crashed in memcmp).

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
    transform_pass(&mut module).expect("sema");
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

const HOLDER: &str = r#"
struct Holder {
    String s;
    int[] nums;
    new(String v = "") {
        s = v;
        nums = Array<int>();
        nums.append(4);
        nums.append(5);
    }
    Holder twice() { return Holder(s + s); }
}
make(String v): Holder { return Holder(v); }
names(): String[] {
    var out = Array<String>();
    out.append("zero");
    out.append("one");
    return out;
}
"#;

#[test]
fn field_of_a_call_result_outlives_the_access() {
    let (result, leaked) = compile_jit_census(&format!(
        r#"{HOLDER}
test(): int {{
    var h = Holder("ab");
    if (!(h.twice().s == "abab")) {{ return 1; }}          # method result
    if (!(make("xy").s == "xy")) {{ return 2; }}           # function result
    if (make("q").twice().twice().s.size() != 4) {{ return 3; }}
    var copy = make("kept").s;                            # copied out, then released
    if (!(copy == "kept")) {{ return 4; }}
    if (make("n").nums[1] != 5) {{ return 5; }}           # field then index
    if (!(names()[1] == "one")) {{ return 6; }}          # element of a result
    make("w").s = "overwritten";                          # store through a temporary
    return 0;
}}"#
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0, "temporaries leaked or double-released");
}

#[test]
fn temporaries_in_conditions_and_returns() {
    let (result, leaked) = compile_jit_census(&format!(
        r#"{HOLDER}
size_of(v: String): int {{
    return make(v).s.size();                               # returned field read
}}
test(): int {{
    var n = 0;
    while (make("abc").s.size() > n) {{                    # loop condition
        n = n + 1;
    }}
    var t = make("ab").s.size() == 2 ? make("c").s.size() : 0;   # ternary arm
    return n + t + size_of("xyz") - 7;
}}"#
    ));
    assert_eq!(result, 0);
    assert_eq!(leaked, 0);
}
