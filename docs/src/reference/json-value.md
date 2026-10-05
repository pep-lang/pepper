<!-- Generated from runtime/json/value.pep by `pep-doc reference`. Do not edit. -->

# JsonValue

`JsonValue`: a JSON value of any kind, and how it is written as text.

Source: `runtime/json/value.pep`

## JsonValue

```pepper
enum JsonValue
```

A JSON value: `null`, a boolean, a number, a string, an array or an
object. `json.parse` makes one from text and `to_string` writes it back.

Look values up with `value["key"]` and `value[index]`. A lookup that
finds nothing (a missing key, an index past the end, or a lookup on a
value of another kind) gives `Null` rather than panicking, so lookups
chain: `root["server"]["port"]`. Then read the value with an `as_` method,
which gives none when the value is of another kind, or `match` on its
case.

Numbers keep the form they were written in: an integer within
±(2^53 − 1), the range every JSON implementation agrees on (RFC 7493), is
an `Integer`; any other number is a `Number`, a `double`.

An `Array` or `Object` case holds its array or map by reference, so
changing them through `value[key] = ...`, `append` or the map from
`as_object()` changes every holder of the value.

**Example**
```pepper
import json;

var reply = json.JsonValue.object();
reply["id"] = json.JsonValue.Integer(42);
reply["tags"] = json.JsonValue.array([json.JsonValue.String("a")]);
assert(reply.to_string() == "{\"id\":42,\"tags\":[\"a\"]}", "compact");
assert(reply["id"].as_int().value() == 42, "a lookup");
assert(reply["missing"]["deeper"].is_null(), "lookups chain");
```

### Cases

#### Null

```pepper
Null
```

JSON's `null`, and what a lookup gives when it finds nothing.

#### Bool

```pepper
Bool(value: bool)
```

`true` or `false`.

**Parameters**
- `value` — the boolean

#### Integer

```pepper
Integer(value: long)
```

A number written without a fraction or an exponent, within
±(2^53 − 1).

**Parameters**
- `value` — the integer

#### Number

```pepper
Number(value: double)
```

Any other number: one with a fraction or an exponent, or an integer
outside ±(2^53 − 1).

**Parameters**
- `value` — the number

#### String

```pepper
String(value: String)
```

A string.

**Parameters**
- `value` — the text

#### Array

```pepper
Array(items: Array<JsonValue>)
```

An array, holding its elements in order.

**Parameters**
- `items` — the elements

#### Object

```pepper
Object(members: OrderedMap<String, JsonValue>)
```

An object, holding its members in insertion order: the order the
text or the code wrote them, so a document round-trips unchanged.

**Parameters**
- `members` — the members, by key

### Static methods

#### object

```pepper
static object(): JsonValue
```

Returns a new, empty object.

**Returns**
- an `Object` with no members

**Example**
```pepper
import json;

var config = json.JsonValue.object();
config["name"] = json.JsonValue.String("pepper");
```

#### array

```pepper
static array(items: Array<JsonValue> = Array<JsonValue>()): JsonValue
```

Returns an array holding `items`, which it keeps by reference rather
than copying.

**Parameters**
- `items` — the elements; an empty array when not given

**Returns**
- an `Array` of `items`

**Example**
```pepper
import json;

var list = json.JsonValue.array([json.JsonValue.Integer(1)]);
list.append(json.JsonValue.Integer(2));
assert(list.to_string() == "[1,2]", "two elements");
```

### Methods

#### operator []

```pepper
[](key: String): JsonValue
```

Reads `value[key]`: the member named `key` of an object.

**Parameters**
- `key` — the member's key

**Returns**
- the member, or `Null` when this is not an object or has no member named `key`

#### operator []

```pepper
[](key: String, member: JsonValue): JsonValue
```

Writes `value[key] = member`: sets the member named `key` of an
object. A new key goes at the end; an existing key keeps its place.

**Parameters**
- `key` — the member's key
- `member` — the value to store

**Returns**
- `member`, the value of the assignment expression

**Panics**
- if this is not an object ("JsonValue[key] = value needs an object")

#### operator []

```pepper
[](index: ulong): JsonValue
```

Reads `value[index]`: an element of an array.

**Parameters**
- `index` — the element's position, from 0

**Returns**
- the element, or `Null` when this is not an array or `index` is not less than its count

#### operator []

```pepper
[](index: ulong, element: JsonValue): JsonValue
```

Writes `value[index] = element`: replaces an element of an array.

**Parameters**
- `index` — the element's position, from 0
- `element` — the value to store

**Returns**
- `element`, the value of the assignment expression

**Panics**
- if this is not an array ("JsonValue[index] = value needs an array")
- if `index` is not less than the array's count (as `Array`'s indexer does)

#### append

```pepper
append(element: JsonValue)
```

Appends `element` to the end of an array.

**Parameters**
- `element` — the value to append

**Panics**
- if this is not an array ("JsonValue.append needs an array")

#### contains

```pepper
contains(key: String): bool
```

Returns whether this is an object with a member named `key`.

**Parameters**
- `key` — the key to look for

**Returns**
- true when the member exists, even if its value is `Null`

#### remove

```pepper
remove(key: String): bool
```

Removes the member named `key` from an object.

**Parameters**
- `key` — the key to remove

**Returns**
- true when this is an object and the member was there

#### is_null

```pepper
is_null(): bool
```

Returns whether this is `Null`, which is also what a lookup that finds
nothing gives.

**Returns**
- true for `Null`

#### as_bool

```pepper
as_bool(): bool?
```

Returns the boolean, when this is one.

**Returns**
- the value of a `Bool`, or none

#### as_int

```pepper
as_int(): long?
```

Returns the number as an integer, when it is one: an `Integer`, or a
`Number` with no fraction that fits in a `long` (`2.0`, `1e3`).

**Returns**
- the integer, or none

**Example**
```pepper
import json;

assert(json.parse("1e3").value().as_int().value() == 1000, "no fraction");
assert(json.parse("1.5").value().as_int().is_empty(), "a fraction");
```

#### as_double

```pepper
as_double(): double?
```

Returns the number as a `double`, when this is an `Integer` or a
`Number`.

**Returns**
- the number, or none

#### as_string

```pepper
as_string(): String?
```

Returns the string, when this is one.

**Returns**
- the text of a `String`, or none

#### as_array

```pepper
as_array(): Array<JsonValue>?
```

Returns the elements, when this is an array. The array is the one
this value holds, not a copy.

**Returns**
- the elements of an `Array`, or none

#### as_object

```pepper
as_object(): OrderedMap<String, JsonValue>?
```

Returns the members, when this is an object. The map is the one this
value holds, not a copy.

**Returns**
- the members of an `Object`, or none

#### to_string

```pepper
to_string(): String
```

Returns the value as compact JSON text, with no spaces or line
breaks: `{"id":42,"tags":["a","b"]}`.

Strings are written as UTF-8, escaping `"`, `\` and the control
characters. A `Number` that is not finite (NaN or an infinity, which
JSON cannot spell) is written as `null`.

**Returns**
- the JSON text

#### to_string

```pepper
to_string(ascii_only: bool): String
```

Returns the value as compact JSON text, like `to_string()`, choosing
whether to escape every character outside ASCII as `\u` (a pair of
them past U+FFFF), so the text is plain ASCII.

**Parameters**
- `ascii_only` — whether to escape every non-ASCII character

**Returns**
- the JSON text

**Example**
```pepper
import json;

var word = json.JsonValue.String("é");
assert(word.to_string(ascii_only = true) == "\"\\u00e9\"", "escaped");
```

#### to_pretty_string

```pepper
to_pretty_string(indent: int = 2, ascii_only: bool = false): String
```

Returns the value as indented JSON text: each element and member on
its own line, indented `indent` spaces per level, with a space after
each `:`. An empty array or object stays `[]` or `{}`.

**Parameters**
- `indent` — the number of spaces per level of nesting
- `ascii_only` — whether to escape every non-ASCII character as `\u`

**Returns**
- the JSON text, without a final line break

**Panics**
- if `indent` is negative ("JsonValue.to_pretty_string needs a non-negative indent")

**Example**
```pepper
import json;

var list = json.JsonValue.array([json.JsonValue.Integer(1)]);
assert(list.to_pretty_string() == "[\n  1\n]", "two spaces");
```
