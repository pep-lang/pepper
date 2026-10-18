## Ordering: `Comparable`, the trait of types whose values sort in one
## order, which every number type, `char` and `String` declare.

## A type whose values have one order: `compare` says whether a value sorts
## before, with or after another.
##
## Declaring it (`extend Version with Comparable;`) gives the type `<`,
## `<=`, `>` and `>=` and the methods `min`, `max` and `clamp`, each
## written in terms of `compare`, unless the type declares its own. A
## generic function asks for an order with `T: Comparable`.
##
## `compare` returns a negative number when this value sorts before
## `other`, zero when the two sort together, and a positive number when it
## sorts after. The order must be total and consistent: two calls with the
## same values give the same answer, and `a.compare(b)` has the opposite
## sign of `b.compare(a)`. `Map`, `Set` and sorting rely on that.
##
## `float` and `double` are `Comparable` with a total order: NaN sorts
## after every number and with every other NaN, and `-0.0` with `0.0`.
## Their `<` and `>` keep IEEE behavior (false whenever NaN takes part),
## while `compare`, `clamp` and `Map` keys follow the total order.
##
## @example
##     struct Version {
##         var major: int;
##         var minor: int;
##
##         construct(this.major = 0, this.minor = 0) {}
##
##         compare(other: Version): int {
##             var order = major.compare(other.major);
##             if (order != 0) {
##                 return order;
##             }
##             return minor.compare(other.minor);
##         }
##     }
##
##     extend Version with Comparable;
##
##     assert(Version(1, 2) < Version(1, 10), "by minor");
##     assert(Version(2, 0).max(Version(1, 9)).major == 2, "max");
export trait Comparable {
    ## Returns the order of this value and `other`.
    ##
    ## @param other the value to compare with
    ## @returns a negative number, zero or a positive number as this value
    ##   sorts before, with or after `other`
    compare(other: this): int;

    ## Returns whether this value sorts before `other`.
    ##
    ## @param other the value to compare with
    ## @returns true when `compare(other) < 0`
    <(other: this): bool {
        return compare(other) < 0;
    }

    ## Returns whether this value sorts before or with `other`.
    ##
    ## @param other the value to compare with
    ## @returns true when `compare(other) <= 0`
    <=(other: this): bool {
        return compare(other) <= 0;
    }

    ## Returns whether this value sorts after `other`.
    ##
    ## @param other the value to compare with
    ## @returns true when `compare(other) > 0`
    >(other: this): bool {
        return compare(other) > 0;
    }

    ## Returns whether this value sorts after or with `other`.
    ##
    ## @param other the value to compare with
    ## @returns true when `compare(other) >= 0`
    >=(other: this): bool {
        return compare(other) >= 0;
    }

    ## Returns the one of this value and `other` that sorts first.
    ##
    ## @param other the value to compare with
    ## @returns this value when it sorts before or with `other`, else `other`
    ## @example
    ##     assert("pear".min("apple") == "apple", "apple sorts first");
    min(other: this): this {
        return compare(other) <= 0 ? this : other;
    }

    ## Returns the one of this value and `other` that sorts last.
    ##
    ## @param other the value to compare with
    ## @returns this value when it sorts after or with `other`, else `other`
    ## @example
    ##     assert("pear".max("apple") == "pear", "pear sorts last");
    max(other: this): this {
        return compare(other) >= 0 ? this : other;
    }

    ## Returns this value limited to the range from `low` to `high`.
    ##
    ## @param low the lowest value to return
    ## @param high the highest value to return
    ## @returns `low` when this value sorts before it, `high` when this value
    ##   sorts after it, else this value
    ## @panics if `low` sorts after `high` ("clamp range is empty")
    ## @example
    ##     assert((15).clamp(0, 10) == 10, "too high");
    ##     assert((-3).clamp(0, 10) == 0, "too low");
    ##     assert((4).clamp(0, 10) == 4, "in range");
    clamp(low: this, high: this): this {
        assert(low.compare(high) <= 0, "clamp range is empty");
        if (compare(low) < 0) {
            return low;
        }
        if (compare(high) > 0) {
            return high;
        }
        return this;
    }
}

## `char` values sort by value.
export extend char with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: char): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `byte` values sort by value.
export extend byte with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: byte): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `short` values sort by value.
export extend short with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: short): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `ushort` values sort by value.
export extend ushort with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: ushort): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `int` values sort by value.
export extend int with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: int): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `uint` values sort by value.
export extend uint with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: uint): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `long` values sort by value.
export extend long with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: long): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `ulong` values sort by value.
export extend ulong with Comparable {
    ## Returns the order of this value and `other`: -1, 0 or 1 as this
    ## value is less than, equal to or greater than `other`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1
    compare(other: ulong): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        return 0;
    }
}

## `float` values sort by value, with NaN after every number.
export extend float with Comparable {
    ## Returns the order of this value and `other` in a total order: by
    ## value, with NaN after every number and equal to every NaN, and
    ## `-0.0` equal to `0.0`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1 as this value sorts before, with or after `other`
    ## @example
    ##     var nan = (0.0 / 0.0) as float;
    ##     assert((1.0 as float).compare(nan) < 0, "NaN sorts last");
    ##     assert(nan.compare(nan) == 0, "NaNs sort together");
    compare(other: float): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        if (this == other) {
            return 0;
        }
        # One or both are NaN, the only value not equal to itself.
        var nan = this != this;
        if (nan == (other != other)) {
            return 0;
        }
        return nan ? 1 : -1;
    }
}

## `double` values sort by value, with NaN after every number.
export extend double with Comparable {
    ## Returns the order of this value and `other` in a total order: by
    ## value, with NaN after every number and equal to every NaN, and
    ## `-0.0` equal to `0.0`.
    ##
    ## @param other the value to compare with
    ## @returns -1, 0 or 1 as this value sorts before, with or after `other`
    ## @example
    ##     var nan = 0.0 / 0.0;
    ##     assert((1.0).compare(nan) < 0, "NaN sorts last");
    ##     assert(nan.compare(nan) == 0, "NaNs sort together");
    compare(other: double): int {
        if (this < other) {
            return -1;
        }
        if (this > other) {
            return 1;
        }
        if (this == other) {
            return 0;
        }
        # One or both are NaN, the only value not equal to itself.
        var nan = this != this;
        if (nan == (other != other)) {
            return 0;
        }
        return nan ? 1 : -1;
    }
}
