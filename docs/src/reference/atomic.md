<!-- Generated from runtime/atomic.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Atomic

Source: `runtime/atomic.pep`

## Atomic

```pepper
[Shared] struct Atomic<T>
```

A value of type `T` that threads can read and update without data races,
like C++ `std::atomic<T>`.

`T` may be a numeric type, a pointer, or a struct type. For a struct `T`
the Atomic holds a counted reference and every operation follows
`std::shared_ptr` rules: `store` and a successful `compare_exchange` acquire
the new reference and release the one they replace, and `load` hands the
caller its own reference. Memory ordering: `load` is an acquire,
`store` a release, and `compare_exchange` and the `fetch_*` operations are
acquire-release.

`Atomic` is a `[Shared]` struct, so copies of it share one slot and may
be used from several threads at once: pass the Atomic around (or keep it
in a `const` global) to share the value between threads. A struct `T` must be
thread-safe (itself `[Shared]`); `Atomic<String>` is a compile error.

**Type parameters**
- `T` — the type of the stored value

**Example**
```pepper
    main(): int {
        var counter = Atomic<long>(0);
        var before = counter.fetch_add(5);   # before == 0
        if (counter.load() != 5) { return 1; }
        return 0;
    }
```

### Fields

#### Data

```pepper
const Data: __ptr<T>
```

The heap slot the value lives in: `sizeof<T>()` bytes for a POD `T`,
or one reference pointer for a struct `T`. Allocated by the
constructor and never null afterwards. Internal storage; access it only
through the methods, which keep every access atomic.

### Constructor

#### Atomic()

```pepper
construct(T value = __default<T>())
```

Creates an Atomic holding `value`.

For a struct `T` the Atomic acquires a reference to `value`.

**Parameters**
- `value` — the initial value; defaults to zero for a POD `T` and null for a struct `T`

**Example**
```pepper
    var a = Atomic<int>(41);
    var p = Atomic<Point>();   # holds null until a store
```

### Methods

#### load

```pepper
T load()
```

Atomically reads the current value, with acquire ordering.

For a struct `T` the returned reference is acquired for the caller, so
it stays valid even if another thread stores a new value afterwards.

**Returns**
- the value currently stored

#### store

```pepper
void store(T v)
```

Atomically replaces the stored value with `v`, with release ordering.

For a struct `T` this is a `shared_ptr` assignment: the slot acquires
`v` and releases its previous occupant, and the swap is a single atomic
exchange, so concurrent stores never leak or double-release.

**Parameters**
- `v` — the new value

#### compare_exchange

```pepper
bool compare_exchange(T expected, T desired)
```

Atomically replaces the stored value with `desired` if and only if it
currently equals `expected` (a compare-and-swap).

Equality is bitwise: a struct `T` compares references (the same object,
not equal contents), and a floating-point `T` compares bit patterns, so
`0.0` and `-0.0` differ. Unlike C++ `compare_exchange_strong`,
`expected` is not updated on failure; call `load()` to retry. On success
a struct slot acquires `desired` and releases the old occupant; on
failure no reference count changes.

**Parameters**
- `expected` — the value the slot must hold for the exchange to happen
- `desired` — the value to store when it does

**Returns**
- true if the slot held `expected` and now holds `desired`, false if it was left unchanged

**Example**
```pepper
    var cur = counter.load();
    while (!counter.compare_exchange(cur, cur + 1)) {
        cur = counter.load();
    }
```

#### exchange

```pepper
T exchange(T v)
```

Atomically replaces the stored value with `v` and returns the value it
replaced.

Implemented as a `compare_exchange` retry loop, so under heavy
contention it may retry several times. For a struct `T` the slot
acquires `v`, and the caller owns the returned reference.

**Parameters**
- `v` — the new value

**Returns**
- the value stored immediately before the exchange

**Example**
```pepper
    var e = Atomic<int>(1);
    var old = e.exchange(2);   # old == 1, e.load() == 2
```

#### is_lock_free

```pepper
bool is_lock_free()
```

Reports whether this Atomic's slot fits a native atomic instruction,
so its operations never need a lock or an atomic library call.

True for every POD `T` of 8 bytes or less and for every struct `T`
(whose slot is one pointer). The answer depends only on `T`, never on
the stored value.

**Returns**
- true when the operations are lock-free

#### fetch_add

```pepper
T fetch_add(T v)
```

Atomically adds `v` to the stored value and returns the value before
the addition, like `std::atomic<T>::fetch_add`.

Integer `T` only. Overflow wraps around. For a non-integer `T` (a
floating-point or struct type) the call compiles but aborts the
program when it runs.

**Parameters**
- `v` — the amount to add

**Returns**
- the value stored immediately before the addition

**Example**
```pepper
    var c = Atomic<long>(10);
    var old = c.fetch_add(5);   # old == 10, c.load() == 15
```

#### fetch_sub

```pepper
T fetch_sub(T v)
```

Atomically subtracts `v` from the stored value and returns the value
before the subtraction, like `std::atomic<T>::fetch_sub`.

Integer `T` only. Overflow wraps around. For a non-integer `T` the call
compiles but aborts the program when it runs.

**Parameters**
- `v` — the amount to subtract

**Returns**
- the value stored immediately before the subtraction

#### fetch_and

```pepper
T fetch_and(T v)
```

Atomically replaces the stored value with its bitwise AND with `v` and
returns the value before the operation, like
`std::atomic<T>::fetch_and`.

Integer `T` only. For a non-integer `T` the call compiles but aborts
the program when it runs.

**Parameters**
- `v` — the mask to AND with

**Returns**
- the value stored immediately before the operation

#### fetch_or

```pepper
T fetch_or(T v)
```

Atomically replaces the stored value with its bitwise OR with `v` and
returns the value before the operation, like
`std::atomic<T>::fetch_or`.

Integer `T` only. For a non-integer `T` the call compiles but aborts
the program when it runs.

**Parameters**
- `v` — the bits to OR in

**Returns**
- the value stored immediately before the operation

#### fetch_xor

```pepper
T fetch_xor(T v)
```

Atomically replaces the stored value with its bitwise XOR with `v` and
returns the value before the operation, like
`std::atomic<T>::fetch_xor`.

Integer `T` only. For a non-integer `T` the call compiles but aborts
the program when it runs.

**Parameters**
- `v` — the bits to XOR with

**Returns**
- the value stored immediately before the operation
