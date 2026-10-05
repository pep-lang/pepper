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
option( name: String, short_name: String = "", help: String = "", value_name: String = "", default_value: String = "", required: bool = false ): Argument<String>
```

Declares an option that takes one String value, such as
`--output a.out`. `option<T>` declares one whose value is a number,
a path or an enum case.

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

#### option

```pepper
option<T>( name: String, short_name: String = "", help: String = "", value_name: String = "", default_value: String = "", required: bool = false ): Argument<T>
```

Declares an option that takes one value of type `T`, such as
`--jobs 4` for `option<int>`. A value that does not read as a `T`
fails the parse: `invalid value 'x' for '--jobs': expected an
integer`.

`T` may be `String`, an integer type, `float`, `double`, `io.Path`,
or an enum whose cases carry no values; a case is written in kebab
case (`DebugInfo` is `debug-info`), and the help lists them.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `name` — the long name, without `--`
- `short_name` — the one-letter short name, without `-`, or empty for none
- `help` — what the option sets, for the help
- `value_name` — what the help calls the value; empty for the long name in capitals (`JOBS`)
- `default_value` — the value when the option is not given, written as on the command line (`"4"`); empty for none
- `required` — whether leaving the option out is an error

**Returns**
- the handle that reads the value

**Panics**
- if `name` or `short_name` is invalid or already declared, or if `default_value` does not read as a `T`

**Example**
```pepper
var jobs = parser.option<int>("jobs", "j", "how many at once", default_value = "4");
```

#### multiple

```pepper
multiple( name: String, short_name: String = "", help: String = "", value_name: String = "", required: bool = false ): ArgumentList<String>
```

Declares an option that may be given any number of times, each with a
String value, such as `-I src -I lib`. `multiple<T>` declares one
whose values are numbers, paths or enum cases.

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

#### multiple

```pepper
multiple<T>( name: String, short_name: String = "", help: String = "", value_name: String = "", required: bool = false ): ArgumentList<T>
```

Declares an option that may be given any number of times, each with a
value of type `T`, such as `-I src -I lib` for `multiple<io.Path>`.
`T` is one of the types `option<T>` takes.

**Type parameters**
- `T` — the type of each value

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
positional(name: String, help: String = "", required: bool = true, default_value: String = ""): Argument<String>
```

Declares the next positional argument, with a String value.
Positional arguments are filled in the order they are declared.
`positional<T>` declares one whose value is a number, a path or an
enum case.

**Parameters**
- `name` — what the help and errors call it
- `help` — what it is, for the help
- `required` — whether leaving it out is an error
- `default_value` — the value when it is left out; empty for none

**Returns**
- the handle that reads the value

**Panics**
- if `name` is empty or already declared, if a required argument follows an optional one, if it follows `positionals`, or if the parser has commands

#### positional

```pepper
positional<T>(name: String, help: String = "", required: bool = true, default_value: String = ""): Argument<T>
```

Declares the next positional argument, with a value of type `T`.
`T` is one of the types `option<T>` takes.

**Type parameters**
- `T` — the type of the value

**Parameters**
- `name` — what the help and errors call it
- `help` — what it is, for the help
- `required` — whether leaving it out is an error
- `default_value` — the value when it is left out, written as on the command line; empty for none

**Returns**
- the handle that reads the value

**Panics**
- if `name` is empty or already declared, if a required argument follows an optional one, if it follows `positionals`, if the parser has commands, or if `default_value` does not read as a `T`

#### positionals

```pepper
positionals(name: String, help: String = "", required: bool = false): ArgumentList<String>
```

Declares a positional argument that takes every remaining value, such
as a list of files. It must be the last positional argument.
`positionals<T>` declares one whose values are numbers, paths or enum
cases.

**Parameters**
- `name` — what the help and errors call it
- `help` — what the values are, for the help
- `required` — whether at least one value must be given

**Returns**
- the handle that reads the values, in the order given

**Panics**
- if `name` is empty or already declared, if it follows `positionals`, or if the parser has commands

#### positionals

```pepper
positionals<T>(name: String, help: String = "", required: bool = false): ArgumentList<T>
```

Declares a positional argument that takes every remaining value, each
of type `T`, such as a list of files for `positionals<io.Path>`. It
must be the last positional argument. `T` is one of the types
`option<T>` takes.

**Type parameters**
- `T` — the type of each value

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

#### add_options

```pepper
add_options<T>(options: T)
```

Declares an option or positional argument for each public field of
`options`, and has every successful parse store the values in those
fields.

A field's type picks what it declares: `bool` is a flag, `String` an
option with one value, `String?` one that may be left out, and
`String[]` one that may be given many times. An option is named after
its field, with each `_` written `-` (`import_path` is
`--import-path`); `[cli.Option]` on a field gives it a short name,
help, another name, or makes it required. `[cli.Positional]` makes a
field the next positional argument instead.

A `String` field that holds a value when this is called keeps it as
the default; an empty one has no default, so leaving the option out
leaves it empty, or is an error for a positional argument. Every
parse sets every field: a flag to whether it was given, a list to the
values given.

The declarations are the same as the builder methods make, so the
help and errors read the same, and the two styles mix on one parser.

**Type parameters**
- `T` — the options struct

**Parameters**
- `options` — the struct whose fields to declare and fill in

**Example**
```pepper
import cli;

struct Options {
    [cli.Option("o", "the executable to write")]
    var output: String = "a.out";
    [cli.Option("v", "say what is happening")]
    var verbose: bool;
    [cli.Positional("the program's entry file")]
    var source: String;
}

main(args: String[]): int {
    var options = Options();
    var parser = cli.Parser("pepper", "Compiles a Pepper program");
    parser.add_options(options);
    if (!parser.parse(args)) {
        return 2;
    }
    print($"{options.source} -> {options.output}");
    return 0;
}
```

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

## closest

```pepper
closest(name: String, candidates: Array<String>): String?
```

Returns the candidate closest to a misspelled `name`, for a "did you
mean" suggestion: the one the fewest single-byte insertions, deletions
and substitutions turn `name` into, when that is at most 2. Of equally
close candidates the first wins.

**Parameters**
- `name` — the name that matched nothing
- `candidates` — the names it could have meant

**Returns**
- the closest candidate, or none when none is within 2 edits

**Example**
```pepper
var names = Array<String>();
names.append("build");
names.append("fmt");
var best = cli.closest("buidl", names);   # some("build")
```

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
struct Argument<T>
```

An option or positional argument that takes one value, from
`Parser.option` or `Parser.positional`.

**Type parameters**
- `T` — the type of the value: `String`, or what `option<T>` or `positional<T>` declared

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
value(): T
```

Returns the value given, or the default when it was left out.

**Returns**
- the value

**Panics**
- if the argument was left out and has no default; check `is_set` or use `value_or` for an optional argument

#### value_or

```pepper
value_or(fallback: T): T
```

Returns the value given, or `fallback` when it was left out.

**Parameters**
- `fallback` — the value to use when the argument was left out

**Returns**
- the value given, else the declared default, else `fallback`

## ArgumentList

```pepper
struct ArgumentList<T>
```

An option that may be given many times, or a positional argument that
takes every remaining value, from `Parser.multiple` or
`Parser.positionals`.

**Type parameters**
- `T` — the type of each value: `String`, or what `multiple<T>` or `positionals<T>` declared

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
values(): Array<T>
```

Returns the values given, in command-line order.

**Returns**
- a new array of the values, empty when none was given
