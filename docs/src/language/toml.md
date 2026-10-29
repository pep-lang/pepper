# TOML

The `toml` module reads [TOML 1.0](https://toml.io/en/v1.0.0) into a
`TomlValue`, lets you look values up and change them, writes tables back
as documents, edits a document in place without disturbing its comments,
and converts structs to TOML and back. The package manager reads and
edits `pep.toml` and `pep.lock` with it.

```pepper
{{#include ../../examples/toml-basics.pep}}
```

## Values

`toml.TomlValue` is an [enum](enums.md) whose cases carry values:

| Case | Holds | TOML |
|------|-------|------|
| `String(value: String)` | the string | `"hi"`, `'C:\path'`, `"""..."""` |
| `Integer(value: long)` | a 64-bit integer | `42`, `0xff`, `1_000` |
| `Float(value: double)` | a float, `inf` and `nan` included | `0.5`, `1e10`, `inf` |
| `Boolean(value: bool)` | the boolean | `true`, `false` |
| `DateTime(value: TomlDateTime)` | a date, a time, or both | `1979-05-27T07:32:00Z`, `1979-05-27`, `07:32:00` |
| `Array(items: Array<TomlValue>)` | the elements | `[1, "two"]` |
| `Table(members: OrderedMap<String, TomlValue>)` | the keys, in the order written | `[server]`, `{ x = 1 }` |

- **Look values up** with `value["key"]` and `value[index]`, which panic
  on a miss, or `try_get("key")` and `lookup("package.name")`, which give
  an empty `Optional`. The `as_` methods (`as_string`, `as_int`,
  `as_float`, `as_bool`, `as_date_time`, `as_array`, `as_table`) give an
  empty `Optional` for another kind; `as_float` also reads an integer.
- **Write** a value on one line with `to_string()` (as after a key's `=`),
  or a table as a whole document with `to_document()`.
- **There is no null.** What `json` writes as `null` is left out, and a
  missing key reads as the property's default.

## Errors

`toml.parse(text, path = "pep.toml")` checks every rule of TOML 1.0 and
gives a `TomlError` that renders like a compiler error:
`pep.toml:4:12: error: expected '=' after the key`. Arrays and inline
tables may nest `max_depth` deep (1000 by default); parsing and writing
use explicit stacks, so deep nesting never overflows the stack. The
module passes all 709 TOML 1.0 cases of
[toml-test](https://github.com/toml-lang/toml-test), which its tests run.

## Editing a document in place

`toml.parse_document(text)` gives a `TomlDocument`, whose `set(keys,
value)` and `remove(keys)` change only the lines they must, keeping every
comment and blank line, the way `cargo add` edits `Cargo.toml`. A changed
value is rewritten on one line; a new key goes after the last key of its
table, indented like it; a new table goes at the end as a `[header]`
section, or as `{ ... }` with `inline = true`. Edits cannot reach inside an
array of tables (`[[bin]]`); set or remove the whole array.

## Structs

`toml.encode(value)` and `toml.decode<T>(text)` (and `to_toml` and
`from_toml`, which work on a `TomlValue`) convert structs through
reflection, with the [serialize](../reference/serialize-module.md)
attributes [JSON](json.md) uses: `[Name("key")]`, `[Ignore]` and
`[Required]`. `unknown_keys = toml.UnknownKeys.Reject` makes an unknown key
an error. See the [reference](../reference/toml-module.md) for every
function.

A table's keys are strings, so a map with other keys is a compile-time
error, as is a set, `Deque`, `PriorityQueue`, `ArrayView` or `BitSet`
(convert it to an `Array` first), as for [JSON](json.md#current-limits).
