//! `with` blocks and the `Scoped<T>` protocol (runtime/scoped.pep).

use pepper_codegen::CodeGenerator;

fn run(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

fn error_of(source: &str) -> String {
    match pepper_driver::compiler::compile_with_runtime("test.pep", source) {
        Ok(_) => panic!("expected a compile error"),
        Err(e) => e.to_string(),
    }
}

/// A scope object that counts enters and exits, created fresh per block.
const SESSION: &str = r#"
const entered = Atomic<int>(0);
const exited = Atomic<int>(0);

struct Session {
    int id = 0;

    construct(this.id = 0) {}

    destruct {
        this.exit();
    }

    Session enter() {
        entered.fetch_add(1);
        return this;
    }

    exit() {
        exited.fetch_add(1);
    }
}
"#;

#[test]
fn with_binds_enter_and_exits_at_block_end() {
    let src = format!(
        "{}{}",
        SESSION,
        r#"
test(): int {
    var id = 0;
    with (var s = Session(7)) {
        id = s.id;
        if (exited.load() != 0) { return -1; }
    }
    if (id != 7) { return -2; }
    if (entered.load() != 1) { return -3; }
    if (exited.load() != 1) { return -4; }
    return 0;
}
"#
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn with_exits_once_on_every_path() {
    let src = format!(
        "{}{}",
        SESSION,
        r#"
early(): int {
    with (var s = Session(1)) {
        return s.id;
    }
    return 0;
}

loop_exits(): int {
    var i = 0;
    while (i < 4) {
        i = i + 1;
        with (Session(i)) {
            if (i == 2) { continue; }
            if (i == 3) { break; }
        }
    }
    return i;
}

test(): int {
    if (early() != 1) { return -1; }
    if (exited.load() != 1) { return -2; }
    if (loop_exits() != 3) { return -3; }
    if (exited.load() != 4) { return -4; }
    if (entered.load() != 4) { return -5; }
    return 0;
}
"#
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn with_null_enter_runs_else() {
    let src = r#"
struct Node {
    int value = 0;
    construct(this.value = 0) {}
}

struct Maybe {
    Node _target;
    construct(Node target) { _target = target; }
    Node enter() { return _target; }
    exit() {}
}

test(): int {
    var ran = 0;
    with (var n = Maybe(Node(5))) {
        ran = n.value;
    } else {
        return -1;
    }
    if (ran != 5) { return -2; }
    with (var n = Maybe(__null)) {
        return -3;
    } else {
        ran = 0;
    }
    return ran;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn with_void_enter_binds_nothing() {
    let src = r#"
const depth = Atomic<int>(0);

struct Lock {
    construct() {}
    destruct { this.exit(); }
    enter() { depth.fetch_add(1); }
    exit() { depth.fetch_sub(1); }
}

test(): int {
    var seen = 0;
    with (Lock()) {
        seen = depth.load();
    }
    return seen * 10 + depth.load() - 10;
}
"#;
    assert_eq!(run(src), 0);
}

#[test]
fn with_shared_scope_outlives_block() {
    // The header's object is also held elsewhere: the block releases only
    // its own reference, so exit() waits for the last owner.
    let src = format!(
        "{}{}",
        SESSION,
        r#"
test(): int {
    var keep = Session(2);
    with (var s = keep) {
    }
    if (exited.load() != 0) { return -1; }
    return 0;
}
"#
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn with_no_leaks() {
    let src = format!(
        "{}{}",
        SESSION,
        r#"
test(): int {
    var before = _pep_live_allocs();
    with (var s = Session(3)) {
        var inner = Session(4);
    }
    with (Session(5)) {}
    return (_pep_live_allocs() - before) as int;
}
"#
    );
    assert_eq!(run(&src), 0);
}

#[test]
fn with_binding_cannot_be_assigned() {
    let src = format!(
        "{}{}",
        SESSION,
        r#"
test(): int {
    with (var s = Session(1)) {
        s = Session(2);
    }
    return 0;
}
"#
    );
    let err = error_of(&src);
    assert!(err.contains("cannot assign to 's': it is bound by a 'with' block"), "{}", err);
}

#[test]
fn with_void_enter_cannot_bind() {
    let src = r#"
struct Lock {
    construct() {}
    enter() {}
    exit() {}
}

test(): int {
    with (var l = Lock()) {}
    return 0;
}
"#;
    let err = error_of(src);
    assert!(err.contains("cannot bind 'l': 'enter()' returns 'void'"), "{}", err);
}

#[test]
fn with_else_needs_a_struct_result() {
    let src = r#"
struct Counter {
    construct() {}
    int enter() { return 1; }
    exit() {}
}

test(): int {
    with (var n = Counter()) {} else {}
    return 0;
}
"#;
    let err = error_of(src);
    assert!(err.contains("'else' requires 'enter()' to return a struct reference, but it returns 'int'"), "{}", err);
}

#[test]
fn with_generic_scope_in_a_method() {
    let src = r#"
struct Node {
    int value = 0;
    construct(this.value = 0) {}
}

struct Holder<T> {
    T _target;
    construct(T target) { _target = target; }
    T enter() { return _target; }
    exit() {}
}

struct Tree {
    Holder<Node> _parent;
    construct(Node parent) { _parent = Holder<Node>(parent); }
    int parent_value() {
        with (var p = _parent) {
            return p.value;
        } else {
            return -1;
        }
        return -2;
    }
}

test(): int {
    var before = _pep_live_allocs();
    {
        var t = Tree(Node(9));
        if (t.parent_value() != 9) { return -1; }
    }
    return (_pep_live_allocs() - before) as int;
}
"#;
    assert_eq!(run(src), 0);
}
