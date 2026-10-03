<!-- Generated from runtime/handle.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Handle

`Handle<T>`: owns a resource that Pepper's reference counting does not
know about, such as a C library's object, and releases it when the last
reference to the handle goes away, like C#'s `SafeHandle`.

Source: `runtime/handle.pep`

## Handle

```pepper
struct Handle<T>
```

Owns a raw resource and calls a release function on it once, when the
handle is destroyed or `release()` is called, whichever comes first.

Use it to tie a C library's object (a `__ptr<void>` from an `extern`, a
file descriptor) to Pepper's lifetimes: hold a `Handle` in a struct
field, and the resource is freed when the struct is. A handle is a
reference like any struct, so copies share one resource, and it is
released when the last copy goes away. `detach()` takes the resource
back without releasing it.

`release` is an ordinary function value, so a closure may capture what
the release needs (such as an owner that must outlive the resource:
holding it in the closure keeps it alive until the release runs).

**Type parameters**
- `T` — the type of the raw resource, usually `__ptr<void>` or an integer

**Example**
```pepper
    extern void* malloc(ulong size);
    extern void free(void* p);

    main(): int {
        var buffer = Handle<__ptr<void>>(malloc(16), (p) => free(p));
        # use buffer.value; free runs when `buffer` goes out of scope
        return 0;
    }
```

### Properties

#### value

```pepper
var value: T { get; }
```

The resource. It stays readable after the handle is released or
detached, but it no longer refers to anything the handle owns.

### Constructor

#### Handle()

```pepper
construct(value: T, release: (T) => void)
```

Creates a handle that owns `value` and calls `release(value)` when
it is destroyed.

**Parameters**
- `value` — the resource to own
- `release` — the function that frees `value`; it is called at most once

### Methods

#### is_owned

```pepper
is_owned(): bool
```

Reports whether the handle still owns its resource: false after
`release()` or `detach()`.

**Returns**
- true while the resource has not been released or detached

#### release

```pepper
release()
```

Releases the resource now instead of when the handle is destroyed.
Calling it again, or after `detach()`, does nothing.

#### detach

```pepper
detach(): T
```

Gives up ownership without releasing the resource, which the caller
then frees itself.

**Returns**
- the resource
