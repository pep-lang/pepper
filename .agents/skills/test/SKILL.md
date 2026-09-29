---
name: test
description: Run the Pepper project's test suite with cargo test. Use when asked to test, run tests, or verify changes to the compiler, parser, sema, or codegen.
---

# Testing Pepper

## Run tests

```bash
cargo test --workspace
```

`--workspace` matters: the repo root is itself a package, so a bare `cargo test` runs only the root package's tests (the `.pep` corpus test) and silently skips every crate under `crates/`.

The workspace must be built first, which needs LLVM provisioned — see the **build** skill if `llvm-sys` reports it cannot find LLVM.

Useful variants:

```bash
cargo test -p pepper-codegen                   # one crate
cargo test --workspace --test compile_tests    # one integration test binary
cargo test --workspace int_add                 # filter by test name (substring)
cargo test --workspace -- --ignored            # run #[ignore]d tests
cargo test --workspace -- --nocapture          # show println!/eprintln! output

# against an LLVM other than the default 20 (must be provisioned first)
cargo test --workspace --no-default-features --features llvm19-1
```

## Test layout

The suite has several hundred tests and grows with nearly every change, so
no count is kept here: a run is good when every `test result:` line says
`0 failed`. A few tests are `#[ignore]`d on purpose (see **Corpus
behavior**).

| Where | What |
|---|---|
| `pepper-parser` | unit tests in `src/parser/parsers.rs` (grammar), `src/parser.rs` and `src/diagnostic.rs` (error rendering) |
| `pepper-sema` | model tests in `src/model_tests.rs` (parse + build + transform → resolved model) and visibility tests in `src/visibility.rs` |
| `pepper-codegen` | `src/target.rs`: the host's own triple resolves to a target machine. It runs alone in its binary because inkwell's execution-engine constructors register the host backend as a side effect, which a JIT test running first could mask. `tests/codegen_tests.rs`: codegen + JIT, asserting the value `test()` returns |
| `pepper-files` | runtime discovery (`src/runtime.rs`) |
| `pepper-driver` | one integration test binary per feature in `tests/*_tests.rs`: most JIT a `test()` function and assert its value; some link and run a binary. `diagnostic_tests.rs` asserts rendered compiler errors (header, source line, caret). `audit_fixes_tests.rs` holds regression tests for bugs found by the docs audit. `corpus_tests.rs` is `#[ignore]`d (see below) |
| `tools/lsp` | language server tests in `src/tests.rs` |
| root `pepper` | `tests/parser_corpus.rs`: every `tests/**/*.pep` file must parse into a well-formed module |
| `xtask` | unit tests in `src/main.rs` for the setup scripts' flag handling and generated cargo config |

`tests/` also holds the `.pep` fixtures: standalone files at the root (`hello.pep`, `array.pep`, `string.pep`, `struct.pep`, `debug.pep`) and one `test.pep` per feature folder.

## Corpus behavior

- `tests/parser_corpus.rs` treats the corpus as the executable spec for the parser: every file must parse with at least one declaration. Adding a `.pep` file extends it automatically.
- `crates/pepper-driver/tests/corpus_tests.rs` compiles and runs each `tests/<Name>/test.pep`. It is `#[ignore]`d because most fixtures still fail on unimplemented features (generics in extensions, trait dispatch, string internals). Ignored ≠ passing — don't count it toward success, and check its progress with `-- --ignored`.

## Diagnosing failures

1. Re-run the single test with `--nocapture` to see its own output.
2. A JIT test that dies with a native fault (`STATUS_ACCESS_VIOLATION` / SIGSEGV) rather than an assertion is usually not a bad-IR problem. Two causes have bitten before: generated code calling a function that is neither in the module nor exported by the host process (the runtime lives in `runtime/*.pep`, merged into every test module — if the name resolves to nothing, `call_function` errors with `unknown function`), and LLVM CRT mismatch on Windows (see the **build** skill).
3. To decide between malformed IR and a runtime fault, dump the module with `Module::print_to_stderr()` before `verify()` — printing streams inside LLVM, so partial output pinpoints a bad construct.
4. For a parse failure, reproduce standalone with the parse-only path: `cargo run -- --emit-ast tests/<Name>/test.pep`. Plain `cargo run -- tests/<Name>/test.pep` runs the whole pipeline (sema, codegen, object emission, link), so it can fail for reasons that have nothing to do with parsing.
