# JSON

The `json` module reads JSON text into a `JsonValue`, lets you look values
up and change them, and writes them back as compact or indented text.

```pepper
{{#include ../../examples/json-basics.pep}}
```

## Values

`json.JsonValue` is an [enum](enums.md) whose cases carry values, so
`match` handles each kind:

| Case | Holds | JSON |
|------|-------|------|
| `Null` | nothing | `null` |
| `Bool(value: bool)` | the boolean | `true`, `false` |
| `Integer(value: long)` | an integer within ±(2^53 − 1) | `42`, `-7` |
| `Number(value: double)` | any other number | `2.5`, `1e3`, `9007199254740993` |
| `String(value: String)` | the string | `"hi"` |
| `Array(items: Array<JsonValue>)` | the elements | `[1, 2]` |
| `Object(members: OrderedMap<String, JsonValue>)` | the members, in insertion order | `{"a": 1}` |

- **Numbers keep their form.** A number written without a fraction or an
  exponent is an `Integer` when it is within ±(2^53 − 1), the range every
  JSON implementation agrees on (RFC 7493). Any other number, including a
  larger integer, is a `Number`.
- **Make values** with the cases (`JsonValue.Integer(42)`,
  `JsonValue.String("a")`, `JsonValue.Null`), and containers with
  `JsonValue.object()` and `JsonValue.array(items)`.
- **Containers are shared.** An `Array` or `Object` holds its array or map
  by reference, so changing it through `value[key] = ...`, `append`, or the
  map from `as_object()` changes every holder of the value.

## Looking values up

| Expression | Result |
|------------|--------|
| `value["key"]` | the member, or `Null` when missing or not an object |
| `value[index]` | the element, or `Null` when out of range or not an array |
| `value.as_string()`, `as_bool()`, `as_double()` | the value, or none for another kind |
| `value.as_int()` | an `Integer`, or a `Number` with no fraction that fits in a `long`; otherwise none |
| `value.as_array()`, `as_object()` | the array or map itself, or none |
| `value.is_null()` | whether it is `Null` |
| `value.contains("key")` | whether an object has the member, even a `null` one |

A lookup that finds nothing gives `Null` rather than panicking, so lookups
chain and a default goes at the end:
`root["server"]["port"].as_int().value_or(8080)`.

## Changing values

- `value["key"] = member` sets an object's member. A new key goes at the
  end; an existing key keeps its place. It panics on a value that is not an
  object.
- `value[index] = element` replaces an array's element, and
  `value.append(element)` adds one at the end. Both panic on a value that is
  not an array.
- `value.remove("key")` removes an object's member and says whether it was
  there.

## Parsing

`json.parse(text)` returns a `Result<JsonValue, JsonError>`. It is strict
RFC 8259:

- The text holds one value, with only spaces, tabs and line breaks around
  it. A byte-order mark at the start is skipped.
- The text must be valid UTF-8; an invalid byte is an error at that byte.
- A string cannot hold a raw control character (write `\n`), and a `\u`
  escape of an unpaired surrogate (`"\uD800"`) is an error.
- No comments, trailing commas, single quotes, `NaN`, leading zeros
  (`01`) or `+` signs.
- When an object repeats a key, the last value wins, in the place of the
  first.

`parse` takes optional arguments, usually passed by name:

| Argument | Default | Meaning |
|----------|---------|---------|
| `comments` | `false` | Accept JSONC, as VS Code's settings files are: `//` and `/* */` comments, and a comma after the last element or member. |
| `path` | `""` | The name of the text, which the error's `to_string()` puts first. |
| `max_depth` | `1000` | How deeply arrays and objects may nest. |

The parser keeps its own stack rather than recursing, so deep nesting in the
text cannot overflow the call stack. `max_depth` still bounds it, because
releasing a value releases its nested values recursively.

### Errors

A `JsonError` has the `message`, the `line` and `column` (from 1, counting
bytes) and the byte `offset`. `to_string()` renders it like a compiler
error:

```text
config.json:3:3: error: expected ',' or '}'
```

Without a `path`, it starts at the line: `3:3: error: expected ',' or '}'`.

## Writing

- `value.to_string()` writes compact text, with no spaces or line breaks:
  `{"id":42,"tags":["a","b"]}`. String interpolation uses it too.
- `value.to_pretty_string()` puts each element and member on its own line,
  indented two spaces per level (`to_pretty_string(indent = 4)` for four),
  with a space after each `:`. An empty array or object stays `[]` or `{}`.
- Strings are written as UTF-8, escaping `"`, `\` and the control
  characters. `to_string(ascii_only = true)` and
  `to_pretty_string(ascii_only = true)` also escape everything outside ASCII
  as `\u`, with a surrogate pair past U+FFFF.
- A `Number` is written as Pepper writes a `double` (`0.5`, `1000.0`,
  `1e+16`), so it reads back as a `Number`. NaN and the infinities, which
  JSON cannot spell, are written as `null`.
- Objects keep their keys in insertion order, so parsing a document and
  writing it back keeps its order.

## Current limits

- Comments are skipped when parsing JSONC; they are not kept in the value
  or written back yet.
- Converting between JSON and structs (`json.encode`, `json.decode<T>`)
  is not supported yet.

The [reference](../reference/json-module.md) lists every function.
