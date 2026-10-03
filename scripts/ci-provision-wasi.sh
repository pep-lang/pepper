#!/usr/bin/env bash
# CI-only: install a wasi-sdk and wasmtime for the WebAssembly tests
# (`--target wasm32-wasip1`), and wasm-ld, which LLVM's lld package ships.
#
# The downloads go to $1 (default ~/.cache/pepper-wasi), which outlives the
# job on a self-hosted runner, so each version is fetched once. Prints the
# `WASI_SDK_PATH=` and `WASMTIME=` lines the tests read; CI appends them to
# $GITHUB_ENV. Linux x86_64 only: no other runner runs these tests.
set -euo pipefail

WASI_SDK_VERSION=25
WASMTIME_VERSION=37.0.2
LLVM_MAJOR=${PEPPER_LLVM_MAJOR:-20}

cache=${1:-$HOME/.cache/pepper-wasi}
mkdir -p "$cache"

# wasm-ld, as `wasm-ld-<major>` and under the LLVM prefix.
if ! command -v "wasm-ld-$LLVM_MAJOR" > /dev/null && [ ! -x "/usr/lib/llvm-$LLVM_MAJOR/bin/wasm-ld" ]; then
  sudo apt-get install -y --no-install-recommends "lld-$LLVM_MAJOR" >&2
fi

sdk="$cache/wasi-sdk-$WASI_SDK_VERSION.0-x86_64-linux"
if [ ! -d "$sdk/share/wasi-sysroot" ]; then
  curl --fail --location --silent --show-error --retry 3 \
    "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$WASI_SDK_VERSION/wasi-sdk-$WASI_SDK_VERSION.0-x86_64-linux.tar.gz" \
    | tar -xz -C "$cache"
fi

wasmtime="$cache/wasmtime-v$WASMTIME_VERSION-x86_64-linux/wasmtime"
if [ ! -x "$wasmtime" ]; then
  curl --fail --location --silent --show-error --retry 3 \
    "https://github.com/bytecodealliance/wasmtime/releases/download/v$WASMTIME_VERSION/wasmtime-v$WASMTIME_VERSION-x86_64-linux.tar.xz" \
    | tar -xJ -C "$cache"
fi

"$wasmtime" --version >&2
echo "WASI_SDK_PATH=$sdk"
echo "WASMTIME=$wasmtime"
