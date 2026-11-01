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
pep-doc build --version 0.11.1 --site <dir>
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
`assert` to check what it shows. An example that prints ends with an
`# Output:` block, a `# ` line for each line it prints (`#` alone for an
empty one), and must print exactly that; leave it out where the output
differs between runs or platforms. A failure is printed as it happens.
`PEPPER_DOCS_EXAMPLE=structs` limits it to
the examples whose name starts with `structs`, and
`PEPPER_DOCS_EXAMPLES=platform` to those marked per platform, which is all
a pull request's macOS and Windows jobs run (see
[Testing](tests.md)). An example whose code differs per platform marks it
with `[Target(OS(...))]` or `[Target(Arch(...))]`. A sample of the examples is
also built at `-O2 -g`, where LLVM checks the debug info. Short fragments that are not whole programs can stay inline in the
chapter.

The same test builds and runs every `@example` in the runtime's doc
comments that is a whole program (it declares `main`), and reports a
failure at its `@example` line. Its names start with `runtime-`, so
`PEPPER_DOCS_EXAMPLE=runtime-` runs only those. One that must not run, such
as a server or a program that needs arguments, is written `@example
no-run`: it is built but not run.

## Versions

Documentation is versioned with the compiler's [semantic version](https://semver.org)
(the one line of the root `VERSION` file). `pep-doc build --version X.Y.Z`
renders the book into `<site>/X.Y.Z/` and leaves every other version in the
site alone; `versions.json` lists them for the version picker, and the site's
`index.html` and `latest/` open the newest release. On GitHub Pages a
deeper `latest/` link, such as `latest/tools/pep-doc.html`, opens that page
in the newest release too, through the site's `404.html`. Builds from `main`
publish as `dev`.

The version picker at the top of every page opens the chosen version as
soon as it is picked with the mouse. Chosen with the arrow keys, it waits
for Enter, so a keyboard user can look through the versions without
leaving the page. It opens the same page in the chosen version, or that
version's introduction when it has no such page.

The `Docs` workflow (`.github/workflows/docs.yml`) publishes to the
`gh-pages` branch: pushing to `main` updates `dev`, and pushing a tag
`vX.Y.Z` adds the `X.Y.Z` docs. Published versions are never deleted.
Every release from 0.2.0 on has its docs except 0.9.0, whose tag's workflow
still fetches from the repository's old name, so it cannot be built again;
0.9.1's docs cover it.

A release's docs are built once, from its tag. When that run fails, the
workflow opens an issue, "Docs for vX.Y.Z did not publish", with the
command that publishes them once the cause is fixed:

```bash
gh workflow run docs.yml --ref vX.Y.Z
```

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
