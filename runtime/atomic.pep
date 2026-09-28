# std::atomic<T>-equivalent. The storage slot is a malloc'd block of the
# T-sized value (POD) or one pointer (struct T stores its reference there),
# so every operation lowers to an LLVM atomic instruction on that slot:
# load = acquire, store = release (a shared_ptr `operator=` for struct T),
# compare_exchange = cmpxchg, fetch_* = atomicrmw. exchange is a CAS loop
# over compare_exchange.

import "internals";

export struct Atomic<T> {
    __ptr<T> Data;

    new(T value = __default<T>()) {
        # A struct T occupies its reference pointer in the slot; a POD T
        # occupies sizeof(T) bytes of the value itself.
        ulong sz = __is_pod<T>() ? sizeof<T>() : 8;
        this.Data = _pep_malloc(sz);
        __atomic_store<T>(this.Data, value);
    }

    destruct {
        _pep_free(this.Data);
    }

    T load() {
        return __atomic_load<T>(this.Data);
    }

    void store(T v) {
        __atomic_store<T>(this.Data, v);
    }

    # True iff *Data == expected (in which case *Data = desired).
    bool compare_exchange(T expected, T desired) {
        return __atomic_cmpxchg<T>(this.Data, expected, desired);
    }

    # Returns the previous value; atomically replaced by v.
    T exchange(T v) {
        var old = this.load();
        while (true) {
            if (__atomic_cmpxchg<T>(this.Data, old, v)) {
                return old;
            }
            old = this.load();
        }
    }

    # True when the slot's operations are native atomics: every POD T with a
    # slot of 8 bytes or less, and struct T (a pointer swap).
    bool is_lock_free() {
        return __is_pod<T>() ? sizeof<T>() <= 8 : true;
    }

    # Returns the previous value; atomically adds v. Integer T only, like
    # std::atomic<T>::fetch_add — one method per operation (Pepper has no
    # method overloading), each a single native atomicrmw on the slot.
    T fetch_add(T v) {
        return __atomic_fetch_add<T>(this.Data, v);
    }

    T fetch_sub(T v) {
        return __atomic_fetch_sub<T>(this.Data, v);
    }

    T fetch_and(T v) {
        return __atomic_fetch_and<T>(this.Data, v);
    }

    T fetch_or(T v) {
        return __atomic_fetch_or<T>(this.Data, v);
    }

    T fetch_xor(T v) {
        return __atomic_fetch_xor<T>(this.Data, v);
    }
}
