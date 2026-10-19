#!/usr/bin/env bash
# Builds the LLVM the Linux release links, from source, inside a
# manylinux_2_28 container (AlmaLinux 8, glibc 2.28):
#
#   bash scripts/build-llvm-manylinux.sh <version> <prefix> <work-dir>
#
# dnf serves only AlmaLinux's current LLVM, whose C API can drop functions
# pepper-llvm calls, and upstream's Linux binaries need a newer glibc than the
# image's. So this builds only what the builds link: the libraries with the
# X86, AArch64 and WebAssembly backends (the targets pepc's --target names;
# it registers the host's), the headers and llvm-config.
#
# Does nothing when <prefix> already holds an llvm-config. With GH_TOKEN and
# GITHUB_REPOSITORY set (as in a workflow), it first tries the package
# llvm-package.yml publishes on the repository's llvm-<version> release, the
# same files without the hours of building. The build goes to
# <prefix>.partial and moves into place only once it is complete, and the
# sources and build tree under <work-dir> are removed afterwards.
#
# release-build.sh calls it for its linux-x64 leg, and llvm-package.yml's
# manylinux leg calls it to publish the result as a package.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <version> <prefix> <work-dir>" >&2
  exit 2
fi
version="$1"
prefix="$2"
work="$3"

if [ -x "$prefix/bin/llvm-config" ]; then
  echo "LLVM $version is already built in $prefix"
  exit 0
fi

python_bin=$(ls -d /opt/python/cp312-*/bin | head -1)
mkdir -p "$work"

# The package llvm-package.yml publishes is this build, already done: use it
# when the repository has one. Any failure falls through to the build.
asset="llvm-$version-linux-x64-manylinux_2_28.tar.xz"
if [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  api="${GITHUB_API_URL:-https://api.github.com}/repos/$GITHUB_REPOSITORY"
  asset_id=$(curl -fsSL -H "Authorization: Bearer $GH_TOKEN" "$api/releases/tags/llvm-$version" \
    | "$python_bin/python" -c "import json, sys; print(next((a['id'] for a in json.load(sys.stdin)['assets'] if a['name'] == sys.argv[1]), ''))" "$asset" \
    || true)
  if [ -n "$asset_id" ]; then
    rm -rf "$prefix.partial"
    mkdir -p "$prefix.partial"
    if curl -fsSL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/octet-stream" "$api/releases/assets/$asset_id" \
      | tar -xJ -C "$prefix.partial" && [ -x "$prefix.partial/bin/llvm-config" ]; then
      mv "$prefix.partial" "$prefix"
      echo "LLVM $version installed in $prefix from the release asset $asset"
      exit 0
    fi
    echo "warning: could not install $asset; building LLVM $version from source" >&2
  else
    echo "no $asset published; building LLVM $version from source"
  fi
fi

"$python_bin/python" -m pip install --quiet cmake ninja
src="$work/llvm-project-$version.src"
build="$work/llvm-build"
rm -rf "$src" "$build" "$prefix.partial"
curl -fsSL "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/llvm-project-$version.src.tar.xz" \
  | tar -xJ -C "$work" "llvm-project-$version.src/llvm" "llvm-project-$version.src/cmake" "llvm-project-$version.src/third-party"
"$python_bin/cmake" -G Ninja -S "$src/llvm" -B "$build" \
  -DCMAKE_MAKE_PROGRAM="$python_bin/ninja" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix.partial" \
  -DLLVM_TARGETS_TO_BUILD="X86;AArch64;WebAssembly" \
  -DLLVM_ENABLE_PROJECTS="" \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_ENABLE_ZLIB=FORCE_ON -DLLVM_ENABLE_ZSTD=FORCE_ON \
  -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_DISTRIBUTION_COMPONENTS="llvm-config;llvm-headers;llvm-libraries"
"$python_bin/ninja" -C "$build" install-distribution
mkdir -p "$(dirname "$prefix")"
mv "$prefix.partial" "$prefix"
rm -rf "$src" "$build"
