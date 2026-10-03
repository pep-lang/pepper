# The pepper command

`pepper` is the entry point to every Pepper tool, the way `go` and `git`
are: `pepper <command> [arguments]` runs a separate program named
`pep-<command>` with the remaining arguments.

```bash
pepper build main.pep -o main     # runs pep-build main.pep -o main
pepper build                      # builds the project pep.toml describes
pepper fmt -w src                 # runs pep-fmt -w src
pepper help                       # lists the commands it can find
pepper help build                 # runs pep-build --help
pepper --version                  # pepper's version; -v adds each command's
```

`pepper` is itself written in Pepper (`tools/pepper/main.pep`). The compiler
is the program `pep-build`, so `pepper build` takes exactly the options the
compiler does (see [The compiler: pep-build](pep-build.md)).

## Usage and options

```text
pepper <command> [arguments]
pepper help [<command>]
pepper --version [-v]
```

| Form | What it does |
| --- | --- |
| `pepper <command> [arguments]` | Runs `pep-<command>` with the arguments (see [How it finds a command](#how-it-finds-a-command)) |
| `pepper help`, `-h`, `--help` | Prints the usage, these options, and the commands it can find |
| `pepper help <command>` | Runs `pep-<command> --help` |
| `--version` | Prints `pepper` and its version |
| `--version -v`, `--version --verbose` | Also prints the version each command reports (its `--version`'s first line, or `(no version)`) |

Options go before the command: everything after the command belongs to it,
so `pepper fmt --help` is `pep-fmt --help`. `pepper` with no arguments prints
the usage to standard error and exits with status 2; an option other than
`-v` or `--verbose` after `--version` is an error that exits with 2. An
unknown command exits with 1. Otherwise the exit status is the command's.

## The commands in this repository

| Command | Program | What it does |
| --- | --- | --- |
| `pepper build` | `pep-build` | Compiles a program, or with no file the project ([The compiler: pep-build](pep-build.md), [Projects: pep.toml](projects.md)) |
| `pepper fmt` | `pep-fmt` | Formats source ([Formatting with pep-fmt](pep-fmt.md)) |
| `pepper profile` | `pep-profile` | Profiles a program and draws a flame graph ([Profiling with pep-profile](pep-profile.md)) |
| `pepper lsp` | `pep-lsp` | Runs the language server, which editors start ([The language server: pep-lsp](pep-lsp.md)) |
| `pepper doc` | `pep-doc` | Generates the library reference and builds this book ([The documentation builder: pep-doc](pep-doc.md)) |

`cargo build --release --workspace` builds `pep-build`, `pep-lsp` and `pep-doc` into
`target/release`; `pep-fmt`, `pep-profile` and `pepper` are Pepper
programs, built with `pep-build`.

## Building it

Build the compiler with cargo, then build `pepper` with the compiler and put
it next to it:

```bash
cargo build --release
target/release/pep-build tools/pepper/main.pep -o target/release/pepper
```

On Windows, name the output `target\release\pepper.exe`.

## How it finds a command

`pepper <command>` looks for `pep-<command>` (`pep-<command>.exe` on
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

## The old form

Before `pepper build`, `pepper` was the compiler. A first argument that is a
`.pep` file or an option still runs the compiler with the whole command line,
after a warning:

```text
$ pepper main.pep -o main
pepper: warning: 'pepper main.pep ...' is deprecated; use 'pepper build main.pep ...'
```

The old form will be removed in a later release.
