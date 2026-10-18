## `Generator`, a fast pseudo-random generator, and functions that use this
## thread's own generator, so code that only needs a random number need not
## pass one around.
##
## The algorithm is xoshiro256** (Blackman and Vigna): 256 bits of state,
## a period of 2^256 - 1, and statistically strong output. It is not secure:
## anyone who sees enough output can predict the rest, so keys and tokens
## come from `random.bytes` instead.

import "entropy";

## A seedable pseudo-random number generator (xoshiro256**).
##
## `Generator()` seeds itself from the operating system, so each one gives
## different numbers; `Generator(seed)` gives the same numbers for the same
## seed on every platform, for reproducible tests and simulations.
##
## A generator is a [value struct](../language/value-structs.md): copying
## one copies its state, and the copy then gives the same numbers as the
## original. Pass it to a function that draws from it as a `var` you return,
## or keep it in a field. A generator belongs to one thread.
##
## @example
##     var g = random.Generator(7);
##     var roll = g.next_int(1..>6);
##     var again = random.Generator(7);
##     assert(again.next_int(1..>6) == roll, "same seed, same numbers");
[Value]
struct Generator {
    ulong _s0;
    ulong _s1;
    ulong _s2;
    ulong _s3;

    ## Makes a generator seeded with 256 bits from the operating system.
    ##
    ## @panics if the operating system cannot give random bytes, which only a broken system does
    construct() {
        _s0 = secure_ulong();
        _s1 = secure_ulong();
        _s2 = secure_ulong();
        _s3 = secure_ulong();
    }

    ## Makes a generator that always gives the same numbers for `seed`.
    ##
    ## The seed is spread over the state with SplitMix64, as xoshiro's
    ## authors recommend, so nearby seeds give unrelated numbers.
    ##
    ## @param seed any number; each gives its own sequence
    construct(seed: ulong) {
        var x = seed;
        _s0 = _split_mix(x);
        x = x.wrapping_add(0x9e3779b97f4a7c15);
        _s1 = _split_mix(x);
        x = x.wrapping_add(0x9e3779b97f4a7c15);
        _s2 = _split_mix(x);
        x = x.wrapping_add(0x9e3779b97f4a7c15);
        _s3 = _split_mix(x);
    }

    # SplitMix64's output for the state after adding the golden gamma to `x`.
    static _split_mix(x: ulong): ulong {
        var z = x.wrapping_add(0x9e3779b97f4a7c15);
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        return z ^ (z >> 31);
    }

    ## Returns the next number, from 0 to 2^64 - 1, every value equally likely.
    ##
    ## @returns the next 64 random bits
    next_ulong(): ulong {
        var result = _s1.wrapping_mul(5).rotate_left(7).wrapping_mul(9);
        var t = _s1 << 17;
        _s2 ^= _s0;
        _s3 ^= _s1;
        _s1 ^= _s2;
        _s0 ^= _s3;
        _s2 ^= t;
        _s3 = _s3.rotate_left(45);
        return result;
    }

    # A number from 0 up to but not including `bound`, unbiased: draws
    # below the threshold would make the low values a little likelier, so
    # they are drawn again (at most half the time, for a bound past 2^63).
    _below(bound: ulong): ulong {
        var threshold = (0 as ulong).wrapping_sub(bound) % bound;
        var r = next_ulong();
        while (r < threshold) {
            r = next_ulong();
        }
        return r % bound;
    }

    ## Returns a number in `range`, every number in it equally likely.
    ##
    ## @param range the numbers to choose from: `0..10` is 0 to 9, `1..>6` is 1 to 6
    ## @returns a number in `range`
    ## @panics if `range` is empty ("random: empty range")
    ## @example
    ##     var g = random.Generator();
    ##     var die = g.next_int(1..>6);
    next_int(range: Range<int>): int {
        var span = (range.end as long) - (range.start as long) + (range.inclusive ? 1 : 0);
        assert(span > 0, "random: empty range");
        return ((range.start as long) + (_below(span as ulong) as long)) as int;
    }

    ## Returns a number from 0 up to but not including 1, evenly spread.
    ##
    ## It is one of the 2^53 multiples of 2^-53 below 1, every one equally likely.
    ##
    ## @returns a `double` with 0 <= result < 1
    next_double(): double {
        return ((next_ulong() >> 11) as double) * 1.1102230246251565e-16;
    }

    ## Returns true or false, each half the time.
    ##
    ## @returns a random bool
    next_bool(): bool {
        return (next_ulong() >> 63) == 1;
    }

    ## Returns one element of `items`, each equally likely.
    ##
    ## @typeParam T the element type
    ## @param items the elements to choose from
    ## @returns a random element of `items`
    ## @panics if `items` is empty ("random: choose from an empty array")
    choose<T>(items: T[]): T {
        assert(items.count > 0, "random: choose from an empty array");
        return items[_below(items.count)];
    }

    ## Puts the elements of `items` in a random order, every order equally
    ## likely (the Fisher–Yates shuffle).
    ##
    ## @typeParam T the element type
    ## @param items the array to shuffle in place
    shuffle<T>(items: T[]) {
        var i = items.count;
        while (i > 1) {
            i -= 1;
            items.swap(i, _below(i + 1));
        }
    }
}

# This thread's generator, seeded from the operating system the first time
# it is used: [ThreadLocal] holds numbers, so its state is kept in four.
[ThreadLocal]
var _random_seeded: bool = false;
[ThreadLocal]
var _random_s0: ulong = 0;
[ThreadLocal]
var _random_s1: ulong = 0;
[ThreadLocal]
var _random_s2: ulong = 0;
[ThreadLocal]
var _random_s3: ulong = 0;

# A copy of this thread's generator, for one draw that `_random_save` stores back.
_random_load(): Generator {
    if (!_random_seeded) {
        _random_save(Generator());
        _random_seeded = true;
    }
    var g = __default<Generator>();
    g._s0 = _random_s0;
    g._s1 = _random_s1;
    g._s2 = _random_s2;
    g._s3 = _random_s3;
    return g;
}

_random_save(g: Generator) {
    _random_s0 = g._s0;
    _random_s1 = g._s1;
    _random_s2 = g._s2;
    _random_s3 = g._s3;
}

## Returns the next number from this thread's generator, from 0 to 2^64 - 1.
##
## Each thread has its own generator, seeded from the operating system the
## first time it is used.
##
## @returns the next 64 random bits
next_ulong(): ulong {
    var g = _random_load();
    var result = g.next_ulong();
    _random_save(g);
    return result;
}

## Returns a number in `range` from this thread's generator, every number
## in it equally likely.
##
## @param range the numbers to choose from: `0..10` is 0 to 9, `1..>6` is 1 to 6
## @returns a number in `range`
## @panics if `range` is empty ("random: empty range")
## @example
##     var die = random.next_int(1..>6);
next_int(range: Range<int>): int {
    var g = _random_load();
    var result = g.next_int(range);
    _random_save(g);
    return result;
}

## Returns a number from 0 up to but not including 1 from this thread's generator.
##
## @returns a `double` with 0 <= result < 1
next_double(): double {
    var g = _random_load();
    var result = g.next_double();
    _random_save(g);
    return result;
}

## Returns true or false from this thread's generator, each half the time.
##
## @returns a random bool
next_bool(): bool {
    var g = _random_load();
    var result = g.next_bool();
    _random_save(g);
    return result;
}

## Returns one element of `items`, chosen by this thread's generator.
##
## @typeParam T the element type
## @param items the elements to choose from
## @returns a random element of `items`
## @panics if `items` is empty ("random: choose from an empty array")
choose<T>(items: T[]): T {
    var g = _random_load();
    var result = g.choose(items);
    _random_save(g);
    return result;
}

## Puts the elements of `items` in a random order with this thread's generator.
##
## @typeParam T the element type
## @param items the array to shuffle in place
## @example
##     var deck = [1, 2, 3, 4, 5];
##     random.shuffle(deck);
shuffle<T>(items: T[]) {
    var g = _random_load();
    g.shuffle(items);
    _random_save(g);
}
