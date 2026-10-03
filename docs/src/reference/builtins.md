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
