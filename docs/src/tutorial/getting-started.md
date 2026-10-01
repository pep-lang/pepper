# Getting started

This chapter gets the Pepper compiler built on your machine, compiles and runs
a first program, and sets up your editor. Pepper has no binary releases yet,
so you build the compiler from source.

## Build the compiler

The compiler is a Rust program that generates code through LLVM. Building it
takes three steps on every platform. The repository's
[README](https://github.com/justinboswell/pepper#setting-up-a-development-environment)
has the full details for each platform; this is the short version.

1. **Install Rust** with [rustup](https://rustup.rs). You need Rust 1.85 or
   newer. On Windows, use the default `x86_64-pc-windows-msvc` toolchain.

2. **Install the platform prerequisites**, which provide the C toolchain that
   links your programs:

   - **Windows:** Visual Studio 2022 or newer with the C++ workload (or the
     standalone Build Tools), and PowerShell.
   - **macOS:** the Xcode Command Line Tools: `xcode-select --install`.
   - **Linux** (Debian and Ubuntu package names):
     `sudo apt install build-essential clang curl xz-utils`.

3. **Set up LLVM.** Clone the repository, then run the setup command from its
   root:

   ```sh
   git clone https://github.com/justinboswell/pepper
   cd pepper
   cargo run -p xtask -- setup --devtools
   ```

   This installs a development build of LLVM (from apt, Homebrew, or the
   official release archive on Windows) and writes `.cargo/config.toml` so
   that plain `cargo` commands find it. `--devtools` also sets up the `lldb`
   debugger; you can leave it out. Run `cargo setup --check` at any time to see
   what is configured.

Now build the compiler:

```sh
cargo build --release
```

The compiler is `target/release/pepper` (`target\release\pepper.exe` on
Windows). To check that everything works, run the test suite with
`cargo test --workspace`.

## Your first program

Pepper source files end in `.pep`. Create a file named `hello.pep`:

```pepper
{{#include ../../examples/tutorial-hello.pep}}
```

Every program starts at `main`, which takes no arguments and returns an `int`:
the process's exit code, where 0 means success. `print` writes a value's text to
standard output, followed by a new line. Comments start with `#` and run to
the end of the line.

## Compile and run it

Pass the source file to `pepper`. It compiles and links a native executable,
but does not run it, so run the result yourself:

```sh
pepper hello.pep -o hello
./hello
```

```text
Hello, world!
```

On Windows, name the output with `.exe` (`-o hello.exe`), since Windows will
not run a file without an extension, and run it as `.\hello.exe`. Without `-o`
the executable is written to the current directory, named after the source
file with no extension (`hello` for `hello.pep`).

The examples here write `pepper`; use the path to the binary you built, or add
`target/release` to your `PATH`. From the repository root, you can also run
the compiler through cargo: `cargo run --release -- hello.pep -o hello`.

### Where the compiler finds the standard library

Every program is compiled together with Pepper's standard library, the
`runtime/` folder of the repository. The compiler looks for it in this order:

1. The directory named by the `PEPPER_RUNTIME` environment variable, if it is
   set. Nothing else is searched.
2. Starting from the directory you run it from: `runtime/`, `.pep/runtime/`,
   then `../runtime/`, `../../runtime/`, and so on, up to five levels up.
3. Starting from the directory that holds the compiler executable:
   `runtime/` beside it, then in each parent directory, up to five levels up.

So a compiler built in `target/release` finds the runtime of the clone it was
built from, wherever you run it. To use a different runtime, set
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
build. Deleting `.pep/cache/` is always safe.

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
main.pep:3:11: error: use of undeclared identifier 'greting'
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
| `-o <file>` | Name the output executable. |
| `-I <dir>` | Add a directory to search for imported modules. See [modules and imports](../language/modules.md). |
| `-l <lib>` | Link a C library. See [linking](../language/linking.md). |
| `--import <name>` | Load a module into every file of the program, like the standard library. |
| `--build <dir>` | Write intermediate files to `<dir>` instead of `.pep/build/`. |
| `-g` | Emit debug info for gdb, lldb, Visual Studio and WinDbg (a `.pdb` on Windows). See [debugging](../tools/debugging.md). |
| `-O`, `-O<n>` | Optimize: `-O0` (the default) through `-O3`; `-O` alone is `-O2`. Without it, `PEPPER_OPT_LEVEL` (`0` to `3`) when set. |
| `--emit-llvm` | Also write the generated LLVM IR to the build directory, as `<name>.ll`, optimized at the `-O` level. |
| `--emit-ast` | Parse only, and print the syntax tree instead of compiling. |
| `-v` | Print what the compiler is doing. |
| `-T time` | Print how long each stage of the compile took. |
| `-T cache` | Print how the build cache supplied each object: `hit` (its sources, and its imports' declarations, unchanged), `hit (same code)` (recompiled, same code), or `miss`. |
| `--no-cache` | Compile everything without reading or writing the build cache. |
| `--cache <dir>` | Keep the build cache in `<dir>` instead of `.pep/cache/` (also `PEPPER_CACHE_DIR`). |
| `--verify-cache` | Compile cache hits anyway and fail if their code differs from the cached object, or if skipping their bodies changes another file's code (for testing the compiler; also `PEPPER_CACHE_VERIFY=1`). |
| `--no-verify-cache` | Do not verify the cache, even with `PEPPER_CACHE_VERIFY` set. |
| `--help` | List every option. |

A program can span several files: pass the entry file, and the compiler finds
the files it imports on its own.

## Editor support

The VS Code extension adds syntax highlighting and a language server, which
reports compiler errors as you type and provides hover information,
completion, go to definition, and an outline of each file.

The packaged extension is published as a `.vsix` file on the repository's
[releases page](https://github.com/justinboswell/pepper/releases), under the
release whose tag starts with `vsix-v`. Download it and install it in VS Code
with **Extensions: Install from VSIX...** from the command palette. The
language server is bundled with the extension, so there is nothing else to
install.

A few things are useful once it is installed:

- **Pepper: Restart Language Server** restarts the server on demand.
- Where a value is converted by an
  [`[Implicit]` constructor](../language/structs.md#implicit-conversions),
  the editor shows the call it stands for as an inlay hint (`Path(` before
  `"notes.txt"` and `)` after), and hovering the value says so. The
  `pepper.inlayHints.implicitConversions` setting turns the hints off.
- Hover and go to definition also work where the compiler has not checked
  the code yet: in a generic function or method nothing calls, on a
  `match` arm's case and the names it binds (`Circle(r) => ...`), and on
  the values an enum case declares.
- The `pepper.lspPath` setting points the extension at a language server you
  built yourself (`cargo build --release -p pepper-lsp` builds
  `target/release/pepper-lsp`). The server restarts whenever that file
  changes.

To install the extension from the branch you have checked out instead of the
release, see
[VS Code extension from any branch](https://github.com/justinboswell/pepper#vs-code-extension-from-any-branch)
in the README.

## What to read next

- [A tour of Pepper](tour.md) builds a small program step by step and shows
  the main features of the language along the way.
- The [language guide](../language/types-and-variables.md) covers each part of
  the language in depth.
- The [standard library reference](../reference/README.md) lists every
  built-in type and function.
