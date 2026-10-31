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

## Generator

```pepper
[Value] struct Generator
```

A seedable pseudo-random number generator (xoshiro256**).

`Generator()` seeds itself from the operating system, so each one gives
different numbers; `Generator(seed)` gives the same numbers for the same
seed on every platform, for reproducible tests and simulations.

A generator is a [value struct](../language/value-structs.md): copying
one copies its state, and the copy then gives the same numbers as the
original. Pass it to a function that draws from it as a `var` you return,
or keep it in a field. A generator belongs to one thread.

**Example**
```pepper
var g = random.Generator(7);
var roll = g.next_int(1..>6);
var again = random.Generator(7);
assert(again.next_int(1..>6) == roll, "same seed, same numbers");
```

### Constructors

#### Generator()

```pepper
construct()
```

Makes a generator seeded with 256 bits from the operating system.

**Panics**
- if the operating system cannot give random bytes, which only a broken system does

#### Generator()

```pepper
construct(seed: ulong)
```

Makes a generator that always gives the same numbers for `seed`.

The seed is spread over the state with SplitMix64, as xoshiro's
authors recommend, so nearby seeds give unrelated numbers.

**Parameters**
- `seed` — any number; each gives its own sequence

### Methods

#### next_ulong

```pepper
next_ulong(): ulong
```

Returns the next number, from 0 to 2^64 - 1, every value equally likely.

**Returns**
- the next 64 random bits

#### next_int

```pepper
next_int(range: Range<int>): int
```

Returns a number in `range`, every number in it equally likely.

**Parameters**
- `range` — the numbers to choose from: `0..10` is 0 to 9, `1..>6` is 1 to 6

**Returns**
- a number in `range`

**Panics**
- if `range` is empty ("random: empty range")

**Example**
```pepper
var g = random.Generator();
var die = g.next_int(1..>6);
```

#### next_double

```pepper
next_double(): double
```

Returns a number from 0 up to but not including 1, evenly spread.

It is one of the 2^53 multiples of 2^-53 below 1, every one equally likely.

**Returns**
- a `double` with 0 <= result < 1

#### next_bool

```pepper
next_bool(): bool
```

Returns true or false, each half the time.

**Returns**
- a random bool

#### choose

```pepper
choose<T>(items: T[]): T
```

Returns one element of `items`, each equally likely.

**Type parameters**
- `T` — the element type

**Parameters**
- `items` — the elements to choose from

**Returns**
- a random element of `items`

**Panics**
- if `items` is empty ("random: choose from an empty array")

#### shuffle

```pepper
shuffle<T>(items: T[])
```

Puts the elements of `items` in a random order, every order equally
likely (the Fisher–Yates shuffle).

**Type parameters**
- `T` — the element type

**Parameters**
- `items` — the array to shuffle in place

## next_ulong

```pepper
next_ulong(): ulong
```

Returns the next number from this thread's generator, from 0 to 2^64 - 1.

Each thread has its own generator, seeded from the operating system the
first time it is used.

**Returns**
- the next 64 random bits

## next_int

```pepper
next_int(range: Range<int>): int
```

Returns a number in `range` from this thread's generator, every number
in it equally likely.

**Parameters**
- `range` — the numbers to choose from: `0..10` is 0 to 9, `1..>6` is 1 to 6

**Returns**
- a number in `range`

**Panics**
- if `range` is empty ("random: empty range")

**Example**
```pepper
var die = random.next_int(1..>6);
```

## next_double

```pepper
next_double(): double
```

Returns a number from 0 up to but not including 1 from this thread's generator.

**Returns**
- a `double` with 0 <= result < 1

## next_bool

```pepper
next_bool(): bool
```

Returns true or false from this thread's generator, each half the time.

**Returns**
- a random bool

## choose

```pepper
choose<T>(items: T[]): T
```

Returns one element of `items`, chosen by this thread's generator.

**Type parameters**
- `T` — the element type

**Parameters**
- `items` — the elements to choose from

**Returns**
- a random element of `items`

**Panics**
- if `items` is empty ("random: choose from an empty array")

## shuffle

```pepper
shuffle<T>(items: T[])
```

Puts the elements of `items` in a random order with this thread's generator.

**Type parameters**
- `T` — the element type

**Parameters**
- `items` — the array to shuffle in place

**Example**
```pepper
var deck = [1, 2, 3, 4, 5];
random.shuffle(deck);
```
