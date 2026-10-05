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
