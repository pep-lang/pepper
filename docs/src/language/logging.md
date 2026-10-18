# Logging

The `log` module writes lines with a level, a message, key/value fields and
the place of the call, from any thread or task. Bring it in with
`import log`.

```pepper
{{#include ../../examples/logging-basics.pep}}
```

On standard error this prints:

```text
2026-10-17T23:48:53.555Z INFO  started (logging-basics.pep:6:5)
2026-10-17T23:48:53.555Z WARN  [storage] disk almost full free_mb=120 (logging-basics.pep:7:5)
2026-10-17T23:48:53.555Z DEBUG [storage] scanning path="/var/data" (logging-basics.pep:12:9)
```

| Function | Does |
|---|---|
| `log.error(message)`, `warning`, `info`, `debug`, `trace` | Writes a line at that `Level`. |
| `log.field(key, value)` | Makes a `Field` for a line's `fields`; the value is written as JSON. |
| `log.set_level(level, target)` | Sets the least important level shown, for one target or (with no target) for all. |
| `log.enabled(level, target)` | Whether a line at `level` for `target` would be written. |
| `log.set_output(writer, format)` | Sends lines to a `Writer` in `Format.Text` or `Format.Json`. |

## Lines

Each logging function takes the message, then two optional arguments,
usually named:

- `fields`: an array of `log.field(key, value)`. A text line shows each as
  `key=value`, with the value's JSON text (`200`, `"/var/data"`, `true`).
- `target`: the part of the program the line is about, such as `"http"`.
  A text line shows it in brackets, and levels can be set for it alone.

Each line names the place of the call, as `assert` does. The time is UTC,
to the millisecond. On a terminal the level is in color,
unless the `NO_COLOR` environment variable is set (on Windows, only in a
console already in virtual terminal mode, such as Windows Terminal).

## Levels

The levels, most important first, are `Error`, `Warning`, `Info`, `Debug`
and `Trace`. A target shows its level and every level above it; `Off`
shows nothing. By default every target shows `Info`.

The `PEPPER_LOG` environment variable sets the levels when the program
first logs: comma-separated items, each a level for every target or
`target=level` for one. The names are `off`, `error`, `warning` (or
`warn`), `info`, `debug` and `trace`, in any case. An item with an unknown
level is reported on standard error and skipped.

```text
$ PEPPER_LOG=warning,http=debug ./server
```

`log.set_level` changes them from code. A target named in `PEPPER_LOG` or
`set_level` uses its own level; every other target uses the global one.

## Cost

A line no target shows costs two atomic loads: no lock and no formatting.
The arguments are still evaluated, so a message or field that is costly to
build goes inside an `if (log.enabled(...))`, as in the example.

## Output and threads

Lines go to standard error as text until `log.set_output` names a
[`Writer`](../reference/io-stream.md), such as a file or a socket, and a format:

- `Format.Text`: the readable lines above.
- `Format.Json`: one JSON object per line (JSON Lines) with `time`,
  `level`, `target` (when there is one), `message` and `location`, then
  each field.

The log keeps the writer, so it must be a new value or one handed over
with `move(x)`. A `File` keeps its path, so make it from `copy(path)`, as
the example does.

Each line is built first and then written whole, with one `write_all`,
under a [`Mutex`](threads.md#mutexes-and-conditions), so lines from many threads and
tasks never interleave. A task waiting for that lock parks instead of
blocking its worker thread. A failed write is ignored.

## Not yet

- Levels cannot be removed at compile time.
- The runtime's own modules (such as `http`) and the `pep-*` tools do not
  log through `log` yet.
