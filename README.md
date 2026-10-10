# Pepper

Pepper is a compiled programming language, written in Pepper. This repository
holds the toolchain: the compiler, `pep-build` (`tools/compiler`, also called
pepc), which generates code through LLVM (the `pepper-llvm` package's
bindings to LLVM's C API); the standard library (`runtime/`); and the tools,
each a Pepper program under `tools/`: `pepper`, the entry point; `pep-fmt`;
`pep-test`; `pep-package`; `pep-install`; `pep-profile`; `pep-lsp`, the
language server; and `pep-doc`, the book builder.

See the [Pepper book](docs/src/introduction.md) (`docs/`, rendered with mdBook; build it with `pep-doc serve`) for the language itself, and [`INTERNALS.md`](INTERNALS.md) for how the compiler works.

## Install

Each release has the toolchain prebuilt for Linux (x64), macOS (arm64, x64)
and Windows (x64). An install script downloads the right archive, checks its
SHA-256, unpacks it into `~/.pepper` (`%LOCALAPPDATA%\pepper` on Windows),
puts its `bin` on the `PATH`, checks that programs can be linked, and builds
and runs a small program to prove the install works.

### Prerequisites

Pepper needs no LLVM development install. It does link
programs with `clang`, which needs the platform's linker and C library:

| Platform | Needs | The script offers to install it with |
| --- | --- | --- |
| Linux | glibc 2.28 or newer (RHEL 8, Debian 10, Ubuntu 18.10 and later; not musl/Alpine), `clang` and the C library's development files | `apt-get install clang build-essential`, `dnf`/`yum install clang gcc glibc-devel`, `pacman -S clang gcc` or `zypper install clang gcc glibc-devel` |
| macOS | Xcode's command line tools | `xcode-select --install` |
| Windows | LLVM (`clang`), and the MSVC libraries and Windows SDK | `scoop`, `winget` or `choco install llvm`, else LLVM's own installer; the Visual Studio Build Tools' C++ workload with `winget` |

The script asks before installing anything (`--yes` / `-Yes` skips asking;
with no terminal it installs nothing and says what is missing). Programs
that use the `tls` module also need OpenSSL 3 (`libssl.so.3` on Linux,
Homebrew's `openssl@3` on macOS; Windows uses SChannel). The macOS binaries
are not signed; the script clears the quarantine flag.

### Running the script

While the repository is private, the release downloads need a GitHub token
that can read it, and so does the raw script URL. With the
[GitHub CLI](https://cli.github.com) signed in:

```sh
# Linux, macOS
gh api repos/justinboswell/pepper/contents/scripts/install.sh -H "Accept: application/vnd.github.raw" > install.sh
GITHUB_TOKEN=$(gh auth token) sh install.sh
```

```powershell
# Windows (PowerShell)
gh api repos/justinboswell/pepper/contents/scripts/install.ps1 -H "Accept: application/vnd.github.raw" > install.ps1
$env:GITHUB_TOKEN = gh auth token
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Once the repository is public, these one-liners do the same:

```sh
curl -fsSL https://raw.githubusercontent.com/justinboswell/pepper/main/scripts/install.sh | sh   # Linux, macOS
```

```powershell
irm https://raw.githubusercontent.com/justinboswell/pepper/main/scripts/install.ps1 | iex       # Windows
```

Then open a new terminal and check it with `pepper --version`.

Toolchains install side by side. Use `pepper install update` to move to the
newest release, `pepper install add 0.3` and `pepper install use 0.3.0` to
keep and pick others, and `toolchain = "0.3"` in a project's `pep.toml` to
pin the one it builds with (see
[Toolchains: pep-install](docs/src/tools/pep-install.md)).

Common options (`install.sh` / `install.ps1`):

- `--version <x.y.z>` / `-Version`: install that release instead of the newest.
- `--prefix <dir>` / `-Prefix`: install somewhere other than `~/.pepper`
  (or set `PEPPER_HOME`).
- `--no-modify-path` / `-NoModifyPath`: leave the `PATH` alone.
- `--no-prerequisites` / `-NoPrerequisites`: skip the linking checks.
- `--uninstall` / `-Uninstall`: remove the install and its `PATH` entries.

Every option, the install layout and how releases are built
(`.github/workflows/release.yml`) are in the book's
[Installing Pepper](docs/src/tools/install.md). The rest of this file is for
building Pepper from source.

## Setting up a development environment

Pepper is written in Pepper: the compiler, `pep-build`, is `tools/compiler`
(also called pepc), and every other tool is a Pepper program under `tools/`.
Building them from source takes a Pepper compiler, so the first one comes
from a published toolchain (stage 0), the same way the release build gets
its own. Four steps on every platform:

1. **A published toolchain.** Install the build of main, the prerelease
   named by the version in `VERSION` (`0.4.0-dev`), with the install script
   (see [Install](#install)):

   ```bash
   sh scripts/install.sh --version 0.4.0-dev
   ```

   ```powershell
   .\scripts\install.ps1 -Version 0.4.0-dev
   ```

   Every merge into main that changes the compiler, the runtime or the tools
   publishes it again; run the install again to refresh it.

2. **Platform prerequisites**, for linking:

   - **Windows**: Visual Studio 2022 or newer with the C++ workload (or the
     standalone Build Tools), which `clang` links through; PowerShell (`pwsh`
     7.x is what the setup script is tested with; Windows PowerShell 5.1 also
     works); and [7-Zip](https://www.7-zip.org/), only for `-DevTools`, which
     extracts lldb from the llvm.org installer rather than running it.
   - **macOS**: the Xcode Command Line Tools (`xcode-select --install`), for
     the SDK, system headers and `ld`. The `clang` that drives the link comes
     from the LLVM prefix when it has one, which it does on macOS.
   - **Linux** (Debian/Ubuntu names): `sudo apt install build-essential clang
     curl xz-utils`. `clang` is the link driver, and on Linux nothing else
     provides one: `llvm-20-dev` installs no `bin/clang` into its prefix.

3. **LLVM 20.** The compiler links LLVM through the `pepper-llvm` package,
   which binds LLVM 20, so building it needs an LLVM 20 development install.
   One command provisions it:

   ```bash
   ./scripts/setup-llvm.sh --devtools            # macOS / Linux
   pwsh -File scripts/setup-llvm.ps1 -DevTools   # Windows
   ```

4. **The private packages.** `tools/compiler` depends on
   `justinboswell/pepper-llvm` and `tools/pep-lsp` on
   `justinboswell/pepper-lsp`. The first build of each fetches its package
   with git into the tool's `.pep/deps`, so your git needs read access to
   those repositories.

The LLVM step is the only unusual part. On macOS and Linux your package
manager has an LLVM 20 and the script uses it:

| platform | where LLVM comes from | cost |
| --- | --- | --- |
| Linux | `apt install llvm-20-dev` (plus `libpolly-20-dev`) | 4–8s, 400–750 MB |
| macOS | `brew install llvm@20` | 13–17s |
| Windows | the official release archive | 896 MB download |

Windows needs the archive because nothing else on the platform works: the
llvm.org installer and the winget, scoop and chocolatey packages ship neither
`llvm-config` nor the component libraries. The script falls back to the
archive on Linux and macOS too, but only when the package manager has no
LLVM 20.

That fallback is sound on Linux but usually unusable on **macOS**: the
release tarballs are LTO builds, so their static libraries are LLVM bitcode,
and Apple's linker rejects bitcode produced by a newer LLVM than its own
(`could not parse bitcode object file … Unknown attribute kind`).
Homebrew's `llvm@20` is not LTO-built and works, so on macOS install it with
`brew` and re-run the script. It warns about this when it takes the archive
path there.

`--devtools` sets up the `lldb` debugger and is recommended (see below). Drop
it to skip: on Windows that saves the extra download; on macOS and Linux it
only skips a check. `PEPPER_SETUP_DEVTOOLS=1` in your environment is
equivalent to passing it, so you can opt in once per machine. Every option is
in the book's [Setting up LLVM](docs/src/contributing/setup.md).

The script:

- provisions LLVM 20, cheapest source first: one that is already installed,
  else the platform's package manager, else the release archive (cached, so
  re-runs are free);
- records the prefix it settled on, one line, in `.pep/llvm-prefix`
  (gitignored), which the test, release and CI scripts read. Re-run the
  script on a new machine rather than copying it;
- is idempotent: with a valid install present it only rewrites that file.
  `./scripts/setup-llvm.sh --check` reports what it would use, changing
  nothing.

Only the Windows archive path is large: budget roughly **5 GB** of disk for
the tree plus its cached archive, and a few minutes for the first run.
Package manager installs are 400–750 MB and take seconds. Everything lands
outside the repository, under `%LOCALAPPDATA%\pepper` or
`~/.local/share/pepper`, except a package-manager prefix, which stays
wherever apt or brew put it.

#### Why devtools is recommended

On Windows, `-DevTools` installs `lldb`, `lldb-dap` and `lldb-server` into the
same prefix. On macOS and Linux, `--devtools` checks whether a usable `lldb` is
present and tells you how to install one if not: those platforms normally get
it from the LLVM prefix or a distro package, so the script does not install a
second toolchain.

It is worth having. A compiler that generates and links native code fails in
native ways: an access violation or SIGSEGV from inside LLVM or inside the
code it generated. `lldb` turns that into a symbolized stack with source
lines and frame arguments. Build the compiler with `-g` for its own frames
(see [Build and test](#build-and-test)), then:

```powershell
& "$env:LOCALAPPDATA\pepper\llvm\20.1.8\bin\lldb.exe" --batch -o run `
  -k "thread backtrace" -- target/bin/pep-build.exe tests/hello.pep
```

On macOS and Linux, with `lldb` on PATH:

```bash
lldb --batch -o run -k "thread backtrace" -- target/bin/pep-build tests/hello.pep
```

On Windows the setup script deliberately leaves PATH alone, so invoke lldb by
full path. What it costs, and why it is opt-in: an extra download (335–434
MB on Windows) that the build itself does not need. Platform notes:

- **Windows**: lldb is absent from the `clang+llvm` tarball and ships only in
  the llvm.org installer, so the script extracts it with 7-Zip instead of
  running the installer, leaving the registry and system PATH untouched.
  `liblldb.dll` is also linked against one exact CPython version and the
  installer bundles no Python, so the script places Python's embeddable
  runtime next to `lldb.exe`; without it lldb aborts with `unable to find
  python311.dll`.
- **macOS / Linux**: lldb normally comes with the LLVM prefix or your
  distro, so the script reports what it found and how to install it if
  nothing usable is there.

## Build and test

Build the compiler from `tools/compiler` with the installed toolchain's
(`pepper build` runs its `pep-build`), against this checkout's runtime, then
every tool with the compiler you built. On macOS and Windows the compiler's
link needs LLVM's library folder (`-L`), and on Windows its `LLVM-C.dll`
beside it:

```bash
export PEPPER_RUNTIME="$PWD/runtime"
llvm="$(head -1 .pep/llvm-prefix)"
mkdir -p target/bin
pepper build -O -I tools tools/compiler/main.pep -o target/bin/pep-build    # + -L "$llvm/lib" on macOS and Windows
# Windows: cp "$llvm/bin/LLVM-C.dll" target/bin/
for tool in pepper pep-fmt pep-test pep-package pep-profile pep-install pep-doc pep-lsp; do
  target/bin/pep-build -O -I tools "tools/$tool/main.pep" -o "target/bin/$tool"
done
```

(`.exe` names on Windows.) The release build (`scripts/release-build.sh`)
does the same, then builds the compiler once more with itself, and ships
that one. A cold build of the compiler takes several minutes; the build
cache (`.pep/cache`, see below) makes a rebuild after an edit take seconds.

The tests are Pepper `[Test]` functions, built with the installed build of
main, as CI builds them:

```bash
scripts/pepper-tests.sh                      # the tests, with `pepper test`
scripts/pepper-tests.sh target/bin           # with the compiler you built
```

`scripts/pepper-tests.sh` builds `pepper`, `pep-test` and the other tools
with that `pep-build` and runs the runtime's and tools' tests, the
compiler's among them (see `docs/src/contributing/tests.md`).

Everything builds against LLVM 20, the one LLVM `pepper-llvm` binds.

## Run the compiler

The compiler is `pep-build`. `pepper`, built from `tools/pepper` as above, is
the entry point to every tool: `pepper build` runs `pep-build`, `pepper fmt`
runs `pep-fmt`, and `pepper help` lists the `pep-*` commands it finds next to
itself or on the `PATH` (see the book's
[pepper command](https://justinboswell.github.io/pepper/tools/pepper.html)).
`pepper main.pep` still runs the compiler, with a deprecation warning.
`pepper -C <dir> <command>` runs the command in `<dir>`, like `git -C`.
`pepper build` with no file builds the project a `pep.toml` describes, with
its dependencies, which `pepper package` adds and fetches (see the book's
[Projects: pep.toml](docs/src/tools/projects.md) and
[pep-package](docs/src/tools/pep-package.md)).
Every option and environment variable the compiler reads is described in
the book's [The compiler: pep-build](docs/src/tools/pep-build.md); the
other tools' options are in [The pepper command](docs/src/tools/pepper.md),
[pep-fmt](docs/src/tools/pep-fmt.md), [pep-profile](docs/src/tools/pep-profile.md),
[pep-install](docs/src/tools/pep-install.md), [pep-test](docs/src/tools/pep-test.md), [pep-lsp](docs/src/tools/pep-lsp.md) and [pep-doc](docs/src/tools/pep-doc.md).
From the repository root:

```bash
pep-build --emit-ast tests/hello.pep     # parse only, dump the AST to stdout (--emit-ast=json for JSON)
pep-build tests/hello.pep --emit-llvm    # print the IR instead of linking
pep-build tests/hello.pep --emit-static  # write the source with static blocks expanded to hello.static/
pep-build tests/hello.pep                # compile + link -> ./hello
pep-build tests/hello.pep -o hello.exe   # choose the output name
pep-build tests/hello.pep -O            # optimize (-O2; -O0 to -O3, default -O0)
pep-build tests/hello.pep -g            # debug info (DWARF; CodeView and a .pdb on Windows)
pep-build tests/hello.pep -g --debug-static=expanded  # ...stepping through static blocks expanded (hello.static.pep)
pep-build tests/hello.pep -O --lto=off  # optimize each file alone (no link-time optimization)
pep-build tests/hello.pep -O -march=x86-64-v3  # generate code for a CPU (clang's -march/-mcpu/-mtune/-m<feature>)
pep-build tests/hello.pep --target aarch64-unknown-linux-gnu  # cross-compile; --sysroot <dir> names its libraries
pep-build tests/hello.pep --target wasm32-wasip1 --sysroot /opt/wasi-sdk -o hello.wasm  # WebAssembly; run with wasmtime
pep-build greeter.pep --target aarch64-apple-ios --lib static  # iOS (or aarch64-linux-android); see the "iOS and Android" chapter
pep-build tests/hello.pep -D USE_ZLIB -D LOG_LEVEL=2  # define build options for [BuildOption] and [Target(BuildOption(...))]
pep-build tests/hello.pep -O --no-runtime-checks=overflow  # drop kinds of runtime check (overflow,divide,shift,bounds,null,all)
pep-build tests/hello.pep -T time       # print each compile stage's time
pep-build tests/hello.pep -T cache      # print which objects came from the build cache
pep-build tests/hello.pep --verify-cache  # regenerate cache hits and check they match
pep-build tests/hello.pep --no-cache    # compile everything, skip the build cache
pep-build main.pep -L libs -l foo        # link libfoo from the folder libs
PEPPER_LIBRARY_PATH=libs pep-build main.pep -l foo  # the same, from the environment
pep-build lib.pep --lib static           # a C library: liblib.a and lib.h ([Export]ed functions)
pep-build lib.pep --lib shared           # liblib.so / liblib.dylib / lib.dll, and lib.h
```

(`pep-build` is `target/bin/pep-build`, or `pepper build` for the installed
one.) The compiler produces an executable (or with `--lib`, a library and
its C header; see the book's
[Calling Pepper from C](docs/src/language/c-interop.md#calling-pepper-from-c));
it does not run it for you. With no `-o`
the output goes to `<cwd>/<source stem>`, so the fourth command leaves a
`hello` in whatever directory you invoked it from. At the repository root that
path is gitignored; anywhere else it is not.

Note that the default name carries **no extension**, which Windows will not
execute; pass `-o hello.exe` there. Then run it yourself:

```bash
# Windows (&& is rejected by Windows PowerShell 5.1, so keep them separate)
pepper build tests/hello.pep -o hello.exe
./hello.exe

# macOS / Linux
pepper build tests/hello.pep
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
`PEPPER_OPT_LEVEL=2` makes `-O2` the default, so every build the tests
make can run optimized:

```bash
PEPPER_OPT_LEVEL=2 scripts/pepper-tests.sh
```

With a [wasi-sdk](https://github.com/WebAssembly/wasi-sdk) and
[wasmtime](https://wasmtime.dev), the suite also builds the docs examples and
the corpus for `wasm32-wasip1` and runs them under wasmtime (except those
needing threads, tasks, sockets or processes, which each test lists).
Without them those tests say they skipped and pass:

```bash
WASI_SDK_PATH=/opt/wasi-sdk WASMTIME=/opt/wasmtime/wasmtime scripts/pepper-tests.sh
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

Sample programs live in `tests/`: `hello.pep`, plus one `test.pep` per
feature directory, which the compiler's corpus test
(`tools/compiler/corpus_test.pep`) builds and runs, so adding one extends the
suite automatically.

## Format Pepper code with pep-fmt

`pep-fmt` formats Pepper source in the one standard style, like `gofmt`. It
is written in Pepper (`tools/pep-fmt`), on top of the Pepper compiler's own
parser (`tools/compiler/parse`) and lexer (`tools/syntax`). Build it with the
compiler, with `tools/` on the import path, then run it on files or
directories:

```bash
pepper build -O -I tools tools/pep-fmt/main.pep -o pep-fmt    # pep-fmt.exe on Windows
./pep-fmt -w src/          # rewrite files that are not formatted
./pep-fmt --check src/     # list them instead; exits with 1 if there are any
./pep-fmt < file.pep       # no files: standard input to standard output
```

On a syntax error it prints a clang-style `file.pep:line:column: error: ...`
to standard error, leaves that file untouched, and exits with 1. The style it applies is described in the
book's [Formatting with pep-fmt](docs/src/tools/pep-fmt.md) chapter.

`runtime/` and `tools/` are kept formatted: `tools/pep-fmt/repository_test.pep`
fails when a file there is not, so run `./pep-fmt -w runtime tools` before
committing a change to them.

## Profile a program with pep-profile

`pep-profile` runs a program under a sampling profiler that is already
installed ([samply](https://github.com/mstange/samply) on any platform,
else perf on Linux or `sample` on macOS) and writes a flame graph SVG. Given
a `.pep` file it first builds it with `-O -g --frame-pointers`. It is
written in Pepper (`tools/pep-profile`):

```bash
pepper build -O -I tools tools/pep-profile/main.pep -o target/bin/pep-profile
target/bin/pep-profile main.pep          # writes main.svg
target/bin/pep-profile --pid 4242 -d 10  # a running process, for 10 seconds
```

Its options are in the book's
[Profiling with pep-profile](docs/src/tools/pep-profile.md) chapter.

## Run unit tests with pep-test

`pep-test` builds the `[Test]` functions of Pepper files with
`pep-build --test` and runs each in a child process of its own, in
parallel, reporting which pass. It is written in Pepper (`tools/pep-test`)
and finds `pep-build` next to itself:

```bash
pepper build -O -I tools tools/pep-test/main.pep -o target/bin/pep-test
target/bin/pep-test src                 # every test under src/
target/bin/pep-test -f words src        # only tests whose name contains "words"
```

Writing tests is covered in the book's
[Unit tests](docs/src/language/testing.md) chapter, and the options in
[Testing with pep-test](docs/src/tools/pep-test.md).

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
Window**. The script builds the server (`tools/pep-lsp`) with the installed
toolchain's `pep-build`. When editing the server, setting `pepper.lspPath` to
`target/pep-lsp/pep-lsp.exe` skips the install: each
`pep-build -O -I tools tools/pep-lsp/main.pep -o target/pep-lsp/pep-lsp.exe`
(with `PEPPER_RUNTIME` set to the checkout's `runtime`) restarts the server
in place.
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
- **Linux x64** works end to end: the suite passes against LLVM 20 from apt,
  and `pepper build tests/hello.pep -o hello && ./hello` prints
  `Hello world!` on `ubuntu-24.04`.
- **macOS arm64** works end to end: the suite passes against Homebrew's
  `llvm@20`, and `pepper build tests/hello.pep -o hello && ./hello` produces
  a `Mach-O 64-bit executable arm64` that prints `Hello world!`. Codegen
  registers the LLVM backends of the targets it compiles for
  (`tools/compiler/codegen/target.pep`), so the LLVM it builds against needs
  them (apt's, Homebrew's and the official Windows archive all have them).
- **Cross-compiling** (`--target`): Linux x64 to Linux arm64 links with
  `lld` and Ubuntu's `libc6-dev-arm64-cross` and runs under `qemu-aarch64`.
  CI links from each of Linux x64, macOS arm64 and Windows x64 for the
  other two with `lld` and their system roots (`--sysroot`: a copy of
  glibc, the macOS SDK, the Windows SDK from `xwin`) and runs the programs
  on their own OS. Other pairs emit their objects; their links are untested.
- **WebAssembly** (`--target wasm32-wasip1`): links with `wasm-ld` and
  wasi-sdk 25 (`--sysroot` or `WASI_SDK_PATH`) and runs under wasmtime.
  Tested on Linux x64 with LLVM 20: the docs examples and the corpus pass
  except those that need threads, tasks, sockets or processes, which WASI
  preview 1 lacks (run them with `WASI_SDK_PATH`, see Build and test).
  CI's `test-linux` job runs them, with the wasi-sdk and wasmtime that
  `scripts/ci-provision-wasi.sh` installs.
- **iOS and Android** (`--target aarch64-apple-ios`,
  `aarch64-apple-ios-simulator`, `aarch64-linux-android` and their x86_64
  simulator and emulator triples): tested on an M1 Mac with Xcode 26 and
  NDK r27, where `scripts/mobile-test.sh` runs the docs examples in the
  iOS 26 simulator and an Android 16 (API 36) emulator, and the prototype
  apps in `docs/examples/mobile/` call a Pepper library from Swift and
  through JNI. Devices and the x86_64 triples only link; see the book's
  "iOS and Android" chapter.
- **macOS x86_64** is untested. Homebrew serves it, which is the path that
  works on macOS anyway; LLVM 20 publishes no `macOS-X64` archive, and the
  fallback reports that rather than attempting a download.

To exercise another platform from the machine you are on, use the
`platform-test` workflow:

```bash
gh workflow run platform-test.yml -f platforms=linux   # the Pepper tests, with the build of main
```

It runs any script you give it (`-f script=...`), and can skip LLVM
provisioning (`-f provision=false`) to see what a bare runner image has.

## When something goes wrong

`.agents/skills/build/SKILL.md` and `.agents/skills/test/SKILL.md` carry the
failure signatures this project has actually hit — LLVM discovery and link
failures, the private packages' fetch, and how to tell a malformed IR module
from a runtime fault. Start there before diagnosing from scratch.

## License

Pepper is licensed under the [Apache License 2.0](LICENSE.md).
