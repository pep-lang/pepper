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
# <x.y.z-dev>`) rather than building the compiler. To test a change
# to the compiler itself with the compiler it builds, build pep-build from
# tools/compiler with the installed one and pass its folder (README.md,
# "Building from source").
#
# The script builds the Pepper tools (`pepper`, `pep-test`, `pep-fmt`,
# `pep-profile`, `pep-package`, `pep-run`, `pep-new`, `pep-init`,
# `pep-install`, `pep-doc`) from this
# checkout with that `pep-build`, into target/pepper-tests/bin (under
# $PEPPER_TARGET_DIR when it is set), beside a link to the `pep-build`, so
# `pepper test` finds `pep-test`, `pep-test` finds `pep-build`, and
# `pep-doc check` finds every tool's `--help` there. Further arguments go
# to every `pepper test` (`-f name`, `-j 1`, `--shard 2/4`, ...).
#
# Besides the plain run, the compress tests run again with `-D USE_ZLIB`
# and the digest tests with `-D USE_LIBCRYPTO`, which link the system's
# zlib and libcrypto. On Windows the zlib run needs PEPPER_TEST_ZLIB_DIR, a
# folder holding zlib.lib, and is skipped without it.
#
# The tools' tests take the longest, mostly building their test programs,
# so they start as soon as the tools they run are built and run beside
# the runtime's. Their output is interleaved with the runtime's as it
# comes, each line starting `tools| `, so a slow or stuck test shows in
# a live log.
#
# PEPPER_TESTS_PART runs part of them, so CI can split the suite between
# runners: `compiler` runs the compiler's tests (tools/compiler), `others`
# everything else (the runtime's and the other tools'); unset or `all`
# runs both.
#
# Every build the tests make checks that sema left no injected construct
# half resolved (PEPC_VERIFY_INJECTED, INTERNALS.md "Debugging").
set -euo pipefail
export PEPC_VERIFY_INJECTED="${PEPC_VERIFY_INJECTED:-1}"
part="${PEPPER_TESTS_PART:-all}"
case "$part" in
  all|compiler|others) ;;
  *) echo "error: PEPPER_TESTS_PART is 'all', 'compiler' or 'others', not '$part'" >&2; exit 2 ;;
esac

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

# The compiler's tests (tools/compiler) import pepper-llvm, which links the
# LLVM library. The toolchain does not ship it (pep-build has LLVM linked
# in), so they need an LLVM install. Linux finds it on the default search
# path; macOS and Windows need its folder (see pepper-llvm's
# llvm_c/link.pep): PEPPER_LLVM_PREFIX or LLVM_SYS_201_PREFIX, else the
# prefix scripts/setup-llvm.sh or .ps1 wrote to .pep/llvm-prefix (this
# checkout's, else, in a git worktree, the main checkout's). Windows also
# needs its DLL's folder on PATH to run the tests.
llvm=()
llvm_path=""
if [ "$(uname -s)" != Linux ]; then
  llvm_prefix="${PEPPER_LLVM_PREFIX:-${LLVM_SYS_201_PREFIX:-}}"
  prefix_file="$root/.pep/llvm-prefix"
  if [ ! -f "$prefix_file" ]; then
    common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    [ -z "$common" ] || prefix_file="$(dirname "$common")/.pep/llvm-prefix"
  fi
  if [ -z "$llvm_prefix" ] && [ -f "$prefix_file" ]; then
    llvm_prefix="$(tr -d '\r' < "$prefix_file" | head -1)"
  fi
  # The library pepper-llvm names: LLVM-C on Windows, LLVM on macOS.
  library="LLVM-C.lib"
  [ -n "$exe" ] || library="libLLVM.dylib"
  if [ -z "$llvm_prefix" ] || [ ! -f "$llvm_prefix/lib/$library" ]; then
    echo "error: the compiler's tests link LLVM 20's $library, not found in ${llvm_prefix:-(no LLVM prefix set)}/lib" >&2
    echo "run scripts/setup-llvm.sh (scripts/setup-llvm.ps1 on Windows) in this checkout, or set PEPPER_LLVM_PREFIX" >&2
    exit 2
  fi
  llvm=(-L "$llvm_prefix/lib")
  [ -z "$exe" ] || llvm_path="$(cygpath -u "$llvm_prefix")/bin"
fi

# A Windows path (`D:/x`) would split the PATH entry below at its colon.
[ -z "$exe" ] || target="$(cygpath -u "$target")"

# The tools get a folder of their own, with a copy of the compiler (and on
# Windows the LLVM-C.dll it loads), so a toolchain's folder is never
# written to. A copy, not a symlink: pep-build runs the pep-package beside
# its resolved path, so through a link into an installed toolchain it would
# run the toolchain's pep-package, which keeps its cache in that home and
# ignores the tests' PEPPER_HOME. The copy keeps the compiler's time: the
# build cache keys on the compiler's path, size and time
# (`compiler_identity`), so a fresh time would rebuild everything on every
# pass.
bin="$target/pepper-tests/bin"
mkdir -p "$bin"
if [ "$compiler" != "$bin" ]; then
  rm -f "$bin/pep-build$exe"  # an older run's symlink, which cp would write through
  cp -fp "$compiler/pep-build$exe" "$bin/"
  if [ -f "$compiler/LLVM-C.dll" ]; then
    cp -fp "$compiler/LLVM-C.dll" "$bin/"
  fi
fi

# A test that reaches a git remote fails instead of waiting for a login
# prompt (Git Credential Manager on Windows) that nobody answers.
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never

# Everything builds against this checkout's runtime, not the toolchain's.
export PEPPER_RUNTIME="$root/runtime"

# The Pepper tools, side by side: `pepper` and `pep-test` run the tests,
# the tools' tests run `pepper`, `pep-test`, `pep-fmt`, `pep-profile`,
# `pep-package`, `pep-run`, `pep-new` and `pep-init` end to end (finding
# them on the PATH, below), and `pep-doc check` reads every tool's `--help`.
# The tests wait for the first eight; the rest are waited for at the end.
pids=()
for tool in pepper pep-test pep-fmt pep-profile pep-package pep-run pep-new pep-init pep-install pep-doc; do
  "$bin/pep-build$exe" -O "$root/tools/$tool/main.pep" -o "$bin/$tool$exe" --build "$bin/pepper-tests-build/$tool" &
  pids+=($!)
done
for pid in "${pids[@]:0:8}"; do
  wait "$pid"
done
pepper="$bin/pepper$exe"
# The tests that run pep-build or a tool find it here, before any
# installed toolchain's.
export PATH="$bin:$PATH"

# Every tool's dependencies, fetched up front: the compiler's imports tests
# check every tool's sources, whichever part of the tests runs.
for project in "$root"/tools/*/pep.toml; do
  "$bin/pep-package$exe" -C "$(dirname "$project")" fetch
done

failed=0
run() {
  echo "=== pepper test $* (in $(basename "$PWD"))"
  "$pepper" test "$@" || failed=1
}

# Tests run in the folder they belong to, so data files beside them are
# found by a path from there; the builds go to its .pep/ folder.
tools_status="$bin/pepper-tests-tools.status"
rm -f "$tools_status"
(
  cd "$root/tools"
  [ -z "$llvm_path" ] || PATH="$llvm_path:$PATH"
  # The folders of this part; none named is every one.
  folders=()
  if [ "$part" = compiler ]; then
    folders=(compiler)
  elif [ "$part" = others ]; then
    for folder in */; do
      folder="${folder%/}"
      if [ "$folder" != compiler ] && grep -rlq --include='*.pep' '^\[Test\]' "$folder"; then
        folders+=("$folder")
      fi
    done
  fi
  if grep -rlq --include='*.pep' '^\[Test\]' .; then
    # At -O1: the compiler's passes tests run the Pepper passes in-process
    # over the test programs, which is slow unoptimized (near the 60 s
    # timeout at -O0), and -O1 builds them quickly enough to save time
    # overall. They still take most of a minute each, and the docs
    # examples' parts, which build every example, take up to 270 s on the
    # Windows runner while it shares its host, so they get 600 s (`-t` in
    # the arguments still wins).
    PEPPER_OPT_LEVEL="${PEPPER_OPT_LEVEL:-1}" run "${llvm[@]+"${llvm[@]}"}" -t 600 "$@" "${folders[@]+"${folders[@]}"}"
  fi
  echo "$failed" > "$tools_status"
) 2>&1 | while IFS= read -r line; do printf 'tools| %s\n' "$line"; done &
# The pipeline's last process, which ends once all the tools' output is out.
tools=$!

cd "$root/runtime"
if [ "$part" != compiler ]; then
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
fi

wait "$tools"
# No status when the tools' subshell stopped early.
[ "$(cat "$tools_status" 2>/dev/null)" = 0 ] || failed=1
for pid in "${pids[@]:8}"; do
  wait "$pid"
done

exit $failed
