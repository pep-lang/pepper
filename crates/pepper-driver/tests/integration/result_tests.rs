//! Result<TValue, TError> with a `void` type argument: how the compiler
//! drops the removed field. The rest of Result's behaviour is tested in
//! `runtime/test/result_test.pep`.

use crate::support::compile_jit_with_runtime;

/// A `void` type argument keeps a call stored into the field it removes
/// (`this.value = body()` runs `body()`), and drops the removed field where
/// it is passed on (`Result<T>.ok(this.value)` becomes `ok()`).
#[test]
fn a_void_instance_keeps_the_call_it_stores_and_passes_nothing_on() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Cell<T> {
    var value: T;
    var runs: int;
    construct() {}
    run(body: () => T) {
        this.value = body();
    }
    result(): Result<T> {
        return Result<T>.ok(this.value);
    }
}

test(): int {
    var counter = Cell<int>();
    var c = Cell<void>();
    c.run(() => { counter.runs = counter.runs + 1; });
    if (!c.result().is_ok()) { return 1; }
    var d = Cell<int>();
    d.run(() => { return 41; });
    return d.result().value() + counter.runs;
}
"#
        ),
        42
    );
}
