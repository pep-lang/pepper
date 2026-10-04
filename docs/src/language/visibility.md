# Visibility

Visibility decides which declarations other files may use. Every top-level
declaration is **internal to its module** unless you mark it with `export`:
the files of one [module](modules.md#modules) see each other's declarations,
and nothing else does. A file outside any module is a module of its own, so
its declarations are **private to the file**. This lets a module, or a file,
keep its helpers to itself and offer a small, clear surface to the code that
imports it.

There is no smaller visibility than the module: Pepper has no `private`
keyword, and no way to hide a declaration from the other files of its module.

## Exporting declarations

Put `export` in front of a declaration to make it usable from other files that
import this one (see [Modules and imports](modules.md) for how to import).
You can export every kind of top-level declaration:

- functions, including `extern` declarations of C functions
- structs
- enums
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
lib.pep:29:1: note: declared here
   29 | make(x: int, y: int): Point {
      | ^~~~
```

The same applies to private structs, enums, type aliases, traits, and variables:
naming one from another file reports `'name' is private to file.pep`.

## Files of a module share their declarations

Inside a module, `export` is not needed for one file to use another's
declarations. Every file of the module sees the top-level declarations of
the module's other files, exported or not, with no import, as if they were
its own. `export` means visible **outside** the module, through its
`module.pep`.

Here the `inventory` module keeps its rules in `rules.pep`, which exports
nothing, and `stock.pep` uses them freely:

```pepper
{{#include ../../examples/visibility-modules/inventory/rules.pep}}
```

```pepper
{{#include ../../examples/visibility-modules/inventory/stock.pep}}
```

```pepper
{{#include ../../examples/visibility-modules/inventory/module.pep}}
```

```pepper
{{#include ../../examples/visibility-modules/main.pep}}
```

A file's own declarations come first, then what its imports bring in, then
the declarations of the module's other files, then the runtime's. A module's
files are the files of the program in its folder (and in subfolders that are
not modules themselves): a file joins the program when the module imports
it, so `module.pep` imports a file with nothing to export, like `rules.pep`,
just to include it. A `[Target(...)]` on that import (see
[Platform-specific imports](modules.md#platform-specific-imports)) includes
the file only on some platforms.

Outside the module, its internal declarations stay hidden. Using one is an
error that names the module:

```text
main.pep:3:13: error: 'Shelf' is internal to module 'inventory'; export it from the module to use it here
    3 |     var s = Shelf();
      |             ^~~~~
inventory/rules.pep:4:8: note: declared here
    4 | struct Shelf {
      |        ^~~~~
```

Because the files of a module share one set of names, two of them may not
both declare a struct, enum, type alias, trait, or variable of one name:
the second is a `redefinition of 'name'`, with a note at the first.
Functions are different: functions of one name in several files of a module
are one [overload set](overloading.md), as they are within a file.
Extensions are shared the same way: a file sees the methods its module's
other files add, exported or not.

## Members of structs and extensions

Fields and methods declared inside a struct's body are reached through the
struct, so they share the struct's visibility: if you can use the struct, you
can use all of its members.

To let other code read a value but not write it, make it a
[property](properties.md) with only a `get`: `var balance: long { get; }`
can be assigned only by the struct's own constructors and methods.

Methods added by an extension share the **extension's** visibility instead. In
the example, `norm()` is added by a private extension, so only `lib.pep` (or,
in a module, the module's files) can call it, even though `Point` itself is
exported:

```text
main.pep:4:14: error: 'norm' is declared in a private extension in lib.pep; declare the extension with 'export' to use it from another file
    4 |     return p.norm();
      |              ^~~~
lib.pep:46:5: note: declared here
   46 |     norm(): int {
      |     ^~~~
```

An exported extension's methods are usable where its file is **imported**,
not everywhere: a file sees the extensions it declares itself, the exported
extensions of the files it imports, the exported extensions of every file of
a module it imports (`import geo` reaches `geo/ext.pep`'s), and those of the
runtime, which every file sees. Here `measure.pep` adds `manhattan()` to
`Point`, and `main.pep` imports it to call it:

```pepper
{{#include ../../examples/visibility-extensions/measure.pep}}
```

```pepper
{{#include ../../examples/visibility-extensions/main.pep}}
```

Without `import "measure";`, the call is an error. If no file of the program
imports `measure.pep`, the method does not exist at all (`no member named
'manhattan' in 'Point'`); if another file does, the error says which import
is missing:

```text
main.pep:8:14: error: 'manhattan' is declared in an extension in measure.pep, which this file does not import; add an import for it
    8 |     assert(p.manhattan() == 7, "an extension from an imported file");
      |              ^~~~~~~~~
measure.pep:5:5: note: declared here
    5 |     manhattan(): int {
      |     ^~~~~~~~~
```

Two kinds of call are checked where they take effect rather than here:

- A method of a trait you can see (`s.area()` where `area` is a method of a
  trait `Shape` you declare, import, or get from the standard library): the
  call may go through a value of that trait, which works whatever file
  declares the conformance. A file can return a `Shape` whose struct and
  conformance stay private, and callers still call `area` on it.
- A call on a receiver whose type is not known in this file: `this.m()` in a
  trait's default method, or `x.m()` (or `x.f().m()`) where `x` is a
  parameter typed by a type parameter, the function's or its struct's
  (`measure<X>(x: X)`). Such a call resolves where the generic is used, with
  that file's imports.

When the extension is in a file of another module, the error names the
module to import instead (`import its module 'geo'`), since a file of another
module is reached only through its module.

Inside a struct's methods (and a trait's default methods), a bare call to a
name that an extension you cannot see adds as a method is an error too,
rather than a call to the top-level function of that name: the compiler
would otherwise bind it to the method.
Rename one of them, or import the extension's file if the method is what you
meant. That import may point back at a file that imports this one (a struct's
file importing the file that extends it); such cycles are allowed.

Extending a struct does not make a private struct visible to other files.

Visibility is checked before types are known, so members are matched by name:
a call `x.m()` is accepted if any struct body visible to the file (its own,
or exported) or any extension visible to it, as above, declares a member
named `m`.

## Where `export` goes

`export` goes directly before the declaration's keyword or name, **after** any
attributes:

```pepper
[Target(OS(Windows))]
export platform_name(): String { return "Windows"; }
```

Writing it before the attributes is a parse error:

```text
main.pep:2:8: error: unexpected '['
    2 | export [Target(OS(Windows))] f(): int { return 1; }
      |        ^
```

`export` controls visibility between Pepper files only. Making a function
callable from C with C linkage is a separate matter, handled by the `[Export]`
attribute described in [Calling Pepper from C](c-interop.md#calling-pepper-from-c).

## The runtime's exports

The runtime's public surface (`String`, `Array`, `HashMap`, `HashSet`,
`Result`, `Error`, `hash`, `assert`, `panic`, and the rest of the
[standard library reference](../reference/README.md)) is exported the same
way, and is visible in every file without an import. The runtime's own helpers
are private, so calling one, such as `_pep_check_sync_enabled`, reports
`'_pep_check_sync_enabled' is private to` followed by the path of the
runtime's `internals.pep`.

## Each module has its own namespace

A private declaration belongs to its file (or its module) alone, so two
files outside any module, or two modules, may each declare a private name
without clashing. Here `main.pep` and `lib.pep` each have their own
`Counter` and `make`, and each file's code reaches its own:

```pepper
{{#include ../../examples/visibility-namespaces/lib.pep}}
```

```pepper
{{#include ../../examples/visibility-namespaces/main.pep}}
```

This holds across modules too: two modules may each have a `util.pep` with a
private `helper`. Files are told apart by their path inside their module
(`io/file.pep`), not by their file name alone. Within one module, the files
share their names instead (see
[Files of a module share their declarations](#files-of-a-module-share-their-declarations)).

Exported names work the same way between modules: each module's exports
are its own, so two modules may export the same name, and importers tell
them apart by qualifier (`a.parse` and `b.parse`) or by an import list
(`import [parse as parse_b] from b`). Using a name that two whole-file
imports both provide is an error at the use (see
[Modules and imports](modules.md#how-imported-names-behave)). A private name
may repeat an exported one from another file; in the file that declares it,
the file's own declaration is the one that name refers to.

Two kinds of file keep their exported names program-wide, because every file
reaches them without an import or by its bare name: the runtime (and any
`--import` module), and the program's main file. So an export may not repeat
a runtime name: `exported 'String' is also declared in` followed by the
runtime's file.

A few kinds of declaration are not private in this sense:

- **`extern` declarations** name a C function, which is the same function in
  every file. Several files may declare the same extern.
- **Concrete overrides** of a generic function, such as `hash<int>` alongside
  `hash<T>`, take the generic function's name: they replace its version for
  those types wherever it is called. So each override may be declared in only
  one file (`override 'hash<int>' is also declared in b.pep`), and overriding
  one the runtime already provides, such as `hash<String>`, is also an error.
  An override must be for a generic function you can see: overriding another
  file's private generic function reports that it is private. An override
  may be for a struct, such as `hash<Point>` (see
  [Generics](generics.md)).
- **Declarations that a `[Target(...)]` attribute drops** for the platform
  being compiled (see [Platform selection](platform-selection.md)) are never
  compiled. This is why the first `lib.pep` above can declare `platform_name`
  twice.
