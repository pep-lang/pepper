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
}

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
