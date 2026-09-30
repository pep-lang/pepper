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
pepper -I tools tools/pep-fmt/main.pep -o pep-fmt
```

It reads a source file on standard input and writes the formatted file to
standard output:

```bash
pep-fmt < main.pep > formatted.pep
```

If the file does not parse, `pep-fmt` writes nothing to standard output,
prints the first syntax error to standard error, and exits with status 1:

```text
<stdin>:2:14: error: expected ')'
```

## The style

**Layout.** Indentation is 4 spaces. A brace goes on the same line as the
declaration or statement that owns it, and `else` goes between the braces:

```pepper
if count > 0 {
    print(count);
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
    .filter((w) => w.length() > 4)
    .map((w) => w.length() * 2)
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

**Declarations.** Pepper functions and methods are written with the
parameter types after the names and the return type last,
`add(a: int, b: int): int`. The C-style form, `int add(int a, int b)`, is
kept for `extern` functions, which mirror C prototypes; `pep-fmt` rewrites
it everywhere else, including operator methods (`bool ==(Point other)`
becomes `==(other: Point): bool`, and `bool !!()` becomes `!!(): bool`),
indexers (`T [](ulong index)` becomes `[](index: ulong): T`) and constructor
parameters.

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

**Semicolons** are added where a statement or declaration leaves its `;`
out (see [Statements and semicolons](../language/statements.md)); none are
removed.

**Kept as written:** parentheses around
conditions (`if x` and `if (x)` are both fine), fields declared either way
(`int x;` or `var x: int;`), and the file's line endings (`\n` or `\r\n`).
