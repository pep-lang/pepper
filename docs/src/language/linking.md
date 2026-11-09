# Linking

The Pepper compiler turns your program into a native executable in two steps:
it compiles your files and the runtime into object files (one per source
file; see [Output files](#output-files)), and then links them with the
system libraries it needs. When you
[call C functions](c-interop.md), linking is where their definitions come
from, so this chapter explains what is linked by default and how to add more.

## What the compiler links

The compiler uses `clang` as its link driver, rather than calling the
platform's linker directly, because clang already knows each platform's
startup files, C library and SDK locations. It uses the `clang` from the LLVM
installation the compiler was built with when there is one, and otherwise
the first `clang` on your `PATH`.

Every program is linked with:

- **Linux:** the C library, which clang adds, and the math library (`m`),
  which the Pepper compiler adds (a floating-point `**` calls its `pow`),
  and, when the compiler runs on a glibc older than 2.34, `pthread` and
  `dl`, where that glibc keeps threads and `dlsym` (a newer one has them in
  the C library).
- **macOS:** `libSystem`, which contains the C library, plus the SDK and
  platform-version flags. clang adds all of these, using the Xcode Command
  Line Tools.
- **Windows:** the Microsoft C runtime (the UCRT, `vcruntime` and the CRT
  startup library), which clang adds, plus `kernel32`, `user32` and `shell32`,
  which the Pepper compiler adds. A program that uses `async` also links
  `synchronization`, which the runtime names with `[Link]` for its locks
  (`WaitOnAddress`). clang finds the Visual Studio and Windows SDK
  libraries itself, so you do not need a Developer Command Prompt.

Any library file named `lib<name>.a` in the runtime directory is linked too.

Anything else must be linked explicitly. On Linux, that includes `pthread`
on older systems. Android keeps `pthread` and `rt` in its C library and has
no library of either name, so the compiler drops `-l pthread` and `-l rt`
when linking for Android: one `[Link("pthread")]` serves both.

## Linking a library from the source: `[Link]`

Attach `[Link("name")]` (or `[Link(lib = "name")]`) to an `extern`
declaration to link the library that defines it. The compiler passes `-lname` to the linker, just like `-l` on the
command line. Name the library the way the linker does: `m` for `libm`,
`gdi32` for `gdi32.lib`.

```pepper
{{#include ../../examples/linking-attribute.pep}}
```

- The library is linked only if the extern survives
  [platform selection](platform-selection.md). Combining `[Link]` with
  `[Target]`, as above, links a library only on the platforms that need it.
- Each library is linked once, however many externs name it.
- The library is linked even when nothing calls the extern.
- The same attribute can also bind the extern to a differently named C
  symbol: `[Link(lib = "m", name = "cbrt")]` (see
  [Binding to a different symbol name](c-interop.md#binding-to-a-different-symbol-name)).

Putting `[Link]` in the source keeps the knowledge of which library a function
comes from next to its declaration, so nobody building your program has to
remember a command-line flag.

## Linking C code a package builds: `[native]` and build scripts

A package can ship a C library's source instead of asking its users to
install the library. When the C needs only compiling and linking, a
[`[native]`](../tools/projects.md#native) table in its `pep.toml` says
which files to compile and what to link, with no script:

```toml
[native]
sources = ["c/*.c"]
include = ["c/include"]
link    = ["m"]
```

The build compiles each source with clang for the build's target and links
the objects into the program. Since it runs no package code,
`--no-build-scripts` allows it, as long as its `flags` are ones that cannot
make clang load code (see [`[native]`](../tools/projects.md#native)).

For anything more, such as generating a header or running `configure`, a
[build script](../tools/projects.md#build-scripts) compiles the C code with
clang for the build's target, and prints the objects and libraries to link
(`pep:object=...`, `pep:link=...`).

## Linking a library from the command line: `-l`

The `-l` option links a library for one build:

```sh
pepper build main.pep -l m -o main
```

Repeat it for more libraries (`-l m -l pthread`).

A library the linker does not find on its own (one outside the system's
library directories, such as a Homebrew install on macOS) needs its folder
on the search path. `-L dir` adds one, like `-L` for clang:

```sh
pepper build main.pep -L /opt/homebrew/opt/llvm@20/lib -o main
```

Repeat it for more folders. The folders are searched for `-l` libraries and
`[Link]` libraries alike, in the order given, before the default ones. On
Windows, clang passes each one to the linker as `/LIBPATH:`.

## Library search directories in the source and the environment

A library that ships with your program, such as a vendored build in a
`vendor/` folder, can name its folder in the `[Link]` attribute with `path`:

```pepper
[Link(lib = "probe", path = "vendor/lib")]
extern int probe_version();
```

A relative `path` is relative to the folder of the file that declares the
extern, not to where you run the compiler, so the program builds the same
from anywhere. Like the library, the folder is searched only when the extern
survives [platform selection](platform-selection.md), so a `[Target]` can
give each platform its own folder.

The `PEPPER_LIBRARY_PATH` environment variable adds folders for every build,
separated like `PATH` (`:`, or `;` on Windows):

```sh
PEPPER_LIBRARY_PATH=/opt/homebrew/lib pepper build main.pep -o main
```

The linker searches `-L` folders first, then `[Link]` paths, then
`PEPPER_LIBRARY_PATH`, then the runtime's folder and the system's.

## When linking fails

If a function you declared with `extern` is not defined by any linked library,
compilation succeeds and the link fails. The compiler prints what the linker
said, which names the missing symbol:

```text
error: Link failed: clang exited with exit status: 1
/usr/bin/ld: .pep/build/main.units/main.o: in function `main':
main:(.text+0x25ba): undefined reference to `no_such_function'
clang: error: linker command failed with exit code 1 (use -v to see invocation)
```

The object the linker names is the one for the file that made the call, in
`.pep/build/<name>.units/`. Symbols of your own functions appear as the
compiler spells them for the linker: `main` and a method such as
`Point.length` keep their names, and any other name is written `_P` followed
by the name with `_` doubled and other characters as `_` and two hex digits,
so a function `parse` appears as `_Pparse` and `Array<int>.count` as
`_PArray_3cint_3e.count`. That way a Pepper function never collides with a C
library function of the same name, such as `exit`. `extern` functions keep
their C names.

To fix it, check the spelling of the extern against the C function (or use
[`[Link(name = "symbol")]`](c-interop.md#binding-to-a-different-symbol-name)
when the names differ), then add the library that defines it with `[Link]` or `-l`.

If the compiler cannot run `clang` at all, the error says
`Link failed: cannot run clang`. Install clang (on Linux, from your package
manager) or the Xcode Command Line Tools on macOS.

Warnings from the linker are passed through unchanged, even when the link
succeeds.

### A library another Pepper build made

A Pepper program imports a library built with `--lib pepper` as it
imports a module, with no source for it: `import geo;` that finds no
source module `geo` reads the library's interface, `libgeo.pepi`
(`geo.pepi` on Windows), from the folders `-L` names and then
`PEPPER_LIBRARY_PATH`'s, and links `libgeo.a` beside it, so no `[Link]`
is needed. Everything the library's root exports is the program's to
use: functions, structs, value structs, enums, traits and their default
methods, generics, and exported extensions (of the program's files that
import it, as with a source module's). See
[`main.pep`](../../examples/library/main.pep), which imports the library
[`lib/geo.pep`](../../examples/library/lib/geo.pep).

```bash
pepper build --lib pepper geo.pep -o lib/libgeo.a
pepper build main.pep -L lib -o main
```

```pepper
import geo;

main(): int {
    var square = geo.Square(3);
    return geo.pair(square).count - 2;
}
```

The interface is the library's checked declarations, so the program
checks against them without checking the library again. The program
compiles the instantiations of the library's generics it uses (and of
its traits' default methods for its own structs), as C++ compiles a
template from a header; everything else the archive defines. A change
inside the body of one of the library's functions that is not generic
leaves the interface as it was, so the program only links the new
archive; any other change makes a new interface, and the program's code
that imports it is checked again. An archive that is not the one built
with the interface beside it is refused at the import:

```text
main.pep:1:8: error: the archive lib/libgeo.a was not built with the interface lib/libgeo.pepi; rebuild the library 'geo'
```

A program can also declare a library's `[Export]`ed functions as
`extern`s, with `[Link("geo")]` (or `-l geo`) naming the library, as it
links a C one; then only C types cross between them.

```pepper
[Link("geo")]
extern int geo_area(int side);

main(): int {
    return geo_area(3) - 9;
}
```

Either way, the program supplies the one runtime both use: `--lib
pepper` leaves the runtime, `main` and the startup code out of the
archive. So one heap and one set of runtime thread-locals serve both, and
a program can link several such libraries.

- **Initialization.** Before `main`, the program sets the runtime's
  globals, then each Pepper library's (one that links another sets its own
  after that one's), then its own. So a program global may call into a
  library in its initializer.
- **Thread-locals.** When a thread ends, the library's thread-locals are
  released with the program's.
- **Runtime modules.** A runtime module the library imports and the
  program does not (`json`, say) is compiled into the program too.
- **Other libraries.** A library that links another Pepper library or a C
  one does not hold it: the program links it too (`-l`, or `[Link]`). A
  library built with `--lib pepper` cannot import another Pepper library's
  interface yet; it can link one through `extern`s.
- A `--lib static` archive is for C: it holds its own runtime and startup
  code, which clash with the program's at the link.
- `--lib pepper` writes a static library only. A shared library must hold
  its runtime, which `--lib shared` gives it: a Pepper program links one too,
  but then it has a second runtime of its own, so free a string it returns
  with its own `pepper_string_free`, and pass no handle from one to the
  other.

Every program and library Pepper writes carries an identity stamp, in a
section of its own (`.pepmeta`, `__DATA,__pepmeta` on macOS and iOS) that
the linker keeps: the compiler's release, its ABI number, the platform, a
hash of the runtime's core files, the CPU, the runtime checks, whether
frame pointers are kept, and the build options defined. A library for
Pepper also lists its kind, its initializer and release functions, the
Pepper libraries it needs, its record version, the hash of the runtime's
interface and of each runtime module's it loaded, and the hash of its
interface file (`libgeo.pepi`, which `--lib pepper` writes beside the
archive: see [`--lib pepper`](../tools/pep-build.md#--lib-pepper)). A
runtime interface hash covers what other code sees of the runtime's
files: a change inside a function body that changes no return type and
no link summary leaves it alone. Before it builds, the compiler reads the
stamp of each library a `[Link]` or `-l` name finds in the search folders,
and of each file a build script links, and refuses a library for Pepper
that does not fit the build:

```text
main.pep:1:7: error: './libgeo.a' was built by pepper 0.13.0 (ABI 2) for linux x86_64; it defines the build option 'LEVEL' as '1', and this build as '2'; rebuild it with this compiler
```

The record version, the ABI number, the platform, the CPU and the
runtime's interface must match, and so must the interface of each runtime
module both builds load and each build option both define (`--test` and
`--entry` are left out). The interfaces are compared once the program is
checked, the rest before anything is built. Different runtime checks or
frame pointers only warn, since they change the code inside each side
alone. The compiler releases may differ: the record version is what
changes when a compiler writes or reads the library's interface
differently, and the ABI number when a compiler changes code that two
builds rely on of each other. A library for
C (`--lib static` or `--lib shared`, or one an older compiler wrote) keeps
its runtime to itself, so only its platform must match. A library with no
stamp, such as a C one, is not checked.

## Output files

With no `-o`, the executable is named after the first source file, in the
directory where you run the compiler: `main` for `main.pep`, and `main.exe`
when building for Windows, which will not run a file without `.exe`. The object files and other
intermediate files go in `.pep/build/` under the current directory, or in the
directory you pass to `--build`: one object per file of the program in
`<name>.units/`, and `<name>.o`, which runs the program's global
initializers. Unchanged objects come from the build cache in `.pep/cache/`
(`--no-cache` skips it).

With `--lib static`, `--lib shared` or `--lib pepper`, the output is a library and a C
header instead (see [Building the library](c-interop.md#building-the-library)).
