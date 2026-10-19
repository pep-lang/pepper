#!/usr/bin/env bash
# Builds the checkout's compiler (tools/compiler) with the installed
# toolchain's pep-build, for a CI job testing a change to the compiler: the
# published build of main cannot test it. Like the release's stage 1
# (scripts/release-build.sh), but linked against LLVM's shared library, as
# the compiler's own tests link it. It then names the new compiler's folder
# in PEPPER_COMPILER_DIR (through $GITHUB_ENV when it is set, else on
# standard output), so every later step tests with it.
#
#   scripts/ci-build-compiler.sh
#
# Environment: PEPPER_COMPILER_DIR, the installed toolchain's folder
# (scripts/ci-install-toolchain.sh); PEPPER_TARGET_DIR, the folder target/
# stands for. macOS and Windows find
# LLVM as scripts/pepper-tests.sh does: PEPPER_LLVM_PREFIX, else the prefix
# scripts/setup-llvm.sh or .ps1 wrote to .pep/llvm-prefix.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
target="${PEPPER_TARGET_DIR:-$root/target}"

stage0="${PEPPER_COMPILER_DIR:-}"
[ -n "$stage0" ] || { echo "error: PEPPER_COMPILER_DIR names no toolchain (run scripts/ci-install-toolchain.sh first)" >&2; exit 1; }
exe=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) exe=".exe"; stage0="$(cygpath -u "$stage0")" ;;
esac

llvm=()
llvm_prefix="${PEPPER_LLVM_PREFIX:-}"
if [ -z "$llvm_prefix" ] && [ -f .pep/llvm-prefix ]; then
  llvm_prefix="$(tr -d '\r' < .pep/llvm-prefix | head -1)"
fi
if [ -n "$llvm_prefix" ] && [ "$(uname -s)" != Linux ]; then
  llvm=(-L "$llvm_prefix/lib")
fi

out="$target/compiler"
mkdir -p "$out"
export PEPPER_RUNTIME="$root/runtime"
echo "=== building tools/compiler with $("$stage0/pep-build$exe" --version)"
# Fetched up front, so a failed fetch shows pep-package's own error.
"$stage0/pep-package$exe" -C tools/compiler fetch
# shortcut: a stage 0 older than 0.10.0-dev (v0.9.4 too) fails on the
# runtime's number extensions that declare `Comparable` when it checks
# a compilation unit again, so it builds without compilation
# units. Drop the variable once the published stage 0 is 0.10.0-dev or
# later.
PEPC_NO_COMPILATION_UNITS=1 "$stage0/pep-build$exe" -O tools/compiler/main.pep \
  -o "$out/pep-build$exe" --build "$out/build" "${llvm[@]+"${llvm[@]}"}"
# pepc loads LLVM-C.dll from its own folder.
if [ -n "$exe" ]; then
  cp -f "$stage0/LLVM-C.dll" "$out/"
fi
"$out/pep-build$exe" --version

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "PEPPER_COMPILER_DIR=$out" >> "$GITHUB_ENV"
else
  echo "PEPPER_COMPILER_DIR=$out"
fi
