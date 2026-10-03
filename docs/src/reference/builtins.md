<!-- Generated from runtime/builtins.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Compiler built-ins

The types and functions the compiler provides itself: raw pointers, weak
references, atomics, checked arithmetic and the other `__` intrinsics the
runtime is built on. Every program can use them without an import, but
most code should not: the runtime wraps each in a safe API (`Atomic<T>`,
`Weak<T>`, `math.checked_add`, ...).

The compiler provides these itself; this file only declares them, with
`[__BuiltIn]`, for this reference and the editor.

Source: `runtime/builtins.pep`

## __ptr

```pepper
struct __ptr<T>
```

A raw pointer to a `T` in memory the program manages itself, as C's `T*`.
It is how the runtime and C interop reach memory directly; nothing checks
that it is valid.

`p[i]` reads or writes the `i`th element, `p + n` and `p - n` move by `n`
elements (bytes for `__ptr<void>`), and `==` and `!=` compare addresses.
A pointer is true when it is not null (`__null`). `as` converts to and
from `__ptr<void>`; `unsafe_cast` converts to any other pointer or to an
integer. A string literal converts to `__ptr<char>`.

**Type parameters**
- `T` — the type pointed at; `void` for untyped memory

### Methods

#### operator []

```pepper
[](index: ulong): T
```

The element `index` places after the one pointed at, as a place that
can be read or assigned.

**Parameters**
- `index` — how many elements past the pointer

**Returns**
- the element

#### operator +

```pepper
+(n: long): __ptr<T>
```

A pointer `n` elements further on (bytes for `__ptr<void>`).

**Parameters**
- `n` — how many elements to move

**Returns**
- the moved pointer

#### operator -

```pepper
-(n: long): __ptr<T>
```

A pointer `n` elements back (bytes for `__ptr<void>`).

**Parameters**
- `n` — how many elements to move

**Returns**
- the moved pointer

#### operator ==

```pepper
==(other: __ptr<T>): bool
```

Whether both point at the same address.

**Parameters**
- `other` — the pointer to compare with

**Returns**
- whether the addresses are equal

#### operator !=

```pepper
!=(other: __ptr<T>): bool
```

Whether they point at different addresses.

**Parameters**
- `other` — the pointer to compare with

**Returns**
- whether the addresses differ

## __weak

```pepper
struct __weak<T>
```

A weak reference to a struct object, like C++'s `std::weak_ptr<T>`: it
keeps the object's memory but not the object alive. Copies step the weak
count; make one with `__weak_from`, read it with `__weak_upgrade`. Use
`Weak<T>`, which wraps it.

**Type parameters**
- `T` — the struct or trait type pointed at

## __null

```pepper
const __null: __ptr<void>
```

The null pointer or reference: a `__ptr<T>` that points nowhere, or an
empty slot of a struct type.

## sizeof

```pepper
sizeof<T>(): ulong
```

The size of `T` in bytes, as C's `sizeof`; a struct reference is the size
of a pointer. Written `sizeof<T>` or `sizeof<T>()`.

**Type parameters**
- `T` — the type to measure

**Returns**
- its size in bytes

## unsafe_cast

```pepper
unsafe_cast<T, TFrom>(value: TFrom): T
```

Reinterprets `value` as a `T`: a pointer as another pointer or an integer,
an integer as a pointer, or a number as another of the same width. It
never applies to a reference-counted type. Prefer `as`, which checks the
conversion.

**Type parameters**
- `T` — the type to reinterpret as
- `TFrom` — the type of `value`

**Parameters**
- `value` — the value to reinterpret

**Returns**
- the same bits as a `T`

## __caller_location

```pepper
__caller_location(): __ptr<char>
```

The place of the call, as `"file:line:col"`. As a parameter's default
(`location: __ptr<char> = __caller_location()`) it is the place of the
call that left the parameter out, which `assert` and `panic` report.

**Returns**
- the location, a NUL-terminated string that lives as long as the program

## __function_pointer

```pepper
__function_pointer<F>(function: F): __ptr<void>
```

The C-callable address of `function`: a free function, a static method of
the enclosing struct, or `this.m`. It is how a C library is handed a
callback.

**Type parameters**
- `F` — the function's type

**Parameters**
- `function` — the function, by name

**Returns**
- its address

## __weak_from

```pepper
__weak_from<T>(target: T): __weak<T>
```

Makes a weak reference to `target`'s object, stepping its weak count.

**Type parameters**
- `T` — the struct or trait type

**Parameters**
- `target` — the object; null makes a reference that is always expired

**Returns**
- the weak reference

## __weak_upgrade

```pepper
__weak_upgrade<T>(weak: __weak<T>): T
```

A strong reference to the object `weak` points at, or null once it has
been destroyed.

**Type parameters**
- `T` — the struct or trait type

**Parameters**
- `weak` — the weak reference

**Returns**
- a new reference to the object, or null

## __weak_expired

```pepper
__weak_expired<T>(weak: __weak<T>): bool
```

Whether the object `weak` points at has been destroyed (or `weak` is
null).

**Type parameters**
- `T` — the struct or trait type

**Parameters**
- `weak` — the weak reference

**Returns**
- whether the object is gone

## __default

```pepper
__default<T>(): T
```

The zero value of `T`: 0, `false`, null, a value struct with every field
zero, or an enum's default case.

**Type parameters**
- `T` — the type

**Returns**
- its zero value

## __is_pod

```pepper
__is_pod<T>(): bool
```

Whether `T` is plain data, with no reference counts to step (a number,
`bool` or pointer, say). Decided while compiling.

**Type parameters**
- `T` — the type

**Returns**
- whether `T` is plain data

## __refcount

```pepper
__refcount<T>(value: T): uint
```

The reference count of `value`'s object; 0 for plain data or null. For
tests and debugging.

**Type parameters**
- `T` — the type

**Parameters**
- `value` — the value

**Returns**
- its strong count

## __address

```pepper
__address<T>(value: T): ulong
```

A hash of `value`'s identity: an object's address, the fields of an
`[Equatable]` struct, or the bits of plain data.

**Type parameters**
- `T` — the type

**Parameters**
- `value` — the value to hash

**Returns**
- the hash

## __copy

```pepper
__copy<T>(value: T, copies: _Copies): T
```

A deep copy of `value`, made in the copy context `copies` so that an
object reached twice is copied once. `copy(value)` calls it.

**Type parameters**
- `T` — the type

**Parameters**
- `value` — the value to copy
- `copies` — the copy context

**Returns**
- the copy

## __copy_object

```pepper
__copy_object<T>(value: T): T
```

A field-by-field copy of struct object `value`, through its generated
`__copy()`.

**Type parameters**
- `T` — the struct

**Parameters**
- `value` — the object to copy

**Returns**
- the copy

## __census

```pepper
__census<T>(slot: __ptr<T>, waiting: ulong): __ptr<T>
```

Under `PEP_CHECK_SYNC`, checks that a `Mutex<T>`'s value at `slot` is not
reachable from outside the lock; otherwise does nothing.

**Type parameters**
- `T` — the locked type

**Parameters**
- `slot` — where the value is stored
- `waiting` — how many threads are waiting on the lock

**Returns**
- `slot`

## __construct_at

```pepper
__construct_at<T>(slot: T, value: T)
```

Stores `value` into `slot`, a raw element (`p[i]`) known to be empty: it
takes a reference to `value` and does not release what the slot held.

**Type parameters**
- `T` — the element type

**Parameters**
- `slot` — the empty element, written `p[i]`
- `value` — the value to store

## __atomic_load

```pepper
__atomic_load<T>(pointer: __ptr<T>): T
```

Reads `*pointer` atomically, with acquire ordering. A struct value comes
with a new reference.

**Type parameters**
- `T` — a number, `bool`, pointer or struct type

**Parameters**
- `pointer` — where the value is

**Returns**
- the value

## __atomic_store

```pepper
__atomic_store<T>(pointer: __ptr<T>, value: T)
```

Writes `value` to `*pointer` atomically, with release ordering. A struct
value is swapped in, and the old one released.

**Type parameters**
- `T` — a number, `bool`, pointer or struct type

**Parameters**
- `pointer` — where to store
- `value` — the value to store

## __atomic_cmpxchg

```pepper
__atomic_cmpxchg<T>(pointer: __ptr<T>, expected: T, desired: T): bool
```

Replaces `*pointer` with `desired` if it holds `expected`, atomically
(acquire-release).

**Type parameters**
- `T` — a number, `bool`, pointer or struct type

**Parameters**
- `pointer` — where the value is
- `expected` — the value it must hold
- `desired` — the value to store

**Returns**
- whether it was replaced

## __atomic_fetch_add

```pepper
__atomic_fetch_add<T>(pointer: __ptr<T>, value: T): T
```

Adds `value` to `*pointer` atomically.

**Type parameters**
- `T` — an integer type

**Parameters**
- `pointer` — where the value is
- `value` — the amount to add

**Returns**
- the value before the addition

## __atomic_fetch_sub

```pepper
__atomic_fetch_sub<T>(pointer: __ptr<T>, value: T): T
```

Subtracts `value` from `*pointer` atomically.

**Type parameters**
- `T` — an integer type

**Parameters**
- `pointer` — where the value is
- `value` — the amount to subtract

**Returns**
- the value before the subtraction

## __atomic_fetch_and

```pepper
__atomic_fetch_and<T>(pointer: __ptr<T>, value: T): T
```

Sets `*pointer` to its bitwise and with `value`, atomically.

**Type parameters**
- `T` — an integer type

**Parameters**
- `pointer` — where the value is
- `value` — the bits to keep

**Returns**
- the value before the change

## __atomic_fetch_or

```pepper
__atomic_fetch_or<T>(pointer: __ptr<T>, value: T): T
```

Sets `*pointer` to its bitwise or with `value`, atomically.

**Type parameters**
- `T` — an integer type

**Parameters**
- `pointer` — where the value is
- `value` — the bits to set

**Returns**
- the value before the change

## __atomic_fetch_xor

```pepper
__atomic_fetch_xor<T>(pointer: __ptr<T>, value: T): T
```

Sets `*pointer` to its bitwise exclusive or with `value`, atomically.

**Type parameters**
- `T` — an integer type

**Parameters**
- `pointer` — where the value is
- `value` — the bits to flip

**Returns**
- the value before the change

## __wrapping_add

```pepper
__wrapping_add<T>(lhs: T, rhs: T): T
```

`lhs + rhs`, wrapping around on overflow instead of panicking.

**Type parameters**
- `T` — an integer type, taken from `lhs`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the sum, modulo the type's range

## __wrapping_sub

```pepper
__wrapping_sub<T>(lhs: T, rhs: T): T
```

`lhs - rhs`, wrapping around on overflow instead of panicking.

**Type parameters**
- `T` — an integer type, taken from `lhs`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the difference, modulo the type's range

## __wrapping_mul

```pepper
__wrapping_mul<T>(lhs: T, rhs: T): T
```

`lhs * rhs`, wrapping around on overflow instead of panicking.

**Type parameters**
- `T` — an integer type, taken from `lhs`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the product, modulo the type's range

## __add_overflows

```pepper
__add_overflows<T>(lhs: T, rhs: T): bool
```

Whether `lhs + rhs` overflows `lhs`'s type.

**Type parameters**
- `T` — an integer type, taken from `lhs`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- whether the sum overflows

## __sub_overflows

```pepper
__sub_overflows<T>(lhs: T, rhs: T): bool
```

Whether `lhs - rhs` overflows `lhs`'s type.

**Type parameters**
- `T` — an integer type, taken from `lhs`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- whether the difference overflows

## __mul_overflows

```pepper
__mul_overflows<T>(lhs: T, rhs: T): bool
```

Whether `lhs * rhs` overflows `lhs`'s type.

**Type parameters**
- `T` — an integer type, taken from `lhs`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- whether the product overflows

## __simd

```pepper
struct __simd<T, N>
```

A vector of `N` lanes of the number type `T`, as LLVM's `<N x T>`: what
`simd.Vector<T, N>` and `simd.Mask<N>` (with `bool` lanes) hold. The
`__simd_` functions below compute on it, each lane at once. It is a value,
with no references inside.

**Type parameters**
- `T` — the lane type: an integer, floating-point or `bool` type
- `N` — the lane count, written as a number (`__simd<byte, 16>`)

## __simd_splat

```pepper
__simd_splat<V>(value: T): V
```

A vector `V` with every lane `value`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `value` — the value of every lane

**Returns**
- the vector

## __simd_add

```pepper
__simd_add<V>(lhs: V, rhs: V): V
```

Adds lane-wise; integer lanes wrap around.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_subtract

```pepper
__simd_subtract<V>(lhs: V, rhs: V): V
```

Subtracts lane-wise; integer lanes wrap around.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_multiply

```pepper
__simd_multiply<V>(lhs: V, rhs: V): V
```

Multiplies lane-wise; integer lanes wrap around.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_divide

```pepper
__simd_divide<V>(lhs: V, rhs: V): V
```

Divides lane-wise. An integer lane of `rhs` that is 0, or a signed `MIN /
-1`, is undefined: `simd.Vector` checks first.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_remainder

```pepper
__simd_remainder<V>(lhs: V, rhs: V): V
```

The lane-wise remainder, with the same undefined cases as `__simd_divide`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_and

```pepper
__simd_and<V>(lhs: V, rhs: V): V
```

The lane-wise bitwise and (integer or `bool` lanes).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_or

```pepper
__simd_or<V>(lhs: V, rhs: V): V
```

The lane-wise bitwise or (integer or `bool` lanes).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_xor

```pepper
__simd_xor<V>(lhs: V, rhs: V): V
```

The lane-wise bitwise exclusive or (integer or `bool` lanes).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_shift_left

```pepper
__simd_shift_left<V>(vector: V, count: int): V
```

Shifts every integer lane left. A count of at least the lane width is
undefined: `simd.Vector` checks first.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the lanes to shift
- `count` — the bits to shift by, less than the lane width

**Returns**
- the shifted lanes

## __simd_shift_right

```pepper
__simd_shift_right<V>(vector: V, count: int): V
```

Shifts every integer lane right: arithmetic for signed lanes, logical for
unsigned. A count of at least the lane width is undefined.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the lanes to shift
- `count` — the bits to shift by, less than the lane width

**Returns**
- the shifted lanes

## __simd_negate

```pepper
__simd_negate<V>(vector: V): V
```

Negates every lane; integer lanes wrap around.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the lane-wise results

## __simd_not

```pepper
__simd_not<V>(vector: V): V
```

Flips every bit of every integer or `bool` lane.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the lane-wise results

## __simd_equal

```pepper
__simd_equal<V>(lhs: V, rhs: V): __simd<bool, N>
```

Compares lane-wise for equality (ordered for floats).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- a `bool` vector of the results

## __simd_not_equal

```pepper
__simd_not_equal<V>(lhs: V, rhs: V): __simd<bool, N>
```

Compares lane-wise for inequality (true for a NaN lane).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- a `bool` vector of the results

## __simd_less

```pepper
__simd_less<V>(lhs: V, rhs: V): __simd<bool, N>
```

Compares lane-wise, signed or unsigned by the lane type.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- a `bool` vector of the results

## __simd_less_equal

```pepper
__simd_less_equal<V>(lhs: V, rhs: V): __simd<bool, N>
```

Compares lane-wise, signed or unsigned by the lane type.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- a `bool` vector of the results

## __simd_greater

```pepper
__simd_greater<V>(lhs: V, rhs: V): __simd<bool, N>
```

Compares lane-wise, signed or unsigned by the lane type.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- a `bool` vector of the results

## __simd_greater_equal

```pepper
__simd_greater_equal<V>(lhs: V, rhs: V): __simd<bool, N>
```

Compares lane-wise, signed or unsigned by the lane type.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- a `bool` vector of the results

## __simd_select

```pepper
__simd_select<V>(mask: __simd<bool, N>, if_true: V, if_false: V): V
```

Picks each lane from `if_true` or `if_false` by `mask`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `mask` — which lanes to take from `if_true`
- `if_true` — the lanes where `mask` is true
- `if_false` — the lanes where `mask` is false

**Returns**
- the selected lanes

## __simd_minimum

```pepper
__simd_minimum<V>(lhs: V, rhs: V): V
```

The lane-wise minimum (`llvm.minnum` for floats: a NaN lane gives the
other).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_maximum

```pepper
__simd_maximum<V>(lhs: V, rhs: V): V
```

The lane-wise maximum (`llvm.maxnum` for floats).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the first operand
- `rhs` — the second operand

**Returns**
- the lane-wise results

## __simd_abs

```pepper
__simd_abs<V>(vector: V): V
```

The lane-wise absolute value; the lowest signed value stays itself.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the lane-wise results

## __simd_rotate_left

```pepper
__simd_rotate_left<V>(vector: V, count: int): V
```

Rotates every integer lane left (`llvm.fshl`).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the lanes to rotate
- `count` — the bits to rotate by, modulo the lane width

**Returns**
- the rotated lanes

## __simd_rotate_right

```pepper
__simd_rotate_right<V>(vector: V, count: int): V
```

Rotates every integer lane right (`llvm.fshr`).

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the lanes to rotate
- `count` — the bits to rotate by, modulo the lane width

**Returns**
- the rotated lanes

## __simd_square_root

```pepper
__simd_square_root<V>(vector: V): V
```

The square root of every float lane.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the lane-wise results

## __simd_floor

```pepper
__simd_floor<V>(vector: V): V
```

Every float lane rounded down.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the lane-wise results

## __simd_ceiling

```pepper
__simd_ceiling<V>(vector: V): V
```

Every float lane rounded up.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the lane-wise results

## __simd_sum

```pepper
__simd_sum<V>(vector: V): T
```

The sum of the lanes: wrapping for integers, in lane order for floats.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the sum

## __simd_reduce_minimum

```pepper
__simd_reduce_minimum<V>(vector: V): T
```

The smallest lane.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the minimum

## __simd_reduce_maximum

```pepper
__simd_reduce_maximum<V>(vector: V): T
```

The largest lane.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the maximum

## __simd_any

```pepper
__simd_any<V>(mask: V): bool
```

Whether any lane of a `bool` vector is true.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `mask` — a `bool` vector

**Returns**
- whether a lane is true

## __simd_all

```pepper
__simd_all<V>(mask: V): bool
```

Whether every lane of a `bool` vector is true.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `mask` — a `bool` vector

**Returns**
- whether every lane is true

## __simd_to_bits

```pepper
__simd_to_bits<V>(mask: V): ulong
```

Packs a `bool` vector into bits: bit `i` is lane `i`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `mask` — a `bool` vector of at most 64 lanes

**Returns**
- the lanes as bits

## __simd_extract

```pepper
__simd_extract<V>(vector: V, index: ulong): T
```

Reads one lane. An index of at least `N` gives an undefined value:
`simd.Vector` checks first.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the vector
- `index` — the lane, less than `N`

**Returns**
- the lane's value

## __simd_insert

```pepper
__simd_insert<V>(vector: V, index: ulong, value: T): V
```

Replaces one lane. An index of at least `N` is undefined: `simd.Vector`
checks first.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the vector
- `index` — the lane, less than `N`
- `value` — the lane's new value

**Returns**
- the vector with the lane replaced

## __simd_shuffle

```pepper
__simd_shuffle<V>(vector: V, indices: __simd<int, N>): V
```

Picks lanes by index, each taken modulo `N`. Constant indices fold to one
`shufflevector`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the lanes to pick from
- `indices` — the lane to pick for each lane, modulo `N`

**Returns**
- the picked lanes

## __simd_reverse

```pepper
__simd_reverse<V>(vector: V): V
```

The lanes in reverse order.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `vector` — the operand

**Returns**
- the lane-wise results

## __simd_interleave_low

```pepper
__simd_interleave_low<V>(lhs: V, rhs: V): V
```

Interleaves the low halves: `lhs[0], rhs[0], lhs[1], ...`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the even lanes' source
- `rhs` — the odd lanes' source

**Returns**
- the interleaved lanes

## __simd_interleave_high

```pepper
__simd_interleave_high<V>(lhs: V, rhs: V): V
```

Interleaves the high halves: `lhs[N / 2], rhs[N / 2], ...`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `lhs` — the even lanes' source
- `rhs` — the odd lanes' source

**Returns**
- the interleaved lanes

## __simd_load

```pepper
__simd_load<V>(pointer: __ptr<T>): V
```

Reads `N` values from memory aligned to `T`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `pointer` — the first of `N` values

**Returns**
- the values

## __simd_load_aligned

```pepper
__simd_load_aligned<V>(pointer: __ptr<T>): V
```

Reads `N` values from memory aligned to the vector's size.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `pointer` — the first of `N` values, aligned to the vector's size

**Returns**
- the values

## __simd_store

```pepper
__simd_store<V>(pointer: __ptr<T>, vector: V)
```

Writes the lanes to memory aligned to `T`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `pointer` — the first of `N` values
- `vector` — the lanes to write

## __simd_store_aligned

```pepper
__simd_store_aligned<V>(pointer: __ptr<T>, vector: V)
```

Writes the lanes to memory aligned to the vector's size.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Parameters**
- `pointer` — the first of `N` values, aligned to the vector's size
- `vector` — the lanes to write

## __simd_convert

```pepper
__simd_convert<R>(vector: __simd<U, N>): R
```

Converts every lane to `R`'s lane type, as `as` does; float to integer
saturates (`llvm.fptosi.sat`), and NaN gives 0.

**Type parameters**
- `R` — the vector type, `__simd<T, N>` of the result

**Parameters**
- `vector` — the lanes to convert

**Returns**
- the converted lanes

## __simd_reinterpret

```pepper
__simd_reinterpret<R>(vector: __simd<U, M>): R
```

Reads a vector's bits as another vector type of the same size.

**Type parameters**
- `R` — the vector type, `__simd<T, N>` of the result

**Parameters**
- `vector` — the vector, the same size as `R`

**Returns**
- the same bits as `R`

## __simd_lanes

```pepper
__simd_lanes<V>(): int
```

The lane count of `V`.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Returns**
- `N`

## __simd_lane_bits

```pepper
__simd_lane_bits<V>(): int
```

The width of `V`'s lane type in bits.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Returns**
- the lane's width in bits

## __simd_is_signed

```pepper
__simd_is_signed<V>(): bool
```

Whether `V`'s lanes are a signed integer type.

**Type parameters**
- `V` — the vector type, `__simd<T, N>`

**Returns**
- whether the lanes are signed integers
