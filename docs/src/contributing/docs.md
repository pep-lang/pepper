# Building this documentation

This book lives in `docs/` and is rendered with [mdBook](https://rust-lang.github.io/mdBook/).
The standard library reference (`docs/src/reference/`) is generated from the
runtime's doc comments by `pep-doc`, a Pepper tool in this repository
(`tools/pep-doc`), which `scripts/pepper-tests.sh` builds beside `pep-build`.

Install mdBook once, from [its releases](https://github.com/rust-lang/mdBook/releases)
(a single binary to put on the `PATH`), then:

```sh

pep-doc serve                                 # live preview while writing
pep-doc reference                             # regenerate the reference after changing runtime docs
pep-doc build                                 # render into target/docs-site/dev/
pep-doc build --version 0.2.0 --site <dir>
```

Run it as `target/pepper-tests/bin/pep-doc` after `scripts/pepper-tests.sh`,
or as `pepper doc`.

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

`tools/pep-doc/examples_test.pep`, which `scripts/pepper-tests.sh` runs,
builds and runs every example; each must return 0 from `main` and uses
`assert` to check what it shows. `PEPPER_DOCS_EXAMPLE=structs` limits it to
the examples whose name starts with `structs`. A sample of the examples is
also built at `-O2 -g`, where LLVM checks the debug info. Short fragments that are not whole programs can stay inline in the
chapter.

## Versions

Documentation is versioned with the compiler's [semantic version](https://semver.org)
(the one line of the root `VERSION` file). `pep-doc build --version X.Y.Z`
renders the book into `<site>/X.Y.Z/` and leaves every other version in the
site alone; `versions.json` lists them for the version picker, and the site's
`index.html` opens the newest release. Builds from `main` publish as `dev`.

The `Docs` workflow (`.github/workflows/docs.yml`) publishes to the
`gh-pages` branch: pushing to `main` updates `dev`, and pushing a tag
`vX.Y.Z` adds the `X.Y.Z` docs. Published versions are never deleted.

## The reference stays current

`pep-doc check` fails when `docs/src/reference/` does not match the
runtime, and CI runs it.

What the compiler provides rather than the runtime declares is still
declared in the runtime, marked `[__BuiltIn]`: `runtime/reflect.pep`
declares the `reflect` functions of `static` blocks and the values they
return, and `runtime/builtins.pep` the raw pointer and weak reference
types, `__null`, `sizeof`, `unsafe_cast` and the `__` intrinsics. The compiler ignores such a declaration (its functions and methods end in
`;`, with no body), so
it costs nothing and cannot clash with the built-in; the reference, the doc
comment check and the language server read it like any other. A string
argument names the built-in when it is not the declaration's own name:
`[__BuiltIn("reflect.name")]` titles the entry and its signature
`reflect.name`, and hover and go-to-definition on a use of `reflect.name`
lead to it. Only the runtime may use the attribute.

Each reference page's title and place in the table of contents come from
`pages()` in `tools/pep-doc/reference.pep`. A new runtime file with public
declarations must be added there, under its module's `module.pep`; until it
is, `reference` and `check` fail and name the file.

`check` also fails on chapter Markdown that renders broken without an
mdBook error. An include indented inside a list item is one: mdBook pastes
the file's lines at column 0, which ends the list and the code block, so the
rest of the example shows as prose and its `#` comments as headings. Put an
included example at column 0, after the list or in its own `###` section. The runtime itself must meet the doc
comment standard in `AGENTS.md`, which `pep-doc check` enforces.

## Tool options stay documented

Every command-line option of every tool has its place in the book:
`docs/src/tools/<tool>.md` for `pep-build`, `pepper`, `pep-fmt`, `pep-lsp`
and `pep-doc`, and [Setting up LLVM](setup.md) for `scripts/setup-llvm.sh`.
`pep-doc check` takes each tool's options from the tool itself (its
`--help` text, from the tools that `scripts/pepper-tests.sh` builds beside
`pep-build`) and fails, naming the tool, the option and the page, when a
page does not mention one. It also checks `pep-build`'s option values,
trace channels and environment variables, and `pep-lsp`'s initialization
options and VS Code settings. A new option goes in the tool's `--help` (or
the usage text at the top of `setup-llvm.sh`) and on its page in the same PR.
