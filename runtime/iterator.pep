# The iterator protocol behind `for (var x in source) { ... }`.
#
# A `for` loop calls `source.iterate()` when the source's type declares it
# (Iterable<T>), else drives the source itself when it declares `next()` and
# `current()` (Iterator<T>); anything else is a compile error. The loop is
#
#     var it = source.iterate();      # or `var it = source;`
#     while (it.next()) {
#         var x = it.current();
#         ...
#     }
#
# The loop goes by the methods a type has, so declaring the trait is
# optional; declaring it (`extend Foo with Iterator<int>`) checks the methods
# and lets the type be used as an `Iterator<int>` value.

## Something a `for` loop can step through, one element at a time.
##
## `for (var x in source)` drives a source that declares `next()` and
## `current()` directly: it calls `next()` before each pass and binds
## `current()` to the loop variable while `next()` returns true. A type whose
## `for` loop should go through a separate iterator implements `Iterable<T>`
## instead. A type with neither protocol is a compile error in a `for` loop.
##
## The loop goes by the methods a type has, so declaring the trait is
## optional. Declaring it (`extend Foo with Iterator<int>;`) checks that
## the methods match and lets the type be used as an `Iterator<int>` value,
## which a `for` loop drives through the trait.
##
## @typeParam T the type of the elements produced
## @example
##     struct Countdown {
##         int remaining;
##         int now;
##
##         construct(this.remaining = 0) {}
##
##         bool next() {
##             if (remaining == 0) {
##                 return false;
##             }
##             now = remaining;
##             remaining = remaining - 1;
##             return true;
##         }
##
##         int current() {
##             return now;
##         }
##     }
##
##     extend Countdown with Iterator<int>;
##
##     main(): int {
##         var total = 0;
##         for (int n in Countdown(3)) {
##             total = total + n;   # visits 3, 2, 1
##         }
##         return total;
##     }
## @see Iterable
export trait Iterator<T> {
    ## Advances to the next element.
    ##
    ## The first call moves to the first element, if any. Once it returns
    ## false it must keep returning false.
    ##
    ## @returns true if there is a current element, false when the elements are exhausted
    next(): bool;

    ## Returns the element the last successful `next()` moved to.
    ##
    ## Calling it before the first `next()`, or after `next()` returned false,
    ## is an error; the runtime's iterators panic in that case.
    ##
    ## @returns the current element
    current(): T;

    ## Returns an iterator over `transform` applied to each element, in order.
    ##
    ## Lazy: `transform` runs once per element, as the result is advanced, and
    ## the result advances this iterator. Every type that declares
    ## `Iterator<T>` gets this method.
    ##
    ## @typeParam U the type `transform` returns
    ## @param transform the function applied to each element
    ## @returns a `MapIterator<T, U>` over the transformed elements
    ## @example
    ##     var names = Array<String>();
    ##     for (var size in names.iterate().map((name) => name.size)) {
    ##         print(size);
    ##     }
    map<U>(transform: (T) => U): MapIterator<T, U> {
        return MapIterator<T, U>(this, transform);
    }

    ## Returns an iterator over the elements for which `keep` returns true, in
    ## order.
    ##
    ## Lazy: `keep` runs once per element, as the result is advanced, and the
    ## result advances this iterator. Every type that declares `Iterator<T>`
    ## gets this method.
    ##
    ## @param keep the test an element must pass
    ## @returns a `FilterIterator<T>` over the elements that pass
    ## @example
    ##     var nums = Array<int>();
    ##     for (var even in nums.iterate().filter((n) => n % 2 == 0)) {
    ##         print(even);
    ##     }
    filter(keep: (T) => bool): FilterIterator<T> {
        return FilterIterator<T>(this, keep);
    }

    ## Returns an iterator over the elements paired with their positions:
    ## `(0, first)`, `(1, second)`, and so on.
    ##
    ## Lazy, like `map`. Destructure the pair in the loop to name both parts.
    ## The positions count in `ulong`, like `Array.count`; name another
    ## integer type to count in it (`enumerate<int>()`). Every type that
    ## declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TIndex the integer type of the positions, `ulong` by default
    ## @returns an `EnumerateIterator<T, TIndex>` over `(index, element)` tuples
    ## @example
    ##     var names = ["Ada", "Grace"];
    ##     for (var (i, name) in names.iterate().enumerate()) {
    ##         print($"{i}: {name}");   # 0: Ada, then 1: Grace
    ##     }
    enumerate<TIndex=ulong>(): EnumerateIterator<T, TIndex> {
        return EnumerateIterator<T, TIndex>(this);
    }

    ## Returns an iterator over pairs of this iterator's elements and
    ## `other`'s, in step: `(first, other's first)`, and so on. It stops when
    ## either runs out.
    ##
    ## Lazy, like `map`. Every type that declares `Iterator<T>` gets this
    ## method.
    ##
    ## @typeParam U the type of `other`'s elements
    ## @param other the iterator whose elements form the second half of each pair
    ## @returns a `ZipIterator<T, U>` over `(element, other element)` tuples
    ## @example
    ##     var names = ["Ada", "Grace"];
    ##     var ages = [36, 45];
    ##     for (var (name, age) in names.iterate().zip(ages.iterate())) {
    ##         print($"{name} is {age}");
    ##     }
    zip<U>(other: Iterator<U>): ZipIterator<T, U> {
        return ZipIterator<T, U>(this, other);
    }

    ## Returns an iterator over at most the first `count` elements.
    ##
    ## Lazy, like `map`: it stops after `count` elements, or sooner when this
    ## iterator runs out, and never advances this iterator past them. Every
    ## type that declares `Iterator<T>` gets this method.
    ##
    ## @param count the most elements to yield
    ## @returns a `TakeIterator<T>` over the first `count` elements
    ## @example
    ##     var firsts = (1..>10).take(3).to_array();   # [1, 2, 3]
    take(count: ulong): TakeIterator<T> {
        return TakeIterator<T>(this, count);
    }

    ## Returns an iterator over the elements after the first `count`.
    ##
    ## Lazy, like `map`: the first `next()` of the result passes over `count`
    ## elements. When there are no more than `count`, it yields nothing.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @param count how many elements to pass over
    ## @returns a `SkipIterator<T>` over the rest of the elements
    ## @example
    ##     var rest = (1..>5).skip(3).to_array();   # [4, 5]
    skip(count: ulong): SkipIterator<T> {
        return SkipIterator<T>(this, count);
    }

    ## Returns an iterator over this iterator's elements, then `other`'s.
    ##
    ## Lazy, like `map`: `other` is not advanced until this iterator runs
    ## out. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @param other the iterator whose elements follow
    ## @returns a `ChainIterator<T>` over both iterators' elements
    ## @example
    ##     var both = (1..>2).chain(7..>8).to_array();   # [1, 2, 7, 8]
    chain(other: Iterator<T>): ChainIterator<T> {
        return ChainIterator<T>(this, other);
    }

    ## Returns a new `Array` holding the remaining elements, in order.
    ##
    ## Runs the iteration to the end. Like the adapters, it works on a copy
    ## of the iterator, so a value iterator (every runtime iterator is one)
    ## is left where it was. Every type that declares `Iterator<T>` gets this
    ## method.
    ##
    ## @returns the elements, possibly none
    ## @example
    ##     var evens = (1..>10).filter((n) => n % 2 == 0).to_array();   # [2, 4, 6, 8, 10]
    to_array(): Array<T> {
        # A copy: a value iterator is left where it was.
        Iterator<T> source = this;
        var result = Array<T>();
        while (source.next()) {
            result.append(source.current());
        }
        return result;
    }

    ## Returns how many elements remain.
    ##
    ## Runs the iteration to the end, on a copy of the iterator, like
    ## `to_array`. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @returns the number of elements, possibly 0
    ## @example
    ##     var evens = (1..>10).filter((n) => n % 2 == 0).count();   # 5
    count(): ulong {
        Iterator<T> source = this;
        ulong result = 0;
        while (source.next()) {
            result += 1;
        }
        return result;
    }

    ## Combines the elements into one value: `combine(initial, first)`, then
    ## `combine` of that and the second element, and so on.
    ##
    ## Runs the iteration to the end, on a copy of the iterator, like
    ## `to_array`. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam U the type of the combined value
    ## @param initial the value to start from, returned as is when there are no elements
    ## @param combine the function that folds one more element into the value so far
    ## @returns the value after every element is folded in
    ## @example
    ##     var product = (1..>5).fold(1, (total, n) => total * n);   # 120
    fold<U>(initial: U, combine: (U, T) => U): U {
        Iterator<T> source = this;
        var result = initial;
        while (source.next()) {
            result = combine(result, source.current());
        }
        return result;
    }

    ## Returns whether `test` returns true for some element.
    ##
    ## Stops at the first element that passes, on a copy of the iterator,
    ## like `to_array`. Every type that declares `Iterator<T>` gets this
    ## method.
    ##
    ## @param test the test to apply
    ## @returns true when an element passes, false when none does or there are none
    ## @example
    ##     var has_even = [1, 3, 4].iterate().any((n) => n % 2 == 0);   # true
    any(test: (T) => bool): bool {
        Iterator<T> source = this;
        while (source.next()) {
            if (test(source.current())) {
                return true;
            }
        }
        return false;
    }

    ## Returns whether `test` returns true for every element.
    ##
    ## Stops at the first element that fails, on a copy of the iterator, like
    ## `to_array`. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @param test the test to apply
    ## @returns true when every element passes, including when there are none
    ## @example
    ##     var all_small = [1, 3, 4].iterate().all((n) => n < 10);   # true
    all(test: (T) => bool): bool {
        Iterator<T> source = this;
        while (source.next()) {
            if (!test(source.current())) {
                return false;
            }
        }
        return true;
    }

    ## Returns the first element for which `test` returns true.
    ##
    ## Stops at that element, on a copy of the iterator, like `to_array`.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @param test the test an element must pass
    ## @returns the first element that passes, or Empty when none does
    ## @example
    ##     var first_even = [1, 3, 4, 6].iterate().find((n) => n % 2 == 0);   # Value(4)
    find(test: (T) => bool): T? {
        Iterator<T> source = this;
        while (source.next()) {
            var element = source.current();
            if (test(element)) {
                return Optional<T>.Value(element);
            }
        }
        return Optional<T>.Empty;
    }

    ## Returns the sum of the elements, with `+`.
    ##
    ## For element types that have `+`, such as the numbers. The sum is
    ## kept in `TSum`, the element type unless named: `sum<long>()` adds
    ## `int` elements without overflowing an `int`. Runs the iteration to
    ## the end, on a copy of the iterator, like `to_array`. Every type that
    ## declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TSum the type the sum is kept in, `T` by default
    ## @returns the sum, or `TSum`'s default value (0 for a number) when there are no elements
    ## @example
    ##     var total = (1..>4).sum();   # 10
    ##     var big = [2000000000, 2000000000].iterate().sum<long>();   # 4000000000
    sum<TSum=T>(): TSum {
        Iterator<T> source = this;
        var result: TSum;
        while (source.next()) {
            result = result + source.current();
        }
        return result;
    }

    ## Returns the smallest element, by `Comparable`'s `compare`.
    ##
    ## For [`Comparable`](compare.md) element types, such as the numbers
    ## and `String`. When several elements sort together, returns the first.
    ## Runs the iteration to the end, on a copy of the iterator, like
    ## `to_array`. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TValue the `Comparable` type the elements are compared as, `T` by default
    ## @returns the smallest element, or Empty when there are none
    ## @example
    ##     var lowest = [3, 1, 2].iterate().min();   # Value(1)
    min<TValue=T>(): TValue? {
        Iterator<T> source = this;
        if (!source.next()) {
            return Optional<TValue>.Empty;
        }
        TValue best = source.current();
        while (source.next()) {
            TValue element = source.current();
            if (element.compare(best) < 0) {
                best = element;
            }
        }
        return Optional<TValue>.Value(best);
    }

    ## Returns the largest element, by `Comparable`'s `compare`.
    ##
    ## For [`Comparable`](compare.md) element types, such as the numbers
    ## and `String`. When several elements sort together, returns the first.
    ## Runs the iteration to the end, on a copy of the iterator, like
    ## `to_array`. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TValue the `Comparable` type the elements are compared as, `T` by default
    ## @returns the largest element, or Empty when there are none
    ## @example
    ##     var highest = [3, 1, 2].iterate().max();   # Value(3)
    max<TValue=T>(): TValue? {
        Iterator<T> source = this;
        if (!source.next()) {
            return Optional<TValue>.Empty;
        }
        TValue best = source.current();
        while (source.next()) {
            TValue element = source.current();
            if (element.compare(best) > 0) {
                best = element;
            }
        }
        return Optional<TValue>.Value(best);
    }
}

## The iterator `Iterator.take` returns: at most the first `count` elements
## of the source iterator.
##
## @typeParam T the type of the elements
## @see Iterator.take
[Value]
export struct TakeIterator<T> {
    ## The iterator whose first elements are yielded.
    Iterator<T> _source;
    ## How many more elements may be yielded.
    ulong _remaining;

    ## Makes an iterator over at most the first `count` elements of `source`.
    ##
    ## @param source the iterator to take from
    ## @param count the most elements to yield
    construct(source: Iterator<T>, count: ulong) {
        _source = source;
        _remaining = count;
    }

    ## Advances to the next element, unless `count` elements were yielded.
    ##
    ## @returns true if there is a current element, false after `count` elements or when the source is exhausted
    next(): bool {
        if (_remaining == 0) {
            return false;
        }
        _remaining -= 1;
        return _source.next();
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    current(): T {
        return _source.current();
    }
}

extend TakeIterator<T> with Iterator<T>;

## The iterator `Iterator.skip` returns: the elements of the source iterator
## after the first `count`.
##
## @typeParam T the type of the elements
## @see Iterator.skip
[Value]
export struct SkipIterator<T> {
    ## The iterator whose later elements are yielded.
    Iterator<T> _source;
    ## How many elements are still to be passed over.
    ulong _skip;

    ## Makes an iterator over the elements of `source` after the first
    ## `count`.
    ##
    ## @param source the iterator to skip into
    ## @param count how many elements to pass over
    construct(source: Iterator<T>, count: ulong) {
        _source = source;
        _skip = count;
    }

    ## Advances to the next element, passing over the first `count` on the
    ## first call.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        while (_skip > 0) {
            _skip -= 1;
            if (!_source.next()) {
                return false;
            }
        }
        return _source.next();
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    current(): T {
        return _source.current();
    }
}

extend SkipIterator<T> with Iterator<T>;

## The iterator `Iterator.chain` returns: the elements of one iterator, then
## those of another.
##
## @typeParam T the type of the elements
## @see Iterator.chain
[Value]
export struct ChainIterator<T> {
    ## The iterator whose elements come first.
    Iterator<T> _first;
    ## The iterator whose elements follow.
    Iterator<T> _second;
    ## Whether `_first` has run out, so the elements come from `_second`.
    bool _on_second;

    ## Makes an iterator over the elements of `first`, then `second`.
    ##
    ## @param first the iterator whose elements come first
    ## @param second the iterator whose elements follow
    construct(first: Iterator<T>, second: Iterator<T>) {
        _first = first;
        _second = second;
    }

    ## Advances to the next element of the first iterator, or once it has
    ## run out, of the second.
    ##
    ## @returns true if there is a current element, false when both are exhausted
    next(): bool {
        if (!_on_second && _first.next()) {
            return true;
        }
        _on_second = true;
        return _second.next();
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    current(): T {
        return _on_second ? _second.current() : _first.current();
    }
}

extend ChainIterator<T> with Iterator<T>;

## The iterator `Iterator.map` returns: each element of the source iterator,
## passed through the transform function.
##
## @typeParam T the type of the source's elements
## @typeParam U the type of the elements produced
## @see Iterator.map
[Value]
export struct MapIterator<T, U> {
    ## The iterator whose elements are transformed.
    Iterator<T> _source;
    ## The function applied to each element.
    (T) => U _transform;
    ## The current element, the transform of the source's current element.
    U _value;

    ## Makes an iterator over `transform` applied to the elements of `source`.
    ##
    ## @param source the iterator to transform
    ## @param transform the function applied to each element
    construct(source: Iterator<T>, transform: (T) => U) {
        _source = source;
        _transform = transform;
    }

    ## Advances to the next element, and applies the transform function to it.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        if (_source.next()) {
            _value = _transform(_source.current());
            return true;
        }
        return false;
    }

    ## Returns the transformed element the last successful `next()` produced.
    ##
    ## @returns the current element
    current(): U {
        return _value;
    }
}

extend MapIterator<T, U> with Iterator<U>;

## The iterator `Iterator.filter` returns: the elements of the source
## iterator that the test function accepts.
##
## @typeParam T the type of the elements
## @see Iterator.filter
[Value]
export struct FilterIterator<T> {
    ## The iterator whose elements are tested.
    Iterator<T> _source;
    ## The test an element must pass.
    (T) => bool _keep;

    ## Makes an iterator over the elements of `source` that `keep` accepts.
    ##
    ## @param source the iterator to filter
    ## @param keep the test an element must pass
    construct(source: Iterator<T>, keep: (T) => bool) {
        _source = source;
        _keep = keep;
    }

    ## Advances to the next element that the test function accepts.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        while (_source.next()) {
            if (_keep(_source.current())) {
                return true;
            }
        }
        return false;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    current(): T {
        return _source.current();
    }
}

extend FilterIterator<T> with Iterator<T>;

## The iterator `Iterator.enumerate` returns: each element of the source
## iterator, paired with its position.
##
## @typeParam T the type of the source's elements
## @typeParam TIndex the integer type of the positions
## @see Iterator.enumerate
[Value]
export struct EnumerateIterator<T, TIndex> {
    ## The iterator whose elements are numbered.
    Iterator<T> _source;
    ## How many elements `next()` has moved past; the current element's index plus one.
    TIndex _count;

    ## Makes an iterator over the elements of `source`, numbered from 0.
    ##
    ## @param source the iterator to number
    construct(source: Iterator<T>) {
        _source = source;
    }

    ## Advances to the next element.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        if (_source.next()) {
            _count += 1;
            return true;
        }
        return false;
    }

    ## Returns the element the last successful `next()` moved to, with its
    ## index.
    ##
    ## @returns the current `(index, element)` pair
    current(): (TIndex, T) {
        return (_count - 1, _source.current());
    }
}

extend EnumerateIterator<T, TIndex> with Iterator<(TIndex, T)>;

## The iterator `Iterator.zip` returns: the elements of two iterators,
## paired in step, until either runs out.
##
## @typeParam T the type of the first iterator's elements
## @typeParam U the type of the second iterator's elements
## @see Iterator.zip
[Value]
export struct ZipIterator<T, U> {
    ## The iterator giving the first half of each pair.
    Iterator<T> _first;
    ## The iterator giving the second half of each pair.
    Iterator<U> _second;

    ## Makes an iterator over the elements of `first` and `second`, paired.
    ##
    ## @param first the iterator giving the first half of each pair
    ## @param second the iterator giving the second half of each pair
    construct(first: Iterator<T>, second: Iterator<U>) {
        _first = first;
        _second = second;
    }

    ## Advances both iterators. `second` is not advanced once `first` has
    ## run out.
    ##
    ## @returns true if both have a current element, false when either is exhausted
    next(): bool {
        return _first.next() && _second.next();
    }

    ## Returns the pair the last successful `next()` moved to.
    ##
    ## @returns the current `(first element, second element)` pair
    current(): (T, U) {
        return (_first.current(), _second.current());
    }
}

extend ZipIterator<T, U> with Iterator<(T, U)>;

## Something that hands out an `Iterator<T>` over its elements, such as
## `Array<T>` and `String` (which yields one code point at a time, as a
## `String`).
##
## `for (var x in source)` calls `source.iterate()` once, then drives the
## returned iterator with `next()` and `current()`. When a type declares both
## `iterate()` and `next()`/`current()`, the loop uses `iterate()`.
##
## @typeParam T the type of the elements produced
## @example
##     var nums = Array<int>();
##     nums.append(1);
##     nums.append(2);
##     var total = 0;
##     for (var x in nums) {
##         total = total + x;
##     }
## @see Iterator
export trait Iterable<T> {
    ## Returns a new iterator positioned before the first element.
    ##
    ## The result may be any type that satisfies `Iterator<T>` (for example
    ## `ArrayIterator<T>`); each call starts a fresh, independent pass.
    ##
    ## @returns an iterator over the elements
    iterate(): Iterator<T>;
}
