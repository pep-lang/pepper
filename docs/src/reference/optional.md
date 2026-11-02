<!-- Generated from runtime/optional.pep by `pep-doc reference`. Do not edit. -->

# Optional

Source: `runtime/optional.pep`

## Optional

```pepper
[Value] enum Optional<T>
```

A value of type `T` that may be absent: either Value, holding a `T`, or
Empty, holding nothing, like Rust's `Option<T>` and Swift's `Optional`.

Use it instead of a null reference or a sentinel (`-1`, `""`) wherever a
value may be missing: the type says so, and reading the value goes through
`value()`, which checks, or `value_or()`, which cannot fail. It works for
every type, including those that have no null, such as `int`.

`T?` is shorthand for `Optional<T>`, and a variable or field of an
optional type that is not given a value starts as Empty.

Build one with its cases (`Optional<int>.Value(1)`, `Optional<int>.Empty`).
Test it with `is_value()` or `is_empty()`, as a condition by itself (`if (found)`), or with `match`
and `is` on its cases (`if (found is Value(v))`).

An optional is a [value enum](../language/value-structs.md): it is stored
inline in whatever holds it, with no allocation, and copying one gives an
independent optional. It is never null, and has no identity, so compare
optionals with `==`, not `===`.

**Type parameters**
- `T` — the type of the value a Value optional holds

**Example**
```pepper
find_even(values: Array<int>): int? {
    for (var v in values) {
        if (v % 2 == 0) { return Optional<int>.Value(v); }
    }
    return Optional<int>.Empty;
}

main(): int {
    var values = Array<int>();
    values.append(3);
    values.append(4);
    var found = find_even(values);
    if (!found) { return 1; }
    return found.value() - 4;   # 0
}
```

### Cases

#### Empty

```pepper
Empty
```

Holds no value. It is the first case, so an optional that is never
given a value is Empty.

#### Value

```pepper
Value(value: T)
```

Holds a value.

**Parameters**
- `value` — the value held

### Static methods

#### some

```pepper
[Deprecated("use the case 'Value' instead", "Value")] static some(value: T): Optional<T>
```

Deprecated: use the `Value` case, `Optional<T>.Value(value)`,
instead.

Returns a Value optional holding `value`.

**Parameters**
- `value` — the value to hold

**Returns**
- a Value optional whose value is `value`

#### none

```pepper
[Deprecated("use the case 'Optional<T>.Empty' instead")] static none(): Optional<T>
```

Deprecated: use the `Empty` case, `Optional<T>.Empty`, instead.

Returns an Empty optional, one holding no value.

**Returns**
- an Empty optional

### Methods

#### is_value

```pepper
is_value(): bool
```

Reports whether this optional holds a value.

**Returns**
- true when the optional is Value

**Example**
```pepper
var found = Optional<int>.Value(7);
if (found.is_value()) { print(found.value()); }   # prints 7
```

#### is_empty

```pepper
is_empty(): bool
```

Reports whether this optional holds no value.

**Returns**
- true when the optional is Empty

**Example**
```pepper
var missing = Optional<int>.Empty;
if (missing.is_empty()) { print("missing"); }
```

#### is_some

```pepper
[Deprecated("use 'is_value' instead", "is_value")] is_some(): bool
```

Deprecated: use `is_value` instead.

Reports whether this optional holds a value.

**Returns**
- true when the optional is Value

#### is_none

```pepper
[Deprecated("use 'is_empty' instead", "is_empty")] is_none(): bool
```

Deprecated: use `is_empty` instead.

Reports whether this optional holds no value.

**Returns**
- true when the optional is Empty

#### operator !!

```pepper
!!(): bool
```

Reports whether this optional holds a value: the truth test, so an
optional can stand as a condition by itself.

`if (found)` means `if (found.is_value())`, `!found` means
`found.is_empty()`, and the same holds in `while`, `&&`, `||` and
`?:`.

**Returns**
- true when the optional is Value

**Example**
```pepper
var found = Optional<int>.Value(7);
if (found) { print(found.value()); }   # prints 7
```

#### value

```pepper
value(): T
```

Returns the value, panicking if this optional is Empty.

For a struct `T` the caller gets its own reference; the optional keeps
its reference too.

**Returns**
- the value of a Value optional

**Panics**
- if the optional is Empty ("Optional.value on an Empty optional")

**Example**
```pepper
var n = Optional<int>.Value(42).value();   # 42
```

#### value_or

```pepper
value_or(fallback: T): T
```

Returns the value, or `fallback` if this optional is Empty.

Never panics. `fallback` is evaluated by the caller whether or not it
is used.

**Parameters**
- `fallback` — the value to return when the optional is Empty

**Returns**
- the value when the optional is Value, otherwise `fallback`

**Example**
```pepper
var n = Optional<int>.Empty.value_or(-1);   # -1
```

## extend Optional<T>

```pepper
extend Optional<T: Comparable> with Comparable
```

Optionals of `Comparable` values are `Comparable`: Empty sorts before
every value, as in Rust and Swift, and two values by their own order, so
`Array<int?>.sort()` puts the Empty ones first.

**Type parameters**
- `T` — the value type, `Comparable`

### Methods

#### compare

```pepper
compare(other: Optional<T>): int
```

Returns the order of this optional and `other`: Empty before any
value, and two values by `compare`.

**Parameters**
- `other` — the optional to compare with

**Returns**
- a negative number, zero or a positive number as this optional sorts before, with or after `other`

**Example**
```pepper
assert(Optional<int>.Empty.compare(Optional<int>.Value(0)) < 0, "Empty first");
```
