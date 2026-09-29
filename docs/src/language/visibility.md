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
- module-scope variables, which are always `const` and thread-safe (see
  [Module-scope variables](threads.md#module-scope-variables))

Here is a library file with a mix of exported and private declarations, and a
program that uses it:

```pepper
{{#include ../../examples/visibility-basics/lib.pep}}
```

```pepper
{{#include ../../examples/visibility-basics/main.pep}}
```

`main.pep` can call `at`, `origin`, and `norm_of`, use `Point` and `Points` as
types, and read the counter in `points_made`, an exported `const` `Atomic<int>`. It cannot use `make` or call `p.norm()`. Trying
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
lib.pep:27:1: note: declared here
   27 | make(x: int, y: int): Point {
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
lib.pep:42:5: note: declared here
   42 |     norm(): int {
      |     ^~~~
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

## Each file has its own namespace

A private declaration belongs to its file alone, so two files may each
declare a private name without clashing. Here `main.pep` and `lib.pep` each
have their own `Counter` and `make`, and each file's code reaches its own:

```pepper
{{#include ../../examples/visibility-namespaces/lib.pep}}
```

```pepper
{{#include ../../examples/visibility-namespaces/main.pep}}
```

This holds across modules too: two modules may each have a `util.pep` with a
private `helper`. Files are told apart by their path inside their module
(`io/file.pep`), not by their file name alone.

Exported names are different: they share one namespace across the whole
program, because importers reach them by name. Two files may not export the
same name, even from modules reached through different qualifiers:
`exported 'f' is also declared in b/module.pep`. A private name may repeat an
exported one from another file; in the file that declares it, the file's own
declaration is the one that name refers to.

A few kinds of declaration are not private in this sense:

- **`extern` declarations** name a C function, which is the same function in
  every file. Several files may declare the same extern.
- **Concrete overrides** of a generic function, such as `hash<int>` alongside
  `hash<T>`, take the generic function's name: they replace its version for
  those types wherever it is called. So each override may be declared in only
  one file (`override 'hash<int>' is also declared in b.pep`), and overriding
  one the runtime already provides, such as `hash<String>`, is also an error.
  An override must be for a generic function you can see: overriding another
  file's private generic function reports that it is private. The exemption
  covers only overrides for primitive types and `String`: `hash<Point>` is a
  second generic function whose type parameter is named `Point`, private to
  its file like any other declaration.
- **Declarations that a `[Target(...)]` attribute drops** for the platform
  being compiled (see [Platform selection](platform-selection.md)) are never
  compiled. This is why the first `lib.pep` above can declare `platform_name`
  twice.
