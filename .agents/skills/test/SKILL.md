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
```

## Test layout

Expect ~99 passing and 1 ignored.

| Crate | Tests |
|---|---|
| `pepper-parser` | 53 unit tests in `src/parser/parsers.rs` (grammar: literals, expressions, structs, traits, generics) |
| `pepper-sema` | 8 model tests in `src/model_tests.rs` (parse + build + transform → resolved model) |
| `pepper-support` | 6 unit tests in `src/lib.rs` (C ABI runtime support functions) |
| `pepper-codegen` | 16 tests in `tests/codegen_tests.rs` — codegen + JIT, asserting the value `test()` returns |
| `pepper-driver` | 15 tests in `tests/compile_tests.rs` (14 JIT value tests + `full_pipeline_link_and_spawn`, which emits an object, links it, and runs the binary) |
| `pepper-driver` | 1 `#[ignore]`d test in `tests/corpus_tests.rs` (compile-and-run the corpus) |
| root `pepper` | `tests/parser_corpus.rs` — every `tests/**/*.pep` file must parse into a well-formed module |

`tests/` also holds the `.pep` fixtures: standalone files at the root (`hello.pep`, `array.pep`, `string.pep`, `struct.pep`, `debug.pep`) and one `test.pep` per feature folder.

## Corpus behavior

- `tests/parser_corpus.rs` treats the corpus as the executable spec for the parser: every file must parse with at least one declaration. Adding a `.pep` file extends it automatically.
- `crates/pepper-driver/tests/corpus_tests.rs` compiles and runs each `tests/<Name>/test.pep`. It is `#[ignore]`d because most fixtures still fail on unimplemented features (generics in extensions, trait dispatch, string internals). Ignored ≠ passing — don't count it toward success, and check its progress with `-- --ignored`.

## Diagnosing failures

1. Re-run the single test with `--nocapture` to see its own output.
2. A JIT test that dies with a native fault (`STATUS_ACCESS_VIOLATION` / SIGSEGV) rather than an assertion is usually not a bad-IR problem. Two causes have bitten before: generated code calling a support function that the JIT could not resolve (`pepper-support::support_symbols()` must list it, since `pepper-codegen` binds that table into the engine with `add_global_mapping` — a static rlib's symbols aren't in the process export table), and LLVM CRT mismatch on Windows (see the **build** skill).
3. To decide between malformed IR and a runtime fault, dump the module with `Module::print_to_stderr()` before `verify()` — printing streams inside LLVM, so partial output pinpoints a bad construct.
4. For a parse failure, reproduce standalone with the parse-only path: `cargo run -- --emit-ast tests/<Name>/test.pep`. Plain `cargo run -- tests/<Name>/test.pep` runs the whole pipeline (sema, codegen, object emission, link), so it can fail for reasons that have nothing to do with parsing.
