<!-- Generated from runtime/toml/parse.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Parsing

`parse`: reading a TOML document into a `TomlValue`, and `TomlError`,
what it reports when the text is not TOML.

Source: `runtime/toml/parse.pep`

## TomlError

```pepper
struct TomlError
```

What `parse` reports when the text is not TOML, and what `decode`
reports when a value does not fit its property: what is wrong, and the
line and column where it is.

`to_string()` renders it like a compiler error:
`pep.toml:4:12: error: expected '='`.

### Fields

#### message

```pepper
var message: String
```

What is wrong, worded like a compiler error (`expected '='`).

#### path

```pepper
var path: String
```

The path given to `parse`, which names the text in `to_string()`;
empty when none was given.

#### line

```pepper
var line: ulong
```

The line of the error, from 1; 0 for an error with no text to point
into, such as one from `from_toml`.

#### column

```pepper
var column: ulong
```

The column of the error, from 1, counting bytes as clang does; 0
when `line` is.

#### offset

```pepper
var offset: ulong
```

The byte offset of the error in the text, from 0.

#### value_path

```pepper
var value_path: String
```

Where in the document the value an error is about is, as a path from
the root `$` (`$.package.version`, `$.bin[0].name`); empty for an
error in the text's syntax. `decode` and `from_toml` set it, and
start `message` with it.

### Constructor

#### TomlError()

```pepper
construct(message: String = "", path: String = "", line: ulong = 1, column: ulong = 1, offset: ulong = 0)
```

Creates an error.

**Parameters**
- `message` — what is wrong
- `path` — the name of the text, or empty
- `line` — the line of the error, from 1
- `column` — the column of the error, from 1
- `offset` — the byte offset of the error, from 0

### Methods

#### to_string

```pepper
to_string(): String
```

Returns the error as a compiler prints one:
`path:line:column: error: message`, without the `path:` when there
is no path and without `line:column:` when `line` is 0.

**Returns**
- the rendered error

## parse

```pepper
parse(text: String, path: String = "", max_depth: ulong = 1000): Result<TomlValue, TomlError>
```

Parses a TOML 1.0 document into a `TomlValue`, a `Table`.

Every rule of TOML 1.0 is checked: a key or table defined twice, a table
extended after it was closed (an inline table, or one written with
dotted keys in another section), strings, numbers and dates as the
specification spells them. The text must be valid UTF-8; a byte-order
mark at the start is skipped. Tables keep their keys in the order they
were written. A line break in a multi-line string reads as `\n`, also
when the text has `\r\n`.

Arrays and inline tables nest as deeply as the text says, so the parser
keeps its own stack rather than recursing, and `max_depth` bounds it.

**Parameters**
- `text` — the TOML text
- `path` — the name of the text (a file name, say), which the error's `to_string()` puts first
- `max_depth` — how deeply arrays and inline tables may nest

**Returns**
- the document's table, or an error naming the first problem and its line and column

**Example**
```pepper
import toml;

var parsed = toml.parse("[server]\nport = 8080\n");
assert(parsed.value()["server"]["port"].as_int().value() == 8080, "a lookup");
var bad = toml.parse("name \"demo\"", path = "pep.toml");
assert(bad.error().to_string() == "pep.toml:1:6: error: expected '=' after the key", "where");
```
