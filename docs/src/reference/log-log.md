<!-- Generated from runtime/log/log.pep by `pep-doc reference`. Do not edit. -->

# Logging

Levels, fields, the output, and the functions that write a line.

Source: `runtime/log/log.pep`

## Level

```pepper
enum Level
```

How much a line matters, most important first.

As the level a target shows (`set_level`, `PEPPER_LOG`), each level also
shows the ones above it: `Info` shows errors, warnings and info lines.

### Cases

#### Off

```pepper
Off
```

Nothing: as the level a target shows, turns its lines off.

#### Error

```pepper
Error
```

Something failed (`error`).

#### Warning

```pepper
Warning
```

Something looks wrong but the program carries on (`warning`).

#### Info

```pepper
Info
```

What the program is doing, at the level of whole operations (`info`).

#### Debug

```pepper
Debug
```

Detail for finding a bug (`debug`).

#### Trace

```pepper
Trace
```

Step-by-step detail (`trace`).

## Format

```pepper
enum Format
```

How each line is written.

### Cases

#### Text

```pepper
Text
```

One readable line: the UTC time, the level, the target in brackets,
the message, `key=value` fields, and the call's location in
parentheses.

#### Json

```pepper
Json
```

One JSON object per line (JSON Lines), with the keys `time`,
`level`, `target` (when there is one), `message` and `location`, then
each field.

## Field

```pepper
struct Field
```

A key and value attached to a line. Make one with `field`.

### Fields

#### key

```pepper
var key: String = ""
```

The key.

#### value

```pepper
var value: String = ""
```

The value as JSON text: `200`, `"ann"`, `true`.

### Constructor

#### Field()

```pepper
construct(key: String, value: String)
```

Creates a field from a key and the JSON text of its value; `field`
makes the text from any value.

**Parameters**
- `key` — the key
- `value` — the value's JSON text

## field

```pepper
field<T>(key: String, value: T): Field
```

Makes a field for a line: `log.info("done", [log.field("ms", 12)])`.

The value is turned into JSON (see `json.encode`) when the field is
made, whether or not the line is written; guard costly fields with
`enabled`.

**Type parameters**
- `T` — the type of `value`

**Parameters**
- `key` — the key
- `value` — the value

**Returns**
- the field

**Example**
```pepper
import log;

main(): int {
    log.info("request done", [log.field("status", 200), log.field("path", "/")]);
    return 0;
}
```

## set_level

```pepper
set_level(level: Level, target: String = "")
```

Sets the level a target shows, or with no target the level every target
without its own shows. The default is `Level.Info`, unless the
`PEPPER_LOG` environment variable says otherwise.

**Parameters**
- `level` — the least important level to show; `Level.Off` shows nothing
- `target` — the target, as the logging functions' `target`; empty for the global level

**Example**
```pepper
import log;

main(): int {
    log.set_level(log.Level.Debug);
    log.set_level(log.Level.Warning, "http");
    log.debug("shown");
    log.info("not shown", target = "http");
    return 0;
}
```

## set_output

```pepper
set_output([Move] writer: io.Writer, format: Format = Format.Text)
```

Sends every line from now on to `writer` in `format`, instead of to
standard error. Lines are written whole, one `write_all` each, under a
lock, so lines from many threads and tasks never interleave. A failed
write is ignored. Colors are off.

**Parameters**
- `writer` — where lines go: a new value, or one handed over with `move(x)`, since the log keeps it
- `format` — how each line is written

**Example**
```pepper
import io;
import log;

main(): int {
    var file = io.File.create(io.Directory.temp().join("app.log")).value();
    log.set_output(move(file), log.Format.Json);
    log.info("started");
    return 0;
}
```

## enabled

```pepper
enabled(level: Level, target: String = ""): bool
```

Reports whether a line at `level` for `target` would be written, so a
caller can skip building a costly message or field.

Cheap when no target shows `level`: two atomic loads, with no lock.

**Parameters**
- `level` — the line's level
- `target` — the line's target; empty for none

**Returns**
- true when `target` shows `level`; false for `Level.Off`

**Example**
```pepper
import log;

main(): int {
    if (log.enabled(log.Level.Debug)) {
        var queue = [1, 2, 3];
        log.debug($"queue: {queue.count} jobs");
    }
    return 0;
}
```

## error

```pepper
error( message: String, fields: Array<Field> = Array<Field>(), target: String = "" )
```

Writes an error line: something failed.

**Parameters**
- `message` — the message
- `fields` — keys and values to add to the line (see `field`)
- `target` — the part of the program the line is about, which `set_level` and `PEPPER_LOG` can show or hide on its own; empty for none

**Example**
```pepper
log.error("cannot open the database", [log.field("path", path)]);
```

## warning

```pepper
warning( message: String, fields: Array<Field> = Array<Field>(), target: String = "" )
```

Writes a warning line: something looks wrong but the program carries on.

**Parameters**
- `message` — the message
- `fields` — keys and values to add to the line (see `field`)
- `target` — the part of the program the line is about; empty for none

**Example**
```pepper
log.warning("retrying", [log.field("attempt", 2)], target = "http");
```

## info

```pepper
info( message: String, fields: Array<Field> = Array<Field>(), target: String = "" )
```

Writes an info line: what the program is doing.

**Parameters**
- `message` — the message
- `fields` — keys and values to add to the line (see `field`)
- `target` — the part of the program the line is about; empty for none

**Example**
```pepper
log.info("listening", [log.field("port", 8080)]);
```

## debug

```pepper
debug( message: String, fields: Array<Field> = Array<Field>(), target: String = "" )
```

Writes a debug line: detail for finding a bug. Not shown by default.

**Parameters**
- `message` — the message
- `fields` — keys and values to add to the line (see `field`)
- `target` — the part of the program the line is about; empty for none

**Example**
```pepper
log.debug("cache miss", [log.field("key", key)], target = "cache");
```

## trace

```pepper
trace( message: String, fields: Array<Field> = Array<Field>(), target: String = "" )
```

Writes a trace line: step-by-step detail. Not shown by default.

**Parameters**
- `message` — the message
- `fields` — keys and values to add to the line (see `field`)
- `target` — the part of the program the line is about; empty for none

**Example**
```pepper
log.trace("read a frame", [log.field("bytes", 512)], target = "http");
```
