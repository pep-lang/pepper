# JSON

The `json` module reads JSON text into a `JsonValue`, lets you look values
up and change them, and writes them back as compact or indented text. It
also converts [structs](#structs) to JSON and back.

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

## Documents with comments

`parse` skips a JSONC file's comments. To change a file people edit, such
as a settings file, and write it back with its comments, read it with
`json.parse_document(text)`, which returns a `Result<JsonDocument,
JsonError>`:

```pepper
{{#include ../../examples/json-comments.pep}}
```

- `document.root` is the `JsonValue`; change it as any other.
- Each comment belongs to a value, by its path from the root `$`
  (`$.editor.tab_size`, `$.files[0]`): the comments on the lines before
  it, and those on the line it ends, after its comma. Comments before a
  closing bracket stay at the end of their array or object, and those
  around the whole value stay before or after it.
- `document.to_string()` writes the text indented, as `to_pretty_string`
  does (`to_string(indent = 4)` for four spaces), with every comment back
  in its place. A file in that layout reads and writes back unchanged.
- A comment whose value is removed is dropped. One whose path later names
  another value, such as an element shifted into its index, goes with
  that value.
- `document.comments(path)` returns the comments before a value, and
  `document.set_comments(path, ["// ..."])` replaces them.
- `parse_document` takes `path` and `max_depth` as `parse` does, and always
  accepts JSONC.

## Structs

`json.encode(value)` writes a struct as JSON text, and
`json.decode<T>(text)` reads one back. There is no code to write per type:
both walk the struct's properties with [reflection](reflection.md) while
compiling, so the conversion costs what hand-written code would.

```pepper
{{#include ../../examples/json-structs.pep}}
```

A struct's public [properties](properties.md) become an object's members,
in declaration order. Each property's type converts as follows, and the
same rules apply at the top level (`json.decode<Array<int>>("[1, 2]")`):

| Pepper | JSON |
|--------|------|
| an integer type (`int`, `u8`, `long`, ...) | a number; reading one checks that it has no fraction and fits the type |
| `float`, `double` | a number |
| `bool` | `true`, `false` |
| `String` | a string |
| an enum | a case that carries no values as its name (`"Safe"`); one that carries values as an object with the case's name as its one key, holding the values by name (`{"Circle": {"radius": 2}}`); [attributes](#attributes) choose other forms |
| `T?` | the value, or `null` when none; a missing key reads as none |
| `Array<T>` | an array |
| `HashMap<String, V>`, `OrderedMap<String, V>`, `Map<String, V>` | an object |
| a struct | an object, recursively |
| `json.JsonValue` | itself, for parts of a document with no fixed shape |

A struct reference that holds nothing (a `String`, array, struct or
reference enum field never assigned) is written as `null`, and `null` reads
back as one, so a value round-trips. Reading a case's value whose key is
missing is an error: `$.shapes[0].Circle: missing value 'radius'`. `null` for a number, `bool` or enum is an error.

### Attributes

The `serialize` module's attributes, which `json` uses (they need no
import of their own), change how a property is converted:

| Attribute | Effect |
|-----------|--------|
| `[Name("key")]` | writes and reads the property under `key` |
| `[Ignore]` | leaves the property out of both |
| `[Required]` | makes a missing key an error when reading |

On an enum and its cases, they choose how a case is written:

| Attribute | Effect |
|-----------|--------|
| `[Name("key")]` on a case | writes and reads the case under `key` instead of its own name |
| `[Tag("kind")]` on an enum | writes each case as an object naming it under `kind`, with its values beside the tag: `{"kind": "Circle", "radius": 2}`, `{"kind": "Point"}` |
| `[Tag("kind", content = "data")]` on an enum | puts the values in an object under `data` instead: `{"kind": "Circle", "data": {"radius": 2}}` |
| `[Untagged]` on an enum | writes no tag: a case's values as an object (`{"radius": 2}`), and a case that carries none as its name (`"Point"`) |

```pepper
{{#include ../../examples/json-enum-forms.pep}}
```

Reading an `[Untagged]` enum tries each case in order and takes the first
that reads without an error (with `UnknownKeys.Reject`, an extra key is
an error too), so a case whose values include another's goes first. When
none reads, the error says so: `$: found an object, which matches no case
of 'Size'`. A `[Tag]` enum's errors name its tag: `$: missing tag 'kind'`,
`$.kind: 'Hex' is not a case of 'Shape'`. A tag with the name of one of a
case's values is a compile error, since both would be written under one
key.

### Reading

`decode` makes a struct with its constructor that takes no arguments, then
reads in each property it finds a key for. A missing key leaves its
property at its default, unless the property is `[Required]`. It takes
optional arguments, usually passed by name:

| Argument | Default | Meaning |
|----------|---------|---------|
| `unknown_keys` | `UnknownKeys.Ignore` | What to do with a key that names no property: skip it, or with `UnknownKeys.Reject`, fail naming it. |
| `comments` | `false` | Accept JSONC, as `parse` does. |
| `path` | `""` | The name of the text, which the error's `to_string()` puts first. |

An error has a line and column as in [Errors](#errors). One in
converting a value also has its `value_path`, where in the document the
value is as a path from the root `$`, and its message starts with that
path. The line and column are the value's, or the enclosing object's for a
missing key:

```text
server.json:3:13: error: $.server.port: expected a number, found a string
server.json:7:21: error: $.tags[2]: expected a string, found null
server.json:4:24: error: $["max-connections"]: 70000 does not fit in 'u16'
server.json:1:1: error: $: missing required key 'port'
```

`json.to_json(value)` and `json.from_json<T>(value)` do the same
conversions to and from a `JsonValue` rather than text (with no text, a
`from_json` error has no line: `error: $.port: ...`), and
`json.encode(value, indent = 2)` writes indented text.

### Types it cannot convert

A property whose type has no JSON form, such as a pointer, a function, or
a `Result` (a result is not a value to send over the wire), is a compile
error naming the property. Notes follow the conversion back to the call
that asked for it:

```text
runtime/json/convert.pep:315:25: error: 'encode' cannot convert property 'outcome' of type 'Result<int>' to JSON
...
main.pep:10:16: note: 'encode<Job>' is used by 'main' here
   10 |     var text = json.encode(job);
      |                ^~~~~~~~~~~
```

## Current limits

- `parse` skips comments; only a `JsonDocument` keeps them, and
  `decode` never does. A document is always written indented.
- A struct's own conversion cannot be customized yet: a type converts as
  its properties do.
- Map keys must be `String`s.

The [reference](../reference/json-module.md) lists every function.
