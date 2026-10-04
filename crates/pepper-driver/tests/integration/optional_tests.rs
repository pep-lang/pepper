//! Optional<T> reference counts: a struct value held by an optional is
//! counted exactly as a `shared_ptr` copy would be. The rest of Optional's
//! behaviour is tested in `runtime/test/optional_test.pep`.

use crate::support::jit_census;

#[test]
fn held_struct_is_released_with_the_optional() {
    let (result, leaked) = jit_census(
        r#"
struct Tracker {
    construct() {}
}
test(): int {
    var t = Tracker();
    {
        var a = Optional<Tracker>.Value(t);
        if (__refcount<Tracker>(t) != 2) { return -1; }
        var copy = a.value();
        if (__refcount<Tracker>(t) != 3) { return -2; }
    }
    if (__refcount<Tracker>(t) != 1) { return -3; }
    return 0;
}"#,
    );
    assert_eq!(result, 0, "test() returned {}", result);
    assert_eq!(leaked, 0, "{} allocations leaked", leaked);
}
