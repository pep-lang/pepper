#!/usr/bin/env bash
# Checks that the newest published toolchain (stage 0) still builds this
# checkout, as main's CI and the release build do: it builds the compiler
# (tools/compiler) and runs the runtime's tests against this checkout's
# runtime/. The branch's own compiler can hide a runtime change that needs
# a compiler fix stage 0 does not have yet (#1004, the `char` compare
# break), so a PR that changes tools/compiler runs this before it merges.
#
#   scripts/stage0-check.sh [--version <version>] [pep-test options...]
#
# It installs stage 0 with scripts/ci-install-toolchain.sh (--version
# names an older one), builds tools/compiler with it with
# scripts/ci-build-compiler.sh, then runs `pepper test` in runtime/ with
# stage 0's own tools. Further arguments go to that `pepper test`.
#
# Environment: those of the two scripts (PEPPER_TARGET_DIR, PEPPER_LLVM_PREFIX,
# GH_TOKEN while the repository is private).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
target="${PEPPER_TARGET_DIR:-$root/target}"
mkdir -p "$target"

install=()
if [ "${1:-}" = --version ]; then
  install=(--version "${2:-}")
  shift 2
fi

# Both scripts name the compiler's folder in $GITHUB_ENV; read it back.
env_file="$target/stage0-check.env"
: > "$env_file"
export GITHUB_ENV="$env_file"
bash scripts/ci-install-toolchain.sh "${install[@]+"${install[@]}"}"
# shellcheck disable=SC1090
source "$env_file"
stage0="$PEPPER_COMPILER_DIR"
export PEPPER_COMPILER_DIR

bash scripts/ci-build-compiler.sh

exe=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) exe=".exe"; stage0="$(cygpath -u "$stage0")" ;;
esac
echo "=== the runtime's tests with $("$stage0/pep-build$exe" --version)"
export PEPPER_RUNTIME="$root/runtime"
cd runtime
PATH="$stage0:$PATH" "$stage0/pepper$exe" test "$@"
