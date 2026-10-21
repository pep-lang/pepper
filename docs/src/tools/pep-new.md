# Starting a project: pep-new and pep-init

`pep-new` starts a project in a new folder, and `pep-init` starts one in
the current folder, the way `cargo new` and `cargo init` do. `pepper new`
and `pepper init` run them. Each writes a [`pep.toml`](projects.md) and the
files a project starts with, so `pepper build` and `pepper test` work at
once:

```bash
pepper new hello                  # a program in the folder hello
cd hello
pepper build                      # builds ./hello
pepper test                       # runs its [Test] function

pepper new geometry --lib         # a package
pepper new pepper-geometry --lib --name geometry --license MIT
pepper init                       # a program in the current folder
```

```text
pep-new [OPTIONS] <path>
pep-init [OPTIONS]
```

| Option | What it does |
| --- | --- |
| `<path>` | The folder `pep-new` writes into, made when missing; its name is the project's unless `--name` gives one (`pep-new` only) |
| `--lib` | Starts a package instead of a program |
| `--license <SPDX>` | Writes `LICENSE` and names the license in `pep.toml`: `MIT` or `Apache-2.0` |
| `--name <NAME>` | Names the project, instead of the folder's name |
| `-h`, `--help` | Prints the usage and these options |
| `-V`, `--version` | Prints the tool and its version |

The exit status is 0 when the project is written, 1 when nothing is
written (the errors below), and 2 for a usage error.

## A program

```text
hello/
  pep.toml        [package] name = "hello", version = "0.1.0"
  main.pep        main() prints Hello, world!, and a [Test] checks it
  .gitignore      .pep/ and the executable
  README.md       how to build, run and test it
```

The test sits in `main.pep`, beside the function it tests (see
[Unit tests](../language/testing.md#where-tests-live)); a plain build
leaves it out.

## A package

`--lib` writes the layout of
[pep-lang/pepper-package-template](https://github.com/pep-lang/pepper-package-template),
with the template's placeholder name replaced by the package's:

```text
geometry/
  pep.toml                  [package] name, version 0.1.0, description, repository
  module.pep                the root module: gathers the public API from its files
  greet.pep                 one documented function, geometry.greet
  tests/greet_test.pep      import geometry; and a [Test]
  tests/run.sh              runs the tests with the package on the import path
  .github/workflows/ci.yml  tests on Linux, macOS and Windows; releases on a vX.Y.Z tag
  .gitignore                .pep/
  README.md                 what it does, how to add it, test it and release it
```

A package's tests import it by name, which `pepper test` finds only with
the package's folder on the import path under that name, so they run with
`tests/run.sh path/to/pepper` (or `bash tests/run.sh` with `pepper` on the
`PATH`), as CI does. The README and `pep.toml` name the repository as
`OWNER/pepper-<name>`: put in the GitHub owner. The template's own
`TEMPLATE.md` lists what else to fill in.

The files come from the template repository word for word, so a package
started either way is the same; the template's CI checks that what
`pepper new mypkg --lib --license Apache-2.0` writes matches it.

## Licenses

`--license MIT` writes the MIT License, with `Copyright (c) The <name>
authors`; `--license Apache-2.0` writes the Apache License 2.0. Either adds
`license = "<SPDX>"` to `pep.toml` and a License section to the README.
Without `--license` none of the three is written. Another license is an
error: write its text to `LICENSE` and its identifier to `pep.toml` by
hand.

## Errors

Nothing is written when any of the files is there already; the error names
each one, and the files are left as they were:

```text
$ pepper init
pep-init: error: nothing written: these files are there already
  ./main.pep
  ./README.md
```

The name is checked as `pep.toml` checks `[package] name`, and the error
suggests one that works, made by turning each character an identifier
cannot hold into `_`:

```text
$ pepper new my-app
pep-new: error: package name 'my-app' is not an identifier: use letters, digits and '_', not starting with a digit; try '--name my_app'
```

## Building them

```bash
target/bin/pep-build tools/pep-new/main.pep -o target/bin/pep-new
target/bin/pep-build tools/pep-init/main.pep -o target/bin/pep-init
```

Both are built on the module in `tools/scaffold`; the package's files are in
`tools/scaffold/template.pep`.
