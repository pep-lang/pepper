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
# Traits are not checked yet, so the loop goes by the methods a type has;
# declaring the trait (`extend Foo with Iterator<int>`) documents the intent.

# Something a `for` loop can step through, one element at a time.
export trait Iterator<T> {
    # Advance to the next element: true if there is one. Once it returns
    # false it keeps returning false.
    bool next();

    # The element the last successful next() moved to. Calling it before the
    # first next(), or after next() returned false, panics.
    T current();
}

# Something that hands out an Iterator<T> over its elements (Array<T>,
# String). `iterate()` returns any type that satisfies Iterator<T>.
export trait Iterable<T> {
    iterate(): Iterator<T>;
}
