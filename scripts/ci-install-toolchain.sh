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
# Windows, into a fresh home under $RUNNER_TEMP. No job builds the
# compiler.
#
# --build builds the compiler with cargo instead, for a change to the
# compiler itself (crates/, Cargo.toml, Cargo.lock), which the published
# build cannot test.
#
# Environment: GH_TOKEN or GITHUB_TOKEN, to list and download the releases
# while the repository is private; RUNNER_TEMP, where the home goes
# (default: target/).
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

if [ "$build" = 1 ]; then
  echo "=== the change touches the compiler: building it with cargo"
  cargo build --workspace --release --locked
  compiler="$target/release"
else
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
fi

"$compiler/pep-build" --version
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "PEPPER_COMPILER_DIR=$compiler" >> "$GITHUB_ENV"
else
  echo "PEPPER_COMPILER_DIR=$compiler"
fi
