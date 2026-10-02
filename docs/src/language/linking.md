# Linking

The Pepper compiler turns your program into a native executable in two steps:
it compiles all of your files, and the runtime, into one object file, and
then links that object file with the system libraries it needs. When you
[call C functions](c-interop.md), linking is where their definitions come
from, so this chapter explains what is linked by default and how to add more.

## What the compiler links

The compiler uses `clang` as its link driver, rather than calling the
platform's linker directly, because clang already knows each platform's
startup files, C library and SDK locations. It uses the `clang` from the LLVM
installation the compiler was built with when there is one, and otherwise
the first `clang` on your `PATH`.

Every program is linked with:

- **Linux:** the C library, which clang adds.
- **macOS:** `libSystem`, which contains the C library, plus the SDK and
  platform-version flags. clang adds all of these, using the Xcode Command
  Line Tools.
- **Windows:** the Microsoft C runtime (the UCRT, `vcruntime` and the CRT
  startup library), which clang adds, plus `kernel32`, `user32` and `shell32`,
  which the Pepper compiler adds. clang finds the Visual Studio and Windows SDK
  libraries itself, so you do not need a Developer Command Prompt.

Any library file named `lib<name>.a` in the runtime directory is linked too.

Anything else must be linked explicitly. On Linux, that includes the math
library (`m`) for functions such as `pow`, and `pthread` on older systems.

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
`[Link]` libraries alike, in the order given, before the default ones.

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

## Output files

With no `-o`, the executable is named after the first source file, without an
extension, in the directory where you run the compiler. Windows will not run a
file without `.exe`, so pass `-o main.exe` there. The object files and other
intermediate files go in `.pep/build/` under the current directory, or in the
directory you pass to `--build`: one object per file of the program in
`<name>.units/`, and `<name>.o`, which runs the program's global
initializers. Unchanged objects come from the build cache in `.pep/cache/`
(`--no-cache` skips it).
