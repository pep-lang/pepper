## The types and functions the compiler provides itself: raw pointers, weak
## references, atomics, checked arithmetic and the other `__` intrinsics the
## runtime is built on. Every program can use them without an import, but
## most code should not: the runtime wraps each in a safe API (`Atomic<T>`,
## `Weak<T>`, `math.checked_add`, ...).
##
## The compiler provides these itself; this file only declares them, with
## `[__BuiltIn]`, for this reference and the editor.

## A raw pointer to a `T` in memory the program manages itself, as C's `T*`.
## It is how the runtime and C interop reach memory directly; nothing checks
## that it is valid.
##
## `p[i]` reads or writes the `i`th element, `p + n` and `p - n` move by `n`
## elements (bytes for `__ptr<void>`), and `==` and `!=` compare addresses.
## A pointer is true when it is not null (`__null`). `as` converts to and
## from `__ptr<void>`; `unsafe_cast` converts to any other pointer or to an
## integer. A string literal converts to `__ptr<char>`.
##
## @typeParam T the type pointed at; `void` for untyped memory
[__BuiltIn]
export struct __ptr<T> {
    ## The element `index` places after the one pointed at, as a place that
    ## can be read or assigned.
    ##
    ## @param index how many elements past the pointer
    ## @returns the element
    [](index: ulong): T;

    ## A pointer `n` elements further on (bytes for `__ptr<void>`).
    ##
    ## @param n how many elements to move
    ## @returns the moved pointer
    +(n: long): __ptr<T>;

    ## A pointer `n` elements back (bytes for `__ptr<void>`).
    ##
    ## @param n how many elements to move
    ## @returns the moved pointer
    -(n: long): __ptr<T>;

    ## Whether both point at the same address.
    ##
    ## @param other the pointer to compare with
    ## @returns whether the addresses are equal
    ==(other: __ptr<T>): bool;

    ## Whether they point at different addresses.
    ##
    ## @param other the pointer to compare with
    ## @returns whether the addresses differ
    !=(other: __ptr<T>): bool;
}

## A weak reference to a struct object, like C++'s `std::weak_ptr<T>`: it
## keeps the object's memory but not the object alive. Copies step the weak
## count; make one with `__weak_from`, read it with `__weak_upgrade`. Use
## `Weak<T>`, which wraps it.
##
## @typeParam T the struct or trait type pointed at
[__BuiltIn]
export struct __weak<T> {}

## The null pointer or reference: a `__ptr<T>` that points nowhere, or an
## empty slot of a struct type.
[__BuiltIn("__null")]
export const null_pointer: __ptr<void>;

## The size of `T` in bytes, as C's `sizeof`; a struct reference is the size
## of a pointer. Written `sizeof<T>` or `sizeof<T>()`.
##
## @typeParam T the type to measure
## @returns its size in bytes
[__BuiltIn("sizeof")]
export size_of<T>(): ulong;

## Reinterprets `value` as a `T`: a pointer as another pointer or an integer,
## an integer as a pointer, or a number as another of the same width. It
## never applies to a reference-counted type. Prefer `as`, which checks the
## conversion.
##
## @typeParam T the type to reinterpret as
## @typeParam TFrom the type of `value`
## @param value the value to reinterpret
## @returns the same bits as a `T`
[__BuiltIn]
export unsafe_cast<T, TFrom>(value: TFrom): T;

## The place of the call, as `"file:line:col"`. As a parameter's default
## (`location: __ptr<char> = __caller_location()`) it is the place of the
## call that left the parameter out, which `assert` and `panic` report.
##
## @returns the location, a NUL-terminated string that lives as long as the
##   program
[__BuiltIn]
export __caller_location(): __ptr<char>;

## The C-callable address of `function`: a free function, a static method of
## the enclosing struct, or `this.m`. It is how a C library is handed a
## callback.
##
## @typeParam F the function's type
## @param function the function, by name
## @returns its address
[__BuiltIn]
export __function_pointer<F>(function: F): __ptr<void>;

## Makes a weak reference to `target`'s object, stepping its weak count.
##
## @typeParam T the struct or trait type
## @param target the object; null makes a reference that is always expired
## @returns the weak reference
[__BuiltIn]
export __weak_from<T>(target: T): __weak<T>;

## A strong reference to the object `weak` points at, or null once it has
## been destroyed.
##
## @typeParam T the struct or trait type
## @param weak the weak reference
## @returns a new reference to the object, or null
[__BuiltIn]
export __weak_upgrade<T>(weak: __weak<T>): T;

## Whether the object `weak` points at has been destroyed (or `weak` is
## null).
##
## @typeParam T the struct or trait type
## @param weak the weak reference
## @returns whether the object is gone
[__BuiltIn]
export __weak_expired<T>(weak: __weak<T>): bool;

## The zero value of `T`: 0, `false`, null, a value struct with every field
## zero, or an enum's default case.
##
## @typeParam T the type
## @returns its zero value
[__BuiltIn]
export __default<T>(): T;

## Whether `T` is plain data, with no reference counts to step (a number,
## `bool` or pointer, say). Decided while compiling.
##
## @typeParam T the type
## @returns whether `T` is plain data
[__BuiltIn]
export __is_pod<T>(): bool;

## The reference count of `value`'s object; 0 for plain data or null. For
## tests and debugging.
##
## @typeParam T the type
## @param value the value
## @returns its strong count
[__BuiltIn]
export __refcount<T>(value: T): uint;

## A hash of `value`'s identity: an object's address, the fields of an
## `[Equatable]` struct, or the bits of plain data.
##
## @typeParam T the type
## @param value the value to hash
## @returns the hash
[__BuiltIn]
export __address<T>(value: T): ulong;

## A deep copy of `value`, made in the copy context `copies` so that an
## object reached twice is copied once. `copy(value)` calls it.
##
## @typeParam T the type
## @param value the value to copy
## @param copies the copy context
## @returns the copy
[__BuiltIn]
export __copy<T>(value: T, copies: _Copies): T;

## A field-by-field copy of struct object `value`, through its generated
## `__copy()`.
##
## @typeParam T the struct
## @param value the object to copy
## @returns the copy
[__BuiltIn]
export __copy_object<T>(value: T): T;

## Under `PEP_CHECK_SYNC`, checks that a `Mutex<T>`'s value at `slot` is not
## reachable from outside the lock; otherwise does nothing.
##
## @typeParam T the locked type
## @param slot where the value is stored
## @param waiting how many threads are waiting on the lock
## @returns `slot`
[__BuiltIn]
export __census<T>(slot: __ptr<T>, waiting: ulong): __ptr<T>;

## Stores `value` into `slot`, a raw element (`p[i]`) known to be empty: it
## takes a reference to `value` and does not release what the slot held.
##
## @typeParam T the element type
## @param slot the empty element, written `p[i]`
## @param value the value to store
[__BuiltIn]
export __construct_at<T>(slot: T, value: T);

## Reads `*pointer` atomically, with acquire ordering. A struct value comes
## with a new reference.
##
## @typeParam T a number, `bool`, pointer or struct type
## @param pointer where the value is
## @returns the value
[__BuiltIn]
export __atomic_load<T>(pointer: __ptr<T>): T;

## Writes `value` to `*pointer` atomically, with release ordering. A struct
## value is swapped in, and the old one released.
##
## @typeParam T a number, `bool`, pointer or struct type
## @param pointer where to store
## @param value the value to store
[__BuiltIn]
export __atomic_store<T>(pointer: __ptr<T>, value: T);

## Replaces `*pointer` with `desired` if it holds `expected`, atomically
## (acquire-release).
##
## @typeParam T a number, `bool`, pointer or struct type
## @param pointer where the value is
## @param expected the value it must hold
## @param desired the value to store
## @returns whether it was replaced
[__BuiltIn]
export __atomic_cmpxchg<T>(pointer: __ptr<T>, expected: T, desired: T): bool;

## Adds `value` to `*pointer` atomically.
##
## @typeParam T an integer type
## @param pointer where the value is
## @param value the amount to add
## @returns the value before the addition
[__BuiltIn]
export __atomic_fetch_add<T>(pointer: __ptr<T>, value: T): T;

## Subtracts `value` from `*pointer` atomically.
##
## @typeParam T an integer type
## @param pointer where the value is
## @param value the amount to subtract
## @returns the value before the subtraction
[__BuiltIn]
export __atomic_fetch_sub<T>(pointer: __ptr<T>, value: T): T;

## Sets `*pointer` to its bitwise and with `value`, atomically.
##
## @typeParam T an integer type
## @param pointer where the value is
## @param value the bits to keep
## @returns the value before the change
[__BuiltIn]
export __atomic_fetch_and<T>(pointer: __ptr<T>, value: T): T;

## Sets `*pointer` to its bitwise or with `value`, atomically.
##
## @typeParam T an integer type
## @param pointer where the value is
## @param value the bits to set
## @returns the value before the change
[__BuiltIn]
export __atomic_fetch_or<T>(pointer: __ptr<T>, value: T): T;

## Sets `*pointer` to its bitwise exclusive or with `value`, atomically.
##
## @typeParam T an integer type
## @param pointer where the value is
## @param value the bits to flip
## @returns the value before the change
[__BuiltIn]
export __atomic_fetch_xor<T>(pointer: __ptr<T>, value: T): T;

## `lhs + rhs`, wrapping around on overflow instead of panicking.
##
## @typeParam T an integer type, taken from `lhs`
## @param lhs the first operand
## @param rhs the second operand
## @returns the sum, modulo the type's range
[__BuiltIn]
export __wrapping_add<T>(lhs: T, rhs: T): T;

## `lhs - rhs`, wrapping around on overflow instead of panicking.
##
## @typeParam T an integer type, taken from `lhs`
## @param lhs the first operand
## @param rhs the second operand
## @returns the difference, modulo the type's range
[__BuiltIn]
export __wrapping_sub<T>(lhs: T, rhs: T): T;

## `lhs * rhs`, wrapping around on overflow instead of panicking.
##
## @typeParam T an integer type, taken from `lhs`
## @param lhs the first operand
## @param rhs the second operand
## @returns the product, modulo the type's range
[__BuiltIn]
export __wrapping_mul<T>(lhs: T, rhs: T): T;

## Whether `lhs + rhs` overflows `lhs`'s type.
##
## @typeParam T an integer type, taken from `lhs`
## @param lhs the first operand
## @param rhs the second operand
## @returns whether the sum overflows
[__BuiltIn]
export __add_overflows<T>(lhs: T, rhs: T): bool;

## Whether `lhs - rhs` overflows `lhs`'s type.
##
## @typeParam T an integer type, taken from `lhs`
## @param lhs the first operand
## @param rhs the second operand
## @returns whether the difference overflows
[__BuiltIn]
export __sub_overflows<T>(lhs: T, rhs: T): bool;

## Whether `lhs * rhs` overflows `lhs`'s type.
##
## @typeParam T an integer type, taken from `lhs`
## @param lhs the first operand
## @param rhs the second operand
## @returns whether the product overflows
[__BuiltIn]
export __mul_overflows<T>(lhs: T, rhs: T): bool;

## A vector of `N` lanes of the number type `T`, as LLVM's `<N x T>`: what
## `simd.Vector<T, N>` and `simd.Mask<N>` (with `bool` lanes) hold. The
## `__simd_` functions below compute on it, each lane at once. It is a value,
## with no references inside.
##
## @typeParam T the lane type: an integer, floating-point or `bool` type
## @typeParam N the lane count, written as a number (`__simd<byte, 16>`)
[__BuiltIn]
export struct __simd<T, N> {}

## A vector `V` with every lane `value`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param value the value of every lane
## @returns the vector
[__BuiltIn]
export __simd_splat<V>(value: T): V;

## Adds lane-wise; integer lanes wrap around.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_add<V>(lhs: V, rhs: V): V;

## Subtracts lane-wise; integer lanes wrap around.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_subtract<V>(lhs: V, rhs: V): V;

## Multiplies lane-wise; integer lanes wrap around.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_multiply<V>(lhs: V, rhs: V): V;

## Divides lane-wise. An integer lane of `rhs` that is 0, or a signed `MIN /
## -1`, is undefined: `simd.Vector` checks first.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_divide<V>(lhs: V, rhs: V): V;

## The lane-wise remainder, with the same undefined cases as `__simd_divide`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_remainder<V>(lhs: V, rhs: V): V;

## The lane-wise bitwise and (integer or `bool` lanes).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_and<V>(lhs: V, rhs: V): V;

## The lane-wise bitwise or (integer or `bool` lanes).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_or<V>(lhs: V, rhs: V): V;

## The lane-wise bitwise exclusive or (integer or `bool` lanes).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_xor<V>(lhs: V, rhs: V): V;

## Shifts every integer lane left. A count of at least the lane width is
## undefined: `simd.Vector` checks first.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the lanes to shift
## @param count the bits to shift by, less than the lane width
## @returns the shifted lanes
[__BuiltIn]
export __simd_shift_left<V>(vector: V, count: int): V;

## Shifts every integer lane right: arithmetic for signed lanes, logical for
## unsigned. A count of at least the lane width is undefined.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the lanes to shift
## @param count the bits to shift by, less than the lane width
## @returns the shifted lanes
[__BuiltIn]
export __simd_shift_right<V>(vector: V, count: int): V;

## Negates every lane; integer lanes wrap around.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_negate<V>(vector: V): V;

## Flips every bit of every integer or `bool` lane.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_not<V>(vector: V): V;

## Compares lane-wise for equality (ordered for floats).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns a `bool` vector of the results
[__BuiltIn]
export __simd_equal<V>(lhs: V, rhs: V): __simd<bool, N>;

## Compares lane-wise for inequality (true for a NaN lane).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns a `bool` vector of the results
[__BuiltIn]
export __simd_not_equal<V>(lhs: V, rhs: V): __simd<bool, N>;

## Compares lane-wise, signed or unsigned by the lane type.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns a `bool` vector of the results
[__BuiltIn]
export __simd_less<V>(lhs: V, rhs: V): __simd<bool, N>;

## Compares lane-wise, signed or unsigned by the lane type.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns a `bool` vector of the results
[__BuiltIn]
export __simd_less_equal<V>(lhs: V, rhs: V): __simd<bool, N>;

## Compares lane-wise, signed or unsigned by the lane type.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns a `bool` vector of the results
[__BuiltIn]
export __simd_greater<V>(lhs: V, rhs: V): __simd<bool, N>;

## Compares lane-wise, signed or unsigned by the lane type.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns a `bool` vector of the results
[__BuiltIn]
export __simd_greater_equal<V>(lhs: V, rhs: V): __simd<bool, N>;

## Picks each lane from `if_true` or `if_false` by `mask`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param mask which lanes to take from `if_true`
## @param if_true the lanes where `mask` is true
## @param if_false the lanes where `mask` is false
## @returns the selected lanes
[__BuiltIn]
export __simd_select<V>(mask: __simd<bool, N>, if_true: V, if_false: V): V;

## The lane-wise minimum (`llvm.minnum` for floats: a NaN lane gives the
## other).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_minimum<V>(lhs: V, rhs: V): V;

## The lane-wise maximum (`llvm.maxnum` for floats).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the first operand
## @param rhs the second operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_maximum<V>(lhs: V, rhs: V): V;

## The lane-wise absolute value; the lowest signed value stays itself.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_abs<V>(vector: V): V;

## Rotates every integer lane left (`llvm.fshl`).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the lanes to rotate
## @param count the bits to rotate by, modulo the lane width
## @returns the rotated lanes
[__BuiltIn]
export __simd_rotate_left<V>(vector: V, count: int): V;

## Rotates every integer lane right (`llvm.fshr`).
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the lanes to rotate
## @param count the bits to rotate by, modulo the lane width
## @returns the rotated lanes
[__BuiltIn]
export __simd_rotate_right<V>(vector: V, count: int): V;

## The square root of every float lane.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_square_root<V>(vector: V): V;

## Every float lane rounded down.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_floor<V>(vector: V): V;

## Every float lane rounded up.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_ceiling<V>(vector: V): V;

## The sum of the lanes: wrapping for integers, in lane order for floats.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the sum
[__BuiltIn]
export __simd_sum<V>(vector: V): T;

## The smallest lane.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the minimum
[__BuiltIn]
export __simd_reduce_minimum<V>(vector: V): T;

## The largest lane.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the maximum
[__BuiltIn]
export __simd_reduce_maximum<V>(vector: V): T;

## Whether any lane of a `bool` vector is true.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param mask a `bool` vector
## @returns whether a lane is true
[__BuiltIn]
export __simd_any<V>(mask: V): bool;

## Whether every lane of a `bool` vector is true.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param mask a `bool` vector
## @returns whether every lane is true
[__BuiltIn]
export __simd_all<V>(mask: V): bool;

## Packs a `bool` vector into bits: bit `i` is lane `i`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param mask a `bool` vector of at most 64 lanes
## @returns the lanes as bits
[__BuiltIn]
export __simd_to_bits<V>(mask: V): ulong;

## Reads one lane. An index of at least `N` gives an undefined value:
## `simd.Vector` checks first.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the vector
## @param index the lane, less than `N`
## @returns the lane's value
[__BuiltIn]
export __simd_extract<V>(vector: V, index: ulong): T;

## Replaces one lane. An index of at least `N` is undefined: `simd.Vector`
## checks first.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the vector
## @param index the lane, less than `N`
## @param value the lane's new value
## @returns the vector with the lane replaced
[__BuiltIn]
export __simd_insert<V>(vector: V, index: ulong, value: T): V;

## Picks lanes by index, each taken modulo `N`. Constant indices fold to one
## `shufflevector`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the lanes to pick from
## @param indices the lane to pick for each lane, modulo `N`
## @returns the picked lanes
[__BuiltIn]
export __simd_shuffle<V>(vector: V, indices: __simd<int, N>): V;

## The lanes in reverse order.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param vector the operand
## @returns the lane-wise results
[__BuiltIn]
export __simd_reverse<V>(vector: V): V;

## Interleaves the low halves: `lhs[0], rhs[0], lhs[1], ...`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the even lanes' source
## @param rhs the odd lanes' source
## @returns the interleaved lanes
[__BuiltIn]
export __simd_interleave_low<V>(lhs: V, rhs: V): V;

## Interleaves the high halves: `lhs[N / 2], rhs[N / 2], ...`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param lhs the even lanes' source
## @param rhs the odd lanes' source
## @returns the interleaved lanes
[__BuiltIn]
export __simd_interleave_high<V>(lhs: V, rhs: V): V;

## Reads `N` values from memory aligned to `T`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param pointer the first of `N` values
## @returns the values
[__BuiltIn]
export __simd_load<V>(pointer: __ptr<T>): V;

## Reads `N` values from memory aligned to the vector's size.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param pointer the first of `N` values, aligned to the vector's size
## @returns the values
[__BuiltIn]
export __simd_load_aligned<V>(pointer: __ptr<T>): V;

## Writes the lanes to memory aligned to `T`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param pointer the first of `N` values
## @param vector the lanes to write
[__BuiltIn]
export __simd_store<V>(pointer: __ptr<T>, vector: V);

## Writes the lanes to memory aligned to the vector's size.
##
## @typeParam V the vector type, `__simd<T, N>`
## @param pointer the first of `N` values, aligned to the vector's size
## @param vector the lanes to write
[__BuiltIn]
export __simd_store_aligned<V>(pointer: __ptr<T>, vector: V);

## Converts every lane to `R`'s lane type, as `as` does; float to integer
## saturates (`llvm.fptosi.sat`), and NaN gives 0.
##
## @typeParam R the vector type, `__simd<T, N>` of the result
## @param vector the lanes to convert
## @returns the converted lanes
[__BuiltIn]
export __simd_convert<R>(vector: __simd<U, N>): R;

## Reads a vector's bits as another vector type of the same size.
##
## @typeParam R the vector type, `__simd<T, N>` of the result
## @param vector the vector, the same size as `R`
## @returns the same bits as `R`
[__BuiltIn]
export __simd_reinterpret<R>(vector: __simd<U, M>): R;

## The lane count of `V`.
##
## @typeParam V the vector type, `__simd<T, N>`
## @returns `N`
[__BuiltIn]
export __simd_lanes<V>(): int;

## The width of `V`'s lane type in bits.
##
## @typeParam V the vector type, `__simd<T, N>`
## @returns the lane's width in bits
[__BuiltIn]
export __simd_lane_bits<V>(): int;

## Whether `V`'s lanes are a signed integer type.
##
## @typeParam V the vector type, `__simd<T, N>`
## @returns whether the lanes are signed integers
[__BuiltIn]
export __simd_is_signed<V>(): bool;
