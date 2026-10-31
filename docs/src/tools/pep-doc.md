# The documentation builder: pep-doc

`pep-doc` builds this book. It generates the
[standard library reference](../reference/README.md) from the runtime's
[documentation comments](../language/doc-comments.md), checks the book, and
renders it with [mdBook](https://rust-lang.github.io/mdBook/), which must be
on the `PATH` (a binary from
[its releases](https://github.com/rust-lang/mdBook/releases)).

It also builds a package's reference
([`pep-doc package`](#pep-doc-package)).

It is a Pepper program (`tools/pep-doc`), and it works on the Pepper
checkout that holds the folder it is run in, except `pep-doc package`,
which works on the package that holds it. `scripts/pepper-tests.sh`
builds it beside `pep-build`, with the other Pepper tools, and `pepper doc`
runs it. To build it alone, from the repository root:

```bash
pepper build -O tools/pep-doc/main.pep -o target/bin/pep-doc
target/bin/pep-doc reference
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
  the tool and the page;
- a Pepper tool's `version()` (in `tools/<tool>/main.pep`, or pep-lsp's in
  `tools/pep-lsp/arguments.pep`) is not the version in the repository's
  `VERSION` file, which `scripts/set-version.sh` sets them all to.

The tools' options come from their `--help`: `pep-build`'s and the Pepper
tools' (`pepper`, `pep-fmt`, `pep-profile`, `pep-package`, `pep-install`,
`pep-run`, `pep-test`, `pep-new`, and `pep-init`, whose page is `pep-new`'s), which `scripts/pepper-tests.sh` builds in
`target/pepper-tests/bin` beside a link to its `pep-build`, so run it
first.

- `--tools <DIR>`: the folder holding the built tools (default:
  `target/pepper-tests/bin` under `$PEPPER_TARGET_DIR` or `target/`).

CI runs it, after the tests.

### `pep-doc build`

Regenerates the reference, renders the book into `<site>/<version>/`, and
refreshes the site's `versions.json`, `index.html`, `latest/index.html` and
`404.html`: `index.html` and `latest/` open the newest release, and
`404.html` sends any deeper `latest/` path to the same page there (GitHub
Pages serves it for every missing page). Other versions in the
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

### `pep-doc package`

Builds the reference of the package that holds the current folder: the
nearest `pep.toml` up from it, which must have a `[package]`. Unlike the
other commands, it needs no Pepper checkout, so `pepper doc package` works
in any package:

```bash
cd geometry
pepper doc package           # writes .pep/doc/, renders it into .pep/doc/html/
```

- **Pages:** one per `.pep` file with a public declaration or a `##`
  introduction, made as the [standard library reference's](../reference/README.md)
  are, from the [doc comments](../language/doc-comments.md). A
  `module.pep` page is titled by the module (`geometry`,
  `geometry.solids`), any other by the file's path. Tests (`test/` and
  `tests/` folders, `_test.pep` files), `examples/`, hidden folders such
  as `.pep/`, and folders with their own `pep.toml` (a workspace's members,
  vendored packages) are left out; run it in each member of a workspace.
- **Features:** a declaration that a [feature](projects.md#features) gates
  says so under its signature ("Available with the feature `tls`"),
  linking to the front page's list of features. It is gated when its
  attributes require the feature's build option (`<package>_<feature>`):
  `[BuildOption("http_tls")]`, or `BuildOption(http_tls)` in a
  `[Target(...)]`, alone or joined by `&&`. One under `!` or `||` is not
  marked.
- **Front page:** the package's name, `version` and `description`, a line
  per page, its `[features]` with what each turns on, and its
  dependencies, each linked to its docs: for a GitHub repository, the
  GitHub Pages site the [package template](#hosting-a-packages-docs)
  publishes (`https://<owner>.github.io/<name>/`), for another host its
  repository, and for a `path` dependency nothing.
- **Output:** an mdBook in `.pep/doc/` (`book.toml`, and `src/` with the
  pages, `README.md` and `SUMMARY.md`, rewritten on each run), rendered
  with mdBook into `.pep/doc/html/`. When mdBook cannot run, the error
  says where the Markdown is.

Options:

- `--check`: changes nothing, and fails (exit status 1) when a public
  declaration has no doc comment, or one without a description or a tag
  the [documentation standard](../contributing/docs.md) requires, as
  `pep-doc check` does for the runtime: a clang-style error at each.
- `--site <DIR>`: renders into `<DIR>/<version>/` instead, the version
  being `pep.toml`'s (`dev` without one), and refreshes `<DIR>`'s
  `versions.json`, `index.html`, `latest/` and `404.html`, which open the
  newest release, as `build` does for this book. Earlier versions stay.

#### Hosting a package's docs

The package template (`pepper new --lib`, and
[pep-lang/pepper-package-template](https://github.com/pep-lang/pepper-package-template))
publishes each release's reference with GitHub Pages, with no server: on a
`vX.Y.Z` tag its CI's `docs` job runs `pepper doc package --site` on the
repository's `gh-pages` branch, which keeps a folder per version, and
pushes it. Turn on GitHub Pages for the `gh-pages` branch once, in the
repository's Settings, Pages. A toolchain whose pep-doc has no `package`
skips the job.

### `pep-doc help`

Prints the commands and options, as `-h` and `--help` do.

## Options

| Option | What it does |
| --- | --- |
| `--version <VERSION>` | With `build`: the version to build |
| `--site <DIR>` | With `build`: the site folder; with `package`: the site to render into |
| `--check` | With `package`: check the doc comments, changing nothing |
| `-h`, `--help` | Print the commands and options |
| `-V`, `--version` | As the only argument: print `pep-doc` and its version |

An unknown command is an error. Each command exits with 0 on success and 1
on failure, with the reason on standard error.

See [Building this documentation](../contributing/docs.md) for how the
book is organized and published.
