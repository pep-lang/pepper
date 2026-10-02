<!-- Generated from runtime/serialize/module.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# The serialize module

Serialization attributes: how a struct's properties are written to and
read from text formats.

`json` reads these attributes when it converts a struct (`json.encode`,
`json.decode`), and other formats will share them, so one set of
attributes describes a type for every format. Write them above a
property; `import serialize` brings them in, and `import json` alone is
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

Writes a property under `value` rather than under its own name.

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

The key the property is written under.

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
