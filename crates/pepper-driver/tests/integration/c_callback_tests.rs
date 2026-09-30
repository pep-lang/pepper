//! C function pointer types (`extern (P...) => R`): named functions, static
//! methods and closures that capture nothing passed to C as callbacks,
//! stored, returned and called through, with the leak census. Threads
//! sharing one are in `async_tests.rs`.

use pepper_codegen::CodeGenerator;
use pepper_sema::model::Module as SemaModule;

fn sema(source: &str) -> Result<SemaModule, String> {
    pepper_driver::compiler::compile_with_runtime("test.pep", source)
}

/// Compile + JIT `test()` and return (result, net live-allocation delta).
fn run(source: &str) -> (i32, i64) {
    let mut module = sema(source).unwrap_or_else(|e| panic!("compile:\n{}", e));
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs = unsafe {
        ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs")
    };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    (result, after - before)
}

const QSORT: &str = r#"
extern void qsort(void* base, ulong count, ulong size, extern (void*, void*) => int compare);

fill(numbers: __ptr<int>) {
    numbers[0] = 30;
    numbers[1] = 10;
    numbers[2] = 40;
    numbers[3] = 20;
}
"#;

#[test]
fn named_functions_and_closures_sort_through_qsort() {
    let src = format!(
        "{}{}",
        QSORT,
        r#"
ascending(a: __ptr<void>, b: __ptr<void>): int {
    __ptr<int> x = a;
    __ptr<int> y = b;
    return x[0] - y[0];
}

struct Order {
    static descending(a: __ptr<void>, b: __ptr<void>): int {
        __ptr<int> x = a;
        __ptr<int> y = b;
        return y[0] - x[0];
    }
}

test(): int {
    __ptr<int> numbers = _pep_malloc(4 * sizeof<int>());
    var score = 0;
    fill(numbers);
    qsort(numbers, 4, sizeof<int>(), ascending);
    if (numbers[0] == 10 && numbers[3] == 40) { score += 1; }
    qsort(numbers, 4, sizeof<int>(), Order.descending);
    if (numbers[0] == 40 && numbers[3] == 10) { score += 10; }
    fill(numbers);
    qsort(numbers, 4, sizeof<int>(), (a, b) => {
        __ptr<int> x = a;
        __ptr<int> y = b;
        return x[0] - y[0];
    });
    if (numbers[0] == 10 && numbers[3] == 40) { score += 100; }
    _pep_free(numbers);
    return score;
}
"#
    );
    assert_eq!(run(&src), (111, 0));
}

#[test]
fn stored_returned_and_called() {
    let src = r#"
twice(x: int): int { return x * 2; }

struct Table {
    extern (int) => int op;
    construct() { op = twice; }
    run(x: int): int { return op(x); }
}

pick(big: bool): extern (int) => int {
    if (big) { return twice; }
    return (x) => x + 1;
}

const doubler: extern (int) => int = twice;

test(): int {
    var t = Table();
    var f = pick(true);
    extern (int) => int g = pick(false);
    return t.run(5) + f(100) + g(1) * 1000 + doubler(3);
}
"#;
    assert_eq!(run(src), (10 + 200 + 2000 + 6, 0));
}
