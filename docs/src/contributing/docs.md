# Building this documentation

This book lives in `docs/` and is rendered with [mdBook](https://rust-lang.github.io/mdBook/).
The standard library reference (`docs/src/reference/`) is generated from the
runtime's doc comments by `pep-doc`, a tool in this repository.

```sh
cargo install mdbook --locked                 # once

cargo run -p pepper-docgen -- serve           # live preview while writing
cargo run -p pepper-docgen -- reference       # regenerate the reference after changing runtime docs
cargo run -p pepper-docgen -- build           # render into target/docs-site/dev/
cargo run -p pepper-docgen -- build --version 0.2.0 --site <dir>
```

`pep-doc`'s commands and options are described in
[The documentation builder: pep-doc](../tools/pep-doc.md).

## Keeping the book current

Documentation changes land in the same PR as the code they describe. The
checklist of what to update for each kind of change is in `AGENTS.md`, under
"Keep the documentation current".

## Examples are tested

Every runnable example lives in `docs/examples/`: a single `name.pep`, or a
folder `name/` whose entry point is `main.pep`. Chapters pull them in with
mdBook's include syntax, so the text on the page is the file that was tested:

````markdown
```pepper
\{{#include ../../examples/structs.pep}}
```
````

`crates/pepper-driver/tests/integration/docs_examples_tests.rs` compiles and runs every
example; each must return 0 from `main` and uses `assert` to check what it
shows. Short fragments that are not whole programs can stay inline in the
chapter.

## Versions

Documentation is versioned with the compiler's [semantic version](https://semver.org)
(`version` in the root `Cargo.toml`). `pep-doc build --version X.Y.Z`
renders the book into `<site>/X.Y.Z/` and leaves every other version in the
site alone; `versions.json` lists them for the version picker, and the site's
`index.html` opens the newest release. Builds from `main` publish as `dev`.

The `Docs` workflow (`.github/workflows/docs.yml`) publishes to the
`gh-pages` branch: pushing to `main` updates `dev`, and pushing a tag
`vX.Y.Z` adds the `X.Y.Z` docs. Published versions are never deleted.

## The reference stays current

`cargo run -p pepper-docgen -- check` fails when `docs/src/reference/` does
not match the runtime, and CI runs it.

What the compiler provides rather than the runtime declares has a page
written by hand: `reference/reflect.md` documents the `reflect` functions
of `static` blocks. `HAND_WRITTEN` in `tools/docgen/src/reference.rs` lists
such pages for the table of contents, and a docgen test fails when the
compiler gains a `reflect` function or property the page does not name.

Each reference page's title and place in the table of contents come from
`PAGES` in `tools/docgen/src/reference.rs`. A new runtime file with public
declarations must be added there, under its module's `module.pep`; until it
is, `reference` and `check` fail and name the file.

`check` also fails on chapter Markdown that renders broken without an
mdBook error. An include indented inside a list item is one: mdBook pastes
the file's lines at column 0, which ends the list and the code block, so the
rest of the example shows as prose and its `#` comments as headings. Put an
included example at column 0, after the list or in its own `###` section. The runtime itself must meet the doc
comment standard in `AGENTS.md`, which `runtime_docs_tests.rs` enforces.

## Tool options stay documented

Every command-line option of every tool has its place in the book:
`docs/src/tools/<tool>.md` for `pep-build`, `pepper`, `pep-fmt`, `pep-lsp`
and `pep-doc`, and [Setting up LLVM](setup.md) for `cargo setup`.
`crates/pepper-driver/tests/integration/tool_docs_tests.rs` takes each tool's
options from the tool itself (clap's definition for `pep-build`, the
`--help` text for the others) and fails, naming the tool, the option and the
page, when a page does not mention one. It also checks `pep-build`'s trace
channels and environment variables, and `pep-lsp`'s initialization options
and VS Code settings. A new option goes in the tool's `--help` (or
`help.txt` / `usage.txt`) and on its page in the same PR.
