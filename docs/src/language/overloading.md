# Overloading

Several free functions in one file can share a name when their parameter
lists differ. Each call picks the one whose parameters fit its arguments
best:

```pepper
{{#include ../../examples/overloading-basics.pep}}
```

The functions of one name in one file are an **overload set**, and each is a
member of it; the files of one [module](modules.md#modules) may share a
set, and so do the sets a file imports, the runtime's, and its own functions of that name. [Methods](#methods-and-operators) of one name in a struct are a
set too, and so are its static methods, its operators, its
[constructors](#constructors), and the methods its
[extensions](#extensions-and-traits) add.

## Declaring overloads

- **The parameter lists must differ** in the number or the types of the
  parameters. Parameter names and default values do not count (though
  [named arguments](#how-a-call-picks-a-member) can pick between members
  that differ in types), and neither does the return type:

  ```text
  main.pep:2:1: error: functions that differ only in their return type cannot be overloaded
      2 | f(x: int): long { return 2; }
        | ^
  main.pep:1:1: note: previous declaration is here
      1 | f(x: int): int { return 1; }
        | ^
  ```

  Two functions with the same parameter types and the same return type are
  a `redefinition of 'f'`.
- **A file's own functions join imported ones.** A file's functions of a
  name and the functions its imports bind to that name are one set (see
  [Imported sets merge](#imported-sets-merge)).

### Files of one module share a set

When an import or a re-export takes one name from two files of the same
module, and both are functions declared under that name, it takes their
union: one set of every member. Here `shapes/module.pep` re-exports `area`
from two files:

```pepper
{{#include ../../examples/overloading-modules/shapes/module.pep}}
```

```pepper
{{#include ../../examples/overloading-modules/shapes/square.pep}}
```

```pepper
{{#include ../../examples/overloading-modules/shapes/rect.pep}}
```

```pepper
{{#include ../../examples/overloading-modules/main.pep}}
```

A file of the module sees the members its own file and the module's files it
imports declare (see
[Visibility](visibility.md#files-of-a-module-see-each-other-through-imports)).
That holds for unexported functions too: functions of one name that files of
a module declare, exported or not, are one set wherever those files are
imported. Members from different files must still differ in their
parameters (`redefinition of 'area'`). Names that are not all functions,
such as two structs `Point`, and a renaming re-export
(`export size as area` beside an `area`) are still `exported twice`.

### Imported sets merge

Sets of one name from different modules merge too, as they do in Swift:
where two imports bind `describe`, and where the file declares `describe`
itself, an unqualified `describe(…)` picks among every member. Here two
modules each export one member and the file adds a third:

```pepper
{{#include ../../examples/overloading-imports/numbers/module.pep}}
```

```pepper
{{#include ../../examples/overloading-imports/flags/module.pep}}
```

```pepper
{{#include ../../examples/overloading-imports/main.pep}}
```

Unlike files of one module, two modules may each export a member with the
same parameters. That is no error until a call cannot tell them apart:

```text
main.pep:3:22: error: call to 'parse' is ambiguous
    3 | main(): int { return parse(1); }
      |                      ^~~~~
a.pep:1:8: note: candidate function
    1 | export parse(x: int): int { return 1; }
      |        ^~~~~
b.pep:1:8: note: candidate function
    1 | export parse(x: int): int { return 2; }
      |        ^~~~~
```

A qualifier (`a.parse(1)`) picks one module's set. A file's own member
hides an imported member with the same parameters, so a file can replace
one member of an imported set. Only functions merge: a struct or variable
of the name hides imported functions of it (or, named in an import list,
is `'parse' is imported but also declared in this file`).

### The runtime's sets

The [prelude](modules.md)'s functions, such as the runtime's `print` and
`to_string`, are a set too, which a file's own and imported functions of
the name join. Here `point.pep` adds a `print` member and the file adds a
`to_string` member, and the runtime's members still take every other
call:

```pepper
{{#include ../../examples/overloading-runtime/point.pep}}
```

```pepper
{{#include ../../examples/overloading-runtime/main.pep}}
```

A member may not take a runtime member's parameters, since a call could
not tell the two apart. With the same return type (or one left to
inference) it is a redefinition:

```text
main.pep:1:1: error: redefinition of 'print'
    1 | print(text: String) {}
      | ^~~~~
runtime/string.pep:1850:8: note: previous definition is here
 1850 | export print(text: String) {
      |        ^~~~~
```

and with another return type it is the same error as for two members of
one file:

```text
main.pep:1:1: error: functions that differ only in their return type cannot be overloaded
    1 | to_string(value: int): int { return value; }
      | ^~~~~~~~~
runtime/string.pep:1621:8: note: previous declaration is here
 1621 | export to_string(value: int): String {
      |        ^~~~~~~~~
```

Give the function another name or other parameters instead. A struct or
variable named like a runtime function hides all of its members.

### Members may differ in visibility

Exported members are what other files see; a private member is a candidate
only for calls in its own file, or in its module's files. Here `shapes.pep` exports `area(int)` and
keeps the two-argument form as a helper:

```pepper
{{#include ../../examples/overloading-visibility/shapes.pep}}
```

```pepper
{{#include ../../examples/overloading-visibility/main.pep}}
```

A call that only the private member fits is an error in another file,
and its notes list only the exported members:

```text
main.pep:2:22: error: no matching function for call to 'area'
    2 | main(): int { return area(2, 3); }
      |                      ^~~~
shapes.pep:2:8: note: candidate function not viable: requires 1 argument, but 2 were provided
    2 | export area(side: int): int {
      |        ^~~~
```

Importing the name (`import [area] from "shapes"`, or the whole file)
brings every exported member, and `import [area as size]` renames the
whole set. A re-export (`export area;`, `export * from "shapes"`) passes
on the exported members too; a set whose members are all private is
re-exported whole.

### `extern` functions do not overload

An `extern` function does not overload, by design: an extern is a C
function, which has one symbol, and keeping one extern per name keeps
the binding to C one-to-one. To put a family of C functions such as
`abs` and `llabs` behind one name, give each extern a name of its own
(`[Link(name = ...)]` binds it to the C symbol) and overload Pepper
functions that call them. With optimization on (`-O2`), LLVM inlines
the small wrappers:

```pepper
{{#include ../../examples/overloading-externs.pep}}
```

Overloading the extern itself is an error that says so (`extern 'abs'
cannot be overloaded; rename it and overload Pepper functions named
'abs' that call it`).

## How a call picks a member

A member is **viable** when the call has between its required and total
number of parameters and each argument converts to its parameter. For each
argument, the conversion has a rank, best first:

| Rank | What converts |
|------|---------------|
| exact | the same type; a string literal to `__ptr<char>` or [`StringConstant`](types-and-variables.md#string-constants) |
| promotion | an integer widening that loses nothing (`int` to `long`, `u8` to `int`; the narrower target ranks better, so a `short` picks `int` over `long`), `float` to `double`, an integer literal to any integer type it fits, a struct to a [trait it declares](traits-and-extensions.md#traits-as-types), `__null` to a reference, a string literal to `String` |
| conversion | any other numeric conversion (`bool` included), and pointer conversions |
| implicit constructor | a value to a struct whose [`[Implicit]` constructor](structs.md#implicit-conversions) takes it |

One viable member is **better** than another when none of its arguments
ranks worse and at least one ranks better, as in C++. Between two members
whose arguments rank the same, a non-generic one is better than a generic
one, and of two generic ones the **more specialized** is better: the one
whose parameter types the other's could take but not the reverse. So
`describe<A, B>(pair: (A, B))` takes a tuple argument over
`describe<T>(value: T)`, which takes anything else. The call picks the
member that is better than every other viable one. When there is none, the
call is an error that lists the candidates:

```text
main.pep:3:22: error: call to 'f' is ambiguous
    3 | main(): int { return f(1); }
      |                      ^
main.pep:1:1: note: candidate function
    1 | f(x: long): int { return 1; }
      | ^
main.pep:2:1: note: candidate function
    2 | f(x: short): int { return 2; }
      | ^
```

An integer literal fits every integer type that holds its value equally
well, so `f(1)` above is ambiguous; an `int` member would take it exactly.
Two widenings to types of the same width (a `ushort` to `long` and `ulong`)
are ambiguous too; convert the argument yourself (`f(n as long)`). When no
member is viable, each note says why:

```text
main.pep:5:12: error: no matching function for call to 'f'
    5 |     return f(s);
      |            ^
main.pep:1:1: note: candidate function not viable: no known conversion from 'String' to 'int' for 1st argument
    1 | f(x: int): int { return 1; }
      | ^
main.pep:2:1: note: candidate function not viable: requires 2 arguments, but 1 was provided
    2 | f(x: int, y: int): int { return 2; }
      | ^
```

A call with [named arguments](functions.md#named-arguments) considers only
the members that have a parameter of each name it uses and get every
required parameter, and binds the names before ranking the arguments as
above. So two overloads whose later parameters have different names can be
told apart by naming one (`pick(1, b = 2)` against `pick(a: int, b: int = 0)`
and `pick(a: String, c: int = 0)`). The members it considers must put each
named argument at the same position; when they do not, the call is an error:
`named arguments bind differently in the overloads of 'f'`.

The member picked decides the call's type, so `var x = half(9.0);` is a
`double` when `half(x: double): double` is picked. In the editor, hovering
the call shows the member it picked and how many others the set has, and
go-to-definition goes to that member.

## Generic members

A set can mix generic and non-generic members. A generic member is viable
when its type arguments can be inferred from the call, and ranks as an exact
match for the arguments that inferred them. When a generic and a non-generic
member tie, the non-generic one wins. Writing type arguments
(`describe<int>(7)`) considers only the generic members:

```pepper
{{#include ../../examples/overloading-generics.pep}}
```

A call inside a generic function or a generic struct's method whose argument
types depend on a type parameter is resolved again for each specialization,
so `label<String>` above calls `kind(s: String)`.

An [override](generics.md#overriding-a-generic-function-for-one-type) such
as `describe<Point>(p: Point)` belongs to the generic member with the same
number of type parameters and parameters; it is not a member itself.

## Methods and operators

A struct's methods of one name are an overload set, and a call picks among
them the same way, whether it is written `m.add(x)`, `this.add(x)`, or
`add(x)` inside a method. Static methods overload among themselves
(`Money.of(250)`), and operators are methods, so `+(Money)` and `+(int)` can
coexist:

```pepper
{{#include ../../examples/overloading-methods.pep}}
```

- **Unary and binary operators of one symbol** are one set: a unary
  `-()` and a binary `-(other: Money)` are told apart by their number of
  parameters (see [Unary operators](structs.md#unary-operators)).
- **A static method and an instance method may not share a name**, since a
  bare `of(x)` inside a method could mean either:

  ```text
  main.pep:3:12: error: static method 'get' cannot share its name with an instance method of 'S'
      3 |     static get(x: String): int { return 2; }
        |            ^~~
  main.pep:2:5: note: previous declaration is here
      2 |     get(x: int): int { return 1; }
        |     ^~~
  ```

- **In a generic struct**, each specialization resolves its own calls: in
  `Holder<int>`, `has(x: T)` takes an `int`. Two members that become the
  same after substitution (`has(x: T)` and `has(x: String)` in
  `Holder<String>`) are only an error when a call cannot tell them apart.
- **A method as a value** (`m.add`, `Money.of`) picks its member from the
  expected function type, like a free function below; without one the
  error is `cannot infer the type of 'f' from overloaded method 'Money.add'`.

## Extensions and traits

An [extension](traits-and-extensions.md#extensions)'s methods join the
struct's overload set of their name, and a trait may declare several methods
of one name. Each of a trait's overloads is implemented by the conforming
type's method with the same parameter types, and a call through a value of
the trait type picks among the trait's members the same way:

```pepper
{{#include ../../examples/overloading-traits.pep}}
```

- **An extension member with a body method's parameters** is
  `redefinition of 'area'`, with a note at the method it repeats.
- **A call sees only the extensions visible in its file** (see
  [Visibility](visibility.md#members-of-structs-and-extensions)): a private
  extension's overload is never a candidate in another file, so importing a
  file can add candidates to a call. If an added candidate makes a call
  ambiguous, the error's notes point at each candidate, the extension's
  included.
- **A trait's default method** is copied into a conforming type that lacks a
  method with its parameter types, even when the type has other methods of
  that name; the copy joins their set.
- **A missing overload** is named with its parameter types:
  `'Square' does not implement 'area(int)', required by trait 'Shape'`.

## Constructors

A struct may declare several constructors. A call `Span(...)` picks among
them exactly as a call picks among functions:

```pepper
{{#include ../../examples/overloading-constructors.pep}}
```

- **Two constructors with the same parameter types** are `constructor of
  'Span' cannot be redeclared`, with a note at the first.
- **No constructor fits** is `no matching constructor for initialization of
  'Span'`, and a tie is `call to constructor of 'Span' is ambiguous`; the
  notes point at each `candidate constructor`.
- **A generic struct's** constructors resolve in each specialization:
  `Pair<int>(1, 2)` picks among `Pair<int>`'s constructors.
- **At most one constructor may be `[Implicit]`**: an
  [implicit conversion](structs.md#implicit-conversions) needs one
  constructor to call.
- **`[Deprecated]` on one constructor** warns only at the calls that
  resolve to it.
- **A constructor as a value** (`var make: (int, int) => Span = Span;`)
  picks its member from the expected function type, like a function below.

## Overloaded functions as values

The name of an overload set, written without a call, is a value only where
the expected function type picks one member exactly: a typed variable, an
argument, a `return` from a function with a declared return type, or an
assignment. A closure whose parameters have no types, passed to an
overloaded function, picks the member whose function parameter has its
number of parameters:

```pepper
{{#include ../../examples/overloading-values.pep}}
```

Without an expected type, the compiler asks for one:

```text
main.pep:4:13: error: cannot infer the type of 'g' from overloaded function 'f'
    4 |     var g = f;
      |             ^
main.pep:1:1: note: candidate function
    1 | f(x: int): int { return 1; }
      | ^
main.pep:2:1: note: candidate function
    2 | f(x: long): int { return 2; }
      | ^
main.pep:4:13: note: declare the type, for example 'var g: (int) => int = f;'
    4 |     var g = f;
      |             ^
```

An expected type that matches no member is `address of overloaded function
'f' does not match required type '(bool) => int'`.
