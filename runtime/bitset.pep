## `BitSet`: a set of small non-negative integers, stored one bit each.

import "array";
import "copy";
import "hash";

## A growable set of non-negative integers, one bit per possible member.
##
## Member `n` is bit `n % 64` of word `n / 64`, so a set whose largest
## member is `m` takes about `m / 8` bytes whatever its count: a good fit for
## visited flags, masks, and sieve or liveness tables over small integers.
## For sparse or large integers use a `HashSet<int>`.
##
## `insert` grows the set as needed and `reserve` grows it ahead of time;
## the set never shrinks. `contains` and `remove` take O(1); `count`,
## `is_empty`, `==`, `hash`, iteration and the set operations take
## O(capacity / 64).
##
## Two sets are `==` when they hold the same members, whatever their
## capacity, and equal sets hash equally, so a `BitSet` works as a
## `HashMap` or `HashSet` key. A `BitSet` is not `[Shared]`: keep each one
## on one thread.
##
## @example
##     BitSet primes = [2, 3, 5, 7];
##     primes.insert(11);
##     assert(primes.contains(5), "a member");
##     assert(primes.count == 5, "five members");
##     for (var p in primes) {
##         print($"{p}");   # 2, 3, 5, 7, 11
##     }
export struct BitSet {
    ## One bit per possible member: bit `n % 64` of word `n / 64`. Internal.
    ulong[] _words;

    ## Creates an empty set with room for the members `0` up to (not
    ## including) `capacity` before it grows.
    ##
    ## @param capacity the number of members to make room for; rounded up to
    ##   a multiple of 64
    ## @panics if `capacity` is negative
    construct(capacity: int = 0) {
        reserve(capacity);
    }

    ## Creates a set holding each element of `items`.
    ##
    ## The constructor is `[Implicit]`: an array converts to a set wherever
    ## a set is expected, so an array literal can initialize one.
    ##
    ## @param items the members to insert; duplicates are kept once
    ## @panics if an element of `items` is negative
    ## @example
    ##     BitSet flags = [1, 4, 4];
    ##     assert(flags.count == 2, "4 is kept once");
    [Implicit]
    construct(items: int[]) {
        for (var item in items) {
            insert(item);
        }
    }

    ## Makes room for the members `0` up to (not including) `capacity`, so
    ## inserting them does not grow the set. Never shrinks it.
    ##
    ## @param capacity the number of members to make room for
    ## @panics if `capacity` is negative
    reserve(capacity: int) {
        assert(capacity >= 0, "BitSet.reserve: negative capacity");
        _reserve_words(((capacity as ulong) + 63) / 64);
    }

    # Grows `_words` to at least `count` words, the new ones zero.
    _reserve_words(count: ulong) {
        if (_words.count >= count) {
            return;
        }
        _words.reserve(count);
        while (_words.count < count) {
            _words.append(0);
        }
    }

    # Word `index`, or 0 past the end, where every bit is clear.
    _word(index: ulong): ulong {
        if (index >= _words.count) {
            return 0;
        }
        return _words[index];
    }

    # The bit for member `n` within its word.
    static _bit(n: int): ulong {
        return (1 as ulong) << ((n & 63) as ulong);
    }

    ## The number of members the set holds without growing, a multiple of 64.
    var capacity: int {
        get {
            return (_words.count * 64) as int;
        }
    }

    ## The number of members in the set. O(capacity / 64).
    var count: int {
        get {
            int total = 0;
            for (var word in _words) {
                total = total + word.count_ones();
            }
            return total;
        }
    }

    ## Whether the set has no members. O(capacity / 64).
    var is_empty: bool {
        get {
            for (var word in _words) {
                if (word != 0) {
                    return false;
                }
            }
            return true;
        }
    }

    ## Removes every member. The set keeps its capacity.
    clear() {
        ulong i = 0;
        while (i < _words.count) {
            _words[i] = 0;
            i = i + 1;
        }
    }

    ## Returns whether `n` is a member. O(1).
    ##
    ## @param n the integer to look up; a negative one is never a member
    ## @returns true when `n` is a member
    contains(n: int): bool {
        if (n < 0) {
            return false;
        }
        return (_word((n / 64) as ulong) & _bit(n)) != 0;
    }

    ## Adds `n` to the set, growing it when `n` is past its capacity.
    ##
    ## @param n the integer to add
    ## @returns true when `n` was added, false when it was already a member
    ## @panics if `n` is negative
    insert(n: int): bool {
        assert(n >= 0, "BitSet.insert: negative member");
        ulong index = (n / 64) as ulong;
        _reserve_words(index + 1);
        ulong word = _words[index];
        if ((word & _bit(n)) != 0) {
            return false;
        }
        _words[index] = word | _bit(n);
        return true;
    }

    ## Removes `n` from the set. Does nothing when `n` is not a member.
    ##
    ## @param n the integer to remove
    ## @returns true when `n` was a member and was removed, false otherwise
    remove(n: int): bool {
        if (!contains(n)) {
            return false;
        }
        ulong index = (n / 64) as ulong;
        _words[index] = _words[index] & ~_bit(n);
        return true;
    }

    ## Returns an iterator over the members in ascending order;
    ## `for (var n in set)` drives it.
    ##
    ## The iterator holds a reference to the set. Changing the set while
    ## iterating is safe: the iterator sees the members above its position
    ## as they are when it reaches them.
    ##
    ## @returns an iterator positioned before the smallest member
    iterate(): BitSetIterator {
        return BitSetIterator(this);
    }

    ## Adds every member of `other` to this set.
    ##
    ## @param other the set whose members to add
    union_with(other: BitSet) {
        _reserve_words(other._words.count);
        ulong i = 0;
        while (i < other._words.count) {
            _words[i] = _words[i] | other._words[i];
            i = i + 1;
        }
    }

    ## Keeps only the members that `other` also holds.
    ##
    ## @param other the set to intersect with
    intersect_with(other: BitSet) {
        ulong i = 0;
        while (i < _words.count) {
            _words[i] = _words[i] & other._word(i);
            i = i + 1;
        }
    }

    ## Removes every member that `other` holds.
    ##
    ## @param other the set whose members to remove
    difference_with(other: BitSet) {
        ulong i = 0;
        while (i < _words.count) {
            _words[i] = _words[i] & ~other._word(i);
            i = i + 1;
        }
    }

    ## Keeps the members that exactly one of the two sets holds: removes
    ## the members `other` also holds and adds those only `other` holds.
    ##
    ## @param other the set to compare with
    symmetric_difference_with(other: BitSet) {
        _reserve_words(other._words.count);
        ulong i = 0;
        while (i < other._words.count) {
            _words[i] = _words[i] ^ other._words[i];
            i = i + 1;
        }
    }

    ## Returns a new set holding the members of either set.
    ##
    ## @param other the other set
    ## @returns the union of the two sets
    union(other: BitSet): BitSet {
        var result = copy();
        result.union_with(other);
        return result;
    }

    ## Returns a new set holding the members both sets hold.
    ##
    ## @param other the other set
    ## @returns the intersection of the two sets
    intersection(other: BitSet): BitSet {
        var result = copy();
        result.intersect_with(other);
        return result;
    }

    ## Returns a new set holding the members of this set that `other` does
    ## not hold.
    ##
    ## @param other the set whose members to leave out
    ## @returns this set minus `other`
    difference(other: BitSet): BitSet {
        var result = copy();
        result.difference_with(other);
        return result;
    }

    ## Returns a new set holding the members that exactly one of the two
    ## sets holds.
    ##
    ## @param other the other set
    ## @returns the symmetric difference of the two sets
    symmetric_difference(other: BitSet): BitSet {
        var result = copy();
        result.symmetric_difference_with(other);
        return result;
    }

    ## Returns whether every member of this set is also a member of `other`.
    ## The empty set is a subset of every set.
    ##
    ## @param other the set to compare with
    ## @returns true when this set holds no member that `other` lacks
    is_subset(other: BitSet): bool {
        ulong i = 0;
        while (i < _words.count) {
            if ((_words[i] & ~other._word(i)) != 0) {
                return false;
            }
            i = i + 1;
        }
        return true;
    }

    ## Returns whether the two sets have no member in common.
    ##
    ## @param other the set to compare with
    ## @returns true when no integer is a member of both sets
    is_disjoint(other: BitSet): bool {
        ulong i = 0;
        while (i < _words.count) {
            if ((_words[i] & other._word(i)) != 0) {
                return false;
            }
            i = i + 1;
        }
        return true;
    }

    ## Reports whether both sets hold the same members. Capacity is not
    ## compared.
    ##
    ## @param rhs the set to compare with
    ## @returns true when the sets have the same members
    ==(rhs: BitSet): bool {
        ulong words = _words.count;
        if (rhs._words.count > words) {
            words = rhs._words.count;
        }
        ulong i = 0;
        while (i < words) {
            if (_word(i) != rhs._word(i)) {
                return false;
            }
            i = i + 1;
        }
        return true;
    }

    ## Reports whether the sets differ in any member; the negation of `==`.
    ##
    ## @param rhs the set to compare with
    ## @returns true when one set holds a member the other lacks
    !=(rhs: BitSet): bool {
        return !(this == rhs);
    }

    ## Returns a new set with the same members and capacity. This is how
    ## `copy(value)` copies a BitSet (the `Copyable<BitSet>`
    ## implementation).
    ##
    ## @returns the copy
    copy(): BitSet {
        var made = BitSet();
        register_copy<BitSet>(this, made);
        made._words = _words.clone();
        return made;
    }
}

## Returns a hash of the members of `value`, so equal sets hash equally
## whatever their capacity and a `BitSet` works as a `HashMap` or `HashSet`
## key. O(capacity / 64).
##
## @param value the set to hash
## @returns the 64-bit hash of the set's members
export hash<BitSet>(value: BitSet): u64 {
    # Trailing zero words are left out, so capacity does not change the hash.
    ulong end = value._words.count;
    while (end > 0 and value._words[end - 1] == 0) {
        end = end - 1;
    }
    u64 result = 0;
    ulong i = 0;
    while (i < end) {
        result = hash<(u64, ulong)>((result, value._words[i]));
        i = i + 1;
    }
    return result;
}

## An `Iterator<int>` over the members of a `BitSet` in ascending order;
## returned by `BitSet.iterate()` and driven by `for (var n in set)`.
##
## @see BitSet.iterate
[Value]
export struct BitSetIterator {
    ## The set being iterated.
    BitSet _source;
    ## The current member, or -1 before the first `next()`.
    int _current;
    ## Whether `next()` returned false.
    bool _done;

    ## Creates an iterator positioned before the smallest member of `source`.
    ##
    ## @param source the set to iterate
    construct(source: BitSet) {
        _source = source;
        _current = -1;
    }

    ## Advances to the next larger member.
    ##
    ## @returns true when there is a current member, false once every member
    ##   was visited
    next(): bool {
        if (_done) {
            return false;
        }
        int start = _current + 1;
        ulong index = (start / 64) as ulong;
        # The bits of the first word from `start` up.
        ulong bits = _source._word(index) & (~(0 as ulong) << ((start & 63) as ulong));
        while (bits == 0) {
            index = index + 1;
            if (index >= _source._words.count) {
                _done = true;
                return false;
            }
            bits = _source._words[index];
        }
        _current = (index * 64) as int + bits.trailing_zeros();
        return true;
    }

    ## Returns the member the last successful `next()` moved to.
    ##
    ## @returns the current member
    ## @panics if `next()` was never called or already returned false
    ##   ("BitSetIterator.current() without a member")
    current(): int {
        assert(_current >= 0 and !_done, "BitSetIterator.current() without a member");
        return _current;
    }
}
