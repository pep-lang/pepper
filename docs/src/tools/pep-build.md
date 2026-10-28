# The compiler: pep-build

`pep-build` compiles a Pepper program into an executable, or into a library
for C code to link. `pepper build` runs it with the same arguments, so
everything on this page applies to both spellings:

```bash
pepper build main.pep -o main          # the same as: pep-build main.pep -o main
```

```text
pep-build [OPTIONS] [<entry.pep>]
```

This page lists every option. `pep-build --help` prints the same list in
short, and `pepper help build` runs it.

## All options at a glance

| Option | What it does | Default |
| --- | --- | --- |
| `<entry.pep>` | The program's entry file | the project's, from `pep.toml` |
| `-I <dir>` | Add a folder to search for imported modules | the runtime's folder only |
| `--import <name>` | Load a module into every file of the program | none |
| `--entry <name>` | The function the program starts in, instead of `main`; it takes no parameters or one `String[]`, and every `main` is left out (not with `--test` or `--lib`) | `main` |
| `--no-runtime` | Compile without the standard library | the runtime is used |
| `-o <file>` | Name the executable or library (with `--emit-static`, the folder) | `<entry stem>` in the current folder; a project's `name` in its folder |
| `--lib static`, `--lib shared` | Build a library for C instead of an executable | an executable |
| `--lib xcframework`, `--lib swift-package` | Build an iOS `.xcframework`, or a Swift package around one, for an app | an executable |
| `--lib aar` | Build an Android library (`.aar`) holding a shared library for each ABI, for an app | an executable |
| `--bindings swift`, `--bindings java` | With `--lib static` or `--lib shared` (`java`: `--lib shared`), also write Swift or Java bindings of the `[Export]`ed functions beside the header | none |
| `--test` | Build the `[Test]` functions of the entry file (or of several files of one folder) into a test program | off |
| `--locked` | Fail, rather than fetch, when `pep.lock` is out of date with `pep.toml` | off, or `PEPPER_LOCKED` |
| `--offline` | Fetch no dependency over the network; fail on one neither `.pep/deps` nor the download cache holds | off, or `PEPPER_OFFLINE` |
| `--frozen` | Both `--locked` and `--offline` | off |
| `--no-build-scripts` | Fail, rather than run it, when a dependency has a build script; a `[native]` table still compiles, unless a dependency's has `flags` that could load code ([which it allows](projects.md#native)) | off, or `PEPPER_NO_BUILD_SCRIPTS` |
| `--build <dir>` | Folder for intermediate files | `.pep/build` (in a project's folder when building it) |
| `--emit-llvm` | Write LLVM IR instead of an executable | off |
| `--emit-static`, `--emit-static=keep` | Write the source with each `static` block expanded, instead of compiling | off |
| `--emit-ast[=text\|json]` | Print the syntax tree instead of compiling | off |
| `--emit-linked` | Print every file's syntax tree after linking, as JSON, instead of compiling | off |
| `--emit-checked` | Print what the checks after linking report, instead of compiling | off |
| `--emit-model` | Print the program's sema model before any sema pass, as JSON, instead of compiling | off |
| `--emit-model-step <N>` | With `--emit-model`, print the model after the first N sema steps | 0 |
| `--emit-steps` | Print the names of the sema steps, one per line, instead of compiling | off |
| `-O`, `-O0` to `-O3` | Optimization level | `-O0`, or `PEPPER_OPT_LEVEL` |
| `--lto=full`, `--lto=off` | Link-time optimization | `off` |
| `-march=`, `-mcpu=`, `-mtune=`, `-m<feature>`, `-mno-<feature>` (`-m <option>`) | The CPU to generate code for | clang's default for the target |
| `-g`, `--emit-debug` | Emit debug info | off |
| `--debug-static=source`, `--debug-static=expanded` | With `-g`, step through `static` blocks as written or expanded | `source` |
| `--frame-pointers` | Keep every function's frame pointer, for profilers | off |
| `--target <triple>` | Compile for another platform | the machine compiling |
| `--sysroot <dir>` | The target's system libraries | `PEPPER_SYSROOT_<TRIPLE>` |
| `-l <lib>` | Link a C library | the platform's defaults |
| `-L <dir>` | Add a folder the linker searches | `PEPPER_LIBRARY_PATH` |
| `--MSVC` | Use the MSVC linker (not ported) | off |
| `-D <name>[=<value>]` | Define a build option | none |
| `-F <names>`, `--features <names>` | Turn on features of the project's package | its `default` feature |
| `--no-default-features` | Leave the project's package's `default` feature off | off |
| `--all` | Build every member of the project's workspace | the project alone, or every member in a root with no `[package]` |
| `-p <name>`, `--package <name>` | Build this workspace member; repeatable | |
| `--no-runtime-checks=<list>` | Remove kinds of runtime check | every check on |
| `--no-cache` | Do not use the build cache | the cache is used |
| `--cache <dir>` | Folder for the build cache | `PEPPER_CACHE_DIR`, else `.pep/cache` (in a project's folder when building it) |
| `--verify-cache` | Check cache hits against fresh code | off, or `PEPPER_CACHE_VERIFY` |
| `--no-verify-cache` | Do not check cache hits | |
| `-T <channel>`, `--Tall` | Print timings and cache decisions | off |
| `-v`, `--verbose` | Accepted; prints nothing more yet | off |
| `--compile-part <dir>`, `--part <N>=<object>`, `--compilation-unit-worker <dir>`, `--members <names>`, `--member <dir>`, `--print-members`, `--build-script <dir>` | Internal: what a build runs in the children it starts, and what `pep-test` asks | |
| `-h`, `--help` | Print the options | |
| `-V`, `--version` | Print the version | |

An option that takes a value accepts it as the next argument or attached:
`-I lib`, `-Ilib`, `--target aarch64-apple-darwin` and
`--target=aarch64-apple-darwin` are all the same. `-O`, `--emit-ast` and
`--emit-static` take a value only attached (`-O3`, `--emit-ast=json`), so
the argument after them is never read as their value. Short options that
take no value combine (`-gv` is `-g -v`). Options may come before or after
the entry file, and every argument after `--` is a file. An unknown option is
an error, and the compiler exits with status 2 after a short usage message.

## Inputs and imports

### The entry file

```bash
pepper build main.pep
```

The file that holds `main`. The compiler finds the files it imports on its
own (see [Modules and imports](../language/modules.md)), so a program of many
files is compiled by naming its entry file alone. Only the first file named
is compiled; any others are ignored.

With no file, the compiler builds the project whose `pep.toml` is in the
current folder or the nearest folder above it: its `[build]` table names the
entry file and the output, and the build goes in the project's `.pep` (see
[Projects: pep.toml](projects.md)). With no file and no `pep.toml`, it stops
with `error: no source files provided, and no pep.toml in <folder> or a
folder above it`.

```bash
cd my_app/src
pepper build              # builds my_app/pep.toml's program into my_app/
```

An entry file inside a project (under a folder with a `pep.toml`) imports the
project's dependencies, and its `[build]` table's `include` folders and
`link` libraries apply to it as well.

Before compiling a program in a project, the compiler fetches whatever
`pep.lock` lists and the project's `.pep/deps` lacks or holds at another
commit, and the Git dependencies that `pep.toml`, or the `pep.toml` of a
`path` dependency it reaches, names and `pep.lock` does not list yet, by
running `pep-package fetch` (beside `pep-build`, else on the
`PATH`). Without
`pep-package`, it checks the missing commits out with `git` itself, and
asks for `pepper package fetch` to move a checkout at another commit. A
dependency checked out on a branch is left as it is. See
[The package manager: pep-package](pep-package.md).

### `--locked`, `--offline`, `--frozen`

These make the fetch reproducible, for CI (see
[Reproducible builds](pep-package.md#reproducible-builds)):

- `--locked` (or `PEPPER_LOCKED=1`) fails when `pep.lock` is out of date
  with `pep.toml`, instead of updating it. A Git dependency `pep.toml`
  names that `pep.lock` does not list is an error before anything is
  fetched; otherwise the build runs `pep-package fetch --locked`, even when
  nothing is missing, so a changed range is caught too.
- `--offline` (or `PEPPER_OFFLINE=1`) fetches nothing over the network:
  `pep-package` runs with `--offline`, taking a locked package `.pep/deps`
  lacks from the [download cache](pep-package.md#the-download-cache), and
  failing on one the cache lacks too. Without `pep-package`, a locked
  package `.pep/deps` lacks is an error that names it.
- `--frozen` is both.

```text
$ pepper build --offline
fetching the dependencies of app/pep.toml failed (pep-package -C app fetch --offline exited with 1):
pep-package: error: cannot fetch github:someone/geometry: --offline, and neither app/.pep/deps/github.com/someone/geometry nor the package cache holds the commit 0582024b9cd7; run 'pepper package fetch' without --offline (or PEPPER_OFFLINE) first
```

### Build scripts and `--no-build-scripts`

Once the dependencies are fetched, and before it loads the program, the
compiler runs the [build script](projects.md#build-scripts) of each package
the build turns on (the project's first): it builds the script for the
machine it runs on, with itself and `--build-script`, into
`.pep/build/<package>-<hash>/`, where the script's package sees only its
[`[build-dependencies]`](projects.md#build-dependencies) and their own
scripts run; then it runs the script in the package's folder, links what
it says to, defines the build options it names, and resolves the
package's `import generated` to the [modules](projects.md#generated-modules)
it wrote. A script whose inputs, the Pepper files it imports among them,
have not changed since its last run is not run again. The script builds in
the program's [build cache](#the-build-cache), even under `--no-cache`,
whose record of the script's build names the files it imports. The `--emit-*` modes run them too, since the program they load
may import what a script generates.

After a package's script, if it has one, the compiler compiles the C its
[`[native]`](projects.md#native) table and the
`[target.'<condition>'.native]` tables that hold for the target name,
with its own clang for the target, the system root and the `-O` level,
into `.pep/build/<package>-<hash>/native/<target>/`, and links the objects. An
object whose source, included headers (from clang's `-MD` list) and flags
have not changed is not compiled again.

`--no-build-scripts` (or `PEPPER_NO_BUILD_SCRIPTS=1`) fails instead of
running a dependency's script, which runs that package's code on this
machine; the project's own script still runs, and so does every
`[native]` table, which runs no package code. A dependency's table is
refused when one of its `flags` is not on the short list that cannot load
code or name a file ([`[native]`](projects.md#native) lists it), since a
flag such as `-fplugin=` makes clang load a plugin from the package. The
error is at the flag in the dependency's `pep.toml`:

```text
app/.pep/deps/github.com/someone/native/pep.toml:8:10: error: '--no-build-scripts' (or PEPPER_NO_BUILD_SCRIPTS) refuses the clang flag '-fplugin=x' of the dependency 'native', which could load code or name a file; it allows only -O0 to -O3, -Os, -Oz, -std=, -march=, -mcpu=, -mtune= and plain -W, -f and -m options; read the flag, and build without that option to use it
```

A dependency's build script is refused outright:

```text
error: the dependency 'native' has a build script, app/.pep/deps/github.com/someone/native/build.pep, which '--no-build-scripts' (or PEPPER_NO_BUILD_SCRIPTS) refuses to run; read it, and build without that option to run it
```

### `-I <dir>`

Adds a folder to search for modules imported by name (`import geometry;`
looks for `geometry/module.pep`). The `-I` folders are searched in the order
given, then a project's `[build]` `include` folders, then the runtime's
folder. A project's dependencies are found through its `pep.toml` instead.
See
[Dependencies and search paths](../language/modules.md#dependencies-and-search-paths).

```bash
pepper build tools/pep-fmt/main.pep -o pep-fmt
```

### `--import <name>`

Loads a module (`<name>/module.pep`) or a file (`<name>.pep`), found on the
search paths, into every file of the program, the way the standard library's
prelude is loaded. Its definitions come ahead of the runtime's, so one that
redefines a runtime export wins. Repeat it for more modules. A name that
cannot be found is an error that lists the folders searched. See
[The runtime prelude and `--import`](../language/modules.md#the-runtime-prelude-and---import).

### `--no-runtime`

Compiles without the standard library: the runtime is neither looked for
nor loaded, so only the program's own files and what `-I` reaches are
compiled. For testing the compiler; ordinary programs need the runtime
(`print`, `String` and `Array` all live there).

Without this option the compiler finds the runtime as
[Getting started](../tutorial/getting-started.md#where-the-compiler-finds-the-standard-library)
describes, and `PEPPER_RUNTIME` names its folder outright.

## Output

### `-o <file>`

The path of the executable, or with `--lib` of the library. Without it, the
output goes to the current folder, named after the entry file with no
extension (`main` for `main.pep`); with `--lib`, the library's usual file
name for that stem (`libmain.a`). Building a project with no file, it is the
`[build]` table's `output`, else the package's `name` in the project's
folder (`libname.a` with `--lib`), with `.exe` added when building for
Windows and the name has no extension. Windows runs only files ending in
`.exe`, so otherwise name the output there: `-o main.exe`. The folders
the path names are made when they do not exist.

With `--emit-static`, it is the folder the expanded source goes into.

### `--lib static`, `--lib shared`

Builds a library for C code to link instead of an executable, with a C
header beside it that declares the program's `[Export]`ed functions. No
`main` is needed.

- `--lib static` writes an archive: `libname.a` (`name.lib` on Windows),
  holding the objects of the whole program, the runtime's included, with the
  index of their symbols that linkers search. The compiler writes it itself
  in the target's format (GNU's for Linux and Android, the BSD format
  Apple's linkers read for macOS and iOS, the COFF archive for Windows), so
  no archiver needs to be installed, and building one for another platform
  needs no system root: nothing is linked. A program linking it also links
  the libraries the program does, which the header names in a comment
  (`/* Link the static library with: -lm */`).
- `--lib shared` links a shared library: `libname.so`, `libname.dylib` on
  macOS, `name.dll` (and its import library `name.lib`) on Windows. Its
  `soname` is its file name; on macOS and iOS its install name is
  `@rpath/<file name>`, so a program that links it finds it on its run
  path. Linking one for another platform needs its system root, as an
  executable does (`--sysroot`). For Android, when the program imports
  `tls`, the `.so` holds the toolchain's static OpenSSL, and its license
  goes beside it as `LICENSE-OpenSSL.txt`.

The header goes beside the library, named for it without the `lib` prefix
(`libname.a` has `name.h`). A library that exports nothing is built with a
warning. See
[Calling Pepper from C](../language/c-interop.md#calling-pepper-from-c).

### `--bindings swift`, `--bindings java`

With `--lib static` or `--lib shared`, also writes bindings beside the
header `name.h`, so Swift, Kotlin or Java code calls the `[Export]`ed
functions with its own values (a `String` in and out, an object for each
struct handle), named in camel case:

- `--bindings swift` writes `name.swift`, a Swift function for each export
  and a class for each struct handle, and the `module.modulemap` of the C
  module they import, `Cname` (the header). Compile `name.swift` with the
  app's Swift code and `-I` its folder.
- `--bindings java` (only with `--lib shared`) writes `name.jar`, the class
  `pepper.name.Name` (in Pascal case) of a `static native` method for each
  export, which loads `libname.so`, and a class for each struct handle
  (`AutoCloseable`); and `name_jni.c`, the JNI functions of those methods,
  which the link compiles into the library. The class files are written
  by the compiler, so this needs no JDK, but the link needs a clang that
  finds `jni.h`, as the Android NDK's does. An export that passes a C
  function pointer, or whose name Java cannot use, is an error.

`--lib swift-package` and `--lib aar` write them themselves; with those,
or without `--lib`, `--bindings` is a usage error. See
[iOS and Android](../language/mobile.md#bindings).

### `--lib xcframework`, `--lib swift-package`

Builds the static library of an iOS app's Pepper code for every iOS target
at once, packaged as Xcode and SwiftPM take it. Each is named for its
output, which must be a Swift module name (letters, digits and `_`):

- `--lib xcframework` writes `Name.xcframework` (`-o Name.xcframework`;
  the output must end in `.xcframework`, since it is replaced whole):
  `ios-arm64/` for devices and `ios-arm64_x86_64-simulator/` for the
  simulator on Apple silicon and Intel Macs, each with `libName.a`, the
  header `Name.h` and a `module.modulemap`, so Swift can `import Name`, and
  the `Info.plist` listing them. The compiler builds the three static
  libraries by running itself with `--lib static --target <triple>`, side
  by side, each in a folder of the build folder's `xcframework/`, and
  writes the simulator's two archives into one universal file itself, as
  `lipo` would, so this needs no Xcode and works on any system.
- `--lib swift-package` writes the folder `Name` (`-o Name`) holding
  `CName.xcframework` (as above, its module named `CName`), the Swift
  bindings of `--bindings swift` as `Sources/Name/Name.swift`, and a
  `Package.swift` whose library product `Name` is that Swift target over
  the binary target, for iOS 15 and later. An app adds it as a local
  package (`.package(path: "Name")`), or from the repository it is
  committed to.

They cannot be combined with `--target` or the `--emit` options. See
[iOS and Android](../language/mobile.md#packaging-for-xcode-and-swiftpm).

### `--lib aar`

Builds the shared library of an Android app's Pepper code for every
Android ABI at once (`arm64-v8a` and `x86_64`), packaged as an Android
library a Gradle build adds: `name.aar` (`-o name.aar`), named for its
output, which takes letters, digits and `_`. It holds
`jni/<abi>/libname.so` for each ABI, the header as `include/name.h`, an
`AndroidManifest.xml` for the package `pepper.name` and API level 30, the
Java bindings of `--bindings java` as `classes.jar` (each `.so` holds their
JNI functions), the empty `R.txt` and `res/` an `.aar` must have, and,
when the program imports `tls`, OpenSSL's license as
`LICENSE-OpenSSL.txt`. The compiler builds each library by running itself
with `--lib shared --bindings java --target <triple>`, side by side, each in a folder of the build folder's
`aar/`, and writes the zip itself, so this needs the Android NDK (found as
for any Android link: `--sysroot`, `ANDROID_NDK_HOME` or `ANDROID_HOME`)
but no Gradle or JDK. It cannot be combined with `--target` or the
`--emit` options. See
[iOS and Android](../language/mobile.md#packaging-for-gradle).

### `--test`

Builds the entry file's tests into a test program, which
[pep-test](pep-test.md) runs. A build without it leaves every `[Test]`
function out. With it:

- the `[Test]` functions are kept, and the build option `TEST` is defined
  (as by `-D TEST`), for code only tests use (`[BuildOption("TEST")]`);
- the runtime's `testing` module is loaded into every file (as by
  `--import testing`);
- the entry file's `main` is replaced by one that answers `--list` (one
  line per test: name, `file:line`, `returns` or `panics`, and the text a
  `[ShouldPanic]` panic must contain, separated by tabs) and
  `--run NAME [--timeout SECONDS]` (run that test; a test still running
  after the timeout ends the program with exit status 124).

Only the entry file's `[Test]` functions become tests. Given several files
of one folder (`pep-build --test a_test.pep b_test.pep`), it builds the
tests of them all into one program: a generated entry file in that folder
(`_pep_test_main.pep`, never written to disk) imports each file and
registers its tests, and each file keeps the scope it has in any program.
`--list` then gives each test's own file, and `--run` also takes
`FILE::NAME`, as `--list` spells the file, to tell apart tests of one name
in two files. It cannot be combined with `--lib`. See [Unit tests](../language/testing.md).

### `--build <dir>`

The folder for intermediate files: the program's objects and, with
`--emit-llvm`, its IR. The default is `.pep/build` in the current folder, or
in the project's folder when building a project with no file.

### `--emit-llvm`

Writes the whole program's LLVM IR to `<build>/<name>.ll` (`.pep/build/main.ll`
for `main.pep`), optimized at the `-O` level, and stops there: nothing is
linked and no executable is written.

```bash
pepper build main.pep -O --emit-llvm      # .pep/build/main.ll
```

### `--emit-static`, `--emit-static=keep`

Writes a copy of the program's source with each `static` block replaced by
the code it emits, like a C compiler's `-E`, and stops there: nothing is
compiled to code. Use it to see what a reflection loop, a serializer or a
library's block does to the program (see
[Seeing what a static block emits](../language/reflection.md#seeing-what-a-static-block-emits)).

```bash
pepper build main.pep --emit-static              # main.static/main.pep
pepper build main.pep --emit-static -o expanded  # expanded/main.pep
pepper build expanded/main.pep -o main           # the same program
```

- Every file of the program in the entry file's folder (and the folders
  under it) is written into the output folder at the same relative path,
  so the folder builds as a whole program; files with no block are copied
  unchanged. The runtime and libraries found elsewhere are not copied. The
  originals are never overwritten.
- The folder is `-o`'s, else `<entry stem>.static` in the current folder.
- Each expansion is a `{ ... }` block between
  `# static (out, value) expanded from main.pep:12:5` and `# end static`.
  `--emit-static=keep` also keeps the block as written, as `#` comments
  above it; `--emit-static=expand` is the default, the same as
  `--emit-static`.
- A block in a generic function expands once per specialization. The
  generic function stays as written, and after it comes a
  [concrete override](../language/generics.md#overriding-a-generic-function-for-one-type)
  for each type the program uses it with (`describe<Point>(value: Point)`),
  its blocks expanded, so the copy still builds into the same program. A
  block in a method of a generic struct, or in a generic method, stays,
  with each specialization's expansion above it as `#` comments.
- When `pep-fmt` is next to the compiler or on `PATH`, it formats the
  copies, wrapping long lines.
- Errors a block reports stop it, as they stop a build. Errors in the code
  a block emits are found when the copy is built, at the copy's line.

### `--emit-ast`

Parses the entry file only and prints its syntax tree to standard output,
instead of compiling. Imports are not followed and nothing is checked.

`--emit-ast` and `--emit-ast=text` print the tree as source-like text.
`--emit-ast=json` prints it as one line of JSON: each node an object with
its fields in declaration order, each enum case an object with the case's
name as its one key, and each span `{"start": ..., "end": ...}` in bytes.
The compiler's parser written in Pepper (`tools/compiler`) prints the same
JSON, and its test compares the two over every source file in the
repository.

### `--emit-linked`

Loads the program as a build does (the entry file, every file its imports
reach, and the runtime), links it, and prints it to standard output as one
line of JSON instead of compiling. Nothing after linking is checked, so a
program with type errors prints too; a file that cannot be read or parsed
stops it, as it stops a build.

The JSON is an object with three keys:

- `files`: every file in load order (the entry file first), each with its
  `name` as the program reached it, its `namespace`, its `module_root`
  folder (or `null`), whether it is part of the `prelude` (the runtime and
  `--import` files) or a `prelude_part` (another file of a forced module),
  the index of the file each of its `imports` names (or `null` when one did
  not resolve), which of them are `folder_imports` (a local import of a
  module folder), and its `module`, the syntax tree as `--emit-ast=json`
  prints it after linking renamed what the file imports and gave its
  private declarations their program-wide names (`helper@io/file`).
- `errors`: the linking errors, by file and position, each with its `file`
  index, `span`, `message`, whether it is an `unresolved` import, and its
  `note` (`[span, message]`, or `null`).
- `overload_unions`: each overload set that spans files, by name, with its
  functions grouped by module.

`-I`, `--import`, `--no-runtime`, `-D` and `--test` apply as for a build.
The compiler's linker written in Pepper (`tools/compiler`) prints the same
JSON, and its test compares the two.

### `--emit-checked`

Loads and links the program as `--emit-linked` does, runs the checks that
come before type checking, and prints what they report instead of
compiling: the errors, rendered as a build reports them, then the warnings.
The errors are the linking errors; when there are none, a `[__BuiltIn]`
declaration outside the runtime; when there is none of those either, every
use of a declaration another file keeps private or this file does not
import. The warnings are deprecated syntax, comparisons with a build option
`-D` does not define, and uses of declarations marked `[Deprecated]`. A
program with neither prints an empty line.

`-I`, `--import`, `--no-runtime`, `-D` and `--test` apply as for a build.
The compiler written in Pepper (`tools/compiler`) prints the same text, and
its test compares the two.

### `--emit-model`

Loads, links and checks the program as `--emit-checked` does, builds the
sema model of each file and joins them, and prints the model as one line of
JSON instead of compiling: what the sema builder made of the syntax trees
(`for`, `with`, `match`, `?`, destructuring, ranges, collection literals and
properties lowered), before any sema pass runs. Object keys are sorted, and
so are the sets (`private_functions` and the `extension_scopes`). When the
checks or the builder reject the program, it prints the rendered error and
fails.

`-I`, `--import`, `--no-runtime`, `-D` and `--test` apply as for a build.
The compiler written in Pepper (`tools/compiler`) prints the same JSON, and
its test compares the two.

### `--emit-model-step <N>`

With `--emit-model`, runs the first N steps of the sema passes before
printing the model. A step is one pass run, in the order the compiler runs
them (platform filters first, then `[Equatable]`, closure lifting and the
rest); `--emit-steps` lists them. When a step rejects the program, it prints
the rendered error and fails. The compiler written in Pepper runs the same
steps, and its test compares the model after each.

### `--emit-steps`

Loads, links, checks and builds the program as `--emit-model` does, runs
every sema pass, and prints the name of each step run, one per line,
instead of compiling: the numbering `--emit-model-step` uses.

## Optimization and code generation

### `-O`, `-O<level>`

The optimization level: `-O0` (no optimization, the default), `-O1`, `-O2`
or `-O3`. `-O` alone is `-O2`, and it does not take the next argument as its
level, so `pepper build -O main.pep` works. Each level runs the pipeline
clang runs at that level. Without the option, the level is
`PEPPER_OPT_LEVEL` (`0` to `3`) when that is set and not empty.

At `-O0` a panic prints a backtrace after its message; at any other level it
prints the message alone, unless the program runs with `PEPPER_BACKTRACE=1`
(see [Backtraces on panic](../language/debug.md#backtraces-on-panic)).

### `--lto=full`, `--lto=off`

Link-time optimization. With `--lto=full`, once every file is compiled the
whole program is optimized again as one module, so a call into another file
(the runtime included) can be inlined. `--lto=off` optimizes each file
alone, which links sooner. The default is `off`: `full` optimizes the whole
program again on every build, an edit's too, so it suits a release build.
`--lto=full` at `-O0` is an error that asks for `-O`.

With it, each file is optimized by LLVM's pre-link pipeline and kept as
bitcode (in the build cache, as an object is), then the compiler links
them into one module, makes every symbol internal but `main` and the C
exports of `[Export]` functions, runs LLVM's link-time pipeline over the
whole program, and writes its objects, one per logical CPU in parallel,
which link as usual. No linker
plugin is involved, so it works on every target. It applies to a library
too (`--lib`).

### `-march=<cpu>`, `-mcpu=<cpu>`, `-mtune=<cpu>`, `-m<feature>`, `-mno-<feature>`

The `-m` options choose the CPU the code is generated for, with clang's
names and meanings (`-m <option>`, with a space, is the same as
`-m<option>`):

- On x86-64, `-march=<cpu>` names the CPU: `x86-64-v3`, `znver4`, or
  `native` for the machine compiling.
- On AArch64, `-mcpu=<cpu>` names the CPU (`apple-m2`, `native`) and
  `-march=<arch>` the architecture (`armv8.2-a+crypto`).
- `-mtune=<cpu>` changes only how instructions are scheduled.
- `-m<feature>` adds a CPU feature (`-mavx2`), and `-mno-<feature>` removes
  one (`-mno-avx2`).

Without them the program runs on any machine of its kind: clang's default
CPU for the target (`x86-64`; `apple-m1` on Apple arm64). An option the
target's architecture does not take is an error worded as clang words it:
`-mcpu=` on x86-64 (`unsupported option '-mcpu=' for target ...; use
'-march' or '-mtune'`), `-march=` on WebAssembly, an AArch64 `-march=`
that is not `armv<version>-a` (`invalid arch name`), `native` for another
platform's target, or an empty value. A CPU or feature name LLVM does not
know is passed on, and LLVM warns about it. The last of each option wins;
the features come after those the CPU implies. The chosen CPU, its
features and its tuning are part of the build cache's key.

### `-g`, `--emit-debug`

Emits debug info for gdb, lldb, Visual Studio and WinDbg: DWARF 4 in the
executable on Linux and macOS, and CodeView on Windows, where the linker
writes `<output>.pdb` beside the executable. On macOS it also runs
`dsymutil` to write `<output>.dSYM` beside the executable, when the
program is built for the Mac it runs on. It works with `-O`. See
[Debugging](debugging.md).

A Windows build without `-g` also writes `<output>.pdb`, holding only the
program's function names, which is where [backtraces](../language/debug.md)
read them.

Every link leaves out the functions and data nothing uses, except a Windows
build with `-g`: its linker keeps them all, so the program is larger.

### `--debug-static=source`, `--debug-static=expanded`

With `-g`, chooses which source the debugger shows for the code a `static`
block emits (see
[Stepping through a `static` block](debugging.md#stepping-through-a-static-block)):

- `source`, the default: the block as written. Stepping stops on a
  compile-time loop's header once per pass, then on its body.
- `expanded`: a copy of each file with its blocks expanded, as
  `--emit-static` writes it (unformatted), saved beside the output as
  `<name>.static.pep` (`main.static.pep` for `main.pep`; a file in a folder
  under the entry's keeps that folder). The debugger steps through the
  expanded statements, `sum = sum + p.y;`, and a breakpoint on one of its
  lines stops in that pass. The rest of the program stays in its own
  files. A build with it does not use the build cache.

```bash
pepper build -g --debug-static=expanded main.pep -o main   # main, main.static.pep
```

### `--frame-pointers`

Keeps the frame pointer in every function, even when optimizing, as clang's
`-fno-omit-frame-pointer` does. A sampling profiler then walks the stack of
each sample by following frame pointers, which is fast and finds every
frame of Pepper code; without them, optimized code reuses the register and
a profiler loses the callers of whatever was running. It costs a register
and a few instructions per call. [pep-profile](pep-profile.md) builds with
it, `-O` and `-g`. It is part of the build cache's key.

## Targets and cross-compiling

### `--target <triple>`

Compiles for another platform, named by an LLVM target triple:
`x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`,
`aarch64-apple-darwin`, `x86_64-apple-darwin`, `x86_64-pc-windows-msvc`,
`aarch64-pc-windows-msvc`, `wasm32-wasip1`, `aarch64-apple-ios`,
`aarch64-apple-ios-simulator`, `x86_64-apple-ios-simulator`,
`aarch64-linux-android` or `x86_64-linux-android`, with a version allowed
where clang allows one (`arm64-apple-macosx14.0`, `aarch64-apple-ios17.0`,
`aarch64-linux-android33`). An unsupported triple is an error that lists the
supported ones. `[Target(...)]` selects code for the target. The default is
the machine the compiler runs on. See
[Cross-compiling](../language/platform-selection.md#cross-compiling) and
[iOS and Android](../language/mobile.md).

### `--sysroot <dir>`

The folder that holds the target's system headers and libraries, passed to
the link driver, for linking with `--target`. Without it, the folder named by
`PEPPER_SYSROOT_<TRIPLE>` when that is set: the triple in capitals, with `_`
for each character that is not a letter or digit
(`PEPPER_SYSROOT_AARCH64_APPLE_DARWIN` for `aarch64-apple-darwin`). An iOS
or Android triple's variable leaves out the OS version
(`PEPPER_SYSROOT_AARCH64_APPLE_IOS_SIMULATOR` for
`aarch64-apple-ios17.0-simulator`). For iOS it is an iOS SDK, which on a Mac
defaults to the one `xcrun` names; for Android it is the NDK (see
`ANDROID_NDK_HOME` below).

## Linking

### `-l <lib>`

Links a C library, as `-l` does for clang: `-l m` links `libm`. Repeat it
for more libraries. A project's `[build]` table adds its `link` libraries. A program's `[Link]` attributes name libraries from the
source instead. See [Linking](../language/linking.md).

### `-L <dir>`

Adds a folder the linker searches for libraries. Folders given with `-L`
come first, then those of `[Link(path = ...)]`, then those in
`PEPPER_LIBRARY_PATH` (separated like `PATH`: `:`, or `;` on Windows). See
[Library search directories](../language/linking.md#library-search-directories-in-the-source-and-the-environment).

```bash
pepper build main.pep -L libs -l foo        # links libs/libfoo
```

### `--MSVC`

Reserved for linking with Microsoft's linker. It is not ported, so it is an
error on every platform; Windows executables link with clang and lld.

The link driver is clang. When `PEPPER_LLVM_PREFIX`, else
`LLVM_SYS_<major>1_PREFIX` (for the LLVM the compiler was built with, such
as `LLVM_SYS_201_PREFIX` for LLVM 20), names an LLVM install, its
`bin/clang` and `lld` are used; else a `clang` beside
`pep-build`, then one on the `PATH` (`clang`, then `clang-<major>`), then one
where LLVM's packages install it off the `PATH`. With none, the link fails
with an error naming what to install. [Installing Pepper](install.md#what-linking-needs)
lists the folders searched.

## Build options

### `-D <name>`, `-D <name>=<value>`

Defines a build option. A bare name is `name=1`, as in C. `[BuildOption]`
and `[Target(BuildOption(...))]` select code by it, and `static` blocks read
it with `reflect.build_option`. Repeat it for more options; of two that name
the same option, the later wins. A name must be an identifier
(`-D 2FAST` is an error). Build options are part of the build cache's key.
See [Build options](../language/build-options.md).

```bash
pepper build main.pep -D USE_ZLIB -D LOG_LEVEL=2
```

### `-F <names>`, `--features <names>`, `--no-default-features`

`--features` turns on features of the project's package, from the
`[features]` of its `pep.toml`: a comma-separated list (`--features
tls,gzip`), or the option repeated. Its `default` feature is on unless
`--no-default-features` is given. Each feature on defines the build option
`<package>_<feature>` (`http_tls`), and turns on what it lists, across the
whole dependency graph; see [Features](projects.md#features). A feature
the package does not have is an error that lists those it has:

```text
unknown feature 'tsl' in '--features': package 'http' has 'default', 'tls', 'gzip'
```

### `--all`, `-p <name>`, `--package <name>`

In a [workspace](projects.md#workspaces-workspace), `--all` builds every
member and `-p` (repeated for more) the members it names by package
name, from the root or any member. Each member builds into its own
output, as `pepper build` in its folder would, one after another, and
the first that fails stops the rest; a member with no `[build]` entry
and no `main.pep`, a library, is skipped. Their features are unified:
the build of each turns on what every selected member turns on in a
package they share, and `--features` turns a feature on in each member
that has it. In a workspace's root with no `[package]` of its own,
`pepper build` builds every member. `-o` names one output, so it takes
one member.

```bash
pepper build --all          # every member
pepper build -p app -O      # the member named app, optimized
```

## Runtime checks

### `--no-runtime-checks=<list>`

Integer overflow, division by zero, an oversized shift, an index out of
range and a call through a null reference panic at run time, at every
optimization level. This option removes the kinds of check it names, as a
comma-separated list, from an optimized build:

| Kind | What is no longer checked | What happens instead |
| --- | --- | --- |
| `overflow` | Integer overflow | Arithmetic wraps |
| `divide` | Division by zero and `MIN / -1` | Undefined behavior |
| `shift` | A shift count of at least the width | The count is masked |
| `bounds` | Array and string indexing | Undefined behavior |
| `null` | Calls and matches through a null reference | Undefined behavior |
| `all` | All of the above | |

Removing `bounds` or `null` gives up memory safety. At `-O0` the option has
no effect and prints `warning: '--no-runtime-checks' has no effect at -O0`.
To remove checks from one function at every level, mark it
`[Unsafe("overflow,bounds")]` instead.
See [Integer overflow](../language/types-and-variables.md#integer-overflow).

```bash
pepper build -O main.pep --no-runtime-checks=overflow,shift
```

## The build cache

The compiler checks a program one **compilation unit** at a time: a file,
or the files that import each other in a cycle, with the runtime as one.
The build cache keeps each compilation unit's checked result and object,
and each file's own object: a file whose sources, and whose imports'
declarations, did not change is not compiled or checked again.
`PEPC_COMPILATION_UNIT_JOBS` sets how many compilation units are checked at
once (one per processor by default; `PEPC_LAYER_JOBS`, its old name, still
works). The optimization level, link-time optimization, debug info,
CPU, removed runtime checks and build options are part of each object's
key. Deleting the cache folder is always safe.

### `--no-cache`

Compiles every file without reading or writing the build cache.

### `--cache <dir>`

Keeps the build cache in `<dir>`. Without it, the folder named by
`PEPPER_CACHE_DIR` when that is set and not empty, else `.pep/cache` in the
current folder, or in the project's folder when building a project with no
file.

No path in the cache adds more than 72 characters to `<dir>`'s, so a
project folder can sit deep without the cache passing Windows'
260-character path limit. The folder holds one subfolder per layout
version (`v3`); a build ignores the others, so an old version's folder can
be deleted.

### `--verify-cache`, `--no-verify-cache`

`--verify-cache` checks the cache, for testing the compiler: every file the
cache would reuse is compiled anyway, and the build fails if its code
differs from the cached object's, or if skipping the reused files' bodies
changes another file's code. Setting `PEPPER_CACHE_VERIFY` to anything but
empty or `0` does the same. `--no-verify-cache` turns it off even when
`PEPPER_CACHE_VERIFY` is set. The two options cannot be combined.
It builds the program a second time, with an empty cache of its own in the
build folder, and compares each object that build makes with the one the
cache holds under the same key, so a check costs about a build from
scratch. A failure names the cached objects that differ.

## Tracing and diagnostics

### `-T <channel>`, `--Tall`

`-T` turns on a trace channel, which prints to standard error. Repeat it for
more channels; `--Tall` turns on every one.

- `-T time` prints how long each stage of the compile took, and the
  compiler's peak memory once it ended (`time: link bodies 1395 ms, peak
  400 MB`). A build in compilation units keeps its workers' timings in
  `compilation-units.<pid>/<k>.stages` in the build folder, each ending
  with that worker's peak memory.
- `-T passes` prints how long each pass of the checker took, summed over its
  runs, slowest first (`pass:  3116.171 ms   16x resolve_implicit_types`),
  the passes run checking the runtime and each module included.
- `-T cache` prints how the build cache supplied each object: `hit` (its
  sources, and its imports' declarations, are unchanged), `hit (same code)`
  (compiled again, to the same code), or `miss`; and whether linking was
  skipped.

Any other channel name is accepted and ignored.

### `-v`, `--verbose`

Accepted for compatibility with other compilers; it prints nothing more yet.

Errors and warnings are printed like clang's, colored when standard error is
a terminal; set `NO_COLOR` to turn color off. See
[Compiler errors](../language/compiler-errors.md).

## Internal options

A build starts copies of the compiler to work side by side, and gives them
these options; they are listed so a failed child's command line can be
rerun by hand (the build prints it).

- `--compile-part <dir> --part <N>=<object>...` compiles parts of the
  program a build split into `<dir>`: each `--part` names a part by its
  number and the object to write it to. Nothing else is read.
- `--compilation-unit-worker <dir>`, after the build's own arguments, checks
  the compilation units the build passes through `<dir>` and compiles their
  objects.
- `--members <names>` names, comma-separated, the workspace members a
  build of several (`--all`, `-p`) builds together, so each child unifies
  its features with theirs. With a file, `--all` and `-p` do the same.
- `--member <dir>`, with no file, builds the project in `<dir>` rather
  than the one around the current folder; a build of several members
  starts each child with it, in its own folder, so relative paths such
  as `-o` keep their meaning.
- `--print-members` prints the package name and folder of each member
  `--all` or `-p` selects, a tab between them, a line each, and builds
  nothing; `pep-test --all` and `-p` run it.

## Help and version

- `-h`, `--help` prints every option with a line of description.
- `-V`, `--version` prints `pep-build` and its version.

## Environment variables

| Variable | What it does | Option that overrides it |
| --- | --- | --- |
| `PEPPER_RUNTIME` | The folder holding the standard library; nothing else is searched | `--no-runtime` skips the runtime |
| `PEPPER_OPT_LEVEL` | The optimization level (`0` to `3`) without `-O`; also the level the test suite's JIT uses | `-O<level>` |
| `PEPPER_LIBRARY_PATH` | More folders the linker searches, after `-L` and `[Link(path = ...)]` | `-L` comes first |
| `PEPPER_SYSROOT_<TRIPLE>` | The system libraries for linking with `--target <triple>` | `--sysroot` |
| `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT` | The Android NDK for linking with an Android `--target`, when neither `--sysroot` nor `PEPPER_SYSROOT_<TRIPLE>` names one | `--sysroot` |
| `ANDROID_HOME`, `ANDROID_SDK_ROOT` | The Android SDK, whose newest `ndk/<version>` links an Android `--target` when nothing above names an NDK | `--sysroot` |
| `WASI_SDK_PATH` | The wasi-sdk for linking with `--target wasm32-wasip1`, when neither `--sysroot` nor `PEPPER_SYSROOT_WASM32_WASIP1` names one | `--sysroot` |
| `PEPPER_CACHE_DIR` | The build cache folder | `--cache`, `--no-cache` |
| `PEPPER_CACHE_VERIFY` | Anything but empty or `0` checks the build cache | `--no-verify-cache` |
| `PEPPER_LOCKED` | Anything but empty or `0`: the same as `--locked` | |
| `PEPPER_OFFLINE` | Anything but empty or `0`: the same as `--offline` | |
| `PEPPER_LLVM_PREFIX` | The LLVM install whose `clang` and `lld` link the program | |
| `LLVM_SYS_<major>1_PREFIX` | The same, when `PEPPER_LLVM_PREFIX` is not set (`LLVM_SYS_201_PREFIX` for LLVM 20) | |
| `PEPPER_PACKAGE_GITHUB_URL`, `PEPPER_PACKAGE_GITLAB_URL`, `PEPPER_PACKAGE_CODEBERG_URL` | Where a build fetching a project's locked dependencies clones that host's repositories from, when `pep-package` is not installed (see [pep-package](pep-package.md#environment-variables)) | |
| `NO_COLOR` | Set and not empty: errors are not colored | |

## Exit status

`pep-build` exits with 0 when the program compiled, 1 when it did not (the
errors are on standard error), and 2 for a command line it cannot parse. A
crash of the compiler itself exits with 101 after printing what went wrong;
please report it.
