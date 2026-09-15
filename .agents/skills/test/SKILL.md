---
name: test
description: Run the Pepper project's test suite with cargo test. Use when asked to test, run tests, or verify changes to the compiler.
---

# Testing Pepper

Standard `cargo test` across the workspace. No special setup.

## Run tests

```bash
cargo test
```

Useful variants:

```bash
cargo test -p pepper-parser                    # one crate
cargo test --test compile_tests                # one integration test binary
cargo test int_add                             # filter by test name (substring)
cargo test -- --ignored                        # run #[ignore]d tests
cargo test -- --nocapture                      # show println!/eprintln! output
```

## Test layout

| Crate | What it tests |
|---|---|
| `pepper-parser` | 53 unit tests in `crates/pepper-parser/src/parser/parsers.rs` (grammar: literals, expressions, structs, traits, generics) |
| `pepper-sema` | 8 model tests in `crates/pepper-sema/src/model_tests.rs` (parse + build + transform → resolved model) |
| `pepper-support` | 6 unit tests in `crates/pepper-support/src/lib.rs` (C ABI runtime support functions) |
| `pepper-codegen` | `crates/pepper-codegen/tests/codegen_tests.rs` (JIT value tests: math, branches, functions, loops) |
| `pepper-driver` | `crates/pepper-driver/tests/compile_tests.rs` (end-to-end compile tests) + `crates/pepper-driver/tests/corpus_tests.rs` (corpus compile-and-run) |
| root `pepper` | `tests/parser_corpus.rs` — every `tests/**/*.pep` file must parse into a well-formed module |

The `tests/` directory also holds `.pep` fixtures: standalone files at the root (`hello.pep`, `array.pep`, `string.pep`, `struct.pep`, `debug.pep`) and one `test.pep` per folder for the corpus test.

## Corpus behavior

- `tests/parser_corpus.rs` treats the whole corpus as the executable spec for the parser: all files must parse with at least one declaration.
- `crates/pepper-driver/tests/corpus_tests.rs` compiles each `tests/<Name>/test.pep` and runs it; some fixtures are currently `#[ignore]`d pending feature work. Ignored ≠ passing — don't count them toward success.

## Debugging a failure

1. Re-run with `cargo test <name> -- --nocapture` to see the failure's own output.
2. For a parse failure, reproduce standalone: `target/debug/pepper tests/<Name>/test.pep` (parse-only; prints `OK` + import/decl counts, non-zero exit on error). `--emit-ast` dumps the parsed AST.
