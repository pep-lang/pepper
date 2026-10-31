# std::atomic<T>-equivalent. The storage slot is a malloc'd block of the
# T-sized value (POD) or one pointer (struct T stores its reference there),
# so every operation lowers to an LLVM atomic instruction on that slot:
# load = acquire, store = release (a shared_ptr `operator=` for struct T),
# compare_exchange = cmpxchg, fetch_* = atomicrmw. exchange is a CAS loop
# over compare_exchange.

## A value of type `T` that threads can read and update without data races,
## like C++ `std::atomic<T>`.
##
## `T` may be a numeric type, a pointer, or a struct type. For a struct `T`
## the Atomic holds a counted reference and every operation follows
## `std::shared_ptr` rules: `store` and a successful `compare_exchange` acquire
## the new reference and release the one they replace, and `load` hands the
## caller its own reference. Memory ordering: `load` is an acquire,
## `store` a release, and `compare_exchange` and the `fetch_*` operations are
## acquire-release.
##
## `Atomic` is a `[Shared]` struct, so copies of it share one slot and may
## be used from several threads at once: pass the Atomic around (or keep it
## in a `const` global) to share the value between threads, so `T` is
## constrained `Shared`: a number, `bool`, an enum, a `[Shared]` struct, or
## another thread-safe type. `async.Atomic<String>` is a compile error at
## `String`.
##
## @typeParam T the type of the stored value, which must be thread-safe
##   (`T: Shared`)
## @example
##     import async;
##
##     main(): int {
##         var counter = async.Atomic<long>(0);
##         var before = counter.fetch_add(5);   # before == 0
##         if (counter.load() != 5) { return 1; }
##         return 0;
##     }
[Shared]
export struct Atomic<T: Shared> {
    ## The heap slot the value lives in: `sizeof<T>()` bytes for a POD `T`,
    ## or one reference pointer for a struct `T`. Allocated by the
    ## constructor and never null afterwards. Internal storage; access it only
    ## through the methods, which keep every access atomic.
    const _data: __ptr<T>;

    ## Creates an Atomic holding `value`.
    ##
    ## For a struct `T` the Atomic acquires a reference to `value`.
    ##
    ## @param value the initial value; defaults to zero for a POD `T` and null for a struct `T`
    ## @example
    ##     var a = async.Atomic<int>(41);
    ##     var p = async.Atomic<Point>();   # holds null until a store
    construct(value: T = __default<T>()) {
        # A struct T occupies its reference pointer in the slot; a POD T
        # occupies sizeof(T) bytes of the value itself.
        ulong sz = __is_pod<T>() ? sizeof<T>() : 8;
        this._data = _pep_malloc(sz);
        __atomic_store<T>(this._data, value);
    }

    destruct {
        # Storing the zero value releases a struct T's reference in the slot.
        __atomic_store<T>(this._data, __default<T>());
        _pep_free(this._data);
    }

    ## Atomically reads the current value, with acquire ordering.
    ##
    ## For a struct `T` the returned reference is acquired for the caller, so
    ## it stays valid even if another thread stores a new value afterwards.
    ##
    ## @returns the value currently stored
    load(): T {
        return __atomic_load<T>(this._data);
    }

    ## Atomically replaces the stored value with `v`, with release ordering.
    ##
    ## For a struct `T` this is a `shared_ptr` assignment: the slot acquires
    ## `v` and releases its previous occupant, and the swap is a single atomic
    ## exchange, so concurrent stores never leak or double-release.
    ##
    ## @param v the new value
    store(v: T) {
        __atomic_store<T>(this._data, v);
    }

    ## Atomically replaces the stored value with `desired` if and only if it
    ## currently equals `expected` (a compare-and-swap).
    ##
    ## Equality is bitwise: a struct `T` compares references (the same object,
    ## not equal contents), and a floating-point `T` compares bit patterns, so
    ## `0.0` and `-0.0` differ. Unlike C++ `compare_exchange_strong`,
    ## `expected` is not updated on failure; call `load()` to retry. On success
    ## a struct slot acquires `desired` and releases the old occupant; on
    ## failure no reference count changes.
    ##
    ## @param expected the value the slot must hold for the exchange to happen
    ## @param desired the value to store when it does
    ## @returns true if the slot held `expected` and now holds `desired`, false if it was left unchanged
    ## @example
    ##     var cur = counter.load();
    ##     while (!counter.compare_exchange(cur, cur + 1)) {
    ##         cur = counter.load();
    ##     }
    compare_exchange(expected: T, desired: T): bool {
        return __atomic_cmpxchg<T>(this._data, expected, desired);
    }

    ## Atomically replaces the stored value with `v` and returns the value it
    ## replaced.
    ##
    ## Implemented as a `compare_exchange` retry loop, so under heavy
    ## contention it may retry several times. For a struct `T` the slot
    ## acquires `v`, and the caller owns the returned reference.
    ##
    ## @param v the new value
    ## @returns the value stored immediately before the exchange
    ## @example
    ##     var e = async.Atomic<int>(1);
    ##     var old = e.exchange(2);   # old == 1, e.load() == 2
    exchange(v: T): T {
        var old = this.load();
        while (true) {
            if (__atomic_cmpxchg<T>(this._data, old, v)) {
                return old;
            }
            old = this.load();
        }
    }

    ## Reports whether this Atomic's slot fits a native atomic instruction,
    ## so its operations never need a lock or an atomic library call.
    ##
    ## True for every POD `T` of 8 bytes or less and for every struct `T`
    ## (whose slot is one pointer). The answer depends only on `T`, never on
    ## the stored value.
    ##
    ## @returns true when the operations are lock-free
    is_lock_free(): bool {
        return __is_pod<T>() ? sizeof<T>() <= 8 : true;
    }

    # One method per operation (Pepper has no method overloading), each a
    # single native atomicrmw on the slot.

    ## Atomically adds `v` to the stored value and returns the value before
    ## the addition, like `std::atomic<T>::fetch_add`.
    ##
    ## Integer `T` only. Overflow wraps around. For a non-integer `T` (a
    ## floating-point or struct type) the call compiles but aborts the
    ## program when it runs.
    ##
    ## @param v the amount to add
    ## @returns the value stored immediately before the addition
    ## @example
    ##     var c = async.Atomic<long>(10);
    ##     var old = c.fetch_add(5);   # old == 10, c.load() == 15
    fetch_add(v: T): T {
        return __atomic_fetch_add<T>(this._data, v);
    }

    ## Atomically subtracts `v` from the stored value and returns the value
    ## before the subtraction, like `std::atomic<T>::fetch_sub`.
    ##
    ## Integer `T` only. Overflow wraps around. For a non-integer `T` the call
    ## compiles but aborts the program when it runs.
    ##
    ## @param v the amount to subtract
    ## @returns the value stored immediately before the subtraction
    fetch_sub(v: T): T {
        return __atomic_fetch_sub<T>(this._data, v);
    }

    ## Atomically replaces the stored value with its bitwise AND with `v` and
    ## returns the value before the operation, like
    ## `std::atomic<T>::fetch_and`.
    ##
    ## Integer `T` only. For a non-integer `T` the call compiles but aborts
    ## the program when it runs.
    ##
    ## @param v the mask to AND with
    ## @returns the value stored immediately before the operation
    fetch_and(v: T): T {
        return __atomic_fetch_and<T>(this._data, v);
    }

    ## Atomically replaces the stored value with its bitwise OR with `v` and
    ## returns the value before the operation, like
    ## `std::atomic<T>::fetch_or`.
    ##
    ## Integer `T` only. For a non-integer `T` the call compiles but aborts
    ## the program when it runs.
    ##
    ## @param v the bits to OR in
    ## @returns the value stored immediately before the operation
    fetch_or(v: T): T {
        return __atomic_fetch_or<T>(this._data, v);
    }

    ## Atomically replaces the stored value with its bitwise XOR with `v` and
    ## returns the value before the operation, like
    ## `std::atomic<T>::fetch_xor`.
    ##
    ## Integer `T` only. For a non-integer `T` the call compiles but aborts
    ## the program when it runs.
    ##
    ## @param v the bits to XOR with
    ## @returns the value stored immediately before the operation
    fetch_xor(v: T): T {
        return __atomic_fetch_xor<T>(this._data, v);
    }
}
