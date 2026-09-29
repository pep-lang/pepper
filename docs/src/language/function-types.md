# Function types and references

Functions in Pepper are values. You can store a function in a variable, a
field or an array, pass it to another function, and return it. This lets you
choose behavior at run time: a sort order, a callback, a step in a pipeline.

## Function types

A function type is written `(parameter types) => return type`:

| Type | Meaning |
|---|---|
| `(int) => int` | takes an `int`, returns an `int` |
| `(String, int) => bool` | takes a `String` and an `int`, returns a `bool` |
| `() => void` | takes nothing, returns nothing |
| `(int) => (int) => int` | takes an `int`, returns an `(int) => int` |

`=>` is right-associative, so the last row is a function that returns a
function. A function type can be used anywhere a type can: for variables,
parameters, return types, struct fields, generic arguments such as
`Array<(int) => int>`, and [type aliases](type-aliases.md).

## Referring to a named function

The name of a free function, written without a call, is a value of that
function's type. Calling a function value calls the function:

```pepper
{{#include ../../examples/function-types-basics.pep}}
```

- `var f = square;` infers `f`'s type, `(int) => int`, from the function.
- A function-typed variable can be reassigned to any function of the same type.
- A parameter of function type, such as `f: (int) => int`, lets the caller pass
  in the behavior. Generic functions can take function parameters too.

## Storing and returning functions

Function values go wherever other values go: struct fields, arrays,
module-level variables and return values. A type alias gives a long function
type a short name, and can have type parameters of its own.

```pepper
{{#include ../../examples/function-types-storage.pep}}
```

- **Fields.** A field of function type is called like a method:
  `t.op(4)`. Inside the struct, `op(x)` and `this.op(x)` both call it.
- **Arrays.** `pipeline[1](5)` indexes the array and calls the element.
- **Return values.** `pick(true)(5)` calls the function that `pick` returns.
- **`void` results.** A function without a return value has a function type
  ending in `=> void`, such as `(int) => void`.

## Type checking

A function value must match the type it flows into exactly: the same parameter
types in the same order and the same return type. The aliases of a primitive
type count as the same type, so `(i32) => i32` and `(int) => int` match.
A mismatch in an initializer, an assignment, an argument or a return is a
compile error, as is calling a function value with the wrong number of
arguments:

```pepper
square(x: int): int { return x * x; }

main(): int {
    var f: (String) => int = square;   # error
    return f(1, 2);                    # error
}
```

```
error: variable 'f' expects a function of type (String) => int, but was given a function of type (int) => int
a function of type (String) => int takes 1 argument(s), but 2 were given
```

These two errors do not show a source location yet.

## Null function values

A function-typed variable or field that has never been assigned is null.
Calling it stops the program with the message `called a null function value`:

```pepper
var handler: (int) => int;
handler(1);   # panics: called a null function value
```

## Names and shadowing

A local variable, parameter or field with the same name as a free function
hides the function inside its scope. Inside a function with a parameter named
`square`, `square` means the parameter, not the function.

## Memory

A function value is a reference, like a struct value, and follows the same
reference-counting rules (see [Memory and reference counting](memory.md)).
Referring to a named function allocates nothing: every reference to `square`
shares one static function object.

## What is not supported yet

- **Closures and lambdas.** Pepper has no anonymous functions yet, and a
  function value cannot capture local variables. Only named free functions can
  be used as values. Closures are planned.
- **Generic functions, methods, constructors and `extern` functions** cannot be
  referenced as values. Naming a generic function without a call reports
  `use of undeclared identifier`, and naming a method without a call
  (`var f = s.get;`) reports `no member named 'get' in 'S'`. To use one of these
  as a value, write a named free function that calls it.
