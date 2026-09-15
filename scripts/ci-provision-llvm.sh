#!/usr/bin/env bash
# CI-only LLVM provisioning: install the repo's prebuilt minimal LLVM package
# if one has been published, otherwise fall back to a full upstream install.
#
# The upstream releases do not fit comfortably on a GitHub runner: 11.6 GB
# extracted on Linux (9 GB of it tools this project never invokes), which is
# what exhausted the disk on the first cross-platform run. The published
# package carries only the pieces the build consumes -- llvm-config, the
# component libraries, the llvm-c headers, and on Windows LLVM-C.dll plus
# clang -- which is ~450 MB installed instead of several GB.
#
# Either way this ends by running the normal setup script, which validates the
# prefix and writes .cargo/config.toml, so there is one source of truth for how
# cargo finds LLVM.
#
# Publish packages with the llvm-package workflow. Needs GH_TOKEN to read
# release assets from a private repo.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

# Each setup script owns its own version pin, and the one that matters here is
# whichever script will actually create the prefix: reading the Unix pin and
# then handing off to the PowerShell script would put the package in a
# directory setup-llvm.ps1 never inspects if the two pins ever drifted, and CI
# would silently re-download the full tree without even logging the
# "no prebuilt package" line. The CR strip matters -- a Windows checkout gives
# these files CRLF endings, and an anchored match would come back empty.
read_pin() {
  tr -d '\r' < "$1" | sed -nE "$2" | head -1
}

# `tar` differs per host. Under Git bash on Windows, PATH finds GNU tar, which
# reads the `C:` of a Windows path as a remote host ("Cannot connect to C:
# resolve failed"). What keeps that from happening is the `cygpath` conversion
# below: every path handed to tar -- the prefix and the archive alike -- is in
# POSIX form, so no drive letter ever reaches it. Keep that conversion.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    platform=windows-x64
    version=$(read_pin scripts/setup-llvm.ps1 "s/^\\\$LlvmVersion = '([^']+)'.*/\\1/p")
    [ -n "$version" ] || { echo "cannot read \$LlvmVersion from scripts/setup-llvm.ps1" >&2; exit 1; }
    # $LOCALAPPDATA is a native path with backslashes; cygpath makes it usable
    # by mkdir/cd, and keeps the drive letter away from tar. setup-llvm.ps1
    # derives the same directory itself, from its own pin (read above).
    local_appdata=$(cygpath -u "$LOCALAPPDATA")
    prefix="$local_appdata/pepper/llvm/$version"
    ;;
  Darwin|Linux)
    case "$(uname -s)" in
      Darwin) platform="macos-$(uname -m)" ;;
      *)      platform="linux-$(uname -m)" ;;
    esac
    version=$(read_pin scripts/setup-llvm.sh 's/^LLVM_VERSION="([^"]+)".*/\1/p')
    [ -n "$version" ] || { echo "cannot read LLVM_VERSION from scripts/setup-llvm.sh" >&2; exit 1; }
    prefix="${XDG_DATA_HOME:-$HOME/.local/share}/pepper/llvm/$version"
    ;;
  *) echo "unsupported host: $(uname -s)" >&2; exit 1 ;;
esac

tag="llvm-$version"
asset="llvm-$version-$platform.tar.xz"

echo "Looking for prebuilt $asset in release $tag"
staging=$(mktemp -d)
if download_error=$(gh release download "$tag" --pattern "$asset" --dir "$staging" 2>&1); then
  echo "Installing prebuilt package to $prefix"
  mkdir -p "$prefix"
  archive=$(cd "$staging" && pwd)/$asset
  (cd "$prefix" && tar -xf "$archive")
  rm -rf "$staging"
else
  rm -rf "$staging"
  # Only an absent release or asset justifies the fallback. An auth failure,
  # rate limit or dropped connection exits non-zero too, and treating those as
  # "nothing published" would quietly pay the multi-GB install this script
  # exists to avoid -- on Linux, the extraction that ran the runner out of
  # disk -- while logging a reason that is simply false.
  # gh has two "nothing to fetch" messages: "no assets match the file pattern"
  # when the release has assets, and "no assets to download" when it has none
  # -- the latter being a state this project's own llvm-package workflow
  # creates, since it opens the release before the matrix uploads to it.
  #
  # The patterns are deliberately exact. A bare *"not found"* would also match
  # `gh: command not found`, reporting a missing gh as a missing package and
  # falling back to the multi-GB install this check exists to prevent.
  case "$download_error" in
    *"release not found"*|*"no assets match"*|*"no assets to download"*)
      echo "No prebuilt package published for $platform; falling back to a full install."
      echo "Publish one with the llvm-package workflow to cut several GB off this job."
      ;;
    *)
      echo "Failed to download $asset from release $tag:" >&2
      printf '%s\n' "$download_error" >&2
      echo "Not falling back: this is a download failure, not a missing package." >&2
      exit 1
      ;;
  esac
fi

# Validates whatever is now in the prefix, installs a full LLVM if the download
# did not happen, and writes .cargo/config.toml either way.
case "$platform" in
  windows-*) pwsh -File scripts/setup-llvm.ps1 ;;
  *)         bash scripts/setup-llvm.sh ;;
esac
