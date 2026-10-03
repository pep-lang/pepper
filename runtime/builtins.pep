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
