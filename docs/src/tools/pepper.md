# The pepper command

`pepper` is the entry point to every Pepper tool, the way `go` and `git`
are: `pepper <command> [arguments]` runs a separate program named
`pep-<command>` with the remaining arguments.

```bash
pepper build main.pep -o main     # runs pep-build main.pep -o main
pepper build                      # builds the project pep.toml describes
pepper fmt -w src                 # runs pep-fmt -w src
pepper -C my_app build            # runs pep-build in my_app
pepper +0.2 build                 # runs the installed 0.2.x toolchain's pep-build
pepper help                       # lists the commands it can find
pepper help build                 # runs pep-build --help
pepper --version                  # pepper's version; -v adds each command's
```

`pepper` is itself written in Pepper (`tools/pepper/main.pep`). The compiler
is the program `pep-build`, so `pepper build` takes exactly the options the
compiler does (see [The compiler: pep-build](pep-build.md)).

## Usage and options

```text
pepper [+<version>] [-C <dir>]... <command> [arguments]
pepper help [<command>]
pepper --version [-v]
```

| Form | What it does |
| --- | --- |
| `pepper <command> [arguments]` | Runs `pep-<command>` with the arguments (see [How it finds a command](#how-it-finds-a-command)) |
| `+<version>` | Runs the command with that installed toolchain, such as `+0.3.0` or `+0.3` (see [Toolchains](#toolchains)) |
| `-C <dir>` | Changes to `<dir>` before running the command (see [Running in another folder](#running-in-another-folder)) |
| `pepper help`, `-h`, `--help` | Prints the usage, these options, and the commands it can find |
| `pepper help <command>` | Runs `pep-<command> --help` |
| `--version` | Prints `pepper` and its version, and in a Pepper home the toolchain the folder uses and why |
| `--version -v`, `--version --verbose` | Also prints the version each command reports (its `--version`'s first line, or `(no version)`) |

Options go before the command: everything after the command belongs to it,
so `pepper fmt --help` is `pep-fmt --help`. `pepper` with no arguments, or
with only `-C` and `+<version>` options, prints the usage to standard error and exits with
status 2; so does a `-C` with no folder after it; an option other than
`-v` or `--verbose` after `--version` is an error that exits with 2. An
unknown command exits with 1. Otherwise the exit status is the command's.

## The commands in this repository

| Command | Program | What it does |
| --- | --- | --- |
| `pepper build` | `pep-build` | Compiles a program, or with no file the project ([The compiler: pep-build](pep-build.md), [Projects: pep.toml](projects.md)) |
| `pepper install` | `pep-install` | Installs toolchains side by side and picks the default ([Toolchains: pep-install](pep-install.md)) |
| `pepper package` | `pep-package` | Adds, removes, updates and fetches a project's dependencies ([The package manager: pep-package](pep-package.md)) |
| `pepper fmt` | `pep-fmt` | Formats source ([Formatting with pep-fmt](pep-fmt.md)) |
| `pepper profile` | `pep-profile` | Profiles a program and draws a flame graph ([Profiling with pep-profile](pep-profile.md)) |
| `pepper test` | `pep-test` | Builds and runs the `[Test]` functions ([Testing with pep-test](pep-test.md)) |
| `pepper lsp` | `pep-lsp` | Runs the language server, which editors start ([The language server: pep-lsp](pep-lsp.md)) |
| `pepper doc` | `pep-doc` | Generates the library reference and builds this book ([The documentation builder: pep-doc](pep-doc.md)) |

Every one of them but `pep-build` is a Pepper program, built with
`pep-build`; `pep-build` itself is too (`tools/compiler`).

## Building it

Build the compiler with cargo, then build `pepper` with the compiler and put
it next to it:

```bash
cargo build --release
target/release/pep-build -I tools tools/pepper/main.pep -o target/release/pepper
```

On Windows, name the output `target\release\pepper.exe`.

## How it finds a command

Outside a Pepper home, `pepper <command>` looks for `pep-<command>` (`pep-<command>.exe` on
Windows) in the directory that holds the running `pepper` first, then in
each directory on the `PATH`, and runs the first it finds. So the tools
installed next to `pepper` win over others with the same name, and any
program named `pep-<name>` on the `PATH` adds the command `<name>`: a tool of
your own becomes `pepper <name>` once it is installed. On Linux and macOS
only files with an execute permission count.

The command takes `pepper`'s place, with its standard input, output and
error: on Linux and macOS `pepper` execs it, so signals such as Ctrl-C reach
the command directly and its exit status is `pepper`'s. Windows cannot
replace a process, so there `pepper` waits for the command, leaves Ctrl-C
to it, and exits with its exit status. A command name is lowercase letters, digits, `-` and `_`;
anything else, such as a path, is not a command.

An unknown command is an error that suggests the closest command and lists
the ones `pepper` found:

```text
$ pepper buidl main.pep
pepper: error: 'buidl' is not a pepper command; did you mean 'build'?

Commands:
  build
  fmt
```

## Running in another folder

`-C <dir>` runs the command as if `pepper` had been started in `<dir>`, like
`git -C`: `pepper -C my_app build` builds the project in `my_app` from
anywhere. Repeated, each `-C` is relative to the one before, so
`pepper -C a -C b build` runs in `a/b`; an empty `-C ""` changes nothing.
A folder that cannot be entered is an error that exits with status 1:

```text
$ pepper -C nowhere build
pepper: error: cannot change to 'nowhere': No such file or directory
```

`-C` and `+<version>` are the only options that go before a command. They
work with `help` and the old form too.

## Toolchains

Installed by [pep-install](pep-install.md), `pepper` lives in the Pepper
home's `bin` folder (`~/.pepper/bin`, `%LOCALAPPDATA%\pepper\bin` on
Windows), beside the installed toolchains, and runs the tools of one of
them. The first of these that names a toolchain picks it:

1. `+<version>` before the command: `pepper +0.3.0 build`;
2. the `PEPPER_TOOLCHAIN` environment variable;
3. `toolchain = "0.3"` in `[package]` of the nearest `pep.toml` at or above
   the folder the command runs in (after `-C`), so a project pins the
   compiler it builds with (see [Projects: pep.toml](projects.md#package));
4. the default, which `pepper install use` sets.

A version is exact (`0.3.0`), or a prefix that picks the newest installed
toolchain that starts so (`0.3`, `0`), or `latest` for the newest installed.
`pepper` then looks for `pep-<command>` in that toolchain's `bin` folder
first, then beside `pepper`, then on the `PATH`, and runs it with
`PEPPER_TOOLCHAIN` set to the exact version, so a `pepper` that command runs
uses the same toolchain. `pepper install` always runs the home's own
`pep-install`, which needs no toolchain.

When the toolchain picked is not installed, or none is installed, `pepper`
says so and how to install it, and exits with status 1:

```text
$ pepper build
pepper: error: toolchain 0.4 (pinned by /work/app/pep.toml) is not installed; install it with 'pepper install add 0.4'
```

`pepper install which` shows which toolchain a folder uses and why.
Outside a Pepper home, as when it is built from this repository, `pepper`
runs the tools beside it, and `+<version>` is an error.

## The old form

Before `pepper build`, `pepper` was the compiler. A first argument that is a
`.pep` file or an option still runs the compiler with the whole command line,
after a warning:

```text
$ pepper main.pep -o main
pepper: warning: 'pepper main.pep ...' is deprecated; use 'pepper build main.pep ...'
```

The old form will be removed in a later release.
