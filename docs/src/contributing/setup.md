# Setting up LLVM: cargo setup

The compiler links against LLVM, which cargo cannot build. `xtask`, a small
program in this repository with no dependencies, provisions it, so it works
on a fresh clone with nothing else installed:

```bash
cargo run -p xtask -- setup --devtools     # the first time
cargo setup --devtools                     # afterwards
```

The first run writes `.cargo/config.toml`, which points the build at the
LLVM it settled on (`LLVM_SYS_<major>1_PREFIX`) and defines the `cargo setup`
alias. Run it again on each new machine rather than copying that file. The
README's
[Setting up a development environment](https://github.com/justinboswell/pepper#setting-up-a-development-environment)
says what each platform needs first and how the versions are chosen.

```text
cargo setup [options]
cargo run -p xtask -- setup [options]
```

## What it does

`cargo setup` runs the platform's script (`scripts/setup-llvm.sh` on Linux
and macOS, `scripts/setup-llvm.ps1` on Windows), which:

- provisions LLVM, cheapest source first: an LLVM of the wanted major that
  is already installed, else the platform's package manager (apt or
  Homebrew), else the LLVM release archive (cached, so a second run is
  free);
- writes `.cargo/config.toml`, so plain `cargo` commands build against it
  with no environment variables set;
- does nothing more when a valid install is already there.

When it provisions an LLVM other than the default (20), it prints the
`--features` flag cargo needs for it, such as
`cargo build --no-default-features --features llvm19-1`.

## Options

| Option | What it does |
| --- | --- |
| `--llvm <major>`, `--llvm=<major>` | Provision this LLVM major (18 to 22) instead of the default, 20 |
| `--devtools` | Also set up the `lldb` debugger: installed into the same prefix on Windows; on Linux and macOS, checked for, with instructions when it is missing |
| `--no-devtools` | Skip the debugger, even when `PEPPER_SETUP_DEVTOOLS` is set |
| `--no-packages` | Do not use apt or Homebrew: use an LLVM already installed, or the release archive |
| `--check` | Report what is configured and the command to build with it, changing nothing |
| `-h`, `--help` | Print the options |

Of `--devtools` and `--no-devtools`, the last one given wins. `--check` wins
over everything else. An unknown argument is an error that prints the
options and exits with status 1.

## Environment variables

| Variable | What it does |
| --- | --- |
| `PEPPER_LLVM_MAJOR` | The LLVM major to provision, as `--llvm` gives it |
| `PEPPER_SETUP_DEVTOOLS` | `1` sets up the debugger on every run, as `--devtools` does, so it can be turned on once per machine |
