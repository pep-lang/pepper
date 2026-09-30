<!-- Generated from runtime/internals.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Built-in functions

Source: `runtime/internals.pep`

## assert

```pepper
assert(condition: bool, message: String)
```

Panics with `message` when `condition` is false; otherwise does nothing.

The check always runs; there is no release mode that removes it. A
string literal message picks the `__ptr<char>` overload instead, which
builds no `String`. Any other message is evaluated before the call.

**Parameters**
- `condition` — the condition that must hold
- `message` — the text to print on failure; a null `String` prints a generic message

**Panics**
- if `condition` is false: prints `message` and aborts (see `panic`)

**Example**
```pepper
    assert(count > 0, "count must be positive");
```

## assert

```pepper
assert(condition: bool, message: __ptr<char>)
```

Checks that `condition` holds; if not, panics with `message`, a
NUL-terminated C string. A string literal message picks this overload,
so an assertion that holds builds no `String`.

**Parameters**
- `condition` — the condition that must hold
- `message` — the text to print on failure, or `__null` for a generic message

**Panics**
- if `condition` is false: prints `message` and aborts (see `panic`)

**Example**
```pepper
    assert(count > 0, "count must be positive");
```

## panic

```pepper
panic(message: String)
```

Prints `message` and aborts the program. It never returns.

Writes `message` and a newline to standard output, or "Assertion failed
with no additional information" when `message` is null. Then it flushes
every C output stream, so the message is not lost when stdout is a pipe,
and calls C `abort()`. No destructors or releases run, and the process
ends abnormally (SIGABRT on POSIX).

**Parameters**
- `message` — the text to print

**Panics**
- always

**Example**
```pepper
    panic("unreachable");
```

## panic

```pepper
panic(message: __ptr<char>)
```

Writes `message`, a NUL-terminated C string, and a newline to standard
output (a generic message when it is `__null`), flushes every C output
stream, and aborts, as `panic(String)` does. A string literal message
picks this overload, so it allocates nothing.

**Parameters**
- `message` — the text to print, or `__null`

**Panics**
- always

**Example**
```pepper
    panic("unreachable");
```
