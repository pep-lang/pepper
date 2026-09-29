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

Such a function ends when it reaches the closing brace. A bare `return;` is not
supported yet (see [Control flow](control-flow.md#return)).

## Return types are not inferred

Always write the return type of a function that returns a value. Return type
inference is not implemented: a function without a return type is compiled as
returning a 32-bit `int`, so a `long` result is silently truncated, a `double`
loses its fraction, and returning a `String` or a struct crashes the compiler or
the program. For example, `half(x: double) { return x / 2; }` returns 2 for
`half(5.0)`, not 2.5.

## Parameters

Parameters are passed by value. For numbers and `bool`, the function receives
its own copy. For a `String`, an `Array` or any other struct, the value is a
reference, so the function receives another reference to the same object: it
can change the object's contents, and the caller sees the change. Assigning a
new object to the parameter does not affect the caller's variable.
[Memory and reference counting](memory.md) describes exactly how references are
counted when you pass them.

Arguments convert to the parameter's type the same way assignment does, so you
can pass an `int` where a `long` or `double` is expected.

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

> **Known problem:** printing a `float` or `double` currently shows the wrong
> digits after the decimal point (for example, `print(0.5)` prints
> `0.000005`). Convert to an integer with `as` if you need to print a
> floating-point value today.

For checks in your programs, the runtime also provides `assert(condition,
message)`, which stops the program with `message` when `condition` is false, and
`panic(message)`. See [Built-in functions](../reference/internals.md).

## Functions as values

A function's name used without a call is a value that you can store in a
variable, pass to another function, or return. See
[Function types and references](function-types.md).
