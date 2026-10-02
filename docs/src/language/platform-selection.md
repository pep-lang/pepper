# Platform selection

Some code only makes sense on one platform: a Windows API call, a
Linux-specific constant, a type whose size differs between operating systems.
The `[Target(...)]` attribute keeps a declaration or a block only when you
compile for a matching platform, so one source file can hold every platform's
version side by side.

The target is the platform you compile on, unless you name another with
`--target` (see [Cross-compiling](#cross-compiling) below).

## Writing a condition

`Target` takes one boolean condition built from these predicates:

- `OS(...)` is true on the named operating system: `Windows`, `Mac` (or
  `MacOS`), or `Linux`.
- `Arch(...)` is true on the named processor architecture: `x64` or `aarch64`.
- `BuildOption(NAME)` is true when the build defines `NAME` with `-D`, and
  can be compared with a literal (`BuildOption(LOG_LEVEL) >= 2`); see
  [Build options](build-options.md).

Values are matched case-insensitively, so `OS(windows)` works too. Combine
predicates with `&&` (or `and`), `||` (or `or`), `!`, and parentheses:

```pepper
[Target(OS(Windows))]                     # Windows
[Target(!OS(Windows))]                    # Linux and macOS
[Target(OS(Linux) && Arch(x64))]          # Linux on x64 only
[Target(OS(Windows) || OS(Mac))]          # Windows and macOS
[Target(!(OS(Windows) || OS(Mac)))]       # Linux
```

An item may carry several attributes. They are combined with "and": the item
is kept only when every `Target` on it matches. Other attributes on the same
item, such as `[Link(...)]`, do not affect the selection.

## What it applies to

Put `[Target(...)]` before any top-level declaration: a function, an `extern`,
a struct, a trait, an extension, a type alias, a module-scope variable, an
`import`, or a re-export. It also works on the methods inside a struct, trait
or extension. When two declarations share a name, give them conditions that
never match on the same platform, so exactly one survives:

```pepper
{{#include ../../examples/platform-declarations.pep}}
```

The attribute goes before `export`, not after it:
`[Target(OS(Windows))] export f()`. Writing `export [Target(OS(Windows))] f()`
is a parse error.

## Blocks inside a function

Inside a function body, attach `[Target(...)]` to a block `{ ... }`. The block
is kept or removed like a declaration. Blocks may nest, and may appear inside
`if` and loop bodies.

This is the usual way to wrap C functions that differ per platform: declare
each platform's `extern` with its own condition, and call each one from a
block with the same condition.

```pepper
{{#include ../../examples/platform-externs.pep}}
```

## What happens to code that does not match

Code whose condition does not match is removed before type checking. That is
what makes the examples above work: a call to `GetCurrentProcessId`, which
exists only on Windows, is fine in a block that is removed everywhere else.
Removed code is not checked for errors beyond parsing, so a typo in it goes
unnoticed until you build on the platform that keeps it. The VS Code
extension shows it dimmed, from its attribute to its end, with a hint saying
it is not compiled for the platform you are building on. A file that is
mostly code for another OS (a Linux-only file opened on Windows) is still
checked as that OS's build would check it, so hover and go-to-definition
work in it. In such a file, an error only your own platform's build would
report (portable code calling a function only the other OS has) appears
when you build, not in the editor.

It still has to parse, and every `Target` condition is validated on every
platform, even one inside removed code. A misspelled value is always an error,
never a silent "no match":

```pepper
[Target(OS(Darwin))] f(): int { return 1; }
```

```text
main.pep:1:1: error: unknown OS value `Darwin` (expected Windows, Mac, MacOS, Linux) in [Target(OS(Darwin))]
    1 | [Target(OS(Darwin))] f(): int { return 1; }
      | ^~~~~~~~~~~~~~~~~~~~
```

Other mistakes the compiler reports:

- `Target` takes exactly one condition: `[Target(OS(Windows), Arch(x64))]` is
  an error; write `[Target(OS(Windows) && Arch(x64))]`.
- Only `OS(...)`, `Arch(...)` and `BuildOption(...)` may appear inside it. A bare name
  (`[Target(Windows)]`), another call (`[Target(Foo(x))]`), `not` in place of
  `!`, or a nested `Target` is an error.
- `OS(...)` and `Arch(...)` are only valid inside `Target(...)`, and the
  brackets hold one attribute: `[OS(Windows)]` and
  `[Target(OS(Windows)) && Export]` are parse errors.
- Struct fields cannot carry `[Target(...)]`. Select the whole struct instead,
  as `Cpu` does in the first example.

## Cross-compiling

`--target <triple>` compiles for another platform: `[Target(...)]` selects
that platform's code, and the compiler emits that platform's machine code
and object format. The supported targets are each OS on each architecture:

| Triple                      | OS      | Arch      |
|-----------------------------|---------|-----------|
| `x86_64-unknown-linux-gnu`  | Linux   | `x64`     |
| `aarch64-unknown-linux-gnu` | Linux   | `aarch64` |
| `x86_64-apple-darwin`       | macOS   | `x64`     |
| `aarch64-apple-darwin`      | macOS   | `aarch64` |
| `x86_64-pc-windows-msvc`    | Windows | `x64`     |
| `aarch64-pc-windows-msvc`   | Windows | `aarch64` |

clang's other spellings work too: `arm64` for `aarch64`, `amd64` for
`x86_64`, any vendor, and an OS version (`arm64-apple-macosx14.0`). Any
other triple is an error that lists these.

```sh
pep-build --target aarch64-unknown-linux-gnu main.pep -o main
```

Linking an executable for another platform needs that platform's system
libraries and LLVM's linker, `lld`: the compiler looks for it beside clang,
in its LLVM install and on the `PATH`, also under the versioned name
Ubuntu's `lld-20` package uses (`ld.lld-20`). Name
the directory that holds the libraries (the sysroot) with `--sysroot <dir>`,
or set `PEPPER_SYSROOT_<TRIPLE>`, the triple in capitals with `_` for each
`-` (`PEPPER_SYSROOT_AARCH64_APPLE_DARWIN`):

- **Linux:** a directory with the target's glibc and GCC runtime
  (`/usr/aarch64-linux-gnu` from Debian's or Ubuntu's
  `libc6-dev-arm64-cross` and `libgcc-13-dev-arm64-cross`, which clang
  also finds without `--sysroot`).
- **macOS:** a macOS SDK (`MacOSX.sdk`).
- **Windows:** a directory laid out like a Visual Studio install, with the
  MSVC libraries and the Windows SDK, as
  [xwin](https://github.com/Jake-Shadle/xwin) `splat --use-winsysroot-style`
  writes it.

When the link fails, the error ends with a note naming what is missing:

```text
note: linking for 'x86_64-pc-windows-msvc' needs that platform's system libraries and LLVM's linker (lld): pass '--sysroot <dir>' or set PEPPER_SYSROOT_X86_64_PC_WINDOWS_MSVC
```

The `-m` options are read for the target: `-mcpu` is an AArch64 option
and `-march=x86-64-v3` an x86 one, and `native`, which names the CPU of the
machine you compile on, is an error for a target of another architecture.

The compiler only builds for the target; copy the executable to a machine
of that platform to run it.
