# Testing the runtime and the compiler

The tests are written in Pepper: `[Test]` functions (see
[Unit tests](../language/testing.md)) that `pepper test`
([`pep-test`](../tools/pep-test.md)) builds and runs. They cover the
runtime and the Pepper tools, the compiler written in Pepper
(`tools/compiler`) among them.

They are the whole suite: Pepper is written in Pepper, and so are its
tests.

## Where runtime tests live

| Code under test | Its tests |
| --- | --- |
| A module, `runtime/<module>/` | `runtime/<module>/test/<topic>_test.pep`, which imports the module |
| A prelude file, `runtime/<name>.pep` | `runtime/test/<topic>_test.pep` |
| A file's private functions | `[Test]` functions in that file itself |
| A Pepper tool, `tools/<tool>/` | `tools/<tool>/<topic>_test.pep`, which imports the tool's files (`import "format";`) |

A `test/` folder holds no `module.pep`, so no program that imports the
module loads it. Its files are still files of the module, though: a test file
that imports one of the module's files (`import "../atomic";` in `runtime/async/test/`) sees its
unexported names. `pep-test` builds each
folder's tests into one program, so a helper (or test name) that two test
files of one folder declare collides; mark it `private` in each (as
`runtime/async/test/` does). Prefer it to tests inside a
source file, which only a test of private internals needs. The reference
generator and the doc-comment check skip `test/` folders, so a test file
needs no `##` comments.

## Running them

`scripts/pepper-tests.sh` runs them all:

```bash
sh scripts/install.sh --version 0.4.0-dev        # the build of main; see below
scripts/pepper-tests.sh                          # every runtime and tool test
scripts/pepper-tests.sh -f parses                # by name, in each run
scripts/pepper-tests.sh target/bin               # with a pep-build you built
```

The tests build with the installed toolchain's `pep-build`, the one
`pepper install which` names. Every merge into main that changes the
compiler, the runtime or the tools publishes the build of main as a
prerelease named by the version the `VERSION` file holds (`0.4.0-dev`), replacing
the one before; CI and the workers install it with the install scripts
rather than building the compiler, and so can you (run the install again to
refresh it). The compiler's own tests (`tools/compiler/*_test.pep`) build
the compiler's sources into their test programs, so they test a change to
it. To run the whole suite with the changed compiler too, build it from
`tools/compiler` (see the README's
[Build and test](https://github.com/justinboswell/pepper#build-and-test))
and pass its folder as the first argument.

The script builds the Pepper tools (`pepper`, `pep-test`, `pep-doc` and the
others) from the checkout with that `pep-build`, against the checkout's
runtime, into `target/pepper-tests/bin` beside a link to the `pep-build`,
and runs `pepper test`:

- in `runtime/`, every runtime test;
- in `runtime/`, the `compress` tests again with `-D USE_ZLIB` and the
  `digest` tests with `-D USE_LIBCRYPTO`, which link the system's zlib and
  libcrypto (on Windows the zlib run needs `PEPPER_TEST_ZLIB_DIR`, a folder
  holding `zlib.lib`, and is skipped without it);
- in `tools/`, with `-I .`, the tools' tests.

The tools' run, the longest, starts as soon as `pepper` and `pep-test`
are built and runs beside the runtime's runs; its output is printed after
theirs.

Once `pepper` is built, run any part of them by hand:

```bash
cd runtime
pepper test                       # every runtime test
pepper test json/test             # one module's
pepper test -f parses test        # by name
```

Tests run with `runtime/` as the current folder, so a test reads data
files kept beside it by a path from there (`archive/test/gnu.tar.gz`).
The builds go to `runtime/.pep/`, which git ignores. A test that writes
files uses a fresh folder under the system's temporary folder
(`TempFolder` in the `testing` module makes and removes one).

CI runs `scripts/pepper-tests.sh` with the installed build of main on
Linux, macOS and Windows. A PR that changes the compiler (`tools/compiler/`)
is tested with that compiler instead: CI builds it with the build of main
first (`scripts/ci-build-compiler.sh`) and runs the suite with it.

Two Pepper tools depend on private repositories. The compiler written in
Pepper, `tools/compiler`, depends on `justinboswell/pepper-llvm`, and the
language server `tools/pep-lsp` depends on `justinboswell/pepper-lsp`. CI
clones each over SSH with a read-only deploy key of that repository, whose
private half is this repository's secret `PEPPER_LLVM_DEPLOY_KEY` or
`PEPPER_LSP_DEPLOY_KEY`.

`scripts/ci-package-auth.sh` writes the keys to temporary files. It gives
each package a host alias in an SSH config that offers only that package's
key, since GitHub takes the first key offered and a deploy key opens only
its own repository. It points git at the aliases through `GIT_CONFIG_*` and
`GIT_SSH_COMMAND` variables of the test step only. Without a secret (in a
fork, say) the step says so in a notice, and the tests of the tool that
uses that package fail when they fetch it.

## Leaks fail a test

Each test counts the runtime's live allocations before and after it runs,
and fails when they differ:

```text
error: test 'parses_components' left 2 allocations behind
```

So a test needs no census of its own: every object it made must be
released by the time it returns. What the program keeps for good, such as
a global made on first use (`async.Lazy`), is made inside
`keep_for_the_program(() => { ... })` at the start of the test, which
leaves it out of the count.
