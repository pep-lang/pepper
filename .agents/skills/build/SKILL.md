---
name: build
description: Build the Pepper compiler (pepc, tools/compiler) and the Pepper tools from source. Use when asked to build, compile, or check the project, when a build fails and you need to iterate on errors, or when LLVM linkage or package-fetch errors appear.
---

# Building Pepper

Pepper is written in Pepper. The compiler, `pep-build`, is the Pepper program in `tools/compiler` (pepc); every other tool is a Pepper program under `tools/` (`pepper`, `pep-fmt`, `pep-test`, `pep-package`, `pep-install`, `pep-profile`, `pep-doc`, `pep-lsp`). Building any of them takes a `pep-build`: the first one comes from a published toolchain (stage 0).

## First time on a machine

1. **Stage 0**, the build of main, the prerelease named by `VERSION` (`0.4.0-dev`):

   ```bash
   sh scripts/install.sh --version 0.4.0-dev     # .\scripts\install.ps1 -Version 0.4.0-dev on Windows
   ```

   `pepper build` then runs its `pep-build`; `pepper install which` prints where it is (second line).

2. **LLVM 20.** pepc links LLVM through the `pepper-llvm` package, which binds LLVM 20 (`[Link("LLVM-20")]` on Linux, `LLVM` on macOS, `LLVM-C` on Windows). Provision it:

   ```bash
   ./scripts/setup-llvm.sh                       # macOS / Linux
   pwsh -File scripts/setup-llvm.ps1             # Windows
   ./scripts/setup-llvm.sh --check               # what it would use, changing nothing
   ```

   Cheapest source first: an LLVM 20 already on the machine, then the package manager (`apt install llvm-20-dev` plus `libpolly-20-dev`, 4–8s; `brew install llvm@20`), then the upstream release archive, of which only what the build consumes is unpacked. Windows always takes the archive: its image LLVM and the winget/scoop/choco packages ship neither `llvm-config` nor the component libraries. The prefix goes to `.pep/llvm-prefix` (gitignored), which `scripts/pepper-tests.sh`, the release build and CI read.

3. **The private packages.** `tools/compiler` depends on `justinboswell/pepper-llvm` and `tools/pep-lsp` on `justinboswell/pepper-lsp` (their `pep.toml`). The first build fetches each into the tool's `.pep/deps` with git, so git needs read access. Cloud sessions need both repositories attached (`add_repo`); CI uses deploy keys (`scripts/ci-package-auth.sh`).

## Build

From the repository root, against this checkout's runtime:

```bash
export PEPPER_RUNTIME="$PWD/runtime"
llvm="$(head -1 .pep/llvm-prefix)"
pepper build -O -I tools tools/compiler/main.pep -o target/bin/pep-build   # + -L "$llvm/lib" on macOS and Windows
target/bin/pep-build -O -I tools tools/pep-fmt/main.pep -o target/bin/pep-fmt
```

- Windows: name outputs `.exe`, and copy `"$llvm/bin/LLVM-C.dll"` beside `pep-build.exe` (it loads the DLL from its own folder).
- A cold build of pepc takes several minutes on 4 cores; the build cache (`.pep/cache`, or `--cache <dir>` / `PEPPER_CACHE_DIR`) makes an edit rebuild in seconds. `-T time` prints each stage's time, `-T cache` what came from the cache.
- `scripts/pepper-tests.sh [dir]` builds the other tools with the `pep-build` in `dir` (default: the installed one) into `target/pepper-tests/bin`, then runs the tests (see the **test** skill).
- The release build (`scripts/release-build.sh`) builds pepc with stage 0, then again with itself (stage 2), and builds every tool with stage 2. To check that a compiler change compiles itself, do the same: build pepc with the pepc you just built.

Errors are pepc's clang-style diagnostics (`file.pep:line:col: error: ...`). Fix top-down: later errors are usually fallout from the first.

### Debugger (opt-in)

```bash
./scripts/setup-llvm.sh --devtools            # macOS / Linux: checks for lldb
pwsh -File scripts/setup-llvm.ps1 -DevTools   # Windows: installs lldb into the prefix
```

`PEPPER_SETUP_DEVTOOLS=1` does the same once per machine. On Windows `lldb` is absent from the `clang+llvm` tarball and ships only in the llvm.org installer, so the script extracts it with 7-Zip (`winget install 7zip.7zip`); `liblldb.dll` needs one exact CPython minor, so the script drops Python's embeddable runtime beside `lldb.exe` (without it: `unable to find python311.dll`). The script leaves PATH alone, so invoke lldb by full path there. pepc accepts `-g` but emits no debug info yet, so expect symbols without source lines:

```powershell
& "$env:LOCALAPPDATA\pepper\llvm\20.1.8\bin\lldb.exe" --batch -o run `
  -k "thread backtrace" -- target/bin/pep-build.exe tests/hello.pep
```

## When the build breaks

- **`'<Name>' is not exported by 'llvm'`** (or another missing name of a package): the copy in `tools/compiler/.pep/deps` is older than `tools/compiler/pep.lock`. Refresh it: `pepper package -C tools/compiler fetch`.
- **A package fetch fails** (`Permission denied (publickey)`, `Repository not found`): git cannot read `pepper-llvm` / `pepper-lsp`. Attach the repository (cloud session) or set up access; in CI, the deploy key secret is missing.
- **`cannot find -lLLVM-20`** (Linux) or **`library 'LLVM' not found`** (macOS): no LLVM 20 on the link's search path. On Linux `llvm-20-dev` puts `libLLVM-20.so` on the default path; on macOS and Windows pass `-L "$(head -1 .pep/llvm-prefix)/lib"`.
- **`could not find native static library Polly`** or a missing `libPolly*.a` in a static link of LLVM (the release build): a Debian `llvm-20-dev` without `libpolly-20-dev`. `llvm-config --libnames --link-static` names Polly's archives whether or not they are installed, so `usable_llvm()` in `setup-llvm.sh` rejects such a prefix and installs `libpolly-20-dev`.
- **Random access violations inside LLVM on Windows**: LLVM's release static libraries are built against the static CRT; two CRTs in one process corrupt the heap. pepc therefore links `LLVM-C.dll` on Windows (pepper-llvm's `[Link("LLVM-C")]`). Don't "fix" this by linking the static libraries.
- **"No available targets are compatible with triple …"**: codegen registers the backends of the targets it compiles for (`tools/compiler/codegen/target.pep`); the LLVM it links must have them (`llvm-config --targets-built`).
- **No `clang`**: the link driver is the LLVM prefix's `clang` (`PEPPER_LLVM_PREFIX`), then one beside `pep-build`, then the PATH's (`tools/compiler/driver/linker.pep`). apt's `llvm-20-dev` has no `bin/clang`: install `clang`.

## Changing the LLVM version

LLVM 20 is pinned in: `pepper-llvm` (its bindings and `[Link("LLVM-20")]`), `LLVM_MAJOR` and `archive_version()` in `scripts/setup-llvm.sh`, `$LlvmMajor` and `$LlvmVersions` in `scripts/setup-llvm.ps1`, `LLVM_MAJOR` in `scripts/ci-provision-cross.sh`, and the `20`s of `ci.yml`'s cross-compile step. `release-build.sh`, `ci-provision-llvm.sh` and `llvm-package.yml` read the setup scripts.

Windows CI installs a prebuilt minimal LLVM published on the `llvm-<version>` release (`.github/workflows/llvm-package.yml`). A new version leaves no package, and nothing fails loudly: `scripts/ci-provision-llvm.sh` falls back to the upstream archive (~900 MB) and logs *"No prebuilt package published for &lt;platform&gt;"*. After the pins merge, publish it:

```bash
gh workflow run llvm-package.yml
```
