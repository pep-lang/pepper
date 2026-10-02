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
    if (sets.count != 1) { return 6; }
    return 0;
}"#,
    );
}

#[test]
fn copyable_implementations_are_used() {
    assert_runs(
        r#"
import async;
const copies_made = async.Atomic<int>(0);

struct Buffer {
    __ptr<u8> _data;
    ulong size;

    construct(this.size = 0) {
        _data = _pep_malloc(size);
    }

    destruct {
        _pep_free(_data);
    }

    copy(): Buffer {
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
fn copyable_implementations_continue_the_running_copy() {
    // `copy(x)` inside `copy()` reaches the free function, and reuses the
    // copies the outer `copy` made; `register_copy` lets a cycle find the
    // copy being built.
    assert_runs(
        r#"
struct Leaf {
    int value;
}

struct Holder {
    __ptr<u8> _raw;
    Leaf first;
    Leaf second;
    Holder back;

    construct() {
        _raw = _pep_malloc(1);
    }

    destruct {
        _pep_free(_raw);
    }

    copy(): Holder {
        var made = Holder();
        register_copy(this, made);
        made.first = copy(first);
        made.second = copy(second);
        made.back = copy(back);
        return made;
    }
}

extend Holder with Copyable<Holder>;

struct Outer {
    Leaf leaf;
    Holder holder;
}

test(): int {
    var o = Outer();
    o.leaf = Leaf();
    o.leaf.value = 7;
    o.holder = Holder();
    o.holder.first = o.leaf;
    o.holder.second = o.leaf;
    o.holder.back = o.holder;
    var c = copy(o);
    if (c.leaf === o.leaf || c.leaf.value != 7) { return 1; }
    # One copy of the leaf, shared by the outer value and the Holder's fields.
    if (c.holder.first !== c.leaf || c.holder.second !== c.leaf) { return 2; }
    if (c.holder.back !== c.holder) { return 3; }
    # Called directly, `copy()` still copies; each `copy(x)` is its own copy.
    var direct = o.holder.copy();
    if (direct.first === o.leaf || direct.first.value != 7) { return 4; }
    # Its `copy(back)` made a separate copy of the cycle.
    if (direct.back === direct || direct.back.back !== direct.back) { return 5; }
    direct.back.back = __null;
    o.holder.back = __null;
    c.holder.back = __null;
    direct.back = __null;
    return 0;
}"#,
    );
}

#[test]
fn a_deprecated_copy_taking_copies_still_implements_copyable() {
    // `copy(copies: Copies)` keeps working for one release, with a warning
    // at `Copies`.
    let source = r#"
struct Buffer {
    __ptr<u8> _data;
    String label;

    construct() {
        _data = _pep_malloc(1);
        label = "b";
    }

    destruct {
        _pep_free(_data);
    }

    copy(copies: Copies): Buffer {
        var made = Buffer();
        copies.register(this, made);
        made.label = copies.copy(label);
        return made;
    }
}

extend Buffer with Copyable<Buffer>;

struct Pair {
    Buffer a;
    Buffer b;
}

test(): int {
    var p = Pair();
    p.a = Buffer();
    p.b = p.a;
    var q = copy(p);
    if (q.a !== q.b || q.a === p.a) { return 1; }
    q.a.label.append("!");
    if (p.a.label != "b") { return 2; }
    return 0;
}"#;
    assert_runs(source);
    let module = pepper_driver::compiler::compile_with_runtime("test.pep", source).expect("compile");
    assert!(
        module.warnings.iter().any(|w| w.message.contains("'Copies' is deprecated: implement 'Copyable<T>' as 'copy(): T'")),
        "{:?}",
        module.warnings
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

/// A value enum holding a struct that cannot be copied compiles when nothing
/// copies it: `Array.copy` reaches the enum's synthesized copy, which is not
/// a request of the program.
#[test]
fn a_value_enum_of_an_uncopyable_struct_compiles_when_not_copied() {
    assert_runs(
        r#"
[NotCopyable("owns a resource")]
struct Handle {
    int id;
}

test(): int {
    var handles = Array<Optional<Handle>>();
    var h = Handle();
    h.id = 3;
    handles.append(Optional<Handle>.Value(h));
    handles.append(Optional<Handle>.Empty);
    if (handles.count != 2 || handles[0].value().id != 3 || handles[1].is_value()) { return 1; }
    return 0;
}"#,
    );
}

/// Structs behind trait values, for the trait-value tests.
const SHAPES: &str = r#"
trait Shape {
    area(): int;
    grow();
}

struct Square {
    int side;
    String name;
    construct(side: int = 0) {
        this.side = side;
        name = "square";
    }
}

extend Square with Shape {
    area(): int { return side * side; }
    grow() {
        side = side + 1;
        name.append("+");
    }
}

struct Holder {
    Shape first;
    Shape second;
    Square direct;
}
"#;

#[test]
fn trait_values_copy_the_struct_behind_them() {
    assert_runs(&format!(
        r#"{SHAPES}
test(): int {{
    Shape s = Square(3);
    var c = copy(s);
    c.grow();
    if (s.area() != 9) {{ return 1; }}
    if (c.area() != 16) {{ return 2; }}
    Shape none = __null;
    if (copy(none) != __null) {{ return 3; }}
    var shapes = Array<Shape>();
    shapes.append(Square(5));
    var copied = copy(shapes);
    copied[0].grow();
    if (shapes[0].area() != 25 || copied[0].area() != 36) {{ return 4; }}
    var pair = copy((s, 7));
    pair.0.grow();
    if (s.area() != 9 || pair.0.area() != 16) {{ return 5; }}
    return 0;
}}"#
    ));
}

#[test]
fn an_object_behind_several_references_stays_shared_in_the_copy() {
    assert_runs(&format!(
        r#"{SHAPES}
test(): int {{
    var square = Square(2);
    var holder = Holder();
    holder.first = square;
    holder.second = square;
    holder.direct = square;
    var c = copy(holder);
    c.first.grow();
    if (c.second.area() != 9) {{ return 1; }}
    if (c.direct.side != 3 || c.direct.name != "square+") {{ return 2; }}
    if (square.side != 2 || square.name != "square") {{ return 3; }}
    return 0;
}}"#
    ));
}

#[test]
fn generic_traits_value_structs_and_shared_structs_copy_through_trait_values() {
    assert_runs(
        r#"
trait Getter<T> {
    get(): T;
}

struct Box<T> {
    T value;
    Getter<T> next;
    construct(value: T) { this.value = value; }
}

extend Box<T> with Getter<T> {
    get(): T { return value; }
}

[Value]
struct Point {
    int x;
    String label;
    construct(this.x = 0, this.label = "") {}
}

extend Point with Getter<int> {
    get(): int { return x; }
}

[Shared]
struct Fixed {
    const n: int;
    construct(this.n = 0) {}
}

extend Fixed with Getter<int> {
    get(): int { return n; }
}

same(a: Getter<int>, b: Getter<int>): bool {
    return a == b;
}

test(): int {
    var b = Box<int>(4);
    b.next = Box<int>(5);
    Getter<int> g = b;
    var c = copy(g);
    if (c.get() != 4 || same(c, g)) { return 1; }
    Getter<String> text = Box<String>("hi");
    if (copy(text).get() != "hi") { return 2; }
    Getter<int> p = Point(7, "p");
    if (copy(p).get() != 7) { return 3; }
    # A thread-safe struct is shared, not copied.
    Getter<int> f = Fixed(9);
    if (!same(copy(f), f)) { return 4; }
    return 0;
}"#,
    );
}

/// What a trait value holds is known only at run time, so copying one that
/// holds a struct that cannot be copied panics.
#[test]
fn copying_a_trait_value_holding_an_uncopyable_struct_panics() {
    let source = r#"
trait Shape {
    area(): int;
}

struct Owner {
    int n;
    construct() {}
    destruct {
        n = 0;
    }
}

extend Owner with Shape {
    area(): int { return 1; }
}

main(): int {
    Shape s = Owner();
    var c = copy(s);
    return 0;
}
"#;
    let exe = crate::io_tests::build("copy_trait_uncopyable", source).expect("compile");
    let output = crate::support::run_program(&mut std::process::Command::new(&exe), source).expect("spawn");
    assert_ne!(output.status.code(), Some(0));
    let printed = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
    assert!(printed.contains("cannot copy the 'Owner' behind a trait value, which is not trivially copyable"), "{printed}");
}

