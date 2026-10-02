<!-- Generated from runtime/ordered_map.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# OrderedMap

`OrderedMap<K, V>`: a hash map that keeps its keys in the order they were
first inserted.

Source: `runtime/ordered_map.pep`

## OrderedMap

```pepper
struct OrderedMap<K, V>
```

A hash map that iterates its entries in the order their keys were first
inserted, like Python's `dict`.

Keys are hashed with `hash<K>` and compared with `==`, as in `HashMap`.
Lookups, inserts and removals take expected O(1) time. Setting the value
of a key that is already present keeps its position; removing a key and
inserting it again moves it to the end.

`iterate()` visits the entries as `(key, value)` tuples in insertion
order. The map holds one reference to each stored key and value, acquired
when they are stored and released when they are overwritten, removed,
cleared, or when the map is destroyed.

**Type parameters**
- `K` — the key type; hashed with `hash<K>` and compared with `==`
- `V` — the value type

**Example**
```pepper
    var config = OrderedMap<String, String>();
    config["name"] = "pepper";
    config["version"] = "0.2";
    config["license"] = "MIT";
    for (var (key, value) in config) {
        print($"{key} = {value}");   # name, version, license
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

#### OrderedMap()

```pepper
construct(initial_capacity: ulong = 8)
```

Creates an empty map whose table has room for at least
`initial_capacity` slots (see `HashMap`).

**Parameters**
- `initial_capacity` — the minimum number of slots in the table

### Methods

#### clear

```pepper
clear()
```

Removes every entry and releases the map's references to their keys
and values. O(capacity).

#### contains

```pepper
contains(key: K): bool
```

Returns whether the map has an entry for `key`. Expected O(1).

**Parameters**
- `key` — the key to look up

**Returns**
- true when `key` is present

#### insert

```pepper
insert(key: K, value: V): bool
```

Maps `key` to `value`. A new key is added at the end of the order; an
existing key keeps its position (and the key object the map already
stores), and only its value is replaced. Expected O(1).

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
is not inserted. Expected O(1).

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
Expected O(1).

**Parameters**
- `key` — the key to look up

**Returns**
- the value for `key`, or none when absent

#### remove

```pepper
remove(key: K): bool
```

Removes the entry for `key`, releasing the map's references to its
key and value. The other entries keep their order. Does nothing when
`key` is absent. Amortized expected O(1).

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

#### iterate

```pepper
iterate(): OrderedMapIterator<K, V>
```

Returns an iterator over the entries as `(key, value)` tuples in
insertion order; `for (var (key, value) in map)` drives it.

The iterator holds a reference to the map. Changing a value through
an existing key while iterating is allowed; adding or removing an
entry makes the iterator's next `next()` or `current()` panic.

**Returns**
- an iterator positioned before the first entry

#### copy

```pepper
copy(): OrderedMap<K, V>
```

Returns a deep copy: a new map holding a copy of each key and value,
in the same order, made with `copy`. This is how `copy(value)`
copies an OrderedMap (the `Copyable<OrderedMap<K, V>>`
implementation); call `copy(map)` rather than this method.

**Returns**
- the copy

## OrderedMapIterator

```pepper
[Value] struct OrderedMapIterator<K, V>
```

An iterator over the entries of an `OrderedMap` as `(key, value)` tuples
in insertion order; returned by `OrderedMap.iterate()` and driven by
`for (var (key, value) in map)`.

Holds a reference to the map. It is fail-fast: adding or removing an
entry after the iterator was created makes its next `next()` or
`current()` panic.

**Type parameters**
- `K` — the key type of the map
- `V` — the value type of the map

**See also**
- `OrderedMap.iterate`

### Constructor

#### OrderedMapIterator()

```pepper
construct(source: OrderedMap<K, V>)
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
- if an entry was added or removed since the iterator was created ("OrderedMap modified during iteration")

#### current

```pepper
current(): (K, V)
```

Returns the entry the last successful `next()` moved to.

**Returns**
- the current entry as a `(key, value)` tuple

**Panics**
- if an entry was added or removed since the iterator was created ("OrderedMap modified during iteration")
- if `next()` was never called or already returned false ("OrderedMapIterator.current() without an entry")
