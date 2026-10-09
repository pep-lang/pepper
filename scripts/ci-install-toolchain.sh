#!/usr/bin/env bash
# Gives a CI job the Pepper toolchain to build and test with (#713), and
# names the folder of its `pep-build` in PEPPER_COMPILER_DIR (through
# $GITHUB_ENV when it is set, else on standard output).
#
#   scripts/ci-install-toolchain.sh [--build]
#
# By default it installs the build of main, the prerelease named by the
# version this checkout holds (`0.4.0-dev`, which release.yml publishes on
# every merge that changes the compiler, the runtime or the tools), with
# the install scripts, as a user would: install.sh, or install.ps1 on
# Windows, into a fresh home under $RUNNER_TEMP.
#
# --build is for a change to the compiler itself (tools/compiler), which
# the published build cannot test: the published pep-build builds pepc
# from this checkout, and that pepc then compiles its own sources, so a
# change the compiler rejects in itself fails here rather than in the
# release build of main. The suite then tests with the pepc built here.
# It fetches the private pepper-llvm package: source
# scripts/ci-package-auth.sh first, with PEPPER_LLVM_DEPLOY_KEY set.
#
# Environment: GH_TOKEN or GITHUB_TOKEN, to list and download the releases
# while the repository is private; RUNNER_TEMP, where the home goes
# (default: target/); LLVM_SYS_201_PREFIX, LLVM's folder on macOS and
# Windows (default: the one scripts/setup-llvm.sh wrote to
# .cargo/config.toml).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
target="${CARGO_TARGET_DIR:-$root/target}"

build=0
case "${1:-}" in
  --build) build=1 ;;
  "") ;;
  *) echo "usage: ci-install-toolchain.sh [--build]" >&2; exit 2 ;;
esac

windows=0
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=1 ;;
esac

version="$(sed -nE '/^\[workspace\.package\]/,/^\[/s/^version = "([^"]+)"/\1/p' Cargo.toml)"
[ -n "$version" ] || { echo "error: no [workspace.package] version in Cargo.toml" >&2; exit 1; }
home="${RUNNER_TEMP:-$target}/pepper-home"
rm -rf "$home"
echo "=== installing Pepper $version into $home"
if [ "$windows" = 1 ]; then
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 \
    -Version "$version" -Prefix "$(cygpath -w "$home")" -NoModifyPath -NoPrerequisites
else
  sh scripts/install.sh --version "$version" --prefix "$home" --no-modify-path --no-prerequisites < /dev/null
fi
exe=""
[ "$windows" = 0 ] || exe=".exe"
installed="$(PEPPER_TOOLCHAIN= "$home/bin/pepper$exe" install which | sed -n 2p | tr -d '\r')"
[ -n "$installed" ] || { echo "error: the install names no pep-build" >&2; exit 1; }
if [ "$windows" = 1 ]; then
  installed="$(cygpath -u "$installed")"
fi
compiler="$(dirname "$installed")"

if [ "$build" = 1 ]; then
  echo "=== the change touches the compiler: building pepc from this checkout"
  # Optimized, as the suite compiles every test program with it. The cache
  # (under the target dir, which self-hosted runners keep) rebuilds only
  # the files a change touches; a cold build takes about ten minutes.
  # pepper-llvm links LLVM: Linux finds it on the default search path;
  # macOS and Windows need its folder, and Windows its DLL beside pepc
  # (as scripts/pepper-tests.sh does for the compiler's tests).
  llvm=()
  llvm_prefix="${LLVM_SYS_201_PREFIX:-}"
  if [ -z "$llvm_prefix" ] && [ -f .cargo/config.toml ]; then
    llvm_prefix="$(sed -nE 's/^LLVM_SYS_[0-9]+_PREFIX *= *"(.*)".*/\1/p' .cargo/config.toml | head -1 | sed 's/\\\\/\\/g')"
  fi
  if [ -n "$llvm_prefix" ] && [ "$(uname -s)" != Linux ]; then
    llvm=(-L "$llvm_prefix/lib")
  fi
  stage="$target/pepc-stage"
  rm -rf "$stage"
  mkdir -p "$stage/bin"
  if [ "$windows" = 1 ] && [ -n "$llvm_prefix" ]; then
    cp "$(cygpath -u "$llvm_prefix")/bin/LLVM-C.dll" "$stage/bin/"
  fi
  export PEPPER_RUNTIME="$root/runtime"
  "$compiler/pep-build$exe" -O -I tools tools/compiler/main.pep -o "$stage/bin/pep-build$exe" \
    --build "$stage/build" --cache "$target/pepc-cache" "${llvm[@]+"${llvm[@]}"}"
  # The new pepc compiles itself as far as LLVM IR: its own sources
  # through every check and pass, without the time an object takes.
  echo "=== pepc compiles its own sources"
  "$stage/bin/pep-build$exe" -I tools tools/compiler/main.pep --emit-llvm --build "$stage/self" --no-cache > /dev/null
  compiler="$stage/bin"
fi

"$compiler/pep-build" --version
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "PEPPER_COMPILER_DIR=$compiler" >> "$GITHUB_ENV"
else
  echo "PEPPER_COMPILER_DIR=$compiler"
fi
