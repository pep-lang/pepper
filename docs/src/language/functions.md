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
    print(n);
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
`double`. `main` with no return type returns an `int`, and reaching its closing
brace exits with 0.

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

Defaults work the same way for methods and constructors. Pepper has no named
arguments: to give a later parameter a value, you pass every parameter before
it.

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

`print` is a built-in function that writes its arguments to standard output,
each on its own line. It accepts any number of arguments, and each one can be a
`String`, an integer, a `bool` (printed as `1` or `0`), a floating-point
number, or a [tuple](tuples.md) of these (printed as `(1, two)`).

```pepper
{{#include ../../examples/functions-print.pep}}
```

To print several values on one line, build a `String` first, with an
[interpolated string](interpolation.md) (`print($"line {n}")`) or `+`
(`print("line " + to_string(n))`).

`print` buffers its output. Writing to standard output through
`io.File.stdout()` flushes that buffer first, so text from the two comes out
in the order the program wrote it, even when standard output is a pipe.

A `float` or `double` prints with six digits after the decimal point, rounded:
`print(0.5)` prints `0.500000`.

For checks in your programs, the runtime also provides `assert(condition,
message)`, which stops the program with `message` when `condition` is false, and
`panic(message)`, which always stops it. Each is
[overloaded](overloading.md): the message may be a `String`, built at run time
(`assert(n > 0, name + " must be positive")`), or a C string, which a string
literal picks, so a literal message builds nothing when the assertion holds. See
[Built-in functions](../reference/internals.md).

## Command-line arguments and exit

`main` comes in two forms. `main(): int` takes nothing. `main(args:
String[]): int` receives the program's command-line arguments: element 0 is
the program as it was started, and the arguments typed after it follow in
order. Declare the parameter only when the program reads it, as a Windows
console program declares `argc`/`argv` only when it needs them. Any other
parameter list on `main` is an error, and so is declaring both forms.

Elsewhere, `arguments()` returns the same array, so code outside `main` can
read the arguments without having them passed down. `exit(code)` ends the
program at once with status `code`, from anywhere, after flushing what was
printed.

```pepper
{{#include ../../examples/functions-arguments.pep}}
```

`exit` skips everything that would run on the way out of `main`: locals are
not released and destructors do not run. Prefer returning from `main`, and
keep `exit` for ending from deep inside a call. See
[Arguments and exit](../reference/process.md).

## Functions as values

A function's name used without a call is a value that you can store in a
variable, pass to another function, or return, and a closure such as
`(x: int) => x * 2` is a function written where it is used. See
[Function types and closures](function-types.md).
