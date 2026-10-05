# Command-line options

The `cli` module parses a program's command line. Declare each option and
positional argument on a `cli.Parser`, call `parse`, then read the values
through the handles the declarations returned, or declare them all at once
as the fields of a struct. The help, `--version` and
the error messages all come from the declarations. Bring it in with
`import cli`; the full API is in the [reference](../reference/cli-module.md).

```pepper
{{#include ../../examples/cli-basics.pep}}
```

`greet --help` prints:

```text
Greets someone

usage: greet [OPTIONS] [names]...

Arguments:
  <names>...  who to greet

Options:
  -g, --greeting <GREETING>  what to say [default: hello]
  -l, --loud                 shout it
  -n, --times <COUNT>        how many times to say it [default: 1]
  -h, --help                 show this help
  -V, --version              show the version
```

The raw arguments stay where they were: `main(args: String[])` receives
them, and `process.arguments()` returns them. `parse` takes them as `main`
receives them, program name first.

## Declaring

| Declaration | Handle | Reads |
|-------------|--------|-------|
| `flag(name, short_name, help, global)` | `Flag` | `is_set` and `occurrences` (properties) |
| `option<T>(name, short_name, help, value_name, default_value, required, global)` | `Argument<T>` | `value()`, `value_or(fallback)`, `is_set` |
| `multiple<T>(name, short_name, help, value_name, required, global)` | `ArgumentList<T>` | `values()`, `is_set` |
| `positional<T>(name, help, required, default_value)` | `Argument<T>` | `value()`, `value_or(fallback)`, `is_set` |
| `positionals<T>(name, help, required)` | `ArgumentList<T>` | `values()`, `is_set` |

`T` is the type of the value (see [Typed values](#typed-values)); leave it
out for a `String`: `option("output")` is `option<String>("output")`.

- An option's `name` is its long name without `--`; `short_name` is one
  character without `-`, or empty for none. Pass the rest by
  [name](functions.md#named-arguments): `option("output", "o",
  "the executable to write", default_value = "a.out")`.
- `value()` returns the value given, else the default; it panics when the
  argument was left out and has no default, so use `value_or` or check
  `is_set` for an optional one. `is_set` (a
  [property](properties.md), like `occurrences` and `is_selected`) is false
  for a value that came from the default.
- Positional arguments fill in declaration order. A required one cannot
  follow an optional one, and `positionals` takes every value that is left,
  so it comes last.
- `-h`/`--help` is always there, and `-V`/`--version` when the parser has a
  `version`. Declaring `-h` or `-V` yourself takes the short name; the long
  forms keep working.
- A mistake in the declarations, such as a name declared twice or a short
  name longer than one character, panics: it is a bug in the program, not
  in its input.

## On the command line

- A value follows its option as `--output a.out`, `--output=a.out`,
  `-o a.out`, `-oa.out` or `-o=a.out`. It is taken as it is, even when it
  starts with `-`.
- Short flags combine: `-vq` is `-v -q`, and `-vo a.out` gives `-v` and
  then `-o a.out`. `-vvv` counts three `occurrences`.
- Options and positional arguments mix in any order. `--` ends the
  options, so `rm -- -file` removes a file named `-file`, and `-` alone is
  a positional argument (by custom, standard input).
- An option that takes one value keeps the last one given.

## Typed values

A declaration with a type argument reads its values as that type, and a
value that is not one fails the parse:

```text
greet: error: invalid value 'x' for '--times': expected an integer
```

| `T` | A value is | An error expects |
|-----|------------|------------------|
| `String` | any text | |
| `int`, `long` | an integer, as `int.parse` reads it | `an integer` |
| `uint`, `ulong` | an integer that is not negative | `a non-negative integer` |
| `byte`, `short`, `ushort` | an integer in the type's range | `an integer from 0 to 255` |
| `float`, `double` | a number, as `double.parse` reads it | `a number` |
| `io.Path` | any text, as a path | |
| an enum whose cases carry no values | a case's name in kebab case: `DebugInfo` is `debug-info` | `'fast' or 'debug-info'` |

- An enum's help lists its cases: `[possible values: fast, debug-info]`.
- `default_value` is written as on the command line, so the help shows it
  as it is: `option<int>("jobs", default_value = "4")`. A default that is
  not a value of the type panics.
- Any other type is a compile error at the call.

## Errors

`parse` writes a clang-style error, the usage and a hint to standard error
and returns false, so the program can exit with 2:

```text
greet: error: unknown option '--lound'; did you mean '--loud'?
usage: greet [OPTIONS] [names]...
Run 'greet --help' for more information.
```

The messages:

- `unknown option '--x'` (with `did you mean '--y'?` for a near miss) and
  `unknown option '-x'`
- `missing value for '-o'`
- `option '--loud' takes no value` (for `--loud=yes`)
- `invalid value 'x' for '--times': expected an integer`
- `missing required option '--target'`, `missing required argument '<source>'`
- `unexpected argument 'x'` when there is no positional argument left for it
- `unknown command 'x'` and `missing command: expected 'add' or 'update'`

`try_parse` does the same parse and writes nothing. It returns a
`Result<String?>`: an error holding the message, some text when `--help` or
`--version` asked for it (print it and exit with 0), or none when the
arguments were parsed. Tests use it, and so can a program that reports
errors its own way.

## Declaring options as a struct

`add_options` declares an option or positional argument for each public
field of a struct, and every successful parse stores the values in that
struct's fields. The attributes `[cli.Option]` and `[cli.Positional]` on
the fields carry what the builder calls take as arguments:

```pepper
{{#include ../../examples/cli-struct.pep}}
```

Its help and errors are the same as the builder example's above: the
declarations are the same ones.

| Field type | Declares | After a parse |
|------------|----------|---------------|
| `bool` | `flag` | whether it was given |
| `T` | `option<T>` | the value given, else the field's starting value |
| `T?` | `option<T>` | the value given, or Empty |
| `T[]` | `multiple<T>` | the values given, in order |

- `T` is any type of [Typed values](#typed-values): `String`, a number
  type, `io.Path` or an enum. A field's starting value is the default the
  help shows, except an empty `String` or a null `io.Path`, which means
  none.
- An option is named after its field, with each `_` written `-`:
  `import_path` is `--import-path`. Any other field type is a compile
  error at the call: `'add_options' cannot declare field 'table' of type
  'Map<String, int>'; use bool, String, a number type, io.Path or an enum,
  or one of those as T? or T[]`.
- `[cli.Option(short_name, help, name, value_name, required, global)]` sets
  the rest, every argument optional: `[cli.Option("o", "the executable to
  write")]`, `[cli.Option(required = true)]`.
- `[cli.Positional(help, name, required)]` makes the field the next
  positional argument. A `T` one is required when it has no default or
  `required` is set; a `T?` one may be left out; a `T[]` one takes every
  value left (`positionals`), and `required` asks for at least one.
- Each parse sets every field again, so a flag left out is false even if
  the field started true.
- A parse that fails, or that asks for `--help` or `--version`, leaves the
  fields as they were.
- The two styles mix: call `flag` and `option` on the same parser, and
  `add_options` on a command's parser for that command's options. A
  command's struct is filled only when that command is given.

## Subcommands

`command(name, about)` declares a subcommand, as in `git add` or
`pep-package update`, and returns its own `Parser` to declare its options
and arguments on. The first argument that is not an option names the
command; after `parse`, `is_selected` tells which command was given.

```pepper
{{#include ../../examples/cli-commands.pep}}
```

- A parser with commands needs one, and cannot have positional arguments
  of its own.
- Options before the command's name belong to the parent, and everything
  after it to the command, so `pkg -v add x` works and `pkg add -v x` does
  not, unless `-v` is global.
- A global option (`flag("verbose", "v", global = true)`, and the same
  argument on `option` and `multiple`) may also be given after the name of
  any command below its parser, at any depth, and each command's help
  lists it. A command cannot declare an option with a global option's
  name, and a required global option may be given anywhere on the line.
- `--help` after a command shows that command's help, and errors show its
  usage.
- Commands nest: a command's parser can declare commands too.

## Not yet

- Windows-style `/option` forms: every platform uses `-` and `--`.
- Generating shell completions.
