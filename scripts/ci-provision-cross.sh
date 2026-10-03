#!/usr/bin/env bash
# CI-only: set up this host to cross-link for the other two operating systems
# (the cross-link jobs in ci.yml).
#
#   bash scripts/ci-provision-cross.sh <cache-dir> <sysroot-archive-dir>
#
# - LLVM's linker for the other platforms' formats: `lld-<major>` from apt
#   on Linux, `lld` from Homebrew on macOS, and on Windows `lld.exe` from the
#   LLVM release archive, copied as `ld.lld.exe` and `ld64.lld.exe` (lld
#   picks its flavor from its own name).
# - A Windows SDK and MSVC CRT, from Microsoft's servers by `xwin splat`, in
#   the `/winsysroot` layout lld-link reads (Linux and macOS only).
# - The Linux and macOS system roots another job packed with
#   ci-export-sysroot.sh, unpacked from <sysroot-archive-dir>.
#
# The downloads go to <cache-dir>, which outlives the job on a self-hosted
# runner, so each version is fetched once. Appends each system root's
# PEPPER_SYSROOT_<TRIPLE>, and the LLVM prefix the compiler finds clang in,
# to $GITHUB_ENV, and the linker's folder to $GITHUB_PATH.
set -euo pipefail

XWIN_VERSION=0.6.5
LLVM_MAJOR=${PEPPER_LLVM_MAJOR:-20}

cache=${1:?usage: ci-provision-cross.sh <cache-dir> <sysroot-archive-dir>}
archives=${2:?usage: ci-provision-cross.sh <cache-dir> <sysroot-archive-dir>}
mkdir -p "$cache"
# POSIX paths from here on: Git's tar on Windows reads the `C:` of a
# Windows path as a remote host.
cache=$(cd "$cache" && pwd)
archives=$(cd "$archives" && pwd)
env_file=${GITHUB_ENV:-/dev/stdout}
path_file=${GITHUB_PATH:-/dev/stdout}

repo_root=$(cd "$(dirname "$0")/.." && pwd)

# The compiler finds clang in the LLVM it was built against through
# LLVM_SYS_<NN>_PREFIX, which cargo sets from .cargo/config.toml only for
# the processes it runs. The cross links run the compiler directly.
prefix_line=$(tr -d '\r' < "$repo_root/.cargo/config.toml" | grep -E '^LLVM_SYS_[0-9]+_PREFIX = ' | head -1)
prefix_name=${prefix_line%% =*}
prefix=$(printf '%s' "$prefix_line" | sed -E 's/^[^"]*"(.*)"$/\1/; s|\\\\|\\|g')
echo "$prefix_name=$prefix" >> "$env_file"

case "$(uname -s)" in
  Linux)
    host=linux
    if [ ! -x "/usr/lib/llvm-$LLVM_MAJOR/bin/ld.lld" ]; then
      sudo apt-get install -y --no-install-recommends "lld-$LLVM_MAJOR" >&2
    fi
    echo "/usr/lib/llvm-$LLVM_MAJOR/bin" >> "$path_file"
    ;;
  Darwin)
    host=macos
    # Homebrew's llvm@<major> no longer carries lld; any recent lld links
    # what this LLVM writes.
    formula="lld@$LLVM_MAJOR"
    brew list "$formula" > /dev/null 2>&1 || brew install "$formula" >&2 || {
      formula=lld
      brew list "$formula" > /dev/null 2>&1 || brew install "$formula" >&2
    }
    echo "$(brew --prefix "$formula")/bin" >> "$path_file"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    host=windows
    version=$(tr -d '\r' < "$repo_root/scripts/setup-llvm.ps1" | sed -nE "s/^ *'$LLVM_MAJOR' = '([^']+)'.*/\\1/p" | head -1)
    [ -n "$version" ] || { echo "no LLVM $LLVM_MAJOR in scripts/setup-llvm.ps1" >&2; exit 1; }
    bin="$cache/lld-$version"
    if [ ! -x "$bin/ld64.lld.exe" ]; then
      asset="clang+llvm-$version-x86_64-pc-windows-msvc.tar.xz"
      # setup-llvm.ps1 caches the same archive when it falls back to it.
      archive="$(cygpath -u "$LOCALAPPDATA")/pepper/cache/$asset"
      if [ ! -f "$archive" ]; then
        archive="$cache/$asset"
        curl --fail --location --silent --show-error --retry 3 -o "$archive.part" \
          "https://github.com/llvm/llvm-project/releases/download/llvmorg-$version/$asset"
        mv "$archive.part" "$archive"
      fi
      mkdir -p "$bin"
      tar -xJf "$archive" -O --wildcards '*/bin/lld.exe' > "$bin/lld.exe.part"
      for name in ld.lld ld64.lld lld-link; do
        cp "$bin/lld.exe.part" "$bin/$name.exe"
      done
      rm "$bin/lld.exe.part"
    fi
    # Only lld was wanted; setup-llvm.ps1's own copy stays where it was.
    rm -f "$cache"/clang+llvm-*.tar.xz
    cygpath -w "$bin" >> "$path_file"
    ;;
  *)
    echo "unsupported host: $(uname -s)" >&2
    exit 1
    ;;
esac

# The Windows SDK and CRT. xwin builds from source on any host with cargo.
if [ "$host" != windows ]; then
  xwin="$cache/xwin-$XWIN_VERSION/bin/xwin"
  if [ ! -x "$xwin" ]; then
    cargo install xwin --version "$XWIN_VERSION" --locked --root "$cache/xwin-$XWIN_VERSION" >&2
  fi
  winsysroot="$cache/winsysroot-$XWIN_VERSION"
  if [ ! -f "$winsysroot/.complete" ]; then
    rm -rf "$winsysroot"
    "$xwin" --accept-license --arch x86_64 --cache-dir "$cache/xwin-cache" \
      splat --use-winsysroot-style --preserve-ms-arch-notation --output "$winsysroot" >&2
    touch "$winsysroot/.complete"
    rm -rf "$cache/xwin-cache"
  fi
  echo "PEPPER_SYSROOT_X86_64_PC_WINDOWS_MSVC=$winsysroot" >> "$env_file"
fi

# The other hosts' system roots, fresh each run: they are a few megabytes.
sysroots="$cache/sysroots"
rm -rf "$sysroots"
mkdir -p "$sysroots"
# GNU tar warns of every macOS extended attribute in the SDK's archive.
# (Not an array: bash 3.2, macOS's, calls an empty one unbound under -u.)
quiet=
if tar --version 2>/dev/null | grep -q GNU; then
  quiet=--warning=no-unknown-keyword
fi
for archive in "$archives"/*.tar.gz; do
  [ -f "$archive" ] || continue
  tar $quiet -xzf "$archive" -C "$sysroots"
done
native() { if [ "$host" = windows ]; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
if [ "$host" != linux ]; then
  [ -d "$sysroots/linux" ] || { echo "no Linux system root in $archives" >&2; exit 1; }
  echo "PEPPER_SYSROOT_X86_64_UNKNOWN_LINUX_GNU=$(native "$sysroots/linux")" >> "$env_file"
fi
if [ "$host" != macos ]; then
  [ -d "$sysroots/MacOSX.sdk" ] || { echo "no macOS SDK in $archives" >&2; exit 1; }
  echo "PEPPER_SYSROOT_AARCH64_APPLE_DARWIN=$(native "$sysroots/MacOSX.sdk")" >> "$env_file"
fi
