import "internals";

# ── Generic hash ─────────────────────────────────────────────────────────────
# FNV-1a 64-bit. POD types fold the value's own bytes; struct types hash by
# identity (the object's address, folded through FNV so aligned addresses
# spread across buckets), so two equal-valued objects are distinct keys;
# strings hash by content via the concrete override below, so equal strings
# at different addresses collide.
export hash<T>(T value): u64 {
    return __address<T>(value);
}

# Concrete override: `hash<String>` is a distinct function from the generic
# base and wins for String call sites (gather_generics rewrites it to its
# specialization form). Content hashing keeps equal strings in one bucket.
export hash<String>(String value): u64 {
    return _pep_hash_bytes(value.Data, value.Size);
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

export struct HashMap<K, V> {
    Array<K> keys;
    Array<V> values;
    Array<int> state;
    ulong capacity;   # power of two
    int size;
    int tombstones;

    new(ulong initial_capacity = 8) {
        ulong cap = 8;
        while (cap < initial_capacity) {
            cap = cap * 2;
        }
        capacity = cap;
        size = 0;
        tombstones = 0;
        keys = Array<K>(cap);
        values = Array<V>(cap);
        state = Array<int>(cap);
        keys.Size = cap;
        values.Size = cap;
        state.Size = cap;
    }

    # Slot index of key, or -1 when absent. Stops at the first empty slot:
    # a tombstone (1) is skipped so removed keys do not truncate probes.
    long find_slot(K key) {
        ulong mask = capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = state.Data[idx];
            if (st == 2) {
                if (keys.Data[idx] == key) {
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

    # Double the table and reinsert every occupied slot. Reinsertion goes
    # through Array store semantics (acquire), so the outgoing arrays can be
    # dropped from the fields right after: the field store releases them,
    # their Size == capacity makes the destructor visit every slot, and the
    # buffer is freed.
    void grow() {
        ulong new_cap = capacity * 2;
        Array<K> new_keys = Array<K>(new_cap);
        Array<V> new_values = Array<V>(new_cap);
        Array<int> new_state = Array<int>(new_cap);
        new_keys.Size = new_cap;
        new_values.Size = new_cap;
        new_state.Size = new_cap;
        ulong mask = new_cap - 1;
        ulong i = 0;
        while (i < capacity) {
            if (state.Data[i] == 2) {
                K k = keys.Data[i];
                V v = values.Data[i];
                ulong h = hash<K>(k);
                ulong start = h & mask;
                ulong probe = 0;
                int placed = 0;
                while (probe < new_cap && placed == 0) {
                    ulong idx = (start + probe * (probe + 1) / 2) & mask;
                    if (new_state.Data[idx] == 0) {
                        new_keys.Data[idx] = k;
                        new_values.Data[idx] = v;
                        new_state.Data[idx] = 2;
                        placed = 1;
                    }
                    probe = probe + 1;
                }
            }
            i = i + 1;
        }
        keys = new_keys;
        values = new_values;
        state = new_state;
        capacity = new_cap;
        tombstones = 0;
    }

    int count() {
        return size;
    }

    bool empty() {
        return size == 0;
    }

    ulong cap() {
        return capacity;
    }

    void clear() {
        ulong i = 0;
        while (i < capacity) {
            if (state.Data[i] == 2) {
                keys.Data[i] = __default<K>();
                values.Data[i] = __default<V>();
            }
            state.Data[i] = 0;
            i = i + 1;
        }
        size = 0;
        tombstones = 0;
    }

    bool contains(K key) {
        return find_slot(key) >= 0;
    }

    # Insert or overwrite. Returns true when a new key was added.
    bool insert(K key, V value) {
        long slot = find_slot(key);
        if (slot >= 0) {
            values.Data[slot] = value;
            return false;
        }
        # Grow when occupied + tombstone slots reach half the table so the
        # probe sequence always covers every slot.
        # grow() reinserts every existing entry into the new table, and this
        # key is not among them (find_slot missed), so it must be placed by
        # the main path below — exactly once. Returning here would lose it;
        # falling through to a second find + insert would double-acquire.
        if ((size + tombstones) * 2 + 1 >= capacity) {
            grow();
        }
        ulong mask = capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = state.Data[idx];
            if (st == 0 || st == 1) {
                keys.Data[idx] = key;
                values.Data[idx] = value;
                state.Data[idx] = 2;
                # Claiming a tombstone slot empties it again.
                if (st == 1) {
                    tombstones = tombstones - 1;
                }
                size = size + 1;
                return true;
            }
            i = i + 1;
        }
        # Unreachable: the triangular probe visits every slot, and the grow
        # threshold keeps at least one empty slot free.
        return false;
    }

    # Value for key, or the type's default when absent.
    V get(K key) {
        long slot = find_slot(key);
        if (slot >= 0) {
            return values.Data[slot];
        }
        return __default<V>();
    }

    # Remove key. Returns true when found and removed. The slot becomes a
    # tombstone: occupied for probe purposes, empty for lookup.
    bool remove(K key) {
        long slot = find_slot(key);
        if (slot < 0) {
            return false;
        }
        keys.Data[slot] = __default<K>();
        values.Data[slot] = __default<V>();
        state.Data[slot] = 1;
        size = size - 1;
        tombstones = tombstones + 1;
        return true;
    }

    # Indexer: read (default when absent).
    V [](K key) {
        return get(key);
    }

    # Indexer: write (insert or overwrite).
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

export struct HashSet<K> {
    Array<K> keys;
    Array<int> state;
    ulong capacity;   # power of two
    int size;
    int tombstones;

    new(ulong initial_capacity = 8) {
        ulong cap = 8;
        while (cap < initial_capacity) {
            cap = cap * 2;
        }
        capacity = cap;
        size = 0;
        tombstones = 0;
        keys = Array<K>(cap);
        state = Array<int>(cap);
        keys.Size = cap;
        state.Size = cap;
    }

    long find_slot(K key) {
        ulong mask = capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = state.Data[idx];
            if (st == 2) {
                if (keys.Data[idx] == key) {
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

    # Double the table and reinsert every occupied slot; dropping the old
    # arrays from the fields releases them (field stores transfer ownership),
    # and their Size == capacity makes the destructor visit every slot.
    void grow() {
        ulong new_cap = capacity * 2;
        Array<K> new_keys = Array<K>(new_cap);
        Array<int> new_state = Array<int>(new_cap);
        new_keys.Size = new_cap;
        new_state.Size = new_cap;
        ulong mask = new_cap - 1;
        ulong i = 0;
        while (i < capacity) {
            if (state.Data[i] == 2) {
                K k = keys.Data[i];
                ulong h = hash<K>(k);
                ulong start = h & mask;
                ulong probe = 0;
                int placed = 0;
                while (probe < new_cap && placed == 0) {
                    ulong idx = (start + probe * (probe + 1) / 2) & mask;
                    if (new_state.Data[idx] == 0) {
                        new_keys.Data[idx] = k;
                        new_state.Data[idx] = 2;
                        placed = 1;
                    }
                    probe = probe + 1;
                }
            }
            i = i + 1;
        }
        keys = new_keys;
        state = new_state;
        capacity = new_cap;
        tombstones = 0;
    }

    int count() {
        return size;
    }

    bool empty() {
        return size == 0;
    }

    ulong cap() {
        return capacity;
    }

    void clear() {
        ulong i = 0;
        while (i < capacity) {
            if (state.Data[i] == 2) {
                keys.Data[i] = __default<K>();
            }
            state.Data[i] = 0;
            i = i + 1;
        }
        size = 0;
        tombstones = 0;
    }

    bool contains(K key) {
        return find_slot(key) >= 0;
    }

    # Insert. Returns true when a new element was added.
    bool insert(K key) {
        long slot = find_slot(key);
        if (slot >= 0) {
            return false;
        }
        # Grow when occupied + tombstone slots reach half the table so the
        # probe sequence always covers every slot.
        # grow() reinserts every existing entry into the new table, and this
        # key is not among them (find_slot missed), so it must be placed by
        # the main path below — exactly once. Returning here would lose it;
        # falling through to a second find + insert would double-acquire.
        if ((size + tombstones) * 2 + 1 >= capacity) {
            grow();
        }
        ulong mask = capacity - 1;
        ulong h = hash<K>(key);
        ulong start = h & mask;
        ulong i = 0;
        while (i < capacity) {
            ulong idx = (start + i * (i + 1) / 2) & mask;
            int st = state.Data[idx];
            if (st == 0 || st == 1) {
                keys.Data[idx] = key;
                state.Data[idx] = 2;
                # Claiming a tombstone slot empties it again.
                if (st == 1) {
                    tombstones = tombstones - 1;
                }
                size = size + 1;
                return true;
            }
            i = i + 1;
        }
        # Unreachable: the triangular probe visits every slot, and the grow
        # threshold keeps at least one empty slot free.
        return false;
    }

    bool remove(K key) {
        long slot = find_slot(key);
        if (slot < 0) {
            return false;
        }
        keys.Data[slot] = __default<K>();
        state.Data[slot] = 1;
        size = size - 1;
        tombstones = tombstones + 1;
        return true;
    }

    K [](K key) {
        long slot = find_slot(key);
        if (slot >= 0) {
            return keys.Data[slot];
        }
        return __default<K>();
    }

    # Write indexer: a set stores only keys, so `s[k] = v` is "ensure k is a
    # member" — the value argument is intentionally ignored, and the
    # expression yields the member key.
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
