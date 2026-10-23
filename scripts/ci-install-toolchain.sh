#!/usr/bin/env bash
# Gives a CI job the Pepper toolchain to build and test with, and
# names the folder of its `pep-build` in PEPPER_COMPILER_DIR (through
# $GITHUB_ENV when it is set, else on standard output).
#
#   scripts/ci-install-toolchain.sh [--newest | --version <version>]
#
# It installs a published toolchain with the install scripts, as a user
# would: install.sh, or install.ps1 on Windows, into a fresh home under
# $RUNNER_TEMP. By default that is stage 0, the build of main that
# .github/stage0 pins: the release build, scripts/stage0-check.sh, Docs,
# and a CI job testing a commit whose compiler the build of main lacks
# (ci.yml's `changes` job decides) build with it. The pin names the build's
# version and commit and each archive's SHA-256 sum, which the install
# checks. The archives are copies on the `stage0` release, named
# `<commit>-<asset>` (the commit's first 12 hex digits), since the build
# of main replaces its own on every merge. The Stage 0 workflow
# (.github/workflows/stage0.yml) moves the pin.
#
# --newest installs the newest published toolchain instead, which CI tests
# a commit with when its compiler is the build of main's: the `vX.Y.Z-dev`
# prerelease release.yml publishes on every merge that changes the
# compiler, the runtime or the tools, or a release with a higher version
# (while main holds a release's version, nothing moves the -dev tag).
# --version names a release.
#
# Environment: GH_TOKEN or GITHUB_TOKEN, to list and download the releases
# while the repository is private; RUNNER_TEMP, where the home goes
# (default: target/); PEPPER_TARGET_DIR, the folder target/ stands for;
# PEPPER_EXPECT_COMMIT, the commit a -dev toolchain that --newest or
# --version installs must be the build of: CI sets it to the merge once
# its own release has published that build, so a job that installs the
# build before it fails instead.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
target="${PEPPER_TARGET_DIR:-$root/target}"

usage="usage: ci-install-toolchain.sh [--newest | --version <version>]"
mode=pin
version=""
case "${1:-}" in
  --version)
    mode=version
    version="${2:-}"
    [ -n "$version" ] || { echo "$usage" >&2; exit 2; }
    ;;
  --newest) mode=newest ;;
  "") ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

windows=0
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=1 ;;
esac

if [ "$mode" = newest ]; then
  api="https://api.github.com/repos/pep-lang/pepper"
  token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  # Gets the API url $1 into $body, whose answer must name the key $2.
  # GitHub sometimes answers with 200 and `[]` (its list of releases does,
  # often: #196), so a failed or empty answer is asked again after each
  # delay in $3; a 404 is not. Fails with got and status set for api_die.
  api_get() {
    local delay
    got="$1"
    for delay in $3 0; do
      # The status goes on a line of its own after the body.
      body="$(curl -sSL -w '\n%{http_code}' ${token:+-H "Authorization: Bearer $token"} "$1")" || body=$'\n0'
      status="${body##*$'\n'}"
      body="${body%$'\n'*}"
      if [ "$status" = 200 ] && grep -q "\"$2\"" <<< "$body"; then
        return 0
      fi
      [ "$status" != 404 ] || return 1
      [ "$delay" = 0 ] || { echo "warning: GET $1 answered HTTP $status (${#body} bytes, no \"$2\"); trying again in ${delay}s" >&2; sleep "$delay"; }
    done
    return 1
  }
  api_die() {
    local message
    message="$(sed -n 's/.*"message": *"\([^"]*\)".*/\1/p' <<< "$body" | sed -n 1p)"
    echo "error: GET $got answered HTTP $status${message:+: $message}, in ${#body} bytes, which start: ${body:0:200}" >&2
    exit 1
  }
  # The versions named by `"$1": "<prefix>vX.Y.Z"` or `-dev` on stdin,
  # highest first, a release sorting before its own -dev: the -dev tag goes
  # stale whenever main holds a release's version. One field per line,
  # whether the JSON comes pretty-printed or compact.
  versions() {
    tr ',' '\n' | sed -n "s|^ *\"$1\": *\"[a-z/]*v\\([0-9]*\\.[0-9]*\\.[0-9]*\\(-dev\\)\\{0,1\\}\\)\".*|\\1|p" \
      | awk -F'[.-]' '{ print $1, $2, $3, ($4 == "dev" ? 0 : 1), $0 }' \
      | sort -k1,1nr -k2,2nr -k3,3nr -k4,4nr | cut -d' ' -f5
  }
  # The highest version whose tag has a release. The list of releases often
  # answers with no releases, so it is asked, more patiently, only when the
  # tags cannot be.
  if api_get "$api/git/matching-refs/tags/v" ref "2 5"; then
    for candidate in $(versions ref <<< "$body"); do
      if api_get "$api/releases/tags/v$candidate" tag_name "2 5"; then
        version="$candidate"
        break
      fi
      [ "$status" = 404 ] || api_die
    done
  else
    api_get "$api/releases?per_page=100" tag_name "2 5 10 20 30" || api_die
    version="$(versions tag_name <<< "$body" | sed -n 1p)"
  fi
  [ -n "$version" ] || { echo "error: no toolchain (vX.Y.Z release or vX.Y.Z-dev prerelease) is published" >&2; exit 1; }
fi
# A release of a -dev VERSION publishes it with its tag on the commit it
# built (release.yml); a release VERSION publishes nothing until tagged.
expected="${PEPPER_EXPECT_COMMIT:-}"
held="$(tr -d '\r' < VERSION)"
if [ "$mode" != pin ] && [ -n "$expected" ] && [ "${held%-dev}" != "$held" ]; then
  built=""
  [ "$version" != "$held" ] || built="$(git ls-remote origin "refs/tags/v$version" | cut -f1)"
  if [ "$built" != "$expected" ]; then
    echo "error: installing Pepper $version (the build of ${built:-another commit}), not the build of $held at $expected that this run's release published" >&2
    exit 1
  fi
fi
home="${RUNNER_TEMP:-$target}/pepper-home"
rm -rf "$home"
if [ "$windows" = 1 ]; then
  source=(-Version "$version")
else
  source=(--version "$version")
fi
# Stage 0: the pinned archives, each with a .sha256 from the pin beside it
# to check it against.
if [ "$mode" = pin ]; then
  pin=.github/stage0
  # A Windows checkout may end its lines with CRLF.
  pinned="$(tr -d '\r' < "$pin")"
  version="$(sed -n 's/^version //p' <<< "$pinned")"
  commit="$(sed -n 's/^commit //p' <<< "$pinned")"
  case "$windows-$(uname -s)-$(uname -m)" in
    1-*) platform=windows-x64 ext=.zip ;;
    0-Linux-x86_64) platform=linux-x64 ext=.tar.gz ;;
    0-Darwin-arm64) platform=macos-arm64 ext=.tar.gz ;;
    *) echo "error: $pin pins no build for $(uname -s) on $(uname -m)" >&2; exit 1 ;;
  esac
  downloads="${RUNNER_TEMP:-$target}/pepper-stage0"
  rm -rf "$downloads"
  mkdir -p "$downloads"
  echo "=== stage 0 ($pin): Pepper $version, the build of $commit"
  for name in "pepper-$version-$platform$ext" "pepper-install-$version-$platform$ext"; do
    grep -E "^[0-9a-f]{64} [ *]$name\$" <<< "$pinned" > "$downloads/$name.sha256" \
      || { echo "error: $pin pins no $name" >&2; exit 1; }
    curl -fsSL --retry 5 --retry-all-errors -o "$downloads/$name" \
      "https://github.com/pep-lang/pepper/releases/download/stage0/${commit:0:12}-$name"
  done
  archive="$downloads/pepper-$version-$platform$ext"
  if [ "$windows" = 1 ]; then
    source=(-Archive "$(cygpath -w "$archive")")
  else
    source=(--archive "$archive")
  fi
fi
echo "=== installing Pepper $version into $home"
if [ "$windows" = 1 ]; then
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1 \
    "${source[@]}" -Prefix "$(cygpath -w "$home")" -NoModifyPath -NoPrerequisites
else
  sh scripts/install.sh "${source[@]}" --prefix "$home" --no-modify-path --no-prerequisites < /dev/null
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
