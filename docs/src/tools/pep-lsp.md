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
Language Server** after switching toolchains. For another editor, build it with
`cargo build --release -p pepper-lsp` (it is
`target/release/pep-lsp`) and configure the editor to run it for `.pep`
files.

## Command-line options

```text
pep-lsp [--stdio]
```

| Option | What it does |
| --- | --- |
| `--stdio` | Talk over standard input and output: the default, accepted for editors that pass it |
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
