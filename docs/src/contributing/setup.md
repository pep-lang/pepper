# Setting up LLVM: setup-llvm.sh

The compiler, `pep-build` (`tools/compiler`), links LLVM 20 through the
`pepper-llvm` package, so building it from source needs an LLVM 20
development install. The setup scripts provision one:

```bash
./scripts/setup-llvm.sh --devtools            # Linux and macOS
pwsh -File scripts/setup-llvm.ps1 -DevTools   # Windows
```

They record the LLVM they settled on in `.pep/llvm-prefix` (gitignored),
which `scripts/pepper-tests.sh`, the release scripts and the workflows read.
Run them again on each new machine rather than copying that file. [Building Pepper from source](building.md) says what each platform needs
first.

```text
scripts/setup-llvm.sh [options]
pwsh -File scripts/setup-llvm.ps1 [-DevTools] [-Force]
```

## What it does

- provisions LLVM 20, the one LLVM major Pepper builds with, cheapest source
  first: an LLVM 20 that is already installed, else the platform's package
  manager (apt `llvm-20-dev` or Homebrew `llvm@20`), else the LLVM release
  archive (cached, so a second run is free). Windows always uses the archive:
  no Windows package ships `llvm-config` and the component libraries;
- on macOS, installs Homebrew `lld@20` when LLVM's `ld64.lld` is not in the
  prefix: iOS links need it, and Homebrew's `llvm@20` no longer ships it.
  Homebrew keeps both off the PATH, so to link for iOS, put them first:
  `export PATH="$(brew --prefix lld@20)/bin:$(brew --prefix llvm@20)/bin:$PATH"`.
  In GitHub Actions the script does that itself, through `$GITHUB_PATH`, for
  the job's later steps;
- writes the prefix, one line, to `.pep/llvm-prefix` in the checkout;
- does nothing more when a valid install is already there.

## Options

`scripts/setup-llvm.sh` takes these; `--help` prints them.

| Option | What it does |
| --- | --- |
| `--devtools` | Also check for the `lldb` debugger, with instructions when it is missing |
| `--no-devtools` | Skip the debugger, even when `PEPPER_SETUP_DEVTOOLS` is set |
| `--no-packages` | Do not use apt or Homebrew: use an LLVM already installed, or the release archive |
| `--check` | Report the LLVM it would use and what `.pep/llvm-prefix` records, changing nothing; the status is 0 only when they agree |
| `-h`, `--help` | Print the options |

Of `--devtools` and `--no-devtools`, the last one given wins. An unknown
argument is an error that exits with status 2.

`scripts/setup-llvm.ps1` takes `-DevTools`, which installs `lldb`,
`lldb-dap` and `lldb-server` into the same prefix, and `-Force`, which
downloads and extracts the archive again even when a valid install is there.

## Environment variables

| Variable | What it does |
| --- | --- |
| `PEPPER_SETUP_DEVTOOLS` | `1` sets up the debugger on every run, as `--devtools` does, so it can be turned on once per machine |
| `PEPPER_LLVM_VERSION` | Provisions that LLVM (such as `20.1.8`) instead of the one the scripts pin; `llvm-package.yml` sets it to package another release |
