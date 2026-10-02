## Ranges of numbers: `a..b` and `a..>b`.
##
## `a..b` (half-open) holds `a` up to but not including `b`; `a..>b`
## (closed) includes `b`. Both make a `Range<T>`, a value that a `for` loop
## steps through without allocating:
##
##     for (var i in 0..count) { ... }   # 0, 1, ..., count - 1
##     for (var i in 1..>10) { ... }     # 1, 2, ..., 10

## A run of consecutive numbers, from `start` up to `end`, as `a..b` and
## `a..>b` make it.
##
## A range is an iterator: `next()` steps from `start` up by one, and a
## `for` loop over a range is a counting loop. A range whose `start` is past
## its end yields nothing. A closed range ending at the largest value of its
## type (`0..>255` as `byte`) stops there without overflowing.
##
## Ranges are [value structs](../language/value-structs.md): copying one
## copies its position, and looping over a range stored in a variable
## advances that variable.
##
## @typeParam T the number type, inferred from the bounds (`0..n` with a `ulong` `n` is a `Range<ulong>`)
## @example
##     var total = 0;
##     for (var i in 1..>4) {
##         total += i;   # 1 + 2 + 3 + 4
##     }
##     var r = 0..10;
##     assert(r.contains(9) && !r.contains(10), "half-open");
[Value]
export struct Range<T> {
    ## The first number of the range.
    T start;
    ## The bound the range stops at: the last number when `inclusive`, else one past it.
    T end;
    ## Whether `end` is part of the range: true for `a..>b`, false for `a..b`.
    bool inclusive;
    ## The current number, once `next()` has moved to one.
    T _value;
    ## 0 before the first `next()`, 1 while there is a current number, 2 once past the end.
    int _state;

    ## Makes the range from `start` to `end`, as `start..end` (or
    ## `start..>end` when `inclusive`).
    ##
    ## @param start the first number
    ## @param end the bound: one past the last number, or the last number when `inclusive`
    ## @param inclusive whether `end` is part of the range
    construct(start: T, end: T, inclusive: bool = false) {
        this.start = start;
        this.end = end;
        this.inclusive = inclusive;
        _value = start;
    }

    ## Advances to the next number: `start` on the first call, then one
    ## more each time.
    ##
    ## Once it returns false it keeps returning false.
    ##
    ## @returns true if there is a current number, false once past the end
    next(): bool {
        if (_state == 2) {
            return false;
        }
        if (_state == 0) {
            _state = 1;
            _value = start;
        } else if (_value == end) {
            # Only a closed range reaches its end; stepping past it could overflow.
            _state = 2;
            return false;
        } else {
            _value = _value + 1;
        }
        if (_value < end || (inclusive && _value == end)) {
            return true;
        }
        _state = 2;
        return false;
    }

    ## Returns the number the last successful `next()` moved to.
    ##
    ## @returns the current number
    ## @panics if `next()` was never called ("Range.current() before next()")
    ## @panics if `next()` already returned false ("Range.current() past the end")
    current(): T {
        assert(_state != 0, "Range.current() before next()");
        assert(_state != 2, "Range.current() past the end");
        return _value;
    }

    ## Returns whether `value` lies in the range, whatever the iteration has
    ## reached.
    ##
    ## @param value the number to test
    ## @returns true if `start <= value` and `value` is before `end` (or equal to it, for a closed range)
    contains(value: T): bool {
        if (value < start) {
            return false;
        }
        if (inclusive) {
            return value <= end;
        }
        return value < end;
    }

    ## Whether the range holds no numbers, whatever the iteration has
    ## reached.
    var is_empty: bool {
        get {
            return !contains(start);
        }
    }
}

extend Range<T> with Iterator<T>;

# `a..b` is `_range(a, b, false)` and `a..>b` is `_range(a, b, true)` (the
# sema builder writes the call), so the bounds infer `T`.
export _range<T>(start: T, end: T, inclusive: bool): Range<T> {
    return Range<T>(start, end, inclusive);
}
