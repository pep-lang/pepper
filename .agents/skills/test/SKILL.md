---
name: test
description: Run the Pepper project's tests, Pepper [Test] functions run with pepper test (scripts/pepper-tests.sh). Use when asked to test, run tests, or verify changes to the compiler, parser, sema, codegen, runtime or tools.
---

# Testing Pepper

## Run tests

The tests are Pepper `[Test]` functions, run with `pepper test`. They build with the installed toolchain: the build of main, which every merge that changes the compiler, the runtime or the tools publishes as the `x.y.z-dev` prerelease named by the version in `VERSION` (#713). Install or refresh it, then run them all:

```bash
sh scripts/install.sh --version "$(cat VERSION)" --yes
scripts/pepper-tests.sh
scripts/pepper-tests.sh -f parses     # by name
```

The compiler's own tests (`tools/compiler/*_test.pep`) build its sources into their test programs, so they test a change to it with the installed `pep-build`. To run the whole suite with a changed compiler, as CI does for a PR that changes `tools/compiler/`, build it from `tools/compiler` (see the **build** skill, or `PEPPER_COMPILER_DIR=<installed bin> scripts/ci-build-compiler.sh`, which builds it into `target/compiler`) and pass its folder as the first argument: `scripts/pepper-tests.sh target/compiler`. See `docs/src/contributing/tests.md`.

Run one test file while iterating, from the folder `scripts/pepper-tests.sh` runs it in, with the tools it built first on the PATH:

```bash
export PATH="$PWD/target/pepper-tests/bin:$PATH"
(cd tools && pepper test -I . -t 300 pep-fmt/cli_test.pep)
(cd runtime && pepper test json/test)
```

## Pepper test layout

| Where | What |
|---|---|
| `runtime/<module>/test/*_test.pep`, `runtime/test/` | The runtime and the prelude |
| `tools/compiler/*_test.pep` | The compiler written in Pepper; `corpus_test.pep` builds and runs every `tests/<Name>/test.pep` with `pep-build -I tests` (each must exit 0; a new fixture joins automatically), and under wasmtime when `WASI_SDK_PATH` and wasmtime are there |
| `tools/pep-doc/examples_test.pep` | Builds and runs every book example |
| `tools/pep-fmt/` | The style (`format_test.pep`), every repository file formats idempotently to the same syntax tree and `runtime/`/`tools/` are formatted (`repository_test.pep`), the program (`cli_test.pep`) |
| `tools/pepper/`, `tools/pep-test/`, `tools/pep-package/`, `tools/pep-profile/` | Each tool end to end (`*_test.pep`), built by the script and found on the PATH, with the `tool_testing` helpers and data in `testdata/`; `pepper_test.pep` also checks every tool's `--version` |
| `tools/pep-install/`, `tools/pep-lsp/` | Those tools, in-process |

A run is good when every `pepper test` summary says `0 failed` and the script exits 0. A test that cannot run here prints `skipped: ...` and passes (the wasmtime corpus runs, the live profile, the package tests without git).

## Diagnosing failures

1. Run the failing test alone (`pepper test -f name <file>`): its output (what it printed, the panic, and the tool output `expect_exit` and `expect_contains` show) follows the summary.
2. A tool test fails with `cannot find <tool> beside the test program or on the PATH`: put `target/pepper-tests/bin` first on the PATH, or run `scripts/pepper-tests.sh`, which builds the tools there.
3. A corpus program that fails: build it by hand, `pep-build -I tests tests/<Name>/test.pep -o /tmp/t && /tmp/t; echo $?`. For a parse failure, `pep-build --emit-ast tests/<Name>/test.pep` stops after parsing.
4. A file `repository_test.pep` says is not formatted: `pep-fmt -w <file>`. One that formats differently a second time, or whose syntax tree changes, is a pep-fmt bug: reproduce it with `pep-fmt < file`.
