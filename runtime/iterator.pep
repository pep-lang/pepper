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
#
# Every type that declares Iterator<T> gets a copy of each non-generic
# default method, checked and compiled whether called or not, which slows
# every build that uses many iterator types. So every default but `filter`
# and `to_array` is generic (`<TElement=T>` when nothing else is): each
# compiles only where called, and a default that returns an adapter type,
# or needs `+` or `compare`, could not be non-generic anyway.

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
    ## @typeParam TElement the element type, `T` by default
    ## @param count the most elements to yield
    ## @returns a `TakeIterator<T>` over the first `count` elements
    ## @example
    ##     var firsts = (1..>10).take(3).to_array();   # [1, 2, 3]
    take<TElement=T>(count: ulong): TakeIterator<TElement> {
        return TakeIterator<TElement>(this, count);
    }

    ## Returns an iterator over the elements after the first `count`.
    ##
    ## Lazy, like `map`: the first `next()` of the result passes over `count`
    ## elements. When there are no more than `count`, it yields nothing.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param count how many elements to pass over
    ## @returns a `SkipIterator<T>` over the rest of the elements
    ## @example
    ##     var rest = (1..>5).skip(3).to_array();   # [4, 5]
    skip<TElement=T>(count: ulong): SkipIterator<TElement> {
        return SkipIterator<TElement>(this, count);
    }

    ## Returns an iterator over this iterator's elements, then `other`'s.
    ##
    ## Lazy, like `map`: `other` is not advanced until this iterator runs
    ## out. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param other the iterator whose elements follow
    ## @returns a `ChainIterator<T>` over both iterators' elements
    ## @example
    ##     var both = (1..>2).chain(7..>8).to_array();   # [1, 2, 7, 8]
    chain<TElement=T>(other: Iterator<T>): ChainIterator<TElement> {
        return ChainIterator<TElement>(this, other);
    }

    ## Returns an iterator over the elements of the iterators `transform`
    ## returns, one source element after another.
    ##
    ## Lazy, like `map`: `transform` runs on a source element only once the
    ## iterator from the one before it has run out. Every type that declares
    ## `Iterator<T>` gets this method.
    ##
    ## @typeParam U the type of the elements of the iterators `transform` returns
    ## @param transform the function that turns each element into an iterator
    ## @returns a `FlatMapIterator<T, U>` over the elements of those iterators
    ## @example
    ##     var words = ["ab", "cd"];
    ##     var letters = words.iterate().flat_map((w) => w.iterate()).to_array();   # a, b, c, d
    flat_map<U>(transform: (T) => Iterator<U>): FlatMapIterator<T, U> {
        return FlatMapIterator<T, U>(MapIterator<T, Iterator<U>>(this, transform));
    }

    ## Returns an iterator over the leading elements for which `keep`
    ## returns true. It stops at the first element that fails.
    ##
    ## Lazy, like `map`: the failing element is read from this iterator but
    ## not yielded. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param keep the test the leading elements pass
    ## @returns a `TakeWhileIterator<T>` over the leading elements that pass
    ## @example
    ##     var small = [1, 2, 7, 3].iterate().take_while((n) => n < 5).to_array();   # [1, 2]
    take_while<TElement=T>(keep: (T) => bool): TakeWhileIterator<TElement> {
        return TakeWhileIterator<TElement>(this, keep);
    }

    ## Returns an iterator over the elements from the first one for which
    ## `skip` returns false.
    ##
    ## Lazy, like `map`: the first `next()` of the result passes over the
    ## leading elements that `skip` accepts, and later elements are not
    ## tested. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param skip the test the leading elements to pass over meet
    ## @returns a `SkipWhileIterator<T>` over the rest of the elements
    ## @example
    ##     var rest = [1, 2, 7, 3].iterate().skip_while((n) => n < 5).to_array();   # [7, 3]
    skip_while<TElement=T>(skip: (T) => bool): SkipWhileIterator<TElement> {
        return SkipWhileIterator<TElement>(this, skip);
    }

    ## Returns an iterator over the first element, then every `step`th one
    ## after it.
    ##
    ## Lazy, like `map`. `step_by(1)` yields every element. Every type that
    ## declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param step how far apart the yielded elements are
    ## @returns a `StepByIterator<T>` over every `step`th element
    ## @panics if `step` is 0 ("step_by step must be positive")
    ## @example
    ##     var evens = (0..10).step_by(2).to_array();   # [0, 2, 4, 6, 8]
    step_by<TElement=T>(step: ulong): StepByIterator<TElement> {
        return StepByIterator<TElement>(this, step);
    }

    ## Returns an iterator over the same elements that can also look at the
    ## next one without moving to it, with `peek()`.
    ##
    ## Lazy, like `map`. Every type that declares `Iterator<T>` gets this
    ## method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @returns a `PeekableIterator<T>` over the elements
    ## @example
    ##     var it = [1, 2].iterate().peekable();
    ##     var ahead = it.peek();   # Value(1); `it` has not moved
    peekable<TElement=T>(): PeekableIterator<TElement> {
        return PeekableIterator<TElement>(this);
    }

    ## Returns an iterator over the elements in arrays of `size`, in order.
    ## The last array is shorter when the elements do not divide evenly.
    ##
    ## Lazy, like `map`: each array is filled as the result is advanced. Each
    ## is a new `Array`, so keeping one is safe. Every type that declares
    ## `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param size the most elements each array holds
    ## @returns a `ChunksIterator<T>` over arrays of up to `size` elements
    ## @panics if `size` is 0 ("chunks size must be positive")
    ## @example
    ##     var rows = (1..>5).chunks(2).to_array();   # [[1, 2], [3, 4], [5]]
    chunks<TElement=T>(size: ulong): ChunksIterator<TElement> {
        return ChunksIterator<TElement>(this, size);
    }

    ## Returns an iterator over every run of `size` consecutive elements:
    ## the first `size`, then the run starting one later, and so on. With
    ## fewer than `size` elements it yields nothing.
    ##
    ## Lazy, like `map`. Each run is a new `Array`, so keeping one is safe.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param size how many elements each run holds
    ## @returns a `WindowsIterator<T>` over arrays of `size` elements
    ## @panics if `size` is 0 ("windows size must be positive")
    ## @example
    ##     var pairs = (1..>4).windows(2).to_array();   # [[1, 2], [2, 3], [3, 4]]
    windows<TElement=T>(size: ulong): WindowsIterator<TElement> {
        return WindowsIterator<TElement>(this, size);
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
    ## @typeParam TElement the element type, `T` by default
    ## @returns the number of elements, possibly 0
    ## @example
    ##     var evens = (1..>10).filter((n) => n % 2 == 0).count();   # 5
    count<TElement=T>(): ulong {
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
    ## @typeParam TElement the element type, `T` by default
    ## @param test the test to apply
    ## @returns true when an element passes, false when none does or there are none
    ## @example
    ##     var has_even = [1, 3, 4].iterate().any((n) => n % 2 == 0);   # true
    any<TElement=T>(test: (T) => bool): bool {
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
    ## @typeParam TElement the element type, `T` by default
    ## @param test the test to apply
    ## @returns true when every element passes, including when there are none
    ## @example
    ##     var all_small = [1, 3, 4].iterate().all((n) => n < 10);   # true
    all<TElement=T>(test: (T) => bool): bool {
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
    ## @typeParam TElement the element type, `T` by default
    ## @param test the test an element must pass
    ## @returns the first element that passes, or Empty when none does
    ## @example
    ##     var first_even = [1, 3, 4, 6].iterate().find((n) => n % 2 == 0);   # Value(4)
    find<TElement=T>(test: (T) => bool): T? {
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

    ## Combines the elements with `combine`, starting from the first:
    ## `combine(first, second)`, then `combine` of that and the third, and so
    ## on. It is `fold` with the first element as the initial value.
    ##
    ## Runs the iteration to the end, on a copy of the iterator, like
    ## `to_array`. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param combine the function that folds one more element into the value so far
    ## @returns the combined value, the only element when there is one, or Empty when there are none
    ## @example
    ##     var longest = ["a", "abc", "ab"].iterate().reduce((a, b) => b.size > a.size ? b : a);   # Value("abc")
    reduce<TElement=T>(combine: (T, T) => T): T? {
        Iterator<T> source = this;
        if (!source.next()) {
            return Optional<T>.Empty;
        }
        var result = source.current();
        while (source.next()) {
            result = combine(result, source.current());
        }
        return Optional<T>.Value(result);
    }

    ## Returns the position of the first element for which `test` returns
    ## true, counting from 0.
    ##
    ## Stops at that element, on a copy of the iterator, like `to_array`.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param test the test an element must pass
    ## @returns the position of the first element that passes, or Empty when none does
    ## @example
    ##     var at = [1, 3, 4].iterate().position((n) => n % 2 == 0);   # Value(2)
    position<TElement=T>(test: (T) => bool): ulong? {
        Iterator<T> source = this;
        ulong index = 0;
        while (source.next()) {
            if (test(source.current())) {
                return Optional<ulong>.Value(index);
            }
            index += 1;
        }
        return Optional<ulong>.Empty;
    }

    ## Returns the last element.
    ##
    ## Runs the iteration to the end, on a copy of the iterator, like
    ## `to_array`. Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @returns the last element, or Empty when there are none
    ## @example
    ##     var final = (1..>4).last();   # Value(4)
    last<TElement=T>(): T? {
        Iterator<T> source = this;
        var result = Optional<T>.Empty;
        while (source.next()) {
            result = Optional<T>.Value(source.current());
        }
        return result;
    }

    ## Calls `action` with each element, in order.
    ##
    ## Runs the iteration to the end, on a copy of the iterator, like
    ## `to_array`; use a `for` loop where `break` or `return` is needed.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param action the function called with each element
    ## @example
    ##     var names = Array<String>();
    ##     var people = ["Ada", "Bo"];
    ##     people.iterate().for_each((name) => names.append(name));
    for_each<TElement=T>(action: (T) => void) {
        Iterator<T> source = this;
        while (source.next()) {
            action(source.current());
        }
    }

    ## Returns the smallest element by `compare`, which returns a negative
    ## number, zero or a positive number as its first argument sorts before,
    ## with or after its second, as `Array.sort`'s does.
    ##
    ## When several elements sort together, returns the first. Runs the
    ## iteration to the end, on a copy of the iterator, like `to_array`.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param compare the order of two elements
    ## @returns the smallest element, or Empty when there are none
    ## @example
    ##     var shortest = ["abc", "a"].iterate().min_by((a, b) => a.size.compare(b.size));   # Value("a")
    min_by<TElement=T>(compare: (T, T) => int): T? {
        Iterator<T> source = this;
        if (!source.next()) {
            return Optional<T>.Empty;
        }
        var best = source.current();
        while (source.next()) {
            var element = source.current();
            if (compare(element, best) < 0) {
                best = element;
            }
        }
        return Optional<T>.Value(best);
    }

    ## Returns the largest element by `compare`, which returns a negative
    ## number, zero or a positive number as its first argument sorts before,
    ## with or after its second, as `Array.sort`'s does.
    ##
    ## When several elements sort together, returns the first. Runs the
    ## iteration to the end, on a copy of the iterator, like `to_array`.
    ## Every type that declares `Iterator<T>` gets this method.
    ##
    ## @typeParam TElement the element type, `T` by default
    ## @param compare the order of two elements
    ## @returns the largest element, or Empty when there are none
    ## @example
    ##     var longest = ["abc", "a"].iterate().max_by((a, b) => a.size.compare(b.size));   # Value("abc")
    max_by<TElement=T>(compare: (T, T) => int): T? {
        Iterator<T> source = this;
        if (!source.next()) {
            return Optional<T>.Empty;
        }
        var best = source.current();
        while (source.next()) {
            var element = source.current();
            if (compare(element, best) > 0) {
                best = element;
            }
        }
        return Optional<T>.Value(best);
    }

    ## Returns a new `HashSet` holding the remaining elements, each once.
    ##
    ## For element types a `HashSet` can hold. Runs the iteration to the end,
    ## on a copy of the iterator, like `to_array`. Every type that declares
    ## `Iterator<T>` gets this method.
    ##
    ## @typeParam K the type the set holds, `T` by default
    ## @returns the distinct elements, possibly none
    ## @example
    ##     var distinct = [1, 2, 1].iterate().to_set();   # holds 1 and 2
    to_set<K=T>(): HashSet<K> {
        Iterator<T> source = this;
        var result = HashSet<K>();
        while (source.next()) {
            result.insert(source.current());
        }
        return result;
    }

    ## Returns a new `HashMap` from the remaining elements, which are
    ## `(key, value)` tuples. A later element with a key already present
    ## replaces its value.
    ##
    ## For tuple elements; name the key and value types. Runs the iteration
    ## to the end, on a copy of the iterator, like `to_array`. Every type that
    ## declares `Iterator<T>` gets this method.
    ##
    ## @typeParam K the type of the keys
    ## @typeParam V the type of the values
    ## @returns the map, possibly empty
    ## @example
    ##     var ages = [("Ada", 36), ("Bo", 12)].iterate().to_map<String, int>();   # ages["Bo"] == 12
    to_map<K, V>(): HashMap<K, V> {
        Iterator<T> source = this;
        var result = HashMap<K, V>();
        while (source.next()) {
            var entry = source.current();
            result[entry.0] = entry.1;
        }
        return result;
    }

    ## Returns the remaining elements, which are `String`s, with `separator`
    ## between each two, as `String.join` does for an array.
    ##
    ## For `String` elements. Runs the iteration to the end, on a copy of the
    ## iterator, like `to_array`. Every type that declares `Iterator<T>` gets
    ## this method.
    ##
    ## @typeParam TText the element type, `T` by default
    ## @param separator the text put between each two elements
    ## @returns the joined text, or `""` when there are no elements
    ## @example
    ##     var ages = [36, 12].iterate().map((n) => $"{n}").join(", ");   # "36, 12"
    join<TText=T>(separator: String): String {
        Iterator<T> source = this;
        var parts = Array<String>();
        while (source.next()) {
            TText part = source.current();
            parts.append(part);
        }
        return separator.join(parts);
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

## The iterator `Iterator.flat_map` returns: the elements of the iterators
## the transform function returns for each source element, in order.
##
## @typeParam T the type of the source's elements
## @typeParam U the type of the elements produced
## @see Iterator.flat_map
[Value]
export struct FlatMapIterator<T, U> {
    # No member names `(T) => Iterator<U>`: the runtime must build with the
    # previous published compiler (stage 0), and compilers without the
    # fix reject that type in a generic struct ("unknown type name 'U'").
    ## The iterators to yield the elements of, one per source element.
    MapIterator<T, Iterator<U>> _source;
    ## The iterator from the current source element, Empty before the first.
    Iterator<U>? _inner;

    ## Makes an iterator over the elements of the iterators `source` yields.
    ##
    ## @param source the source iterator, mapped to an iterator per element
    construct(source: MapIterator<T, Iterator<U>>) {
        _source = source;
    }

    ## Advances to the next element of the current inner iterator, moving to
    ## the next source element's iterator each time one runs out.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        while (true) {
            if (_inner is Value(inner)) {
                if (inner.next()) {
                    return true;
                }
            }
            if (!_source.next()) {
                return false;
            }
            _inner = Optional<Iterator<U>>.Value(_source.current());
        }
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    ## @panics if `next()` has not moved to an element
    current(): U {
        return _inner.value().current();
    }
}

extend FlatMapIterator<T, U> with Iterator<U>;

## The iterator `Iterator.take_while` returns: the leading elements of the
## source iterator that the test function accepts.
##
## @typeParam T the type of the elements
## @see Iterator.take_while
[Value]
export struct TakeWhileIterator<T> {
    ## The iterator whose leading elements are yielded.
    Iterator<T> _source;
    ## The test the leading elements pass.
    (T) => bool _keep;
    ## Whether an element failed the test, or the source ran out.
    bool _done;

    ## Makes an iterator over the leading elements of `source` that `keep`
    ## accepts.
    ##
    ## @param source the iterator to take from
    ## @param keep the test the leading elements pass
    construct(source: Iterator<T>, keep: (T) => bool) {
        _source = source;
        _keep = keep;
    }

    ## Advances to the next element, unless it or an earlier one failed the
    ## test.
    ##
    ## @returns true if there is a current element, false once an element fails or the source is exhausted
    next(): bool {
        if (_done) {
            return false;
        }
        if (_source.next() && _keep(_source.current())) {
            return true;
        }
        _done = true;
        return false;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    current(): T {
        return _source.current();
    }
}

extend TakeWhileIterator<T> with Iterator<T>;

## The iterator `Iterator.skip_while` returns: the elements of the source
## iterator from the first one the test function rejects.
##
## @typeParam T the type of the elements
## @see Iterator.skip_while
[Value]
export struct SkipWhileIterator<T> {
    ## The iterator whose later elements are yielded.
    Iterator<T> _source;
    ## The test the leading elements to pass over meet.
    (T) => bool _skip;
    ## Whether the leading elements were passed over.
    bool _started;

    ## Makes an iterator over the elements of `source` from the first one
    ## `skip` rejects.
    ##
    ## @param source the iterator to skip into
    ## @param skip the test the leading elements to pass over meet
    construct(source: Iterator<T>, skip: (T) => bool) {
        _source = source;
        _skip = skip;
    }

    ## Advances to the next element, passing over the leading elements the
    ## test accepts on the first call.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        if (_started) {
            return _source.next();
        }
        _started = true;
        while (_source.next()) {
            if (!_skip(_source.current())) {
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

extend SkipWhileIterator<T> with Iterator<T>;

## The iterator `Iterator.step_by` returns: the first element of the source
## iterator, then every `step`th one after it.
##
## @typeParam T the type of the elements
## @see Iterator.step_by
[Value]
export struct StepByIterator<T> {
    ## The iterator whose elements are stepped through.
    Iterator<T> _source;
    ## How far apart the yielded elements are.
    ulong _step;
    ## Whether the first element was yielded.
    bool _started;

    ## Makes an iterator over the first element of `source` and every
    ## `step`th one after it.
    ##
    ## @param source the iterator to step through
    ## @param step how far apart the yielded elements are
    ## @panics if `step` is 0 ("step_by step must be positive")
    construct(source: Iterator<T>, step: ulong) {
        assert(step > 0, "step_by step must be positive");
        _source = source;
        _step = step;
    }

    ## Advances to the first element, then `step` elements at a time.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        if (!_started) {
            _started = true;
            return _source.next();
        }
        ulong moved = 0;
        while (moved < _step) {
            if (!_source.next()) {
                return false;
            }
            moved += 1;
        }
        return true;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    current(): T {
        return _source.current();
    }
}

extend StepByIterator<T> with Iterator<T>;

## The iterator `Iterator.peekable` returns: the elements of the source
## iterator, with `peek()` to look at the next one without moving to it.
##
## @typeParam T the type of the elements
## @see Iterator.peekable
[Value]
export struct PeekableIterator<T> {
    ## The iterator whose elements are yielded.
    Iterator<T> _source;
    ## The element the last successful `next()` moved to.
    T _current;
    ## The next element, read from the source by `peek()` and not yet yielded.
    T? _ahead;

    ## Makes an iterator over the elements of `source` that can peek.
    ##
    ## @param source the iterator to yield from
    construct(source: Iterator<T>) {
        _source = source;
    }

    ## Advances to the next element: the one `peek()` returned, if any.
    ##
    ## @returns true if there is a current element, false when the source is exhausted
    next(): bool {
        if (_ahead is Value(ahead)) {
            _current = ahead;
            _ahead = Optional<T>.Empty;
            return true;
        }
        if (!_source.next()) {
            return false;
        }
        _current = _source.current();
        return true;
    }

    ## Returns the element the last successful `next()` moved to.
    ##
    ## @returns the current element
    current(): T {
        return _current;
    }

    ## Returns the element the next `next()` will move to, without moving.
    ##
    ## @returns the next element, or Empty when there are no more
    ## @example
    ##     var it = [1, 2].iterate().peekable();
    ##     it.next();               # at 1
    ##     var ahead = it.peek();   # Value(2), still at 1
    peek(): T? {
        if (_ahead.is_value()) {
            return _ahead;
        }
        if (_source.next()) {
            _ahead = Optional<T>.Value(_source.current());
        }
        return _ahead;
    }
}

extend PeekableIterator<T> with Iterator<T>;

## The iterator `Iterator.chunks` returns: the elements of the source
## iterator in arrays of up to `size`.
##
## @typeParam T the type of the elements
## @see Iterator.chunks
[Value]
export struct ChunksIterator<T> {
    ## The iterator whose elements are grouped.
    Iterator<T> _source;
    ## The most elements each array holds.
    ulong _size;
    ## The array the last successful `next()` filled.
    Array<T> _chunk;

    ## Makes an iterator over the elements of `source` in arrays of up to
    ## `size`.
    ##
    ## @param source the iterator to group
    ## @param size the most elements each array holds
    ## @panics if `size` is 0 ("chunks size must be positive")
    construct(source: Iterator<T>, size: ulong) {
        assert(size > 0, "chunks size must be positive");
        _source = source;
        _size = size;
        _chunk = Array<T>();
    }

    ## Fills a new array with up to `size` more elements.
    ##
    ## @returns true if there is a current array, false when the source is exhausted
    next(): bool {
        var chunk = Array<T>();
        while (chunk.count < _size && _source.next()) {
            chunk.append(_source.current());
        }
        _chunk = chunk;
        return chunk.count > 0;
    }

    ## Returns the array the last successful `next()` filled.
    ##
    ## @returns the current array
    current(): Array<T> {
        return _chunk;
    }
}

extend ChunksIterator<T> with Iterator<Array<T>>;

## The iterator `Iterator.windows` returns: every run of `size` consecutive
## elements of the source iterator.
##
## @typeParam T the type of the elements
## @see Iterator.windows
[Value]
export struct WindowsIterator<T> {
    ## The iterator whose elements are grouped.
    Iterator<T> _source;
    ## How many elements each run holds.
    ulong _size;
    ## The run the last successful `next()` made.
    Array<T> _window;

    ## Makes an iterator over every run of `size` consecutive elements of
    ## `source`.
    ##
    ## @param source the iterator to group
    ## @param size how many elements each run holds
    ## @panics if `size` is 0 ("windows size must be positive")
    construct(source: Iterator<T>, size: ulong) {
        assert(size > 0, "windows size must be positive");
        _source = source;
        _size = size;
        _window = Array<T>();
    }

    ## Makes a new run: the last one's elements after its first, then
    ## enough more to fill it.
    ##
    ## @returns true if there is a current run, false when the source is exhausted
    next(): bool {
        var window = Array<T>();
        ulong index = 1;
        while (_window.count == _size && index < _size) {
            window.append(_window[index]);
            index += 1;
        }
        while (window.count < _size) {
            if (!_source.next()) {
                return false;
            }
            window.append(_source.current());
        }
        _window = window;
        return true;
    }

    ## Returns the run the last successful `next()` made.
    ##
    ## @returns the current run
    current(): Array<T> {
        return _window;
    }
}

extend WindowsIterator<T> with Iterator<Array<T>>;

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
