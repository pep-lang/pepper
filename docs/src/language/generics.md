# Generics

Generics let you write a struct or a function once and use it with many types.
Add type parameters in angle brackets after the name, then use them like any
other type name. The standard library's [`Array<T>`](../reference/array.md),
[`HashMap<K, V>`](../reference/hash.md), and
[`Result<TValue, TError>`](../reference/result.md) are all ordinary generic
structs written this way.

Pepper generics work like C++ templates: each distinct set of type arguments,
such as `Stack<int>` or `Stack<String>`, produces its own copy of the code,
compiled for those exact types. There is no runtime cost for using them.

## Generic structs

```pepper
{{#include ../../examples/generics-structs.pep}}
```

- Name the type parameters after the struct's name: `struct Stack<T>`,
  `struct Entry<K, V>`. Inside the struct, fields, parameters, return types,
  and locals can all use them.
- Name the type arguments whenever you use the struct: `Stack<int>()`,
  `var s: Stack<String>;`.
- `Stack<int>` and `Stack<String>` are different types.
- Each type argument makes a separate copy of the struct, so a struct whose
  copy needs a copy with a larger argument never ends: `struct Foo<T>` with
  a field `var inner: Foo<Array<T>>` makes `Foo<int>` need
  `Foo<Array<int>>`, which needs `Foo<Array<Array<int>>>`, and so on. The
  compiler stops 64 levels deep with an error at the type that asks for the
  next level (`'Foo' is specialized 65 levels deep, past the limit of 64`),
  with a note where the chain started.

## Generic functions

A free function takes type parameters the same way:

```pepper
{{#include ../../examples/generics-functions.pep}}
```

Pepper infers the type arguments from the arguments, so `larger(3, 9)` calls
`larger<int>`. You can always write them out, `larger<float>(2.5, 1.5)`, or
write only the leading ones and let the arguments give the rest:
`pick<int>(1, "x")` for `pick<T, U>(a: T, b: U)`. You must write them when the
arguments do not determine every type parameter, for example one that appears
only in the return type:

```text
main.pep:4:13: error: cannot infer the type arguments of 'make' from its arguments; write them: make<T>(...)
    4 |     var b = make();
      |             ^~~~
main.pep:1:1: note: declared here
    1 | make<T>(): Box<T> { return Box<T>(); }
      | ^~~~
```

A parameter whose type is a trait takes its type arguments from the trait the
argument's type declares: given `total<T>(items: Iterator<T>)`, the call
`total(Countdown(4))` infers `T = int` from `extend Countdown with
Iterator<int>`.

Inference works through closures in both directions. In
`transform(words, (w) => w.size)`, where `transform<T, U>(items: Array<T>,
f: (T) => U)`, `words` gives `T`, which types the closure's parameter `w`, and
the closure's result gives `U`.

Because each use is compiled for its concrete types, the body may use any
operator, field, or method that the type arguments provide. `total_area<T>`
calls `shape.area()`, so it works with any `T` that has an `area()` method
returning a number, and using it with a type that lacks one is a compile
error inside `total_area`. To state the requirement up front, and have the
compiler report it where the function is used, give `T` a
[constraint](#constraints).

## Generic methods

A method can have type parameters of its own, in a struct, a generic struct,
an extension, or a trait's default method. They are inferred at each call like
a function's, or written after the method name:

```pepper
{{#include ../../examples/generics-methods.pep}}
```

- Write the type arguments with no space before `<` or after `>`:
  `b.map<long>(f)`. With a space, `a.b < c` is a comparison.
- A generic method cannot be called through a [trait value](traits-and-extensions.md#traits-as-types),
  since each of its uses is compiled separately. Call it on the concrete type.
- The iterator adapters `map`, `filter`, `enumerate` and `zip` are generic
  default methods of `Iterator<T>`; see [Iteration](iteration.md#adapters).

## Default type arguments

A type parameter can have a default, written `Name=Type`. When a use leaves
that argument out, the default fills it in:

```pepper
{{#include ../../examples/generics-defaults.pep}}
```

Arguments are matched to parameters in order, so put the parameters that have
defaults last. The standard library declares `struct Result<TValue, TError=Error>`, so
`Result<int>` means `Result<int, Error>`. See
[Error handling with Result](results.md).

## Constraints

A type parameter can require a [trait](traits-and-extensions.md#traits):
write the trait after a colon, `T: Shape`. Every type argument for `T` must
then conform to `Shape`. Several constraints are joined with `&`, and a
constrained parameter can still have a default, written after them:

```pepper
{{#include ../../examples/generics-constraints.pep}}
```

Constraints work on generic structs, enums whose cases carry values,
functions, methods, traits and type aliases. A constraint may name the
parameters before it in the same list: `sum<T, I: Iterator<T>>(values: I)`.

A type argument conforms to a trait when:

- it is a struct declared to have the trait with
  `extend Circle with Shape`. For a generic struct, `extend Box<T> with Shape`
  makes every `Box<X>` conform, and `extend Box<int> with Shape` only
  `Box<int>`. A generic trait must match exactly: `extend Counter with
  Iterator<int>` conforms to `Iterator<int>`, not to `Iterator<long>`.
  Having the right methods is not enough; the extension is what declares it.
- it is the trait type itself (`Array<Shape>` passed as `Array<T>` with
  `T: Shape`), as long as every member of the trait can be called through a
  value of the trait type (see
  [traits as types](traits-and-extensions.md#traits-as-types)).
- it is a type parameter constrained by that trait: inside
  `wrap<T: Shape>`, `Gallery<String, T>` is allowed.

A number type, `char`, `bool` or an enum whose cases carry no values
conforms when it declares the trait the same way (`extend int with Shape`;
see [numbers, `bool` and enums](traits-and-extensions.md#numbers-bool-and-enums)),
for constraints only: it never becomes a trait value. Pointers, tuples and
function types conform to no trait.

### The `Shared` constraint

`T: Shared` is built in: it requires a type that is safe to share between
threads, by the same rule as a field of a `[Shared]` struct. The types that
conform are listed in
[What threads can share](threads.md#what-threads-can-share); no `extend`
can make another type conform. It gives `T` no methods, and it joins other
constraints with `&` (`T: Shared & Named`):

```pepper
{{#include ../../examples/generics-shared.pep}}
```

The standard library states the rule this way where it applies:
`spawn<T: Shared>`, `run_blocking<T: Shared>` and `Lazy<T: Shared>`, so
`async.spawn<String>(...)` is reported at `String`, with a note saying why
it is not thread-safe (`'String' is not declared [Shared]`). In a
constraint, `Shared` always means this built-in, so a trait cannot be
named `Shared`. A generic that passes its own `T` to one of these (say
`run_blocking<T>`) needs `T: Shared` too.

A constraint can name another type parameter of the same declaration:
`count_all<T, I: Iterator<T>>(source: I)`. Inference reads it too: the
argument gives `I`, and the `Iterator<...>` that `I` declares gives `T`. A
trait's default method may name the trait's own parameters
(`put_all<I: Iterator<T>>` in `trait Sink<T>`), which take the arguments of
the conformance (`extend Sum with Sink<int>`).

```pepper
{{#include ../../examples/generics-constraint-inference.pep}}
```

The compiler checks every use: a type argument you write, one it infers from
a call, a default, and a
[concrete override](#overriding-a-generic-function-for-one-type). The error
points at the type argument, or at the call argument the type came from:

```text
main.pep:11:21: error: 'Circle' does not conform to trait 'Shape', required by 'T' in 'Gallery'
   11 |     var g = Gallery<Circle>();
      |                     ^~~~~~
main.pep:7:19: note: constraint declared here
    7 | struct Gallery<T: Shape> {
      |                   ^~~~~
main.pep:4:8: note: declare it with 'extend Circle with Shape'
    4 | struct Circle {
      |        ^~~~~~
```

A type parameter passed on to a constrained one must carry the constraint
itself: `wrap<T>(item: T): Gallery<String, T>` is an error that suggests
`T: Shape`. The language server offers both the extension and the constraint
as quick fixes.

- A constraint must name a trait: `T: Point`, with `Point` a struct, is an
  error.
- An extension of a constrained struct keeps its constraints:
  `extend Gallery<TTag, TShape>` needs no `TShape: Shape` of its own. You
  may restate them as documentation, `extend Gallery<TTag, TShape: Shape>`.
  A constraint the struct does not have makes a
  [constrained extension](#constrained-extensions).
- In an [overload set](overloading.md#generic-members), a generic member
  whose inferred type arguments do not meet its constraints is not viable,
  and the error lists why.
- A constrained name is always a type parameter, never an override's type
  argument: `describe<Point: Shape>` declares a generic function whose
  parameter happens to be named `Point`.

### Inside a constrained generic

The compiler also checks the generic itself, once, whether or not anything
uses it: inside `largest<T: Shape & Ordered>`, a value of type `T` offers
exactly what `Shape` and `Ordered` declare. It may:

- call their instance methods and operators (`item.area()`, `best < item`),
- call their static members through the parameter (`T.unit()`),
- convert to one of their trait types (`var shape: Shape = item;`),
- be stored, passed, returned, and compared with `==`, `!=`, `===` and `!==`.

```pepper
{{#include ../../examples/generics-constrained-bodies.pep}}
```

Anything else is an error at the member or operator, even before any use:
a field, a method no constraint declares, a constructor `T()`, a call of a
constraint's method with the wrong number or types of arguments, or
initializing, assigning or returning a `T` as another type. (Passing a `T`
to a function that takes another type is still reported in each
specialization.)

```text
main.pep:5:45: error: no member named 'perimeter' in 'T'
    5 | total<T: Shape>(item: T): int { return item.perimeter(); }
      |                                             ^~~~~~~~~
main.pep:5:10: note: 'T' is constrained by 'Shape', which has no member 'perimeter'
    5 | total<T: Shape>(item: T): int { return item.perimeter(); }
      |          ^~~~~
```

A method that two constraints both declare is an error too
(`'name' is declared by both 'Named' and 'Titled'; call it through one of
them`).

Each use is still compiled for its type argument, so a call goes straight
to that type's own method, with no trait value in between. A parameter
without a constraint keeps working as before: its uses are checked in each
specialization. In a list that mixes the two, such as `f<T: Shape, U>`, only
the uses of `T` are checked in the generic.

## Constrained extensions

An extension of a generic struct can add a constraint the struct does not
have: `extend Box<T: Named> { ... }`. Its members exist only on the
specializations whose type argument meets it, so `Box<Square>` has
`label()` and `Box<String>` does not. With `with`, the constraint makes a
**conditional conformance**: after `extend Box<T: Shape> with Shape`, a
`Box<Square>` is a `Shape` (it can be passed where `T: Shape` is required
and converted to a `Shape` value), and a `Box<String>` is not.

```pepper
{{#include ../../examples/generics-constrained-extensions.pep}}
```

- Every `Box<X>` keeps the struct's own members and constraints; an
  extension adds to them, it never removes any.
- Inside the extension, `T` offers the struct's constraints and the
  extension's, as in any [constrained generic](#inside-a-constrained-generic).
- A call of a member the specialization does not have names the constraint
  it misses:

```text
main.pep:20:9: error: no member named 'label' in 'Box<Circle>'
   20 |     box.label();
      |         ^~~~~
main.pep:15:15: note: 'label' requires 'Circle' to conform to 'Named'
   15 | extend Box<T: Named> {
      |               ^~~~~
```

  and a type argument that misses a conditional conformance says so too
  (`'Box<String>' conforms to 'Shape' only when 'String' conforms to
  'Shape'`).
- Only the struct's own parameters can carry an extension's constraints:
  `extend Box<int: Shape>` is an error.
- A conformance that holds for every `Box` needs its members on every
  `Box`: `extend Box<T> with Named` cannot rest on a `name()` that only
  `extend Box<T: Named>` provides. Make the conformance conditional
  instead (`extend Box<T: Named> with Named`).
- Several extensions may declare the same trait with different
  constraints; a specialization conforms when it meets any of them.
- Inside another generic, a call such as `b.label()` on a `Box<T>` is
  checked in each specialization, like any member of a generic struct.

## Overriding a generic function for one type

You can give a generic function a separate definition for a specific type
argument. Write the concrete type where the type parameter would go:

```pepper
{{#include ../../examples/generics-overrides.pep}}
```

A call whose type argument matches an override, such as `describe<int>(7)`,
uses the override; every other call uses the generic version. The standard
library uses this to give [`hash<String>`](../reference/hash.md) a
content-based hash, while `hash<T>` hashes other structs by identity; a
struct keyed by its content overrides `hash<T>` the same way (see
[Hashing and equality](hashing.md)).

An override can name a built-in type (`int`, `bool`, `String`, and so on) or
a struct, such as `describe<Point>`. It may be declared in any file that can
see both the generic function and the struct: here `main.pep` overrides
`shapes.pep`'s `describe<T>` for its own `Point`, and the generic code in
`shapes.pep` uses the override too:

```pepper
{{#include ../../examples/generics-struct-override/shapes.pep}}
```

```pepper
{{#include ../../examples/generics-struct-override/main.pep}}
```

A function whose type parameters all name types the file can see (its own,
the ones it imports, under any name such as `P` after
`import [Point as P] from geo`, and the standard library's) is an override
when the file can also see a generic function of that name and number of
type parameters (its own, an imported one, or the standard library's);
otherwise a struct's name is just the name of a type parameter. The generic
may be spelled by any name the file has for it (`show<Point>` after
`import [describe as show]`). A type argument must name a struct, not a type
alias or a trait. A generic and another function of the same name in one
file are [overloads](overloading.md#generic-members), unless they have the
same parameters, or the generic's type parameters all name structs the file
can see without a generic of that name to override: either is an error,
since it usually means an override whose type argument the file cannot see,
or of a generic the file's own function of that name hides.

To add methods to a generic struct from outside its declaration, use an
[extension](traits-and-extensions.md#extending-generic-structs).
