---
name: build
description: Build the Pepper compiler with cargo. Use when asked to build, compile, or check the project, when a build fails and you need to iterate on errors, or when LLVM/llvm-sys/inkwell linkage errors appear.
---

# Building Pepper

Pepper is a Rust workspace: root crate `pepper` (lib + `main.rs` CLI) plus the crates `pepper-parser`, `pepper-sema`, `pepper-codegen`, and `pepper-driver` under `crates/`.

## First time on a machine: provision LLVM

`pepper-codegen` and `pepper-driver` use `inkwell`, which links LLVM through `llvm-sys`. `llvm-sys` locates LLVM by running `<prefix>/bin/llvm-config`, asks it which component libraries to link, and compiles a C shim against the `llvm-c` headers — so a full LLVM *development* install is required.

```bash
cargo run -p xtask -- setup      # first time: works with no LLVM installed
cargo setup                      # afterwards, via the alias setup writes
cargo setup --check              # what is configured, and how to build it
```

`xtask` is dependency-free precisely so this works on a fresh clone: `llvm-sys` fails to *compile* when no LLVM is configured (`compile_error!` in its lib.rs), and it builds before `pepper-codegen`'s build script exists — so nothing inside the build can discover LLVM in time to configure it. `cargo run -p xtask` never pulls it in. It runs the platform's script (`scripts/setup-llvm.{sh,ps1}`, also usable directly, which is what CI does) and finds a shell for it: `pwsh`, else Windows PowerShell 5.1.

Where LLVM comes from, cheapest source first: an install of the wanted major already on the machine, then the platform's package manager (`apt install llvm-<major>-dev` plus `libpolly-<major>-dev`, 4–8s; `brew install llvm@<major>`, 13–17s), then the upstream release archive, from which only the members the build consumes are unpacked. Windows always takes the archive: its image LLVM and the winget/scoop/choco packages ship neither `llvm-config` nor the component libraries.

Setup writes `.cargo/config.toml` with `LLVM_SYS_<major>1_PREFIX` plus the `cargo setup` alias, and the same prefix, one line, to `.pep/llvm-prefix`, which the scripts and workflows read (in CI it also exports `LLVM_SYS_<major>1_PREFIX` through `$GITHUB_ENV`). Both are generated and gitignored; cargo's `[env]` reaches build scripts, so afterwards plain `cargo` commands work with no shell setup. It is the *only* mechanism that reaches `llvm-sys` without shell state, which is why provisioning cannot live in a build script. Re-running is cheap and idempotent.

### LLVM version

The workspace builds against **LLVM 18–22**, chosen by a cargo feature on the root package and forwarded to `pepper-driver` and `pepper-codegen`. LLVM 20 is the default (`cargo build` needs no flag); anything else is named explicitly, and the setup script prints the command when it provisions a non-default version:

```bash
cargo setup --llvm 19                  # or PEPPER_LLVM_MAJOR=19
cargo build --release --no-default-features --features llvm19-1
```

Verified coverage: 18, 19 and 20 pass the suite on Linux — those are what `apt` on `ubuntu-24.04` serves — and all five pass on macOS, where Homebrew has `llvm@18` through `llvm@22`. Only the *Windows* archive install is a full LLVM tree with `clang`, `lld`, `llc`, `lli` and `opt`; the Unix archive path unpacks just `llvm-config`, the libraries and the `llvm-c` headers, so with either that or an apt prefix the driver falls back to `clang` on PATH (`crates/pepper-driver/src/linker.rs`). Homebrew prefixes do carry clang.

### Debugger (opt-in)

Add `lldb` for debugging native faults in the compiler or its JIT'd code:

```bash
pwsh -File scripts/setup-llvm.ps1 -DevTools   # Windows
./scripts/setup-llvm.sh --devtools            # macOS / Linux
```

`PEPPER_SETUP_DEVTOOLS=1` in the environment does the same, so it can be opted into once per machine or in CI. It is off by default because the build does not need it and it costs an extra download.

Windows specifics worth knowing, since they are not obvious: `lldb` is **absent** from the `clang+llvm` tarball and ships only in the llvm.org NSIS installer, so the script extracts it (7-Zip required — `winget install 7zip.7zip`) rather than running the installer, which keeps the registry and system PATH untouched. `liblldb.dll` is also linked against one exact CPython minor version and the installer bundles no Python, so the script drops Python's embeddable runtime next to `lldb.exe`; without it `lldb` aborts with `unable to find python311.dll`. On Unix, lldb normally lives in the same LLVM prefix or the distro package, so the script only reports what it finds.

`lldb` resolves Rust symbols, source lines, and frame arguments on these builds, which is the fastest way to localize an access violation. Since the script leaves PATH untouched (see above), invoke it by full path on Windows — a bare `lldb` only appears to work on a machine that happens to have an unrelated LLVM installed:

```powershell
& "$env:LOCALAPPDATA\pepper\llvm\20.1.8\bin\lldb.exe" --batch -o run `
  -k "thread backtrace" -- target/debug/pep-build.exe tests/hello.pep
```

The `20.1.8` in that path is the default major's version from `$LlvmVersions` in `scripts/setup-llvm.ps1`; with `-Llvm <major>` it is that major's version instead.

On macOS and Linux, with `lldb` on PATH:

```bash
lldb --batch -o run -k "thread backtrace" -- target/debug/pep-build tests/hello.pep
```

## Build

```bash
cargo build              # debug → target/debug/pep-build(.exe)
cargo build --release    # → target/release/pep-build(.exe), the compiler
cargo check              # fast type-check; use while iterating on errors
cargo build -p pepper-parser   # single crate
```

Errors are `rustc` diagnostics in `crates/*/src` — fix top-down, since later errors are usually fallout from the first.

## When LLVM linkage breaks

Symptoms and causes worth knowing before you start guessing:

- **`No suitable version of LLVM was found ... LLVM_SYS_<major>1_PREFIX`** — no usable install for the *selected* version. Either run the setup script for that major, or name the major you do have: the variable in the message tells you which one cargo is looking for.
- **`no LLVM version feature enabled`** from `build.rs` — `--no-default-features` without a `--features llvmNN-1`.
- **`could not find native static library Polly`** — a Debian `llvm-N-dev` without `libpolly-N-dev`: `llvm-config --libnames --link-static` names Polly's archives whether or not they are installed, and llvm-sys prefers static, falling back to shared only when that command *fails* rather than when the files it names are missing. So `usable_llvm()` in the setup script checks the mode llvm-sys will actually choose and rejects such a prefix, which both catches this at provisioning and makes the script install `libpolly-N-dev`. The preinstalled `/usr/lib/llvm-18` on `ubuntu-24.04` is exactly this case.
- **Unresolved `LLVMInitialize<Target>*` at link time** — `inkwell`'s default `target-all` feature wants initializers for every LLVM target, including ones a given LLVM build omits (`llvm-config --targets-built` lists them). The crates therefore set `default-features = false` and request one backend per host architecture, in the `cfg(target_arch = …)` dependency tables of `crates/pepper-{codegen,driver}/Cargo.toml`: `target-x86` on x86_64, `target-aarch64` on aarch64. `crates/pepper-codegen/src/target.rs` registers that backend and builds the machine everything emits for; registering the wrong one breaks every CLI invocation with *"No available targets are compatible with triple …"* while the suite can stay green, since inkwell's JIT registers the host backend as a side effect and whichever test does that first masks it for the rest. `target.rs`'s own unit test asks the question directly instead.
- **Random access violations inside LLVM (verifier, printer) on Windows** — LLVM's release libs are built against the *static* CRT (`DEFAULTLIB:libcmt.lib`) while Rust MSVC uses the dynamic one; two CRTs in one process corrupt the heap, and `LNK4098` warns about it. Windows therefore links `LLVM-C.dll` instead: each supported `llvm-sys` major is a windows-only optional dependency carrying `no-llvm-linking`, and `crates/pepper-codegen/build.rs` emits the DLL link and copies it next to the built artifacts. Don't "fix" this by re-enabling static linking.

## Adding or changing an LLVM version

Supported majors are listed in six places that must agree, and `inkwell` must publish a matching `llvmNN-1` feature:

- the `[features]` tables in `Cargo.toml`, `crates/pepper-driver/Cargo.toml` and `crates/pepper-codegen/Cargo.toml`, plus the windows-only `llvm-sys-<major>1` dependency in the latter two;
- `LLVM_SYS_MAJORS` in `crates/pepper-codegen/build.rs`;
- the `LLVM_PREFIX_ENV` cfg cascade in `crates/pepper-driver/src/linker.rs` — a *missing* arm stops the build at the `compile_error!` there, but an arm naming the *wrong* variable is silent: `link_driver()` just falls back to `clang` on PATH;
- `SUPPORTED_MAJORS` and `archive_version()` in `scripts/setup-llvm.sh`;
- `$LlvmVersions` **and** the `-Llvm` `[ValidateSet]` in `scripts/setup-llvm.ps1`, which rejects any major not enumerated in it.

A new *host architecture* is a separate list: the `cfg(target_arch)` inkwell tables in both crate manifests, and `initialize_host`, its `compile_error!`, and the expected-triple list in that module's test, all in `crates/pepper-codegen/src/target.rs`.

CI discovers its version matrix from `SUPPORTED_MAJORS` intersected with what apt offers, so a new major is tested as soon as both carry it.

**Republish the Windows CI package for a new default:**

```bash
gh workflow run llvm-package.yml -f llvm=20
```

Windows CI installs a prebuilt minimal LLVM published as an asset on the `llvm-<version>` release (see `.github/workflows/llvm-package.yml`); Linux and macOS install from apt or Homebrew and need no package. Those assets are per-version, so a bump leaves no package for the new one — and nothing fails loudly when that happens: `scripts/ci-provision-llvm.sh` falls back to the upstream archive, so the Windows job quietly starts paying an ~900 MB download and extraction again. The only signal is a line in the provisioning log: *"No prebuilt package published for &lt;platform&gt;"*.

Run the workflow after the pins are updated and merged: it builds from the version the setup scripts name, so it has to see the new value. The LLVM caches invalidate themselves, since their keys hash the setup scripts.

## Notes

- There is no configure step; `Cargo.toml`/`Cargo.lock` are the only build configuration.
- Never edit `Cargo.lock` by hand; change `Cargo.toml` and let cargo resolve.
