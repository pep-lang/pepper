//! Shared_ptr reference-semantics matrix: every container operation is
//! exercised against BOTH a POD element type (no refcounting expected) and a
//! struct element type (refcounts must stay balanced). Each test returns 0 on
//! success or a distinct negative code per check, so a failure pinpoints the
//! exact broken invariant without hand-tracing IR.

use pepper_codegen::CodeGenerator;

fn compile_jit_with_runtime(source: &str) -> i32 {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    generator.jit_execute(&mut module, "test").expect("jit")
}

/// Compile + JIT and return (entry result, net live-allocation delta). The
/// census is taken around the entry call so it reflects only the test body.
fn compile_jit_census(source: &str) -> (i32, i64) {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    // The census is a process-global counter in the JIT'd module: read it
    // before and after the entry call so the delta reflects only this test body.
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

const POINT: &str = r#"
struct Point {
    int x;
    construct(this.x = 0) {}
}
"#;

const TALLY: &str = r#"
struct Tally {
    int alive;
    construct(this.alive = 1) {}
    destruct {
        alive = 0;
    }
}
"#;

// ── append + read back ───────────────────────────────────────────────────────

#[test]
fn append_read_back_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    if (a.count() != 3) { return -1; }
    if (a[0] != 1 || a[1] != 2 || a[2] != 3) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn append_read_back_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Array<Point>();
    var p = Point();
    p.x = 5;
    a.append(p);
    if (a.count() != 1) {{ return -1; }}
    if (a[0].x != 5) {{ return -2; }}
    if (__refcount<Point>(p) != 2) {{ return -3; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── += / append_all (fluent, returns this) ───────────────────────────────────

#[test]
fn plus_assign_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    var b = Array<int>();
    b.append(2);
    b.append(3);
    a += b;
    if (a.count() != 3) { return -1; }
    if (a[0] != 1 || a[1] != 2 || a[2] != 3) { return -2; }
    # b is untouched.
    if (b.count() != 2 || b[0] != 2 || b[1] != 3) { return -3; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn plus_assign_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Array<Point>();
    var p1 = Point();
    p1.x = 1;
    a.append(p1);
    var b = Array<Point>();
    var p2 = Point();
    p2.x = 2;
    b.append(p2);
    if (__refcount<Point>(p1) != 2) {{ return -1; }}
    if (__refcount<Point>(p2) != 2) {{ return -2; }}
    a += b;
    if (a.count() != 2) {{ return -3; }}
    if (a[0].x != 1 || a[1].x != 2) {{ return -4; }}
    # The append acquired each moved reference into its new slot.
    if (__refcount<Point>(p1) != 2) {{ return -5; }}
    if (__refcount<Point>(p2) != 3) {{ return -6; }}
    # b keeps its own copy of p2.
    if (b.count() != 1 || b[0].x != 2) {{ return -7; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

#[test]
fn self_append_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var h = Array<int>();
    h.append(1);
    h.append(2);
    h += h;
    if (h.count() != 4) { return -1; }
    if (!(h[0] == 1 && h[1] == 2 && h[2] == 1 && h[3] == 2)) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn self_append_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var h = Array<Point>();
    var p = Point();
    p.x = 9;
    h.append(p);
    if (__refcount<Point>(p) != 2) {{ return -1; }}
    h += h;
    if (h.count() != 2) {{ return -2; }}
    # Each element now has two references in the Array plus p's own.
    if (__refcount<Point>(p) != 3) {{ return -3; }}
    if (h[0].x != 9 || h[1].x != 9) {{ return -4; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── pop / remove_at / clear / clone / first / last ───────────────────────────

#[test]
fn pop_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    var v = a.pop();
    if (v != 2) { return -1; }
    if (a.count() != 1 || a[0] != 1) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn pop_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Array<Point>();
    var p = Point();
    p.x = 7;
    a.append(p);
    if (__refcount<Point>(p) != 2) {{ return -1; }}
    var q = a.pop();
    # pop returns the reference: slot release + return acquire cancel, so
    # p's count is unchanged and q aliases p.
    if (__refcount<Point>(p) != 2) {{ return -2; }}
    if (q.x != 7) {{ return -3; }}
    if (a.count() != 0) {{ return -4; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

#[test]
fn remove_at_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a.append(3);
    var v = a.remove_at(1);
    if (v != 2) { return -1; }
    if (a.count() != 2 || a[0] != 1 || a[1] != 3) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn remove_at_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Array<Point>();
    var p1 = Point();
    p1.x = 1;
    var p2 = Point();
    p2.x = 2;
    var p3 = Point();
    p3.x = 3;
    a.append(p1);
    a.append(p2);
    a.append(p3);
    if (__refcount<Point>(p2) != 2) {{ return -1; }}
    var r = a.remove_at(1);
    # The removed reference is returned: p2 keeps its count.
    if (r.x != 2) {{ return -2; }}
    if (__refcount<Point>(p2) != 2) {{ return -3; }}
    if (a.count() != 2 || a[0].x != 1 || a[1].x != 3) {{ return -4; }}
    # p1 and p3 were shifted into new slots: their counts are unchanged.
    if (__refcount<Point>(p1) != 2) {{ return -5; }}
    if (__refcount<Point>(p3) != 2) {{ return -6; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

#[test]
fn clear_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    a.clear();
    if (a.count() != 0) { return -1; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn clear_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{tally}
test(): int {{
    var t = Tally();
    var a = Array<Tally>();
    a.append(t);
    a.append(Tally());
    if (__refcount<Tally>(t) != 2) {{ return -1; }}
    a.clear();
    # clear releases every slot: t drops back to its own reference.
    if (t.alive != 1) {{ return -2; }}
    if (__refcount<Tally>(t) != 1) {{ return -3; }}
    return 0;
}}"#,
                tally = TALLY
            )
        ),
        0
    );
}

#[test]
fn clone_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    var b = a.clone();
    b.append(2);
    if (a.count() != 1) { return -1; }
    if (b.count() != 2 || b[1] != 2) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn clone_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Array<Point>();
    var p = Point();
    p.x = 4;
    a.append(p);
    if (__refcount<Point>(p) != 2) {{ return -1; }}
    var b = a.clone();
    # clone copies the reference into b's slot: acquires p.
    if (__refcount<Point>(p) != 3) {{ return -2; }}
    if (b.count() != 1 || b[0].x != 4) {{ return -3; }}
    a.clear();
    # a's copy is released; b keeps its own.
    if (__refcount<Point>(p) != 2) {{ return -4; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

#[test]
fn first_last_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    if (a.first() != 1) { return -1; }
    if (a.last() != 2) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn first_last_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Array<Point>();
    var p1 = Point();
    p1.x = 1;
    var p2 = Point();
    p2.x = 2;
    a.append(p1);
    a.append(p2);
    if (a.first().x != 1) {{ return -1; }}
    if (a.last().x != 2) {{ return -2; }}
    # first()/last() are lvalue reads: they do not add references.
    if (__refcount<Point>(p1) != 2) {{ return -3; }}
    if (__refcount<Point>(p2) != 2) {{ return -4; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── index read + store (the __index_get / __index_set path) ──────────────────

#[test]
fn index_read_store_pod() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = Array<int>();
    a.append(1);
    a.append(2);
    var v = a[0];
    if (v != 1) { return -1; }
    a[0] = 9;
    if (a[0] != 9) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn index_read_store_struct() {
    assert_eq!(
        compile_jit_with_runtime(
            &format!(
                r#"{point}
test(): int {{
    var a = Array<Point>();
    var p1 = Point();
    p1.x = 1;
    a.append(p1);
    # Reading a[0] is an lvalue read (no refcount work); copying it into `v`
    # is a shared_ptr copy, so the object gains one reference.
    var v = a[0];
    if (v.x != 1) {{ return -1; }}
    if (__refcount<Point>(p1) != 3) {{ return -2; }}
    # Store over the slot: releases the old occupant, acquires the new.
    var p2 = Point();
    p2.x = 2;
    a[0] = p2;
    if (a[0].x != 2) {{ return -3; }}
    # The slot no longer holds p1, but `v` still does: p1 keeps two refs.
    if (__refcount<Point>(p1) != 2) {{ return -4; }}
    if (__refcount<Point>(p2) != 2) {{ return -5; }}
    return 0;
}}"#,
                point = POINT
            )
        ),
        0
    );
}

// ── leak census: every operation must net-zero its temporaries ───────────────

#[test]
fn census_append_pop_struct() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var a = Array<Tally>();
    a.append(Tally());
    var t = a.pop();
    # t escapes the scope; its reference is the one that should remain.
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // The popped element's reference outlives the function (t is a local that
    // is released at scope exit), so the net allocation delta is zero.
    assert_eq!(delta, 0, "append+pop must net-zero its allocations");
}

#[test]
fn census_plus_assign_struct() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var a = Array<Tally>();
    var b = Array<Tally>();
    b.append(Tally());
    a += b;
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    assert_eq!(delta, 0, "fluent += must not leak the returned this");
}

// ── control-flow exits: break/continue destroy exactly the exited scopes ────

#[test]
fn census_break_body_local() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var i = 0;
    while (i < 5) {{
        var t = Tally();
        if (i == 2) {{ break; }}
        i = i + 1;
    }}
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // The body-local `t` must be destroyed at the break site, not leaked:
    // a shared_ptr local goes out of scope when the loop exits early.
    assert_eq!(delta, 0, "break must release the body scope's locals");
}

#[test]
fn census_break_nested_block() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var i = 0;
    while (i < 5) {{
        {{
            var t = Tally();
            if (i == 2) {{ break; }}
        }}
        i = i + 1;
    }}
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // The nested `{ }` scope is exited by the break: its locals are released
    // at the jump site (the fall-through exit is unreachable).
    assert_eq!(delta, 0, "break in a nested block must release that block's locals");
}

#[test]
fn census_continue_nested_block() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var i = 0;
    while (i < 5) {{
        i = i + 1;
        {{
            var t = Tally();
            if (i == 3) {{ continue; }}
        }}
    }}
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // The continue re-enters through the loop head, which releases the body
    // scope; the nested block's locals must not survive the jump.
    assert_eq!(delta, 0, "continue in a nested block must release that block's locals");
}

#[test]
fn census_break_outer_local_survives() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var o = Tally();
    var i = 0;
    while (i < 5) {{
        if (i == 2) {{ break; }}
        i = i + 1;
    }}
    if (o.alive != 1) {{ return -1; }}
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0, "outer local must survive the break (its scope did not exit)");
    assert_eq!(delta, 0);
}

// ── ternary: a conditional of owned rvalues is one owned temporary ──────────

#[test]
fn census_ternary_owned() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var c = 1;
    var x = c ? Tally() : Tally();
    if (__refcount<Tally>(x) != 1) {{ return -1; }}
    if (x.alive != 1) {{ return -2; }}
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // Exactly one of the two arm temporaries survives (the chosen one's ref
    // flows into x); the other is destroyed at the end of the full expression.
    assert_eq!(delta, 0, "ternary must yield exactly one live reference");
}

#[test]
fn census_ternary_discarded() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var c = 1;
    c ? Tally() : Tally();
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // A discarded ternary of owned rvalues is a temporary: destroyed at the
    // end of the full expression.
    assert_eq!(delta, 0, "discarded ternary rvalue must be released");
}

#[test]
fn census_break_inner_loop() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var i = 0;
    while (i < 3) {{
        var o = Tally();
        var j = 0;
        while (j < 4) {{
            var t = Tally();
            if (j == 1) {{ break; }}
            j = j + 1;
        }}
        i = i + 1;
    }}
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // The inner break releases only the inner body scope (t); the outer
    // scopes (o) release at their own tails. Both must net zero.
    assert_eq!(delta, 0, "inner-loop break must not leak or over-release");
}

#[test]
fn census_break_if_arm_local() {
    let (code, delta) = compile_jit_census(
        &format!(
            r#"{tally}
test(): int {{
    var i = 0;
    while (i < 5) {{
        if (i == 2) {{
            var t = Tally();
            break;
        }}
        i = i + 1;
    }}
    return 0;
}}"#,
            tally = TALLY
        ),
    );
    assert_eq!(code, 0);
    // The if-arm scope is exited by the break: its local is released at the
    // jump site (the arm's fall-through tail is unreachable).
    assert_eq!(delta, 0, "break in an if-arm must release the arm's locals");
}

// ── sync primitives: locks, channels and lazy values net-zero ───────────────

/// A `[Shared]` value with an atomic count, the kind the `async` sync types
/// hold today.
const LABEL: &str = r#"
import async;

[Shared]
struct Label {
    const id: int;
    construct(this.id = 0) {}
}
"#;

#[test]
fn census_mutex_lock_exit_paths() {
    let (code, delta) = compile_jit_census(&format!(
        r#"{LABEL}
int returns(async.Mutex<Label> m) {{
    with (var label = m.lock()) {{
        var local = Label(label.id + 1);
        return local.id;
    }}
    return -1;
}}

test(): int {{
    var m = async.Mutex<Label>(Label(1));
    if (returns(m) != 2) {{ return 1; }}
    var i = 0;
    while (i < 4) {{
        i = i + 1;
        with (var label = m.lock()) {{
            var local = Label(i);
            if (i == 1) {{ continue; }}
            if (i == 3) {{ break; }}
        }}
    }}
    with (var label = m.try_lock()) {{
        var local = label;
    }} else {{
        return 2;
    }}
    var c = m.condition();
    return 0;
}}"#
    ));
    assert_eq!(code, 0, "every exit path must unlock");
    assert_eq!(delta, 0, "lock, try_lock and every exit from a with body must net zero");
}

#[test]
fn census_channel_dropped_with_values() {
    let (code, delta) = compile_jit_census(&format!(
        r#"{LABEL}
test(): int {{
    var c = async.Channel<Label>();
    var i = 0;
    while (i < 40) {{
        c.send(Label(i));
        i = i + 1;
    }}
    var first = c.receive();
    if (first.value().id != 0) {{ return 1; }}
    for (var label in c.iterate()) {{
        if (label.id == 10) {{ break; }}
    }}
    var bounded = async.Channel<Label>(2);
    bounded.send(Label(1));
    bounded.try_send(Label(2));
    bounded.close();
    return 0;
}}"#
    ));
    assert_eq!(code, 0);
    assert_eq!(delta, 0, "a channel dropped with values queued must release them");
}

#[test]
fn census_once_and_lazy() {
    let (code, delta) = compile_jit_census(&format!(
        r#"{LABEL}
make(): Label {{
    return Label(7);
}}

nothing() {{}}

test(): int {{
    var once = async.Once();
    once.call(nothing);
    var lazy = async.Lazy<Label>(make);
    if (lazy.get().id != 7) {{ return 1; }}
    var unused = async.Lazy<Label>(make);
    return 0;
}}"#
    ));
    assert_eq!(code, 0);
    assert_eq!(delta, 0, "Once and Lazy, built or not, must free everything");
}

#[test]
fn census_copy_of_a_graph() {
    // A cycle, an object referenced twice, and a weak reference out of the
    // copied value: the copy and the original both free everything.
    let (code, delta) = compile_jit_census(
        r#"
struct Node {
    int value;
    Node next;
    Node other;
    __weak<Node> back;
    Array<String> names;
    construct(this.value = 0) {
        names = Array<String>();
        names.append("n");
    }
}

test(): int {
    var outside = Node(9);
    var a = Node(1);
    var b = Node(2);
    a.next = b;
    a.other = b;
    b.next = a;
    b.back = __weak_from<Node>(outside);
    var c = copy(a);
    if (c.next !== c.other || c.next.next !== c) { return 1; }
    if (!__weak_expired<Node>(c.next.back)) { return 2; }
    a.next = __null;
    b.next = __null;
    c.next.next = __null;
    return 0;
}"#,
    );
    assert_eq!(code, 0);
    assert_eq!(delta, 0, "copying a graph must net zero once both are dropped");
}

#[test]
fn census_confined_mutex() {
    // A Mutex of a struct that is not thread-safe: every exit from a lock's
    // body, `replace`, and dropping the Mutex net zero.
    let (code, delta) = compile_jit_census(
        r#"
import async;

int count(async.Mutex<Array<String>> m) {
    with (var list = m.lock()) {
        var extra = "local";
        return list.count() as int;
    }
    return -1;
}

test(): int {
    var m = async.Mutex<Array<String>>(Array<String>());
    var i = 0;
    while (i < 5) {
        i = i + 1;
        with (var list = m.lock()) {
            list.append("line");
            var tmp = list[0].copy();
            if (i == 2) { continue; }
            if (i == 4) { break; }
        }
    }
    if (count(m) != 4) { return 1; }
    var old = m.replace(Array<String>());
    if (old.count() != 4) { return 2; }
    if (count(m) != 0) { return 3; }
    return 0;
}"#,
    );
    assert_eq!(code, 0);
    assert_eq!(delta, 0, "locking, replace and dropping a confined Mutex must net zero");
}
