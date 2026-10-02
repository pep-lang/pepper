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
function. A function type carries no parameter names, so a call through a
function value passes its arguments by position:
[named arguments](functions.md#named-arguments) are an error there. A function type can be used anywhere a type can: for variables,
parameters, return types, struct fields, generic arguments such as
`Array<(int) => int>`, and [type aliases](type-aliases.md).

Written with `shared` in front, as in `shared () => void`, a function type is
thread-safe: its values can be passed to other threads. See
[Sharing function values between threads](#sharing-function-values-between-threads).

## Referring to a named function

The name of a free function, written without a call, is a value of that
function's type. Calling a function value calls the function:

```pepper
{{#include ../../examples/function-types-basics.pep}}
```

- `var f = square;` infers `f`'s type, `(int) => int`, from the function.
  An [overloaded](overloading.md#overloaded-functions-as-values) name, or
  an overloaded method (`p.move`), needs a declared type instead, which
  picks the member.
- An [`extern` function](c-interop.md) is a value too, of the type its C
  prototype gives: `var f = abs;` is an `(int) => int`. A variadic one,
  such as `snprintf`, is not.
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
| `b.map<long>` (a generic method) | `((int) => long) => Box<long>` | `b.map<long>(...)`, on the object `b` referred to |

- **Bound methods.** `p.norm` keeps a reference to the object, like a closure
  `() => p.norm()` that captured `p`, so the object lives as long as the
  value does. The expression before the `.` is evaluated once, when the value
  is made.
  A bound method is a function value, not the value the method returns:
  passing `p.name` where a `String` is expected is an error. Call it,
  `p.name()`. The methods of an enum whose cases carry nothing are not
  values at all (see [enums](enums.md#current-limits)).
- **Inside a method.** A bare method name is a value too, as a bare call
  is a call: `norm` means `this.norm`, and a static method's bare name
  means `Point.origin`. This works in closures, extensions and trait default
  methods as well. A local or parameter of the same name hides the method.
  Storing `norm` (or `this.norm`) in a field of `this` would be a reference
  cycle, and is an error, as for [closures](#this-in-methods).
- **Traits and extensions.** A method declared in an
  [extension](traits-and-extensions.md) works the same way, and so does a
  method of a trait-typed value (`shape.area`), which calls through the trait.
- **Generic functions.** Where a function type is expected, the generic
  function's name alone is enough: the expected type picks the
  specialization, as a call's arguments do. `var f: (int, int) => int =
  larger;` and `combine(larger, 2, 9)` both mean `larger<int>`, and a type
  parameter that appears only in the return type is bound from the
  expected return type. With no function type to go by, as in `var f =
  larger;`, write the type arguments:

  ```text
  main.pep:3:13: error: cannot infer the type arguments of 'larger' used as a value; write them (larger<T>) or give the value a function type
  ```
- **Generic methods.** A method with type parameters of its own is a
  value once they are known: written (`b.map<long>`,
  `Box<int>.map<long>`, `Box<int>.wrap<int>`) or picked by the function
  type it flows into, as for generic functions:
  `var m: ((int) => String) => Box<String> = b.map;` is `b.map<String>`.
  Without either, `var m = b.map;` is an error that asks for them.
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
- **Module-level variables.** Every module-level variable is `const` and
  thread-safe (see [Module-scope variables](threads.md#module-scope-variables)),
  so one whose function changes is an `Atomic` of a
  [`shared` function type](#sharing-function-values-between-threads):
  `handler.load()(1)` calls the current function and `handler.store(square)`
  replaces it.
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
the fields, so it sees the fields' current values. In a trait's
[default method](traits-and-extensions.md#default-method-bodies), a closure
can use `this` and the trait's methods the same way.

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

```text
main.pep:4:30: error: cannot initialize variable 'f' of type '(String) => int' with a value of type '(int) => int'
    4 |     var f: (String) => int = square;   # error
      |                              ^~~~~~
main.pep:5:12: error: too many arguments to function of type '(String) => int': expected 1, have 2
    5 |     return f(1, 2);                    # error
      |            ^
```

The compiler reports [one error at a time](compiler-errors.md#one-error-at-a-time),
so the second appears once the first is fixed.

## Sharing function values between threads

A plain function type such as `() => void` can hold any function value,
including a closure that captures a `String` or an `Array`. Such values stay
on the thread that made them: their reference counts are plain increments,
like those of a struct that is not `[Shared]` (see
[What threads can share](threads.md#what-threads-can-share)).

A function type written with `shared` in front, such as `shared () => void`
or `shared (long) => void`, is thread-safe. Its reference counts are atomic,
and its values hold only thread-safe state, so any thread may copy, call and
drop them. It goes wherever a thread-safe type is required: the body of a
thread (`ThreadBody` is `shared () => void`), a field of a `[Shared]` struct,
a module-scope variable, or `async.Atomic<shared (int) => int>`.

```pepper
{{#include ../../examples/function-types-shared.pep}}
```

- **What converts to `shared`.** A named function, which holds no state; a
  method, constructor or generic function value with nothing captured, such
  as `Point.norm` or `Box<int>`; and a closure literal (or a bound method
  such as `p.norm`) whose captured values are all
  [thread-safe](threads.md#what-threads-can-share): numbers, `Atomic<T>`
  and other `[Shared]` structs, `shared` function values, and the rest of
  that list. The value must be written where the `shared` type is expected,
  so that it is made thread-safe from the start.
- **What does not.** A closure that captures a value that is not thread-safe
  is reported at the capture, with a note at the captured variable:

  ```text
  main.pep:5:46: error: closure passed as 'shared () => void' captures 'name' of type 'String', which is not thread-safe
      5 |     var t = async.Thread.spawn(() => { print(name); });
        |                                              ^~~~
  main.pep:4:9: note: capture a thread-safe value instead, such as an 'async.Atomic<T>' or a '[Shared]' struct
      4 |     var name = "worker";
        |         ^~~~
  ```

  A closure in a method that uses `this` or a member captures `this`, so it
  is thread-safe only in a `[Shared]` struct. A value that already has a
  plain type (a variable, a parameter, a call result) never becomes
  `shared`, even when it holds nothing:

  ```text
  main.pep:3:32: error: cannot initialize variable 'f' of type 'shared () => void' with a value of type '() => void'
      3 |     var f: shared () => void = g;
        |                                ^
  ```

- **From `shared` to plain.** A `shared` value converts to the plain type of
  the same signature anywhere: `shared (long) => long` can be passed to a
  parameter of type `(long) => long`. The conversion allocates a small plain
  function value that holds the shared one and calls it, so the plain copy
  counts with plain increments while the shared value keeps its atomic ones.
- **Inference.** A variable initialized with a closure, such as
  `var f = () => 1;`, has a plain type. Write the type to make it `shared`:
  `var f: shared () => int = () => 1;`.
- `shared` is special only directly before a function type; elsewhere it is
  an ordinary name.

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
shares one static function object, and so does a generic function named
without its type arguments (`larger` as an `(int, int) => int`). A method, constructor or generic function
value allocates one small object, like a closure; a bound method's object
holds a reference to its receiver.

Creating a closure allocates one object holding the captured values, like
constructing a struct. Copying the closure adds a reference to that object,
and when the last reference goes, the object releases what it captured.

A plain function value's counts are plain increments; a `shared` one's are
atomic, like a `[Shared]` struct's (see
[Sharing function values between threads](#sharing-function-values-between-threads)).

## C function pointers

A C function pointer type, `extern (P...) => R`, holds a bare address that C
can call, not a function value: it takes a named function or a closure that
captures nothing, and never a closure that captures values. That is by
design; see [Passing a Pepper function to C](c-interop.md#passing-a-pepper-function-to-c)
for how a callback gets the state it needs.
