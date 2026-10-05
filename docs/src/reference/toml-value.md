<!-- Generated from runtime/toml/value.pep by `pep-doc reference`. Do not edit. -->

# TomlValue

`TomlValue`: a TOML value of any kind, and `TomlDateTime`, TOML's dates
and times.

Source: `runtime/toml/value.pep`

## TomlDateTime

```pepper
struct TomlDateTime
```

A TOML date, time, or date and time: an offset date-time
(`1979-05-27T07:32:00Z`), a local date-time (`1979-05-27T07:32:00`), a
local date (`1979-05-27`) or a local time (`07:32:00.5`).

`has_date`, `has_time` and `has_offset` say which of the four it is;
the fields of a part it does not have are 0. `to_string()` writes it in
the RFC 3339 form TOML uses, with as many fraction digits as it was
read with.

**Example**
```pepper
import toml;

var when = toml.TomlDateTime.offset(1979, 5, 27, 7, 32, 0, -420);
assert(when.to_string() == "1979-05-27T07:32:00-07:00", "an offset");
assert(toml.TomlDateTime.date(2024, 2, 29).to_string() == "2024-02-29", "a date");
```

### Fields

#### year

```pepper
var year: int
```

The year, 0 to 9999; 0 without a date.

#### month

```pepper
var month: int
```

The month, 1 to 12; 0 without a date.

#### day

```pepper
var day: int
```

The day of the month, from 1; 0 without a date.

#### hour

```pepper
var hour: int
```

The hour, 0 to 23.

#### minute

```pepper
var minute: int
```

The minute, 0 to 59.

#### second

```pepper
var second: int
```

The second, 0 to 59.

#### nanosecond

```pepper
var nanosecond: int
```

The fraction of the second, in nanoseconds.

#### fraction_digits

```pepper
var fraction_digits: int
```

How many digits of the fraction `to_string()` writes, 0 to 9; 0
writes none.

#### offset_minutes

```pepper
var offset_minutes: int
```

The offset from UTC in minutes (`-07:00` is -420); 0 for `Z`.

#### has_date

```pepper
var has_date: bool
```

Whether it has a date.

#### has_time

```pepper
var has_time: bool
```

Whether it has a time of day.

#### has_offset

```pepper
var has_offset: bool
```

Whether it has an offset from UTC, which only a date and time has.

### Constructor

#### TomlDateTime()

```pepper
construct()
```

Creates a local date-time at midnight on 0000-00-00, to fill in.

### Static methods

#### date

```pepper
static date(year: int, month: int, day: int): TomlDateTime
```

Returns a local date, such as `1979-05-27`.

**Parameters**
- `year` — the year
- `month` — the month, from 1
- `day` — the day of the month, from 1

**Returns**
- the date

#### time

```pepper
static time(hour: int, minute: int, second: int, nanosecond: int = 0): TomlDateTime
```

Returns a local time of day, such as `07:32:00`.

**Parameters**
- `hour` — the hour
- `minute` — the minute
- `second` — the second
- `nanosecond` — the fraction of the second, in nanoseconds; written with as few digits as it needs

**Returns**
- the time

#### local

```pepper
static local( year: int, month: int, day: int, hour: int, minute: int, second: int, nanosecond: int = 0 ): TomlDateTime
```

Returns a local date-time, with no offset: `1979-05-27T07:32:00`.

**Parameters**
- `year` — the year
- `month` — the month, from 1
- `day` — the day of the month, from 1
- `hour` — the hour
- `minute` — the minute
- `second` — the second
- `nanosecond` — the fraction of the second, in nanoseconds

**Returns**
- the date-time

#### offset

```pepper
static offset( year: int, month: int, day: int, hour: int, minute: int, second: int, offset_minutes: int, nanosecond: int = 0 ): TomlDateTime
```

Returns a date-time at an offset from UTC: `1979-05-27T07:32:00Z`.

**Parameters**
- `year` — the year
- `month` — the month, from 1
- `day` — the day of the month, from 1
- `hour` — the hour
- `minute` — the minute
- `second` — the second
- `offset_minutes` — the offset from UTC in minutes; 0 is written `Z`
- `nanosecond` — the fraction of the second, in nanoseconds

**Returns**
- the date-time

### Methods

#### to_string

```pepper
to_string(): String
```

Returns the value as TOML writes it: `1979-05-27T07:32:00.5-07:00`,
`1979-05-27`, `07:32:00`.

**Returns**
- the text

## TomlValue

```pepper
enum TomlValue
```

A TOML value: a string, an integer, a float, a boolean, a date-time, an
array or a table. `toml.parse` makes a table from a document, and
`to_document` writes one back.

Look members up with `value["key"]` and elements with `value[index]`,
which panic when there is none; `try_get` and `lookup` give none
instead, and `lookup` follows a dotted key (`"package.name"`). Then read
the value with an `as_` method, which gives none when the value is of
another kind, or `match` on its case.

A `Table` keeps its keys in the order they were written. An `Array` or
`Table` case holds its array or map by reference, so changing them
through `value[key] = ...` or `append` changes every holder of the
value.

**Example**
```pepper
import toml;

var package = toml.TomlValue.table();
package["name"] = toml.TomlValue.String("demo");
package["authors"] = toml.TomlValue.array([toml.TomlValue.String("Ada")]);
assert(package.to_string() == "{ name = \"demo\", authors = [\"Ada\"] }", "inline");
assert(package["name"].as_string().value() == "demo", "a lookup");
```

### Cases

#### String

```pepper
String(value: String)
```

A string.

**Parameters**
- `value` — the text

#### Integer

```pepper
Integer(value: long)
```

A 64-bit integer.

**Parameters**
- `value` — the integer

#### Float

```pepper
Float(value: double)
```

A 64-bit float, including `inf` and `nan`.

**Parameters**
- `value` — the number

#### Boolean

```pepper
Boolean(value: bool)
```

`true` or `false`.

**Parameters**
- `value` — the boolean

#### DateTime

```pepper
DateTime(value: TomlDateTime)
```

A date, a time, or both.

**Parameters**
- `value` — the date-time

#### Array

```pepper
Array(items: Array<TomlValue>)
```

An array, holding its elements in order.

**Parameters**
- `items` — the elements

#### Table

```pepper
Table(members: OrderedMap<String, TomlValue>)
```

A table, holding its members in the order they were written.

**Parameters**
- `members` — the members, by key

### Static methods

#### table

```pepper
static table(): TomlValue
```

Returns a new, empty table.

**Returns**
- a `Table` with no members

#### array

```pepper
static array(items: Array<TomlValue> = Array<TomlValue>()): TomlValue
```

Returns an array holding `items`, which it keeps by reference rather
than copying.

**Parameters**
- `items` — the elements; an empty array when not given

**Returns**
- an `Array` of `items`

### Methods

#### operator []

```pepper
[](key: String): TomlValue
```

Reads `value[key]`: the member named `key` of a table.

**Parameters**
- `key` — the member's key

**Returns**
- the member

**Panics**
- if this is not a table or has no member named `key` ("no key 'k' in the TOML table"); use `try_get` to check

#### operator []

```pepper
[](key: String, member: TomlValue): TomlValue
```

Writes `value[key] = member`: sets the member named `key` of a
table. A new key goes at the end; an existing key keeps its place.

**Parameters**
- `key` — the member's key
- `member` — the value to store

**Returns**
- `member`, the value of the assignment expression

**Panics**
- if this is not a table ("TomlValue[key] = value needs a table")

#### operator []

```pepper
[](index: ulong): TomlValue
```

Reads `value[index]`: an element of an array.

**Parameters**
- `index` — the element's position, from 0

**Returns**
- the element

**Panics**
- if this is not an array ("TomlValue[index] needs an array")
- if `index` is not less than the array's count (as `Array`'s indexer does)

#### operator []

```pepper
[](index: ulong, element: TomlValue): TomlValue
```

Writes `value[index] = element`: replaces an element of an array.

**Parameters**
- `index` — the element's position, from 0
- `element` — the value to store

**Returns**
- `element`, the value of the assignment expression

**Panics**
- if this is not an array ("TomlValue[index] = value needs an array")
- if `index` is not less than the array's count

#### try_get

```pepper
try_get(key: String): TomlValue?
```

Returns the member named `key`, when this is a table that has one.

**Parameters**
- `key` — the member's key

**Returns**
- the member, or none

#### lookup

```pepper
lookup(key: String): TomlValue?
```

Returns the value at a dotted key below this table, read as TOML
reads a key: `package.name`, `dependencies."my.crate".version`.

**Parameters**
- `key` — the dotted key

**Returns**
- the value, or none when a part is missing, is not a table, or `key` is not a valid TOML key

**Example**
```pepper
import toml;

var root = toml.parse("[package]\nname = \"demo\"").value();
assert(root.lookup("package.name").value().as_string().value() == "demo", "found");
assert(root.lookup("package.version").is_empty(), "missing");
```

#### get_path

```pepper
get_path(keys: Array<String>): TomlValue?
```

Returns the value at the path of keys `keys` below this table.

**Parameters**
- `keys` — the keys, outermost first; empty gives this value

**Returns**
- the value, or none when a part is missing or is not a table

#### append

```pepper
append(element: TomlValue)
```

Appends `element` to the end of an array.

**Parameters**
- `element` — the value to append

**Panics**
- if this is not an array ("TomlValue.append needs an array")

#### contains

```pepper
contains(key: String): bool
```

Returns whether this is a table with a member named `key`.

**Parameters**
- `key` — the key to look for

**Returns**
- true when the member exists

#### remove

```pepper
remove(key: String): bool
```

Removes the member named `key` from a table.

**Parameters**
- `key` — the key to remove

**Returns**
- true when this is a table and the member was there

#### type_name

```pepper
type_name(): String
```

Returns what kind of value this is, as errors name it: `string`,
`integer`, `float`, `boolean`, `date-time`, `array` or `table`.

**Returns**
- the kind's name

#### as_string

```pepper
as_string(): String?
```

Returns the string, when this is one.

**Returns**
- the text of a `String`, or none

#### as_int

```pepper
as_int(): long?
```

Returns the integer, when this is one.

**Returns**
- the value of an `Integer`, or none

#### as_float

```pepper
as_float(): double?
```

Returns the number as a `double`, when this is a `Float` or an
`Integer`.

**Returns**
- the number, or none

#### as_bool

```pepper
as_bool(): bool?
```

Returns the boolean, when this is one.

**Returns**
- the value of a `Boolean`, or none

#### as_date_time

```pepper
as_date_time(): TomlDateTime?
```

Returns the date-time, when this is one.

**Returns**
- the value of a `DateTime`, or none

#### as_array

```pepper
as_array(): Array<TomlValue>?
```

Returns the elements, when this is an array. The array is the one
this value holds, not a copy.

**Returns**
- the elements of an `Array`, or none

#### as_table

```pepper
as_table(): OrderedMap<String, TomlValue>?
```

Returns the members, when this is a table. The map is the one this
value holds, not a copy.

**Returns**
- the members of a `Table`, or none

#### to_string

```pepper
to_string(): String
```

Returns the value as TOML writes it after a key's `=`, on one line:
`"text"`, `42`, `1.5`, `[1, 2]`, `{ name = "demo" }`.

**Returns**
- the TOML text

#### to_document

```pepper
to_document(): String
```

Returns a table as a TOML document: its plain members as `key =
value` lines, then each table member under a `[header]` and each
array of tables as `[[header]]` sections, nested tables after their
parent's members.

**Returns**
- the document text, ending with a line break unless it is empty

**Panics**
- if this is not a table ("TomlValue.to_document needs a table")

**Example**
```pepper
import toml;

var root = toml.TomlValue.table();
root["title"] = toml.TomlValue.String("demo");
var server = toml.TomlValue.table();
server["port"] = toml.TomlValue.Integer(8080);
root["server"] = server;
assert(root.to_document() == "title = \"demo\"\n\n[server]\nport = 8080\n", "a document");
```
