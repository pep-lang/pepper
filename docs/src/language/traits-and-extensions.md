# Traits and extensions

Pepper has no inheritance. Instead, you add behavior to a type with an
*extension*, and describe a set of behavior that several types share with a
*trait*. Extensions can be written anywhere, so you can add methods to a
library type, such as `String`, from your own code.

A trait is also a type: a value of type `Shape` holds any struct that has the
`Shape` trait, and calls its methods (see [Traits as types](#traits-as-types)).

## Extensions

An `extend` block adds methods to a struct declared elsewhere, whether in the
same file, another file, or the standard library:

```pepper
{{#include ../../examples/traits-extensions.pep}}
```

- An extension can hold anything a struct body can hold except fields, a
  constructor, and a destructor: methods, static methods, operators, and
  indexers.
- Methods in an extension behave exactly like methods declared in the struct.
  They can use `this` and name the struct's fields directly, and they are
  called the same way.
- A type can have any number of extensions.
- An extension method may share its name with the struct's methods if its
  parameter types differ: it joins their
  [overload set](overloading.md#extensions-and-traits).
- An extension in another file is usable only where that file (or its
  module) is imported, and only if it is exported; the standard library's
  extensions are usable everywhere. See
  [Visibility](visibility.md#members-of-structs-and-extensions).

### Extending generic structs

`extend Box<T>`, using the struct's own type parameter name, adds the methods
to every specialization: `Box<int>`, `Box<String>`, and so on. The example
above does this.

When `Box` constrains its parameter (`struct Box<T: Shape>`), the extension
keeps the constraint without restating it; `extend Box<T: Shape>` may
restate it as documentation (see [constraints](generics.md#constraints)).
A constraint the struct does not have limits the extension to the
specializations that meet it: `extend Box<T: Named> { ... }` adds its
methods to `Box<Square>` but not to `Box<String>`, and
`extend Box<T: Shape> with Shape` makes a `Box` of shapes a shape (see
[constrained extensions](generics.md#constrained-extensions)).

`extend Box<int>` targets one specialization: its methods exist only on
`Box<int>`, and calling one on a `Box<String>` is an error
(`no member named 'doubled' in 'Box<String>'`).

A library type's specialization can be extended the same way. The example's
`extend Array<int>` adds `total()`, which loops over `this` with `for`.

An extension cannot add fields; declare every field in the struct itself.

## Traits

A trait names a set of methods. Declare one with `trait` and method
signatures ending in `;`. Then declare that a type has the trait with
`extend Type with Trait`, and provide the methods in that extension:

```pepper
{{#include ../../examples/traits-declare.pep}}
```

- A trait can have type parameters, like `From<T>`.
- A trait can declare static methods. In a trait, `this` used as a type
  stands for the type that has the trait.
- `extend Square with Shape, Printable { ... }` attaches several traits at
  once.
- A trait can declare several methods of one name with different parameter
  types; the type implements each with the method whose parameter types
  match (see [Overloading](overloading.md#extensions-and-traits)).
- The methods in the extension are ordinary methods of the struct, so you
  call them on a `Square` as usual.
- A generic parameter can require a trait, `total_area<T: Shape>`, so that
  only types declared to have it are accepted (see
  [constraints](generics.md#constraints)).
- The runtime declares traits too. `ToString` (`to_string(): String`) makes
  a type usable in an [interpolated string](interpolation.md).

The compiler checks that the type has every method the trait declares, either
in the extension or in the struct itself. A missing method is an error at the
extension, with a note at the trait's method:

```text
main.pep:9:8: error: 'Square' does not implement 'area', required by trait 'Shape'
    9 | extend Square with Shape {
      |        ^~~~~~
main.pep:2:5: note: 'area' declared here
    2 |     area(): int;
      |     ^~~~
```

### Default method bodies

A trait method can have a body. A type that has the trait and does not define
that method gets the trait's body as its own method; a type that defines the
method keeps its own. Inside a default body, the trait's type parameters and
`this` stand for the types named in the `with` clause:

```pepper
trait Shape {
    area(): int;
    sides(): int { return 4; }
}

extend Square with Shape {
    area(): int { return side * side; }
}
```

Here `Square(3).sides()` returns 4.

A default method can have type parameters of its own (see
[Generic methods](generics.md#generic-methods)). The runtime's `Iterator<T>`
uses this for its `map<U>` and `filter` [adapters](iteration.md#adapters),
which every type that declares `Iterator<T>` gets.

A default body sees only what its trait declares: a bare call to one of the
trait's methods calls it on `this`, and any other bare name means what it
means where the trait is declared (a top-level function or variable), even
when a conforming type happens to have a method or field of that name. Call
through `this` explicitly only for the trait's own methods.

### Traits as types

A trait's name is also a type. A variable, parameter, field, return value, or
collection element of type `Shape` holds any struct that declares `Shape`, and
calling a method on it runs that struct's own method:

```pepper
{{#include ../../examples/traits-values.pep}}
```

- **Conversion is implicit.** A `Square` becomes a `Shape` wherever a `Shape`
  is expected: an initializer, an assignment, an argument, a return value.
- **Conformance is declared.** Only a type that declares the trait with
  `extend Type with Trait` converts. Having the right methods is not enough:

  ```text
  main.pep:11:20: error: 'Circle' does not conform to trait 'Shape'
     11 |     var s: Shape = Circle();
        |                    ^~~~~~
  main.pep:6:8: note: declare it with 'extend Circle with Shape'
      6 | struct Circle {
        |        ^~~~~~
  ```

- **A trait value is a shared reference** to the struct, like any other
  struct value (see [Memory](memory.md)). When the last reference goes away,
  whether it was a `Shape` or a `Square`, the struct's own destructor runs.
- **Only instance methods are callable through the trait.** Static methods,
  generic methods, and methods whose signature uses `this` as a type, need the
  concrete type;
  calling one through a trait value is an error.
- **Methods must match the trait's signature.** An implementation with
  different parameter or return types is an error. The one exception is a
  trait method that returns a trait type: the implementation may return a
  struct that declares that trait, as `iterate()` does in
  [Iteration](iteration.md#writing-your-own-iterator).
- `==` and `!=` on trait values compare identity: they are equal when they
  refer to the same object.

What traits do not do yet:

- **A trait value cannot convert back** to its struct, or to another trait.
- **`Atomic<Shape>` is not supported.** A trait value is two pointers wide
  and cannot be swapped atomically.
- **`Weak<Shape>` is not supported.** Take the weak reference to the struct
  type instead.
