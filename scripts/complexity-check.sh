#!/usr/bin/env bash
# The complexity gate: every function in runtime/ and tools/ keeps a
# cognitive complexity of 25 or less, or, when .github/complexity-baseline.txt
# lists it, no more than the score listed there. It runs pep-complexity
# (pep-lang/pepper-complexity), built from its release tag with this
# checkout's own parser (tools/compiler/parse) and runtime, so it reads the
# syntax this checkout's compiler does. Tests, test data and the generated
# record codec are not checked. See docs/src/contributing/complexity.md.
#
#   scripts/complexity-check.sh [--write-baseline] [compiler-dir]
#
# compiler-dir holds the `pep-build` to build pep-complexity with; by
# default, the installed toolchain's. `--write-baseline` rewrites the
# baseline from the current sources instead of checking them. The build
# goes to target/complexity (under $PEPPER_TARGET_DIR when it is set).
set -euo pipefail

VERSION=v0.2.0
MAX=25

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${PEPPER_TARGET_DIR:-$root/target}"
write=""
if [ "${1:-}" = --write-baseline ]; then
  write=1
  shift
fi
exe=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) exe=".exe" ;;
esac
if [ $# -gt 0 ]; then
  compiler="$1/pep-build$exe"
else
  # The installed toolchain's pep-build: the second line of `which`.
  compiler="$(pepper install which | sed -n 2p)"
fi

# The package's sources, outside any pep.toml: its own would fetch the
# released Pepper its parser comes from, which this checkout's tools/
# stands in for.
work="$target/complexity"
rm -rf "$work/src" "$work/package"
mkdir -p "$work/package"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$VERSION" https://github.com/pep-lang/pepper-complexity "$work/src"
cp "$work/src"/*.pep "$work/package/"
PEPPER_RUNTIME="$root/runtime" "$compiler" -O "$work/package/main.pep" -I "$root/tools" \
  -o "$work/pep-complexity$exe" --build "$work/build"

cd "$root"
arguments=(--max "$MAX" --exclude '**/*_test.pep' --exclude 'runtime/**/test/**' --exclude '**/testdata/**'
  --exclude tools/compiler/sema/record_codec.pep)
if [ -n "$write" ]; then
  "$work/pep-complexity$exe" "${arguments[@]}" --write-baseline .github/complexity-baseline.txt runtime tools
else
  "$work/pep-complexity$exe" "${arguments[@]}" --baseline .github/complexity-baseline.txt runtime tools
fi
