//! HashMap / HashSet and derived equality cases that check compiler
//! behaviour (codegen regressions, `==` overload resolution inside a
//! specialization, `[Equatable]` derivation rules). Runtime behaviour of the
//! hash containers is tested in `runtime/test/hash_test.pep`.

use crate::support::{compile_jit_with_runtime, jit_census};

#[test]
fn pointer_values_and_keys() {
    // `HashMap<ulong, __ptr<u8>>` once failed codegen with "storing a value
    // of LLVM type 'i32' into 'return value'" in `Array<__ptr<u8>>`'s
    // indexer: the specialization's body depended on which sema round
    // created it. Canonical specialization (#296) fixed it; the IOCP driver
    // had kept addresses as `ulong` to work around it.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Blocks<T> {
    var _by_key: HashMap<ulong, __ptr<T>>;
    construct() {
        this._by_key = HashMap<ulong, __ptr<T>>();
    }
    put(key: ulong, block: __ptr<T>) {
        this._by_key.insert(key, block);
    }
    take(key: ulong): __ptr<T> {
        return this._by_key.get(key);
    }
}
build(): int {
    var m = HashMap<ulong, __ptr<u8>>();
    var pending = HashSet<__ptr<u8>>();
    var i = 0;
    while (i < 20) {
        __ptr<u8> block = _pep_malloc(8);
        block[0] = i as u8;
        m.insert(i as ulong, block);
        pending.insert(block);
        i = i + 1;
    }
    __ptr<u8> missing = m.get(99);
    if (missing != __null) { return -1; }
    if (m.get(7)[0] != 7) { return -2; }
    if (!pending.contains(m.get(7))) { return -3; }
    var sum = 0;
    for (var entry in m) {
        var (key, block) = entry;
        if (block[0] as ulong != key) { return -4; }
        sum = sum + block[0] as int;
    }
    if (sum != 190) { return -5; }
    var blocks = Blocks<u8>();
    blocks.put(3, m.get(3));
    if (blocks.take(3)[0] != 3) { return -6; }
    for (var block in pending) {
        _pep_free(block);
    }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # The maps' tables are freed when build's scope exits; the blocks were
    # freed by hand.
    if (_pep_live_allocs() != before) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn equatable_fields_that_are_null_arrays_or_structs_compare_consistently() {
    // A null field equals only null; an `Array` field compares by its
    // elements and, since its hash is its address, adds nothing to the hash;
    // a field that is itself `[Equatable]` compares and hashes by content; a
    // generic struct derives per specialization.
    let (result, leaked) = jit_census(
        r#"
[Equatable]
struct Inner {
    String text;
}

[Equatable]
struct Outer {
    String label;
    int[] values;
    Inner inner;
}

[Equatable]
struct Box<T> {
    T value;
}

make(label: String, text: String): Outer {
    var outer = Outer();
    outer.label = label;
    outer.values = [1, 2, 3];
    outer.inner = Inner();
    outer.inner.text = text;
    return outer;
}

test(): int {
    if (Outer() != Outer()) { return -1; }
    if (Outer() == make("a", "b")) { return -2; }
    if (make("a", "b") != make("a", "b")) { return -3; }
    if (make("a", "b") == make("a", "c")) { return -4; }
    if (hash(make("a", "b")) != hash(make("a", "b"))) { return -5; }
    var other = make("a", "b");
    other.values.append(4);
    if (other == make("a", "b")) { return -6; }
    var set = HashSet<Outer>();
    set.insert(make("a", "b"));
    if (!set.contains(make("a", "b"))) { return -7; }
    var x = Box<String>();
    x.value = "q";
    var y = Box<String>();
    y.value = "q";
    if (x != y || hash(x) != hash(y)) { return -8; }
    var boxes = HashSet<Box<int>>();
    var z = Box<int>();
    z.value = 3;
    boxes.insert(z);
    var w = Box<int>();
    w.value = 3;
    if (!boxes.contains(w)) { return -9; }
    return 0;
}
"#,
    );
    assert_eq!(result, 0, "test() returned {}", result);
    assert_eq!(leaked, 0, "{} allocations leaked", leaked);
}

#[test]
fn equatable_fields_take_part_unless_excluded_either_way() {
    // `include = false` and `exclude = true` both leave a field out;
    // `include = true`, `exclude = false` and neither keep it.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
[Equatable]
struct Row {
    [Equatable(include = false)]
    int a;
    [Equatable(exclude = true)]
    int b;
    [Equatable(include = true)]
    int c;
    [Equatable(exclude = false)]
    int d;
    int e;
}

make(a: int, b: int, c: int, d: int, e: int): Row {
    var row = Row();
    row.a = a;
    row.b = b;
    row.c = c;
    row.d = d;
    row.e = e;
    return row;
}

test(): int {
    if (make(1, 2, 3, 4, 5) != make(9, 9, 3, 4, 5)) { return -1; }
    if (hash(make(1, 2, 3, 4, 5)) != hash(make(9, 9, 3, 4, 5))) { return -2; }
    if (make(1, 2, 3, 4, 5) == make(1, 2, 0, 4, 5)) { return -3; }
    if (make(1, 2, 3, 4, 5) == make(1, 2, 3, 0, 5)) { return -4; }
    if (make(1, 2, 3, 4, 5) == make(1, 2, 3, 4, 0)) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn overloaded_equality_keys() {
    // #504: a key struct whose `==` is overloaded picks the `==(A)` member
    // inside the specialized map and set, where the key is typed `K`; and a
    // raw index into an array of arrays (`Array<Array<String>>.find`) is the
    // inner array, not its element, and indexing that element still works.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
[Value]
struct A {
    int v;
    ==(rhs: int): bool { return v == rhs; }
    ==(rhs: A): bool { return v == rhs.v; }
}
hash<A>(value: A): u64 { return value.v as u64; }
make(v: int): A {
    var a = A();
    a.v = v;
    return a;
}
test(): int {
    var m = HashMap<A, int>();
    m[A()] = 3;
    m[make(7)] = 9;
    if (m[A()] != 3) { return -1; }
    if (m[make(7)] != 9) { return -2; }
    if (!m.contains(make(7)) || m.contains(make(8))) { return -3; }
    if (!m.remove(make(7)) || m.count != 1) { return -4; }
    var s = HashSet<A>();
    s.insert(make(2));
    if (!s.contains(make(2)) || s.contains(make(3))) { return -5; }
    var rows = Array<Array<String>>();
    var row = Array<String>();
    row.append("x");
    rows.append(row);
    if (!rows.find(row).is_value()) { return -6; }
    var outer = Array<Array<int>>(1);
    outer._size = 1;
    var inner = Array<int>();
    inner.append(10);
    outer._data[0] = inner;
    outer._data[0][0] += 5;
    if (inner[0] != 15 || outer._data[0][0] != 15) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn overloaded_equality_in_tuples_and_equatable_fields() {
    // A tuple element or `[Equatable]` field whose struct overloads `==`
    // compares through the member taking its own type, not by identity.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct A {
    int v;
    construct(int v) { this.v = v; }
    ==(rhs: int): bool { return v == rhs; }
    ==(rhs: A): bool { return v == rhs.v; }
}
[Equatable]
struct Holder {
    A a;
    construct(A a) { this.a = a; }
}
test(): int {
    if ((A(1), 2) != (A(1), 2)) { return -1; }
    if ((A(1), 2) == (A(3), 2)) { return -2; }
    if (Holder(A(4)) != Holder(A(4))) { return -3; }
    var some = Optional<A>.Value(A(5));
    if (some != Optional<A>.Value(A(5))) { return -4; }
    return 0;
}"#
        ),
        0
    );
}
