import "internals";

# ── Generic hash ─────────────────────────────────────────────────────────────
# FNV-1a 64-bit (the same constants as `_pep_hash_bytes` and the compiler's
# `__address` lowering).

## Returns a 64-bit FNV-1a hash of `value`, the hash `HashMap` and `HashSet`
## use for their keys.
##
## - POD types (integers, floats, pointers, `bool`) fold the value's own
##   bytes, so equal values hash equally.
## - Struct types hash by identity: the object's address, folded through
##   FNV-1a so that aligned addresses spread across buckets. Two distinct
##   objects with equal fields therefore hash differently and are distinct
##   keys. A null reference hashes to the FNV-1a offset basis.
## - `String` hashes by content through the concrete `hash<String>`
##   override, so equal strings at different addresses collide.
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
export hash<T>(T value): u64 {
    return __address<T>(value);
}

# Concrete override: `hash<String>` is a distinct function from the generic
# base and wins for String call sites (gather_generics rewrites it to its
# specialization form).

## Returns a 64-bit FNV-1a hash of a String's bytes, so equal strings hash
## equally wherever they are stored. Keeps equal `String` keys of a
## `HashMap` or `HashSet` in one bucket.
##
## Hashes the `size()` bytes of the String (not the NUL terminator) in O(size). An
## empty String hashes to the FNV-1a offset basis.
##
## @param value the String to hash; it must not be a null reference
## @returns the 64-bit hash of the String's content
## @example
##     assert(hash<String>("hello") == hash<String>("hello"), "content hash");
export hash<String>(String value): u64 {
    return _pep_hash_bytes(value.c_str(), value.size());
}

# ── HashMap<K, V> ───────────────────────────────────────────────────────────
# Open addressing with triangular probing over a power-of-two table:
# probe(i) = (h & mask) + i*(i+1)/2 visits every slot of the table, which
# the 50% grow threshold keeps reachable. Slot occupancy is tracked in a parallel
# state Array (0 = empty, 1 = tombstone, 2 = occupied) so K can be any type;
# keys and values live in arrays, whose store protocol handles struct
# reference counting for us. The map never uses the arrays' Size (it writes
# Data[idx] directly), but it keeps Size == capacity so an Array's destructor
# visits every slot when the map dies.

## A hash table that maps keys of type `K` to values of type `V`.
##
## Keys are hashed with `hash<K>` and compared with `==`: POD keys by value,
## `String` keys by content, and other struct keys by identity (two distinct
## objects with equal fields are different keys). Any type can be a key.
##
## The map holds one reference to each stored key and value. It acquires
## them when they are stored and releases them when they are overwritten,
## removed, cleared, or when the map is destroyed.
##
## Lookups, inserts, and removals take expected O(1) time. The table doubles
## before an insert of a new key would fill half of it (live entries plus
## removed-slot tombstones), so it never shrinks, and churn (many inserts and
## removals of different keys) can keep growing it even while `count()`
## stays small.
##
## There is no iterator, and entries have no defined order.
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
##     assert(ages.count() == 1, "one entry left");
export struct HashMap<K, V> {
    ## The key of each slot; only slots whose `_state` is 2 hold a live key,
    ## the rest hold the default of `K`. Internal: its count equals
    ## `_capacity` rather than the entry count, and `grow` replaces it.
    Array<K> _keys;
    ## The value of each slot, parallel to `_keys`; only occupied slots hold a
    ## live value. Internal: `grow` replaces it.
    Array<V> _values;
    ## The occupancy of each slot: 0 is empty, 1 is a tombstone (a removed
    ## entry that still extends probe sequences), 2 is occupied. Internal.
    Array<int> _state;
    ## The number of slots in the table: always a power of two and at least
    ## 8. Internal; read it with `capacity()`.
    ulong _capacity;
    ## The number of live entries. Internal; read it with `count()`.
    int _size;
    ## The number of tombstone slots. They count toward the grow threshold
    ## until an insert reuses them or `grow` or `clear` resets them.
    ## Internal.
    int _tombstones;

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
    construct(ulong initial_capacity = 8) {
        ulong cap = 8;
        while (cap < initial_capacity) {
            cap = cap * 2;
        }
        _capacity = cap;
        _size = 0;
        _tombstones = 0;
        _keys = Array<K>(cap);
        _values = Array<V>(cap);
        _state = Array<int>(cap);
        _keys._size = cap;
        _values._size = cap;
        _state._size = cap;
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
    long _find_slot(K key) {
        ulong mask = _capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < _capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = _state._data[idx];
            if (st == 2) {
                if (_keys._data[idx] == key) {
                    return idx;
                }
            } else {
                if (st == 0) {
                    return -1;
                }
            }
            i = i + 1;
        }
        return -1;
    }

    ## Doubles the table and reinserts every entry, dropping all tombstones.
    ##
    ## `insert` calls it automatically. Calling it directly is safe but only
    ## costs memory. Runs in O(capacity). It replaces the table's arrays and
    ## moves entries to new slots. Reference counts are unchanged overall:
    ## each entry is acquired by the new arrays and released by the old ones.
    void grow() {
        # Reinsertion goes through Array store semantics (acquire), so the
        # outgoing arrays can be dropped from the fields right after: the
        # field store releases them, their Size == capacity makes the
        # destructor visit every slot, and the buffer is freed.
        ulong new_cap = _capacity * 2;
        Array<K> new_keys = Array<K>(new_cap);
        Array<V> new_values = Array<V>(new_cap);
        Array<int> new_state = Array<int>(new_cap);
        new_keys._size = new_cap;
        new_values._size = new_cap;
        new_state._size = new_cap;
        ulong mask = new_cap - 1;
        ulong i = 0;
        while (i < _capacity) {
            if (_state._data[i] == 2) {
                K k = _keys._data[i];
                V v = _values._data[i];
                ulong h = hash<K>(k);
                ulong start = h & mask;
                ulong probe = 0;
                int placed = 0;
                while (probe < new_cap && placed == 0) {
                    ulong idx = (start + probe * (probe + 1) / 2) & mask;
                    if (new_state._data[idx] == 0) {
                        new_keys._data[idx] = k;
                        new_values._data[idx] = v;
                        new_state._data[idx] = 2;
                        placed = 1;
                    }
                    probe = probe + 1;
                }
            }
            i = i + 1;
        }
        _keys = new_keys;
        _values = new_values;
        _state = new_state;
        _capacity = new_cap;
        _tombstones = 0;
    }

    ## Returns the number of entries in the map. O(1).
    ##
    ## @returns the number of live key-value pairs
    int count() {
        return _size;
    }

    ## Returns whether the map has no entries. O(1).
    ##
    ## @returns true when `count()` is 0
    bool empty() {
        return _size == 0;
    }

    ## Returns the number of slots in the table, a power of two and at least 8.
    ## The map grows before its entries and tombstones reach half of it. O(1).
    ##
    ## @returns the current slot count
    ulong capacity() {
        return _capacity;
    }

    ## Deprecated: use `capacity` instead. Returns the number of slots in
    ## the table.
    ##
    ## @returns the same as `capacity()`
    [Deprecated("use 'capacity' instead", "capacity")]
    ulong cap() {
        return capacity();
    }

    ## Removes every entry and releases the map's references to their keys
    ## and values. The table keeps its capacity. Runs in O(capacity).
    void clear() {
        ulong i = 0;
        while (i < _capacity) {
            if (_state._data[i] == 2) {
                _keys._data[i] = __default<K>();
                _values._data[i] = __default<V>();
            }
            _state._data[i] = 0;
            i = i + 1;
        }
        _size = 0;
        _tombstones = 0;
    }

    ## Returns whether the map has an entry for `key`. Expected O(1).
    ##
    ## @param key the key to look up
    ## @returns true when `key` is present
    bool contains(K key) {
        return _find_slot(key) >= 0;
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
    bool insert(K key, V value) {
        long slot = _find_slot(key);
        if (slot >= 0) {
            _values._data[slot] = value;
            return false;
        }
        # Grow when occupied + tombstone slots reach half the table so the
        # probe sequence always covers every slot.
        # grow() reinserts every existing entry into the new table, and this
        # key is not among them (find_slot missed), so it must be placed by
        # the main path below — exactly once. Returning here would lose it;
        # falling through to a second find + insert would double-acquire.
        if ((_size + _tombstones) * 2 + 1 >= _capacity) {
            grow();
        }
        ulong mask = _capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < _capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = _state._data[idx];
            if (st == 0 || st == 1) {
                _keys._data[idx] = key;
                _values._data[idx] = value;
                _state._data[idx] = 2;
                # Claiming a tombstone slot empties it again.
                if (st == 1) {
                    _tombstones = _tombstones - 1;
                }
                _size = _size + 1;
                return true;
            }
            i = i + 1;
        }
        # Unreachable: the triangular probe visits every slot, and the grow
        # threshold keeps at least one empty slot free.
        return false;
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
    V get(K key) {
        long slot = _find_slot(key);
        if (slot >= 0) {
            return _values._data[slot];
        }
        return __default<V>();
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
    bool remove(K key) {
        long slot = _find_slot(key);
        if (slot < 0) {
            return false;
        }
        _keys._data[slot] = __default<K>();
        _values._data[slot] = __default<V>();
        _state._data[slot] = 1;
        _size = _size - 1;
        _tombstones = _tombstones + 1;
        return true;
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
    V [](K key) {
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
    V [](K key, V value) {
        insert(key, value);
        return value;
    }

    # No explicit slot loop here: each occupied slot holds exactly one ref
    # (acquired on insert), and the keys/values arrays' destructors null
    # every slot (Size == capacity), releasing it exactly once. The field
    # releases that release_field_refs appends run after this body, dropping
    # the arrays' own refs last.
    destruct {
    }
}

# ── HashSet<K> ──────────────────────────────────────────────────────────────
# Same table machinery as HashMap without the value Array.

## A hash set of distinct elements of type `K`, built on the same table as
## `HashMap` but without values.
##
## Elements are hashed with `hash<K>` and compared with `==`: POD elements
## by value, `String` elements by content, and other struct elements by
## identity (two distinct objects with equal fields are both members). The
## set holds one reference to each member. It acquires the reference on
## insert and releases it on remove, on `clear`, or when the set is
## destroyed.
##
## Membership tests, inserts, and removals take expected O(1) time. The
## table doubles before an insert of a new element would fill half of it
## (members plus tombstones), and it never shrinks. There is no iterator, and
## members have no defined order. The lowercase fields and the `_find_slot`
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
##     assert(seen.count() == 2, "two members");
export struct HashSet<K> {
    ## The element of each slot; only slots whose `_state` is 2 hold a live
    ## member, the rest hold the default of `K`. Internal: its count equals
    ## `_capacity` rather than the member count, and `grow` replaces it.
    Array<K> _keys;
    ## The occupancy of each slot: 0 is empty, 1 is a tombstone (a removed
    ## member that still extends probe sequences), 2 is occupied. Internal.
    Array<int> _state;
    ## The number of slots in the table: always a power of two and at least
    ## 8. Internal; read it with `capacity()`.
    ulong _capacity;
    ## The number of members. Internal; read it with `count()`.
    int _size;
    ## The number of tombstone slots. They count toward the grow threshold
    ## until an insert reuses them or `grow` or `clear` resets them.
    ## Internal.
    int _tombstones;

    ## Creates an empty set whose table has room for at least
    ## `initial_capacity` slots.
    ##
    ## The slot count is rounded up to a power of two, with a minimum of 8.
    ## The set holds up to half its slot count before the first grow.
    ##
    ## @param initial_capacity the minimum number of slots in the table
    construct(ulong initial_capacity = 8) {
        ulong cap = 8;
        while (cap < initial_capacity) {
            cap = cap * 2;
        }
        _capacity = cap;
        _size = 0;
        _tombstones = 0;
        _keys = Array<K>(cap);
        _state = Array<int>(cap);
        _keys._size = cap;
        _state._size = cap;
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
    long _find_slot(K key) {
        ulong mask = _capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < _capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = _state._data[idx];
            if (st == 2) {
                if (_keys._data[idx] == key) {
                    return idx;
                }
            } else {
                if (st == 0) {
                    return -1;
                }
            }
            i = i + 1;
        }
        return -1;
    }

    ## Doubles the table and reinserts every member, dropping all tombstones.
    ##
    ## `insert` calls it automatically. Calling it directly is safe but only
    ## costs memory. Runs in O(capacity). It replaces the table's arrays and
    ## moves members to new slots.
    void grow() {
        # Dropping the old arrays from the fields releases them (field stores
        # transfer ownership), and their Size == capacity makes the
        # destructor visit every slot.
        ulong new_cap = _capacity * 2;
        Array<K> new_keys = Array<K>(new_cap);
        Array<int> new_state = Array<int>(new_cap);
        new_keys._size = new_cap;
        new_state._size = new_cap;
        ulong mask = new_cap - 1;
        ulong i = 0;
        while (i < _capacity) {
            if (_state._data[i] == 2) {
                K k = _keys._data[i];
                ulong h = hash<K>(k);
                ulong start = h & mask;
                ulong probe = 0;
                int placed = 0;
                while (probe < new_cap && placed == 0) {
                    ulong idx = (start + probe * (probe + 1) / 2) & mask;
                    if (new_state._data[idx] == 0) {
                        new_keys._data[idx] = k;
                        new_state._data[idx] = 2;
                        placed = 1;
                    }
                    probe = probe + 1;
                }
            }
            i = i + 1;
        }
        _keys = new_keys;
        _state = new_state;
        _capacity = new_cap;
        _tombstones = 0;
    }

    ## Returns the number of members in the set. O(1).
    ##
    ## @returns the number of members
    int count() {
        return _size;
    }

    ## Returns whether the set has no members. O(1).
    ##
    ## @returns true when `count()` is 0
    bool empty() {
        return _size == 0;
    }

    ## Returns the number of slots in the table, a power of two and at least 8.
    ## O(1).
    ##
    ## @returns the current slot count
    ulong capacity() {
        return _capacity;
    }

    ## Deprecated: use `capacity` instead. Returns the number of slots in
    ## the table.
    ##
    ## @returns the same as `capacity()`
    [Deprecated("use 'capacity' instead", "capacity")]
    ulong cap() {
        return capacity();
    }

    ## Removes every member and releases the set's references to them. The
    ## table keeps its capacity. Runs in O(capacity).
    void clear() {
        ulong i = 0;
        while (i < _capacity) {
            if (_state._data[i] == 2) {
                _keys._data[i] = __default<K>();
            }
            _state._data[i] = 0;
            i = i + 1;
        }
        _size = 0;
        _tombstones = 0;
    }

    ## Returns whether `key` is a member of the set. Expected O(1).
    ##
    ## @param key the element to look up
    ## @returns true when `key` is a member
    bool contains(K key) {
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
    bool insert(K key) {
        long slot = _find_slot(key);
        if (slot >= 0) {
            return false;
        }
        # Grow when occupied + tombstone slots reach half the table so the
        # probe sequence always covers every slot.
        # grow() reinserts every existing entry into the new table, and this
        # key is not among them (find_slot missed), so it must be placed by
        # the main path below — exactly once. Returning here would lose it;
        # falling through to a second find + insert would double-acquire.
        if ((_size + _tombstones) * 2 + 1 >= _capacity) {
            grow();
        }
        ulong mask = _capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < _capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = _state._data[idx];
            if (st == 0 || st == 1) {
                _keys._data[idx] = key;
                _state._data[idx] = 2;
                # Claiming a tombstone slot empties it again.
                if (st == 1) {
                    _tombstones = _tombstones - 1;
                }
                _size = _size + 1;
                return true;
            }
            i = i + 1;
        }
        # Unreachable: the triangular probe visits every slot, and the grow
        # threshold keeps at least one empty slot free.
        return false;
    }

    ## Removes `key` from the set, releasing the set's reference to the
    ## member. Does nothing when `key` is not a member. The slot becomes a
    ## tombstone (see `_tombstones`). Expected O(1).
    ##
    ## @param key the element to remove
    ## @returns true when `key` was a member and was removed, false otherwise
    bool remove(K key) {
        long slot = _find_slot(key);
        if (slot < 0) {
            return false;
        }
        _keys._data[slot] = __default<K>();
        _state._data[slot] = 1;
        _size = _size - 1;
        _tombstones = _tombstones + 1;
        return true;
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
    K [](K key) {
        long slot = _find_slot(key);
        if (slot >= 0) {
            return _keys._data[slot];
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
    K [](K key, K value) {
        insert(key);
        return key;
    }

    # No explicit slot loop here: each occupied slot holds exactly one ref
    # (acquired on insert), and the keys Array's destructor nulls every slot
    # (Size == capacity), releasing it exactly once. The field release that
    # release_field_refs appends runs after this body, dropping the Array's
    # own ref last.
    destruct {
    }
}
