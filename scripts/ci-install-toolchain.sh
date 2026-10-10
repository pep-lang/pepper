#!/usr/bin/env bash
# Gives a CI job the Pepper toolchain to build and test with (#713), and
# names the folder of its `pep-build` in PEPPER_COMPILER_DIR (through
# $GITHUB_ENV when it is set, else on standard output).
#
#   scripts/ci-install-toolchain.sh [--version <version>]
#
# It installs a published toolchain with the install scripts, as a user
# would: install.sh, or install.ps1 on Windows, into a fresh home under
# $RUNNER_TEMP. By default that is the build of main, the prerelease named
# by the version this checkout's VERSION file holds (`0.4.0-dev`, which
# release.yml publishes on every merge that changes the compiler, the
# runtime or the tools); --version names another release (release.yml's
# stage 0). No job builds the compiler except the release build, which
# builds it with the toolchain this installs.
#
# Environment: GH_TOKEN or GITHUB_TOKEN, to list and download the releases
# while the repository is private; RUNNER_TEMP, where the home goes
# (default: target/); PEPPER_TARGET_DIR, the folder target/ stands for.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
target="${PEPPER_TARGET_DIR:-$root/target}"

version=""
case "${1:-}" in
  --version)
    version="${2:-}"
    [ -n "$version" ] || { echo "usage: ci-install-toolchain.sh [--version <version>]" >&2; exit 2; }
    ;;
  "") ;;
  *) echo "usage: ci-install-toolchain.sh [--version <version>]" >&2; exit 2 ;;
esac

windows=0
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=1 ;;
esac

if [ -z "$version" ]; then
  version="$(tr -d '\r' < VERSION)"
  [ -n "$version" ] || { echo "error: no version in VERSION" >&2; exit 1; }
fi
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

"$compiler/pep-build" --version
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "PEPPER_COMPILER_DIR=$compiler" >> "$GITHUB_ENV"
else
  echo "PEPPER_COMPILER_DIR=$compiler"
fi
