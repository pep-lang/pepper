<!-- Generated from runtime/optional.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Optional

Source: `runtime/optional.pep`

## Optional

```pepper
struct Optional<T>
```

A value of type `T` that may be absent: either Some, holding a `T`, or
None, holding nothing, like Rust's `Option<T>` and Swift's `Optional`.

Use it instead of a null reference or a sentinel (`-1`, `""`) wherever a
value may be missing: the type says so, and reading the value goes through
`value()`, which checks, or `value_or()`, which cannot fail. It works for
every type, including those that have no null, such as `int`.

`T?` is shorthand for `Optional<T>`, and a variable or field of an
optional type that is not given a value starts as None.

Build one with the static `some` or `none` functions, or `Optional<T>()`
for None, and test it with `is_some()` or `is_none()`, or as a condition
by itself (`if (found)`).

**Type parameters**
- `T` — the type of the value a Some optional holds

**Example**
```pepper
    find_even(values: Array<int>): int? {
        for (var v in values) {
            if (v % 2 == 0) { return Optional<int>.some(v); }
        }
        return Optional<int>.none();
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

### Constructor

#### Optional()

```pepper
construct()
```

Creates a None optional, one holding no value.

**Example**
```pepper
    var nothing = Optional<int>();   # nothing.is_none() == true
```

### Static methods

#### some

```pepper
static some(value: T): Optional<T>
```

Returns a Some optional holding `value`.

For a struct `T` the optional acquires a reference to `value`.

**Parameters**
- `value` — the value to hold

**Returns**
- a Some optional whose value is `value`

**Example**
```pepper
    var answer = Optional<int>.some(42);
```

#### none

```pepper
static none(): Optional<T>
```

Returns a None optional, one holding no value; the same as
`Optional<T>()`.

**Returns**
- a None optional

**Example**
```pepper
    var nothing = Optional<String>.none();
```

### Methods

#### is_some

```pepper
is_some(): bool
```

Reports whether this optional holds a value.

**Returns**
- true when the optional is Some

#### is_none

```pepper
is_none(): bool
```

Reports whether this optional holds no value.

**Returns**
- true when the optional is None

#### operator !!

```pepper
!!(): bool
```

Reports whether this optional holds a value: the truth test, so an
optional can stand as a condition by itself.

`if (found)` means `if (found.is_some())`, `!found` means
`found.is_none()`, and the same holds in `while`, `&&`, `||` and
`?:`.

**Returns**
- true when the optional is Some

**Example**
```pepper
    var found = Optional<int>.some(7);
    if (found) { print(found.value()); }   # prints 7
```

#### value

```pepper
value(): T
```

Returns the value, panicking if this optional is None.

For a struct `T` the caller gets its own reference; the optional keeps
its reference too.

**Returns**
- the value of a Some optional

**Panics**
- if the optional is None ("Optional.value on a None value")

**Example**
```pepper
    var n = Optional<int>.some(42).value();   # 42
```

#### value_or

```pepper
value_or(fallback: T): T
```

Returns the value, or `fallback` if this optional is None.

Never panics. `fallback` is evaluated by the caller whether or not it
is used.

**Parameters**
- `fallback` — the value to return when the optional is None

**Returns**
- the value when the optional is Some, otherwise `fallback`

**Example**
```pepper
    var n = Optional<int>.none().value_or(-1);   # -1
```
