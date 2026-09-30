<!-- Generated from runtime/hash.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# HashMap and HashSet

Source: `runtime/hash.pep`

## hash

```pepper
hash<T>(T value): u64
```

Returns a 64-bit FNV-1a hash of `value`, the hash `HashMap` and `HashSet`
use for their keys.

- POD types (integers, floats, pointers, `bool`) fold the value's own
  bytes, so equal values hash equally.
- Struct types hash by identity: the object's address, folded through
  FNV-1a so that aligned addresses spread across buckets. Two distinct
  objects with equal fields therefore hash differently and are distinct
  keys. A null reference hashes to the FNV-1a offset basis.
- `String` hashes by content through the concrete `hash<String>`
  override, so equal strings at different addresses collide.

The result is deterministic within and across runs of a program for POD
values and strings; for other struct types it depends on where the object
was allocated. Reading the address does no refcount work, and a temporary
argument is released afterwards.

**Type parameters**
- `T` — the type of the value to hash

**Parameters**
- `value` — the value to hash

**Returns**
- the 64-bit hash of `value`

**See also**
- `hash<String>`

**Example**
```pepper
    var a = hash<int>(5);
    var b = hash<int>(5);   # a == b
```

## hash

```pepper
hash<String>(String value): u64
```

Returns a 64-bit FNV-1a hash of a String's bytes, so equal strings hash
equally wherever they are stored. Keeps equal `String` keys of a
`HashMap` or `HashSet` in one bucket.

Hashes the `size()` bytes of the String (not the NUL terminator) in O(size). An
empty String hashes to the FNV-1a offset basis.

**Parameters**
- `value` — the String to hash; it must not be a null reference

**Returns**
- the 64-bit hash of the String's content

**Example**
```pepper
    assert(hash<String>("hello") == hash<String>("hello"), "content hash");
```

## HashMap

```pepper
struct HashMap<K, V>
```

A hash table that maps keys of type `K` to values of type `V`.

Keys are hashed with `hash<K>` and compared with `==`: POD keys by value,
`String` keys by content, and other struct keys by identity (two distinct
objects with equal fields are different keys). Any type can be a key.

The map holds one reference to each stored key and value. It acquires
them when they are stored and releases them when they are overwritten,
removed, cleared, or when the map is destroyed.

Lookups, inserts, and removals take expected O(1) time. The table doubles
before an insert of a new key would fill half of it (live entries plus
removed-slot tombstones), so it never shrinks, and churn (many inserts and
removals of different keys) can keep growing it even while `count()`
stays small.

`iterate()` visits the entries as `(key, value)` tuples, in no defined order.

**Type parameters**
- `K` — the key type; hashed with `hash<K>` and compared with `==`
- `V` — the value type

**Example**
```pepper
    var ages = HashMap<String, int>();
    ages["ada"] = 36;
    ages.insert("alan", 41);
    assert(ages["ada"] == 36, "lookup");
    assert(ages.get("grace") == 0, "a missing key reads as the default");
    assert(ages.remove("alan"), "removed");
    assert(ages.count() == 1, "one entry left");
```

### Constructor

#### HashMap()

```pepper
construct(ulong initial_capacity = 8)
```

Creates an empty map whose table has room for at least
`initial_capacity` slots.

The slot count is rounded up to a power of two, with a minimum of 8.
The map holds up to half its slot count before the first grow, so pass
about twice the expected number of entries to avoid regrowing. Allocates
three arrays of that many slots.

**Parameters**
- `initial_capacity` — the minimum number of slots in the table

**Example**
```pepper
    var m = HashMap<int, int>(64);   # 64 slots, 32 entries before growing
```

### Methods

#### grow

```pepper
void grow()
```

Doubles the table and reinserts every entry, dropping all tombstones.

`insert` calls it automatically. Calling it directly is safe but only
costs memory. Runs in O(capacity). It replaces the table's arrays and
moves entries to new slots. Reference counts are unchanged overall:
each entry is acquired by the new arrays and released by the old ones.

#### count

```pepper
int count()
```

Returns the number of entries in the map. O(1).

**Returns**
- the number of live key-value pairs

#### empty

```pepper
bool empty()
```

Returns whether the map has no entries. O(1).

**Returns**
- true when `count()` is 0

#### capacity

```pepper
ulong capacity()
```

Returns the number of slots in the table, a power of two and at least 8.
The map grows before its entries and tombstones reach half of it. O(1).

**Returns**
- the current slot count

#### cap

```pepper
[Deprecated("use 'capacity' instead", "capacity")] ulong cap()
```

Deprecated: use `capacity` instead. Returns the number of slots in
the table.

**Returns**
- the same as `capacity()`

#### clear

```pepper
void clear()
```

Removes every entry and releases the map's references to their keys
and values. The table keeps its capacity. Runs in O(capacity).

#### copy

```pepper
HashMap<K, V> copy(Copies copies)
```

Returns a deep copy: a new map holding a copy of each key and value,
made with `copies.copy`. This is how `copy(value)` copies a HashMap
(the `Copyable<HashMap<K, V>>` implementation); call `copy(map)`
rather than this method.

The copied keys are hashed again, so a map keyed by struct identity
finds its entries under the copied keys. Runs in O(capacity) plus the
cost of copying the entries.

**Parameters**
- `copies` — the objects copied so far

**Returns**
- the copy

#### contains

```pepper
bool contains(K key)
```

Returns whether the map has an entry for `key`. Expected O(1).

**Parameters**
- `key` — the key to look up

**Returns**
- true when `key` is present

#### insert

```pepper
bool insert(K key, V value)
```

Maps `key` to `value`, adding a new entry or overwriting the value of
an existing one.

When the key is already present, only the value is replaced: the map
keeps the key object it already stores and releases the old value.
A new entry acquires both `key` and `value`, and may first grow the
table (see `grow`). Expected O(1); a grow costs O(capacity).

**Parameters**
- `key` — the key to add or update
- `value` — the value to store for `key`

**Returns**
- true when a new key was added, false when an existing key's value was overwritten

**Example**
```pepper
    var m = HashMap<int, int>();
    m.insert(1, 10);   # true: added
    m.insert(1, 20);   # false: overwritten; m.get(1) == 20
```

#### get

```pepper
V get(K key)
```

Returns the value stored for `key`, or the default of `V` when `key`
is absent.

The default is 0 for numbers and a null reference for struct types,
including `String`. A missing key is not an error and is not
inserted. When `V` is a struct type, call `contains` first rather than
using a null result. The caller gets its own reference to the stored
value. Expected O(1).

**Parameters**
- `key` — the key to look up

**Returns**
- the value for `key`, or the default of `V` when absent

#### remove

```pepper
bool remove(K key)
```

Removes the entry for `key`, releasing the map's references to its key
and value. Does nothing when `key` is absent.

The slot becomes a tombstone: occupied for probing, empty for lookup.
It counts toward the grow threshold until an insert reuses it or the
table grows. Expected O(1).

**Parameters**
- `key` — the key to remove

**Returns**
- true when `key` was present and removed, false when absent

#### operator []

```pepper
V [](K key)
```

Reads `m[key]`: returns the value for `key`, or the default of `V`
(0, or a null reference for struct types) when `key` is absent. The
same as `get`. A missing key is not inserted.

**Parameters**
- `key` — the key to look up

**Returns**
- the value for `key`, or the default of `V` when absent

**Example**
```pepper
    var m = HashMap<String, int>();
    var n = m["missing"];   # 0; m is still empty
```

#### operator []

```pepper
V [](K key, V value)
```

Writes `m[key] = value`: inserts `key` or overwrites its value, the
same as `insert`.

**Parameters**
- `key` — the key to add or update
- `value` — the value to store for `key`

**Returns**
- `value`, the value of the assignment expression

**Example**
```pepper
    var m = HashMap<String, int>();
    m["hello"] = 5;
```

#### iterate

```pepper
iterate(): HashMapIterator<K, V>
```

Returns an iterator over the entries as `(key, value)` tuples, in no
defined order; `for (var (key, value) in map)` drives it.

The iterator holds a reference to the map. Changing a value through an
existing key while iterating is allowed; adding or removing an entry
makes the iterator's next `next()` or `current()` panic.

**Returns**
- an iterator positioned before the first entry

**Example**
```pepper
    var total = 0;
    for (var (name, age) in ages) {
        total += age;
    }
```

## HashSet

```pepper
struct HashSet<K>
```

A hash set of distinct elements of type `K`, built on the same table as
`HashMap` but without values.

Elements are hashed with `hash<K>` and compared with `==`: POD elements
by value, `String` elements by content, and other struct elements by
identity (two distinct objects with equal fields are both members). The
set holds one reference to each member. It acquires the reference on
insert and releases it on remove, on `clear`, or when the set is
destroyed.

Membership tests, inserts, and removals take expected O(1) time. The
table doubles before an insert of a new element would fill half of it
(members plus tombstones), and it never shrinks. `iterate()` visits the
members, in no defined order. The lowercase fields and the `_find_slot`
and `grow` methods are the table's internal state: they are public but
may change, and writing to them breaks the set.

**Type parameters**
- `K` — the element type; hashed with `hash<K>` and compared with `==`

**Example**
```pepper
    var seen = HashSet<String>();
    seen.insert("a");
    seen["b"] = "b";   # the same as seen.insert("b")
    assert(seen.contains("a"), "member");
    assert(!seen.insert("a"), "already a member");
    assert(seen.count() == 2, "two members");
```

### Constructors

#### HashSet()

```pepper
construct(ulong initial_capacity = 8)
```

Creates an empty set whose table has room for at least
`initial_capacity` slots.

The slot count is rounded up to a power of two, with a minimum of 8.
The set holds up to half its slot count before the first grow.

**Parameters**
- `initial_capacity` — the minimum number of slots in the table

#### HashSet()

```pepper
[Implicit] construct(items: Array<K>)
```

Creates a set holding each element of `items` once.

The constructor is `[Implicit]`: an array converts to a set wherever
a set is expected, so an array literal can initialize one.

**Parameters**
- `items` — the elements to insert; duplicates are kept once

**Example**
```pepper
    HashSet<String> keywords = ["if", "else", "while"];
    assert(keywords.contains("else"), "a member");
```

### Methods

#### grow

```pepper
void grow()
```

Doubles the table and reinserts every member, dropping all tombstones.

`insert` calls it automatically. Calling it directly is safe but only
costs memory. Runs in O(capacity). It replaces the table's arrays and
moves members to new slots.

#### count

```pepper
int count()
```

Returns the number of members in the set. O(1).

**Returns**
- the number of members

#### empty

```pepper
bool empty()
```

Returns whether the set has no members. O(1).

**Returns**
- true when `count()` is 0

#### capacity

```pepper
ulong capacity()
```

Returns the number of slots in the table, a power of two and at least 8.
O(1).

**Returns**
- the current slot count

#### cap

```pepper
[Deprecated("use 'capacity' instead", "capacity")] ulong cap()
```

Deprecated: use `capacity` instead. Returns the number of slots in
the table.

**Returns**
- the same as `capacity()`

#### clear

```pepper
void clear()
```

Removes every member and releases the set's references to them. The
table keeps its capacity. Runs in O(capacity).

#### contains

```pepper
bool contains(K key)
```

Returns whether `key` is a member of the set. Expected O(1).

**Parameters**
- `key` — the element to look up

**Returns**
- true when `key` is a member

#### insert

```pepper
bool insert(K key)
```

Adds `key` to the set if it is not already a member.

A new member is acquired, and the insert may first grow the table
(see `grow`). When an equal member already exists, the set keeps the
member it has and does not store `key`. Expected O(1); a grow costs
O(capacity).

**Parameters**
- `key` — the element to add

**Returns**
- true when `key` was added, false when it was already a member

#### remove

```pepper
bool remove(K key)
```

Removes `key` from the set, releasing the set's reference to the
member. Does nothing when `key` is not a member. The slot becomes a
tombstone (see `_tombstones`). Expected O(1).

**Parameters**
- `key` — the element to remove

**Returns**
- true when `key` was a member and was removed, false otherwise

#### operator []

```pepper
K [](K key)
```

Reads `s[key]`: returns the stored member equal to `key`, or the
default of `K` (0, or a null reference for struct types) when `key` is
not a member.

For `String` elements this returns the instance the set stores, which
may be a different object than `key` with the same content. A missing
element is not inserted.

**Parameters**
- `key` — the element to look up

**Returns**
- the stored member equal to `key`, or the default of `K`

#### operator []

```pepper
K [](K key, K value)
```

Writes `s[key] = value`: makes `key` a member, the same as
`insert(key)`.

A set stores only keys, so `value` is ignored.

**Parameters**
- `key` — the element to add
- `value` — ignored

**Returns**
- `key` (the argument, not an existing equal member), the value of the assignment expression

#### iterate

```pepper
iterate(): HashSetIterator<K>
```

Returns an iterator over the members, in no defined order;
`for (var x in set)` drives it.

The iterator holds a reference to the set. Adding or removing a member
while iterating makes the iterator's next `next()` or `current()` panic.

**Returns**
- an iterator positioned before the first member

**Example**
```pepper
    for (var name in seen) {
        print(name);
    }
```

#### copy

```pepper
HashSet<K> copy(Copies copies)
```

Returns a deep copy: a new set holding a copy of each element, made
with `copies.copy`. This is how `copy(value)` copies a HashSet (the
`Copyable<HashSet<K>>` implementation); call `copy(set)` rather than
this method.

The copied elements are hashed again, so a set of structs compared by
identity finds the copied elements. Runs in O(capacity) plus the cost
of copying the elements.

**Parameters**
- `copies` — the objects copied so far

**Returns**
- the copy

## HashMapIterator

```pepper
struct HashMapIterator<K, V>
```

An `Iterator<(K, V)>` over the entries of a `HashMap`, as `(key, value)`
tuples in no defined order; returned by `HashMap.iterate()` and driven by
`for (var (key, value) in map)`.

Holds a reference to the map. It is fail-fast: adding or removing an
entry after the iterator was created makes its next `next()` or
`current()` panic.

**Type parameters**
- `K` — the key type of the map
- `V` — the value type of the map

**See also**
- `HashMap.iterate`

### Constructor

#### HashMapIterator()

```pepper
construct(source: HashMap<K, V>)
```

Creates an iterator positioned before the first entry of `source`.

**Parameters**
- `source` — the map to iterate

### Methods

#### next

```pepper
next(): bool
```

Advances to the next entry.

**Returns**
- true when there is a current entry, false once every entry was visited

**Panics**
- if an entry was added or removed since the iterator was created ("HashMap modified during iteration")

#### current

```pepper
current(): (K, V)
```

Returns the entry the last successful `next()` moved to.

**Returns**
- the current entry as a `(key, value)` tuple

**Panics**
- if an entry was added or removed since the iterator was created ("HashMap modified during iteration")
- if `next()` was never called or already returned false ("HashMapIterator.current() without an entry")

## HashSetIterator

```pepper
struct HashSetIterator<K>
```

An `Iterator<K>` over the members of a `HashSet`, in no defined order;
returned by `HashSet.iterate()` and driven by `for (var x in set)`.

Holds a reference to the set. It is fail-fast: adding or removing a member
after the iterator was created makes its next `next()` or `current()`
panic.

**Type parameters**
- `K` — the element type of the set

**See also**
- `HashSet.iterate`

### Constructor

#### HashSetIterator()

```pepper
construct(source: HashSet<K>)
```

Creates an iterator positioned before the first member of `source`.

**Parameters**
- `source` — the set to iterate

### Methods

#### next

```pepper
next(): bool
```

Advances to the next member.

**Returns**
- true when there is a current member, false once every member was visited

**Panics**
- if a member was added or removed since the iterator was created ("HashSet modified during iteration")

#### current

```pepper
current(): K
```

Returns the member the last successful `next()` moved to.

**Returns**
- the current member

**Panics**
- if a member was added or removed since the iterator was created ("HashSet modified during iteration")
- if `next()` was never called or already returned false ("HashSetIterator.current() without a member")
