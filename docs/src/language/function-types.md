# Function types and closures

Functions in Pepper are values. You can store a function in a variable, a
field or an array, pass it to another function, and return it. This lets you
choose behavior at run time: a sort order, a callback, a step in a pipeline.
A function value is a named function, a method, a constructor, or a closure:
an anonymous function written where it is used.

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

## Methods, constructors and generic functions

Methods, constructors and specializations of generic functions are values
too:

```pepper
{{#include ../../examples/function-types-references.pep}}
```

| Written | Type | Calls |
|---|---|---|
| `p.norm` | `() => int` | `p.norm()`, on the object `p` referred to when the value was made |
| `Point.norm` | `(Point) => int` | `norm` on the object passed as the first argument |
| `Point.origin` (a `static` method) | `() => Point` | `Point.origin()` |
| `Point` | `(int, int) => Point` | the constructor |
| `Box<int>` | `(int) => Box<int>` | the constructor of `Box<int>` |
| `larger<int>` | `(int, int) => int` | the specialization `larger<int>` |

- **Bound methods.** `p.norm` keeps a reference to the object, like a closure
  `() => p.norm()` that captured `p`, so the object lives as long as the
  value does. The expression before the `.` is evaluated once, when the value
  is made. Inside a method, write `this.norm`; a bare `norm` is not a value.
  Storing `this.norm` in a field of `this` would be a reference cycle, and is
  an error, as for [closures](#this-in-methods).
- **Traits and extensions.** A method declared in an
  [extension](traits-and-extensions.md) works the same way, and so does a
  method of a trait-typed value (`shape.area`), which calls through the trait.
- **Generic functions** need their type arguments: `larger<int>`, not
  `larger`.
- **A type with a constructor that takes no arguments.** `Box<int>` on its
  own names the constructor only when the constructor needs at least one
  argument; otherwise it is a call, `Box<int>()`. The same goes for a generic
  function whose parameters all have defaults.

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
- **Module-level variables.** Every module-level variable is `const` (see
  [Module-scope variables](threads.md#module-scope-variables)), so one whose
  function changes is an `Atomic`: `handler.load()(1)` calls the current
  function and `handler.store(square)` replaces it.
- **Return values.** `pick(true)(5)` calls the function that `pick` returns.
- **`void` results.** A function without a return value has a function type
  ending in `=> void`, such as `(int) => void`.

## Closures

A closure literal is a parameter list, `=>`, and a body. The body is an
expression or a block:

```pepper
{{#include ../../examples/function-types-closures.pep}}
```

- **Parameter types.** `(x: int) => x * 2` writes the parameter type. When the
  closure goes straight into a slot of function type (a typed variable, a
  parameter, an assignment, a `return`, a field), the types come from that
  slot, so `(a, b) => a + b` is enough. A parameter of a generic function
  counts too: passing `(x) => x + 1` to `apply<T>(f: (T) => T, x: T)` with
  `x` an `int` types the closure's `x` as `int` (see
  [Generics](generics.md#generic-functions)). With no slot to take them from, a
  parameter without a type is an error:

  ```
  main.pep:2:14: error: cannot infer the type of parameter 'x'; write it: (x: Type) => ...
  ```

- **Return type.** It is inferred from the body, or from the slot. To write
  it, put it after the parameters: `(x: int): long => x`.
- **Body.** An expression body is the value the closure returns. A block body
  uses `return` like a function. A closure whose type returns `void` can have
  an expression body such as `() => counter.add(1)`; the value is discarded.
- **Calling.** A closure is called like any function value, and can be called
  where it is written: `((x: int) => x + 1)(2)`.

### Captured values

A closure can use the local variables and parameters around it. It keeps a
copy of each one it uses, made when the closure is created, so it can outlive
the function that created it (`make_adder` above).

A captured variable must never be assigned, before or after the closure is
created, inside the closure or outside it. Then the copy and the variable can
never differ:

```pepper
var count = 0;
var f = () => count;
count = 5;   # error
```

```
main.pep:4:5: error: cannot assign to 'count' because a closure captures it
main.pep:3:19: note: captured here; a closure keeps a copy, so the variable must not change
```

The rule applies to `++`, `--` and compound assignments too. Only the
variable is fixed: a captured struct is a reference to the same object, so the
closure can call its methods and change its fields (`counter` above). To share
a changing number, capture a struct that holds it, such as a `Counter` or an
[`Atomic<int>`](atomics.md).

### `this` in methods

A closure written in a method can use `this`, the struct's fields and its
methods. It captures `this` (one reference to the object), never a copy of
the fields, so it sees the fields' current values.

Storing such a closure in a field of the same object would make the object
and the closure keep each other alive forever (a reference cycle), so that
direct case is an error:

```
main.pep:4:15: error: storing a closure that captures 'this' in field 'measure' of 'this' creates a reference cycle that is never freed
```

Capture a [weak reference](memory.md#weak-references) to the object instead.

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
shares one static function object. A method, constructor or generic function
value allocates one small object, like a closure; a bound method's object
holds a reference to its receiver.

Creating a closure allocates one object holding the captured values, like
constructing a struct. Copying the closure adds a reference to that object,
and when the last reference goes, the object releases what it captured.

## What is not supported yet

- **Generic functions without type arguments and `extern` functions** cannot
  be referenced as values. `larger` alone is not a value even where the
  expected type would pick `larger<int>`. To use an `extern` function as a
  value, wrap it in a closure: `(x: int) => abs(x)`.
- **Generic methods** cannot be referenced as values: `b.map<long>` is not
  a value. Wrap the call in a closure: `(f: (int) => long) => b.map(f)`.
- **A bare method name inside a method** (`var f = norm;`) is not a value;
  write `this.norm`.
- **Closures in trait default methods** cannot use `this` or the members of
  the struct yet.
- **C callbacks.** A closure cannot be passed to a C function that expects a
  function pointer.
