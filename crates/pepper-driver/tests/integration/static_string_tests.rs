//! String literals as immortal static objects (#410,
//! `passes::static_strings`): a literal is one shared object where no use
//! keeps or changes it, and a new `String` everywhere else, so a literal
//! stored, returned or modified behaves as before. Such a parameter's copy
//! is made by the caller (`Module::caller_copies`).

use crate::support::{jit_cases, output_text, run_linked_with, sema};
use pepper_sema::model::{Expression, Module};

/// The values of the shared literals in function `name`, in order.
fn shared_in(module: &Module, name: &str) -> Vec<String> {
    let function = module.functions.iter().find(|f| f.name == name).unwrap_or_else(|| panic!("no function '{name}'"));
    let mut shared = vec![];
    pepper_sema::passes::visit_function(function, &mut |e| {
        if let Expression::StaticString { value, .. } = e {
            shared.push(value.clone());
        }
    });
    shared
}

const PROGRAM: &str = r##"
struct Holder {
    String name;
    construct(String name) {
        this.name = name;
    }
}

read(s: String): ulong {
    return s.size;
}

read_through(s: String): ulong {
    return read(s);
}

keep(s: String): String {
    return s;
}

change(s: String) {
    assert(s == "change me", "a literal a callee changed is not shared");
    s.append("!");
}

change_through(s: String) {
    change(s);
}

returns_literal(): String {
    return "returned";
}

count_down(s: String, n: int): ulong {
    if (n == 0) {
        return s.size;
    }
    return count_down(s, n - 1);
}

shares() {
    var sb = StringBuilder();
    sb.append("builder");
    read("read");
    read_through("through");
    count_down("recursive", 3);
    if ("left" == sb.to_string()) {
        print("compare");
    }
}

copies() {
    var s = "variable";
    keep("kept");
    change("change me");
    change_through("change me");
    var h = Holder("field");
    var a = Array<String>();
    a.append("element");
}

stored_literals_are_new_objects(): int {
    for (var i in 0..3) {
        var s = "abc";
        s.append("d");
        assert(s == "abcd", "a variable's literal is its own");
        var h = Holder("field");
        h.name.append("+");
        assert(h.name == "field+", "a field's literal is its own");
        var a = Array<String>();
        a.append("element");
        a[0].append("*");
        assert(a[0] == "element*", "an element's literal is its own");
        var k = keep("kept");
        k.append("?");
        assert(k == "kept?", "a kept parameter's literal is its own");
        var r = returns_literal();
        r.append("#");
        assert(r == "returned#", "a returned literal is its own");
        change("change me");
        change_through("change me");
    }
    return 0;
}

shared_literals_compare_and_read(): int {
    var sb = StringBuilder();
    for (var i in 0..100) {
        sb.append("x");
    }
    assert(sb.to_string().size == 100, "100 appends");
    assert("same" == "same", "literals compare by content");
    assert(!("same" == "other"), "different literals differ");
    assert(read("four") == 4, "a shared literal's size");
    assert(count_down("recursive", 5) == 9, "recursion keeps it shared");
    assert("a,b".split(",").count == 2, "a method on a literal");
    assert("-".join("a,b".split(",")) == "a-b", "a literal receiver passed on as an argument");
    return 0;
}

seen_count(s: String, other: String): ulong {
    return __refcount<String>(other) as ulong + s.size * 0;
}

callers_copy_their_arguments(): int {
    var local = "abc".copy();
    assert(__refcount<String>(local) == 1, "one owner");
    assert(read(local) == 3, "a free parameter reads a local");
    assert(read_through(local) == 3, "and passes it on");
    assert(__refcount<String>(local) == 1, "the caller's copies are dropped");
    var h = Holder("abc".copy());
    assert(read(h.name) == 3, "a free parameter reads a field");
    assert(__refcount<String>(h.name) == 1, "the field's copy is dropped");
    assert(seen_count(local, local) == 3, "the callee's parameter holds a copy");
    return 0;
}
"##;

#[test]
fn literals_are_shared_only_where_nothing_keeps_or_changes_them() {
    let module = sema(PROGRAM).unwrap();
    assert_eq!(shared_in(&module, "shares"), ["builder", "read", "through", "recursive", "left", "compare"]);
    assert_eq!(shared_in(&module, "copies"), Vec::<String>::new());
}

#[test]
fn shared_and_new_literals_behave_as_before() {
    jit_cases(PROGRAM, &["stored_literals_are_new_objects", "shared_literals_compare_and_read", "callers_copy_their_arguments"]);
}

#[test]
fn threads_share_a_literal_without_touching_its_count() {
    let source = r#"
import async;

const total = async.Atomic<long>(0);

work() {
    var sb = StringBuilder();
    for (var i in 0..20000) {
        sb.append("x");
    }
    total.fetch_add(sb.to_string().size as long);
}

main(): int {
    var workers = Array<async.Thread>();
    for (var i in 0..4) {
        workers.append(async.Thread.spawn(work));
    }
    for (var worker in workers) {
        worker.join();
    }
    assert(total.load() == 80000, "every thread appended");
    print("appended");
    return 0;
}
"#;
    let module = sema(source).unwrap();
    assert_eq!(shared_in(&module, "work"), ["x"]);
    let output = run_linked_with("static_string_threads", source, &["-O"], |_| {});
    assert_eq!(output_text(&output), "appended\n");
}
