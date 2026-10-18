## Greatest common divisors and least common multiples of integers.
##
## For integer powers, use `**`: `3 ** 4` is 81, and it panics on overflow.

## Returns the greatest common divisor of `a` and `b`: the largest integer
## that divides both. It is never negative, and `gcd(0, 0)` is 0.
##
## @param a the first integer
## @param b the second integer
## @returns the greatest common divisor
## @panics if `a` or `b` is the smallest `long`, whose magnitude does not fit
## @example
##     assert(math.gcd(12, -18) == 6, "divides both");
export gcd(a: long, b: long): long {
    var x = a.abs();
    var y = b.abs();
    while (y != 0) {
        var rest = x % y;
        x = y;
        y = rest;
    }
    return x;
}

## Returns the least common multiple of `a` and `b`: the smallest
## non-negative integer both divide. It is 0 when either is 0.
##
## @param a the first integer
## @param b the second integer
## @returns the least common multiple
## @panics if the result does not fit a `long`
## @example
##     assert(math.lcm(4, 6) == 12, "both divide 12");
export lcm(a: long, b: long): long {
    if (a == 0 || b == 0) {
        return 0;
    }
    return (a / gcd(a, b) * b).abs();
}
