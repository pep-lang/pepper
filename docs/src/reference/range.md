<!-- Generated from runtime/range.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# range.pep

Ranges of numbers: `a..b` and `a..>b`.

`a..b` (half-open) holds `a` up to but not including `b`; `a..>b`
(closed) includes `b`. Both make a `Range<T>`, a value that a `for` loop
steps through without allocating:

    for (var i in 0..count) { ... }   # 0, 1, ..., count - 1
    for (var i in 1..>10) { ... }     # 1, 2, ..., 10

Source: `runtime/range.pep`

## Range

```pepper
[Value] struct Range<T>
```

A run of consecutive numbers, from `start` up to `end`, as `a..b` and
`a..>b` make it.

A range is an iterator: `next()` steps from `start` up by one, and a
`for` loop over a range is a counting loop. A range whose `start` is past
its end yields nothing. A closed range ending at the largest value of its
type (`0..>255` as `byte`) stops there without overflowing.

Ranges are [value structs](../language/value-structs.md): copying one
copies its position, and looping over a range stored in a variable
advances that variable.

**Type parameters**
- `T` — the number type, inferred from the bounds (`0..n` with a `ulong` `n` is a `Range<ulong>`)

**Example**
```pepper
    var total = 0;
    for (var i in 1..>4) {
        total += i;   # 1 + 2 + 3 + 4
    }
    var r = 0..10;
    assert(r.contains(9) && !r.contains(10), "half-open");
```

### Fields

#### start

```pepper
T start
```

The first number of the range.

#### end

```pepper
T end
```

The bound the range stops at: the last number when `inclusive`, else one past it.

#### inclusive

```pepper
bool inclusive
```

Whether `end` is part of the range: true for `a..>b`, false for `a..b`.

### Properties

#### is_empty

```pepper
var is_empty: bool { get; }
```

Whether the range holds no numbers, whatever the iteration has
reached.

### Constructor

#### Range()

```pepper
construct(start: T, end: T, inclusive: bool = false)
```

Makes the range from `start` to `end`, as `start..end` (or
`start..>end` when `inclusive`).

**Parameters**
- `start` — the first number
- `end` — the bound: one past the last number, or the last number when `inclusive`
- `inclusive` — whether `end` is part of the range

### Methods

#### next

```pepper
next(): bool
```

Advances to the next number: `start` on the first call, then one
more each time.

Once it returns false it keeps returning false.

**Returns**
- true if there is a current number, false once past the end

#### current

```pepper
current(): T
```

Returns the number the last successful `next()` moved to.

**Returns**
- the current number

**Panics**
- if `next()` was never called ("Range.current() before next()")
- if `next()` already returned false ("Range.current() past the end")

#### contains

```pepper
contains(value: T): bool
```

Returns whether `value` lies in the range, whatever the iteration has
reached.

**Parameters**
- `value` — the number to test

**Returns**
- true if `start <= value` and `value` is before `end` (or equal to it, for a closed range)
