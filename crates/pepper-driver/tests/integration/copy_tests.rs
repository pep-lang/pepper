//! `copy(value)` (`runtime/copy.pep`, `passes/copies.rs`): each program runs
//! through the JIT and returns 0, or a distinct nonzero code per failed
//! check, and every test also checks the allocation census, so a copy that
//! leaks or releases twice fails.

use pepper_codegen::CodeGenerator;

/// Compile and JIT `source`'s `test()`; return its result and the net
/// number of allocations it left behind.
fn run(source: &str) -> (i32, i64) {
    let mut module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    let ctx = inkwell::context::Context::create();
    let mut generator = CodeGenerator::new(&ctx, "test");
    let ee = generator.jit_engine(&mut module).expect("jit");
    let live_allocs = unsafe { ee.get_function::<unsafe extern "C" fn() -> i64>("_pep_live_allocs").expect("_pep_live_allocs") };
    let before = unsafe { live_allocs.call() };
    let result = CodeGenerator::jit_call_i32(&ee, "test").expect("entry");
    let after = unsafe { live_allocs.call() };
    (result, after - before)
}

fn assert_runs(source: &str) {
    let (code, leaked) = run(source);
    assert_eq!(code, 0, "check {code} failed");
    assert_eq!(leaked, 0, "leaked {leaked} allocations");
}

/// A self-referential struct: a field of its own type.
const NODE: &str = r#"
[Shared]
struct Settings {
    const port: int;
    construct(this.port = 0) {}
}

struct Node {
    int value;
    String name;
    Node next;
    Node other;
    Settings settings;
    __weak<Node> back;
    construct(this.value = 0) {
        name = "node";
    }
}

same(a: Node, b: Node): bool {
    return a === b;
}
"#;

#[test]
fn copies_are_new_objects_with_the_same_values() {
    assert_runs(&format!(
        r#"{NODE}
test(): int {{
    var a = Node(7);
    var c = copy(a);
    if (c.value != 7) {{ return 1; }}
    if (same(a, c)) {{ return 2; }}
    if (c.name != "node") {{ return 3; }}
    c.name.append("!");
    if (a.name != "node") {{ return 4; }}
    if (c.next !== __null) {{ return 5; }}
    return 0;
}}"#
    ));
}

#[test]
fn shared_objects_stay_shared_and_cycles_are_kept() {
    assert_runs(&format!(
        r#"{NODE}
test(): int {{
    var a = Node(1);
    var b = Node(2);
    a.next = b;
    a.other = b;
    b.next = a;
    var c = copy(a);
    if (!same(c.next, c.other)) {{ return 1; }}
    if (same(c.next, b)) {{ return 2; }}
    if (!same(c.next.next, c)) {{ return 3; }}
    if (c.next.value != 2) {{ return 4; }}
    # Break both cycles so the census sees everything freed.
    a.next = __null;
    b.next = __null;
    c.next.next = __null;
    return 0;
}}"#
    ));
}

#[test]
fn thread_safe_objects_are_not_copied() {
    assert_runs(&format!(
        r#"{NODE}
test(): int {{
    var a = Node(1);
    a.settings = Settings(8080);
    var c = copy(a);
    if (__address<Settings>(c.settings) != __address<Settings>(a.settings)) {{ return 1; }}
    var s = copy(a.settings);
    if (__address<Settings>(s) != __address<Settings>(a.settings)) {{ return 2; }}
    if (copy(42) != 42) {{ return 3; }}
    return 0;
}}"#
    ));
}

#[test]
fn weak_references_point_at_copies_or_become_null() {
    assert_runs(&format!(
        r#"{NODE}
test(): int {{
    # `back` is visited before its target's strong reference (`next`):
    # it is fixed up once everything is copied.
    var a = Node(1);
    var b = Node(2);
    a.back = __weak_from<Node>(b);
    a.next = b;
    var c = copy(a);
    var target = __weak_upgrade<Node>(c.back);
    if (!same(target, c.next)) {{ return 1; }}
    # A weak reference to an object outside the copied value becomes null.
    var outside = Node(3);
    var d = Node(4);
    d.back = __weak_from<Node>(outside);
    var e = copy(d);
    if (!__weak_expired<Node>(e.back)) {{ return 2; }}
    if (__weak_expired<Node>(d.back)) {{ return 3; }}
    return 0;
}}"#
    ));
}

#[test]
fn strings_and_containers_copy_deeply() {
    assert_runs(
        r#"
struct Tag {
    int id;
    construct(this.id = 0) {}
}

test(): int {
    var s = "abc";
    var t = s.copy();
    t.append("d");
    if (s != "abc" || t != "abcd") { return 1; }
    var u = copy(s);
    if (u != "abc" || u === s) { return 2; }

    var names = Array<Array<String>>();
    var inner = Array<String>();
    inner.append("ada");
    names.append(inner);
    names.append(inner);
    var copied = copy(names);
    copied[0][0].append(" lovelace");
    if (names[0][0] != "ada") { return 3; }
    # The inner Array appeared twice: it is copied once.
    if (copied[1][0] != "ada lovelace") { return 4; }

    var tags = HashMap<String, Tag>();
    tags.insert("a", Tag(1));
    var tags2 = copy(tags);
    if (tags2.get("a").id != 1 || tags2.get("a") === tags.get("a")) { return 5; }

    # Keyed by struct identity: the copy is hashed again under its keys.
    var by_tag = HashSet<Tag>();
    by_tag.insert(Tag(2));
    var sets = copy(by_tag);
    if (sets.count() != 1) { return 6; }
    return 0;
}"#,
    );
}

#[test]
fn copyable_implementations_are_used() {
    assert_runs(
        r#"
const copies_made = Atomic<int>(0);

struct Buffer {
    __ptr<u8> _data;
    ulong size;

    construct(this.size = 0) {
        _data = _pep_malloc(size);
    }

    destruct {
        _pep_free(_data);
    }

    Buffer copy(Copies copies) {
        copies_made.fetch_add(1);
        var made = Buffer(size);
        var i: ulong = 0;
        while (i < size) {
            made._data[i] = _data[i];
            i = i + 1;
        }
        return made;
    }
}

extend Buffer with Copyable<Buffer> {}

struct Message {
    Buffer body;
    Buffer again;
}

test(): int {
    var m = Message();
    m.body = Buffer(4);
    m.body._data[0] = 9;
    m.again = m.body;
    var c = copy(m);
    if (c.body._data[0] != 9) { return 1; }
    if (c.body === m.body) { return 2; }
    # Copied once, though referenced twice.
    if (c.again !== c.body || copies_made.load() != 1) { return 3; }
    return 0;
}"#,
    );
}

#[test]
fn enum_values_are_copied_as_values() {
    assert_runs(
        r#"
enum Suit {
    Clubs,
    Hearts,
}

struct Card {
    Suit suit;
    String name;
}

test(): int {
    var c = Card();
    c.suit = Suit.Hearts;
    c.name = "queen";
    var d = copy(c);
    if (d.suit != Suit.Hearts || d.name != "queen" || d.name === c.name) { return 1; }
    if (copy(Suit.Clubs) != Suit.Clubs) { return 2; }
    return 0;
}"#,
    );
}
