#!/usr/bin/env bash
# CI-only: makes the stage 0 of the linux-arm64 release (release.yml), on an
# x64 Ubuntu runner, since no published build of Pepper runs on arm64 Linux.
#
#   bash scripts/cross-stage0-linux-arm64.sh <output-dir>
#
# Builds pep-build and pep-package from the commit .github/stage0 pins,
# with that commit's x64 build, for aarch64-unknown-linux-gnu, statically linked, so
# they run in the release's manylinux_2_28_aarch64 container (glibc 2.28)
# though Ubuntu's cross glibc is newer. So the result is the pin's build for
# aarch64 and changes only with the pin (release.yml caches it). They are only stage 0: the release
# builds pepc again with them (stage 1), and again with that (stage 2).
#
# What the link takes for aarch64: Ubuntu's cross C and C++ libraries
# (`--sysroot /`, where clang finds Debian's cross layout), upstream LLVM's
# aarch64 Linux release (its component libraries, merged into one
# `libLLVM-<major>.a` as release-build.sh merges them, and the libc++ it is
# built against), and zlib and zstd built here with the cross gcc. A clang
# that adds `-static` stands in for the link driver (PEPPER_LLVM_PREFIX),
# since pep-build has no option to pass the linker one.
set -euo pipefail

output="${1:?usage: cross-stage0-linux-arm64.sh <output-dir>}"
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
mkdir -p "$output"
output=$(cd "$output" && pwd)
work="${RUNNER_TEMP:-$output}/cross-arm64"
rm -rf "$work"
mkdir -p "$work/static"
static="$work/static"

echo "=== cross C and C++ libraries"
sudo apt-get update -qq
sudo apt-get install -y -qq gcc-aarch64-linux-gnu libc6-dev-arm64-cross libstdc++-13-dev-arm64-cross

echo "=== LLVM for aarch64"
llvm_major=$(sed -nE 's/^LLVM_MAJOR="([0-9]+)".*/\1/p' scripts/setup-llvm.sh)
llvm_version=$(sed -nE "s/^ *$llvm_major\) echo \"([0-9.]+)\" ;;.*/\1/p" scripts/setup-llvm.sh | head -1)
llvm="$work/llvm"
mkdir -p "$llvm"
curl -fsSL --retry 3 "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvm_version/LLVM-$llvm_version-Linux-ARM64.tar.xz" \
  | tar -xJ -C "$llvm" --strip-components=1
{ echo "create $static/libLLVM-$llvm_major.a"; for a in "$llvm"/lib/libLLVM*.a; do echo "addlib $a"; done; echo save; echo end; } | ar -M
cp "$llvm"/lib/aarch64-unknown-linux-gnu/{libc++.a,libc++abi.a,libunwind.a} "$static/"

echo "=== zlib and zstd for aarch64"
zlib_version=1.3.1
zstd_version=1.5.7
curl -fsSL --retry 3 "https://github.com/madler/zlib/releases/download/v$zlib_version/zlib-$zlib_version.tar.gz" | tar -xz -C "$work"
(cd "$work/zlib-$zlib_version" && CC=aarch64-linux-gnu-gcc CFLAGS="-O2 -fPIC" ./configure --static && make -j"$(nproc)" libz.a)
cp "$work/zlib-$zlib_version/libz.a" "$static/"
curl -fsSL --retry 3 "https://github.com/facebook/zstd/releases/download/v$zstd_version/zstd-$zstd_version.tar.gz" | tar -xz -C "$work"
make -C "$work/zstd-$zstd_version/lib" -j"$(nproc)" libzstd.a CC=aarch64-linux-gnu-gcc CFLAGS="-O2 -fPIC"
cp "$work/zstd-$zstd_version/lib/libzstd.a" "$static/"
ls -l "$static"

echo "=== a link driver that links statically"
driver="$work/driver"
mkdir -p "$driver/bin"
printf '#!/bin/sh\nexec clang "$@" -static\n' > "$driver/bin/clang"
chmod +x "$driver/bin/clang"
lld=$(command -v ld.lld || command -v "ld.lld-$llvm_major")
ln -sf "$lld" "$driver/bin/ld.lld"

echo "=== stage 0's stage 0"
stage0="$(GITHUB_ENV= bash scripts/ci-install-toolchain.sh | sed -n 's/^PEPPER_COMPILER_DIR=//p' | tail -1)"
"$stage0/pep-build" --version

echo "=== the pinned commit's source"
commit=$(sed -n 's/^commit //p' .github/stage0)
git fetch -q --depth 1 origin "$commit"
src="$work/src"
mkdir -p "$src"
git archive "$commit" | tar -x -C "$src"
cd "$src"

echo "=== pep-build and pep-package for aarch64"
export PEPPER_LLVM_PREFIX="$driver"
for project in tools/compiler tools/pep-package; do
  "$stage0/pep-package" -C "$project" fetch
done
link=(-L "$static" -l "LLVM-$llvm_major" -l c++ -l c++abi -l z -l zstd -l pthread)
"$stage0/pep-build" -O --target aarch64-unknown-linux-gnu --sysroot / tools/compiler/main.pep \
  -o "$output/pep-build" "${link[@]}"
"$stage0/pep-build" -O --target aarch64-unknown-linux-gnu --sysroot / tools/pep-package/main.pep \
  -o "$output/pep-package"
file "$output/pep-build" "$output/pep-package"
