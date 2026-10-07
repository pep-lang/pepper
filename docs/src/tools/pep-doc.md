# The documentation builder: pep-doc

`pep-doc` builds this book. It generates the
[standard library reference](../reference/README.md) from the runtime's
[documentation comments](../language/doc-comments.md), checks the book, and
renders it with [mdBook](https://rust-lang.github.io/mdBook/), which must be
on the `PATH` (`cargo install mdbook --locked`).

It is a Pepper program (`tools/pep-doc`), and it works on the Pepper
checkout that holds the folder it is run in. `scripts/pepper-tests.sh`
builds it beside `pep-build`, with the other Pepper tools, and `pepper doc`
runs it. To build it alone, from the repository root:

```bash
target/release/pep-build -O -I tools tools/pep-doc/main.pep -o target/release/pep-doc
target/release/pep-doc reference
```

```text
pep-doc [<command>] [options]
```

## Commands

### `pep-doc reference`

Regenerates `docs/src/reference/` and the reference's entries in
`docs/src/SUMMARY.md` from the doc comments under `runtime/`, and prints each
file it changed. Run it after changing a runtime doc comment, and commit the
result.

### `pep-doc check`

Changes nothing, and fails (exit status 1) when:

- the committed reference does not match the runtime, naming the stale
  pages;
- a chapter has Markdown that renders broken without an mdBook error, such
  as an include indented inside a list item;
- a public declaration in `runtime/` (or `tools/syntax`) has no doc comment,
  or one without a description or a tag the
  [documentation standard](../contributing/docs.md) requires, as a
  clang-style error at the declaration;
- a tool's option, command, option value, trace channel, environment
  variable or setting is missing from the tool's page in this book, naming
  the tool and the page.

The tools' options come from their `--help`: `pep-build`'s and the Pepper
tools' (`pepper`, `pep-fmt`, `pep-profile`, `pep-package`, `pep-install`,
`pep-test`), which `scripts/pepper-tests.sh` builds in
`target/pepper-tests/bin` beside a link to its `pep-build`, so run it
first.

- `--tools <DIR>`: the folder holding the built tools (default:
  `target/pepper-tests/bin` under `$CARGO_TARGET_DIR` or `target/` when it
  holds `pep-build`, else the release build's folder when it does, else the
  debug build's).

CI runs it, after the tests.

### `pep-doc build`

Regenerates the reference, renders the book into `<site>/<version>/`, and
refreshes the site's `versions.json` and `index.html`. Other versions in the
site are left as they are, so every published version stays available. This
is the command when none is given.

- `--version <VERSION>`: the version to build, `X.Y.Z` or `dev` (the
  default). Anything else is an error.
- `--site <DIR>`: the site folder (default: `target/docs-site`).

```bash
pep-doc build --version 0.3.0 --site site     # renders into site/0.3.0/
```

### `pep-doc serve`

Regenerates the reference and serves the book locally with `mdbook serve`,
opening it in the browser and rebuilding as chapters change.

### `pep-doc help`

Prints the commands and options, as `-h` and `--help` do.

## Options

| Option | What it does |
| --- | --- |
| `--version <VERSION>` | With `build`: the version to build |
| `--site <DIR>` | With `build`: the site folder |
| `-h`, `--help` | Print the commands and options |
| `-V`, `--version` | As the only argument: print `pep-doc` and its version |

An unknown command is an error. Each command exits with 0 on success and 1
on failure, with the reason on standard error.

See [Building this documentation](../contributing/docs.md) for how the
book is organized and published.
