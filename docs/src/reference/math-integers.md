<!-- Generated from runtime/math/integers.pep by `pep-doc reference`. Do not edit. -->

# Integers

Greatest common divisors and least common multiples of integers.

For integer powers, use `**`: `3 ** 4` is 81, and it panics on overflow.

Source: `runtime/math/integers.pep`

## gcd

```pepper
gcd(a: long, b: long): long
```

Returns the greatest common divisor of `a` and `b`: the largest integer
that divides both. It is never negative, and `gcd(0, 0)` is 0.

**Parameters**
- `a` — the first integer
- `b` — the second integer

**Returns**
- the greatest common divisor

**Panics**
- if `a` or `b` is the smallest `long`, whose magnitude does not fit

**Example**
```pepper
assert(math.gcd(12, -18) == 6, "divides both");
```

## lcm

```pepper
lcm(a: long, b: long): long
```

Returns the least common multiple of `a` and `b`: the smallest
non-negative integer both divide. It is 0 when either is 0.

**Parameters**
- `a` — the first integer
- `b` — the second integer

**Returns**
- the least common multiple

**Panics**
- if the result does not fit a `long`

**Example**
```pepper
assert(math.lcm(4, 6) == 12, "both divide 12");
```
