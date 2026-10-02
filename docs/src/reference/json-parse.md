<!-- Generated from runtime/json/parse.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Parsing

`parse`: reading JSON text into a `JsonValue`, and `JsonError`, what it
reports when the text is not JSON.

Source: `runtime/json/parse.pep`

## JsonError

```pepper
struct JsonError
```

What `parse` reports when the text is not JSON: what is wrong, and the
line and column where it is.

`to_string()` renders it like a compiler error:
`config.json:3:17: error: expected ',' or '}'`.

### Fields

#### message

```pepper
var message: String
```

What is wrong, worded like a compiler error (`expected ':'`).

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

The line of the error, from 1; 0 for an error from `from_json`, which
has no text to point into.

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
the root `$` (`$.server.port`); empty for an error in the text's
syntax. `decode` and `from_json` set it, and start `message` with it.

### Constructor

#### JsonError()

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
parse( text: String, comments: bool = false, path: String = "", max_depth: ulong = 1000 ): Result<JsonValue, JsonError>
```

Parses JSON text into a `JsonValue`.

Parsing is strict RFC 8259: one value, surrounded only by spaces, tabs
and line breaks. A byte-order mark at the start is skipped. The text
must be valid UTF-8, and a string cannot hold a raw control character
or a `\u` escape of an unpaired surrogate (`"\uD800"`). When an object
repeats a key, the last value wins, in the place of the first.

With `comments = true` the text may be JSONC, as VS Code's settings
files are: `//` line comments, `/* */` block comments, and a trailing
comma after the last element or member. The comments are skipped.

Nesting comes from the text, so the parser keeps its own stack rather
than recursing, and `max_depth` bounds it.

**Parameters**
- `text` — the JSON text
- `comments` — whether to accept comments and trailing commas
- `path` — the name of the text (a file name, say), which the error's `to_string()` puts first
- `max_depth` — how deeply arrays and objects may nest

**Returns**
- the value, or an error naming the first problem and its line and column

**Example**
```pepper
    import json;

    var parsed = json.parse("{\"server\": {\"port\": 8080}}");
    assert(parsed.value()["server"]["port"].as_int().value() == 8080, "a lookup");
    var bad = json.parse("[1 2]", path = "list.json");
    assert(bad.error().to_string() == "list.json:1:4: error: expected ',' or ']'", "where");
```
