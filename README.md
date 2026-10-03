# Pepper

Pepper is a compiled programming language. This repository holds the compiler,
written in Rust: the root `pepper` crate is the CLI, and the stages live in
`crates/` as `pepper-parser`, `pepper-sema`, `pepper-codegen`, and `pepper-driver`. Codegen goes through LLVM via `inkwell`.

See the [Pepper book](docs/src/introduction.md) (`docs/`, rendered with mdBook; build it with `cargo run -p pepper-docgen -- serve`) for the language itself, and [`INTERNALS.md`](INTERNALS.md) for how the compiler works.

## Setting up a development environment

Three steps on every platform: install Rust, install the platform
prerequisites, run the LLVM setup script.

The LLVM step is the only unusual part. `inkwell` links LLVM through
`llvm-sys`, which finds LLVM by running `<prefix>/bin/llvm-config`, asks it
which component libraries to link, and compiles a small C shim against the
`llvm-c` headers — so it needs a full LLVM *development* install, not just
clang. On macOS and Linux your package manager has one and the script uses it:

| platform | where LLVM comes from | cost |
| --- | --- | --- |
| Linux | `apt install llvm-<major>-dev` (plus `libpolly-<major>-dev`) | 4–8s, 400–750 MB |
| macOS | `brew install llvm@<major>` | 13–17s |
| Windows | the official release archive | 800–950 MB download (896 MB for the default major) |

Windows needs the archive because nothing else on the platform works: the
llvm.org installer and the winget, scoop and chocolatey packages ship neither
`llvm-config` nor the component libraries. The script falls back to the archive
on Linux and macOS too, but only if the package manager cannot serve the
version you asked for.

That fallback is sound on Linux — verified by building and testing against an
archive-installed LLVM 22 on `ubuntu-24.04`, which apt does not carry — but is
usually unusable on **macOS**: the release tarballs are LTO builds, so their
static libraries are LLVM bitcode, and Apple's linker rejects bitcode produced
by a newer LLVM than its own (`could not parse bitcode object file … Unknown
attribute kind`). Homebrew's `llvm@<major>` is not LTO-built and works, so on
macOS install the version you want with `brew` and re-run the script. It warns
about this when it takes the archive path there.

### 1. Rust

Install via [rustup](https://rustup.rs). The workspace is edition 2024, so it
needs **Rust 1.85 or newer**; anything current is fine.

On Windows, use the default `x86_64-pc-windows-msvc` host toolchain.

### 2. Platform prerequisites

**Windows**
- Visual Studio 2022 or newer with the C++ workload (or the standalone Build
  Tools). Rust's MSVC toolchain links through it, and so does `clang` when it
  builds a Pepper executable.
- PowerShell. `pwsh` (7.x) is what the setup script is tested with; Windows
  PowerShell 5.1 also works.
- [7-Zip](https://www.7-zip.org/) — only needed for `-DevTools`, which extracts
  lldb from the llvm.org installer rather than running it.

**macOS**
- Xcode Command Line Tools: `xcode-select --install`. Linking needs the SDK,
  system headers and `ld` these provide. The `clang` that drives the link comes
  from the LLVM prefix when it has one — which it does on macOS — and only
  falls back to `clang` on PATH otherwise.

**Linux** (Debian/Ubuntu names; translate for your distro)
- `sudo apt install build-essential clang curl xz-utils`
- `build-essential` supplies the libc, startup objects and `ld` that linking
  needs. `clang` is load-bearing too: it is the link driver, and on Linux
  nothing else provides one — `llvm-<major>-dev` does not install a
  `bin/clang` into the prefix (that is the separate `clang-<major>` package),
  and the archive path deliberately omits it — so PATH is what supplies it.

### 3. LLVM

One command, the same on every platform:

```bash
cargo run -p xtask -- setup --devtools
```

`--devtools` sets up the `lldb` debugger and is recommended (see below). Drop
it to skip — on Windows that saves the extra download; on macOS and Linux it
only skips a check.

That works on a fresh clone with no LLVM installed, because `xtask` has no
dependencies: nothing in the LLVM half of the workspace has to compile first.
It writes `.cargo/config.toml`, which also defines a `cargo setup` alias, so
re-runs are just:

```bash
cargo setup --llvm 19        # provision a different major
cargo setup --check          # what is configured, and how to build it
```

Under the hood it runs the platform's script, which you can also invoke
directly — that is what CI does:

```bash
pwsh -File scripts/setup-llvm.ps1 -DevTools   # Windows
./scripts/setup-llvm.sh --devtools            # macOS / Linux
```

`PEPPER_SETUP_DEVTOOLS=1` in your environment is equivalent to passing the
flag, so you can opt in once per machine instead of remembering it.

Either way the script:

- provisions LLVM, cheapest source first: an LLVM of the wanted major that is
  already installed, else the platform's package manager, else the release
  archive (cached, so re-runs are free);
- writes `.cargo/config.toml` with `LLVM_SYS_<major>1_PREFIX` pointing at
  whichever prefix it settled on. Cargo applies its `[env]` table to build
  scripts, so from then on plain `cargo` commands work with no shell setup, no
  environment variables, and no Developer Prompt. That file is generated and
  gitignored — re-run the script on a new machine rather than copying it;
- is idempotent: with a valid install present it only rewrites the cargo config.

#### Choosing an LLVM version

The workspace builds against **LLVM 18 through 22**, selected by a cargo
feature. LLVM 20 is the default because both package managers serve it, so
after a default setup plain `cargo build` works:

```bash
cargo setup --llvm 19
cargo test --workspace --no-default-features --features llvm19-1
```

Setup prints that exact `--features` command whenever it provisions something
other than the default, and `cargo setup --check` prints it again later, so
you do not have to remember the mapping. `PEPPER_LLVM_MAJOR` works too, and
`--no-packages` forces the archive path.

Only the Windows archive path is large: budget roughly **5 GB** of disk for the
tree plus its cached archive, and a few minutes for the first run. Package
manager installs are 400–750 MB and take seconds. Everything lands outside the
repository, under `%LOCALAPPDATA%\pepper` or `~/.local/share/pepper`, except a
package-manager prefix, which stays wherever apt or brew put it.

#### Why devtools is recommended

On Windows, `-DevTools` installs `lldb`, `lldb-dap` and `lldb-server` into the
same prefix. On macOS and Linux, `--devtools` checks whether a usable `lldb` is
present and tells you how to install one if not — those platforms normally get
it from the LLVM prefix or a distro package, so the script does not install a
second toolchain.

It is worth having. A compiler that JITs and links native code fails in native
ways: an access violation or SIGSEGV with no Rust backtrace, from inside LLVM or
inside code the JIT just generated. `lldb` turns that into a symbolized stack
with source lines and frame arguments:

On Windows the setup script deliberately leaves PATH alone, so invoke it by
full path from PowerShell. The version directory is whichever one setup
installed — `20.1.8` for the default:

```powershell
& "$env:LOCALAPPDATA\pepper\llvm\20.1.8\bin\lldb.exe" --batch -o run `
  -k "thread backtrace" -- target/debug/pep-build.exe tests/hello.pep
```

On macOS and Linux, with `lldb` on PATH:

```bash
lldb --batch -o run -k "thread backtrace" -- target/debug/pep-build tests/hello.pep
```

Two real bugs in this repository were found exactly that way. Without it you
are left bisecting by `eprintln!`.

What it costs, and why it is opt-in rather than default: an extra download
(335–434 MB on Windows, depending on the major) that the build itself does not
need. Platform notes:

- **Windows** — lldb is absent from the `clang+llvm` tarball and ships only in
  the llvm.org installer, so the script extracts it with 7-Zip instead of
  running the installer, leaving the registry and system PATH untouched.
  `liblldb.dll` is also linked against one exact CPython version and the
  installer bundles no Python, so the script places Python's embeddable runtime
  next to `lldb.exe`; without it lldb aborts with `unable to find
  python311.dll`.
- **macOS / Linux** — lldb normally comes with the LLVM prefix or your distro,
  so the script reports what it found and how to install it if nothing usable
  is there, rather than installing a second toolchain.

## Build and test

```bash
cargo build                # debug compiler at target/debug/pep-build(.exe)
cargo build --release
target/release/pep-build tools/pepper/main.pep -o target/release/pepper   # pepper.exe on Windows
cargo test --workspace
```

`--workspace` is not optional. The repository root is itself a package, so a
bare `cargo test` runs only its single integration test and **silently skips
every crate** under `crates/`. A good run has `0 failed` on every
`test result:` line; nothing is ignored.

Those commands build against the default LLVM 20. For any other version, name
it — the same count should pass:

```bash
cargo test --workspace --no-default-features --features llvm18-1
```

PR CI tests only the default LLVM. Pushing a release tag runs the suite on
Linux against every LLVM apt offers (18, 19 and 20 on `ubuntu-24.04`) before
the extension is packaged and the release's docs are published, and does
neither unless all pass. To check a commit before tagging it, run the same
matrix by hand:

```bash
gh workflow run llvm-versions.yml --ref main
```

On macOS, where Homebrew carries `llvm@18` through `llvm@22`,
all five pass; CI's `test-macos` job runs the suite there against LLVM 20.

### Benchmarks

`benchmarks/` holds scripts that time runtime modules against a reference
implementation, for comparing a change before and after. They need a release
build (`cargo build --release`) and Python 3:

```bash
python3 benchmarks/compress/bench.py    # compress vs the gzip command, 12 MB of text
python3 benchmarks/compress/check.py    # round trips against Python's zlib; ends "failures 0"
```

`bench.py --tool <binary>` times a tool built from another checkout instead.

## Run the compiler

The compiler is `pep-build`. `pepper`, built from `tools/pepper` as above, is
the entry point to every tool: `pepper build` runs `pep-build`, `pepper fmt`
runs `pep-fmt`, and `pepper help` lists the `pep-*` commands it finds next to
itself or on the `PATH` (see the book's
[pepper command](https://justinboswell.github.io/pepper/tools/pepper.html)).
`pepper main.pep` still runs the compiler, with a deprecation warning.
From the repository root, `cargo run --` runs `pep-build`:

```bash
cargo run -- --emit-ast tests/hello.pep     # parse only, dump the AST to stdout
cargo run -- tests/hello.pep --emit-llvm    # emit IR to .pep/build/hello.ll
cargo run -- tests/hello.pep                # compile + link -> ./hello
cargo run -- tests/hello.pep -o hello.exe   # choose the output name
cargo run -- tests/hello.pep -O            # optimize (-O2; -O0 to -O3, default -O0)
cargo run -- tests/hello.pep -g            # debug info (DWARF; CodeView and a .pdb on Windows)
cargo run -- tests/hello.pep -O --lto=off  # optimize each file alone (no link-time optimization)
cargo run -- tests/hello.pep -O -march=x86-64-v3  # generate code for a CPU (clang's -march/-mcpu/-mtune/-m<feature>)
cargo run -- tests/hello.pep --target aarch64-unknown-linux-gnu  # cross-compile; --sysroot <dir> names its libraries
cargo run -- tests/hello.pep --target wasm32-wasip1 --sysroot /opt/wasi-sdk -o hello.wasm  # WebAssembly; run with wasmtime
cargo run -- tests/hello.pep -D USE_ZLIB -D LOG_LEVEL=2  # define build options for [BuildOption] and [Target(BuildOption(...))]
cargo run -- tests/hello.pep -O --no-runtime-checks=overflow  # drop kinds of runtime check (overflow,divide,shift,bounds,null,all)
cargo run -- tests/hello.pep -T time       # print each compile stage's time
cargo run -- tests/hello.pep -T passes     # print each sema pass's time
cargo run -- tests/hello.pep -T cache      # print which objects came from the build cache
cargo run -- tests/hello.pep --verify-cache  # regenerate cache hits and check they match
cargo run -- tests/hello.pep --no-cache    # compile everything, skip the build cache
cargo run -- main.pep -L libs -l foo        # link libfoo from the folder libs
PEPPER_LIBRARY_PATH=libs cargo run -- main.pep -l foo  # the same, from the environment
cargo run -- lib.pep --lib static           # a C library: liblib.a and lib.h ([Export]ed functions)
cargo run -- lib.pep --lib shared           # liblib.so / liblib.dylib / lib.dll, and lib.h
```

The compiler produces an executable (or with `--lib`, a library and its C
header; see the book's
[Calling Pepper from C](docs/src/language/c-interop.md#calling-pepper-from-c));
it does not run it for you. With no `-o`
the output goes to `<cwd>/<source stem>` — so the third command leaves a
`hello` in whatever directory you invoked it from. At the repository root that
path is gitignored; anywhere else it is not.

Note that the default name carries **no extension**, which Windows will not
execute; pass `-o hello.exe` there. Then run it yourself:

```bash
# Windows (&& is rejected by Windows PowerShell 5.1, so keep them separate)
cargo run -- tests/hello.pep -o hello.exe
./hello.exe

# macOS / Linux
cargo run -- tests/hello.pep
./hello
```

Both print `Hello world!`. Intermediate artifacts land in `.pep/build/` next to
where you ran the compiler, which is gitignored. Each file (each import cycle,
and the runtime as one) becomes its own object, and `.pep/cache/` keeps them:
a file whose sources did not change, and whose imports' declarations did
not change, is not compiled again (its bodies are not even checked), and one
whose generated code did not change is not emitted again. Editing a function
body recompiles only that file: the files importing it are reused. A file
whose text did not change is not even parsed again, and when nothing changed
the compiler checks nothing and does not link again. Delete
`.pep/cache/` to clear it, or move it with `--cache <dir>` or
`PEPPER_CACHE_DIR`. The optimization level, target CPU and removed runtime checks are part of every object's key, so
switching between `-O0` and `-O2` never reuses the other level's objects.

Integer overflow, division by zero, an oversized shift, an index out of
range and a call through a null reference panic at run time, at every
optimization level. `--no-runtime-checks=<list>` removes the kinds a build
names (`overflow`, `divide`, `shift`, `bounds`, `null`, or `all`) from `-O1`
up; at `-O0` it is ignored with a warning. Removing `bounds` or `null` gives
up memory safety (see the book's
[Integer overflow](docs/src/language/types-and-variables.md#integer-overflow)).

`-O` runs LLVM's standard `default<O2>` pipeline (what clang runs at `-O2`)
over each file's object; `-O1` and `-O3` run theirs. At `-O2` and `-O3` the
compiler also optimizes the program as a whole once every file is compiled
(link-time optimization), so a call into another file, the runtime
included, can inline; `--lto=off` optimizes each file alone, which links
sooner. The code runs on any machine of its target: clang's default CPU
for it (`x86-64`; `apple-m1` on Apple arm64), unless `-march`, `-mcpu`,
`-mtune` or `-m<feature>` (`-mavx2`, `-mno-avx2`) say otherwise, with
clang's meanings; `-march=native` targets the machine compiling.
`PEPPER_OPT_LEVEL=2` makes `-O2` the default, for the compiler
and for the JIT the tests run, so the whole suite can run optimized:

```bash
PEPPER_OPT_LEVEL=2 cargo test --workspace
```

With a [wasi-sdk](https://github.com/WebAssembly/wasi-sdk) and
[wasmtime](https://wasmtime.dev), the suite also builds every docs example
and corpus fixture for `wasm32-wasip1` and runs it under wasmtime (except
those needing threads, tasks, sockets or processes, listed as `NOT_ON_WASI`
in each test). Without them those tests print why they skipped and pass:

```bash
WASI_SDK_PATH=/opt/wasi-sdk WASMTIME=/opt/wasmtime/wasmtime cargo test --workspace
```

`-g` emits debug info: DWARF 4 on Linux and macOS, CodeView on Windows,
where the linker writes `<output>.pdb` beside the executable. Break on a
`file:line`, step, print a backtrace and inspect variables in gdb
(`gdb ./hello`), lldb (`lldb ./hello`, or `lldb-dap` in VS Code), or Visual
Studio and WinDbg (open the `.exe`). Formatters in `runtime/debuggers/` show
`String`, `Array` and `Optional` naturally: gdb loads them from the program
(`gdb -iex "add-auto-load-safe-path ." ./hello`), Visual Studio from the
`.pdb`, and lldb with `command script import runtime/debuggers/lldb_formatters.py`.
The book's [Debugging](docs/src/tools/debugging.md) chapter walks through a
session.

The compiler needs the standard library in `runtime/`. It uses the directory
named by `PEPPER_RUNTIME` when that is set, and otherwise searches near the
current directory and then near the compiler executable, so a compiler built
from this repository finds its runtime wherever you run it. When it finds none
it says so and stops. The book's
[Getting started](docs/src/tutorial/getting-started.md) chapter gives the exact
search order.

Sample programs live in `tests/`: standalone files such as `hello.pep` and
`array.pep`, plus one `test.pep` per feature directory. Every `.pep` file under
`tests/` is part of the parser's corpus test, so adding one extends the suite
automatically.

## Format Pepper code with pep-fmt

`pep-fmt` formats Pepper source in the one standard style, like `gofmt`. It
is written in Pepper (`tools/pep-fmt`), on top of a Pepper syntax library
(`tools/syntax`) that other tools can reuse. Build it with the compiler, with
`tools/` on the import path, then run it on files or directories:

```bash
cargo run --release -- -I tools tools/pep-fmt/main.pep -o pep-fmt    # pep-fmt.exe on Windows
./pep-fmt -w src/          # rewrite files that are not formatted
./pep-fmt --check src/     # list them instead; exits with 1 if there are any
./pep-fmt < file.pep       # no files: standard input to standard output
```

On a syntax error it prints a clang-style `file.pep:line:column: error: ...`
to standard error, leaves that file untouched, and exits with 1. The style it applies is described in the
book's [Formatting with pep-fmt](docs/src/tools/pep-fmt.md) chapter.

`runtime/` and `tools/` are kept formatted: `pep_fmt_sources_are_formatted`
fails when a file there is not, so run `./pep-fmt -w runtime tools` before
committing a change to them.

## VS Code extension from any branch

The released extension comes from the `vsix-v*` GitHub release, which the VSIX
workflow updates only for a release tag (`vX.Y.Z`) or a manual run on `main`
(`gh workflow run vsix.yml`). To run the extension and language server from
whatever branch is checked out, before it merges:

```powershell
scripts/install-vscode-extension.ps1          # build pep-lsp + vsix, install into VS Code
scripts/install-vscode-extension.ps1 -Watch   # follow the branch: pull and reinstall on change
```

The extension restarts its language server by itself when the installed server
changes; a change to the extension's own code needs **Developer: Reload
Window**. When editing the server, setting `pepper.lspPath` to
`target/release/pep-lsp.exe` skips the install: each
`cargo build --release -p pepper-lsp` restarts the server in place.
**Pepper: Restart Language Server** restarts it on demand. The **Pepper
Language Server** output channel logs each background analysis (the file,
how many files its program has, and how long sema took) and every request
slower than 200 ms. Code a
`[Target(...)]` attribute leaves out on the platform you build on is shown
dimmed.
`pepper.inlayHints.implicitConversions` (default on) shows the constructor
call an `[Implicit]` conversion inserts as an inlay hint, and
`pepper.inlayHints.parameterNames` (default on) shows the parameter name
before a literal argument passed by position (`width:` before `800`);
`pepper.buildOptions` lists the build options the server analyzes with, as
`-D` takes them (`["USE_ZLIB", "LOG_LEVEL=2"]`); changing any of these
restarts the server. Completion inside a call's parentheses
offers the parameter names (`width = `) of the function it calls.

Packaging (`vsce package`, run by the script and the VSIX workflow) bundles
`tools/vscode-pepper/src` and its dependencies into one file with esbuild
(`npm run bundle`, the `vscode:prepublish` script), and copies the root
`LICENSE.md` beside `package.json`.

## Platform support, honestly

- **Windows x64** is the platform the compiler is developed against and the one
  CI gates on. The full suite passes, and the CLI compiles and links programs
  that then run correctly.
- **Linux x64** works end to end: the suite passes against LLVM 18, 19 and 20
  from apt, and `cargo run -- tests/hello.pep -o hello && ./hello` prints
  `Hello world!` on `ubuntu-24.04`.
- **macOS arm64** works end to end: the suite passes against Homebrew LLVM 18
  through 22, and `cargo run -- tests/hello.pep -o hello && ./hello` produces
  a `Mach-O 64-bit executable arm64` that prints `Hello world!`. Codegen
  registers both the x86 and AArch64 LLVM backends on every host
  (`crates/pepper-codegen/src/target.rs`), so the LLVM it builds against
  needs both (apt's, Homebrew's and the official Windows archive all have
  them). Registering only x86, as it once did, broke every CLI invocation on
  Apple silicon with *"No available targets are compatible with triple
  arm64-apple-darwin"* while the suite stayed green, because inkwell's JIT
  registers the host backend as a side effect and whichever test did that
  first masked the problem for the others.
- **Cross-compiling** (`--target`): Linux x64 to Linux arm64 links with
  `lld` and Ubuntu's `libc6-dev-arm64-cross` and runs under `qemu-aarch64`.
  Every other pair emits its objects; linking them needs that platform's
  sysroot (`--sysroot`), which is untested so far.
- **WebAssembly** (`--target wasm32-wasip1`): links with `wasm-ld` and
  wasi-sdk 25 (`--sysroot` or `WASI_SDK_PATH`) and runs under wasmtime.
  Tested on Linux x64 with LLVM 20: the docs examples and the corpus pass
  except those that need threads, tasks, sockets or processes, which WASI
  preview 1 lacks (run them with `WASI_SDK_PATH`, see Build and test).
- **macOS x86_64** is untested. Homebrew serves it, which is the path that
  works on macOS anyway; of the supported majors only LLVM 19 publishes a
  `macOS-X64` archive, and the fallback reports that the version has no build
  for this platform rather than attempting a download.

To exercise another platform from the machine you are on, use the
`platform-test` workflow:

```bash
gh workflow run platform-test.yml -f platforms=linux -f script="cargo test --workspace"
```

It can also skip LLVM provisioning entirely (`-f provision=false`), which is
how `scripts/probe-llvm-packages.sh` reports what a bare runner image can
install and whether the result actually builds.

## When something goes wrong

`.agents/skills/build/SKILL.md` and `.agents/skills/test/SKILL.md` carry the
failure signatures this project has actually hit — LLVM discovery failures, a
Windows CRT mismatch that corrupts the heap inside LLVM, JIT symbol resolution,
and how to tell a malformed IR module from a runtime fault. Start there before
diagnosing from scratch.

## License

Pepper is licensed under the [Apache License 2.0](LICENSE.md).
