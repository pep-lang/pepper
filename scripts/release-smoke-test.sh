#!/usr/bin/env bash
# Prove a release archive works as installed: unpack it outside the
# checkout, with no LLVM_SYS_*_PREFIX, PEPPER_LLVM_PREFIX or PEPPER_RUNTIME
# set, and build and run a program through `pepper`. Then check what the
# binaries load: on Linux only the C and C++ runtimes and libz, from glibc
# 2.28 or older; on macOS only the system's libraries; on Windows,
# pep-build starts with nothing but the system folder on the PATH
# (LLVM-C.dll beside it). The installer archive beside it,
# `pepper-install-<version>-<target>`, must hold a `pep-install` that runs.
#
#   scripts/release-smoke-test.sh <archive> <target>
set -euo pipefail

archive="${1:?usage: release-smoke-test.sh <archive> <target>}"
target="${2:?usage: release-smoke-test.sh <archive> <target>}"

archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")

exe=""
[ "$target" = windows-x64 ] && exe=".exe"

# Outside the checkout, so the compiler cannot find the repository's
# runtime from the current folder and must use the archive's.
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pepper-smoke.XXXXXX")
cd "$work"
case "$archive" in
  *.zip) unzip -q "$archive" ;;
  *) tar -xzf "$archive" ;;
esac
install=$(echo "$work"/pepper-*)
bin="$install/bin"
ls -l "$bin"

for variable in $(env | sed -nE 's/^(LLVM_SYS_[0-9]+_PREFIX|PEPPER_LLVM_PREFIX|PEPPER_RUNTIME)=.*/\1/p'); do
  unset "$variable"
done

echo "=== version"
"$bin/pepper$exe" --version -v
# The language server is Pepper too (tools/pep-lsp): it starts.
"$bin/pep-lsp$exe" --version

echo "=== build and run"
printf 'main(): int {\n    print("Hello world!");\n    return 0;\n}\n' > hello.pep
"$bin/pepper$exe" build hello.pep -o "hello$exe"
out=$("./hello$exe")
echo "$out"
[ "$out" = "Hello world!" ] || { echo "unexpected output from hello" >&2; exit 1; }
"$bin/pepper$exe" fmt --check hello.pep
# A project `pepper new` starts builds.
"$bin/pepper$exe" new smoke_app
"$bin/pepper$exe" -C smoke_app build

echo "=== installer"
installer="$(dirname "$archive")/$(basename "$archive" | sed 's/^pepper-/pepper-install-/')"
mkdir "$work/installer"
case "$installer" in
  *.zip) unzip -q "$installer" -d "$work/installer" ;;
  *) tar -xzf "$installer" -C "$work/installer" ;;
esac
ls -l "$work/installer"
"$work/installer/pep-install$exe" --version

echo "=== dependencies"
case "$target" in
  linux-*)
    status=0
    for file in "$bin"/*; do
      ldd "$file"
      # Anything but the C and C++ runtimes and libz is a library a user
      # may not have.
      if ldd "$file" | grep '=>' | grep -vE '^\s*(linux-vdso|libc|libm|libdl|librt|libpthread|libgcc_s|libstdc\+\+|libz|ld-linux[^ ]*)\.so'; then
        echo "error: $file needs a library outside the C and C++ runtimes and libz" >&2
        status=1
      fi
      newest=$(objdump -T "$file" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -t. -k2 -n | tail -1)
      echo "$(basename "$file"): newest glibc symbol $newest"
      case "$newest" in
        GLIBC_2.[0-9]|GLIBC_2.1[0-9]|GLIBC_2.2[0-8]) ;;
        *) echo "error: $file needs $newest, newer than glibc 2.28" >&2; status=1 ;;
      esac
    done
    exit $status
    ;;
  macos-*)
    status=0
    for file in "$bin"/*; do
      otool -L "$file"
      if otool -L "$file" | tail -n +2 | grep -vE '^\s*(/usr/lib/|/System/Library/)'; then
        echo "error: $file loads a library from outside macOS itself" >&2
        status=1
      fi
    done
    exit $status
    ;;
  windows-*)
    PATH="/c/Windows/System32" "$bin/pep-build.exe" --version
    ;;
esac
