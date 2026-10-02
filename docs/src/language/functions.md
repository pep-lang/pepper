# Functions

A function is a named block of code that takes parameters and can return a
value. Functions declared at the top level of a file are free functions; functions
declared inside a struct are methods, covered in [Structs](structs.md).

## Declaring a function

Write the name, the parameters in parentheses as `name: Type`, and the return
type after a colon:

```pepper
area(width: int, height: int): int {
    return width * height;
}
```

Pepper also accepts a C-style form, with the return type first and each
parameter's type before its name:

```pepper
int perimeter(int width, int height) {
    return 2 * (width + height);
}
```

Both forms declare the same kind of function; pick one style and use it
consistently. The first form is the one used throughout this book.

```pepper
{{#include ../../examples/functions-basics.pep}}
```

- **Order does not matter.** A function can call functions declared later in
  the file, and can call itself.
- **The program starts at `main`.** `main(): int` returns the process's exit
  code; return 0 for success. To receive the command-line arguments, declare
  it `main(args: String[]): int` instead. See
  [Command-line arguments and exit](#command-line-arguments-and-exit).
- **Calls must match the declaration.** Passing the wrong number of arguments
  is a compile error:

  ```
  main.pep:3:12: error: too many arguments to 'add': expected 2, have 3
      3 |     return add(1, 2, 3);
        |            ^~~
  ```

## Functions that return nothing

A function that returns no value leaves out the return type. You can also write
`: void`, or `void` in front in the C-style form:

```pepper
log(message: String) { print(message); }
log_line(message: String): void { print(message); }
void log_c(String message) { print(message); }
```

Such a function ends when it reaches the closing brace, or earlier at a bare
`return;`:

```pepper
log_positive(n: int) {
    if n <= 0 {
        return;
    }
    print($"{n}");
}
```

A call to such a function has no value, so it cannot be stored, passed,
returned, or used as an operand or condition: `var x = log("hi");` reports
`cannot use a value of type 'void' as variable 'x'`.

In a function that returns a value, `return;` is an error:

```text
main.pep:2:5: error: non-void function 'f' should return a value
    2 |     return;
      |     ^~~~~~
```

## Inferred return types

A function without a return type gets one from its `return` statements. It
returns `void` when no `return` has a value, and otherwise the type of the first
`return` that has one, so `half(x: double) { return x / 2; }` returns a
`double`. A generic function's return type is inferred for each
specialization, so `first<T>(a: T, b: T) { return a; }` returns an `int` for
`first<int>`. `main` with no return type returns an `int`, and reaching its
closing brace exits with 0.

Writing the return type is still clearer for a function that returns a value,
and it lets the compiler check each `return` against it.

## Parameters

Parameters are passed by value. For numbers and `bool`, the function receives
its own copy. For a `String`, an `Array` or any other struct, the value is a
reference, so the function receives another reference to the same object: it
can change the object's contents, and the caller sees the change. Assigning a
new object to the parameter does not affect the caller's variable.
[Memory and reference counting](memory.md) describes exactly how references are
counted when you pass them.

Arguments convert to the parameter's type the same way assignment does, so you
can pass an `int` where a `long` or `double` is expected, a `double` where an
`int` is expected (it truncates toward zero, like `int n = 2.7;`), and a
`String` where a struct with an
[`[Implicit]` constructor](structs.md#implicit-conversions) from `String` (such
as `io.Path`) is expected.

## Default parameter values

A parameter can have a default value, written `= value` after its type. A call
that leaves the argument out gets the default. Put parameters with defaults at
the end of the list, since arguments are matched from the left.

```pepper
{{#include ../../examples/functions-defaults.pep}}
```

Defaults work the same way for methods and constructors. To give a later
parameter a value without passing every parameter before it, name it (see
[Named arguments](#named-arguments)).

## Named arguments

A call can name its arguments, `name = value`, so it reads clearly and can
set one defaulted parameter without passing the ones before it:

```pepper
{{#include ../../examples/functions-named-arguments.pep}}
```

- **Positional first.** Positional arguments come first and match parameters
  from the left; named arguments follow, in any order. A positional argument
  after a named one is an error: `positional argument cannot follow a named
  argument`.
- **Each parameter once.** Naming a parameter that already has an argument is
  an error: `argument for 'width' given twice`.
- **Every required parameter.** A parameter without a default must get an
  argument: `missing argument for parameter 'title' in call to 'window'`. A
  name the function does not have is an error, with a suggestion when one is
  close: `no parameter named 'widht' in 'window'; did you mean 'width'?`.
- **Order of evaluation.** Arguments are evaluated in the order written, then
  passed to their parameters.
- **Everywhere a call is.** Free functions, methods, static methods,
  constructors (a `this.x` parameter is named `x`), extension methods, enum
  methods, generic functions, and calls through a [trait](traits-and-extensions.md)
  value, which use the trait's parameter names. A method that implements a
  trait should use the trait's names, so a call names the same arguments
  either way: a different name is a warning (`parameter 'factor' of 'area'
  is named 'scale' in trait 'Shape'`) whose fix renames the parameter.
- **Overloads.** A member of an [overload set](overloading.md) without a
  parameter of a given name is not a candidate, so names can pick between
  overloads.
- **Not through function values.** A [function type](function-types.md)
  carries no parameter names, so a call through a function value is
  positional only: `cannot name arguments in a call through a function value
  of type '(int, int) => int'`.
- **Not to `extern` functions.** Their parameter names are copied from C
  headers and stay free to change: `cannot name arguments in a call to extern
  function 'CreateFileW'`. Wrap the C function in a Pepper function to give
  it named arguments.

### Other names for a parameter

Two attributes on a function give its parameters more names. In both, the
declared parameter's name comes second:

- `[Alias("size", "count")]` lets a call name parameter `count` as `size`
  too, permanently.
- `[Rename("n", "count")]` keeps the former name `n` working after the
  parameter was renamed to `count`. Each use warns, like a
  [deprecated](deprecation.md) declaration, with a fix that renames it.

The first name must not already be a parameter or another name, and the
second must be a parameter of the function. A call that names one parameter
by two of its names gets `argument for 'count' given twice`.

## Returning several values

A function returns several values as a [tuple](tuples.md), and the caller
destructures it:

```pepper
divide(a: int, b: int): (int, int) {
    return (a / b, a % b);
}

var (quotient, remainder) = divide(17, 5);
```

## Overloading

Functions of one file can share a name when their parameter lists differ,
and each call picks the best fit for its arguments. See
[Overloading](overloading.md).

## Generic functions

A function can take type parameters in angle brackets after its name, such as
`first<T>(items: T[]): T`. [Generics](generics.md) covers them.

## Printing with `print`

`print(value)` writes a value's text and a line break to standard output:
what [interpolating](interpolation.md#which-values-can-be-interpolated) it,
`$"{value}"`, would make. That covers a `String`, numbers, `bool` (`true` or
`false`), tuples, and any type with a `to_string()`. To print several values
on one line, interpolate them (`print($"total: {n}")`), or pass a format
string and its arguments, which prints what
[`String.format`](interpolation.md#formatting-by-position-stringformat) makes
of them (`print("{0} of {1}", done, total)`).

```pepper
{{#include ../../examples/functions-print.pep}}
```

- With a string literal and **no other arguments**, the text prints as
  written: its braces are not a format.
- A value with no text form is an error at the argument:

```text
main.pep:5:11: error: cannot print a value of type 'Foo': it has no 'to_string()' method and no 'to_string' overload
    5 |     print(f);
      |           ^
```

`print` writes each line out as it prints it, like Rust's `println!`, so the
output appears as the program runs even when standard output is a pipe or a
file. Text from `print` and from `io.File.stdout()` comes out in the order
the program wrote it.

A `float` or `double` prints its shortest exact text (`print(0.5)` prints
`0.5`), and a tuple its elements in parentheses (`(1, two)`).

## Assertions and panics

For checks in your programs, the runtime provides `assert(condition,
message)`, which stops the program with `message` when `condition` is false, and
`panic(message)`, which always stops it. Each is
[overloaded](overloading.md): the message may be a `String`, built at run time
(`assert(n > 0, name + " must be positive")`), or a C string, which a string
literal picks, so a literal message builds nothing when the assertion holds. See
[Built-in functions](../reference/internals.md).

A panic flushes what the program printed, writes the location of the failing
call and the message to standard error, and aborts:

```text
main.pep:12:5: panic: count must be positive
```

The checks the compiler adds report the same way, at the expression that
failed: an [overflowing operator](types-and-variables.md#integer-overflow), a
null function value, a `match` on a null reference enum. So do the runtime's
checking methods, which report their caller's line, not their own: indexing an
`Array` or `String` out of range, `Array.pop()` on an empty array,
`Optional.value()` on none, `Result.value()` on an error, and the like.

They do it with an ordinary [default parameter](#default-parameter-values),
`location: __ptr<char> = __caller_location()`. A call that leaves `location`
out gets the place of that call, as `file:line:col`. Write the same parameter on
a function of your own that checks its arguments, and pass `location` on to
`assert` or `panic`, so a failure names the line that passed the bad value:

```pepper
{{#include ../../examples/functions-caller-location.pep}}
```

Written anywhere else, `__caller_location()` is its own location. A
compiler-generated check with no single place to report, such as a call through
a null trait value, prints the message alone.

## Command-line arguments and exit

`main` comes in two forms. `main(): int` takes nothing. `main(args:
String[]): int` receives the program's command-line arguments: element 0 is
the program as it was started, and the arguments typed after it follow in
order. Declare the parameter only when the program reads it, as a Windows
console program declares `argc`/`argv` only when it needs them. Any other
parameter list on `main` is an error, and so is declaring both forms.

Elsewhere, `process.arguments()` returns the same array, so code outside
`main` can read the arguments without having them passed down.
`process.exit(code)` ends the program at once with status `code`, from
anywhere, after flushing what was printed. Both are in the
[`process` module](processes.md), so the file needs `import process`.

```pepper
{{#include ../../examples/functions-arguments.pep}}
```

`exit` skips everything that would run on the way out of `main`: locals are
not released and destructors do not run. Prefer returning from `main`, and
keep `exit` for ending from deep inside a call. See
[Processes](processes.md).

## Functions as values

A function's name used without a call is a value that you can store in a
variable, pass to another function, or return, and a closure such as
`(x: int) => x * 2` is a function written where it is used. See
[Function types and closures](function-types.md).
