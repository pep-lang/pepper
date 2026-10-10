# Installing Pepper

Each release publishes the Pepper toolchain prebuilt for Linux, macOS and
Windows, with an install script that downloads the right one. You need no
Rust, cargo or LLVM development install to use it; building from source is
for working on Pepper itself (see [Getting started](../tutorial/getting-started.md#building-from-source)).

```sh
# Linux and macOS
curl -fsSL https://raw.githubusercontent.com/justinboswell/pepper/main/scripts/install.sh | sh
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/justinboswell/pepper/main/scripts/install.ps1 | iex
```

Each release also carries both scripts as assets, beside its archives.

The script:

1. picks this machine's archive (`linux-x64`, `macos-arm64`, `macos-x64` or
   `windows-x64`) from the newest release that has one;
2. downloads it and checks it against its `.sha256`;
3. unpacks it into `~/.pepper/toolchains/<version>` (`%LOCALAPPDATA%\pepper`
   on Windows), makes it the default toolchain, and puts the entry point
   `pepper` and `pep-install` in `~/.pepper/bin`; toolchains installed
   before stay (see [Toolchains: pep-install](pep-install.md));
4. adds that folder's `bin` to the `PATH`: in `~/.profile`, `~/.bashrc`,
   `~/.bash_profile` and `~/.zshrc` and fish's `conf.d`, or in the Windows
   user's `PATH`, which it asks about first;
5. checks that programs can be linked (below), offering to install what is
   missing;
6. builds and runs a small program with the new install, and fails if it
   cannot.

Open a new terminal afterwards so the `PATH` change takes effect, then
`pepper build hello.pep -o hello` works as in [Getting started](../tutorial/getting-started.md).

## What it installs

```text
~/.pepper/
  bin/
    pepper              the entry point (The pepper command), which runs a toolchain's tools
    pep-install         installs and removes toolchains (pepper install)
  toolchains/
    0.4.0/
      bin/
        pep-build       the compiler, with LLVM inside it (on Windows, LLVM-C.dll beside it)
        pep-fmt  pep-test  pep-package  pep-profile  pep-lsp  pep-doc  pepper  pep-install
      runtime/          the runtime, which pep-build finds from its own folder
      LICENSE.md
  default-toolchain     the default toolchain's version
```

`pepper` runs the tools of the toolchain a folder uses: the default, unless
`pepper +<version>`, `PEPPER_TOOLCHAIN` or the project's `pep.toml` names
another (see [Toolchains](pepper.md#toolchains)). `pepper install add`,
`use` and `update` install more and change the default; `update` also
updates `pepper` and `pep-install` themselves.

Running the script again installs the newest release beside the others
and makes it the default. An install from before toolchains, with `bin`
and `runtime` straight in `~/.pepper`, moves into `toolchains/<its
version>` first, so it stays installed. A release from before toolchains
(0.3.0 and earlier, which have no `pep-install`) installs the old way, into
`~/.pepper` itself, unless the home already holds toolchains; then it goes
into `toolchains/` like any other.

On Linux the binaries need glibc 2.28 or newer (RHEL 8, Debian 10, Ubuntu
18.10 and later); systems that use musl, such as Alpine, are not supported.
There are no prebuilt binaries for Linux or Windows on arm64 yet. The macOS
binaries are not signed: the script clears the quarantine flag, but an
archive downloaded with a browser makes Gatekeeper warn before it runs.

## What linking needs

`pep-build` compiles with the LLVM inside it, but links each program with
`clang`, which also needs the platform's linker and C library:

| Platform | Needs | The script offers |
| --- | --- | --- |
| Linux | `clang` and the C library's development files | `apt-get install clang build-essential`, `dnf`/`yum install clang gcc glibc-devel`, `pacman -S clang gcc` or `zypper install clang gcc glibc-devel`, whichever manager is present |
| macOS | Xcode's command line tools | `xcode-select --install` |
| Windows | LLVM (`clang`) and the MSVC libraries and Windows SDK | LLVM with `scoop install llvm`, `winget install LLVM.LLVM` or `choco install llvm` (the first present), else LLVM's own installer from its GitHub release; the Visual Studio Build Tools' C++ workload with `winget` |

It asks before installing anything, unless given `--yes` (`-Yes`). With no
terminal to ask on it installs nothing and says what to install.

Programs that use the `tls` module also need OpenSSL 3 (`libssl.so.3` on
Linux, Homebrew's `openssl@3` on macOS; Windows uses SChannel). The script
says so when it finds none, and on macOS offers `brew install openssl@3`.

`pep-build` looks for `clang` in this order, and uses the first it finds:

1. in the LLVM named by `PEPPER_LLVM_PREFIX`, else by
   `LLVM_SYS_<major>1_PREFIX` (`LLVM_SYS_201_PREFIX` for LLVM 20);
2. beside `pep-build` itself;
3. on the `PATH`, as `clang`, then as `clang-<major>` for the LLVM it is
   built with (what Ubuntu's `clang-20` package installs);
4. where LLVM's packages put it when they leave it off the `PATH`:
   `C:\Program Files\LLVM\bin` and Scoop's `llvm` on Windows; Homebrew's
   `llvm` and `llvm@<major>` on macOS; `/usr/lib/llvm-<major>/bin`, then the
   newest `/usr/lib/llvm-*/bin`, on Linux.

When there is none, linking fails with an error that names what to install.

## Options

```text
install.sh [--version <x.y.z> | --archive <file>] [--prefix <dir>]
           [--yes] [--no-modify-path] [--no-prerequisites]
install.sh --uninstall [--prefix <dir>]
```

| `install.sh` | `install.ps1` | What it does |
| --- | --- | --- |
| `--version <x.y.z>` | `-Version <x.y.z>` | Installs that release instead of the newest, or a prerelease such as `0.4.0-dev`, the build of main (see below), which installing again refreshes |
| `--archive <file>` | `-Archive <file>` | Installs an archive already downloaded, checked against `<file>.sha256` beside it. One not named for a release, such as a `dev` build, installs as the version its `pep-build --version` reports |
| `--prefix <dir>` | `-Prefix <dir>` | Installs into `<dir>` instead of `~/.pepper` (`%LOCALAPPDATA%\pepper`) |
| `-y`, `--yes` | `-Yes` | Installs missing prerequisites, and on Windows changes the `PATH`, without asking |
| `--no-modify-path` | `-NoModifyPath` | Leaves the `PATH` alone |
| `--no-prerequisites` | `-NoPrerequisites` | Neither checks for nor installs what linking needs |
| `--uninstall` | `-Uninstall` | Removes the install, every toolchain in it, and the `PATH` entries the script added |
| `-h`, `--help` | `Get-Help .\install.ps1` | Shows the usage |

Piped into a shell, the script still takes options: `curl ... | sh -s -- --version 0.4.0`.
`irm ... | iex` takes none, so `install.ps1` reads two environment variables
in their place:

| Variable | Instead of |
| --- | --- |
| `PEPPER_HOME` | `--prefix` / `-Prefix` (both scripts) |
| `PEPPER_VERSION` | `-Version` (`install.ps1`) |

While the repository is private, its releases need a GitHub token to
download: set `GITHUB_TOKEN` (or `GH_TOKEN`) to one that can read it, for
example `GITHUB_TOKEN=$(gh auth token)`. The raw script URLs above need it too,
so download the script with `gh` first:

```sh
gh api repos/justinboswell/pepper/contents/scripts/install.sh -H "Accept: application/vnd.github.raw" > install.sh
GITHUB_TOKEN=$(gh auth token) sh install.sh
```

## Uninstalling

```sh
sh install.sh --uninstall           # or: curl ... | sh -s -- --uninstall
```

```powershell
.\install.ps1 -Uninstall
```

This removes the install folder (only when it holds `bin/pep-build`) and the
`PATH` lines the script added. Prerequisites it installed, such as clang,
stay.

## How releases are built

The `Release` workflow (`.github/workflows/release.yml`) publishes:

- **the build of main**, on each merge into main that changes the compiler,
  the runtime or the tools: main holds the version being developed as a
  prerelease (`0.4.0-dev` in `VERSION` and each tool's `version()`), and
  the workflow publishes it on the prerelease `v0.4.0-dev`, moving its tag
  to the merge and replacing its archives. CI and the workers install it
  (`--version 0.4.0-dev`) instead of building the compiler. The newest
  release, the default, never picks a prerelease.
- **a release**, on a `vX.Y.Z` tag, made by hand: `scripts/set-version.sh
  0.4.0` sets the version everywhere a tool reads it, the commit is tagged
  `v0.4.0` (the workflow checks that it holds that version). Once it is
  published, the workflow opens a pull request that starts the next minor
  version on main (`0.5.0-dev`) and merges itself once its checks pass,
  unless main has already moved on; a major
  version is started by hand. A pull request the workflow opens with its
  own token starts no workflows, so it is opened with the
  `RELEASE_BUMP_TOKEN` secret when that is set, and otherwise the workflow
  dispatches CI on its branch.

For each platform, `scripts/release-build.sh` builds the
tools, lays them out as above, archives them as
`pepper-<version>-<target>.tar.gz` (`.zip` on Windows) with a `.sha256`, and
`scripts/release-smoke-test.sh` proves the archive works: unpacked outside the
repository with no LLVM variables set, `pepper build` must build and run a
program, and the binaries must load nothing beyond the system's C and C++
runtimes (on Linux, nothing newer than glibc 2.28: the Linux leg builds in a
`manylinux_2_28` container). The workflow then installs each archive with
the install script. Last, it uploads the archives, their checksums, a
`SHA256SUMS` and both scripts to the release. A pull request that
changes these scripts runs every leg too, without publishing.
