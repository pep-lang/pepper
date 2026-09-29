# Traits and extensions

Pepper has no inheritance. Instead, you add behavior to a type with an
*extension*, and describe a set of behavior that several types share with a
*trait*. Extensions can be written anywhere, so you can add methods to a
library type, such as `String`, from your own code.

Extensions work today. Traits can be declared and attached to types, and the
compiler checks that a type provides the trait's methods, but a trait cannot
be used as a type yet; see [What traits do not do yet](#what-traits-do-not-do-yet).

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

### Extending generic structs

`extend Box<T>`, using the struct's own type parameter name, adds the methods
to every specialization: `Box<int>`, `Box<String>`, and so on. The example
above does this.

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
- The methods in the extension are ordinary methods of the struct, so you
  call them on a `Square` as usual.

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

> **Known problem:** a default body that uses a string literal does not work
> yet: it fails to compile (`not a struct`) or the program crashes. Write such a
> method in each extension instead.

### What traits do not do yet

Beyond checking conformance and supplying default bodies, the compiler does not
use traits yet. In particular:

- **A trait cannot be used as a type.** A parameter, variable, or field of
  type `Shape` does not compile, so you cannot yet write one function that
  accepts any `Shape`:

  ```pepper
  measure(shape: Shape): int {
      return shape.area();
  }
  ```

  ```text
  main.pep:5:16: error: unknown type name 'Shape'
      5 | measure(shape: Shape): int {
        |                ^~~~~
  ```

  To write code that works with several types today, use a
  [generic function](generics.md#generic-functions): `total_area<T>` accepts
  any `T` that has an `area()` method.
- **Generic parameters cannot require a trait.** There is no syntax yet for
  saying that `T` must have `Shape`.

The standard library declares the traits `Iterator<T>` and `Iterable<T>` in
this spirit: a `for` loop looks for the methods themselves, not for the
trait. See [Iteration](iteration.md).
