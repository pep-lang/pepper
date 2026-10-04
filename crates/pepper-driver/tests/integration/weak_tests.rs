//! `__weak<T>` (std::weak_ptr<T>) and its intrinsics: `__weak_from<T>`,
//! `__weak_upgrade<T>`, `__weak_expired<T>` (passes/weak_types.rs).

use crate::support::compile_jit_with_runtime as run;

fn error_of(source: &str) -> String {
    match pepper_driver::compiler::compile_with_runtime("test.pep", source) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e.to_string(),
    }
}

const NODE: &str = r#"
import async;
const destroyed = async.Atomic<int>(0);

struct Node {
    int value = 0;
    construct(this.value = 0) {}
    destruct { destroyed.fetch_add(1); }
}
"#;

fn with_node(body: &str) -> String {
    format!("{}{}", NODE, body)
}

#[test]
fn upgrade_while_alive_and_after_destruction() {
    let src = with_node(
        r#"
test(): int {
    var before = _pep_live_allocs();
    {
        var n = Node(7);
        __weak<Node> w = __weak_from<Node>(n);
        if (__weak_expired<Node>(w)) { return -1; }
        var strong = __weak_upgrade<Node>(w);
        if (strong.value != 7) { return -2; }
        if (__refcount<Node>(n) != 2) { return -3; }
        strong = __null;
        n = __null;
        # Destroyed, but the weak reference keeps the memory.
        if (destroyed.load() != 1) { return -4; }
        if (!__weak_expired<Node>(w)) { return -5; }
        var gone = __weak_upgrade<Node>(w);
        if (gone != __null) { return -6; }
        if (_pep_live_allocs() - before != 1) { return -7; }
    }
    # The last weak reference freed it.
    return (_pep_live_allocs() - before) as int;
}
"#,
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn weak_copies_count_like_shared_ptr() {
    let src = with_node(
        r#"
keep(__weak<Node> w): __weak<Node> {
    return w;
}

test(): int {
    var before = _pep_live_allocs();
    {
        var n = Node(1);
        var a = __weak_from<Node>(n);
        var b = a;
        var c = keep(b);
        b = c;
        a = __null;
        n = __null;
        if (destroyed.load() != 1) { return -1; }
        if (_pep_live_allocs() - before != 1) { return -2; }
    }
    return (_pep_live_allocs() - before) as int;
}
"#,
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn weak_field_breaks_a_cycle() {
    let src = r#"
import async;
const freed = async.Atomic<int>(0);

struct Child {
    __weak<Parent> parent;
    construct() {}
    destruct { freed.fetch_add(1); }
    int parent_value() {
        var p = __weak_upgrade<Parent>(parent);
        if (p == __null) { return -1; }
        return p.value;
    }
}

struct Parent {
    int value = 42;
    Child child;
    construct() {}
    destruct { freed.fetch_add(10); }
}

test(): int {
    var before = _pep_live_allocs();
    {
        var p = Parent();
        var c = Child();
        c.parent = __weak_from<Parent>(p);
        p.child = c;
        if (c.parent_value() != 42) { return -1; }
    }
    if (freed.load() != 11) { return -2; }
    return (_pep_live_allocs() - before) as int;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn weak_to_self_released_in_destructor() {
    let src = r#"
import async;
const ran = async.Atomic<int>(0);

struct Self {
    __weak<Self> me;
    construct() {}
    destruct { ran.fetch_add(1); }
}

test(): int {
    var before = _pep_live_allocs();
    {
        var s = Self();
        s.me = __weak_from<Self>(s);
    }
    if (ran.load() != 1) { return -1; }
    return (_pep_live_allocs() - before) as int;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn weak_from_a_temporary_is_expired() {
    let src = with_node(
        r#"
test(): int {
    var before = _pep_live_allocs();
    {
        var w = __weak_from<Node>(Node(3));
        if (destroyed.load() != 1) { return -1; }
        if (!__weak_expired<Node>(w)) { return -2; }
    }
    return (_pep_live_allocs() - before) as int;
}
"#,
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn weak_made_during_construction_upgrades_and_does_not_free() {
    // The constructor's `this` owns the first reference, so a weak reference
    // made from it upgrades, and dropping the weak and upgraded references
    // must not free the object (#617).
    let src = r#"
import async;
const upgraded = async.Atomic<int>(0);

struct Early {
    construct() {
        var w = __weak_from<Early>(this);
        if (__weak_upgrade<Early>(w) != __null) { upgraded.store(1); }
    }
}

test(): int {
    var before = _pep_live_allocs();
    {
        var e = Early();
        if (__refcount<Early>(e) != 1) { return -1; }
    }
    if (upgraded.load() != 1) { return -2; }
    return (_pep_live_allocs() - before) as int;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn weak_to_a_function_value() {
    let src = r#"
square(x: int): int { return x * x; }

test(): int {
    var f: (int) => int = square;
    var w = __weak_from<(int) => int>(f);
    var g = __weak_upgrade<(int) => int>(w);
    return g(3) - 9;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn strong_does_not_convert_to_weak() {
    let err = error_of(&with_node(
        r#"
test(): int {
    var n = Node(1);
    __weak<Node> w = n;
    return 0;
}
"#,
    ));
    assert!(err.contains("test.pep:13:22: error: cannot initialize variable 'w' of type '__weak<Node>' with a value of type 'Node'; use '__weak_from<Node>(...)' to make one"), "{}", err);
}

#[test]
fn weak_does_not_convert_to_strong() {
    let err = error_of(&with_node(
        r#"
test(): int {
    var n = Node(1);
    var w = __weak_from<Node>(n);
    Node m = w;
    return 0;
}
"#,
    ));
    assert!(err.contains("test.pep:14:14: error: cannot initialize variable 'm' of type 'Node' with a value of type '__weak<Node>'; use '__weak_upgrade<Node>(...)' to get a strong reference"), "{}", err);
}

#[test]
fn weak_struct_in_a_with_block() {
    let src = r#"
import async;
const freed = async.Atomic<int>(0);

struct Parent {
    String name;
    Child kid;
    construct(String name) { this.name = name; }
    destruct { freed.fetch_add(1); }
}

struct Child {
    Weak<Parent> owner;
    construct(Parent owner) { this.owner = Weak<Parent>(owner); }
    destruct { freed.fetch_add(1); }
    int owner_length() {
        with (var parent = this.owner) {
            return parent.name.length as int;
        } else {
            return -1;
        }
        return -2;
    }
}

test(): int {
    var before = _pep_live_allocs();
    Child orphan = __null;
    {
        var p = Parent("ada");
        p.kid = Child(p);
        if (p.kid.owner_length() != 3) { return -1; }
        if (p.kid.owner.expired()) { return -2; }
        orphan = p.kid;
    }
    # The cycle is broken: the parent is gone, the child lives on in orphan.
    if (freed.load() != 1) { return -3; }
    if (!orphan.owner.expired()) { return -4; }
    if (orphan.owner_length() != -1) { return -5; }
    orphan = __null;
    if (freed.load() != 2) { return -6; }
    return (_pep_live_allocs() - before) as int;
}
"#;
    assert_eq!(run(src), 0);
}
