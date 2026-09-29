<!-- Generated from runtime/iterator.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Iterators

Source: `runtime/iterator.pep`

## Iterator

```pepper
trait Iterator<T>
```

Something a `for` loop can step through, one element at a time.

`for (var x in source)` drives a source that declares `next()` and
`current()` directly: it calls `next()` before each pass and binds
`current()` to the loop variable while `next()` returns true. A type whose
`for` loop should go through a separate iterator implements `Iterable<T>`
instead. A type with neither protocol is a compile error in a `for` loop.

The loop goes by the methods a type has, so declaring the trait is
optional. Declaring it (`extend Foo with Iterator<int> {}`) checks that
the methods match and lets the type be used as an `Iterator<int>` value,
which a `for` loop drives through the trait.

**Type parameters**
- `T` — the type of the elements produced

**See also**
- `Iterable`

**Example**
```pepper
    struct Countdown {
        int Remaining;
        int Now;

        new(this.Remaining = 0) {}

        bool next() {
            if (Remaining == 0) {
                return false;
            }
            Now = Remaining;
            Remaining = Remaining - 1;
            return true;
        }

        int current() {
            return Now;
        }
    }

    extend Countdown with Iterator<int> {}

    main(): int {
        var total = 0;
        for (int n in Countdown(3)) {
            total = total + n;   # visits 3, 2, 1
        }
        return total;
    }
```

### Methods

#### next

```pepper
bool next()
```

Advances to the next element.

The first call moves to the first element, if any. Once it returns
false it must keep returning false.

**Returns**
- true if there is a current element, false when the elements are exhausted

#### current

```pepper
T current()
```

Returns the element the last successful `next()` moved to.

Calling it before the first `next()`, or after `next()` returned false,
is an error; the runtime's iterators panic in that case.

**Returns**
- the current element

## Iterable

```pepper
trait Iterable<T>
```

Something that hands out an `Iterator<T>` over its elements, such as
`Array<T>` and `String` (which yields one code point at a time, as a
`String`).

`for (var x in source)` calls `source.iterate()` once, then drives the
returned iterator with `next()` and `current()`. When a type declares both
`iterate()` and `next()`/`current()`, the loop uses `iterate()`.

**Type parameters**
- `T` — the type of the elements produced

**See also**
- `Iterator`

**Example**
```pepper
    var nums = Array<int>();
    nums.append(1);
    nums.append(2);
    var total = 0;
    for (var x in nums) {
        total = total + x;
    }
```

### Methods

#### iterate

```pepper
iterate(): Iterator<T>
```

Returns a new iterator positioned before the first element.

The result may be any type that satisfies `Iterator<T>` (for example
`ArrayIterator<T>`); each call starts a fresh, independent pass.

**Returns**
- an iterator over the elements
