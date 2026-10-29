## Sorted collections: `Map<K, V>` and `Set<K>`, kept in key order on a
## red-black tree, and `compare<T>`, the ordering they sort keys by.

# ── Ordering ────────────────────────────────────────────────────────────────

## Returns a negative number when `a` sorts before `b`, zero when they are
## equal, and a positive number when `a` sorts after `b`: the order `Map` and
## `Set` keep their keys in.
##
## The generic version compares with `<`, so it works for every
## `Comparable` type (see `Comparable`), every integer type, `char`, and any
## struct that declares a `<` operator. Two values neither of which is `<`
## the other are equal keys. `String`, `float` and `double` go through
## concrete overrides that call their `compare`, so a NaN key sorts after
## every number instead of breaking the order.
##
## A struct with no `<` operator declares `Comparable`, or overrides this
## function for itself, to be a `Map` key or `Set` element:
## `compare<Point>(a: Point, b: Point): int`. The order must be a strict
## weak order (consistent across calls), or the tree loses track of its
## keys.
##
## @typeParam T the type of the values to compare
## @param a the first value
## @param b the second value
## @returns a negative number, zero or a positive number as `a` sorts before,
##   equal to or after `b`
## @see compare<String>
## @example
##     assert(compare<int>(1, 2) < 0, "1 sorts first");
##     assert(compare<int>(2, 2) == 0, "equal");
export compare<T>(a: T, b: T): int {
    if (a < b) {
        return -1;
    }
    if (b < a) {
        return 1;
    }
    return 0;
}

## Compares two Strings by content, the order `Map` and `Set` keep `String`
## keys in: the same as `a.compare(b)`.
##
## @param a the first String
## @param b the second String
## @returns a negative number, zero or a positive number as `a` sorts before,
##   equal to or after `b`
## @example
##     assert(compare<String>("apple", "pear") < 0, "apple sorts first");
export compare<String>(a: String, b: String): int {
    return a.compare(b);
}

## Compares two `float`s in `float.compare`'s total order: by value, with
## NaN after every number.
##
## @param a the first value
## @param b the second value
## @returns -1, 0 or 1 as `a` sorts before, with or after `b`
export compare<float>(a: float, b: float): int {
    return a.compare(b);
}

## Compares two `double`s in `double.compare`'s total order: by value, with
## NaN after every number.
##
## @param a the first value
## @param b the second value
## @returns -1, 0 or 1 as `a` sorts before, with or after `b`
export compare<double>(a: double, b: double): int {
    return a.compare(b);
}

# ── The tree ────────────────────────────────────────────────────────────────
# A red-black tree (CLRS) whose nodes live in parallel arrays, addressed by
# index. Index 0 is the sentinel "nil" node: always black, its key and value
# the defaults. Child and parent links are indices, so the tree keeps no
# reference cycles and costs no reference counting to walk. Removed nodes go
# on a free list (linked through `_right`) and are reused by later inserts;
# their key and value slots are reset to the default so the tree releases
# them at once.
#
# One tree serves both containers, as `_HashTable` does for HashMap and
# HashSet: a Set's tree has `_NoValue` values, which take no bytes.

# The tree behind `Map` and `Set`. Internal.
[Value]
export struct _RedBlackTree<K, V> {
    # The key of each node; index 0 is the sentinel.
    Array<K> _keys;
    # The value of each node, parallel to `_keys`.
    Array<V> _values;
    # The left child of each node, 0 for none.
    Array<ulong> _left;
    # The right child of each node, 0 for none; on the free list, the next
    # free node.
    Array<ulong> _right;
    # The parent of each node, 0 for the root.
    Array<ulong> _parent;
    # Whether each node is red; the sentinel is always black.
    Array<bool> _red;
    # The root node, 0 when the tree is empty.
    ulong _root;
    # The first node on the free list, 0 when it is empty.
    ulong _free;
    # The number of live entries.
    int _size;
    # Counts the changes that add or remove entries, so an iterator can tell
    # that the tree changed under it.
    ulong _version;

    # Sets up an empty tree: just the sentinel.
    _init() {
        _keys = Array<K>();
        _values = Array<V>();
        _left = Array<ulong>();
        _right = Array<ulong>();
        _parent = Array<ulong>();
        _red = Array<bool>();
        _keys.append(__default<K>());
        _values.append(__default<V>());
        _left.append(0);
        _right.append(0);
        _parent.append(0);
        _red.append(false);
        _root = 0;
        _free = 0;
        _size = 0;
    }

    # A new red leaf holding `key` and `value` under `parent`.
    _new_node(key: K, value: V, parent: ulong): ulong {
        if (_free != 0) {
            var node = _free;
            _free = _right[node];
            _keys[node] = key;
            _values[node] = value;
            _left[node] = 0;
            _right[node] = 0;
            _parent[node] = parent;
            _red[node] = true;
            return node;
        }
        _keys.append(key);
        _values.append(value);
        _left.append(0);
        _right.append(0);
        _parent.append(parent);
        _red.append(true);
        return _keys.count - 1;
    }

    # The node holding `key`, or 0 when there is none.
    _find(key: K): ulong {
        var node = _root;
        while (node != 0) {
            var order = compare<K>(key, _keys[node]);
            if (order == 0) {
                return node;
            }
            node = order < 0 ? _left[node] : _right[node];
        }
        return 0;
    }

    # The leftmost node of the subtree at `node` (not 0).
    _minimum(node: ulong): ulong {
        var at = node;
        while (_left[at] != 0) {
            at = _left[at];
        }
        return at;
    }

    # The rightmost node of the subtree at `node` (not 0).
    _maximum(node: ulong): ulong {
        var at = node;
        while (_right[at] != 0) {
            at = _right[at];
        }
        return at;
    }

    # The first node in key order, 0 when the tree is empty.
    _first(): ulong {
        return _root == 0 ? 0 : _minimum(_root);
    }

    # The last node in key order, 0 when the tree is empty.
    _last(): ulong {
        return _root == 0 ? 0 : _maximum(_root);
    }

    # The node after `node` in key order, 0 after the last.
    _successor(node: ulong): ulong {
        if (_right[node] != 0) {
            return _minimum(_right[node]);
        }
        var child = node;
        var at = _parent[node];
        while (at != 0 and child == _right[at]) {
            child = at;
            at = _parent[at];
        }
        return at;
    }

    # The node before `node` in key order, 0 before the first.
    _predecessor(node: ulong): ulong {
        if (_left[node] != 0) {
            return _maximum(_left[node]);
        }
        var child = node;
        var at = _parent[node];
        while (at != 0 and child == _left[at]) {
            child = at;
            at = _parent[at];
        }
        return at;
    }

    # The next node in an iteration that runs forward or in `reverse`.
    _step(node: ulong, reverse: bool): ulong {
        return reverse ? _predecessor(node) : _successor(node);
    }

    # The first node whose key is not less than `key` (`strict`: greater
    # than `key`), 0 when there is none.
    _bound(key: K, strict: bool): ulong {
        var node = _root;
        ulong result = 0;
        while (node != 0) {
            var order = compare<K>(_keys[node], key);
            if (order > 0 or (order == 0 and !strict)) {
                result = node;
                node = _left[node];
            } else {
                node = _right[node];
            }
        }
        return result;
    }

    _rotate_left(node: ulong) {
        var pivot = _right[node];
        _right[node] = _left[pivot];
        if (_left[pivot] != 0) {
            _parent[_left[pivot]] = node;
        }
        _replace_child(node, pivot);
        _left[pivot] = node;
        _parent[node] = pivot;
    }

    _rotate_right(node: ulong) {
        var pivot = _left[node];
        _left[node] = _right[pivot];
        if (_right[pivot] != 0) {
            _parent[_right[pivot]] = node;
        }
        _replace_child(node, pivot);
        _right[pivot] = node;
        _parent[node] = pivot;
    }

    # Puts `replacement` where `node` hangs from its parent (or the root),
    # and gives it `node`'s parent; `replacement` may be the sentinel.
    _replace_child(node: ulong, replacement: ulong) {
        var parent = _parent[node];
        if (parent == 0) {
            _root = replacement;
        } else if (node == _left[parent]) {
            _left[parent] = replacement;
        } else {
            _right[parent] = replacement;
        }
        _parent[replacement] = parent;
    }

    # Stores `value` for `key`: replaces the value when `key` is present
    # (keeping the stored key) and returns false, else adds the entry and
    # returns true.
    _insert(key: K, value: V): bool {
        ulong parent = 0;
        var node = _root;
        var order = 0;
        while (node != 0) {
            parent = node;
            order = compare<K>(key, _keys[node]);
            if (order == 0) {
                if (sizeof<V>() != 0) {
                    _values[node] = value;
                }
                return false;
            }
            node = order < 0 ? _left[node] : _right[node];
        }
        var added = _new_node(key, value, parent);
        if (parent == 0) {
            _root = added;
        } else if (order < 0) {
            _left[parent] = added;
        } else {
            _right[parent] = added;
        }
        _insert_fixup(added);
        _size = _size + 1;
        _version += 1;
        return true;
    }

    # Restores the red-black rules after `node` was added as a red leaf.
    _insert_fixup(node: ulong) {
        var at = node;
        while (_red[_parent[at]]) {
            var parent = _parent[at];
            var grandparent = _parent[parent];
            if (parent == _left[grandparent]) {
                var uncle = _right[grandparent];
                if (_red[uncle]) {
                    _red[parent] = false;
                    _red[uncle] = false;
                    _red[grandparent] = true;
                    at = grandparent;
                } else {
                    if (at == _right[parent]) {
                        at = parent;
                        _rotate_left(at);
                        parent = _parent[at];
                    }
                    _red[parent] = false;
                    _red[grandparent] = true;
                    _rotate_right(grandparent);
                }
            } else {
                var uncle = _left[grandparent];
                if (_red[uncle]) {
                    _red[parent] = false;
                    _red[uncle] = false;
                    _red[grandparent] = true;
                    at = grandparent;
                } else {
                    if (at == _left[parent]) {
                        at = parent;
                        _rotate_right(at);
                        parent = _parent[at];
                    }
                    _red[parent] = false;
                    _red[grandparent] = true;
                    _rotate_left(grandparent);
                }
            }
        }
        _red[_root] = false;
    }

    # Removes `key`'s entry; false when it is absent.
    _remove(key: K): bool {
        var node = _find(key);
        if (node == 0) {
            return false;
        }
        _remove_node(node);
        return true;
    }

    # Unlinks `node`, rebalances, and puts its slot on the free list.
    _remove_node(node: ulong) {
        var moved = node;
        var moved_red = _red[moved];
        ulong fill = 0;
        if (_left[node] == 0) {
            fill = _right[node];
            _replace_child(node, fill);
        } else if (_right[node] == 0) {
            fill = _left[node];
            _replace_child(node, fill);
        } else {
            # Two children: the successor takes `node`'s place.
            moved = _minimum(_right[node]);
            moved_red = _red[moved];
            fill = _right[moved];
            if (_parent[moved] == node) {
                _parent[fill] = moved;
            } else {
                _replace_child(moved, fill);
                _right[moved] = _right[node];
                _parent[_right[moved]] = moved;
            }
            _replace_child(node, moved);
            _left[moved] = _left[node];
            _parent[_left[moved]] = moved;
            _red[moved] = _red[node];
        }
        if (!moved_red) {
            _remove_fixup(fill);
        }
        _keys[node] = __default<K>();
        if (sizeof<V>() != 0) {
            _values[node] = __default<V>();
        }
        _right[node] = _free;
        _free = node;
        _size = _size - 1;
        _version += 1;
    }

    # Restores the red-black rules after a black node was unlinked and
    # `node` (perhaps the sentinel) took its place.
    _remove_fixup(node: ulong) {
        var at = node;
        while (at != _root and !_red[at]) {
            var parent = _parent[at];
            if (at == _left[parent]) {
                var sibling = _right[parent];
                if (_red[sibling]) {
                    _red[sibling] = false;
                    _red[parent] = true;
                    _rotate_left(parent);
                    sibling = _right[parent];
                }
                if (!_red[_left[sibling]] and !_red[_right[sibling]]) {
                    _red[sibling] = true;
                    at = parent;
                } else {
                    if (!_red[_right[sibling]]) {
                        _red[_left[sibling]] = false;
                        _red[sibling] = true;
                        _rotate_right(sibling);
                        sibling = _right[parent];
                    }
                    _red[sibling] = _red[parent];
                    _red[parent] = false;
                    _red[_right[sibling]] = false;
                    _rotate_left(parent);
                    at = _root;
                }
            } else {
                var sibling = _left[parent];
                if (_red[sibling]) {
                    _red[sibling] = false;
                    _red[parent] = true;
                    _rotate_right(parent);
                    sibling = _left[parent];
                }
                if (!_red[_left[sibling]] and !_red[_right[sibling]]) {
                    _red[sibling] = true;
                    at = parent;
                } else {
                    if (!_red[_left[sibling]]) {
                        _red[_right[sibling]] = false;
                        _red[sibling] = true;
                        _rotate_left(sibling);
                        sibling = _left[parent];
                    }
                    _red[sibling] = _red[parent];
                    _red[parent] = false;
                    _red[_left[sibling]] = false;
                    _rotate_right(parent);
                    at = _root;
                }
            }
        }
        _red[at] = false;
    }

    # Removes every entry, releasing the keys and values, and keeps the
    # arrays' capacity.
    _clear() {
        _keys.truncate(1);
        _values.truncate(1);
        _left.truncate(1);
        _right.truncate(1);
        _parent.truncate(1);
        _red.truncate(1);
        _root = 0;
        _free = 0;
        _size = 0;
        _version += 1;
    }

    # The first node of the entries with `from <= key < to`, 0 when the
    # range is empty because `from` is not less than `to`.
    _range_start(from: K, to: K): ulong {
        if (compare<K>(from, to) >= 0) {
            return 0;
        }
        return _bound(from, false);
    }
}

# ── Map<K, V> ───────────────────────────────────────────────────────────────

## A map from keys of type `K` to values of type `V` that keeps its keys
## sorted.
##
## Keys are ordered by `compare<K>`: numbers by value, `String` by content,
## and other structs by their `<` operator or a `compare<K>` override. Two
## keys that compare equal are the same key. Lookups, inserts and removals
## take O(log count) time on a red-black tree.
##
## `iterate()` visits the entries as `(key, value)` tuples in ascending key
## order, `reversed()` in descending order, and `range(from, to)` the keys
## from `from` up to (not including) `to`. `first`, `last`, `lower_bound`
## and `upper_bound` find single entries by order.
##
## The map holds one reference to each stored key and value. It acquires
## them when they are stored and releases them when they are overwritten,
## removed, cleared, or when the map is destroyed.
##
## For keys kept in the order they were inserted, use `OrderedMap`; for
## expected O(1) lookups in no order, `HashMap`.
##
## @typeParam K the key type; ordered by `compare<K>`
## @typeParam V the value type
## @example
##     var scores = Map<String, int>();
##     scores["carol"] = 91;
##     scores["alice"] = 84;
##     scores["bob"] = 77;
##     for (var (name, score) in scores) {
##         print($"{name}: {score}");   # alice, bob, carol
##     }
export struct Map<K, V> {
    ## The tree holding the entries. Internal.
    _RedBlackTree<K, V> _tree;

    ## Creates an empty map.
    construct() {
        _tree._init();
    }

    ## The number of entries in the map. O(1).
    var count: int {
        get {
            return _tree._size;
        }
    }

    ## Whether the map has no entries. O(1).
    var is_empty: bool {
        get {
            return _tree._size == 0;
        }
    }

    ## Removes every entry and releases the map's references to their keys
    ## and values. O(count).
    clear() {
        _tree._clear();
    }

    ## Returns whether the map has an entry for `key`. O(log count).
    ##
    ## @param key the key to look up
    ## @returns true when `key` is present
    contains(key: K): bool {
        return _tree._find(key) != 0;
    }

    ## Maps `key` to `value`, adding a new entry or overwriting the value of
    ## an existing one.
    ##
    ## When the key is already present, only the value is replaced: the map
    ## keeps the key object it already stores and releases the old value.
    ## O(log count).
    ##
    ## @param key the key to add or update
    ## @param value the value to store for `key`
    ## @returns true when a new key was added, false when an existing key's
    ##   value was overwritten
    insert(key: K, value: V): bool {
        return _tree._insert(key, value);
    }

    ## Returns the value stored for `key`, or the default of `V` (0, or a
    ## null reference for struct types) when `key` is absent. A missing key
    ## is not inserted. O(log count).
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or the default of `V` when absent
    ## @see try_get
    get(key: K): V {
        var node = _tree._find(key);
        if (node != 0) {
            return _tree._values[node];
        }
        return __default<V>();
    }

    ## Returns the value stored for `key`, or none when `key` is absent.
    ## O(log count).
    ##
    ## @param key the key to look up
    ## @returns the value for `key`, or none when absent
    ## @example
    ##     if (scores.try_get("alice") is Value(score)) {
    ##         print($"{score}");
    ##     }
    try_get(key: K): V? {
        var node = _tree._find(key);
        if (node != 0) {
            return Optional<V>.Value(_tree._values[node]);
        }
        return Optional<V>.Empty;
    }

    ## Removes the entry for `key`, releasing the map's references to its
    ## key and value. Does nothing when `key` is absent. O(log count).
    ##
    ## @param key the key to remove
    ## @returns true when `key` was present and removed, false when absent
    remove(key: K): bool {
        return _tree._remove(key);
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

    # The entry at `node` as a tuple, or none for the sentinel.
    _entry(node: ulong): (K, V)? {
        if (node == 0) {
            return Optional<(K, V)>.Empty;
        }
        return Optional<(K, V)>.Value((_tree._keys[node], _tree._values[node]));
    }

    ## Returns the entry with the smallest key. O(log count).
    ##
    ## @returns the first `(key, value)` in key order, or none when the map
    ##   is empty
    first(): (K, V)? {
        return _entry(_tree._first());
    }

    ## Returns the entry with the largest key. O(log count).
    ##
    ## @returns the last `(key, value)` in key order, or none when the map is
    ##   empty
    last(): (K, V)? {
        return _entry(_tree._last());
    }

    ## Returns the first entry whose key is not less than `key`: the entry
    ## for `key` itself when present, else the next one after it. O(log
    ## count).
    ##
    ## @param key the key to search from
    ## @returns the first `(key, value)` with a key `>= key`, or none when
    ##   every key is less
    ## @example
    ##     var after_b = scores.lower_bound("b");   # ("bob", 77)
    lower_bound(key: K): (K, V)? {
        return _entry(_tree._bound(key, false));
    }

    ## Returns the first entry whose key is greater than `key`. O(log count).
    ##
    ## @param key the key to search from
    ## @returns the first `(key, value)` with a key `> key`, or none when no
    ##   key is greater
    upper_bound(key: K): (K, V)? {
        return _entry(_tree._bound(key, true));
    }

    ## Returns an iterator over the entries as `(key, value)` tuples in
    ## ascending key order; `for (var (key, value) in map)` drives it.
    ##
    ## The iterator holds a reference to the map. Changing a value through
    ## an existing key while iterating is allowed; adding or removing an
    ## entry makes the iterator's next `next()` or `current()` panic.
    ##
    ## @returns an iterator positioned before the first entry
    iterate(): SortedMapIterator<K, V> {
        return SortedMapIterator<K, V>(this, _tree._first(), 0, false);
    }

    ## Returns an iterator over the entries in descending key order, under
    ## the same rules as `iterate`.
    ##
    ## @returns an iterator positioned before the last entry
    ## @example
    ##     for (var (name, score) in scores.reversed()) {
    ##         print(name);   # carol, bob, alice
    ##     }
    reversed(): SortedMapIterator<K, V> {
        return SortedMapIterator<K, V>(this, _tree._last(), 0, true);
    }

    ## Returns an iterator over the entries whose keys are at least `from`
    ## and less than `to`, in ascending key order, under the same rules as
    ## `iterate`. It is empty when `from` is not less than `to`.
    ##
    ## @param from the smallest key to visit
    ## @param to the key to stop before
    ## @returns an iterator positioned before the first entry in the range
    ## @example
    ##     for (var (name, score) in scores.range("a", "c")) {
    ##         print(name);   # alice, bob
    ##     }
    range(from: K, to: K): SortedMapIterator<K, V> {
        var start = _tree._range_start(from, to);
        var stop = start == 0 ? 0 : _tree._bound(to, false);
        return SortedMapIterator<K, V>(this, start, stop, false);
    }

    ## Returns a deep copy: a new map holding a copy of each key and value,
    ## made with `copy`. This is how `copy(value)` copies a Map (the
    ## `Copyable<Map<K, V>>` implementation); call `copy(map)` rather than
    ## this method. O(count log count) plus the cost of copying the entries.
    ##
    ## @returns the copy
    copy(): Map<K, V> {
        var made = Map<K, V>();
        register_copy<Map<K, V>>(this, made);
        var node = _tree._first();
        while (node != 0) {
            made.insert(copy<K>(_tree._keys[node]), copy<V>(_tree._values[node]));
            node = _tree._successor(node);
        }
        return made;
    }
}

## An iterator over the entries of a `Map` as `(key, value)` tuples, in key
## order or reversed; returned by `Map.iterate()`, `reversed()` and
## `range(from, to)`, and driven by `for (var (key, value) in ...)`.
##
## Holds a reference to the map. It is fail-fast: adding or removing an
## entry after the iterator was created makes its next `next()` or
## `current()` panic.
##
## @typeParam K the key type of the map
## @typeParam V the value type of the map
## @see Map.iterate
[Value]
export struct SortedMapIterator<K, V> {
    ## The map being iterated.
    Map<K, V> _source;
    ## The current node; before the first `next()`, the first node to visit.
    ulong _node;
    ## The node to stop at (not visited), 0 for the end of the map.
    ulong _stop;
    ## The map's version when iteration began.
    ulong _version;
    ## Whether the iteration runs in descending key order.
    bool _reverse;
    ## Whether `next()` has been called.
    bool _started;

    ## Creates an iterator over `source` from node `start` up to node `stop`.
    ## Internal: call `Map.iterate`, `reversed` or `range` instead.
    ##
    ## @param source the map to iterate
    ## @param start the first node to visit
    ## @param stop the node to stop before, 0 for the end
    ## @param reverse whether to step in descending key order
    construct(source: Map<K, V>, start: ulong, stop: ulong, reverse: bool) {
        _source = source;
        _node = start;
        _stop = stop;
        _reverse = reverse;
        _version = source._tree._version;
    }

    ## Advances to the next entry.
    ##
    ## @returns true when there is a current entry, false once every entry was visited
    ## @panics if an entry was added or removed since the iterator was created ("Map modified during iteration")
    next(): bool {
        return next(__caller_location());
    }

    ## `next()` for a `for` loop, which passes its own location so that
    ## the panic names the loop.
    ##
    ## @param location the loop's location, which a panic reports
    ## @returns true when there is a current entry, false once every entry was visited
    ## @panics if an entry was added or removed since the iterator was created ("Map modified during iteration")
    next(location: __ptr<char>): bool {
        assert(_source._tree._version == _version, "Map modified during iteration", location);
        if (!_started) {
            _started = true;
        } else if (_node != _stop) {
            _node = _source._tree._step(_node, _reverse);
        }
        return _node != _stop;
    }

    ## Returns the entry the last successful `next()` moved to.
    ##
    ## @returns the current entry as a `(key, value)` tuple
    ## @panics if an entry was added or removed since the iterator was created ("Map modified during iteration")
    ## @panics if `next()` was never called or already returned false ("SortedMapIterator.current() without an entry")
    current(): (K, V) {
        assert(_source._tree._version == _version, "Map modified during iteration");
        assert(_started and _node != _stop, "SortedMapIterator.current() without an entry");
        return (_source._tree._keys[_node], _source._tree._values[_node]);
    }
}

# ── Set<K> ──────────────────────────────────────────────────────────────────

## A set of distinct elements of type `K` kept in sorted order, on the same
## red-black tree as `Map` but without values.
##
## Elements are ordered by `compare<K>` (see `Map`); two elements that
## compare equal are the same member. Membership tests, inserts and removals
## take O(log count) time. `iterate()` visits the members in ascending
## order, `reversed()` in descending order, and `range(from, to)` the
## members from `from` up to (not including) `to`.
##
## The set holds one reference to each member, acquired on insert and
## released on remove, on `clear`, or when the set is destroyed.
##
## @typeParam K the element type; ordered by `compare<K>`
## @example
##     Set<int> primes = [7, 2, 5, 3];
##     for (var p in primes) {
##         print($"{p}");   # 2, 3, 5, 7
##     }
export struct Set<K> {
    ## The tree holding the members. Internal.
    _RedBlackTree<K, _NoValue> _tree;

    ## Creates an empty set.
    construct() {
        _tree._init();
    }

    ## Creates a set holding each element of `items` once.
    ##
    ## The constructor is `[Implicit]`: an array converts to a set wherever
    ## a set is expected, so an array literal can initialize one.
    ##
    ## @param items the elements to insert; duplicates are kept once
    ## @example
    ##     Set<String> keywords = ["while", "if", "else"];
    ##     assert(keywords.first().value() == "else", "sorted");
    [Implicit]
    construct(items: Array<K>) {
        _tree._init();
        for (var item in items) {
            insert(item);
        }
    }

    ## The number of members. O(1).
    var count: int {
        get {
            return _tree._size;
        }
    }

    ## Whether the set has no members. O(1).
    var is_empty: bool {
        get {
            return _tree._size == 0;
        }
    }

    ## Removes every member and releases the set's references to them.
    ## O(count).
    clear() {
        _tree._clear();
    }

    ## Returns whether `key` is a member. O(log count).
    ##
    ## @param key the element to look up
    ## @returns true when `key` is a member
    contains(key: K): bool {
        return _tree._find(key) != 0;
    }

    ## Adds `key` to the set if it is not already a member. When an equal
    ## member exists, the set keeps the member it has. O(log count).
    ##
    ## @param key the element to add
    ## @returns true when `key` was added, false when it was already a member
    insert(key: K): bool {
        return _tree._insert(key, __default<_NoValue>());
    }

    ## Removes `key` from the set, releasing the set's reference to the
    ## member. Does nothing when `key` is not a member. O(log count).
    ##
    ## @param key the element to remove
    ## @returns true when `key` was a member and was removed, false otherwise
    remove(key: K): bool {
        return _tree._remove(key);
    }

    # The member at `node`, or none for the sentinel.
    _member(node: ulong): K? {
        if (node == 0) {
            return Optional<K>.Empty;
        }
        return Optional<K>.Value(_tree._keys[node]);
    }

    ## Returns the smallest member. O(log count).
    ##
    ## @returns the smallest member, or none when the set is empty
    first(): K? {
        return _member(_tree._first());
    }

    ## Returns the largest member. O(log count).
    ##
    ## @returns the largest member, or none when the set is empty
    last(): K? {
        return _member(_tree._last());
    }

    ## Returns the smallest member that is not less than `key`. O(log count).
    ##
    ## @param key the element to search from
    ## @returns the first member `>= key`, or none when every member is less
    lower_bound(key: K): K? {
        return _member(_tree._bound(key, false));
    }

    ## Returns the smallest member greater than `key`. O(log count).
    ##
    ## @param key the element to search from
    ## @returns the first member `> key`, or none when no member is greater
    upper_bound(key: K): K? {
        return _member(_tree._bound(key, true));
    }

    ## Returns an iterator over the members in ascending order;
    ## `for (var x in set)` drives it.
    ##
    ## The iterator holds a reference to the set. Adding or removing a member
    ## while iterating makes the iterator's next `next()` or `current()`
    ## panic.
    ##
    ## @returns an iterator positioned before the smallest member
    iterate(): SortedSetIterator<K> {
        return SortedSetIterator<K>(this, _tree._first(), 0, false);
    }

    ## Returns an iterator over the members in descending order, under the
    ## same rules as `iterate`.
    ##
    ## @returns an iterator positioned before the largest member
    reversed(): SortedSetIterator<K> {
        return SortedSetIterator<K>(this, _tree._last(), 0, true);
    }

    ## Returns an iterator over the members that are at least `from` and
    ## less than `to`, in ascending order, under the same rules as `iterate`.
    ## It is empty when `from` is not less than `to`.
    ##
    ## @param from the smallest member to visit
    ## @param to the element to stop before
    ## @returns an iterator positioned before the first member in the range
    range(from: K, to: K): SortedSetIterator<K> {
        var start = _tree._range_start(from, to);
        var stop = start == 0 ? 0 : _tree._bound(to, false);
        return SortedSetIterator<K>(this, start, stop, false);
    }

    ## Returns a deep copy: a new set holding a copy of each member, made
    ## with `copy`. This is how `copy(value)` copies a Set (the
    ## `Copyable<Set<K>>` implementation); call `copy(set)` rather than this
    ## method.
    ##
    ## @returns the copy
    copy(): Set<K> {
        var made = Set<K>();
        register_copy<Set<K>>(this, made);
        var node = _tree._first();
        while (node != 0) {
            made.insert(copy<K>(_tree._keys[node]));
            node = _tree._successor(node);
        }
        return made;
    }
}

## An `Iterator<K>` over the members of a `Set`, in order or reversed;
## returned by `Set.iterate()`, `reversed()` and `range(from, to)`, and
## driven by `for (var x in ...)`.
##
## Holds a reference to the set. It is fail-fast: adding or removing a member
## after the iterator was created makes its next `next()` or `current()`
## panic.
##
## @typeParam K the element type of the set
## @see Set.iterate
[Value]
export struct SortedSetIterator<K> {
    ## The set being iterated.
    Set<K> _source;
    ## The current node; before the first `next()`, the first node to visit.
    ulong _node;
    ## The node to stop at (not visited), 0 for the end of the set.
    ulong _stop;
    ## The set's version when iteration began.
    ulong _version;
    ## Whether the iteration runs in descending order.
    bool _reverse;
    ## Whether `next()` has been called.
    bool _started;

    ## Creates an iterator over `source` from node `start` up to node `stop`.
    ## Internal: call `Set.iterate`, `reversed` or `range` instead.
    ##
    ## @param source the set to iterate
    ## @param start the first node to visit
    ## @param stop the node to stop before, 0 for the end
    ## @param reverse whether to step in descending order
    construct(source: Set<K>, start: ulong, stop: ulong, reverse: bool) {
        _source = source;
        _node = start;
        _stop = stop;
        _reverse = reverse;
        _version = source._tree._version;
    }

    ## Advances to the next member.
    ##
    ## @returns true when there is a current member, false once every member was visited
    ## @panics if a member was added or removed since the iterator was created ("Set modified during iteration")
    next(): bool {
        return next(__caller_location());
    }

    ## `next()` for a `for` loop, which passes its own location so that
    ## the panic names the loop.
    ##
    ## @param location the loop's location, which a panic reports
    ## @returns true when there is a current member, false once every member was visited
    ## @panics if a member was added or removed since the iterator was created ("Set modified during iteration")
    next(location: __ptr<char>): bool {
        assert(_source._tree._version == _version, "Set modified during iteration", location);
        if (!_started) {
            _started = true;
        } else if (_node != _stop) {
            _node = _source._tree._step(_node, _reverse);
        }
        return _node != _stop;
    }

    ## Returns the member the last successful `next()` moved to.
    ##
    ## @returns the current member
    ## @panics if a member was added or removed since the iterator was created ("Set modified during iteration")
    ## @panics if `next()` was never called or already returned false ("SortedSetIterator.current() without a member")
    current(): K {
        assert(_source._tree._version == _version, "Set modified during iteration");
        assert(_started and _node != _stop, "SortedSetIterator.current() without a member");
        return _source._tree._keys[_node];
    }
}

extend SortedSetIterator<K> with Iterator<K>;

extend Map<K, V> with Copyable<Map<K, V>>;

extend Set<K> with Copyable<Set<K>>;
