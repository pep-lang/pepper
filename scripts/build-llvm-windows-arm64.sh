#!/usr/bin/env bash
# Builds the LLVM the windows-arm64 release links, from source, on an arm64
# Windows machine under Git bash (llvm-package.yml's windows-arm64 leg):
#
#   bash scripts/build-llvm-windows-arm64.sh <version> <prefix> <work-dir>
#
# Upstream's arm64 Windows release is built for AArch64, ARM and X86 only, so
# a pepc linked with it could not target WebAssembly. So this builds what the
# release links, as build-llvm-manylinux.sh does for Linux: the X86, AArch64
# and WebAssembly backends, LLVM-C.dll and its import library, the component
# libraries llvm-config names, the C headers and llvm-config, with Visual
# Studio's arm64 tools. clang.exe, which links Pepper programs, comes from
# upstream's arm64 release (no part of pepc runs it for another target).
#
# The result goes to <prefix>, the tree package-llvm.ps1 packages; the
# sources and build tree under <work-dir> are removed afterwards.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <version> <prefix> <work-dir>" >&2
  exit 2
fi
version="$1"
prefix=$(cygpath -u "$2")
work=$(cygpath -u "$3")
mkdir -p "$work"

vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
vs=$("$vswhere" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64 -property installationPath)
[ -n "$vs" ] || { echo "error: no Visual Studio with the arm64 C++ tools" >&2; exit 1; }

echo "=== sources"
src="$work/llvm-project-$version.src"
build="$work/llvm-build"
rm -rf "$src" "$build" "$prefix"
curl -fsSL --retry 3 "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/llvm-project-$version.src.tar.xz" \
  | tar -xJ -C "$work" "llvm-project-$version.src/llvm" "llvm-project-$version.src/cmake" "llvm-project-$version.src/third-party"

echo "=== configure and build"
# vcvarsall sets up the arm64 compiler, and puts Visual Studio's CMake and
# Ninja on the PATH, in cmd; a script file keeps bash's quoting out of it.
cat > "$work/build.cmd" <<EOF
call "$vs\\VC\\Auxiliary\\Build\\vcvarsall.bat" arm64 || exit /b 1
cmake -G Ninja -S "$(cygpath -w "$src/llvm")" -B "$(cygpath -w "$build")" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_INSTALL_PREFIX="$(cygpath -w "$prefix")" ^
  -DLLVM_TARGETS_TO_BUILD="X86;AArch64;WebAssembly" ^
  -DLLVM_ENABLE_PROJECTS="" ^
  -DLLVM_BUILD_LLVM_C_DYLIB=ON ^
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF ^
  -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF ^
  || exit /b 1
cmake --build "$(cygpath -w "$build")" || exit /b 1
cmake --install "$(cygpath -w "$build")" || exit /b 1
EOF
cmd //c "$(cygpath -w "$work/build.cmd")"

echo "=== clang from upstream's arm64 release"
upstream="$work/upstream"
mkdir -p "$upstream"
curl -fsSL --retry 3 "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/clang+llvm-$version-aarch64-pc-windows-msvc.tar.xz" \
  | tar -xJ -C "$upstream" --strip-components=1 --wildcards '*/bin/clang.exe'
cp "$upstream/bin/clang.exe" "$prefix/bin/"

"$prefix/bin/llvm-config.exe" --version --targets-built
ls -l "$prefix/bin/LLVM-C.dll" "$prefix/lib/LLVM-C.lib"
rm -rf "$src" "$build" "$upstream"
