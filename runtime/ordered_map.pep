## `OrderedMap<K, V>`: a hash map that keeps its keys in the order they were
## first inserted.

# Entries live in parallel arrays in insertion order; a `_HashTable` maps
# each key to its entry's position. Removing an entry leaves a hole (its
# `_live` flag cleared, its key and value reset to the default so they are
# released at once), which iteration skips. Once holes outnumber the live
# entries the arrays are compacted and the table's positions rewritten, so
# removal is amortized O(1) and the arrays stay at most about twice the
# entry count.

## A hash map that iterates its entries in the order their keys were first
## inserted, like Python's `dict`.
##
## Keys are hashed with `hash<K>` and compared with `==`, as in `HashMap`.
## Lookups, inserts and removals take expected O(1) time. Setting the value
## of a key that is already present keeps its position; removing a key and
## inserting it again moves it to the end.
##
## `iterate()` visits the entries as `(key, value)` tuples in insertion
## order. The map holds one reference to each stored key and value, acquired
## when they are stored and released when they are overwritten, removed,
## cleared, or when the map is destroyed.
##
## @typeParam K the key type; hashed with `hash<K>` and compared with `==`
## @typeParam V the value type
## @example
##     var config = OrderedMap<String, String>();
##     config["name"] = "pepper";
##     config["version"] = "0.2";
##     config["license"] = "MIT";
##     for (var (key, value) in config) {
##         print($"{key} = {value}");   # name, version, license
##     }
export struct OrderedMap<K, V> {
    ## Maps each key to the position of its entry. Internal.
    _HashTable<K, ulong> _positions;
    ## The key of each entry, in insertion order. Internal.
    Array<K> _keys;
    ## The value of each entry, parallel to `_keys`. Internal.
    Array<V> _values;
    ## Whether each entry is live (false for a removed entry's hole). Internal.
    Array<bool> _live;
    ## The number of live entries. Internal.
    int _size;
    ## Counts the changes that add or remove entries, so an iterator can
    ## tell that the map changed under it. Internal.
    ulong _version;

    ## Creates an empty map whose table has room for at least
    ## `initial_capacity` slots (see `HashMap`).
    ##
    ## @param initial_capacity the minimum number of slots in the table
    construct(initial_capacity: ulong = 8) {
        _positions._init(initial_capacity);
        _keys = Array<K>();
        _values = Array<V>();
        _live = Array<bool>();
    }

    ## The number of entries in the map. O(1).
    var count: int {
        get {
            return _size;
        }
    }

    ## Whether the map has no entries. O(1).
    var is_empty: bool {
        get {
            return _size == 0;
        }
    }

    ## Removes every entry and releases the map's references to their keys
    ## and values. O(capacity).
    clear() {
        _positions._clear();
        _keys.clear();
        _values.clear();
        _live.clear();
        _size = 0;
        _version += 1;
    }

    ## Returns whether the map has an entry for `key`. Expected O(1).
    ##
    ## @param key the key to look up
    ## @returns true when `key` is present
    contains(key: K): bool {
        return _positions._find_slot(key) >= 0;
    }

    ## Maps `key` to `value`. A new key is added at the end of the order; an
    ## existing key keeps its position (and the key object the map already
    ## stores), and only its value is replaced. Expected O(1).
    ##
    ## @param key the key to add or update
    ## @param value the value to store for `key`
    ## @returns true when a new key was added, false when an existing key's
    ##   value was overwritten
    insert(key: K, value: V): bool {
        long slot = _positions._find_slot(key);
        if (slot >= 0) {
            _values[_positions._values._data[slot]] = value;
            return false;
        }
        _positions._insert(key, _keys.count);
        _keys.append(key);
        _values.append(value);
        _live.append(true);
        _size = _size + 1;
        _version += 1;
        return true;
    }

    ## Returns the value stored for `key`, or the default of `V` (0, or a
    ## null reference for struct types) when `key` is absent. A missing key
    ## is not inserted. Expected O(1).
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or the default of `V` when absent
    ## @see try_get
    get(key: K): V {
        long slot = _positions._find_slot(key);
        if (slot >= 0) {
            return _values[_positions._values._data[slot]];
        }
        return __default<V>();
    }

    ## Returns the value stored for `key`, or none when `key` is absent.
    ## Expected O(1).
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or none when absent
    try_get(key: K): V? {
        long slot = _positions._find_slot(key);
        if (slot >= 0) {
            return Optional<V>.Value(_values[_positions._values._data[slot]]);
        }
        return Optional<V>.Empty;
    }

    ## Removes the entry for `key`, releasing the map's references to its
    ## key and value. The other entries keep their order. Does nothing when
    ## `key` is absent. Amortized expected O(1).
    ##
    ## @param key the key to remove
    ## @returns true when `key` was present and removed, false when absent
    remove(key: K): bool {
        long slot = _positions._find_slot(key);
        if (slot < 0) {
            return false;
        }
        var position = _positions._values._data[slot];
        _positions._remove(key);
        _keys[position] = __default<K>();
        _values[position] = __default<V>();
        _live[position] = false;
        _size = _size - 1;
        _version += 1;
        if (_keys.count >= 16 and _keys.count > (_size as ulong) * 2) {
            _compact();
        }
        return true;
    }

    # Moves the live entries to the front, in order, drops the holes, and
    # points the table at the new positions.
    _compact() {
        ulong to = 0;
        ulong from = 0;
        var end = _keys.count;
        while (from < end) {
            if (_live[from]) {
                if (to != from) {
                    _keys.swap(to, from);
                    _values.swap(to, from);
                    _live.swap(to, from);
                    long slot = _positions._find_slot(_keys[to]);
                    _positions._values._data[slot] = to;
                }
                to = to + 1;
            }
            from = from + 1;
        }
        _keys.truncate(to);
        _values.truncate(to);
        _live.truncate(to);
    }

    ## Reads `m[key]`: the same as `get`. A missing key reads as the default
    ## of `V` and is not inserted.
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or the default of `V` when absent
    [](key: K): V {
        return get(key);
    }

    ## Writes `m[key] = value`: the same as `insert`.
    ##
    ## @param key the key to add or update
    ## @param value the value to store for `key`
    ## @returns `value`, the value of the assignment expression
    [](key: K, value: V): V {
        insert(key, value);
        return value;
    }

    ## Returns an iterator over the entries as `(key, value)` tuples in
    ## insertion order; `for (var (key, value) in map)` drives it.
    ##
    ## The iterator holds a reference to the map. Changing a value through
    ## an existing key while iterating is allowed; adding or removing an
    ## entry makes the iterator's next `next()` or `current()` panic.
    ##
    ## @returns an iterator positioned before the first entry
    iterate(): OrderedMapIterator<K, V> {
        return OrderedMapIterator<K, V>(this);
    }

    ## Returns a deep copy: a new map holding a copy of each key and value,
    ## in the same order, made with `copies.copy`. This is how `copy(value)`
    ## copies an OrderedMap (the `Copyable<OrderedMap<K, V>>`
    ## implementation); call `copy(map)` rather than this method.
    ##
    ## @param copies the objects copied so far
    ## @returns the copy
    copy(copies: Copies): OrderedMap<K, V> {
        var made = OrderedMap<K, V>(_positions._capacity);
        copies.register<OrderedMap<K, V>>(this, made);
        ulong i = 0;
        while (i < _keys.count) {
            if (_live[i]) {
                made.insert(copies.copy<K>(_keys[i]), copies.copy<V>(_values[i]));
            }
            i = i + 1;
        }
        return made;
    }
}

## An iterator over the entries of an `OrderedMap` as `(key, value)` tuples
## in insertion order; returned by `OrderedMap.iterate()` and driven by
## `for (var (key, value) in map)`.
##
## Holds a reference to the map. It is fail-fast: adding or removing an
## entry after the iterator was created makes its next `next()` or
## `current()` panic.
##
## @typeParam K the key type of the map
## @typeParam V the value type of the map
## @see OrderedMap.iterate
[Value]
export struct OrderedMapIterator<K, V> {
    ## The map being iterated.
    OrderedMap<K, V> _source;
    ## The position of the current entry; meaningful once `_started` is set.
    ulong _index;
    ## The map's `_version` when iteration began.
    ulong _version;
    ## Whether `next()` has been called.
    bool _started;

    ## Creates an iterator positioned before the first entry of `source`.
    ##
    ## @param source the map to iterate
    construct(source: OrderedMap<K, V>) {
        _source = source;
        _version = source._version;
    }

    ## Advances to the next entry.
    ##
    ## @returns true when there is a current entry, false once every entry was visited
    ## @panics if an entry was added or removed since the iterator was created ("OrderedMap modified during iteration")
    next(): bool {
        assert(_source._version == _version, "OrderedMap modified during iteration");
        var end = _source._keys.count;
        if (_started) {
            if (_index < end) {
                _index = _index + 1;
            }
        } else {
            _started = true;
        }
        while (_index < end and !_source._live[_index]) {
            _index = _index + 1;
        }
        return _index < end;
    }

    ## Returns the entry the last successful `next()` moved to.
    ##
    ## @returns the current entry as a `(key, value)` tuple
    ## @panics if an entry was added or removed since the iterator was created ("OrderedMap modified during iteration")
    ## @panics if `next()` was never called or already returned false ("OrderedMapIterator.current() without an entry")
    current(): (K, V) {
        assert(_source._version == _version, "OrderedMap modified during iteration");
        assert(_started and _index < _source._keys.count, "OrderedMapIterator.current() without an entry");
        return (_source._keys[_index], _source._values[_index]);
    }
}

extend OrderedMap<K, V> with Copyable<OrderedMap<K, V>>;
