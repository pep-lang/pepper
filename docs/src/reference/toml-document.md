<!-- Generated from runtime/toml/document.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Documents with comments

`TomlDocument`: a TOML document changed in place, keeping its comments,
blank lines and layout, as `pepper package add` changes `pep.toml`.

Source: `runtime/toml/document.pep`

## TomlDocument

```pepper
struct TomlDocument
```

A TOML document that keeps the text it was read from, so a file people
edit can be changed and written back without reformatting it.

`set` and `remove` change only the text they must: a changed value is
rewritten where it stands, a new key goes after the last key of its
table, a new table goes at the end, and a removed key or table takes
its lines with it, along with the comment lines right above them. Every
other byte, comments included, stays as it was. Each edit parses the
result again, so `root()` and `get` always see the current text.

Keys are given as arrays, outermost first (`["dependencies", "json5"]`),
so a key holding a dot needs no quoting. An edit cannot reach inside an
array of tables (`[[bin]]`); set or remove the whole array instead.

**Example**
```pepper
import toml;

var text = "[package]\nname = \"demo\"  # the name\n\n[dependencies]\njson5 = \"1.0\"\n";
var document = toml.parse_document(text).value();
document.set(["package", "version"], toml.TomlValue.String("0.2.0")).value();
document.set(["dependencies", "yaml"], toml.TomlValue.String("0.3")).value();
document.remove(["dependencies", "json5"]).value();
assert(
    document.to_string()
        == "[package]\nname = \"demo\"  # the name\nversion = \"0.2.0\"\n\n[dependencies]\nyaml = \"0.3\"\n",
    "only the edits change"
);
```

### Constructor

#### TomlDocument()

```pepper
construct()
```

Creates an empty document.

### Methods

#### root

```pepper
root(): TomlValue
```

Returns the document's table, as `parse` reads the current text.
Changing it does not change the document; use `set` and `remove`.

**Returns**
- the root table

#### get

```pepper
get(keys: Array<String>): TomlValue?
```

Returns the value at `keys`.

**Parameters**
- `keys` — the keys, outermost first

**Returns**
- the value, or none when a part is missing or is not a table

#### lookup

```pepper
lookup(key: String): TomlValue?
```

Returns the value at a dotted key, read as TOML reads a key:
`package.name`, `dependencies."my.package"`.

**Parameters**
- `key` — the dotted key

**Returns**
- the value, or none when it is missing or `key` is not a valid TOML key

#### set

```pepper
set(keys: Array<String>, value: TomlValue, inline: bool = false): Result<void, TomlError>
```

Sets the value at `keys`, adding the key, and any tables above it,
when it is missing.

A key that is there has its value rewritten in place, on one line;
a key inside an inline table rewrites that inline table. A new key
goes after the last key of the table it belongs to, indented like
it, or under a new `[header]` at the end when that table has no
section to put it in. A new table value (or array of tables) is
written as its own `[header]` section at the end, unless `inline` is
true, which writes it `{ ... }` on the key's line instead, as
`cargo add` writes a dependency.

**Parameters**
- `keys` — the keys, outermost first
- `value` — the value to store
- `inline` — whether a new table value is written as an inline table rather than a section

**Returns**
- nothing, or an error when a part of `keys` holds a value that is not a table, or lies inside an array of tables

**Panics**
- if `keys` is empty ("TomlDocument.set needs a key")

#### remove

```pepper
remove(keys: Array<String>): Result<bool, TomlError>
```

Removes the key or table at `keys`, with its lines and the comment
lines right above them. Removing a table removes its sections, the
tables below it, and any dotted keys that define it.

**Parameters**
- `keys` — the keys, outermost first

**Returns**
- whether something was removed, or an error when a part of `keys` lies inside an array of tables

**Panics**
- if `keys` is empty ("TomlDocument.remove needs a key")

#### to_string

```pepper
to_string(): String
```

Returns the document's text, with every edit made.

**Returns**
- the TOML text

## parse_document

```pepper
parse_document(text: String, path: String = ""): Result<TomlDocument, TomlError>
```

Parses a TOML document into a `TomlDocument`, to change it in place.

The text is read as `parse` reads it. Use it to change a file people
edit, such as `pep.toml`, and write it back with its comments and
layout; use `parse` when only the values matter.

**Parameters**
- `text` — the TOML text
- `path` — the name of the text (a file name, say), which an error's `to_string()` puts first

**Returns**
- the document, or an error naming the first problem and its line and column
