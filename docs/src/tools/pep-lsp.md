# The language server: pep-lsp

`pep-lsp` is Pepper's language server. An editor starts it and talks to it
over standard input and output with the
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/):
it reports compiler errors and warnings as you type, and provides hover,
completion, go to definition, document outlines and inlay hints. It checks
code with the compiler's own front end, and finds the standard library the
way the compiler does (see
[Where the compiler finds the standard library](../tutorial/getting-started.md#where-the-compiler-finds-the-standard-library)).

The [VS Code extension](../tutorial/getting-started.md#editor-support) bundles
it. When [`pepper install`](pep-install.md) manages your Pepper home, the
extension instead runs the `pep-lsp` of the toolchain the first workspace
folder uses, as `pepper install which` reports it there, so the editor
checks code with the same compiler and standard library as `pepper build`.
If that fails (say the project pins a toolchain that is not installed), a
warning says why and the bundled server runs. Run **Pepper: Restart
Language Server** after switching toolchains.

The extension also offers to install what is missing, running it as a task
whose terminal shows the progress and any error, then offers to reload the
window to pick the toolchain up:

- with no Pepper home, **Install Pepper** runs the
  [install script](install.md);
- when the toolchain the workspace uses is not installed, **Install** runs
  the `pepper install add <version>` (or `pepper install update`) that
  `pepper install which` suggests;
- when the default toolchain is older than the extension, **Update** runs
  `pepper install update`. A toolchain a project pins, or
  `PEPPER_TOOLCHAIN` names, is left as it is.

**Don't Ask Again** stops an offer for good. For another editor, run the
toolchain's `pep-lsp` (or `pepper lsp`) for `.pep` files.

The server is written in Pepper, in `tools/pep-lsp`, on the
[`lsp` package](https://github.com/justinboswell/pepper-lsp), a framework
for writing a language server for any language in Pepper. To build it from
a checkout of the repository, with this checkout's standard library:

```bash
PEPPER_RUNTIME=$PWD/runtime pep-build -O tools/pep-lsp/main.pep -o target/pep-lsp/pep-lsp
```

## When the server crashes

`pep-lsp` runs the server in a child process (`pep-lsp --serve`) and
passes messages between the editor and it. If the server crashes (a bug in
the compiler or the server ends it with a panic), `pep-lsp` answers the
requests it left unanswered with an empty result, logs `the server ended
...; restarting it` to the editor's output, and starts a new one, which
gets the open documents again. If the new one crashes too before you
change anything, the document you changed last is left out until you
change it again, so one text that crashes the server cannot keep it down;
after five crashes in a row `pep-lsp` gives up and exits.

## Checking as you type

The server checks a file as the root of its own program, the way
`pepper build` checks one: one compilation unit at a time, starting with
the standard library and working up through each file's imports. A
compilation unit is one file, or the files that import each other in a
cycle. It saves what it learned about each compilation unit in the build
cache, in the `.pep/cache` folder of the
file's project (the folder holding its `pep.toml`, else the file's own
folder), or in `$PEPPER_CACHE_DIR` when that is set. When you edit a file,
only the file you are editing is checked again. Every other compilation unit loads
from the cache, unless its files changed on disk or a declaration it
depends on changed. The cache outlives the server, so a restarted editor
answers quickly once the files have been checked once. Delete the folder
to start over.

The first time, when the cache has nothing yet (it lacks even the standard
library's compilation unit), the server checks the whole program at once,
which is quicker than one compilation unit after another, and meanwhile a
copy of itself (`pep-lsp --fill-cache`) fills the cache: it checks the
compilation units the file depends on in parallel, in more copies
(`pep-lsp --compilation-unit-worker`), one per processor at most, as
`pepper build` does. Until it is done, an edit is checked again on the
record of the whole program the first check left: only the bodies and
declarations the edit changed or added are checked. An edit that does more,
or that has an error or a warning, waits for the copy, then loads the
compilation units it checked. When the
cache has some compilation units but not others, the server checks the
missing ones that way itself.

## Command-line options

```text
pep-lsp [--stdio]
```

| Option | What it does |
| --- | --- |
| `--stdio` | Talk over standard input and output: the default, accepted for editors that pass it |
| `--serve` | Internal: run the server in this process, without the supervisor that restarts it. The supervisor starts it so |
| `--compilation-unit-worker <dir>` | Internal: check compilation units for the server that started it, which passes them through `<dir>`. The server starts these itself. `--layer-worker` is its deprecated spelling |
| `--fill-cache <dir>` | Internal: check the compilation units the build cache lacks, in `--compilation-unit-worker` copies, for the server that started it, which passes the program through `<dir>`. The server starts it itself when the cache is empty |
| `-h`, `--help` | Print the options and exit |
| `-V`, `--version` | Print `pep-lsp` and its version, and exit |

Any other argument is an error, and the server exits with status 2 without
starting.

## Initialization options

The server's settings arrive in the `initializationOptions` of the LSP
`initialize` request, read once when it starts:

```json
{
  "inlayHints": { "implicitConversions": true, "parameterNames": true },
  "buildOptions": ["USE_ZLIB", "LOG_LEVEL=2"]
}
```

| Option | Type | Default | What it does |
| --- | --- | --- | --- |
| `inlayHints.implicitConversions` | boolean | `true` | Show the constructor call an [`[Implicit]` conversion](../language/structs.md#implicit-conversions) inserts, such as `Path(` ... `)` around a `String` passed where a `Path` is expected |
| `inlayHints.parameterNames` | boolean | `true` | Show the parameter name before a literal argument passed by position (`resize(width: 800, height: 600)`) |
| `buildOptions` | array of strings | `[]` | The [build options](../language/build-options.md) to analyze with, as the compiler's `-D` takes them: `NAME` or `NAME=VALUE`. One that does not parse is left out |

## VS Code settings

The extension passes its settings to the server as the initialization
options above, and restarts the server when one changes:

| Setting | Default | What it does |
| --- | --- | --- |
| `pepper.lspPath` | empty | The `pep-lsp` to run; empty uses the project's toolchain's, else the one bundled with the extension. The server restarts whenever that file is rebuilt |
| `pepper.inlayHints.implicitConversions` | `true` | `inlayHints.implicitConversions` |
| `pepper.inlayHints.parameterNames` | `true` | `inlayHints.parameterNames` |
| `pepper.buildOptions` | `[]` | `buildOptions` |

Inlay hints also need VS Code's own `editor.inlayHints.enabled`. The command
**Pepper: Restart Language Server** (`pepper.restartServer`) restarts the
server on demand.
