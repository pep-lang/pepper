# Random numbers

The `random` module gives random numbers two ways: secure bytes from the
operating system, for keys, tokens and identifiers, and `Generator`, a fast
pseudo-random generator for everything else: games, simulations, sampling,
shuffling and jitter. Bring it in with `import random`; the full API is in
the [reference](../reference/random-module.md).

```pepper
{{#include ../../examples/random-basics.pep}}
```

## Secure bytes

| Function | Gives |
|---|---|
| `random.bytes(count)` | a new `u8[]` of `count` random bytes |
| `random.fill(bytes)` | overwrites every element of an existing `u8[]` |
| `random.secure_ulong()` | a random `ulong` |

They come from `getentropy` on Linux, Android, macOS, iOS and WASI, and
from `BCryptGenRandom` on Windows, so no one can predict them. Each call
asks the kernel, which is slower than a generator. They panic only if the
operating system cannot give random bytes, which a working system never
does.

## Generators

`random.Generator` is xoshiro256**: 256 bits of state, statistically
strong output, and a few instructions a number. It is not secure: anyone
who sees enough of its output can predict the rest.

- `Generator()` seeds itself from the operating system, so each run gives
  different numbers.
- `Generator(seed)` gives the same numbers for the same `seed` on every
  platform, for reproducible tests and simulations.

| Method | Gives |
|---|---|
| `next_ulong()` | 64 random bits |
| `next_int(range)` | an `int` in `range`: `0..10` is 0 to 9, `1..>6` is 1 to 6 |
| `next_double()` | a `double` from 0 up to but not including 1 |
| `next_bool()` | true or false |
| `choose(items)` | one element of an array |
| `shuffle(items)` | puts an array in a random order, in place |

Every number in a range is equally likely: `next_int` draws again rather
than let the low numbers come up a little more often. An empty range, or
`choose` on an empty array, panics.

A generator is a [value struct](value-structs.md): copying one copies its
state, so the copy gives the same numbers as the original, and a function
that takes a generator as a parameter draws from its own copy. A generator
belongs to one thread.

## This thread's generator

`random.next_ulong`, `next_int`, `next_double`, `next_bool`, `choose` and
`shuffle` draw from a generator each thread has of its own, seeded from the
operating system the first time the thread uses it. Code that needs a
random number calls them without passing a generator around, and threads
never share or lock one.
