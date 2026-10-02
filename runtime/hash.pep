import "internals";

# ── Generic hash ─────────────────────────────────────────────────────────────
# The compiler lowers `__address` to one 64x64->128-bit multiply of the value
# with an odd constant, the product's halves xored (wyhash's "mum").

## Returns a 64-bit hash of `value`, the hash `HashMap` and `HashSet` use for
## their keys.
##
## - POD types (integers, floats, pointers, `bool`) mix the value's own
##   bits, so equal values hash equally.
## - Struct types hash by identity: the object's address, mixed so that
##   aligned addresses spread across buckets. Two distinct objects with
##   equal fields therefore hash differently and are distinct keys. A null
##   reference hashes to the FNV-1a offset basis (0xcbf29ce484222325).
##
## Every input bit reaches the low bits of the result, which a power-of-two
## table masks with. The hash is not keyed, so it does not resist inputs
## chosen to collide.
## - `String` hashes by content through the concrete `hash<String>`
##   override, so equal strings at different addresses collide.
##
## A struct whose keys should match by content instead declares an `==`
## operator and overrides this function for itself, hashing the fields `==`
## compares: `hash<Point>(value: Point): u64`. Keys that are `==` must hash
## equally (see the "Hashing and equality" chapter of the book).
##
## The result is deterministic within and across runs of a program for POD
## values and strings; for other struct types it depends on where the object
## was allocated. Reading the address does no refcount work, and a temporary
## argument is released afterwards.
##
## @typeParam T the type of the value to hash
## @param value the value to hash
## @returns the 64-bit hash of `value`
## @see hash<String>
## @example
##     var a = hash<int>(5);
##     var b = hash<int>(5);   # a == b
export hash<T>(value: T): u64 {
    return __address<T>(value);
}

# Concrete override: `hash<String>` is a distinct function from the generic
# base and wins for String call sites (gather_generics rewrites it to its
# specialization form).

## Returns a 64-bit hash of a String's bytes, so equal strings hash equally
## wherever they are stored. Keeps equal `String` keys of a `HashMap` or
## `HashSet` in one bucket.
##
## Hashes the `size` bytes of the String (not the NUL terminator) 8 bytes
## at a time, in O(size). An empty String hashes to the FNV-1a offset basis
## (0xcbf29ce484222325).
##
## @param value the String to hash; it must not be a null reference
## @returns the 64-bit hash of the String's content
## @example
##     assert(hash<String>("hello") == hash<String>("hello"), "content hash");
export hash<String>(value: String): u64 {
    return _pep_hash_bytes(value.c_str(), value.size);
}

# ── The table ───────────────────────────────────────────────────────────────
# Open addressing with triangular probing over a power-of-two table:
# probe(i) = (h & mask) + i*(i+1)/2 visits every slot of the table, which
# the 50% load threshold keeps reachable; each probe adds the next step to
# the last index. Slot occupancy is tracked in a
# parallel control Array of bytes (0 = empty, 1 = tombstone, 0x80 | the top
# 7 hash bits = full) so K can be
# any type; keys and values live in parallel arrays, whose store protocol
# handles struct reference counting for us, and a probe compares the stored
# key in place. The table never uses the arrays' size (it writes
# `_data[index]` directly), but keeps it equal to the capacity so an Array's
# destructor visits every slot when the table dies.
#
# One table serves both containers. It is a value struct, so it lives inline
# in the HashMap or HashSet that holds it: no extra object or indirection.
# A HashSet's table has `_NoValue` values, an empty value struct, so its
# values array holds no bytes and its stores compile to nothing.

# The value type of a HashSet's table: no bytes, no reference counting.
[Value]
export struct _NoValue {}

# The table behind `HashMap` and `HashSet`. Internal.
[Value]
export struct _HashTable<K, V> {
    # The key of each slot; only full slots hold a live key, the rest hold
    # the default of `K`.
    Array<K> _keys;
    # The value of each slot, parallel to `_keys`.
    Array<V> _values;
    # One control byte per slot: 0 is empty, 1 is a tombstone (a removed
    # entry that still extends probe sequences), and a full slot holds
    # 0x80 | the top 7 bits of its key's hash, so a probe skips most
    # non-matching keys without comparing them.
    Array<u8> _control;
    # The number of slots: always a power of two and at least 8.
    ulong _capacity;
    # The number of live entries.
    int _size;
    # The number of tombstones. They count toward the grow threshold until
    # an insert reuses them or `_resize` or `_clear` resets them.
    int _tombstones;
    # Counts the changes that add or remove entries (and growth), so an
    # iterator can tell that the table changed under it.
    ulong _version;

    # Sets up an empty table of at least `initial_capacity` slots.
    _init(initial_capacity: ulong) {
        ulong cap = 8;
        while (cap < initial_capacity) {
            cap = cap * 2;
        }
        _capacity = cap;
        _size = 0;
        _tombstones = 0;
        _keys = Array<K>(cap);
        _values = Array<V>(cap);
        _control = Array<u8>(cap);
        _keys._size = cap;
        _values._size = cap;
        _control._size = cap;
    }

    # The control byte of a full slot whose key hashes to `h`.
    _tag(h: ulong): u8 {
        return (0x80 | (h >> 57)) as u8;
    }

    # The slot holding `key`, or -1 when there is none. Probes from the
    # key's hash, skips tombstones, and stops at the first empty slot.
    _find_slot(key: K): long {
        ulong h = hash<K>(key);
        u8 tag = _tag(h);
        ulong mask = _capacity - 1;
        ulong index = h & mask;
        ulong step = 0;
        while (step < _capacity) {
            u8 control = _control._data[index];
            if (control == tag) {
                if (_keys._data[index] == key) {
                    return index;
                }
            } else if (control == 0) {
                return -1;
            }
            step = step + 1;
            index = (index + step) & mask;
        }
        return -1;
    }

    # Rebuilds the table with `new_capacity` slots (a power of two that
    # holds every entry under the 50% threshold), reinserting every entry
    # and dropping the tombstones.
    _resize(new_capacity: ulong) {
        # Reinsertion goes through Array store semantics (acquire), so the
        # outgoing arrays can be dropped from the fields right after: the
        # field store releases them, their size == capacity makes the
        # destructor visit every slot, and the buffer is freed.
        Array<K> keys = Array<K>(new_capacity);
        # A zero-size value (a HashSet's `_NoValue`) has nothing to move, so
        # the table keeps its one values array instead of allocating another.
        Array<V> values = sizeof<V>() == 0 ? _values : Array<V>(new_capacity);
        Array<u8> control = Array<u8>(new_capacity);
        keys._size = new_capacity;
        values._size = new_capacity;
        control._size = new_capacity;
        ulong mask = new_capacity - 1;
        ulong i = 0;
        while (i < _capacity) {
            if (_control._data[i] >= 0x80) {
                # The new table holds no tombstones, so the probe stops at the
                # first empty slot. The step grows by one each time: the
                # triangular sequence, which visits every slot.
                ulong h = hash<K>(_keys._data[i]);
                ulong index = h & mask;
                ulong step = 0;
                while (control._data[index] != 0) {
                    step = step + 1;
                    index = (index + step) & mask;
                }
                keys._data[index] = _keys._data[i];
                if (sizeof<V>() != 0) {
                    values._data[index] = _values._data[i];
                }
                control._data[index] = _tag(h);
            }
            i = i + 1;
        }
        _keys = keys;
        _values = values;
        _control = control;
        _capacity = new_capacity;
        _version += 1;
        _tombstones = 0;
    }

    # Doubles the table and reinserts every entry, dropping the tombstones.
    _grow() {
        _resize(_capacity * 2);
    }

    # Makes room for one more entry once entries and tombstones reach half
    # the table. When tombstones are at least half of that load, rebuilding
    # at the same size clears them, so insert/remove churn does not keep
    # doubling a table whose entry count stays small.
    _make_room() {
        if (_tombstones >= _size) {
            _resize(_capacity);
        } else {
            _grow();
        }
    }

    # Stores `value` for `key`: replaces the value when `key` is present
    # (keeping the stored key) and returns false, else adds the entry and
    # returns true.
    _insert(key: K, value: V): bool {
        # One probe both looks for `key` and finds where a new entry goes:
        # the first tombstone on the way, else the empty slot that ends it.
        ulong h = hash<K>(key);
        u8 tag = _tag(h);
        ulong mask = _capacity - 1;
        ulong index = h & mask;
        long reuse = -1;
        ulong step = 0;
        while (step < _capacity) {
            u8 control = _control._data[index];
            if (control == tag) {
                if (_keys._data[index] == key) {
                    if (sizeof<V>() != 0) {
                        _values._data[index] = value;
                    }
                    return false;
                }
            } else if (control == 0) {
                break;
            } else if (control == 1 and reuse < 0) {
                reuse = index;
            }
            step = step + 1;
            index = (index + step) & mask;
        }
        if (reuse >= 0) {
            # Claiming a tombstone leaves the load unchanged.
            index = reuse;
            _tombstones = _tombstones - 1;
        } else if ((_size + _tombstones) * 2 + 1 >= _capacity) {
            # Filling an empty slot adds to the load: keep it under half the
            # table, so every probe sequence still reaches an empty slot.
            # The rebuilt table has no tombstones, so `key` goes in the
            # first empty slot of its sequence.
            _make_room();
            mask = _capacity - 1;
            index = h & mask;
            step = 0;
            while (_control._data[index] != 0) {
                step = step + 1;
                index = (index + step) & mask;
            }
        }
        _keys._data[index] = key;
        if (sizeof<V>() != 0) {
            _values._data[index] = value;
        }
        _control._data[index] = tag;
        _size = _size + 1;
        _version += 1;
        return true;
    }

    # Removes `key`'s entry, leaving a tombstone; false when it is absent.
    _remove(key: K): bool {
        long slot = _find_slot(key);
        if (slot < 0) {
            return false;
        }
        _keys._data[slot] = __default<K>();
        if (sizeof<V>() != 0) {
            _values._data[slot] = __default<V>();
        }
        _control._data[slot] = 1;
        _size = _size - 1;
        _version += 1;
        _tombstones = _tombstones + 1;
        return true;
    }

    # Removes every entry, keeping the capacity.
    _clear() {
        ulong i = 0;
        while (i < _capacity) {
            if (_control._data[i] >= 0x80) {
                _keys._data[i] = __default<K>();
                if (sizeof<V>() != 0) {
                    _values._data[i] = __default<V>();
                }
            }
            _control._data[i] = 0;
            i = i + 1;
        }
        _size = 0;
        _tombstones = 0;
        _version += 1;
    }

    # The first full slot at or after `index`, or `_capacity`.
    _next_occupied(index: ulong): ulong {
        var i = index;
        while (i < _capacity and _control._data[i] < 0x80) {
            i = i + 1;
        }
        return i;
    }
}

# ── HashMap<K, V> ───────────────────────────────────────────────────────────

## A hash table that maps keys of type `K` to values of type `V`.
##
## Keys are hashed with `hash<K>` and compared with `==`: POD keys by value,
## `String` keys by content, and other struct keys by identity (two distinct
## objects with equal fields are different keys) unless the struct declares
## an `==` operator and a matching `hash<K>` override. Any type can be a key.
##
## The map holds one reference to each stored key and value. It acquires
## them when they are stored and releases them when they are overwritten,
## removed, cleared, or when the map is destroyed.
##
## Lookups, inserts, and removals take expected O(1) time. Before an insert
## of a new key would fill half the table (live entries plus removed-slot
## tombstones), the table is rebuilt: at double the size, or at the same size
## when tombstones make up at least half of that load, so churn (many
## inserts and removals of different keys) does not keep growing it. It
## never shrinks.
##
## `iterate()` visits the entries as `(key, value)` tuples, in no defined order.
##
## @typeParam K the key type; hashed with `hash<K>` and compared with `==`
## @typeParam V the value type
## @example
##     var ages = HashMap<String, int>();
##     ages["ada"] = 36;
##     ages.insert("alan", 41);
##     assert(ages["ada"] == 36, "lookup");
##     assert(ages.get("grace") == 0, "a missing key reads as the default");
##     assert(ages.remove("alan"), "removed");
##     assert(ages.count == 1, "one entry left");
export struct HashMap<K, V> {
    ## The hash table holding the entries. Internal.
    _HashTable<K, V> _table;

    ## Creates an empty map whose table has room for at least
    ## `initial_capacity` slots.
    ##
    ## The slot count is rounded up to a power of two, with a minimum of 8.
    ## The map holds up to half its slot count before the first grow, so pass
    ## about twice the expected number of entries to avoid regrowing. Allocates
    ## three arrays of that many slots.
    ##
    ## @param initial_capacity the minimum number of slots in the table
    ## @example
    ##     var m = HashMap<int, int>(64);   # 64 slots, 32 entries before growing
    construct(initial_capacity: ulong = 8) {
        _table._init(initial_capacity);
    }

    ## Returns the slot index that holds `key`, or -1 when `key` is absent.
    ##
    ## Probes from the key's hash and stops at the first empty slot.
    ## Tombstones are skipped, so removed keys do not cut probe sequences
    ## short. Expected O(1), worst case O(capacity).
    ##
    ## Internal: the index is only valid until the next `insert`, `grow`,
    ## or `clear`. Use `contains` or `get` instead.
    ##
    ## @param key the key to look up
    ## @returns the index of the slot that holds `key` in `_keys` and `_values`,
    ##   or -1 when `key` is absent
    _find_slot(key: K): long {
        return _table._find_slot(key);
    }

    ## Doubles the table and reinserts every entry, dropping all tombstones.
    ##
    ## `insert` calls it automatically. Calling it directly is safe but only
    ## costs memory. Runs in O(capacity). It replaces the table's arrays and
    ## moves entries to new slots. Reference counts are unchanged overall:
    ## each entry is acquired by the new arrays and released by the old ones.
    grow() {
        _table._grow();
    }

    ## The number of entries in the map. O(1).
    var count: int {
        get {
            return _table._size;
        }
    }

    ## Whether the map has no entries. O(1).
    var is_empty: bool {
        get {
            return _table._size == 0;
        }
    }

    ## The number of slots in the table, a power of two and at least 8.
    ## The map grows before its entries and tombstones reach half of it. O(1).
    var capacity: ulong {
        get {
            return _table._capacity;
        }
    }

    ## Deprecated: use `capacity` instead. Returns the number of slots in
    ## the table.
    ##
    ## @returns the same as `capacity`
    [Deprecated("use the 'capacity' property instead")]
    cap(): ulong {
        return capacity;
    }

    ## Removes every entry and releases the map's references to their keys
    ## and values. The table keeps its capacity. Runs in O(capacity).
    clear() {
        _table._clear();
    }

    ## Returns a deep copy: a new map holding a copy of each key and value,
    ## made with `copies.copy`. This is how `copy(value)` copies a HashMap
    ## (the `Copyable<HashMap<K, V>>` implementation); call `copy(map)`
    ## rather than this method.
    ##
    ## The copied keys are hashed again, so a map keyed by struct identity
    ## finds its entries under the copied keys. Runs in O(capacity) plus the
    ## cost of copying the entries.
    ##
    ## @param copies the objects copied so far
    ## @returns the copy
    copy(copies: Copies): HashMap<K, V> {
        HashMap<K, V> made = HashMap<K, V>(_table._capacity);
        copies.register<HashMap<K, V>>(this, made);
        ulong i = _table._next_occupied(0);
        while (i < _table._capacity) {
            made.insert(copies.copy<K>(_table._keys._data[i]), copies.copy<V>(_table._values._data[i]));
            i = _table._next_occupied(i + 1);
        }
        return made;
    }

    ## Returns whether the map has an entry for `key`. Expected O(1).
    ##
    ## @param key the key to look up
    ## @returns true when `key` is present
    contains(key: K): bool {
        return _find_slot(key) >= 0;
    }

    # A map literal `[k1: v1, k2: v2]` is built as
    # `_map_literal(k1, v1)._literal_insert(k2, v2)`: each step inserts
    # (a repeated key keeps the last value) and returns the same map.
    _literal_insert(key: K, value: V): HashMap<K, V> {
        insert(key, value);
        return this;
    }

    # Joins the short chains of a long map literal, as
    # `Array._literal_then` does for arrays.
    _literal_then(next: HashMap<K, V>): HashMap<K, V> {
        return next;
    }

    ## Maps `key` to `value`, adding a new entry or overwriting the value of
    ## an existing one.
    ##
    ## When the key is already present, only the value is replaced: the map
    ## keeps the key object it already stores and releases the old value.
    ## A new entry acquires both `key` and `value`, and may first grow the
    ## table (see `grow`). Expected O(1); a grow costs O(capacity).
    ##
    ## @param key the key to add or update
    ## @param value the value to store for `key`
    ## @returns true when a new key was added, false when an existing key's
    ##   value was overwritten
    ## @example
    ##     var m = HashMap<int, int>();
    ##     m.insert(1, 10);   # true: added
    ##     m.insert(1, 20);   # false: overwritten; m.get(1) == 20
    insert(key: K, value: V): bool {
        return _table._insert(key, value);
    }

    ## Returns the value stored for `key`, or the default of `V` when `key`
    ## is absent.
    ##
    ## The default is 0 for numbers and a null reference for struct types,
    ## including `String`. A missing key is not an error and is not
    ## inserted. When `V` is a struct type, call `contains` first rather than
    ## using a null result. The caller gets its own reference to the stored
    ## value. Expected O(1).
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or the default of `V` when absent
    get(key: K): V {
        long slot = _table._find_slot(key);
        if (slot >= 0) {
            return _table._values._data[slot];
        }
        return __default<V>();
    }

    ## Returns the value stored for `key`, or none when `key` is absent.
    ## Expected O(1).
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or none when absent
    ## @example
    ##     if (ages.try_get("ada") is Some(age)) {
    ##         print($"{age}");
    ##     }
    try_get(key: K): V? {
        long slot = _table._find_slot(key);
        if (slot >= 0) {
            return Optional<V>.some(_table._values._data[slot]);
        }
        return Optional<V>.none();
    }

    ## Removes the entry for `key`, releasing the map's references to its key
    ## and value. Does nothing when `key` is absent.
    ##
    ## The slot becomes a tombstone: occupied for probing, empty for lookup.
    ## It counts toward the grow threshold until an insert reuses it or the
    ## table grows. Expected O(1).
    ##
    ## @param key the key to remove
    ## @returns true when `key` was present and removed, false when absent
    remove(key: K): bool {
        return _table._remove(key);
    }

    ## Reads `m[key]`: returns the value for `key`, or the default of `V`
    ## (0, or a null reference for struct types) when `key` is absent. The
    ## same as `get`. A missing key is not inserted.
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or the default of `V` when absent
    ## @example
    ##     var m = HashMap<String, int>();
    ##     var n = m["missing"];   # 0; m is still empty
    [](key: K): V {
        return get(key);
    }

    ## Writes `m[key] = value`: inserts `key` or overwrites its value, the
    ## same as `insert`.
    ##
    ## @param key the key to add or update
    ## @param value the value to store for `key`
    ## @returns `value`, the value of the assignment expression
    ## @example
    ##     var m = HashMap<String, int>();
    ##     m["hello"] = 5;
    [](key: K, value: V): V {
        insert(key, value);
        return value;
    }

    ## Returns an iterator over the entries as `(key, value)` tuples, in no
    ## defined order; `for (var (key, value) in map)` drives it.
    ##
    ## The iterator holds a reference to the map. Changing a value through an
    ## existing key while iterating is allowed; adding or removing an entry
    ## makes the iterator's next `next()` or `current()` panic.
    ##
    ## @returns an iterator positioned before the first entry
    ## @example
    ##     var total = 0;
    ##     for (var (name, age) in ages) {
    ##         total += age;
    ##     }
    iterate(): HashMapIterator<K, V> {
        return HashMapIterator<K, V>(this);
    }
}

# ── HashSet<K> ──────────────────────────────────────────────────────────────

## A hash set of distinct elements of type `K`, built on the same table as
## `HashMap` but without values.
##
## Elements are hashed with `hash<K>` and compared with `==`: POD elements
## by value, `String` elements by content, and other struct elements by
## identity (two distinct objects with equal fields are both members)
## unless the struct declares an `==` operator and a matching `hash<K>`
## override. The
## set holds one reference to each member. It acquires the reference on
## insert and releases it on remove, on `clear`, or when the set is
## destroyed.
##
## Membership tests, inserts, and removals take expected O(1) time. Before
## an insert of a new element would fill half the table (members plus
## tombstones), the table is rebuilt: at double the size, or at the same
## size when tombstones make up at least half of that load. It never
## shrinks. `iterate()` visits the
## members, in no defined order. The lowercase fields and the `_find_slot`
## and `grow` methods are the table's internal state: they are public but
## may change, and writing to them breaks the set.
##
## @typeParam K the element type; hashed with `hash<K>` and compared with `==`
## @example
##     var seen = HashSet<String>();
##     seen.insert("a");
##     seen["b"] = "b";   # the same as seen.insert("b")
##     assert(seen.contains("a"), "member");
##     assert(!seen.insert("a"), "already a member");
##     assert(seen.count == 2, "two members");
export struct HashSet<K> {
    ## The hash table holding the members. Internal.
    _HashTable<K, _NoValue> _table;

    ## Creates an empty set whose table has room for at least
    ## `initial_capacity` slots.
    ##
    ## The slot count is rounded up to a power of two, with a minimum of 8.
    ## The set holds up to half its slot count before the first grow.
    ##
    ## @param initial_capacity the minimum number of slots in the table
    construct(initial_capacity: ulong = 8) {
        _init(initial_capacity);
    }

    ## Creates a set holding each element of `items` once.
    ##
    ## The constructor is `[Implicit]`: an array converts to a set wherever
    ## a set is expected, so an array literal can initialize one.
    ##
    ## @param items the elements to insert; duplicates are kept once
    ## @example
    ##     HashSet<String> keywords = ["if", "else", "while"];
    ##     assert(keywords.contains("else"), "a member");
    [Implicit]
    construct(items: Array<K>) {
        _init(items.count * 2);
        for (var item in items) {
            insert(item);
        }
    }

    # Sets up an empty table of at least `initial_capacity` slots.
    _init(initial_capacity: ulong) {
        _table._init(initial_capacity);
    }

    ## Returns the slot index that holds `key`, or -1 when `key` is not a
    ## member.
    ##
    ## Probes from the key's hash and stops at the first empty slot,
    ## skipping tombstones. Expected O(1), worst case O(capacity).
    ##
    ## Internal: the index is only valid until the next `insert`, `grow`, or
    ## `clear`. Use `contains` instead.
    ##
    ## @param key the element to look up
    ## @returns the index of the slot that holds `key` in `_keys`, or -1 when
    ##   `key` is not a member
    _find_slot(key: K): long {
        return _table._find_slot(key);
    }

    ## Doubles the table and reinserts every member, dropping all tombstones.
    ##
    ## `insert` calls it automatically. Calling it directly is safe but only
    ## costs memory. Runs in O(capacity). It replaces the table's arrays and
    ## moves members to new slots.
    grow() {
        _table._grow();
    }

    ## The number of members in the set. O(1).
    var count: int {
        get {
            return _table._size;
        }
    }

    ## Whether the set has no members. O(1).
    var is_empty: bool {
        get {
            return _table._size == 0;
        }
    }

    ## The number of slots in the table, a power of two and at least 8.
    ## O(1).
    var capacity: ulong {
        get {
            return _table._capacity;
        }
    }

    ## Deprecated: use `capacity` instead. Returns the number of slots in
    ## the table.
    ##
    ## @returns the same as `capacity`
    [Deprecated("use the 'capacity' property instead")]
    cap(): ulong {
        return capacity;
    }

    ## Removes every member and releases the set's references to them. The
    ## table keeps its capacity. Runs in O(capacity).
    clear() {
        _table._clear();
    }

    ## Returns whether `key` is a member of the set. Expected O(1).
    ##
    ## @param key the element to look up
    ## @returns true when `key` is a member
    contains(key: K): bool {
        return _find_slot(key) >= 0;
    }

    ## Adds `key` to the set if it is not already a member.
    ##
    ## A new member is acquired, and the insert may first grow the table
    ## (see `grow`). When an equal member already exists, the set keeps the
    ## member it has and does not store `key`. Expected O(1); a grow costs
    ## O(capacity).
    ##
    ## @param key the element to add
    ## @returns true when `key` was added, false when it was already a member
    insert(key: K): bool {
        return _table._insert(key, __default<_NoValue>());
    }

    ## Removes `key` from the set, releasing the set's reference to the
    ## member. Does nothing when `key` is not a member. The slot becomes a
    ## tombstone (see `_tombstones`). Expected O(1).
    ##
    ## @param key the element to remove
    ## @returns true when `key` was a member and was removed, false otherwise
    remove(key: K): bool {
        return _table._remove(key);
    }

    ## Reads `s[key]`: returns the stored member equal to `key`, or the
    ## default of `K` (0, or a null reference for struct types) when `key` is
    ## not a member.
    ##
    ## For `String` elements this returns the instance the set stores, which
    ## may be a different object than `key` with the same content. A missing
    ## element is not inserted.
    ##
    ## @param key the element to look up
    ## @returns the stored member equal to `key`, or the default of `K`
    [](key: K): K {
        long slot = _table._find_slot(key);
        if (slot >= 0) {
            return _table._keys._data[slot];
        }
        return __default<K>();
    }

    ## Writes `s[key] = value`: makes `key` a member, the same as
    ## `insert(key)`.
    ##
    ## A set stores only keys, so `value` is ignored.
    ##
    ## @param key the element to add
    ## @param value ignored
    ## @returns `key` (the argument, not an existing equal member), the value
    ##   of the assignment expression
    [](key: K, value: K): K {
        insert(key);
        return key;
    }

    ## Returns an iterator over the members, in no defined order;
    ## `for (var x in set)` drives it.
    ##
    ## The iterator holds a reference to the set. Adding or removing a member
    ## while iterating makes the iterator's next `next()` or `current()` panic.
    ##
    ## @returns an iterator positioned before the first member
    ## @example
    ##     for (var name in seen) {
    ##         print(name);
    ##     }
    iterate(): HashSetIterator<K> {
        return HashSetIterator<K>(this);
    }

    ## Returns a deep copy: a new set holding a copy of each element, made
    ## with `copies.copy`. This is how `copy(value)` copies a HashSet (the
    ## `Copyable<HashSet<K>>` implementation); call `copy(set)` rather than
    ## this method.
    ##
    ## The copied elements are hashed again, so a set of structs compared by
    ## identity finds the copied elements. Runs in O(capacity) plus the cost
    ## of copying the elements.
    ##
    ## @param copies the objects copied so far
    ## @returns the copy
    copy(copies: Copies): HashSet<K> {
        HashSet<K> made = HashSet<K>(_table._capacity);
        copies.register<HashSet<K>>(this, made);
        ulong i = _table._next_occupied(0);
        while (i < _table._capacity) {
            made.insert(copies.copy<K>(_table._keys._data[i]));
            i = _table._next_occupied(i + 1);
        }
        return made;
    }
}

## An `Iterator<(K, V)>` over the entries of a `HashMap`, as `(key, value)`
## tuples in no defined order; returned by `HashMap.iterate()` and driven by
## `for (var (key, value) in map)`.
##
## Holds a reference to the map. It is fail-fast: adding or removing an
## entry after the iterator was created makes its next `next()` or
## `current()` panic.
##
## @typeParam K the key type of the map
## @typeParam V the value type of the map
## @see HashMap.iterate
[Value]
export struct HashMapIterator<K, V> {
    ## The map being iterated.
    HashMap<K, V> _source;
    ## The slot of the current entry; meaningful once `_started` is set.
    ulong _index;
    ## The map's `_version` when iteration began.
    ulong _version;
    ## Whether `next()` has been called.
    bool _started;

    ## Creates an iterator positioned before the first entry of `source`.
    ##
    ## @param source the map to iterate
    construct(source: HashMap<K, V>) {
        _source = source;
        _version = source._table._version;
    }

    ## Advances to the next entry.
    ##
    ## @returns true when there is a current entry, false once every entry was visited
    ## @panics if an entry was added or removed since the iterator was created ("HashMap modified during iteration")
    next(): bool {
        assert(_source._table._version == _version, "HashMap modified during iteration");
        if (_started) {
            if (_index < _source._table._capacity) {
                _index = _index + 1;
            }
        } else {
            _started = true;
        }
        _index = _source._table._next_occupied(_index);
        return _index < _source._table._capacity;
    }

    ## Returns the entry the last successful `next()` moved to.
    ##
    ## @returns the current entry as a `(key, value)` tuple
    ## @panics if an entry was added or removed since the iterator was created ("HashMap modified during iteration")
    ## @panics if `next()` was never called or already returned false ("HashMapIterator.current() without an entry")
    current(): (K, V) {
        assert(_source._table._version == _version, "HashMap modified during iteration");
        assert(_started and _index < _source._table._capacity, "HashMapIterator.current() without an entry");
        return (_source._table._keys._data[_index], _source._table._values._data[_index]);
    }
}

## An `Iterator<K>` over the members of a `HashSet`, in no defined order;
## returned by `HashSet.iterate()` and driven by `for (var x in set)`.
##
## Holds a reference to the set. It is fail-fast: adding or removing a member
## after the iterator was created makes its next `next()` or `current()`
## panic.
##
## @typeParam K the element type of the set
## @see HashSet.iterate
[Value]
export struct HashSetIterator<K> {
    ## The set being iterated.
    HashSet<K> _source;
    ## The slot of the current member; meaningful once `_started` is set.
    ulong _index;
    ## The set's `_version` when iteration began.
    ulong _version;
    ## Whether `next()` has been called.
    bool _started;

    ## Creates an iterator positioned before the first member of `source`.
    ##
    ## @param source the set to iterate
    construct(source: HashSet<K>) {
        _source = source;
        _version = source._table._version;
    }

    ## Advances to the next member.
    ##
    ## @returns true when there is a current member, false once every member was visited
    ## @panics if a member was added or removed since the iterator was created ("HashSet modified during iteration")
    next(): bool {
        assert(_source._table._version == _version, "HashSet modified during iteration");
        if (_started) {
            if (_index < _source._table._capacity) {
                _index = _index + 1;
            }
        } else {
            _started = true;
        }
        _index = _source._table._next_occupied(_index);
        return _index < _source._table._capacity;
    }

    ## Returns the member the last successful `next()` moved to.
    ##
    ## @returns the current member
    ## @panics if a member was added or removed since the iterator was created ("HashSet modified during iteration")
    ## @panics if `next()` was never called or already returned false ("HashSetIterator.current() without a member")
    current(): K {
        assert(_source._table._version == _version, "HashSet modified during iteration");
        assert(_started and _index < _source._table._capacity, "HashSetIterator.current() without a member");
        return _source._table._keys._data[_index];
    }
}

# The start of a map literal: a new map holding `key: value`, whose types
# give the literal's key and value types (see `HashMap._literal_insert`).
export _map_literal<K, V>(key: K, value: V): HashMap<K, V> {
    var result = HashMap<K, V>();
    result.insert(key, value);
    return result;
}

extend HashSetIterator<K> with Iterator<K>;

extend HashMap<K, V> with Copyable<HashMap<K, V>>;

extend HashSet<K> with Copyable<HashSet<K>>;
