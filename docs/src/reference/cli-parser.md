<!-- Generated from runtime/cli/parser.pep by `cargo run -p pepper-docgen -- reference`. Do not edit. -->

# Parser

Parser and the handles its declarations return: Flag, Argument and
ArgumentList.

Source: `runtime/cli/parser.pep`

## Parser

```pepper
struct Parser
```

Declares a program's command-line interface and parses its arguments.

Declare each option and positional argument with `flag`, `option`,
`multiple`, `positional` and `positionals`; each returns a handle that
reads its value once `parse` has run. `parse` also writes the help
(`--help`), the version (`--version`) and clang-style errors, all from
the declarations.

Options have a long name (`--output`) and an optional one-letter short
name (`-o`). A value follows as `--output a.out`, `--output=a.out`,
`-o a.out` or `-oa.out`; short flags combine (`-vq` is `-v -q`), and
`--` ends the options, so every argument after it is positional. A value
is taken as it is, even when it starts with `-`. When an option that
takes one value is given twice, the last value wins.

Subcommands (`git add`, `pep-package update`) are parsers of their own,
made with `command`. Options before the command's name belong to this
parser, and everything after it to the command's.

**Example**
```pepper
    import cli;

    main(args: String[]): int {
        var parser = cli.Parser("pepper", "Compiles a Pepper program", version = "0.2.1");
        var output = parser.option("output", "o", "the executable to write", default_value = "a.out");
        var imports = parser.multiple("import-path", "I", "a directory to search for modules");
        var verbose = parser.flag("verbose", "v", "say what is happening");
        var source = parser.positional("source", "the program's entry file");
        if (!parser.parse(args)) {
            return 2;
        }
        print($"{source.value()} -> {output.value()}");
        return 0;
    }
```

### Properties

#### is_selected

```pepper
var is_selected: bool { get; }
```

Whether the last `parse` reached this parser: whether this command
was given. The top-level parser is selected whenever its arguments
were parsed.

### Constructor

#### Parser()

```pepper
construct(name: String, about: String = "", version: String = "")
```

Makes a parser for the program `name`.

**Parameters**
- `name` — the program's name, as the help and errors show it
- `about` — a sentence on what the program does, the help's first line
- `version` — the program's version; when not empty, `--version` and `-V` print `name version`

### Methods

#### flag

```pepper
flag(name: String, short_name: String = "", help: String = ""): Flag
```

Declares an option that takes no value, such as `--verbose`.

**Parameters**
- `name` — the long name, without `--`
- `short_name` — the one-letter short name, without `-`, or empty for none
- `help` — what the option does, for the help

**Returns**
- the handle that tells whether the flag was given

**Panics**
- if `name` or `short_name` is invalid or already declared

#### option

```pepper
option( name: String, short_name: String = "", help: String = "", value_name: String = "", default_value: String = "", required: bool = false ): Argument
```

Declares an option that takes one value, such as `--output a.out`.

**Parameters**
- `name` — the long name, without `--`
- `short_name` — the one-letter short name, without `-`, or empty for none
- `help` — what the option sets, for the help
- `value_name` — what the help calls the value; empty for the long name in capitals (`OUTPUT`)
- `default_value` — the value when the option is not given; empty for none
- `required` — whether leaving the option out is an error

**Returns**
- the handle that reads the value

**Panics**
- if `name` or `short_name` is invalid or already declared

#### multiple

```pepper
multiple( name: String, short_name: String = "", help: String = "", value_name: String = "", required: bool = false ): ArgumentList
```

Declares an option that may be given any number of times, each with a
value, such as `-I src -I lib`.

**Parameters**
- `name` — the long name, without `--`
- `short_name` — the one-letter short name, without `-`, or empty for none
- `help` — what the option adds, for the help
- `value_name` — what the help calls the value; empty for the long name in capitals (`IMPORT_PATH`)
- `required` — whether leaving the option out is an error

**Returns**
- the handle that reads the values, in the order given

**Panics**
- if `name` or `short_name` is invalid or already declared

#### positional

```pepper
positional(name: String, help: String = "", required: bool = true, default_value: String = ""): Argument
```

Declares the next positional argument. Positional arguments are
filled in the order they are declared.

**Parameters**
- `name` — what the help and errors call it
- `help` — what it is, for the help
- `required` — whether leaving it out is an error
- `default_value` — the value when it is left out; empty for none

**Returns**
- the handle that reads the value

**Panics**
- if `name` is empty or already declared, if a required argument follows an optional one, if it follows `positionals`, or if the parser has commands

#### positionals

```pepper
positionals(name: String, help: String = "", required: bool = false): ArgumentList
```

Declares a positional argument that takes every remaining value, such
as a list of files. It must be the last positional argument.

**Parameters**
- `name` — what the help and errors call it
- `help` — what the values are, for the help
- `required` — whether at least one value must be given

**Returns**
- the handle that reads the values, in the order given

**Panics**
- if `name` is empty or already declared, if it follows `positionals`, or if the parser has commands

#### command

```pepper
command(name: String, about: String = ""): Parser
```

Declares a subcommand, such as `add` in `pep-package add NAME`, and
returns its parser, on which to declare its own options and
arguments.

A parser with commands requires one: the first argument that is not
an option names it, and the arguments after it go to its parser.
After `parse`, `is_selected` on the command's parser tells whether
it was the one given.

**Parameters**
- `name` — the command's name
- `about` — what the command does, for the help

**Returns**
- the command's parser

**Panics**
- if `name` is empty, starts with `-` or is already declared, or if this parser has positional arguments

#### usage

```pepper
usage(): String
```

Returns the one-line usage, such as
`usage: pepper [OPTIONS] <source>`.

**Returns**
- the usage line, without a line break

#### help

```pepper
help(): String
```

Returns the help that `--help` prints: what the program does, the
usage, and a line for each argument, option and command.

**Returns**
- the help text, ending in a line break

#### try_parse

```pepper
try_parse(args: String[]): Result<String?>
```

Parses `args` and fills in every handle, or reports the problem.

Writes nothing. Use it to handle errors, help and the version
yourself; `parse` does it the usual way.

**Parameters**
- `args` — the arguments as `main` receives them: the program's name, then its arguments

**Returns**
- some text when `--help` or `--version` was given (the program should print it and exit with 0), none when the arguments were parsed, or an error when they are wrong, with a clang-style message such as `missing value for '-o'`

#### parse

```pepper
parse(args: String[]): bool
```

Parses `args` and fills in every handle.

For `--help` or `--version` it prints the text to standard output and
ends the program with status 0. When the arguments are wrong it
writes the error, the usage and a hint to standard error, such as

    pepper: error: missing value for '-o'
    usage: pepper [OPTIONS] <source>
    Run 'pepper --help' for more information.

and returns false; exit with status 2, as the example does.

**Parameters**
- `args` — the arguments as `main` receives them: the program's name, then its arguments

**Returns**
- true when the arguments were parsed, false after an error

## Flag

```pepper
struct Flag
```

An option that takes no value, from `Parser.flag`.

### Properties

#### is_set

```pepper
var is_set: bool { get; }
```

Whether the flag was given at least once.

#### occurrences

```pepper
var occurrences: int { get; }
```

How many times the flag was given, so `-vvv` can mean more than `-v`.

### Constructor

#### Flag()

```pepper
construct(argument: _CliArgument)
```

Wraps a declaration. `Parser.flag` makes flags; this constructor is
for the runtime.

**Parameters**
- `argument` — the declaration

## Argument

```pepper
struct Argument
```

An option or positional argument that takes one value, from
`Parser.option` or `Parser.positional`.

### Properties

#### is_set

```pepper
var is_set: bool { get; }
```

Whether a value was given on the command line; false when the
argument was left out, even when it has a default.

### Constructor

#### Argument()

```pepper
construct(argument: _CliArgument)
```

Wraps a declaration. `Parser.option` and `Parser.positional` make
arguments; this constructor is for the runtime.

**Parameters**
- `argument` — the declaration

### Methods

#### value

```pepper
value(): String
```

Returns the value given, or the default when it was left out.

**Returns**
- the value

**Panics**
- if the argument was left out and has no default; check `is_set` or use `value_or` for an optional argument

#### value_or

```pepper
value_or(fallback: String): String
```

Returns the value given, or `fallback` when it was left out.

**Parameters**
- `fallback` — the value to use when the argument was left out

**Returns**
- the value given, else the declared default, else `fallback`

## ArgumentList

```pepper
struct ArgumentList
```

An option that may be given many times, or a positional argument that
takes every remaining value, from `Parser.multiple` or
`Parser.positionals`.

### Properties

#### is_set

```pepper
var is_set: bool { get; }
```

Whether at least one value was given.

### Constructor

#### ArgumentList()

```pepper
construct(argument: _CliArgument)
```

Wraps a declaration. `Parser.multiple` and `Parser.positionals` make
argument lists; this constructor is for the runtime.

**Parameters**
- `argument` — the declaration

### Methods

#### values

```pepper
values(): Array<String>
```

Returns the values given, in command-line order.

**Returns**
- a new array of the values, empty when none was given
