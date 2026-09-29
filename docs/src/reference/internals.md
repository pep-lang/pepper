<!-- Generated from runtime/internals.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Built-in functions

Source: `runtime/internals.pep`

## memcpy

```pepper
extern void memcpy(void* dest, void* src, ulong n)
```

Copies `n` bytes from `src` to `dest` (the C library's `memcpy`).

The regions must not overlap, and both must be valid for `n` bytes.
Nothing is bounds-checked, and no reference counts change: copying a
struct reference with it neither acquires nor releases. Runs in O(n).
This declaration discards C's return value.

**Parameters**
- `dest` — the start of the destination region, a `__ptr<void>`
- `src` — the start of the source region, a `__ptr<void>`
- `n` — the number of bytes to copy; 0 copies nothing

## assert

```pepper
assert(condition: bool, msg: __ptr<char>): void
```

Panics with `msg` when `condition` is false; otherwise does nothing.

The check always runs; there is no release mode that removes it.
The message is a raw `__ptr<char>` (C `char*`), not a `String`. A string
literal is passed as its global pointer with no temporary allocation,
which keeps hot paths like array index bounds checks allocation-free. A
non-literal `String` message is lowered to `msg.c_str()` at the call site.

**Parameters**
- `condition` — the condition that must hold
- `msg` — the NUL-terminated message to print on failure; `__null` prints a generic message

**Panics**
- if `condition` is false: prints `msg` and aborts (see `panic`)

**Example**
```pepper
    assert(count > 0, "count must be positive");
```

## panic

```pepper
panic(msg: __ptr<char>)
```

Prints `msg` and aborts the program. It never returns.

Writes `msg` and a newline to standard output with `puts`, or
"Assertion failed with no additional information" when `msg` is
`__null`. Then it flushes every C output stream, so the message is not
lost when stdout is a pipe, and calls C `abort()`. No destructors or
releases run, and the process ends abnormally (SIGABRT on POSIX).

**Parameters**
- `msg` — the NUL-terminated message to print, or `__null`

**Panics**
- always

**Example**
```pepper
    panic("unreachable");
```

## trace_region

```pepper
trace_region(ptr: __ptr<void>, size: ulong, name: __ptr<char>)
```

Prints `name`, the address `ptr`, and the first 8 bytes at `ptr` when
tracing is on. Does nothing otherwise.

Tracing is on when the `PEP_TRACE` environment variable is set to any
value, even an empty one. It is read once at program start. The line has
the form `name: AAAAAAAAAAAAAAAAWWWWWWWWWWWWWWWW`: 16 uppercase hex
digits of the address, then, with no separator, the first 8 bytes read as
a little-endian 64-bit word. The word is omitted when `ptr` is `__null`
or `size` is less than 8. Only those 8 bytes are read, whatever `size` is.
The line goes to standard output.

Each traced call allocates buffers it never frees, so `_pep_live_allocs()`
counts them. `name` must be shorter than about 470 bytes.

**Parameters**
- `ptr` — the start of the region to trace
- `size` — the region's size in bytes; the word is printed only when it is at least 8
- `name` — a NUL-terminated label for the line, or `__null` for none

## trace_ptr

```pepper
trace_ptr(ptr: __ptr<void>, name: __ptr<char>)
```

Prints `name: ` followed by the address `ptr` as 16 uppercase hex digits
when tracing is on (the `PEP_TRACE` environment variable is set, checked
once at program start). Does nothing otherwise.

Each traced call allocates buffers it never frees, so
`_pep_live_allocs()` counts them. `name` must be shorter than about 490
bytes.

**Parameters**
- `ptr` — the address to print; it is not dereferenced
- `name` — a NUL-terminated label for the line, or `__null` for none

## trace_int

```pepper
trace_int(value: long, name: __ptr<char>)
```

Prints `name: ` followed by `value` in signed decimal when tracing is on
(the `PEP_TRACE` environment variable is set, checked once at program
start). Does nothing otherwise.

Each traced call allocates buffers it never frees, so
`_pep_live_allocs()` counts them. `name` must be shorter than about 485
bytes.

**Parameters**
- `value` — the number to print
- `name` — a NUL-terminated label for the line, or `__null` for none

**Example**
```pepper
    trace_int(count, "count");   # prints "count: 3" under PEP_TRACE=1
```
