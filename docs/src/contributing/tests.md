# Testing the runtime and the compiler

The tests are written in Pepper: `[Test]` functions (see
[Unit tests](../language/testing.md)) that `pepper test`
([`pep-test`](../tools/pep-test.md)) builds and runs. They cover the
runtime and the Pepper tools, the compiler written in Pepper
(`tools/compiler`) among them.

The Rust compiler's own tests (`crates/*/tests/`, the root package's
`tests/*.rs`; see `INTERNALS.md`, section 9) are still in the repository,
and `cargo test --workspace` runs them, but neither CI nor the pre-merge
checks do: the Rust compiler is not expected to change much, and new tests
go in Pepper.

## Where runtime tests live

| Code under test | Its tests |
| --- | --- |
| A module, `runtime/<module>/` | `runtime/<module>/test/<topic>_test.pep`, which imports the module |
| A prelude file, `runtime/<name>.pep` | `runtime/test/<topic>_test.pep` |
| A file's private functions | `[Test]` functions in that file itself |
| A Pepper tool, `tools/<tool>/` | `tools/<tool>/<topic>_test.pep`, which imports the tool's files (`import "format";`) |

A `test/` folder holds no `module.pep`, so no program that imports the
module loads it. Its files are still files of the module, though: they see
the module's unexported names and each other's. `pep-test` builds each
folder's tests into one program, so a helper (or test name) that two test
files of one folder declare collides; mark it `private` in each (as
`runtime/async/test/` does). Prefer it to tests inside a
source file, which only a test of private internals needs. The reference
generator and the doc-comment check skip `test/` folders, so a test file
needs no `##` comments.

## Running them

`scripts/pepper-tests.sh` runs them all:

```bash
cargo build                                      # or --release
scripts/pepper-tests.sh                          # every runtime and tool test
scripts/pepper-tests.sh -f parses                # by name, in each run
```

It builds `pepper` and `pep-test` with the `pep-build` you built (the
release build if there is one, else the debug build; a folder given as the
first argument overrides it), puts them beside it, and runs `pepper test`:

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

CI runs `scripts/pepper-tests.sh` after `cargo build --release` on
Linux, macOS and Windows.

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
