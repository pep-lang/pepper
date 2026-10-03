//! HashMap / HashSet API coverage: each snippet is compiled together with
//! the runtime prelude and JIT-executed through the entry function `test`.

use crate::support::{compile_jit_with_runtime, jit_census};

#[test]
fn hash_is_deterministic() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = hash<int>(5);
    var b = hash<int>(5);
    if (a != b) { return -1; }
    if (hash<String>("hello") != hash<String>("hello")) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn hash_string_override() {
    // The concrete `hash<String>` override must be used for String call
    // sites (not the generic base): equal strings at different addresses
    // hash identically, and a different String hashes differently.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a = "hello";
    var b = "hello";
    if (hash<String>(a) != hash<String>(b)) { return -1; }
    var c = "world";
    if (hash<String>(a) == hash<String>(c)) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn empty_map() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.is_empty) { return -1; }
    if (m.count != 0) { return -2; }
    if (m.contains(1)) { return -3; }
    if (m[42] != 0) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn insert_get_contains() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.insert(1, 10)) { return -1; }
    if (m.insert(2, 20) != true) { return -2; }
    if (m.count != 2) { return -3; }
    if (!m.contains(1) || !m.contains(2)) { return -4; }
    if (m[1] != 10 || m[2] != 20) { return -5; }
    if (m.get(2) != 20) { return -6; }
    if (m.get(99) != 0) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn duplicate_key_overwrites() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.insert(5, 1)) { return -1; }
    if (m.insert(5, 2) != false) { return -2; }
    if (m.count != 1) { return -3; }
    if (m[5] != 2) { return -4; }
    m[5] = 3;
    if (m[5] != 3) { return -5; }
    if (m.count != 1) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn same_bucket_collision() {
    // Two int keys that hash to the same initial bucket of an 8-slot table
    // but have distinct full hashes must be separated by probing. The second
    // key is found by search, so the test holds for any hash function.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    var other = 2;
    while ((hash<int>(other) & 7) != (hash<int>(1) & 7)) { other = other + 1; }
    if (!m.insert(1, 100)) { return -2; }
    if (!m.insert(other, 200)) { return -3; }
    if (m.count != 2) { return -4; }
    if (m[1] != 100 || m[other] != 200) { return -5; }
    if (!m.remove(1)) { return -6; }
    if (m[other] != 200) { return -7; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn growth_preserves_entries() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    var i = 0;
    while (i < 25) {
        if (!m.insert(i, i * 10)) { return -1; }
        i = i + 1;
    }
    if (m.count != 25) { return -2; }
    if (m.capacity < 64) { return -3; }
    var j = 0;
    while (j < 25) {
        if (m[j] != j * 10) { return -4; }
        j = j + 1;
    }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn remove_and_reinsert() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    if (!m.insert(3, 30)) { return -1; }
    if (!m.insert(11, 110)) { return -2; }
    if (m.remove(99) != false) { return -3; }
    if (!m.remove(3)) { return -4; }
    if (m.count != 1) { return -5; }
    if (m.contains(3)) { return -6; }
    if (m[3] != 0) { return -7; }
    if (!m.insert(3, 31)) { return -8; }
    if (m.count != 2) { return -9; }
    if (m[3] != 31 || m[11] != 110) { return -10; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn clear_empties_map() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, int>();
    m.insert(1, 1);
    m.insert(2, 2);
    m.clear();
    if (!m.is_empty) { return -1; }
    if (m.count != 0) { return -2; }
    if (!m.insert(3, 3)) { return -3; }
    if (m[3] != 3) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn struct_keys_by_identity() {
    // Struct keys hash by object address: two equal-valued Points are
    // DISTINCT keys, and a lookup finds only the exact stored object.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
}
build(): int {
    var m = HashMap<Point, int>();
    var p = Point();
    p.x = 1;
    p.y = 2;
    if (!m.insert(p, 42)) { return -1; }
    var q = Point();
    q.x = 1;
    q.y = 2;
    if (m.contains(q)) { return -2; }
    if (!m.insert(q, 7)) { return -3; }
    if (m.count != 2) { return -4; }
    if (m.get(p) != 42 || m.get(q) != 7) { return -5; }
    if (!m.remove(q)) { return -6; }
    if (m.count != 1 || !m.contains(p)) { return -7; }
    if (m.get(p) != 42) { return -8; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn string_keys_by_content() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<String, int>();
    if (!m.insert("hello", 1)) { return -1; }
    var s = "hello";
    if (!m.contains(s)) { return -2; }
    if (m.get(s) != 1) { return -3; }
    m[s] = 5;
    if (m["hello"] != 5) { return -4; }
    if (m.count != 1) { return -5; }
    if (!m.insert("world", 2)) { return -6; }
    if (m.count != 2) { return -7; }
    if (m["hello"] != 5 || m["world"] != 2) { return -8; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn empty_set() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = HashSet<int>();
    if (!s.is_empty) { return -1; }
    if (s.count != 0) { return -2; }
    if (s.contains(1)) { return -3; }
    if (s[7] != 0) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn set_insert_contains_remove() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = HashSet<int>();
    if (!s.insert(1)) { return -1; }
    if (s.insert(1) != false) { return -2; }
    if (s.count != 1) { return -3; }
    if (!s.contains(1)) { return -4; }
    if (s[1] != 1) { return -5; }
    if (s[9] != 0) { return -6; }
    s[2] = 2;
    if (s.count != 2) { return -7; }
    if (!s.remove(1)) { return -8; }
    if (s.remove(1) != false) { return -9; }
    if (s.count != 1 || !s.contains(2)) { return -10; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn set_growth_and_clear() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var s = HashSet<int>();
    var i = 0;
    while (i < 20) {
        if (!s.insert(i)) { return -1; }
        i = i + 1;
    }
    if (s.count != 20) { return -2; }
    var j = 0;
    while (j < 20) {
        if (!s.contains(j)) { return -3; }
        j = j + 1;
    }
    s.clear();
    if (!s.is_empty) { return -4; }
    if (!s.insert(5)) { return -5; }
    if (s.count != 1) { return -6; }
    return 0;
}
"#
        ),
        0
    );
}

#[test]
fn set_struct_keys_identity() {
    // Struct elements hash by address: equal-valued Points are distinct
    // members, and remove finds only the exact stored object.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
}
build(): int {
    var s = HashSet<Point>();
    var p = Point();
    p.x = 3;
    p.y = 4;
    if (!s.insert(p)) { return -1; }
    var q = Point();
    q.x = 3;
    q.y = 4;
    if (!s.insert(q)) { return -2; }
    if (s.count != 2) { return -3; }
    var r = Point();
    r.x = 4;
    r.y = 3;
    if (!s.insert(r)) { return -4; }
    if (s.count != 3) { return -5; }
    if (!s.remove(q)) { return -6; }
    if (s.count != 2 || !s.contains(p) || !s.contains(r)) { return -7; }
    if (s.contains(q)) { return -8; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn map_string_values_refcounted() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = HashMap<int, String>();
    if (!m.insert(1, "alpha")) { return -1; }
    if (m[1] != "alpha") { return -2; }
    m[1] = "beta";
    if (m[1] != "beta") { return -3; }
    if (m.count != 1) { return -4; }
    if (!m.remove(1)) { return -5; }
    if (!m.is_empty) { return -6; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn map_release_frees_contents() {
    // The map and its contents are allocated inside `build`; when build's
    // scope exits, the automatic releases must free every allocation made
    // for the map (Point keys, String values, arrays).
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
}
build(): int {
    var m = HashMap<Point, String>();
    var p1 = Point();
    p1.x = 1;
    p1.y = 2;
    var p2 = Point();
    p2.x = 2;
    p2.y = 4;
    var p3 = Point();
    p3.x = 3;
    p3.y = 6;
    var s1 = "one";
    var s2 = "two";
    var s3 = "three";
    if (!m.insert(p1, s1)) { return -1; }
    if (!m.insert(p2, s2)) { return -2; }
    if (!m.insert(p3, s3)) { return -3; }
    # The map's slots hold one ref each (acquired on insert); build's
    # scope exit drops the creators' refs.
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation made for the map and its contents must be freed.
    if (_pep_live_allocs() != before) { return -4; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn many_struct_keys_same_bucket() {
    // Regression: every `_pep_malloc` result is 8-byte aligned, so a raw
    // address hash lands ALL struct keys in bucket 0 of a small table. The
    // address bits must be folded through FNV and the probe sequence must
    // cover every slot, or the 4th insert finds no empty slot at capacity 8
    // and is silently dropped. Struct keys are identity-hashed, so lookups
    // re-use the stored objects themselves.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
}
build(): int {
    var m = HashMap<Point, int>(8);
    var kept = Array<Point>();
    var i = 0;
    while (i < 4) {
        var p = Point();
        p.x = i + 1;
        p.y = (i + 1) * 2;
        if (!m.insert(p, (i + 1) * 10)) { return -1 - i; }
        kept.append(p);
        i = i + 1;
    }
    if (m.count != 4) { return -5; }
    if (m.get(kept[2]) != 30) { return -6; }
    var fresh = Point();
    fresh.x = 3;
    fresh.y = 6;
    if (m.contains(fresh)) { return -7; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -8; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn many_struct_set_members_same_bucket() {
    // Same regression as `many_struct_keys_same_bucket`, for HashSet: four
    // distinct Point members must all be stored and found at capacity 8.
    // Identity-hashed, so lookups re-use the stored objects themselves.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Point {
    int x;
    int y;
    construct(this.x = 0, this.y = 0) {}
}
build(): int {
    var s = HashSet<Point>(8);
    var kept = Array<Point>();
    var i = 0;
    while (i < 4) {
        var p = Point();
        p.x = i + 1;
        p.y = (i + 1) * 2;
        if (!s.insert(p)) { return -1 - i; }
        kept.append(p);
        i = i + 1;
    }
    if (s.count != 4) { return -5; }
    if (!s.contains(kept[1])) { return -6; }
    var fresh = Point();
    fresh.x = 9;
    fresh.y = 9;
    if (s.contains(fresh)) { return -7; }
    return 0;
}
test(): int {
    long before = _pep_live_allocs();
    var r = build();
    if (r != 0) { return r; }
    # Every allocation must be freed when build's scope exits.
    if (_pep_live_allocs() != before) { return -8; }
    return 0;
}"#
        ),
        0
    );
}

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
fn struct_keys_with_their_own_hash_and_equality_match_by_content() {
    // A struct that declares `==` and overrides `hash<T>` is keyed by its
    // fields: a fresh object with equal fields finds, replaces and removes
    // the stored entry, through every HashMap and HashSet path (insert,
    // lookup, remove, growth, iteration, copy), with no leaked references.
    let (result, leaked) = jit_census(
        r#"
struct Person {
    String name;
    int id;
    String nickname;

    construct(this.name = "", this.id = 0, this.nickname = "") {}

    ==(other: Person): bool {
        return id == other.id and name == other.name;
    }
}

hash<Person>(value: Person): u64 {
    return hash<(String, int)>((value.name, value.id));
}

test(): int {
    var ages = HashMap<Person, int>();
    var i = 0;
    while (i < 100) {
        ages[Person($"p{i}", i)] = i;
        i = i + 1;
    }
    if (ages.count != 100) { return -1; }
    if (ages[Person("p42", 42, "nick")] != 42) { return -2; }
    if (ages.insert(Person("p7", 7), 70)) { return -3; }
    if (ages[Person("p7", 7)] != 70 || ages.count != 100) { return -4; }
    if (ages.contains(Person("p7", 8))) { return -5; }
    if (!ages.remove(Person("p7", 7)) || ages.contains(Person("p7", 7))) { return -6; }
    var total = 0;
    for (var (person, age) in ages) {
        total += age;
    }
    if (total != 4950 - 7) { return -7; }
    var people = HashSet<Person>();
    people.insert(Person("Ada", 1, "A"));
    if (people.insert(Person("Ada", 1, "Countess"))) { return -8; }
    if (people[Person("Ada", 1)].nickname != "A") { return -9; }
    var copied = copy(people);
    if (!copied.contains(Person("Ada", 1))) { return -10; }
    return 0;
}
"#,
    );
    assert_eq!(result, 0, "test() returned {}", result);
    assert_eq!(leaked, 0, "{} allocations leaked", leaked);
}

#[test]
fn equatable_struct_keys_match_by_their_compared_fields() {
    // `[Equatable]` derives `==` and the hash from the fields, leaving out a
    // `[Equatable(exclude = true)]` one: the same paths as a hand-written pair, with no
    // leaked references.
    let (result, leaked) = jit_census(
        r#"
[Equatable]
struct Person {
    String name;
    int id;
    [Equatable(exclude = true)]
    String nickname;

    construct(this.name = "", this.id = 0, this.nickname = "") {}
}

test(): int {
    var ages = HashMap<Person, int>();
    var i = 0;
    while (i < 100) {
        ages[Person($"p{i}", i)] = i;
        i = i + 1;
    }
    if (ages.count != 100) { return -1; }
    if (ages[Person("p42", 42, "nick")] != 42) { return -2; }
    if (ages.insert(Person("p7", 7), 70)) { return -3; }
    if (ages[Person("p7", 7)] != 70 || ages.count != 100) { return -4; }
    if (ages.contains(Person("p7", 8))) { return -5; }
    if (!ages.remove(Person("p7", 7)) || ages.contains(Person("p7", 7))) { return -6; }
    var people = HashSet<Person>();
    people.insert(Person("Ada", 1, "A"));
    if (people.insert(Person("Ada", 1, "Countess"))) { return -7; }
    if (people[Person("Ada", 1)].nickname != "A") { return -8; }
    if (Person("Ada", 1) != Person("Ada", 1, "B")) { return -9; }
    if (Person("Ada", 1) == Person("Ada", 2)) { return -10; }
    if (hash(Person("Ada", 1, "x")) != hash(Person("Ada", 1, "y"))) { return -11; }
    return 0;
}
"#,
    );
    assert_eq!(result, 0, "test() returned {}", result);
    assert_eq!(leaked, 0, "{} allocations leaked", leaked);
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
fn equatable_enum_keys_match_by_case_and_values() {
    let (result, leaked) = jit_census(
        r#"
[Equatable]
enum Token {
    Word(text: String),
    Number(value: int),
    End,
}

test(): int {
    if (Token.Word("a") != Token.Word("a")) { return -1; }
    if (Token.Word("a") == Token.Word("b")) { return -2; }
    if (Token.Number(0) == Token.End) { return -3; }
    if (Token.End != Token.End) { return -4; }
    var counts = HashMap<Token, int>();
    counts[Token.Word("x")] = 1;
    counts[Token.Number(2)] = 2;
    counts[Token.End] = 3;
    if (counts[Token.Word("x")] != 1 || counts[Token.Number(2)] != 2 || counts[Token.End] != 3) { return -5; }
    if (counts.contains(Token.Number(3))) { return -6; }
    return 0;
}
"#,
    );
    assert_eq!(result, 0, "test() returned {}", result);
    assert_eq!(leaked, 0, "{} allocations leaked", leaked);
}

#[test]
fn tuple_keys_holding_arrays_find_equal_arrays() {
    // An `Array` compares by its elements but hashes by its address, so a
    // tuple's hash leaves it out: equal tuples hash equally.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var a: int[] = [1, 2];
    var b: int[] = [1, 2];
    if (hash((a, 5)) != hash((b, 5))) { return -1; }
    var set = HashSet<(int[], int)>();
    set.insert((a, 5));
    if (!set.contains((b, 5))) { return -2; }
    return 0;
}"#
        ),
        0
    );
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
