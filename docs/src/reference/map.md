<!-- Generated from runtime/map.pep by `pep-doc reference`. Do not edit. -->

# Map and Set

Sorted collections: `Map<K, V>` and `Set<K>`, kept in key order on a
red-black tree, and `compare<T>`, the ordering they sort keys by.

Source: `runtime/map.pep`

## compare

```pepper
compare<T>(a: T, b: T): int
```

Returns a negative number when `a` sorts before `b`, zero when they are
equal, and a positive number when `a` sorts after `b`: the order `Map` and
`Set` keep their keys in.

The generic version compares with `<`, so it works for every
`Comparable` type (see `Comparable`), every integer type, `char`, and any
struct that declares a `<` operator. Two values neither of which is `<`
the other are equal keys. `String`, `float` and `double` go through
concrete overrides that call their `compare`, so a NaN key sorts after
every number instead of breaking the order.

A struct with no `<` operator declares `Comparable`, or overrides this
function for itself, to be a `Map` key or `Set` element:
`compare<Point>(a: Point, b: Point): int`. The order must be a strict
weak order (consistent across calls), or the tree loses track of its
keys.

**Type parameters**
- `T` — the type of the values to compare

**Parameters**
- `a` — the first value
- `b` — the second value

**Returns**
- a negative number, zero or a positive number as `a` sorts before, equal to or after `b`

**See also**
- `compare<String>`

**Example**
```pepper
assert(compare<int>(1, 2) < 0, "1 sorts first");
assert(compare<int>(2, 2) == 0, "equal");
```

## compare

```pepper
compare<String>(a: String, b: String): int
```

Compares two Strings by content, the order `Map` and `Set` keep `String`
keys in: the same as `a.compare(b)`.

**Parameters**
- `a` — the first String
- `b` — the second String

**Returns**
- a negative number, zero or a positive number as `a` sorts before, equal to or after `b`

**Example**
```pepper
assert(compare<String>("apple", "pear") < 0, "apple sorts first");
```

## compare

```pepper
compare<float>(a: float, b: float): int
```

Compares two `float`s in `float.compare`'s total order: by value, with
NaN after every number.

**Parameters**
- `a` — the first value
- `b` — the second value

**Returns**
- -1, 0 or 1 as `a` sorts before, with or after `b`

## compare

```pepper
compare<double>(a: double, b: double): int
```

Compares two `double`s in `double.compare`'s total order: by value, with
NaN after every number.

**Parameters**
- `a` — the first value
- `b` — the second value

**Returns**
- -1, 0 or 1 as `a` sorts before, with or after `b`

## Map

```pepper
struct Map<K, V>
```

A map from keys of type `K` to values of type `V` that keeps its keys
sorted.

Keys are ordered by `compare<K>`: numbers by value, `String` by content,
and other structs by their `<` operator or a `compare<K>` override. Two
keys that compare equal are the same key. Lookups, inserts and removals
take O(log count) time on a red-black tree.

`iterate()` visits the entries as `(key, value)` tuples in ascending key
order, `reversed()` in descending order, and `range(from, to)` the keys
from `from` up to (not including) `to`. `first`, `last`, `lower_bound`
and `upper_bound` find single entries by order.

The map holds one reference to each stored key and value. It acquires
them when they are stored and releases them when they are overwritten,
removed, cleared, or when the map is destroyed.

For keys kept in the order they were inserted, use `OrderedMap`; for
expected O(1) lookups in no order, `HashMap`.

**Type parameters**
- `K` — the key type; ordered by `compare<K>`
- `V` — the value type

**Example**
```pepper
var scores = Map<String, int>();
scores["carol"] = 91;
scores["alice"] = 84;
scores["bob"] = 77;
for (var (name, score) in scores) {
    print($"{name}: {score}");   # alice, bob, carol
}
```

### Properties

#### count

```pepper
var count: int { get; }
```

The number of entries in the map. O(1).

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the map has no entries. O(1).

### Constructor

#### Map()

```pepper
construct()
```

Creates an empty map.

### Methods

#### clear

```pepper
clear()
```

Removes every entry and releases the map's references to their keys
and values. O(count).

#### contains

```pepper
contains(key: K): bool
```

Returns whether the map has an entry for `key`. O(log count).

**Parameters**
- `key` — the key to look up

**Returns**
- true when `key` is present

#### insert

```pepper
insert(key: K, value: V): bool
```

Maps `key` to `value`, adding a new entry or overwriting the value of
an existing one.

When the key is already present, only the value is replaced: the map
keeps the key object it already stores and releases the old value.
O(log count).

**Parameters**
- `key` — the key to add or update
- `value` — the value to store for `key`

**Returns**
- true when a new key was added, false when an existing key's value was overwritten

#### get

```pepper
get(key: K): V
```

Returns the value stored for `key`, or the default of `V` (0, or a
null reference for struct types) when `key` is absent. A missing key
is not inserted. O(log count).

**Parameters**
- `key` — the key to look up

**Returns**
- the value for `key`, or the default of `V` when absent

**See also**
- `try_get`

#### try_get

```pepper
try_get(key: K): V?
```

Returns the value stored for `key`, or none when `key` is absent.
O(log count).

**Parameters**
- `key` — the key to look up

**Returns**
- the value for `key`, or none when absent

**Example**
```pepper
if (scores.try_get("alice") is Value(score)) {
    print($"{score}");
}
```

#### remove

```pepper
remove(key: K): bool
```

Removes the entry for `key`, releasing the map's references to its
key and value. Does nothing when `key` is absent. O(log count).

**Parameters**
- `key` — the key to remove

**Returns**
- true when `key` was present and removed, false when absent

#### operator []

```pepper
[](key: K): V
```

Reads `m[key]`: the same as `get`. A missing key reads as the default
of `V` and is not inserted.

**Parameters**
- `key` — the key to look up

**Returns**
- the value for `key`, or the default of `V` when absent

#### operator []

```pepper
[](key: K, value: V): V
```

Writes `m[key] = value`: the same as `insert`.

**Parameters**
- `key` — the key to add or update
- `value` — the value to store for `key`

**Returns**
- `value`, the value of the assignment expression

#### first

```pepper
first(): (K, V)?
```

Returns the entry with the smallest key. O(log count).

**Returns**
- the first `(key, value)` in key order, or none when the map is empty

#### last

```pepper
last(): (K, V)?
```

Returns the entry with the largest key. O(log count).

**Returns**
- the last `(key, value)` in key order, or none when the map is empty

#### lower_bound

```pepper
lower_bound(key: K): (K, V)?
```

Returns the first entry whose key is not less than `key`: the entry
for `key` itself when present, else the next one after it. O(log
count).

**Parameters**
- `key` — the key to search from

**Returns**
- the first `(key, value)` with a key `>= key`, or none when every key is less

**Example**
```pepper
var after_b = scores.lower_bound("b");   # ("bob", 77)
```

#### upper_bound

```pepper
upper_bound(key: K): (K, V)?
```

Returns the first entry whose key is greater than `key`. O(log count).

**Parameters**
- `key` — the key to search from

**Returns**
- the first `(key, value)` with a key `> key`, or none when no key is greater

#### iterate

```pepper
iterate(): SortedMapIterator<K, V>
```

Returns an iterator over the entries as `(key, value)` tuples in
ascending key order; `for (var (key, value) in map)` drives it.

The iterator holds a reference to the map. Changing a value through
an existing key while iterating is allowed; adding or removing an
entry makes the iterator's next `next()` or `current()` panic.

**Returns**
- an iterator positioned before the first entry

#### reversed

```pepper
reversed(): SortedMapIterator<K, V>
```

Returns an iterator over the entries in descending key order, under
the same rules as `iterate`.

**Returns**
- an iterator positioned before the last entry

**Example**
```pepper
for (var (name, score) in scores.reversed()) {
    print(name);   # carol, bob, alice
}
```

#### range

```pepper
range(from: K, to: K): SortedMapIterator<K, V>
```

Returns an iterator over the entries whose keys are at least `from`
and less than `to`, in ascending key order, under the same rules as
`iterate`. It is empty when `from` is not less than `to`.

**Parameters**
- `from` — the smallest key to visit
- `to` — the key to stop before

**Returns**
- an iterator positioned before the first entry in the range

**Example**
```pepper
for (var (name, score) in scores.range("a", "c")) {
    print(name);   # alice, bob
}
```

#### copy

```pepper
copy(): Map<K, V>
```

Returns a deep copy: a new map holding a copy of each key and value,
made with `copy`. This is how `copy(value)` copies a Map (the
`Copyable<Map<K, V>>` implementation); call `copy(map)` rather than
this method. O(count log count) plus the cost of copying the entries.

**Returns**
- the copy

## SortedMapIterator

```pepper
[Value] struct SortedMapIterator<K, V>
```

An iterator over the entries of a `Map` as `(key, value)` tuples, in key
order or reversed; returned by `Map.iterate()`, `reversed()` and
`range(from, to)`, and driven by `for (var (key, value) in ...)`.

Holds a reference to the map. It is fail-fast: adding or removing an
entry after the iterator was created makes its next `next()` or
`current()` panic.

**Type parameters**
- `K` — the key type of the map
- `V` — the value type of the map

**See also**
- `Map.iterate`

### Constructor

#### SortedMapIterator()

```pepper
construct(source: Map<K, V>, start: ulong, stop: ulong, reverse: bool)
```

Creates an iterator over `source` from node `start` up to node `stop`.
Internal: call `Map.iterate`, `reversed` or `range` instead.

**Parameters**
- `source` — the map to iterate
- `start` — the first node to visit
- `stop` — the node to stop before, 0 for the end
- `reverse` — whether to step in descending key order

### Methods

#### next

```pepper
next(): bool
```

Advances to the next entry.

**Returns**
- true when there is a current entry, false once every entry was visited

**Panics**
- if an entry was added or removed since the iterator was created ("Map modified during iteration")

#### current

```pepper
current(): (K, V)
```

Returns the entry the last successful `next()` moved to.

**Returns**
- the current entry as a `(key, value)` tuple

**Panics**
- if an entry was added or removed since the iterator was created ("Map modified during iteration")
- if `next()` was never called or already returned false ("SortedMapIterator.current() without an entry")

## Set

```pepper
struct Set<K>
```

A set of distinct elements of type `K` kept in sorted order, on the same
red-black tree as `Map` but without values.

Elements are ordered by `compare<K>` (see `Map`); two elements that
compare equal are the same member. Membership tests, inserts and removals
take O(log count) time. `iterate()` visits the members in ascending
order, `reversed()` in descending order, and `range(from, to)` the
members from `from` up to (not including) `to`.

The set holds one reference to each member, acquired on insert and
released on remove, on `clear`, or when the set is destroyed.

**Type parameters**
- `K` — the element type; ordered by `compare<K>`

**Example**
```pepper
Set<int> primes = [7, 2, 5, 3];
for (var p in primes) {
    print($"{p}");   # 2, 3, 5, 7
}
```

### Properties

#### count

```pepper
var count: int { get; }
```

The number of members. O(1).

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the set has no members. O(1).

### Constructors

#### Set()

```pepper
construct()
```

Creates an empty set.

#### Set()

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
Set<String> keywords = ["while", "if", "else"];
assert(keywords.first().value() == "else", "sorted");
```

### Methods

#### clear

```pepper
clear()
```

Removes every member and releases the set's references to them.
O(count).

#### contains

```pepper
contains(key: K): bool
```

Returns whether `key` is a member. O(log count).

**Parameters**
- `key` — the element to look up

**Returns**
- true when `key` is a member

#### insert

```pepper
insert(key: K): bool
```

Adds `key` to the set if it is not already a member. When an equal
member exists, the set keeps the member it has. O(log count).

**Parameters**
- `key` — the element to add

**Returns**
- true when `key` was added, false when it was already a member

#### remove

```pepper
remove(key: K): bool
```

Removes `key` from the set, releasing the set's reference to the
member. Does nothing when `key` is not a member. O(log count).

**Parameters**
- `key` — the element to remove

**Returns**
- true when `key` was a member and was removed, false otherwise

#### first

```pepper
first(): K?
```

Returns the smallest member. O(log count).

**Returns**
- the smallest member, or none when the set is empty

#### last

```pepper
last(): K?
```

Returns the largest member. O(log count).

**Returns**
- the largest member, or none when the set is empty

#### lower_bound

```pepper
lower_bound(key: K): K?
```

Returns the smallest member that is not less than `key`. O(log count).

**Parameters**
- `key` — the element to search from

**Returns**
- the first member `>= key`, or none when every member is less

#### upper_bound

```pepper
upper_bound(key: K): K?
```

Returns the smallest member greater than `key`. O(log count).

**Parameters**
- `key` — the element to search from

**Returns**
- the first member `> key`, or none when no member is greater

#### iterate

```pepper
iterate(): SortedSetIterator<K>
```

Returns an iterator over the members in ascending order;
`for (var x in set)` drives it.

The iterator holds a reference to the set. Adding or removing a member
while iterating makes the iterator's next `next()` or `current()`
panic.

**Returns**
- an iterator positioned before the smallest member

#### reversed

```pepper
reversed(): SortedSetIterator<K>
```

Returns an iterator over the members in descending order, under the
same rules as `iterate`.

**Returns**
- an iterator positioned before the largest member

#### range

```pepper
range(from: K, to: K): SortedSetIterator<K>
```

Returns an iterator over the members that are at least `from` and
less than `to`, in ascending order, under the same rules as `iterate`.
It is empty when `from` is not less than `to`.

**Parameters**
- `from` — the smallest member to visit
- `to` — the element to stop before

**Returns**
- an iterator positioned before the first member in the range

#### copy

```pepper
copy(): Set<K>
```

Returns a deep copy: a new set holding a copy of each member, made
with `copy`. This is how `copy(value)` copies a Set (the
`Copyable<Set<K>>` implementation); call `copy(set)` rather than this
method.

**Returns**
- the copy

## SortedSetIterator

```pepper
[Value] struct SortedSetIterator<K>
```

An `Iterator<K>` over the members of a `Set`, in order or reversed;
returned by `Set.iterate()`, `reversed()` and `range(from, to)`, and
driven by `for (var x in ...)`.

Holds a reference to the set. It is fail-fast: adding or removing a member
after the iterator was created makes its next `next()` or `current()`
panic.

**Type parameters**
- `K` — the element type of the set

**See also**
- `Set.iterate`

### Constructor

#### SortedSetIterator()

```pepper
construct(source: Set<K>, start: ulong, stop: ulong, reverse: bool)
```

Creates an iterator over `source` from node `start` up to node `stop`.
Internal: call `Set.iterate`, `reversed` or `range` instead.

**Parameters**
- `source` — the set to iterate
- `start` — the first node to visit
- `stop` — the node to stop before, 0 for the end
- `reverse` — whether to step in descending order

### Methods

#### next

```pepper
next(): bool
```

Advances to the next member.

**Returns**
- true when there is a current member, false once every member was visited

**Panics**
- if a member was added or removed since the iterator was created ("Set modified during iteration")

#### current

```pepper
current(): K
```

Returns the member the last successful `next()` moved to.

**Returns**
- the current member

**Panics**
- if a member was added or removed since the iterator was created ("Set modified during iteration")
- if `next()` was never called or already returned false ("SortedSetIterator.current() without a member")
