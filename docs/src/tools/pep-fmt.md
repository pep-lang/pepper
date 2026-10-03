# Formatting with pep-fmt

`pep-fmt` rewrites Pepper source in one standard style, so that every Pepper
file reads the same and nobody has to argue about layout. It changes only
whitespace, line breaks, the order of imports, and the form of function
declarations; the program means exactly what it meant before.

`pep-fmt` is written in Pepper. Its parser is a separate library,
`tools/syntax`, that other tools can use.

## Running it

Build it with the compiler, with the `tools` folder on the import path:

```bash
pepper build -I tools tools/pep-fmt/main.pep -o pep-fmt
```

Give it files or directories, like `gofmt`:

```bash
pep-fmt main.pep            # print the formatted file to standard output
pep-fmt -w main.pep src/    # rewrite each file that is not formatted
pep-fmt --check src/        # list each file that is not formatted
pep-fmt < main.pep          # no files: standard input to standard output
```

### Options

```text
pep-fmt [OPTIONS] [paths]...
```

| Option | What it does |
| --- | --- |
| `<paths>` | Files to format, and directories to search for `.pep` files; none means standard input |
| `-w`, `--write` | Rewrite each file that is not formatted, instead of printing it |
| `--check` | Print the path of each file that is not formatted, and exit with 1 if there is one |
| `-h`, `--help` | Print the options |
| `-V`, `--version` | Print `pep-fmt` and its version |

`-w` and `--check` need at least one path. `pepper fmt` runs `pep-fmt` with
the same arguments.

A directory stands for every `.pep` file under it, in name order, skipping
directories whose names start with `.` (such as `.git` and the `.pep` build
cache). `-w` (or `--write`) rewrites only the files whose formatting changes. `--check`
changes nothing, prints the path of each file that `-w` would rewrite, and
exits with status 1 if there is one, which suits a CI step. The two can be
combined.

If a file does not parse, `pep-fmt` leaves it untouched, prints the first
syntax error to standard error, and exits with status 1 after the other
files. Standard input is named `<stdin>`:

```text
main.pep:2:14: error: expected ')'
```

A file that cannot be read or written also exits with status 1, and an
unknown option, or `-w` or `--check` without a path, exits with status 2
after printing the usage (`pep-fmt -h` prints the full help). pep-fmt parses its options with the
[`cli` module](../language/cli.md).

## The style

**Layout.** Indentation is 4 spaces. A brace goes on the same line as the
declaration or statement that owns it, and `else` goes between the braces:

```pepper
if count > 0 {
    print($"{count}");
} else {
    print("none");
}
```

A block stays on one line only when it holds a single `break`, `continue`
or `return` and was written on one line: `if done { return; }`.

**Line width.** Lines are at most 120 columns. A list that does not fit
(arguments, parameters, an import list) moves to its own indented line, and
if it still does not fit, puts one item on each line:

```pepper
report_values(
    first_argument, second_argument, third_argument, fourth_argument, fifth_argument, a_much_longer_argument
);
report_values(
    first_argument,
    second_argument,
    an_argument_so_long_that_the_whole_list_no_longer_fits_on_one_line_even_after_moving_it_down_one
);
```

A long expression breaks before each operator, and a chain of three or more
method calls that does not fit breaks before each `.`:

```pepper
if (first_condition_that_is_long(value) and second_condition_that_is_long(value)
    or third_condition_that_is_long(value)) {
    run();
}
total = first_value_that_is_long_enough
    + second_value_that_is_long_enough
    + third_value_that_is_long_and_longer_still;
var count = words
    .iterate()
    .filter((w) => w.length > 4)
    .map((w) => w.length * 2)
    .count_them_all();
```

Comments and string literals are never reflowed, so a line can stay longer
than 120 columns when it has nowhere to break.

**Attributes** go one per line, each on its own line above the declaration:

```pepper
[Target(OS(Linux))]
[Deprecated("use 'open' instead", "open")]
export open_file(path: String): int { return 0; }
```

A parameter's attributes are the exception: they stay on the parameter's line,
in front of it, as in `construct([Sending] T value)`.

**Declarations.** Pepper functions and methods are written with the
parameter types after the names and the return type last,
`add(a: int, b: int): int`. The C-style form, `int add(int a, int b)`, is
kept for `extern` functions, which mirror C prototypes; `pep-fmt` rewrites
it everywhere else, including operator methods (`bool ==(Point other)`
becomes `==(other: Point): bool`, and `bool !!()` becomes `!!(): bool`),
indexers (`T [](ulong index)` becomes `[](index: ulong): T`) and constructor
parameters. A `void` return type is left out when the function has a body
(`void run()` and `run(): void` both become `run()`); a declaration without
a body, such as a trait method, keeps it.

**Blank lines.** At most one blank line in a row. Top-level structs,
traits, extensions and functions with a body are separated by one blank
line.

**Comments** stay where they are, attached to the code next to them.
Trailing comments on consecutive lines are aligned, two spaces after the
longest line:

```pepper
var total = 0;      # the running sum
var count = 0;      # how many values
var average = 0.0;  # total / count
```

**Imports** that are next to each other (no blank line or comment between
them) are sorted: modules first (`import io;`), then files of this module
(`import "util";`), each by name.

**Kept as written:** parentheses around
conditions (`if x` and `if (x)` are both fine), fields declared either way
(`int x;` or `var x: int;`), and the file's line endings (`\n` or `\r\n`).

## Turning it off for a section

Code between a `# format: off` comment and a `# format: on` comment is left
exactly as written, for layouts the style would undo, such as a table of
numbers:

```pepper
# format: off
const IDENTITY = matrix(1, 0, 0,
                        0, 1, 0,
                        0, 0, 1);
# format: on
```

Each comment goes on its own line, between declarations or statements, and
the pair must be in the same block (or both at the top level). Without a
`# format: on`, the region runs to the end of the block or file.
