<!-- Generated from runtime/copy.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# copy.pep

Deep copies: `copy(value)` makes a copy that shares no object that is
not thread-safe with the original, so it can be handed to another thread;
`Copyable<T>` lets a type say how it is copied.

Source: `runtime/copy.pep`

## copy

```pepper
copy<T>(value: T): T
```

Returns a copy of `value` that shares no non-thread-safe object with it,
so the copy can be handed to another thread.

Every struct reachable from `value` whose type is not thread-safe is
copied once. Objects referenced twice stay shared inside the copy, and
cycles are preserved. Thread-safe objects (`[Shared]` structs, `shared`
function values) are not copied: the copy references the same ones. A
weak reference to a copied object points at its copy; a weak reference to
an object outside the copied value becomes null.

A struct is copied field by field, without running its constructor,
unless it implements `Copyable<T>`. A struct with a destructor or a raw
pointer field must implement `Copyable<T>` to be copied, since copying
its fields would share what it owns; `String`, `Array`, `HashMap` and
`HashSet` do. Copying such a struct that does not, or a plain function
value, is a compile error.

A trait value is copied by copying the struct behind it, which is known
only at run time: when that struct cannot be copied, `copy` panics.

Runs in O(size of the value) and allocates each copied object.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `value` — the value to copy

**Returns**
- a copy that shares no non-thread-safe object with `value`; `value` itself when `T` is thread-safe

**Panics**
- if `value` reaches a trait value holding a struct that cannot be copied

**Example**
```pepper
    var names = Array<String>();
    names.append("ada");
    var copied = copy(names);
    copied[0].append(" lovelace");   # names[0] is still "ada"
```

## move

```pepper
move<T>([MoveSource] value: T): T
```

Hands over the reference `value` holds and leaves it null, with no copy
and no change to any count: the result is the same object.

`value` must be a local variable (or a `[Move]` parameter) that holds
the only reference to its value: nothing else may refer to it or to
anything it reaches. The compiler checks that, and that the variable is
not used again until it is assigned a new value. Use it to pass a value
you built to a parameter that takes a new value, such as `Channel.send`
or `Mutex.replace`, without the cost of `copy`.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `value` — the variable to move from

**Returns**
- the value `value` held, which nothing else references

**Example**
```pepper
    var lines = Array<String>();
    lines.append("first");
    var log = async.Mutex<Array<String>>(move(lines));   # lines is null now
```

## Copyable

```pepper
trait Copyable<T>
```

A type that says how `copy` copies it, for a struct that `copy` cannot
copy field by field: one with a destructor or a raw pointer field, such as
a container that owns a buffer.

Declare it with `extend Buffer with Copyable<Buffer>;` and give the
struct a `copy(Copies copies)` method. The method builds the copy and
copies each value it holds with `copies.copy(value)`, which reuses a copy
already made, so objects referenced twice stay shared.

**Type parameters**
- `T` — the implementing type

**Example**
```pepper
    struct Buffer {
        __ptr<u8> data;
        ulong size;

        construct(ulong size = 0) {
            data = _pep_malloc(size);
            this.size = size;
        }

        destruct {
            _pep_free(data);
        }

        Buffer copy(Copies copies) {
            var made = Buffer(size);
            var i: ulong = 0;
            while (i < size) {
                made.data[i] = data[i];
                i = i + 1;
            }
            return made;
        }
    }

    extend Buffer with Copyable<Buffer>;
```

### Methods

#### copy

```pepper
copy(copies: Copies): T
```

Returns a copy of this value, for `copy`.

Copy each struct value this one holds with `copies.copy(value)`. A
value that can hold a reference back to itself calls
`copies.register(this, made)` before copying what it holds, so the
cycle leads back to the copy.

**Parameters**
- `copies` — the objects copied so far

**Returns**
- the copy

## Copies

```pepper
struct Copies
```

The objects one `copy` call has copied so far, so each is copied once:
objects referenced twice stay shared inside the copy, and cycles end.

`copy(value)` makes one and passes it to every `Copyable<T>`
implementation it calls; programs do not create their own.

### Constructor

#### Copies()

```pepper
construct()
```

Creates an empty set of copies.

### Methods

#### copy

```pepper
copy<T>(value: T): T
```

Returns the copy of `value`: `value` itself when `T` is thread-safe,
the copy already made when the same object was copied before, and a
new copy otherwise.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `value` — the value to copy

**Returns**
- the copy

**Example**
```pepper
    Pair copy(Copies copies) {
        return Pair(copies.copy(first), copies.copy(second));
    }
```

#### register

```pepper
register<T>(original: T, made: T)
```

Records `made` as the copy of `original`, so that copying `original`
again returns `made`. A `Copyable<T>` implementation calls it before
copying the values it holds when one of them may lead back to it.

**Type parameters**
- `T` — the type of the value, a struct

**Parameters**
- `original` — the object being copied
- `made` — its copy
