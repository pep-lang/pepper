//! `for (var x in source)` and the iterator protocol (runtime/iterator.pep):
//! the loop calls `source.iterate()` when the source declares it, else drives
//! the source itself through `next()` / `current()`. Each JIT case also
//! checks the allocation census, since the lowering relies on ordinary
//! scope-exit releases for the hidden iterator and the loop variable.
//! The runtime's iterators (String, Range, the modification guards) are
//! tested in `runtime/test/iterator_test.pep` and `range_test.pep`.

use pepper_codegen::CodeGenerator;

/// Compile + JIT `test()`; return (result, net live-allocation delta), or the
/// compile error.
fn try_compile_jit_census(source: &str) -> Result<(i32, i64), String> {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source)?;
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module)?;
    let live_allocs = unsafe {
        ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs")
            .expect("_pep_live_allocs")
    };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    Ok((result, after - before))
}

fn compile_jit_census(source: &str) -> (i32, i64) {
    try_compile_jit_census(source).unwrap_or_else(|e| panic!("compile error: {e}"))
}

/// Assert `test()` returns 0 and leaves no allocation behind.
fn assert_runs_clean(source: &str) {
    let (result, leaked) = compile_jit_census(source);
    assert_eq!(result, 0, "test() returned {result}");
    assert_eq!(leaked, 0, "allocations leaked or double-released");
}

const ITEM: &str = r#"
struct Item {
    int v;
    construct(this.v = 0) {}
}
"#;

#[test]
fn sums_an_int_array() {
    assert_runs_clean(
        r#"
test(): int {
    var nums = Array<int>();
    nums.append(1);
    nums.append(2);
    nums.append(39);
    var total = 0;
    for (var x in nums) {
        total = total + x;
    }
    return total - 42;
}
"#,
    );
}

#[test]
fn typed_binding_and_optional_parens() {
    assert_runs_clean(
        r#"
test(): int {
    var nums = Array<long>();
    nums.append(40);
    nums.append(2);
    long total = 0;
    for (long x in nums) {
        total = total + x;
    }
    for var y: long in nums {
        total = total - y;
    }
    return total;
}
"#,
    );
}

#[test]
fn empty_array_runs_no_iterations() {
    assert_runs_clean(
        r#"
test(): int {
    var nums = Array<int>();
    for (var x in nums) {
        return 1;
    }
    return 0;
}
"#,
    );
}

#[test]
fn struct_elements_with_break_continue_and_return() {
    // Each exit releases the loop variable and the hidden iterator exactly once.
    assert_runs_clean(&format!(
        r#"{ITEM}
first_over(Array<Item> items, int limit): int {{
    for (var it in items) {{
        if (it.v > limit) {{
            return it.v;
        }}
    }}
    return -1;
}}
test(): int {{
    var items = Array<Item>();
    var i = 0;
    while (i < 10) {{
        items.append(Item(i));
        i = i + 1;
    }}
    var odd = 0;
    for (var it in items) {{
        if (it.v % 2 == 0) {{
            continue;
        }}
        if (it.v == 9) {{
            break;
        }}
        odd = odd + it.v;
    }}
    # 1 + 3 + 5 + 7 = 16
    return (odd - 16) + (first_over(items, 6) - 7);
}}
"#
    ));
}

#[test]
fn loop_variable_is_a_shared_reference_to_the_element() {
    // `x.v = ...` changes the element (both are references to one object);
    // rebinding `x` does not write back to the Array.
    assert_runs_clean(&format!(
        r#"{ITEM}
test(): int {{
    var items = Array<Item>();
    items.append(Item(1));
    items.append(Item(2));
    for (var it in items) {{
        it.v = it.v * 10;
        it = Item(99);
    }}
    return items[0].v + items[1].v - 30;
}}
"#
    ));
}

#[test]
fn temporary_source_stays_alive_for_the_loop() {
    assert_runs_clean(&format!(
        r#"{ITEM}
make(): Array<Item> {{
    var items = Array<Item>();
    items.append(Item(20));
    items.append(Item(22));
    return items;
}}
test(): int {{
    var total = 0;
    for (var it in make()) {{
        total = total + it.v;
    }}
    return total - 42;
}}
"#
    ));
}

#[test]
fn nested_loops_and_body_shadowing() {
    assert_runs_clean(
        r#"
test(): int {
    var rows = Array<Array<int>>();
    var i = 0;
    while (i < 3) {
        var row = Array<int>();
        row.append(i);
        row.append(i * 10);
        rows.append(row);
        i = i + 1;
    }
    var total = 0;
    for (var row in rows) {
        for (var x in row) {
            var row = x;         # shadows the outer loop variable
            total = total + row;
        }
    }
    # (0 + 0) + (1 + 10) + (2 + 20) = 33
    return total - 33;
}
"#,
    );
}

#[test]
fn custom_iterator_is_driven_directly() {
    // A type with next()/current() but no iterate() is used as the iterator
    // itself, and the loop shares the object: it is exhausted afterwards.
    assert_runs_clean(
        r#"
struct Countdown {
    int remaining;
    int now;
    construct(this.remaining = 0) {}
    bool next() {
        if (remaining == 0) {
            return false;
        }
        now = remaining;
        remaining = remaining - 1;
        return true;
    }
    int current() {
        return now;
    }
}
extend Countdown with Iterator<int> {}

test(): int {
    var total = 0;
    var c = Countdown(4);
    for (var n in c) {
        total = total + n;
    }
    if (c.next()) {
        return 100;
    }
    for (var n in Countdown(2)) {
        total = total + n;
    }
    # 4 + 3 + 2 + 1 + 2 + 1 = 13
    return total - 13;
}
"#,
    );
}

#[test]
fn custom_iterable_hands_out_an_iterator() {
    assert_runs_clean(
        r#"
struct Evens {
    int limit;
    construct(this.limit = 0) {}
    EvensIterator iterate() {
        var it = EvensIterator();
        it.limit = limit;
        it.now = -2;
        return it;
    }
}
struct EvensIterator {
    int limit;
    int now;
    bool next() {
        now = now + 2;
        return now < limit;
    }
    int current() {
        return now;
    }
}

test(): int {
    var total = 0;
    for (var n in Evens(10)) {
        total = total + n;
    }
    # 0 + 2 + 4 + 6 + 8 = 20
    return total - 20;
}
"#,
    );
}

#[test]
fn iterates_a_field_inside_a_method() {
    assert_runs_clean(&format!(
        r#"{ITEM}
struct Bag {{
    Array<Item> items;
    construct() {{
        items = Array<Item>();
    }}
    int total() {{
        var sum = 0;
        for (var it in items) {{
            sum = sum + it.v;
        }}
        return sum;
    }}
}}
test(): int {{
    var bag = Bag();
    bag.items.append(Item(40));
    bag.items.append(Item(2));
    return bag.total() - 42;
}}
"#
    ));
}

#[test]
fn iterates_a_generic_parameter() {
    assert_runs_clean(
        r#"
sum<C>(C values): int {
    var total = 0;
    for (var v in values) {
        total = total + v;
    }
    return total;
}
test(): int {
    var nums = Array<int>();
    nums.append(30);
    nums.append(12);
    return sum<Array<int>>(nums) - 42;
}
"#,
    );
}

#[test]
fn not_iterable_is_a_compile_error() {
    for (source, ty) in [
        ("struct Foo { int x; }\ntest(): int { var f = Foo(); for (var x in f) { } return 0; }", "Foo"),
        (
            "struct OnlyNext { bool next() { return false; } }\ntest(): int { for (var x in OnlyNext()) { } return 0; }",
            "OnlyNext",
        ),
    ] {
        let err = try_compile_jit_census(source).expect_err("expected a compile error");
        assert!(
            err.contains(&format!(
                "type '{ty}' is not iterable: implement Iterable<T> (iterate()) or Iterator<T> (next() and current())"
            )),
            "unexpected error: {err}"
        );
    }
}
