//! Map / Set (sorted, red-black tree) and OrderedMap (insertion order)
//! coverage: each snippet is compiled together with the runtime prelude and
//! JIT-executed through the entry function `test`.

use crate::support::{compile_jit_with_runtime, jit_census, run_linked};

#[test]
fn map_iterates_in_key_order() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var scores = Map<String, int>();
    if (!scores.is_empty || scores.count != 0) { return -1; }
    scores["carol"] = 91;
    scores["alice"] = 84;
    scores["bob"] = 77;
    if (scores.insert("alice", 85)) { return -2; }
    if (scores.count != 3 || scores["alice"] != 85) { return -3; }
    var names = "";
    for (var (name, score) in scores) {
        names = names + name + ",";
    }
    if (names != "alice,bob,carol,") { return -4; }
    var reversed = "";
    for (var (name, score) in scores.reversed()) {
        reversed = reversed + name + ",";
    }
    if (reversed != "carol,bob,alice,") { return -5; }
    var ranged = "";
    for (var (name, score) in scores.range("b", "c")) {
        ranged = ranged + name + ",";
    }
    if (ranged != "bob,") { return -6; }
    for (var (name, score) in scores.range("c", "b")) {
        return -7;
    }
    for (var (name, score) in scores.range("d", "z")) {
        return -8;
    }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn map_lookups_and_order_queries() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = Map<int, int>();
    if (m.first().is_value() || m.last().is_value()) { return -1; }
    m[30] = 3;
    m[10] = 1;
    m[20] = 2;
    if (m.first().value().0 != 10 || m.last().value().0 != 30) { return -2; }
    if (m.lower_bound(20).value().0 != 20) { return -3; }
    if (m.lower_bound(15).value().1 != 2) { return -4; }
    if (m.upper_bound(20).value().0 != 30) { return -5; }
    if (m.upper_bound(30).is_value() || m.lower_bound(31).is_value()) { return -6; }
    if (m.lower_bound(0).value().0 != 10) { return -7; }
    if (m.try_get(20).value() != 2 || m.try_get(25).is_value()) { return -8; }
    if (m.get(25) != 0 || m[25] != 0 || m.contains(25)) { return -9; }
    if (!m.remove(20) || m.remove(20) || m.count != 2) { return -10; }
    m.clear();
    if (!m.is_empty || m.first().is_value()) { return -11; }
    m[5] = 50;
    if (m[5] != 50) { return -12; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn map_stays_balanced_through_random_inserts_and_removes() {
    // Checks the red-black rules (no red node with a red child, equal black
    // heights, a black root), the parent links and the key order after every
    // hundred operations, against a shadow array of which keys are present.
    assert_eq!(
        compile_jit_with_runtime(
            r#"
black_height(m: Map<int, int>, node: ulong): int {
    if (node == 0) { return 1; }
    var red = m._tree._red[node];
    var left = m._tree._left[node];
    var right = m._tree._right[node];
    if (red and (m._tree._red[left] or m._tree._red[right])) { return -1; }
    if (left != 0 and (m._tree._parent[left] != node or m._tree._keys[left] >= m._tree._keys[node])) { return -1; }
    if (right != 0 and (m._tree._parent[right] != node or m._tree._keys[right] <= m._tree._keys[node])) { return -1; }
    var left_height = black_height(m, left);
    var right_height = black_height(m, right);
    if (left_height < 0 or left_height != right_height) { return -1; }
    return left_height + (red ? 0 : 1);
}

test(): int {
    var m = Map<int, int>();
    var present = Array<bool>();
    var i = 0;
    while (i < 500) {
        present.append(false);
        i += 1;
    }
    long seed = 12345;
    var expected = 0;
    var step = 0;
    while (step < 6000) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        var key = ((seed >> 8) % 500) as int;
        if ((seed >> 4) % 3 == 0) {
            if (m.remove(key) != present[key as ulong]) { return -1; }
            if (present[key as ulong]) { expected -= 1; }
            present[key as ulong] = false;
        } else {
            if (m.insert(key, key * 2) == present[key as ulong]) { return -2; }
            if (!present[key as ulong]) { expected += 1; }
            present[key as ulong] = true;
        }
        if (m.count != expected) { return -3; }
        if (step % 100 == 0) {
            if (m._tree._red[m._tree._root] or m._tree._parent[m._tree._root] != 0) { return -4; }
            if (black_height(m, m._tree._root) < 0) { return -5; }
        }
        step += 1;
    }
    var previous = -1;
    var seen = 0;
    for (var (key, value) in m) {
        if (key <= previous || value != key * 2 || !present[key as ulong]) { return -6; }
        previous = key;
        seen += 1;
    }
    if (seen != expected) { return -7; }
    # Removed nodes are reused, so the arrays never outgrow the key range.
    if (m._tree._keys.count > 501) { return -8; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn set_is_sorted_and_converts_from_an_array() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    Set<int> primes = [7, 2, 5, 3, 2];
    if (primes.count != 4) { return -1; }
    var order = 0;
    for (var p in primes) {
        order = order * 10 + p;
    }
    if (order != 2357) { return -2; }
    order = 0;
    for (var p in primes.reversed()) {
        order = order * 10 + p;
    }
    if (order != 7532) { return -3; }
    order = 0;
    for (var p in primes.range(3, 7)) {
        order = order * 10 + p;
    }
    if (order != 35) { return -4; }
    if (primes.first().value() != 2 || primes.last().value() != 7) { return -5; }
    if (primes.lower_bound(4).value() != 5 || primes.upper_bound(5).value() != 7) { return -6; }
    if (primes.upper_bound(7).is_value()) { return -7; }
    if (primes.insert(3) || !primes.insert(11) || !primes.contains(11)) { return -8; }
    if (!primes.remove(2) || primes.contains(2) || primes.remove(2)) { return -9; }
    var copied = copy(primes);
    primes.clear();
    if (!primes.is_empty || copied.count != 4 || copied.first().value() != 3) { return -10; }
    Set<String> words = ["pear", "apple", "fig"];
    if (words.first().value() != "apple" || words.last().value() != "pear") { return -11; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn struct_keys_order_by_their_less_than_operator_or_a_compare_override() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
struct Version {
    int major;
    int minor;

    construct(this.major = 0, this.minor = 0) {}

    <(other: Version): bool {
        return major < other.major or (major == other.major and minor < other.minor);
    }
}

struct Point {
    int x;
    int y;

    construct(this.x = 0, this.y = 0) {}
}

compare<Point>(a: Point, b: Point): int {
    return a.x != b.x ? a.x - b.x : a.y - b.y;
}

test(): int {
    var releases = Map<Version, String>();
    releases[Version(1, 10)] = "c";
    releases[Version(0, 2)] = "a";
    releases[Version(1, 2)] = "b";
    releases[Version(1, 2)] = "b2";
    if (releases.count != 3) { return -1; }
    var names = "";
    for (var (version, name) in releases) {
        names = names + name;
    }
    if (names != "ab2c") { return -2; }
    var points = Set<Point>();
    points.insert(Point(2, 1));
    points.insert(Point(1, 5));
    points.insert(Point(2, 0));
    if (points.insert(Point(1, 5))) { return -3; }
    var first = points.first().value();
    if (first.x != 1 || first.y != 5) { return -4; }
    if (!points.contains(Point(2, 0))) { return -5; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn ordered_map_keeps_insertion_order() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var config = OrderedMap<String, String>();
    if (!config.is_empty) { return -1; }
    config["name"] = "pepper";
    config["version"] = "0.2";
    config["license"] = "MIT";
    if (config.insert("name", "Pepper")) { return -2; }
    var keys = "";
    for (var (key, value) in config) {
        keys = keys + key + "=" + value + ",";
    }
    if (keys != "name=Pepper,version=0.2,license=MIT,") { return -3; }
    if (!config.remove("version") || config.contains("version") || config.count != 2) { return -4; }
    config["version"] = "0.3";
    keys = "";
    for (var (key, value) in config) {
        keys = keys + key + ",";
    }
    if (keys != "name,license,version,") { return -5; }
    if (config.try_get("license").value() != "MIT" || config.try_get("x").is_value()) { return -6; }
    if (config.contains("x") || config["name"] != "Pepper") { return -7; }
    var copied = copy(config);
    config.clear();
    if (!config.is_empty || copied.count != 3) { return -8; }
    keys = "";
    for (var (key, value) in copied) {
        keys = keys + key + ",";
    }
    if (keys != "name,license,version,") { return -9; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn ordered_map_compacts_after_many_removals() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var m = OrderedMap<int, int>();
    var i = 0;
    while (i < 1000) {
        m[999 - i] = i;
        i += 1;
    }
    i = 0;
    while (i < 1000) {
        if (i % 5 != 0) {
            if (!m.remove(i)) { return -1; }
        }
        i += 1;
    }
    if (m.count != 200) { return -2; }
    # Holes are compacted once they outnumber the entries.
    if (m._keys.count > 400) { return -3; }
    var previous = 1000;
    for (var (key, value) in m) {
        if (key >= previous || key % 5 != 0 || value != 999 - key) { return -4; }
        previous = key;
    }
    i = 0;
    while (i < 1000) {
        if (m.contains(i) != (i % 5 == 0)) { return -5; }
        if (i % 5 == 0 && m[i] != 999 - i) { return -6; }
        i += 1;
    }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn hash_map_try_get() {
    assert_eq!(
        compile_jit_with_runtime(
            r#"
test(): int {
    var ages = HashMap<String, int>();
    ages["ada"] = 36;
    if (ages.try_get("ada").value() != 36) { return -1; }
    if (ages.try_get("alan").is_value()) { return -2; }
    return 0;
}"#
        ),
        0
    );
}

#[test]
fn ordered_collections_release_their_keys_and_values() {
    let (result, leaked) = jit_census(
        r#"
struct Box {
    int n;
    construct(this.n = 0) {}
}

test(): int {
    var sorted = Map<String, Box>();
    var members = Set<String>();
    var ordered = OrderedMap<String, Box>();
    var i = 0;
    while (i < 200) {
        sorted[$"k{i}"] = Box(i);
        members.insert($"k{i}");
        ordered[$"k{i}"] = Box(i);
        i += 1;
    }
    sorted["k3"] = Box(-3);
    ordered["k3"] = Box(-3);
    i = 0;
    while (i < 200) {
        if (i % 2 == 0) {
            sorted.remove($"k{i}");
            members.remove($"k{i}");
            ordered.remove($"k{i}");
        }
        i += 1;
    }
    var total = 0;
    for (var (key, box) in sorted) {
        total += box.n;
    }
    for (var (key, box) in ordered) {
        total += box.n;
    }
    if (sorted.first().value().1.n != 1 || members.count != 100) { return -1; }
    var copied = copy(sorted);
    sorted.clear();
    ordered.clear();
    if (copied.count != 100) { return -2; }
    return total == 2 * (10000 - 6) ? 0 : -3;
}
"#,
    );
    assert_eq!(result, 0, "test() returned {}", result);
    assert_eq!(leaked, 0, "{} allocations leaked", leaked);
}

#[test]
fn inserting_while_iterating_ordered_collections_panics() {
    for (name, kind, message) in [
        ("map_insert", "Map", "Map modified during iteration"),
        ("ordered_map_insert", "OrderedMap", "OrderedMap modified during iteration"),
    ] {
        let source = format!(
            r#"
main(): int {{
    var m = {kind}<int, int>();
    m[1] = 1;
    for (var (k, v) in m) {{
        m[k + 100] = v;
    }}
    return 0;
}}
"#
        );
        let output = run_linked(name, &source, |_| {});
        let stdout = crate::support::output_text(&output);
        assert!(!output.status.success(), "{name}: expected a panic; stdout: {stdout:?}");
        assert!(stdout.contains(message), "{name}: stdout: {stdout:?}");
    }
}
