# Map and Set (sorted, red-black tree) and OrderedMap (insertion order):
# iteration order, lookups and order queries, tree balance, struct keys,
# compaction, releasing contents, and modification during iteration.

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

struct Box {
    int n;

    construct(this.n = 0) {}
}

[Test]
map_iterates_in_key_order() {
    var scores = Map<String, int>();
    expect_true(scores.is_empty);
    expect_equal(scores.count, 0);
    scores["carol"] = 91;
    scores["alice"] = 84;
    scores["bob"] = 77;
    expect_false(scores.insert("alice", 85));
    expect_equal(scores.count, 3);
    expect_equal(scores["alice"], 85);
    var names = "";
    for (var (name, score) in scores) {
        names = names + name + ",";
    }
    expect_equal(names, "alice,bob,carol,");
    var reversed = "";
    for (var (name, score) in scores.reversed()) {
        reversed = reversed + name + ",";
    }
    expect_equal(reversed, "carol,bob,alice,");
    var ranged = "";
    for (var (name, score) in scores.range("b", "c")) {
        ranged = ranged + name + ",";
    }
    expect_equal(ranged, "bob,");
    var empty_ranges = 0;
    for (var (name, score) in scores.range("c", "b")) {
        empty_ranges += 1;
    }
    for (var (name, score) in scores.range("d", "z")) {
        empty_ranges += 1;
    }
    expect_equal(empty_ranges, 0);
}

[Test]
map_lookups_and_order_queries() {
    var m = Map<int, int>();
    expect_false(m.first().is_value());
    expect_false(m.last().is_value());
    m[30] = 3;
    m[10] = 1;
    m[20] = 2;
    expect_equal(m.first().value().0, 10);
    expect_equal(m.last().value().0, 30);
    expect_equal(m.lower_bound(20).value().0, 20);
    expect_equal(m.lower_bound(15).value().1, 2);
    expect_equal(m.upper_bound(20).value().0, 30);
    expect_false(m.upper_bound(30).is_value());
    expect_false(m.lower_bound(31).is_value());
    expect_equal(m.lower_bound(0).value().0, 10);
    expect_equal(m.try_get(20).value(), 2);
    expect_false(m.try_get(25).is_value());
    expect_equal(m.get(25), 0);
    expect_equal(m[25], 0);
    expect_false(m.contains(25));
    expect_true(m.remove(20));
    expect_false(m.remove(20));
    expect_equal(m.count, 2);
    m.clear();
    expect_true(m.is_empty);
    expect_false(m.first().is_value());
    m[5] = 50;
    expect_equal(m[5], 50);
}

# The black height of the subtree at `node`, or -1 when it breaks a
# red-black rule, a parent link or the key order.
black_height(m: Map<int, int>, node: ulong): int {
    if (node == 0) {
        return 1;
    }
    var red = m._tree._red[node];
    var left = m._tree._left[node];
    var right = m._tree._right[node];
    if (red and (m._tree._red[left] or m._tree._red[right])) {
        return -1;
    }
    if (left != 0 and (m._tree._parent[left] != node or m._tree._keys[left] >= m._tree._keys[node])) {
        return -1;
    }
    if (right != 0 and (m._tree._parent[right] != node or m._tree._keys[right] <= m._tree._keys[node])) {
        return -1;
    }
    var left_height = black_height(m, left);
    var right_height = black_height(m, right);
    if (left_height < 0 or left_height != right_height) {
        return -1;
    }
    return left_height + (red ? 0 : 1);
}

# Checks the red-black rules (no red node with a red child, equal black
# heights, a black root), the parent links and the key order after every
# hundred operations, against a shadow array of which keys are present.
[Test]
map_stays_balanced_through_random_inserts_and_removes() {
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
            expect_equal(m.remove(key), present[key as ulong]);
            if (present[key as ulong]) {
                expected -= 1;
            }
            present[key as ulong] = false;
        } else {
            expect_not_equal(m.insert(key, key * 2), present[key as ulong]);
            if (!present[key as ulong]) {
                expected += 1;
            }
            present[key as ulong] = true;
        }
        expect_equal(m.count, expected as ulong);
        if (step % 100 == 0) {
            expect_false(m._tree._red[m._tree._root]);
            expect_equal(m._tree._parent[m._tree._root], 0);
            expect_true(black_height(m, m._tree._root) >= 0);
        }
        step += 1;
    }
    var previous = -1;
    var seen = 0;
    for (var (key, value) in m) {
        expect_true(key > previous);
        expect_equal(value, key * 2);
        expect_true(present[key as ulong]);
        previous = key;
        seen += 1;
    }
    expect_equal(seen, expected);
    # Removed nodes are reused, so the arrays never outgrow the key range.
    expect_true(m._tree._keys.count <= 501);
}

[Test]
set_is_sorted_and_converts_from_an_array() {
    Set<int> primes = [7, 2, 5, 3, 2];
    expect_equal(primes.count, 4);
    var order = 0;
    for (var p in primes) {
        order = order * 10 + p;
    }
    expect_equal(order, 2357);
    order = 0;
    for (var p in primes.reversed()) {
        order = order * 10 + p;
    }
    expect_equal(order, 7532);
    order = 0;
    for (var p in primes.range(3, 7)) {
        order = order * 10 + p;
    }
    expect_equal(order, 35);
    expect_equal(primes.first().value(), 2);
    expect_equal(primes.last().value(), 7);
    expect_equal(primes.lower_bound(4).value(), 5);
    expect_equal(primes.upper_bound(5).value(), 7);
    expect_false(primes.upper_bound(7).is_value());
    expect_false(primes.insert(3));
    expect_true(primes.insert(11));
    expect_true(primes.contains(11));
    expect_true(primes.remove(2));
    expect_false(primes.contains(2));
    expect_false(primes.remove(2));
    var copied = copy(primes);
    primes.clear();
    expect_true(primes.is_empty);
    expect_equal(copied.count, 4);
    expect_equal(copied.first().value(), 3);
    Set<String> words = ["pear", "apple", "fig"];
    expect_equal(words.first().value(), "apple");
    expect_equal(words.last().value(), "pear");
}

[Test]
struct_keys_order_by_their_less_than_operator_or_a_compare_override() {
    var releases = Map<Version, String>();
    releases[Version(1, 10)] = "c";
    releases[Version(0, 2)] = "a";
    releases[Version(1, 2)] = "b";
    releases[Version(1, 2)] = "b2";
    expect_equal(releases.count, 3);
    var names = "";
    for (var (version, name) in releases) {
        names = names + name;
    }
    expect_equal(names, "ab2c");
    var points = Set<Point>();
    points.insert(Point(2, 1));
    points.insert(Point(1, 5));
    points.insert(Point(2, 0));
    expect_false(points.insert(Point(1, 5)));
    var first = points.first().value();
    expect_equal(first.x, 1);
    expect_equal(first.y, 5);
    expect_true(points.contains(Point(2, 0)));
}

[Test]
ordered_map_keeps_insertion_order() {
    var config = OrderedMap<String, String>();
    expect_true(config.is_empty);
    config["name"] = "pepper";
    config["version"] = "0.2";
    config["license"] = "MIT";
    expect_false(config.insert("name", "Pepper"));
    var keys = "";
    for (var (key, value) in config) {
        keys = keys + key + "=" + value + ",";
    }
    expect_equal(keys, "name=Pepper,version=0.2,license=MIT,");
    expect_true(config.remove("version"));
    expect_false(config.contains("version"));
    expect_equal(config.count, 2);
    config["version"] = "0.3";
    keys = "";
    for (var (key, value) in config) {
        keys = keys + key + ",";
    }
    expect_equal(keys, "name,license,version,");
    expect_equal(config.try_get("license").value(), "MIT");
    expect_false(config.try_get("x").is_value());
    expect_false(config.contains("x"));
    expect_equal(config["name"], "Pepper");
    var copied = copy(config);
    config.clear();
    expect_true(config.is_empty);
    expect_equal(copied.count, 3);
    keys = "";
    for (var (key, value) in copied) {
        keys = keys + key + ",";
    }
    expect_equal(keys, "name,license,version,");
}

[Test]
ordered_map_compacts_after_many_removals() {
    var m = OrderedMap<int, int>();
    var i = 0;
    while (i < 1000) {
        m[999 - i] = i;
        i += 1;
    }
    i = 0;
    while (i < 1000) {
        if (i % 5 != 0) {
            expect_true(m.remove(i));
        }
        i += 1;
    }
    expect_equal(m.count, 200);
    # Holes are compacted once they outnumber the entries.
    expect_true(m._keys.count <= 400);
    var previous = 1000;
    for (var (key, value) in m) {
        expect_true(key < previous);
        expect_equal(key % 5, 0);
        expect_equal(value, 999 - key);
        previous = key;
    }
    i = 0;
    while (i < 1000) {
        expect_equal(m.contains(i), i % 5 == 0);
        if (i % 5 == 0) {
            expect_equal(m[i], 999 - i);
        }
        i += 1;
    }
}

[Test]
hash_map_try_get() {
    var ages = HashMap<String, int>();
    ages["ada"] = 36;
    expect_equal(ages.try_get("ada").value(), 36);
    expect_false(ages.try_get("alan").is_value());
}

[Test]
ordered_collections_release_their_keys_and_values() {
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
    expect_equal(sorted.first().value().1.n, 1);
    expect_equal(members.count, 100);
    var copied = copy(sorted);
    sorted.clear();
    ordered.clear();
    expect_equal(copied.count, 100);
    expect_equal(total, 2 * (10000 - 6));
}

[Test]
[ShouldPanic("Map modified during iteration")]
inserting_while_iterating_a_map_panics() {
    var m = Map<int, int>();
    m[1] = 1;
    for (var (key, value) in m) {
        m[key + 100] = value;
    }
}

[Test]
[ShouldPanic("OrderedMap modified during iteration")]
inserting_while_iterating_an_ordered_map_panics() {
    var m = OrderedMap<int, int>();
    m[1] = 1;
    for (var (key, value) in m) {
        m[key + 100] = value;
    }
}
