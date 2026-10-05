<!-- Generated from runtime/json/convert.pep by `pep-doc reference`. Do not edit. -->

# Struct conversion

Struct conversion: `encode` and `decode` turn Pepper values into JSON text
and back, through reflection, with no per-type code to write.

Source: `runtime/json/convert.pep`

## UnknownKeys

```pepper
enum UnknownKeys
```

What `decode` does with an object key that names no property of the
struct it is read into.

### Cases

#### Ignore

```pepper
Ignore
```

Skips the key and its value.

#### Reject

```pepper
Reject
```

Fails with an error naming the key and its path.

## to_json

```pepper
to_json<T>(value: T): JsonValue
```

Converts `value` to a `JsonValue`.

`T` may be a number type, `bool`, `String`, an enum (a case that carries
no values as its name, `"Point"`; one that carries values as
`{"Circle": {"radius": 2}}`; `[Tag]` and `[Untagged]` choose other forms), `Optional<U>` (the value, or `null`), `Array<U>`, a map with `String` keys (`HashMap`, `OrderedMap` or
`Map`) as an object, `JsonValue` itself, or a struct, whose public
properties become an object's members in declaration order. Element and
property types follow the same rules, so structs nest.

A struct property takes its key from `[Name("key")]` when it has one,
and is left out when marked `[Ignore]` (the attributes of the `serialize`
module, which `json` exports). A property of a struct type that holds no
object (a struct field never assigned) is written as `null`. An empty
`Array`, even one never assigned, is written as `[]`.

The conversion is generated while compiling, by a `static` block per
type. A type it cannot convert, such as a `Result` or an `io.File`, is a
compile error naming the property:
`'encode' cannot convert property 'outcome' of type 'Result<int>' to JSON`.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `value` — the value to convert

**Returns**
- the value as JSON

**Example**
```pepper
import json;

struct Point {
    var x: int;
    var y: int;
}

main(): int {
    var p = Point();
    p.x = 1;
    p.y = 2;
    assert(json.to_json(p)["y"].as_int().value() == 2, "a member");
    return 0;
}
```

## encode

```pepper
encode<T>(value: T, indent: int = 0, ascii_only: bool = false): String
```

Writes `value` as JSON text, converting it as `to_json` does.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `value` — the value to write
- `indent` — spaces per nesting level; 0, the default, writes compact text on one line
- `ascii_only` — whether to escape every character outside ASCII as `\u`

**Returns**
- the JSON text

**Example**
```pepper
import json;

struct ServerConfig {
    var host: String;
    var port: int;
    [Name("max-connections")]
    var max_connections: int;
    [Ignore]
    var started_at: long;
}

main(): int {
    var config = ServerConfig();
    config.host = "localhost";
    config.port = 8080;
    config.max_connections = 16;
    var text = json.encode(config);
    assert(text == "{\"host\":\"localhost\",\"port\":8080,\"max-connections\":16}", "compact");
    return 0;
}
```

## from_json

```pepper
from_json<T>(value: JsonValue, unknown_keys: UnknownKeys = UnknownKeys.Ignore): Result<T, JsonError>
```

Converts a `JsonValue` to a `T`, the reverse of `to_json`.

A struct is made with its constructor that takes no arguments, then each
property found in the object is read in. A missing key leaves its
property at its default, unless the property is marked `[Required]`,
which makes it an error; a property marked `[Ignore]` is never read. A
key that names no property is skipped, or with
`unknown_keys = UnknownKeys.Reject` is an error.

A number converts to an integer type when it has no fraction and fits
the type, and to `float` or `double` always. `null` converts only to an
`Optional` (as none) and to `JsonValue`.

An error names where in the document it is, as a path from the root `$`
in its `value_path` and at the start of its message, and has no line or
column, since there is no text: `$.server.port: expected a number, found
a string`.

**Type parameters**
- `T` — the type to convert to

**Parameters**
- `value` — the JSON value
- `unknown_keys` — what to do with an object key that names no property

**Returns**
- the converted value, or the first error

**Example**
```pepper
import json;

struct Point {
    var x: int;
    var y: int;
}

main(): int {
    var parsed = json.parse("{\"x\": 1, \"y\": 2}");
    var p = json.from_json<Point>(parsed.value());
    assert(p.value().y == 2, "a property");
    return 0;
}
```

## decode

```pepper
decode<T>( text: String, unknown_keys: UnknownKeys = UnknownKeys.Ignore, comments: bool = false, path: String = "" ): Result<T, JsonError>
```

Parses JSON text and converts it to a `T`: `parse`, then `from_json`.

**Type parameters**
- `T` — the type to convert to

**Parameters**
- `text` — the JSON text
- `unknown_keys` — what to do with an object key that names no property
- `comments` — whether to accept JSONC: comments and trailing commas
- `path` — the name of the text (a file name, say), which the error's `to_string()` puts first

**Returns**
- the value, or the first error: a syntax error, or a conversion error with its path in the document; either has its line and column

**Example**
```pepper
import json;

struct ServerConfig {
    var host: String;
    [Required]
    var port: int;
    var tags: Array<String>;
    var timeout: int?;
}

main(): int {
    var config = json.decode<ServerConfig>("{\"host\": \"a\", \"port\": 80, \"tags\": [\"x\"]}");
    assert(config.value().port == 80, "a number");
    assert(config.value().tags[0] == "x", "an array");
    assert(config.value().timeout.is_empty(), "a missing optional");

    var bad = json.decode<ServerConfig>("{\"port\": \"80\"}", path = "server.json");
    assert(bad.error().to_string() == "server.json:1:10: error: $.port: expected a number, found a string", "a path");
    return 0;
}
```
