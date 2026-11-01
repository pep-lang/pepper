# The operating system

The `os` module reports what the operating system provides beyond the
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

## Changing the environment

`os.set_environment(name, value)` sets a variable for the running process,
and `os.remove_environment(name)` removes one. Later reads see the change,
and so do the children the process starts afterwards.

```pepper
{{#include ../../examples/os-set-environment.pep}}
```

- Every read and change the runtime makes goes through one lock, so Pepper
  code never races with itself over the environment, from any thread.
- C code that calls `getenv` itself is outside that lock. On POSIX,
  `setenv` races with such a call on another thread (Rust 2024 marks its
  `set_var` `unsafe` for this reason), so set variables before starting
  threads that run C code reading them.
- A name that is empty or contains `=` or a NUL byte, or a value that
  contains a NUL byte, panics.
- On Windows names ignore case, and the C runtime's own `getenv` copy does
  not see the change. On WASI the change stays inside the program.
- To give only a child a different environment, use `process.Command`'s
  `environment`, `remove_environment` and `clear_environment` (see
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
  The [`time` module](time.md) turns it into a date and time, in UTC or a
  time zone, and back.

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
| `logical_cpus()`, `physical_cpus()` | processor counts, the same as `async`'s, capped by a Linux container's CPU quota |
| `total_memory()`, `page_size()` | physical memory, or a Linux container's lower memory limit, and the virtual memory page size, in bytes |
| `peak_memory()` | the most physical memory the process has held at once (its peak resident set), in bytes; 0 on WASI |
| `user_name()` | the user the program runs as, or none |
| `home_directory()` | `HOME` (on Windows `USERPROFILE`), or the user database's entry, or none |
| `temp_directory()` | the directory for temporary files, the same as `io.Directory.temp()` |
| `is_elevated()` | whether the program runs as root, or elevated ("Run as administrator") on Windows; never on WASI |

## Containers

On Linux, `total_memory()` and `logical_cpus()` report what a container
lets the program use, as the JVM and Go do, so a pool or a cache sized from
them fits inside it. Both read the process's cgroup and each cgroup above
it, under `/sys/fs/cgroup`, with cgroup v2 or v1:

- `total_memory()` returns the smallest of the physical memory and every
  memory limit found (`memory.max`, or v1's `memory.limit_in_bytes`), as
  `docker run --memory` sets it.
- `logical_cpus()` returns the smaller of the online processors and the
  smallest CPU quota (`cpu.max`, or v1's `cpu.cfs_quota_us` over
  `cpu.cfs_period_us`), rounded up to whole processors: `docker run
  --cpus=1.5` counts as 2. `physical_cpus()` is never more than that.

Where no limit is set, or the files cannot be read, they report the
machine.
