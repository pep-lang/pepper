#!/usr/bin/env bash
# Runs the Pepper tests: the `[Test]` functions of the runtime
# (`runtime/**/test/`, `runtime/test/`) and of the Pepper tools
# (`tools/<tool>/*_test.pep`), with `pepper test`. These are the tests CI
# and the pre-merge checks run; the Rust compiler's own `cargo test` suite
# no longer runs there (#662).
#
#   scripts/pepper-tests.sh [compiler-dir] [pep-test options...]
#
# compiler-dir holds the `pep-build` to test with (default: the release
# build, else the debug build, under $CARGO_TARGET_DIR or target/). The
# script builds the Pepper tools (`pepper`, `pep-test`, `pep-fmt`,
# `pep-profile`, `pep-package`) with it, into that same folder, so
# `pepper test` finds `pep-test`, `pep-test` finds `pep-build`, and
# `pep-doc check` finds every tool's `--help`. Further
# arguments go to every `pepper test` (`-f name`, `-j 1`, ...).
#
# Besides the plain run, the compress tests run again with `-D USE_ZLIB`
# and the digest tests with `-D USE_LIBCRYPTO`, which link the system's
# zlib and libcrypto. On Windows the zlib run needs PEPPER_TEST_ZLIB_DIR, a
# folder holding zlib.lib, and is skipped without it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${CARGO_TARGET_DIR:-$root/target}"
exe=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) exe=".exe" ;;
esac

if [ $# -gt 0 ] && [ -d "$1" ]; then
  bin="$(cd "$1" && pwd)"
  shift
elif [ -x "$target/release/pep-build$exe" ]; then
  bin="$target/release"
else
  bin="$target/debug"
fi
if [ ! -x "$bin/pep-build$exe" ]; then
  echo "error: no pep-build in $bin; run 'cargo build' first" >&2
  exit 2
fi

# The Pepper tools, side by side: `pepper` and `pep-test` run the tests,
# and `pep-doc check` reads every tool's `--help`.
pids=()
for tool in pepper pep-test pep-fmt pep-profile pep-package; do
  "$bin/pep-build$exe" -O -I "$root/tools" "$root/tools/$tool/main.pep" -o "$bin/$tool$exe" --build "$bin/pepper-tests-build/$tool" &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid"
done
pepper="$bin/pepper$exe"
export PEPPER_RUNTIME="$root/runtime"
# The compiler's parser test (tools/compiler) runs pep-build itself.
export PATH="$bin:$PATH"

failed=0
run() {
  echo "=== pepper test $* (in $(basename "$PWD"))"
  "$pepper" test "$@" || failed=1
}

# Tests run in the folder they belong to, so data files beside them are
# found by a path from there; the builds go to its .pep/ folder.
cd "$root/runtime"
run "$@"
if [ -d compress/test ]; then
  if [ -z "$exe" ]; then
    run -D USE_ZLIB "$@" compress/test
  elif [ -n "${PEPPER_TEST_ZLIB_DIR:-}" ]; then
    run -D USE_ZLIB -L "$PEPPER_TEST_ZLIB_DIR" "$@" compress/test
  else
    echo "=== skipped: -D USE_ZLIB compress/test (set PEPPER_TEST_ZLIB_DIR to a folder holding zlib.lib)"
  fi
fi
if [ -d digest/test ]; then
  libcrypto=()
  for dir in /opt/homebrew/opt/openssl@3/lib /usr/local/opt/openssl@3/lib; do
    if [ "$(uname -s)" = Darwin ] && [ -d "$dir" ]; then
      libcrypto+=(-L "$dir")
    fi
  done
  run -D USE_LIBCRYPTO "${libcrypto[@]+"${libcrypto[@]}"}" "$@" digest/test
fi

cd "$root/tools"
if grep -rlq --include='*.pep' '^\[Test\]' .; then
  # At -O1: the compiler's passes tests run the Pepper passes in-process
  # over the test programs, which is slow unoptimized (near the 60 s
  # timeout at -O0), and -O1 builds them quickly enough to save time
  # overall. They still take most of a minute each, so on a runner that
  # shares its host they get 300 s (`-t` in the arguments still wins).
  PEPPER_OPT_LEVEL="${PEPPER_OPT_LEVEL:-1}" run -I . -t 300 "$@"
fi

exit $failed
