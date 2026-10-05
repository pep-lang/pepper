<!-- Generated from runtime/internals.pep by `pep-doc reference`. Do not edit. -->

# Built-in functions

`assert` and `panic`, which every program can call without an import.

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
- if `condition` is false: prints the location and `message`, and aborts (see `panic`)

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
- if `condition` is false: prints the location and `message`, and aborts (see `panic`)

**Example**
```pepper
assert(count > 0, "count must be positive");
```

## panic

```pepper
panic(message: String)
```

Prints `message` and aborts the program. It never returns.

Flushes every C output stream, so output printed so far is not lost,
then writes `location: panic: message` and a newline to standard error
("Assertion failed with no additional information" when `message` is
null), followed in a build without `-O` by a backtrace of the calls
that led there (`PEPPER_BACKTRACE` overrides the build; see the `debug`
module's `print_backtrace`), and calls C `abort()`. No destructors or
releases run, and the process ends abnormally (SIGABRT on POSIX).

The location is the call's `file:line:col`, which the compiler passes
in a hidden parameter, the way a C++ `std::source_location` default
argument works. A function that panics on its caller's behalf, as the
runtime's indexers do, declares that parameter itself and passes it on,
so the panic names its caller's line:

    check_positive(value: int, location: __ptr<char> = __caller_location()) {
        if (value <= 0) {
            panic("expected a positive value", location);
        }
    }

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

Reports `message`, a NUL-terminated C string (a generic message when it
is `__null`), as a panic and aborts, as `panic(String)` does. A string
literal message picks this overload, so it allocates nothing.

**Parameters**
- `message` — the text to print, or `__null`

**Panics**
- always

**Example**
```pepper
panic("unreachable");
```
