# The compiler: pep-build

`pep-build` compiles a Pepper program into an executable, or into a library
for C code to link. `pepper build` runs it with the same arguments, so
everything on this page applies to both spellings:

```bash
pepper build main.pep -o main          # the same as: pep-build main.pep -o main
```

```text
pep-build [OPTIONS] <entry.pep>
```

This page lists every option. `pep-build --help` prints the same list in
short, and `pepper help build` runs it.

## All options at a glance

| Option | What it does | Default |
| --- | --- | --- |
| `<entry.pep>` | The program's entry file | required |
| `-I <dir>` | Add a folder to search for imported modules | the runtime's folder only |
| `--import <name>` | Load a module into every file of the program | none |
| `--no-runtime` | Compile without the standard library | the runtime is used |
| `-o <file>` | Name the executable or library | `<entry stem>` in the current folder |
| `--lib static`, `--lib shared` | Build a library for C instead of an executable | an executable |
| `--build <dir>` | Folder for intermediate files | `.pep/build` |
| `--emit-llvm` | Write LLVM IR instead of an executable | off |
| `--emit-ast` | Print the syntax tree instead of compiling | off |
| `-O`, `-O0` to `-O3` | Optimization level | `-O0`, or `PEPPER_OPT_LEVEL` |
| `--lto=full`, `--lto=off` | Link-time optimization | `full` at `-O2`/`-O3`, else `off` |
| `-march=`, `-mcpu=`, `-mtune=`, `-m<feature>`, `-mno-<feature>` | The CPU to generate code for | clang's default for the target |
| `-g`, `--emit-debug` | Emit debug info | off |
| `--frame-pointers` | Keep every function's frame pointer, for profilers | off |
| `--target <triple>` | Compile for another platform | the machine compiling |
| `--sysroot <dir>` | The target's system libraries | `PEPPER_SYSROOT_<TRIPLE>` |
| `-l <lib>` | Link a C library | the platform's defaults |
| `-L <dir>` | Add a folder the linker searches | `PEPPER_LIBRARY_PATH` |
| `--MSVC` | Use the MSVC linker (not ported) | off |
| `-D <name>[=<value>]` | Define a build option | none |
| `--no-runtime-checks=<list>` | Remove kinds of runtime check | every check on |
| `--no-cache` | Do not use the build cache | the cache is used |
| `--cache <dir>` | Folder for the build cache | `PEPPER_CACHE_DIR`, else `.pep/cache` |
| `--verify-cache` | Check cache hits against fresh code | off, or `PEPPER_CACHE_VERIFY` |
| `--no-verify-cache` | Do not check cache hits | |
| `-T <channel>`, `--Tall` | Print timings and cache decisions | off |
| `-v`, `--verbose` | Accepted; prints nothing more yet | off |
| `-h`, `--help` | Print the options | |
| `-V`, `--version` | Print the version | |

An option that takes a value accepts it as the next argument or attached:
`-I lib`, `-Ilib`, `--target aarch64-apple-darwin` and
`--target=aarch64-apple-darwin` are all the same. Options may come before or
after the entry file. An unknown option is an error, and the compiler exits
with status 2 after a short usage message.

## Inputs and imports

### The entry file

```bash
pepper build main.pep
```

The file that holds `main`. The compiler finds the files it imports on its
own (see [Modules and imports](../language/modules.md)), so a program of many
files is compiled by naming its entry file alone. Only the first file named
is compiled; any others are ignored. With no file, the compiler stops with
`error: no source files provided`.

### `-I <dir>`

Adds a folder to search for modules imported by name (`import geometry;`
looks for `geometry/module.pep`). The `-I` folders are searched in the order
given, before the runtime's folder. See
[Dependencies and search paths](../language/modules.md#dependencies-and-search-paths).

```bash
pepper build -I tools tools/pep-fmt/main.pep -o pep-fmt
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
name for that stem (`libmain.a`). Windows runs only files ending in `.exe`,
so name the output there: `-o main.exe`.

### `--lib static`, `--lib shared`

Builds a library for C code to link instead of an executable, with a C
header beside it that declares the program's `[Export]`ed functions. No
`main` is needed.

- `--lib static` writes an archive: `libname.a` (`name.lib` on Windows).
- `--lib shared` links a shared library: `libname.so`, `libname.dylib` on
  macOS, `name.dll` on Windows.

See [Calling Pepper from C](../language/c-interop.md#calling-pepper-from-c).

### `--build <dir>`

The folder for intermediate files: the program's objects and, with
`--emit-llvm`, its IR. The default is `.pep/build` in the current folder.

### `--emit-llvm`

Writes the whole program's LLVM IR to `<build>/<name>.ll` (`.pep/build/main.ll`
for `main.pep`), optimized at the `-O` level, and stops there: nothing is
linked and no executable is written.

```bash
pepper build main.pep -O --emit-llvm      # .pep/build/main.ll
```

### `--emit-ast`

Parses the entry file only and prints its syntax tree to standard output,
instead of compiling. Imports are not followed and nothing is checked.

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
alone, which links sooner. The default is `full` at `-O2` and `-O3` and
`off` below; `--lto=full` at `-O0` is an error that asks for `-O`.

### `-march=<cpu>`, `-mcpu=<cpu>`, `-mtune=<cpu>`, `-m<feature>`, `-mno-<feature>`

The `-m` options choose the CPU the code is generated for, with clang's
names and meanings:

- On x86-64, `-march=<cpu>` names the CPU: `x86-64-v3`, `znver4`, or
  `native` for the machine compiling.
- On AArch64, `-mcpu=<cpu>` names the CPU (`apple-m2`, `native`) and
  `-march=<arch>` the architecture (`armv8.2-a+crypto`).
- `-mtune=<cpu>` changes only how instructions are scheduled.
- `-m<feature>` adds a CPU feature (`-mavx2`), and `-mno-<feature>` removes
  one (`-mno-avx2`).

Without them the program runs on any machine of its kind: clang's default
CPU for the target (`x86-64`; `apple-m1` on Apple arm64). An option the
target's architecture does not know is an error. The chosen CPU is part of
the build cache's key.

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
`aarch64-apple-darwin`, `x86_64-apple-darwin`, `x86_64-pc-windows-msvc` or
`aarch64-pc-windows-msvc`, with a version allowed where clang allows one
(`arm64-apple-macosx14.0`). An unsupported triple is an error that lists the
supported ones. `[Target(...)]` selects code for the target. The default is
the machine the compiler runs on. See
[Cross-compiling](../language/platform-selection.md#cross-compiling).

### `--sysroot <dir>`

The folder that holds the target's system headers and libraries, passed to
the link driver, for linking with `--target`. Without it, the folder named by
`PEPPER_SYSROOT_<TRIPLE>` when that is set: the triple in capitals, with `_`
for each character that is not a letter or digit
(`PEPPER_SYSROOT_AARCH64_APPLE_DARWIN` for `aarch64-apple-darwin`).

## Linking

### `-l <lib>`

Links a C library, as `-l` does for clang: `-l m` links `libm`. Repeat it
for more libraries. A program's `[Link]` attributes name libraries from the
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

The link driver is clang. When `LLVM_SYS_<major>1_PREFIX` (for the LLVM the
compiler was built with, such as `LLVM_SYS_201_PREFIX` for LLVM 20) names an
LLVM install, its `bin/clang` and `lld` are used, else those on the `PATH`.

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
See [Integer overflow](../language/types-and-variables.md#integer-overflow).

```bash
pepper build -O main.pep --no-runtime-checks=overflow,shift
```

## The build cache

Each file of the program (each import cycle, and the runtime as one) is
compiled to its own object, and the build cache keeps them: a file whose
sources, and whose imports' declarations, did not change is not compiled or
checked again. The optimization level, link-time optimization, debug info,
CPU, removed runtime checks and build options are part of each object's
key. Deleting the cache folder is always safe.

### `--no-cache`

Compiles every file without reading or writing the build cache.

### `--cache <dir>`

Keeps the build cache in `<dir>`. Without it, the folder named by
`PEPPER_CACHE_DIR` when that is set and not empty, else `.pep/cache` in the
current folder.

### `--verify-cache`, `--no-verify-cache`

`--verify-cache` checks the cache, for testing the compiler: every file the
cache would reuse is compiled anyway, and the build fails if its code
differs from the cached object's, or if skipping the reused files' bodies
changes another file's code. Setting `PEPPER_CACHE_VERIFY` to anything but
empty or `0` does the same. `--no-verify-cache` turns it off even when
`PEPPER_CACHE_VERIFY` is set. The two options cannot be combined.

## Tracing and diagnostics

### `-T <channel>`, `--Tall`

`-T` turns on a trace channel, which prints to standard error. Repeat it for
more channels; `--Tall` turns on every one.

- `-T time` prints how long each stage of the compile took
  (`time: check and build    470.763 ms`).
- `-T passes` prints how long each pass of the checker took, summed over its
  runs, slowest first.
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
| `PEPPER_CACHE_DIR` | The build cache folder | `--cache`, `--no-cache` |
| `PEPPER_CACHE_VERIFY` | Anything but empty or `0` checks the build cache | `--no-verify-cache` |
| `LLVM_SYS_<major>1_PREFIX` | The LLVM install whose `clang` and `lld` link the program (`LLVM_SYS_201_PREFIX` for LLVM 20); `cargo setup` writes it for builds | |
| `NO_COLOR` | Set and not empty: errors are not colored | |

## Exit status

`pep-build` exits with 0 when the program compiled, 1 when it did not (the
errors are on standard error), and 2 for a command line it cannot parse. A
crash of the compiler itself exits with 101 after printing what went wrong;
please report it.
