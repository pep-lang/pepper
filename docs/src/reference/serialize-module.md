<!-- Generated from runtime/serialize/module.pep by `pep-doc reference`. Do not edit. -->

# The serialize module

Serialization attributes: how a struct's properties are written to and
read from text formats.

`json` reads these attributes when it converts a struct (`json.encode`,
`json.decode`), and other formats will share them, so one set of
attributes describes a type for every format. Write them above a
property (or an enum or one of its cases: `Tag`, `Untagged`, `Name`);
`import serialize` brings them in, and `import json` alone is
enough too, since `json` exports them.

**Example**
```pepper
import json;

struct ServerConfig {
    var host: String;
    [Name("max-connections")]
    var max_connections: int;
    [Required]
    var port: int;
    [Ignore]
    var started_at: long;
}
```

Source: `runtime/serialize/module.pep`

## Name

```pepper
[Attribute] struct Name
```

Writes a property, or an enum case, under `value` rather than under its
own name.

**Example**
```pepper
import json;

struct Limits {
    [Name("max-connections")]
    var max_connections: int;
}
```

### Fields

#### value

```pepper
const value: String
```

The key the property is written under, or the name the case is
written as.

## Ignore

```pepper
[Attribute] struct Ignore
```

Leaves a property out: it is not written, and reading leaves it as it
was.

## Required

```pepper
[Attribute] struct Required
```

Makes a missing key an error when reading. Without it, a missing key
leaves the property at its default.

## Tag

```pepper
[Attribute] struct Tag
```

Writes an enum's cases as objects that name their case under `key`,
rather than as `{"Case": {...}}`.

Without `content`, a case's values sit beside the tag:
`{"kind": "Circle", "radius": 2}`. With `content`, they go in an object
under that key: `{"kind": "Circle", "data": {"radius": 2}}`. A case that
carries no values is `{"kind": "Point"}` either way. Write it above an
enum.

**Example**
```pepper
import json;

[Tag("kind")]
enum Shape {
    Circle(radius: int),
    Point,
}
```

### Fields

#### key

```pepper
const key: String
```

The key that holds the case's name.

#### content

```pepper
const content: String = ""
```

The key that holds the case's values, or empty to put them beside
the tag.

## Untagged

```pepper
[Attribute] struct Untagged
```

Writes an enum's cases with no tag at all: a case that carries values as
the object of its values (`{"radius": 2}`), and one that carries none as
its name (`"Point"`).

Reading tries each case in order and takes the first that reads without
an error, so list a case whose values are a superset of another's first.
Write it above an enum.

**Example**
```pepper
import json;

[Untagged]
enum Size {
    Fixed(px: int),
    Auto,
}
```
