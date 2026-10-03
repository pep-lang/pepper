#!/usr/bin/env bash
# Build one platform's release archive of the Pepper toolchain, then prove
# the archive works with scripts/release-smoke-test.sh.
#
#   scripts/release-build.sh <target> <version> <output-dir>
#
# <target> is one of:
#
#   linux-x64     in a manylinux_2_28 container (glibc 2.28: RHEL 8, Debian 10
#                 and later), with LLVM from its dnf repositories
#   macos-arm64   on an arm64 Mac, with LLVM from Homebrew
#   macos-x64     on an Intel Mac, with LLVM from Homebrew
#   windows-x64   under Git bash, with LLVM from scripts/ci-provision-llvm.sh
#
# The archive (`pepper-<version>-<target>.tar.gz`, `.zip` on Windows) holds
# one folder, `pepper-<version>-<target>`, laid out as an install:
#
#   bin/pepper        the entry point, and every `pep-<command>` it runs:
#   bin/pep-build     the compiler, LLVM linked in (Windows: LLVM-C.dll beside it)
#   bin/pep-fmt, pep-test, pep-package, pep-profile, pep-lsp, pep-doc
#   runtime/          the runtime, which the compiler finds from bin/..
#   LICENSE.md
#
# Beside it lands `<archive>.sha256`, in `sha256sum`'s format.
#
# LLVM is linked into pep-build (statically on Linux and macOS, as
# LLVM-C.dll on Windows), so a user needs no LLVM of their own to compile;
# the libraries LLVM itself pulls in (zstd, libffi, libxml2) are linked
# statically too, so the binary needs nothing beyond the C and C++ runtimes.
# Linking a program still needs a clang, which the install scripts find or
# install (see crates/pepper-driver/src/linker.rs).
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
    # The manylinux_2_28 image is AlmaLinux 8. Its llvm-static carries the
    # component archives llvm-sys links; clang is the smoke test's link
    # driver, as it is a user's.
    dnf install -y llvm-devel llvm-static clang libffi-devel libzstd-devel zlib-devel libxml2-devel
    llvm_config=$(command -v llvm-config)
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
# provisioned the default one and wrote .cargo/config.toml; elsewhere the
# LLVM the platform serves, which must be one this workspace supports.
features=()
if [ -n "$llvm_config" ]; then
  llvm_version=$("$llvm_config" --version)
  major=${llvm_version%%.*}
  case "$major" in
    18|19|20|21|22) ;;
    *) echo "LLVM $llvm_version from $llvm_config is not one Pepper builds with (18-22)" >&2; exit 1 ;;
  esac
  echo "LLVM $llvm_version at $("$llvm_config" --prefix)"
  export "LLVM_SYS_${major}1_PREFIX=$("$llvm_config" --prefix)"
  features=(--no-default-features --features "llvm$major-1")
fi

echo "=== build the Rust tools"
export RUSTFLAGS="${RUSTFLAGS:-} -L native=$static_dir"
cargo --version
cargo build --release --locked -p pepper "${features[@]}"
cargo build --release --locked -p pepper-lsp -p pepper-docgen
release="${CARGO_TARGET_DIR:-target}/release"

stage_name="pepper-$version-$target"
stage="$output/$stage_name"
rm -rf "$stage"
mkdir -p "$stage/bin"
for tool in pep-build pep-lsp pep-doc; do
  cp "$release/$tool$exe" "$stage/bin/"
done
if [ "$target" = windows-x64 ]; then
  # pepper-codegen's build script puts the LLVM-C.dll pep-build links
  # beside it; Windows loads it from the executable's folder.
  cp "$release/LLVM-C.dll" "$stage/bin/"
fi
cp -R runtime "$stage/runtime"
cp LICENSE.md "$stage/"

echo "=== build the Pepper tools"
for tool in pepper pep-fmt pep-test pep-package pep-profile; do
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
