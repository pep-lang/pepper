# Traits and extensions

Pepper has no inheritance. Instead, you add behavior to a type with an
*extension*, and describe a set of behavior that several types share with a
*trait*. Extensions can be written anywhere, so you can add methods to a
library type, such as `String`, from your own code.

Extensions work today. Traits can be declared and attached to types, but the
compiler does not do anything with them yet beyond that; see
[What traits do not do yet](#what-traits-do-not-do-yet).

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

You can also write `extend Box<int>` to target one specialization, but this is
not reliable yet: the methods are currently added to every specialization of
`Box` that the program uses, and they fail to compile for the other ones. Use
it only when the program uses a single specialization of the struct.

Two more limitations of extensions today:

- A `for` loop over `this` inside an extension of `Array<int>` does not
  compile. Loop with an index instead.
- An extension cannot add fields; declare every field in the struct itself.

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

### What traits do not do yet

Traits are currently documentation that the compiler records but does not
use. In particular:

- **A trait cannot be used as a type.** A parameter, variable, or field of
  type `Shape` does not compile, so you cannot yet write one function that
  accepts any `Shape`:

  ```pepper
  measure(shape: Shape): int {
      return shape.area();
  }
  ```

  ```text
  main.pep:5:1: error: unknown param type Shape
      5 | measure(shape: Shape): int {
        | ^~~~~~~
  ```

  To write code that works with several types today, use a
  [generic function](generics.md#generic-functions): `total_area<T>` accepts
  any `T` that has an `area()` method.
- **Conformance is not checked.** `extend Square with Shape {}` compiles even
  though it leaves out the trait's methods. The error, if any, appears only
  when something calls a missing method.
- **Default method bodies are not inherited.** The parser accepts a trait
  method with a body, but the body is not added to types that have the
  trait. Write every method in the extension.
- **Generic parameters cannot require a trait.** There is no syntax yet for
  saying that `T` must have `Shape`.

The standard library declares the traits `Iterator<T>` and `Iterable<T>` in
this spirit: a `for` loop looks for the methods themselves, not for the
trait. See [Iteration](iteration.md).
