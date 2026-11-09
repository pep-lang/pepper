# Pepper libraries

A **Pepper library** is Pepper code built once, with `--lib pepper`, and
shipped without its source. A Pepper program imports it as it imports a
module, `import geo;`, and uses everything the library exports: functions,
structs, value structs, enums, traits and their default methods,
generics, and extensions.

To call Pepper from C, or from Swift, Kotlin or Java, build a C library
instead (`--lib static` or `--lib shared`, see
[Calling Pepper from C](c-interop.md#calling-pepper-from-c)).

## Building a library

The library [`lib/geo.pep`](../../examples/library/lib/geo.pep) exports a
trait with a default method, a struct that takes it, and a generic
function:

```pepper
{{#include ../../examples/library/lib/geo.pep}}
```

Build it with `--lib pepper`:

```bash
pepper build --lib pepper geo.pep -o lib/libgeo.a
```

This writes three files into `lib`:

| File | What it is |
|---|---|
| `libgeo.a` (`geo.lib` on Windows) | the archive: the objects of the library's own files, without the runtime, `main` or startup code, which the program supplies |
| `libgeo.pepi` (`geo.pepi` on Windows) | the **interface**: the library's checked declarations, which a program compiles against |
| `geo.h` | a C header for the library's `[Export]`ed functions, as `--lib static` writes |

The archive carries an identity stamp, which names the compiler, the
platform, the runtime and the interface it was built with (see
[What must match](#what-must-match)). Ship the archive and the interface
together, in one folder; the program needs no source.

The library's name is the archive's (`geo` for `libgeo.a`), and a program
imports it by that name. The library is checked whole on every build, with
or without the build cache.

## Importing it

The program [`main.pep`](../../examples/library/main.pep) imports `geo`,
gives a struct of its own the library's trait, and calls the library's
generic at that struct:

```pepper
{{#include ../../examples/library/main.pep}}
```

```bash
pepper build main.pep -L lib -o main
```

The import finds `lib/libgeo.pepi` and links `lib/libgeo.a` beside it, so
the program needs no `[Link]` or `-l`. The library's names are used as a
source module's are (`geo.Square`, or `import [Square] from geo;`), and
its exported extensions apply in the files that import it.

### Where the compiler looks

`import geo;` looks for a source module first, as any identifier import
does: a folder `geo/module.pep` in the `-I` folders, then the runtime's
(see [Dependencies and search paths](modules.md#dependencies-and-search-paths)).
Only when none answers does it look for a library's interface, `libgeo.pepi`
(`geo.pepi` on Windows), in these folders, in order:

1. each `-L` folder;
2. the folders the project's packages add for linking (a build script's
   `pep:link-path`, a `pkg-config` library's `-L`; see
   [build scripts](../tools/projects.md#build-scripts));
3. each folder of `PEPPER_LIBRARY_PATH`.

The first interface found wins. Its archive must be beside it; an interface
alone is an error at the import. A dotted import (`import geo.shapes;`)
never finds a library.

## Generics

The interface holds the bodies of the library's generic functions, of its
generic structs' methods and of its traits' default methods. The program
compiles each instantiation it uses, as C++ compiles a template from a
header: `geo.pair(Circle(2))` above is compiled into the program, at the
program's own type, and so is `describe()` for `Circle`. The program
never compiles the library's other functions: the archive defines them,
and they are not inlined into the program.

## Changing a library

A change inside the body of a function that is not generic usually leaves
the interface as it was: the program links the new archive without compiling
anything again. Any other change (a signature, a field, a generic's body, a
new declaration) writes a new interface, and the program's files that
import the library are checked again.

An archive and an interface from different builds of the library are
refused at the import:

```text
main.pep:1:8: error: the archive lib/libgeo.a was not built with the interface lib/libgeo.pepi; rebuild the library 'geo'
```

## What must match

The interface is the compiler's own record of the checked library, the
format its build cache keeps, so a program loads a library only when it
agrees with the library on:

- the **record version**, which a compiler changes when it writes or reads
  the interface differently;
- the **ABI number**, which a compiler changes when it changes how two
  builds' code calls into each other (object layouts, names, reference
  counting);
- the **runtime's interface**: what other code sees of the runtime the
  library was checked against, and of each runtime module both load. A
  runtime change inside a function body leaves it alone;
- the platform and the CPU, and each build option both define.

The compiler releases may differ: any compiler whose record version, ABI
number and runtime interface match the library's loads it. A library that
does not fit is refused, naming what differs; rebuild it with the
program's compiler. Different runtime checks or frame pointers only warn.
The archive's stamp, which holds all of this, is described in
[Identity stamps](linking.md#identity-stamps).

## One runtime

The program supplies the one runtime the program and its libraries use, so
one heap and one set of runtime thread-locals serve them all, and a program
can import several libraries.

- **Initialization.** Before `main`, the program sets the runtime's
  globals, then each library's (one that links another sets its own after
  that one's), then its own. So a program global may call into a library
  in its initializer.
- **Thread-locals.** When a thread ends, the library's thread-locals are
  released with the program's.
- **Runtime modules.** A runtime module the library imports and the
  program does not (`json`, say) is compiled into the program too.
- **C libraries.** The archive does not hold the C libraries the
  library's externs name with `[Link]`: the program links them, found in
  its own search folders (see [Linking](linking.md)).

## Deep chains

A chain of objects that runs through a library's structs and the
program's in turn, such as a library `Box` holding a trait value that is
the program's `Wrap`, which holds a `Box`, is released in a loop, as one
in a program built from source is (see [Memory](memory.md)): however
long it is, it does not run out of stack. The library was compiled
without knowing the program's structs, so the program compiles its own
release of each library struct its chains run through, and the linker
keeps the program's copy, which comes ahead of the library's archive.

## Not supported yet

- **A library that imports a library.** Only an executable or a shared
  library can import a Pepper library; a static library (`--lib pepper`
  or `--lib static`) can still call another one's `[Export]`ed functions
  through `extern`s:

  ```text
  main.pep:1:8: error: only an executable or a shared library can import the Pepper library 'geo' yet
  ```

- **Shared libraries.** `--lib pepper` writes a static library only:
  a shared library must hold a runtime of its own (`--lib shared`), and
  then only C types cross between it and the program.
- **A module both use from source.** A library carries the source modules
  it imports, other than the runtime's (an `-I` module, a package), in its
  interface and archive. A program that imports the library and the same
  module from source is refused:

  ```text
  error: ../deps/shapes/module.pep has the namespace 'shapes/module' of a file of a Pepper library this program imports; a program cannot import a library built from its own files
  ```

- **`[Link(path = ...)]` in a library.** The folder is relative to the
  library's source file, which the program does not have: in the program
  it names a folder inside the interface, which never exists. Pass the
  folder to the program's build with `-L` or `PEPPER_LIBRARY_PATH`
  instead.
- **Checking a program whole.** `--emit-llvm`, `--emit-model`,
  `--emit-steps` and `--emit-static` refuse a program that imports a
  library, since they need every file's source.
- **Checking in parallel.** A program that imports a library is checked in
  one process, one compilation unit at a time, whatever
  `PEPC_COMPILATION_UNIT_JOBS` says (see
  [The build cache](../tools/pep-build.md#the-build-cache)).
- **The language server.** pep-lsp does not look for interfaces, so it
  reports a library's import as `cannot find module`, and shows nothing
  from the library.
