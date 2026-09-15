---
name: legacy_build
description: Configure and build the Pepper compiler project with CMake (Ninja + MSVC) on Windows. Use when asked to build, compile, or reconfigure the project.
---

# Building Pepper

Pepper is a C++23 compiler built with CMake + Ninja + MSVC. The established build tree is `D:/pepper/build` (Release). Do not create other build trees unless asked.

## Environment

A plain shell does NOT have the MSVC toolchain or CMake on PATH. Every configure/build command must run inside a Visual Studio environment:

- vcvars: `C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat`
- CMake/CTest: `C:\Program Files\CMake\bin` (CMake 4.x; not on PATH)
- Ninja: bundled with VS at `C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja` (not on PATH)

For a non-interactive shell (e.g. Git Bash), wrap everything in one `cmd //c` invocation:

```bash
cmd //c 'call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" && set "PATH=C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%" && "C:\Program Files\CMake\bin\cmake.exe" --build D:/pepper/build --parallel'
```

(Alternative: use the CMake bundled with VS at `...\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`, which finds the VS-bundled Ninja automatically; then the PATH tweak is unnecessary.)

## Configure (first time, or after any CMakeLists.txt change)

```bat
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_DEPS=ON -S D:/pepper -B D:/pepper/build
```

- `BUILD_DEPS=ON` is only expensive on the very first run: it fetches and builds LLVM 23.1.1 + lld into `deps/llvm/install/Release` (can take a long time). Once that exists, reconfigure finds it via `find_package` and skips it. fmt, Boost parser, and lexy come from FetchContent into `build/_deps`.
- The build is already configured in this repo; only re-run configure when CMake files changed or you get generator/cache errors.

## Build

```bat
cmake --build D:/pepper/build --parallel
```

Notes:

- The `pepper` target post-build step copies `lli.exe`, `lld-link.exe`, and `llvm-lib.exe` next to `pepper.exe`; the `PepperTests` target (in `unittests/`) does the same. Don't move these files.
- Build errors are MSVC C++ errors in `source/` — read them, fix, rebuild.
- Never delete `deps/llvm/install` or `deps/*/build` to "clean"; that forces a full LLVM rebuild. To clean just Pepper's objects, delete `D:/pepper/build` (dependencies survive).

## Verify

A good build ends with `pepper.exe`, `PepperTests.exe`, and their helper exes present under `D:/pepper/build/`. Use the test skill to verify behavior after building.
