<!-- Generated from runtime/compare.pep by `pep-doc reference`. Do not edit. -->

# Comparable

Ordering: `Comparable`, the trait of types whose values sort in one
order, which every number type, `char` and `String` declare.

Source: `runtime/compare.pep`

## Comparable

```pepper
trait Comparable
```

A type whose values have one order: `compare` says whether a value sorts
before, with or after another.

Declaring it (`extend Version with Comparable;`) gives the type `<`,
`<=`, `>` and `>=` and the methods `min`, `max` and `clamp`, each
written in terms of `compare`, unless the type declares its own. A
generic function asks for an order with `T: Comparable`.

`compare` returns a negative number when this value sorts before
`other`, zero when the two sort together, and a positive number when it
sorts after. The order must be total and consistent: two calls with the
same values give the same answer, and `a.compare(b)` has the opposite
sign of `b.compare(a)`. `Map`, `Set` and sorting rely on that.

`float` and `double` are `Comparable` with a total order: NaN sorts
after every number and with every other NaN, and `-0.0` with `0.0`.
Their `<` and `>` keep IEEE behavior (false whenever NaN takes part),
while `compare`, `clamp` and `Map` keys follow the total order.

**Example**
```pepper
struct Version {
    var major: int;
    var minor: int;

    construct(this.major = 0, this.minor = 0) {}

    compare(other: Version): int {
        var order = major.compare(other.major);
        if (order != 0) {
            return order;
        }
        return minor.compare(other.minor);
    }
}

extend Version with Comparable;

assert(Version(1, 2) < Version(1, 10), "by minor");
assert(Version(2, 0).max(Version(1, 9)).major == 2, "max");
```

### Methods

#### compare

```pepper
compare(other: this): int
```

Returns the order of this value and `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- a negative number, zero or a positive number as this value sorts before, with or after `other`

#### operator <

```pepper
<(other: this): bool
```

Returns whether this value sorts before `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- true when `compare(other) < 0`

#### operator <=

```pepper
<=(other: this): bool
```

Returns whether this value sorts before or with `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- true when `compare(other) <= 0`

#### operator >

```pepper
>(other: this): bool
```

Returns whether this value sorts after `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- true when `compare(other) > 0`

#### operator >=

```pepper
>=(other: this): bool
```

Returns whether this value sorts after or with `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- true when `compare(other) >= 0`

#### min

```pepper
min(other: this): this
```

Returns the one of this value and `other` that sorts first.

**Parameters**
- `other` — the value to compare with

**Returns**
- this value when it sorts before or with `other`, else `other`

**Example**
```pepper
assert("pear".min("apple") == "apple", "apple sorts first");
```

#### max

```pepper
max(other: this): this
```

Returns the one of this value and `other` that sorts last.

**Parameters**
- `other` — the value to compare with

**Returns**
- this value when it sorts after or with `other`, else `other`

**Example**
```pepper
assert("pear".max("apple") == "pear", "pear sorts last");
```

#### clamp

```pepper
clamp(low: this, high: this): this
```

Returns this value limited to the range from `low` to `high`.

**Parameters**
- `low` — the lowest value to return
- `high` — the highest value to return

**Returns**
- `low` when this value sorts before it, `high` when this value sorts after it, else this value

**Panics**
- if `low` sorts after `high` ("clamp range is empty")

**Example**
```pepper
assert((15).clamp(0, 10) == 10, "too high");
assert((-3).clamp(0, 10) == 0, "too low");
assert((4).clamp(0, 10) == 4, "in range");
```

## extend char

```pepper
extend char with Comparable
```

`char` values sort by value.

### Methods

#### compare

```pepper
compare(other: char): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend byte

```pepper
extend byte with Comparable
```

`byte` values sort by value.

### Methods

#### compare

```pepper
compare(other: byte): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend short

```pepper
extend short with Comparable
```

`short` values sort by value.

### Methods

#### compare

```pepper
compare(other: short): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend ushort

```pepper
extend ushort with Comparable
```

`ushort` values sort by value.

### Methods

#### compare

```pepper
compare(other: ushort): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend int

```pepper
extend int with Comparable
```

`int` values sort by value.

### Methods

#### compare

```pepper
compare(other: int): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend uint

```pepper
extend uint with Comparable
```

`uint` values sort by value.

### Methods

#### compare

```pepper
compare(other: uint): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend long

```pepper
extend long with Comparable
```

`long` values sort by value.

### Methods

#### compare

```pepper
compare(other: long): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend ulong

```pepper
extend ulong with Comparable
```

`ulong` values sort by value.

### Methods

#### compare

```pepper
compare(other: ulong): int
```

Returns the order of this value and `other`: -1, 0 or 1 as this
value is less than, equal to or greater than `other`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1

## extend float

```pepper
extend float with Comparable
```

`float` values sort by value, with NaN after every number.

### Methods

#### compare

```pepper
compare(other: float): int
```

Returns the order of this value and `other` in a total order: by
value, with NaN after every number and equal to every NaN, and
`-0.0` equal to `0.0`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1 as this value sorts before, with or after `other`

**Example**
```pepper
var nan = (0.0 / 0.0) as float;
assert((1.0 as float).compare(nan) < 0, "NaN sorts last");
assert(nan.compare(nan) == 0, "NaNs sort together");
```

## extend double

```pepper
extend double with Comparable
```

`double` values sort by value, with NaN after every number.

### Methods

#### compare

```pepper
compare(other: double): int
```

Returns the order of this value and `other` in a total order: by
value, with NaN after every number and equal to every NaN, and
`-0.0` equal to `0.0`.

**Parameters**
- `other` — the value to compare with

**Returns**
- -1, 0 or 1 as this value sorts before, with or after `other`

**Example**
```pepper
var nan = 0.0 / 0.0;
assert((1.0).compare(nan) < 0, "NaN sorts last");
assert(nan.compare(nan) == 0, "NaNs sort together");
```
