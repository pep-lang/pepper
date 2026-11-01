# Getting started

This chapter installs Pepper on your machine, compiles and runs a first
program, and sets up your editor.

## Install Pepper

Each release has the Pepper toolchain prebuilt for Linux, macOS and Windows.
One command installs it:

```sh
# Linux and macOS
curl -fsSL https://raw.githubusercontent.com/pep-lang/pepper/main/scripts/install.sh | sh
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/pep-lang/pepper/main/scripts/install.ps1 | iex
```

It installs into `~/.pepper` (`%LOCALAPPDATA%\pepper` on Windows), adds its
`bin` folder to your `PATH`, and offers to install what linking a program
needs when it is missing: clang on Linux, Xcode's command line tools on
macOS, LLVM and the Visual Studio Build Tools on Windows. Open a new terminal
afterwards. [Installing Pepper](../tools/install.md) covers the options, what
it installs, and uninstalling.

## Building from source

To work on Pepper itself, or on a platform with no prebuilt binaries, build
the toolchain from source: see
[Building Pepper from source](../contributing/building.md).

## Your first program

Pepper source files end in `.pep`. Create a file named `hello.pep`:

```pepper
{{#include ../../examples/tutorial-hello.pep}}
```

Every program starts at `main`, which here takes no arguments and returns an
`int` (it can also take the command-line arguments; see
[Functions](../language/functions.md#command-line-arguments-and-exit)):
the process's exit code, where 0 means success. `print` writes a value's text to
standard output, followed by a new line. Comments start with `#` and run to
the end of the line.

## Compile and run it

Pass the source file to `pepper build`. It compiles and links a native executable,
but does not run it, so run the result yourself:

```sh
pepper build hello.pep
./hello
```

```text
Hello, world!
```

The executable is written to the current directory, named after the source
file: `hello` for `hello.pep`, and `hello.exe` on Windows, where you run it as
`.\hello.exe`. Name it yourself with `-o`.

### Running a program

To build and run in one step, as `python hello.py` does, use `pepper run`.
It keeps the executable out of your folder, and runs it again at once when
nothing changed:

```sh
pepper run hello.pep
```

Arguments after the file go to the program's `main`; see
[Running a program: pep-run](../tools/pep-run.md).

### Starting a project

A program bigger than one file is a project: a folder with a
[`pep.toml`](../tools/projects.md) that names it and lists the packages it
uses. `pepper new` starts one, with a `main.pep` and a test, so `pepper
build` and `pepper test` work in it straight away:

```sh
pepper new hello
cd hello
pepper build     # builds ./hello
pepper test      # runs its [Test] function
```

`pepper new geometry --lib` starts a package instead, and `pepper init`
starts either in the current folder; see
[Starting a project: pep-new and pep-init](../tools/pep-new.md).

### Where the compiler finds the standard library

Every program is compiled together with Pepper's standard library, the
`runtime/` folder of the repository. The compiler looks for it in this order:

1. The directory named by the `PEPPER_RUNTIME` environment variable, if it is
   set. Nothing else is searched.
2. Starting from the directory you run it from: `runtime/`, `.pep/runtime/`,
   then `../runtime/`, `../../runtime/`, and so on, up to five levels up.
3. Starting from the directory that holds the compiler executable:
   `runtime/` beside it, then in each parent directory, up to five levels up.

So an installed compiler, in `~/.pepper/bin`, finds `~/.pepper/runtime`, and
one built in `target/bin` finds the runtime of the clone it was built
from, wherever you run it. To use a different runtime, set
`PEPPER_RUNTIME` or link the runtime into a project's `.pep` folder:

```sh
mkdir .pep
ln -s /path/to/pepper/runtime .pep/runtime
```

If the compiler cannot find the runtime, it stops with an error:

```text
error: cannot find the Pepper runtime: no runtime directory near /home/me/project or the compiler; set PEPPER_RUNTIME to its path
```

The compiler also writes intermediate files to `.pep/build/` under the
directory you run it from, and keeps a build cache in `.pep/cache/`: each file
of the program (and the standard library) is compiled to its own object, and
on the next build a file whose sources did not change reuses its object
without being compiled or checked again, as long as what its imports declare
did not change either: editing a function's body recompiles that file alone,
while changing a signature also recompiles the files that import it. A file
that compiled with warnings is checked again, so its warnings print on every
build. When nothing changed, nothing is checked or linked again. The cache also
keeps the standard library checked, so a program's own files are the only ones
checked on each build. Deleting `.pep/cache/` is always safe.

## When something is wrong

The compiler reports errors the way clang does: the file, line and column,
a message, and the source line with a caret under the exact token to fix.
Store the message in a variable first, then misspell its name:

```pepper
main(): int {
    var greeting = "Hello, world!";
    print(greting);
    return 0;
}
```

The compiler reports:

```text
hello.pep:3:11: error: use of undeclared identifier 'greting'
    3 |     print(greting);
      |           ^~~~~~~
```

Errors are colored when the output is a terminal; set `NO_COLOR` to turn
color off. The chapter on [compiler errors](../language/compiler-errors.md)
covers them in more detail.

A failed `assert` or a `panic` at run time prints its message and stops the
program abnormally. For example, `value()` on a failed `Result` prints
`Result.value on an Err value`.

## Useful compiler options

| Option | What it does |
|---|---|
| `-o <file>` | Name the output executable (or library, with `--lib`). |
| `-O`, `-O<n>` | Optimize: `-O0` (the default) through `-O3`; `-O` alone is `-O2`. |
| `-g` | Emit debug info for gdb, lldb, Visual Studio and WinDbg. See [debugging](../tools/debugging.md). |
| `-I <dir>` | Add a directory to search for imported modules. See [modules and imports](../language/modules.md). |
| `-l <lib>`, `-L <dir>` | Link a C library, and add a folder to find it in. See [linking](../language/linking.md). |
| `-D <name>[=<value>]` | Define a [build option](../language/build-options.md). |
| `--target <triple>` | Compile for another platform; see [Cross-compiling](../language/platform-selection.md#cross-compiling). |
| `--lib static`, `--lib shared` | Build a library for C code to link. See [calling Pepper from C](../language/c-interop.md#calling-pepper-from-c). |
| `--help` | List every option. |

[The compiler: pep-build](../tools/pep-build.md) describes every option and
environment variable the compiler reads.

A program can span several files: pass the entry file, and the compiler finds
the files it imports on its own.

## Editor support

The VS Code extension adds syntax highlighting and a language server, which
reports compiler errors as you type and provides hover information,
completion, go to definition, and an outline of each file.

The packaged extension is published as a `.vsix` file on the
[pep-lang/vscode-pepper releases page](https://github.com/pep-lang/vscode-pepper/releases).
Download it and install it in VS Code with **Extensions: Install from
VSIX...** from the command palette. It runs the language server of your
Pepper toolchain, and offers to install the toolchain when there is none.

A few things are useful once it is installed:

- **Pepper: Restart Language Server** restarts the server on demand.
- Where a value is converted by an
  [`[Implicit]` constructor](../language/structs.md#implicit-conversions),
  the editor shows the call it stands for as an inlay hint (`Path(` before
  `"notes.txt"` and `)` after), and hovering the value says so. The
  `pepper.inlayHints.implicitConversions` setting turns the hints off.
- A literal passed by position shows the name of its parameter as an inlay
  hint (`resize(width: 800, height: 600)`); the
  `pepper.inlayHints.parameterNames` setting turns these off. Inside a
  call's parentheses, completion offers the parameter names to
  [name](../language/functions.md#named-arguments) (`width = `).
- Hover and go to definition also work where the compiler has not checked
  the code yet: in a generic function or method nothing calls, on a
  `match` arm's case and the names it binds (`Circle(r) => ...`), and on
  the values an enum case declares.
- The `pepper.lspPath` setting points the extension at a language server you
  built yourself (`pep-build -O tools/pep-lsp/main.pep -o
  target/pep-lsp/pep-lsp` in a checkout of the repository; see
  [The language server: pep-lsp](../tools/pep-lsp.md)). The server
  restarts whenever that file changes.

To install the extension from the branch you have checked out instead of the
release, see
[The VS Code extension](../contributing/building.md#the-vs-code-extension).

## What to read next

- [A tour of Pepper](tour.md) builds a small program step by step and shows
  the main features of the language along the way.
- The [language guide](../language/types-and-variables.md) covers each part of
  the language in depth.
- The [standard library reference](../reference/README.md) lists every
  built-in type and function.
