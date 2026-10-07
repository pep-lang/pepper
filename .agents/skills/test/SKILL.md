---
name: test
description: Run the Pepper project's tests, Pepper [Test] functions run with pepper test (scripts/pepper-tests.sh). Use when asked to test, run tests, or verify changes to the compiler, parser, sema, codegen, runtime or tools.
---

# Testing Pepper

## Run tests

The tests are Pepper `[Test]` functions, run with `pepper test`. They build with the installed toolchain: the build of main, which every merge that changes the compiler, the runtime or the tools publishes as the `x.y.z-dev` prerelease named by `Cargo.toml`'s version (#713). Install or refresh it, then run them all:

```bash
sh scripts/install.sh --version "$(sed -nE 's/^version = "([^"]+)"/\1/p' Cargo.toml | head -n 1)" --yes
scripts/pepper-tests.sh
scripts/pepper-tests.sh -f parses     # by name
```

Only a change to the Rust compiler itself (`crates/`) needs a cargo build, passed as the first argument: `cargo build --release && scripts/pepper-tests.sh target/release` (LLVM must be provisioned for that; see the **build** skill). See `docs/src/contributing/tests.md`.

The Rust compiler's own tests (`cargo test --workspace`) are still in the repository, but neither CI nor the pre-merge checks run them (#662). Run them only when asked, or when changing the Rust compiler's internals:

```bash
cargo test --workspace --test integration compile_tests::  # one driver test module
cargo test --workspace int_add                 # filter by test name (substring)
```

`--workspace` matters: the repo root is itself a package, so a bare `cargo test` runs only the root package's tests and silently skips every crate under `crates/`.

## Rust test layout

The suite has several hundred tests and grows with nearly every change, so
no count is kept here: a run is good when every `test result:` line says
`0 failed`. No test is `#[ignore]`d.

| Where | What |
|---|---|
| `pepper-parser` | unit tests in `src/parser/parsers.rs` (grammar), `src/parser.rs` and `src/diagnostic.rs` (error rendering) |
| `pepper-sema` | model tests in `src/model_tests.rs` (parse + build + transform → resolved model) and visibility tests in `src/visibility.rs` |
| `pepper-codegen` | `src/target.rs`: the host's own triple resolves to a target machine. It runs alone in its binary because inkwell's execution-engine constructors register the host backend as a side effect, which a JIT test running first could mask. `tests/codegen_tests.rs`: codegen + JIT, asserting the value `test()` returns |
| `pepper-files` | runtime discovery (`src/runtime.rs`) |
| `pepper-driver` | one integration test binary, `tests/integration/main.rs`, with a module per feature in `tests/integration/*_tests.rs` (add new ones there, not as new `tests/*.rs` binaries): most JIT a `test()` function and assert its value; some link and run a binary. `diagnostic_tests.rs` asserts rendered compiler errors (header, source line, caret). `audit_fixes_tests.rs` holds regression tests for bugs found by the docs audit. `corpus_tests.rs` runs every corpus fixture (see below) |
| `tools/lsp` | language server tests in `src/tests.rs` |
| `xtask` | unit tests in `src/main.rs` for the setup scripts' flag handling and generated cargo config |

`tests/` also holds the `.pep` fixtures: `hello.pep` at the root (the README's example) and one `test.pep` per feature folder.

## Corpus behavior

- `crates/pepper-driver/tests/integration/corpus_tests.rs` compiles and runs each `tests/<Name>/test.pep`. Every fixture must exit 0; a new `tests/<Name>/test.pep` joins the run automatically.

## Diagnosing failures

1. Re-run the single test with `--nocapture` to see its own output.
2. A JIT test that dies with a native fault (`STATUS_ACCESS_VIOLATION` / SIGSEGV) rather than an assertion is usually not a bad-IR problem. Two causes have bitten before: generated code calling a function that is neither in the module nor exported by the host process (the runtime lives in `runtime/*.pep`, merged into every test module — if the name resolves to nothing, `call_function` errors with `unknown function`), and LLVM CRT mismatch on Windows (see the **build** skill).
3. To decide between malformed IR and a runtime fault, dump the module with `Module::print_to_stderr()` before `verify()` — printing streams inside LLVM, so partial output pinpoints a bad construct.
4. For a parse failure, reproduce standalone with the parse-only path: `cargo run -- --emit-ast tests/<Name>/test.pep`. Plain `cargo run -- tests/<Name>/test.pep` runs the whole pipeline (sema, codegen, object emission, link), so it can fail for reasons that have nothing to do with parsing.
