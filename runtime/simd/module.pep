## SIMD vectors: `Vector<T, N>` holds `N` numbers of type `T` and computes
## on all of them at once, in the CPU's vector registers.
##
## Bring it in with `import simd`. `T` is an integer or floating-point type
## (`byte`, `char`, `short`, `ushort`, `int`, `uint`, `long`, `ulong`,
## `float`, `double`) and `N`, the lane count, is a power of two from 1 to
## 64, written as a number: `simd.Vector<byte, 16>`. A vector is a value
## (`[Value]`): it is stored inline, copied like a number, and safe to share
## between threads.
##
## The operations compile to the target's vector instructions: SSE2 on
## x86-64 (AVX2 with `-march=x86-64-v3`), NEON on arm64, and `simd128` on
## WebAssembly with `-msimd128`. A target without vector registers gets the
## same results from scalar code. Sixteen bytes (`Vector<byte, 16>`,
## `Vector<int, 4>`, `Vector<double, 2>`) is the width every target handles
## well; wider vectors use several registers where the target has no wider
## ones.
##
## Lane-wise comparisons (`less`, `equal`, ...) give a `Mask<N>`, which
## selects lanes (`select`), answers `any` and `all`, and packs into a bit
## mask with `to_bits`, whose `trailing_zeros` finds the first match.
##
## @example
##     import simd;
##
##     main(): int {
##         var a = simd.Vector<int, 4>(10);
##         var b = a + simd.Vector<int, 4>(5);
##         assert(b[0] == 15 && b.sum() == 60, "lane-wise add");
##         var over = b.greater(12);
##         assert(over.all() && over.to_bits() == 0xF, "a mask per lane");
##         return 0;
##     }

## The number types a `Vector` holds: every integer and floating-point
## type. The runtime declares the conformances; another type cannot be a
## lane.
export trait Lane {}

## The integer lane types, whose vectors have checked division, the bitwise
## operators, shifts and rotates.
export trait IntegerLane {}

## The floating-point lane types, whose vectors have floating-point
## division, `square_root`, `floor` and `ceiling`.
export trait FloatLane {}

extend byte with Lane;
extend byte with IntegerLane;
extend char with Lane;
extend char with IntegerLane;
extend short with Lane;
extend short with IntegerLane;
extend ushort with Lane;
extend ushort with IntegerLane;
extend int with Lane;
extend int with IntegerLane;
extend uint with Lane;
extend uint with IntegerLane;
extend long with Lane;
extend long with IntegerLane;
extend ulong with Lane;
extend ulong with IntegerLane;
extend float with Lane;
extend float with FloatLane;
extend double with Lane;
extend double with FloatLane;

## `N` lanes of the number type `T`, computed on together.
##
## Integer `+`, `-` and `*` wrap around on overflow in each lane, as vector
## instructions do, where scalar arithmetic panics. Integer `/` and `%`
## panic on a zero divisor lane; shifts panic on a count outside the lane's
## width. Every other operation is defined for every input.
##
## @typeParam T the lane type: an integer or floating-point type
## @typeParam N the lane count: a power of two from 1 to 64
[Value]
export struct Vector<T: Lane, N> {
    var _lanes: __simd<T, N>;

    ## Makes a vector with every lane 0.
    construct() {}

    ## Makes a vector with every lane `value`.
    ##
    ## @param value the value of every lane
    construct(value: T) {
        _lanes = __simd_splat<__simd<T, N>>(value);
    }

    static _of(lanes: __simd<T, N>): Vector<T, N> {
        var made = __default<Vector<T, N>>();
        made._lanes = lanes;
        return made;
    }

    ## Reads `N` values from `pointer`, which need not be aligned.
    ##
    ## @param pointer the first of `N` readable values
    ## @returns a vector of the values, the first in lane 0
    static load(pointer: __ptr<T>): Vector<T, N> {
        return Vector<T, N>._of(__simd_load<__simd<T, N>>(pointer));
    }

    ## Reads `N` values from `pointer`, which must be aligned to the
    ## vector's size (`N` times the size of `T`).
    ##
    ## @param pointer the first of `N` readable values
    ## @returns a vector of the values, the first in lane 0
    ## @panics if `pointer` is not aligned to the vector's size
    static load_aligned(pointer: __ptr<T>, location: __ptr<char> = __caller_location()): Vector<T, N> {
        Vector<T, N>._check_aligned(pointer, location);
        return Vector<T, N>._of(__simd_load_aligned<__simd<T, N>>(pointer));
    }

    ## Reads the `N` elements of `array` from `index` on.
    ##
    ## @param array the array to read
    ## @param index the element that goes in lane 0
    ## @returns a vector of `array[index]` through `array[index + N - 1]`
    ## @panics if `array` has fewer than `index + N` elements
    static load(array: Array<T>, index: ulong, location: __ptr<char> = __caller_location()): Vector<T, N> {
        Vector<T, N>._check_span(array, index, location);
        return Vector<T, N>._of(__simd_load<__simd<T, N>>(array._data + index));
    }

    ## Writes the lanes to the `N` values at `pointer`, which need not be
    ## aligned.
    ##
    ## @param pointer the first of `N` writable values
    store(pointer: __ptr<T>) {
        __simd_store<__simd<T, N>>(pointer, _lanes);
    }

    ## Writes the lanes to the `N` values at `pointer`, which must be
    ## aligned to the vector's size.
    ##
    ## @param pointer the first of `N` writable values
    ## @panics if `pointer` is not aligned to the vector's size
    store_aligned(pointer: __ptr<T>, location: __ptr<char> = __caller_location()) {
        Vector<T, N>._check_aligned(pointer, location);
        __simd_store_aligned<__simd<T, N>>(pointer, _lanes);
    }

    ## Writes the lanes to the `N` elements of `array` from `index` on.
    ##
    ## @param array the array to write
    ## @param index the element lane 0 goes to
    ## @panics if `array` has fewer than `index + N` elements
    store(array: Array<T>, index: ulong, location: __ptr<char> = __caller_location()) {
        Vector<T, N>._check_span(array, index, location);
        __simd_store<__simd<T, N>>(array._data + index, _lanes);
    }

    static _check_aligned(pointer: __ptr<T>, location: __ptr<char>) {
        var size = (__simd_lanes<__simd<T, N>>() * __simd_lane_bits<__simd<T, N>>() / 8) as ulong;
        if ((unsafe_cast<ulong>(pointer) & (size - 1)) != 0) {
            panic("vector access is not aligned to the vector's size", location);
        }
    }

    static _check_span(array: Array<T>, index: ulong, location: __ptr<char>) {
        var lanes = __simd_lanes<__simd<T, N>>() as ulong;
        if (index > array.count || array.count - index < lanes) {
            panic(
                $"vector access of {lanes} elements at index {index} is out of bounds for an array of {array.count}",
                location
            );
        }
    }

    ## The number of lanes, `N`.
    var count: int {
        get {
            return __simd_lanes<__simd<T, N>>();
        }
    }

    ## Returns lane `index`.
    ##
    ## @param index the lane to read
    ## @returns the value in lane `index`
    ## @panics if `index` is not less than `N`
    [](index: ulong, location: __ptr<char> = __caller_location()): T {
        Vector<T, N>._check_lane(index, location);
        return __simd_extract<__simd<T, N>>(_lanes, index);
    }

    ## Sets lane `index` to `value`.
    ##
    ## @param index the lane to write
    ## @param value the new value of the lane
    ## @returns `value`
    ## @panics if `index` is not less than `N`
    [](index: ulong, value: T, location: __ptr<char> = __caller_location()): T {
        Vector<T, N>._check_lane(index, location);
        _lanes = __simd_insert<__simd<T, N>>(_lanes, index, value);
        return value;
    }

    static _check_lane(index: ulong, location: __ptr<char>) {
        var lanes = __simd_lanes<__simd<T, N>>() as ulong;
        if (index >= lanes) {
            panic($"lane index {index} is out of range for a vector of {lanes} lanes", location);
        }
    }

    ## Adds each lane of `other` to the same lane of this vector. Integer
    ## lanes wrap around on overflow.
    ##
    ## @param other the vector to add
    ## @returns the lane-wise sums
    +(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_add<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Adds `other` to every lane. Integer lanes wrap around on overflow.
    ##
    ## @param other the value to add
    ## @returns the lane-wise sums
    +(other: T): Vector<T, N> {
        return this + Vector<T, N>(other);
    }

    ## Subtracts each lane of `other` from the same lane of this vector.
    ## Integer lanes wrap around on overflow.
    ##
    ## @param other the vector to subtract
    ## @returns the lane-wise differences
    -(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_subtract<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Subtracts `other` from every lane. Integer lanes wrap around on
    ## overflow.
    ##
    ## @param other the value to subtract
    ## @returns the lane-wise differences
    -(other: T): Vector<T, N> {
        return this - Vector<T, N>(other);
    }

    ## Multiplies each lane by the same lane of `other`. Integer lanes wrap
    ## around on overflow.
    ##
    ## @param other the vector to multiply by
    ## @returns the lane-wise products
    *(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_multiply<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Multiplies every lane by `other`. Integer lanes wrap around on
    ## overflow.
    ##
    ## @param other the value to multiply by
    ## @returns the lane-wise products
    *(other: T): Vector<T, N> {
        return this * Vector<T, N>(other);
    }

    ## Negates every lane. Integer lanes wrap around: the lowest value stays
    ## itself.
    ##
    ## @returns the negated lanes
    -(): Vector<T, N> {
        return Vector<T, N>._of(__simd_negate<__simd<T, N>>(_lanes));
    }

    ## Whether every lane equals the same lane of `other`. A NaN lane equals
    ## nothing. For a mask per lane, use `equal`.
    ##
    ## @param other the vector to compare with
    ## @returns true when all lanes are equal
    ==(other: Vector<T, N>): bool {
        return equal(other).all();
    }

    ## Whether some lane differs from the same lane of `other`.
    ##
    ## @param other the vector to compare with
    ## @returns true when any lane differs
    !=(other: Vector<T, N>): bool {
        return not_equal(other).any();
    }

    ## Compares each lane with the same lane of `other` for equality.
    ##
    ## @param other the vector to compare with
    ## @returns a mask, true in each lane that is equal
    equal(other: Vector<T, N>): Mask<N> {
        return Mask<N>._of(__simd_equal<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Compares every lane with `other` for equality.
    ##
    ## @param other the value to compare with
    ## @returns a mask, true in each lane equal to `other`
    equal(other: T): Mask<N> {
        return equal(Vector<T, N>(other));
    }

    ## Compares each lane with the same lane of `other` for inequality. A
    ## NaN lane differs from everything.
    ##
    ## @param other the vector to compare with
    ## @returns a mask, true in each lane that differs
    not_equal(other: Vector<T, N>): Mask<N> {
        return Mask<N>._of(__simd_not_equal<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Compares every lane with `other` for inequality.
    ##
    ## @param other the value to compare with
    ## @returns a mask, true in each lane that differs from `other`
    not_equal(other: T): Mask<N> {
        return not_equal(Vector<T, N>(other));
    }

    ## Tests whether each lane is less than the same lane of `other`.
    ##
    ## @param other the vector to compare with
    ## @returns a mask, true in each lane that is less
    less(other: Vector<T, N>): Mask<N> {
        return Mask<N>._of(__simd_less<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Tests whether every lane is less than `other`.
    ##
    ## @param other the value to compare with
    ## @returns a mask, true in each lane less than `other`
    less(other: T): Mask<N> {
        return less(Vector<T, N>(other));
    }

    ## Tests whether each lane is less than or equal to the same lane of
    ## `other`.
    ##
    ## @param other the vector to compare with
    ## @returns a mask, true in each lane that is less or equal
    less_equal(other: Vector<T, N>): Mask<N> {
        return Mask<N>._of(__simd_less_equal<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Tests whether every lane is less than or equal to `other`.
    ##
    ## @param other the value to compare with
    ## @returns a mask, true in each lane less than or equal to `other`
    less_equal(other: T): Mask<N> {
        return less_equal(Vector<T, N>(other));
    }

    ## Tests whether each lane is greater than the same lane of `other`.
    ##
    ## @param other the vector to compare with
    ## @returns a mask, true in each lane that is greater
    greater(other: Vector<T, N>): Mask<N> {
        return Mask<N>._of(__simd_greater<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Tests whether every lane is greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns a mask, true in each lane greater than `other`
    greater(other: T): Mask<N> {
        return greater(Vector<T, N>(other));
    }

    ## Tests whether each lane is greater than or equal to the same lane of
    ## `other`.
    ##
    ## @param other the vector to compare with
    ## @returns a mask, true in each lane that is greater or equal
    greater_equal(other: Vector<T, N>): Mask<N> {
        return Mask<N>._of(__simd_greater_equal<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Tests whether every lane is greater than or equal to `other`.
    ##
    ## @param other the value to compare with
    ## @returns a mask, true in each lane greater than or equal to `other`
    greater_equal(other: T): Mask<N> {
        return greater_equal(Vector<T, N>(other));
    }

    ## The smaller of each lane and the same lane of `other`. For floats, a
    ## NaN lane gives the other lane.
    ##
    ## @param other the vector to compare with
    ## @returns the lane-wise minimums
    min(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_minimum<__simd<T, N>>(_lanes, other._lanes));
    }

    ## The larger of each lane and the same lane of `other`. For floats, a
    ## NaN lane gives the other lane.
    ##
    ## @param other the vector to compare with
    ## @returns the lane-wise maximums
    max(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_maximum<__simd<T, N>>(_lanes, other._lanes));
    }

    ## The absolute value of every lane. For a signed integer `T` the lowest
    ## value has no positive counterpart and stays itself.
    ##
    ## @returns the lane-wise absolute values
    abs(): Vector<T, N> {
        return Vector<T, N>._of(__simd_abs<__simd<T, N>>(_lanes));
    }

    ## The sum of the lanes. Integer lanes wrap around on overflow; float
    ## lanes are added in lane order.
    ##
    ## @returns the sum of all lanes
    sum(): T {
        return __simd_sum<__simd<T, N>>(_lanes);
    }

    ## The smallest lane.
    ##
    ## @returns the minimum over all lanes
    minimum(): T {
        return __simd_reduce_minimum<__simd<T, N>>(_lanes);
    }

    ## The largest lane.
    ##
    ## @returns the maximum over all lanes
    maximum(): T {
        return __simd_reduce_maximum<__simd<T, N>>(_lanes);
    }

    ## Picks lanes by index: lane `i` of the result is lane `indices[i]` of
    ## this vector. Each index is taken modulo `N`, so every index picks a
    ## lane. When the indices are constants, an optimized build compiles this
    ## to one shuffle instruction.
    ##
    ## @param indices the lane to pick for each lane of the result
    ## @returns the picked lanes
    shuffle(indices: Vector<int, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_shuffle<__simd<T, N>>(_lanes, indices._lanes));
    }

    ## The lanes in reverse order.
    ##
    ## @returns a vector whose lane `i` is lane `N - 1 - i` of this one
    reverse(): Vector<T, N> {
        return Vector<T, N>._of(__simd_reverse<__simd<T, N>>(_lanes));
    }

    ## Interleaves the low halves of this vector and `other`: lanes
    ## `this[0], other[0], this[1], other[1], ...`.
    ##
    ## @param other the vector whose lanes go in the odd lanes
    ## @returns the interleaved lanes
    interleave_low(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_interleave_low<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Interleaves the high halves of this vector and `other`: lanes
    ## `this[N / 2], other[N / 2], this[N / 2 + 1], ...`.
    ##
    ## @param other the vector whose lanes go in the odd lanes
    ## @returns the interleaved lanes
    interleave_high(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_interleave_high<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Converts every lane to `U`, as `as` converts a number: integers
    ## truncate or extend, and floats round toward zero into integers. A
    ## float lane outside `U`'s range gives `U`'s nearest value, and NaN
    ## gives 0.
    ##
    ## @typeParam U the new lane type
    ## @returns the converted lanes
    convert<U: Lane>(): Vector<U, N> {
        return Vector<U, N>._of(__simd_convert<__simd<U, N>>(_lanes));
    }

    ## Reads the vector's bits as `M` lanes of type `U`. The two must have
    ## the same size in bytes, or it is a compile-time error.
    ##
    ## @typeParam U the new lane type
    ## @typeParam M the new lane count
    ## @returns the same bits as a vector of `U`
    reinterpret<U: Lane, M>(): Vector<U, M> {
        return Vector<U, M>._of(__simd_reinterpret<__simd<U, M>>(_lanes));
    }
}

## The operations of vectors of integers: checked division, the bitwise
## operators, shifts and rotates.
##
## @typeParam T the integer lane type
## @typeParam N the lane count
export extend Vector<T: IntegerLane, N> {
    ## Divides each lane by the same lane of `other`. Division truncates
    ## toward zero.
    ##
    ## @param other the vector to divide by
    ## @returns the lane-wise quotients
    ## @panics if a lane of `other` is 0, or `T` is signed and a lane divides the lowest value by -1
    /(other: Vector<T, N>, location: __ptr<char> = __caller_location()): Vector<T, N> {
        return _divide(other, location);
    }

    ## Divides every lane by `other`. Division truncates toward zero.
    ##
    ## @param other the value to divide by
    ## @returns the lane-wise quotients
    ## @panics if `other` is 0, or `T` is signed and a lane divides the lowest value by -1
    /(other: T, location: __ptr<char> = __caller_location()): Vector<T, N> {
        return _divide(Vector<T, N>(other), location);
    }

    ## The remainder of dividing each lane by the same lane of `other`, with
    ## the sign of this vector's lane.
    ##
    ## @param other the vector to divide by
    ## @returns the lane-wise remainders
    ## @panics if a lane of `other` is 0, or `T` is signed and a lane divides the lowest value by -1
    %(other: Vector<T, N>, location: __ptr<char> = __caller_location()): Vector<T, N> {
        return _remainder(other, location);
    }

    ## The remainder of dividing every lane by `other`, with the sign of the
    ## lane.
    ##
    ## @param other the value to divide by
    ## @returns the lane-wise remainders
    ## @panics if `other` is 0, or `T` is signed and a lane divides the lowest value by -1
    %(other: T, location: __ptr<char> = __caller_location()): Vector<T, N> {
        return _remainder(Vector<T, N>(other), location);
    }

    _divide(other: Vector<T, N>, location: __ptr<char>): Vector<T, N> {
        _check_divisor(other, location);
        return Vector<T, N>._of(__simd_divide<__simd<T, N>>(_lanes, other._lanes));
    }

    _remainder(other: Vector<T, N>, location: __ptr<char>): Vector<T, N> {
        _check_divisor(other, location);
        return Vector<T, N>._of(__simd_remainder<__simd<T, N>>(_lanes, other._lanes));
    }

    # Integer division by 0, and `MIN / -1`, are undefined in LLVM; panic
    # first, as scalar division does.
    _check_divisor(other: Vector<T, N>, location: __ptr<char>) {
        var zero = Vector<T, N>();
        if (other.equal(zero).any()) {
            panic("division by zero in a vector lane", location);
        }
        if (__simd_is_signed<__simd<T, N>>()) {
            var lowest = Vector<T, N>(1 as T) << (__simd_lane_bits<__simd<T, N>>() - 1);
            var minus_one = zero - Vector<T, N>(1 as T);
            if ((equal(lowest) & other.equal(minus_one)).any()) {
                panic("integer overflow in a vector lane division", location);
            }
        }
    }

    ## The bitwise AND of each lane with the same lane of `other`.
    ##
    ## @param other the vector to combine with
    ## @returns the lane-wise ANDs
    &(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_and<__simd<T, N>>(_lanes, other._lanes));
    }

    ## The bitwise AND of every lane with `other`.
    ##
    ## @param other the value to combine with
    ## @returns the lane-wise ANDs
    &(other: T): Vector<T, N> {
        return this & Vector<T, N>(other);
    }

    ## The bitwise OR of each lane with the same lane of `other`.
    ##
    ## @param other the vector to combine with
    ## @returns the lane-wise ORs
    |(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_or<__simd<T, N>>(_lanes, other._lanes));
    }

    ## The bitwise OR of every lane with `other`.
    ##
    ## @param other the value to combine with
    ## @returns the lane-wise ORs
    |(other: T): Vector<T, N> {
        return this | Vector<T, N>(other);
    }

    ## The bitwise XOR of each lane with the same lane of `other`.
    ##
    ## @param other the vector to combine with
    ## @returns the lane-wise XORs
    ^(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_xor<__simd<T, N>>(_lanes, other._lanes));
    }

    ## The bitwise XOR of every lane with `other`.
    ##
    ## @param other the value to combine with
    ## @returns the lane-wise XORs
    ^(other: T): Vector<T, N> {
        return this ^ Vector<T, N>(other);
    }

    ## Shifts every lane left by `count` bits.
    ##
    ## @param count the number of bits to shift by
    ## @returns the shifted lanes
    ## @panics if `count` is negative or not less than the lane's width in bits
    <<(count: int, location: __ptr<char> = __caller_location()): Vector<T, N> {
        Vector<T, N>._check_shift(count, location);
        return Vector<T, N>._of(__simd_shift_left<__simd<T, N>>(_lanes, count));
    }

    ## Shifts every lane right by `count` bits: arithmetic (copying the sign
    ## bit) for a signed `T`, logical (filling with zeros) for an unsigned one.
    ##
    ## @param count the number of bits to shift by
    ## @returns the shifted lanes
    ## @panics if `count` is negative or not less than the lane's width in bits
    >>(count: int, location: __ptr<char> = __caller_location()): Vector<T, N> {
        Vector<T, N>._check_shift(count, location);
        return Vector<T, N>._of(__simd_shift_right<__simd<T, N>>(_lanes, count));
    }

    static _check_shift(count: int, location: __ptr<char>) {
        var bits = __simd_lane_bits<__simd<T, N>>();
        if (count < 0 || count >= bits) {
            panic($"shift count {count} is out of range for {bits}-bit vector lanes", location);
        }
    }

    ## Flips every bit of every lane.
    ##
    ## @returns the complemented lanes
    ~(): Vector<T, N> {
        return Vector<T, N>._of(__simd_not<__simd<T, N>>(_lanes));
    }

    ## Rotates the bits of every lane left by `count`, taken modulo the
    ## lane's width (a negative count rotates right).
    ##
    ## @param count the number of bits to rotate by
    ## @returns the rotated lanes
    rotate_left(count: int): Vector<T, N> {
        return Vector<T, N>._of(__simd_rotate_left<__simd<T, N>>(_lanes, count));
    }

    ## Rotates the bits of every lane right by `count`, taken modulo the
    ## lane's width (a negative count rotates left).
    ##
    ## @param count the number of bits to rotate by
    ## @returns the rotated lanes
    rotate_right(count: int): Vector<T, N> {
        return Vector<T, N>._of(__simd_rotate_right<__simd<T, N>>(_lanes, count));
    }
}

## The operations of vectors of floating-point numbers: division and
## rounding.
##
## @typeParam T the floating-point lane type
## @typeParam N the lane count
export extend Vector<T: FloatLane, N> {
    ## Divides each lane by the same lane of `other`, as floating-point
    ## division does: a zero divisor gives an infinity or NaN.
    ##
    ## @param other the vector to divide by
    ## @returns the lane-wise quotients
    /(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_divide<__simd<T, N>>(_lanes, other._lanes));
    }

    ## Divides every lane by `other`, as floating-point division does.
    ##
    ## @param other the value to divide by
    ## @returns the lane-wise quotients
    /(other: T): Vector<T, N> {
        return this / Vector<T, N>(other);
    }

    ## The remainder of dividing each lane by the same lane of `other`
    ## (C's `fmod`), with the sign of this vector's lane.
    ##
    ## @param other the vector to divide by
    ## @returns the lane-wise remainders
    %(other: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_remainder<__simd<T, N>>(_lanes, other._lanes));
    }

    ## The remainder of dividing every lane by `other` (C's `fmod`).
    ##
    ## @param other the value to divide by
    ## @returns the lane-wise remainders
    %(other: T): Vector<T, N> {
        return this % Vector<T, N>(other);
    }

    ## The square root of every lane (NaN for a negative lane).
    ##
    ## @returns the lane-wise square roots
    square_root(): Vector<T, N> {
        return Vector<T, N>._of(__simd_square_root<__simd<T, N>>(_lanes));
    }

    ## Every lane rounded down to a whole number.
    ##
    ## @returns the lane-wise floors
    floor(): Vector<T, N> {
        return Vector<T, N>._of(__simd_floor<__simd<T, N>>(_lanes));
    }

    ## Every lane rounded up to a whole number.
    ##
    ## @returns the lane-wise ceilings
    ceiling(): Vector<T, N> {
        return Vector<T, N>._of(__simd_ceiling<__simd<T, N>>(_lanes));
    }
}

## `N` booleans, one per vector lane: what lane-wise comparisons give.
##
## @typeParam N the lane count: a power of two from 1 to 64
[Value]
export struct Mask<N> {
    var _lanes: __simd<bool, N>;

    ## Makes a mask with every lane false.
    construct() {}

    ## Makes a mask with every lane `value`.
    ##
    ## @param value the value of every lane
    construct(value: bool) {
        _lanes = __simd_splat<__simd<bool, N>>(value);
    }

    static _of(lanes: __simd<bool, N>): Mask<N> {
        var made = __default<Mask<N>>();
        made._lanes = lanes;
        return made;
    }

    ## The number of lanes, `N`.
    var count: int {
        get {
            return __simd_lanes<__simd<bool, N>>();
        }
    }

    ## Returns lane `index`.
    ##
    ## @param index the lane to read
    ## @returns the value in lane `index`
    ## @panics if `index` is not less than `N`
    [](index: ulong, location: __ptr<char> = __caller_location()): bool {
        var lanes = __simd_lanes<__simd<bool, N>>() as ulong;
        if (index >= lanes) {
            panic($"lane index {index} is out of range for a mask of {lanes} lanes", location);
        }
        return __simd_extract<__simd<bool, N>>(_lanes, index);
    }

    ## Whether any lane is true.
    ##
    ## @returns true when at least one lane is true
    any(): bool {
        return __simd_any<__simd<bool, N>>(_lanes);
    }

    ## Whether every lane is true.
    ##
    ## @returns true when no lane is false
    all(): bool {
        return __simd_all<__simd<bool, N>>(_lanes);
    }

    ## The lanes packed into bits: bit `i` is lane `i`. Its
    ## `trailing_zeros()` is the first true lane (64 when none is), and its
    ## `count_ones()` the number of true lanes.
    ##
    ## @returns the lanes as a bit mask
    to_bits(): ulong {
        return __simd_to_bits<__simd<bool, N>>(_lanes);
    }

    ## The lane-wise AND of the two masks.
    ##
    ## @param other the mask to combine with
    ## @returns true in each lane true in both
    &(other: Mask<N>): Mask<N> {
        return Mask<N>._of(__simd_and<__simd<bool, N>>(_lanes, other._lanes));
    }

    ## The lane-wise OR of the two masks.
    ##
    ## @param other the mask to combine with
    ## @returns true in each lane true in either
    |(other: Mask<N>): Mask<N> {
        return Mask<N>._of(__simd_or<__simd<bool, N>>(_lanes, other._lanes));
    }

    ## The lane-wise XOR of the two masks.
    ##
    ## @param other the mask to combine with
    ## @returns true in each lane true in exactly one
    ^(other: Mask<N>): Mask<N> {
        return Mask<N>._of(__simd_xor<__simd<bool, N>>(_lanes, other._lanes));
    }

    ## The lane-wise negation of the mask.
    ##
    ## @returns true in each lane that is false here
    ~(): Mask<N> {
        return Mask<N>._of(__simd_not<__simd<bool, N>>(_lanes));
    }

    ## Picks each lane from `if_true` where this mask is true, and from
    ## `if_false` where it is false.
    ##
    ## @typeParam T the lane type of the vectors
    ## @param if_true the lanes to take where the mask is true
    ## @param if_false the lanes to take where the mask is false
    ## @returns the selected lanes
    select<T: Lane>(if_true: Vector<T, N>, if_false: Vector<T, N>): Vector<T, N> {
        return Vector<T, N>._of(__simd_select<__simd<T, N>>(_lanes, if_true._lanes, if_false._lanes));
    }
}
