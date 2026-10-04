# Testing the runtime and the compiler

The repository has two kinds of tests, split by what they check.

- **The runtime and the Pepper tools** are tested in Pepper: `[Test]`
  functions (see [Unit tests](../language/testing.md)) that `pepper test`
  ([`pep-test`](../tools/pep-test.md)) builds and runs.
- **The compiler** is tested in Rust: diagnostics, codegen and IR facts,
  reference-count order, optimization, linking, cross-compiling, debug
  info, the build cache, the documentation checks, and the drivers. These
  live in `crates/*/tests/` and the root package's `tests/*.rs` (see
  `INTERNALS.md`, section 9), and `cargo test --workspace` runs them.

The two run separately, and CI runs both on every platform.

A test that checks a library function's result belongs with the runtime; a
test that checks what the compiler emits or reports stays in Rust.

## Where runtime tests live

| Code under test | Its tests |
| --- | --- |
| A module, `runtime/<module>/` | `runtime/<module>/test/<topic>_test.pep`, which imports the module |
| A prelude file, `runtime/<name>.pep` | `runtime/test/<topic>_test.pep` |
| A file's private functions | `[Test]` functions in that file itself |
| A Pepper tool, `tools/<tool>/` | `tools/<tool>/<topic>_test.pep`, which imports the tool's files (`import "format";`) |

A `test/` folder holds no `module.pep`, so it is never part of the module:
no program that imports the module sees it. Prefer it to tests inside a
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

CI runs `scripts/pepper-tests.sh` after `cargo test --workspace` on
Linux, macOS and Windows.

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
