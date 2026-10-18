<!-- Generated from runtime/random/generator.pep by `pep-doc reference`. Do not edit. -->

# Generators

`Generator`, a fast pseudo-random generator, and functions that use this
thread's own generator, so code that only needs a random number need not
pass one around.

The algorithm is xoshiro256** (Blackman and Vigna): 256 bits of state,
a period of 2^256 - 1, and statistically strong output. It is not secure:
anyone who sees enough output can predict the rest, so keys and tokens
come from `random.bytes` instead.

Source: `runtime/random/generator.pep`
