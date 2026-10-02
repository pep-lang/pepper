# The operating system

The `os` module reads what the operating system provides beyond the
running process: environment variables, clocks, and facts about the
machine and the user. Bring it in with `import os`. The full API is in the
[reference](../reference/os-module.md).

## Environment variables

`os.environment(name)` returns a variable's value as a `String?`: none when
it is not set, and an empty String when it is set to nothing.
`os.environment_variables()` returns them all as a `HashMap<String, String>`
from name to value.

```pepper
{{#include ../../examples/os-environment.pep}}
```

- On Windows, names ignore case (`Path` finds `PATH`), and values are read
  as UTF-16, so text outside the ANSI code page survives.
- On POSIX a value is whatever bytes the parent passed; one that is not
  valid UTF-8 is returned as it is.
- `os` only reads the environment. Changing the running process's own
  environment is not thread-safe on POSIX (`setenv` races with every other
  thread's `getenv`), so there is no `set_environment`. Give a child a
  different environment with `process.Command`'s `environment`,
  `remove_environment` and `clear_environment` instead (see
  [Processes](processes.md#environment-and-working-directory)).

## Time

Three value types cover time. Each is a [value struct](value-structs.md):
copied, compared with `==`, `<` and the other comparisons, and never
allocated.

- `Duration` is a span of time in nanoseconds, never negative. Make one
  with `from_seconds`, `from_milliseconds`, `from_microseconds` or
  `from_nanoseconds`, read it back with `seconds()`, `milliseconds()` and
  the others (rounded down), and add, subtract, multiply or divide it.
  Printing one shows it in the largest unit it reaches: `2.5s`, `15ms`,
  `40ns`.
- `Instant` reads a monotonic clock, for measuring how long something
  takes. It only moves forward, whatever the system's date is set to.
  `later - earlier` is the `Duration` between two instants, and
  `start.elapsed()` the time since one.
- `SystemTime` reads the wall clock: nanoseconds since the Unix epoch
  (1970-01-01 00:00:00 UTC). `unix_seconds()` is what file systems and most
  protocols record. Since the wall clock can be set back,
  `duration_since(earlier)` is an optional: none when `earlier` is later.

```pepper
{{#include ../../examples/os-time.pep}}
```

Subtracting a longer `Duration`, or a later `Instant`, panics: neither can
be negative.

## The machine and the user

```pepper
{{#include ../../examples/os-machine.pep}}
```

| Function | Returns |
|---|---|
| `system_os()` | the `OperatingSystem` the program was built for: `Linux`, `Mac`, `Windows` or `Wasi` |
| `system_name()` | the same as text: `"linux"`, `"macos"` or `"windows"` |
| `system_version()` | the kernel release on Linux, the product version on macOS (`14.5`), `major.minor.build` on Windows |
| `architecture()` | `"x64"`, `"aarch64"` or `"wasm32"`, as `[Target(Arch(...))]` names them |
| `hostname()` | the machine's host name |
| `logical_cpus()`, `physical_cpus()` | processor counts, the same as `async`'s |
| `total_memory()`, `page_size()` | physical memory and the virtual memory page size, in bytes |
| `user_name()` | the user the program runs as, or none |
| `home_directory()` | `HOME` (on Windows `USERPROFILE`), or the user database's entry, or none |
| `temp_directory()` | the directory for temporary files, the same as `io.Directory.temp()` |

## Current limitations

- Dates, time zones, and formatting a `SystemTime` as a date are not
  supported yet.
- `async.timeout` still takes milliseconds, not a `Duration`.
- `total_memory()` does not take a container's memory limit into account.
