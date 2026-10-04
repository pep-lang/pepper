# HashMap and HashSet, and the hash function: inserting, finding, removing,
# growing and clearing; keys hashed by identity (structs), by content
# (strings, tuples) or by a struct's own or derived `==` and hash; and
# releasing what a map holds, nested containers included.

struct Point {
    int x;
    int y;

    construct(this.x = 0, this.y = 0) {}
}

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

[Equatable]
struct EquatablePerson {
    String name;
    int id;
    [Equatable(exclude = true)]
    String nickname;

    construct(this.name = "", this.id = 0, this.nickname = "") {}
}

[Equatable]
enum Token {
    Word(text: String),
    Number(value: int),
    End,
}

[Test]
hash_is_deterministic() {
    expect_equal(hash<int>(5), hash<int>(5));
    expect_equal(hash<String>("hello"), hash<String>("hello"));
}

# The concrete `hash<String>` override is used for String call sites (not
# the generic base): equal strings at different addresses hash identically,
# and a different String hashes differently.
[Test]
hash_string_override() {
    var a = "hello";
    var b = "hello";
    expect_equal(hash<String>(a), hash<String>(b));
    var c = "world";
    expect_not_equal(hash<String>(a), hash<String>(c));
}

[Test]
empty_map() {
    var m = HashMap<int, int>();
    expect_true(m.is_empty);
    expect_equal(m.count, 0);
    expect_false(m.contains(1));
    expect_equal(m[42], 0);
}

[Test]
insert_get_contains() {
    var m = HashMap<int, int>();
    expect_true(m.insert(1, 10));
    expect_true(m.insert(2, 20));
    expect_equal(m.count, 2);
    expect_true(m.contains(1));
    expect_true(m.contains(2));
    expect_equal(m[1], 10);
    expect_equal(m[2], 20);
    expect_equal(m.get(2), 20);
    expect_equal(m.get(99), 0);
}

[Test]
duplicate_key_overwrites() {
    var m = HashMap<int, int>();
    expect_true(m.insert(5, 1));
    expect_false(m.insert(5, 2));
    expect_equal(m.count, 1);
    expect_equal(m[5], 2);
    m[5] = 3;
    expect_equal(m[5], 3);
    expect_equal(m.count, 1);
}

# Two int keys that hash to the same initial bucket of an 8-slot table but
# have distinct full hashes are separated by probing. The second key is
# found by search, so the test holds for any hash function.
[Test]
same_bucket_collision() {
    var m = HashMap<int, int>();
    var other = 2;
    while ((hash<int>(other) & 7) != (hash<int>(1) & 7)) {
        other = other + 1;
    }
    expect_true(m.insert(1, 100));
    expect_true(m.insert(other, 200));
    expect_equal(m.count, 2);
    expect_equal(m[1], 100);
    expect_equal(m[other], 200);
    expect_true(m.remove(1));
    expect_equal(m[other], 200);
}

[Test]
growth_preserves_entries() {
    var m = HashMap<int, int>();
    var i = 0;
    while (i < 25) {
        expect_true(m.insert(i, i * 10));
        i = i + 1;
    }
    expect_equal(m.count, 25);
    expect_true(m.capacity >= 64);
    var j = 0;
    while (j < 25) {
        expect_equal(m[j], j * 10);
        j = j + 1;
    }
}

[Test]
remove_and_reinsert() {
    var m = HashMap<int, int>();
    expect_true(m.insert(3, 30));
    expect_true(m.insert(11, 110));
    expect_false(m.remove(99));
    expect_true(m.remove(3));
    expect_equal(m.count, 1);
    expect_false(m.contains(3));
    expect_equal(m[3], 0);
    expect_true(m.insert(3, 31));
    expect_equal(m.count, 2);
    expect_equal(m[3], 31);
    expect_equal(m[11], 110);
}

[Test]
clear_empties_map() {
    var m = HashMap<int, int>();
    m.insert(1, 1);
    m.insert(2, 2);
    m.clear();
    expect_true(m.is_empty);
    expect_equal(m.count, 0);
    expect_true(m.insert(3, 3));
    expect_equal(m[3], 3);
}

# Struct keys hash by object address: two equal-valued Points are distinct
# keys, and a lookup finds only the exact stored object.
[Test]
struct_keys_by_identity() {
    var m = HashMap<Point, int>();
    var p = Point(1, 2);
    expect_true(m.insert(p, 42));
    var q = Point(1, 2);
    expect_false(m.contains(q));
    expect_true(m.insert(q, 7));
    expect_equal(m.count, 2);
    expect_equal(m.get(p), 42);
    expect_equal(m.get(q), 7);
    expect_true(m.remove(q));
    expect_equal(m.count, 1);
    expect_true(m.contains(p));
    expect_equal(m.get(p), 42);
}

[Test]
string_keys_by_content() {
    var m = HashMap<String, int>();
    expect_true(m.insert("hello", 1));
    var s = "hello";
    expect_true(m.contains(s));
    expect_equal(m.get(s), 1);
    m[s] = 5;
    expect_equal(m["hello"], 5);
    expect_equal(m.count, 1);
    expect_true(m.insert("world", 2));
    expect_equal(m.count, 2);
    expect_equal(m["hello"], 5);
    expect_equal(m["world"], 2);
}

[Test]
empty_set() {
    var s = HashSet<int>();
    expect_true(s.is_empty);
    expect_equal(s.count, 0);
    expect_false(s.contains(1));
    expect_equal(s[7], 0);
}

[Test]
set_insert_contains_remove() {
    var s = HashSet<int>();
    expect_true(s.insert(1));
    expect_false(s.insert(1));
    expect_equal(s.count, 1);
    expect_true(s.contains(1));
    expect_equal(s[1], 1);
    expect_equal(s[9], 0);
    s[2] = 2;
    expect_equal(s.count, 2);
    expect_true(s.remove(1));
    expect_false(s.remove(1));
    expect_equal(s.count, 1);
    expect_true(s.contains(2));
}

[Test]
set_growth_and_clear() {
    var s = HashSet<int>();
    var i = 0;
    while (i < 20) {
        expect_true(s.insert(i));
        i = i + 1;
    }
    expect_equal(s.count, 20);
    var j = 0;
    while (j < 20) {
        expect_true(s.contains(j));
        j = j + 1;
    }
    s.clear();
    expect_true(s.is_empty);
    expect_true(s.insert(5));
    expect_equal(s.count, 1);
}

# Struct elements hash by address: equal-valued Points are distinct
# members, and remove finds only the exact stored object.
[Test]
set_struct_keys_identity() {
    var s = HashSet<Point>();
    var p = Point(3, 4);
    expect_true(s.insert(p));
    var q = Point(3, 4);
    expect_true(s.insert(q));
    expect_equal(s.count, 2);
    var r = Point(4, 3);
    expect_true(s.insert(r));
    expect_equal(s.count, 3);
    expect_true(s.remove(q));
    expect_equal(s.count, 2);
    expect_true(s.contains(p));
    expect_true(s.contains(r));
    expect_false(s.contains(q));
}

[Test]
map_string_values_refcounted() {
    var m = HashMap<int, String>();
    expect_true(m.insert(1, "alpha"));
    expect_equal(m[1], "alpha");
    m[1] = "beta";
    expect_equal(m[1], "beta");
    expect_equal(m.count, 1);
    expect_true(m.remove(1));
    expect_true(m.is_empty);
}

# The map holds Point keys and String values; the runner's leak check
# confirms that releasing the map frees them all.
[Test]
map_release_frees_contents() {
    var m = HashMap<Point, String>();
    var p1 = Point(1, 2);
    var p2 = Point(2, 4);
    var p3 = Point(3, 6);
    var s1 = "one";
    var s2 = "two";
    var s3 = "three";
    expect_true(m.insert(p1, s1));
    expect_true(m.insert(p2, s2));
    expect_true(m.insert(p3, s3));
}

# Regression: every `_pep_malloc` result is 8-byte aligned, so a raw address
# hash lands all struct keys in bucket 0 of a small table. The address bits
# must be folded through FNV and the probe sequence must cover every slot,
# or the 4th insert finds no empty slot at capacity 8 and is silently
# dropped. Struct keys are identity-hashed, so lookups re-use the stored
# objects themselves.
[Test]
many_struct_keys_same_bucket() {
    var m = HashMap<Point, int>(8);
    var kept = Array<Point>();
    var i = 0;
    while (i < 4) {
        var p = Point(i + 1, (i + 1) * 2);
        expect_true(m.insert(p, (i + 1) * 10));
        kept.append(p);
        i = i + 1;
    }
    expect_equal(m.count, 4);
    expect_equal(m.get(kept[2]), 30);
    var fresh = Point(3, 6);
    expect_false(m.contains(fresh));
}

# The same regression for HashSet: four distinct Point members are all
# stored and found at capacity 8.
[Test]
many_struct_set_members_same_bucket() {
    var s = HashSet<Point>(8);
    var kept = Array<Point>();
    var i = 0;
    while (i < 4) {
        var p = Point(i + 1, (i + 1) * 2);
        expect_true(s.insert(p));
        kept.append(p);
        i = i + 1;
    }
    expect_equal(s.count, 4);
    expect_true(s.contains(kept[1]));
    var fresh = Point(9, 9);
    expect_false(s.contains(fresh));
}

# A struct that declares `==` and overrides `hash<T>` is keyed by its
# fields: a fresh object with equal fields finds, replaces and removes the
# stored entry, through every HashMap and HashSet path (insert, lookup,
# remove, growth, iteration, copy).
[Test]
struct_keys_with_their_own_hash_and_equality_match_by_content() {
    var ages = HashMap<Person, int>();
    var i = 0;
    while (i < 100) {
        ages[Person($"p{i}", i)] = i;
        i = i + 1;
    }
    expect_equal(ages.count, 100);
    expect_equal(ages[Person("p42", 42, "nick")], 42);
    expect_false(ages.insert(Person("p7", 7), 70));
    expect_equal(ages[Person("p7", 7)], 70);
    expect_equal(ages.count, 100);
    expect_false(ages.contains(Person("p7", 8)));
    expect_true(ages.remove(Person("p7", 7)));
    expect_false(ages.contains(Person("p7", 7)));
    var total = 0;
    for (var (person, age) in ages) {
        total += age;
    }
    expect_equal(total, 4950 - 7);
    var people = HashSet<Person>();
    people.insert(Person("Ada", 1, "A"));
    expect_false(people.insert(Person("Ada", 1, "Countess")));
    expect_equal(people[Person("Ada", 1)].nickname, "A");
    var copied = copy(people);
    expect_true(copied.contains(Person("Ada", 1)));
}

# `[Equatable]` derives `==` and the hash from the fields, leaving out a
# `[Equatable(exclude = true)]` one: the same paths as a hand-written pair.
[Test]
equatable_struct_keys_match_by_their_compared_fields() {
    var ages = HashMap<EquatablePerson, int>();
    var i = 0;
    while (i < 100) {
        ages[EquatablePerson($"p{i}", i)] = i;
        i = i + 1;
    }
    expect_equal(ages.count, 100);
    expect_equal(ages[EquatablePerson("p42", 42, "nick")], 42);
    expect_false(ages.insert(EquatablePerson("p7", 7), 70));
    expect_equal(ages[EquatablePerson("p7", 7)], 70);
    expect_equal(ages.count, 100);
    expect_false(ages.contains(EquatablePerson("p7", 8)));
    expect_true(ages.remove(EquatablePerson("p7", 7)));
    expect_false(ages.contains(EquatablePerson("p7", 7)));
    var people = HashSet<EquatablePerson>();
    people.insert(EquatablePerson("Ada", 1, "A"));
    expect_false(people.insert(EquatablePerson("Ada", 1, "Countess")));
    expect_equal(people[EquatablePerson("Ada", 1)].nickname, "A");
    expect_true(EquatablePerson("Ada", 1) == EquatablePerson("Ada", 1, "B"));
    expect_false(EquatablePerson("Ada", 1) == EquatablePerson("Ada", 2));
    expect_equal(hash(EquatablePerson("Ada", 1, "x")), hash(EquatablePerson("Ada", 1, "y")));
}

[Test]
equatable_enum_keys_match_by_case_and_values() {
    expect_true(Token.Word("a") == Token.Word("a"));
    expect_false(Token.Word("a") == Token.Word("b"));
    expect_false(Token.Number(0) == Token.End);
    expect_true(Token.End == Token.End);
    var counts = HashMap<Token, int>();
    counts[Token.Word("x")] = 1;
    counts[Token.Number(2)] = 2;
    counts[Token.End] = 3;
    expect_equal(counts[Token.Word("x")], 1);
    expect_equal(counts[Token.Number(2)], 2);
    expect_equal(counts[Token.End], 3);
    expect_false(counts.contains(Token.Number(3)));
}

# An `Array` compares by its elements but hashes by its address, so a
# tuple's hash leaves it out: equal tuples hash equally.
[Test]
tuple_keys_holding_arrays_find_equal_arrays() {
    var a: int[] = [1, 2];
    var b: int[] = [1, 2];
    expect_equal(hash((a, 5)), hash((b, 5)));
    var set = HashSet<(int[], int)>();
    set.insert((a, 5));
    expect_true(set.contains((b, 5)));
}

# A map whose values are `Array<String>` releases each value's String slots
# and its own value slots.
[Test]
hash_map_values_release_frees_all() {
    var m = HashMap<int, Array<String>>();
    var a1 = Array<String>(1);
    var s1 = "one";
    a1.append(s1);
    var a2 = Array<String>(1);
    var s2 = "two";
    a2.append(s2);
    expect_true(m.insert(1, a1));
    expect_true(m.insert(2, a2));
    expect_equal(m.count, 2);
    expect_equal(m[1][0], s1);
    expect_equal(m[2][0], s2);
}

# Five inserts into a default-capacity (8) map grow it once at the fifth
# insert. Growing reinserts every existing value into fresh arrays and
# releases the old ones, so any refcount slip shows up as a leak or a
# double free.
[Test]
hash_map_growth_release_frees_all() {
    var m = HashMap<int, Array<String>>();
    var i = 0;
    while (i < 5) {
        var a = Array<String>(1);
        var s = "v";
        a.append(s);
        m.insert(i, a);
        i = i + 1;
    }
    expect_equal(m.count, 5);
    expect_equal(m[4][0].size, 1);
}

# `HashMap<String, HashMap<int, int>>`: the outer map's value slots hold
# inner maps whose own keys and values all release.
[Test]
nested_hash_map_release_frees_all() {
    var m = HashMap<String, HashMap<int, int>>();
    var k1 = "a";
    var inner1 = HashMap<int, int>();
    inner1.insert(1, 10);
    inner1.insert(2, 20);
    var k2 = "b";
    var inner2 = HashMap<int, int>();
    inner2.insert(3, 30);
    expect_true(m.insert(k1, inner1));
    expect_true(m.insert(k2, inner2));
    expect_equal(m.count, 2);
    expect_equal(m[k1][1], 10);
    expect_equal(m[k2][3], 30);
}

# `HashSet<Array<int>>`: arrays hash by identity, so distinct objects are
# distinct members; the set's key slots release each Array.
[Test]
hash_set_array_release_frees_all() {
    var s = HashSet<Array<int>>();
    var a1 = Array<int>(2);
    a1.append(1);
    a1.append(2);
    var a2 = Array<int>(2);
    a2.append(3);
    a2.append(4);
    expect_true(s.insert(a1));
    expect_true(s.insert(a2));
    expect_equal(s.count, 2);
}
