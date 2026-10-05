<!-- Generated from runtime/toml/convert.pep by `pep-doc reference`. Do not edit. -->

# Struct conversion

Struct conversion: `encode` and `decode` turn Pepper values into TOML
documents and back, through reflection, with no per-type code to write.
They read the same `serialize` attributes `json` does, so one set of
attributes describes a type for both formats.

Source: `runtime/toml/convert.pep`

## UnknownKeys

```pepper
enum UnknownKeys
```

What `decode` does with a table key that names no property of the
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

## to_toml

```pepper
to_toml<T>(value: T): TomlValue?
```

Converts `value` to a `TomlValue`.

`T` may be a number type, `bool`, `String`, `TomlDateTime`, an enum (a
case that carries no values as its name, `"Point"`; one that carries
values as `{ Circle = { radius = 2 } }`), `Optional<U>`, `Array<U>`, a
map with `String` keys (`HashMap`, `OrderedMap` or `Map`) as a table,
`TomlValue` itself, or a struct, whose public properties become a
table's members in declaration order. Element and property types follow
the same rules, so structs nest.

TOML has no null, so what JSON writes as `null` is left out: an empty
`Optional`, a `String` or struct property that holds no object, and such
an element of an array or map. A `ulong` past the largest TOML integer,
2^63 - 1, is written as a float.

A struct property takes its key from `[Name("key")]` when it has one,
and is left out when marked `[Ignore]` (the attributes of the
`serialize` module, which `toml` shares with `json`).

The conversion is generated while compiling, by a `static` block per
type. A type it cannot convert, such as a `Result`, is a compile error
naming the property:
`'encode' cannot convert property 'outcome' of type 'Result<int>' to TOML`.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `value` — the value to convert

**Returns**
- the value as TOML, or none when there is nothing to write

**Example**
```pepper
import toml;

struct Point {
    var x: int;
    var y: int;
}

main(): int {
    var p = Point();
    p.x = 1;
    p.y = 2;
    assert(toml.to_toml(p).value()["y"].as_int().value() == 2, "a member");
    return 0;
}
```

## encode

```pepper
encode<T>(value: T): String
```

Writes `value`, a struct or a map, as a TOML document, converting it as
`to_toml` does.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `value` — the value to write

**Returns**
- the document text

**Panics**
- if `value` does not convert to a table, as a number or an array does ("toml.encode needs a value that converts to a table")

**Example**
```pepper
import toml;

struct Package {
    var name: String;
    var version: String;
    var authors: Array<String>;
}

struct Manifest {
    var package: Package;
    [Name("build-script")]
    var build_script: String?;
}

main(): int {
    var manifest = Manifest();
    manifest.package = Package();
    manifest.package.name = "demo";
    manifest.package.version = "0.1.0";
    manifest.package.authors = ["Ada"];
    var text = toml.encode(manifest);
    assert(text == "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nauthors = [\"Ada\"]\n", "a document");
    return 0;
}
```

## from_toml

```pepper
from_toml<T>(value: TomlValue, unknown_keys: UnknownKeys = UnknownKeys.Ignore): Result<T, TomlError>
```

Converts a `TomlValue` to a `T`, the reverse of `to_toml`.

A struct is made with its constructor that takes no arguments, then each
property found in the table is read in. A missing key leaves its
property at its default (an empty `Optional`, for one), unless the
property is marked `[Required]`, which makes it an error; a property
marked `[Ignore]` is never read. A key that names no property is
skipped, or with `unknown_keys = UnknownKeys.Reject` is an error.

An integer converts to an integer type it fits, and to `float` or
`double`; a float converts only to `float` or `double`.

An error names where in the document it is, as a path from the root `$`
in its `value_path` and at the start of its message, and has no line or
column, since there is no text: `$.package.version: expected a string,
found an integer`.

**Type parameters**
- `T` — the type to convert to

**Parameters**
- `value` — the TOML value
- `unknown_keys` — what to do with a key that names no property

**Returns**
- the converted value, or the first error

## decode

```pepper
decode<T>( text: String, unknown_keys: UnknownKeys = UnknownKeys.Ignore, path: String = "" ): Result<T, TomlError>
```

Parses a TOML document and converts it to a `T`: `parse`, then
`from_toml`.

**Type parameters**
- `T` — the type to convert to

**Parameters**
- `text` — the TOML text
- `unknown_keys` — what to do with a key that names no property
- `path` — the name of the text (a file name, say), which the error's `to_string()` puts first

**Returns**
- the value, or the first error: a syntax error, or a conversion error with its path in the document; either has its line and column when the value it is about is written in the text

**Example**
```pepper
import toml;

struct Package {
    [Required]
    var name: String;
    var version: String;
    var authors: Array<String>;
    var edition: int?;
}

struct Manifest {
    [Required]
    var package: Package;
}

main(): int {
    var text = "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nauthors = [\"Ada\"]\n";
    var manifest = toml.decode<Manifest>(text);
    assert(manifest.value().package.name == "demo", "a string");
    assert(manifest.value().package.authors[0] == "Ada", "an array");
    assert(manifest.value().package.edition.is_empty(), "a missing optional");

    var bad = toml.decode<Manifest>("[package]\nname = 7\n", path = "pep.toml");
    assert(
        bad.error().to_string() == "pep.toml:2:8: error: $.package.name: expected a string, found an integer",
        "where"
    );
    return 0;
}
```
