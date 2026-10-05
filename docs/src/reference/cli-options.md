<!-- Generated from runtime/cli/options.pep by `pep-doc reference`. Do not edit. -->

# Options

The attributes that shape the options `Parser.add_options` declares
from a struct's fields.

Source: `runtime/cli/options.pep`

## Option

```pepper
[Attribute] struct Option
```

Sets how a field of an options struct is declared as an option: its
short name, its help, and whether it is required or global. A field without it is
still an option, named after the field.

**Example**
```pepper
import cli;

struct Options {
    [cli.Option("o", "the executable to write")]
    var output: String = "a.out";
    [cli.Option("v", "say what is happening")]
    var verbose: bool;
}
```

### Fields

#### short_name

```pepper
const short_name: String = ""
```

The one-letter short name, without `-`, or empty for none.

#### help

```pepper
const help: String = ""
```

What the option does, for the help.

#### name

```pepper
const name: String = ""
```

The long name, without `--`; empty for the field's name with each
`_` written `-` (`import_path` is `--import-path`).

#### value_name

```pepper
const value_name: String = ""
```

What the help calls the value; empty for the long name in capitals.

#### required

```pepper
const required: bool = false
```

Whether leaving the option out is an error.

#### global

```pepper
const global: bool = false
```

Whether the option may also be given after the name of a command, at
any depth.

## Positional

```pepper
[Attribute] struct Positional
```

Declares a field of an options struct as the next positional argument
instead of an option. A `T` field takes one value, required unless the
field starts with a value (its default; an empty `String` or a null
`io.Path` is none); a `T?` field takes an optional one; a `T[]` field
takes every value that is left.

**Example**
```pepper
import cli;

struct Options {
    [cli.Positional("the program's entry file")]
    var source: String;
}
```

### Fields

#### help

```pepper
const help: String = ""
```

What the argument is, for the help.

#### name

```pepper
const name: String = ""
```

What the help and errors call it; empty for the field's name.

#### required

```pepper
const required: bool = false
```

Whether leaving it out is an error, even when the field has a
default; for a `T[]` field, whether at least one value must be
given. A `T?` field ignores it.
