#!/usr/bin/env bash
# Runs the Pepper tests: the `[Test]` functions of the runtime
# (`runtime/**/test/`, `runtime/test/`) and of the Pepper tools
# (`tools/<tool>/*_test.pep`), the compiler's among them, with `pepper
# test`. These are the tests CI and the pre-merge checks run.
#
#   scripts/pepper-tests.sh [compiler-dir] [pep-test options...]
#
# compiler-dir holds the `pep-build` to test with. By default it is the
# installed toolchain's, the one `pepper install which` names: CI and the
# workers install the build of main (`scripts/install.sh --version
# <x.y.z-dev>`, #713) rather than building the compiler. To test a change
# to the compiler itself with the compiler it builds, build pep-build from
# tools/compiler with the installed one and pass its folder (README.md,
# "Building from source").
#
# The script builds the Pepper tools (`pepper`, `pep-test`, `pep-fmt`,
# `pep-profile`, `pep-package`, `pep-install`, `pep-doc`) from this
# checkout with that `pep-build`, into target/pepper-tests/bin (under
# $PEPPER_TARGET_DIR when it is set), beside a link to the `pep-build`, so
# `pepper test` finds `pep-test`, `pep-test` finds `pep-build`, and
# `pep-doc check` finds every tool's `--help` there. Further arguments go
# to every `pepper test` (`-f name`, `-j 1`, ...).
#
# Besides the plain run, the compress tests run again with `-D USE_ZLIB`
# and the digest tests with `-D USE_LIBCRYPTO`, which link the system's
# zlib and libcrypto. On Windows the zlib run needs PEPPER_TEST_ZLIB_DIR, a
# folder holding zlib.lib, and is skipped without it.
#
# The tools' tests take the longest, mostly building their test programs,
# so they start as soon as the tools they run are built and run beside
# the runtime's; their output follows the runtime's (#662).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${PEPPER_TARGET_DIR:-$root/target}"
exe=""
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) exe=".exe" ;;
esac

if [ $# -gt 0 ] && [ -d "$1" ]; then
  compiler="$(cd "$1" && pwd)"
  shift
else
  # The installed toolchain's pep-build: the second line of `which`.
  compiler=""
  if command -v pepper >/dev/null 2>&1; then
    installed="$(pepper install which 2>/dev/null | sed -n 2p || true)"
    [ -z "$installed" ] || compiler="$(dirname "$installed")"
  fi
  if [ -z "$compiler" ]; then
    echo "error: no installed Pepper toolchain; install the build of main with" >&2
    echo "  sh scripts/install.sh --version $(tr -d '\r' < "$root/VERSION")" >&2
    echo "or pass the folder of a pep-build to test with" >&2
    exit 2
  fi
fi
if [ ! -x "$compiler/pep-build$exe" ]; then
  echo "error: no pep-build in $compiler" >&2
  exit 2
fi
"$compiler/pep-build$exe" --version

# The tools get a folder of their own, with a link to the compiler (a copy
# on Windows, with the LLVM-C.dll it loads), so a toolchain's folder is
# never written to.
bin="$target/pepper-tests/bin"
mkdir -p "$bin"
if [ "$compiler" != "$bin" ]; then
  if [ -n "$exe" ]; then
    cp -f "$compiler/pep-build$exe" "$bin/"
    if [ -f "$compiler/LLVM-C.dll" ]; then
      cp -f "$compiler/LLVM-C.dll" "$bin/"
    fi
  else
    ln -sf "$compiler/pep-build" "$bin/pep-build"
  fi
fi

# Everything builds against this checkout's runtime, not the toolchain's.
export PEPPER_RUNTIME="$root/runtime"

# The Pepper tools, side by side: `pepper` and `pep-test` run the tests,
# the tools' tests run `pepper`, `pep-test`, `pep-fmt`, `pep-profile` and
# `pep-package` end to end (finding them on the PATH, below), and
# `pep-doc check` reads every tool's `--help`. The tests wait for the
# first five; the rest are waited for at the end.
pids=()
for tool in pepper pep-test pep-fmt pep-profile pep-package pep-install pep-doc; do
  "$bin/pep-build$exe" -O -I "$root/tools" "$root/tools/$tool/main.pep" -o "$bin/$tool$exe" --build "$bin/pepper-tests-build/$tool" &
  pids+=($!)
done
for pid in "${pids[@]:0:5}"; do
  wait "$pid"
done
pepper="$bin/pepper$exe"
# The tests that run pep-build or a tool find it here, before any
# installed toolchain's.
export PATH="$bin:$PATH"

failed=0
run() {
  echo "=== pepper test $* (in $(basename "$PWD"))"
  "$pepper" test "$@" || failed=1
}

# Tests run in the folder they belong to, so data files beside them are
# found by a path from there; the builds go to its .pep/ folder.
tools_log="$bin/pepper-tests-tools.log"
(
  cd "$root/tools"
  # The compiler's tests (tools/compiler) import pepper-llvm, which links the
  # LLVM library. Linux finds it on the default search path; macOS and
  # Windows need its folder (see pepper-llvm's llvm_c/link.pep):
  # PEPPER_LLVM_PREFIX or LLVM_SYS_201_PREFIX, else the prefix
  # scripts/setup-llvm.sh or .ps1 wrote to .pep/llvm-prefix. Windows also
  # needs its DLL's folder on PATH to run the tests.
  llvm=()
  llvm_prefix="${PEPPER_LLVM_PREFIX:-${LLVM_SYS_201_PREFIX:-}}"
  if [ -z "$llvm_prefix" ] && [ -f "$root/.pep/llvm-prefix" ]; then
    llvm_prefix="$(tr -d '\r' < "$root/.pep/llvm-prefix" | head -1)"
  fi
  if [ -n "$llvm_prefix" ] && [ "$(uname -s)" != Linux ]; then
    llvm=(-L "$llvm_prefix/lib")
    if [ -n "$exe" ]; then
      PATH="$(cygpath -u "$llvm_prefix")/bin:$PATH"
    fi
  fi
  if grep -rlq --include='*.pep' '^\[Test\]' .; then
    # At -O1: the compiler's passes tests run the Pepper passes in-process
    # over the test programs, which is slow unoptimized (near the 60 s
    # timeout at -O0), and -O1 builds them quickly enough to save time
    # overall. They still take most of a minute each, so on a runner that
    # shares its host they get 300 s (`-t` in the arguments still wins).
    PEPPER_OPT_LEVEL="${PEPPER_OPT_LEVEL:-1}" run -I . "${llvm[@]+"${llvm[@]}"}" -t 300 "$@"
  fi
  exit $failed
) > "$tools_log" 2>&1 &
tools=$!

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

wait "$tools" || failed=1
cat "$tools_log"
for pid in "${pids[@]:5}"; do
  wait "$pid"
done

exit $failed
