#!/usr/bin/env bash
# Gives a CI job the Pepper toolchain to build and test with, and
# names the folder of its `pep-build` in PEPPER_COMPILER_DIR (through
# $GITHUB_ENV when it is set, else on standard output).
#
#   scripts/ci-install-toolchain.sh [--version <version>]
#
# It installs a published toolchain with the install scripts, as a user
# would: install.sh, or install.ps1 on Windows, into a fresh home under
# $RUNNER_TEMP. By default that is the newest published toolchain: the
# build of main, the `vX.Y.Z-dev` prerelease release.yml publishes on every
# merge that changes the compiler, the runtime or the tools, or a release
# with a higher version (while main holds a release's version, nothing
# moves the -dev tag). That is whatever version this checkout's VERSION
# file holds, so a change of VERSION (a release, or the next -dev) never
# asks for a build that is not published yet; --version names a release
# instead. The release build, and a CI job testing a commit whose compiler
# this toolchain lacks (ci.yml's `changes` job decides), build the compiler
# with the toolchain this installs.
#
# Environment: GH_TOKEN or GITHUB_TOKEN, to list and download the releases
# while the repository is private; RUNNER_TEMP, where the home goes
# (default: target/); PEPPER_TARGET_DIR, the folder target/ stands for;
# PEPPER_EXPECT_COMMIT, the commit a -dev toolchain must be the build of:
# CI sets it to the merge once its own release has published that build,
# so a job that installs the build before it fails instead.
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
  # The API lists releases newest first (by the commit each tag is on).
  # GitHub sometimes answers it with 200 and `[]` (#196), so a failed or
  # empty answer is tried twice more before failing with what it was.
  url="https://api.github.com/repos/pep-lang/pepper/releases?per_page=100"
  token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  for delay in 2 5 0; do
    # The status goes on a line of its own after the body.
    releases="$(curl -sSL -w '\n%{http_code}' ${token:+-H "Authorization: Bearer $token"} "$url")" || releases=$'\n0'
    status="${releases##*$'\n'}"
    releases="${releases%$'\n'*}"
    if [ "$status" = 200 ] && grep -q '"tag_name"' <<< "$releases"; then
      break
    fi
    if [ "$delay" = 0 ]; then
      message="$(sed -n 's/.*"message": *"\([^"]*\)".*/\1/p' <<< "$releases" | head -1)"
      echo "error: GET $url answered HTTP $status${message:+: $message}, with no release in its ${#releases} bytes, which start: ${releases:0:200}" >&2
      exit 1
    fi
    echo "warning: GET $url answered HTTP $status (${#releases} bytes, no release); trying again in ${delay}s" >&2
    sleep "$delay"
  done
  # The highest version, a release sorting after its own -dev: the -dev tag
  # goes stale whenever main holds a release's version. One field per line,
  # whether the JSON comes pretty-printed or compact.
  version="$(tr ',' '\n' <<< "$releases" | sed -n 's/^ *"tag_name": *"v\([0-9]*\.[0-9]*\.[0-9]*\(-dev\)\{0,1\}\)".*/\1/p' \
    | awk -F'[.-]' '{ print $1, $2, $3, ($4 == "dev" ? 0 : 1), $0 }' \
    | sort -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -d' ' -f5)"
  [ -n "$version" ] || { echo "error: no toolchain (vX.Y.Z release or vX.Y.Z-dev prerelease) is published" >&2; exit 1; }
fi
# A release of a -dev VERSION publishes it with its tag on the commit it
# built (release.yml); a release VERSION publishes nothing until tagged.
expected="${PEPPER_EXPECT_COMMIT:-}"
held="$(tr -d '\r' < VERSION)"
if [ -n "$expected" ] && [ "${held%-dev}" != "$held" ]; then
  built=""
  [ "$version" != "$held" ] || built="$(git ls-remote origin "refs/tags/v$version" | cut -f1)"
  if [ "$built" != "$expected" ]; then
    echo "error: installing Pepper $version (the build of ${built:-another commit}), not the build of $held at $expected that this run's release published" >&2
    exit 1
  fi
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
