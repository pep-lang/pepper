# Testing the runtime and the compiler

The repository has two kinds of tests, split by what they check.

- **The runtime and the Pepper tools** are tested in Pepper: `[Test]`
  functions (see [Unit tests](../language/testing.md)) that
  [`pep-test`](../tools/pep-test.md) builds and runs.
- **The compiler** is tested in Rust: diagnostics, codegen and IR facts,
  reference-count order, optimization, linking, cross-compiling, debug
  info, the build cache, the documentation checks, and the drivers. These
  live in `crates/*/tests/` and the root package's `tests/*.rs` (see
  `INTERNALS.md`, section 9).

A test that checks a library function's result belongs with the runtime; a
test that checks what the compiler emits or reports stays in Rust.

## Where runtime tests live

| Code under test | Its tests |
| --- | --- |
| A module, `runtime/<module>/` | `runtime/<module>/test/<topic>_test.pep`, which imports the module |
| A prelude file, `runtime/<name>.pep` | `runtime/test/<topic>_test.pep` |
| A file's private functions | `[Test]` functions in that file itself |

A `test/` folder holds no `module.pep`, so it is never part of the module:
no program that imports the module sees it. Prefer it to tests inside a
source file, which only a test of private internals needs. The reference
generator and the doc-comment check skip `test/` folders, so a test file
needs no `##` comments.

## Running them

```bash
cargo build --release
target/release/pep-build -I tools tools/pep-test/main.pep -o target/release/pep-test
cd runtime
../target/release/pep-test                       # every runtime test
../target/release/pep-test json/test             # one module's
../target/release/pep-test -f parses test        # by name
```

Tests run with `runtime/` as the current folder, so a test reads data
files kept beside it by a path from there (`archive/test/gnu.tar.gz`).
The builds go to `runtime/.pep/`, which git ignores. A test that writes
files uses a fresh folder under the system's temporary folder
(`TempFolder` in the `testing` module makes and removes one).

`cargo test --workspace` runs them all too, on every platform CI runs:
`the_runtime_tests_pass` in the root package's `tests/pep_test_tool.rs`
builds `pep-test` with this source's `pep-build` and runs it in
`runtime/`.

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
