# The pepper command

`pepper` is the entry point to every Pepper tool, the way `go` and `git`
are: `pepper <command> [arguments]` runs a separate program named
`pep-<command>` with the remaining arguments.

```bash
pepper build main.pep -o main     # runs pep-build main.pep -o main
pepper fmt -w src                 # runs pep-fmt -w src
pepper help                       # lists the commands it can find
pepper help build                 # runs pep-build --help
pepper --version                  # pepper's version; -v adds each command's
```

`pepper` is itself written in Pepper (`tools/pepper/main.pep`). The compiler
is the program `pep-build`, so `pepper build` takes exactly the options the
compiler does.

## The commands in this repository

| Command | Program | What it does |
| --- | --- | --- |
| `pepper build` | `pep-build` | Compiles a program (the compiler) |
| `pepper fmt` | `pep-fmt` | Formats source ([Formatting with pep-fmt](pep-fmt.md)) |
| `pepper lsp` | `pep-lsp` | Runs the language server, which editors start |
| `pepper doc` | `pep-doc` | Generates the library reference and builds this book |

`cargo build --release --workspace` builds `pep-build`, `pep-lsp` and `pep-doc` into
`target/release`; `pep-fmt` and `pepper` are Pepper programs, built with
`pep-build`.

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

The command runs with `pepper`'s own standard input, output and error, and
`pepper` exits with its exit status (`128 + n` when signal `n` ended it, as a
shell reports it). A command name is lowercase letters, digits, `-` and `_`;
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
