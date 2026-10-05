<!-- Generated from runtime/simd/module.pep by `pep-doc reference`. Do not edit. -->

# The simd module

SIMD vectors: `Vector<T, N>` holds `N` numbers of type `T` and computes
on all of them at once, in the CPU's vector registers.

Bring it in with `import simd`. `T` is an integer or floating-point type
(`byte`, `char`, `short`, `ushort`, `int`, `uint`, `long`, `ulong`,
`float`, `double`) and `N`, the lane count, is a power of two from 1 to
64, written as a number: `simd.Vector<byte, 16>`. A vector is a value
(`[Value]`): it is stored inline, copied like a number, and safe to share
between threads.

The operations compile to the target's vector instructions: SSE2 on
x86-64 (AVX2 with `-march=x86-64-v3`), NEON on arm64, and `simd128` on
WebAssembly with `-msimd128`. A target without vector registers gets the
same results from scalar code. Sixteen bytes (`Vector<byte, 16>`,
`Vector<int, 4>`, `Vector<double, 2>`) is the width every target handles
well; wider vectors use several registers where the target has no wider
ones.

Lane-wise comparisons (`less`, `equal`, ...) give a `Mask<N>`, which
selects lanes (`select`), answers `any` and `all`, and packs into a bit
mask with `to_bits`, whose `trailing_zeros` finds the first match.

**Example**
```pepper
import simd;

main(): int {
    var a = simd.Vector<int, 4>(10);
    var b = a + simd.Vector<int, 4>(5);
    assert(b[0] == 15 && b.sum() == 60, "lane-wise add");
    var over = b.greater(12);
    assert(over.all() && over.to_bits() == 0xF, "a mask per lane");
    return 0;
}
```

Source: `runtime/simd/module.pep`

## Lane

```pepper
trait Lane
```

The number types a `Vector` holds: every integer and floating-point
type. The runtime declares the conformances; another type cannot be a
lane.

## IntegerLane

```pepper
trait IntegerLane
```

The integer lane types, whose vectors have checked division, the bitwise
operators, shifts and rotates.

## FloatLane

```pepper
trait FloatLane
```

The floating-point lane types, whose vectors have floating-point
division, `square_root`, `floor` and `ceiling`.

## Vector

```pepper
[Value] struct Vector<T: Lane, N>
```

`N` lanes of the number type `T`, computed on together.

Integer `+`, `-` and `*` wrap around on overflow in each lane, as vector
instructions do, where scalar arithmetic panics. Integer `/` and `%`
panic on a zero divisor lane; shifts panic on a count outside the lane's
width. Every other operation is defined for every input.

**Type parameters**
- `T` — the lane type: an integer or floating-point type
- `N` — the lane count: a power of two from 1 to 64

### Properties

#### count

```pepper
var count: int { get; }
```

The number of lanes, `N`.

### Constructors

#### Vector()

```pepper
construct()
```

Makes a vector with every lane 0.

#### Vector()

```pepper
construct(value: T)
```

Makes a vector with every lane `value`.

**Parameters**
- `value` — the value of every lane

### Static methods

#### load

```pepper
static load(pointer: __ptr<T>): Vector<T, N>
```

Reads `N` values from `pointer`, which need not be aligned.

**Parameters**
- `pointer` — the first of `N` readable values

**Returns**
- a vector of the values, the first in lane 0

#### load_aligned

```pepper
static load_aligned(pointer: __ptr<T>): Vector<T, N>
```

Reads `N` values from `pointer`, which must be aligned to the
vector's size (`N` times the size of `T`).

**Parameters**
- `pointer` — the first of `N` readable values

**Returns**
- a vector of the values, the first in lane 0

**Panics**
- if `pointer` is not aligned to the vector's size

#### load

```pepper
static load(array: Array<T>, index: ulong): Vector<T, N>
```

Reads the `N` elements of `array` from `index` on.

**Parameters**
- `array` — the array to read
- `index` — the element that goes in lane 0

**Returns**
- a vector of `array[index]` through `array[index + N - 1]`

**Panics**
- if `array` has fewer than `index + N` elements

### Methods

#### store

```pepper
store(pointer: __ptr<T>)
```

Writes the lanes to the `N` values at `pointer`, which need not be
aligned.

**Parameters**
- `pointer` — the first of `N` writable values

#### store_aligned

```pepper
store_aligned(pointer: __ptr<T>)
```

Writes the lanes to the `N` values at `pointer`, which must be
aligned to the vector's size.

**Parameters**
- `pointer` — the first of `N` writable values

**Panics**
- if `pointer` is not aligned to the vector's size

#### store

```pepper
store(array: Array<T>, index: ulong)
```

Writes the lanes to the `N` elements of `array` from `index` on.

**Parameters**
- `array` — the array to write
- `index` — the element lane 0 goes to

**Panics**
- if `array` has fewer than `index + N` elements

#### operator []

```pepper
[](index: ulong): T
```

Returns lane `index`.

**Parameters**
- `index` — the lane to read

**Returns**
- the value in lane `index`

**Panics**
- if `index` is not less than `N`

#### operator []

```pepper
[](index: ulong, value: T): T
```

Sets lane `index` to `value`.

**Parameters**
- `index` — the lane to write
- `value` — the new value of the lane

**Returns**
- `value`

**Panics**
- if `index` is not less than `N`

#### operator +

```pepper
+(other: Vector<T, N>): Vector<T, N>
```

Adds each lane of `other` to the same lane of this vector. Integer
lanes wrap around on overflow.

**Parameters**
- `other` — the vector to add

**Returns**
- the lane-wise sums

#### operator +

```pepper
+(other: T): Vector<T, N>
```

Adds `other` to every lane. Integer lanes wrap around on overflow.

**Parameters**
- `other` — the value to add

**Returns**
- the lane-wise sums

#### operator -

```pepper
-(other: Vector<T, N>): Vector<T, N>
```

Subtracts each lane of `other` from the same lane of this vector.
Integer lanes wrap around on overflow.

**Parameters**
- `other` — the vector to subtract

**Returns**
- the lane-wise differences

#### operator -

```pepper
-(other: T): Vector<T, N>
```

Subtracts `other` from every lane. Integer lanes wrap around on
overflow.

**Parameters**
- `other` — the value to subtract

**Returns**
- the lane-wise differences

#### operator *

```pepper
*(other: Vector<T, N>): Vector<T, N>
```

Multiplies each lane by the same lane of `other`. Integer lanes wrap
around on overflow.

**Parameters**
- `other` — the vector to multiply by

**Returns**
- the lane-wise products

#### operator *

```pepper
*(other: T): Vector<T, N>
```

Multiplies every lane by `other`. Integer lanes wrap around on
overflow.

**Parameters**
- `other` — the value to multiply by

**Returns**
- the lane-wise products

#### operator -

```pepper
-(): Vector<T, N>
```

Negates every lane. Integer lanes wrap around: the lowest value stays
itself.

**Returns**
- the negated lanes

#### operator ==

```pepper
==(other: Vector<T, N>): bool
```

Whether every lane equals the same lane of `other`. A NaN lane equals
nothing. For a mask per lane, use `equal`.

**Parameters**
- `other` — the vector to compare with

**Returns**
- true when all lanes are equal

#### operator !=

```pepper
!=(other: Vector<T, N>): bool
```

Whether some lane differs from the same lane of `other`.

**Parameters**
- `other` — the vector to compare with

**Returns**
- true when any lane differs

#### equal

```pepper
equal(other: Vector<T, N>): Mask<N>
```

Compares each lane with the same lane of `other` for equality.

**Parameters**
- `other` — the vector to compare with

**Returns**
- a mask, true in each lane that is equal

#### equal

```pepper
equal(other: T): Mask<N>
```

Compares every lane with `other` for equality.

**Parameters**
- `other` — the value to compare with

**Returns**
- a mask, true in each lane equal to `other`

#### not_equal

```pepper
not_equal(other: Vector<T, N>): Mask<N>
```

Compares each lane with the same lane of `other` for inequality. A
NaN lane differs from everything.

**Parameters**
- `other` — the vector to compare with

**Returns**
- a mask, true in each lane that differs

#### not_equal

```pepper
not_equal(other: T): Mask<N>
```

Compares every lane with `other` for inequality.

**Parameters**
- `other` — the value to compare with

**Returns**
- a mask, true in each lane that differs from `other`

#### less

```pepper
less(other: Vector<T, N>): Mask<N>
```

Tests whether each lane is less than the same lane of `other`.

**Parameters**
- `other` — the vector to compare with

**Returns**
- a mask, true in each lane that is less

#### less

```pepper
less(other: T): Mask<N>
```

Tests whether every lane is less than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- a mask, true in each lane less than `other`

#### less_equal

```pepper
less_equal(other: Vector<T, N>): Mask<N>
```

Tests whether each lane is less than or equal to the same lane of
`other`.

**Parameters**
- `other` — the vector to compare with

**Returns**
- a mask, true in each lane that is less or equal

#### less_equal

```pepper
less_equal(other: T): Mask<N>
```

Tests whether every lane is less than or equal to `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- a mask, true in each lane less than or equal to `other`

#### greater

```pepper
greater(other: Vector<T, N>): Mask<N>
```

Tests whether each lane is greater than the same lane of `other`.

**Parameters**
- `other` — the vector to compare with

**Returns**
- a mask, true in each lane that is greater

#### greater

```pepper
greater(other: T): Mask<N>
```

Tests whether every lane is greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- a mask, true in each lane greater than `other`

#### greater_equal

```pepper
greater_equal(other: Vector<T, N>): Mask<N>
```

Tests whether each lane is greater than or equal to the same lane of
`other`.

**Parameters**
- `other` — the vector to compare with

**Returns**
- a mask, true in each lane that is greater or equal

#### greater_equal

```pepper
greater_equal(other: T): Mask<N>
```

Tests whether every lane is greater than or equal to `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- a mask, true in each lane greater than or equal to `other`

#### min

```pepper
min(other: Vector<T, N>): Vector<T, N>
```

The smaller of each lane and the same lane of `other`. For floats, a
NaN lane gives the other lane.

**Parameters**
- `other` — the vector to compare with

**Returns**
- the lane-wise minimums

#### max

```pepper
max(other: Vector<T, N>): Vector<T, N>
```

The larger of each lane and the same lane of `other`. For floats, a
NaN lane gives the other lane.

**Parameters**
- `other` — the vector to compare with

**Returns**
- the lane-wise maximums

#### abs

```pepper
abs(): Vector<T, N>
```

The absolute value of every lane. For a signed integer `T` the lowest
value has no positive counterpart and stays itself.

**Returns**
- the lane-wise absolute values

#### sum

```pepper
sum(): T
```

The sum of the lanes. Integer lanes wrap around on overflow; float
lanes are added in lane order.

**Returns**
- the sum of all lanes

#### minimum

```pepper
minimum(): T
```

The smallest lane.

**Returns**
- the minimum over all lanes

#### maximum

```pepper
maximum(): T
```

The largest lane.

**Returns**
- the maximum over all lanes

#### shuffle

```pepper
shuffle(indices: Vector<int, N>): Vector<T, N>
```

Picks lanes by index: lane `i` of the result is lane `indices[i]` of
this vector. Each index is taken modulo `N`, so every index picks a
lane. When the indices are constants, an optimized build compiles this
to one shuffle instruction.

**Parameters**
- `indices` — the lane to pick for each lane of the result

**Returns**
- the picked lanes

#### reverse

```pepper
reverse(): Vector<T, N>
```

The lanes in reverse order.

**Returns**
- a vector whose lane `i` is lane `N - 1 - i` of this one

#### interleave_low

```pepper
interleave_low(other: Vector<T, N>): Vector<T, N>
```

Interleaves the low halves of this vector and `other`: lanes
`this[0], other[0], this[1], other[1], ...`.

**Parameters**
- `other` — the vector whose lanes go in the odd lanes

**Returns**
- the interleaved lanes

#### interleave_high

```pepper
interleave_high(other: Vector<T, N>): Vector<T, N>
```

Interleaves the high halves of this vector and `other`: lanes
`this[N / 2], other[N / 2], this[N / 2 + 1], ...`.

**Parameters**
- `other` — the vector whose lanes go in the odd lanes

**Returns**
- the interleaved lanes

#### convert

```pepper
convert<U: Lane>(): Vector<U, N>
```

Converts every lane to `U`, as `as` converts a number: integers
truncate or extend, and floats round toward zero into integers. A
float lane outside `U`'s range gives `U`'s nearest value, and NaN
gives 0.

**Type parameters**
- `U` — the new lane type

**Returns**
- the converted lanes

#### reinterpret

```pepper
reinterpret<U: Lane, M>(): Vector<U, M>
```

Reads the vector's bits as `M` lanes of type `U`. The two must have
the same size in bytes, or it is a compile-time error.

**Type parameters**
- `U` — the new lane type
- `M` — the new lane count

**Returns**
- the same bits as a vector of `U`

## extend Vector<T, N>

```pepper
extend Vector<T: IntegerLane, N>
```

The operations of vectors of integers: checked division, the bitwise
operators, shifts and rotates.

**Type parameters**
- `T` — the integer lane type
- `N` — the lane count

### Methods

#### operator /

```pepper
/(other: Vector<T, N>): Vector<T, N>
```

Divides each lane by the same lane of `other`. Division truncates
toward zero.

**Parameters**
- `other` — the vector to divide by

**Returns**
- the lane-wise quotients

**Panics**
- if a lane of `other` is 0, or `T` is signed and a lane divides the lowest value by -1

#### operator /

```pepper
/(other: T): Vector<T, N>
```

Divides every lane by `other`. Division truncates toward zero.

**Parameters**
- `other` — the value to divide by

**Returns**
- the lane-wise quotients

**Panics**
- if `other` is 0, or `T` is signed and a lane divides the lowest value by -1

#### operator %

```pepper
%(other: Vector<T, N>): Vector<T, N>
```

The remainder of dividing each lane by the same lane of `other`, with
the sign of this vector's lane.

**Parameters**
- `other` — the vector to divide by

**Returns**
- the lane-wise remainders

**Panics**
- if a lane of `other` is 0, or `T` is signed and a lane divides the lowest value by -1

#### operator %

```pepper
%(other: T): Vector<T, N>
```

The remainder of dividing every lane by `other`, with the sign of the
lane.

**Parameters**
- `other` — the value to divide by

**Returns**
- the lane-wise remainders

**Panics**
- if `other` is 0, or `T` is signed and a lane divides the lowest value by -1

#### operator &

```pepper
&(other: Vector<T, N>): Vector<T, N>
```

The bitwise AND of each lane with the same lane of `other`.

**Parameters**
- `other` — the vector to combine with

**Returns**
- the lane-wise ANDs

#### operator &

```pepper
&(other: T): Vector<T, N>
```

The bitwise AND of every lane with `other`.

**Parameters**
- `other` — the value to combine with

**Returns**
- the lane-wise ANDs

#### operator |

```pepper
|(other: Vector<T, N>): Vector<T, N>
```

The bitwise OR of each lane with the same lane of `other`.

**Parameters**
- `other` — the vector to combine with

**Returns**
- the lane-wise ORs

#### operator |

```pepper
|(other: T): Vector<T, N>
```

The bitwise OR of every lane with `other`.

**Parameters**
- `other` — the value to combine with

**Returns**
- the lane-wise ORs

#### operator ^

```pepper
^(other: Vector<T, N>): Vector<T, N>
```

The bitwise XOR of each lane with the same lane of `other`.

**Parameters**
- `other` — the vector to combine with

**Returns**
- the lane-wise XORs

#### operator ^

```pepper
^(other: T): Vector<T, N>
```

The bitwise XOR of every lane with `other`.

**Parameters**
- `other` — the value to combine with

**Returns**
- the lane-wise XORs

#### operator <<

```pepper
<<(count: int): Vector<T, N>
```

Shifts every lane left by `count` bits.

**Parameters**
- `count` — the number of bits to shift by

**Returns**
- the shifted lanes

**Panics**
- if `count` is negative or not less than the lane's width in bits

#### operator >>

```pepper
>>(count: int): Vector<T, N>
```

Shifts every lane right by `count` bits: arithmetic (copying the sign
bit) for a signed `T`, logical (filling with zeros) for an unsigned one.

**Parameters**
- `count` — the number of bits to shift by

**Returns**
- the shifted lanes

**Panics**
- if `count` is negative or not less than the lane's width in bits

#### operator ~

```pepper
~(): Vector<T, N>
```

Flips every bit of every lane.

**Returns**
- the complemented lanes

#### rotate_left

```pepper
rotate_left(count: int): Vector<T, N>
```

Rotates the bits of every lane left by `count`, taken modulo the
lane's width (a negative count rotates right).

**Parameters**
- `count` — the number of bits to rotate by

**Returns**
- the rotated lanes

#### rotate_right

```pepper
rotate_right(count: int): Vector<T, N>
```

Rotates the bits of every lane right by `count`, taken modulo the
lane's width (a negative count rotates left).

**Parameters**
- `count` — the number of bits to rotate by

**Returns**
- the rotated lanes

## extend Vector<T, N>

```pepper
extend Vector<T: FloatLane, N>
```

The operations of vectors of floating-point numbers: division and
rounding.

**Type parameters**
- `T` — the floating-point lane type
- `N` — the lane count

### Methods

#### operator /

```pepper
/(other: Vector<T, N>): Vector<T, N>
```

Divides each lane by the same lane of `other`, as floating-point
division does: a zero divisor gives an infinity or NaN.

**Parameters**
- `other` — the vector to divide by

**Returns**
- the lane-wise quotients

#### operator /

```pepper
/(other: T): Vector<T, N>
```

Divides every lane by `other`, as floating-point division does.

**Parameters**
- `other` — the value to divide by

**Returns**
- the lane-wise quotients

#### operator %

```pepper
%(other: Vector<T, N>): Vector<T, N>
```

The remainder of dividing each lane by the same lane of `other`
(C's `fmod`), with the sign of this vector's lane.

**Parameters**
- `other` — the vector to divide by

**Returns**
- the lane-wise remainders

#### operator %

```pepper
%(other: T): Vector<T, N>
```

The remainder of dividing every lane by `other` (C's `fmod`).

**Parameters**
- `other` — the value to divide by

**Returns**
- the lane-wise remainders

#### square_root

```pepper
square_root(): Vector<T, N>
```

The square root of every lane (NaN for a negative lane).

**Returns**
- the lane-wise square roots

#### floor

```pepper
floor(): Vector<T, N>
```

Every lane rounded down to a whole number.

**Returns**
- the lane-wise floors

#### ceiling

```pepper
ceiling(): Vector<T, N>
```

Every lane rounded up to a whole number.

**Returns**
- the lane-wise ceilings

## Mask

```pepper
[Value] struct Mask<N>
```

`N` booleans, one per vector lane: what lane-wise comparisons give.

**Type parameters**
- `N` — the lane count: a power of two from 1 to 64

### Properties

#### count

```pepper
var count: int { get; }
```

The number of lanes, `N`.

### Constructors

#### Mask()

```pepper
construct()
```

Makes a mask with every lane false.

#### Mask()

```pepper
construct(value: bool)
```

Makes a mask with every lane `value`.

**Parameters**
- `value` — the value of every lane

### Methods

#### operator []

```pepper
[](index: ulong): bool
```

Returns lane `index`.

**Parameters**
- `index` — the lane to read

**Returns**
- the value in lane `index`

**Panics**
- if `index` is not less than `N`

#### any

```pepper
any(): bool
```

Whether any lane is true.

**Returns**
- true when at least one lane is true

#### all

```pepper
all(): bool
```

Whether every lane is true.

**Returns**
- true when no lane is false

#### to_bits

```pepper
to_bits(): ulong
```

The lanes packed into bits: bit `i` is lane `i`. Its
`trailing_zeros()` is the first true lane (64 when none is), and its
`count_ones()` the number of true lanes.

**Returns**
- the lanes as a bit mask

#### operator &

```pepper
&(other: Mask<N>): Mask<N>
```

The lane-wise AND of the two masks.

**Parameters**
- `other` — the mask to combine with

**Returns**
- true in each lane true in both

#### operator |

```pepper
|(other: Mask<N>): Mask<N>
```

The lane-wise OR of the two masks.

**Parameters**
- `other` — the mask to combine with

**Returns**
- true in each lane true in either

#### operator ^

```pepper
^(other: Mask<N>): Mask<N>
```

The lane-wise XOR of the two masks.

**Parameters**
- `other` — the mask to combine with

**Returns**
- true in each lane true in exactly one

#### operator ~

```pepper
~(): Mask<N>
```

The lane-wise negation of the mask.

**Returns**
- true in each lane that is false here

#### select

```pepper
select<T: Lane>(if_true: Vector<T, N>, if_false: Vector<T, N>): Vector<T, N>
```

Picks each lane from `if_true` where this mask is true, and from
`if_false` where it is false.

**Type parameters**
- `T` — the lane type of the vectors

**Parameters**
- `if_true` — the lanes to take where the mask is true
- `if_false` — the lanes to take where the mask is false

**Returns**
- the selected lanes
