# Pepper

Pepper is a compiled programming language. This repository holds the compiler,
written in Rust: the root `pepper` crate is the CLI, and the stages live in
`crates/` as `pepper-parser`, `pepper-sema`, `pepper-codegen`, `pepper-driver`,
and `pepper-support`. Codegen goes through LLVM via `inkwell`.

See [`docs/pepper.md`](docs/pepper.md) for the language itself.

## Setting up a development environment

Three steps on every platform: install Rust, install the platform
prerequisites, run the LLVM setup script. The script is the only unusual part —
`inkwell` links LLVM through `llvm-sys`, which finds LLVM by running
`<prefix>/bin/llvm-config` and matching its major version, and the LLVM builds
distributed by winget, scoop, chocolatey and the llvm.org installers do **not**
satisfy that (no `llvm-config`, no component libraries). The script installs one
that does — or, on macOS and Linux, reuses a system LLVM of the right major
version if you already have one, probing `llvm-config-22`, `llvm-config`,
`brew --prefix llvm@22`, `brew --prefix llvm` and `/usr/lib/llvm-22` in that
order and taking the first whose major version matches.

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
- `build-essential` is the load-bearing one: linking needs the libc, startup
  objects and `ld` it provides. `clang` is there as a fallback — the LLVM
  prefix normally supplies the one that drives the link, and PATH is only
  consulted when it does not.

### 3. LLVM

Recommended — with devtools, which sets up the `lldb` debugger. On Windows it
installs lldb; on macOS and Linux it checks that a usable one is present and
tells you how to get it:

```bash
pwsh -File scripts/setup-llvm.ps1 -DevTools   # Windows
./scripts/setup-llvm.sh --devtools            # macOS / Linux
```

Without devtools — on Windows, this is what saves the extra download; on macOS
and Linux it only skips the check:

```bash
pwsh -File scripts/setup-llvm.ps1             # Windows
./scripts/setup-llvm.sh                       # macOS / Linux
```

`PEPPER_SETUP_DEVTOOLS=1` in your environment is equivalent to passing the
flag, so you can opt in once per machine instead of remembering it.

Either way the script:

- makes sure LLVM 22 is available — installing the version the `inkwell`
  feature demands (currently 22.1.8) and caching the download so re-runs are
  cheap, or adopting a matching system LLVM on macOS/Linux if it finds one;
- writes `.cargo/config.toml` with `LLVM_SYS_221_PREFIX` pointing at whichever
  prefix it settled on. Cargo applies its `[env]` table to build scripts, so
  from then on plain `cargo` commands work with no shell setup, no environment
  variables, and no Developer Prompt. That file is generated and gitignored —
  re-run the script on a new machine rather than copying it;
- is idempotent: with a valid install present it only rewrites the cargo config.

When it does install LLVM itself, budget roughly **5 GB** of disk on Windows and
**12 GB** on Linux for the tree plus its cached archive, and several minutes for
the first run (822 MB to download, then extraction). It all lands outside the
repository, under `%LOCALAPPDATA%\pepper` or `~/.local/share/pepper`. If an
existing system LLVM is adopted instead, nothing is downloaded and the prefix is
wherever that LLVM already lives.

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
full path from PowerShell:

```powershell
& "$env:LOCALAPPDATA\pepper\llvm\22.1.8\bin\lldb.exe" --batch -o run `
  -k "thread backtrace" -- target/debug/pepper.exe tests/hello.pep
```

On macOS and Linux, with `lldb` on PATH:

```bash
lldb --batch -o run -k "thread backtrace" -- target/debug/pepper tests/hello.pep
```

Two real bugs in this repository were found exactly that way. Without it you
are left bisecting by `eprintln!`.

What it costs, and why it is opt-in rather than default: an extra download
(434 MB on Windows) that the build itself does not need. Platform notes:

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
cargo build                # debug binary at target/debug/pepper(.exe)
cargo build --release
cargo test --workspace
```

`--workspace` is not optional. The repository root is itself a package, so a
bare `cargo test` runs only its single integration test and **silently skips
every crate** under `crates/`. Expect about 99 passing tests and 1 ignored (a
corpus test whose fixtures need language features that are not implemented
yet).

## Run the compiler

```bash
cargo run -- --emit-ast tests/hello.pep     # parse only, dump the AST to stdout
cargo run -- tests/hello.pep --emit-llvm    # emit IR to .pep/build/hello.ll
cargo run -- tests/hello.pep                # compile + link -> ./hello
cargo run -- tests/hello.pep -o hello.exe   # choose the output name
```

The compiler produces an executable; it does not run it for you. With no `-o`
the output goes to `<cwd>/<source stem>` — so the third command leaves a `hello`
in whatever directory you invoked it from, including the repository root, where
it is not gitignored.

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
where you ran the compiler, which is gitignored.

Sample programs live in `tests/`: standalone files such as `hello.pep` and
`array.pep`, plus one `test.pep` per feature directory. Every `.pep` file under
`tests/` is part of the parser's corpus test, so adding one extends the suite
automatically.

## Platform support, honestly

- **Windows x64** is the platform the compiler is developed against and the one
  CI gates on. The full suite passes, and the CLI compiles and links programs
  that then run correctly.
- **Linux x64** builds the parser, sema and support crates; the LLVM
  provisioning is verified on CI, but a full build has not yet been confirmed
  end to end.
- **macOS** is unverified in both halves. On x86_64 the setup script has no
  prebuilt asset at all, so it needs an existing LLVM 22 (`brew install
  llvm@22`). On arm64 provisioning works but codegen does not: the driver
  initializes only the x86 LLVM target, so it cannot resolve an
  `aarch64-apple-darwin` triple. Adding arm64 means adding the `inkwell` target
  feature *and* the initialization call.

To exercise another platform from the machine you are on, use the
`platform-test` workflow:

```bash
gh workflow run platform-test.yml -f platforms=linux -f script="cargo test --workspace"
```

## When something goes wrong

`.agents/skills/build/SKILL.md` and `.agents/skills/test/SKILL.md` carry the
failure signatures this project has actually hit — LLVM discovery failures, a
Windows CRT mismatch that corrupts the heap inside LLVM, JIT symbol resolution,
and how to tell a malformed IR module from a runtime fault. Start there before
diagnosing from scratch.
