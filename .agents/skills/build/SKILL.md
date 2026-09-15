---
name: build
description: Build the Pepper compiler with cargo. Use when asked to build, compile, or check the project, when a build fails and you need to iterate on errors, or when LLVM/llvm-sys/inkwell linkage errors appear.
---

# Building Pepper

Pepper is a Rust workspace: root crate `pepper` (lib + `main.rs` CLI) plus the crates `pepper-parser`, `pepper-sema`, `pepper-codegen`, `pepper-support`, and `pepper-driver` under `crates/`.

## First time on a machine: provision LLVM

`pepper-codegen` and `pepper-driver` use `inkwell`, which links LLVM through `llvm-sys`. `llvm-sys` locates LLVM by running `<prefix>/bin/llvm-config` and matching its major version, so a full LLVM install tree is required — the LLVM builds from winget/scoop/chocolatey and the llvm.org installers do **not** qualify (no `llvm-config`, no component libs).

```bash
pwsh -File scripts/setup-llvm.ps1   # Windows
./scripts/setup-llvm.sh             # macOS / Linux
```

The script installs the LLVM version the `inkwell` feature demands (`llvm22-1` → LLVM 22.1.x), caches the download, and writes `.cargo/config.toml` with `LLVM_SYS_221_PREFIX`. That file is generated and gitignored; cargo's `[env]` reaches build scripts, so afterwards plain `cargo` commands work with no shell setup. Re-running is cheap and idempotent.

The install also provides `clang`, `lld`, `llc`, `lli`, and `opt` — the driver links through the prefix's `clang` (see `crates/pepper-driver/src/linker.rs`).

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
& "$env:LOCALAPPDATA\pepper\llvm\22.1.8\bin\lldb.exe" --batch -o run `
  -k "thread backtrace" -- target/debug/pepper.exe tests/hello.pep
```

The `22.1.8` in that path is the version pinned in `scripts/setup-llvm.ps1`; after a bump it is whatever that script now installs.

On macOS and Linux, with `lldb` on PATH:

```bash
lldb --batch -o run -k "thread backtrace" -- target/debug/pepper tests/hello.pep
```

## Build

```bash
cargo build              # debug → target/debug/pepper(.exe)
cargo build --release    # → target/release/pepper(.exe)
cargo check              # fast type-check; use while iterating on errors
cargo build -p pepper-parser   # single crate
```

Errors are `rustc` diagnostics in `crates/*/src` — fix top-down, since later errors are usually fallout from the first.

## When LLVM linkage breaks

Symptoms and causes worth knowing before you start guessing:

- **`No suitable version of LLVM was found ... LLVM_SYS_221_PREFIX`** — no usable install. Run the setup script. Check `<prefix>/bin/llvm-config --version` matches the major version the `inkwell` feature implies.
- **Unresolved `LLVMInitialize<Target>*` at link time** — `inkwell`'s default `target-all` feature wants initializers for every LLVM target, including ones a given LLVM build omits (`llvm-config --targets-built` lists them). The crates therefore set `default-features = false` and select only `target-x86`.
- **Random access violations inside LLVM (verifier, printer) on Windows** — LLVM's release libs are built against the *static* CRT (`DEFAULTLIB:libcmt.lib`) while Rust MSVC uses the dynamic one; two CRTs in one process corrupt the heap, and `LNK4098` warns about it. Windows therefore links `LLVM-C.dll` instead, via `inkwell`'s `llvm22-1-no-llvm-linking` feature plus `crates/pepper-codegen/build.rs`, which also copies the DLL next to the built artifacts. Don't "fix" this by re-enabling static linking.

## Upgrading LLVM

The version is pinned in three places that must agree: the `inkwell` feature (`llvm22-1`) in `crates/pepper-codegen/Cargo.toml` and `crates/pepper-driver/Cargo.toml`, `LLVM_SYS_MAJOR` in `crates/pepper-codegen/build.rs` and `LLVM_PREFIX_ENV` in `crates/pepper-driver/src/linker.rs`, and the version constants in both setup scripts.

**Then republish the CI packages:**

```bash
gh workflow run llvm-package.yml
```

CI installs a prebuilt minimal LLVM published as an asset on the `llvm-<version>` release (see `.github/workflows/llvm-package.yml`). Those assets are per-version, so a bump leaves no package for the new one — and nothing fails loudly when that happens. `scripts/ci-provision-llvm.sh` quietly falls back to a full upstream install, which means every CI job silently starts paying a multi-gigabyte download and extraction again, and the Linux and macOS legs of `platform-test` can exhaust the runner's disk outright, which is what the package exists to avoid. The only signal is a line in the provisioning log: *"No prebuilt package published for &lt;platform&gt;"*.

Run the workflow after the pins are updated and merged: it builds from the version the setup scripts name, so it has to see the new value. The LLVM caches invalidate themselves, since their keys hash the setup scripts.

## Notes

- There is no configure step; `Cargo.toml`/`Cargo.lock` are the only build configuration.
- Never edit `Cargo.lock` by hand; change `Cargo.toml` and let cargo resolve.
