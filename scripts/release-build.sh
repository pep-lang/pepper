#!/usr/bin/env bash
# Build one platform's release archive of the Pepper toolchain, then prove
# the archive works with scripts/release-smoke-test.sh.
#
#   scripts/release-build.sh <target> <version> <output-dir>
#
# <target> is one of:
#
#   linux-x64     in a manylinux_2_28 container (glibc 2.28: RHEL 8, Debian 10
#                 and later), with LLVM built from source (cached)
#   macos-arm64   on an arm64 Mac, with LLVM from Homebrew
#   macos-x64     on an Intel Mac, with LLVM from Homebrew
#   windows-x64   under Git bash, with LLVM from scripts/ci-provision-llvm.sh
#
# The archive (`pepper-<version>-<target>.tar.gz`, `.zip` on Windows) holds
# one folder, `pepper-<version>-<target>`, laid out as an install:
#
#   bin/pepper        the entry point, and every `pep-<command>` it runs:
#   bin/pep-build     the compiler, pepc (tools/compiler), LLVM linked in
#                     (Windows: LLVM-C.dll beside it)
#   bin/pep-fmt, pep-test, pep-package, pep-profile, pep-install, pep-lsp, pep-doc
#   runtime/          the runtime, which the compiler finds from bin/..
#   LICENSE.md
#
# Beside it lands `<archive>.sha256`, in `sha256sum`'s format.
#
# pep-build is pepc, the compiler written in Pepper: built with the Rust
# compiler (stage 0), then again with itself, and the second build ships.
# Every other tool, the language server pep-lsp (tools/pep-lsp) among them,
# is Pepper built by that pep-build. LLVM is linked into it (statically on
# Linux and macOS, as LLVM-C.dll on Windows), so a user needs no LLVM of
# their own to compile; the libraries LLVM itself pulls in (zstd, libffi,
# libxml2) are linked statically too, so the binary needs nothing beyond the
# C and C++ runtimes. Linking a program still needs a clang, which the
# install scripts find or install (see tools/compiler/driver/linker.pep).
set -euo pipefail

target="${1:?usage: release-build.sh <target> <version> <output-dir>}"
version="${2:?usage: release-build.sh <target> <version> <output-dir>}"
output="${3:?usage: release-build.sh <target> <version> <output-dir>}"

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
mkdir -p "$output"
output=$(cd "$output" && pwd)

exe=""
[ "$target" = windows-x64 ] && exe=".exe"

# A folder holding only static archives of LLVM's own dependencies. It is
# searched before LLVM's library folder (RUSTFLAGS' -L comes first), and the
# linkers take the first folder that has a library in either form, so
# `-lzstd` picks up libzstd.a here instead of libzstd.so beside LLVM's libs.
static_dir="$output/.static-libs"
rm -rf "$static_dir"
mkdir -p "$static_dir"

# Links each named static library from the folders given into $static_dir.
collect_static() {
  local dirs="$1"; shift
  local name dir
  for name in "$@"; do
    for dir in $dirs; do
      if [ -f "$dir/lib$name.a" ]; then
        ln -sf "$dir/lib$name.a" "$static_dir/lib$name.a"
        break
      fi
    done
  done
}

echo "=== provision ($target)"
case "$target" in
  linux-x64)
    # The manylinux_2_28 image is AlmaLinux 8. clang is the smoke test's
    # link driver, as it is a user's. openssh-clients: git fetches pepc's
    # pepper-llvm package over SSH.
    dnf install -y clang libffi-devel libzstd-devel zlib-devel libxml2-devel git openssh-clients xz
    # LLVM is the major pepper-llvm binds, built here from source: dnf
    # serves only AlmaLinux's current LLVM (21 since 2026-10), whose C API
    # dropped functions pepper-llvm calls, and upstream's Linux binaries need
    # a newer glibc than this image's. Only what the builds link: the
    # libraries with the X86, AArch64 and WebAssembly backends (the Rust
    # compiler's targets; pepc registers the host's), the headers and
    # llvm-config. Built once, kept beside the runner's workspace, which
    # outlives the container.
    llvm_major=$(sed -nE 's/^DEFAULT_MAJOR="([0-9]+)".*/\1/p' scripts/setup-llvm.sh)
    llvm_version=$(sed -nE "s/^ *$llvm_major\) echo \"([0-9.]+)\" ;;.*/\1/p" scripts/setup-llvm.sh | head -1)
    llvm_prefix="${RUNNER_WORKSPACE:-$output}/pepper-data/llvm-$llvm_version-manylinux_2_28"
    if [ ! -x "$llvm_prefix/bin/llvm-config" ]; then
      python_bin=$(ls -d /opt/python/cp312-*/bin | head -1)
      "$python_bin/python" -m pip install --quiet cmake ninja
      llvm_src="$output/llvm-project-$llvm_version.src"
      rm -rf "$llvm_src" "$output/llvm-build" "$llvm_prefix.partial"
      curl -fsSL "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvm_version/llvm-project-$llvm_version.src.tar.xz" \
        | tar -xJ -C "$output" "llvm-project-$llvm_version.src/llvm" "llvm-project-$llvm_version.src/cmake" "llvm-project-$llvm_version.src/third-party"
      "$python_bin/cmake" -G Ninja -S "$llvm_src/llvm" -B "$output/llvm-build" \
        -DCMAKE_MAKE_PROGRAM="$python_bin/ninja" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$llvm_prefix.partial" \
        -DLLVM_TARGETS_TO_BUILD="X86;AArch64;WebAssembly" \
        -DLLVM_ENABLE_PROJECTS="" \
        -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF \
        -DLLVM_INCLUDE_UTILS=OFF \
        -DLLVM_ENABLE_ZLIB=FORCE_ON -DLLVM_ENABLE_ZSTD=FORCE_ON \
        -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_LIBEDIT=OFF \
        -DLLVM_DISTRIBUTION_COMPONENTS="llvm-config;llvm-headers;llvm-libraries"
      "$python_bin/ninja" -C "$output/llvm-build" install-distribution
      mv "$llvm_prefix.partial" "$llvm_prefix"
      rm -rf "$llvm_src" "$output/llvm-build"
    fi
    llvm_config="$llvm_prefix/bin/llvm-config"
    collect_static "/usr/lib64 /usr/lib" zstd ffi xml2 z
    if [ ! -f "$static_dir/libzstd.a" ]; then
      # AlmaLinux ships no libzstd.a: build one from zstd's own release.
      zstd_version=1.5.7
      curl -fsSL "https://github.com/facebook/zstd/releases/download/v$zstd_version/zstd-$zstd_version.tar.gz" | tar -xz -C "$output"
      make -C "$output/zstd-$zstd_version/lib" -j"$(nproc)" libzstd.a CFLAGS="-O2 -fPIC"
      cp "$output/zstd-$zstd_version/lib/libzstd.a" "$static_dir/"
    fi
    if [ ! -f "$static_dir/libffi.a" ]; then
      # Nor a libffi.a: build one from libffi's own release.
      ffi_version=3.4.8
      curl -fsSL "https://github.com/libffi/libffi/releases/download/v$ffi_version/libffi-$ffi_version.tar.gz" | tar -xz -C "$output"
      (cd "$output/libffi-$ffi_version" && ./configure --disable-shared --enable-static --with-pic --disable-docs --prefix="$output/libffi" && make -j"$(nproc)" install)
      cp "$output"/libffi/lib*/libffi.a "$static_dir/"
    fi
    if ! command -v cargo >/dev/null 2>&1; then
      curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
      export PATH="$HOME/.cargo/bin:$PATH"
    fi
    ;;
  macos-arm64|macos-x64)
    major=$(sed -nE 's/^DEFAULT_MAJOR="([0-9]+)".*/\1/p' scripts/setup-llvm.sh)
    brew list --formula "llvm@$major" >/dev/null 2>&1 || brew install "llvm@$major"
    brew list --formula zstd >/dev/null 2>&1 || brew install zstd
    llvm_config="$(brew --prefix "llvm@$major")/bin/llvm-config"
    collect_static "$(brew --prefix zstd)/lib" zstd
    ;;
  windows-x64)
    bash scripts/ci-provision-llvm.sh
    llvm_config=""
    ;;
  *)
    echo "unknown target '$target' (expected linux-x64, macos-arm64, macos-x64 or windows-x64)" >&2
    exit 1
    ;;
esac
ls -l "$static_dir"

# The cargo feature for the LLVM provisioned: on Windows the setup script
# provisioned the default one and wrote .cargo/config.toml and
# .pep/llvm-prefix; elsewhere the LLVM the platform serves, which must be
# one this workspace supports.
features=()
if [ -n "$llvm_config" ]; then
  llvm_version=$("$llvm_config" --version)
  major=${llvm_version%%.*}
  case "$major" in
    18|19|20|21|22) ;;
    *) echo "LLVM $llvm_version from $llvm_config is not one Pepper builds with (18-22)" >&2; exit 1 ;;
  esac
  # pepc's pepper-llvm binds one major, the setup scripts' default.
  pepc_major=$(sed -nE 's/^DEFAULT_MAJOR="([0-9]+)".*/\1/p' scripts/setup-llvm.sh)
  if [ "$major" != "$pepc_major" ]; then
    echo "LLVM $llvm_version from $llvm_config is not LLVM $pepc_major, which pepc (pepper-llvm) binds" >&2
    exit 1
  fi
  echo "LLVM $llvm_version at $("$llvm_config" --prefix)"
  export "LLVM_SYS_${major}1_PREFIX=$("$llvm_config" --prefix)"
  features=(--no-default-features --features "llvm$major-1")
fi

echo "=== build the Rust tools"
export RUSTFLAGS="${RUSTFLAGS:-} -L native=$static_dir"
cargo --version
cargo build --release --locked -p pepper "${features[@]}"
release="${CARGO_TARGET_DIR:-target}/release"

stage_name="pepper-$version-$target"
stage="$output/$stage_name"
rm -rf "$stage"
mkdir -p "$stage/bin"
if [ "$target" = windows-x64 ]; then
  # pepper-codegen's build script puts the LLVM-C.dll the compiler links
  # beside the Rust one; Windows loads it from the executable's folder.
  cp "$release/LLVM-C.dll" "$stage/bin/"
fi
cp -R runtime "$stage/runtime"
cp LICENSE.md "$stage/"

echo "=== build pepc"
# How pepc links LLVM (pepper-llvm's llvm_c/link.pep names the library:
# LLVM-20 on Linux, LLVM on macOS, LLVM-C on Windows). On Linux and macOS
# LLVM's component archives become one static archive of that name in
# $static_dir, which the link searches first, followed by what LLVM needs
# from the system and the C++ runtime.
llvm_link=()
case "$target" in
  linux-x64|macos-arm64|macos-x64)
    libdir=$("$llvm_config" --libdir)
    archives=()
    for name in $("$llvm_config" --link-static --libnames); do
      archives+=("$libdir/$name")
    done
    if [ "$target" = linux-x64 ]; then
      merged="$static_dir/libLLVM-$major.a"
      { echo "create $merged"; for a in "${archives[@]}"; do echo "addlib $a"; done; echo save; echo end; } | ar -M
      cxx=stdc++
    else
      merged="$static_dir/libLLVM.a"
      libtool -static -o "$merged" "${archives[@]}"
      cxx=c++
    fi
    llvm_link=(-L "$static_dir" -L "$libdir")
    # The Rust compiler (stage 1) puts these before pepper-llvm's
    # [Link("LLVM-20")] and links no group, so LLVM is named here first:
    # GNU ld then resolves its references with the libraries after it.
    [ "$target" = linux-x64 ] && llvm_link+=(-l "LLVM-20")
    for flag in $("$llvm_config" --link-static --system-libs) ; do
      case "$flag" in
        -l*) llvm_link+=(-l "${flag#-l}") ;;
        /*.a|/*.so|/*.dylib|/*.tbd)
          # A library by its path: its folder and name.
          base=$(basename "$flag"); base=${base#lib}; base=${base%.*}
          llvm_link+=(-L "$(dirname "$flag")" -l "$base") ;;
      esac
    done
    llvm_link+=(-l "$cxx")
    ;;
  windows-x64)
    # The prefix setup-llvm.ps1 settled on.
    llvm_prefix="$(tr -d '\r' < .pep/llvm-prefix | head -1)"
    llvm_link=(-L "$llvm_prefix/lib")
    PATH="$(cygpath -u "$llvm_prefix")/bin:$PATH"
    ;;
esac
pepc_build="$output/pepc-build"
mkdir -p "$pepc_build"
# Stage 1: pepc built by the Rust compiler. Stage 2, which ships: pepc built
# by stage 1, with the runtime of this checkout.
PEPPER_RUNTIME="$repo_root/runtime" "$release/pep-build$exe" -O -I tools tools/compiler/main.pep \
  -o "$pepc_build/pepc-stage1$exe" --build "$pepc_build/stage1" "${llvm_link[@]}"
[ "$target" = windows-x64 ] && cp "$release/LLVM-C.dll" "$pepc_build/"
PEPPER_RUNTIME="$repo_root/runtime" "$pepc_build/pepc-stage1$exe" -O -I tools tools/compiler/main.pep \
  -o "$stage/bin/pep-build$exe" --build "$pepc_build/stage2" --no-cache "${llvm_link[@]}"
"$stage/bin/pep-build$exe" --version

echo "=== build the Pepper tools"
# pep-lsp depends on the private pepper-lsp package, which the build fetches
# (scripts/ci-package-auth.sh in CI).
for tool in pepper pep-fmt pep-test pep-package pep-profile pep-install pep-lsp pep-doc; do
  "$stage/bin/pep-build$exe" -O -I tools "tools/$tool/main.pep" -o "$stage/bin/$tool$exe"
done
# Windows builds write a .pdb beside each program; the archive does not
# need them.
rm -f "$stage"/bin/*.pdb "$stage"/bin/*.ilk

echo "=== package"
cd "$output"
if [ "$target" = windows-x64 ]; then
  archive="$stage_name.zip"
  rm -f "$archive"
  pwsh -NoProfile -Command "Compress-Archive -Path '$stage_name' -DestinationPath '$archive'"
else
  archive="$stage_name.tar.gz"
  tar -czf "$archive" "$stage_name"
fi
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$archive" > "$archive.sha256"
else
  shasum -a 256 "$archive" > "$archive.sha256"
fi
cat "$archive.sha256"
ls -l "$archive"

echo "=== smoke test"
cd "$repo_root"
bash scripts/release-smoke-test.sh "$output/$archive" "$target"
