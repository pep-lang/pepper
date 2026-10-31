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
  `MacOS`), `Linux`, `Wasi` (WebAssembly, see [below](#webassembly)),
  `IOS` or `Android` (see [iOS and Android](mobile.md)). As in C, where
  `TARGET_OS_MAC` holds on every Apple OS and `__linux__` on Android,
  `OS(Mac)` is also true on iOS and `OS(Linux)` on Android: they share
  the kernel and most of the C library, so code for macOS or Linux usually
  works there unchanged. Write `OS(Mac) && !OS(IOS)` for macOS alone, and
  `OS(Linux) && !OS(Android)` for desktop and server Linux alone.
- `Arch(...)` is true on the named processor architecture: `x64`,
  `aarch64`, or `wasm32`.
- `BuildOption(NAME)` is true when the build defines `NAME` with `-D`, and
  can be compared with a literal (`BuildOption(LOG_LEVEL) >= 2`), with
  another build option, or after arithmetic (`BuildOption(LEVEL) % 2 == 0`); see
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
a struct, an enum, a trait, an extension, a type alias, a module-scope
variable, an `import`, or a re-export. It also works on the methods inside a
struct, trait or extension, and on an enum's cases. When two declarations share a name, give them conditions that
never match on the same platform, so exactly one survives:

```pepper
{{#include ../../examples/platform-declarations.pep}}
```

The attribute goes before `export`, not after it:
`[Target(OS(Windows))] export f()`. Writing `export [Target(OS(Windows))] f()`
is a parse error.

A project's `pep.toml` takes the same conditions for the packages only some
platforms need (`[target.'OS(Windows)'.dependencies]`): a build sees them
only for a target the condition selects, so guard their imports with it
too. See [Projects: pep.toml](../tools/projects.md#targetconditiondependencies).

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
[Target(OS(Darwin))]
f(): int { return 1; }
```

```text
main.pep:1:12: error: unknown OS 'Darwin'; expected 'Windows', 'Mac', 'MacOS', 'Linux', 'Wasi', 'IOS' or 'Android'
    1 | [Target(OS(Darwin))]
      |            ^~~~~~
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
- Struct fields cannot carry `[Target(...)]` or `[BuildOption(...)]`, which
  is an error at the attribute. Select the whole struct instead, as `Cpu`
  does in the first example.

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
| `wasm32-wasip1`             | Wasi    | `wasm32`  |
| `aarch64-apple-ios`         | iOS     | `aarch64` |
| `aarch64-apple-ios-simulator` | iOS (simulator) | `aarch64` |
| `x86_64-apple-ios-simulator`  | iOS (simulator) | `x64`     |
| `aarch64-linux-android`     | Android | `aarch64` |
| `x86_64-linux-android`      | Android | `x64`     |

clang's other spellings work too: `arm64` for `aarch64`, `amd64` for
`x86_64`, any vendor, and an OS version (`arm64-apple-macosx14.0`,
`aarch64-apple-ios17.0`, `aarch64-linux-android33`). Any other triple is an
error that lists these. `wasm32-wasi`, `wasm32-unknown-wasi` and
`wasm32-unknown-wasip1` all mean `wasm32-wasip1`. The iOS and Android
targets, their versions and their SDKs are described in
[iOS and Android](mobile.md).

```sh
pepper build --target aarch64-unknown-linux-gnu main.pep -o main
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
  also finds without `--sysroot`). From another OS, copy a Linux machine's
  at the same paths: the C startup files and `libc`, `libm`, `libgcc_s`
  and the dynamic loader from `/usr/lib/x86_64-linux-gnu`, and
  `crtbegin*.o`, `crtend*.o` and `libgcc*` from
  `/usr/lib/gcc/x86_64-linux-gnu/<version>`.
- **macOS:** a macOS SDK (`MacOSX.sdk`, `xcrun --show-sdk-path` on a Mac).
  Linking reads only its `SDKSettings.json` and the library stubs in
  `usr/lib`.
- **Windows:** a directory laid out like a Visual Studio install, with the
  MSVC libraries and the Windows SDK, as
  [xwin](https://github.com/Jake-Shadle/xwin) writes it:

  ```sh
  xwin --accept-license --arch x86_64 splat --use-winsysroot-style --preserve-ms-arch-notation --output ~/winsysroot
  ```

CI links each of these from the other two (from Linux x64, macOS arm64 and
Windows x64, for `x86_64-unknown-linux-gnu`, `aarch64-apple-darwin` and
`x86_64-pc-windows-msvc`) and runs the programs on their own OS; its scripts,
`scripts/ci-export-sysroot.sh` and `scripts/ci-provision-cross.sh`, show the
setup end to end.

When the link fails, the error ends with a note naming what is missing:

```text
note: linking for 'x86_64-pc-windows-msvc' needs that platform's system libraries and LLVM's linker (lld): pass '--sysroot <dir>' or set PEPPER_SYSROOT_X86_64_PC_WINDOWS_MSVC
```

The `-m` options are read for the target: `-mcpu` is an AArch64 option
and `-march=x86-64-v3` an x86 one, and `native`, which names the CPU of the
machine you compile on, is an error for a target of another architecture.

The compiler only builds for the target; copy the executable to a machine
of that platform to run it.

## WebAssembly

`--target wasm32-wasip1` compiles to a WebAssembly module for
[WASI](https://wasi.dev) preview 1, which runtimes such as
[wasmtime](https://wasmtime.dev) run from the command line:

```sh
pep-build --target wasm32-wasip1 --sysroot /opt/wasi-sdk main.pep -o main.wasm
wasmtime run --dir . main.wasm
```

Linking needs a [wasi-sdk](https://github.com/WebAssembly/wasi-sdk) (its
sysroot holds wasi-libc and clang's builtins) and LLVM's `wasm-ld`, which the
compiler finds as it finds `lld` (also as `wasm-ld-20`). Name the SDK
directory, or its `share/wasi-sysroot`, with `--sysroot`, or set
`PEPPER_SYSROOT_WASM32_WASIP1` or `WASI_SDK_PATH`. wasi-sdk 25 is the version
tested. The program needs a runtime's `--dir` to reach a directory and
`-S inherit-env` (wasmtime) to see the environment. `Directory.temp()` is
`TMPDIR`, else `/tmp`, so grant one (`--dir /tmp`) to use it.

WASI preview 1 is a small system, and `wasm32` is a 32-bit target, so some
things work differently:

- `OS(Wasi)` code selects the WASI versions of the runtime's platform layer.
  Code written for `!OS(Windows)` also compiles for WASI, so check that it
  only calls what wasi-libc has.
- There are no threads and no stack switching: `Thread.spawn` panics, and
  so does starting tasks (`async.run`, `async.run_with`). Mutexes, channels
  and atomics still work, as long as nothing waits for another thread.
- Sockets, TLS, HTTP connections and starting processes return an
  `IoError` saying they are not supported on WASI.
- Files work through the directories the runtime grants. `Metadata` has no
  permission bits (`read_only` is false) and no creation time, and
  `set_permissions` and `set_read_only` return an error;
  `set_executable` and the `mode` of `OpenOptions` and `Directory.create`
  do nothing. Timestamps and symlinks work.
- `os` reports `OperatingSystem.Wasi`, `"wasm32"`, an empty host name and
  version, and no total memory.
- Pointers and C's `long` and `size_t` are 32 bits; see
  [32-bit targets](c-interop.md#32-bit-targets).
