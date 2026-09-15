---
name: legacy_test
description: Build the Pepper project first, then run its test suite with ctest. Use when asked to test, run tests, or verify changes to the compiler.
---

# Testing Pepper

The test suite is a gtest binary (`PepperTests`) driven by ctest. Each `CompileTest` compiles and JIT-runs a `.pep` file from `tests/`, so a full run takes several minutes — start it with a long timeout or in the background, and don't assume it hung.

## Step 1: Build first (required)

Tests must be built before ctest can see them: `gtest_discover_tests` registers tests at build time, and the post-build step copies `.env` (which sets `PEP_SEARCH_DIR`) and `TestSupport.pep` next to `PepperTests.exe`. A stale or missing build yields zero or crashing tests.

Follow the **legacy_build** skill: configure if CMake files changed, then

```bat
cmake --build D:/pepper/build --parallel
```

(remember the vcvars + Ninja PATH setup from the build skill; `cl.exe` won't work without it)

## Step 2: Run ctest

```bat
"C:\Program Files\CMake\bin\ctest.exe" --test-dir D:/pepper/build -C Release --output-on-failure
```

cTest itself does not need the MSVC environment, but running both steps in one `cmd //c` session (as in the build skill) is simplest.

Useful variants:

- Filter by name (regex): add `--tests-regex "Structs.*"`
- Re-run only failures: `ctest --rerun-failed --test-dir D:/pepper/build -C Release --output-on-failure`
- List tests without running: `ctest --test-dir D:/pepper/build -N`

Do NOT use `ctest --preset windows`: it points at a different tree (`out/build/win-msvc-x64-debug`) and would trigger a separate Debug configure + build. Always target `D:/pepper/build`.

## Reporting

- Expect ~100 tests (the count grows as `tests/` folders are added).
- Report the pass/fail summary line ctest prints at the end.
- On failure, show the failing test's output (`--output-on-failure` already does this) and note which `.pep` file under `tests/<Name>/test.pep` it compiles — that is usually where the bug reproduces. Reproduce standalone with `D:/pepper/build/pepper.exe tests/<Name>/test.pep` if needed.
