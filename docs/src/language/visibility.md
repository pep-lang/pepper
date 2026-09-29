# Visibility

Visibility decides which declarations other files may use. Every top-level
declaration is **private to the file that declares it** unless you mark it with
`export`. This lets a file keep its helpers to itself and offer a small, clear
surface to the files that import it.

## Exporting declarations

Put `export` in front of a declaration to make it usable from other files that
import this one (see [Modules and imports](modules.md) for how to import).
You can export every kind of top-level declaration:

- functions, including `extern` declarations of C functions
- structs
- type aliases
- traits
- extensions
- module-scope variables

Here is a library file with a mix of exported and private declarations, and a
program that uses it:

```pepper
{{#include ../../examples/visibility-basics/lib.pep}}
```

```pepper
{{#include ../../examples/visibility-basics/main.pep}}
```

`main.pep` can call `at`, `origin`, and `norm_of`, use `Point` and `Points` as
types, and read `points_made`. It cannot use `make` or call `p.norm()`. Trying
to is an error that tells you how to fix it:

```pepper
import "lib";

main(): int {
    var q = make(1, 2);
    return 0;
}
```

```text
main.pep:4:13: error: 'make' is private to lib.pep; declare it with 'export' to use it from another file
    4 |     var q = make(1, 2);
      |             ^~~~
lib.pep:25:1: note: declared here
   25 | make(x: int, y: int): Point {
      | ^~~~
```

The same applies to private structs, type aliases, traits, and variables:
naming one from another file reports `'name' is private to file.pep`.

## Members of structs and extensions

Fields and methods declared inside a struct's body are reached through the
struct, so they share the struct's visibility: if you can use the struct, you
can use all of its members.

Methods added by an extension share the **extension's** visibility instead. In
the example, `norm()` is added by a private extension, so only `lib.pep` can
call it, even though `Point` itself is exported:

```text
main.pep:4:14: error: 'norm' is declared in a private extension in lib.pep; declare the extension with 'export' to use it from another file
    4 |     return p.norm();
      |              ^~~~
```

Likewise, a trait that a private extension implements is only available
through that extension in its own file. Extending a struct does not make a
private struct visible to other files.

Visibility is checked before types are known, so members are matched by name:
a call `x.m()` in another file is accepted if any struct body or extension
visible to that file (its own, or exported) declares a member named `m`.

## Where `export` goes

`export` goes directly before the declaration's keyword or name, **after** any
attributes:

```pepper
[Target(OS(Windows))] export platform_name(): String { return "Windows"; }
```

Writing it before the attributes is a parse error:

```text
main.pep:2:8: error: unexpected '['
    2 | export [Target(OS(Windows))] f(): int { return 1; }
      |        ^
```

`export` controls visibility between Pepper files only. Making a function
callable from C with C linkage is a separate matter, handled by the `[Export]`
attribute described in [Calling C](c-interop.md).

## The runtime's exports

The runtime's public surface (`String`, `Array`, `HashMap`, `HashSet`,
`Atomic`, `Result`, `Error`, `hash`, `assert`, `panic`, and the rest of the
[standard library reference](../reference/README.md)) is exported the same
way, and is visible in every file without an import. The runtime's own helpers
are private, so calling one, such as the integer formatter `dec`, reports
`'dec' is private to` followed by the path of the runtime's `internals.pep`.

## One namespace for the whole program

Visibility controls who may *use* a name, but all the files of a program still
share one namespace for their declarations. Two files may not both declare the
same top-level name, even if both declarations are private:

```pepper
import "lib";

make(x: int): int { return x; }   # lib.pep also has a private make()
main(): int { return make(1); }
```

```text
main.pep:3:1: error: private 'make' is also declared in lib.pep; top-level names must be unique across files
    3 | make(x: int): int { return x; }
      | ^~~~
lib.pep:25:1: note: also declared here
   25 | make(x: int, y: int): Point {
      | ^~~~
```

An exported name must be unique too, even across modules that are reached
through different qualifiers: `exported 'f' is also declared in b/module.pep`.
Give private helpers names that are unlikely to collide, for example with a
prefix for the file or module they belong to. The runtime's io module, for
instance, prefixes its private helpers with `_io_`.

A few kinds of declaration are exempt from this rule:

- **`extern` declarations**, since every declaration of an extern names the
  same C function.
- **Concrete overrides** of an exported generic function, such as `hash<int>`
  alongside `hash<T>`. Overriding one the runtime already provides, such as
  `hash<String>`, is still a duplicate. The exemption covers only overrides
  for primitive types and `String`: an override for a struct, such as
  `hash<Point>`, collides with `hash<T>` when the two are in different files,
  so declare it in the same file as the generic function. Type parameters
  are compared by position, not by name, so a private `pick<U>` also
  collides with `pick<T>`.
- **Declarations that a `[Target(...)]` attribute drops** for the platform
  being compiled (see [Platform selection](platform-selection.md)). This is
  why `lib.pep` above can declare `platform_name` twice.
