<!-- Generated from runtime/iterator.pep by `pep-doc reference`. Do not edit. -->

# Iterators

Source: `runtime/iterator.pep`

## Iterator

```pepper
trait Iterator<T>
```

Something a `for` loop can step through, one element at a time.

`for (var x in source)` drives a source that declares `next()` and
`current()` directly: it calls `next()` before each pass and binds
`current()` to the loop variable while `next()` returns true. A type whose
`for` loop should go through a separate iterator implements `Iterable<T>`
instead. A type with neither protocol is a compile error in a `for` loop.

The loop goes by the methods a type has, so declaring the trait is
optional. Declaring it (`extend Foo with Iterator<int>;`) checks that
the methods match and lets the type be used as an `Iterator<int>` value,
which a `for` loop drives through the trait.

**Type parameters**
- `T` — the type of the elements produced

**See also**
- `Iterable`

**Example**
```pepper
struct Countdown {
    int remaining;
    int now;

    construct(this.remaining = 0) {}

    bool next() {
        if (remaining == 0) {
            return false;
        }
        now = remaining;
        remaining = remaining - 1;
        return true;
    }

    int current() {
        return now;
    }
}

extend Countdown with Iterator<int>;

main(): int {
    var total = 0;
    for (int n in Countdown(3)) {
        total = total + n;   # visits 3, 2, 1
    }
    return total;
}
```

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element.

The first call moves to the first element, if any. Once it returns
false it must keep returning false.

**Returns**
- true if there is a current element, false when the elements are exhausted

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

Calling it before the first `next()`, or after `next()` returned false,
is an error; the runtime's iterators panic in that case.

**Returns**
- the current element

#### map

```pepper
map<U>(transform: (T) => U): MapIterator<T, U>
```

Returns an iterator over `transform` applied to each element, in order.

Lazy: `transform` runs once per element, as the result is advanced, and
the result advances this iterator. Every type that declares
`Iterator<T>` gets this method.

**Type parameters**
- `U` — the type `transform` returns

**Parameters**
- `transform` — the function applied to each element

**Returns**
- a `MapIterator<T, U>` over the transformed elements

**Example**
```pepper
var names = Array<String>();
for (var size in names.iterate().map((name) => name.size)) {
    print(size);
}
```

#### filter

```pepper
filter(keep: (T) => bool): FilterIterator<T>
```

Returns an iterator over the elements for which `keep` returns true, in
order.

Lazy: `keep` runs once per element, as the result is advanced, and the
result advances this iterator. Every type that declares `Iterator<T>`
gets this method.

**Parameters**
- `keep` — the test an element must pass

**Returns**
- a `FilterIterator<T>` over the elements that pass

**Example**
```pepper
var nums = Array<int>();
for (var even in nums.iterate().filter((n) => n % 2 == 0)) {
    print(even);
}
```

#### enumerate

```pepper
enumerate<TIndex=ulong>(): EnumerateIterator<T, TIndex>
```

Returns an iterator over the elements paired with their positions:
`(0, first)`, `(1, second)`, and so on.

Lazy, like `map`. Destructure the pair in the loop to name both parts.
The positions count in `ulong`, like `Array.count`; name another
integer type to count in it (`enumerate<int>()`). Every type that
declares `Iterator<T>` gets this method.

**Type parameters**
- `TIndex` — the integer type of the positions, `ulong` by default

**Returns**
- an `EnumerateIterator<T, TIndex>` over `(index, element)` tuples

**Example**
```pepper
var names = ["Ada", "Grace"];
for (var (i, name) in names.iterate().enumerate()) {
    print($"{i}: {name}");   # 0: Ada, then 1: Grace
}
```

#### zip

```pepper
zip<U>(other: Iterator<U>): ZipIterator<T, U>
```

Returns an iterator over pairs of this iterator's elements and
`other`'s, in step: `(first, other's first)`, and so on. It stops when
either runs out.

Lazy, like `map`. Every type that declares `Iterator<T>` gets this
method.

**Type parameters**
- `U` — the type of `other`'s elements

**Parameters**
- `other` — the iterator whose elements form the second half of each pair

**Returns**
- a `ZipIterator<T, U>` over `(element, other element)` tuples

**Example**
```pepper
var names = ["Ada", "Grace"];
var ages = [36, 45];
for (var (name, age) in names.iterate().zip(ages.iterate())) {
    print($"{name} is {age}");
}
```

#### take

```pepper
take(count: ulong): TakeIterator<T>
```

Returns an iterator over at most the first `count` elements.

Lazy, like `map`: it stops after `count` elements, or sooner when this
iterator runs out, and never advances this iterator past them. Every
type that declares `Iterator<T>` gets this method.

**Parameters**
- `count` — the most elements to yield

**Returns**
- a `TakeIterator<T>` over the first `count` elements

**Example**
```pepper
var firsts = (1..>10).take(3).to_array();   # [1, 2, 3]
```

#### skip

```pepper
skip(count: ulong): SkipIterator<T>
```

Returns an iterator over the elements after the first `count`.

Lazy, like `map`: the first `next()` of the result passes over `count`
elements. When there are no more than `count`, it yields nothing.
Every type that declares `Iterator<T>` gets this method.

**Parameters**
- `count` — how many elements to pass over

**Returns**
- a `SkipIterator<T>` over the rest of the elements

**Example**
```pepper
var rest = (1..>5).skip(3).to_array();   # [4, 5]
```

#### chain

```pepper
chain(other: Iterator<T>): ChainIterator<T>
```

Returns an iterator over this iterator's elements, then `other`'s.

Lazy, like `map`: `other` is not advanced until this iterator runs
out. Every type that declares `Iterator<T>` gets this method.

**Parameters**
- `other` — the iterator whose elements follow

**Returns**
- a `ChainIterator<T>` over both iterators' elements

**Example**
```pepper
var both = (1..>2).chain(7..>8).to_array();   # [1, 2, 7, 8]
```

#### to_array

```pepper
to_array(): Array<T>
```

Returns a new `Array` holding the remaining elements, in order.

Runs the iteration to the end. Like the adapters, it works on a copy
of the iterator, so a value iterator (every runtime iterator is one)
is left where it was. Every type that declares `Iterator<T>` gets this
method.

**Returns**
- the elements, possibly none

**Example**
```pepper
var evens = (1..>10).filter((n) => n % 2 == 0).to_array();   # [2, 4, 6, 8, 10]
```

#### count

```pepper
count(): ulong
```

Returns how many elements remain.

Runs the iteration to the end, on a copy of the iterator, like
`to_array`. Every type that declares `Iterator<T>` gets this method.

**Returns**
- the number of elements, possibly 0

**Example**
```pepper
var evens = (1..>10).filter((n) => n % 2 == 0).count();   # 5
```

#### fold

```pepper
fold<U>(initial: U, combine: (U, T) => U): U
```

Combines the elements into one value: `combine(initial, first)`, then
`combine` of that and the second element, and so on.

Runs the iteration to the end, on a copy of the iterator, like
`to_array`. Every type that declares `Iterator<T>` gets this method.

**Type parameters**
- `U` — the type of the combined value

**Parameters**
- `initial` — the value to start from, returned as is when there are no elements
- `combine` — the function that folds one more element into the value so far

**Returns**
- the value after every element is folded in

**Example**
```pepper
var product = (1..>5).fold(1, (total, n) => total * n);   # 120
```

#### any

```pepper
any(test: (T) => bool): bool
```

Returns whether `test` returns true for some element.

Stops at the first element that passes, on a copy of the iterator,
like `to_array`. Every type that declares `Iterator<T>` gets this
method.

**Parameters**
- `test` — the test to apply

**Returns**
- true when an element passes, false when none does or there are none

**Example**
```pepper
var has_even = [1, 3, 4].iterate().any((n) => n % 2 == 0);   # true
```

#### all

```pepper
all(test: (T) => bool): bool
```

Returns whether `test` returns true for every element.

Stops at the first element that fails, on a copy of the iterator, like
`to_array`. Every type that declares `Iterator<T>` gets this method.

**Parameters**
- `test` — the test to apply

**Returns**
- true when every element passes, including when there are none

**Example**
```pepper
var all_small = [1, 3, 4].iterate().all((n) => n < 10);   # true
```

#### find

```pepper
find(test: (T) => bool): T?
```

Returns the first element for which `test` returns true.

Stops at that element, on a copy of the iterator, like `to_array`.
Every type that declares `Iterator<T>` gets this method.

**Parameters**
- `test` — the test an element must pass

**Returns**
- the first element that passes, or Empty when none does

**Example**
```pepper
var first_even = [1, 3, 4, 6].iterate().find((n) => n % 2 == 0);   # Value(4)
```

#### sum

```pepper
sum<TSum=T>(): TSum
```

Returns the sum of the elements, with `+`.

For element types that have `+`, such as the numbers. The sum is
kept in `TSum`, the element type unless named: `sum<long>()` adds
`int` elements without overflowing an `int`. Runs the iteration to
the end, on a copy of the iterator, like `to_array`. Every type that
declares `Iterator<T>` gets this method.

**Type parameters**
- `TSum` — the type the sum is kept in, `T` by default

**Returns**
- the sum, or `TSum`'s default value (0 for a number) when there are no elements

**Example**
```pepper
var total = (1..>4).sum();   # 10
var big = [2000000000, 2000000000].iterate().sum<long>();   # 4000000000
```

#### min

```pepper
min<TValue=T>(): TValue?
```

Returns the smallest element, by `Comparable`'s `compare`.

For [`Comparable`](compare.md) element types, such as the numbers
and `String`. When several elements sort together, returns the first.
Runs the iteration to the end, on a copy of the iterator, like
`to_array`. Every type that declares `Iterator<T>` gets this method.

**Type parameters**
- `TValue` — the `Comparable` type the elements are compared as, `T` by default

**Returns**
- the smallest element, or Empty when there are none

**Example**
```pepper
var lowest = [3, 1, 2].iterate().min();   # Value(1)
```

#### max

```pepper
max<TValue=T>(): TValue?
```

Returns the largest element, by `Comparable`'s `compare`.

For [`Comparable`](compare.md) element types, such as the numbers
and `String`. When several elements sort together, returns the first.
Runs the iteration to the end, on a copy of the iterator, like
`to_array`. Every type that declares `Iterator<T>` gets this method.

**Type parameters**
- `TValue` — the `Comparable` type the elements are compared as, `T` by default

**Returns**
- the largest element, or Empty when there are none

**Example**
```pepper
var highest = [3, 1, 2].iterate().max();   # Value(3)
```

## TakeIterator

```pepper
[Value] struct TakeIterator<T>
```

The iterator `Iterator.take` returns: at most the first `count` elements
of the source iterator.

**Type parameters**
- `T` — the type of the elements

**See also**
- `Iterator.take`

### Constructor

#### TakeIterator()

```pepper
construct(source: Iterator<T>, count: ulong)
```

Makes an iterator over at most the first `count` elements of `source`.

**Parameters**
- `source` — the iterator to take from
- `count` — the most elements to yield

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element, unless `count` elements were yielded.

**Returns**
- true if there is a current element, false after `count` elements or when the source is exhausted

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

## SkipIterator

```pepper
[Value] struct SkipIterator<T>
```

The iterator `Iterator.skip` returns: the elements of the source iterator
after the first `count`.

**Type parameters**
- `T` — the type of the elements

**See also**
- `Iterator.skip`

### Constructor

#### SkipIterator()

```pepper
construct(source: Iterator<T>, count: ulong)
```

Makes an iterator over the elements of `source` after the first
`count`.

**Parameters**
- `source` — the iterator to skip into
- `count` — how many elements to pass over

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element, passing over the first `count` on the
first call.

**Returns**
- true if there is a current element, false when the source is exhausted

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

## ChainIterator

```pepper
[Value] struct ChainIterator<T>
```

The iterator `Iterator.chain` returns: the elements of one iterator, then
those of another.

**Type parameters**
- `T` — the type of the elements

**See also**
- `Iterator.chain`

### Constructor

#### ChainIterator()

```pepper
construct(first: Iterator<T>, second: Iterator<T>)
```

Makes an iterator over the elements of `first`, then `second`.

**Parameters**
- `first` — the iterator whose elements come first
- `second` — the iterator whose elements follow

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element of the first iterator, or once it has
run out, of the second.

**Returns**
- true if there is a current element, false when both are exhausted

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

## MapIterator

```pepper
[Value] struct MapIterator<T, U>
```

The iterator `Iterator.map` returns: each element of the source iterator,
passed through the transform function.

**Type parameters**
- `T` — the type of the source's elements
- `U` — the type of the elements produced

**See also**
- `Iterator.map`

### Constructor

#### MapIterator()

```pepper
construct(source: Iterator<T>, transform: (T) => U)
```

Makes an iterator over `transform` applied to the elements of `source`.

**Parameters**
- `source` — the iterator to transform
- `transform` — the function applied to each element

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element, and applies the transform function to it.

**Returns**
- true if there is a current element, false when the source is exhausted

#### current

```pepper
current(): U
```

Returns the transformed element the last successful `next()` produced.

**Returns**
- the current element

## FilterIterator

```pepper
[Value] struct FilterIterator<T>
```

The iterator `Iterator.filter` returns: the elements of the source
iterator that the test function accepts.

**Type parameters**
- `T` — the type of the elements

**See also**
- `Iterator.filter`

### Constructor

#### FilterIterator()

```pepper
construct(source: Iterator<T>, keep: (T) => bool)
```

Makes an iterator over the elements of `source` that `keep` accepts.

**Parameters**
- `source` — the iterator to filter
- `keep` — the test an element must pass

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element that the test function accepts.

**Returns**
- true if there is a current element, false when the source is exhausted

#### current

```pepper
current(): T
```

Returns the element the last successful `next()` moved to.

**Returns**
- the current element

## EnumerateIterator

```pepper
[Value] struct EnumerateIterator<T, TIndex>
```

The iterator `Iterator.enumerate` returns: each element of the source
iterator, paired with its position.

**Type parameters**
- `T` — the type of the source's elements
- `TIndex` — the integer type of the positions

**See also**
- `Iterator.enumerate`

### Constructor

#### EnumerateIterator()

```pepper
construct(source: Iterator<T>)
```

Makes an iterator over the elements of `source`, numbered from 0.

**Parameters**
- `source` — the iterator to number

### Methods

#### next

```pepper
next(): bool
```

Advances to the next element.

**Returns**
- true if there is a current element, false when the source is exhausted

#### current

```pepper
current(): (TIndex, T)
```

Returns the element the last successful `next()` moved to, with its
index.

**Returns**
- the current `(index, element)` pair

## ZipIterator

```pepper
[Value] struct ZipIterator<T, U>
```

The iterator `Iterator.zip` returns: the elements of two iterators,
paired in step, until either runs out.

**Type parameters**
- `T` — the type of the first iterator's elements
- `U` — the type of the second iterator's elements

**See also**
- `Iterator.zip`

### Constructor

#### ZipIterator()

```pepper
construct(first: Iterator<T>, second: Iterator<U>)
```

Makes an iterator over the elements of `first` and `second`, paired.

**Parameters**
- `first` — the iterator giving the first half of each pair
- `second` — the iterator giving the second half of each pair

### Methods

#### next

```pepper
next(): bool
```

Advances both iterators. `second` is not advanced once `first` has
run out.

**Returns**
- true if both have a current element, false when either is exhausted

#### current

```pepper
current(): (T, U)
```

Returns the pair the last successful `next()` moved to.

**Returns**
- the current `(first element, second element)` pair

## Iterable

```pepper
trait Iterable<T>
```

Something that hands out an `Iterator<T>` over its elements, such as
`Array<T>` and `String` (which yields one code point at a time, as a
`String`).

`for (var x in source)` calls `source.iterate()` once, then drives the
returned iterator with `next()` and `current()`. When a type declares both
`iterate()` and `next()`/`current()`, the loop uses `iterate()`.

**Type parameters**
- `T` — the type of the elements produced

**See also**
- `Iterator`

**Example**
```pepper
var nums = Array<int>();
nums.append(1);
nums.append(2);
var total = 0;
for (var x in nums) {
    total = total + x;
}
```

### Methods

#### iterate

```pepper
iterate(): Iterator<T>
```

Returns a new iterator positioned before the first element.

The result may be any type that satisfies `Iterator<T>` (for example
`ArrayIterator<T>`); each call starts a fresh, independent pass.

**Returns**
- an iterator over the elements
