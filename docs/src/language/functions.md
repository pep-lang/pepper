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
  code; return 0 for success.
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
can pass an `int` where a `long` or `double` is expected, and a `String` where
a struct with an [`[Implicit]` constructor](structs.md#implicit-conversions)
from `String` (such as `io.Path`) is expected.

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

## Generic functions

A function can take type parameters in angle brackets after its name, such as
`first<T>(items: T[]): T`. [Generics](generics.md) covers them.

## Printing with `print`

`print` is a built-in function that writes its arguments to standard output,
each on its own line. It accepts any number of arguments, and each one can be a
`String`, an integer, a `bool` (printed as `1` or `0`), or a floating-point
number.

```pepper
{{#include ../../examples/functions-print.pep}}
```

To print several values on one line, build a `String` with `+` first.

A `float` or `double` prints with six digits after the decimal point, rounded:
`print(0.5)` prints `0.500000`.

For checks in your programs, the runtime also provides `assert(condition,
message)`, which stops the program with `message` when `condition` is false, and
`panic(message)`, which always stops it. Both take the message as a `String`, so
it can be built at run time (`assert(n > 0, name + " must be positive")`); a
string literal message costs nothing when the assertion holds. See
[Built-in functions](../reference/internals.md).

## Functions as values

A function's name used without a call is a value that you can store in a
variable, pass to another function, or return, and a closure such as
`(x: int) => x * 2` is a function written where it is used. See
[Function types and closures](function-types.md).
