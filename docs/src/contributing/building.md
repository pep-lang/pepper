# Building Pepper from source

Pepper is written in Pepper. The compiler, `pep-build`, is the Pepper
program in `tools/compiler` (also called pepc), and every other tool is a
Pepper program under `tools/`. Building them takes a Pepper compiler, so
the first one comes from a published toolchain. CI and the release build
use [stage 0](tests.md#stage-0), the build of main that `.github/stage0`
pins; for working on Pepper the newest build of main does as well. The Rust
compiler that once bootstrapped Pepper plays no part.

You need this to work on Pepper itself, or on a platform with no prebuilt
binaries. To use Pepper, [install it](../tools/install.md) instead.

## Setting up

Four steps, on every platform:

1. **The build of main.** Every merge into main that changes the compiler,
   the runtime or the tools publishes it as a prerelease named
   `x.y.z-dev` (the version in `VERSION`), which
   `pepper install list --available` lists. Install it and make it the
   default, with the [install script](../tools/install.md) on a new machine
   or with `pepper install`:

   ```bash
   sh scripts/install.sh --version 0.12.0-dev    # the -dev version listed
   pepper install add 0.12.0-dev && pepper install use 0.12.0-dev
   ```

   A prerelease is picked only by its exact name, never by `update` or
   `latest`. `pepper install add --force <version>` refreshes it.

   This is the newest build of main, which may be newer than stage 0, the
   build CI and the release build the compiler with
   ([Stage 0](tests.md#stage-0)). Runtime code must build with stage 0
   too, so before a change to `runtime/` or `tools/compiler/` merges,
   `scripts/stage0-check.sh` installs stage 0 and checks it.

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
   One command provisions it (every option is in
   [Setting up LLVM](setup.md)):

   ```bash
   ./scripts/setup-llvm.sh --devtools            # macOS / Linux
   pwsh -File scripts/setup-llvm.ps1 -DevTools   # Windows
   ```

4. **The packages.** `tools/compiler` depends on
   `pep-lang/pepper-llvm`, `tools/pep-lsp` on `pep-lang/pepper-lsp`, and
   `tools/pep-package` on `pep-lang/pepper-semver`. The first build of
   each fetches its package into the tool's `.pep/deps`, with the
   `pep-package` beside the compiler or on the `PATH`, or with git at the
   commit `pep.lock` records when there is none. So `pep-package` itself
   builds before any `pep-package` exists; the release build fetches all
   three with stage 0's.

### Where LLVM comes from

On macOS and Linux your package manager has an LLVM 20 and the script uses
it:

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

The script records the prefix it settled on in `.pep/llvm-prefix`
(gitignored), which the test, release and CI scripts read (a git worktree
reads its main checkout's). Re-run it on a new machine rather than copying
that file. With a valid install present it only rewrites the file, and
`./scripts/setup-llvm.sh --check` reports what it would use, changing
nothing.

CI provisions LLVM with `scripts/ci-provision-llvm.sh`, through
`.github/actions/provision-llvm`. On Linux, apt's 89 MB of packages come
from the runner's Ubuntu mirror, which on a slow day took longer than the
step's 15 minutes, so the action caches the `.deb` files apt downloaded
(keyed on `scripts/setup-llvm.sh` and the Ubuntu release) and the script
puts them in apt's archive, so apt downloads none it already has. A miss,
or a set the image has moved past, downloads from the mirror, retrying a
download that stalls for 30 seconds, and refills the cache; only main's
runs save it, under a new key, so the newest set is the one restored.

Only the Windows archive path is large: budget roughly **5 GB** of disk for
the tree plus its cached archive, and a few minutes for the first run.
Everything lands outside the repository, under `%LOCALAPPDATA%\pepper` or
`~/.local/share/pepper`, except a package-manager prefix, which stays
wherever apt or brew put it.

### The debugger

`--devtools` sets up the `lldb` debugger, and is worth it: a compiler that
generates and links native code fails in native ways, an access violation
or SIGSEGV from inside LLVM or the code it generated, and `lldb` turns that
into a symbolized stack. On Windows it installs `lldb`, `lldb-dap` and
`lldb-server` into the LLVM prefix (an extra 335–434 MB), extracting them
from the llvm.org installer with 7-Zip and placing the embeddable Python
that `liblldb.dll` needs beside them. On macOS and Linux it checks for a
usable `lldb` and says how to install one if there is none.
`PEPPER_SETUP_DEVTOOLS=1` turns it on for every run.

Build the compiler with `-g` for its own frames, then:

```bash
lldb --batch -o run -k "thread backtrace" -- target/bin/pep-build tests/hello.pep
```

On Windows the setup script leaves the `PATH` alone, so run
`"$env:LOCALAPPDATA\pepper\llvm\20.1.8\bin\lldb.exe"` by its full path.
[Debugging](../tools/debugging.md) covers debugging Pepper programs.

## Building

Build the compiler from `tools/compiler` with the installed toolchain,
against this checkout's runtime, then every tool with the compiler you
built. Each tool is a project: its `tools/<tool>/pep.toml` adds `tools/` to
the import search path, for the modules the tools share, and names the
packages it depends on. On macOS and Windows the compiler's link needs
LLVM's library folder (`-L`), and on Windows its `LLVM-C.dll` beside it:

```bash
export PEPPER_RUNTIME="$PWD/runtime"
llvm="$(head -1 .pep/llvm-prefix)"
mkdir -p target/bin
pepper build -O tools/compiler/main.pep -o target/bin/pep-build    # + -L "$llvm/lib" on macOS and Windows
# Windows: cp "$llvm/bin/LLVM-C.dll" target/bin/
for tool in pepper pep-fmt pep-test pep-package pep-profile pep-run pep-new pep-init pep-install pep-doc pep-lsp; do
  target/bin/pep-build -O "tools/$tool/main.pep" -o "target/bin/$tool"
done
```

(`.exe` names on Windows.) The release build (`scripts/release-build.sh`)
does the same with stage 0, then builds the compiler once more with itself,
and ships that one. A cold build of the compiler takes several minutes; the
[build cache](../tools/pep-build.md#the-build-cache) makes a rebuild after
an edit take seconds.

CI builds the compiler with `scripts/ci-build-compiler.sh`, which
`scripts/stage0-check.sh` also runs. It reads two environment variables:

- `PEPPER_COMPILER_DIR`: the folder of the `pep-build` to build with, which
  `scripts/ci-install-toolchain.sh` names after installing stage 0. The
  script then sets it to the new compiler's folder (through `$GITHUB_ENV`
  in a workflow, else on standard output), so later steps test with it.
- `PEPPER_TARGET_DIR`: the folder that stands for `target/`; the compiler
  goes in its `compiler/` folder, with a build cache of its own.

On macOS and Windows it finds LLVM as `scripts/pepper-tests.sh` does
(`PEPPER_LLVM_PREFIX`, else `.pep/llvm-prefix`).

## Testing

The tests are Pepper `[Test]` functions, run by `scripts/pepper-tests.sh`
as CI runs them; there is no `cargo test`.

```bash
scripts/pepper-tests.sh                      # with the installed build of main
scripts/pepper-tests.sh target/bin           # with the compiler you built
PEPPER_OPT_LEVEL=2 scripts/pepper-tests.sh   # every build the tests make at -O2
WASI_SDK_PATH=/opt/wasi-sdk WASMTIME=/opt/wasmtime/wasmtime scripts/pepper-tests.sh
```

The last also builds the docs examples and the corpus for `wasm32-wasip1`
and runs them under [wasmtime](https://wasmtime.dev), except those that
need threads, tasks, sockets or processes; without a
[wasi-sdk](https://github.com/WebAssembly/wasi-sdk) those tests say they
skipped and pass, except under CI on Linux, which provisions both. [Testing the runtime and the compiler](tests.md) says
what runs and where new tests go. Before a pull request, also run what CI
checks:

```bash
target/pepper-tests/bin/pep-doc check        # the reference and the tools' pages are current
target/pepper-tests/bin/pep-fmt --check runtime tools
```

`AGENTS.md`, at the repository's root, holds the rules every change
follows, for people and agents alike: the reference-counting model, how
errors are reported, naming, formatting, and which docs a change must
update. `INTERNALS.md` is the map of the compiler: where each stage lives
and the patterns it follows. `.agents/skills/` holds step-by-step
workflows (build, test, finish a PR, test another platform), and its
`build` and `test` skills carry the failure signatures this project has
hit, such as LLVM discovery and link failures and the packages'
fetch. Start there before diagnosing a failure from scratch.

## The VS Code extension

The extension lives in pep-lang/vscode-pepper and runs the toolchain's
`pep-lsp`. `scripts/install-vscode-extension.ps1` installs its newest
release. To try a server built from a branch, set `pepper.lspPath` to the
`pep-lsp` you build (see
[The language server: pep-lsp](../tools/pep-lsp.md)); the extension
restarts the server whenever that file changes.

## Platforms

- **Windows x64**, **Linux x64** and **macOS arm64** build and pass the
  suite; CI runs it on all three.
- **Cross-compiling** (`--target`): CI links from each of Linux x64, macOS
  arm64 and Windows x64 for the other two with `lld` and their system roots
  and runs the programs on their own OS. Other pairs emit their objects;
  their links are untested.
- **WebAssembly** (`--target wasm32-wasip1`) and **iOS and Android**: see
  [Platform selection](../language/platform-selection.md#webassembly) and
  [iOS and Android](../language/mobile.md).
- **macOS x86_64** is untested. LLVM 20 publishes no `macOS-X64` archive,
  so it needs Homebrew's `llvm@20`.

To exercise another platform from the machine you are on, run the
`platform-test` workflow (`gh workflow run platform-test.yml -f
platforms=linux`); the `platform-test` skill in `.agents/skills/` describes
it.
