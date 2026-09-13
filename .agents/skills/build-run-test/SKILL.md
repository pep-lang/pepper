---
name: build-run-test
display-name: Build / Run / Test
description: Build, run, and test the Pepper compiler project. Use when configuring, building, running the compiler, or running tests for this repository.
---

# Pepper — Build, Run, Test

Pepper is a compiled programming language. The compiler is written in C++ (CMake + Ninja). A complete Rust parser in `src/` parses the language (and the `tests/` corpus) before codegen.

## Build

### Configure (one-time, per preset)

```bash
# Windows (MSVC)
cmake --preset win-msvc-x64-debug

# macOS
cmake --preset mac-llvm-clang-x64-debug

# Linux
cmake --preset linux-clang-x64-debug
```

### Build

```bash
# Windows
cmake --build out/build/win-msvc-x64-debug --parallel

# macOS
cmake --build out/build/mac-llvm-clang-x64-debug --parallel

# Linux
cmake --build out/build/linux-clang-x64-debug --parallel
```

> **Note:** LLVM 17 is built locally in `deps/llvm/` on first configure. This takes a long time. If `deps/llvm/install/` already exists, re-configure is fast.

### Release build (Windows)

```bash
cmake --preset win-msvc-x64-release
cmake --build out/build/win-msvc-x64-release --parallel
```

## Run the Compiler

The compiler executable lives at:
- Windows: `out/build/<preset>/bin/pepper.exe`
- macOS / Linux: `out/build/<preset>/bin/pepper`

```bash
# JIT-compile and run a .pep file
out/build/win-msvc-x64-debug/bin/pepper.exe tests/hello.pep

# Emit LLVM IR instead of executing
out/build/win-msvc-x64-debug/bin/pepper.exe --emit-llvm tests/hello.pep
```

Example `.pep` files are in `tests/` (e.g. `hello.pep`, `string.pep`, `struct.pep`).

## Tests

Unit tests are GoogleTest-based (`unittests/`). Test cases reference `.pep` files in `tests/`.

### Run all tests

```bash
# Windows
ctest --preset windows

# macOS
ctest --preset mac

# Or explicitly (any platform)
ctest --test-dir out/build/win-msvc-x64-debug --output-on-failure
```

### Run a single test

```bash
ctest --test-dir out/build/win-msvc-x64-debug -R "TestName" --output-on-failure
```

### Run the test binary directly

```bash
# Windows
out/build/win-msvc-x64-debug/unittests/PepperTests.exe --gtest_filter="SomeTest.*"

# macOS / Linux
out/build/mac-llvm-clang-x64-debug/unittests/PepperTests --gtest_filter="SomeTest.*"
```

## Rust Parser (`src/`)

Separate from the C++ build. A complete, strict recursive-descent parser of the Pepper language (see `source/Parser/LexyParser.h` for the reference grammar). It parses the whole `tests/` corpus; the corpus is the executable spec — the parser must accept all of it and fail loudly on anything else.

```bash
cargo build
cargo test        # 53 unit tests + 1 integration test over every tests/**/*.pep file
```

Run the parser CLI (debug binary at `target/debug/pepper`):

```bash
target/debug/pepper tests/hello.pep            # parse only; prints OK + import/decl counts
target/debug/pepper tests/array.pep --emit-ast # print the parsed AST as text
target/debug/pepper a.pep b.pep                # multiple files; non-zero exit on any error
```

Useful corpus check (all files must say `OK`):

```bash
for f in $(find tests -name "*.pep"); do target/debug/pepper "$f" 2>&1 | tail -1; done
```

## Key Paths

| What | Path |
|---|---|
| C++ compiler source | `source/` |
| Rust parser (complete) | `src/` (lib + `main.rs` CLI; corpus test in `tests/parser_corpus.rs`) |
| Test `.pep` files | `tests/` |
| Unit test sources | `unittests/` |
| LLVM (local build) | `deps/llvm/` |
| Build output (Windows debug) | `out/build/win-msvc-x64-debug/` |
| CMake presets | `CMakePresets.json` |
