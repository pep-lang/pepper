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
# From a build cache of its own beside the compiler, which ci.yml carries
# between runs. Its keys name stage 0 by its contents, not by its path,
# size and time: each job installs stage 0 afresh, with a new time, which
# would miss every key.
#
# In compilation units, so a compiler change rebuilds only the units it
# reaches. Since #183 a worker peaks at about 1.6 GB, so one per processor
# fits a 4-core, 16 GB runner, and two fit macOS's 7 GB.
jobs=4
[ "$(uname -s)" != Darwin ] || jobs=2
identity="stage0 $(git hash-object "$stage0/pep-build$exe")"
echo "=== stage 0 identity: $identity"
log="$out/build.log"
# The workers' timings from earlier runs, which the cache would carry.
rm -rf "$out/build"/compilation-units.*
PEPC_COMPILATION_UNIT_JOBS="$jobs" PEPC_COMPILER_IDENTITY="$identity" PEPPER_CACHE_DIR="$out/cache" \
  "$stage0/pep-build$exe" -O tools/compiler/main.pep -T time -T cache \
  -o "$out/pep-build$exe" --build "$out/build" "${llvm[@]+"${llvm[@]}"}" 2> "$log" || { cat "$log" >&2; exit 1; }
# The stages' times, and how many compilation units the cache supplied.
grep '^time:' "$log" || true
grep -E '^cache: [0-9]+ of [0-9]+ compilation units' "$log" || true
# The largest worker's peak memory (each worker's `-T time` stages end with it).
find "$out/build" -name '*.stages' -exec grep -h '^peak ' {} + | sort -n -k2 | tail -1 | sed 's/^/workers: /' || true
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
