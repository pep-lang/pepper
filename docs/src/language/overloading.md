# Overloading

Several free functions in one file can share a name when their parameter
lists differ. Each call picks the one whose parameters fit its arguments
best:

```pepper
{{#include ../../examples/overloading-basics.pep}}
```

The functions of one name in one file are an **overload set**, and each is a
member of it. [Methods](#methods-and-operators) of one name in a struct are a
set too, and so are its static methods, its operators, its
[constructors](#constructors), and the methods its
[extensions](#extensions-and-traits) add.

## Declaring overloads

- **The parameter lists must differ** in the number or the types of the
  parameters. Parameter names and default values do not count, and neither
  does the return type:

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
- **One file, one set.** A file's own functions hide an imported function of
  the same name, as before; overloads do not merge across files.
- **One visibility per set.** The members are all exported or all private,
  so a set is imported or hidden as a whole:

  ```text
  util.pep:2:1: error: overloads of 'scale' must all be exported or all be private
      2 | scale(x: double): double { return x * 3.0; }
        | ^~~~~
  util.pep:1:8: note: other overload declared here
      1 | export scale(x: int): int { return x * 2; }
        |        ^~~~~
  ```

  Importing the name (`import [scale] from util`, or the whole file) brings
  every member, and `import [scale as grow]` renames the whole set.
- **`extern` functions do not overload**: a C function has one symbol. Wrap
  it in a Pepper function to give it company.

## How a call picks a member

A member is **viable** when the call has between its required and total
number of parameters and each argument converts to its parameter. For each
argument, the conversion has a rank, best first:

| Rank | What converts |
|------|---------------|
| exact | the same type; a string literal to `__ptr<char>` |
| promotion | an integer widening that loses nothing (`int` to `long`, `u8` to `int`; the narrower target ranks better, so a `short` picks `int` over `long`), `float` to `double`, an integer literal to any integer type it fits, a struct to a [trait it declares](traits-and-extensions.md#traits-as-types), `__null` to a reference, a string literal to `String` |
| conversion | any other numeric conversion (`bool` included), and pointer conversions |
| implicit constructor | a value to a struct whose [`[Implicit]` constructor](structs.md#implicit-conversions) takes it |

One viable member is **better** than another when none of its arguments
ranks worse and at least one ranks better, as in C++. The call picks the
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

## What is not supported yet

- **Unary operators** cannot be declared at all yet.
- **`extern` functions** do not overload.
- **Overloads across files** do not merge: a file's own functions of a name
  hide an imported set of that name.
