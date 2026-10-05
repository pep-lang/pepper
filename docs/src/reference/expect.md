<!-- Generated from runtime/expect.pep by `pep-doc reference`. Do not edit. -->

# Test checks

Checks for tests: `expect_equal`, `expect_not_equal`, `expect_true` and
`expect_false`, which every program can call without an import. Each
panics when its check fails, as `assert` does, but reports the values it
compared, at the line of the call:

    math_test.pep:12:5: panic: expect_equal failed
      actual:   3
      expected: 4

A `[Test]` function fails on that panic (see the testing chapter).

Source: `runtime/expect.pep`

## expect_equal

```pepper
expect_equal<T>(actual: T, expected: T)
```

Panics unless `actual == expected`, reporting both values.

**Type parameters**
- `T` — the type of the values; it needs `==` and a text form (see `to_string`)

**Parameters**
- `actual` — the value the code under test produced
- `expected` — the value it should have produced

**Panics**
- if the values differ: prints the location of the call and both values, and aborts (see `panic`)

**Example**
```pepper
var numbers = Array<int>();
numbers.append(1);
expect_equal(numbers.count, 1);
```

## expect_not_equal

```pepper
expect_not_equal<T>(actual: T, unexpected: T)
```

Panics if `actual == unexpected`, reporting the value.

**Type parameters**
- `T` — the type of the values; it needs `==` and a text form (see `to_string`)

**Parameters**
- `actual` — the value the code under test produced
- `unexpected` — the value it must not be

**Panics**
- if the values are equal: prints the location of the call and the value, and aborts (see `panic`)

**Example**
```pepper
expect_not_equal("a".repeat(2), "a");
```

## expect_true

```pepper
expect_true(condition: bool)
```

Panics unless `condition` holds. Unlike `assert`, it needs no message:
the location names the check.

**Parameters**
- `condition` — the condition that must hold

**Panics**
- if `condition` is false: prints the location of the call, and aborts (see `panic`)

**Example**
```pepper
expect_true("pepper".starts_with("pep"));
```

## expect_false

```pepper
expect_false(condition: bool)
```

Panics if `condition` holds.

**Parameters**
- `condition` — the condition that must not hold

**Panics**
- if `condition` is true: prints the location of the call, and aborts (see `panic`)

**Example**
```pepper
expect_false("pepper".is_empty);
```
