# Modules and imports

As a program grows, you split it into files, and group related files into
modules. An **import** makes another file's or module's exported declarations
available in the importing file. What a file exports is covered in
[Visibility](visibility.md).

## Importing a file

The simplest import names another file, as a string, relative to the importing
file. The `.pep` extension is optional:

```pepper
{{#include ../../examples/modules-files/main.pep}}
```

`util.pep` sits next to `main.pep`, and `text.pep` is in a `helpers` folder:

```pepper
{{#include ../../examples/modules-files/util.pep}}
```

```pepper
{{#include ../../examples/modules-files/helpers/text.pep}}
```

An import comes in one of these forms:

| Form | What it makes available |
|---|---|
| `import "util";` | Every export of `util.pep`, unqualified: `twice(BASE)`. |
| `import "util" as u;` | Every export, qualified by the name you choose: `u.twice(1)`. |
| `import [thrice as triple, twice] from "util";` | Only the listed exports, unqualified, each under its own name or the one after `as`. |
| `import geometry;` | A module's exports, qualified by the module's name: `geometry.Point`. |
| `import geometry as g;` | A module's exports, qualified by `g`. |
| `import [area, Point as Pt] from geometry;` | The listed exports of a module, unqualified. |

An import ends with a semicolon.

An import binds names only in the file that contains it. The exports of a file
that this file did not import are not visible to it, even when another file of
the program imports them. Here `geometry/module.pep` imports `shapes.pep`, but
`main.pep` imports only the module:

```pepper
import geometry;
main(): int { return area(1, 2); }
```

```text
main.pep:2:22: error: 'area' is exported by deps/geometry/shapes.pep, which this file does not import; add an import for it
    2 | main(): int { return area(1, 2); }
      |                      ^~~~
deps/geometry/shapes.pep:3:8: note: declared here
    3 | export area(w: int, h: int): int {
      |        ^~~~
```

## Imports come first

Every import, and every `export ... from`, comes before all of a file's declarations
and `export name` re-exports:

```pepper
main(): int { return 0; }
import geometry;
```

```text
main.pep:2:1: error: imports must come before all declarations
    2 | import geometry;
      | ^~~~~~
```

## Modules

A **module** is a folder that contains a `module.pep` file. The module is named
after its folder, and its exports are exactly what its `module.pep` exports.
The other files in the folder are the module's own files: `module.pep` imports
them and chooses what to pass on to the module's users.

This example has a `geometry` module next to `main.pep`:

```text
modules-folders/
    main.pep
    geometry/
        module.pep      # the module's interface
        shapes.pep      # a file of the module
        solids/
            module.pep  # a module nested inside geometry
```

```pepper
{{#include ../../examples/modules-folders/geometry/shapes.pep}}
```

```pepper
{{#include ../../examples/modules-folders/geometry/solids/module.pep}}
```

```pepper
{{#include ../../examples/modules-folders/geometry/module.pep}}
```

```pepper
{{#include ../../examples/modules-folders/main.pep}}
```

`main.pep` imports the folder with a string, `import "geometry"`, because the
module lives next to it. A string import names either a file (`geometry.pep`)
or a module folder (`geometry/`) relative to the importing file. A module
imports a module nested in its own folder the same way: `geometry/module.pep`
imports `"solids"`.

### Re-exports

`export name as new_name;` exports `name` to importers under `new_name`, and
`export name;` exports it under its own name. The name may be declared in the
file (even privately) or imported from another file or module, qualified or
not. This is how a `module.pep` publishes what its other files define.

The semicolon is required. Without it, `export Box` followed by a declaration
would read as an exported C-style declaration whose type is `Box`.

The exports of the module's other files are not the module's exports. In the
example, users of `geometry` can call `g.rect_area`, but not `g.area`:

```text
main.pep:2:22: error: 'area' is not exported by 'geometry' (deps/geometry/module.pep)
    2 | main(): int { return geometry.area(1, 2); }
      |                      ^~~~~~~~~~~~~
```

### Re-exporting a whole file or module

A `module.pep` that only passes on its files' exports would repeat every name.
`export ... from` passes them on in one line, in the same shapes as the
`import ... from` forms:

| Form | What importers get |
|---|---|
| `export * from "rect";` | Every export of `rect.pep`, each under its own name. |
| `export * from geometry;` | Every export of the module `geometry`. |
| `export [perimeter as outline, Side] from "measure";` | Only the listed exports, each under its own name or the one after `as`. |

```pepper
{{#include ../../examples/modules-reexports/shapes/module.pep}}
```

```pepper
{{#include ../../examples/modules-reexports/main.pep}}
```

- **It re-exports; it doesn't import.** `export * from "rect";` makes no name
  visible in the file that contains it. A file that also uses those names
  imports them as usual, with `import "rect";`.
- **Only exports travel.** Private declarations stay behind, and extensions
  stay visible only as they always are.
- **Collisions are errors.** If two re-exports, or a re-export and one of the
  file's own exports, publish one name for different declarations, the
  compiler reports it at the `export ... from` that adds the second one. List the names you want instead, or
  rename one with `as`:

  ```text
  shapes/module.pep:2:1: error: 'area' is exported twice by module 'shapes'
      2 | export * from "measure";
        | ^~~~~~~~~~~~~~~~~~~~~~~
  shapes/module.pep:1:1: note: also exported here
      1 | export * from "rect";
        | ^~~~~~~~~~~~~~~~~~~~
  ```

- Like imports, `export ... from` lines come before every declaration and
  take attributes such as `[Target(...)]`. A deprecated declaration stays
  deprecated through every re-export.

### A module's files stay inside it

A string import from a file of a module must name a file of the same module,
or a module folder. Reaching into another module's files, or out of your own
module, is an error:

```text
main.pep:1:8: error: "geometry/shapes.pep" belongs to another module; import that module's folder instead
    1 | import "geometry/shapes";
      |        ^~~~~~~~~~~~~~~~~
```

```text
geometry/bad.pep:1:8: error: "../main.pep" is outside this file's module; a module imports only its own files
    1 | import "../main";
      |        ^~~~~~~~~
```

A file outside any module, such as your program's `main.pep`, may import files
in its own folder or below, except files inside a module folder there.

Files of one module may import each other, even in a cycle.

## Dependencies and search paths

A module that is not part of your program's own folders, such as a library you
depend on, is imported by **name** rather than by string:

```pepper
import geometry;

main(): int {
    var p: geometry.Point = geometry.make(3, 4);
    return p.x - 3;
}
```

An identifier import looks for a folder `geometry/module.pep` on the **search
paths**: first each directory you pass with `-I`, in order, then the runtime
directory. If `geometry` lives in a `deps` folder, compile with:

```sh
pepper main.pep -I deps -o main
```

An identifier import never looks next to the importing file. A module that is
not found is reported with the places the compiler looked:

```text
main.pep:1:8: error: cannot find module 'nowhere': no nowhere/module.pep in deps, /home/you/pepper/runtime
    1 | import nowhere;
      |        ^~~~~~~
```

The standard library's [io module](../reference/io-module.md) is found this
way, in the runtime directory: `import io;` then `io.File`, or
`import [File, Path] from io;`.

### The runtime prelude and `--import`

The runtime itself is not a module: its files are loaded into every program,
and their exports, such as `String`, `Array`, and `Result`, are visible
everywhere without an import.

`--import NAME` adds a module, or a file `NAME.pep`, found on the search paths
to that prelude, so every file sees its exports without importing it. A name
that resolves to neither is an error:

```text
error: --import no_such_module: cannot find module 'no_such_module' (no no_such_module/module.pep) or file no_such_module.pep in /home/you/pepper/runtime
```

A prelude module may redefine an export of the runtime, such as `panic`: it is
loaded ahead of the runtime and its definition wins. It must declare the name
itself (`export panic(...)`); re-exporting another function under a runtime
export's name is an error, since the runtime's own files would keep calling
their version. When the runtime's function is [overloaded](overloading.md),
the prelude module replaces only the overloads it declares, matched by
parameter types: an `export assert(condition: bool, message: String)`
replaces the `String` form, and a string literal message still calls the
runtime's `__ptr<char>` form.

## How imported names behave

- **Qualified names work wherever a name does**: in expressions
  (`g.rect_area(1, 2)`, or a module variable such as `u.BASE`), in types (`var p: g.Point`,
  `g.Box<int>[]`, a return type `g.Point`), and in generic constructions
  (`g.Box<int>()`). A generic construction is recognized only for a qualifier
  imported earlier in the file; elsewhere `a.b < c, d > (e)` is two
  comparisons.
- **Local names shadow imports.** A local variable, parameter, generic
  parameter, or struct member hides a qualifier or an imported name of the
  same name.
- **A file may not import a name it also declares** at top level:
  `'make' is imported but also declared in this file`.
- **An import list wins.** A name listed in `import [...]` takes priority over
  the same name from a whole-file import. When two whole-file imports provide
  the same name differently, using that name is an error because it is
  ambiguous.
- **An imported name keeps its original identity.** An imported name is
  compiled as the name of the declaration it denotes, so a local with that
  declaration's own name may not be in scope where you use it. If
  `g.rect_area` is `shapes.pep`'s `area`, calling `g.rect_area(1, 2)` inside a
  function with a parameter named `area` is an error that asks you to rename
  one of them.

Each file has its own namespace for its private declarations, so files and
modules may reuse private names freely. Exported names share one namespace,
so two modules may not export the same name, even though users reach them
through different qualifiers. See [Each file has its own namespace](visibility.md#each-file-has-its-own-namespace).

## Platform-specific imports

An import or a re-export may carry attributes like any declaration. With a
`[Target(...)]` attribute it applies only on matching platforms and is ignored
elsewhere (see [Platform selection](platform-selection.md)):

```pepper
[Target(OS(Linux))] import linux;
[Target(OS(Linux))] export linux_open as open;
[Target(OS(Windows))] export * from "windows";
```
